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






