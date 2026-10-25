//
//  ChatScreen.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation


struct ChatScreen: View {

    @Environment(\.modelContext) private var context

    @Bindable var conversation: ConversationModel
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil

    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @State private var message = ""

    @State private var messages: [ChatMessage] = []

    @State private var isLoading = false

    @State private var showSnackbar = false
    @State private var snackbarMessage = ""
    @State private var pickingTarget: WordPickTarget?
    @State private var isTabBarVisible = false

    @State private var typingSuggestions: [TypingSuggestionItem] = []
    @State private var isFetchingTypingSuggestions = false
    @State private var suggestionTask: Task<Void, Never>?

    @StateObject private var speechRecognizer = SpeechRecognizerManager()

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
        guard let word = highlightedWord?.normalizedVocabularyWord, !word.isEmpty else {
            return nil
        }

        let trimmedSource = highlightedSourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sorted = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })

        if !trimmedSource.isEmpty,
           let matchedBySource = sorted.first(where: { messageMatchesSource($0, source: trimmedSource) }) {
            return matchedBySource.id
        }

        return sorted.first(where: { messageContainsWord($0, normalizedWord: word) })?.id
    }

    private func messageMatchesSource(_ msg: MessageModel, source: String) -> Bool {
        let lowerSource = source.lowercased()
        let candidates: [String] = [
            msg.text,
            msg.fixed ?? "",
            msg.natural ?? "",
            msg.followUpQuestion ?? ""
        ] + (msg.explanations ?? []) + (msg.suggestedReplies ?? [])

        return candidates.contains { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !trimmed.isEmpty && (trimmed == lowerSource || trimmed.contains(lowerSource) || lowerSource.contains(trimmed))
        }
    }

    private func messageContainsWord(_ msg: MessageModel, normalizedWord: String) -> Bool {
        let candidates: [String] = [
            msg.text,
            msg.fixed ?? "",
            msg.natural ?? "",
            msg.followUpQuestion ?? ""
        ] + (msg.explanations ?? []) + (msg.suggestedReplies ?? [])

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

                                            UserBubble(
                                                id: item.id,
                                                text: item.text,
                                                isPickingWords: pickingTarget == WordPickTarget(messageID: item.id, section: "user"),
                                                savedWords: savedVocabularyWords,
                                                isHighlightedMessage: isHighlightedMsg,
                                                highlightedWord: activeHighlightWord,
                                                onCopy: {
                                                    copyText(item.text)
                                                },
                                                onSaveVocabulary: { word in
                                                    saveVocabulary(word, sourceText: item.text, showToast: pickingTarget == nil)
                                                },
                                                onStartPickingWords: {
                                                    pickingTarget = WordPickTarget(messageID: item.id, section: "user")
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
                                                    saveNote(text: noteText, originalText: originalText, context: fixed, isExplanation: isExplanation, explanationNoted: noted)
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

                                if isLoading {

                                    ProgressView()
                                        .tint(AppTheme.Primary.p500)
                                        .padding(.top, 20)
                                }

                                // Bottom anchor for auto-scroll
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top)
                        .onChange(of: conversation.messages.count) { _, _ in
                            let sortedMessages = conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
                            guard let lastMessage = sortedMessages.last else { return }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if lastMessage.isUser {
                                        proxy.scrollTo("bottom", anchor: .bottom)
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
            SpeechSynthesizerManager.shared.stop()
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
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
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
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                }
            }
        }
        .padding()
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
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
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.Primary.p500)
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
                                    .foregroundStyle(
                                        item.isAI
                                        ? AppTheme.Primary.p700
                                        : AppTheme.Neutral.n900
                                    )
                                    .lineLimit(1)

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
                                        lineWidth: 1
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

            HStack(alignment: .bottom, spacing: 10) {

                TextField(
                    speechRecognizer.isRecording ? "Speaking..." : "Write naturally...",
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
                            lineWidth: 1.5
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
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                            }
                        }
                }
                .disabled(isLoading)
                .accessibilityLabel(speechRecognizer.isRecording ? "Stop voice input" : "Start voice input")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            isLoading
                            ? AppTheme.Neutral.n400
                            : AppTheme.Primary.p500
                        )
                        .clipShape(Circle())
                }
                .disabled(
                    message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    isLoading
                )
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

    private func saveNote(text: String, originalText: String, context: String, isExplanation: Bool, explanationNoted: String? = nil) {
        let note = SavedNoteModel(
            text: text,
            originalText: originalText,
            originalContext: context,
            isExplanation: isExplanation,
            explanationNoted: explanationNoted
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
    private func sendMessage() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }

        let userText = message

        guard !userText.isEmpty else { return }

        message = ""
        isLoading = true


        // 1. SAVE USER MESSAGE (LOCAL)
        let userMessage = MessageModel(
            text: userText,
            isUser: true
        )
        userMessage.conversation = conversation
        context.insert(userMessage)

        do {
            try context.save()
            print("DEBUG: User message saved successfully.")
        } catch {
            print("DEBUG: Failed to save user message: \(error)")
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

struct WordPickTarget: Hashable {
    let messageID: UUID
    let section: String
}

func vocabularyHighlightedText(
    _ text: String,
    targetWord: String?,
    defaultColor: Color,
    highlightColor: Color = AppTheme.Accent.a600
) -> Text {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let targetWord,
          !targetWord.normalizedVocabularyWord.isEmpty else {
        return Text(trimmed).foregroundColor(defaultColor)
    }

    let normalizedTarget = targetWord.normalizedVocabularyWord
    let words = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    var result = Text("")

    for (index, word) in words.enumerated() {
        let suffix = index < words.count - 1 ? " " : ""
        if word.normalizedVocabularyWord == normalizedTarget {
            result = result + Text(word + suffix)
                .foregroundColor(highlightColor)
                .fontWeight(.heavy)
                .underline(true, color: highlightColor)
        } else {
            result = result + Text(word + suffix)
                .foregroundColor(defaultColor)
        }
    }

    return result
}

struct UserBubble: View {

    let id: UUID
    let text: String
    let isPickingWords: Bool
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    let onCopy: () -> Void
    let onSaveVocabulary: (String) -> Void
    let onStartPickingWords: () -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: () -> Void
    let onDelete: () -> Void

    var body: some View {

        HStack {

            Spacer(minLength: UIScreen.main.bounds.width * 0.25)

            VStack(alignment: .trailing, spacing: 6) {
                if isHighlightedMessage, let highlightedWord, !highlightedWord.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.bold))
                        Text("Từ vựng: \"\(highlightedWord)\"")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Accent.a500, lineWidth: 1)
                    }
                }

                Group {
                    if isPickingWords {
                        WordPickerText(
                            text: text,
                            foregroundStyle: .white,
                            chipBackground: AppTheme.Primary.p700,
                            modeBackground: AppTheme.Primary.p700.opacity(0.38),
                            savedWords: savedWords,
                            onPick: onSaveVocabulary,
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            text,
                            targetWord: highlightedWord,
                            defaultColor: .white,
                            highlightColor: AppTheme.Semantic.warning
                        )
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .messageActions(
                            speakText: text,
                            onCopy: onCopy,
                            onPickWords: onStartPickingWords,
                            onFollowUp: onFollowUp,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.Primary.p500)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                            lineWidth: isHighlightedMessage ? 2.5 : 1.5
                        )
                }
                .shadow(
                    color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.35) : .clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
        }
    }
}

struct AIBubble: View {

    let messageID: UUID
    let original: String
    let fixed: String
    let natural: String
    let explanations: [String]
    let explanationNoted: [String]
    let followUpQuestion: String?
    let suggestedReplies: [String]
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    let onSave: (String, Bool, String?) -> Void
    let onCopy: (String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: (String) -> Void
    let onDelete: () -> Void

    private func isSectionHighlighted(_ sectionText: String) -> Bool {
        guard isHighlightedMessage else { return false }
        let trimmedSection = sectionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedSection.isEmpty else { return false }

        if let source = highlightedSourceText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !source.isEmpty {
            if trimmedSection == source || trimmedSection.contains(source) || source.contains(trimmedSection) {
                return true
            }
        }

        if let word = highlightedWord?.normalizedVocabularyWord, !word.isEmpty {
            return sectionText
                .split(whereSeparator: \.isWhitespace)
                .contains { String($0).normalizedVocabularyWord == word }
        }

        return false
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            if isHighlightedMessage, let highlightedWord, !highlightedWord.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                    Text("Từ vựng đã lưu: \"\(highlightedWord)\"")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(AppTheme.Accent.a600)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.Accent.a50)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.Accent.a500, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 10) {
                    Label("Fixed", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Semantic.success)

                    Spacer()

                    SpeakButton(
                        text: fixed,
                        font: .caption,
                        activeColor: AppTheme.Semantic.success
                    )

                    Button {
                        onSave(fixed, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let fixedTarget = WordPickTarget(messageID: messageID, section: "fixed")
                let fixedHighlighted = isSectionHighlighted(fixed)

                Group {
                    if pickingTarget == fixedTarget {
                        WordPickerText(
                            text: fixed,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, fixed)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        highlightedText(original: original, revised: fixed)
                            .font(.body)
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: fixed,
                                onCopy: {
                                    onCopy(fixed)
                                },
                                onPickWords: {
                                    onStartPickingWords(fixedTarget)
                                },
                                onFollowUp: {
                                    onFollowUp(fixed)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                    .padding(12)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                fixedHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                lineWidth: fixedHighlighted ? 2.0 : 1.2
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 10) {
                    Label("Natural", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    Spacer()

                    SpeakButton(
                        text: natural,
                        font: .caption,
                        activeColor: AppTheme.Primary.p500
                    )

                    Button {
                        onSave(natural, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let naturalTarget = WordPickTarget(messageID: messageID, section: "natural")
                let naturalHighlighted = isSectionHighlighted(natural)

                Group {
                    if pickingTarget == naturalTarget {
                        WordPickerText(
                            text: natural,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, natural)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            natural,
                            targetWord: highlightedWord,
                            defaultColor: AppTheme.Neutral.n900
                        )
                            .font(.body)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: natural,
                                onCopy: {
                                    onCopy(natural)
                                },
                                onPickWords: {
                                    onStartPickingWords(naturalTarget)
                                },
                                onFollowUp: {
                                    onFollowUp(natural)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                    .padding(12)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                naturalHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                lineWidth: naturalHighlighted ? 2.0 : 1.2
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !explanations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Explanations")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Accent.a600)

                    ForEach(Array(explanations.enumerated()), id: \.offset) { index, item in
                        let noted = (index < explanationNoted.count) ? explanationNoted[index] : nil
                        let explanationTarget = WordPickTarget(messageID: messageID, section: "explanation-\(index)")
                        HStack(alignment: .top, spacing: 8) {
                            Group {
                                if pickingTarget == explanationTarget {
                                    WordPickerText(
                                        text: item,
                                        foregroundStyle: AppTheme.Neutral.n700,
                                        chipBackground: AppTheme.Surface.cardMuted,
                                        modeBackground: AppTheme.Accent.a50,
                                        savedWords: savedWords,
                                        onPick: { word in
                                            onSaveVocabulary(word, item)
                                        },
                                        onDone: onStopPickingWords
                                    )
                                } else {
                                    (Text("• ") + explanationText(item, highlight: noted))
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Neutral.n700)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .messageActions(
                                            speakText: item,
                                            onCopy: {
                                                onCopy(item)
                                            },
                                            onPickWords: {
                                                onStartPickingWords(explanationTarget)
                                            },
                                            onFollowUp: {
                                                onFollowUp(item)
                                            },
                                            onDelete: onDelete
                                        )
                                }
                            }
                            .layoutPriority(1)

                            Button {
                                onSave(item, true, noted)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }
                    }
                }
            }

            // KEEP CHATTING: FOLLOW-UP QUESTION & SUGGESTED REPLIES
            let trimmedQuestion = followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let validReplies = suggestedReplies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !trimmedQuestion.isEmpty || !validReplies.isEmpty {
                Divider()
                    .overlay(AppTheme.Surface.border)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Label("Keep Chatting", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Primary.p500)

                        Spacer()

                        if !trimmedQuestion.isEmpty {
                            SpeakButton(
                                text: trimmedQuestion,
                                font: .caption,
                                activeColor: AppTheme.Primary.p500
                            )

                            Button {
                                onSave(trimmedQuestion, false, nil)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }
                    }

                    if !trimmedQuestion.isEmpty {
                        let followUpTarget = WordPickTarget(messageID: messageID, section: "followUp")
                        let questionHighlighted = isSectionHighlighted(trimmedQuestion)

                        Group {
                            if pickingTarget == followUpTarget {
                                WordPickerText(
                                    text: trimmedQuestion,
                                    foregroundStyle: AppTheme.Neutral.n900,
                                    chipBackground: AppTheme.Surface.card,
                                    modeBackground: AppTheme.Accent.a50,
                                    savedWords: savedWords,
                                    onPick: { word in
                                        onSaveVocabulary(word, trimmedQuestion)
                                    },
                                    onDone: onStopPickingWords
                                )
                            } else {
                                vocabularyHighlightedText(
                                    trimmedQuestion,
                                    targetWord: highlightedWord,
                                    defaultColor: AppTheme.Neutral.n900
                                )
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .messageActions(
                                        speakText: trimmedQuestion,
                                        onCopy: {
                                            onCopy(trimmedQuestion)
                                        },
                                        onPickWords: {
                                            onStartPickingWords(followUpTarget)
                                        },
                                        onFollowUp: {
                                            onFollowUp(trimmedQuestion)
                                        },
                                        onDelete: onDelete
                                    )
                            }
                        }
                        .padding(12)
                        .background(AppTheme.Accent.a50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    questionHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                    lineWidth: questionHighlighted ? 2.0 : 1.2
                                )
                        }
                    }

                    if !validReplies.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested replies (tap to edit & send):")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.Neutral.n500)

                            ForEach(Array(validReplies.enumerated()), id: \.offset) { index, reply in
                                let replyTarget = WordPickTarget(messageID: messageID, section: "reply-\(index)")
                                let replyHighlighted = isSectionHighlighted(reply)

                                if pickingTarget == replyTarget {
                                    WordPickerText(
                                        text: reply,
                                        foregroundStyle: AppTheme.Neutral.n900,
                                        chipBackground: AppTheme.Surface.card,
                                        modeBackground: AppTheme.Accent.a50,
                                        savedWords: savedWords,
                                        onPick: { word in
                                            onSaveVocabulary(word, reply)
                                        },
                                        onDone: onStopPickingWords
                                    )
                                } else {
                                    HStack(alignment: .center, spacing: 8) {
                                        Button {
                                            onFollowUp(reply)
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "arrow.turn.down.right")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(AppTheme.Primary.p500)
                                                    .padding(.top, 2)

                                                vocabularyHighlightedText(
                                                    reply,
                                                    targetWord: highlightedWord,
                                                    defaultColor: AppTheme.Neutral.n900
                                                )
                                                    .font(.subheadline)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        SpeakButton(
                                            text: reply,
                                            font: .caption,
                                            activeColor: AppTheme.Primary.p500
                                        )
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.Surface.cardMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                replyHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                                lineWidth: replyHighlighted ? 2.0 : 1
                                            )
                                    }
                                    .messageActions(
                                        speakText: reply,
                                        onCopy: {
                                            onCopy(reply)
                                        },
                                        onPickWords: {
                                            onStartPickingWords(replyTarget)
                                        },
                                        onFollowUp: {
                                            onFollowUp(reply)
                                        },
                                        onDelete: onDelete
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                    lineWidth: isHighlightedMessage ? 2.5 : 1.5
                )
        }
        .shadow(
            color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.28) : AppTheme.Shadow.card,
            radius: 12,
            x: 0,
            y: 6
        )
    }

    private func explanationText(_ text: String, highlight: String? = nil) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var resultText = Text("")

        let highlightKeywords = ["formal", "suitable", "natural", "better", "correct", "native", "instead", "grammar", "mistake"]
        let targetVocab = highlightedWord?.normalizedVocabularyWord ?? ""

        // Prepare specific highlight words if provided
        let specificHighlights = highlight?.lowercased().split(separator: " ").map(String.init) ?? []

        // Combine punctuation and quotes into a single CharacterSet
        var trimSet = CharacterSet.punctuationCharacters
        trimSet.insert(charactersIn: "'\"")

        for word in words {
            let cleanWord = word.lowercased().trimmingCharacters(in: trimSet)
            let inQuotes = word.contains("'") || word.contains("\"")

            let isTargetVocab = !targetVocab.isEmpty && word.normalizedVocabularyWord == targetVocab
            let isSpecificHighlight = specificHighlights.contains(cleanWord)
            let isGeneralKeyword = highlightKeywords.contains(cleanWord)

            if isTargetVocab {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Accent.a600)
                    .fontWeight(.heavy)
                    .underline(true, color: AppTheme.Accent.a600)
            } else if inQuotes || isSpecificHighlight || isGeneralKeyword {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Semantic.success)
                    .fontWeight(.bold)
            } else {
                resultText = resultText + Text(word + " ")
            }
        }

        return resultText
    }

    private func highlightedText(original: String, revised: String) -> Text {
        let originalWords = original.lowercased().split(separator: " ").map(String.init)
        let revisedWords = revised.split(separator: " ").map(String.init)
        let targetVocab = highlightedWord?.normalizedVocabularyWord ?? ""

        var resultText = Text("")

        for word in revisedWords {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let isTargetVocab = !targetVocab.isEmpty && word.normalizedVocabularyWord == targetVocab
            let isChanged = !originalWords.contains(cleanWord)

            if isTargetVocab {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Accent.a600)
                    .fontWeight(.heavy)
                    .underline(true, color: AppTheme.Accent.a600)
            } else if isChanged {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Semantic.success)
                    .fontWeight(.bold)
            } else {
                resultText = resultText + Text(word + " ")
            }
        }

        return resultText
    }
}

struct WordPickerText: View {
    let text: String
    let foregroundStyle: Color
    let chipBackground: Color
    let modeBackground: Color
    let savedWords: Set<String>
    let onPick: (String) -> Void
    let onDone: () -> Void

    @AppStorage("wordPickerUsesPills") private var usesPills = true
    @State private var selectedWords: Set<String> = []
    @State private var sessionSavedWords: Set<String> = []

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.normalizedVocabularyWord.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Pick word", systemImage: "hand.tap")
                    .font(.caption.bold())
                    .foregroundStyle(foregroundStyle)

                Spacer()

                Button {
                    usesPills.toggle()
                } label: {
                    Label(
                        usesPills ? "Text" : "Pill",
                        systemImage: usesPills ? "textformat" : "capsule"
                    )
                    .labelStyle(.iconOnly)
                }
                .font(.caption.bold())
                .foregroundStyle(foregroundStyle)

                Button {
                    addSelectedWords()
                } label: {
                    Label("Add selected", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .font(.caption.bold())
                .foregroundStyle(selectedWords.isEmpty ? foregroundStyle.opacity(0.35) : foregroundStyle)
                .disabled(selectedWords.isEmpty)

                Button("Done", action: onDone)
                    .font(.caption.bold())
                    .foregroundStyle(foregroundStyle)
            }

            WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    let normalizedWord = word.normalizedVocabularyWord
                    let isSelected = selectedWords.contains(normalizedWord)
                    let isSaved = savedWords.contains(normalizedWord) || sessionSavedWords.contains(normalizedWord)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            if isSaved {
                                return
                            }

                            if isSelected {
                                selectedWords.remove(normalizedWord)
                            } else {
                                selectedWords.insert(normalizedWord)
                            }
                        }
                    } label: {
                        let displayWord = word.trimmingCharacters(in: .punctuationCharacters)
                        let activeBackground = isSaved
                        ? AppTheme.Semantic.success
                        : AppTheme.Accent.a500
                        let activeTextColor: Color = .white

                        if usesPills {
                            HStack(spacing: 5) {
                                if isSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2.weight(.bold))
                                }

                                Text(displayWord)
                                    .lineLimit(1)
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle((isSelected || isSaved) ? activeTextColor : foregroundStyle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((isSelected || isSaved) ? activeBackground : chipBackground)
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            (isSelected || isSaved) ? activeBackground : foregroundStyle.opacity(0.18),
                                            lineWidth: 1
                                        )
                                }
                                .clipShape(Capsule())
                                .scaleEffect((isSelected || isSaved) ? 1.04 : 1)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSaved)
                        } else {
                            HStack(spacing: 4) {
                                if isSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2.weight(.bold))
                                }

                                Text(displayWord)
                                    .lineLimit(1)
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(
                                isSaved
                                ? AppTheme.Semantic.success
                                : isSelected ? AppTheme.Accent.a600 : foregroundStyle
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                                .background(
                                    isSaved
                                    ? AppTheme.Semantic.success.opacity(0.14)
                                    : isSelected ? AppTheme.Accent.a100
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(
                                            isSaved
                                            ? AppTheme.Semantic.success
                                            : isSelected ? AppTheme.Accent.a600 : foregroundStyle.opacity(0.28)
                                        )
                                        .frame(height: 1)
                                }
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSaved)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(modeBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.Accent.a100, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func addSelectedWords() {
        let wordsToSave = selectedWords

        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            sessionSavedWords.formUnion(wordsToSave)
            selectedWords.removeAll()
        }

        for word in wordsToSave {
            onPick(word)
        }
    }
}

struct WordPickerFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(proposal.width ?? UIScreen.main.bounds.width - 64, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: ceil(y + lineHeight))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct StarterAIBubble: View {

    let messageID: UUID
    let text: String
    let suggestedReplies: [String]
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    let onCopy: (String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: (String) -> Void
    let onDelete: () -> Void

    private var validReplies: [String] {
        suggestedReplies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let target = WordPickTarget(messageID: messageID, section: "message")

        HStack {
            VStack(alignment: .leading, spacing: 12) {
                if isHighlightedMessage, let highlightedWord, !highlightedWord.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.bold))
                        Text("Từ vựng đã lưu: \"\(highlightedWord)\"")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Accent.a500, lineWidth: 1)
                    }
                }

                HStack(spacing: 10) {
                    Label("AI Coach", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    Spacer()

                    SpeakButton(
                        text: text,
                        font: .caption,
                        activeColor: AppTheme.Primary.p500
                    )
                }

                Group {
                    if pickingTarget == target {
                        WordPickerText(
                            text: text,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, text)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            text,
                            targetWord: highlightedWord,
                            defaultColor: AppTheme.Neutral.n900
                        )
                            .font(.subheadline.weight(.medium))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: text,
                                onCopy: {
                                    onCopy(text)
                                },
                                onPickWords: {
                                    onStartPickingWords(target)
                                },
                                onFollowUp: {
                                    onFollowUp(text)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                .padding(12)
                .background(AppTheme.Accent.a50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                }

                if !validReplies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested replies (tap to edit & send):")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n500)

                        ForEach(Array(validReplies.enumerated()), id: \.offset) { index, reply in
                            let replyTarget = WordPickTarget(messageID: messageID, section: "starter-reply-\(index)")

                            if pickingTarget == replyTarget {
                                WordPickerText(
                                    text: reply,
                                    foregroundStyle: AppTheme.Neutral.n900,
                                    chipBackground: AppTheme.Surface.card,
                                    modeBackground: AppTheme.Accent.a50,
                                    savedWords: savedWords,
                                    onPick: { word in
                                        onSaveVocabulary(word, reply)
                                    },
                                    onDone: onStopPickingWords
                                )
                            } else {
                                HStack(alignment: .center, spacing: 8) {
                                    Button {
                                        onFollowUp(reply)
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AppTheme.Primary.p500)
                                                .padding(.top, 2)

                                            vocabularyHighlightedText(
                                                reply,
                                                targetWord: highlightedWord,
                                                defaultColor: AppTheme.Neutral.n900
                                            )
                                                .font(.subheadline)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    SpeakButton(
                                        text: reply,
                                        font: .caption,
                                        activeColor: AppTheme.Primary.p500
                                    )
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.Surface.cardMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                                }
                                .messageActions(
                                    speakText: reply,
                                    onCopy: {
                                        onCopy(reply)
                                    },
                                    onPickWords: {
                                        onStartPickingWords(replyTarget)
                                    },
                                    onFollowUp: {
                                        onFollowUp(reply)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                        lineWidth: isHighlightedMessage ? 2.5 : 1.5
                    )
            }
            .shadow(
                color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.28) : AppTheme.Shadow.card,
                radius: 10,
                x: 0,
                y: 4
            )

            Spacer(minLength: 10)
        }
    }
}

private extension View {

    func messageActions(
        speakText: String? = nil,
        onCopy: @escaping () -> Void,
        onPickWords: (() -> Void)? = nil,
        onFollowUp: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            if let speakText, !speakText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    SpeechSynthesizerManager.shared.toggleSpeak(speakText)
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2.fill")
                }
            }

            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if let onPickWords {
                Button {
                    onPickWords()
                } label: {
                    Label("Pick word", systemImage: "hand.tap")
                }
            }

            Button {
                onFollowUp()
            } label: {
                Label("Follow up", systemImage: "arrowshape.turn.up.left")
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
            }
        }
    }
}

@MainActor
final class SpeechRecognizerManager: ObservableObject {

    @Published private(set) var isRecording = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startRecording(
        existingText: String,
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stopRecording()

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }

                guard authStatus == .authorized else {
                    onError("Please allow Speech Recognition in Settings")
                    return
                }

                let micAllowed = await AVAudioApplication.requestRecordPermission()
                guard micAllowed else {
                    onError("Please allow Microphone access in Settings")
                    return
                }

                self.beginSession(
                    existingText: existingText,
                    onUpdate: onUpdate,
                    onError: onError
                )
            }
        }
    }

    func stopRecording() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        if isRecording {
            isRecording = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginSession(
        existingText: String,
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            onError("Speech recognition is currently unavailable")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true

            let baseText = existingText.trimmingCharacters(in: .whitespacesAndNewlines)

            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        let spoken = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if !spoken.isEmpty {
                            let combined = baseText.isEmpty ? spoken : "\(baseText) \(spoken)"
                            onUpdate(combined)
                        }

                        if result.isFinal {
                            self.stopRecording()
                        }
                    }

                    if error != nil, self.isRecording {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            onError("Could not start microphone: \(error.localizedDescription)")
        }
    }
}


