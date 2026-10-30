//
//  RootTabView.swift
//  English Corrector
//

import SwiftUI
import UIKit

struct RootTabView: View {
    @AppStorage("appThemeMode") private var appThemeModeRawValue = AppThemeMode.light.rawValue
    @ObservedObject private var coordinator = StructureNavigationCoordinator.shared

    private var appThemeMode: AppThemeMode {
        AppThemeMode(rawValue: appThemeModeRawValue) ?? .light
    }

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            ListConversationScreen()
                .tabItem {
                    Label("Chat", image: "chat_nav_icon")
                }
                .tag(AppTab.chat)

            SituationAskScreen()
                .tabItem {
                    Label("Ask AI", image: "ask_nav_icon")
                }
                .tag(AppTab.askAI)

            SentenceStructureScreen()
                .tabItem {
                    Label("Structure", image: "structure_nav_icon")
                }
                .tag(AppTab.structure)

            NotedAIScreen()
                .tabItem {
                    Label("Notes", image: "note_nav_icon")
                }
                .tag(AppTab.notes)

            VocabularyNotesScreen()
                .tabItem {
                    Label("Vocabulary", image: "dictionary_nav_icon")
                }
                .tag(AppTab.vocabulary)
        }
        .tint(AppTheme.Primary.p500)
        .preferredColorScheme(appThemeMode.colorScheme)
        .scrollDismissesKeyboard(.immediately)
        .background(GlobalKeyboardDismissInstaller())
    }
}

/// Installs a non-blocking tap gesture on the key UIWindow so tapping anywhere outside a text input dismisses the keyboard automatically.
private struct GlobalKeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            KeyboardDismissManager.shared.installIfNeeded()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            KeyboardDismissManager.shared.installIfNeeded()
        }
    }
}

@MainActor
private final class KeyboardDismissManager: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissManager()

    private weak var installedWindow: UIWindow?

    func installIfNeeded() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return
        }

        guard installedWindow !== window else { return }
        installedWindow = window

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleWindowTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delaysTouchesBegan = false
        tapGesture.delaysTouchesEnded = false
        tapGesture.delegate = self
        window.addGestureRecognizer(tapGesture)
    }

    @objc private func handleWindowTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }

        // Do not dismiss keyboard if the user tapped inside a UITextField, UITextView, or keyboard view
        var current: UIView? = touchedView
        while let view = current {
            if view is UITextField || view is UITextView {
                return false
            }
            let className = NSStringFromClass(type(of: view))
            if className.contains("UIKB") || className.contains("Keyboard") || className.contains("TextField") {
                return false
            }
            current = view.superview
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

#Preview {
    RootTabView()
}
