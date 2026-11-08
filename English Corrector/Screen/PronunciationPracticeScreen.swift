//
//  PronunciationPracticeScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct PronunciationPracticeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VocabularyNoteModel.createdAt, order: .reverse)
    private var savedVocabulary: [VocabularyNoteModel]

    @StateObject private var speechRecognizer = SpeechRecognizerManager()
    @StateObject private var tts = SpeechSynthesizerManager.shared

    // Practice Modes
    enum PracticeMode: String, CaseIterable, Identifiable {
        case quickCheck = "Kiểm tra nhanh"
        case phoneticTraps = "Chuyên đề âm vị"
        case savedVocabulary = "Sổ từ vựng"
        case roleplayVoice = "Voice AI 1:1"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .quickCheck: return "mic.badge.sparkle"
            case .phoneticTraps: return "waveform.badge.magnifyingglass"
            case .savedVocabulary: return "character.book.closed.fill"
            case .roleplayVoice: return "waveform.circle.fill"
            }
        }
    }

    @State private var selectedMode: PracticeMode = .quickCheck

    // Quick Sentence Check State
    @State private var sentenceInput: String = "Could you please tell me how to get to the airport?"
    @State private var currentSentenceTranslation: String = "Bạn có thể chỉ giúp tôi đường đến sân bay được không?"
    @State private var currentSentenceFocus: String = "Lưu ý âm đuôi /z/ ở 'please' và trọng âm đầu 'air-port'"
    @State private var selectedSentenceCategory: PracticeCategory = .all
    @State private var isGeneratingAISentence: Bool = false
    @State private var diceRotationAngle: Double = 0
    @State private var recordedSpokenText: String = ""
    @State private var isAssessingSentence: Bool = false
    @State private var assessmentResult: PronunciationAssessmentResult?
    @State private var assessmentErrorMessage: String?

    // Drill Sheet State
    @State private var isDrillSheetPresented: Bool = false
    @State private var selectedAssessmentForDrill: PronunciationAssessmentResult?
    @State private var selectedWordForDrill: WordPronunciationScore?

    // Voice Studio & Roleplay
    @State private var showVoiceStudio: Bool = false
    @State private var showRoleplayPicker: Bool = false
    @State private var activeVoiceConversation: ConversationModel?

    // Selected Topic for Phonetic Traps
    @State private var selectedPhoneticTopic: VietnamesePhoneticCategory?

    // User Practice Stats stored in AppStorage
    @AppStorage("pronunciation_total_drilled_count") private var totalDrilledCount: Int = 18
    @AppStorage("pronunciation_avg_score") private var averageScore: Int = 84
    @AppStorage("pronunciation_day_streak") private var dayStreak: Int = 3

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSummaryCard

                        modeSegmentControl

                        switch selectedMode {
                        case .quickCheck:
                            quickSentenceCheckSection
                        case .phoneticTraps:
                            phoneticTrapsSection
                        case .savedVocabulary:
                            savedVocabularyDrillSection
                        case .roleplayVoice:
                            roleplayQuickLaunchSection
                        }

                        Spacer(minLength: 90) // Safe padding for bottom custom tab bar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Luyện Phát Âm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVoiceStudio = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Giọng AI")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(AppTheme.Primary.p600)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showVoiceStudio) {
                AIVoiceStudioSheet()
            }
            .sheet(isPresented: $isDrillSheetPresented) {
                if let assessment = selectedAssessmentForDrill {
                    PronunciationDrillSheet(
                        result: assessment,
                        selectedWord: selectedWordForDrill
                    )
                }
            }
            .sheet(isPresented: $showRoleplayPicker) {
                VoiceRoleplayPickerSheet { scenario in
                    showRoleplayPicker = false
                    startRoleplay(scenario)
                }
            }
            .fullScreenCover(item: $activeVoiceConversation) { voiceConv in
                LiveVoiceConversationScreen(conversation: voiceConv)
            }
        }
    }

    // MARK: - Header Summary Card

    private var headerSummaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "waveform.badge.sparkle")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Pronunciation Coach")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)

                    Text("Nhận biết & sửa lỗi nuốt âm, trọng âm, khẩu hình")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }

                Spacer()
            }

            Divider()
                .overlay(AppTheme.Surface.border)

            HStack(spacing: 8) {
                statItem(
                    icon: "target",
                    title: "Điểm TB",
                    value: "\(averageScore)%",
                    color: AppTheme.Primary.p600
                )

                Divider()
                    .frame(height: 24)
                    .overlay(AppTheme.Surface.border)

                statItem(
                    icon: "flame.fill",
                    title: "Streak",
                    value: "\(dayStreak) ngày",
                    color: .orange
                )

                Divider()
                    .frame(height: 24)
                    .overlay(AppTheme.Surface.border)

                statItem(
                    icon: "checkmark.seal.fill",
                    title: "Đã luyện",
                    value: "\(totalDrilledCount) câu",
                    color: .green
                )
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
        }
        .shadow(color: AppTheme.Primary.p500.opacity(0.04), radius: 8, y: 3)
    }

    private func statItem(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.Neutral.n400)
                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n800)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mode Segment Control

    private var modeSegmentControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PracticeMode.allCases) { mode in
                    let isSelected = selectedMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.caption.bold())
                            Text(mode.rawValue)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ?
                            LinearGradient(
                                colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [AppTheme.Surface.card, AppTheme.Surface.card],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Section 1: Quick Sentence Check

    private var quickSentenceCheckSection: some View {
        VStack(spacing: 16) {
            // Text Input Card
            VStack(alignment: .leading, spacing: 12) {
                // Top Action Bar
                HStack(spacing: 6) {
                    Label("Câu luyện nói", systemImage: "text.quote")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p600)

                    Spacer()

                    // Random sentence button
                    Button {
                        pickRandomSentence()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "dice.fill")
                                .rotationEffect(.degrees(diceRotationAngle))
                            Text("Random câu")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Accent.a600)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.Accent.a50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // AI Generate Button
                    Button {
                        generateAISentence()
                    } label: {
                        HStack(spacing: 4) {
                            if isGeneratingAISentence {
                                ProgressView()
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("AI Gợi ý")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Primary.p600)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingAISentence)

                    // Play Native Model Audio Button
                    Button {
                        playCurrentSentenceAudio(slow: false)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Primary.p600)
                            .padding(6)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Sentence Input Field
                TextField("Nhập hoặc dán câu tiếng Anh...", text: $sentenceInput, axis: .vertical)
                    .font(.body.weight(.semibold))
                    .lineLimit(2...4)
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .padding(10)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // Translation & Phonetic Tip Row
                if !currentSentenceTranslation.isEmpty || !currentSentenceFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !currentSentenceTranslation.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Text("🇻🇳")
                                    .font(.caption2)
                                Text(currentSentenceTranslation)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Neutral.n700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !currentSentenceFocus.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "target")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppTheme.Accent.a600)
                                    .padding(.top, 2)
                                Text(currentSentenceFocus)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.Accent.a600)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Surface.cardMuted.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Category Selector Filter Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Chủ đề câu:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Neutral.n500)
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(PracticeCategory.allCases) { cat in
                                let isSelected = selectedSentenceCategory == cat
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedSentenceCategory = cat
                                        pickRandomSentence(category: cat)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon)
                                            .font(.system(size: 9))
                                        Text(cat.rawValue)
                                            .font(.caption2.weight(isSelected ? .bold : .medium))
                                    }
                                    .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n600)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.Surface.border, lineWidth: 1))

            // Big Record & Speak Button
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(speechRecognizer.isRecording ? Color.red : AppTheme.Primary.p500)
                            .frame(width: 44, height: 44)

                        Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(speechRecognizer.isRecording ? "Đang lắng nghe bạn đọc..." : "Bấm Micro để nói câu này")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(speechRecognizer.isRecording ? "Bấm lại để hoàn tất & AI chấm điểm" : "Hệ thống sẽ chấm điểm phát âm & chỉ lỗi từng từ")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if speechRecognizer.isRecording {
                        Color.red
                    } else {
                        LinearGradient(
                            colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: (speechRecognizer.isRecording ? Color.red : AppTheme.Primary.p500).opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isAssessingSentence)

            // Assessing Indicator
            if isAssessingSentence {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AI đang chấm điểm & phân tích phiên âm IPA...")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p600)
                }
                .padding(.vertical, 10)
            }

            // Assessment Result Display Card
            if let result = assessmentResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: result.overallLevel.iconName)
                            Text("\(result.overallScore)% • \(result.overallLevel.title)")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(result.overallLevel.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(result.overallLevel.badgeBackgroundColor)
                        .clipShape(Capsule())

                        Spacer()

                        Button {
                            selectedAssessmentForDrill = result
                            selectedWordForDrill = nil
                            isDrillSheetPresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text("Luyện chi tiết từng từ")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Primary.p600)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if !recordedSpokenText.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Primary.p500)
                            Text("AI nghe bạn đọc: \"\(recordedSpokenText)\"")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.Neutral.n700)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Chạm vào từng từ để xem phiên âm IPA và chỉnh khẩu hình:")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n500)

                    WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(result.words) { wordScore in
                            Button {
                                selectedAssessmentForDrill = result
                                selectedWordForDrill = wordScore
                                isDrillSheetPresented = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(wordScore.word)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(wordScore.level.color)

                                    if wordScore.level != .excellent {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(wordScore.level.color)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(wordScore.level.badgeBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(wordScore.level.color.opacity(0.3), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Specific mistake breakdown
                    let mistakeWords = result.words.filter { $0.level != .excellent && $0.errorDescription != nil }
                    if !mistakeWords.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Các lỗi phát âm nhận diện:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.Neutral.n700)

                            ForEach(mistakeWords.prefix(3)) { errWord in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundStyle(errWord.level.color)
                                    Text("\(errWord.word): \(errWord.errorDescription ?? "")")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.Neutral.n800)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !result.summaryFeedback.isEmpty {
                        Divider()
                            .overlay(AppTheme.Surface.border)

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                                .padding(.top, 2)

                            Text(result.summaryFeedback)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.Surface.border, lineWidth: 1))
            }
        }
    }

    // MARK: - Section 2: Phonetic Traps for Vietnamese Learners

    private var phoneticTrapsSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("6 Chuyên Đề Âm Vị Dễ Sai Của Người Việt")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text("Tập trung vào các bẫy nuốt âm cuối, đuôi -ed, âm cắn lưỡi và trọng âm")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ForEach(VietnamesePhoneticData.categories) { category in
                    phoneticCategoryCard(category)
                }
            }
        }
    }

    private func phoneticCategoryCard(_ category: VietnamesePhoneticCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: category.icon)
                        .font(.headline)
                        .foregroundStyle(category.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)

                    Text(category.subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }

                Spacer()
            }

            // Example Word Chips
            WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(category.examples) { example in
                    Button {
                        openDrillForExample(example)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(example.word)
                                    .font(.caption.bold())
                                    .foregroundStyle(AppTheme.Neutral.n900)

                                Text(example.ipa)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(category.color)
                            }
                            Text(example.meaning)
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.Surface.border, lineWidth: 1))
    }

    // MARK: - Section 3: Saved Vocabulary Drill

    private var savedVocabularyDrillSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Luyện Phát Âm Từ Sổ Từ Vựng Của Bạn")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text("Thực hành phát âm chính những từ bạn đã bookmark khi đọc báo và trò chuyện")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if savedVocabulary.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.Neutral.n300)

                    Text("Chưa có từ vựng nào được lưu")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n700)

                    Text("Khi đọc tin tức hoặc trò chuyện, hãy chạm vào từ vựng bất kỳ và chọn 'Lưu' để luyện phát âm tại đây.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(savedVocabulary.prefix(12)) { item in
                        Button {
                            openDrillForSavedWord(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.word)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(AppTheme.Neutral.n900)
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: "waveform")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.Primary.p500)
                                }

                                if let phonetic = item.phonetic, !phonetic.isEmpty {
                                    Text(phonetic)
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.Primary.p600)
                                }

                                if let vi = item.vietnameseMeaning, !vi.isEmpty {
                                    Text(vi)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.Neutral.n500)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .background(AppTheme.Surface.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.Surface.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Section 4: Roleplay Quick Launch

    private var roleplayQuickLaunchSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Luyện Nói Phản Xạ Voice AI 1:1")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text("Hội thoại thời gian thực bằng giọng nói bản xứ với AI và chấm phát âm tự động")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showRoleplayPicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)

                        Image(systemName: "waveform.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bắt đầu buổi đàm thoại Voice AI")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Neutral.n900)

                        Text("Chọn kịch bản: Phỏng vấn xin việc, Đặt đồ ăn, Du lịch, IELTS Speaking")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
                .padding(14)
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.Surface.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions & Logic

    private func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            assessSpokenSpeech()
        } else {
            assessmentResult = nil
            assessmentErrorMessage = nil
            recordedSpokenText = ""
            speechRecognizer.startRecording(
                existingText: "",
                onUpdate: { updated in
                    recordedSpokenText = updated
                },
                onError: { err in
                    assessmentErrorMessage = err
                }
            )
        }
    }

    private func assessSpokenSpeech() {
        let spoken = recordedSpokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            assessmentErrorMessage = "Chưa nhận diện được giọng nói. Vui lòng bấm Micro và nói lại."
            return
        }

        isAssessingSentence = true

        Task {
            let segments = speechRecognizer.latestSegments
            let result = await PronunciationAssessmentService.shared.assessPronunciation(
                targetSentence: sentenceInput,
                spokenSentence: spoken,
                acousticSegments: segments
            )

            await MainActor.run {
                self.assessmentResult = result
                self.isAssessingSentence = false
                self.totalDrilledCount += 1
                self.averageScore = (self.averageScore * 3 + result.overallScore) / 4
            }
        }
    }

    private func playCurrentSentenceAudio(slow: Bool) {
        let text = sentenceInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tts.speak(text, slow: slow)
    }

    private func openDrillForExample(_ example: PhoneticExampleWord) {
        let mockResult = PronunciationAssessmentResult(
            overallScore: 80,
            overallLevel: .fair,
            sentence: example.word,
            words: [
                WordPronunciationScore(
                    word: example.word,
                    cleanWord: example.word.lowercased(),
                    score: 80,
                    level: .fair,
                    ipa: example.ipa,
                    syllables: example.word,
                    stressedSyllable: example.word,
                    errorType: .correct,
                    mouthTip: example.tip
                )
            ],
            summaryFeedback: example.tip
        )
        selectedAssessmentForDrill = mockResult
        selectedWordForDrill = mockResult.words.first
        isDrillSheetPresented = true
    }

    private func openDrillForSavedWord(_ wordItem: VocabularyNoteModel) {
        let clean = wordItem.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipa = wordItem.phonetic ?? ""
        let tip = wordItem.vietnameseMeaning ?? "Luyện phát âm rõ âm tiết và nhấn đúng trọng âm."
        let mockResult = PronunciationAssessmentResult(
            overallScore: 82,
            overallLevel: .fair,
            sentence: clean,
            words: [
                WordPronunciationScore(
                    word: clean,
                    cleanWord: clean.lowercased(),
                    score: 82,
                    level: .fair,
                    ipa: ipa,
                    syllables: clean,
                    stressedSyllable: clean,
                    errorType: .correct,
                    mouthTip: tip
                )
            ],
            summaryFeedback: tip
        )
        selectedAssessmentForDrill = mockResult
        selectedWordForDrill = mockResult.words.first
        isDrillSheetPresented = true
    }

    private func startRoleplay(_ scenario: VoiceRoleplayScenario) {
        let conversation = ConversationModel(
            title: scenario.title,
            conversationDescription: scenario.contextDescription
        )
        context.insert(conversation)

        let trimmedStarter = scenario.starterQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStarter.isEmpty {
            let starterMessage = MessageModel(
                text: trimmedStarter,
                isUser: false,
                followUpQuestion: trimmedStarter,
                suggestedReplies: scenario.starterReplies
            )
            starterMessage.conversation = conversation
            context.insert(starterMessage)
        }

        try? context.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.activeVoiceConversation = conversation
        }
    }

    // MARK: - Random Sentence Generator & AI Sentence Generator

    private func pickRandomSentence(category: PracticeCategory? = nil) {
        let cat = category ?? selectedSentenceCategory
        let pool = PracticeSentenceBank.sentences(for: cat)
        guard let picked = pool.filter({ $0.english != sentenceInput }).randomElement() ?? pool.randomElement() else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            diceRotationAngle += 360
            sentenceInput = picked.english
            currentSentenceTranslation = picked.vietnamese
            currentSentenceFocus = picked.phoneticFocus
            assessmentResult = nil
            assessmentErrorMessage = nil
            recordedSpokenText = ""
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func generateAISentence() {
        guard !isGeneratingAISentence else { return }
        isGeneratingAISentence = true
        assessmentResult = nil
        assessmentErrorMessage = nil

        Task {
            let groqKey = APIKeyStore.groqAPIKey
            let prompt = """
            Generate 1 natural English sentence for pronunciation practice in category "\(selectedSentenceCategory.rawValue)".
            Focus on common difficulties for Vietnamese learners (e.g. ending sounds /s/, /z/, /t/, -ed, consonant clusters, or word stress).
            Return strict JSON only (no markdown, no extra text):
            {
              "english": "<1 natural English sentence between 6 and 14 words>",
              "vietnamese": "<Vietnamese translation>",
              "phoneticFocus": "<1 concise Vietnamese sentence pointing out key sounds to focus on>"
            }
            """

            var newEnglish: String?
            var newVietnamese: String?
            var newFocus: String?

            if !groqKey.isEmpty {
                if let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") {
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(groqKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 8

                    let body: [String: Any] = [
                        "model": "openai/gpt-oss-20b",
                        "messages": [
                            ["role": "system", "content": "You are an English phonetics trainer. Output strict JSON only."],
                            ["role": "user", "content": prompt]
                        ],
                        "temperature": 0.7,
                        "response_format": ["type": "json_object"]
                    ]

                    if let bodyData = try? JSONSerialization.data(withJSONObject: body) {
                        req.httpBody = bodyData
                        if let (data, resp) = try? await URLSession.shared.data(for: req),
                           let http = resp as? HTTPURLResponse, http.statusCode == 200,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let msg = first["message"] as? [String: Any],
                           let content = msg["content"] as? String,
                           let cData = content.data(using: .utf8),
                           let parsed = try? JSONSerialization.jsonObject(with: cData) as? [String: Any] {
                            newEnglish = parsed["english"] as? String
                            newVietnamese = parsed["vietnamese"] as? String
                            newFocus = parsed["phoneticFocus"] as? String
                        }
                    }
                }
            }

            await MainActor.run {
                self.isGeneratingAISentence = false
                if let eng = newEnglish, !eng.isEmpty {
                    withAnimation {
                        self.sentenceInput = eng
                        self.currentSentenceTranslation = newVietnamese ?? ""
                        self.currentSentenceFocus = newFocus ?? "Luyện phát âm rõ âm đuôi và nhấn đúng trọng âm."
                        self.recordedSpokenText = ""
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    // Fallback to local random
                    self.pickRandomSentence()
                }
            }
        }
    }
}

// MARK: - Practice Sentences Dataset

struct PracticeSentenceItem: Identifiable, Equatable {
    let id = UUID()
    let english: String
    let vietnamese: String
    let level: String
    let phoneticFocus: String
    let category: PracticeCategory
}

enum PracticeCategory: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case daily = "Hàng ngày"
    case business = "Công việc"
    case travel = "Du lịch"
    case challenge = "Thử thách âm"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .daily: return "bubble.left.and.bubble.right.fill"
        case .business: return "briefcase.fill"
        case .travel: return "airplane"
        case .challenge: return "flame.fill"
        }
    }
}

enum PracticeSentenceBank {
    static let allSentences: [PracticeSentenceItem] = [
        // Daily
        PracticeSentenceItem(
            english: "Could you please tell me how to get to the airport?",
            vietnamese: "Bạn có thể chỉ giúp tôi đường đến sân bay được không?",
            level: "A2",
            phoneticFocus: "Lưu ý âm đuôi /z/ ở 'please' và trọng âm đầu 'air-port'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "I am really looking forward to meeting you tomorrow.",
            vietnamese: "Tôi rất mong chờ được gặp bạn vào ngày mai.",
            level: "B1",
            phoneticFocus: "Nối âm 'looking forward' và nguyên âm đôi ở 'really'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "Practice makes perfect when learning English pronunciation.",
            vietnamese: "Có công mài sắt có ngày nên kim khi học phát âm tiếng Anh.",
            level: "B1",
            phoneticFocus: "Âm đuôi /s/ ở 'makes' và trọng âm từ 'pro-nun-ci-A-tion'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "What are you planning to do this upcoming weekend?",
            vietnamese: "Bạn có kế hoạch gì cho dịp cuối tuần sắp tới chưa?",
            level: "A2",
            phoneticFocus: "Âm /ð/ ở 'this' và trọng âm 'up-COM-ing'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "I usually take a quick walk in the park after dinner.",
            vietnamese: "Tôi thường đi dạo nhanh trong công viên sau bữa tối.",
            level: "A2",
            phoneticFocus: "Âm /ʒ/ ở 'usually' và đuôi /k/ ở 'quick', 'park'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "Could you pass me the salt and pepper, please?",
            vietnamese: "Bạn có thể chuyển giúp tôi lọ muối và tiêu được không?",
            level: "A1",
            phoneticFocus: "Âm /s/ ở 'pass', 'salt' và 'please'",
            category: .daily
        ),
        PracticeSentenceItem(
            english: "I love drinking a fresh cup of coffee every morning.",
            vietnamese: "Tôi thích uống một tách cà phê thơm ngon vào mỗi buổi sáng.",
            level: "A1",
            phoneticFocus: "Âm /f/ ở 'fresh', 'coffee' và đuôi /p/ ở 'cup'",
            category: .daily
        ),

        // Business
        PracticeSentenceItem(
            english: "Let's schedule a follow-up meeting for next Tuesday morning.",
            vietnamese: "Chúng ta hãy lên lịch họp tiếp vào sáng thứ Ba tuần tới nhé.",
            level: "B2",
            phoneticFocus: "Trọng âm 'SCHE-dule' và âm /z/ ở 'Tuesday'",
            category: .business
        ),
        PracticeSentenceItem(
            english: "Could you walk me through the key highlights of the proposal?",
            vietnamese: "Bạn có thể tóm tắt cho tôi các điểm nổi bật của bản đề xuất không?",
            level: "B2",
            phoneticFocus: "Âm cắn lưỡi /θ/ ở 'through' và đuôi /ts/ ở 'highlights'",
            category: .business
        ),
        PracticeSentenceItem(
            english: "We need to analyze customer feedback to improve our product.",
            vietnamese: "Chúng ta cần phân tích phản hồi của khách hàng để cải tiến sản phẩm.",
            level: "B1",
            phoneticFocus: "Trọng âm 'AN-a-lyze' và đuôi /t/ ở 'product'",
            category: .business
        ),
        PracticeSentenceItem(
            english: "Thank you for taking the time to interview with us today.",
            vietnamese: "Cảm ơn bạn đã dành thời gian tham gia phỏng vấn với chúng tôi hôm nay.",
            level: "B1",
            phoneticFocus: "Âm /θ/ ở 'thank', 'with' và trọng âm 'IN-ter-view'",
            category: .business
        ),
        PracticeSentenceItem(
            english: "Our team achieved outstanding results in the last quarter.",
            vietnamese: "Đội ngũ của chúng ta đã đạt kết quả vượt bậc trong quý vừa qua.",
            level: "B2",
            phoneticFocus: "Đuôi -ed /d/ ở 'achieved' và trọng âm 'out-STAND-ing'",
            category: .business
        ),
        PracticeSentenceItem(
            english: "I appreciate your prompt assistance on this urgent project.",
            vietnamese: "Tôi rất trân trọng sự hỗ trợ kịp thời của bạn về dự án khẩn này.",
            level: "B2",
            phoneticFocus: "Trọng âm 'ap-PRE-ci-ate' và âm /ʃ/ ở 'assistance'",
            category: .business
        ),

        // Travel
        PracticeSentenceItem(
            english: "I'd like to make a reservation for two people at seven.",
            vietnamese: "Tôi muốn đặt bàn cho hai người vào lúc 7 giờ.",
            level: "A2",
            phoneticFocus: "Trọng âm 'res-er-VA-tion' và âm /v/ ở 'seven'",
            category: .travel
        ),
        PracticeSentenceItem(
            english: "Excuse me, where can I find the baggage claim area?",
            vietnamese: "Xin lỗi, tôi có thể tìm khu vực nhận hành lý ở đâu?",
            level: "A2",
            phoneticFocus: "Âm /s/ ở 'excuse' và âm /dʒ/ ở 'baggage'",
            category: .travel
        ),
        PracticeSentenceItem(
            english: "Could you recommend a traditional local restaurant nearby?",
            vietnamese: "Bạn có thể giới thiệu một nhà hàng đặc sản địa phương gần đây không?",
            level: "B1",
            phoneticFocus: "Trọng âm 'rec-om-MEND' và 'tra-DI-tion-al'",
            category: .travel
        ),
        PracticeSentenceItem(
            english: "How much does a one-way ticket to downtown cost?",
            vietnamese: "Một vé một chiều đến trung tâm thành phố giá bao nhiêu?",
            level: "A2",
            phoneticFocus: "Âm /z/ ở 'does' và đuôi /st/ ở 'cost'",
            category: .travel
        ),
        PracticeSentenceItem(
            english: "Is breakfast included in the room rate for our stay?",
            vietnamese: "Bữa sáng đã bao gồm trong giá phòng của chúng tôi chưa?",
            level: "A2",
            phoneticFocus: "Đuôi -ed /ɪd/ ở 'included' và âm /eɪ/ ở 'rate'",
            category: .travel
        ),

        // Challenge (Tongue Twisters & Complex Phonetics)
        PracticeSentenceItem(
            english: "She sells seashells by the seashore.",
            vietnamese: "Cô ấy bán vỏ sò bên bờ biển.",
            level: "C1",
            phoneticFocus: "Luyện phân biệt /s/ vs /ʃ/ cực chuẩn",
            category: .challenge
        ),
        PracticeSentenceItem(
            english: "I thought a thought, but the thought I thought wasn't the thought I thought I thought.",
            vietnamese: "Tôi nghĩ một ý nghĩ, nhưng ý nghĩ tôi nghĩ không phải ý nghĩ tôi nghĩ tôi nghĩ.",
            level: "C1",
            phoneticFocus: "Luyện âm cắn lưỡi /θ/ ở 'thought' liên tục",
            category: .challenge
        ),
        PracticeSentenceItem(
            english: "Peter Piper picked a peck of pickled peppers.",
            vietnamese: "Peter Piper đã hái một đấu ớt muối.",
            level: "C1",
            phoneticFocus: "Luyện bật hơi phụ âm bật môi /p/ dứt khoát",
            category: .challenge
        ),
        PracticeSentenceItem(
            english: "Comfortable photographers photographed extraordinarily picturesque architecture.",
            vietnamese: "Các nhiếp ảnh gia thoải mái đã chụp lại kiến trúc đẹp như tranh vẽ.",
            level: "C1",
            phoneticFocus: "Luyện trọng âm từ đa âm tiết khó (COMF-ter-ble, pho-TOG-ra-pher)",
            category: .challenge
        )
    ]

    static func sentences(for category: PracticeCategory) -> [PracticeSentenceItem] {
        if category == .all {
            return allSentences
        }
        return allSentences.filter { $0.category == category }
    }
}

// MARK: - Vietnamese Phonetic Dataset

struct VietnamesePhoneticCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let examples: [PhoneticExampleWord]
}

struct PhoneticExampleWord: Identifiable {
    let id = UUID()
    let word: String
    let ipa: String
    let meaning: String
    let tip: String
}

enum VietnamesePhoneticData {
    static let categories: [VietnamesePhoneticCategory] = [
        VietnamesePhoneticCategory(
            id: "ending_s_z",
            title: "1. Âm Đuôi Gió (/s/, /z/, /ʃ/, /tʃ/)",
            subtitle: "Tránh lỗi nuốt âm cuối đặc trưng của người Việt",
            icon: "wind",
            color: Color.blue,
            examples: [
                PhoneticExampleWord(word: "Miss", ipa: "/mɪs/", meaning: "Nhớ/nhỡ", tip: "Khép nhẹ hai hàm răng, xì hơi mạnh qua kẽ răng."),
                PhoneticExampleWord(word: "Please", ipa: "/pliːz/", meaning: "Làm ơn", tip: "Rung dây thanh quản khi phát âm âm /z/ cuối."),
                PhoneticExampleWord(word: "Watch", ipa: "/wɒtʃ/", meaning: "Xem/đồng hồ", tip: "Chu tròn môi và bật mạnh âm /tʃ/ dứt khoát."),
                PhoneticExampleWord(word: "Change", ipa: "/tʃeɪndʒ/", meaning: "Thay đổi", tip: "Bật âm /dʒ/ kèm rung cổ họng rõ ràng."),
                PhoneticExampleWord(word: "Office", ipa: "/ˈɒfɪs/", meaning: "Văn phòng", tip: "Nhớ âm /s/ đuôi, không đọc 'o-fit'.")
            ]
        ),
        VietnamesePhoneticCategory(
            id: "ed_endings",
            title: "2. Đuôi Quá Khứ (-ed Endings)",
            subtitle: "3 quy tắc phát âm /t/, /d/, và /ɪd/",
            icon: "clock.arrow.circlepath",
            color: Color.purple,
            examples: [
                PhoneticExampleWord(word: "Worked", ipa: "/wɜːkt/", meaning: "Đã làm", tip: "Âm /k/ vô thanh nên -ed đọc là /t/."),
                PhoneticExampleWord(word: "Played", ipa: "/pleɪd/", meaning: "Đã chơi", tip: "Nguyên âm hữu thanh nên -ed đọc là /d/."),
                PhoneticExampleWord(word: "Wanted", ipa: "/ˈwɒntɪd/", meaning: "Đã muốn", tip: "Tận cùng là /t/ nên đọc là /ɪd/."),
                PhoneticExampleWord(word: "Decided", ipa: "/dɪˈsaɪdɪd/", meaning: "Đã quyết định", tip: "Tận cùng là /d/ nên đọc là /ɪd/."),
                PhoneticExampleWord(word: "Stopped", ipa: "/stɒpt/", meaning: "Đã dừng lại", tip: "Bật /p/ rồi bật ngay /t/ dứt khoát.")
            ]
        ),
        VietnamesePhoneticCategory(
            id: "th_sounds",
            title: "3. Âm Cắn Lưỡi (/θ/ & /ð/)",
            subtitle: "Đặt lưỡi giữa 2 hàm răng, đẩy luồng hơi nhẹ",
            icon: "mouth.fill",
            color: Color.teal,
            examples: [
                PhoneticExampleWord(word: "Think", ipa: "/θɪŋk/", meaning: "Suy nghĩ", tip: "Kẹp đầu lưỡi giữa 2 hàm răng, thổi luồng hơi nhẹ."),
                PhoneticExampleWord(word: "Thanks", ipa: "/θæŋks/", meaning: "Cảm ơn", tip: "Không đọc là 'xanh' hay 'tanh'."),
                PhoneticExampleWord(word: "Together", ipa: "/təˈɡeðər/", meaning: "Cùng nhau", tip: "Âm /ð/ rung dây thanh quản ở giữa từ."),
                PhoneticExampleWord(word: "Breathe", ipa: "/briːð/", meaning: "Hít thở", tip: "Kéo dài nguyên âm /iː/ rồi kết thúc bằng /ð/ rung."),
                PhoneticExampleWord(word: "Three", ipa: "/θriː/", meaning: "Số 3", tip: "Kẹp lưỡi phát âm /θ/ rồi cuộn lưỡi đọc /r/.")
            ]
        ),
        VietnamesePhoneticCategory(
            id: "vowel_pairs",
            title: "4. Cặp Nguyên Âm Dễ Nhầm (Dài vs Ngắn)",
            subtitle: "Phân biệt nguyên âm căng (long) và thả lỏng (short)",
            icon: "arrow.left.arrow.right",
            color: Color.orange,
            examples: [
                PhoneticExampleWord(word: "Sheep", ipa: "/ʃiːp/", meaning: "Con cừu (dài)", tip: "Căng khóe miệng như mỉm cười khi phát âm /iː/."),
                PhoneticExampleWord(word: "Ship", ipa: "/ʃɪp/", meaning: "Tàu thủy (ngắn)", tip: "Thả lỏng hàm dưới, phát âm /ɪ/ nhanh và dứt khoát."),
                PhoneticExampleWord(word: "Bad", ipa: "/bæd/", meaning: "Tồi tệ (/æ/)", tip: "Mở rộng miệng cả chiều ngang lẫn chiều dọc."),
                PhoneticExampleWord(word: "Bed", ipa: "/bed/", meaning: "Cái giường (/e/)", tip: "Miệng mở vừa phải, phát âm /e/ tự nhiên."),
                PhoneticExampleWord(word: "Leave", ipa: "/liːv/", meaning: "Rời đi (dài)", tip: "Nguyên âm /iː/ kéo dài hơn từ 'live'.")
            ]
        ),
        VietnamesePhoneticCategory(
            id: "clusters",
            title: "5. Phụ Âm Kép (Consonant Blends)",
            subtitle: "Không chèn thêm nguyên âm thừa ở giữa",
            icon: "bolt.fill",
            color: Color.indigo,
            examples: [
                PhoneticExampleWord(word: "Street", ipa: "/striːt/", meaning: "Đường phố", tip: "Nối liền /s/ - /t/ - /r/, không đọc 'xì-tơ-rít'."),
                PhoneticExampleWord(word: "Spring", ipa: "/sprɪŋ/", meaning: "Mùa xuân", tip: "Lướt nhanh /s/ -> /p/ -> /r/ thành một khối âm."),
                PhoneticExampleWord(word: "Clean", ipa: "/kliːn/", meaning: "Sạch sẽ", tip: "Bật /k/ và đầu lưỡi chạm vòm họng đọc /l/ ngay."),
                PhoneticExampleWord(word: "Practice", ipa: "/ˈpræktɪs/", meaning: "Luyện tập", tip: "Nhấn âm 1, nối mượt /pr/ và có âm /s/ cuối.")
            ]
        ),
        VietnamesePhoneticCategory(
            id: "word_stress",
            title: "6. Trọng Âm Từ Đa Âm Tiết",
            subtitle: "Nói cao hơn, to hơn và ngân dài hơn ở âm nhấn",
            icon: "target",
            color: Color.red,
            examples: [
                PhoneticExampleWord(word: "Photograph", ipa: "/ˈfəʊtəɡrɑːf/", meaning: "Bức ảnh", tip: "Trọng âm rơi vào âm tiết đầu tiên PHO-to-graph."),
                PhoneticExampleWord(word: "Photographer", ipa: "/fəˈtɒɡrəfər/", meaning: "Nhiếp ảnh gia", tip: "Đổi trọng âm sang âm tiết thứ 2 pho-TO-gra-pher!"),
                PhoneticExampleWord(word: "Develop", ipa: "/dɪˈveləp/", meaning: "Phát triển", tip: "Trọng âm rơi vào âm thứ 2 de-VE-lop."),
                PhoneticExampleWord(word: "Comfortable", ipa: "/ˈkʌmftəbl/", meaning: "Thoải mái", tip: "Chỉ phát âm 3 âm tiết COMF-ter-ble, nhấn âm 1.")
            ]
        )
    ]
}
