//
//  PronunciationDrillSheet.swift
//  English Corrector
//
//

import SwiftUI
import AVFoundation
import Speech

public struct PronunciationDrillSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let initialResult: PronunciationAssessmentResult
    public let initialSelectedWord: WordPronunciationScore?

    @State private var currentResult: PronunciationAssessmentResult
    @State private var selectedWord: WordPronunciationScore?
    @State private var isPlayingSample = false
    @State private var isPlayingSlow = false

    // Real-time Retry Speaking
    @StateObject private var speechRecognizer = SpeechRecognizerManager()
    @State private var isRecordingRetry = false
    @State private var retryTranscript = ""
    @State private var isEvaluatingRetry = false
    @State private var retrySuccessCelebration = false

    public init(
        result: PronunciationAssessmentResult,
        selectedWord: WordPronunciationScore? = nil
    ) {
        self.initialResult = result
        self.initialSelectedWord = selectedWord
        _currentResult = State(initialValue: result)
        _selectedWord = State(initialValue: selectedWord ?? result.words.first(where: { $0.level != .excellent }) ?? result.words.first)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Score Card
                    overallHeaderCard

                    // Interactive Sentence Bar (Tap any word to switch drill focus)
                    sentenceWordPickerBar

                    if let word = selectedWord {
                        // Word Phonetic & Syllables Card
                        wordPhoneticCard(for: word)

                        // Mouth & Tongue Articulation Tip Card
                        if let tip = word.mouthTip, !tip.isEmpty {
                            mouthTipCard(tip: tip, description: word.errorDescription)
                        }

                        // Listen to Native Model Audio (Normal & Slow)
                        audioListenSection(for: word)

                        // Real-time Retry Microphone Section
                        interactiveRetrySection(for: word)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(AppTheme.Surface.background.ignoresSafeArea())
            .navigationTitle("Luyện Phát Âm Chuyên Sâu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        stopAllAudio()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p500)
                }
            }
            .onDisappear {
                stopAllAudio()
            }
        }
    }

    // MARK: - 1. Overall Header Card
    private var overallHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Neutral.n200, lineWidth: 6)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: CGFloat(currentResult.overallScore) / 100.0)
                    .stroke(
                        currentResult.overallLevel.color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)

                VStack(spacing: 0) {
                    Text("\(currentResult.overallScore)")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                    Text("%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: currentResult.overallLevel.iconName)
                        .foregroundStyle(currentResult.overallLevel.color)
                    Text(currentResult.overallLevel.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(currentResult.overallLevel.color)
                }

                Text(currentResult.summaryFeedback)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Neutral.n600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))
    }

    // MARK: - 2. Sentence Word Picker Bar
    private var sentenceWordPickerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chạm vào từ để xem chi tiết & luyện lại:")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.Neutral.n600)

            FlowLayout(spacing: 6) {
                ForEach(currentResult.words) { item in
                    let isCurrent = (selectedWord?.id == item.id)

                    Button {
                        selectWord(item)
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.word)
                                .font(.system(size: 14, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? .white : item.level.color)

                            Circle()
                                .fill(isCurrent ? .white : item.level.color)
                                .frame(width: 5, height: 5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isCurrent ? item.level.color : item.level.badgeBackgroundColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isCurrent ? item.level.color : item.level.color.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))
    }

    // MARK: - 3. Word Phonetic Card
    private func wordPhoneticCard(for word: WordPronunciationScore) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(AppTheme.Neutral.n900)

                    if !word.ipa.isEmpty {
                        Text(word.ipa)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.Primary.p500)
                    }
                }

                Spacer()

                // Word score pill
                HStack(spacing: 4) {
                    Image(systemName: word.level.iconName)
                    Text("\(word.score)% • \(word.level.title)")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(word.level.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(word.level.badgeBackgroundColor)
                .clipShape(Capsule())
            }

            if word.level != .excellent {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(word.level.color)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lỗi nhận diện: \(word.errorType.labelVi)")
                            .font(.caption.bold())
                            .foregroundStyle(word.level.color)

                        if let desc = word.errorDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.Neutral.n800)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(word.level.badgeBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(word.level.color.opacity(0.3), lineWidth: 1))
            }

            // Syllables Breakdown with stress highlight
            if !word.syllables.isEmpty {
                Divider()

                HStack(spacing: 8) {
                    Text("Âm tiết:")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n500)

                    let parts = word.syllables.components(separatedBy: "-")
                    HStack(spacing: 4) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, syllable in
                            let isStressed = !word.stressedSyllable.isEmpty &&
                                syllable.lowercased().contains(word.stressedSyllable.lowercased())

                            Text(syllable)
                                .font(.system(size: 13, weight: isStressed ? .bold : .medium))
                                .foregroundStyle(isStressed ? .white : AppTheme.Neutral.n800)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isStressed ? AppTheme.Primary.p500 : AppTheme.Neutral.n200)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if !word.stressedSyllable.isEmpty {
                        Text("(Trọng âm: '\(word.stressedSyllable)')")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Primary.p500)
                    }

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(word.level.color.opacity(0.4), lineWidth: 1.5))
    }

    // MARK: - 4. Mouth & Tongue Articulation Tip Card
    private func mouthTipCard(tip: String, description: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(AppTheme.Highlight.h600)
                Text("Mẹo Khẩu Hình & Cách Đặt Lưỡi")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Neutral.n900)
            }

            if let desc = description, !desc.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text(desc)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Neutral.n800)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(AppTheme.Primary.p500)
                Text(tip)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Neutral.n700)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Highlight.h50.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Highlight.h500.opacity(0.3)))
    }

    // MARK: - 5. Audio Listen Section (Normal 1.0x & Slow 0.6x)
    private func audioListenSection(for word: WordPronunciationScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nghe phát âm chuẩn người bản xứ:")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.Neutral.n600)

            HStack(spacing: 12) {
                // Button 1: Normal Speed (1.0x)
                Button {
                    playWordSample(word.cleanWord, slow: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: (isPlayingSample && !isPlayingSlow) ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        Text("Tốc độ chuẩn (1.0x)")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.Primary.p500)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                // Button 2: Slow Speed (0.6x)
                Button {
                    playWordSample(word.cleanWord, slow: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: (isPlayingSample && isPlayingSlow) ? "speaker.wave.3.fill" : "tortoise.fill")
                        Text("Nghe chậm (0.6x)")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.Primary.p300, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))
    }

    // MARK: - 6. Real-time Retry Microphone Section
    private func interactiveRetrySection(for word: WordPronunciationScore) -> some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "mic.badge.plus")
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Luyện nói lại ngay tại chỗ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                Spacer()

                if retrySuccessCelebration {
                    Text("🎉 Xuất sắc! Phát âm chuẩn")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Semantic.success)
                }
            }

            if !retryTranscript.isEmpty {
                VStack(spacing: 4) {
                    Text("Hệ thống nhận diện bạn vừa nói:")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n500)

                    Text("\"\(retryTranscript)\"")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }
                .padding(.vertical, 4)
            }

            // Retry Microphone Record Button
            Button {
                toggleRetryRecording(for: word)
            } label: {
                HStack(spacing: 8) {
                    if isEvaluatingRetry {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Đang phân tích âm học...")
                            .font(.system(size: 14, weight: .bold))
                    } else if isRecordingRetry {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                        Text("Đang lắng nghe... Bấm để kết thúc")
                            .font(.system(size: 14, weight: .bold))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Bấm Micro để nói lại từ \"\(word.cleanWord)\"")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    if isRecordingRetry {
                        Color.red
                    } else {
                        LinearGradient(
                            colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: (isRecordingRetry ? Color.red : AppTheme.Primary.p500).opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isEvaluatingRetry)
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))
    }

    // MARK: - Actions
    private func selectWord(_ word: WordPronunciationScore) {
        stopAllAudio()
        selectedWord = word
        retryTranscript = ""
        retrySuccessCelebration = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func playWordSample(_ text: String, slow: Bool) {
        stopAllAudio()
        isPlayingSample = true
        isPlayingSlow = slow

        let rateMultiplier: Float = slow ? 0.60 : 1.0

        SpeechSynthesizerManager.shared.speakWithCallback(text, rateMultiplier: rateMultiplier) {
            self.isPlayingSample = false
            self.isPlayingSlow = false
        }
    }

    private func toggleRetryRecording(for word: WordPronunciationScore) {
        if isRecordingRetry {
            finishRetryAndEvaluate(for: word)
        } else {
            startRetryRecording()
        }
    }

    private func startRetryRecording() {
        stopAllAudio()
        retryTranscript = ""
        retrySuccessCelebration = false
        isRecordingRetry = true

        speechRecognizer.startRecording(
            existingText: "",
            onUpdate: { updated in
                self.retryTranscript = updated
            },
            onError: { err in
                self.isRecordingRetry = false
                print("DEBUG: Retry mic error: \(err)")
            }
        )
    }

    private func finishRetryAndEvaluate(for word: WordPronunciationScore) {
        speechRecognizer.stopRecording()
        isRecordingRetry = false
        isEvaluatingRetry = true

        let spoken = retryTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = speechRecognizer.latestSegments

        Task {
            let updatedWord = await PronunciationAssessmentService.shared.assessSingleWord(
                targetWord: word.cleanWord,
                spokenTranscript: spoken.isEmpty ? word.cleanWord : spoken,
                acousticSegments: segments
            )

            await MainActor.run {
                self.isEvaluatingRetry = false
                self.selectedWord = updatedWord

                // Update in full sentence result
                if let idx = self.currentResult.words.firstIndex(where: { $0.id == word.id }) {
                    self.currentResult.words[idx] = updatedWord
                    let total = self.currentResult.words.reduce(0) { $0 + $1.score }
                    self.currentResult.overallScore = total / self.currentResult.words.count
                    self.currentResult.overallLevel = self.currentResult.overallScore >= 85 ? .excellent : (self.currentResult.overallScore >= 50 ? .fair : .poor)
                }

                if updatedWord.score >= 85 {
                    self.retrySuccessCelebration = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
        }
    }

    private func stopAllAudio() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        isRecordingRetry = false
        isPlayingSample = false
        isPlayingSlow = false
        SpeechSynthesizerManager.shared.stop()
    }
}

// MARK: - Flow Layout Helper for Wrap-around Words
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
