//
//  NewsArticleReaderScreen.swift
//  English Corrector
//
//

import SwiftUI
import SwiftData

struct SelectedArticleRange: Equatable {
    let paragraphKey: String // "title" or "p_0", "p_1", etc.
    var startIndex: Int
    var endIndex: Int
    var anchorIndex: Int
}

struct NewsArticleReaderScreen: View {
    let article: NewsArticleItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @State private var paragraphs: [String] = []
    @State private var isLoadingContent = true
    @State private var fontSizeMultiplier: CGFloat = 1.0 // 0.9, 1.0, 1.2
    @State private var toastMessage: String?

    // Light Pick Word & Phrase Popover State
    @State private var selectedRange: SelectedArticleRange?
    @State private var isPopoverPresented = false
    @State private var sessionSavedWords: Set<String> = []
    @State private var analyzingParagraphText: String?

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord)).union(sessionSavedWords)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.Neutral.n50
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        articleHeaderSection

                        articleBodySection

                        originalArticleLinkSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }

                if let toastMessage {
                    toastBannerView(message: toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Báo tiếng Anh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    fontSizeMenu

                    ShareLink(item: URL(string: article.link) ?? URL(string: "https://bbc.com")!) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppTheme.Neutral.n700)
                    }
                }
            }
            .task {
                await loadArticleData()
            }
            .sheet(
                isPresented: Binding(
                    get: { analyzingParagraphText != nil },
                    set: { if !$0 { analyzingParagraphText = nil } }
                )
            ) {
                if let text = analyzingParagraphText {
                    NewsSentenceAnalysisSheetView(
                        initialText: text,
                        onOpenFullStructure: { targetSentence in
                            analyzingParagraphText = nil
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                StructureNavigationCoordinator.shared.openAndAnalyze(targetSentence)
                            }
                        },
                        onSaveWord: { word, _ in
                            sessionSavedWords.insert(word.normalizedVocabularyWord)
                            showToast("Đã lưu \"\(word)\" vào Sổ tay")
                        },
                        isWordSaved: { word in
                            savedVocabularyWords.contains(word.normalizedVocabularyWord)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Article Header Section

    private var articleHeaderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Source & Category & PubDate
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: article.category.iconName)
                        .font(.caption2)
                    Text(article.category.displayName)
                        .font(.caption.bold())
                }
                .foregroundStyle(AppTheme.Primary.p700)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.Primary.p50)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
                }

                Text(article.source)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n700)

                Text("•")
                    .foregroundStyle(AppTheme.Neutral.n400)

                Text(article.timeAgoDisplay)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)

                Spacer()
            }

            // Headline (Tap word or drag to select phrase)
            InteractiveArticleTextView(
                paragraphKey: "title",
                text: article.title,
                fontSize: 22 * fontSizeMultiplier,
                isTitle: true,
                savedWords: savedVocabularyWords,
                selectedRange: selectedRange,
                isPopoverPresented: $isPopoverPresented,
                onSelectRange: { startIdx, endIdx, showPopover in
                    updateSelection(paragraphKey: "title", startIndex: startIdx, endIndex: endIdx, presentPopover: showPopover)
                },
                onAdjustRange: { newStart, newEnd in
                    adjustSelection(paragraphKey: "title", startIndex: newStart, endIndex: newEnd)
                },
                onDismissPopover: {
                    clearSelection()
                },
                onWordSaved: { savedPhrase in
                    sessionSavedWords.insert(savedPhrase.normalizedVocabularyWord)
                    showToast("Đã lưu \"\(savedPhrase)\" vào Sổ tay")
                },
                onAnalyzeSentence: {
                    isPopoverPresented = false
                    selectedRange = nil
                    analyzingParagraphText = article.title
                }
            )

            // Hint Pill
            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Primary.p500)
                Text("Chạm vào từ hoặc kéo ngang qua nhiều từ để tra nghĩa cụm từ")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.Primary.p50.opacity(0.6))
            .clipShape(Capsule())

            // Hero Image
            if let imgURL = article.imageURL, let url = URL(string: imgURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
                            }
                    case .empty:
                        Rectangle()
                            .fill(AppTheme.Neutral.n100)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                ProgressView()
                            }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Article Body Section

    private var articleBodySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isLoadingContent {
                VStack(spacing: 12) {
                    AppThemeLoadingView(customSize: 26)
                    Text("Đang tải nội dung chính xác của bài báo...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if paragraphs.isEmpty {
                VStack(spacing: 10) {
                    Text("Không tìm thấy nội dung bài báo.")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n700)
                    Text("Bạn có thể mở bài viết gốc bằng liên kết bên dưới.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    let pKey = "p_\(index)"
                    InteractiveArticleTextView(
                        paragraphKey: pKey,
                        text: paragraph,
                        fontSize: 17 * fontSizeMultiplier,
                        isTitle: false,
                        savedWords: savedVocabularyWords,
                        selectedRange: selectedRange,
                        isPopoverPresented: $isPopoverPresented,
                        onSelectRange: { startIdx, endIdx, showPopover in
                            updateSelection(paragraphKey: pKey, startIndex: startIdx, endIndex: endIdx, presentPopover: showPopover)
                        },
                        onAdjustRange: { newStart, newEnd in
                            adjustSelection(paragraphKey: pKey, startIndex: newStart, endIndex: newEnd)
                        },
                        onDismissPopover: {
                            clearSelection()
                        },
                        onWordSaved: { savedPhrase in
                            sessionSavedWords.insert(savedPhrase.normalizedVocabularyWord)
                            showToast("Đã lưu \"\(savedPhrase)\" vào Sổ tay")
                        },
                        onAnalyzeSentence: {
                            isPopoverPresented = false
                            selectedRange = nil
                            analyzingParagraphText = paragraph
                        }
                    )
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Original Article Link

    private var originalArticleLinkSection: some View {
        VStack(spacing: 8) {
            if let url = URL(string: article.link) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Mở bài viết đầy đủ tại \(article.source)")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Primary.p500)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Font Size Menu

    private var fontSizeMenu: some View {
        Menu {
            Button("Cỡ chữ nhỏ (90%)") {
                withAnimation { fontSizeMultiplier = 0.9 }
            }
            Button("Cỡ chữ chuẩn (100%)") {
                withAnimation { fontSizeMultiplier = 1.0 }
            }
            Button("Cỡ chữ lớn (120%)") {
                withAnimation { fontSizeMultiplier = 1.2 }
            }
        } label: {
            Image(systemName: "textformat.size")
                .foregroundStyle(AppTheme.Neutral.n700)
        }
    }

    // MARK: - Actions & Logic

    private func loadArticleData() async {
        isLoadingContent = true
        let content = await EnglishNewsService.shared.fetchArticleContent(for: article)
        await MainActor.run {
            self.paragraphs = content
            self.isLoadingContent = false
        }
    }

    private func updateSelection(paragraphKey: String, startIndex: Int, endIndex: Int, presentPopover: Bool) {
        let anchor = (startIndex + endIndex) / 2
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.82)) {
            if !presentPopover {
                isPopoverPresented = false
            }
            selectedRange = SelectedArticleRange(
                paragraphKey: paragraphKey,
                startIndex: startIndex,
                endIndex: endIndex,
                anchorIndex: anchor
            )
            if presentPopover {
                isPopoverPresented = true
            }
        }
    }

    private func adjustSelection(paragraphKey: String, startIndex: Int, endIndex: Int) {
        guard var current = selectedRange, current.paragraphKey == paragraphKey else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
            current.startIndex = startIndex
            current.endIndex = endIndex
            selectedRange = current
        }
    }

    private func clearSelection() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPopoverPresented = false
            selectedRange = nil
        }
    }

    // MARK: - Toast Banner & Helpers

    private func toastBannerView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.Semantic.success)
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
        .padding(.bottom, 20)
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Interactive Article Text View (Light Pick Word & Drag Phrase Selection)

struct InteractiveArticleTextView: View {
    let paragraphKey: String
    let text: String
    let fontSize: CGFloat
    let isTitle: Bool
    let savedWords: Set<String>
    let selectedRange: SelectedArticleRange?
    @Binding var isPopoverPresented: Bool
    let onSelectRange: (Int, Int, Bool) -> Void
    let onAdjustRange: (Int, Int) -> Void
    let onDismissPopover: () -> Void
    let onWordSaved: (String) -> Void
    let onAnalyzeSentence: () -> Void

    @State private var wordFrames: [Int: CGRect] = [:]

    private var words: [(index: Int, display: String, normalized: String)] {
        text.split(whereSeparator: \.isWhitespace).enumerated().map { (idx, raw) in
            let str = String(raw)
            return (index: idx, display: str, normalized: str.normalizedVocabularyWord)
        }
    }

    private var coordSpaceName: String {
        "article_coord_\(paragraphKey)"
    }

    private var selectedPhraseText: String {
        guard let r = selectedRange,
              r.paragraphKey == paragraphKey,
              r.startIndex >= 0,
              r.endIndex < words.count,
              r.startIndex <= r.endIndex else {
            return ""
        }
        let raw = words[r.startIndex...r.endIndex].map(\.display).joined(separator: " ")
        let clean = raw.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return clean.isEmpty ? raw : clean
    }

    var body: some View {
        WordPickerFlowLayout(spacing: isTitle ? 6 : 4, lineSpacing: isTitle ? 8 : 6) {
            ForEach(words, id: \.index) { item in
                let isSaved = !item.normalized.isEmpty && savedWords.contains(item.normalized)
                let isSelected = checkIfSelected(itemIndex: item.index)
                let isAnchor = checkIfAnchor(itemIndex: item.index)

                ArticleWordTokenView(
                    display: item.display,
                    fontSize: fontSize,
                    isTitle: isTitle,
                    isSaved: isSaved,
                    isSelected: isSelected
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WordTokenFramePreferenceKey.self,
                            value: [item.index: proxy.frame(in: .named(coordSpaceName))]
                        )
                    }
                )
                .popover(
                    isPresented: Binding(
                        get: { isPopoverPresented && isAnchor },
                        set: { presented in
                            if !presented && isAnchor {
                                onDismissPopover()
                            }
                        }
                    ),
                    attachmentAnchor: .rect(.bounds)
                ) {
                    let phrase = selectedPhraseText
                    let normPhrase = phrase.normalizedVocabularyWord
                    let isAlreadySaved = savedWords.contains(normPhrase)
                    let currentStart = selectedRange?.startIndex ?? item.index
                    let currentEnd = selectedRange?.endIndex ?? item.index

                    QuickWordLookupPopoverView(
                        word: phrase.isEmpty ? item.display : phrase,
                        sentence: text,
                        isAlreadySaved: isAlreadySaved,
                        onSaveWord: {
                            onWordSaved(phrase.isEmpty ? item.display : phrase)
                        },
                        onAnalyzeFullSentence: {
                            onAnalyzeSentence()
                        },
                        canExpandBefore: currentStart > 0,
                        canExpandAfter: currentEnd < words.count - 1,
                        canShrinkBefore: currentStart < currentEnd,
                        canShrinkAfter: currentEnd > currentStart,
                        onExpandBefore: {
                            if currentStart > 0 {
                                onAdjustRange(currentStart - 1, currentEnd)
                            }
                        },
                        onExpandAfter: {
                            if currentEnd < words.count - 1 {
                                onAdjustRange(currentStart, currentEnd + 1)
                            }
                        },
                        onShrinkBefore: {
                            if currentStart < currentEnd {
                                onAdjustRange(currentStart + 1, currentEnd)
                            }
                        },
                        onShrinkAfter: {
                            if currentEnd > currentStart {
                                onAdjustRange(currentStart, currentEnd - 1)
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
                    guard idx >= 0 && idx < words.count else { return }
                    onSelectRange(idx, idx, true)
                },
                onDragRangeChanged: { startIdx, endIdx in
                    guard startIdx >= 0 && endIdx < words.count else { return }
                    onSelectRange(startIdx, endIdx, false)
                },
                onDragRangeEnded: { startIdx, endIdx in
                    guard startIdx >= 0 && endIdx < words.count else { return }
                    onSelectRange(startIdx, endIdx, true)
                }
            )
        }
    }

    private func checkIfSelected(itemIndex: Int) -> Bool {
        guard let r = selectedRange, r.paragraphKey == paragraphKey else { return false }
        return itemIndex >= r.startIndex && itemIndex <= r.endIndex
    }

    private func checkIfAnchor(itemIndex: Int) -> Bool {
        guard let r = selectedRange, r.paragraphKey == paragraphKey else { return false }
        return itemIndex == r.anchorIndex
    }
}

struct ArticleWordTokenView: View {
    let display: String
    let fontSize: CGFloat
    let isTitle: Bool
    let isSaved: Bool
    let isSelected: Bool

    private var textColor: Color {
        if isSelected { return AppTheme.Primary.p700 }
        if isSaved { return AppTheme.Semantic.success }
        return AppTheme.Neutral.n900
    }

    private var fontWeight: Font.Weight {
        (isTitle || isSelected) ? .bold : .regular
    }

    var body: some View {
        Text(display)
            .font(.system(size: fontSize, weight: fontWeight, design: .serif))
            .foregroundStyle(textColor)
            .padding(.vertical, 2)
            .padding(.horizontal, isSelected ? 4 : 1)
            .background(
                isSelected
                ? AppTheme.Primary.p100
                : (isSaved ? AppTheme.Semantic.success.opacity(0.1) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) {
                if isSelected || isSaved {
                    Rectangle()
                        .fill(isSelected ? AppTheme.Primary.p500 : AppTheme.Semantic.success.opacity(0.6))
                        .frame(height: isSelected ? 2 : 1)
                }
            }
    }
}
