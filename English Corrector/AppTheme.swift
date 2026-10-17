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
