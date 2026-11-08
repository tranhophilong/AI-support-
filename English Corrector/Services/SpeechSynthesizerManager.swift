//
//  SpeechSynthesizerManager.swift
//  English Corrector
//

import SwiftUI
import AVFoundation

@MainActor
final class SpeechSynthesizerManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    static let shared = SpeechSynthesizerManager()

    @Published private(set) var speakingText: String?
    @Published private(set) var isSpeakingSlow: Bool = false
    @Published private(set) var isLoadingVoiceAudio: Bool = false
    @Published var currentVoiceProfile: AIVoiceProfile

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?
    private var onFinishCallback: (@MainActor () -> Void)?
    private var currentSpeechTask: Task<Void, Never>?

    override init() {
        self.currentVoiceProfile = VoiceProfileStorage.loadSelectedVoice()
        super.init()
        synthesizer.delegate = self

        NotificationCenter.default.addObserver(
            forName: .aiVoiceProfileDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            if let newProfile = notif.object as? AIVoiceProfile {
                self.currentVoiceProfile = newProfile
            } else {
                self.currentVoiceProfile = VoiceProfileStorage.loadSelectedVoice()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func setVoiceProfile(_ profile: AIVoiceProfile) {
        currentVoiceProfile = profile
        VoiceProfileStorage.saveSelectedVoice(profile)
    }

    func isSpeaking(_ text: String, slow: Bool? = nil) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, speakingText == cleaned else { return false }
        if let slow {
            return isSpeakingSlow == slow
        }
        return true
    }

    func toggleSpeak(_ text: String, slow: Bool = false) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let isCurrentlyActive = (synthesizer.isSpeaking || (audioPlayer?.isPlaying == true) || isLoadingVoiceAudio)
        if isCurrentlyActive, speakingText == cleaned, isSpeakingSlow == slow {
            stop()
            return
        }

        speak(cleaned, slow: slow)
    }

    func speak(_ text: String, slow: Bool = false) {
        let rateMultiplier: Float = slow ? 0.75 : 1.0
        speakWithCallback(text, rateMultiplier: rateMultiplier, onFinish: nil)
    }

    func speakWithCallback(
        _ text: String,
        rateMultiplier: Float = 1.0,
        onFinish: (@MainActor () -> Void)? = nil
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            onFinish?()
            return
        }

        stop()

        speakingText = cleaned
        isSpeakingSlow = rateMultiplier < 0.9
        onFinishCallback = onFinish

        configureAudioSessionForPlayback()

        // 1. Check if using ElevenLabs Voice
        if currentVoiceProfile.type == .elevenLabsCurated || currentVoiceProfile.type == .elevenLabsCustom {
            let key = AudioCacheManager.shared.cacheKey(
                voiceId: currentVoiceProfile.voiceId,
                text: cleaned,
                speed: Double(rateMultiplier) * currentVoiceProfile.speed,
                stability: currentVoiceProfile.stability,
                style: currentVoiceProfile.style
            )

            // A. Check local Smart Audio Cache first
            if let cachedURL = AudioCacheManager.shared.cachedAudioURL(for: key) {
                playAudioFile(at: cachedURL, rateMultiplier: rateMultiplier)
                return
            }

            // B. Fetch from ElevenLabs API
            isLoadingVoiceAudio = true
            currentSpeechTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    var tunedProfile = self.currentVoiceProfile
                    if rateMultiplier < 0.9 {
                        tunedProfile.speed = 0.85
                    }
                    let data = try await ElevenLabsVoiceService.shared.synthesizeSpeech(
                        text: cleaned,
                        profile: tunedProfile
                    )
                    guard !Task.isCancelled else { return }
                    if let savedURL = AudioCacheManager.shared.saveAudio(data: data, for: key) {
                        self.playAudioFile(at: savedURL, rateMultiplier: rateMultiplier)
                    } else {
                        self.playAudioDataDirectly(data: data, rateMultiplier: rateMultiplier)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    print("DEBUG: ElevenLabs TTS failed: \(error). Falling back to Apple Enhanced Voice.")
                    self.fallbackAppleSpeak(cleaned, rateMultiplier: rateMultiplier)
                }
                self.isLoadingVoiceAudio = false
            }
        } else {
            // 2. Play via Apple Enhanced System Voice
            fallbackAppleSpeak(cleaned, rateMultiplier: rateMultiplier)
        }
    }

    // MARK: - Audio Playback Engine

    private func playAudioFile(at url: URL, rateMultiplier: Float) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = min(max(rateMultiplier, 0.6), 1.6)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isLoadingVoiceAudio = false
        } catch {
            print("DEBUG: AVAudioPlayer failed to play cached file: \(error)")
            fallbackAppleSpeak(speakingText ?? "", rateMultiplier: rateMultiplier)
        }
    }

    private func playAudioDataDirectly(data: Data, rateMultiplier: Float) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = min(max(rateMultiplier, 0.6), 1.6)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isLoadingVoiceAudio = false
        } catch {
            print("DEBUG: AVAudioPlayer failed to play data: \(error)")
            fallbackAppleSpeak(speakingText ?? "", rateMultiplier: rateMultiplier)
        }
    }

    private func fallbackAppleSpeak(_ text: String, rateMultiplier: Float) {
        isLoadingVoiceAudio = false
        let utterance = AVSpeechUtterance(string: text)

        // Strict English Voice Selection (Matching both Accent and Gender)
        var voiceToUse: AVSpeechSynthesisVoice?

        // 1. Check if the profile specifies a valid English system voice
        if let specificVoice = AVSpeechSynthesisVoice(identifier: currentVoiceProfile.voiceId),
           specificVoice.language.lowercased().hasPrefix("en") {
            voiceToUse = specificVoice
        }

        // 2. Otherwise find the highest-quality native English voice with matching gender
        if voiceToUse == nil {
            voiceToUse = bestAppleEnhancedVoice(
                for: currentVoiceProfile.accent.rawValue,
                gender: currentVoiceProfile.gender
            )
        }

        utterance.voice = voiceToUse ?? (currentVoiceProfile.gender == .male ? maleFallbackVoice() : femaleFallbackVoice())

        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let clampedRate = min(max(baseRate * rateMultiplier * Float(currentVoiceProfile.speed), 0.32), 0.65)
        utterance.rate = clampedRate

        // Natural pitch modulation based on profile gender
        switch currentVoiceProfile.gender {
        case .male:
            utterance.pitchMultiplier = 0.90
        case .female:
            utterance.pitchMultiplier = 1.05
        case .neutral:
            utterance.pitchMultiplier = 1.0
        }

        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    private func bestAppleEnhancedVoice(
        for rawAccentCode: String,
        gender: AIVoiceGender
    ) -> AVSpeechSynthesisVoice? {
        let targetCode = rawAccentCode.lowercased().hasPrefix("en") ? rawAccentCode : "en-US"
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.lowercased().hasPrefix("en") }

        let targetGenderInt = (gender == .male) ? 1 : ((gender == .female) ? 2 : 0)
        let maleNames = ["aaron", "alex", "daniel", "gordon", "arthur", "fred", "oliver", "rishi"]
        let femaleNames = ["samantha", "ava", "martha", "karen", "catherine", "nicky", "serena", "tessa", "moira"]

        let isGenderMatch: (AVSpeechSynthesisVoice) -> Bool = { voice in
            if gender == .neutral { return true }
            if voice.gender.rawValue == targetGenderInt { return true }
            let lower = voice.name.lowercased()
            if gender == .male && maleNames.contains(where: { lower.contains($0) }) { return true }
            if gender == .female && femaleNames.contains(where: { lower.contains($0) }) { return true }
            return false
        }

        // 1. Exact dialect + matching gender with Premium / Enhanced quality
        if let highQuality = englishVoices.first(where: {
            $0.language.caseInsensitiveCompare(targetCode) == .orderedSame &&
            ($0.quality == .premium || $0.quality == .enhanced) &&
            isGenderMatch($0)
        }) {
            return highQuality
        }

        // 2. Exact dialect + matching gender (Preferred named voices)
        let preferredPool = (gender == .male) ? maleNames : femaleNames
        for name in preferredPool {
            if let matchedNamed = englishVoices.first(where: {
                $0.language.caseInsensitiveCompare(targetCode) == .orderedSame &&
                $0.name.lowercased().contains(name)
            }) {
                return matchedNamed
            }
        }

        // 3. Any voice in the exact dialect with matching gender
        if let dialectAndGender = englishVoices.first(where: {
            $0.language.caseInsensitiveCompare(targetCode) == .orderedSame &&
            isGenderMatch($0)
        }) {
            return dialectAndGender
        }

        // 4. Any English voice with matching gender cross-dialect
        for name in preferredPool {
            if let crossDialect = englishVoices.first(where: { $0.name.lowercased().contains(name) }) {
                return crossDialect
            }
        }

        if let anyEnglishMatchingGender = englishVoices.first(where: { isGenderMatch($0) }) {
            return anyEnglishMatchingGender
        }

        // 5. Final fallback by gender
        return (gender == .male) ? maleFallbackVoice() : femaleFallbackVoice()
    }

    private func maleFallbackVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("en") }
        let names = ["aaron", "alex", "daniel", "gordon", "arthur", "fred"]
        for n in names {
            if let v = all.first(where: { $0.name.lowercased().contains(n) }) {
                return v
            }
        }
        return all.first(where: { $0.gender.rawValue == 1 }) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func femaleFallbackVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("en") }
        let names = ["samantha", "ava", "martha", "karen", "nicky"]
        for n in names {
            if let v = all.first(where: { $0.name.lowercased().contains(n) }) {
                return v
            }
        }
        return all.first(where: { $0.gender.rawValue == 2 }) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DEBUG: Failed to configure AVAudioSession for TTS: \(error)")
        }
    }

    func stop() {
        currentSpeechTask?.cancel()
        currentSpeechTask = nil

        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentUtterance = nil

        speakingText = nil
        isSpeakingSlow = false
        isLoadingVoiceAudio = false

        let callback = onFinishCallback
        onFinishCallback = nil
        callback?()
    }

    // MARK: - Delegates

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.speakingText = nil
            self.isSpeakingSlow = false
            self.isLoadingVoiceAudio = false
            let callback = self.onFinishCallback
            self.onFinishCallback = nil
            callback?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.speakingText = nil
            self.isSpeakingSlow = false
            self.isLoadingVoiceAudio = false
            let callback = self.onFinishCallback
            self.onFinishCallback = nil
            callback?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.speakingText = nil
            self.isSpeakingSlow = false
            self.isLoadingVoiceAudio = false
            self.onFinishCallback = nil
        }
    }
}

// MARK: - SpeakButton Component

struct SpeakButton: View {
    let text: String
    var slow: Bool = false
    var font: Font = .caption
    var activeColor: Color = AppTheme.Primary.p500
    var inactiveColor: Color = AppTheme.Neutral.n500
    var showBackground: Bool = false

    @ObservedObject private var tts = SpeechSynthesizerManager.shared

    private var isActive: Bool {
        tts.isSpeaking(text, slow: slow)
    }

    var body: some View {
        Button {
            tts.toggleSpeak(text, slow: slow)
        } label: {
            HStack(spacing: 4) {
                if isActive && tts.isLoadingVoiceAudio {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(activeColor)
                } else {
                    Image(systemName: iconName)
                        .font(font)
                        .symbolEffect(.variableColor.iterative, isActive: isActive && !slow)
                        .foregroundStyle(isActive ? activeColor : inactiveColor)
                }
            }
            .padding(showBackground ? 6 : 2)
            .background(
                showBackground
                ? (isActive ? activeColor.opacity(0.15) : AppTheme.Surface.cardMuted)
                : Color.clear
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Stop speaking" : (slow ? "Speak slowly in English" : "Speak in English"))
    }

    private var iconName: String {
        if slow {
            return isActive ? "stop.circle.fill" : "tortoise.fill"
        } else {
            return isActive ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
        }
    }
}
