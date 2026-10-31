//
//  NewsSentenceAnalysisSheetView.swift
//  English Corrector
//

import SwiftUI

struct NewsSentenceAnalysisSheetView: View {
    let initialText: String
    let onOpenFullStructure: (String) -> Void
    let onSaveWord: (String, String) -> Void
    let isWordSaved: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue
    @ObservedObject private var speechManager = SpeechSynthesizerManager.shared

    @State private var sentences: [String] = []
    @State private var selectedSentenceIndex: Int = 0
    @State private var cache: [String: AISentenceStructureResponse] = [:]
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var activeText: String {
        if sentences.count > 1 && selectedSentenceIndex == -1 {
            return initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if selectedSentenceIndex >= 0 && selectedSentenceIndex < sentences.count {
            return sentences[selectedSentenceIndex]
        }
        return initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentResult: AISentenceStructureResponse? {
        cache[activeText.lowercased()]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Multi-sentence Tab Selector (if paragraph has > 1 sentence)
                    if sentences.count > 1 {
                        sentenceSelectorHeader
                    }

                    // 2. Active English Text Card (with Speak & Copy)
                    activeSentenceBanner

                    // 3. Status View (Loading, Error, or Results)
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorCardView(error)
                    } else if let result = currentResult {
                        analysisContent(result)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.Neutral.n50.ignoresSafeArea())
            .navigationTitle("Phân tích ngữ pháp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                }
            }
            .task {
                setupSentences()
                await performAnalysis(for: activeText, force: false)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var sentenceSelectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chọn câu trong đoạn để phân tích chi tiết:")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Neutral.n500)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Button to analyze full paragraph
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedSentenceIndex = -1
                        }
                        Task { await performAnalysis(for: activeText, force: false) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.alignleft")
                                .font(.caption2)
                            Text("Toàn đoạn")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(selectedSentenceIndex == -1 ? Color.white : AppTheme.Neutral.n700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedSentenceIndex == -1 ? AppTheme.Primary.p500 : Color.white)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(selectedSentenceIndex == -1 ? AppTheme.Primary.p500 : AppTheme.Neutral.n200, lineWidth: 0.5)
                        }
                    }

                    // Individual sentences
                    ForEach(Array(sentences.enumerated()), id: \.offset) { idx, sentence in
                        let isSelected = (selectedSentenceIndex == idx)
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                selectedSentenceIndex = idx
                            }
                            Task { await performAnalysis(for: sentence, force: false) }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Câu \(idx + 1)")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(isSelected ? Color.white : AppTheme.Neutral.n700)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? AppTheme.Primary.p500 : Color.white)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(isSelected ? AppTheme.Primary.p500 : AppTheme.Neutral.n200, lineWidth: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeSentenceBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activeText)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.Neutral.n900)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    speechManager.toggleSpeak(activeText)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                        Text("Phát âm")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(AppTheme.Primary.p700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                }

                Button {
                    UIPasteboard.general.string = activeText
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                        Text("Copy")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Neutral.n100)
                    .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            AppThemeLoadingView(customSize: 26)
            Text("AI đang phân tích ngữ pháp & cấu trúc câu...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func errorCardView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.Semantic.warning)

            Text("Không thể phân tích ngữ pháp lúc này")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.Neutral.n900)

            Text(error)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n500)
                .multilineTextAlignment(.center)

            Button {
                Task { await performAnalysis(for: activeText, force: true) }
            } label: {
                Text("Thử lại")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.Primary.p500)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func analysisContent(_ result: AISentenceStructureResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Vietnamese Translation
            if !result.vietnameseTranslation.isEmpty {
                translationCard(result.vietnameseTranslation)
            }

            // 2. Formula & Tense Badges
            formulaAndTenseCard(result)

            // 3. Components Breakdown (S - V - O - Clauses...)
            if !result.components.isEmpty {
                componentsSection(result.components)
            }

            // 4. Key Grammar Patterns
            if !result.grammarPatterns.isEmpty {
                grammarPatternsSection(result.grammarPatterns)
            }

            // 5. Sentence Variations / Alternative Expressions
            if !result.variations.isEmpty {
                variationsSection(result.variations)
            }

            // 6. Action: Open in Full Structure Tab
            Button {
                onOpenFullStructure(activeText)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.3.group.fill")
                    Text("Xem chi tiết và hỏi đáp thêm tại tab Structure")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Primary.p500)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.Primary.p500.opacity(0.25), radius: 6, x: 0, y: 3)
            }
            .padding(.top, 6)
        }
    }

    private func translationCard(_ translation: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Primary.p500)
                Text("Dịch nghĩa tiếng Việt:")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n700)
            }

            Text(translation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Neutral.n900)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Primary.p50.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Primary.p300.opacity(0.6), lineWidth: 0.5)
        }
    }

    private func formulaAndTenseCard(_ result: AISentenceStructureResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !result.sentenceType.isEmpty {
                Text(result.sentenceType)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Neutral.n900)
            }

            WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                if !result.generalFormula.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "function")
                            .font(.caption2)
                        Text(result.generalFormula)
                            .font(.caption.bold())
                    }
                    .foregroundStyle(AppTheme.Primary.p700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
                    }
                }

                if !result.tense.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text(result.tense)
                            .font(.caption.bold())
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(AppTheme.Accent.a500.opacity(0.3), lineWidth: 0.5)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
        }
    }

    private func componentsSection(_ components: [AISentenceComponentItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Thành phần ngữ pháp câu:", systemImage: "rectangle.3.group")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.Neutral.n900)

            VStack(spacing: 8) {
                ForEach(components) { comp in
                    let style = componentStyle(for: comp.symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(comp.symbol)
                                .font(.caption2.bold())
                                .foregroundStyle(style.foreground)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(style.background)
                                .clipShape(Capsule())

                            Text(comp.roleName)
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.Neutral.n700)

                            Spacer()

                            if !comp.grammaticalForm.isEmpty {
                                Text(comp.grammaticalForm)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }

                        Text(comp.segment)
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        if !comp.explanation.isEmpty {
                            Text(comp.explanation)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
                    }
                }
            }
        }
    }

    private func grammarPatternsSection(_ patterns: [AISentenceGrammarPatternItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Điểm ngữ pháp trọng tâm:", systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.Neutral.n900)

            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Semantic.warning)
                        Text(pattern.pattern)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Primary.p700)
                    }

                    Text(pattern.explanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n700)
                        .lineSpacing(2)

                    if !pattern.example.isEmpty {
                        Text("Ví dụ tương tự: \"\(pattern.example)\"")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(AppTheme.Neutral.n500)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
                }
            }
        }
    }

    private func variationsSection(_ variations: [AISentenceVariationItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Cách diễn đạt tương đương:", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.Neutral.n900)

            ForEach(variations) { variation in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(variation.style)
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Accent.a600)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.Accent.a50)
                            .clipShape(Capsule())

                        Spacer()

                        Button {
                            speechManager.speak(variation.sentence)
                        } label: {
                            Image(systemName: "speaker.wave.1.fill")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Primary.p500)
                        }
                    }

                    Text(variation.sentence)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)

                    if !variation.note.isEmpty {
                        Text(variation.note)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
                }
            }
        }
    }

    private func componentStyle(for symbol: String) -> (foreground: Color, background: Color) {
        let upper = symbol.uppercased()
        if upper.contains("S") && !upper.contains("CLAUSE") {
            return (AppTheme.Primary.p700, AppTheme.Primary.p50)
        } else if upper.contains("V") && !upper.contains("ADV") {
            return (AppTheme.Semantic.success, AppTheme.Semantic.success.opacity(0.12))
        } else if upper.contains("O") || upper.contains("C") && !upper.contains("CLAUSE") && !upper.contains("CONJ") {
            return (AppTheme.Accent.a600, AppTheme.Accent.a50)
        } else if upper.contains("CLAUSE") {
            return (Color(lightHex: 0x9333EA, darkHex: 0xC084FC), Color(lightHex: 0xF3E8FF, darkHex: 0x3B0764))
        } else {
            return (AppTheme.Secondary.s600, AppTheme.Secondary.s100)
        }
    }

    // MARK: - Logic & AI Call

    private func setupSentences() {
        let cleaned = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        // Split paragraph into separate sentences by punctuation [.?!]
        var extracted: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..<cleaned.endIndex, options: [.bySentences]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), sentence.count >= 8 {
                extracted.append(sentence)
            }
        }

        if extracted.count > 1 {
            self.sentences = extracted
            self.selectedSentenceIndex = 0 // Focus on 1st sentence by default for maximum precision
        } else {
            self.sentences = [cleaned]
            self.selectedSentenceIndex = 0
        }
    }

    private func performAnalysis(for text: String, force: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cacheKey = trimmed.lowercased()
        if !force, let _ = cache[cacheKey] {
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        let provider = selectedAIModel.makeSentenceStructureProvider()
        let service = SentenceStructureAIService(provider: provider)

        do {
            let response = try await service.analyzeSentence(sentence: trimmed)
            await MainActor.run {
                self.cache[cacheKey] = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
