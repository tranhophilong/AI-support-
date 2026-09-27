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

    @State private var message = ""

    @State private var messages: [ChatMessage] = []

    @State private var isLoading = false

    @State private var showSnackbar = false
    @State private var snackbarMessage = ""

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
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
                                }
                            }
                            .padding()
                            .background(AppTheme.Surface.card)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.Surface.border, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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
                                            text: item.text,
                                            onCopy: {
                                                copyText(item.text)
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
                                            original: originalText,
                                            fixed: fixed,
                                            natural: natural,
                                            explanations: item.explanations ?? [],
                                            explanationNoted: item.explanationNoted ?? [],
                                            onSave: { noteText, isExplanation, noted in
                                                saveNote(text: noteText, originalText: originalText, context: fixed, isExplanation: isExplanation, explanationNoted: noted)
                                            },
                                            onCopy: { text in
                                                copyText(text)
                                            },
                                            onFollowUp: { text in
                                                followUp(with: text)
                                            },
                                            onDelete: {
                                                deleteMessage(item)
                                            }
                                        )
                                    } else {
                                        Text(item.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .messageActions(
                                                onCopy: {
                                                    copyText(item.text)
                                                },
                                                onFollowUp: {
                                                    followUp(with: item.text)
                                                },
                                                onDelete: {
                                                    deleteMessage(item)
                                                }
                                            )
                                        .padding()
                                        .foregroundStyle(AppTheme.Neutral.n900)
                                        .background(AppTheme.Surface.cardMuted)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
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
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.Surface.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))

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
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
                        Label(
                            "AI Model: \(selectedAIModel.providerName)",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
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
    }

    // MARK: - Helpers

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showStatusMessage("Copied")
    }

    private func followUp(with text: String) {
        message = text
        showStatusMessage("Added to input")
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

struct UserBubble: View {

    let text: String
    let onCopy: () -> Void
    let onFollowUp: () -> Void
    let onDelete: () -> Void

    var body: some View {

        HStack {

            Spacer()

            Text(text)
                .foregroundStyle(.white)
                .messageActions(
                    onCopy: onCopy,
                    onFollowUp: onFollowUp,
                    onDelete: onDelete
                )
            .padding()
            .background(AppTheme.Primary.p500)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct AIBubble: View {

    let original: String
    let fixed: String
    let natural: String
    let explanations: [String]
    let explanationNoted: [String]
    let onSave: (String, Bool, String?) -> Void
    let onCopy: (String) -> Void
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

                highlightedText(original: original, revised: fixed)
                    .font(.body)
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .messageActions(
                        onCopy: {
                            onCopy(fixed)
                        },
                        onFollowUp: {
                            onFollowUp(fixed)
                        },
                        onDelete: onDelete
                    )
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

                Text(natural)
                    .font(.body)
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .messageActions(
                        onCopy: {
                            onCopy(natural)
                        },
                        onFollowUp: {
                            onFollowUp(natural)
                        },
                        onDelete: onDelete
                    )
            }

            if !explanations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Explanations")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Accent.a600)

                    ForEach(Array(explanations.enumerated()), id: \.offset) { index, item in
                        let noted = (index < explanationNoted.count) ? explanationNoted[index] : nil
                        HStack(alignment: .top) {
                            (Text("• ") + explanationText(item, highlight: noted))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n700)

                            Spacer()

                            Button {
                                onSave(item, true, noted)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }
                        .messageActions(
                            onCopy: {
                                onCopy(item)
                            },
                            onFollowUp: {
                                onFollowUp(item)
                            },
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.Surface.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

private extension View {

    func messageActions(
        onCopy: @escaping () -> Void,
        onFollowUp: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
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
