//
//  ChatWordPickerViews.swift
//  English Corrector
//

import SwiftUI
import SwiftData
import UIKit

enum WordInteractionMode: String, Hashable {
    case pickWord
    case lightPickWord
}

struct WordPickTarget: Hashable {
    let messageID: UUID
    let section: String
    var mode: WordInteractionMode = .pickWord

    func matchesSection(_ other: WordPickTarget) -> Bool {
        messageID == other.messageID && section == other.section
    }
}

func vocabularyHighlightedText(
    _ text: String,
    targetWord: String?,
    defaultColor: Color,
    highlightColor: Color = AppTheme.Accent.a600
) -> Text {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let targetWord,
          !targetWord.normalizedVocabularyWord.isEmpty else {
        return Text(trimmed).foregroundColor(defaultColor)
    }

    let normalizedTarget = targetWord.normalizedVocabularyWord
    let words = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    var result = Text("")

    for (index, word) in words.enumerated() {
        let suffix = index < words.count - 1 ? " " : ""
        if word.normalizedVocabularyWord == normalizedTarget {
            result = result + Text(word + suffix)
                .foregroundColor(highlightColor)
                .fontWeight(.heavy)
                .underline(true, color: highlightColor)
        } else {
            result = result + Text(word + suffix)
                .foregroundColor(defaultColor)
        }
    }

    return result
}

struct WordPickerText: View {
    let text: String
    var mode: WordInteractionMode = .pickWord
    let foregroundStyle: Color
    let chipBackground: Color
    let modeBackground: Color
    let savedWords: Set<String>
    let onPick: (String) -> Void
    let onDone: () -> Void

    @AppStorage("wordPickerUsesPills") private var usesPills = true
    @State private var selectedWords: Set<String> = []
    @State private var sessionSavedWords: Set<String> = []
    @State private var activePopoverIndex: Int?

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.normalizedVocabularyWord.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if mode == .pickWord {
                    Label("Pick words", systemImage: "hand.tap")
                        .font(.caption.bold())
                        .foregroundStyle(foregroundStyle)
                } else {
                    Label("Light pick word", systemImage: "character.book.closed.fill")
                        .font(.caption.bold())
                        .foregroundStyle(foregroundStyle)
                }

                Spacer()

                Button {
                    usesPills.toggle()
                } label: {
                    Label(
                        usesPills ? "Text" : "Pill",
                        systemImage: usesPills ? "textformat" : "capsule"
                    )
                    .labelStyle(.iconOnly)
                }
                .font(.caption.bold())
                .foregroundStyle(foregroundStyle)

                if mode == .pickWord && !selectedWords.isEmpty {
                    Button {
                        addSelectedWords()
                    } label: {
                        Label("Add selected", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(foregroundStyle)
                }

                Button("Done", action: onDone)
                    .font(.caption.bold())
                    .foregroundStyle(foregroundStyle)
            }

            WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    let normalizedWord = word.normalizedVocabularyWord
                    let isSelected = (mode == .pickWord)
                        ? selectedWords.contains(normalizedWord)
                        : (activePopoverIndex == index)
                    let isSaved = savedWords.contains(normalizedWord) || sessionSavedWords.contains(normalizedWord)
                    let displayWord = word.trimmingCharacters(in: .punctuationCharacters)

                    Button {
                        if mode == .pickWord {
                            guard !isSaved else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                if selectedWords.contains(normalizedWord) {
                                    selectedWords.remove(normalizedWord)
                                } else {
                                    selectedWords.insert(normalizedWord)
                                }
                            }
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                activePopoverIndex = index
                            }
                        }
                    } label: {
                        let activeBackground = isSaved
                        ? AppTheme.Semantic.success
                        : AppTheme.Accent.a500
                        let activeTextColor: Color = .white

                        if usesPills {
                            HStack(spacing: 5) {
                                if isSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2.weight(.bold))
                                }

                                Text(displayWord)
                                    .lineLimit(1)
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle((isSelected || isSaved) ? activeTextColor : foregroundStyle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((isSelected || isSaved) ? activeBackground : chipBackground)
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            (isSelected || isSaved) ? activeBackground : foregroundStyle.opacity(0.18),
                                            lineWidth: 1
                                        )
                                }
                                .clipShape(Capsule())
                                .scaleEffect((isSelected || isSaved) ? 1.04 : 1)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSaved)
                        } else {
                            HStack(spacing: 4) {
                                if isSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2.weight(.bold))
                                }

                                Text(displayWord)
                                    .lineLimit(1)
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(
                                isSaved
                                ? AppTheme.Semantic.success
                                : isSelected ? AppTheme.Accent.a600 : foregroundStyle
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                                .background(
                                    isSaved
                                    ? AppTheme.Semantic.success.opacity(0.14)
                                    : isSelected ? AppTheme.Accent.a100
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(
                                            isSaved
                                            ? AppTheme.Semantic.success
                                            : isSelected ? AppTheme.Accent.a600 : foregroundStyle.opacity(0.28)
                                        )
                                        .frame(height: 1)
                                }
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSaved)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(mode == .pickWord && isSaved)
                    .popover(
                        isPresented: Binding(
                            get: { mode == .lightPickWord && activePopoverIndex == index },
                            set: { isPresented in
                                if !isPresented && activePopoverIndex == index {
                                    activePopoverIndex = nil
                                }
                            }
                        ),
                        attachmentAnchor: .rect(.bounds)
                    ) {
                        QuickWordLookupPopoverView(
                            word: displayWord.isEmpty ? word : displayWord,
                            sentence: text,
                            isAlreadySaved: isSaved,
                            onSaveWord: {
                                sessionSavedWords.insert(normalizedWord)
                                onPick(normalizedWord)
                            },
                            onAnalyzeFullSentence: {
                                activePopoverIndex = nil
                                StructureNavigationCoordinator.shared.openAndAnalyze(text)
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(modeBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.Accent.a100, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func addSelectedWords() {
        let wordsToSave = selectedWords

        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            sessionSavedWords.formUnion(wordsToSave)
            selectedWords.removeAll()
        }

        for word in wordsToSave {
            onPick(word)
        }
    }
}

struct LightPickableSentenceText: View {
    let sentence: String
    var font: Font = .title3.weight(.bold)
    var foregroundColor: Color = AppTheme.Neutral.n900
    let savedWords: Set<String>
    let onSaveVocabulary: (String, String) -> Void

    @State private var activePopoverIndex: Int?
    @State private var sessionSavedWords: Set<String> = []

    private var tokens: [String] {
        sentence.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        WordPickerFlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, rawToken in
                let normalized = rawToken.normalizedVocabularyWord
                let cleanWord = rawToken.trimmingCharacters(in: .punctuationCharacters)
                let isSelected = (activePopoverIndex == index)
                let isSaved = savedWords.contains(normalized) || sessionSavedWords.contains(normalized)

                Button {
                    guard !normalized.isEmpty else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        activePopoverIndex = index
                    }
                } label: {
                    Text(rawToken)
                        .font(font)
                        .foregroundStyle(
                            isSelected
                            ? AppTheme.Primary.p700
                            : isSaved ? AppTheme.Semantic.success : foregroundColor
                        )
                        .padding(.horizontal, isSelected ? 5 : 2)
                        .padding(.vertical, 2)
                        .background(
                            isSelected
                            ? AppTheme.Primary.p100
                            : isSaved ? AppTheme.Semantic.success.opacity(0.1) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(
                                    isSelected
                                    ? AppTheme.Primary.p500
                                    : isSaved ? AppTheme.Semantic.success.opacity(0.6) : AppTheme.Neutral.n400.opacity(0.35)
                                )
                                .frame(height: isSelected ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { activePopoverIndex == index },
                        set: { isPresented in
                            if !isPresented && activePopoverIndex == index {
                                activePopoverIndex = nil
                            }
                        }
                    ),
                    attachmentAnchor: .rect(.bounds)
                ) {
                    QuickWordLookupPopoverView(
                        word: cleanWord.isEmpty ? rawToken : cleanWord,
                        sentence: sentence,
                        isAlreadySaved: isSaved,
                        onSaveWord: {
                            sessionSavedWords.insert(normalized)
                            onSaveVocabulary(cleanWord.isEmpty ? rawToken : cleanWord, sentence)
                        },
                        onAnalyzeFullSentence: nil
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
}

struct QuickWordLookupPopoverView: View {
    @Environment(\.modelContext) private var context

    let word: String
    let sentence: String
    let isAlreadySaved: Bool
    let onSaveWord: () -> Void
    let onAnalyzeFullSentence: (() -> Void)?

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var result: AIQuickWordLookupResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSaved = false

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var effectiveSaved: Bool {
        isAlreadySaved || hasSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. HEADER: WORD + IPA + POS + SPEAK
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result?.word.isEmpty == false ? result!.word : word)
                            .font(.headline.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        if let baseForm = result?.baseForm,
                           !baseForm.isEmpty,
                           baseForm.lowercased() != word.lowercased() {
                            Text("(\(baseForm))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }
                    }

                    HStack(spacing: 6) {
                        if let phonetic = result?.phonetic, !phonetic.isEmpty {
                            Text(phonetic)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }

                        if let pos = result?.partOfSpeech, !pos.isEmpty {
                            Text(pos)
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Primary.p700)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Primary.p50)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                SpeakButton(
                    text: word,
                    slow: false,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Primary.p500,
                    showBackground: true
                )

                SpeakButton(
                    text: word,
                    slow: true,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Accent.a600,
                    showBackground: true
                )
            }

            Divider()
                .overlay(AppTheme.Surface.border)

            // 2. BODY: MEANING & GRAMMAR ROLE IN SENTENCE
            if isLoading {
                HStack(spacing: 8) {
                    AppThemeLoadingView(customSize: 18)
                    Text("Đang tra nghĩa & vai trò trong câu...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .padding(.vertical, 10)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Semantic.error)
                        .lineLimit(2)

                    Button("Thử lại") {
                        performLookup(force: true)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                }
            } else if let result {
                VStack(alignment: .leading, spacing: 8) {
                    // Contextual Meaning
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nghĩa trong câu")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Primary.p500)

                        Text(result.contextualMeaning)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Role in Sentence Structure
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Vai trò & Cấu trúc câu")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Accent.a600)

                        Text(result.grammarRoleInSentence)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .fixedSize(horizontal: false, vertical: true)

                        if let pattern = result.structurePattern?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !pattern.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "function")
                                    .font(.caption2)
                                Text(pattern)
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(AppTheme.Primary.p700)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                            .padding(.top, 2)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // 3. FOOTER ACTIONS
            HStack(spacing: 8) {
                Button {
                    saveWordToStore()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: effectiveSaved ? "checkmark.circle.fill" : "bookmark.fill")
                        Text(effectiveSaved ? "Đã lưu" : "Lưu từ")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(effectiveSaved ? AppTheme.Semantic.success : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        effectiveSaved
                        ? AppTheme.Semantic.success.opacity(0.14)
                        : AppTheme.Primary.p500
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if let onAnalyzeFullSentence {
                    Button(action: onAnalyzeFullSentence) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.3.group.fill")
                            Text("Cấu trúc câu")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 285)
        .background(AppTheme.Surface.card)
        .onAppear {
            performLookup(force: false)
        }
    }

    private func saveWordToStore() {
        if let result {
            _ = try? VocabularyNoteStore.saveQuickLookupResult(
                word: word,
                quickLookup: result,
                sourceText: sentence,
                in: context
            )
        }
        hasSaved = true
        onSaveWord()
    }

    private func performLookup(force: Bool) {
        errorMessage = nil

        if !force, let cached = QuickWordLookupCache.shared.get(word: word, sentence: sentence) {
            result = cached
            return
        }

        isLoading = true
        let provider = selectedAIModel.makeVocabularyProvider()

        Task {
            do {
                let service = VocabularyAIService(provider: provider)
                let response = try await service.quickLookupWord(word: word, sentence: sentence)

                await MainActor.run {
                    QuickWordLookupCache.shared.set(response, word: word, sentence: sentence)
                    result = response
                    isLoading = false

                    if effectiveSaved {
                        _ = try? VocabularyNoteStore.saveQuickLookupResult(
                            word: word,
                            quickLookup: response,
                            sourceText: sentence,
                            in: context
                        )
                    }
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

struct WordPickerFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(proposal.width ?? UIScreen.main.bounds.width - 64, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: ceil(y + lineHeight))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
