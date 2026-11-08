//
//  ElevenLabsVoiceService.swift
//  English Corrector
//

import Foundation
import UIKit

public struct GeneratedVoicePreview: Identifiable {
    public let id: String
    public let generatedVoiceId: String
    public let audioData: Data
    public let durationSecs: Double
}

public actor ElevenLabsVoiceService {
    public static let shared = ElevenLabsVoiceService()

    private let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    private let session = URLSession.shared

    private init() {}

    // MARK: - 1. Text-To-Speech (Native Expressive Pronunciation)

    /// Synthesizes text using ElevenLabs TTS with high-expressiveness settings
    public func synthesizeSpeech(
        text: String,
        profile: AIVoiceProfile,
        apiKey: String? = nil
    ) async throws -> Data {
        let key = (apiKey?.isEmpty == false ? apiKey! : APIKeyStore.elevenLabsAPIKey)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Nội dung cần đọc không được để trống")
        }
        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "ElevenLabs", keyName: "ELEVENLABS_API_KEY")
        }

        let voiceId = profile.voiceId
        let url = baseURL.appendingPathComponent("text-to-speech/\(voiceId)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25

        let body: [String: Any] = [
            "text": cleaned,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": profile.stability,
                "similarity_boost": profile.similarityBoost,
                "style": profile.style,
                "use_speaker_boost": profile.useSpeakerBoost
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Phản hồi không hợp lệ từ server")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Lỗi gọi API: HTTP \(httpResponse.statusCode)"
            throw AIServiceError.requestFailed(provider: "ElevenLabs", statusCode: httpResponse.statusCode, message: errorMsg)
        }

        return data
    }

    // MARK: - 2. Voice Design (Create from Text Description)

    /// Generates 3 voice previews from a prompt description
    public func createPreviewsFromDescription(
        description: String,
        textSample: String? = nil,
        apiKey: String? = nil
    ) async throws -> [GeneratedVoicePreview] {
        let key = (apiKey?.isEmpty == false ? apiKey! : APIKeyStore.elevenLabsAPIKey)
        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "ElevenLabs", keyName: "ELEVENLABS_API_KEY")
        }

        // ElevenLabs requirement: voice_description must be 20 to 1000 characters
        var safeDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeDescription.count < 20 {
            safeDescription = "A natural, fluent native English speaker with pleasant tone: \(safeDescription)"
        }
        if safeDescription.count > 1000 {
            safeDescription = String(safeDescription.prefix(1000))
        }

        // ElevenLabs requirement: text preview sample must be 100 to 1000 characters
        var sample = (textSample?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if sample.count < 100 {
            sample = "Hello there! It is wonderful to converse with you in English today. I hope you are having a productive and pleasant day learning new skills together."
        }
        if sample.count > 1000 {
            sample = String(sample.prefix(1000))
        }

        let url = baseURL.appendingPathComponent("text-to-voice/create-previews")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let body: [String: Any] = [
            "voice_description": safeDescription,
            "text": sample,
            "loudness": 0.5,
            "quality": 0.95
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Phản hồi mạng không hợp lệ")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = parseElevenLabsError(from: data, statusCode: httpResponse.statusCode)
            throw AIServiceError.requestFailed(provider: "ElevenLabs", statusCode: httpResponse.statusCode, message: errorMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let previews = json["previews"] as? [[String: Any]] else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Dữ liệu preview trả về không đúng định dạng")
        }

        var results: [GeneratedVoicePreview] = []
        for (index, item) in previews.enumerated() {
            guard let b64 = item["audio_base_64"] as? String,
                  let genId = item["generated_voice_id"] as? String,
                  let audioBytes = Data(base64Encoded: b64) else { continue }

            let duration = (item["duration_secs"] as? Double) ?? 3.5
            results.append(GeneratedVoicePreview(
                id: "preview_\(index)_\(genId.prefix(6))",
                generatedVoiceId: genId,
                audioData: audioBytes,
                durationSecs: duration
            ))
        }

        guard !results.isEmpty else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Không sinh được mẫu giọng nào từ mô tả này")
        }

        return results
    }

    /// Saves a generated preview into a persistent voice ID
    public func saveVoiceFromPreview(
        generatedVoiceId: String,
        name: String,
        description: String,
        apiKey: String? = nil
    ) async throws -> String {
        let key = (apiKey?.isEmpty == false ? apiKey! : APIKeyStore.elevenLabsAPIKey)
        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "ElevenLabs", keyName: "ELEVENLABS_API_KEY")
        }

        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Voice" : name
        var safeDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeDesc.count < 20 {
            safeDesc = "A custom native English voice: \(safeDesc)"
        }
        if safeDesc.count > 1000 {
            safeDesc = String(safeDesc.prefix(1000))
        }

        let url = baseURL.appendingPathComponent("text-to-voice/create-voice-from-preview")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "voice_name": safeName,
            "voice_description": safeDesc,
            "generated_voice_id": generatedVoiceId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let msg = parseElevenLabsError(from: data, statusCode: statusCode)
            throw AIServiceError.apiError(provider: "ElevenLabs", message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voiceId = json["voice_id"] as? String else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Không nhận được voice_id sau khi lưu")
        }

        return voiceId
    }

    private func parseElevenLabsError(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detailArray = json["detail"] as? [[String: Any]] {
                let msgs = detailArray.compactMap { $0["msg"] as? String }
                if !msgs.isEmpty {
                    return msgs.joined(separator: ", ")
                }
            } else if let detailString = json["detail"] as? String {
                return detailString
            } else if let message = json["message"] as? String {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }

    // MARK: - 3. Instant Voice Cloning (From Recorded Audio / Sound File)

    /// Clones voice from audio recording data (M4A / WAV / MP3)
    public func cloneVoice(
        name: String,
        description: String,
        audioData: Data,
        fileExtension: String = "m4a",
        apiKey: String? = nil
    ) async throws -> String {
        let key = (apiKey?.isEmpty == false ? apiKey! : APIKeyStore.elevenLabsAPIKey)
        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "ElevenLabs", keyName: "ELEVENLABS_API_KEY")
        }
        guard audioData.count > 1000 else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "File âm thanh ghi âm quá ngắn hoặc không có dữ liệu")
        }

        let url = baseURL.appendingPathComponent("voices/add")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        var body = Data()

        // Name field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)

        // Description field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(description)\r\n".data(using: .utf8)!)

        // Files field
        let mimeType = (fileExtension.lowercased() == "wav") ? "audio/wav" : (fileExtension.lowercased() == "mp3" ? "audio/mpeg" : "audio/m4a")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"sample.\(fileExtension)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Lỗi clone giọng"
            throw AIServiceError.apiError(provider: "ElevenLabs", message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voiceId = json["voice_id"] as? String else {
            throw AIServiceError.apiError(provider: "ElevenLabs", message: "Không nhận được voice_id sau khi clone")
        }

        return voiceId
    }

    // MARK: - 4. Prompt Enhancement

    /// Translates or enriches Vietnamese descriptions into an optimal English Voice Design prompt
    public func enhanceVoicePrompt(userPrompt: String) async -> String {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A friendly and articulate American English speaker" }

        // If already pure English with good length, return directly
        let isVietnamese = trimmed.range(of: #"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]"#, options: .regularExpression) != nil
        if !isVietnamese && trimmed.count >= 20 {
            return trimmed
        }

        // Use Groq/Gemini to produce a vivid prompt for ElevenLabs
        let systemPrompt = """
        You are an expert voice design assistant for ElevenLabs Voice Design API.
        Convert the user's description into a concise, vivid English voice prompt describing:
        - Age and gender (e.g., "A 35-year-old British male")
        - Accent (e.g., "standard American accent", "posh British RP accent", "warm Australian accent")
        - Tone, emotional quality, and intonation (e.g., "deep resonant timbre, highly expressive melodic intonation, cheerful and reassuring")
        Return ONLY the final English prompt string, without explanations or quotation marks.
        """

        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            if let res = try? await queryGroqPrompt(system: systemPrompt, user: trimmed, apiKey: groqKey) {
                return res
            }
        }

        return "A clear, natural native English speaker with lively intonation and warm tone: \(trimmed)"
    }

    private func queryGroqPrompt(system: String, user: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return user }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "openai/gpt-oss-20b",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.4,
            "max_tokens": 150
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await session.data(for: req)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else { return user }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
