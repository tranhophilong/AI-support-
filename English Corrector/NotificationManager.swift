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

    func cancelNoteNotification(for note: SavedNoteModel) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [note.id.uuidString])
        print("DEBUG: Cancelled notification for note \(note.id.uuidString)")
    }

    // Handle foreground notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
