//
//  SentenceStructureScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

struct PendingConversationNavigation: Identifiable, Equatable {
    let id = UUID()
    let noteID: UUID?
    let conversationID: UUID?
    let messageID: UUID?
    let noteText: String
    let originalContext: String
    let originalText: String
}

@MainActor
final class StructureNavigationCoordinator: ObservableObject {
    static let shared = StructureNavigationCoordinator()

    @Published var selectedTab: AppTab = .chat
    @Published var pendingSentenceToAnalyze: String?
    @Published var pendingConversationNavigation: PendingConversationNavigation?
    @Published var forceOpenMistakeSummarySection = false
    @Published var pendingMistakeCategoryToHighlight: String?

    private init() {}

    func openAndAnalyze(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingSentenceToAnalyze = trimmed
        selectedTab = .structure
    }

    func openConversationForNote(
        noteID: UUID? = nil,
        conversationID: UUID? = nil,
        messageID: UUID? = nil,
        noteText: String = "",
        originalContext: String = "",
        originalText: String = ""
    ) {
        pendingConversationNavigation = PendingConversationNavigation(
            noteID: noteID,
            conversationID: conversationID,
            messageID: messageID,
            noteText: noteText,
            originalContext: originalContext,
            originalText: originalText
        )
        selectedTab = .chat
    }

    func openMistakeSummary(highlightedCategory: String? = nil) {
        forceOpenMistakeSummarySection = true
        pendingMistakeCategoryToHighlight = highlightedCategory
        selectedTab = .notes
    }
}

enum AppTab: String, Hashable {
    case chat
    case askAI
    case structure
    case notes
    case vocabulary
}

struct SampleStructureSentence: Identifiable {
    let id = UUID()
    let tag: String
    let sentence: String
    let highlightNote: String
}

struct SentenceStructureScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SentenceStructureAnalysisModel.updatedAt, order: .reverse)
    private var savedAnalyses: [SentenceStructureAnalysisModel]

    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @ObservedObject private var coordinator = StructureNavigationCoordinator.shared

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var inputSentence = ""
    @State private var activeRecord: SentenceStructureAnalysisModel?
    @State private var selectedComponentID: String?

    @State private var isAnalyzing = false
    @State private var analysisError: String?

    @State private var followUpQuestionInput = ""
    @State private var isAskingFollowUp = false
    @State private var dynamicSuggestedQuestions: [String] = []

    @State private var pickingTarget: WordPickTarget?
    @State private var showHistorySheet = false
    @State private var showSnackbar = false
    @State private var snackbarMessage = ""

    @StateObject private var speechRecognizer = SpeechRecognizerManager()

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    private let sampleSentences: [SampleStructureSentence] = [
        SampleStructureSentence(
            tag: "Mệnh đề quan hệ + Hiện tại hoàn thành",
            sentence: "The book that you recommended yesterday has completely changed my perspective on life.",
            highlightNote: "Phân tích S - Clause - V - O và cách rút gọn đại từ quan hệ"
        ),
        SampleStructureSentence(
            tag: "Đảo ngữ (Inversion)",
            sentence: "Not only did she finish the project ahead of schedule, but she also helped her teammates.",
            highlightNote: "Cấu trúc đảo ngữ với Not only ... but also ..."
        ),
        SampleStructureSentence(
            tag: "Cụm phân từ (Participle Phrase)",
            sentence: "Having worked in international environments for years, he easily adapts to new cultures.",
            highlightNote: "Rút gọn mệnh đề trạng ngữ chỉ nguyên nhân/thời gian"
        ),
        SampleStructureSentence(
            tag: "Câu điều kiện hỗn hợp",
            sentence: "If I had taken that job offer last year, I would be living in Singapore right now.",
            highlightNote: "Kết hợp giả định quá khứ (Type 3) và kết quả hiện tại (Type 2)"
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sentenceInputCard

                        if isAnalyzing {
                            loadingCard
                        } else if let analysisError {
                            errorCard(analysisError)
                        } else if let record = activeRecord,
                                  let analysis = record.decodedAnalysis {
                            overviewCard(record: record, analysis: analysis)

                            componentsDiagramCard(analysis: analysis)

                            if !analysis.grammarPatterns.isEmpty {
                                grammarPatternsCard(analysis: analysis)
                            }

                            if !analysis.variations.isEmpty {
                                variationsCard(recordID: record.id, analysis: analysis)
                            }

                            followUpQACard(record: record, analysis: analysis)
                        } else {
                            sampleSentencesSection
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)

                if showSnackbar {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.Semantic.success)
                            Text(snackbarMessage)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppTheme.Neutral.n900.opacity(0.88))
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.Shadow.card, radius: 8, x: 0, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                    }
                    .animation(.spring(), value: showSnackbar)
                    .zIndex(1)
                }
            }
            .navigationTitle("Cấu trúc câu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                            if !savedAnalyses.isEmpty {
                                Text("\(savedAnalyses.count)")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(AppTheme.Primary.p700)
                    }
                    .accessibilityLabel("Lịch sử phân tích cấu trúc câu")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AIModelOption.allCases) { option in
                            Button {
                                selectedAIModelRawValue = option.rawValue
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: selectedAIModel == option
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                            }
                        }
                    } label: {
                        Image("swap_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .accessibilityLabel("AI Model: \(selectedAIModel.providerName)")
                    }
                    .disabled(isAnalyzing)

                    if activeRecord != nil || !inputSentence.isEmpty {
                        Button {
                            resetToNewAnalysis()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(AppTheme.Primary.p700)
                        }
                        .disabled(isAnalyzing)
                        .accessibilityLabel("Phân tích câu mới")
                    }
                }
            }
            .sheet(isPresented: $showHistorySheet) {
                SentenceStructureHistorySheet(
                    records: savedAnalyses,
                    activeRecordID: activeRecord?.id,
                    onSelect: { record in
                        selectSavedRecord(record)
                        showHistorySheet = false
                    },
                    onDelete: { record in
                        deleteRecord(record)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                handlePendingSentenceIfNeeded()
                if activeRecord == nil, coordinator.pendingSentenceToAnalyze == nil {
                    if let first = savedAnalyses.first {
                        selectSavedRecord(first)
                    }
                }
            }
            .onChange(of: coordinator.pendingSentenceToAnalyze) { _, _ in
                handlePendingSentenceIfNeeded()
            }
            .onDisappear {
                speechRecognizer.stopRecording()
                SpeechSynthesizerManager.shared.stop()
            }
        }
    }

    // MARK: - 1. Input Card

    private var sentenceInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Nhập câu tiếng Anh cần bóc tách", systemImage: "text.magnifyingglass")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Neutral.n900)

                Spacer()

                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        inputSentence = pasted
                    }
                } label: {
                    Label("Dán", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if !inputSentence.isEmpty {
                    Button {
                        inputSentence = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.Neutral.n400)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(
                speechRecognizer.isRecording
                ? "Đang nghe câu tiếng Anh..."
                : "Ví dụ: Having finished the report, she went straight home...",
                text: $inputSentence,
                axis: .vertical
            )
            .lineLimit(2...5)
            .padding(12)
            .background(AppTheme.Surface.cardMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        speechRecognizer.isRecording ? AppTheme.Semantic.error : AppTheme.Surface.border,
                        lineWidth: 1.2
                    )
            }

            HStack(spacing: 10) {
                Button {
                    toggleVoiceRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic.fill")
                            .symbolEffect(.variableColor.iterative, isActive: speechRecognizer.isRecording)
                        Text(speechRecognizer.isRecording ? "Dừng nghe" : "Đọc câu")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(speechRecognizer.isRecording ? .white : AppTheme.Neutral.n700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(speechRecognizer.isRecording ? AppTheme.Semantic.error : AppTheme.Surface.cardMuted)
                    .clipShape(Capsule())
                    .overlay {
                        if !speechRecognizer.isRecording {
                            Capsule()
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing)

                Button {
                    analyzeSentence(inputSentence, forceRefresh: true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Phân tích cấu trúc")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        inputSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing
                        ? AppTheme.Neutral.n400
                        : AppTheme.Primary.p500
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(inputSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - Loading & Error Cards

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.Primary.p500)
            Text("Đang bóc tách từng thành phần S - V - O, mệnh đề và cấu trúc ngữ pháp...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.Semantic.error)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n700)
                .multilineTextAlignment(.center)

            Button {
                analyzeSentence(inputSentence, forceRefresh: true)
            } label: {
                Label("Thử lại", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppTheme.Primary.p500)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Semantic.error.opacity(0.5), lineWidth: 1.5)
        }
    }

    // MARK: - Sample Sentences Section

    private var sampleSentencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Câu mẫu tiêu biểu (chạm để xem phân tích)")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Neutral.n500)
                .textCase(.uppercase)

            ForEach(sampleSentences) { sample in
                Button {
                    inputSentence = sample.sentence
                    analyzeSentence(sample.sentence, forceRefresh: false)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(sample.tag)
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Primary.p500)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.Primary.p50)
                                .clipShape(Capsule())

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.Neutral.n400)
                        }

                        Text(sample.sentence)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .multilineTextAlignment(.leading)

                        Text(sample.highlightNote)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 2. Part 1: Overview & Formula Card

    private func overviewCard(
        record: SentenceStructureAnalysisModel,
        analysis: AISentenceStructureResponse
    ) -> some View {
        let displaySentence: String = {
            if let corrected = analysis.correctedSentence?.trimmingCharacters(in: .whitespacesAndNewlines),
               !corrected.isEmpty {
                return corrected
            }
            return analysis.originalSentence
        }()

        let overviewPickTarget = WordPickTarget(messageID: record.id, section: "overview-sentence")
        let isPicking = (pickingTarget == overviewPickTarget)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Tổng quan & Công thức câu", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Spacer()

                SpeakButton(
                    text: displaySentence,
                    slow: false,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Primary.p500,
                    showBackground: true
                )

                SpeakButton(
                    text: displaySentence,
                    slow: true,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Accent.a600,
                    showBackground: true
                )

                Button {
                    if isPicking {
                        pickingTarget = nil
                    } else {
                        pickingTarget = overviewPickTarget
                    }
                } label: {
                    Image(systemName: "hand.tap")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isPicking ? .white : AppTheme.Neutral.n500)
                        .padding(6)
                        .background(isPicking ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick word")

                Button {
                    saveToNotedAI(
                        text: displaySentence,
                        context: "\(analysis.generalFormula) — \(analysis.vietnameseTranslation)",
                        isExplanation: false
                    )
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .padding(6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    copyText(displaySentence)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .padding(6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let corrected = analysis.correctedSentence?.trimmingCharacters(in: .whitespacesAndNewlines),
               !corrected.isEmpty,
               corrected.lowercased() != analysis.originalSentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bản chuẩn ngữ pháp:")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Semantic.success)

                    Text(corrected)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Semantic.success)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Semantic.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if isPicking {
                WordPickerText(
                    text: displaySentence,
                    foregroundStyle: AppTheme.Neutral.n900,
                    chipBackground: AppTheme.Surface.card,
                    modeBackground: AppTheme.Accent.a50,
                    savedWords: savedVocabularyWords,
                    onPick: { word in
                        saveVocabulary(word, sourceText: displaySentence)
                    },
                    onDone: {
                        pickingTarget = nil
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    LightPickableSentenceText(
                        sentence: displaySentence,
                        font: .title3.weight(.bold),
                        foregroundColor: AppTheme.Neutral.n900,
                        savedWords: savedVocabularyWords,
                        onSaveVocabulary: { word, src in
                            saveVocabulary(word, sourceText: src)
                        }
                    )

                    Text("Chạm vào bất kỳ từ nào để xem nhanh nghĩa & vai trò ngữ pháp")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Vietnamese Translation
            VStack(alignment: .leading, spacing: 4) {
                Text("Dịch nghĩa:")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)

                Text(analysis.vietnameseTranslation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Neutral.n700)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Surface.cardMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // General Formula Box
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "function")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Công thức tổng quát")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                }

                Text(analysis.generalFormula)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.Primary.p700)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(AppTheme.Primary.p50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppTheme.Primary.p300, lineWidth: 1)
            }

            // Tense & Sentence Type Badges
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                    Text(analysis.tense)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.Accent.a600)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.Accent.a50)
                .clipShape(Capsule())

                HStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption2)
                    Text(analysis.sentenceType)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.Secondary.s600)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.Secondary.s100)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - 3. Part 2: Visual Syntax Components Breakdown

    private func componentsDiagramCard(analysis: AISentenceStructureResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Sơ đồ bóc tách thành phần câu", systemImage: "rectangle.3.group.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Spacer()

                if selectedComponentID != nil {
                    Button("Hiện tất cả") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedComponentID = nil
                        }
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                } else {
                    Text("Chạm vào khối để lọc")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
            }

            // Visual Flow Blocks
            WordPickerFlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(analysis.components) { comp in
                    let isSelected = (selectedComponentID == comp.id)
                    let style = componentStyle(for: comp.symbol)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedComponentID == comp.id {
                                selectedComponentID = nil
                            } else {
                                selectedComponentID = comp.id
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comp.symbol)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(isSelected ? .white : style.foreground)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    isSelected
                                    ? style.foreground.opacity(0.3)
                                    : style.foreground.opacity(0.14)
                                )
                                .clipShape(Capsule())

                            Text(comp.segment)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n900)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? style.foreground : style.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style.foreground.opacity(isSelected ? 1 : 0.45), lineWidth: isSelected ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(AppTheme.Surface.cardMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Detailed Component Cards
            let visibleComponents = selectedComponentID == nil
                ? analysis.components
                : analysis.components.filter { $0.id == selectedComponentID }

            VStack(spacing: 10) {
                ForEach(visibleComponents) { comp in
                    let style = componentStyle(for: comp.symbol)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(comp.symbol)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(style.foreground)
                                .clipShape(Capsule())

                            Text(comp.roleName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.Neutral.n900)

                            Spacer()

                            SpeakButton(
                                text: comp.segment,
                                font: .caption,
                                activeColor: style.foreground,
                                showBackground: true
                            )
                        }

                        HStack(spacing: 8) {
                            Text("\"\(comp.segment)\"")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(style.foreground)

                            Text("•")
                                .foregroundStyle(AppTheme.Neutral.n400)

                            Text(comp.grammaticalForm)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }

                        Text(comp.explanation)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style.foreground.opacity(0.35), lineWidth: 1.2)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - 4. Part 3: Key Grammar Patterns Card

    private func grammarPatternsCard(analysis: AISentenceStructureResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cấu trúc ngữ pháp & Cụm từ quan trọng", systemImage: "sparkles.rectangle.stack.fill")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Accent.a600)

            ForEach(analysis.grammarPatterns) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.pattern)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.Primary.p700)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())

                        Spacer()

                        Button {
                            saveToNotedAI(
                                text: "\(item.pattern): \(item.explanation)",
                                context: item.example,
                                isExplanation: true,
                                explanationNoted: item.pattern
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.square.on.square")
                                Text("Lưu Note")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Primary.p500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.Surface.cardMuted)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(item.explanation)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Neutral.n700)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Text("Ví dụ: \(item.example)")
                                .font(.caption)
                                .italic()
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            SpeakButton(
                                text: item.example,
                                font: .caption,
                                activeColor: AppTheme.Primary.p500
                            )
                        }
                        .padding(10)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
                .background(AppTheme.Secondary.s50)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                }
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - 5. Part 4: Sentence Variations Card

    private func variationsCard(
        recordID: UUID,
        analysis: AISentenceStructureResponse
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cách viết lại câu tương đương", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Secondary.s600)

            ForEach(Array(analysis.variations.enumerated()), id: \.offset) { index, variation in
                variationRowView(recordID: recordID, index: index, variation: variation)
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private func variationRowView(
        recordID: UUID,
        index: Int,
        variation: AISentenceVariationItem
    ) -> some View {
        let baseTarget = WordPickTarget(messageID: recordID, section: "variation-\(index)")
        let activeMode: WordInteractionMode? = (pickingTarget?.matchesSection(baseTarget) == true) ? pickingTarget?.mode : nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(variation.style)
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Semantic.success)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppTheme.Semantic.success.opacity(0.14))
                    .clipShape(Capsule())

                Spacer()

                SpeakButton(
                    text: variation.sentence,
                    font: .caption.weight(.semibold),
                    activeColor: AppTheme.Primary.p500,
                    showBackground: true
                )

                Button {
                    if activeMode == .pickWord {
                        pickingTarget = nil
                    } else {
                        pickingTarget = WordPickTarget(messageID: recordID, section: "variation-\(index)", mode: .pickWord)
                    }
                } label: {
                    Image(systemName: "hand.tap")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activeMode == .pickWord ? .white : AppTheme.Neutral.n500)
                        .padding(6)
                        .background(activeMode == .pickWord ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    if activeMode == .lightPickWord {
                        pickingTarget = nil
                    } else {
                        pickingTarget = WordPickTarget(messageID: recordID, section: "variation-\(index)", mode: .lightPickWord)
                    }
                } label: {
                    Image(systemName: "character.book.closed.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activeMode == .lightPickWord ? Color.white : AppTheme.Primary.p500)
                        .padding(6)
                        .background(activeMode == .lightPickWord ? AppTheme.Primary.p500 : AppTheme.Primary.p50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    saveToNotedAI(
                        text: variation.sentence,
                        context: variation.note,
                        isExplanation: false
                    )
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .padding(6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    copyText(variation.sentence)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .padding(6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let activeMode {
                WordPickerText(
                    text: variation.sentence,
                    mode: activeMode,
                    foregroundStyle: AppTheme.Neutral.n900,
                    chipBackground: AppTheme.Surface.card,
                    modeBackground: AppTheme.Accent.a50,
                    savedWords: savedVocabularyWords,
                    onPick: { word in
                        saveVocabulary(word, sourceText: variation.sentence)
                    },
                    onDone: {
                        pickingTarget = nil
                    }
                )
            } else {
                Text(variation.sentence)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(variation.note)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n500)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppTheme.Secondary.s50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
        }
    }

    // MARK: - 6. Follow-up Grammar Q&A Section

    private func followUpQACard(
        record: SentenceStructureAnalysisModel,
        analysis: AISentenceStructureResponse
    ) -> some View {
        let qas = record.followUpQAs
        let questionsToShow = dynamicSuggestedQuestions.isEmpty
            ? analysis.suggestedQuestions
            : dynamicSuggestedQuestions

        return VStack(alignment: .leading, spacing: 14) {
            Label("Hỏi thêm về ngữ pháp câu này", systemImage: "questionmark.bubble.fill")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Primary.p500)

            // Previous Q&As
            if !qas.isEmpty {
                VStack(spacing: 12) {
                    ForEach(qas) { qa in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "person.fill.questionmark")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Primary.p500)
                                    .padding(.top, 2)

                                Text(qa.question)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.Primary.p700)
                            }

                            Text(qa.answer)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n900)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !qa.examples.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(qa.examples, id: \.self) { ex in
                                        HStack(spacing: 8) {
                                            Text("• \(ex)")
                                                .font(.caption)
                                                .italic()
                                                .foregroundStyle(AppTheme.Neutral.n700)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            SpeakButton(
                                                text: ex,
                                                font: .caption2,
                                                activeColor: AppTheme.Primary.p500
                                            )
                                        }
                                    }
                                }
                                .padding(10)
                                .background(AppTheme.Surface.card)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(12)
                        .background(AppTheme.Primary.p50.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(AppTheme.Primary.p300, lineWidth: 1)
                        }
                    }
                }
            }

            if isAskingFollowUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.Primary.p500)
                    Text("Đang giải đáp thắc mắc ngữ pháp...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .padding(.vertical, 4)
            }

            // Suggested Questions
            if !questionsToShow.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gợi ý câu hỏi:")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Neutral.n500)

                    ForEach(questionsToShow, id: \.self) { q in
                        Button {
                            askFollowUpQuestion(q, for: record, analysis: analysis)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.Primary.p500)

                                Text(q)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AppTheme.Surface.cardMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isAskingFollowUp)
                    }
                }
            }

            // Custom Follow-up Question Input
            HStack(spacing: 8) {
                TextField(
                    "Hỏi thêm (VD: Tại sao dùng giới từ on ở đây?)...",
                    text: $followUpQuestionInput
                )
                .font(.subheadline)
                .padding(10)
                .background(AppTheme.Surface.cardMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                }

                Button {
                    let q = followUpQuestionInput
                    followUpQuestionInput = ""
                    askFollowUpQuestion(q, for: record, analysis: analysis)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            followUpQuestionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAskingFollowUp
                            ? AppTheme.Neutral.n400
                            : AppTheme.Primary.p500
                        )
                }
                .disabled(
                    followUpQuestionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAskingFollowUp
                )
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - Component Color Helper

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

    // MARK: - Logic & Helpers

    private func handlePendingSentenceIfNeeded() {
        guard let pending = coordinator.pendingSentenceToAnalyze?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pending.isEmpty else {
            return
        }
        coordinator.pendingSentenceToAnalyze = nil
        inputSentence = pending
        analyzeSentence(pending, forceRefresh: false)
    }

    private func selectSavedRecord(_ record: SentenceStructureAnalysisModel) {
        activeRecord = record
        inputSentence = record.sentence
        selectedComponentID = nil
        pickingTarget = nil
        analysisError = nil
        dynamicSuggestedQuestions = []
    }

    private func resetToNewAnalysis() {
        activeRecord = nil
        inputSentence = ""
        selectedComponentID = nil
        pickingTarget = nil
        analysisError = nil
        dynamicSuggestedQuestions = []
    }

    @MainActor
    private func analyzeSentence(_ rawSentence: String, forceRefresh: Bool) {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }

        let trimmed = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }

        selectedComponentID = nil
        pickingTarget = nil
        analysisError = nil
        dynamicSuggestedQuestions = []

        if !forceRefresh,
           let cached = savedAnalyses.first(where: {
               $0.sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
               && $0.decodedAnalysis != nil
           }) {
            activeRecord = cached
            return
        }

        isAnalyzing = true
        let provider = selectedAIModel.makeSentenceStructureProvider()

        Task {
            do {
                let service = SentenceStructureAIService(provider: provider)
                let response = try await service.analyzeSentence(sentence: trimmed)

                await MainActor.run {
                    if let existing = savedAnalyses.first(where: {
                        $0.sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
                    }) {
                        existing.decodedAnalysis = response
                        existing.updatedAt = Date()
                        try? context.save()
                        activeRecord = existing
                    } else {
                        let newRecord = SentenceStructureAnalysisModel(
                            sentence: trimmed,
                            analysis: response
                        )
                        context.insert(newRecord)
                        try? context.save()
                        activeRecord = newRecord
                    }
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    analysisError = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    @MainActor
    private func askFollowUpQuestion(
        _ rawQuestion: String,
        for record: SentenceStructureAnalysisModel,
        analysis: AISentenceStructureResponse
    ) {
        let trimmed = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAskingFollowUp else { return }

        isAskingFollowUp = true
        let provider = selectedAIModel.makeSentenceStructureProvider()
        let summary = "\(analysis.generalFormula) | \(analysis.tense) | \(analysis.sentenceType)"
        let currentQAs = record.followUpQAs

        Task {
            do {
                let service = SentenceStructureAIService(provider: provider)
                let result = try await service.askFollowUp(
                    sentence: record.sentence,
                    analysisSummary: summary,
                    question: trimmed,
                    previousQAs: currentQAs
                )

                await MainActor.run {
                    var updated = record.followUpQAs
                    updated.append(
                        AISentenceStructureFollowUpQA(
                            question: trimmed,
                            answer: result.answer,
                            examples: result.examples
                        )
                    )
                    record.followUpQAs = updated
                    record.updatedAt = Date()
                    if !result.nextQuestions.isEmpty {
                        dynamicSuggestedQuestions = result.nextQuestions
                    }
                    try? context.save()
                    isAskingFollowUp = false
                }
            } catch {
                await MainActor.run {
                    showStatusMessage("Không thể gửi câu hỏi: \(error.localizedDescription)")
                    isAskingFollowUp = false
                }
            }
        }
    }

    private func saveToNotedAI(
        text: String,
        context: String,
        isExplanation: Bool,
        explanationNoted: String? = nil
    ) {
        let note = SavedNoteModel(
            text: text,
            originalText: nil,
            originalContext: context,
            isExplanation: isExplanation,
            explanationNoted: explanationNoted
        )
        self.context.insert(note)

        do {
            try self.context.save()
            WidgetNoteStore.upsert(
                WidgetNoteSnapshot(
                    id: note.id,
                    text: note.text,
                    originalContext: note.originalContext,
                    isExplanation: note.isExplanation,
                    explanationNoted: note.explanationNoted,
                    createdAt: note.createdAt
                )
            )
            showStatusMessage("Đã lưu vào Noted AI")
        } catch {
            print("DEBUG: Failed to save note from structure screen: \(error)")
        }
    }

    private func saveVocabulary(_ word: String, sourceText: String) {
        do {
            _ = try VocabularyNoteStore.save(
                word: word,
                sourceText: sourceText,
                sourceConversation: nil,
                in: context
            )
            if pickingTarget == nil {
                showStatusMessage("Đã lưu từ vựng")
            }
        } catch {
            print("DEBUG: Failed to save vocabulary: \(error)")
        }
    }

    private func deleteRecord(_ record: SentenceStructureAnalysisModel) {
        let deletingActive = (activeRecord?.id == record.id)
        context.delete(record)
        try? context.save()

        if deletingActive {
            activeRecord = savedAnalyses.first(where: { $0.id != record.id })
            inputSentence = activeRecord?.sentence ?? ""
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        showStatusMessage("Đã sao chép")
    }

    private func toggleVoiceRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            SpeechSynthesizerManager.shared.stop()
            speechRecognizer.startRecording(
                existingText: inputSentence,
                onUpdate: { updated in
                    inputSentence = updated
                },
                onError: { err in
                    showStatusMessage(err)
                }
            )
        }
    }

    private func showStatusMessage(_ text: String) {
        withAnimation {
            snackbarMessage = text
            showSnackbar = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSnackbar = false
            }
        }
    }
}

// MARK: - History Sheet

private struct SentenceStructureHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let records: [SentenceStructureAnalysisModel]
    let activeRecordID: UUID?
    let onSelect: (SentenceStructureAnalysisModel) -> Void
    let onDelete: (SentenceStructureAnalysisModel) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                if records.isEmpty {
                    ContentUnavailableView(
                        "Chưa có câu nào được phân tích",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Các câu tiếng Anh bạn đã phân tích cấu trúc sẽ được lưu tại đây.")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            let isCurrent = (record.id == activeRecordID)
                            let analysis = record.decodedAnalysis

                            Button {
                                onSelect(record)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(record.sentence)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(AppTheme.Neutral.n900)
                                            .lineLimit(2)

                                        Spacer()

                                        if isCurrent {
                                            Text("Đang xem")
                                                .font(.caption2.bold())
                                                .foregroundStyle(AppTheme.Primary.p500)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.Primary.p50)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    if let analysis {
                                        Text(analysis.vietnameseTranslation)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Text(analysis.generalFormula)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.Primary.p700)
                                                .lineLimit(1)

                                            Spacer()

                                            Text(record.updatedAt, style: .date)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.Neutral.n400)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AppTheme.Surface.card)
                            .swipeActions {
                                Button(role: .destructive) {
                                    onDelete(record)
                                } label: {
                                    Label("Xoá", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Lịch sử phân tích câu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SentenceStructureScreen()
        .modelContainer(
            for: [
                ConversationModel.self,
                MessageModel.self,
                SavedNoteModel.self,
                VocabularyNoteModel.self,
                SituationAskSessionModel.self,
                SituationAskMessageModel.self,
                SentenceStructureAnalysisModel.self
            ],
            inMemory: true
        )
}
