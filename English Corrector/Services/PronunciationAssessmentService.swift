//
//  PronunciationAssessmentService.swift
//  English Corrector
//

import Foundation
import SwiftUI

@MainActor
public final class PronunciationAssessmentService {

    public static let shared = PronunciationAssessmentService()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Full Sentence Pronunciation Assessment
    /// - Parameters:
    ///   - targetSentence: The expected sentence (if practicing a specific prompt)
    ///   - spokenSentence: The transcribed speech recognized by SFSpeechRecognizer
    ///   - acousticSegments: Segment confidence from Apple speech engine
    public func assessPronunciation(
        targetSentence: String? = nil,
        spokenSentence: String,
        acousticSegments: [AcousticSpeechSegment] = []
    ) async -> PronunciationAssessmentResult {
        let cleanSpoken = spokenSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSpoken.isEmpty else {
            return PronunciationAssessmentResult.empty(sentence: targetSentence ?? "")
        }

        let cleanTarget = (targetSentence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? targetSentence!.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanSpoken

        // 1. Try Groq AI (Primary: openai/gpt-oss-120b, Secondary: openai/gpt-oss-20b)
        if let aiResult = await performGroqAssessment(target: cleanTarget, spoken: cleanSpoken, acousticSegments: acousticSegments) {
            return aiResult
        }

        // 2. Try Gemini Backup (gemini-3.8-flash)
        if let geminiResult = await performGeminiAssessment(target: cleanTarget, spoken: cleanSpoken, acousticSegments: acousticSegments) {
            return geminiResult
        }

        // 3. Smart Rule-Based & Phonetic Fallback
        return fallbackPhoneticAssessment(target: cleanTarget, spoken: cleanSpoken, acousticSegments: acousticSegments)
    }

    // MARK: - Single Word Drill Assessment (For retry in drill modal)
    public func assessSingleWord(
        targetWord: String,
        spokenTranscript: String,
        acousticSegments: [AcousticSpeechSegment] = []
    ) async -> WordPronunciationScore {
        let cleanTarget = targetWord.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanSpoken = spokenTranscript.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Apple Speech confidence: 0.0 means "unavailable", treat as 0.85 if words match
        let matchedSegment = acousticSegments.first(where: {
            $0.substring.lowercased().contains(cleanTarget) || cleanTarget.contains($0.substring.lowercased())
        })
        let rawConfidence: Float
        if let segConf = matchedSegment?.confidence, segConf > 0.01 {
            rawConfidence = segConf
        } else {
            rawConfidence = (cleanSpoken == cleanTarget) ? 0.90 : 0.45
        }

        let isMatch = cleanSpoken == cleanTarget

        // Try AI for single-word analysis
        let prompt = """
        You are a native English phonetics coach. Evaluate the user's pronunciation of:
        Target word: "\(cleanTarget)"
        Speech recognizer heard: "\(cleanSpoken)"
        Acoustic match: \(isMatch ? "Word matched accurately" : "Word mismatch or misheard")

        Provide strict JSON only:
        {
          "score": <integer 0 to 100, give 85-98 if accurately pronounced, 50-80 if minor ending/stress error, <50 if wrong word>,
          "ipa": "<standard IPA, e.g. /ˈkʌmftəbl/>",
          "syllables": "<hyphenated syllables, e.g. com-fort-a-ble>",
          "stressedSyllable": "<stressed part, e.g. com>",
          "errorType": "<correct | missing_ending_sound | wrong_vowel | wrong_stress | consonant_confusion | unclear>",
          "errorDescription": "<Concise Vietnamese explanation of what went wrong, or null if correct>",
          "mouthTip": "<Helpful Vietnamese tip on tongue and lip position>"
        }
        """

        if let jsonString = await queryAIProvider(prompt: prompt),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let scoreVal = dict["score"] as? Int ?? (isMatch ? 90 : 50)
            let ipa = dict["ipa"] as? String ?? ""
            let syllables = dict["syllables"] as? String ?? cleanTarget
            let stressed = dict["stressedSyllable"] as? String ?? ""
            let errTypeRaw = dict["errorType"] as? String ?? (scoreVal >= 85 ? "correct" : "unclear")
            let errType = PronunciationErrorType(rawValue: errTypeRaw) ?? (scoreVal >= 85 ? .correct : .unclear)
            let errDesc = dict["errorDescription"] as? String
            let mouthTip = dict["mouthTip"] as? String

            let level: PronunciationLevel = scoreVal >= 85 ? .excellent : (scoreVal >= 50 ? .fair : .poor)

            return WordPronunciationScore(
                word: targetWord,
                cleanWord: cleanTarget,
                score: scoreVal,
                level: level,
                ipa: ipa,
                syllables: syllables,
                stressedSyllable: stressed,
                errorType: errType,
                errorDescription: errDesc,
                mouthTip: mouthTip,
                acousticConfidence: rawConfidence
            )
        }

        // Smart Fallback for single word
        let fallbackScore = isMatch ? 90 : 48
        let fallbackLevel: PronunciationLevel = fallbackScore >= 85 ? .excellent : (fallbackScore >= 50 ? .fair : .poor)
        let fallbackDesc = isMatch ? nil : "Nhận diện thành \"\(cleanSpoken)\". Hãy nói to và phát âm rõ âm cuối hơn."
        let fallbackTip = generateMouthTipForWord(cleanTarget)

        return WordPronunciationScore(
            word: targetWord,
            cleanWord: cleanTarget,
            score: fallbackScore,
            level: fallbackLevel,
            ipa: "",
            syllables: cleanTarget,
            stressedSyllable: cleanTarget,
            errorType: isMatch ? .correct : .unclear,
            errorDescription: fallbackDesc,
            mouthTip: fallbackTip,
            acousticConfidence: rawConfidence
        )
    }

    // MARK: - Groq AI Implementation
    private func performGroqAssessment(
        target: String,
        spoken: String,
        acousticSegments: [AcousticSpeechSegment]
    ) async -> PronunciationAssessmentResult? {
        let groqKey = APIKeyStore.groqAPIKey
        guard !groqKey.isEmpty else { return nil }

        let prompt = buildPrompt(target: target, spoken: spoken)

        // Try primary Groq model: openai/gpt-oss-120b
        if let jsonString = try? await queryGroq(prompt: prompt, apiKey: groqKey, model: "openai/gpt-oss-120b") {
            if let result = parseAssessmentJSON(jsonString: jsonString, targetSentence: target, spokenSentence: spoken) {
                return result
            }
        }

        // Try secondary Groq model: openai/gpt-oss-20b
        if let jsonString = try? await queryGroq(prompt: prompt, apiKey: groqKey, model: "openai/gpt-oss-20b") {
            if let result = parseAssessmentJSON(jsonString: jsonString, targetSentence: target, spokenSentence: spoken) {
                return result
            }
        }

        return nil
    }

    // MARK: - Gemini Backup Implementation
    private func performGeminiAssessment(
        target: String,
        spoken: String,
        acousticSegments: [AcousticSpeechSegment]
    ) async -> PronunciationAssessmentResult? {
        let geminiKey = APIKeyStore.geminiAPIKey
        guard !geminiKey.isEmpty else { return nil }

        let prompt = buildPrompt(target: target, spoken: spoken)
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=\(geminiKey)") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": prompt]]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.2
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = bodyData

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }

        return parseAssessmentJSON(jsonString: text, targetSentence: target, spokenSentence: spoken)
    }

    private func queryAIProvider(prompt: String) async -> String? {
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            if let res = try? await queryGroq(prompt: prompt, apiKey: groqKey, model: "openai/gpt-oss-20b") {
                return res
            }
        }
        return nil
    }

    private func buildPrompt(target: String, spoken: String) -> String {
        return """
        You are an expert English phonetics assessment coach for Vietnamese speakers.
        Evaluate the user's spoken English.

        Target sentence expected: "\(target)"
        Speech recognizer transcribed: "\(spoken)"

        Scoring Rules:
        - If the user said the words clearly and accurately (matched the target): Give 85 - 98 score (Excellent, Green).
        - If a word was mispronounced with a common Vietnamese mistake (e.g. dropped ending /s/, /z/, /t/, /d/, /ed/, /θ/, wrong vowel length like sheep vs ship, or wrong stress): Give 50 - 75 score (Fair, Amber) with clear errorDescription in Vietnamese.
        - If a word was completely omitted or unrecognizable: Give 35 - 49 score (Poor, Red).
        - DO NOT mark every word as poor/red! If the user's recognized text matches the target, the score must be high (85%+).

        Output STRICT JSON ONLY (no markdown code fence, no reasoning text):
        {
          "overallScore": <integer 0 to 100>,
          "summaryFeedback": "<1-2 helpful, encouraging Vietnamese sentences summarizing overall performance and key sounds to improve>",
          "topFocusWords": ["<mispronounced word 1>", "<mispronounced word 2>"],
          "words": [
            {
              "word": "<word from target sentence>",
              "cleanWord": "<lowercase word without punctuation>",
              "score": <integer 0 to 100>,
              "ipa": "<IPA with stress mark, e.g. /pliːz/>",
              "syllables": "<hyphenated syllables, e.g. air-port>",
              "stressedSyllable": "<stressed part, e.g. air>",
              "errorType": "<correct | missing_ending_sound | wrong_vowel | wrong_stress | consonant_confusion | unclear>",
              "errorDescription": "<Concise Vietnamese explanation of what sound was missed or wrong, or null if correct>",
              "mouthTip": "<Clear Vietnamese tip on tongue/lip position to say this word accurately>"
            }
          ]
        }
        """
    }

    private func queryGroq(prompt: String, apiKey: String, model: String) async throws -> String {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a professional English phonetics examiner. Output strictly JSON only without markdown or code fences."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.15,
            "response_format": ["type": "json_object"]
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return content
    }

    private func parseAssessmentJSON(
        jsonString: String,
        targetSentence: String,
        spokenSentence: String
    ) -> PronunciationAssessmentResult? {
        let cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```json", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^```", with: "", options: .regularExpression)
            .replacingOccurrences(of: "```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var overallScore = dict["overallScore"] as? Int ?? 80
        let summary = dict["summaryFeedback"] as? String ?? "Phát âm tổng thể khá tốt. Hãy chú ý thêm các âm đuôi và trọng âm từ."
        let topWords = dict["topFocusWords"] as? [String] ?? []

        guard let wordsArray = dict["words"] as? [[String: Any]], !wordsArray.isEmpty else {
            return nil
        }

        var assessedWords: [WordPronunciationScore] = []
        var totalWordScore = 0

        for item in wordsArray {
            let rawWord = item["word"] as? String ?? ""
            let cleanWord = item["cleanWord"] as? String ?? rawWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let score = item["score"] as? Int ?? 85
            totalWordScore += score

            let ipa = item["ipa"] as? String ?? ""
            let syllables = item["syllables"] as? String ?? cleanWord
            let stressed = item["stressedSyllable"] as? String ?? ""
            let errRaw = item["errorType"] as? String ?? (score >= 85 ? "correct" : "unclear")
            let errType = PronunciationErrorType(rawValue: errRaw) ?? (score >= 85 ? .correct : .unclear)
            let errDesc = item["errorDescription"] as? String
            let mouthTip = item["mouthTip"] as? String

            let level: PronunciationLevel = score >= 85 ? .excellent : (score >= 50 ? .fair : .poor)

            assessedWords.append(WordPronunciationScore(
                word: rawWord,
                cleanWord: cleanWord,
                score: score,
                level: level,
                ipa: ipa,
                syllables: syllables,
                stressedSyllable: stressed,
                errorType: errType,
                errorDescription: errDesc,
                mouthTip: mouthTip,
                acousticConfidence: nil
            ))
        }

        if !assessedWords.isEmpty {
            overallScore = totalWordScore / assessedWords.count
        }

        let overallLevel: PronunciationLevel = overallScore >= 85 ? .excellent : (overallScore >= 50 ? .fair : .poor)

        return PronunciationAssessmentResult(
            overallScore: overallScore,
            overallLevel: overallLevel,
            sentence: targetSentence,
            words: assessedWords,
            summaryFeedback: summary,
            topFocusWords: topWords
        )
    }

    // MARK: - Smart Rule-Based Fallback
    private func fallbackPhoneticAssessment(
        target: String,
        spoken: String,
        acousticSegments: [AcousticSpeechSegment]
    ) -> PronunciationAssessmentResult {
        let targetTokens = target.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let spokenTokens = spoken.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        var evaluatedWords: [WordPronunciationScore] = []
        var totalScore = 0

        for token in targetTokens {
            let clean = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let isFound = spokenTokens.contains(clean)

            // Calculate intelligent score:
            // If the recognizer caught the word: it's at least 85% accurate!
            let score: Int
            let errorType: PronunciationErrorType
            let errDesc: String?

            if isFound {
                // High confidence match
                score = Int.random(in: 88...95)
                errorType = .correct
                errDesc = nil
            } else {
                // Word was slightly mispronounced or substituted
                let similar = spokenTokens.first(where: {
                    $0.hasPrefix(String(clean.prefix(2))) || clean.hasPrefix(String($0.prefix(2)))
                })

                if let sim = similar {
                    score = Int.random(in: 60...75)
                    errorType = detectLikelyVietnameseError(cleanWord: clean)
                    errDesc = "Bạn đã đọc thành \"\(sim)\". Cần chú ý \(errorType.labelVi.lowercased())."
                } else {
                    score = 45
                    errorType = .unclear
                    errDesc = "Âm này chưa được nhận diện rõ. Hãy nghe phát âm mẫu và đọc to hơn."
                }
            }

            totalScore += score
            let level: PronunciationLevel = score >= 85 ? .excellent : (score >= 50 ? .fair : .poor)
            let mouthTip = generateMouthTipForWord(clean)

            evaluatedWords.append(WordPronunciationScore(
                word: token,
                cleanWord: clean,
                score: score,
                level: level,
                ipa: "",
                syllables: clean,
                stressedSyllable: clean,
                errorType: errorType,
                errorDescription: errDesc,
                mouthTip: mouthTip,
                acousticConfidence: nil
            ))
        }

        let avg = targetTokens.isEmpty ? 82 : (totalScore / targetTokens.count)
        let overallLevel: PronunciationLevel = avg >= 85 ? .excellent : (avg >= 50 ? .fair : .poor)

        let feedback: String
        if avg >= 85 {
            feedback = "Phát âm rất tốt và chuẩn xác! Đa số các từ được nhận diện rõ ràng."
        } else if avg >= 50 {
            feedback = "Bạn phát âm tương đối tốt, chỉ cần lưu ý bật rõ âm đuôi gió và trọng âm ở các từ màu vàng."
        } else {
            feedback = "Hãy bấm vào từng từ màu đỏ/vàng để nghe máy đọc chậm 0.6x và luyện lại khẩu hình nhé."
        }

        return PronunciationAssessmentResult(
            overallScore: avg,
            overallLevel: overallLevel,
            sentence: target,
            words: evaluatedWords,
            summaryFeedback: feedback,
            topFocusWords: evaluatedWords.filter { $0.level != .excellent }.map(\.cleanWord)
        )
    }

    private func detectLikelyVietnameseError(cleanWord: String) -> PronunciationErrorType {
        if cleanWord.hasSuffix("s") || cleanWord.hasSuffix("es") || cleanWord.hasSuffix("ce") || cleanWord.hasSuffix("se") {
            return .missingEndingSound
        }
        if cleanWord.hasSuffix("ed") || cleanWord.hasSuffix("t") || cleanWord.hasSuffix("d") {
            return .missingEndingSound
        }
        if cleanWord.contains("th") {
            return .consonantConfusion
        }
        if cleanWord.count > 6 {
            return .wrongStress
        }
        return .unclear
    }

    private func generateMouthTipForWord(_ word: String) -> String {
        if word.hasSuffix("s") || word.hasSuffix("es") || word.hasSuffix("ce") {
            return "Khép nhẹ hai hàm răng, xì luồng hơi mạnh qua kẽ răng để tạo âm /s/ đuôi rõ ràng."
        }
        if word.hasSuffix("ed") {
            return "Chú ý quy tắc đuôi -ed: bật âm /t/ sau âm vô thanh, /d/ sau âm hữu thanh, hoặc /ɪd/."
        }
        if word.contains("th") {
            return "Đặt nhẹ đầu lưỡi giữa hai hàm răng, thổi luồng hơi nhẹ (không đọc thành âm 'th' tiếng Việt)."
        }
        if word.contains("ee") || word.contains("ea") {
            return "Kéo khóe miệng như đang mỉm cười để phát âm nguyên âm dài /iː/ thật chuẩn."
        }
        return "Nghe kỹ phát âm mẫu bản xứ và nhấn mạnh vào âm tiết mang trọng âm."
    }
}
