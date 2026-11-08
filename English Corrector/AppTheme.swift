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
        static let p200 = Color(lightHex: 0xC7D2FE, darkHex: 0x4338CA)
        static let p300 = Color(lightHex: 0xA5B4FC, darkHex: 0x818CF8)
        static let p400 = Color(lightHex: 0x6366F1, darkHex: 0x818CF8)
        static let p500 = Color(lightHex: 0x4F46E5, darkHex: 0x6366F1)
        static let p600 = Color(lightHex: 0x4338CA, darkHex: 0x6366F1)
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
        static let n300 = Color(lightHex: 0xD6D3D1, darkHex: 0x3F3F46)
        static let n400 = Color(lightHex: 0x9CA3AF, darkHex: 0x71717A)
        static let n500 = Color(lightHex: 0x6B7280, darkHex: 0xA1A1AA)
        static let n600 = Color(lightHex: 0x57534E, darkHex: 0xBEBDBA)
        static let n700 = Color(lightHex: 0x44403C, darkHex: 0xE4E4E7)
        static let n800 = Color(lightHex: 0x292524, darkHex: 0xD6D3D1)
        static let n900 = Color(lightHex: 0x1C1917, darkHex: 0xF5F5F4)
    }

    enum Text {
        static let primary = Neutral.n900
        static let secondary = Secondary.s500
    }

    // Background: #F5F5F4 (Warm Stone) - Hạn chế ánh sáng xanh, tốt cho mắt vào buổi tối
    enum Surface {
        static let appBackground = Neutral.n100
        static let background = appBackground
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

// MARK: - App Icon Vector Shapes for Loading Indicator

/// Ngôi sao 4 cánh lấp lánh (✦) lấy cảm hứng từ góc phải trên của App Icon
struct AppIconSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let top = CGPoint(x: cx, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: cy)
        let bottom = CGPoint(x: cx, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: cy)

        // Độ lõm hướng về tâm tạo đường cong mềm như icon AI
        let insetX = rect.width * 0.14
        let insetY = rect.height * 0.14

        path.move(to: top)
        path.addQuadCurve(
            to: right,
            control: CGPoint(x: cx + insetX, y: cy - insetY)
        )
        path.addQuadCurve(
            to: bottom,
            control: CGPoint(x: cx + insetX, y: cy + insetY)
        )
        path.addQuadCurve(
            to: left,
            control: CGPoint(x: cx - insetX, y: cy + insetY)
        )
        path.addQuadCurve(
            to: top,
            control: CGPoint(x: cx - insetX, y: cy - insetY)
        )
        path.closeSubpath()
        return path
    }
}

/// Chữ "A" bo tròn đậm nét ở trung tâm App Icon
struct AppIconLetterAShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        let bottomLeft = CGPoint(x: rect.minX + width * 0.14, y: rect.maxY - height * 0.08)
        let apex = CGPoint(x: rect.midX, y: rect.minY + height * 0.08)
        let bottomRight = CGPoint(x: rect.maxX - width * 0.14, y: rect.maxY - height * 0.08)

        // Hai chân chữ A hội tụ tại đỉnh
        path.move(to: bottomLeft)
        path.addLine(to: apex)
        path.addLine(to: bottomRight)

        // Thanh ngang chữ A
        let barY = rect.minY + height * 0.64
        let barLeft = CGPoint(x: rect.minX + width * 0.25, y: barY)
        let barRight = CGPoint(x: rect.maxX - width * 0.25, y: barY)
        path.move(to: barLeft)
        path.addLine(to: barRight)

        return path
    }
}

/// Dấu tích (✓) ở khoảng hở bên phải của vòng chữ C trên App Icon
struct AppIconCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let start = CGPoint(x: rect.minX + w * 0.56, y: rect.minY + h * 0.56)
        let vertex = CGPoint(x: rect.minX + w * 0.70, y: rect.minY + h * 0.70)
        let end = CGPoint(x: rect.minX + w * 0.97, y: rect.minY + h * 0.37)

        path.move(to: start)
        path.addLine(to: vertex)
        path.addLine(to: end)
        return path
    }
}

struct AppThemeLoadingView: View {
    @Environment(\.controlSize) private var controlSize

    var customSize: CGFloat? = nil
    var lineWidth: CGFloat? = nil
    var isCompleted: Bool = false

    @State private var isSpinning = false
    @State private var isPulsing = false
    @State private var sparklePrimaryPulse = false
    @State private var sparkleSecondaryPulse = false
    @State private var checkmarkProgress: CGFloat = 0

    private static let iconCyan = Color(lightHex: 0x06B6D4, darkHex: 0x22D3EE)
    private static let iconTeal = Color(lightHex: 0x14B8A6, darkHex: 0x2DD4BF)

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
            return max(3.6, resolvedSize * 0.105)
        }
    }

    private var letterLineWidth: CGFloat {
        max(1.8, resolvedLineWidth * 0.92)
    }

    private var checkmarkLineWidth: CGFloat {
        max(1.9, resolvedLineWidth * 0.95)
    }

    var body: some View {
        ZStack {
            // 1. Vòng nền mờ định hình khung tròn của App Icon
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.Primary.p100.opacity(0.65),
                            Self.iconCyan.opacity(0.28),
                            AppTheme.Primary.p100.opacity(0.65)
                        ],
                        center: .center
                    ),
                    lineWidth: resolvedLineWidth * 0.85
                )
                .padding(resolvedLineWidth * 0.5)

            // 2. Vòng cung chữ C chuyển sắc Indigo -> Cyan đặc trưng của App Icon
            Circle()
                .trim(
                    from: isCompleted ? 0.0 : 0.08,
                    to: isCompleted ? 0.76 : (isPulsing ? 0.78 : 0.36)
                )
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.Primary.p700,
                            AppTheme.Primary.p500,
                            Self.iconCyan,
                            Self.iconTeal,
                            AppTheme.Primary.p700
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: resolvedLineWidth,
                        lineCap: .round
                    )
                )
                .padding(resolvedLineWidth * 0.5)
                .rotationEffect(.degrees(isCompleted ? 28 : (isSpinning ? 360 : 0)))

            // 3. Chữ "A" bo tròn ở tâm hiệu ứng nhịp thở nhẹ nhàng
            AppIconLetterAShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.Primary.p500,
                            AppTheme.Primary.p700
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(
                        lineWidth: letterLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: resolvedSize * 0.48, height: resolvedSize * 0.48)
                .scaleEffect(isCompleted ? 0.95 : (isPulsing ? 1.05 : 0.91))
                .offset(
                    x: isCompleted ? -resolvedSize * 0.045 : 0,
                    y: resolvedSize * 0.015
                )

            // 4. Cụm 2 ngôi sao AI 4 cánh (✦) lấp lánh lệch pha ở góc trên bên phải
            AppIconSparkleShape()
                .fill(
                    LinearGradient(
                        colors: [Self.iconCyan, AppTheme.Primary.p500],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: max(4.5, resolvedSize * 0.25),
                    height: max(4.5, resolvedSize * 0.25)
                )
                .scaleEffect(isCompleted ? 1.0 : (sparklePrimaryPulse ? 1.18 : 0.62))
                .opacity(isCompleted ? 1.0 : (sparklePrimaryPulse ? 1.0 : 0.45))
                .rotationEffect(.degrees(isCompleted ? 0 : (sparklePrimaryPulse ? 12 : -8)))
                .offset(
                    x: resolvedSize * 0.26,
                    y: -resolvedSize * 0.27
                )

            AppIconSparkleShape()
                .fill(
                    LinearGradient(
                        colors: [Self.iconTeal, Self.iconCyan],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: max(3.2, resolvedSize * 0.16),
                    height: max(3.2, resolvedSize * 0.16)
                )
                .scaleEffect(isCompleted ? 1.0 : (sparkleSecondaryPulse ? 1.22 : 0.55))
                .opacity(isCompleted ? 0.95 : (sparkleSecondaryPulse ? 1.0 : 0.35))
                .rotationEffect(.degrees(isCompleted ? 0 : (sparkleSecondaryPulse ? -15 : 10)))
                .offset(
                    x: resolvedSize * 0.39,
                    y: -resolvedSize * 0.12
                )

            // 5. Dấu tích hoàn thành (✓) bên phải khi isCompleted = true
            AppIconCheckmarkShape()
                .trim(from: 0, to: isCompleted ? checkmarkProgress : 0)
                .stroke(
                    LinearGradient(
                        colors: [
                            Self.iconTeal,
                            Self.iconCyan,
                            AppTheme.Primary.p500
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: checkmarkLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .frame(width: resolvedSize, height: resolvedSize)
        .fixedSize()
        .onAppear {
            if isCompleted {
                checkmarkProgress = 1.0
            } else {
                startLoadingAnimations()
            }
        }
        .onChange(of: isCompleted) { _, completed in
            if completed {
                checkmarkProgress = 0
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                    checkmarkProgress = 1.0
                }
            } else {
                checkmarkProgress = 0
                startLoadingAnimations()
            }
        }
        .accessibilityLabel(isCompleted ? "Đã hoàn thành" : "Đang tải")
    }

    private func startLoadingAnimations() {
        isSpinning = false
        isPulsing = false
        sparklePrimaryPulse = false
        sparkleSecondaryPulse = false

        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
            withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                sparklePrimaryPulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
                    sparkleSecondaryPulse = true
                }
            }
        }
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
