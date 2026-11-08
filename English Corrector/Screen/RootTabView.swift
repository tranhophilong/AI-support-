//
//  RootTabView.swift
//  English Corrector
//

import SwiftUI
import UIKit

struct RootTabView: View {
    @AppStorage("appThemeMode") private var appThemeModeRawValue = AppThemeMode.light.rawValue
    @ObservedObject private var coordinator = StructureNavigationCoordinator.shared
    @State private var isKeyboardVisible = false

    private var appThemeMode: AppThemeMode {
        AppThemeMode(rawValue: appThemeModeRawValue) ?? .light
    }

    var body: some View {
        ZStack {
            // Keep all 6 tab view hierarchies alive in memory to preserve scroll positions & navigation paths
            ZStack {
                ListConversationScreen()
                    .opacity(coordinator.selectedTab == .chat ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .chat)

                PronunciationPracticeScreen()
                    .opacity(coordinator.selectedTab == .pronunciation ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .pronunciation)

                SituationAskScreen()
                    .opacity(coordinator.selectedTab == .askAI ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .askAI)

                SentenceStructureScreen()
                    .opacity(coordinator.selectedTab == .structure ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .structure)

                NotedAIScreen()
                    .opacity(coordinator.selectedTab == .notes ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .notes)

                VocabularyNotesScreen()
                    .opacity(coordinator.selectedTab == .vocabulary ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == .vocabulary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !coordinator.isTabBarHidden && !isKeyboardVisible {
                customModernTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(AppTheme.Primary.p500)
        .progressViewStyle(AppThemeProgressViewStyle())
        .preferredColorScheme(appThemeMode.colorScheme)
        .scrollDismissesKeyboard(.immediately)
        .background(GlobalKeyboardDismissInstaller())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardVisible = false
            }
        }
    }

    // MARK: - Custom Modern Tab Bar (6 Tabs)

    private var customModernTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(AppTheme.Surface.border.opacity(0.8))

            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let isSelected = coordinator.selectedTab == tab

                    Button {
                        guard coordinator.selectedTab != tab else { return }
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            coordinator.selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            tabIcon(for: tab, isSelected: isSelected)
                                .foregroundStyle(isSelected ? AppTheme.Primary.p500 : AppTheme.Neutral.n400)
                                .scaleEffect(isSelected ? 1.04 : 1.0)
                                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)

                            Text(tabTitle(for: tab))
                                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.Primary.p600 : AppTheme.Neutral.n400)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(
            AppTheme.Surface.card
                .opacity(0.96)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func tabIcon(for tab: AppTab, isSelected: Bool) -> some View {
        switch tab {
        case .chat:
            Image("chat_nav_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        case .pronunciation:
            Image(systemName: isSelected ? "waveform.badge.sparkle" : "waveform.and.mic")
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .frame(width: 17, height: 17)
        case .askAI:
            Image("ask_nav_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        case .structure:
            Image("structure_nav_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        case .notes:
            Image("note_nav_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        case .vocabulary:
            Image("dictionary_nav_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        }
    }

    private func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .chat: return "Chat"
        case .pronunciation: return "Phát âm"
        case .askAI: return "Hỏi AI"
        case .structure: return "Cấu trúc"
        case .notes: return "Ghi chú"
        case .vocabulary: return "Từ vựng"
        }
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
