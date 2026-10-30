//
//  SituationAskScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

enum SituationToneOption: String, CaseIterable, Identifiable {
    case auto = "Tự động"
    case daily = "Giao tiếp hàng ngày"
    case workFormal = "Công việc / Trang trọng"
    case casualFriends = "Thân mật / Bạn bè"
    case travelService = "Du lịch / Dịch vụ"
    case messageEmail = "Nhắn tin / Email"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .daily: return "bubble.left.and.bubble.right.fill"
        case .workFormal: return "briefcase.fill"
        case .casualFriends: return "person.2.fill"
        case .travelService: return "airplane"
        case .messageEmail: return "envelope.fill"
        }
    }
}

struct SituationStarterPrompt: Identifiable {
    let id = UUID()
    let category: String
    let icon: String
    let prompt: String
    let tone: SituationToneOption
}

struct SituationAskScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SituationAskSessionModel.updatedAt, order: .reverse)
    private var sessions: [SituationAskSessionModel]

    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var activeSession: SituationAskSessionModel?
    @State private var selectedTone: SituationToneOption = .auto
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var showHistorySheet = false
    @State private var pickingTarget: WordPickTarget?
    @State private var showSnackbar = false
    @State private var snackbarMessage = ""
    @State private var practiceConversationDestination: ConversationModel?

    @StateObject private var speechRecognizer = SpeechRecognizerManager()

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    private var sortedMessages: [SituationAskMessageModel] {
        (activeSession?.messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    private let starterPrompts: [SituationStarterPrompt] = [
        SituationStarterPrompt(
            category: "Công sở",
            icon: "briefcase.fill",
            prompt: "Muốn từ chối khéo lời mời đi ăn tối sau giờ làm của đồng nghiệp và hẹn dịp khác thì nói sao?",
            tone: .daily
        ),
        SituationStarterPrompt(
            category: "Họp & Công việc",
            icon: "person.wave.2.fill",
            prompt: "Trong cuộc họp online, mạng bị lag không nghe rõ người khác vừa nói gì, muốn nhờ họ nhắc lại lịch sự?",
            tone: .workFormal
        ),
        SituationStarterPrompt(
            category: "Du lịch & Ẩm thực",
            icon: "fork.knife",
            prompt: "Ở nhà hàng nước ngoài, muốn hỏi nhân viên món này có cay không và nhờ tính tiền riêng từng người?",
            tone: .travelService
        ),
        SituationStarterPrompt(
            category: "Bạn bè",
            icon: "heart.text.square.fill",
            prompt: "Lâu ngày mới nhắn tin hỏi thăm một người bạn nước ngoài, mở lời sao cho tự nhiên không bị khách sáo?",
            tone: .casualFriends
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    toneSelectorBar

                    Divider()
                        .overlay(AppTheme.Surface.border.opacity(0.5))

                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(spacing: 18) {
                                if sortedMessages.isEmpty && !isLoading {
                                    emptyStarterView
                                } else {
                                    LazyVStack(spacing: 18) {
                                        ForEach(sortedMessages) { item in
                                            Group {
                                                if item.isUser {
                                                    SituationUserBubble(
                                                        message: item,
                                                        onCopy: {
                                                            copyText(item.text)
                                                        },
                                                        onAskAgain: {
                                                            inputText = item.text
                                                        },
                                                        onDelete: {
                                                            deleteMessage(item)
                                                        }
                                                    )
                                                } else if let response = item.decodedResponse {
                                                    SituationAIBubble(
                                                        messageID: item.id,
                                                        response: response,
                                                        pickingTarget: pickingTarget,
                                                        savedWords: savedVocabularyWords,
                                                        onCopy: { text in
                                                            copyText(text)
                                                        },
                                                        onSaveNote: { english, nuance in
                                                            saveExpressionToNotedAI(english: english, nuance: nuance)
                                                        },
                                                        onSaveVocabulary: { word, sourceSentence in
                                                            saveVocabulary(word, sourceText: sourceSentence)
                                                        },
                                                        onStartPickingWords: { target in
                                                            pickingTarget = target
                                                        },
                                                        onStopPickingWords: {
                                                            pickingTarget = nil
                                                        },
                                                        onSelectFollowUp: { followUp in
                                                            sendQuestion(followUp)
                                                        },
                                                        onStartPractice: { scenario in
                                                            startPracticeConversation(scenario)
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
                                            HStack(spacing: 10) {
                                                ProgressView()
                                                    .tint(AppTheme.Primary.p500)
                                                Text("AI đang phân tích tình huống & tìm cách nói tự nhiên nhất...")
                                                    .font(.subheadline)
                                                    .foregroundStyle(AppTheme.Neutral.n500)
                                            }
                                            .padding(.vertical, 16)
                                            .frame(maxWidth: .infinity)
                                        }

                                        if let errorMessage {
                                            errorBanner(errorMessage)
                                        }

                                        Color.clear
                                            .frame(height: 1)
                                            .id("situation-bottom")
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 14)
                                }
                            }
                            .onChange(of: sortedMessages.count) { _, _ in
                                guard let lastMsg = sortedMessages.last else { return }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if lastMsg.isUser {
                                            proxy.scrollTo("situation-bottom", anchor: .bottom)
                                        } else {
                                            proxy.scrollTo(lastMsg.id, anchor: .top)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        hideKeyboard()
                    }

                    Divider()
                        .overlay(AppTheme.Surface.border)

                    inputBar
                }

                if showSnackbar {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
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
                        .padding(.bottom, 90)
                    }
                    .animation(.spring(), value: showSnackbar)
                    .zIndex(1)
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                            if sessions.count > 1 {
                                Text("\(sessions.count)")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(AppTheme.Primary.p700)
                    }
                    .accessibilityLabel("Lịch sử hỏi đáp tình huống")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
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

                    Button {
                        startFreshSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(AppTheme.Primary.p700)
                    }
                    .disabled(isLoading || (activeSession?.messages.isEmpty ?? true))
                    .accessibilityLabel("Tạo phiên hỏi mới")
                }
            }
            .navigationDestination(item: $practiceConversationDestination) { conversation in
                ChatScreen(conversation: conversation)
            }
            .sheet(isPresented: $showHistorySheet) {
                SituationHistorySheet(
                    sessions: sessions,
                    activeSessionID: activeSession?.id,
                    onSelectSession: { session in
                        activeSession = session
                        if let tone = SituationToneOption(rawValue: session.selectedTone) {
                            selectedTone = tone
                        }
                        showHistorySheet = false
                    },
                    onCreateNew: {
                        startFreshSession()
                        showHistorySheet = false
                    },
                    onDeleteSession: { session in
                        deleteSession(session)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                if activeSession == nil {
                    activeSession = sessions.first
                    if let toneRaw = activeSession?.selectedTone,
                       let tone = SituationToneOption(rawValue: toneRaw) {
                        selectedTone = tone
                    }
                }
            }
            .onDisappear {
                speechRecognizer.stopRecording()
                SpeechSynthesizerManager.shared.stop()
            }
        }
    }

    private var navigationTitleText: String {
        guard let session = activeSession,
              !session.messages.isEmpty,
              !session.title.isEmpty,
              session.title != "Hỏi đáp tình huống" else {
            return "Hỏi cách nói"
        }
        return session.title
    }

    // MARK: - Subviews

    private var toneSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SituationToneOption.allCases) { option in
                    let isSelected = (selectedTone == option)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTone = option
                            activeSession?.selectedTone = option.rawValue
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.caption2.weight(.semibold))
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                            ? AppTheme.Primary.p500
                            : AppTheme.Surface.card
                        )
                        .foregroundStyle(
                            isSelected
                            ? .white
                            : AppTheme.Neutral.n700
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? AppTheme.Primary.p500 : AppTheme.Surface.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppTheme.Surface.appBackground)
    }

    private var emptyStarterView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.Accent.a600)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.Accent.a100)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trong hoàn cảnh này nói tiếng Anh thế nào?")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("Mô tả tình huống hoặc câu tiếng Việt bạn muốn diễn đạt, AI sẽ gợi ý các câu tự nhiên nhất theo từng sắc thái.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
            }
            .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Gợi ý tình huống thực tế (chạm để hỏi ngay)")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .textCase(.uppercase)

                ForEach(starterPrompts) { item in
                    Button {
                        selectedTone = item.tone
                        sendQuestion(item.prompt)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Primary.p500)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.Primary.p50)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.category)
                                        .font(.caption2.bold())
                                        .foregroundStyle(AppTheme.Primary.p500)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.Primary.p50)
                                        .clipShape(Capsule())

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.Neutral.n400)
                                }

                                Text(item.prompt)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Semantic.error)

            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n700)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let lastUserQuestion = sortedMessages.last(where: \.isUser)?.text {
                Button("Thử lại") {
                    retryQuestion(lastUserQuestion)
                }
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Primary.p500)
            }
        }
        .padding(12)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.Semantic.error.opacity(0.5), lineWidth: 1)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if speechRecognizer.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.Semantic.error)
                        .frame(width: 8, height: 8)

                    Text("Listening... Tap mic to stop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Semantic.error)

                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    speechRecognizer.isRecording
                    ? "Đang nghe..."
                    : "Mô tả hoàn cảnh hoặc câu muốn nói bằng tiếng Anh...",
                    text: $inputText,
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

                Button {
                    sendQuestion(inputText)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? AppTheme.Neutral.n400
                            : AppTheme.Primary.p500
                        )
                        .clipShape(Circle())
                }
                .disabled(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                )
            }
        }
        .padding()
        .background(AppTheme.Surface.appBackground)
    }

    // MARK: - Actions

    private func startFreshSession() {
        pickingTarget = nil
        errorMessage = nil
        inputText = ""

        if let existingEmpty = sessions.first(where: { $0.messages.isEmpty }) {
            activeSession = existingEmpty
            return
        }

        let newSession = SituationAskSessionModel(
            title: "Hỏi đáp tình huống",
            selectedTone: selectedTone.rawValue
        )
        context.insert(newSession)
        try? context.save()
        activeSession = newSession
    }

    private func ensureActiveSession() -> SituationAskSessionModel {
        if let activeSession {
            return activeSession
        }
        if let first = sessions.first {
            activeSession = first
            return first
        }
        let created = SituationAskSessionModel(
            title: "Hỏi đáp tình huống",
            selectedTone: selectedTone.rawValue
        )
        context.insert(created)
        try? context.save()
        activeSession = created
        return created
    }

    @MainActor
    private func sendQuestion(_ rawQuestion: String) {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }

        let trimmed = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil
        pickingTarget = nil

        let session = ensureActiveSession()
        session.selectedTone = selectedTone.rawValue
        session.updatedAt = Date()

        let userMsg = SituationAskMessageModel(
            text: trimmed,
            toneTag: selectedTone == .auto ? nil : selectedTone.rawValue,
            isUser: true
        )
        userMsg.session = session
        context.insert(userMsg)
        try? context.save()

        performAIRequest(for: trimmed, in: session, excludingMessageID: userMsg.id)
    }

    @MainActor
    private func retryQuestion(_ question: String) {
        guard !isLoading else { return }
        errorMessage = nil
        let session = ensureActiveSession()
        performAIRequest(for: question, in: session, excludingMessageID: nil)
    }

    @MainActor
    private func performAIRequest(
        for question: String,
        in session: SituationAskSessionModel,
        excludingMessageID: UUID?
    ) {
        isLoading = true

        let recentHistory: [String] = session.messages
            .filter { $0.id != excludingMessageID }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(10)
            .map { msg in
                if msg.isUser {
                    return "User question: \(msg.text)"
                } else if let resp = msg.decodedResponse {
                    let topExpressions = resp.expressions.prefix(3).map(\.english).joined(separator: " | ")
                    return "Coach suggested: \(topExpressions)"
                } else {
                    return "Coach: \(msg.text)"
                }
            }

        let tonePreference = selectedTone.rawValue
        let provider = selectedAIModel.makeSituationProvider()

        Task {
            do {
                let service = SituationAIService(provider: provider)
                let response = try await service.askHowToSay(
                    question: question,
                    tonePreference: tonePreference,
                    recentHistory: recentHistory
                )

                await MainActor.run {
                    if let newTitle = response.situationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !newTitle.isEmpty,
                       (session.title.isEmpty || session.title == "Hỏi đáp tình huống" || session.messages.filter(\.isUser).count <= 1) {
                        session.title = newTitle
                    }
                    session.updatedAt = Date()

                    let aiMsg = SituationAskMessageModel(
                        text: response.situationAdvice,
                        isUser: false,
                        response: response
                    )
                    aiMsg.session = session
                    context.insert(aiMsg)
                    try? context.save()

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func startPracticeConversation(_ scenario: VocabularyChatTopicSuggestion) {
        let newConversation = ConversationModel(
            title: scenario.title,
            conversationDescription: scenario.contextDescription
        )
        context.insert(newConversation)

        let starterMessage = MessageModel(
            text: scenario.starterQuestion,
            isUser: false,
            followUpQuestion: scenario.starterQuestion,
            suggestedReplies: scenario.sampleReplies
        )
        starterMessage.conversation = newConversation
        context.insert(starterMessage)

        do {
            try context.save()
            practiceConversationDestination = newConversation
        } catch {
            print("DEBUG: Failed to start practice conversation: \(error)")
        }
    }

    private func saveExpressionToNotedAI(english: String, nuance: String) {
        let note = SavedNoteModel(
            text: english,
            originalText: nil,
            originalContext: nuance,
            isExplanation: true,
            explanationNoted: english
        )
        context.insert(note)

        do {
            try context.save()
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
            showStatusMessage("Đã lưu vào Noted AI")
        } catch {
            print("DEBUG: Failed to save note from situation screen: \(error)")
        }
    }

    private func saveVocabulary(_ word: String, sourceText: String) {
        do {
            _ = try VocabularyNoteStore.save(
                word: word,
                sourceText: sourceText,
                sourceConversation: nil,
                in: context
            )
            if pickingTarget == nil {
                showStatusMessage("Đã lưu từ vựng")
            }
        } catch {
            print("DEBUG: Failed to save vocabulary: \(error)")
        }
    }

    private func deleteMessage(_ item: SituationAskMessageModel) {
        context.delete(item)
        try? context.save()
        showStatusMessage("Đã xoá")
    }

    private func deleteSession(_ session: SituationAskSessionModel) {
        let deletingActive = (activeSession?.id == session.id)
        context.delete(session)
        try? context.save()

        if deletingActive {
            activeSession = sessions.first(where: { $0.id != session.id })
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showStatusMessage("Đã sao chép")
    }

    private func toggleVoiceRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            SpeechSynthesizerManager.shared.stop()
            speechRecognizer.startRecording(
                existingText: inputText,
                onUpdate: { updated in
                    inputText = updated
                },
                onError: { err in
                    showStatusMessage(err)
                }
            )
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
}

// MARK: - User Bubble

private struct SituationUserBubble: View {
    let message: SituationAskMessageModel
    let onCopy: () -> Void
    let onAskAgain: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: UIScreen.main.bounds.width * 0.2)

            VStack(alignment: .trailing, spacing: 6) {
                if let toneTag = message.toneTag, !toneTag.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(toneTag)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.Primary.p700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.Primary.p500)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .contextMenu {
                        Button(action: onCopy) {
                            Label("Sao chép", systemImage: "doc.on.doc")
                        }
                        Button(action: onAskAgain) {
                            Label("Đưa vào ô nhập", systemImage: "arrowshape.turn.up.left")
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

// MARK: - AI Response Bubble

private struct SituationAIBubble: View {
    let messageID: UUID
    let response: AISituationAskResponse
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    let onCopy: (String) -> Void
    let onSaveNote: (String, String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onSelectFollowUp: (String) -> Void
    let onStartPractice: (VocabularyChatTopicSuggestion) -> Void
    let onDelete: () -> Void

    @State private var activeLightAnalysisIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. SITUATION ADVICE / CULTURAL TIP
            if !response.situationAdvice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Tư vấn ngữ cảnh", systemImage: "lightbulb.fill")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Accent.a600)

                        Spacer()

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n400)
                        }
                    }

                    Text(response.situationAdvice)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(AppTheme.Accent.a50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                }
            }

            // 2. EXPRESSIONS LIST
            VStack(alignment: .leading, spacing: 12) {
                Label("Các cách nói tiếng Anh phù hợp", systemImage: "text.bubble.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                ForEach(Array(response.expressions.enumerated()), id: \.offset) { index, item in
                    expressionCardView(index: index, item: item)
                }
            }

            // 3. PRACTICE CONVERSATION BUTTON
            if let scenario = response.practiceScenario {
                Button {
                    onStartPractice(scenario)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.Primary.p500)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Luyện hội thoại tình huống này")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.Primary.p700)

                            Text(scenario.starterQuestion)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Primary.p500)
                    }
                    .padding(12)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppTheme.Primary.p300, lineWidth: 1.2)
                    }
                }
                .buttonStyle(.plain)
            }

            // 4. FOLLOW-UP QUESTIONS
            let validFollowUps = response.followUpQuestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !validFollowUps.isEmpty {
                Divider()
                    .overlay(AppTheme.Surface.border)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Hỏi sâu hơn về tình huống này:", systemImage: "sparkles")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Neutral.n500)

                    ForEach(validFollowUps, id: \.self) { question in
                        Button {
                            onSelectFollowUp(question)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.Primary.p500)

                                Text(question)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppTheme.Surface.cardMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func expressionCardView(index: Int, item: AISituationExpressionItem) -> some View {
        let baseTarget = WordPickTarget(messageID: messageID, section: "expr-\(index)")
        let activeMode: WordInteractionMode? = (pickingTarget?.matchesSection(baseTarget) == true) ? pickingTarget?.mode : nil

        VStack(alignment: .leading, spacing: 10) {
            expressionHeaderToolbar(index: index, item: item, activeMode: activeMode)

            if let activeMode {
                WordPickerText(
                    text: item.english,
                    mode: activeMode,
                    foregroundStyle: AppTheme.Neutral.n900,
                    chipBackground: AppTheme.Surface.card,
                    modeBackground: AppTheme.Accent.a50,
                    savedWords: savedWords,
                    onPick: { word in
                        onSaveVocabulary(word, item.english)
                    },
                    onDone: onStopPickingWords
                )
            } else {
                Text(item.english)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button {
                            SpeechSynthesizerManager.shared.toggleSpeak(item.english)
                        } label: {
                            Label("Speak", systemImage: "speaker.wave.2.fill")
                        }

                        Button {
                            onCopy(item.english)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "expr-\(index)", mode: .pickWord))
                        } label: {
                            Label("Pick word", systemImage: "hand.tap")
                        }

                        Button {
                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "expr-\(index)", mode: .lightPickWord))
                        } label: {
                            Label("Light pick word", systemImage: "character.book.closed.fill")
                        }

                        Button {
                            activeLightAnalysisIndex = index
                        } label: {
                            Label("Light analysis", systemImage: "sparkles.rectangle.stack.fill")
                        }

                        Button {
                            StructureNavigationCoordinator.shared.openAndAnalyze(item.english)
                        } label: {
                            Label("Phân tích cấu trúc", systemImage: "rectangle.3.group.fill")
                        }
                    }
            }

            Text(item.vietnameseNuance)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n700)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let exchange = item.exampleExchange?.trimmingCharacters(in: .whitespacesAndNewlines),
               !exchange.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n400)
                        .padding(.top, 2)

                    Text(exchange)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SpeakButton(
                        text: exchange,
                        font: .caption2,
                        activeColor: AppTheme.Primary.p500
                    )
                }
                .padding(10)
                .background(AppTheme.Surface.cardMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(AppTheme.Secondary.s50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private func expressionHeaderToolbar(
        index: Int,
        item: AISituationExpressionItem,
        activeMode: WordInteractionMode?
    ) -> some View {
        let isPickWord = (activeMode == .pickWord)
        let isLightPick = (activeMode == .lightPickWord)

        HStack(spacing: 8) {
            Text(item.tone)
                .font(.caption2.bold())
                .foregroundStyle(toneColor(for: item.tone))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(toneBackground(for: item.tone))
                .clipShape(Capsule())

            Spacer()

            SpeakButton(
                text: item.english,
                slow: false,
                font: .caption.weight(.semibold),
                activeColor: AppTheme.Primary.p500,
                showBackground: true
            )

            SpeakButton(
                text: item.english,
                slow: true,
                font: .caption.weight(.semibold),
                activeColor: AppTheme.Accent.a600,
                showBackground: true
            )

            Button {
                if isPickWord {
                    onStopPickingWords()
                } else {
                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "expr-\(index)", mode: .pickWord))
                }
            } label: {
                Image(systemName: "hand.tap")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPickWord ? Color.white : AppTheme.Neutral.n500)
                    .padding(6)
                    .background(isPickWord ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                if isLightPick {
                    onStopPickingWords()
                } else {
                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "expr-\(index)", mode: .lightPickWord))
                }
            } label: {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLightPick ? Color.white : AppTheme.Primary.p500)
                    .padding(6)
                    .background(isLightPick ? AppTheme.Primary.p500 : AppTheme.Primary.p50)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                activeLightAnalysisIndex = index
            } label: {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(6)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: Binding(
                    get: { activeLightAnalysisIndex == index },
                    set: { isPresented in
                        if !isPresented && activeLightAnalysisIndex == index {
                            activeLightAnalysisIndex = nil
                        }
                    }
                ),
                attachmentAnchor: .rect(.bounds)
            ) {
                QuickSentenceAnalysisPopoverView(
                    sentence: item.english,
                    onOpenFullAnalysis: {
                        activeLightAnalysisIndex = nil
                        StructureNavigationCoordinator.shared.openAndAnalyze(item.english)
                    }
                )
                .presentationCompactAdaptation(.popover)
            }

            Button {
                onSaveNote(item.english, item.vietnameseNuance)
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding(6)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                onCopy(item.english)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding(6)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toneColor(for tone: String) -> Color {
        let lower = tone.lowercased()
        if lower.contains("trang trọng") || lower.contains("lịch sự") || lower.contains("công") {
            return AppTheme.Primary.p700
        } else if lower.contains("thân mật") || lower.contains("bạn") || lower.contains("ngắn") {
            return AppTheme.Accent.a600
        } else {
            return AppTheme.Semantic.success
        }
    }

    private func toneBackground(for tone: String) -> Color {
        let lower = tone.lowercased()
        if lower.contains("trang trọng") || lower.contains("lịch sự") || lower.contains("công") {
            return AppTheme.Primary.p50
        } else if lower.contains("thân mật") || lower.contains("bạn") || lower.contains("ngắn") {
            return AppTheme.Accent.a100
        } else {
            return AppTheme.Semantic.success.opacity(0.14)
        }
    }
}

// MARK: - History Sheet

private struct SituationHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessions: [SituationAskSessionModel]
    let activeSessionID: UUID?
    let onSelectSession: (SituationAskSessionModel) -> Void
    let onCreateNew: () -> Void
    let onDeleteSession: (SituationAskSessionModel) -> Void

    private var nonEmptySessions: [SituationAskSessionModel] {
        sessions.filter { !$0.messages.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                if nonEmptySessions.isEmpty {
                    ContentUnavailableView(
                        "Chưa có lịch sử hỏi đáp",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Các tình huống bạn đã hỏi AI sẽ được lưu tại đây để xem lại bất cứ lúc nào.")
                    )
                } else {
                    List {
                        ForEach(nonEmptySessions) { session in
                            let isCurrent = (session.id == activeSessionID)
                            let lastUserText = session.messages
                                .filter(\.isUser)
                                .sorted { $0.createdAt < $1.createdAt }
                                .last?.text ?? ""

                            Button {
                                onSelectSession(session)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(session.title)
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.Neutral.n900)
                                                .lineLimit(1)

                                            if isCurrent {
                                                Text("Đang mở")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(AppTheme.Primary.p500)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(AppTheme.Primary.p50)
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        if !lastUserText.isEmpty {
                                            Text(lastUserText)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.Neutral.n500)
                                                .lineLimit(2)
                                        }

                                        HStack(spacing: 8) {
                                            Text(session.selectedTone)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.Accent.a600)

                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.Neutral.n400)

                                            Text(session.updatedAt, style: .date)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.Neutral.n400)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.Neutral.n400)
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(AppTheme.Surface.card)
                            .swipeActions {
                                Button(role: .destructive) {
                                    onDeleteSession(session)
                                } label: {
                                    Label("Xoá", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Lịch sử tình huống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCreateNew()
                    } label: {
                        Label("Tạo mới", systemImage: "plus")
                    }
                }
            }
        }
    }
}

#Preview {
    SituationAskScreen()
        .modelContainer(
            for: [
                ConversationModel.self,
                MessageModel.self,
                SavedNoteModel.self,
                VocabularyNoteModel.self,
                SituationAskSessionModel.self,
                SituationAskMessageModel.self
            ],
            inMemory: true
        )
}
