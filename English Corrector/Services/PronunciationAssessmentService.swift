//
//  PronunciationAssessmentService.swift
//  English Corrector
//
//

import Foundation
import SwiftUI

@MainActor
public final class PronunciationAssessmentService {

    public static let shared = PronunciationAssessmentService()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Full Sentence Pronunciation Assessment
    public func assessPronunciation(
        sentence: String,
        acousticSegments: [AcousticSpeechSegment] = []
    ) async -> PronunciationAssessmentResult {
        let cleanedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSentence.isEmpty else {
            return PronunciationAssessmentResult.empty(sentence: "")
        }

        // 1. Try AI-powered analysis with Groq/Gemini
        if let aiResult = await performAIAssessment(sentence: cleanedSentence, acousticSegments: acousticSegments) {
            return aiResult
        }

        // 2. Rule-based / Acoustic fallback if AI network is unavailable
        return fallbackAcousticAssessment(sentence: cleanedSentence, acousticSegments: acousticSegments)
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

        // Acoustic confidence check
        let matchedSegment = acousticSegments.first(where: {
            $0.substring.lowercased().contains(cleanTarget) || cleanTarget.contains($0.substring.lowercased())
        })
        let rawConfidence = matchedSegment?.confidence ?? (cleanSpoken == cleanTarget ? 0.90 : 0.40)

        // Query AI for fast single-word re-evaluation
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            let prompt = """
            Evaluate the pronunciation of the English word "\(cleanTarget)".
            The user tried to say it and speech-to-text recognized: "\(cleanSpoken)".
            Acoustic confidence: \(String(format: "%.2f", rawConfidence)).
            Return JSON only with:
            {
              "score": <0 to 100>,
              "ipa": "<IPA with stress mark, e.g. /ˈkʌmftəbl/>",
              "syllables": "<syllable breakdown, e.g. com-fort-a-ble>",
              "stressedSyllable": "<stressed part, e.g. com>",
              "errorType": "<correct | missing_ending_sound | wrong_vowel | wrong_stress | consonant_confusion | unclear>",
              "errorDescription": "<Concise Vietnamese explanation of pronunciation mistake, or empty if correct>",
              "mouthTip": "<Clear Vietnamese tip on tongue/mouth position to pronounce accurately>"
            }
            """

            if let jsonString = try? await queryGroq(prompt: prompt, apiKey: groqKey),
               let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let scoreVal = dict["score"] as? Int ?? (cleanSpoken == cleanTarget ? 88 : 45)
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
        }

        // Fallback rule for single word
        let isMatch = cleanSpoken == cleanTarget
        let score = isMatch ? Int(max(rawConfidence * 100, 85)) : Int(rawConfidence * 60)
        let level: PronunciationLevel = score >= 85 ? .excellent : (score >= 50 ? .fair : .poor)

        return WordPronunciationScore(
            word: targetWord,
            cleanWord: cleanTarget,
            score: score,
            level: level,
            ipa: "",
            syllables: cleanTarget,
            stressedSyllable: cleanTarget,
            errorType: isMatch ? .correct : .unclear,
            errorDescription: isMatch ? nil : "Chưa nhận diện chuẩn âm này, hãy bật rõ âm đuôi.",
            mouthTip: "Nghe lại phát âm mẫu và tập trung vào trọng âm chính.",
            acousticConfidence: rawConfidence
        )
    }

    // MARK: - Private AI Implementation (Groq API)
    private func performAIAssessment(
        sentence: String,
        acousticSegments: [AcousticSpeechSegment]
    ) async -> PronunciationAssessmentResult? {
        let groqKey = APIKeyStore.groqAPIKey
        guard !groqKey.isEmpty else { return nil }

        // Build acoustic confidence map to guide the LLM
        var confidenceInfo: [String] = []
        for seg in acousticSegments {
            confidenceInfo.append("\(seg.substring): confidence=\(String(format: "%.2f", seg.confidence))")
        }
        let acousticHint = confidenceInfo.isEmpty ? "None" : confidenceInfo.joined(separator: ", ")

        let prompt = """
        You are a native English pronunciation coach specialized in helping Vietnamese learners.
        Analyze this spoken English sentence:
        "\(sentence)"

        Acoustic speech recognition confidence data:
        [\(acousticHint)]

        For Vietnamese learners, pay special attention to:
        1. Missing ending consonant sounds (-s, -es, -ed, -t, -k, -d, -z, -θ, -dʒ).
        2. Vowel confusion (e.g. /iː/ vs /ɪ/, /æ/ vs /e/, /ʌ/ vs /ɑː/).
        3. Incorrect word stress (trọng âm) in multi-syllable words.
        4. Consonant cluster simplifications (e.g., "sp", "st", "str", "pl", "cl").

        Return ONLY a strict JSON object (no markdown code fence, no extra text):
        {
          "overallScore": <integer 0 to 100>,
          "summaryFeedback": "<1-2 concise, encouraging Vietnamese sentences summarizing overall pronunciation quality and key areas to improve>",
          "topFocusWords": ["<word1>", "<word2>"],
          "words": [
            {
              "word": "<original word with punctuation>",
              "cleanWord": "<normalized lowercase word without punctuation>",
              "score": <integer 0 to 100>,
              "ipa": "<standard IPA pronunciation with stress mark /ˈ/ or /ˌ/>",
              "syllables": "<syllable breakdown, e.g. com-fort-a-ble>",
              "stressedSyllable": "<the stressed syllable, e.g. com>",
              "errorType": "<correct | missing_ending_sound | wrong_vowel | wrong_stress | consonant_confusion | unclear>",
              "errorDescription": "<concise Vietnamese note explaining what was mispronounced, or null if correct>",
              "mouthTip": "<practical Vietnamese tip on tongue/lip position to say this word naturally>"
            }
          ]
        }
        """

        guard let jsonString = try? await queryGroq(prompt: prompt, apiKey: groqKey) else {
            return nil
        }

        return parseAssessmentJSON(jsonString: jsonString, originalSentence: sentence, acousticSegments: acousticSegments)
    }

    private func queryGroq(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 18

        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                [
                    "role": "system",
                    "content": "You are an expert English phonetics assessment coach for Vietnamese speakers. Output strict JSON only without markdown code blocks."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.2,
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
        originalSentence: String,
        acousticSegments: [AcousticSpeechSegment]
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

        let overallScore = dict["overallScore"] as? Int ?? 75
        let summary = dict["summaryFeedback"] as? String ?? "Phát âm khá tốt, chú ý thêm âm đuôi và trọng âm."
        let topWords = dict["topFocusWords"] as? [String] ?? []

        guard let wordsArray = dict["words"] as? [[String: Any]] else {
            return nil
        }

        var assessedWords: [WordPronunciationScore] = []
        for item in wordsArray {
            let rawWord = item["word"] as? String ?? ""
            let cleanWord = item["cleanWord"] as? String ?? rawWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
            var score = item["score"] as? Int ?? 80
            let ipa = item["ipa"] as? String ?? ""
            let syllables = item["syllables"] as? String ?? cleanWord
            let stressed = item["stressedSyllable"] as? String ?? ""
            let errRaw = item["errorType"] as? String ?? (score >= 85 ? "correct" : "unclear")
            let errType = PronunciationErrorType(rawValue: errRaw) ?? .correct
            let errDesc = item["errorDescription"] as? String
            let mouthTip = item["mouthTip"] as? String

            // Match acoustic segment confidence
            let matchedSegment = acousticSegments.first(where: {
                $0.substring.lowercased() == cleanWord || $0.substring.lowercased().contains(cleanWord)
            })
            let acousticConf = matchedSegment?.confidence

            // If acoustic confidence is very low (< 0.4), adjust score accordingly
            if let conf = acousticConf, conf < 0.35 && score > 70 {
                score = Int(Double(score) * 0.75 + Double(conf * 100) * 0.25)
            }

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
                acousticConfidence: acousticConf
            ))
        }

        let level: PronunciationLevel = overallScore >= 85 ? .excellent : (overallScore >= 50 ? .fair : .poor)

        return PronunciationAssessmentResult(
            overallScore: overallScore,
            overallLevel: level,
            sentence: originalSentence,
            words: assessedWords,
            summaryFeedback: summary,
            topFocusWords: topWords
        )
    }

    // MARK: - Rule-based Fallback (No network / No API key)
    private func fallbackAcousticAssessment(
        sentence: String,
        acousticSegments: [AcousticSpeechSegment]
    ) -> PronunciationAssessmentResult {
        let rawTokens = sentence.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var evaluatedWords: [WordPronunciationScore] = []
        var totalScore = 0

        for token in rawTokens {
            let clean = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let matchedSeg = acousticSegments.first(where: {
                $0.substring.lowercased() == clean || $0.substring.lowercased().contains(clean)
            })
            let conf = matchedSeg?.confidence ?? 0.80

            let score = Int(min(max(conf * 100, 40), 98))
            totalScore += score

            let level: PronunciationLevel = score >= 85 ? .excellent : (score >= 50 ? .fair : .poor)
            let errType: PronunciationErrorType = score >= 85 ? .correct : .unclear

            evaluatedWords.append(WordPronunciationScore(
                word: token,
                cleanWord: clean,
                score: score,
                level: level,
                ipa: "",
                syllables: clean,
                stressedSyllable: clean,
                errorType: errType,
                errorDescription: score < 85 ? "Cần phát âm rõ ràng và nhấn âm mạnh hơn." : nil,
                mouthTip: "Nghe phát âm chuẩn và luyện lại âm đuôi.",
                acousticConfidence: conf
            ))
        }

        let avg = rawTokens.isEmpty ? 80 : (totalScore / rawTokens.count)
        let overallLevel: PronunciationLevel = avg >= 85 ? .excellent : (avg >= 50 ? .fair : .poor)

        return PronunciationAssessmentResult(
            overallScore: avg,
            overallLevel: overallLevel,
            sentence: sentence,
            words: evaluatedWords,
            summaryFeedback: avg >= 85 ? "Phát âm rất tốt và rõ chữ!" : "Phát âm khá ổn, bạn hãy chạm vào các từ màu vàng/đỏ để nghe mẫu và luyện lại nhé.",
            topFocusWords: evaluatedWords.filter { $0.level != .excellent }.map(\.cleanWord)
        )
    }
}
