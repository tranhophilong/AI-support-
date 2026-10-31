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
    @ObservedObject private var speechManager = SpeechSynthesizerManager.shared

    @State private var paragraphs: [String] = []
    @State private var isLoadingContent = true
    @State private var aiSummary: NewsAISummary?
    @State private var isLoadingSummary = false
    @State private var showSummaryCard = true
    @State private var fontSizeMultiplier: CGFloat = 1.0 // 0.9, 1.0, 1.15

    // Word Lookup & Sentence Analysis Popovers
    @State private var selectedWord: String?
    @State private var selectedWordContext: String?
    @State private var wordLookupResult: AIVocabularyLookupResponse?
    @State private var isLoadingWordLookup = false
    @State private var showWordLookupSheet = false

    @State private var selectedSentenceForAnalysis: String?
    @State private var showSentenceAnalysisSheet = false

    // TTS Audio state
    @State private var isPlayingAudio = false
    @State private var currentAudioParagraphIndex: Int = 0
    @State private var speechRate: Float = 1.0 // 0.8, 1.0, 1.2

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.Neutral.n50
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        articleHeaderSection

                        if isLoadingSummary {
                            summaryLoadingView
                        } else if let summary = aiSummary, showSummaryCard {
                            aiSummaryCardView(summary)
                        }

                        articleBodySection

                        originalArticleLinkSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 100) // Space for audio player bar
                }

                if isPlayingAudio || speechManager.speakingText != nil {
                    audioPlayerBottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Reader Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        stopAudio()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    fontSizeMenu

                    Button {
                        if isPlayingAudio {
                            stopAudio()
                        } else {
                            startAudioReading()
                        }
                    } label: {
                        Image(systemName: isPlayingAudio ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .foregroundStyle(isPlayingAudio ? AppTheme.Primary.p500 : AppTheme.Neutral.n700)
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
            .onDisappear {
                stopAudio()
            }
            .sheet(isPresented: $showWordLookupSheet) {
                wordLookupSheetView
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSentenceAnalysisSheet) {
                if let sentence = selectedSentenceForAnalysis {
                    NavigationStack {
                        QuickSentenceAnalysisPopoverView(
                            sentence: sentence,
                            onOpenFullAnalysis: {
                                showSentenceAnalysisSheet = false
                            }
                        )
                        .navigationTitle("Phân tích cấu trúc câu")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Đóng") {
                                    showSentenceAnalysisSheet = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - Article Header Section

    private var articleHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            // Headline
            Text(article.title)
                .font(.system(size: 24 * fontSizeMultiplier, weight: .bold, design: .serif))
                .foregroundStyle(AppTheme.Neutral.n900)
                .lineSpacing(4)

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

    // MARK: - AI Summary Card

    private func aiSummaryCardView(_ summary: NewsAISummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppTheme.Accent.a600)
                    Text("Tóm tắt ý chính & Từ vựng AI")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                Spacer()

                Text("Cấp độ: \(summary.cefrLevel)")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Primary.p700)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.Primary.p100)
                    .clipShape(Capsule())

                Button {
                    withAnimation {
                        showSummaryCard = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
            }

            Divider()

            // 3 Takeaways (English + Vietnamese)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(summary.englishTakeaways.indices), id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Primary.p500)

                            Text(summary.englishTakeaways[idx])
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.Neutral.n900)
                        }

                        if idx < summary.vietnameseTakeaways.count {
                            Text(summary.vietnameseTakeaways[idx])
                                .font(.caption)
                                .italic()
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .padding(.leading, 14)
                        }
                    }
                }
            }

            // Key vocabulary chips
            if !summary.keyVocabulary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Từ vựng trọng tâm trong bài:")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Neutral.n700)
                        .padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(summary.keyVocabulary) { vocab in
                                Button {
                                    lookupWordDirectly(vocab.word, contextSentence: vocab.contextExplanation)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(vocab.word)
                                            .font(.caption.bold())
                                            .foregroundStyle(AppTheme.Primary.p700)
                                        Text(vocab.phonetic)
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                        Text("• \(vocab.vietnameseMeaning)")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.Primary.p50)
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Accent.a500.opacity(0.4), lineWidth: 0.5)
        }
        .shadow(color: AppTheme.Neutral.n900.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    private var summaryLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("AI đang tổng hợp ý chính và từ vựng của bài viết...")
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n500)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
        }
    }

    // MARK: - Article Body Section

    private var articleBodySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isLoadingContent {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang bóc tách nội dung bài viết sạch...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    paragraphCardView(index: index, paragraph: paragraph)
                }
            }
        }
    }

    private func paragraphCardView(index: Int, paragraph: String) -> some View {
        let isHighlighted = isPlayingAudio && currentAudioParagraphIndex == index

        return VStack(alignment: .leading, spacing: 8) {
            Text(paragraph)
                .font(.system(size: 17 * fontSizeMultiplier, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.Neutral.n900)
                .lineSpacing(6 * fontSizeMultiplier)
                .textSelection(.enabled)

            // Paragraph helper actions
            HStack(spacing: 12) {
                Button {
                    playSingleParagraphAudio(paragraph, index: index)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.1.fill")
                            .font(.caption2)
                        Text("Nghe")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(AppTheme.Neutral.n700)
                }

                Button {
                    selectedSentenceForAnalysis = paragraph
                    showSentenceAnalysisSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.caption2)
                        Text("Phân tích ngữ pháp")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(AppTheme.Primary.p500)
                }

                Button {
                    inspectWordsInParagraph(paragraph)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "character.book.closed.fill")
                            .font(.caption2)
                        Text("Tra từ vựng")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(isHighlighted ? AppTheme.Primary.p50 : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHighlighted ? AppTheme.Primary.p500 : AppTheme.Neutral.n200, lineWidth: 0.5)
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

    // MARK: - Floating Audio Player Bar

    private var audioPlayerBottomBar: some View {
        HStack(spacing: 14) {
            Button {
                togglePlayPauseAudio()
            } label: {
                Image(systemName: (speechManager.speakingText != nil) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.Primary.p500)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text("Đoạn \(currentAudioParagraphIndex + 1) / \(max(1, paragraphs.count))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            Spacer()

            // Speed toggle
            Button {
                cycleSpeechRate()
            } label: {
                Text(String(format: "%.1fx", speechRate))
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Neutral.n100)
                    .clipShape(Capsule())
            }

            Button {
                stopAudio()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .padding(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Neutral.n200, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                        ProgressView()
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
            .padding(16)
            .navigationTitle("Tra từ vựng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") {
                        showWordLookupSheet = false
                    }
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
        // 1. Fetch clean article content
        isLoadingContent = true
        let content = await EnglishNewsService.shared.fetchArticleContent(for: article)
        await MainActor.run {
            self.paragraphs = content
            self.isLoadingContent = false
        }

        // 2. Fetch AI summary in background
        isLoadingSummary = true
        let fullText = content.joined(separator: "\n\n")
        do {
            let summary = try await EnglishNewsService.shared.generateAISummary(
                title: article.title,
                content: fullText
            )
            await MainActor.run {
                self.aiSummary = summary
                self.isLoadingSummary = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingSummary = false
            }
        }
    }

    private func lookupWordDirectly(_ word: String, contextSentence: String?) {
        selectedWord = word
        selectedWordContext = contextSentence
        showWordLookupSheet = true
        isLoadingWordLookup = true
        wordLookupResult = nil

        Task {
            do {
                let service = VocabularyAIService()
                let result = try await service.lookupWord(
                    word: word,
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

    private func inspectWordsInParagraph(_ paragraph: String) {
        // Extract words from paragraph to let user pick one
        let words = paragraph
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }

        if let first = words.first {
            lookupWordDirectly(first, contextSentence: paragraph)
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
        } catch {
            // Handled
        }
    }

    // MARK: - TTS Audio Reading

    private func startAudioReading() {
        guard !paragraphs.isEmpty else { return }
        isPlayingAudio = true
        currentAudioParagraphIndex = 0
        readParagraphAtIndex(0)
    }

    private func readParagraphAtIndex(_ index: Int) {
        guard index < paragraphs.count else {
            isPlayingAudio = false
            return
        }
        currentAudioParagraphIndex = index
        let paragraph = paragraphs[index]

        speechManager.speakWithCallback(paragraph, rateMultiplier: speechRate) {
            if isPlayingAudio && currentAudioParagraphIndex == index {
                readParagraphAtIndex(index + 1)
            }
        }
    }

    private func playSingleParagraphAudio(_ text: String, index: Int) {
        isPlayingAudio = true
        currentAudioParagraphIndex = index
        speechManager.speakWithCallback(text, rateMultiplier: speechRate) {
            isPlayingAudio = false
        }
    }

    private func togglePlayPauseAudio() {
        if speechManager.speakingText != nil {
            speechManager.stop()
            isPlayingAudio = false
        } else {
            isPlayingAudio = true
            readParagraphAtIndex(currentAudioParagraphIndex)
        }
    }

    private func cycleSpeechRate() {
        if speechRate < 1.0 {
            speechRate = 1.0
        } else if speechRate < 1.2 {
            speechRate = 1.2
        } else {
            speechRate = 0.8
        }
    }

    private func stopAudio() {
        speechManager.stop()
        isPlayingAudio = false
    }
}
