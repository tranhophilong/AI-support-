//
//  EnglishCorrectorWidget.swift
//  English Corrector Widget
//

import SwiftUI
import WidgetKit

private struct NotedAIEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetNoteSnapshot]
}

private struct NotedAIProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotedAIEntry {
        NotedAIEntry(
            date: Date(),
            notes: [
                WidgetNoteSnapshot(
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

    func getSnapshot(
        in context: Context,
        completion: @escaping (NotedAIEntry) -> Void
    ) {
        completion(NotedAIEntry(date: Date(), notes: WidgetNoteStore.load()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NotedAIEntry>) -> Void
    ) {
        let entry = NotedAIEntry(date: Date(), notes: WidgetNoteStore.load())
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: Date()
        ) ?? Date()

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct EnglishCorrectorWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: NotedAIEntry

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

                Text("Save AI corrections to review them here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            } else if family == .systemSmall {
                smallContent(entry.notes[0])
            } else {
                mediumContent(entry.notes.prefix(3).map { $0 })
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func smallContent(_ note: WidgetNoteSnapshot) -> some View {
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

    private func mediumContent(_ notes: [WidgetNoteSnapshot]) -> some View {
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

@main
struct EnglishCorrectorWidget: Widget {
    let kind = "EnglishCorrectorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: NotedAIProvider()
        ) { entry in
            EnglishCorrectorWidgetView(entry: entry)
        }
        .configurationDisplayName("Noted AI")
        .description("Review saved English corrections on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
