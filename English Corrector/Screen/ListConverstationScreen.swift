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
    @State private var showHotNewsFeed = false
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
                                    .strokeBorder(AppTheme.Accent.a500.opacity(0.5), lineWidth: 0.5)
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
                                        conversation: conversation,
                                        onOpenVoiceAI: {
                                            activeVoiceConversation = conversation
                                        }
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
                            showHotNewsFeed = true
                        } label: {
                            Image(systemName: "newspaper.fill")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Primary.p700)
                        }
                        .accessibilityLabel("Tin tức tiếng Anh nóng hổi")

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
            .sheet(isPresented: $showHotNewsFeed) {
                HotNewsFeedScreen()
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
                    .strokeBorder(AppTheme.Primary.p300, lineWidth: 0.5)
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

        let trimmedStarter = scenario.starterQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStarter.isEmpty {
            let starterMessage = MessageModel(
                text: trimmedStarter,
                isUser: false,
                followUpQuestion: trimmedStarter,
                suggestedReplies: scenario.starterReplies
            )
            starterMessage.conversation = conversation
            context.insert(starterMessage)
        }

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
// MARK: - Conversation Card & Topic Style

private struct ConversationTopicTheme {
    let categoryLabel: String
    let icon: String
    let tintColor: Color
    let badgeBackground: Color

    static func resolve(title: String, description: String) -> ConversationTopicTheme {
        let combined = "\(title) \(description)".lowercased()

        let workKeywords = [
            "interview", "job", "work", "office", "meeting", "salary", "manager",
            "colleague", "business", "project", "standup", "career",
            "phỏng vấn", "công việc", "sếp", "họp", "lương", "đồng nghiệp", "văn phòng"
        ]
        if workKeywords.contains(where: { combined.contains($0) }) {
            return ConversationTopicTheme(
                categoryLabel: "CÔNG VIỆC",
                icon: "briefcase.fill",
                tintColor: AppTheme.Primary.p500,
                badgeBackground: AppTheme.Primary.p50
            )
        }

        let foodKeywords = [
            "coffee", "cafe", "restaurant", "order", "food", "drink", "menu",
            "dinner", "lunch", "breakfast", "waiter", "barista",
            "nhà hàng", "cà phê", "gọi món", "ăn uống", "ẩm thực"
        ]
        if foodKeywords.contains(where: { combined.contains($0) }) {
            return ConversationTopicTheme(
                categoryLabel: "ẨM THỰC & CAFE",
                icon: "cup.and.saucer.fill",
                tintColor: AppTheme.Accent.a600,
                badgeBackground: AppTheme.Accent.a50
            )
        }

        let travelKeywords = [
            "airport", "flight", "hotel", "travel", "customs", "immigration",
            "direction", "check-in", "booking", "room", "taxi", "train",
            "du lịch", "sân bay", "khách sạn", "hỏi đường", "chuyến bay"
        ]
        if travelKeywords.contains(where: { combined.contains($0) }) {
            return ConversationTopicTheme(
                categoryLabel: "DU LỊCH",
                icon: "airplane.departure",
                tintColor: AppTheme.Semantic.success,
                badgeBackground: AppTheme.Semantic.success.opacity(0.12)
            )
        }

        let serviceKeywords = [
            "shopping", "store", "buy", "price", "doctor", "hospital", "clinic",
            "symptom", "bank", "support",
            "mua sắm", "khám bệnh", "bác sĩ", "cửa hàng"
        ]
        if serviceKeywords.contains(where: { combined.contains($0) }) {
            return ConversationTopicTheme(
                categoryLabel: "ĐỜI SỐNG",
                icon: "bag.fill",
                tintColor: AppTheme.Accent.a600,
                badgeBackground: AppTheme.Accent.a50
            )
        }

        return ConversationTopicTheme(
            categoryLabel: "GIAO TIẾP HÀNG NGÀY",
            icon: "bubble.left.and.text.bubble.right.fill",
            tintColor: AppTheme.Primary.p500,
            badgeBackground: AppTheme.Primary.p50
        )
    }
}

struct ConversationCard: View {

    let conversation: ConversationModel
    var onOpenVoiceAI: (() -> Void)? = nil

    private var sortedMessages: [MessageModel] {
        conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private var latestMessage: MessageModel? {
        sortedMessages.last
    }

    private var topicTheme: ConversationTopicTheme {
        ConversationTopicTheme.resolve(
            title: conversation.title,
            description: conversation.conversationDescription
        )
    }

    private var displayTitle: String {
        let trimmed = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Chat" : trimmed
    }

    private var displaySubtitle: String {
        conversation.conversationDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private var latestMessagePreview: (senderLabel: String, isUser: Bool, content: String)? {
        guard let msg = latestMessage else { return nil }
        if msg.isUser {
            let cleaned = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return ("Bạn:", true, cleaned)
        } else {
            let natural = msg.natural?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let followUp = msg.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fixed = msg.fixed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)

            let bestLine: String = {
                if !natural.isEmpty { return natural }
                if !followUp.isEmpty { return followUp }
                if !fixed.isEmpty { return fixed }
                return raw.replacingOccurrences(of: "\n", with: " ")
            }()

            guard !bestLine.isEmpty else { return nil }
            return ("AI Coach:", false, bestLine)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 1. TẦNG HEADER: ICON CHỦ ĐỀ + CATEGORY & NGÀY + TITLE ĐẬM LỚN + NÚT VOICE AI
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(topicTheme.badgeBackground)
                        .frame(width: 44, height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(topicTheme.tintColor.opacity(0.28), lineWidth: 0.5)
                        }

                    Image(systemName: topicTheme.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(topicTheme.tintColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(topicTheme.categoryLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.4)
                            .foregroundStyle(topicTheme.tintColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(topicTheme.badgeBackground)
                            .clipShape(Capsule())

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Neutral.n400)

                        Text(conversation.createdAt, style: .date)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.Neutral.n500)

                        Spacer(minLength: 4)
                    }

                    Text(displayTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .lineLimit(1)
                }

                if let onOpenVoiceAI {
                    Button {
                        onOpenVoiceAI()
                    } label: {
                        Image(systemName: "waveform.and.mic")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Primary.p700)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(AppTheme.Primary.p300, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mở Voice AI cho hội thoại này")
                }
            }

            // 2. TẦNG SUBTITLE (NGỮ CẢNH AI): ĐÓNG KHUNG NHẸ CÓ NHÃN RÕ RÀNG
            if !displaySubtitle.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(topicTheme.tintColor.opacity(0.75))
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.system(size: 10, weight: .bold))
                            Text("Ngữ cảnh tình huống")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.Neutral.n500)

                        Text(displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.Surface.cardMuted)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }

            Divider()
                .overlay(AppTheme.Surface.border.opacity(0.6))

            // 3. TẦNG PREVIEW TIN NHẮN GẦN NHẤT + SỐ LƯỢNG CÂU
            HStack(alignment: .center, spacing: 8) {
                if let preview = latestMessagePreview {
                    HStack(spacing: 4) {
                        Image(systemName: preview.isUser ? "person.fill" : "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text(preview.senderLabel)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(preview.isUser ? AppTheme.Primary.p700 : AppTheme.Semantic.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        preview.isUser
                        ? AppTheme.Primary.p50
                        : AppTheme.Semantic.success.opacity(0.12)
                    )
                    .clipShape(Capsule())

                    Text(preview.content)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.Neutral.n900.opacity(0.88))
                        .lineLimit(1)
                } else {
                    Image(systemName: "hand.wave.fill")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Accent.a600)

                    Text("Chưa có tin nhắn • Chạm để bắt đầu hội thoại")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(sortedMessages.count)")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppTheme.Neutral.n500)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.Surface.cardMuted)
                .clipShape(Capsule())
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
        }
        .shadow(
            color: AppTheme.Shadow.card,
            radius: 10,
            x: 0,
            y: 5
        )
    }
}


#Preview {
    ListConversationScreen()
        .modelContainer(for: [ConversationModel.self], inMemory: true)
}
