//
//  NotedAIScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

enum NotedAISectionMode: String, CaseIterable, Identifiable {
    case savedNotes = "Ghi chú đã lưu"
    case mistakeSummary = "AI Tổng hợp lỗi sai"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .savedNotes:
            return "note.text"
        case .mistakeSummary:
            return "sparkles"
        }
    }
}

struct NotedAIScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedNoteModel.createdAt, order: .reverse) private var notes: [SavedNoteModel]
    @Query(sort: \ConversationModel.createdAt, order: .reverse) private var conversations: [ConversationModel]
    @Query(sort: \MistakeSummaryReportModel.updatedAt, order: .reverse) private var savedReports: [MistakeSummaryReportModel]

    @ObservedObject private var coordinator = StructureNavigationCoordinator.shared

    @AppStorage("notificationHour") private var notificationHour = 12
    @AppStorage("notificationMinute") private var notificationMinute = 0
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled = false

    @AppStorage("improvementNotificationHour") private var improvementNotificationHour = 20
    @AppStorage("improvementNotificationMinute") private var improvementNotificationMinute = 0
    @AppStorage("isImprovementNotificationEnabled") private var isImprovementNotificationEnabled = false
    @AppStorage("improvementNotificationTapBehavior") private var improvementNotificationTapBehavior = "summary"
    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var sectionMode: NotedAISectionMode = .savedNotes

    @State private var selectedTime = Date()
    @State private var showTimePicker = false

    @State private var selectedNoteForTime: SavedNoteModel?
    @State private var showNoteTimePicker = false

    @State private var showImprovementTimePicker = false
    @State private var selectedCategoryForReminder: AIMistakeCategoryItem?
    @State private var showCategoryReminderPicker = false

    @State private var isAnalyzingMistakes = false
    @State private var analysisErrorMessage: String?
    @State private var highlightedCategoryName: String?

    @State private var showWidgetStatus = false
    @State private var widgetStatusMessage = ""

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var activeReportRecord: MistakeSummaryReportModel? {
        savedReports.first
    }

    private var activeReport: AIMistakeSummaryResponse? {
        activeReportRecord?.decodedReport
    }

    private var collectedSamples: [UserMistakeSample] {
        var samples: [UserMistakeSample] = []

        // 1. Collect from conversation corrections
        for conv in conversations {
            let sorted = conv.messages.sorted(by: { $0.createdAt < $1.createdAt })
            for (idx, msg) in sorted.enumerated() where !msg.isUser {
                let fixed = (msg.fixed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let explanations = (msg.explanations ?? []).joined(separator: "; ")
                guard !fixed.isEmpty || !explanations.isEmpty else { continue }

                var userOriginal = ""
                if idx > 0 {
                    for prevIdx in stride(from: idx - 1, through: 0, by: -1) {
                        if sorted[prevIdx].isUser {
                            userOriginal = sorted[prevIdx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                            break
                        }
                    }
                }

                let isDifferent = !userOriginal.isEmpty &&
                    userOriginal.caseInsensitiveCompare(fixed) != .orderedSame

                if isDifferent || !explanations.isEmpty {
                    samples.append(
                        UserMistakeSample(
                            source: "Chat: \(conv.title.isEmpty ? "Daily English" : conv.title)",
                            userOriginal: userOriginal,
                            correctedSentence: !fixed.isEmpty ? fixed : (msg.natural ?? ""),
                            explanation: explanations
                        )
                    )
                }
            }
        }

        // 2. Collect from saved notes
        for note in notes {
            let original = (note.originalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = note.isExplanation
                ? note.originalContext.trimmingCharacters(in: .whitespacesAndNewlines)
                : note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let explanation = note.isExplanation
                ? note.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : (note.explanationNoted ?? "")

            guard !corrected.isEmpty || !explanation.isEmpty else { continue }
            samples.append(
                UserMistakeSample(
                    source: "Saved Note",
                    userOriginal: original,
                    correctedSentence: corrected,
                    explanation: explanation
                )
            )
        }

        return Array(samples.prefix(40))
    }

    private var totalCorrectionCountInChat: Int {
        conversations.reduce(0) { acc, conv in
            acc + conv.messages.filter { !$0.isUser && ($0.fixed != nil || !($0.explanations ?? []).isEmpty) }.count
        }
    }

    private var hasNewDataSinceLastReport: Bool {
        guard let record = activeReportRecord else { return !collectedSamples.isEmpty }
        return record.analyzedCorrectionCount != totalCorrectionCountInChat ||
            record.analyzedNoteCount != notes.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionSwitcherBar

                if sectionMode == .savedNotes {
                    savedNotesContentView
                } else {
                    mistakeSummaryContentView
                }
            }
            .navigationTitle("Noted AI")
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if sectionMode == .savedNotes {
                        Button {
                            saveAllNotesToWidget()
                        } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                        .foregroundStyle(AppTheme.Primary.p500)
                        .disabled(notes.isEmpty)
                    } else {
                        Button {
                            analyzeUserMistakes()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .foregroundStyle(AppTheme.Primary.p500)
                        .disabled(isAnalyzingMistakes || collectedSamples.isEmpty)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                statusToastOverlay
            }
            .sheet(isPresented: $showTimePicker) {
                dailyNoteTimePickerSheet
            }
            .sheet(isPresented: $showNoteTimePicker) {
                perNoteTimePickerSheet
            }
            .sheet(isPresented: $showImprovementTimePicker) {
                improvementDailyTimePickerSheet
            }
            .sheet(isPresented: $showCategoryReminderPicker) {
                categoryReminderTimePickerSheet
            }
            .onAppear {
                print("DEBUG: Notes loaded: \(notes.count)")
                backfillNoteConversationLinksIfNeeded()
                WidgetNoteStore.replace(
                    with: notes.map { note in
                        widgetSnapshot(from: note)
                    }
                )
                var components = DateComponents()
                components.hour = notificationHour
                components.minute = notificationMinute
                selectedTime = Calendar.current.date(from: components) ?? Date()

                handlePendingMistakeSummaryNavigation()

                Task {
                    await NotificationManager.shared.requestAuthorization()
                }
            }
            .onChange(of: coordinator.forceOpenMistakeSummarySection) { _, _ in
                handlePendingMistakeSummaryNavigation()
            }
            .onChange(of: coordinator.pendingMistakeCategoryToHighlight) { _, _ in
                handlePendingMistakeSummaryNavigation()
            }
            .onChange(of: sectionMode) { _, newMode in
                if newMode == .mistakeSummary,
                   activeReport == nil,
                   !isAnalyzingMistakes,
                   !collectedSamples.isEmpty {
                    analyzeUserMistakes()
                }
            }
            .onDisappear {
                SpeechSynthesizerManager.shared.stop()
            }
        }
    }

    // MARK: - Section Switcher

    private var sectionSwitcherBar: some View {
        HStack(spacing: 8) {
            ForEach(NotedAISectionMode.allCases) { mode in
                let isSelected = (sectionMode == mode)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sectionMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.caption.weight(.bold))
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? AppTheme.Primary.p500 : AppTheme.Surface.card)
                    .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
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
        .background(AppTheme.Surface.appBackground)
    }

    // MARK: - Saved Notes Content

    private var savedNotesContentView: some View {
        VStack(spacing: 0) {
            // Notification Setting Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Daily Review", systemImage: "bell.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("Get a random note delivered daily")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }

                    Spacer()

                    Toggle("", isOn: $isNotificationEnabled)
                        .labelsHidden()
                        .onChange(of: isNotificationEnabled) { _, newValue in
                            if newValue {
                                updateNotification()
                            } else {
                                NotificationManager.shared.cancelDailyNotification()
                            }
                        }
                }

                if isNotificationEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Presets")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Neutral.n400)
                            .textCase(.uppercase)

                        HStack(spacing: 12) {
                            presetButton(label: "12 AM", hour: 0, minute: 0)
                            presetButton(label: "12 PM", hour: 12, minute: 0)
                            presetButton(label: "8 PM", hour: 20, minute: 0)

                            Button {
                                showTimePicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text("Custom")
                                }
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.Surface.cardMuted)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .clipShape(Capsule())
                            }
                        }

                        HStack {
                            Text("Scheduled for:")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n500)

                            Text(formatTime(hour: notificationHour, minute: notificationMinute))
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Primary.p500)
                        }
                        .padding(.top, 4)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding()
            .background(AppTheme.Primary.p50)
            .animation(.spring(), value: isNotificationEnabled)

            List {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No saved notes",
                        systemImage: "note.text",
                        description: Text("Save interesting AI explanations to see them here.")
                    )
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .listRowBackground(AppTheme.Surface.appBackground)
                } else {
                    ForEach(notes) { note in
                        savedNoteRow(note)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Surface.appBackground)
        }
    }

    @ViewBuilder
    private func savedNoteRow(_ note: SavedNoteModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if note.isExplanation {
                explanationText(note.text, highlight: note.explanationNoted)
                    .font(.body)
                    .foregroundStyle(AppTheme.Neutral.n900)
            } else {
                diffText(original: note.originalText ?? "", revised: note.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.Neutral.n900)
            }

            if !note.originalContext.isEmpty && note.isExplanation {
                HStack(spacing: 8) {
                    Text(note.originalContext)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SpeakButton(
                        text: note.originalContext,
                        font: .caption,
                        activeColor: AppTheme.Primary.p500
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.Surface.cardMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Text(note.isExplanation ? "Explanation" : "Sentence")
                    .font(.caption2.bold())
                    .foregroundStyle(note.isExplanation ? AppTheme.Accent.a600 : AppTheme.Secondary.s600)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(note.isExplanation ? AppTheme.Accent.a100 : AppTheme.Secondary.s100)
                    .clipShape(Capsule())

                SpeakButton(
                    text: note.text,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Primary.p500,
                    showBackground: true
                )

                Menu {
                    if hasMatchingConversation(for: note) {
                        Button {
                            openConversation(for: note)
                        } label: {
                            Label("Open Saved Conversation", systemImage: "bubble.left.and.bubble.right")
                        }

                        Divider()
                    }

                    Button {
                        saveNoteToWidget(note)
                    } label: {
                        Label("Save to Widget", systemImage: "square.grid.2x2")
                    }

                    Divider()

                    Button("12:00 AM") { setNoteTime(note: note, hour: 0, minute: 0) }
                    Button("08:00 PM") { setNoteTime(note: note, hour: 20, minute: 0) }
                    Button("Custom Time...") {
                        selectedNoteForTime = note
                        showNoteTimePicker = true
                    }
                    if note.notificationHour != nil {
                        Divider()
                        Button("Remove Reminder", role: .destructive) {
                            removeNoteNotification(note: note)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: note.notificationHour != nil ? "bell.badge.fill" : "bell")
                        if let h = note.notificationHour, let m = note.notificationMinute {
                            Text(formatTime(hour: h, minute: m))
                                .font(.caption2.bold())
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(note.notificationHour != nil ? AppTheme.Semantic.warning : AppTheme.Neutral.n500)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(note.notificationHour != nil ? AppTheme.Semantic.warning.opacity(0.12) : AppTheme.Surface.cardMuted)
                    .clipShape(Capsule())
                }

                if hasMatchingConversation(for: note) {
                    Button {
                        openConversation(for: note)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.up.right")
                            Text("Hội thoại")
                                .font(.caption2.bold())
                        }
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(note.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n400)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(AppTheme.Surface.card)
        .swipeActions {
            Button {
                saveNoteToWidget(note)
            } label: {
                Label("Widget", systemImage: "square.grid.2x2")
            }
            .tint(AppTheme.Primary.p500)

            Button(role: .destructive) {
                context.delete(note)
                do {
                    try context.save()
                    WidgetNoteStore.remove(id: note.id)
                } catch {
                    print("DEBUG: Failed to delete note: \(error)")
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Mistake Summary Content

    private var mistakeSummaryContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    improvementReminderSettingCard

                    if isAnalyzingMistakes {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(AppTheme.Primary.p500)
                                .scaleEffect(1.2)
                            Text("AI đang phân tích lịch sử lỗi sai và tổng hợp điểm cần cải thiện...")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                        }
                    } else if let error = analysisErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Không thể tạo bản tổng hợp", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Semantic.error)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n700)
                            Button {
                                analyzeUserMistakes()
                            } label: {
                                Label("Thử lại", systemImage: "arrow.clockwise")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.Primary.p500)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if let report = activeReport {
                        MistakeOverallSummaryCard(
                            report: report,
                            updatedAt: activeReportRecord?.updatedAt,
                            hasNewData: hasNewDataSinceLastReport,
                            isAnalyzing: isAnalyzingMistakes,
                            onRefresh: {
                                analyzeUserMistakes()
                            }
                        )

                        Text("Phân nhóm lỗi sai & Hướng cải thiện")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .padding(.top, 4)

                        ForEach(report.categories) { category in
                            let reminder = activeReportRecord?.categoryReminders[category.categoryName]
                            let isHighlighted = (highlightedCategoryName == category.categoryName)

                            MistakeCategoryCardView(
                                category: category,
                                reminder: reminder,
                                isHighlighted: isHighlighted,
                                formattedReminderTime: reminder.map { formatTime(hour: $0.hour, minute: $0.minute) },
                                canOpenConversation: { example in
                                    canResolveExampleConversation(example)
                                },
                                onOpenConversation: { example in
                                    openExampleConversation(example)
                                },
                                onSetPresetReminder: { hour, minute in
                                    setCategoryReminder(category: category, hour: hour, minute: minute)
                                },
                                onOpenCustomReminder: {
                                    selectedCategoryForReminder = category
                                    var comps = DateComponents()
                                    comps.hour = reminder?.hour ?? 20
                                    comps.minute = reminder?.minute ?? 0
                                    selectedTime = Calendar.current.date(from: comps) ?? Date()
                                    showCategoryReminderPicker = true
                                },
                                onRemoveReminder: {
                                    removeCategoryReminder(category: category)
                                }
                            )
                            .id(category.categoryName)
                        }
                    } else if !isAnalyzingMistakes {
                        emptyMistakeSummaryState
                    }
                }
                .padding(16)
            }
            .onChange(of: highlightedCategoryName) { _, newTarget in
                guard let newTarget, !newTarget.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newTarget, anchor: .center)
                    }
                }
            }
        }
    }

    private var improvementReminderSettingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nhắc nhở điều cần cải thiện", systemImage: "bell.badge.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Neutral.n900)

                    Text("Nhận thông báo hằng ngày về điểm yếu ngữ pháp/từ vựng cần khắc phục")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }

                Spacer()

                Toggle("", isOn: $isImprovementNotificationEnabled)
                    .labelsHidden()
                    .onChange(of: isImprovementNotificationEnabled) { _, enabled in
                        if enabled {
                            scheduleDailyImprovementReminderIfPossible()
                        } else {
                            NotificationManager.shared.cancelDailyImprovementNotification()
                        }
                    }
            }

            if isImprovementNotificationEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Khung giờ nhắc nhở")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Neutral.n400)
                        .textCase(.uppercase)

                    HStack(spacing: 10) {
                        improvementPresetButton(label: "8 AM", hour: 8, minute: 0)
                        improvementPresetButton(label: "12 PM", hour: 12, minute: 0)
                        improvementPresetButton(label: "8 PM", hour: 20, minute: 0)

                        Button {
                            var comps = DateComponents()
                            comps.hour = improvementNotificationHour
                            comps.minute = improvementNotificationMinute
                            selectedTime = Calendar.current.date(from: comps) ?? Date()
                            showImprovementTimePicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text("Custom")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.Surface.card)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .clipShape(Capsule())
                        }
                    }

                    HStack {
                        Text("Giờ hẹn hằng ngày:")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)

                        Text(formatTime(hour: improvementNotificationHour, minute: improvementNotificationMinute))
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Accent.a600)

                        Spacer()
                    }

                    Divider()
                        .overlay(AppTheme.Surface.border)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Khi bấm vào thông báo nhắc nhở:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n700)

                        HStack(spacing: 8) {
                            tapBehaviorOptionButton(
                                title: "Mở mục cần cải thiện",
                                value: "summary",
                                icon: "list.Star"
                            )
                            tapBehaviorOptionButton(
                                title: "Mở hội thoại gốc",
                                value: "conversation",
                                icon: "bubble.left.and.bubble.right"
                            )
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(AppTheme.Accent.a50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Accent.a500.opacity(0.45), lineWidth: 1.2)
        }
    }

    private func tapBehaviorOptionButton(title: String, value: String, icon: String) -> some View {
        let isSelected = (improvementNotificationTapBehavior == value)
        return Button {
            improvementNotificationTapBehavior = value
            scheduleDailyImprovementReminderIfPossible()
            rescheduleAllCategoryReminders()
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? AppTheme.Accent.a600 : AppTheme.Surface.card)
                .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var emptyMistakeSummaryState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Primary.p500)
                .frame(width: 76, height: 76)
                .background(AppTheme.Primary.p50)
                .clipShape(Circle())

            Text(collectedSamples.isEmpty ? "Chưa có dữ liệu lỗi sai" : "Tổng hợp lỗi sai với AI")
                .font(.headline)
                .foregroundStyle(AppTheme.Neutral.n900)

            Text(
                collectedSamples.isEmpty
                ? "Hãy trò chuyện với AI trong tab Chat hoặc lưu các câu sửa lỗi vào Noted AI để AI phân tích những điểm bạn cần cải thiện."
                : "Đã tìm thấy \(collectedSamples.count) mẫu câu sửa lỗi từ hội thoại và ghi chú của bạn. Bấm nút bên dưới để AI tổng hợp các lỗi sai thường gặp nhất."
            )
            .font(.subheadline)
            .foregroundStyle(AppTheme.Neutral.n500)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)

            if !collectedSamples.isEmpty {
                Button {
                    analyzeUserMistakes()
                } label: {
                    Label("Phân tích lỗi sai ngay", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppTheme.Primary.p500)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
        }
    }

    // MARK: - Sheets & Overlays

    @ViewBuilder
    private var statusToastOverlay: some View {
        if showWidgetStatus {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Semantic.success)

                Text(widgetStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(AppTheme.Neutral.n900.opacity(0.88))
            .clipShape(Capsule())
            .shadow(color: AppTheme.Shadow.card, radius: 8, x: 0, y: 4)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var dailyNoteTimePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Select Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()

                Text("Choose a custom time for your daily review.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Custom Time")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
                        notificationHour = components.hour ?? 12
                        notificationMinute = components.minute ?? 0
                        updateNotification()
                        showTimePicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }

    private var perNoteTimePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Reminder Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()

                Text("Set a specific time to review this note every day.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding()

                Spacer()
            }
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNoteTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let note = selectedNoteForTime {
                            let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
                            setNoteTime(note: note, hour: components.hour ?? 12, minute: components.minute ?? 0)
                        }
                        showNoteTimePicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }

    private var improvementDailyTimePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Select Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()

                Text("Chọn giờ nhận thông báo nhắc nhở điểm cần cải thiện mỗi ngày.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Giờ nhắc cải thiện")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showImprovementTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
                        improvementNotificationHour = comps.hour ?? 20
                        improvementNotificationMinute = comps.minute ?? 0
                        scheduleDailyImprovementReminderIfPossible()
                        showImprovementTimePicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }

    private var categoryReminderTimePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Reminder Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()

                if let category = selectedCategoryForReminder {
                    Text("Đặt lịch nhắc nhở riêng mỗi ngày cho nhóm lỗi: \"\(category.categoryName)\"")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Nhắc nhở theo nhóm lỗi")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showCategoryReminderPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        if let category = selectedCategoryForReminder {
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
                            setCategoryReminder(
                                category: category,
                                hour: comps.hour ?? 20,
                                minute: comps.minute ?? 0
                            )
                        }
                        showCategoryReminderPicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }

    private func hasMatchingConversation(for note: SavedNoteModel) -> Bool {
        NoteConversationResolver.resolve(
            conversations: conversations,
            conversationID: note.sourceConversationID,
            messageID: note.sourceMessageID,
            noteText: note.text,
            originalContext: note.originalContext,
            originalText: note.originalText ?? ""
        ) != nil
    }

    private func openConversation(for note: SavedNoteModel) {
        StructureNavigationCoordinator.shared.openConversationForNote(
            noteID: note.id,
            conversationID: note.sourceConversationID,
            messageID: note.sourceMessageID,
            noteText: note.text,
            originalContext: note.originalContext,
            originalText: note.originalText ?? ""
        )
    }

    private func backfillNoteConversationLinksIfNeeded() {
        guard !conversations.isEmpty, !notes.isEmpty else { return }
        var hasChanges = false

        for note in notes where note.sourceConversationID == nil || note.sourceMessageID == nil {
            if let resolved = NoteConversationResolver.resolve(
                conversations: conversations,
                conversationID: note.sourceConversationID,
                messageID: note.sourceMessageID,
                noteText: note.text,
                originalContext: note.originalContext,
                originalText: note.originalText ?? ""
            ) {
                note.sourceConversationID = resolved.conversation.id
                note.sourceMessageID = resolved.messageID
                note.sourceConversationTitle = resolved.conversation.title
                hasChanges = true

                if note.notificationHour != nil, note.notificationMinute != nil {
                    NotificationManager.shared.scheduleNoteNotification(for: note)
                }
            }
        }

        if hasChanges {
            try? context.save()
            if isNotificationEnabled {
                updateNotification()
            }
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func setPresetTime(hour: Int, minute: Int) {
        notificationHour = hour
        notificationMinute = minute
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        selectedTime = Calendar.current.date(from: components) ?? Date()
        updateNotification()
        showTimePicker = false
    }

    private func updateNotification() {
        NotificationManager.shared.scheduleDailyNotification(
            at: notificationHour,
            minute: notificationMinute,
            notes: notes
        )
    }

    private func saveNoteToWidget(_ note: SavedNoteModel) {
        WidgetNoteStore.upsert(widgetSnapshot(from: note))
        showWidgetMessage("Saved to Widget")
    }

    private func saveAllNotesToWidget() {
        WidgetNoteStore.replace(
            with: notes.map { note in
                widgetSnapshot(from: note)
            }
        )
        showWidgetMessage("Widget updated")
    }

    private func widgetSnapshot(from note: SavedNoteModel) -> WidgetNoteSnapshot {
        WidgetNoteSnapshot(
            id: note.id,
            text: note.text,
            originalContext: note.originalContext,
            isExplanation: note.isExplanation,
            explanationNoted: note.explanationNoted,
            createdAt: note.createdAt
        )
    }

    private func showWidgetMessage(_ message: String) {
        withAnimation {
            widgetStatusMessage = message
            showWidgetStatus = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showWidgetStatus = false
            }
        }
    }

    private func setNoteTime(note: SavedNoteModel, hour: Int, minute: Int) {
        note.notificationHour = hour
        note.notificationMinute = minute
        NotificationManager.shared.scheduleNoteNotification(for: note)
        try? context.save()
    }

    private func removeNoteNotification(note: SavedNoteModel) {
        note.notificationHour = nil
        note.notificationMinute = nil
        NotificationManager.shared.cancelNoteNotification(for: note)
        try? context.save()
    }

    private func presetButton(label: String, hour: Int, minute: Int) -> some View {
        let isSelected = notificationHour == hour && notificationMinute == minute
        return Button {
            setPresetTime(hour: hour, minute: minute)
        } label: {
            Text(label)
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                .clipShape(Capsule())
        }
    }

    private func improvementPresetButton(label: String, hour: Int, minute: Int) -> some View {
        let isSelected = improvementNotificationHour == hour && improvementNotificationMinute == minute
        return Button {
            improvementNotificationHour = hour
            improvementNotificationMinute = minute
            scheduleDailyImprovementReminderIfPossible()
            showWidgetMessage("Đã hẹn nhắc nhở lúc \(formatTime(hour: hour, minute: minute))")
        } label: {
            Text(label)
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.Accent.a600 : AppTheme.Surface.card)
                .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                .clipShape(Capsule())
        }
    }

    // MARK: - AI Mistake Summary Actions

    private func handlePendingMistakeSummaryNavigation() {
        if coordinator.forceOpenMistakeSummarySection {
            coordinator.forceOpenMistakeSummarySection = false
            sectionMode = .mistakeSummary
        }
        if let targetCat = coordinator.pendingMistakeCategoryToHighlight {
            coordinator.pendingMistakeCategoryToHighlight = nil
            sectionMode = .mistakeSummary
            highlightedCategoryName = targetCat
        }
    }

    @MainActor
    private func analyzeUserMistakes() {
        let samples = collectedSamples
        guard !samples.isEmpty, !isAnalyzingMistakes else { return }

        isAnalyzingMistakes = true
        analysisErrorMessage = nil
        let provider = selectedAIModel.makeProvider()
        let correctionCountSnapshot = totalCorrectionCountInChat
        let noteCountSnapshot = notes.count

        Task {
            do {
                let aiService = AIService(provider: provider)
                let response = try await aiService.summarizeUserMistakes(samples: samples)

                await MainActor.run {
                    if let existing = activeReportRecord {
                        existing.decodedReport = response
                        existing.analyzedCorrectionCount = correctionCountSnapshot
                        existing.analyzedNoteCount = noteCountSnapshot
                        existing.updatedAt = Date()
                    } else {
                        let newRecord = MistakeSummaryReportModel(
                            analyzedCorrectionCount: correctionCountSnapshot,
                            analyzedNoteCount: noteCountSnapshot,
                            report: response
                        )
                        context.insert(newRecord)
                    }

                    try? context.save()
                    isAnalyzingMistakes = false
                    scheduleDailyImprovementReminderIfPossible()
                    rescheduleAllCategoryReminders()
                    showWidgetMessage("Đã cập nhật bản tổng hợp lỗi sai AI")
                }
            } catch {
                await MainActor.run {
                    isAnalyzingMistakes = false
                    analysisErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func scheduleDailyImprovementReminderIfPossible() {
        guard isImprovementNotificationEnabled, let report = activeReport else { return }
        NotificationManager.shared.scheduleDailyImprovementNotification(
            at: improvementNotificationHour,
            minute: improvementNotificationMinute,
            report: report,
            tapBehavior: improvementNotificationTapBehavior
        )
    }

    private func setCategoryReminder(category: AIMistakeCategoryItem, hour: Int, minute: Int) {
        guard let record = activeReportRecord else { return }
        var map = record.categoryReminders
        map[category.categoryName] = MistakeCategoryReminderConfig(
            categoryName: category.categoryName,
            hour: hour,
            minute: minute
        )
        record.categoryReminders = map
        try? context.save()

        NotificationManager.shared.scheduleCategoryImprovementNotification(
            category: category,
            hour: hour,
            minute: minute,
            tapBehavior: improvementNotificationTapBehavior
        )
        showWidgetMessage("Đã hẹn giờ nhắc nhở nhóm lỗi")
    }

    private func removeCategoryReminder(category: AIMistakeCategoryItem) {
        guard let record = activeReportRecord else { return }
        var map = record.categoryReminders
        map.removeValue(forKey: category.categoryName)
        record.categoryReminders = map
        try? context.save()

        NotificationManager.shared.cancelCategoryImprovementNotification(
            categoryName: category.categoryName
        )
        showWidgetMessage("Đã tắt nhắc nhở nhóm lỗi")
    }

    private func rescheduleAllCategoryReminders() {
        guard let record = activeReportRecord,
              let report = record.decodedReport else { return }
        let reminders = record.categoryReminders
        for category in report.categories {
            if let cfg = reminders[category.categoryName] {
                NotificationManager.shared.scheduleCategoryImprovementNotification(
                    category: category,
                    hour: cfg.hour,
                    minute: cfg.minute,
                    tapBehavior: improvementNotificationTapBehavior
                )
            }
        }
    }

    private func canResolveExampleConversation(_ example: AIMistakeExampleItem) -> Bool {
        NoteConversationResolver.resolve(
            conversations: conversations,
            conversationID: nil,
            messageID: nil,
            noteText: example.correctSentence,
            originalContext: example.correctSentence,
            originalText: example.wrongSentence
        ) != nil
    }

    private func openExampleConversation(_ example: AIMistakeExampleItem) {
        StructureNavigationCoordinator.shared.openConversationForNote(
            noteID: nil,
            conversationID: nil,
            messageID: nil,
            noteText: example.correctSentence,
            originalContext: example.correctSentence,
            originalText: example.wrongSentence
        )
    }

    // MARK: - Highlight Helpers

    private func diffText(original: String, revised: String) -> Text {
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
}

// MARK: - Mistake Overall Summary Card

private struct MistakeOverallSummaryCard: View {
    let report: AIMistakeSummaryResponse
    let updatedAt: Date?
    let hasNewData: Bool
    let isAnalyzing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Đánh giá tổng quan từ AI", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Primary.p700)

                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(hasNewData ? "Cập nhật mới" : "Làm mới")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasNewData ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                    .foregroundStyle(hasNewData ? .white : AppTheme.Primary.p500)
                    .clipShape(Capsule())
                }
                .disabled(isAnalyzing)
            }

            // Priority Focus Box
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text("Trọng tâm cần cải thiện ngay")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Semantic.warning)
                        .textCase(.uppercase)
                }

                Text(report.topPriorityFocus)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n900)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Semantic.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(report.overallAssessment)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n700)
                .fixedSize(horizontal: false, vertical: true)

            if !report.actionableGoals.isEmpty {
                Divider()
                    .overlay(AppTheme.Surface.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Thói quen luyện tập gợi ý hằng ngày")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    ForEach(Array(report.actionableGoals.enumerated()), id: \.offset) { _, goal in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Semantic.success)
                                .padding(.top, 2)

                            Text(goal)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n900)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let updatedAt {
                HStack {
                    if hasNewData {
                        Text("Có thêm câu sửa lỗi mới chưa được tổng hợp")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Primary.p500)
                    }
                    Spacer()
                    Text("Cập nhật: \(updatedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
        }
    }
}

// MARK: - Mistake Category Card View

private struct MistakeCategoryCardView: View {
    let category: AIMistakeCategoryItem
    let reminder: MistakeCategoryReminderConfig?
    let isHighlighted: Bool
    let formattedReminderTime: String?
    let canOpenConversation: (AIMistakeExampleItem) -> Bool
    let onOpenConversation: (AIMistakeExampleItem) -> Void
    let onSetPresetReminder: (Int, Int) -> Void
    let onOpenCustomReminder: () -> Void
    let onRemoveReminder: () -> Void

    private var severityColor: Color {
        let lower = category.severity.lowercased()
        if lower.contains("cao") || lower.contains("high") {
            return AppTheme.Semantic.error
        } else if lower.contains("trung") || lower.contains("medium") {
            return AppTheme.Semantic.warning
        } else {
            return AppTheme.Primary.p500
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.categoryName)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)

                    HStack(spacing: 8) {
                        Text("Mức độ: \(category.severity)")
                            .font(.caption2.bold())
                            .foregroundStyle(severityColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(severityColor.opacity(0.12))
                            .clipShape(Capsule())

                        if category.frequencyCount > 0 {
                            Text("\(category.frequencyCount) lần gặp")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.Surface.cardMuted)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Per-category reminder menu
                Menu {
                    Button("08:00 AM") { onSetPresetReminder(8, 0) }
                    Button("12:00 PM") { onSetPresetReminder(12, 0) }
                    Button("08:00 PM") { onSetPresetReminder(20, 0) }
                    Button("Chọn giờ khác...") { onOpenCustomReminder() }
                    if reminder != nil {
                        Divider()
                        Button("Tắt nhắc nhở nhóm này", role: .destructive) {
                            onRemoveReminder()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: reminder != nil ? "bell.badge.fill" : "bell")
                        if let formattedReminderTime {
                            Text(formattedReminderTime)
                                .font(.caption2.bold())
                        } else {
                            Text("Nhắc tôi")
                                .font(.caption2.weight(.medium))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(reminder != nil ? AppTheme.Semantic.warning : AppTheme.Neutral.n500)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(reminder != nil ? AppTheme.Semantic.warning.opacity(0.14) : AppTheme.Surface.cardMuted)
                    .clipShape(Capsule())
                }
            }

            // What to improve
            VStack(alignment: .leading, spacing: 4) {
                Text("Cần cải thiện điều gì:")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Accent.a600)

                Text(category.whatToImprove)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Quick Rule
            if !category.quickRule.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Primary.p500)

                    Text(category.quickRule)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Primary.p700)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(AppTheme.Primary.p50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Examples
            if !category.examples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ví dụ lỗi sai của bạn:")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Neutral.n500)

                    ForEach(category.examples) { example in
                        MistakeExampleRowView(
                            example: example,
                            canOpenConversation: canOpenConversation(example),
                            onOpenConversation: {
                                onOpenConversation(example)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                    lineWidth: isHighlighted ? 2.2 : 1.2
                )
        }
        .shadow(
            color: isHighlighted ? AppTheme.Accent.a500.opacity(0.25) : .clear,
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

private struct MistakeExampleRowView: View {
    let example: AIMistakeExampleItem
    let canOpenConversation: Bool
    let onOpenConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !example.wrongSentence.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Semantic.error)
                        .padding(.top, 2)

                    Text(example.wrongSentence)
                        .font(.caption)
                        .strikethrough(true, color: AppTheme.Semantic.error.opacity(0.7))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Semantic.success)
                    .padding(.top, 2)

                Text(example.correctSentence)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SpeakButton(
                    text: example.correctSentence,
                    font: .caption,
                    activeColor: AppTheme.Primary.p500
                )
            }

            HStack(alignment: .center, spacing: 8) {
                if !example.explanation.isEmpty {
                    Text(example.explanation)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }

                if canOpenConversation {
                    Button(action: onOpenConversation) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.up.right")
                            Text("Hội thoại gốc")
                                .font(.caption2.bold())
                        }
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(AppTheme.Surface.cardMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NotedAIScreen()
        .modelContainer(for: [SavedNoteModel.self, ConversationModel.self, MistakeSummaryReportModel.self], inMemory: true)
}
