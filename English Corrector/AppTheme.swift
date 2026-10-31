//
//  AppTheme.swift
//  English Corrector
//

import SwiftUI
import UIKit

enum AppThemeMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppTheme {
    // Primary: #4F46E5 (Indigo) - Nhấn mạnh tiến độ, hành động hoàn thành
    enum Primary {
        static let p50 = Color(lightHex: 0xEEF2FF, darkHex: 0x1E1B4B)
        static let p100 = Color(lightHex: 0xE0E7FF, darkHex: 0x312E81)
        static let p300 = Color(lightHex: 0xA5B4FC, darkHex: 0x818CF8)
        static let p500 = Color(lightHex: 0x4F46E5, darkHex: 0x6366F1)
        static let p700 = Color(lightHex: 0x4338CA, darkHex: 0x818CF8)
    }

    // Secondary: #6B7280 (Neutral Gray) - Các nút thứ cấp, phân cách nội dung
    enum Secondary {
        static let s50 = Color(lightHex: 0xF9FAFB, darkHex: 0x1F2937)
        static let s100 = Color(lightHex: 0xF3F4F6, darkHex: 0x374151)
        static let s500 = Color(lightHex: 0x6B7280, darkHex: 0x9CA3AF)
        static let s600 = Color(lightHex: 0x4B5563, darkHex: 0xD1D5DB)
    }

    // Highlight / Accent: #EAB308 (Warm Yellow) - Tính năng highlight từ vựng, ghi chú quan trọng
    enum Highlight {
        static let h50 = Color(lightHex: 0xFEFCE8, darkHex: 0x292211)
        static let h100 = Color(lightHex: 0xFEF9C3, darkHex: 0x423513)
        static let h500 = Color(lightHex: 0xEAB308, darkHex: 0xEAB308)
        static let h600 = Color(lightHex: 0xCA8A04, darkHex: 0xFACC15)
    }

    enum Accent {
        static let a50 = Highlight.h50
        static let a100 = Highlight.h100
        static let a500 = Highlight.h500
        static let a600 = Highlight.h600
    }

    enum Semantic {
        static let success = Color(lightHex: 0x16A34A, darkHex: 0x22C55E)
        static let warning = Color(lightHex: 0xEAB308, darkHex: 0xFACC15)
        static let error = Color(lightHex: 0xDC2626, darkHex: 0xEF4444)
        static let info = Color(lightHex: 0x4F46E5, darkHex: 0x6366F1)
    }

    // Text Primary: #1C1917 (Stone 900) & Warm Stone scale
    enum Neutral {
        static let n50 = Color(lightHex: 0xFAF5FF, darkHex: 0x18181B)
        static let n100 = Color(lightHex: 0xF5F5F4, darkHex: 0x121214)
        static let n200 = Color(lightHex: 0xE7E5E4, darkHex: 0x27272A)
        static let n400 = Color(lightHex: 0x9CA3AF, darkHex: 0x71717A)
        static let n500 = Color(lightHex: 0x6B7280, darkHex: 0xA1A1AA)
        static let n700 = Color(lightHex: 0x44403C, darkHex: 0xE4E4E7)
        static let n900 = Color(lightHex: 0x1C1917, darkHex: 0xF5F5F4)
    }

    enum Text {
        static let primary = Neutral.n900
        static let secondary = Secondary.s500
    }

    // Background: #F5F5F4 (Warm Stone) - Hạn chế ánh sáng xanh, tốt cho mắt vào buổi tối
    enum Surface {
        static let appBackground = Neutral.n100
        static let appBackgroundAlt = Neutral.n50
        static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1F)
        static let cardMuted = Color(lightHex: 0xF5F5F4, darkHex: 0x27272A)
        static let border = Color(
            lightHex: 0x9CA3AF,
            lightOpacity: 0.7,
            darkHex: 0x52525B,
            darkOpacity: 0.9
        )
    }

    enum Shadow {
        static let card = Color(
            lightHex: 0x4F46E5,
            lightOpacity: 0.08,
            darkHex: 0x000000,
            darkOpacity: 0.35
        )
    }

    /// Bảng màu chuẩn dùng cho hiệu ứng Loading đa sắc của ứng dụng
    static let loadingPalette: [Color] = [
        Primary.p500,
        Primary.p300,
        Accent.a500,
        Semantic.success,
        Primary.p500
    ]
}

// MARK: - Custom Multi-Color AppTheme Loading Indicator & Bouncing Wave Dots

/// Hiệu ứng 3 dấu chấm nhảy lên xuống lệch pha như gợn sóng với bộ màu của AppTheme
struct AppThemeWaveDotsView: View {
    var dotSize: CGFloat = 5.5
    var spacing: CGFloat = 3.5
    var bounceHeight: CGFloat = 4.0

    @State private var bounceStates: [Bool] = [false, false, false]

    private let dotColors: [Color] = [
        AppTheme.Primary.p500,
        AppTheme.Accent.a500,
        AppTheme.Semantic.success
    ]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColors[index])
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(bounceStates[index] ? 1.15 : 0.82)
                    .offset(y: bounceStates[index] ? -bounceHeight : bounceHeight * 0.55)
            }
        }
        .frame(
            width: dotSize * 3 + spacing * 2,
            height: dotSize + bounceHeight * 2.2
        )
        .fixedSize()
        .onAppear {
            bounceStates = [false, false, false]
            for index in 0..<3 {
                let delay = Double(index) * 0.14
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(
                        .easeInOut(duration: 0.42)
                        .repeatForever(autoreverses: true)
                    ) {
                        bounceStates[index] = true
                    }
                }
            }
        }
    }
}

struct AppThemeLoadingView: View {
    @Environment(\.controlSize) private var controlSize

    var customSize: CGFloat? = nil
    var lineWidth: CGFloat? = nil

    @State private var isSpinning = false
    @State private var isPulsing = false

    private var resolvedSize: CGFloat {
        if let customSize {
            return customSize
        }
        switch controlSize {
        case .mini:
            return 16
        case .small:
            return 20
        case .regular:
            return 28
        case .large, .extraLarge:
            return 36
        @unknown default:
            return 28
        }
    }

    private var resolvedLineWidth: CGFloat {
        if let lineWidth {
            return lineWidth
        }
        if resolvedSize <= 20 {
            return 2.2
        } else if resolvedSize <= 28 {
            return 3.0
        } else {
            return 3.6
        }
    }

    var body: some View {
        ZStack {
            // 1. Vòng nền mờ kết hợp màu Primary & Accent
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.Primary.p100.opacity(0.75),
                            AppTheme.Accent.a100.opacity(0.75),
                            AppTheme.Primary.p100.opacity(0.75)
                        ],
                        center: .center
                    ),
                    lineWidth: resolvedLineWidth
                )

            // 2. Vòng cung xoay chuyển sắc với các màu hiện có trong AppTheme
            Circle()
                .trim(from: 0.08, to: isPulsing ? 0.78 : 0.36)
                .stroke(
                    AngularGradient(
                        colors: AppTheme.loadingPalette,
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: resolvedLineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))

            // 3. Dấu 3 chấm nhảy lên xuống như gợn sóng ở tâm vòng tròn
            AppThemeWaveDotsView(
                dotSize: max(2.8, resolvedSize * 0.145),
                spacing: max(1.6, resolvedSize * 0.065),
                bounceHeight: max(2.0, resolvedSize * 0.12)
            )
        }
        .frame(width: resolvedSize, height: resolvedSize)
        .fixedSize()
        .onAppear {
            isSpinning = false
            isPulsing = false
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityLabel("Đang tải")
    }
}

struct AppThemeProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        if let fraction = configuration.fractionCompleted {
            VStack(alignment: .leading, spacing: 6) {
                configuration.label
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.Surface.cardMuted)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.Primary.p500,
                                        AppTheme.Accent.a500,
                                        AppTheme.Semantic.success
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width, geo.size.width * fraction)))
                    }
                }
                .frame(height: 6)
            }
        } else {
            VStack(spacing: 6) {
                AppThemeLoadingView()
                configuration.label
            }
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(
        lightHex: UInt,
        lightOpacity: Double = 1,
        darkHex: UInt,
        darkOpacity: Double = 1
    ) {
        self.init(
            uiColor: UIColor { traitCollection in
                let isDark = traitCollection.userInterfaceStyle == .dark
                let hex = isDark ? darkHex : lightHex
                let alpha = isDark ? darkOpacity : lightOpacity
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: CGFloat(alpha)
                )
            }
        )
    }
}
