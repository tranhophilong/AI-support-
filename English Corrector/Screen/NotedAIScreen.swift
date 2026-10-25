//
//  NotedAIScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

struct NotedAIScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedNoteModel.createdAt, order: .reverse) private var notes: [SavedNoteModel]

    @AppStorage("notificationHour") private var notificationHour = 12
    @AppStorage("notificationMinute") private var notificationMinute = 0
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled = false

    @State private var selectedTime = Date()
    @State private var showTimePicker = false

    @State private var selectedNoteForTime: SavedNoteModel?
    @State private var showNoteTimePicker = false
    @State private var showWidgetStatus = false
    @State private var widgetStatusMessage = ""

    var body: some View {
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
                                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
                        VStack(alignment: .leading, spacing: 10) {

                            // Main Highlighted Text
                            if note.isExplanation {
                                explanationText(note.text, highlight: note.explanationNoted)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Neutral.n900)
                            } else {
                                diffText(original: note.originalText ?? "", revised: note.text)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Neutral.n900)
                            }

                            // Context / Correct Sentence
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

                                // PER-NOTE NOTIFICATION SETTING
                                Menu {
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
                                    print("DEBUG: Successfully deleted and saved note.")
                                } catch {
                                    print("DEBUG: Failed to delete note: \(error)")
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Surface.appBackground)
        }
        .navigationTitle("Noted AI")
        .background(AppTheme.Surface.appBackground)
        .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveAllNotesToWidget()
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .foregroundStyle(AppTheme.Primary.p500)
                .disabled(notes.isEmpty)
            }
        }
        .overlay(alignment: .bottom) {
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
        .sheet(isPresented: $showTimePicker) {
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
        .sheet(isPresented: $showNoteTimePicker) {
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
        .onAppear {
            print("DEBUG: Notes loaded: \(notes.count)")
            WidgetNoteStore.replace(
                with: notes.map { note in
                    widgetSnapshot(from: note)
                }
            )
            // Initialize selectedTime from stored values
            var components = DateComponents()
            components.hour = notificationHour
            components.minute = notificationMinute
            selectedTime = Calendar.current.date(from: components) ?? Date()

            Task {
                await NotificationManager.shared.requestAuthorization()
            }
        }
        .onDisappear {
            SpeechSynthesizerManager.shared.stop()
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

#Preview {
    NotedAIScreen()
        .modelContainer(for: [SavedNoteModel.self], inMemory: true)
}
