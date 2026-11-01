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
    @State private var selectedStartIndex: Int?
    @State private var selectedEndIndex: Int?
    @State private var activePopoverIndex: Int?
    @State private var isPopoverPresented = false
    @State private var wordFrames: [Int: CGRect] = [:]
    @State private var spaceID = UUID().uuidString

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.normalizedVocabularyWord.isEmpty }
    }

    private var selectedPhraseInLightMode: String {
        guard let s = selectedStartIndex,
              let e = selectedEndIndex,
              s >= 0, e < words.count, s <= e else {
            if let idx = activePopoverIndex, idx >= 0, idx < words.count {
                let w = words[idx]
                let clean = w.trimmingCharacters(in: .punctuationCharacters)
                return clean.isEmpty ? w : clean
            }
            return ""
        }
        let raw = words[s...e].joined(separator: " ")
        let clean = raw.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return clean.isEmpty ? raw : clean
    }

    var body: some View {
        let coordSpaceName = "word_picker_\(spaceID)"

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if mode == .pickWord {
                    Label("Pick words", systemImage: "hand.tap")
                        .font(.caption.bold())
                        .foregroundStyle(foregroundStyle)
                } else {
                    Label("Light pick word (Chạm hoặc kéo cụm từ)", systemImage: "character.book.closed.fill")
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
                    let isSelected: Bool = {
                        if mode == .pickWord {
                            return selectedWords.contains(normalizedWord)
                        } else {
                            guard let s = selectedStartIndex, let e = selectedEndIndex else {
                                return activePopoverIndex == index
                            }
                            return index >= s && index <= e
                        }
                    }()
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
                                selectedStartIndex = index
                                selectedEndIndex = index
                                activePopoverIndex = index
                                isPopoverPresented = true
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
                                        lineWidth: 0.5
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
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: WordTokenFramePreferenceKey.self,
                                value: [index: proxy.frame(in: .named(coordSpaceName))]
                            )
                        }
                    )
                    .popover(
                        isPresented: Binding(
                            get: { mode == .lightPickWord && isPopoverPresented && activePopoverIndex == index },
                            set: { isPresented in
                                if !isPresented && activePopoverIndex == index {
                                    isPopoverPresented = false
                                    activePopoverIndex = nil
                                    selectedStartIndex = nil
                                    selectedEndIndex = nil
                                }
                            }
                        ),
                        attachmentAnchor: .rect(.bounds)
                    ) {
                        let targetPhrase = selectedPhraseInLightMode
                        let phraseNorm = targetPhrase.normalizedVocabularyWord
                        let phraseSaved = savedWords.contains(phraseNorm) || sessionSavedWords.contains(phraseNorm)

                        QuickWordLookupPopoverView(
                            word: targetPhrase,
                            sentence: text,
                            isAlreadySaved: phraseSaved,
                            onSaveWord: {
                                sessionSavedWords.insert(phraseNorm)
                                onPick(phraseNorm)
                            },
                            onAnalyzeFullSentence: {
                                isPopoverPresented = false
                                activePopoverIndex = nil
                                StructureNavigationCoordinator.shared.openAndAnalyze(text)
                            },
                            canExpandBefore: (selectedStartIndex ?? 0) > 0,
                            canExpandAfter: (selectedEndIndex ?? 0) < words.count - 1,
                            canShrinkBefore: (selectedStartIndex ?? 0) < (selectedEndIndex ?? 0),
                            canShrinkAfter: (selectedEndIndex ?? 0) > (selectedStartIndex ?? 0),
                            onExpandBefore: {
                                if let s = selectedStartIndex, s > 0 {
                                    selectedStartIndex = s - 1
                                }
                            },
                            onExpandAfter: {
                                if let e = selectedEndIndex, e < words.count - 1 {
                                    selectedEndIndex = e + 1
                                }
                            },
                            onShrinkBefore: {
                                if let s = selectedStartIndex, let e = selectedEndIndex, s < e {
                                    selectedStartIndex = s + 1
                                }
                            },
                            onShrinkAfter: {
                                if let s = selectedStartIndex, let e = selectedEndIndex, e > s {
                                    selectedEndIndex = e - 1
                                }
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .coordinateSpace(name: coordSpaceName)
            .onPreferenceChange(WordTokenFramePreferenceKey.self) { frames in
                wordFrames = frames
            }
            .overlay {
                if mode == .lightPickWord {
                    PhraseDragSelectionOverlay(
                        wordFrames: wordFrames,
                        onTapWord: { idx in
                            guard idx >= 0 && idx < words.count else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedStartIndex = idx
                                selectedEndIndex = idx
                                activePopoverIndex = idx
                                isPopoverPresented = true
                            }
                        },
                        onDragRangeChanged: { startIdx, endIdx in
                            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.85)) {
                                isPopoverPresented = false
                                selectedStartIndex = startIdx
                                selectedEndIndex = endIdx
                            }
                        },
                        onDragRangeEnded: { startIdx, endIdx in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedStartIndex = startIdx
                                selectedEndIndex = endIdx
                                activePopoverIndex = (startIdx + endIdx) / 2
                                isPopoverPresented = true
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(modeBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.Accent.a100, lineWidth: 0.5)
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

    @State private var selectedStartIndex: Int?
    @State private var selectedEndIndex: Int?
    @State private var popoverAnchorIndex: Int?
    @State private var isPopoverPresented = false
    @State private var wordFrames: [Int: CGRect] = [:]
    @State private var sessionSavedWords: Set<String> = []
    @State private var spaceID = UUID().uuidString

    private var tokens: [String] {
        sentence.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var selectedPhrase: String {
        guard let s = selectedStartIndex,
              let e = selectedEndIndex,
              s >= 0, e < tokens.count, s <= e else {
            return ""
        }
        let raw = tokens[s...e].joined(separator: " ")
        let clean = raw.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return clean.isEmpty ? raw : clean
    }

    var body: some View {
        let coordSpaceName = "light_pick_\(spaceID)"

        WordPickerFlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, rawToken in
                let normalized = rawToken.normalizedVocabularyWord
                let isSelected: Bool = {
                    guard let s = selectedStartIndex, let e = selectedEndIndex else { return false }
                    return index >= s && index <= e
                }()
                let isSaved = savedWords.contains(normalized) || sessionSavedWords.contains(normalized)

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
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: WordTokenFramePreferenceKey.self,
                                value: [index: proxy.frame(in: .named(coordSpaceName))]
                            )
                        }
                    )
                    .popover(
                        isPresented: Binding(
                            get: { isPopoverPresented && popoverAnchorIndex == index },
                            set: { presented in
                                if !presented && popoverAnchorIndex == index {
                                    isPopoverPresented = false
                                    selectedStartIndex = nil
                                    selectedEndIndex = nil
                                    popoverAnchorIndex = nil
                                }
                            }
                        ),
                        attachmentAnchor: .rect(.bounds)
                    ) {
                        let targetPhrase = selectedPhrase
                        let phraseNormalized = targetPhrase.normalizedVocabularyWord
                        let phraseSaved = savedWords.contains(phraseNormalized) || sessionSavedWords.contains(phraseNormalized)

                        QuickWordLookupPopoverView(
                            word: targetPhrase,
                            sentence: sentence,
                            isAlreadySaved: phraseSaved,
                            onSaveWord: {
                                sessionSavedWords.insert(phraseNormalized)
                                onSaveVocabulary(targetPhrase, sentence)
                            },
                            onAnalyzeFullSentence: nil,
                            canExpandBefore: (selectedStartIndex ?? 0) > 0,
                            canExpandAfter: (selectedEndIndex ?? 0) < tokens.count - 1,
                            canShrinkBefore: (selectedStartIndex ?? 0) < (selectedEndIndex ?? 0),
                            canShrinkAfter: (selectedEndIndex ?? 0) > (selectedStartIndex ?? 0),
                            onExpandBefore: {
                                if let s = selectedStartIndex, s > 0 {
                                    selectedStartIndex = s - 1
                                }
                            },
                            onExpandAfter: {
                                if let e = selectedEndIndex, e < tokens.count - 1 {
                                    selectedEndIndex = e + 1
                                }
                            },
                            onShrinkBefore: {
                                if let s = selectedStartIndex, let e = selectedEndIndex, s < e {
                                    selectedStartIndex = s + 1
                                }
                            },
                            onShrinkAfter: {
                                if let s = selectedStartIndex, let e = selectedEndIndex, e > s {
                                    selectedEndIndex = e - 1
                                }
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .coordinateSpace(name: coordSpaceName)
        .onPreferenceChange(WordTokenFramePreferenceKey.self) { frames in
            wordFrames = frames
        }
        .overlay {
            PhraseDragSelectionOverlay(
                wordFrames: wordFrames,
                onTapWord: { idx in
                    guard idx >= 0 && idx < tokens.count else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        selectedStartIndex = idx
                        selectedEndIndex = idx
                        popoverAnchorIndex = idx
                        isPopoverPresented = true
                    }
                },
                onDragRangeChanged: { startIdx, endIdx in
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.85)) {
                        isPopoverPresented = false
                        selectedStartIndex = startIdx
                        selectedEndIndex = endIdx
                    }
                },
                onDragRangeEnded: { startIdx, endIdx in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        selectedStartIndex = startIdx
                        selectedEndIndex = endIdx
                        popoverAnchorIndex = (startIdx + endIdx) / 2
                        isPopoverPresented = true
                    }
                }
            )
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

    var canExpandBefore: Bool = false
    var canExpandAfter: Bool = false
    var canShrinkBefore: Bool = false
    var canShrinkAfter: Bool = false
    var onExpandBefore: (() -> Void)? = nil
    var onExpandAfter: (() -> Void)? = nil
    var onShrinkBefore: (() -> Void)? = nil
    var onShrinkAfter: (() -> Void)? = nil

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

    private var hasPhraseControls: Bool {
        onExpandBefore != nil || onExpandAfter != nil
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
                            .fixedSize(horizontal: false, vertical: true)

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

            if hasPhraseControls {
                HStack(spacing: 6) {
                    Button {
                        onExpandBefore?()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Image(systemName: "arrow.left")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(canExpandBefore ? AppTheme.Primary.p50 : AppTheme.Neutral.n100)
                        .foregroundStyle(canExpandBefore ? AppTheme.Primary.p700 : AppTheme.Neutral.n400)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canExpandBefore)

                    if canShrinkBefore {
                        Button {
                            onShrinkBefore?()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(AppTheme.Neutral.n100)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("Mở rộng cụm từ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.Neutral.n500)

                    Spacer()

                    if canShrinkAfter {
                        Button {
                            onShrinkAfter?()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(AppTheme.Neutral.n100)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onExpandAfter?()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.right")
                            Image(systemName: "plus")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(canExpandAfter ? AppTheme.Primary.p50 : AppTheme.Neutral.n100)
                        .foregroundStyle(canExpandAfter ? AppTheme.Primary.p700 : AppTheme.Neutral.n400)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canExpandAfter)
                }
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
        .onChange(of: word) { _, _ in
            hasSaved = false
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
        let targetWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetWord.isEmpty else { return }

        if !force, let cached = QuickWordLookupCache.shared.get(word: targetWord, sentence: sentence) {
            result = cached
            return
        }

        isLoading = true
        let provider = selectedAIModel.makeVocabularyProvider()

        Task {
            do {
                let service = VocabularyAIService(provider: provider)
                let response = try await service.quickLookupWord(word: targetWord, sentence: sentence)

                await MainActor.run {
                    QuickWordLookupCache.shared.set(response, word: targetWord, sentence: sentence)
                    if self.word.trimmingCharacters(in: .whitespacesAndNewlines) == targetWord {
                        result = response
                        isLoading = false
                    }

                    if effectiveSaved {
                        _ = try? VocabularyNoteStore.saveQuickLookupResult(
                            word: targetWord,
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

struct WordTokenFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PhraseDragSelectionOverlay: UIViewRepresentable {
    let wordFrames: [Int: CGRect]
    let onTapWord: (Int) -> Void
    let onDragRangeChanged: (Int, Int) -> Void
    let onDragRangeEnded: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.delegate = context.coordinator
        panGesture.cancelsTouchesInView = true
        view.addGestureRecognizer(panGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.22
        longPressGesture.cancelsTouchesInView = true
        view.addGestureRecognizer(longPressGesture)

        tapGesture.require(toFail: panGesture)
        tapGesture.require(toFail: longPressGesture)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PhraseDragSelectionOverlay
        private var dragStartIndex: Int?
        private var dragCurrentIndex: Int?
        private let selectionFeedback = UISelectionFeedbackGenerator()
        private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

        init(parent: PhraseDragSelectionOverlay) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let pan = gestureRecognizer as? UIPanGestureRecognizer,
               let view = pan.view {
                let velocity = pan.velocity(in: view)
                // Only capture horizontal drags so vertical ScrollView scrolling is never blocked
                guard abs(velocity.x) > abs(velocity.y) * 0.75 else {
                    return false
                }
                let location = pan.location(in: view)
                let translation = pan.translation(in: view)
                let startPoint = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
                return wordIndex(near: startPoint, allowNearest: true) != nil
            }
            return true
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let point = recognizer.location(in: view)
            if let index = wordIndex(near: point, allowNearest: false) {
                impactFeedback.impactOccurred()
                parent.onTapWord(index)
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                let translation = recognizer.translation(in: view)
                let startPoint = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
                if let startIdx = wordIndex(near: startPoint, allowNearest: true) {
                    dragStartIndex = startIdx
                    dragCurrentIndex = startIdx
                    selectionFeedback.prepare()
                    selectionFeedback.selectionChanged()
                    parent.onDragRangeChanged(startIdx, startIdx)
                }
            case .changed:
                guard let startIdx = dragStartIndex else { return }
                if let currentIdx = wordIndex(near: location, allowNearest: true),
                   currentIdx != dragCurrentIndex {
                    dragCurrentIndex = currentIdx
                    selectionFeedback.selectionChanged()
                    parent.onDragRangeChanged(min(startIdx, currentIdx), max(startIdx, currentIdx))
                }
            case .ended, .cancelled, .failed:
                if let startIdx = dragStartIndex, let endIdx = dragCurrentIndex {
                    impactFeedback.impactOccurred()
                    parent.onDragRangeEnded(min(startIdx, endIdx), max(startIdx, endIdx))
                }
                dragStartIndex = nil
                dragCurrentIndex = nil
            default:
                break
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)

            switch recognizer.state {
            case .began:
                if let startIdx = wordIndex(near: location, allowNearest: true) {
                    dragStartIndex = startIdx
                    dragCurrentIndex = startIdx
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectionFeedback.prepare()
                    parent.onDragRangeChanged(startIdx, startIdx)
                }
            case .changed:
                guard let startIdx = dragStartIndex else { return }
                if let currentIdx = wordIndex(near: location, allowNearest: true),
                   currentIdx != dragCurrentIndex {
                    dragCurrentIndex = currentIdx
                    selectionFeedback.selectionChanged()
                    parent.onDragRangeChanged(min(startIdx, currentIdx), max(startIdx, currentIdx))
                }
            case .ended, .cancelled, .failed:
                if let startIdx = dragStartIndex, let endIdx = dragCurrentIndex {
                    impactFeedback.impactOccurred()
                    parent.onDragRangeEnded(min(startIdx, endIdx), max(startIdx, endIdx))
                }
                dragStartIndex = nil
                dragCurrentIndex = nil
            default:
                break
            }
        }

        private func wordIndex(near point: CGPoint, allowNearest: Bool) -> Int? {
            if let exact = parent.wordFrames.first(where: { $0.value.insetBy(dx: -4, dy: -4).contains(point) }) {
                return exact.key
            }
            guard allowNearest else { return nil }

            let sameLineCandidates = parent.wordFrames.filter { (_, rect) in
                let expanded = rect.insetBy(dx: 0, dy: -10)
                return point.y >= expanded.minY && point.y <= expanded.maxY
            }
            let pool = sameLineCandidates.isEmpty ? parent.wordFrames : sameLineCandidates

            var bestIndex: Int?
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (idx, rect) in pool {
                let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
                let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
                let dist = hypot(dx, dy)
                if dist < bestDist && dist < 52 {
                    bestDist = dist
                    bestIndex = idx
                }
            }
            return bestIndex
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
