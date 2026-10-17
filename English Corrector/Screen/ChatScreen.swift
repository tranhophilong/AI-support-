//
//  ChatScreen.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData


struct ChatScreen: View {

    @Environment(\.modelContext) private var context

    @Bindable var conversation: ConversationModel
    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @State private var message = ""

    @State private var messages: [ChatMessage] = []

    @State private var isLoading = false

    @State private var showSnackbar = false
    @State private var snackbarMessage = ""
    @State private var pickingTarget: WordPickTarget?
    @State private var isTabBarVisible = false

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    var body: some View {

        ZStack {
            AppTheme.Surface.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {

                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 20) {

                            // AI CONFIG CARD

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

                            // CHAT MESSAGES

                            LazyVStack(spacing: 16) {

                                ForEach(conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })) { item in

                                    if item.isUser {

                                        UserBubble(
                                            id: item.id,
                                            text: item.text,
                                            isPickingWords: pickingTarget == WordPickTarget(messageID: item.id, section: "user"),
                                            savedWords: savedVocabularyWords,
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
                                            pickingTarget: pickingTarget,
                                            savedWords: savedVocabularyWords,
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
                                        let target = WordPickTarget(messageID: item.id, section: "message")

                                        HStack {
                                            Group {
                                                if pickingTarget == target {
                                                    WordPickerText(
                                                        text: item.text,
                                                        foregroundStyle: AppTheme.Neutral.n900,
                                                        chipBackground: AppTheme.Surface.card,
                                                        modeBackground: AppTheme.Accent.a50,
                                                        savedWords: savedVocabularyWords,
                                                        onPick: { word in
                                                            saveVocabulary(word, sourceText: item.text, showToast: false)
                                                        },
                                                        onDone: {
                                                            pickingTarget = nil
                                                        }
                                                    )
                                                } else {
                                                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                                        .foregroundStyle(AppTheme.Neutral.n900)
                                                        .lineLimit(nil)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                        .messageActions(
                                                            onCopy: {
                                                                copyText(item.text)
                                                            },
                                                            onPickWords: {
                                                                pickingTarget = target
                                                            },
                                                            onFollowUp: {
                                                                followUp(with: item.text)
                                                            },
                                                            onDelete: {
                                                                deleteMessage(item)
                                                            }
                                                        )
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(AppTheme.Surface.cardMuted)
                                            .clipShape(RoundedRectangle(cornerRadius: 18))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 18)
                                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                                            }

                                            Spacer(minLength: UIScreen.main.bounds.width * 0.22)
                                        }
                                    }
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
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        .onAppear {
                            // Scroll to bottom on initial load
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy.scrollTo("bottom", anchor: .bottom)
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

                // INPUT BAR

                HStack(alignment: .bottom, spacing: 12) {

                    TextField(
                        "Write naturally...",
                        text: $message,
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                    .padding(12)
                    .background(AppTheme.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                    }

                    Button {

                        sendMessage()

                    } label: {

                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                message.isEmpty ||
                                conversation.conversationDescription.isEmpty ||
                                isLoading
                                ? AppTheme.Neutral.n400
                                : AppTheme.Primary.p500
                            )
                            .clipShape(Circle())
                    }
                    .disabled(
                        message.isEmpty ||
                        conversation.conversationDescription.isEmpty ||
                        isLoading
                    )
                }
                .padding()
                .background(AppTheme.Surface.appBackground)
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
    }

    // MARK: - Helpers

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

        // 2. AUTO-GENERATE TITLE & DESCRIPTION IF FIRST MESSAGE
        // We check if count is 1 so we only do this once at the start of the chat
        if conversation.messages.count == 1 {
            conversation.title = "Topic: \(userText)"
            conversation.conversationDescription = "You have been learned English about \(userText)"
        }

        Task {

            do {
                // 3. CALL AI
                let aiService = AIService(
                    provider: selectedAIModel.makeProvider()
                )

                let response = try await aiService.improveEnglish(
                    userInput: userText,
                    context: conversation.conversationDescription
                )

                await MainActor.run {
                    // 4. SAVE AI MESSAGE
                    let aiMessage = MessageModel(
                        text: """
                    Fixed: \(response.fixed)
                    Natural: \(response.natural)
                    """,
                        isUser: false,
                        fixed: response.fixed,
                        natural: response.natural,
                        explanations: response.explanations.map { $0.text },
                        explanationNoted: response.explanations.map { $0.explanation_noted ?? "" }
                    )
                    aiMessage.conversation = conversation
                    context.insert(aiMessage)

                    do {
                        try context.save()
                        print("DEBUG: AI message saved successfully.")
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

struct UserBubble: View {

    let id: UUID
    let text: String
    let isPickingWords: Bool
    let savedWords: Set<String>
    let onCopy: () -> Void
    let onSaveVocabulary: (String) -> Void
    let onStartPickingWords: () -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: () -> Void
    let onDelete: () -> Void

    var body: some View {

        HStack {

            Spacer(minLength: UIScreen.main.bounds.width * 0.25)

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
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .foregroundStyle(.white)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .messageActions(
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
                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
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
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    let onSave: (String, Bool, String?) -> Void
    let onCopy: (String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: (String) -> Void
    let onDelete: () -> Void

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 6) {

                HStack {
                    Label("Fixed", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Semantic.success)

                    Spacer()

                    Button {
                        onSave(fixed, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let fixedTarget = WordPickTarget(messageID: messageID, section: "fixed")

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
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {

                HStack {
                    Label("Natural", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    Spacer()

                    Button {
                        onSave(natural, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let naturalTarget = WordPickTarget(messageID: messageID, section: "natural")

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
                        Text(natural.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
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
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
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
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 12, x: 0, y: 6)
    }

    private func explanationText(_ text: String, highlight: String? = nil) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var resultText = Text("")

        let highlightKeywords = ["formal", "suitable", "natural", "better", "correct", "native", "instead", "grammar", "mistake"]

        // Prepare specific highlight words if provided
        let specificHighlights = highlight?.lowercased().split(separator: " ").map(String.init) ?? []

        // Combine punctuation and quotes into a single CharacterSet
        var trimSet = CharacterSet.punctuationCharacters
        trimSet.insert(charactersIn: "'\"")

        for word in words {
            let cleanWord = word.lowercased().trimmingCharacters(in: trimSet)
            let inQuotes = word.contains("'") || word.contains("\"")

            let isSpecificHighlight = specificHighlights.contains(cleanWord)
            let isGeneralKeyword = highlightKeywords.contains(cleanWord)

            if inQuotes || isSpecificHighlight || isGeneralKeyword {
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

        var resultText = Text("")

        for word in revisedWords {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let isChanged = !originalWords.contains(cleanWord)

            if isChanged {
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

private extension View {

    func messageActions(
        onCopy: @escaping () -> Void,
        onPickWords: (() -> Void)? = nil,
        onFollowUp: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
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
