//
//  ListConversationScreen.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData

struct ConversationDeepLinkDestination: Hashable {
    let conversation: ConversationModel
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    var highlightedMessageID: UUID? = nil
}

enum NoteConversationResolver {
    static func resolve(
        conversations: [ConversationModel],
        conversationID: UUID?,
        messageID: UUID?,
        noteText: String,
        originalContext: String,
        originalText: String
    ) -> (conversation: ConversationModel, messageID: UUID?, highlightedSourceText: String?)? {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = originalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSourceText = !trimmedNote.isEmpty ? trimmedNote : (!trimmedContext.isEmpty ? trimmedContext : nil)

        // 1. Direct match by conversationID
        if let conversationID,
           let conv = conversations.first(where: { $0.id == conversationID }) {
            let matchedMsg = findMatchingMessage(
                in: conv,
                messageID: messageID,
                noteText: trimmedNote,
                contextText: trimmedContext,
                originalText: trimmedOriginal
            )
            return (conv, matchedMsg?.id ?? messageID, effectiveSourceText)
        }

        // 2. Match by messageID across all conversations
        if let messageID {
            for conv in conversations {
                if let matched = conv.messages.first(where: { $0.id == messageID }) {
                    return (conv, matched.id, effectiveSourceText)
                }
            }
        }

        // 3. Match by noteText across all conversations (exact candidate match first, then substring match)
        if !trimmedNote.isEmpty {
            for conv in conversations {
                if let matched = findMessageMatchingText(in: conv, query: trimmedNote, exactOnly: true) {
                    return (conv, matched.id, effectiveSourceText)
                }
            }
            for conv in conversations {
                if let matched = findMessageMatchingText(in: conv, query: trimmedNote, exactOnly: false) {
                    return (conv, matched.id, effectiveSourceText)
                }
            }
        }

        // 4. Match by originalContext across all conversations
        if !trimmedContext.isEmpty {
            for conv in conversations {
                if let matched = findMessageMatchingText(in: conv, query: trimmedContext, exactOnly: false) {
                    return (conv, matched.id, effectiveSourceText)
                }
            }
        }

        // 5. Match by originalText (user message) across all conversations
        if !trimmedOriginal.isEmpty {
            for conv in conversations {
                let sorted = conv.messages.sorted(by: { $0.createdAt < $1.createdAt })
                if let userIdx = sorted.firstIndex(where: {
                    $0.isUser && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedOriginal) == .orderedSame
                }) {
                    // Prefer the AI response right after the user message if available
                    if userIdx + 1 < sorted.count, !sorted[userIdx + 1].isUser {
                        return (conv, sorted[userIdx + 1].id, effectiveSourceText)
                    }
                    return (conv, sorted[userIdx].id, effectiveSourceText)
                }
            }
        }

        return nil
    }

    private static func findMatchingMessage(
        in conv: ConversationModel,
        messageID: UUID?,
        noteText: String,
        contextText: String,
        originalText: String
    ) -> MessageModel? {
        if let messageID,
           let matched = conv.messages.first(where: { $0.id == messageID }) {
            return matched
        }
        if !noteText.isEmpty {
            if let exact = findMessageMatchingText(in: conv, query: noteText, exactOnly: true) {
                return exact
            }
            if let partial = findMessageMatchingText(in: conv, query: noteText, exactOnly: false) {
                return partial
            }
        }
        if !contextText.isEmpty,
           let matched = findMessageMatchingText(in: conv, query: contextText, exactOnly: false) {
            return matched
        }
        if !originalText.isEmpty,
           let matched = findMessageMatchingText(in: conv, query: originalText, exactOnly: false) {
            return matched
        }
        return nil
    }

    private static func findMessageMatchingText(
        in conv: ConversationModel,
        query: String,
        exactOnly: Bool
    ) -> MessageModel? {
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowerQuery.isEmpty else { return nil }

        let sorted = conv.messages.sorted(by: { $0.createdAt < $1.createdAt })
        for msg in sorted {
            var candidates: [String] = [
                msg.fixed ?? "",
                msg.natural ?? "",
                msg.followUpQuestion ?? "",
                msg.text
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

            let hit = candidates.contains { candidate in
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !trimmed.isEmpty else { return false }
                if exactOnly {
                    return trimmed == lowerQuery
                } else {
                    return trimmed == lowerQuery || trimmed.contains(lowerQuery) || lowerQuery.contains(trimmed)
                }
            }
            if hit {
                return msg
            }
        }
        return nil
    }
}

struct ListConversationScreen: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \ConversationModel.createdAt, order: .reverse) private var conversations: [ConversationModel]
    @Query private var savedNotes: [SavedNoteModel]

    @ObservedObject private var coordinator = StructureNavigationCoordinator.shared

    @AppStorage("hasSeenWidgetOnboarding") private var hasSeenWidgetOnboarding = false
    @AppStorage("appThemeMode") private var appThemeModeRawValue = AppThemeMode.light.rawValue

    @State private var path = NavigationPath()
    @State private var showWidgetOnboarding = false
    @State private var showNotedAIScreen = false
    @State private var showVoiceRoleplaySheet = false
    @State private var activeVoiceConversation: ConversationModel?

    private var appThemeMode: AppThemeMode {
        AppThemeMode(rawValue: appThemeModeRawValue) ?? .light
    }

    var body: some View {

        NavigationStack(path: $path) {

            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                // EMPTY STATE
                if conversations.isEmpty {

                    VStack(spacing: 18) {

                        Image(systemName: "message.badge.plus")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.Primary.p500)
                            .frame(width: 104, height: 104)
                            .background(AppTheme.Primary.p100)
                            .clipShape(Circle())

                        Text("No Conversations Yet")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("Start practicing your English with AI")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n500)

                        Button {

                            createConversation()

                        } label: {

                            HStack(spacing: 10) {

                                Image(systemName: "plus")

                                Text("Create Conversation")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(AppTheme.Primary.p500)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(
                                color: AppTheme.Primary.p500.opacity(0.22),
                                radius: 14,
                                x: 0,
                                y: 8
                            )
                        }

                        Button {
                            showVoiceRoleplaySheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.and.mic")
                                Text("Giao tiếp Voice AI & Roleplay")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 13)
                            .background(AppTheme.Accent.a50)
                            .foregroundStyle(AppTheme.Accent.a600)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(AppTheme.Accent.a500.opacity(0.5), lineWidth: 1.2)
                            }
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, 100)
                    .padding()

                } else {

                    // LIST STATE
                    ScrollView {

                        LazyVStack(spacing: 14) {

                            liveVoiceQuickStartBanner

                            ForEach(conversations) { conversation in

                                NavigationLink(value: conversation) {

                                    ConversationCard(
                                        conversation: conversation
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        activeVoiceConversation = conversation
                                    } label: {
                                        Label("Mở Giao tiếp Voice AI", systemImage: "waveform.and.mic")
                                    }

                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(AppThemeMode.allCases) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appThemeModeRawValue = mode.rawValue
                                }
                            } label: {
                                Label(
                                    mode.title,
                                    systemImage: appThemeMode == mode
                                    ? "checkmark.circle.fill"
                                    : mode.icon
                                )
                            }
                        }
                    } label: {
                        Image(systemName: appThemeMode.icon)
                            .foregroundStyle(appThemeMode == .dark ? AppTheme.Highlight.h600 : AppTheme.Primary.p700)
                            .accessibilityLabel("Theme: \(appThemeMode.title)")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showVoiceRoleplaySheet = true
                        } label: {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.Accent.a600)
                        }
                        .accessibilityLabel("Giao tiếp Voice AI")

                        Button {
                            createConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(AppTheme.Primary.p700)
                        }
                    }
                }
            }
            .navigationDestination(for: ConversationModel.self) { conversation in

                ChatScreen(conversation: conversation)
            }
            .navigationDestination(for: ConversationDeepLinkDestination.self) { destination in
                ChatScreen(
                    conversation: destination.conversation,
                    highlightedWord: destination.highlightedWord,
                    highlightedSourceText: destination.highlightedSourceText,
                    highlightedMessageID: destination.highlightedMessageID
                )
            }
            .navigationDestination(isPresented: $showNotedAIScreen) {
                NotedAIScreen()
            }
            .sheet(isPresented: $showVoiceRoleplaySheet) {
                VoiceRoleplayPickerSheet { scenario in
                    showVoiceRoleplaySheet = false
                    startRoleplayVoiceConversation(scenario)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $activeVoiceConversation) { voiceConv in
                LiveVoiceConversationScreen(conversation: voiceConv)
            }
            .sheet(isPresented: $showWidgetOnboarding) {
                WidgetOnboardingSheet(
                    onOpenNotedAI: {
                        hasSeenWidgetOnboarding = true
                        showWidgetOnboarding = false
                        showNotedAIScreen = true
                    },
                    onDismiss: {
                        hasSeenWidgetOnboarding = true
                        showWidgetOnboarding = false
                    }
                )
                .onDisappear {
                    hasSeenWidgetOnboarding = true
                }
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                print("DEBUG: Conversations loaded: \(conversations.count)")
                showWidgetOnboardingIfNeeded()
                handlePendingConversationNavigation()
            }
            .onChange(of: coordinator.pendingConversationNavigation) { _, _ in
                handlePendingConversationNavigation()
            }
            .onChange(of: conversations.count) { _, _ in
                handlePendingConversationNavigation()
            }
        }
    }

    @MainActor
    private func handlePendingConversationNavigation() {
        guard let target = coordinator.pendingConversationNavigation else { return }
        guard !conversations.isEmpty else { return }

        let matchedNote = savedNotes.first(where: { $0.id == target.noteID })
            ?? savedNotes.first(where: { !target.noteText.isEmpty && $0.text == target.noteText })

        let convID = target.conversationID ?? matchedNote?.sourceConversationID
        let msgID = target.messageID ?? matchedNote?.sourceMessageID
        let noteText = !target.noteText.isEmpty ? target.noteText : (matchedNote?.text ?? "")
        let contextText = !target.originalContext.isEmpty ? target.originalContext : (matchedNote?.originalContext ?? "")
        let originalText = !target.originalText.isEmpty ? target.originalText : (matchedNote?.originalText ?? "")

        coordinator.pendingConversationNavigation = nil

        if let resolved = NoteConversationResolver.resolve(
            conversations: conversations,
            conversationID: convID,
            messageID: msgID,
            noteText: noteText,
            originalContext: contextText,
            originalText: originalText
        ) {
            if let matchedNote, matchedNote.sourceConversationID == nil {
                matchedNote.sourceConversationID = resolved.conversation.id
                matchedNote.sourceMessageID = resolved.messageID
                matchedNote.sourceConversationTitle = resolved.conversation.title
                try? context.save()
            }

            let destination = ConversationDeepLinkDestination(
                conversation: resolved.conversation,
                highlightedWord: nil,
                highlightedSourceText: resolved.highlightedSourceText,
                highlightedMessageID: resolved.messageID
            )
            path = NavigationPath()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                path.append(destination)
            }
        } else {
            // Fallback to Notes tab if the source conversation was deleted
            coordinator.selectedTab = .notes
        }
    }

    private var liveVoiceQuickStartBanner: some View {
        Button {
            showVoiceRoleplaySheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Primary.p500)
                        .frame(width: 48, height: 48)
                    Image(systemName: "waveform.and.mic")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Giao tiếp Voice AI 2 chiều")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Accent.a600)
                            .clipShape(Capsule())
                    }

                    Text("Đóng vai tình huống thực tế & luyện phản xạ nghe nói trực tiếp")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [AppTheme.Primary.p50, AppTheme.Accent.a50],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.Primary.p300, lineWidth: 1.3)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func startRoleplayVoiceConversation(_ scenario: VoiceRoleplayScenario) {
        let conversation = ConversationModel(
            title: scenario.title,
            conversationDescription: scenario.contextDescription
        )
        context.insert(conversation)

        let starterMessage = MessageModel(
            text: scenario.starterQuestion,
            isUser: false,
            followUpQuestion: scenario.starterQuestion,
            suggestedReplies: scenario.starterReplies
        )
        starterMessage.conversation = conversation
        context.insert(starterMessage)

        try? context.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            activeVoiceConversation = conversation
        }
    }

    // MARK: - Create Conversation

    @MainActor
    private func createConversation() {

        let conversation = ConversationModel(
            title: "Daily Life English",
            conversationDescription: """
 Help me practice casual English for daily conversations.
 Fix grammar mistakes and rewrite my sentences like a native speaker.
 Keep responses simple and friendly.
 """
        )

        // insert
        context.insert(conversation)

        do {
            try context.save()
            print("DEBUG: Successfully created and saved conversation.")
        } catch {
            print("DEBUG: Failed to save conversation: \(error)")
        }

        // navigate
        path.append(conversation)
    }

    private func deleteConversation(_ conversation: ConversationModel) {
        context.delete(conversation)

        do {
            try context.save()
            print("DEBUG: Successfully deleted conversation.")
        } catch {
            print("DEBUG: Failed to delete conversation: \(error)")
        }
    }

    private func showWidgetOnboardingIfNeeded() {
        guard !hasSeenWidgetOnboarding else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showWidgetOnboarding = true
        }
    }
}

private struct WidgetOnboardingSheet: View {
    let onOpenNotedAI: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Accent.a600)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.Accent.a100)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Noted AI Widget")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Neutral.n900)

                    Text("Review saved notes from your iPhone Home Screen.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                WidgetOnboardingStep(
                    icon: "note.text",
                    title: "Save notes",
                    message: "Open Noted AI and sync your saved notes to the widget."
                )

                WidgetOnboardingStep(
                    icon: "hand.tap",
                    title: "Add manually",
                    message: "On the Home Screen, touch and hold, tap +, then choose Noted AI."
                )

                WidgetOnboardingStep(
                    icon: "arrow.clockwise",
                    title: "Keep it updated",
                    message: "Use the widget sync button any time you want to refresh notes."
                )
            }

            Spacer(minLength: 0)

            Button {
                onOpenNotedAI()
            } label: {
                Label("Open Noted AI", systemImage: "note.text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.Primary.p500)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Later") {
                onDismiss()
            }
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.Neutral.n500)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(22)
        .background(AppTheme.Surface.appBackground)
    }
}

private struct WidgetOnboardingStep: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppTheme.Primary.p500)
                .frame(width: 28, height: 28)
                .background(AppTheme.Primary.p50)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
// MARK: - Conversation Card

struct ConversationCard: View {

    let conversation: ConversationModel

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Secondary.s600)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.Secondary.s100)
                    .clipShape(Circle())

                Text(conversation.title.isEmpty ? "New Chat" : conversation.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Spacer()

                Text(conversation.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            if !conversation.conversationDescription.isEmpty {

                Text(conversation.conversationDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .lineLimit(2)
            }

            Text(conversation.messages.sorted(by: { $0.createdAt < $1.createdAt }).last?.text ?? "No messages yet")
                .font(.footnote)
                .foregroundStyle(AppTheme.Neutral.n500)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}


#Preview {
    ListConversationScreen()
        .modelContainer(for: [ConversationModel.self], inMemory: true)
}
