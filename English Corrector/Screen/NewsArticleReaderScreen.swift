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
}

struct NewsArticleReaderScreen: View {
    let article: NewsArticleItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyNotes: [VocabularyNoteModel]
    @ObservedObject private var speechManager = SpeechSynthesizerManager.shared

    @State private var paragraphs: [String] = []
    @State private var isLoadingContent = true
    @State private var fontSizeMultiplier: CGFloat = 1.0 // 0.9, 1.0, 1.2
    @State private var toastMessage: String?

    // Phrase & Word Selection State
    @State private var selectedRange: SelectedArticleRange?
    @State private var selectedWord: String?
    @State private var selectedWordContext: String?
    @State private var wordLookupResult: AIVocabularyLookupResponse?
    @State private var isLoadingWordLookup = false
    @State private var showWordLookupSidePanel = false
    @State private var isSidePanelExpanded = false

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let isCompact = totalWidth < 600

                // Responsive side panel width
                let sidePanelWidth: CGFloat = {
                    if !showWordLookupSidePanel { return 0 }
                    if isCompact {
                        return isSidePanelExpanded
                            ? min(totalWidth * 0.75, 340)
                            : min(totalWidth * 0.52, 250)
                    } else {
                        return isSidePanelExpanded
                            ? min(totalWidth * 0.50, 480)
                            : min(totalWidth * 0.38, 380)
                    }
                }()

                ZStack(alignment: .bottom) {
                    AppTheme.Neutral.n50
                        .ignoresSafeArea()

                    HStack(spacing: 0) {
                        // 1. Article Content (Left Column)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                articleHeaderSection

                                articleBodySection

                                originalArticleLinkSection
                            }
                            .padding(.horizontal, showWordLookupSidePanel ? 12 : 18)
                            .padding(.top, 14)
                            .padding(.bottom, 40)
                        }
                        .frame(maxWidth: .infinity)

                        // 2. Side-by-side Word / Phrase Lookup Inspector (Right Column)
                        if showWordLookupSidePanel {
                            Rectangle()
                                .fill(AppTheme.Neutral.n200)
                                .frame(width: 1)
                                .ignoresSafeArea(edges: .bottom)

                            wordLookupSidePanelView
                                .frame(width: sidePanelWidth)
                                .background(AppTheme.Surface.card)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }

                    if let toastMessage {
                        toastBannerView(message: toastMessage)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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

                    if showWordLookupSidePanel {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                isSidePanelExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isSidePanelExpanded ? "sidebar.right" : "sidebar.trailing")
                                .foregroundStyle(AppTheme.Primary.p500)
                        }
                    }

                    ShareLink(item: URL(string: article.link) ?? URL(string: "https://bbc.com")!) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppTheme.Neutral.n700)
                    }
                }
            }
            .task {
                await loadArticleData()
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

            // Headline (Tap word or select phrase)
            InteractiveArticleTextView(
                paragraphKey: "title",
                text: article.title,
                fontSize: 22 * fontSizeMultiplier,
                isTitle: true,
                savedWords: savedVocabularyWords,
                selectedRange: selectedRange,
                onWordTapped: { index in
                    handleWordTapped(paragraphKey: "title", wordIndex: index)
                }
            )

            // Hint Pill
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Primary.p500)
                Text("Chạm vào từ hoặc chạm 2 từ để chọn cụm từ tra cứu")
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
                            .frame(height: showWordLookupSidePanel ? 160 : 210)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
                            }
                    case .empty:
                        Rectangle()
                            .fill(AppTheme.Neutral.n100)
                            .frame(height: 160)
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
                        onWordTapped: { wordIndex in
                            handleWordTapped(paragraphKey: pKey, wordIndex: wordIndex)
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

    // MARK: - Word & Phrase Lookup Side Panel View (Side-by-side)

    private var wordLookupSidePanelView: some View {
        VStack(spacing: 0) {
            // Panel Header
            sidePanelHeaderView

            // Phrase Expansion Quick Toolbar
            if let range = selectedRange {
                phraseAdjustmentToolbar(range: range)
            }

            Divider()
                .overlay(AppTheme.Neutral.n200)

            // Panel Body (Scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoadingWordLookup {
                        VStack(spacing: 12) {
                            AppThemeLoadingView(customSize: 22)
                            Text("Đang tra cứu từ & cụm từ...")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let lookup = wordLookupResult {
                        sidePanelDetailCard(lookup)
                    } else if let phrase = selectedWord {
                        VStack(spacing: 10) {
                            Text(phrase)
                                .font(.headline.bold())
                                .foregroundStyle(AppTheme.Neutral.n900)
                            Text("Không tìm thấy kết quả từ điển cho cụm từ này.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
    }

    private var sidePanelHeaderView: some View {
        HStack {
            let isPhrase = (selectedRange?.startIndex != selectedRange?.endIndex)
            HStack(spacing: 4) {
                Image(systemName: isPhrase ? "text.word.spacing" : "character.book.closed.fill")
                    .font(.caption2)
                Text(isPhrase ? "Cụm từ" : "Từ vựng")
                    .font(.caption2.bold())
            }
            .foregroundStyle(AppTheme.Primary.p700)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.Primary.p50)
            .clipShape(Capsule())

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isSidePanelExpanded.toggle()
                }
            } label: {
                Image(systemName: isSidePanelExpanded ? "arrow.right.to.line" : "arrow.left.to.line")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding(6)
                    .background(AppTheme.Neutral.n100)
                    .clipShape(Circle())
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showWordLookupSidePanel = false
                    selectedRange = nil
                    selectedWord = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding(6)
                    .background(AppTheme.Neutral.n100)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func phraseAdjustmentToolbar(range: SelectedArticleRange) -> some View {
        let words = wordsIn(paragraphKey: range.paragraphKey)
        let canExpandBefore = range.startIndex > 0
        let canExpandAfter = range.endIndex < words.count - 1
        let canShrinkBefore = range.startIndex < range.endIndex
        let canShrinkAfter = range.endIndex > range.startIndex
        let wordCount = range.endIndex - range.startIndex + 1

        return HStack(spacing: 4) {
            // Add word before
            Button {
                expandSelectedPhrase(before: true)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(canExpandBefore ? AppTheme.Primary.p50 : AppTheme.Neutral.n100)
                .foregroundStyle(canExpandBefore ? AppTheme.Primary.p700 : AppTheme.Neutral.n400)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(!canExpandBefore)

            // Shrink word before
            if canShrinkBefore {
                Button {
                    shrinkSelectedPhrase(before: true)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(AppTheme.Neutral.n100)
                        .foregroundStyle(AppTheme.Neutral.n700)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Spacer()

            Text("\(wordCount) từ")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.Neutral.n500)

            Spacer()

            // Shrink word after
            if canShrinkAfter {
                Button {
                    shrinkSelectedPhrase(before: false)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(AppTheme.Neutral.n100)
                        .foregroundStyle(AppTheme.Neutral.n700)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Add word after
            Button {
                expandSelectedPhrase(before: false)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(canExpandAfter ? AppTheme.Primary.p50 : AppTheme.Neutral.n100)
                .foregroundStyle(canExpandAfter ? AppTheme.Primary.p700 : AppTheme.Neutral.n400)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(!canExpandAfter)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.Neutral.n50)
    }

    private func sidePanelDetailCard(_ lookup: AIVocabularyLookupResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Target Word & Speech & Bookmark
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(lookup.word)
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            speechManager.speak(lookup.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.Primary.p500)
                                .padding(6)
                                .background(AppTheme.Primary.p50)
                                .clipShape(Circle())
                        }

                        Button {
                            saveWordToNotebook(lookup)
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.Accent.a600)
                                .padding(6)
                                .background(AppTheme.Accent.a50)
                                .clipShape(Circle())
                        }
                    }
                }

                HStack(spacing: 6) {
                    if !lookup.phonetic.isEmpty {
                        Text(lookup.phonetic)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }

                    if !lookup.partOfSpeech.isEmpty {
                        Text(lookup.partOfSpeech)
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Primary.p700)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                    }
                }
            }

            // Vietnamese Meaning Card
            VStack(alignment: .leading, spacing: 3) {
                Text("NGHĨA TIẾNG VIỆT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p500)

                Text(lookup.vietnameseMeaning)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Primary.p700)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Primary.p50.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // English Definition
            if !lookup.englishDefinition.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ĐỊNH NGHĨA TIẾNG ANH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                    Text(lookup.englishDefinition)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n700)
                }
            }

            // Example Sentence
            if !lookup.exampleSentence.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VÍ DỤ TRONG CÂU")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                    Text(lookup.exampleSentence)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n700)
                }
                .padding(8)
                .background(AppTheme.Neutral.n100.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Synonyms
            if !lookup.synonyms.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TỪ & CỤM TỪ TƯƠNG ĐƯƠNG")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n500)

                    FlowTagLayout(spacing: 4) {
                        ForEach(lookup.synonyms, id: \.self) { syn in
                            Text(syn)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.Neutral.n100)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
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

    private func wordsIn(paragraphKey: String) -> [String] {
        if paragraphKey == "title" {
            return article.title.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        if paragraphKey.hasPrefix("p_"),
           let idx = Int(paragraphKey.dropFirst(2)),
           idx >= 0 && idx < paragraphs.count {
            return paragraphs[idx].split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return []
    }

    private func handleWordTapped(paragraphKey: String, wordIndex: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if var current = selectedRange, current.paragraphKey == paragraphKey {
            if current.startIndex == current.endIndex && current.startIndex == wordIndex {
                // Tapped same word -> refresh lookup
                applyNewRange(current)
                return
            }
            if wordIndex >= current.startIndex && wordIndex <= current.endIndex {
                // Tapped inside selected range -> isolate tapped word
                current.startIndex = wordIndex
                current.endIndex = wordIndex
                applyNewRange(current)
                return
            }
            // Tapped outside -> extend range to include this word
            if wordIndex < current.startIndex {
                current.startIndex = wordIndex
            } else if wordIndex > current.endIndex {
                current.endIndex = wordIndex
            }
            applyNewRange(current)
        } else {
            // New single word selected
            let newRange = SelectedArticleRange(paragraphKey: paragraphKey, startIndex: wordIndex, endIndex: wordIndex)
            applyNewRange(newRange)
        }
    }

    private func expandSelectedPhrase(before: Bool) {
        guard var range = selectedRange else { return }
        let words = wordsIn(paragraphKey: range.paragraphKey)
        if before {
            if range.startIndex > 0 {
                range.startIndex -= 1
            }
        } else {
            if range.endIndex < words.count - 1 {
                range.endIndex += 1
            }
        }
        applyNewRange(range)
    }

    private func shrinkSelectedPhrase(before: Bool) {
        guard var range = selectedRange else { return }
        if before {
            if range.startIndex < range.endIndex {
                range.startIndex += 1
            }
        } else {
            if range.endIndex > range.startIndex {
                range.endIndex -= 1
            }
        }
        applyNewRange(range)
    }

    private func applyNewRange(_ range: SelectedArticleRange) {
        let words = wordsIn(paragraphKey: range.paragraphKey)
        guard range.startIndex >= 0, range.endIndex < words.count, range.startIndex <= range.endIndex else { return }

        let slice = words[range.startIndex...range.endIndex]
        let phrase = slice.joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))

        guard !phrase.isEmpty else { return }

        let contextText: String
        if range.paragraphKey == "title" {
            contextText = article.title
        } else if let idx = Int(range.paragraphKey.dropFirst(2)), idx < paragraphs.count {
            contextText = paragraphs[idx]
        } else {
            contextText = phrase
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            self.selectedRange = range
            self.selectedWord = phrase
            self.selectedWordContext = contextText
            self.showWordLookupSidePanel = true
        }

        lookupPhraseDirectly(phrase, contextSentence: contextText)
    }

    private func lookupPhraseDirectly(_ phrase: String, contextSentence: String?) {
        isLoadingWordLookup = true
        wordLookupResult = nil

        Task {
            do {
                let service = VocabularyAIService()
                let result = try await service.lookupWord(
                    word: phrase,
                    context: contextSentence
                )
                await MainActor.run {
                    self.wordLookupResult = result
                    self.isLoadingWordLookup = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingWordLookup = false
                }
            }
        }
    }

    private func saveWordToNotebook(_ lookup: AIVocabularyLookupResponse) {
        do {
            _ = try VocabularyNoteStore.saveLookupResult(
                word: lookup.word,
                lookup: lookup,
                sourceText: selectedWordContext,
                in: modelContext
            )
            showToast("Đã lưu \"\(lookup.word)\" vào Sổ tay")
        } catch {
            print("DEBUG: Failed to save vocabulary: \(error)")
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

// MARK: - Interactive Article Text View (Word & Phrase Selection)

struct InteractiveArticleTextView: View {
    let paragraphKey: String
    let text: String
    let fontSize: CGFloat
    let isTitle: Bool
    let savedWords: Set<String>
    let selectedRange: SelectedArticleRange?
    let onWordTapped: (Int) -> Void

    private var words: [(index: Int, display: String, normalized: String)] {
        text.split(whereSeparator: \.isWhitespace).enumerated().map { (idx, raw) in
            let str = String(raw)
            return (index: idx, display: str, normalized: str.normalizedVocabularyWord)
        }
    }

    var body: some View {
        WordPickerFlowLayout(spacing: isTitle ? 6 : 4, lineSpacing: isTitle ? 8 : 6) {
            ForEach(words, id: \.index) { item in
                let isSaved = !item.normalized.isEmpty && savedWords.contains(item.normalized)
                let isSelected = checkIfSelected(itemIndex: item.index)

                ArticleWordTokenView(
                    display: item.display,
                    fontSize: fontSize,
                    isTitle: isTitle,
                    isSaved: isSaved,
                    isSelected: isSelected,
                    action: { onWordTapped(item.index) }
                )
            }
        }
    }

    private func checkIfSelected(itemIndex: Int) -> Bool {
        guard let r = selectedRange, r.paragraphKey == paragraphKey else { return false }
        return itemIndex >= r.startIndex && itemIndex <= r.endIndex
    }
}

struct ArticleWordTokenView: View {
    let display: String
    let fontSize: CGFloat
    let isTitle: Bool
    let isSaved: Bool
    let isSelected: Bool
    let action: () -> Void

    private var textColor: Color {
        if isSelected { return AppTheme.Primary.p700 }
        if isSaved { return AppTheme.Semantic.success }
        return AppTheme.Neutral.n900
    }

    private var fontWeight: Font.Weight {
        (isTitle || isSelected) ? .bold : .regular
    }

    var body: some View {
        Button(action: action) {
            Text(display)
                .font(.system(size: fontSize, weight: fontWeight, design: .serif))
                .foregroundStyle(textColor)
                .padding(.vertical, 2)
                .padding(.horizontal, isSelected ? 4 : 1)
                .background(isSelected ? AppTheme.Primary.p100 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(AppTheme.Primary.p300, lineWidth: 1)
                    }
                }
                .underline(!isSelected && isSaved, color: AppTheme.Semantic.success.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowTagLayout Helper for Synonyms

struct FlowTagLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }

        return CGSize(width: width, height: currentY + maxHeightInRow)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            maxHeightInRow = max(maxHeightInRow, size.height)
        }
    }
}
