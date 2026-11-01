//
//  LiveVoiceConversationScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Roleplay Scenarios

struct VoiceRoleplayScenario: Identifiable, Equatable {
    let id: String
    let title: String
    let vietnameseSubtitle: String
    let icon: String
    let badgeText: String
    let contextDescription: String
    let starterQuestion: String
    let starterReplies: [String]

    static let presets: [VoiceRoleplayScenario] = [
        VoiceRoleplayScenario(
            id: "free_talk",
            title: "Daily Free Talk",
            vietnameseSubtitle: "Trò chuyện tự do hằng ngày cùng AI Coach",
            icon: "waveform.and.mic",
            badgeText: "Mọi trình độ",
            contextDescription: """
            Have a natural, friendly daily voice conversation in English.
            Fix grammar mistakes gently, suggest natural phrasing, and ask engaging follow-up questions to keep the user talking.
            """,
            starterQuestion: "Hey there! How is your day going so far? Tell me something interesting you did today.",
            starterReplies: [
                "My day is going pretty well, I just finished my work.",
                "It's been a busy day, but I'm feeling good now.",
                "Honestly, I'm a bit tired today and just want to relax."
            ]
        ),
        VoiceRoleplayScenario(
            id: "job_interview",
            title: "Job Interview Practice",
            vietnameseSubtitle: "Đóng vai nhà tuyển dụng phỏng vấn xin việc",
            icon: "briefcase.fill",
            badgeText: "Công việc",
            contextDescription: """
            Roleplay as a friendly but professional hiring manager interviewing the user for a role.
            Help the user refine their answers to sound confident, professional, and grammatically accurate, then ask the next interview question.
            """,
            starterQuestion: "Welcome! Thanks for joining the interview today. To start off, could you tell me a little bit about yourself and your background?",
            starterReplies: [
                "Sure! I have been working as a software developer for the past two years.",
                "Thank you for having me. I specialize in product design and user research.",
                "I'm a recent graduate passionate about building mobile applications."
            ]
        ),
        VoiceRoleplayScenario(
            id: "cafe_ordering",
            title: "Ordering at a Cafe & Restaurant",
            vietnameseSubtitle: "Gọi đồ uống, món ăn và yêu cầu đặc biệt",
            icon: "cup.and.saucer.fill",
            badgeText: "Đời sống",
            contextDescription: """
            Roleplay as a friendly barista or waiter at a cozy English cafe.
            Take the user's order, ask about size/preferences/dietary needs, and help them sound like a native speaker when ordering.
            """,
            starterQuestion: "Hi there! Welcome to Morning Brew Cafe. What can I get started for you today?",
            starterReplies: [
                "Can I get a medium iced latte with oat milk, please?",
                "I'd like to order a cappuccino and a croissant for here.",
                "What do you recommend if I want something not too sweet?"
            ]
        ),
        VoiceRoleplayScenario(
            id: "airport_travel",
            title: "Airport & Hotel Check-in",
            vietnameseSubtitle: "Làm thủ tục sân bay, hải quan và nhận phòng",
            icon: "airplane.departure",
            badgeText: "Du lịch",
            contextDescription: """
            Roleplay as an airport check-in agent, immigration officer, or hotel receptionist helping an international traveler.
            Guide the conversation through realistic travel situations.
            """,
            starterQuestion: "Good afternoon! May I see your passport and booking confirmation, please? Where are you flying to today?",
            starterReplies: [
                "Here is my passport. I'm flying to Tokyo for aone-week vacation.",
                "Sure, here you go. Could I get a window seat if possible?",
                "I have a connecting flight and I'd like to check this suitcase."
            ]
        ),
        VoiceRoleplayScenario(
            id: "work_standup",
            title: "Workplace Meeting & Standup",
            vietnameseSubtitle: "Báo cáo tiến độ dự án và thảo luận cùng đồng nghiệp",
            icon: "person.3.fill",
            badgeText: "Công sở",
            contextDescription: """
            Roleplay as a supportive team lead in a daily standup or project sync meeting.
            Ask about what the user accomplished, what they are working on next, and any blockers they are facing.
            """,
            starterQuestion: "Good morning! Let's do a quick sync. How is your current task progressing, and are you running into any blockers?",
            starterReplies: [
                "Everything is on track. I finished the UI yesterday and I'm testing it today.",
                "I made good progress, but I'm waiting for the API specs from the backend team.",
                "I'm almost done with the feature and should be ready for code review this afternoon."
            ]
        ),
        VoiceRoleplayScenario(
            id: "small_talk",
            title: "Small Talk & Making Friends",
            vietnameseSubtitle: "Làm quen bạn mới và bắt chuyện tự nhiên",
            icon: "sparkles",
            badgeText: "Giao tiếp",
            contextDescription: """
            Roleplay as a friendly native speaker meeting the user for the first time at a community event or coffee shop.
            Practice natural small talk about hobbies, movies, travel, and weekend plans.
            """,
            starterQuestion: "Hi! Great event, isn't it? Is this your first time coming to this meetup?",
            starterReplies: [
                "Yes, it's my first time here! Everyone seems really friendly.",
                "I've been here once before. What brought you to the event today?",
                "Yeah, I just moved to this area recently and wanted to meet new people."
            ]
        )
    ]
}

// MARK: - Voice Speed & Subtitle Modes

enum VoiceSpeechSpeed: Float, CaseIterable, Identifiable {
    case slow = 0.80
    case normal = 1.0
    case fast = 1.15

    var id: Float { rawValue }

    var label: String {
        switch self {
        case .slow:
            return "0.8x Chậm"
        case .normal:
            return "1.0x Chuẩn"
        case .fast:
            return "1.15x Nhanh"
        }
    }

    var shortLabel: String {
        switch self {
        case .slow:
            return "0.8x"
        case .normal:
            return "1.0x"
        case .fast:
            return "1.15x"
        }
    }
}

enum VoiceSubtitleMode: String, CaseIterable, Identifiable {
    case english = "Phụ đề Tiếng Anh"
    case bilingual = "Song ngữ Anh - Việt"
    case blindListening = "Ẩn chữ (Luyện nghe)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .english:
            return "captions.bubble"
        case .bilingual:
            return "character.bubble.fill"
        case .blindListening:
            return "ear.and.waveform"
        }
    }
}

// MARK: - Live Voice Conversation Screen

struct LiveVoiceConversationScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var conversation: ConversationModel

    @Query private var vocabularyNotes: [VocabularyNoteModel]

    @StateObject private var speechRecognizer = SpeechRecognizerManager()
    @ObservedObject private var tts = SpeechSynthesizerManager.shared

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue
    @AppStorage("voiceHandsFreeEnabled") private var isHandsFreeMode = true
    @AppStorage("voiceSubtitleMode") private var subtitleModeRawValue = VoiceSubtitleMode.bilingual.rawValue

    @State private var speechSpeed: VoiceSpeechSpeed = .normal
    @State private var liveTranscript = ""
    @State private var isSendingToAI = false
    @State private var isBlindSubtitleRevealed = false
    @State private var showCorrectionDetails = false
    @State private var isLastSpokenTurnCleared = true
    @State private var showHints = true

    @State private var aiVietnameseTranslation: String?
    @State private var isTranslatingAITurn = false

    @State private var silenceTimerTask: Task<Void, Never>?
    @State private var toastMessage = ""
    @State private var showToast = false

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var subtitleMode: VoiceSubtitleMode {
        get { VoiceSubtitleMode(rawValue: subtitleModeRawValue) ?? .bilingual }
        nonmutating set { subtitleModeRawValue = newValue.rawValue }
    }

    private var savedVocabularyWords: Set<String> {
        Set(vocabularyNotes.map(\.normalizedWord))
    }

    private var sortedMessages: [MessageModel] {
        conversation.messages.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private var latestAIMessage: MessageModel? {
        sortedMessages.last(where: { !$0.isUser })
    }

    private var latestUserMessage: MessageModel? {
        sortedMessages.last(where: { $0.isUser })
    }

    private var currentAISpokenLine: String {
        guard let ai = latestAIMessage else {
            return "Hi there! Tap the microphone below and start speaking in English."
        }
        if let q = ai.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            return q
        }
        if let nat = ai.natural?.trimmingCharacters(in: .whitespacesAndNewlines), !nat.isEmpty {
            return nat
        }
        return ai.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSuggestedReplies: [String] {
        (latestAIMessage?.suggestedReplies ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isAISpeakingNow: Bool {
        tts.speakingText != nil
    }

    private var currentVoiceStatusTitle: String {
        if isSendingToAI {
            return "AI đang suy nghĩ..."
        } else if isAISpeakingNow {
            return "AI Coach đang nói..."
        } else if speechRecognizer.isRecording {
            return hasLiveTranscriptText ? "Đang nghe • Bấm Gửi hoặc Xoá nói lại" : "Đang nghe bạn nói..."
        } else if hasLiveTranscriptText {
            return "Đã nói xong • Bấm Gửi hoặc Xoá nói lại"
        } else {
            return "Sẵn sàng lắng nghe"
        }
    }

    var body: some View {
        ZStack {
            // Subtle gradient background for live voice room
            LinearGradient(
                colors: [
                    AppTheme.Surface.appBackground,
                    AppTheme.Primary.p50.opacity(0.65),
                    AppTheme.Surface.appBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topHeaderBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        // 1. VOICE ORB
                        VoicePulseOrbView(
                            isListening: speechRecognizer.isRecording,
                            isThinking: isSendingToAI,
                            isAISpeaking: isAISpeakingNow,
                            statusText: currentVoiceStatusTitle,
                            onTapOrb: {
                                handleOrbTap()
                            }
                        )
                        .padding(.top, 6)

                        // 2. AI CURRENT SPOKEN TURN CARD
                        aiSpokenSubtitleCard

                        // 3. USER LAST TURN & GENTLE CORRECTION CARD
                        // Cleared automatically when AI responds with a new question
                        if let latestUser = latestUserMessage, !isLastSpokenTurnCleared {
                            userLastTurnCorrectionCard(userMsg: latestUser, aiMsg: latestAIMessage)
                        } else if let latestUser = latestUserMessage,
                                  let latestAI = latestAIMessage,
                                  latestAI.createdAt >= latestUser.createdAt,
                                  !speechRecognizer.isRecording,
                                  !hasLiveTranscriptText {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isLastSpokenTurnCleared = false
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "sparkles")
                                            .font(.caption2.bold())
                                        Text("Xem góp ý câu vừa trả lời")
                                            .font(.caption.bold())
                                    }
                                    .foregroundStyle(AppTheme.Primary.p500)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.Primary.p50)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                        }

                        // 4. HINTS / SUGGESTED REPLIES
                        if !currentSuggestedReplies.isEmpty {
                            hintsSectionCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                Divider()
                    .overlay(AppTheme.Surface.border)

                bottomCallControlArea
            }
        }
        .overlay(alignment: .top) {
            if showToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.Semantic.success)
                    Text(toastMessage)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppTheme.Neutral.n900.opacity(0.9))
                .clipShape(Capsule())
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            startInitialGreetingIfNeeded()
        }
        .onDisappear {
            stopAllAudioAndTimers()
        }
        .onChange(of: currentAISpokenLine) { _, newLine in
            silenceTimerTask?.cancel()
            liveTranscript = ""
            isLastSpokenTurnCleared = true
            showCorrectionDetails = false
            isBlindSubtitleRevealed = false
            aiVietnameseTranslation = nil
            if subtitleMode == .bilingual {
                fetchTranslationForCurrentAITurn(newLine)
            }
        }
        .onChange(of: subtitleModeRawValue) { _, _ in
            if subtitleMode == .bilingual, aiVietnameseTranslation == nil {
                fetchTranslationForCurrentAITurn(currentAISpokenLine)
            }
        }
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            speechRecognizer.isRecording
                            ? AppTheme.Semantic.success
                            : (isAISpeakingNow ? AppTheme.Primary.p500 : AppTheme.Neutral.n400)
                        )
                        .frame(width: 8, height: 8)

                    Text(conversation.title.isEmpty ? "Live Voice AI" : conversation.title)
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .lineLimit(1)
                }

                Text(currentVoiceStatusTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            Spacer()

            // Speed Menu
            Menu {
                ForEach(VoiceSpeechSpeed.allCases) { speed in
                    Button {
                        speechSpeed = speed
                        speakCurrentAITurn(autoListenAfter: false)
                    } label: {
                        Label(
                            speed.label,
                            systemImage: speechSpeed == speed ? "checkmark.circle.fill" : "speedometer"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                    Text(speechSpeed.shortLabel)
                }
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Primary.p700)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppTheme.Surface.card)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                }
            }

            // Subtitle Mode Menu
            Menu {
                ForEach(VoiceSubtitleMode.allCases) { mode in
                    Button {
                        subtitleMode = mode
                    } label: {
                        Label(
                            mode.rawValue,
                            systemImage: subtitleMode == mode ? "checkmark.circle.fill" : mode.icon
                        )
                    }
                }
            } label: {
                Image(systemName: subtitleMode.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Accent.a600)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                    }
            }

            // Close Call Button
            Button {
                stopAllAudioAndTimers()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n700)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - AI Spoken Subtitle Card

    private var aiSpokenSubtitleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("AI Coach", systemImage: "waveform")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Text("• Chạm vào từ bất kỳ để tra nhanh")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n400)

                Spacer()

                Button {
                    speakCurrentAITurn(autoListenAfter: false)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAISpeakingNow ? "stop.fill" : "speaker.wave.2.fill")
                        Text(isAISpeakingNow ? "Dừng" : "Nghe lại")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Primary.p500)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if subtitleMode == .blindListening && !isBlindSubtitleRevealed {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBlindSubtitleRevealed = true
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.Primary.p500)
                        Text("Đang ẩn phụ đề để luyện nghe phản xạ")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n700)
                        Text("Chạm vào đây để hiển thị câu tiếng Anh")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                LightPickableSentenceText(
                    sentence: currentAISpokenLine,
                    font: .body.weight(.semibold),
                    foregroundColor: AppTheme.Neutral.n900,
                    savedWords: savedVocabularyWords,
                    onSaveVocabulary: { word, source in
                        saveVocabulary(word, sourceText: source)
                    }
                )
            }

            if subtitleMode == .bilingual {
                Divider()
                    .overlay(AppTheme.Surface.border)

                if isTranslatingAITurn {
                    HStack(spacing: 6) {
                        AppThemeLoadingView(customSize: 16)
                        Text("Đang dịch nghĩa tiếng Việt...")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                } else if let translation = aiVietnameseTranslation, !translation.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Accent.a600)
                            .padding(.top, 2)
                        Text(translation)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isAISpeakingNow ? AppTheme.Primary.p500 : AppTheme.Surface.border,
                    lineWidth: isAISpeakingNow ? 2.0 : 1.2
                )
        }
        .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 4)
    }

    // MARK: - User Last Turn & Gentle Correction Card

    @ViewBuilder
    private func userLastTurnCorrectionCard(userMsg: MessageModel, aiMsg: MessageModel?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Câu bạn vừa nói", systemImage: "person.wave.2.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Neutral.n500)

                Spacer()

                if let aiMsg, (aiMsg.fixed != nil || aiMsg.natural != nil) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCorrectionDetails.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showCorrectionDetails ? "Thu gọn" : "Chi tiết sửa lỗi")
                            Image(systemName: showCorrectionDetails ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLastSpokenTurnCleared = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
                .buttonStyle(.plain)
            }

            Text("\"\(userMsg.text)\"")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Neutral.n700)

            if let aiMsg, aiMsg.createdAt >= userMsg.createdAt {
                let bestNatural = (aiMsg.natural ?? aiMsg.fixed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !bestNatural.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Semantic.success)
                            .padding(.top, 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cách diễn đạt tự nhiên:")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Semantic.success)

                            Text(bestNatural)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Neutral.n900)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        SpeakButton(
                            text: bestNatural,
                            font: .caption,
                            activeColor: AppTheme.Semantic.success
                        )

                        Button {
                            saveNote(
                                text: bestNatural,
                                originalText: userMsg.text,
                                context: aiMsg.fixed ?? bestNatural,
                                isExplanation: false,
                                sourceMessageID: aiMsg.id
                            )
                        } label: {
                            Image(systemName: "plus.square.on.square")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if showCorrectionDetails {
                    let alternatives = (aiMsg.alternativeExpressions ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let explanations = (aiMsg.explanations ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    if !alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cách nói khác:")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Accent.a600)

                            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                                HStack(spacing: 8) {
                                    Text("• \(alt)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.Neutral.n900)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    SpeakButton(
                                        text: alt,
                                        font: .caption2,
                                        activeColor: AppTheme.Accent.a600
                                    )
                                }
                            }
                        }
                        .padding(10)
                        .background(AppTheme.Accent.a50.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !explanations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Giải thích ngữ pháp:")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Primary.p700)

                            ForEach(Array(explanations.enumerated()), id: \.offset) { _, exp in
                                Text("• \(exp)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Neutral.n700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.1)
        }
    }

    // MARK: - Hints Section Card

    private var hintsSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gợi ý câu trả lời (đọc theo hoặc chạm để gửi)", systemImage: "lightbulb.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Accent.a600)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHints.toggle()
                    }
                } label: {
                    Text(showHints ? "Ẩn" : "Hiện")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                }
                .buttonStyle(.plain)
            }

            if showHints {
                ForEach(Array(currentSuggestedReplies.enumerated()), id: \.offset) { _, hint in
                    HStack(spacing: 8) {
                        Button {
                            sendSpokenTurn(hint)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "mic.badge.plus")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Primary.p500)
                                    .padding(.top, 2)

                                Text(hint)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Neutral.n900)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)

                        SpeakButton(
                            text: hint,
                            font: .caption,
                            activeColor: AppTheme.Primary.p500
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.1)
        }
    }

    // MARK: - Bottom Call Control Area

    private var hasLiveTranscriptText: Bool {
        !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bottomCallControlArea: some View {
        VStack(spacing: 12) {
            // Live spoken transcript preview / editable field
            if speechRecognizer.isRecording || hasLiveTranscriptText {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: speechRecognizer.isRecording ? "waveform" : "text.bubble.fill")
                            .font(.caption.bold())
                            .foregroundStyle(speechRecognizer.isRecording ? AppTheme.Semantic.success : AppTheme.Primary.p500)

                        TextField("Đang nghe bạn nói tiếng Anh...", text: $liveTranscript, axis: .vertical)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1...3)
                    }

                    HStack(spacing: 10) {
                        if speechRecognizer.isRecording {
                            GradientWaveRibbonCanvas(
                                colors: [
                                    AppTheme.Semantic.success,
                                    AppTheme.Primary.p500,
                                    AppTheme.Accent.a500
                                ],
                                isActive: true,
                                amplitudeMultiplier: 0.55
                            )
                            .frame(height: 18)
                        } else {
                            Text("Đã nói xong • Bạn có thể gửi hoặc xoá để nói lại")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                        }

                        if hasLiveTranscriptText {
                            // Nút Xoá đi để nói lại
                            Button {
                                clearTranscriptAndRespeak()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Xoá nói lại")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.Semantic.error)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.Semantic.error.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            // Nút Submit gửi câu vừa nói
                            Button {
                                let textToSend = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                                sendSpokenTurn(textToSend)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Gửi")
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.Semantic.success)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSendingToAI)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: speechRecognizer.isRecording
                                ? [AppTheme.Semantic.success, AppTheme.Primary.p500, AppTheme.Accent.a500]
                                : [AppTheme.Primary.p300, AppTheme.Primary.p500],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }

            HStack(spacing: 20) {
                // Auto Hands-Free Mode Toggle
                Button {
                    isHandsFreeMode.toggle()
                    showStatusToast(isHandsFreeMode ? "Đã bật chế độ Rảnh tay tự động" : "Đã chuyển sang Chạm để nói")
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isHandsFreeMode ? "hands.and.sparkles.fill" : "hand.tap.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(isHandsFreeMode ? AppTheme.Accent.a100 : AppTheme.Surface.card)
                            .foregroundStyle(isHandsFreeMode ? AppTheme.Accent.a600 : AppTheme.Neutral.n700)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }

                        Text(isHandsFreeMode ? "Rảnh tay: BẬT" : "Thủ công")
                            .font(.caption2.bold())
                            .foregroundStyle(isHandsFreeMode ? AppTheme.Accent.a600 : AppTheme.Neutral.n500)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Primary Mic / Send Action Button
                Button {
                    handlePrimaryMicButtonTap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                (speechRecognizer.isRecording || hasLiveTranscriptText)
                                ? AppTheme.Semantic.success
                                : AppTheme.Primary.p500
                            )
                            .frame(width: 72, height: 72)
                            .shadow(
                                color: ((speechRecognizer.isRecording || hasLiveTranscriptText) ? AppTheme.Semantic.success : AppTheme.Primary.p500).opacity(0.35),
                                radius: 14,
                                x: 0,
                                y: 6
                            )

                        Image(
                            systemName: hasLiveTranscriptText
                            ? "arrow.up"
                            : (speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                        )
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSendingToAI)

                Spacer()

                // Replay AI Turn Button
                Button {
                    speakCurrentAITurn(autoListenAfter: isHandsFreeMode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isAISpeakingNow ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(isAISpeakingNow ? AppTheme.Primary.p100 : AppTheme.Surface.card)
                            .foregroundStyle(AppTheme.Primary.p500)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }

                        Text("Nghe lại AI")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.Surface.card)
    }

    // MARK: - Voice Interaction Logic

    private func startInitialGreetingIfNeeded() {
        if conversation.messages.isEmpty {
            generateInitialSituationGreetingAndSpeak()
            return
        }

        if subtitleMode == .bilingual {
            fetchTranslationForCurrentAITurn(currentAISpokenLine)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            speakCurrentAITurn(autoListenAfter: isHandsFreeMode)
        }
    }

    @MainActor
    private func generateInitialSituationGreetingAndSpeak() {
        guard !isSendingToAI else { return }
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        tts.stop()
        isSendingToAI = true

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let situationDesc = conversation.conversationDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveContext = situationDesc.isEmpty
            ? "Roleplay conversation about \(title.isEmpty ? "daily English communication" : title)."
            : situationDesc
        let provider = selectedAIModel.makeProvider()

        Task {
            do {
                let aiService = AIService(provider: provider)
                let response = try await aiService.improveEnglish(
                    userInput: "Please start our roleplay conversation in character by speaking first in English with a natural opening greeting and question that fits the situation: \(effectiveContext)",
                    context: effectiveContext,
                    recentHistory: []
                )

                await MainActor.run {
                    let openingLine: String = {
                        let q = response.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !q.isEmpty { return q }
                        let nat = response.natural.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !nat.isEmpty { return nat }
                        return "Hi! Let's start our conversation. How can I help you today?"
                    }()

                    if title.isEmpty || title == "Daily Life English" || title == "New Chat" || title == "Tình huống tuỳ chỉnh",
                       let suggestedTitle = response.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !suggestedTitle.isEmpty {
                        conversation.title = suggestedTitle
                    }

                    let starterMessage = MessageModel(
                        text: openingLine,
                        isUser: false,
                        followUpQuestion: openingLine,
                        suggestedReplies: response.suggestedReplies
                    )
                    starterMessage.conversation = conversation
                    context.insert(starterMessage)
                    try? context.save()

                    isSendingToAI = false
                    if subtitleMode == .bilingual {
                        fetchTranslationForCurrentAITurn(openingLine)
                    }
                    speakCurrentAITurn(autoListenAfter: isHandsFreeMode)
                }
            } catch {
                await MainActor.run {
                    let fallbackLine = title.isEmpty
                        ? "Hi there! Let's start our roleplay conversation. How can I help you today?"
                        : "Hi! Let's start our roleplay about \(title). How can I help you today?"
                    let starterMessage = MessageModel(
                        text: fallbackLine,
                        isUser: false,
                        followUpQuestion: fallbackLine,
                        suggestedReplies: [
                            "Hi! Thank you for speaking with me today.",
                            "Could you tell me more about this situation?"
                        ]
                    )
                    starterMessage.conversation = conversation
                    context.insert(starterMessage)
                    try? context.save()

                    isSendingToAI = false
                    speakCurrentAITurn(autoListenAfter: isHandsFreeMode)
                }
            }
        }
    }

    private func handleOrbTap() {
        if isAISpeakingNow {
            tts.stop()
            if isHandsFreeMode {
                startListeningSession()
            }
        } else if speechRecognizer.isRecording {
            handlePrimaryMicButtonTap()
        } else if !isSendingToAI {
            startListeningSession()
        }
    }

    private func handlePrimaryMicButtonTap() {
        silenceTimerTask?.cancel()

        if speechRecognizer.isRecording {
            let trimmed = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            speechRecognizer.stopRecording()
            if !trimmed.isEmpty {
                sendSpokenTurn(trimmed)
            }
        } else {
            let trimmed = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sendSpokenTurn(trimmed)
            } else {
                startListeningSession()
            }
        }
    }

    private func clearTranscriptAndRespeak() {
        silenceTimerTask?.cancel()
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        liveTranscript = ""
        startListeningSession()
    }

    private func startListeningSession() {
        guard !isSendingToAI else { return }
        tts.stop()
        silenceTimerTask?.cancel()
        liveTranscript = ""
        isLastSpokenTurnCleared = true

        speechRecognizer.startRecording(
            existingText: "",
            onUpdate: { updatedText in
                liveTranscript = updatedText
            },
            onError: { err in
                showStatusToast(err)
            }
        )
    }

    private func speakCurrentAITurn(autoListenAfter: Bool) {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        let line = currentAISpokenLine
        guard !line.isEmpty else { return }

        tts.speakWithCallback(line, rateMultiplier: speechSpeed.rawValue) {
            if autoListenAfter && !self.isSendingToAI {
                self.startListeningSession()
            }
        }
    }

    @MainActor
    private func sendSpokenTurn(_ rawText: String) {
        let userText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !isSendingToAI else { return }

        silenceTimerTask?.cancel()
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        tts.stop()

        liveTranscript = ""
        isLastSpokenTurnCleared = false
        isSendingToAI = true

        // 1. Save user message to ConversationModel
        let userMessage = MessageModel(
            text: userText,
            isUser: true
        )
        userMessage.conversation = conversation
        context.insert(userMessage)
        try? context.save()

        // 2. Prepare recent history
        let recentHistory: [String] = conversation.messages
            .filter { $0.id != userMessage.id }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .suffix(20)
            .map { msg in
                if msg.isUser {
                    return "User: \(msg.text)"
                } else {
                    let aiReply = msg.followUpQuestion ?? msg.natural ?? msg.text
                    return "Coach: \(aiReply)"
                }
            }

        let currentContext = conversation.conversationDescription
        let provider = selectedAIModel.makeProvider()

        Task {
            do {
                let aiService = AIService(provider: provider)
                let response = try await aiService.improveEnglish(
                    userInput: userText,
                    context: currentContext,
                    recentHistory: recentHistory
                )

                await MainActor.run {
                    if let updatedContext = response.updatedContext?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !updatedContext.isEmpty {
                        conversation.conversationDescription = updatedContext
                    }

                    if let suggestedTitle = response.conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !suggestedTitle.isEmpty {
                        let currentTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let userTurnCount = conversation.messages.filter(\.isUser).count
                        if currentTitle.isEmpty || currentTitle == "Daily Life English" || currentTitle == "New Chat" || userTurnCount <= 1 {
                            conversation.title = suggestedTitle
                        }
                    }

                    let aiMessage = MessageModel(
                        text: """
                        Fixed: \(response.fixed)
                        Natural: \(response.natural)
                        """,
                        isUser: false,
                        fixed: response.fixed,
                        natural: response.natural,
                        alternativeExpressions: response.alternativeExpressions,
                        explanations: response.explanations.map { $0.text },
                        explanationNoted: response.explanations.map { $0.explanation_noted ?? "" },
                        followUpQuestion: response.followUpQuestion,
                        suggestedReplies: response.suggestedReplies
                    )
                    aiMessage.conversation = conversation
                    context.insert(aiMessage)
                    try? context.save()

                    // Clear spoken sentence when AI responds with a new question
                    liveTranscript = ""
                    isLastSpokenTurnCleared = true
                    showCorrectionDetails = false
                    isSendingToAI = false
                    speakCurrentAITurn(autoListenAfter: isHandsFreeMode)
                }
            } catch {
                await MainActor.run {
                    isSendingToAI = false
                    showStatusToast("Lỗi kết nối AI: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fetchTranslationForCurrentAITurn(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let cached = QuickSentenceAnalysisCache.shared.get(sentence: trimmed) {
            aiVietnameseTranslation = cached.vietnameseTranslation
            return
        }

        isTranslatingAITurn = true
        let provider = selectedAIModel.makeSentenceStructureProvider()

        Task {
            do {
                let service = SentenceStructureAIService(provider: provider)
                let result = try await service.analyzeSentence(sentence: trimmed)
                await MainActor.run {
                    QuickSentenceAnalysisCache.shared.set(result, sentence: trimmed)
                    aiVietnameseTranslation = result.vietnameseTranslation
                    isTranslatingAITurn = false
                }
            } catch {
                await MainActor.run {
                    isTranslatingAITurn = false
                }
            }
        }
    }

    private func saveVocabulary(_ word: String, sourceText: String) {
        do {
            _ = try VocabularyNoteStore.save(
                word: word,
                sourceText: sourceText,
                sourceConversation: conversation,
                in: context
            )
            showStatusToast("Đã lưu từ vựng: \(word)")
        } catch {
            print("DEBUG: Failed to save vocabulary in voice mode: \(error)")
        }
    }

    private func saveNote(
        text: String,
        originalText: String,
        context: String,
        isExplanation: Bool,
        sourceMessageID: UUID?
    ) {
        let note = SavedNoteModel(
            text: text,
            originalText: originalText,
            originalContext: context,
            isExplanation: isExplanation,
            explanationNoted: nil,
            sourceConversationID: conversation.id,
            sourceMessageID: sourceMessageID,
            sourceConversationTitle: conversation.title
        )
        self.context.insert(note)
        try? self.context.save()
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
        showStatusToast("Đã lưu vào Noted AI")
    }

    private func showStatusToast(_ message: String) {
        withAnimation {
            toastMessage = message
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showToast = false
            }
        }
    }

    private func stopAllAudioAndTimers() {
        silenceTimerTask?.cancel()
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        tts.stop()
    }
}

// MARK: - Animated Voice Pulse Orb & Gradient Wave Ripple View

private struct VoicePulseOrbView: View {
    let isListening: Bool
    let isThinking: Bool
    let isAISpeaking: Bool
    let statusText: String
    let onTapOrb: () -> Void

    private var isActive: Bool {
        isListening || isThinking || isAISpeaking
    }

    private var activeColor: Color {
        if isListening {
            return AppTheme.Semantic.success
        } else if isThinking {
            return AppTheme.Accent.a600
        } else if isAISpeaking {
            return AppTheme.Primary.p500
        } else {
            return AppTheme.Primary.p300
        }
    }

    private var gradientPalette: [Color] {
        if isListening {
            return [
                AppTheme.Semantic.success,
                AppTheme.Primary.p500,
                AppTheme.Accent.a500,
                AppTheme.Semantic.success
            ]
        } else if isThinking {
            return [
                AppTheme.Accent.a600,
                AppTheme.Primary.p500,
                AppTheme.Secondary.s500,
                AppTheme.Accent.a600
            ]
        } else if isAISpeaking {
            return [
                AppTheme.Primary.p500,
                AppTheme.Accent.a600,
                AppTheme.Secondary.s500,
                AppTheme.Primary.p500
            ]
        } else {
            return [
                AppTheme.Primary.p300,
                AppTheme.Accent.a500,
                AppTheme.Primary.p500,
                AppTheme.Primary.p300
            ]
        }
    }

    private var centerIcon: String {
        if isThinking {
            return "sparkles"
        } else if isAISpeaking {
            return "waveform"
        } else if isListening {
            return "mic.fill"
        } else {
            return "waveform.and.mic"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTapOrb) {
                ZStack {
                    // 1. Horizontal multi-layered flowing gradient sine waves behind the orb
                    GradientWaveRibbonCanvas(
                        colors: gradientPalette,
                        isActive: isActive,
                        amplitudeMultiplier: isListening ? 1.15 : (isAISpeaking ? 1.0 : (isThinking ? 0.75 : 0.35))
                    )
                    .frame(height: 156)
                    .allowsHitTesting(false)

                    // 2. Concentric expanding gradient ripple rings + rotating aura
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let cycleSpeed = isActive ? 0.65 : 0.25

                        ZStack {
                            ForEach(0..<3, id: \.self) { index in
                                let phaseOffset = Double(index) / 3.0
                                let rawPhase = (t * cycleSpeed + phaseOffset).truncatingRemainder(dividingBy: 1.0)
                                let scale = 0.78 + rawPhase * (isActive ? 1.05 : 0.55)
                                let opacity = (1.0 - rawPhase) * (isActive ? 0.58 : 0.25)

                                Circle()
                                    .strokeBorder(
                                        AngularGradient(
                                            colors: gradientPalette,
                                            center: .center,
                                            angle: .degrees(t * 70 + Double(index) * 60)
                                        ),
                                        lineWidth: isActive ? 2.6 : 1.6
                                    )
                                    .background(
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [
                                                        activeColor.opacity(opacity * 0.35),
                                                        Color.clear
                                                    ],
                                                    center: .center,
                                                    startRadius: 10,
                                                    endRadius: 80
                                                )
                                            )
                                    )
                                    .frame(width: 96, height: 96)
                                    .scaleEffect(scale)
                                    .opacity(opacity)
                            }

                            // Rotating outer gradient glow ring
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: gradientPalette,
                                        center: .center,
                                        angle: .degrees(t * (isActive ? 120 : 45))
                                    ),
                                    lineWidth: isActive ? 3.5 : 2.0
                                )
                                .frame(width: 98, height: 98)
                                .blur(radius: isActive ? 3 : 1)
                        }
                    }

                    // 3. Core gradient orb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    gradientPalette[0],
                                    gradientPalette[1],
                                    gradientPalette[2]
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .shadow(color: activeColor.opacity(0.42), radius: 16, x: 0, y: 7)

                    if isThinking {
                        AppThemeLoadingView(customSize: 36, lineWidth: 3.6)
                    } else {
                        Image(systemName: centerIcon)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isAISpeaking || isListening)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 172)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? activeColor : AppTheme.Neutral.n500)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(activeColor.opacity(0.10))
                )
        }
    }
}

// MARK: - Multi-layered Flowing Gradient Sine Wave Canvas

private struct GradientWaveRibbonCanvas: View {
    let colors: [Color]
    let isActive: Bool
    let amplitudeMultiplier: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let midY = size.height / 2.0
                let width = size.width
                guard width > 10 else { return }

                let waveConfigs: [(freq: Double, speed: Double, ampRatio: CGFloat, lineWidth: CGFloat, opacity: Double)] = [
                    (freq: 1.6, speed: 3.4, ampRatio: 0.34, lineWidth: 3.2, opacity: isActive ? 0.85 : 0.40),
                    (freq: 2.3, speed: -2.6, ampRatio: 0.25, lineWidth: 2.4, opacity: isActive ? 0.65 : 0.30),
                    (freq: 3.1, speed: 4.2, ampRatio: 0.18, lineWidth: 1.8, opacity: isActive ? 0.50 : 0.22),
                    (freq: 1.2, speed: -1.8, ampRatio: 0.42, lineWidth: 1.5, opacity: isActive ? 0.38 : 0.16)
                ]

                let gradient = Gradient(colors: colors)
                let startPt = CGPoint(x: 0, y: midY)
                let endPt = CGPoint(x: width, y: midY)

                for (idx, cfg) in waveConfigs.enumerated() {
                    var path = Path()
                    let step: CGFloat = 4.0
                    let dynamicPulse = 0.75 + 0.25 * sin(time * 2.5 + Double(idx))
                    let maxAmp = size.height * cfg.ampRatio * amplitudeMultiplier * CGFloat(dynamicPulse)

                    var x: CGFloat = 0
                    var isFirst = true
                    while x <= width {
                        let normalizedX = Double(x / width)
                        // Bell-shaped envelope so wave tapers smoothly at both edges and peaks near the orb
                        let envelope = sin(normalizedX * .pi)
                        let angle = normalizedX * .pi * 2.0 * cfg.freq + time * cfg.speed + Double(idx) * 0.9
                        let secondary = 0.35 * cos(normalizedX * .pi * 4.0 - time * cfg.speed * 0.7)
                        let yOffset = CGFloat((sin(angle) + secondary) * envelope) * maxAmp
                        let point = CGPoint(x: x, y: midY + yOffset)

                        if isFirst {
                            path.move(to: point)
                            isFirst = false
                        } else {
                            path.addLine(to: point)
                        }
                        x += step
                    }

                    var layerContext = context
                    layerContext.opacity = cfg.opacity
                    layerContext.stroke(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: startPt,
                            endPoint: endPt
                        ),
                        style: StrokeStyle(lineWidth: cfg.lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}

// MARK: - Roleplay Scenario Picker Sheet

struct VoiceRoleplayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelectScenario: (VoiceRoleplayScenario) -> Void

    @State private var customTopicTitle = ""
    @State private var customTopicSituation = ""
    @State private var showCustomForm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Banner
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.Primary.p500)
                            .frame(width: 56, height: 56)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Giao tiếp Voice AI 2 chiều")
                                .font(.headline.bold())
                                .foregroundStyle(AppTheme.Neutral.n900)

                            Text("Chọn tình huống đóng vai để bắt đầu luyện nghe nói phản xạ cùng AI Coach")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Neutral.n500)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                    }

                    // Custom Scenario Toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCustomForm.toggle()
                        }
                    } label: {
                        HStack {
                            Label("Tự tạo tình huống đóng vai riêng", systemImage: "plus.bubble.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Accent.a600)
                            Spacer()
                            Image(systemName: showCustomForm ? "chevron.up" : "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.Accent.a600)
                        }
                        .padding(14)
                        .background(AppTheme.Accent.a50)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    if showCustomForm {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Tên chủ đề (VD: Thương lượng lương, Hỏi đường...)", text: $customTopicTitle)
                                .textFieldStyle(.roundedBorder)

                            TextField("Mô tả vai của AI (VD: AI đóng vai sếp của tôi...)", text: $customTopicSituation, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                let rawTitle = customTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                let desc = customTopicSituation.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !rawTitle.isEmpty || !desc.isEmpty else { return }
                                let effectiveTitle = rawTitle.isEmpty ? "Tình huống tuỳ chỉnh" : rawTitle
                                let effectiveDesc = desc.isEmpty
                                    ? "Roleplay conversation about \(effectiveTitle). Start in character and help the user practice speaking naturally."
                                    : desc
                                let customScenario = VoiceRoleplayScenario(
                                    id: UUID().uuidString,
                                    title: effectiveTitle,
                                    vietnameseSubtitle: desc.isEmpty ? "Tình huống tuỳ chỉnh" : desc,
                                    icon: "sparkles",
                                    badgeText: "Tuỳ chỉnh",
                                    contextDescription: effectiveDesc,
                                    starterQuestion: "",
                                    starterReplies: []
                                )
                                onSelectScenario(customScenario)
                            } label: {
                                Label("Bắt đầu tình huống này (AI nói trước)", systemImage: "speaker.wave.2.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.Accent.a600)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(
                                customTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                customTopicSituation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        .padding(14)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                        }
                    }

                    Text("Tình huống phổ biến")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n700)

                    ForEach(VoiceRoleplayScenario.presets) { scenario in
                        Button {
                            onSelectScenario(scenario)
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: scenario.icon)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.Primary.p500)
                                    .frame(width: 46, height: 46)
                                    .background(AppTheme.Primary.p50)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(scenario.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(AppTheme.Neutral.n900)

                                        Text(scenario.badgeText)
                                            .font(.caption2.bold())
                                            .foregroundStyle(AppTheme.Primary.p700)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppTheme.Primary.p50)
                                            .clipShape(Capsule())
                                    }

                                    Text(scenario.vietnameseSubtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Neutral.n500)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "waveform.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.Primary.p500)
                            }
                            .padding(14)
                            .background(AppTheme.Surface.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Chọn tình huống giao tiếp")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.Surface.appBackground)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}
