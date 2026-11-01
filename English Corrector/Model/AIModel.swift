import Foundation

struct GeminiGenerateContentRequest: Codable {

    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

struct GeminiContent: Codable {

    let parts: [GeminiPart]
}

struct GeminiPart: Codable {

    let text: String
}

struct GeminiGenerationConfig: Codable {

    let responseMimeType: String
    let responseSchema: GeminiSchema
}

struct GeminiSchema: Codable {

    let type: String
    let required: [String]
    let properties: [String: GeminiSchemaProperty]
}

final class GeminiSchemaProperty: Codable {

    let type: String?
    let description: String?
    let items: GeminiSchemaProperty?
    let properties: [String: GeminiSchemaProperty]?
    let required: [String]?

    init(
        type: String? = nil,
        description: String? = nil,
        items: GeminiSchemaProperty? = nil,
        properties: [String: GeminiSchemaProperty]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.items = items
        self.properties = properties
        self.required = required
    }
}

struct GeminiGenerateContentResponse: Codable {

    let candidates: [GeminiCandidate]?
    let error: GeminiAPIError?
}

struct GeminiCandidate: Codable {

    let content: GeminiContent?
}

struct GeminiAPIError: Codable {

    let code: Int?
    let message: String
}

struct GroqChatCompletionRequest: Codable {

    let model: String
    let messages: [GroqMessage]
    let temperature: Double
    var max_tokens: Int? = nil
    var response_format: [String: String]? = nil
}

struct GroqMessage: Codable {

    let role: String
    let content: String
}

struct GroqChatCompletionResponse: Codable {

    let choices: [GroqChoice]?
    let error: GroqAPIError?
}

struct GroqChoice: Codable {

    let message: GroqResponseMessage
}

struct GroqResponseMessage: Codable {

    let role: String?
    let content: String?
}

struct GroqAPIError: Codable {

    let message: String
}

// MARK: - AI Correction Response

struct AICorrectionResponse: Codable {

    let fixed: String
    let natural: String
    let alternativeExpressions: [String]?
    let explanations: [ExplanationItem]
    let corrections: [Correction]?
    let followUpQuestion: String?
    let suggestedReplies: [String]?
    let conversationTitle: String?
    let updatedContext: String?
}

struct ExplanationItem: Codable {
    let text: String
    let explanation_noted: String? // Keywords or terms to highlight
}

// MARK: - Word Corrections

struct Correction: Codable, Identifiable {

    let id = UUID()

    let wrong: String

    let correct: String

    enum CodingKeys: String, CodingKey {
        case wrong
        case correct
    }
}


struct ChatMessage: Identifiable {

    let id = UUID()

    let text: String

    let isUser: Bool

    let correction: AICorrectionResponse?
}

// MARK: - AI Vocabulary Lookup Response

struct VocabularyChatTopicSuggestion: Codable, Equatable, Hashable, Identifiable {
    var id: String { title }
    let title: String
    let contextDescription: String
    let starterQuestion: String
    let sampleReplies: [String]
}

struct AIVocabularyLookupResponse: Codable, Equatable {
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let vietnameseMeaning: String
    let englishDefinition: String
    let exampleSentence: String
    let synonyms: [String]
    let chatTopics: [VocabularyChatTopicSuggestion]?
}

// MARK: - AI Next-Word Suggestion Response

struct AINextWordSuggestionResponse: Codable, Equatable {
    let suggestions: [String]
}

// MARK: - AI Situation Ask Response

struct AISituationExpressionItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { "\(tone)-\(english)" }
    let english: String
    let tone: String
    let vietnameseNuance: String
    let exampleExchange: String?
}

struct AISituationAskResponse: Codable, Equatable {
    let situationTitle: String?
    let situationAdvice: String
    let expressions: [AISituationExpressionItem]
    let followUpQuestions: [String]
    let practiceScenario: VocabularyChatTopicSuggestion?
}

// MARK: - AI Sentence Structure Breakdown Response

struct AISentenceComponentItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { "\(symbol)-\(segment)" }
    let segment: String
    let symbol: String        // e.g. "S", "V", "O", "C", "Adv", "Clause", "Conj"
    let roleName: String      // e.g. "Chủ ngữ (Subject)", "Động từ chính (Main Verb)"
    let grammaticalForm: String // e.g. "Noun Phrase", "Present Perfect Verb", "Relative Clause"
    let explanation: String   // Detailed Vietnamese explanation of this component's role
}

struct AISentenceGrammarPatternItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { pattern }
    let pattern: String       // e.g. "have difficulty + V-ing"
    let explanation: String   // Vietnamese explanation of usage & nuance
    let example: String       // Another English example sentence using this pattern
}

struct AISentenceVariationItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { "\(style)-\(sentence)" }
    let style: String         // e.g. "Tự nhiên / Giao tiếp", "Trang trọng / Học thuật", "Rút gọn mệnh đề"
    let sentence: String
    let note: String          // Brief Vietnamese explanation of how the structure changed
}

struct AISentenceStructureFollowUpQA: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    let question: String
    let answer: String
    let examples: [String]
}

struct AISentenceStructureFollowUpResponse: Codable, Equatable {
    let answer: String
    let examples: [String]
    let nextQuestions: [String]
}

struct AISentenceStructureResponse: Codable, Equatable {
    let originalSentence: String
    let correctedSentence: String?
    let vietnameseTranslation: String
    let tense: String
    let sentenceType: String
    let generalFormula: String
    let components: [AISentenceComponentItem]
    let grammarPatterns: [AISentenceGrammarPatternItem]
    let variations: [AISentenceVariationItem]
    let suggestedQuestions: [String]
}

// MARK: - AI Quick Word Lookup (Light Pick Word Popover)

struct AIQuickWordLookupResponse: Codable, Equatable {
    let word: String
    let baseForm: String
    let phonetic: String
    let partOfSpeech: String
    let contextualMeaning: String
    let grammarRoleInSentence: String
    let structurePattern: String?
}

// MARK: - AI Mistake Summary & Improvement Report

struct UserMistakeSample: Codable, Equatable {
    let source: String
    let userOriginal: String
    let correctedSentence: String
    let explanation: String
}

struct AIMistakeExampleItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { "\(wrongSentence)-\(correctSentence)" }
    let wrongSentence: String
    let correctSentence: String
    let explanation: String
}

struct AIMistakeCategoryItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let severity: String
    let frequencyCount: Int
    let whatToImprove: String
    let quickRule: String
    let examples: [AIMistakeExampleItem]
}

struct AIMistakeSummaryResponse: Codable, Equatable {
    let overallAssessment: String
    let topPriorityFocus: String
    let actionableGoals: [String]
    let categories: [AIMistakeCategoryItem]
}

struct MistakeCategoryReminderConfig: Codable, Equatable, Hashable {
    let categoryName: String
    let hour: Int
    let minute: Int
}

// MARK: - AI Scene & Camera Vision Description

struct AISceneObjectVocabularyItem: Codable, Equatable, Hashable, Identifiable {
    var id: String { internalId }
    private let internalId: String
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let vietnameseMeaning: String
    let exampleInContext: String
    let xPercent: Double?
    let yPercent: Double?
    let box2d: [Double]?
    var isOffline: Bool? = false

    init(
        word: String,
        phonetic: String = "",
        partOfSpeech: String = "Noun",
        vietnameseMeaning: String = "",
        exampleInContext: String = "",
        xPercent: Double? = nil,
        yPercent: Double? = nil,
        box2d: [Double]? = nil,
        isOffline: Bool? = false,
        internalId: String = UUID().uuidString
    ) {
        self.internalId = internalId
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.vietnameseMeaning = vietnameseMeaning
        self.exampleInContext = exampleInContext
        self.xPercent = xPercent
        self.yPercent = yPercent
        self.box2d = box2d
        self.isOffline = isOffline
    }

    enum CodingKeys: String, CodingKey {
        case word
        case label
        case phonetic
        case partOfSpeech = "part_of_speech"
        case partOfSpeechAlt = "partOfSpeech"
        case vietnameseMeaning = "vietnamese_meaning"
        case vietnameseMeaningAlt = "vietnameseMeaning"
        case exampleInContext = "example_in_context"
        case exampleInContextAlt = "exampleInContext"
        case point
        case xPercent
        case xPercentAlt = "x_percent"
        case yPercent
        case yPercentAlt = "y_percent"
        case box2d = "box_2d"
        case box2dAlt = "box2d"
        case bbox
        case box
        case isOffline
    }

    init(from decoder: Decoder) throws {
        self.internalId = UUID().uuidString

        if let singleValue = try? decoder.singleValueContainer(),
           let stringWord = try? singleValue.decode(String.self) {
            self.word = stringWord
            self.phonetic = ""
            self.partOfSpeech = "Noun"
            self.vietnameseMeaning = stringWord
            self.exampleInContext = ""
            self.xPercent = nil
            self.yPercent = nil
            self.box2d = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.word = (try? container.decode(String.self, forKey: .word))
            ?? (try? container.decode(String.self, forKey: .label))
            ?? ""
        self.phonetic = (try? container.decode(String.self, forKey: .phonetic)) ?? ""
        self.partOfSpeech = (try? container.decode(String.self, forKey: .partOfSpeech))
            ?? (try? container.decode(String.self, forKey: .partOfSpeechAlt))
            ?? "Noun"
        self.vietnameseMeaning = (try? container.decode(String.self, forKey: .vietnameseMeaning))
            ?? (try? container.decode(String.self, forKey: .vietnameseMeaningAlt))
            ?? ""
        self.exampleInContext = (try? container.decode(String.self, forKey: .exampleInContext))
            ?? (try? container.decode(String.self, forKey: .exampleInContextAlt))
            ?? ""

        func normalizeCoordinate(_ val: Double) -> Double {
            if val > 100.0 {
                return max(0.0, min(100.0, val / 10.0))
            } else if val <= 1.0 && val > 0.0 {
                return max(0.0, min(100.0, val * 100.0))
            } else {
                return max(0.0, min(100.0, val))
            }
        }

        var decodedPoint: [Double]? = nil
        if let pt = try? container.decode([Double].self, forKey: .point) {
            decodedPoint = pt
        } else if let intPt = try? container.decode([Int].self, forKey: .point) {
            decodedPoint = intPt.map { Double($0) }
        }

        var decodedBox: [Double]? = nil
        let boxKeys: [CodingKeys] = [.box2d, .box2dAlt, .bbox, .box]
        for key in boxKeys {
            if let d = try? container.decode([Double].self, forKey: key) {
                decodedBox = d
                break
            }
            if let ints = try? container.decode([Int].self, forKey: key) {
                decodedBox = ints.map { Double($0) }
                break
            }
        }
        self.box2d = decodedBox

        var computedX: Double?
        var computedY: Double?

        // 1. Try point: [x, y]
        if let pt = decodedPoint, pt.count >= 2 {
            computedX = normalizeCoordinate(pt[0])
            computedY = normalizeCoordinate(pt[1])
        }
        // 2. Try visual grounding box [ymin, xmin, ymax, xmax]
        else if let box = decodedBox, box.count >= 4 {
            let ymin = box[0]
            let xmin = box[1]
            let ymax = box[2]
            let xmax = box[3]

            let midX = (xmin + xmax) / 2.0
            let midY = (ymin + ymax) / 2.0

            computedX = normalizeCoordinate(midX)
            computedY = normalizeCoordinate(midY)
        }

        if let computedX, let computedY {
            self.xPercent = computedX
            self.yPercent = computedY
        } else {
            // 3. Try raw xPercent / yPercent with automatic normalization
            var rawX: Double? = nil
            if let x = try? container.decode(Double.self, forKey: .xPercent) {
                rawX = x
            } else if let x = try? container.decode(Double.self, forKey: .xPercentAlt) {
                rawX = x
            } else if let xInt = try? container.decode(Int.self, forKey: .xPercent) {
                rawX = Double(xInt)
            } else if let xInt = try? container.decode(Int.self, forKey: .xPercentAlt) {
                rawX = Double(xInt)
            }

            var rawY: Double? = nil
            if let y = try? container.decode(Double.self, forKey: .yPercent) {
                rawY = y
            } else if let y = try? container.decode(Double.self, forKey: .yPercentAlt) {
                rawY = y
            } else if let yInt = try? container.decode(Int.self, forKey: .yPercent) {
                rawY = Double(yInt)
            } else if let yInt = try? container.decode(Int.self, forKey: .yPercentAlt) {
                rawY = Double(yInt)
            }

            self.xPercent = rawX.map { normalizeCoordinate($0) }
            self.yPercent = rawY.map { normalizeCoordinate($0) }
        }

        self.isOffline = (try? container.decodeIfPresent(Bool.self, forKey: .isOffline)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(phonetic, forKey: .phonetic)
        try container.encode(partOfSpeech, forKey: .partOfSpeechAlt)
        try container.encode(vietnameseMeaning, forKey: .vietnameseMeaningAlt)
        try container.encode(exampleInContext, forKey: .exampleInContextAlt)
        try container.encodeIfPresent(xPercent, forKey: .xPercent)
        try container.encodeIfPresent(yPercent, forKey: .yPercent)
        try container.encodeIfPresent(box2d, forKey: .box2d)
        try container.encodeIfPresent(isOffline, forKey: .isOffline)
    }
}

struct AISceneDescriptionResponse: Codable, Equatable {
    var sceneOverview: String
    var sceneVietnameseTranslation: String
    var objectsDetected: [AISceneObjectVocabularyItem]
    var situationalConversationalPhrases: [String]
    var adviceOrCulturalNote: String?

    enum CodingKeys: String, CodingKey {
        case sceneOverview
        case sceneVietnameseTranslation
        case objectsDetected
        case situationalConversationalPhrases
        case adviceOrCulturalNote
    }

    init(
        sceneOverview: String,
        sceneVietnameseTranslation: String,
        objectsDetected: [AISceneObjectVocabularyItem],
        situationalConversationalPhrases: [String],
        adviceOrCulturalNote: String? = nil
    ) {
        self.sceneOverview = sceneOverview
        self.sceneVietnameseTranslation = sceneVietnameseTranslation
        self.objectsDetected = objectsDetected
        self.situationalConversationalPhrases = situationalConversationalPhrases
        self.adviceOrCulturalNote = adviceOrCulturalNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sceneOverview = (try? container.decode(String.self, forKey: .sceneOverview)) ?? ""
        self.sceneVietnameseTranslation = (try? container.decode(String.self, forKey: .sceneVietnameseTranslation)) ?? ""
        self.objectsDetected = (try? container.decode([AISceneObjectVocabularyItem].self, forKey: .objectsDetected)) ?? []

        if let phrases = try? container.decode([String].self, forKey: .situationalConversationalPhrases) {
            self.situationalConversationalPhrases = phrases
        } else if let dict = try? container.decode([String: String].self, forKey: .situationalConversationalPhrases) {
            self.situationalConversationalPhrases = Array(dict.values)
        } else {
            self.situationalConversationalPhrases = []
        }

        self.adviceOrCulturalNote = try? container.decode(String.self, forKey: .adviceOrCulturalNote)
    }
}

