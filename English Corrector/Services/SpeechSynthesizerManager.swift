//
//  SpeechSynthesizerManager.swift
//  English Corrector
//

import SwiftUI
import AVFoundation

@MainActor
final class SpeechSynthesizerManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    static let shared = SpeechSynthesizerManager()

    @Published private(set) var speakingText: String?
    @Published private(set) var isSpeakingSlow: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinishCallback: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
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

        if synthesizer.isSpeaking, speakingText == cleaned, isSpeakingSlow == slow {
            stop()
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DEBUG: Failed to configure AVAudioSession for TTS: \(error)")
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.36 : AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        speakingText = cleaned
        isSpeakingSlow = slow
        onFinishCallback = nil
        synthesizer.speak(utterance)
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

        if synthesizer.isSpeaking {
            onFinishCallback = nil
            synthesizer.stopSpeaking(at: .immediate)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DEBUG: Failed to configure AVAudioSession for TTS: \(error)")
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let clampedRate = min(max(baseRate * rateMultiplier, 0.32), 0.62)
        utterance.rate = clampedRate
        utterance.pitchMultiplier = 1.0

        speakingText = cleaned
        isSpeakingSlow = rateMultiplier < 0.9
        onFinishCallback = onFinish
        synthesizer.speak(utterance)
    }

    func stop() {
        onFinishCallback = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingText = nil
        isSpeakingSlow = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.speakingText == utterance.speechString {
                self.speakingText = nil
                self.isSpeakingSlow = false
                let callback = self.onFinishCallback
                self.onFinishCallback = nil
                callback?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.speakingText == utterance.speechString {
                self.speakingText = nil
                self.isSpeakingSlow = false
                self.onFinishCallback = nil
            }
        }
    }
}

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
            Image(systemName: iconName)
                .font(font)
                .symbolEffect(.variableColor.iterative, isActive: isActive && !slow)
                .foregroundStyle(isActive ? activeColor : inactiveColor)
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
