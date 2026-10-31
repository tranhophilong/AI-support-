//
//  SpeechRecognizerManager.swift
//  English Corrector
//

import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizerManager: ObservableObject {

    @Published private(set) var isRecording = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startRecording(
        existingText: String,
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stopRecording()

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }

                guard authStatus == .authorized else {
                    onError("Please allow Speech Recognition in Settings")
                    return
                }

                let micAllowed = await AVAudioApplication.requestRecordPermission()
                guard micAllowed else {
                    onError("Please allow Microphone access in Settings")
                    return
                }

                self.beginSession(
                    existingText: existingText,
                    onUpdate: onUpdate,
                    onError: onError
                )
            }
        }
    }

    func stopRecording() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        if isRecording {
            isRecording = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginSession(
        existingText: String,
        onUpdate: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            onError("Speech recognition is currently unavailable")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true

            let baseText = existingText.trimmingCharacters(in: .whitespacesAndNewlines)

            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        let spoken = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if !spoken.isEmpty {
                            let combined = baseText.isEmpty ? spoken : "\(baseText) \(spoken)"
                            onUpdate(combined)
                        }

                        if result.isFinal {
                            self.stopRecording()
                        }
                    }

                    if error != nil, self.isRecording {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            onError("Could not start microphone: \(error.localizedDescription)")
        }
    }
}
