//
//  ChatScreen.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI


struct ChatScreen: View {

    @Environment(\.modelContext) private var context

    @Bindable var conversation: ConversationModel
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    var highlightedMessageID: UUID? = nil

    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @State private var message = ""

    @State private var messages: [ChatMessage] = []

    @State private var isLoading = false

    @State private var showSnackbar = false
    @State private var snackbarMessage = ""
    @State private var pickingTarget: WordPickTarget?
    @State private var isTabBarVisible = false
    @State private var showLiveVoiceMode = false

    @State private var typingSuggestions: [TypingSuggestionItem] = []
    @State private var isFetchingTypingSuggestions = false
    @State private var suggestionTask: Task<Void, Never>?

    @StateObject private var speechRecognizer = SpeechRecognizerManager()

    @State private var selectedAttachedImage: UIImage?
    @State private var showCameraPicker = false
    @State private var showPhotosPicker = false
    @State private var showCameraPermissionAlert = false
    @State private var showCameraUnavailableAlert = false
    @State private var photosPickerItem: PhotosPickerItem?

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue


    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    private var latestAIMessage: MessageModel? {
        conversation.messages
            .filter { !$0.isUser }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first
    }

    private var targetHighlightedMessageID: UUID? {
        if let highlightedMessageID,
           conversation.messages.contains(where: { $0.id == highlightedMessageID }) {
            return highlightedMessageID
        }

        let trimmedSource = highlightedSourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sorted = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })

        if !trimmedSource.isEmpty,
           let matchedBySource = sorted.first(where: { messageMatchesSource($0, source: trimmedSource) }) {
            return matchedBySource.id
        }

        if let word = highlightedWord?.normalizedVocabularyWord, !word.isEmpty {
            return sorted.first(where: { messageContainsWord($0, normalizedWord: word) })?.id
        }

        return nil
    }

    private func candidateTexts(for msg: MessageModel) -> [String] {
        var candidates: [String] = [
            msg.text,
            msg.fixed ?? "",
            msg.natural ?? "",
            msg.followUpQuestion ?? ""
        ]
        if let alt = msg.alternativeExpressions {
            candidates.append(contentsOf: alt)
        }
        if let exp = msg.explanations {
            candidates.append(contentsOf: exp)
        }
        if let replies = msg.suggestedReplies {
            candidates.append(contentsOf: replies)
        }
        return candidates
    }

    private func messageMatchesSource(_ msg: MessageModel, source: String) -> Bool {
        let lowerSource = source.lowercased()
        let candidates = candidateTexts(for: msg)

        return candidates.contains { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !trimmed.isEmpty && (trimmed == lowerSource || trimmed.contains(lowerSource) || lowerSource.contains(trimmed))
        }
    }

    private func messageContainsWord(_ msg: MessageModel, normalizedWord: String) -> Bool {
        let candidates = candidateTexts(for: msg)

        return candidates.contains { candidate in
            candidate
                .split(whereSeparator: \.isWhitespace)
                .contains { String($0).normalizedVocabularyWord == normalizedWord }
        }
    }


    var body: some View {

        ZStack {
            AppTheme.Surface.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {

                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 20) {

                            aiConfigCard

                            // CHAT MESSAGES


                            LazyVStack(spacing: 16) {

                                let targetMessageID = targetHighlightedMessageID

                                ForEach(conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })) { item in
                                    let isHighlightedMsg = (item.id == targetMessageID)
                                    let activeHighlightWord = isHighlightedMsg ? highlightedWord : nil
                                    let activeHighlightSource = isHighlightedMsg ? highlightedSourceText : nil

                                    Group {
                                        if item.isUser {
                                            let aiMessage = conversation.messages.first(where: {
                                                !$0.isUser && $0.createdAt >= item.createdAt && $0.decodedSceneDescription != nil
                                            })
                                            let matchingScene = aiMessage?.decodedSceneDescription

                                            UserBubble(
                                                id: item.id,
                                                text: item.text,
                                                imageData: item.imageData,
                                                sceneForImage: matchingScene,
                                                onSaveWord: { wordItem in
                                                    saveVocabulary(
                                                        wordItem.word,
                                                        sourceText: "\(wordItem.partOfSpeech) \(wordItem.phonetic): \(wordItem.vietnameseMeaning)",
                                                        showToast: true
                                                    )
                                                },
                                                isWordSaved: { word in
                                                    savedVocabularyWords.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                                                },
                                                onUpdateScene: { updatedScene in
                                                    if let aiMsg = aiMessage {
                                                        aiMsg.decodedSceneDescription = updatedScene
                                                        try? context.save()
                                                    }
                                                },
                                                pickingTarget: pickingTarget,
                                                savedWords: savedVocabularyWords,
                                                isHighlightedMessage: isHighlightedMsg,
                                                highlightedWord: activeHighlightWord,
                                                onCopy: {
                                                    copyText(item.text)
                                                },
                                                onSaveVocabulary: { word in
                                                    saveVocabulary(word, sourceText: item.text, showToast: pickingTarget == nil)
                                                },
                                                onStartPickingWords: { target in
                                                    pickingTarget = target
                                                },
                                                onStopPickingWords: {
                                                    pickingTarget = nil
                                                },
                                                onFollowUp: {
                                                    followUp(with: item.text)
                                                },
                                                onDelete: {
                                                    deleteMessage(item)
                                                }
                                            )

                                        } else if let fixed = item.fixed, let natural = item.natural {

                                            // Find the user message just before this one to use as 'original'
                                            let originalText = conversation.messages
                                                .filter { $0.isUser && $0.createdAt < item.createdAt }
                                                .sorted(by: { $0.createdAt > $1.createdAt })
                                                .first?.text ?? ""

                                            AIBubble(
                                                messageID: item.id,
                                                original: originalText,
                                                fixed: fixed,
                                                natural: natural,
                                                alternativeExpressions: item.alternativeExpressions ?? [],
                                                explanations: item.explanations ?? [],
                                                explanationNoted: item.explanationNoted ?? [],
                                                followUpQuestion: item.followUpQuestion,
                                                suggestedReplies: item.suggestedReplies ?? [],
                                                pickingTarget: pickingTarget,
                                                savedWords: savedVocabularyWords,
                                                isHighlightedMessage: isHighlightedMsg,
                                                highlightedWord: activeHighlightWord,
                                                highlightedSourceText: activeHighlightSource,
                                                onSave: { noteText, isExplanation, noted in
                                                    saveNote(
                                                        text: noteText,
                                                        originalText: originalText,
                                                        context: fixed,
                                                        isExplanation: isExplanation,
                                                        explanationNoted: noted,
                                                        sourceMessageID: item.id
                                                    )
                                                },
                                                onCopy: { text in
                                                    copyText(text)
                                                },
                                                onSaveVocabulary: { word, source in
                                                    saveVocabulary(word, sourceText: source, showToast: pickingTarget == nil)
                                                },
                                                onStartPickingWords: { target in
                                                    pickingTarget = target
                                                },
                                                onStopPickingWords: {
                                                    pickingTarget = nil
                                                },
                                                onFollowUp: { text in
                                                    followUp(with: text)
                                                },
                                                onDelete: {
                                                    deleteMessage(item)
                                                }
                                            )
                                        } else if let scene = item.decodedSceneDescription {
                                            SceneDescriptionCardView(
                                                scene: scene,
                                                imageData: item.imageData,
                                                onUpdateScene: { updatedScene in
                                                    item.decodedSceneDescription = updatedScene
                                                    try? context.save()
                                                },
                                                onSaveWord: { wordItem in
                                                    saveVocabulary(
                                                        wordItem.word,
                                                        sourceText: "\(wordItem.partOfSpeech) \(wordItem.phonetic): \(wordItem.vietnameseMeaning)",
                                                        showToast: true
                                                    )
                                                },
                                                isWordSaved: { word in
                                                    savedVocabularyWords.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                                                },
                                                messageID: item.id,
                                                pickingTarget: pickingTarget,
                                                savedWords: savedVocabularyWords,
                                                isHighlightedMessage: isHighlightedMsg,
                                                highlightedWord: activeHighlightWord,
                                                highlightedSourceText: activeHighlightSource,
                                                onSaveNote: { noteText, isExplanation, noted in
                                                    saveNote(
                                                        text: noteText,
                                                        originalText: "Ảnh chụp tình huống",
                                                        context: scene.sceneOverview,
                                                        isExplanation: isExplanation,
                                                        explanationNoted: noted,
                                                        sourceMessageID: item.id
                                                    )
                                                },
                                                onCopy: { text in
                                                    copyText(text)
                                                },
                                                onSaveVocabulary: { word, source in
                                                    saveVocabulary(word, sourceText: source, showToast: pickingTarget == nil)
                                                },
                                                onStartPickingWords: { target in
                                                    pickingTarget = target
                                                },
                                                onStopPickingWords: {
                                                    pickingTarget = nil
                                                },
                                                onFollowUp: { text in
                                                    followUp(with: text)
                                                },
                                                onDelete: {
                                                    deleteMessage(item)
                                                }
                                            )
                                        } else {
                                            StarterAIBubble(
                                                messageID: item.id,
                                                text: item.text,
                                                suggestedReplies: item.suggestedReplies ?? [],
                                                pickingTarget: pickingTarget,
                                                savedWords: savedVocabularyWords,
                                                isHighlightedMessage: isHighlightedMsg,
                                                highlightedWord: activeHighlightWord,
                                                highlightedSourceText: activeHighlightSource,
                                                onCopy: { text in
                                                    copyText(text)
                                                },
                                                onSaveVocabulary: { word, source in
                                                    saveVocabulary(word, sourceText: source, showToast: pickingTarget == nil)
                                                },
                                                onStartPickingWords: { target in
                                                    pickingTarget = target
                                                },
                                                onStopPickingWords: {
                                                    pickingTarget = nil
                                                },
                                                onFollowUp: { text in
                                                    followUp(with: text)
                                                },
                                                onDelete: {
                                                    deleteMessage(item)
                                                }
                                            )
                                        }
                                    }
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal)

                            if isLoading {
                                HStack(spacing: 10) {
                                    AppThemeLoadingView(customSize: 28)
                                    HStack(spacing: 5) {
                                        Text("AI đang phân tích & phản hồi")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                        AppThemeWaveDotsView(dotSize: 5, spacing: 3, bounceHeight: 3.8)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(AppTheme.Surface.card)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                                .id("loading-indicator")
                            }

                            // Bottom anchor for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.top)
                        .onChange(of: isLoading) { _, newValue in
                            guard newValue else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                guard isLoading else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: conversation.messages.count) { _, _ in
                            let sortedMessages = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
                            guard let lastMessage = sortedMessages.last else { return }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if lastMessage.isUser {
                                        if isLoading {
                                            proxy.scrollTo("loading-indicator", anchor: .bottom)
                                        } else {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    } else {
                                        proxy.scrollTo(lastMessage.id, anchor: .top)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if let targetID = targetHighlightedMessageID {
                                        proxy.scrollTo(targetID, anchor: .center)
                                    } else {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }

                        }
                        .onChange(of: highlightedMessageID) { _, _ in
                            if let targetID = targetHighlightedMessageID {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(targetID, anchor: .center)
                                    }
                                }
                            }
                        }
                        .onChange(of: highlightedSourceText) { _, _ in
                            if let targetID = targetHighlightedMessageID {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(targetID, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in
                            hideTabBar()
                        }
                )
                .onTapGesture {
                    hideKeyboard()
                }

                Divider()
                    .overlay(AppTheme.Surface.border)

                nextWordSuggestionBar

                inputBar
            }
            .navigationTitle(conversation.title.isEmpty
                             ? "New Chat"
                             : conversation.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isTabBarVisible ? .visible : .hidden, for: .tabBar)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showLiveVoiceMode = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.and.mic")
                                    .font(.caption.bold())
                                Text("Voice AI")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.Primary.p500)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            ForEach(AIModelOption.allCases) { option in
                                Button {
                                    selectedAIModelRawValue = option.rawValue
                                } label: {
                                    Label(
                                        option.title,
                                        systemImage: selectedAIModel == option
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                    )
                                }
                            }
                        } label: {
                            Image("swap_icon")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .accessibilityLabel("AI Model: \(selectedAIModel.providerName)")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .fullScreenCover(isPresented: $showLiveVoiceMode) {
                LiveVoiceConversationScreen(conversation: conversation)
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            selectedAttachedImage = uiImage
                        }
                    }
                }
            }
            .alert("Cần quyền truy cập Camera", isPresented: $showCameraPermissionAlert) {
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Ứng dụng cần quyền Camera để chụp ảnh đồ vật và phân tích cảnh vật giúp bạn học từ vựng tiếng Anh. Vui lòng bật quyền Camera trong Cài đặt của máy.")
            }
            .alert("Camera không khả dụng", isPresented: $showCameraUnavailableAlert) {
                Button("Chọn từ thư viện ảnh") {
                    showPhotosPicker = true
                }
                Button("Đóng", role: .cancel) {}
            } message: {
                Text("Thiết bị này không có camera vật lý hoặc đang chạy trên trình giả lập Simulator. Bạn có thể chọn ảnh có sẵn từ thư viện ảnh.")
            }

            if showSnackbar {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Semantic.success)
                        Text(snackbarMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(AppTheme.Neutral.n900.opacity(0.88))
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.Shadow.card, radius: 8, x: 0, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
                }
                .animation(.spring(), value: showSnackbar)
                .zIndex(1)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    toggleTabBar()
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            hideTabBar()
        }
        .onChange(of: message) { _, newValue in
            updateTypingSuggestions(for: newValue)
        }
        .onDisappear {
            suggestionTask?.cancel()
            speechRecognizer.stopRecording()
            if !showLiveVoiceMode {
                SpeechSynthesizerManager.shared.stop()
            }
        }
    }

    // MARK: - Subviews

    private var aiConfigCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("AI Conversation Setup")
                .font(.headline)
                .foregroundStyle(AppTheme.Neutral.n900)

            VStack(alignment: .leading, spacing: 8) {

                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n500)

                TextField(
                    "Daily English Practice",
                    text: $conversation.title
                )
                .padding()
                .background(AppTheme.Surface.cardMuted)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                }
            }

            VStack(alignment: .leading, spacing: 8) {

                Text("AI Context")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n500)

                TextField(
                    """
                    Help me improve conversational English naturally...
                    """,
                    text: $conversation.conversationDescription,
                    axis: .vertical
                )
                .lineLimit(4...8)
                .padding()
                .background(AppTheme.Surface.cardMuted)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                }
            }

            if conversation.messages.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        startSituationWithAISpeakingFirst()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("AI mở lời tình huống trước")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.Primary.p500)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    Button {
                        showLiveVoiceMode = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.and.mic")
                            Text("Voice AI")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Accent.a600)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.Accent.a50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(AppTheme.Accent.a500, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }
        }
        .padding()
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
        }
        .shadow(
            color: AppTheme.Shadow.card,
            radius: 12,
            x: 0,
            y: 6
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var nextWordSuggestionBar: some View {
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (!typingSuggestions.isEmpty || isFetchingTypingSuggestions) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isFetchingTypingSuggestions {
                        AppThemeLoadingView(customSize: 16)
                            .padding(.trailing, 2)
                    }

                    ForEach(typingSuggestions) { item in
                        Button {
                            applyTypingSuggestion(item.text)
                        } label: {
                            HStack(spacing: 5) {
                                if item.isAI {
                                    Image(systemName: "sparkles")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.Primary.p500)
                                }

                                Text(item.text)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.Neutral.n900)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                item.isAI
                                ? AppTheme.Primary.p50
                                : AppTheme.Surface.card
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        item.isAI
                                        ? AppTheme.Primary.p500.opacity(0.35)
                                        : AppTheme.Surface.border,
                                        lineWidth: 0.5
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }
            .background(AppTheme.Surface.appBackground)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let image = selectedAttachedImage {
                InputBarImagePreviewView(image: image) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedAttachedImage = nil
                        photosPickerItem = nil
                    }
                }
            }

            if speechRecognizer.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.Semantic.error)
                        .frame(width: 8, height: 8)

                    Text("Listening in English... Tap mic to stop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Semantic.error)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        handleCameraTap()
                    } label: {
                        Label("Chụp ảnh mới", systemImage: "camera")
                    }

                    Button {
                        showPhotosPicker = true
                    } label: {
                        Label("Chọn từ thư viện ảnh", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.headline)
                        .foregroundStyle(selectedAttachedImage != nil ? AppTheme.Primary.p500 : AppTheme.Neutral.n700)
                        .frame(width: 42, height: 42)
                        .background(selectedAttachedImage != nil ? AppTheme.Primary.p50 : AppTheme.Surface.card)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedAttachedImage != nil ? AppTheme.Primary.p500 : AppTheme.Surface.border,
                                    lineWidth: 0.5
                                )
                        }
                }
                .disabled(isLoading)
                .accessibilityLabel("Chụp hoặc chọn ảnh cảnh vật")
                .fullScreenCover(isPresented: $showCameraPicker) {
                    CameraPickerView(selectedImage: $selectedAttachedImage, isPresented: $showCameraPicker)
                        .ignoresSafeArea()
                }

                TextField(
                    speechRecognizer.isRecording ? "Speaking..." : (selectedAttachedImage != nil ? "Ask about this photo..." : "Write naturally..."),
                    text: $message,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .padding(12)
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            speechRecognizer.isRecording
                            ? AppTheme.Semantic.error
                            : AppTheme.Surface.border,
                            lineWidth: 0.5
                        )
                }

                Button {
                    toggleVoiceRecording()
                } label: {
                    Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic.fill")
                        .font(.headline)
                        .symbolEffect(.variableColor.iterative, isActive: speechRecognizer.isRecording)
                        .foregroundStyle(
                            speechRecognizer.isRecording
                            ? .white
                            : AppTheme.Neutral.n900
                        )
                        .frame(width: 42, height: 42)
                        .background(
                            speechRecognizer.isRecording
                            ? AppTheme.Semantic.error
                            : AppTheme.Surface.card
                        )
                        .clipShape(Circle())
                        .overlay {
                            if !speechRecognizer.isRecording {
                                Circle()
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                            }
                        }
                }
                .disabled(isLoading)
                .accessibilityLabel(speechRecognizer.isRecording ? "Stop voice input" : "Start voice input")

                let canSend = (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAttachedImage != nil) && !isLoading

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            !canSend
                            ? AppTheme.Neutral.n400
                            : AppTheme.Primary.p500
                        )
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding()
        .background(AppTheme.Surface.appBackground)
        .animation(.easeInOut(duration: 0.2), value: speechRecognizer.isRecording)
    }

    // MARK: - Helpers

    private func toggleVoiceRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            SpeechSynthesizerManager.shared.stop()
            speechRecognizer.startRecording(
                existingText: message,
                onUpdate: { updatedText in
                    message = updatedText
                },
                onError: { errorText in
                    showStatusMessage(errorText)
                }
            )
        }
    }



    private func applyTypingSuggestion(_ suggestion: String) {
        message = LocalNextWordSuggester.apply(suggestion: suggestion, to: message)
    }

    private func updateTypingSuggestions(for input: String) {
        suggestionTask?.cancel()

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            typingSuggestions = []
            isFetchingTypingSuggestions = false
            return
        }

        let contextReplies = latestAIMessage?.suggestedReplies ?? []
        let localItems = LocalNextWordSuggester.suggest(
            for: input,
            suggestedReplies: contextReplies,
            savedWords: savedVocabularyWords,
            limit: 6
        )
        typingSuggestions = localItems

        // Debounce AI next-word suggestions (~500ms) when input has at least 2 characters
        guard trimmed.count >= 2 else {
            isFetchingTypingSuggestions = false
            return
        }

        let currentContext = conversation.conversationDescription
        let lastQuestion = latestAIMessage?.followUpQuestion
        let provider = selectedAIModel.makeProvider()

        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isFetchingTypingSuggestions = true
            }

            do {
                let aiService = AIService(provider: provider)
                let aiWords = try await aiService.suggestNextWords(
                    currentInput: input,
                    context: currentContext,
                    lastQuestion: lastQuestion
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    isFetchingTypingSuggestions = false

                    let lastTokenLower = input
                        .split(whereSeparator: { $0.isWhitespace })
                        .last
                        .map { String($0).trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? ""

                    var merged: [TypingSuggestionItem] = []
                    var seen = Set<String>()

                    for raw in aiWords {
                        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        let key = cleaned.lowercased()
                        guard !cleaned.isEmpty,
                              key != lastTokenLower,
                              key != trimmed.lowercased(),
                              !seen.contains(key) else {
                            continue
                        }
                        seen.insert(key)
                        merged.append(TypingSuggestionItem(text: cleaned, isAI: true))
                        if merged.count >= 4 {
                            break
                        }
                    }

                    for local in localItems {
                        let key = local.text.lowercased()
                        guard !seen.contains(key) else { continue }
                        seen.insert(key)
                        merged.append(local)
                        if merged.count >= 6 {
                            break
                        }
                    }

                    typingSuggestions = merged
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isFetchingTypingSuggestions = false
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func toggleTabBar() {
        hideKeyboard()

        withAnimation(.easeInOut(duration: 0.2)) {
            isTabBarVisible.toggle()
        }
    }

    private func hideTabBar() {
        guard isTabBarVisible else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            isTabBarVisible = false
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showStatusMessage("Copied")
    }

    private func followUp(with text: String) {
        message = text
        showStatusMessage("Added to input")
    }

    private func handleCameraTap() {
        let status = CameraPermissionHelper.checkStatus()
        switch status {
        case .available:
            showCameraPicker = true
        case .needsPermission:
            CameraPermissionHelper.requestPermission { granted in
                if granted {
                    showCameraPicker = true
                } else {
                    showCameraPermissionAlert = true
                }
            }
        case .permissionDenied:
            showCameraPermissionAlert = true
        case .notAvailable:
            showCameraUnavailableAlert = true
        }
    }


    private func saveVocabulary(_ word: String, sourceText: String, showToast: Bool = true) {
        do {
            _ = try VocabularyNoteStore.save(
                word: word,
                sourceText: sourceText,
                sourceConversation: conversation,
                in: context
            )

            if showToast {
                showStatusMessage("Saved vocabulary")
            }
        } catch {
            print("DEBUG: Failed to save vocabulary note: \(error)")
        }
    }

    private func deleteMessage(_ item: MessageModel) {
        context.delete(item)

        do {
            try context.save()
            showStatusMessage("Deleted")
        } catch {
            print("DEBUG: Failed to delete message: \(error)")
        }
    }

    private func showStatusMessage(_ text: String) {
        withAnimation {
            snackbarMessage = text
            showSnackbar = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSnackbar = false
            }
        }
    }

    // MARK: - Save Note

    private func saveNote(
        text: String,
        originalText: String,
        context: String,
        isExplanation: Bool,
        explanationNoted: String? = nil,
        sourceMessageID: UUID? = nil
    ) {
        let note = SavedNoteModel(
            text: text,
            originalText: originalText,
            originalContext: context,
            isExplanation: isExplanation,
            explanationNoted: explanationNoted,
            sourceConversationID: conversation.id,
            sourceMessageID: sourceMessageID,
            sourceConversationTitle: conversation.title
        )
        self.context.insert(note)

        do {
            try self.context.save()
            WidgetNoteStore.upsert(
                WidgetNoteSnapshot(
                    id: note.id,
                    text: note.text,
                    originalContext: note.originalContext,
                    isExplanation: note.isExplanation,
                    explanationNoted: note.explanationNoted,
                    createdAt: note.createdAt
                )
            )
            print("DEBUG: Successfully saved note to context.")
        } catch {
            print("DEBUG: Failed to save note: \(error)")
        }

        showStatusMessage("Added to Noted AI")
    }

    // MARK: - Send Message

    @MainActor
    private func startSituationWithAISpeakingFirst() {
        guard !isLoading else { return }
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        hideKeyboard()
        isLoading = true

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = conversation.conversationDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveContext = desc.isEmpty
            ? "Roleplay conversation about \(title.isEmpty ? "daily English communication" : title)."
            : desc

        Task {
            do {
                let aiService = AIService(provider: selectedAIModel.makeProvider())
                let response = try await aiService.improveEnglish(
                    userInput: "Please start our roleplay conversation in character by speaking first in English with a natural opening greeting and question that fits the situation: \(effectiveContext)",
                    context: effectiveContext,
                    recentHistory: []
                )

                await MainActor.run {
                    let openingLine: String = {
                        let q = response.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !q.isEmpty { return q }
                        let nat = response.natural.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !nat.isEmpty { return nat }
                        return "Hi! Let's start our conversation. How can I help you today?"
                    }()

                    if title.isEmpty || title == "Daily Life English" || title == "New Chat",
                       let suggestedTitle = response.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !suggestedTitle.isEmpty {
                        conversation.title = suggestedTitle
                    }

                    let starterMessage = MessageModel(
                        text: openingLine,
                        isUser: false,
                        followUpQuestion: openingLine,
                        suggestedReplies: response.suggestedReplies
                    )
                    starterMessage.conversation = conversation
                    context.insert(starterMessage)
                    try? context.save()

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showStatusMessage("Không thể khởi tạo lời mở đầu AI")
                }
            }
        }
    }

    @MainActor
    private func sendMessage() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }

        let userText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedImage = selectedAttachedImage

        guard !userText.isEmpty || attachedImage != nil else { return }

        message = ""
        selectedAttachedImage = nil
        photosPickerItem = nil
        isLoading = true

        let imgData = attachedImage?.jpegData(compressionQuality: 0.8)

        // 1. SAVE USER MESSAGE (LOCAL)
        let userMessage = MessageModel(
            text: userText.isEmpty ? "Describe what you see in this photo" : userText,
            isUser: true,
            imageData: imgData
        )
        userMessage.conversation = conversation
        context.insert(userMessage)

        do {
            try context.save()
            print("DEBUG: User message saved successfully.")
        } catch {
            print("DEBUG: Failed to save user message: \(error)")
        }

        if let imgData {
            Task {
                do {
                    let response = try await SceneVisionAIService.shared.describeScene(
                        imageData: imgData,
                        userPrompt: userText
                    )

                    await MainActor.run {
                        let aiMessage = MessageModel(
                            text: response.sceneOverview,
                            isUser: false,
                            imageData: imgData,
                            sceneDescription: response
                        )
                        aiMessage.conversation = conversation
                        context.insert(aiMessage)
                        try? context.save()
                        isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        showStatusMessage("Lỗi phân tích ảnh: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        // 2. PREPARE RECENT CONVERSATION HISTORY (LAST 20 MESSAGES)
        let recentHistory: [String] = conversation.messages
            .filter { $0.id != userMessage.id }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .suffix(20)
            .map { msg in
                if msg.isUser {
                    return "User: \(msg.text)"
                } else {
                    let aiReply = msg.followUpQuestion ?? msg.natural ?? msg.text
                    return "Coach: \(aiReply)"
                }
            }

        let currentContext = conversation.conversationDescription

        Task {

            do {
                // 3. CALL AI
                let aiService = AIService(
                    provider: selectedAIModel.makeProvider()
                )

                let response = try await aiService.improveEnglish(
                    userInput: userText,
                    context: currentContext,
                    recentHistory: recentHistory
                )

                await MainActor.run {
                    // 4. UPDATE AI CONTEXT & CONVERSATION TITLE FROM AI SUMMARY
                    if let updatedContext = response.updatedContext?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !updatedContext.isEmpty {
                        conversation.conversationDescription = updatedContext
                    }

                    if let suggestedTitle = response.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !suggestedTitle.isEmpty {
                        let currentTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let userTurnCount = conversation.messages.filter(\.isUser).count
                        let isDefaultOrAutoTitle = currentTitle.isEmpty
                            || currentTitle == "Daily Life English"
                            || currentTitle == "New Chat"
                            || currentTitle.hasPrefix("Topic:")

                        if isDefaultOrAutoTitle || userTurnCount <= 1 {
                            conversation.title = suggestedTitle
                        }
                    }

                    // 5. SAVE AI MESSAGE
                    let aiMessage = MessageModel(
                        text: """
                    Fixed: \(response.fixed)
                    Natural: \(response.natural)
                    """,
                        isUser: false,
                        fixed: response.fixed,
                        natural: response.natural,
                        alternativeExpressions: response.alternativeExpressions,
                        explanations: response.explanations.map { $0.text },
                        explanationNoted: response.explanations.map { $0.explanation_noted ?? "" },
                        followUpQuestion: response.followUpQuestion,
                        suggestedReplies: response.suggestedReplies
                    )
                    aiMessage.conversation = conversation
                    context.insert(aiMessage)

                    do {
                        try context.save()
                        print("DEBUG: AI message and updated context saved successfully.")
                    } catch {
                        print("DEBUG: Failed to save AI message: \(error)")
                    }

                    isLoading = false
                }

            } catch {
                await MainActor.run {
                    isLoading = false
                    print(error.localizedDescription)
                }
            }
        }
    }
}
