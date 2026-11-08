//
//  PronunciationAssessmentModel.swift
//  English Corrector
//
//

import Foundation
import SwiftUI

public enum PronunciationLevel: String, Codable, CaseIterable {
    case excellent = "excellent" // >= 85%
    case fair = "fair"           // 50 - 84%
    case poor = "poor"           // < 50%

    public var title: String {
        switch self {
        case .excellent: return "Phát âm chuẩn"
        case .fair: return "Cần cải thiện"
        case .poor: return "Phát âm chưa đúng"
        }
    }

    public var color: Color {
        switch self {
        case .excellent: return Color(lightHex: 0x16A34A, darkHex: 0x22C55E) // Green
        case .fair: return Color(lightHex: 0xD97706, darkHex: 0xFBBF24)      // Amber
        case .poor: return Color(lightHex: 0xDC2626, darkHex: 0xEF4444)      // Red
        }
    }

    public var badgeBackgroundColor: Color {
        color.opacity(0.15)
    }

    public var iconName: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .fair: return "exclamationmark.triangle.fill"
        case .poor: return "xmark.octagon.fill"
        }
    }
}

public enum PronunciationErrorType: String, Codable, CaseIterable {
    case correct = "correct"
    case missingEndingSound = "missing_ending_sound"
    case wrongVowel = "wrong_vowel"
    case wrongStress = "wrong_stress"
    case consonantConfusion = "consonant_confusion"
    case unclear = "unclear"

    public var labelVi: String {
        switch self {
        case .correct: return "Chuẩn"
        case .missingEndingSound: return "Nuốt âm đuôi"
        case .wrongVowel: return "Sai nguyên âm"
        case .wrongStress: return "Sai trọng âm"
        case .consonantConfusion: return "Nhầm phụ âm"
        case .unclear: return "Chưa rõ âm"
        }
    }
}

public struct WordPronunciationScore: Identifiable, Codable, Equatable {
    public var id: String
    public var word: String
    public var cleanWord: String
    public var score: Int
    public var level: PronunciationLevel
    public var ipa: String
    public var syllables: String
    public var stressedSyllable: String
    public var errorType: PronunciationErrorType
    public var errorDescription: String?
    public var mouthTip: String?
    public var acousticConfidence: Float?

    public init(
        id: String = UUID().uuidString,
        word: String,
        cleanWord: String,
        score: Int,
        level: PronunciationLevel,
        ipa: String = "",
        syllables: String = "",
        stressedSyllable: String = "",
        errorType: PronunciationErrorType = .correct,
        errorDescription: String? = nil,
        mouthTip: String? = nil,
        acousticConfidence: Float? = nil
    ) {
        self.id = id
        self.word = word
        self.cleanWord = cleanWord
        self.score = min(max(score, 0), 100)
        self.level = level
        self.ipa = ipa
        self.syllables = syllables
        self.stressedSyllable = stressedSyllable
        self.errorType = errorType
        self.errorDescription = errorDescription
        self.mouthTip = mouthTip
        self.acousticConfidence = acousticConfidence
    }
}

public struct PronunciationAssessmentResult: Identifiable, Codable, Equatable {
    public var id: String
    public var overallScore: Int
    public var overallLevel: PronunciationLevel
    public var sentence: String
    public var words: [WordPronunciationScore]
    public var summaryFeedback: String
    public var topFocusWords: [String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        overallScore: Int,
        overallLevel: PronunciationLevel,
        sentence: String,
        words: [WordPronunciationScore],
        summaryFeedback: String,
        topFocusWords: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.overallScore = min(max(overallScore, 0), 100)
        self.overallLevel = overallLevel
        self.sentence = sentence
        self.words = words
        self.summaryFeedback = summaryFeedback
        self.topFocusWords = topFocusWords
        self.createdAt = createdAt
    }

    public static func empty(sentence: String) -> PronunciationAssessmentResult {
        PronunciationAssessmentResult(
            overallScore: 0,
            overallLevel: .poor,
            sentence: sentence,
            words: [],
            summaryFeedback: ""
        )
    }

    public func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func fromJSONString(_ json: String) -> PronunciationAssessmentResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PronunciationAssessmentResult.self, from: data)
    }
}
