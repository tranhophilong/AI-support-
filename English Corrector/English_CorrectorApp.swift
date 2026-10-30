//
//  English_CorrectorApp.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftUI
import SwiftData

@main
struct English_CorrectorApp: App {

    let container: ModelContainer

    init() {
        _ = NotificationManager.shared

        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            container = try ModelContainer(
                for: ConversationModel.self,
                MessageModel.self,
                SavedNoteModel.self,
                VocabularyNoteModel.self,
                SituationAskSessionModel.self,
                SituationAskMessageModel.self,
                SentenceStructureAnalysisModel.self,
                MistakeSummaryReportModel.self,
                configurations: config
            )

            // Print database location for debugging
            if let url = container.configurations.first?.url {
                print("DEBUG: Database URL: \(url.path)")
            }
        } catch {
            print("SwiftData Error:", error)
            dump(error)
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
