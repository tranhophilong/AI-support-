//
//  NewsArticleReaderScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

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

    // Word Lookup Popover & Sheet
    @State private var selectedWord: String?
    @State private var selectedWordContext: String?
    @State private var wordLookupResult: AIVocabularyLookupResponse?
    @State private var isLoadingWordLookup = false
    @State private var showWordLookupSheet = false

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
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
            .sheet(isPresented: $showWordLookupSheet) {
                wordLookupSheetView
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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

            // Headline (Tap any word to look up)
            InteractiveArticleTextView(
                text: article.title,
                fontSize: 22 * fontSizeMultiplier,
                isTitle: true,
                savedWords: savedVocabularyWords,
                onLookupWord: { word in
                    lookupWordDirectly(word, contextSentence: article.title)
                }
            )

            // Hint Pill
            HStack(spacing: 5) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Primary.p500)
                Text("Chạm vào từ bất kỳ để tra nghĩa & lưu từ vựng")
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
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    InteractiveArticleTextView(
                        text: paragraph,
                        fontSize: 17 * fontSizeMultiplier,
                        isTitle: false,
                        savedWords: savedVocabularyWords,
                        onLookupWord: { word in
                            lookupWordDirectly(word, contextSentence: paragraph)
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

    // MARK: - Word Lookup Sheet View

    private var wordLookupSheetView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoadingWordLookup {
                    VStack(spacing: 12) {
                        AppThemeLoadingView(customSize: 24)
                        Text("Đang tra từ vựng...")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let lookup = wordLookupResult {
                    wordDetailCard(lookup)
                } else if let word = selectedWord {
                    VStack(spacing: 12) {
                        Text(word)
                            .font(.title2.bold())
                        Text("Không tìm thấy kết quả từ điển cho từ này.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
            .navigationTitle("Tra từ vựng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") {
                        showWordLookupSheet = false
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                }
            }
        }
    }

    private func wordDetailCard(_ lookup: AIVocabularyLookupResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(lookup.word)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.Neutral.n900)

                        if !lookup.phonetic.isEmpty {
                            Text(lookup.phonetic)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }

                        Text(lookup.partOfSpeech)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Primary.p700)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                    }

                    Text(lookup.vietnameseMeaning)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Primary.p500)
                }

                Spacer()

                Button {
                    speechManager.speak(lookup.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(8)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Circle())
                }

                Button {
                    saveWordToNotebook(lookup)
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.Accent.a600)
                        .padding(8)
                        .background(AppTheme.Accent.a50)
                        .clipShape(Circle())
                }
            }

            if !lookup.englishDefinition.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Định nghĩa tiếng Anh:")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Neutral.n500)
                    Text(lookup.englishDefinition)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n900)
                }
            }

            if !lookup.exampleSentence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ví dụ trong ngữ cảnh:")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Neutral.n500)
                    Text(lookup.exampleSentence)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n700)
                }
            }

            Spacer()
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

    private func lookupWordDirectly(_ word: String, contextSentence: String?) {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        selectedWord = cleaned
        selectedWordContext = contextSentence
        showWordLookupSheet = true
        isLoadingWordLookup = true
        wordLookupResult = nil

        Task {
            do {
                let service = VocabularyAIService()
                let result = try await service.lookupWord(
                    word: cleaned,
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

// MARK: - Interactive Article Text View (Tap to look up word)

struct InteractiveArticleTextView: View {
    let text: String
    let fontSize: CGFloat
    let isTitle: Bool
    let savedWords: Set<String>
    let onLookupWord: (String) -> Void

    private var words: [(display: String, normalized: String)] {
        text.split(whereSeparator: \.isWhitespace).map { raw in
            let str = String(raw)
            return (display: str, normalized: str.normalizedVocabularyWord)
        }
    }

    var body: some View {
        WordPickerFlowLayout(spacing: isTitle ? 6 : 4, lineSpacing: isTitle ? 8 : 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, item in
                let isSaved = !item.normalized.isEmpty && savedWords.contains(item.normalized)

                Button {
                    guard !item.normalized.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onLookupWord(item.normalized)
                } label: {
                    Text(item.display)
                        .font(
                            .system(
                                size: fontSize,
                                weight: isTitle ? .bold : .regular,
                                design: .serif
                            )
                        )
                        .foregroundStyle(isSaved ? AppTheme.Semantic.success : AppTheme.Neutral.n900)
                        .underline(isSaved, color: AppTheme.Semantic.success.opacity(0.55))
                        .padding(.vertical, 1)
                        .padding(.horizontal, 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
