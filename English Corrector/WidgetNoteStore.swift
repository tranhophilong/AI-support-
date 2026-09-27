//
//  WidgetNoteStore.swift
//  English Corrector
//

import Foundation
import WidgetKit

struct WidgetNoteSnapshot: Codable, Identifiable {
    let id: UUID
    let text: String
    let originalContext: String
    let isExplanation: Bool
    let explanationNoted: String?
    let createdAt: Date
}

enum WidgetNoteStore {
    static let appGroupID = "group.philong.com.English-Corrector"
    private static let notesKey = "widget.notes"

    static func replace(with notes: [WidgetNoteSnapshot]) {
        let snapshots = notes
            .sorted { $0.createdAt > $1.createdAt }

        save(snapshots)
    }

    static func upsert(_ snapshot: WidgetNoteSnapshot) {
        var snapshots = load()

        snapshots.removeAll { $0.id == snapshot.id }
        snapshots.insert(snapshot, at: 0)

        save(snapshots)
    }

    static func remove(id: UUID) {
        var snapshots = load()
        snapshots.removeAll { $0.id == id }
        save(snapshots)
    }

    static func load() -> [WidgetNoteSnapshot] {
        guard let data = defaults.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([WidgetNoteSnapshot].self, from: data) else {
            return []
        }

        return notes
    }

    private static func save(_ notes: [WidgetNoteSnapshot]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        defaults.set(data, forKey: notesKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "Noted_AI_Wiget")
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
