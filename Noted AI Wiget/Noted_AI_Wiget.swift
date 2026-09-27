//
//  Noted_AI_Wiget.swift
//  Noted AI Wiget
//
//  Created by Long Tran on 20/9/26.
//

import WidgetKit
import SwiftUI

struct NotedWidgetNoteSnapshot: Codable, Identifiable {
    let id: UUID
    let text: String
    let originalContext: String
    let isExplanation: Bool
    let explanationNoted: String?
    let createdAt: Date
}

private enum WidgetNoteReader {
    private static let appGroupID = "group.philong.com.English-Corrector"
    private static let notesKey = "widget.notes"

    static func load() -> [NotedWidgetNoteSnapshot] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([NotedWidgetNoteSnapshot].self, from: data) else {
            return []
        }

        return notes
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            notes: [
                NotedWidgetNoteSnapshot(
                    id: UUID(),
                    text: "I went to school yesterday.",
                    originalContext: "Yesterday, I go to school.",
                    isExplanation: false,
                    explanationNoted: nil,
                    createdAt: Date()
                )
            ]
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: configuration,
            notes: WidgetNoteReader.load()
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = SimpleEntry(
            date: Date(),
            configuration: configuration,
            notes: WidgetNoteReader.load()
        )
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: Date()
        ) ?? Date()

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

//    func relevances() async -> WidgetRelevances<ConfigurationAppIntent> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let notes: [NotedWidgetNoteSnapshot]
}

struct Noted_AI_WigetEntryView : View {
    @Environment(\.widgetFamily) private var family

    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)

                Text("Noted AI")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if entry.notes.isEmpty {
                Spacer()

                Text("No saved notes")
                    .font(.headline)

                Text("Save corrections in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            } else if family == .systemSmall {
                smallContent(entry.notes[0])
            } else {
                mediumContent(entry.notes.prefix(3).map { $0 })
            }
        }
    }

    private func smallContent(_ note: NotedWidgetNoteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.isExplanation ? "Explanation" : "Sentence")
                .font(.caption2.bold())
                .foregroundStyle(.blue)

            Text(note.text)
                .font(.headline)
                .lineLimit(5)
                .minimumScaleFactor(0.75)

            if !note.originalContext.isEmpty {
                Text(note.originalContext)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func mediumContent(_ notes: [NotedWidgetNoteSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.isExplanation ? "Explanation" : "Sentence")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)

                    Text(note.text)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                if note.id != notes.last?.id {
                    Divider()
                }
            }
        }
    }
}

struct Noted_AI_Wiget: Widget {
    let kind: String = "Noted_AI_Wiget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            Noted_AI_WigetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Noted AI")
        .description("Review saved English corrections on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .systemSmall) {
    Noted_AI_Wiget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: .smiley,
        notes: [
            NotedWidgetNoteSnapshot(
                id: UUID(),
                text: "I went to school yesterday.",
                originalContext: "Yesterday, I go to school.",
                isExplanation: false,
                explanationNoted: nil,
                createdAt: Date()
            )
        ]
    )
}
