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
    let explanations: [ExplanationItem]
    let corrections: [Correction]?
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

struct AIVocabularyLookupResponse: Codable, Equatable {
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let vietnameseMeaning: String
    let englishDefinition: String
    let exampleSentence: String
    let synonyms: [String]
}

