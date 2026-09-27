//
//  AppTheme.swift
//  English Corrector
//

import SwiftUI

enum AppTheme {
    enum Primary {
        static let p50 = Color(hex: 0xEFF6FF)
        static let p100 = Color(hex: 0xDBEAFE)
        static let p300 = Color(hex: 0x93C5FD)
        static let p500 = Color(hex: 0x2563EB)
        static let p700 = Color(hex: 0x1D4ED8)
    }

    enum Secondary {
        static let s50 = Color(hex: 0xECFDF5)
        static let s100 = Color(hex: 0xD1FAE5)
        static let s500 = Color(hex: 0x10B981)
        static let s600 = Color(hex: 0x059669)
    }

    enum Accent {
        static let a50 = Color(hex: 0xF5F3FF)
        static let a100 = Color(hex: 0xEDE9FE)
        static let a500 = Color(hex: 0x8B5CF6)
        static let a600 = Color(hex: 0x7C3AED)
    }

    enum Semantic {
        static let success = Color(hex: 0x16A34A)
        static let warning = Color(hex: 0xF59E0B)
        static let error = Color(hex: 0xDC2626)
        static let info = Color(hex: 0x0EA5E9)
    }

    enum Neutral {
        static let n50 = Color(hex: 0xFAFAF9)
        static let n100 = Color(hex: 0xF5F5F4)
        static let n200 = Color(hex: 0xE7E5E4)
        static let n400 = Color(hex: 0xA8A29E)
        static let n500 = Color(hex: 0x78716C)
        static let n700 = Color(hex: 0x44403C)
        static let n900 = Color(hex: 0x1C1917)
    }

    enum Surface {
        static let appBackground = Neutral.n50
        static let card = Color.white
        static let cardMuted = Neutral.n100
        static let border = Neutral.n200
    }

    enum Shadow {
        static let card = Color(hex: 0x1D4ED8).opacity(0.08)
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
}
