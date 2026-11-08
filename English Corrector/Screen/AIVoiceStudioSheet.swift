//
//  AIVoiceStudioSheet.swift
//  English Corrector
//

import SwiftUI
import AVFoundation

struct AIVoiceStudioSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var tts = SpeechSynthesizerManager.shared
    @AppStorage("custom_elevenlabs_api_key") private var storedCustomKey: String = ""
    @State private var customVoices: [AIVoiceProfile] = []
    @State private var selectedVoice: AIVoiceProfile = VoiceProfileStorage.loadSelectedVoice()

    @State private var isCreateSheetPresented = false
    @State private var isAPIKeyAlertPresented = false
    @State private var apiKeyInput = ""

    private var hasActiveKey: Bool {
        let trimmed = storedCustomKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "YOUR_ELEVENLABS_API_KEY" {
            return true
        }
        return !APIKeyStore.elevenLabsAPIKey.isEmpty
    }

    // Voice Tuning
    @State private var selectedPreset: VoiceExpressivenessPreset = .conversational
    @State private var currentStyle: Double = 0.40
    @State private var currentStability: Double = 0.50
    @State private var currentSpeed: Double = 1.0

    @State private var isTestingVoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    apiKeyBannerCard

                    // Section 1: User's Custom Voices
                    customVoicesSection

                    // Section 2: Curated ElevenLabs Voices
                    curatedElevenLabsSection

                    // Section 3: Apple Enhanced Voices
                    appleEnhancedSection

                    // Section 4: Expressiveness & Intonation Tuning
                    tuningSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(AppTheme.Surface.background.ignoresSafeArea())
            .navigationTitle("AI Voice Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        tts.stop()
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.Neutral.n600)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateSheetPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Tạo mới")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.Primary.p600)
                    }
                }
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreateCustomVoiceSheet { newVoice in
                    reloadVoices()
                    selectVoice(newVoice)
                }
            }
            .alert("Cấu hình ElevenLabs API Key", isPresented: $isAPIKeyAlertPresented) {
                TextField("Nhập xi-api-key...", text: $apiKeyInput)
                Button("Lưu") {
                    let cleaned = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(cleaned, forKey: "custom_elevenlabs_api_key")
                    apiKeyInput = ""
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Nhập API Key cá nhân từ ElevenLabs.io để mở khóa tạo giọng không giới hạn, clone giọng và biểu cảm ngữ điệu tự nhiên nhất.")
            }
            .onAppear {
                reloadVoices()
                loadCurrentTuning()
            }
            .onDisappear {
                tts.stop()
            }
        }
    }

    // MARK: - API Key Banner
    private var apiKeyBannerCard: some View {
        let hasKey = hasActiveKey

        return HStack(spacing: 12) {
            Image(systemName: hasKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(hasKey ? AppTheme.Semantic.success : AppTheme.Semantic.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasKey ? "ElevenLabs AI Engine: Đang hoạt động" : "Chưa có ElevenLabs API Key")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Neutral.n900)

                Text(hasKey ? "Sẵn sàng tạo giọng từ mô tả, clone âm thanh và nhấn nhá bản xứ." : "Giọng đang được phát mô phỏng qua Apple TTS theo đúng giới tính & ngữ điệu.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Neutral.n600)
            }

            Spacer()

            Button {
                apiKeyInput = storedCustomKey.isEmpty ? (UserDefaults.standard.string(forKey: "custom_elevenlabs_api_key") ?? "") : storedCustomKey
                isAPIKeyAlertPresented = true
            } label: {
                Text(hasKey ? "Đổi Key" : "Nhập Key")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hasKey ? AppTheme.Semantic.success.opacity(0.3) : AppTheme.Semantic.warning.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Section 1: User Custom Voices
    private var customVoicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Giọng Tùy Chỉnh Của Bạn")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                Spacer()

                Button {
                    isCreateSheetPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "wand.and.stars")
                        Text("Tạo giọng mới")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p600)
                }
            }

            if customVoices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.Neutral.n400)

                    Text("Bạn chưa tạo giọng nói riêng nào")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Neutral.n700)

                    Text("Tạo giọng thầy cô bản xứ từ câu mô tả văn bản hoặc clone giọng nói từ file/mic chỉ trong vài giây.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button {
                        isCreateSheetPresented = true
                    } label: {
                        Text("+ Tạo giọng nói ngay")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppTheme.Primary.p500)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(AppTheme.Surface.cardMuted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(customVoices) { voice in
                        voiceCardView(voice: voice, isDeletable: true)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: ElevenLabs Curated Native Voices
    private var curatedElevenLabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.tv.fill")
                    .foregroundStyle(AppTheme.Primary.p500)
                Text("Giọng Bản Xứ Tuyển Chọn (ElevenLabs)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n900)
            }

            if !hasActiveKey {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text("Chưa có ElevenLabs Key: Đang phát mô phỏng giọng nam/nữ Apple chuẩn.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Neutral.n600)
                }
                .padding(.horizontal, 4)
            }

            VStack(spacing: 8) {
                ForEach(AIVoiceProfile.curatedElevenLabsVoices) { voice in
                    voiceCardView(voice: voice, isDeletable: false)
                }
            }
        }
    }

    // MARK: - Section 3: Apple Enhanced Voices
    private var appleEnhancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "applelogo")
                    .foregroundStyle(AppTheme.Neutral.n700)
                Text("Giọng Apple Enhanced (Miễn Phí & Offline)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n900)
            }

            VStack(spacing: 8) {
                ForEach(AIVoiceProfile.curatedAppleVoices) { voice in
                    voiceCardView(voice: voice, isDeletable: false)
                }
            }
        }
    }

    // MARK: - Section 4: Expressiveness & Intonation Tuning
    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Tinh Chỉnh Ngữ Điệu & Nhấn Nhá")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                Spacer()

                Button {
                    testCurrentTunedVoice()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isTestingVoice ? "stop.fill" : "play.fill")
                        Text(isTestingVoice ? "Dừng" : "Nghe thử")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.Primary.p500)
                    .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Phong cách biểu cảm cho: \(selectedVoice.name)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.Neutral.n600)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VoiceExpressivenessPreset.allCases) { preset in
                            Button {
                                withAnimation {
                                    selectedPreset = preset
                                    currentStability = preset.stability
                                    currentStyle = preset.style
                                    applyTuningToSelectedVoice()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Image(systemName: preset.icon)
                                            .font(.caption)
                                        Text(preset.title)
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    Text(preset.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(selectedPreset == preset ? .white.opacity(0.85) : AppTheme.Neutral.n500)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPreset == preset ? AppTheme.Primary.p500 : AppTheme.Surface.card)
                                .foregroundStyle(selectedPreset == preset ? .white : AppTheme.Neutral.n800)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selectedPreset == preset ? AppTheme.Primary.p500 : AppTheme.Neutral.n200)
                                )
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                // Slider: Style Exaggeration (Độ nhấn nhá)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Độ nhấn nhá biểu cảm (Style)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Neutral.n700)
                        Spacer()
                        Text("\(Int(currentStyle * 100))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.Primary.p600)
                    }

                    Slider(value: $currentStyle, in: 0.05...0.95, step: 0.05) {
                        Text("Style")
                    } onEditingChanged: { editing in
                        if !editing {
                            selectedPreset = .custom
                            applyTuningToSelectedVoice()
                        }
                    }
                    .tint(AppTheme.Primary.p500)
                }

                // Slider: Speech Speed
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tốc độ nói (Speed)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Neutral.n700)
                        Spacer()
                        Text(String(format: "%.2fx", currentSpeed))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.Primary.p600)
                    }

                    Slider(value: $currentSpeed, in: 0.75...1.30, step: 0.05) {
                        Text("Speed")
                    } onEditingChanged: { editing in
                        if !editing {
                            applyTuningToSelectedVoice()
                        }
                    }
                    .tint(AppTheme.Primary.p500)
                }
            }
            .padding(14)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.Neutral.n200))
        }
    }

    // MARK: - Voice Card View
    private func voiceCardView(voice: AIVoiceProfile, isDeletable: Bool) -> some View {
        let isSelected = (selectedVoice.id == voice.id)

        return HStack(spacing: 12) {
            // Flag / Avatar
            ZStack {
                Circle()
                    .fill(isSelected ? AppTheme.Primary.p50 : AppTheme.Surface.cardMuted)
                    .frame(width: 42, height: 42)

                Text(voice.accent.flagEmoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(voice.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Neutral.n900)

                    if voice.type == .elevenLabsCustom {
                        Text("Custom")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.Primary.p500)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 5) {
                    Text(voice.gender.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(voice.gender == .male ? Color.blue : Color.pink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background((voice.gender == .male ? Color.blue : Color.pink).opacity(0.12))
                        .clipShape(Capsule())

                    Text(voice.accent.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.Neutral.n600)
                }

                Text(voice.descriptionText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .lineLimit(1)
            }

            Spacer()

            // Preview Sample Play Button
            Button {
                togglePlaySample(for: voice)
            } label: {
                Image(systemName: isVoiceCurrentlyPlaying(voice) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.Primary.p500)
            }
            .buttonStyle(.plain)

            // Select Checkmark
            Button {
                selectVoice(voice)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppTheme.Primary.p500 : AppTheme.Neutral.n300)
            }
            .buttonStyle(.plain)

            // Delete (if custom)
            if isDeletable {
                Button {
                    withAnimation {
                        VoiceProfileStorage.deleteCustomVoice(id: voice.id)
                        reloadVoices()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .background(isSelected ? AppTheme.Primary.p50.opacity(0.5) : AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? AppTheme.Primary.p400 : AppTheme.Neutral.n200, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectVoice(voice)
        }
    }

    // MARK: - Actions
    private func reloadVoices() {
        customVoices = VoiceProfileStorage.loadCustomVoices()
        selectedVoice = VoiceProfileStorage.loadSelectedVoice()
    }

    private func selectVoice(_ voice: AIVoiceProfile) {
        tts.stop()
        selectedVoice = voice
        VoiceProfileStorage.saveSelectedVoice(voice)
        tts.setVoiceProfile(voice)
        loadCurrentTuning()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func loadCurrentTuning() {
        selectedPreset = selectedVoice.expressivenessPreset
        currentStability = selectedVoice.stability
        currentStyle = selectedVoice.style
        currentSpeed = selectedVoice.speed
    }

    private func applyTuningToSelectedVoice() {
        var updated = selectedVoice
        updated.expressivenessPreset = selectedPreset
        updated.stability = currentStability
        updated.style = currentStyle
        updated.speed = currentSpeed
        selectedVoice = updated

        // If it's a custom voice, update it in storage
        if updated.type == .elevenLabsCustom {
            VoiceProfileStorage.addCustomVoice(updated)
        }
        VoiceProfileStorage.saveSelectedVoice(updated)
        tts.setVoiceProfile(updated)
    }

    private func isVoiceCurrentlyPlaying(_ voice: AIVoiceProfile) -> Bool {
        tts.speakingText == voice.samplePhrase
    }

    private func togglePlaySample(for voice: AIVoiceProfile) {
        if isVoiceCurrentlyPlaying(voice) {
            tts.stop()
        } else {
            tts.stop()
            // Select and sync tuning state to match this voice
            selectVoice(voice)
            tts.speak(voice.samplePhrase)
        }
    }

    private func testCurrentTunedVoice() {
        if isTestingVoice {
            tts.stop()
            isTestingVoice = false
        } else {
            tts.stop()
            isTestingVoice = true
            tts.speakWithCallback(selectedVoice.samplePhrase) {
                self.isTestingVoice = false
            }
        }
    }
}
