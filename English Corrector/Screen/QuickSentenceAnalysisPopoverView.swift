//
//  QuickSentenceAnalysisPopoverView.swift
//  English Corrector
//

import SwiftUI

@MainActor
final class QuickSentenceAnalysisCache {
    static let shared = QuickSentenceAnalysisCache()
    private var cache: [String: AISentenceStructureResponse] = [:]

    private init() {}

    private func makeKey(sentence: String) -> String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func get(sentence: String) -> AISentenceStructureResponse? {
        cache[makeKey(sentence: sentence)]
    }

    func set(_ response: AISentenceStructureResponse, sentence: String) {
        cache[makeKey(sentence: sentence)] = response
    }
}

struct QuickSentenceAnalysisPopoverView: View {
    let sentence: String
    let onOpenFullAnalysis: () -> Void

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var result: AISentenceStructureResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // HEADER
            HStack(spacing: 8) {
                Label("Light Analysis", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Primary.p700)

                Spacer()

                SpeakButton(
                    text: sentence,
                    slow: false,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Primary.p500,
                    showBackground: true
                )
            }

            Divider()
                .overlay(AppTheme.Surface.border)

            if isLoading {
                HStack(spacing: 8) {
                    AppThemeLoadingView(customSize: 18)
                    Text("Đang phân tích nhanh cấu trúc câu...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .padding(.vertical, 12)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Semantic.error)
                        .lineLimit(2)

                    Button("Thử lại") {
                        performAnalysis(force: true)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                }
            } else if let result {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Translation
                        if !result.vietnameseTranslation.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tạm dịch")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppTheme.Primary.p500)
                                Text(result.vietnameseTranslation)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Formula & Tense badges
                        WordPickerFlowLayout(spacing: 6, lineSpacing: 6) {
                            if !result.generalFormula.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "function")
                                        .font(.caption2)
                                    Text(result.generalFormula)
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(AppTheme.Primary.p700)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.Primary.p50)
                                .clipShape(Capsule())
                            }

                            if !result.tense.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.caption2)
                                    Text(result.tense)
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(AppTheme.Accent.a600)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.Accent.a50)
                                .clipShape(Capsule())
                            }
                        }

                        // Main Components (S - V - O...)
                        if !result.components.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Thành phần câu")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppTheme.Neutral.n500)

                                ForEach(result.components.prefix(4)) { comp in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(comp.symbol)
                                                .font(.caption2.bold())
                                                .foregroundStyle(AppTheme.Primary.p700)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.Primary.p50)
                                                .clipShape(Capsule())

                                            Text(comp.segment)
                                                .font(.caption.bold())
                                                .foregroundStyle(AppTheme.Neutral.n900)
                                        }

                                        if !comp.explanation.isEmpty {
                                            Text(comp.explanation)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.Neutral.n500)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.Surface.cardMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        // Key Grammar Point
                        if let firstPattern = result.grammarPatterns.first {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.Semantic.warning)
                                    Text(firstPattern.pattern)
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.Primary.p700)
                                }

                                Text(firstPattern.explanation)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.Primary.p50.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            // FOOTER: OPEN FULL STRUCTURE TAB
            Button(action: onOpenFullAnalysis) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.3.group.fill")
                    Text("Xem chi tiết tại tab Structure")
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Primary.p500)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 310)
        .background(AppTheme.Surface.card)
        .onAppear {
            performAnalysis(force: false)
        }
    }

    private func performAnalysis(force: Bool) {
        errorMessage = nil

        if !force, let cached = QuickSentenceAnalysisCache.shared.get(sentence: sentence) {
            result = cached
            return
        }

        isLoading = true
        let provider = selectedAIModel.makeSentenceStructureProvider()

        Task {
            do {
                let service = SentenceStructureAIService(provider: provider)
                let response = try await service.analyzeSentence(sentence: sentence)

                await MainActor.run {
                    QuickSentenceAnalysisCache.shared.set(response, sentence: sentence)
                    result = response
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
