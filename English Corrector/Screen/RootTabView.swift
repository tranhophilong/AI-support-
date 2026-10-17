//
//  RootTabView.swift
//  English Corrector
//

import SwiftUI

struct RootTabView: View {
    @AppStorage("appThemeMode") private var appThemeModeRawValue = AppThemeMode.light.rawValue

    private var appThemeMode: AppThemeMode {
        AppThemeMode(rawValue: appThemeModeRawValue) ?? .light
    }

    var body: some View {
        TabView {
            ListConversationScreen()
                .tabItem {
                    Label("Chat", image: "chat_nav_icon")
                }

            NotedAIScreen()
                .tabItem {
                    Label("Notes", image: "note_nav_icon")
                }

            VocabularyNotesScreen()
                .tabItem {
                    Label("Vocabulary", image: "dictionary_nav_icon")
                }
        }
        .tint(AppTheme.Primary.p500)
        .preferredColorScheme(appThemeMode.colorScheme)
    }
}

#Preview {
    RootTabView()
}
