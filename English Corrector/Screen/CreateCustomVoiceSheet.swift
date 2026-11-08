//
//  CreateCustomVoiceSheet.swift
//  English Corrector
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct CreateCustomVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onVoiceCreated: ((AIVoiceProfile) -> Void)? = nil

    enum CreationTab: String, CaseIterable, Identifiable {
        case fromPrompt = "Mô tả văn bản"
        case fromAudio = "Clone từ âm thanh"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .fromPrompt: return "wand.and.stars"
            case .fromAudio: return "waveform.and.mic"
            }
        }
    }

    @State private var selectedTab: CreationTab = .fromPrompt

    // MARK: - Tab 1: Voice Design States
    @State private var voiceDescription: String = ""
    @State private var selectedGender: AIVoiceGender = .female
    @State private var selectedAccent: AIVoiceAccent = .american
    @State private var selectedPreset: VoiceExpressivenessPreset = .conversational
    @State private var isGeneratingPreviews = false
    @State private var generatedPreviews: [GeneratedVoicePreview] = []
    @State private var activePlayingPreviewId: String? = nil
    @State private var previewAudioPlayer: AVAudioPlayer? = nil
    @State private var selectedPreviewForSave: GeneratedVoicePreview? = nil
    @State private var customVoiceName: String = ""
    @State private var isSavingVoice = false

    // MARK: - Tab 2: Voice Clone States
    @State private var cloneVoiceName: String = ""
    @State private var cloneDescription: String = ""
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer? = nil
    @State private var audioRecorder: AVAudioRecorder? = nil
    @State private var recordedAudioURL: URL? = nil
    @State private var isPlayingRecordedAudio = false
    @State private var isCloningVoice = false
    @State private var isFileImporterPresented = false
    @State private var importedAudioData: Data? = nil
    @State private var importedAudioFileName: String? = nil

    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false

    private let promptInspirations: [(label: String, prompt: String, gender: AIVoiceGender, accent: AIVoiceAccent)] = [
        (
            "🇬🇧 Thầy giáo Anh quốc",
            "A charismatic 40-year-old British male English teacher with a warm, deep voice, articulate pronunciation, and reassuring pace",
            .male,
            .british
        ),
        (
            "🇺🇸 Cô giáo Mỹ năng động",
            "An energetic and friendly 28-year-old American female tutor with bright melodic intonation and clear diction",
            .female,
            .american
        ),
        (
            "🇦🇺 Bạn đàm thoại người Úc",
            "A warm and relaxed Australian male in his early 30s with conversational Australian accent and cheerful cadence",
            .male,
            .australian
        ),
        (
            "📖 Người kể chuyện trầm ấm",
            "A mature American narrator with a velvety, deep timbre, expressive pauses, and soothing rhythm",
            .male,
            .american
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 20) {
                        if selectedTab == .fromPrompt {
                            voiceDesignSection
                        } else {
                            voiceCloneSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .background(AppTheme.Surface.background.ignoresSafeArea())
            .navigationTitle("Tạo Giọng AI Tùy Chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        stopAllAudioPlayback()
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Neutral.n600)
                }
            }
            .alert("Thông báo", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Đã có lỗi xảy ra. Vui lòng kiểm tra lại kết nối mạng hoặc API Key.")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
            .onDisappear {
                stopAllAudioPlayback()
            }
        }
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(CreationTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        stopAllAudioPlayback()
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : AppTheme.Neutral.n600)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab
                        ? AppTheme.Primary.p500
                        : AppTheme.Surface.cardMuted
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.Surface.cardMuted.opacity(0.6))
        .clipShape(Capsule())
    }

    // MARK: - Tab 1: Voice Design (Text to Voice)
    private var voiceDesignSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Inspiration Chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Gợi ý phong cách phổ biến")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n600)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(promptInspirations, id: \.label) { item in
                            Button {
                                withAnimation {
                                    voiceDescription = item.prompt
                                    selectedGender = item.gender
                                    selectedAccent = item.accent
                                    customVoiceName = item.label.components(separatedBy: " ").dropFirst().joined(separator: " ")
                                }
                            } label: {
                                Text(item.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.Primary.p600)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(AppTheme.Primary.p50)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(AppTheme.Primary.p200, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }

            // Description Input Field
            VStack(alignment: .leading, spacing: 6) {
                Text("Mô tả giọng nói mong muốn (Tiếng Việt hoặc English)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n800)

                ZStack(alignment: .topLeading) {
                    if voiceDescription.isEmpty {
                        Text("Ví dụ: Giọng nam người Anh 35 tuổi, trầm ấm, nói rõ ràng từng âm, nhịp điệu từ tốn, truyền cảm và đáng tin cậy...")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.Neutral.n400)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }

                    TextEditor(text: $voiceDescription)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 85)
                }
                .background(AppTheme.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Neutral.n200, lineWidth: 1)
                )
            }

            // Voice Attribute Pickers
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Gender Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Giới tính")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Neutral.n600)

                        Picker("Giới tính", selection: $selectedGender) {
                            ForEach(AIVoiceGender.allCases, id: \.self) { g in
                                Text(g.displayName).tag(g)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Accent Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chất giọng (Accent)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Neutral.n600)

                        Menu {
                            ForEach(AIVoiceAccent.allCases, id: \.self) { acc in
                                Button {
                                    selectedAccent = acc
                                } label: {
                                    Text("\(acc.flagEmoji) \(acc.displayName)")
                                }
                            }
                        } label: {
                            HStack {
                                Text("\(selectedAccent.flagEmoji) \(selectedAccent.displayName)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppTheme.Neutral.n800)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.Surface.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.Neutral.n200))
                        }
                    }
                }

                // Preset Intonation
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phong cách nhấn nhá")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n600)

                    Picker("Phong cách", selection: $selectedPreset) {
                        ForEach([VoiceExpressivenessPreset.conversational, .teacher, .dynamic, .storyteller]) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Generate Previews Button
            Button {
                generateVoicePreviews()
            } label: {
                HStack(spacing: 8) {
                    if isGeneratingPreviews {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Đang tạo 3 mẫu giọng thử nghiệm...")
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                        Text("Sinh 3 Mẫu Giọng Nghe Thử")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AppTheme.Primary.p500, AppTheme.Accent.a500],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.Primary.p500.opacity(0.3), radius: 8, y: 3)
            }
            .disabled(isGeneratingPreviews || voiceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity((voiceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingPreviews) ? 0.6 : 1.0)

            // Generated Previews List
            if !generatedPreviews.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "headphones")
                            .foregroundStyle(AppTheme.Primary.p500)
                        Text("Nghe thử & Chọn mẫu ưng ý nhất")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.Neutral.n800)
                    }

                    ForEach(Array(generatedPreviews.enumerated()), id: \.element.id) { index, preview in
                        previewCardView(index: index + 1, preview: preview)
                    }
                }
                .padding(.top, 8)
            }

            // Save Voice Section (Once a preview is selected)
            if let selected = selectedPreviewForSave {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Đặt tên cho giọng nói để lưu vào thư viện")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n800)

                    TextField("Ví dụ: Thầy David London", text: $customVoiceName)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.Primary.p400, lineWidth: 1.5))

                    Button {
                        saveSelectedPreviewAsVoice(preview: selected)
                    } label: {
                        HStack(spacing: 6) {
                            if isSavingVoice {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                                Text("Đang lưu giọng...")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Lưu & Đặt Làm Giọng Mặc Định")
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppTheme.Primary.p600)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSavingVoice || customVoiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)
                .background(AppTheme.Primary.p50.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Primary.p200))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func previewCardView(index: Int, preview: GeneratedVoicePreview) -> some View {
        let isPlaying = (activePlayingPreviewId == preview.id && previewAudioPlayer?.isPlaying == true)
        let isChosen = (selectedPreviewForSave?.id == preview.id)

        return HStack(spacing: 12) {
            Button {
                togglePlayPreviewAudio(preview: preview)
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(isPlaying ? AppTheme.Semantic.warning : AppTheme.Primary.p500)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mẫu thử #\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text(String(format: "Thời lượng: %.1fs • Nhấn nhá bản xứ", preview.durationSecs))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            Spacer()

            Button {
                withAnimation {
                    selectedPreviewForSave = preview
                    if customVoiceName.isEmpty {
                        customVoiceName = "Giọng tùy chỉnh #\(index)"
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isChosen {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                    }
                    Text(isChosen ? "Đã chọn" : "Chọn mẫu")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(isChosen ? .white : AppTheme.Primary.p600)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isChosen ? AppTheme.Primary.p600 : AppTheme.Primary.p50)
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isChosen ? AppTheme.Primary.p500 : AppTheme.Neutral.n200, lineWidth: isChosen ? 2 : 1)
        )
    }

    // MARK: - Tab 2: Voice Clone (From Audio / Mic)
    private var voiceCloneSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Voice Name & Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Tên giọng Clone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n800)

                TextField("Ví dụ: Giọng Clone của tôi / Giọng Podcaster John", text: $cloneVoiceName)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.Neutral.n200))
            }

            // Option 1: Direct Microphone Recording
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text("Cách 1: Thu âm trực tiếp (10 - 20 giây)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                // Sample prompt card
                VStack(alignment: .leading, spacing: 6) {
                    Text("Đoạn văn mẫu để bạn đọc khi thu âm:")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Primary.p600)

                    Text("\"The quick brown fox jumps over the lazy dog. Speaking English fluently opens up wonderful opportunities to travel, learn, and connect with people around the world.\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Neutral.n800)
                        .italic()
                }
                .padding(12)
                .background(AppTheme.Primary.p50.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Record controls
                HStack(spacing: 16) {
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isRecording ? "stop.fill" : "mic.circle.fill")
                                .font(.system(size: 20))
                            Text(isRecording ? "Dừng ghi âm (\(Int(recordingDuration))s)" : "Bắt đầu ghi âm")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isRecording ? Color.red : AppTheme.Semantic.warning)
                        .clipShape(Capsule())
                    }

                    if let audioURL = recordedAudioURL, !isRecording {
                        Button {
                            togglePlayRecordedAudio(url: audioURL)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isPlayingRecordedAudio ? "pause.circle.fill" : "play.circle.fill")
                                Text(isPlayingRecordedAudio ? "Tạm dừng" : "Nghe lại")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.Primary.p600)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(14)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))

            // Option 2: Upload audio file
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.badge.arrow.up.fill")
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Cách 2: Hoặc tải lên file âm thanh mẫu (M4A, MP3, WAV)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                if let fileName = importedAudioFileName {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(AppTheme.Primary.p500)
                        Text(fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            importedAudioData = nil
                            importedAudioFileName = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.Neutral.n400)
                        }
                    }
                    .padding(10)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                            Text("Chọn file âm thanh từ máy")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Primary.p600)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))

            // Action Button: Clone Voice
            Button {
                executeVoiceClone()
            } label: {
                HStack(spacing: 8) {
                    if isCloningVoice {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Đang phân tích & clone giọng...")
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Tạo Giọng Clone Tức Thì")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AppTheme.Primary.p600, AppTheme.Accent.a600],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.Primary.p600.opacity(0.3), radius: 8, y: 3)
            }
            .disabled(isCloningVoice || cloneVoiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (recordedAudioURL == nil && importedAudioData == nil))
            .opacity((cloneVoiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (recordedAudioURL == nil && importedAudioData == nil) || isCloningVoice) ? 0.6 : 1.0)
        }
    }

    // MARK: - Voice Design Logic
    private func generateVoicePreviews() {
        stopAllAudioPlayback()
        isGeneratingPreviews = true
        generatedPreviews = []
        selectedPreviewForSave = nil

        Task {
            do {
                // Enhance user prompt (e.g. if written in Vietnamese)
                let enhancedPrompt = await ElevenLabsVoiceService.shared.enhanceVoicePrompt(userPrompt: voiceDescription)

                let previews = try await ElevenLabsVoiceService.shared.createPreviewsFromDescription(
                    description: enhancedPrompt
                )

                await MainActor.run {
                    self.generatedPreviews = previews
                    self.isGeneratingPreviews = false
                    // Auto-select first preview
                    if let first = previews.first {
                        self.selectedPreviewForSave = first
                        self.togglePlayPreviewAudio(preview: first)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingPreviews = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func togglePlayPreviewAudio(preview: GeneratedVoicePreview) {
        if activePlayingPreviewId == preview.id, previewAudioPlayer?.isPlaying == true {
            previewAudioPlayer?.stop()
            activePlayingPreviewId = nil
            return
        }

        do {
            previewAudioPlayer?.stop()
            previewAudioPlayer = try AVAudioPlayer(data: preview.audioData)
            previewAudioPlayer?.play()
            activePlayingPreviewId = preview.id
        } catch {
            print("DEBUG: Failed to play preview audio: \(error)")
        }
    }

    private func saveSelectedPreviewAsVoice(preview: GeneratedVoicePreview) {
        let name = customVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isSavingVoice = true
        Task {
            do {
                let voiceId = try await ElevenLabsVoiceService.shared.saveVoiceFromPreview(
                    generatedVoiceId: preview.generatedVoiceId,
                    name: name,
                    description: voiceDescription
                )

                let newProfile = AIVoiceProfile(
                    id: "custom_\(UUID().uuidString.prefix(8))",
                    name: name,
                    type: .elevenLabsCustom,
                    voiceId: voiceId,
                    gender: selectedGender,
                    accent: selectedAccent,
                    descriptionText: voiceDescription,
                    expressivenessPreset: selectedPreset
                )

                await MainActor.run {
                    VoiceProfileStorage.addCustomVoice(newProfile)
                    VoiceProfileStorage.saveSelectedVoice(newProfile)
                    SpeechSynthesizerManager.shared.setVoiceProfile(newProfile)
                    self.isSavingVoice = false
                    self.onVoiceCreated?(newProfile)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isSavingVoice = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                }
            }
        }
    }

    // MARK: - Voice Clone Logic
    private func startRecording() {
        stopAllAudioPlayback()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("DEBUG: Audio session error: \(error)")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("clone_sample_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0
            recordedAudioURL = fileURL

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
                if recordingDuration >= 25 {
                    stopRecording()
                }
            }
        } catch {
            errorMessage = "Không thể khởi động micro ghi âm"
            showErrorAlert = true
        }
    }

    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
    }

    private func togglePlayRecordedAudio(url: URL) {
        if isPlayingRecordedAudio {
            previewAudioPlayer?.stop()
            isPlayingRecordedAudio = false
            return
        }

        do {
            previewAudioPlayer = try AVAudioPlayer(contentsOf: url)
            previewAudioPlayer?.play()
            isPlayingRecordedAudio = true
        } catch {
            print("DEBUG: Failed to play recorded audio: \(error)")
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    importedAudioData = data
                    importedAudioFileName = url.lastPathComponent
                    if cloneVoiceName.isEmpty {
                        cloneVoiceName = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func executeVoiceClone() {
        let name = cloneVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var targetData: Data? = importedAudioData
        var ext = "mp3"

        if let recURL = recordedAudioURL, targetData == nil {
            targetData = try? Data(contentsOf: recURL)
            ext = "m4a"
        }

        guard let data = targetData, data.count > 1000 else {
            errorMessage = "Vui lòng thu âm hoặc chọn 1 file âm thanh mẫu hợp lệ"
            showErrorAlert = true
            return
        }

        isCloningVoice = true
        stopAllAudioPlayback()

        Task {
            do {
                let voiceId = try await ElevenLabsVoiceService.shared.cloneVoice(
                    name: name,
                    description: cloneDescription.isEmpty ? "Cloned voice by user" : cloneDescription,
                    audioData: data,
                    fileExtension: ext
                )

                let profile = AIVoiceProfile(
                    id: "clone_\(UUID().uuidString.prefix(8))",
                    name: name,
                    type: .elevenLabsCustom,
                    voiceId: voiceId,
                    gender: .neutral,
                    accent: .american,
                    descriptionText: "Giọng Clone cá nhân",
                    expressivenessPreset: .conversational
                )

                await MainActor.run {
                    VoiceProfileStorage.addCustomVoice(profile)
                    VoiceProfileStorage.saveSelectedVoice(profile)
                    SpeechSynthesizerManager.shared.setVoiceProfile(profile)
                    self.isCloningVoice = false
                    self.onVoiceCreated?(profile)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isCloningVoice = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func stopAllAudioPlayback() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        previewAudioPlayer?.stop()
        previewAudioPlayer = nil
        activePlayingPreviewId = nil
        isPlayingRecordedAudio = false
    }
}
