//
//  NewsArticleReaderScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

struct NewsWordPickTarget: Hashable, Equatable {
    let sectionID: String
    var mode: WordInteractionMode = .pickWord
}

struct NewsArticleReaderScreen: View {
    let article: NewsArticleItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularyNotes: [VocabularyNoteModel]
    @ObservedObject private var speechManager = SpeechSynthesizerManager.shared

    @State private var paragraphs: [String] = []
    @State private var isLoadingContent = true
    @State private var aiSummary: NewsAISummary?
    @State private var isLoadingSummary = false
    @State private var showSummaryCard = true
    @State private var fontSizeMultiplier: CGFloat = 1.0 // 0.9, 1.0, 1.15

    // Word Pick & Interaction State
    @State private var pickingTarget: NewsWordPickTarget?
    @State private var toastMessage: String?

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

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

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

                if let toastMessage {
                    toastBannerView(message: toastMessage)
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
                                openSentenceStructureAnalysis(for: sentence)
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
            let headlineSectionID = "headline"
            let isPickingHeadline = pickingTarget?.sectionID == headlineSectionID
            let activeHeadlineMode = isPickingHeadline ? pickingTarget?.mode : nil

            VStack(alignment: .leading, spacing: 8) {
                if let activeMode = activeHeadlineMode {
                    WordPickerText(
                        text: article.title,
                        mode: activeMode,
                        foregroundStyle: AppTheme.Neutral.n900,
                        chipBackground: AppTheme.Surface.card,
                        modeBackground: AppTheme.Accent.a50,
                        savedWords: savedVocabularyWords,
                        onPick: { word in
                            saveVocabulary(word, sourceText: article.title)
                        },
                        onDone: {
                            pickingTarget = nil
                        }
                    )
                } else {
                    Text(article.title)
                        .font(.system(size: 24 * fontSizeMultiplier, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .lineSpacing(4)
                        .contextMenu {
                            itemContextMenu(text: article.title, sectionID: headlineSectionID)
                        }

                    HStack(spacing: 12) {
                        Button {
                            speechManager.toggleSpeak(article.title)
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
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                pickingTarget = NewsWordPickTarget(sectionID: headlineSectionID, mode: .pickWord)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.tap")
                                    .font(.caption2)
                                Text("Pick word")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(AppTheme.Primary.p700)
                        }

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                pickingTarget = NewsWordPickTarget(sectionID: headlineSectionID, mode: .lightPickWord)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.caption2)
                                Text("Light pick")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(AppTheme.Accent.a600)
                        }

                        Button {
                            selectedSentenceForAnalysis = article.title
                            showSentenceAnalysisSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.caption2)
                                Text("Ngữ pháp")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(AppTheme.Primary.p500)
                        }

                        Button {
                            copyText(article.title)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                Text("Copy")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(AppTheme.Neutral.n500)
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }

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
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(summary.englishTakeaways.indices), id: \.self) { idx in
                    let englishText = summary.englishTakeaways[idx]
                    let sectionID = "takeaway-\(idx)"
                    let isPickingTakeaway = pickingTarget?.sectionID == sectionID
                    let activeTakeawayMode = isPickingTakeaway ? pickingTarget?.mode : nil

                    VStack(alignment: .leading, spacing: 6) {
                        if let activeMode = activeTakeawayMode {
                            WordPickerText(
                                text: englishText,
                                mode: activeMode,
                                foregroundStyle: AppTheme.Neutral.n900,
                                chipBackground: AppTheme.Surface.card,
                                modeBackground: AppTheme.Accent.a50,
                                savedWords: savedVocabularyWords,
                                onPick: { word in
                                    saveVocabulary(word, sourceText: englishText)
                                },
                                onDone: {
                                    pickingTarget = nil
                                }
                            )
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.Primary.p500)

                                Text(englishText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .contextMenu {
                                        itemContextMenu(text: englishText, sectionID: sectionID)
                                    }
                            }

                            // Quick helper action buttons for takeaway
                            HStack(spacing: 12) {
                                Button {
                                    speechManager.toggleSpeak(englishText)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "speaker.wave.1.fill")
                                            .font(.system(size: 10))
                                        Text("Nghe")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(AppTheme.Neutral.n700)
                                }

                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .pickWord)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "hand.tap")
                                            .font(.system(size: 10))
                                        Text("Pick word")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(AppTheme.Primary.p700)
                                }

                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .lightPickWord)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "character.book.closed.fill")
                                            .font(.system(size: 10))
                                        Text("Light pick")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(AppTheme.Accent.a600)
                                }

                                Button {
                                    selectedSentenceForAnalysis = englishText
                                    showSentenceAnalysisSheet = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "text.magnifyingglass")
                                            .font(.system(size: 10))
                                        Text("Ngữ pháp")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(AppTheme.Primary.p500)
                                }

                                Button {
                                    copyText(englishText)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text("Copy")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(AppTheme.Neutral.n500)
                                }

                                Spacer()
                            }
                            .padding(.leading, 14)
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
                                let isSaved = savedVocabularyWords.contains(vocab.word.normalizedVocabularyWord)

                                Button {
                                    lookupWordDirectly(vocab.word, contextSentence: vocab.contextExplanation)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSaved {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.Semantic.success)
                                        }

                                        Text(vocab.word)
                                            .font(.caption.bold())
                                            .foregroundStyle(isSaved ? AppTheme.Semantic.success : AppTheme.Primary.p700)
                                        Text(vocab.phonetic)
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                        Text("• \(vocab.vietnameseMeaning)")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(isSaved ? AppTheme.Semantic.success.opacity(0.12) : AppTheme.Primary.p50)
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(isSaved ? AppTheme.Semantic.success.opacity(0.5) : AppTheme.Primary.p300.opacity(0.5), lineWidth: 0.5)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        speechManager.speak(vocab.word)
                                    } label: {
                                        Label("Phát âm", systemImage: "speaker.wave.2")
                                    }

                                    Button {
                                        saveVocabulary(vocab.word, sourceText: vocab.contextExplanation)
                                    } label: {
                                        Label(isSaved ? "Đã lưu vào Sổ tay" : "Lưu vào Sổ tay", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                                    }

                                    Button {
                                        lookupWordDirectly(vocab.word, contextSentence: vocab.contextExplanation)
                                    } label: {
                                        Label("Xem chi tiết", systemImage: "character.book.closed.fill")
                                    }
                                }
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
        let sectionID = "paragraph-\(index)"
        let isHighlighted = isPlayingAudio && currentAudioParagraphIndex == index
        let isSpeakingThis = speechManager.speakingText == paragraph
        let isPicking = pickingTarget?.sectionID == sectionID
        let activeMode = isPicking ? pickingTarget?.mode : nil

        return VStack(alignment: .leading, spacing: 10) {
            if let activeMode {
                WordPickerText(
                    text: paragraph,
                    mode: activeMode,
                    foregroundStyle: AppTheme.Neutral.n900,
                    chipBackground: AppTheme.Surface.card,
                    modeBackground: AppTheme.Accent.a50,
                    savedWords: savedVocabularyWords,
                    onPick: { word in
                        saveVocabulary(word, sourceText: paragraph)
                    },
                    onDone: {
                        pickingTarget = nil
                    }
                )
            } else {
                Text(paragraph)
                    .font(.system(size: 17 * fontSizeMultiplier, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .lineSpacing(6 * fontSizeMultiplier)
                    .textSelection(.enabled)
                    .contextMenu {
                        itemContextMenu(text: paragraph, sectionID: sectionID)
                    }

                // Paragraph helper actions toolbar
                HStack(spacing: 12) {
                    Button {
                        if isSpeakingThis {
                            speechManager.stop()
                        } else {
                            playSingleParagraphAudio(paragraph, index: index)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isSpeakingThis ? "stop.circle.fill" : "speaker.wave.1.fill")
                                .font(.caption2)
                            Text(isSpeakingThis ? "Dừng" : "Nghe")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(isSpeakingThis ? AppTheme.Semantic.warning : AppTheme.Neutral.n700)
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .pickWord)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.tap")
                                .font(.caption2)
                            Text("Pick word")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(AppTheme.Primary.p700)
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .lightPickWord)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.caption2)
                            Text("Light pick")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(AppTheme.Accent.a600)
                    }

                    Button {
                        selectedSentenceForAnalysis = paragraph
                        showSentenceAnalysisSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.caption2)
                            Text("Phân tích")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(AppTheme.Primary.p500)
                    }

                    Button {
                        copyText(paragraph)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                            Text("Copy")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(AppTheme.Neutral.n500)
                    }

                    Spacer()
                }
                .padding(.top, 4)
            }
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
            showToast("Đã lưu \"\(lookup.word)\" vào Sổ tay")
        } catch {
            // Handled
        }
    }

    // MARK: - Context Menu for News Items

    @ViewBuilder
    private func itemContextMenu(text: String, sectionID: String) -> some View {
        Button {
            speechManager.toggleSpeak(text)
        } label: {
            Label("Nghe phát âm", systemImage: "speaker.wave.2.fill")
        }

        Button {
            copyText(text)
        } label: {
            Label("Sao chép", systemImage: "doc.on.doc")
        }

        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .pickWord)
            }
        } label: {
            Label("Pick word", systemImage: "hand.tap")
        }

        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                pickingTarget = NewsWordPickTarget(sectionID: sectionID, mode: .lightPickWord)
            }
        } label: {
            Label("Light pick word", systemImage: "character.book.closed.fill")
        }

        Button {
            selectedSentenceForAnalysis = text
            showSentenceAnalysisSheet = true
        } label: {
            Label("Light analysis", systemImage: "sparkles.rectangle.stack.fill")
        }

        Button {
            openSentenceStructureAnalysis(for: text)
        } label: {
            Label("Phân tích cấu trúc câu", systemImage: "rectangle.3.group.fill")
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
        .padding(.bottom, isPlayingAudio ? 80 : 20)
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

    private func saveVocabulary(_ word: String, sourceText: String) {
        do {
            _ = try VocabularyNoteStore.save(
                word: word,
                sourceText: sourceText,
                sourceConversation: nil,
                in: modelContext
            )
            showToast("Đã lưu \"\(word)\" vào Sổ tay từ vựng")
        } catch {
            print("DEBUG: Failed to save vocabulary: \(error)")
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showToast("Đã sao chép nội dung")
    }

    private func openSentenceStructureAnalysis(for sentence: String) {
        stopAudio()
        dismiss()
        StructureNavigationCoordinator.shared.openAndAnalyze(sentence)
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
