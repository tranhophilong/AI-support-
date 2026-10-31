import Foundation
import UserNotifications
import SwiftData

@MainActor
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("DEBUG: Notification authorization failed: \(error)")
        }
    }

    private func notificationUserInfo(for note: SavedNoteModel) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "noteID": note.id.uuidString,
            "noteText": note.text,
            "originalContext": note.originalContext,
            "originalText": note.originalText ?? ""
        ]
        if let conversationID = note.sourceConversationID {
            info["conversationID"] = conversationID.uuidString
        }
        if let messageID = note.sourceMessageID {
            info["messageID"] = messageID.uuidString
        }
        return info
    }

    func scheduleDailyNotification(at hour: Int, minute: Int, notes: [SavedNoteModel]) {
        // This is the global random note notification (optional to keep)
        let identifier = "daily_random_note"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard !notes.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Review your English notes"

        if let randomNote = notes.randomElement() {
            content.body = randomNote.text
            content.sound = .default
            content.userInfo = notificationUserInfo(for: randomNote)
        }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    func scheduleNoteNotification(for note: SavedNoteModel) {
        guard let hour = note.notificationHour, let minute = note.notificationMinute else {
            cancelNoteNotification(for: note)
            return
        }

        let identifier = note.id.uuidString
        let content = UNMutableNotificationContent()
        content.title = "Time to review your note"
        content.body = note.text
        content.sound = .default
        content.userInfo = notificationUserInfo(for: note)

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DEBUG: Error scheduling note notification: \(error)")
            } else {
                print("DEBUG: Scheduled note \(identifier) for \(hour):\(minute)")
            }
        }
    }

    func cancelDailyNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_random_note"])
    }

    func cancelNoteNotification(for note: SavedNoteModel) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [note.id.uuidString])
        print("DEBUG: Cancelled notification for note \(note.id.uuidString)")
    }

    // MARK: - AI Mistake Summary / Improvement Reminders

    func scheduleDailyImprovementNotification(
        at hour: Int,
        minute: Int,
        report: AIMistakeSummaryResponse,
        tapBehavior: String = "summary"
    ) {
        let identifier = "daily_improvement_reminder"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.sound = .default

        if let category = report.categories.randomElement() {
            let example = category.examples.first
            content.title = "🎯 Cần cải thiện: \(category.categoryName)"
            content.subtitle = category.quickRule
            if let example {
                content.body = "💡 \(category.whatToImprove)\n❌ \(example.wrongSentence) → ✅ \(example.correctSentence)"
            } else {
                content.body = "💡 \(category.whatToImprove)"
            }
            content.userInfo = [
                "notificationType": "improvement",
                "categoryName": category.categoryName,
                "tapBehavior": tapBehavior,
                "wrongSentence": example?.wrongSentence ?? "",
                "correctSentence": example?.correctSentence ?? ""
            ]
        } else {
            content.title = "🎯 Mục tiêu cải thiện tiếng Anh"
            content.body = report.topPriorityFocus
            content.userInfo = [
                "notificationType": "improvement",
                "categoryName": "",
                "tapBehavior": "summary",
                "wrongSentence": "",
                "correctSentence": ""
            ]
        }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelDailyImprovementNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_improvement_reminder"])
    }

    func scheduleCategoryImprovementNotification(
        category: AIMistakeCategoryItem,
        hour: Int,
        minute: Int,
        tapBehavior: String = "summary"
    ) {
        let identifier = categoryNotificationIdentifier(for: category.categoryName)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let example = category.examples.first
        let content = UNMutableNotificationContent()
        content.title = "🎯 Cần cải thiện: \(category.categoryName)"
        content.subtitle = category.quickRule
        if let example {
            content.body = "💡 \(category.whatToImprove)\n❌ \(example.wrongSentence) → ✅ \(example.correctSentence)"
        } else {
            content.body = "💡 \(category.whatToImprove)"
        }
        content.sound = .default
        content.userInfo = [
            "notificationType": "improvement",
            "categoryName": category.categoryName,
            "tapBehavior": tapBehavior,
            "wrongSentence": example?.wrongSentence ?? "",
            "correctSentence": example?.correctSentence ?? ""
        ]

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelCategoryImprovementNotification(categoryName: String) {
        let identifier = categoryNotificationIdentifier(for: categoryName)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func categoryNotificationIdentifier(for categoryName: String) -> String {
        let slug = categoryName.lowercased().replacingOccurrences(of: " ", with: "_")
        return "improvement_cat_\(slug)"
    }

    // Handle foreground notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle tap on notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let userInfo = request.content.userInfo

        if (userInfo["notificationType"] as? String) == "improvement" {
            let categoryName = (userInfo["categoryName"] as? String) ?? ""
            let tapBehavior = (userInfo["tapBehavior"] as? String) ?? "summary"
            let wrongSentence = (userInfo["wrongSentence"] as? String) ?? ""
            let correctSentence = (userInfo["correctSentence"] as? String) ?? ""

            Task { @MainActor in
                if tapBehavior == "conversation",
                   (!correctSentence.isEmpty || !wrongSentence.isEmpty) {
                    StructureNavigationCoordinator.shared.openConversationForNote(
                        noteText: correctSentence,
                        originalContext: correctSentence,
                        originalText: wrongSentence
                    )
                } else {
                    StructureNavigationCoordinator.shared.openMistakeSummary(
                        highlightedCategory: categoryName.isEmpty ? nil : categoryName
                    )
                }
            }
            completionHandler()
            return
        }

        let noteIDString = (userInfo["noteID"] as? String) ?? request.identifier
        let noteID = UUID(uuidString: noteIDString)
        let conversationID = (userInfo["conversationID"] as? String).flatMap(UUID.init(uuidString:))
        let messageID = (userInfo["messageID"] as? String).flatMap(UUID.init(uuidString:))
        let noteText = (userInfo["noteText"] as? String) ?? request.content.body
        let originalContext = (userInfo["originalContext"] as? String) ?? ""
        let originalText = (userInfo["originalText"] as? String) ?? ""

        Task { @MainActor in
            StructureNavigationCoordinator.shared.openConversationForNote(
                noteID: noteID,
                conversationID: conversationID,
                messageID: messageID,
                noteText: noteText,
                originalContext: originalContext,
                originalText: originalText
            )
        }

        completionHandler()
    }
}

extension Notification.Name {
    static let dismissNewsFeed = Notification.Name("dismissNewsFeed")
}
