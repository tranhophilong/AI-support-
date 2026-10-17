//
//  VocabularyAIService.swift
//  English Corrector
//

import Foundation

protocol VocabularyLookupAIProvider {
    var name: String { get }

    func lookupWord(
        word: String,
        context: String?
    ) async throws -> AIVocabularyLookupResponse
}

final class VocabularyAIService {

    private let provider: VocabularyLookupAIProvider

    init(provider: VocabularyLookupAIProvider = GroqVocabularyAIProvider()) {
        self.provider = provider
    }

    func lookupWord(
        word: String,
        context: String? = nil
    ) async throws -> AIVocabularyLookupResponse {
        try await provider.lookupWord(
            word: word,
            context: context
        )
    }
}

extension AIModelOption {

    func makeVocabularyProvider() -> VocabularyLookupAIProvider {
        switch self {
        case .groqGPTOSS20B, .groqGPTOSS120B:
            return GroqVocabularyAIProvider(model: modelID)
        case .geminiFlash:
            return GeminiVocabularyAIProvider(model: modelID)
        }
    }
}

struct VocabularyLookupPrompt {

    let system: String
    let user: String

    init(word: String, context: String?) {
        system = """
        You are an English-Vietnamese dictionary and vocabulary coach.
        Given an English word (and optional context sentence where the word appeared), provide:
        - "word": the base or normalized form of the word
        - "phonetic": IPA pronunciation (e.g. "/ˈnætʃ.ər.əl/")
        - "partOfSpeech": part of speech (e.g. "noun", "verb", "adjective", "adverb")
        - "vietnameseMeaning": clear, concise Vietnamese meaning appropriate for the context
        - "englishDefinition": short, easy-to-understand English definition
        - "exampleSentence": one natural English example sentence using the word
        - "synonyms": 3 to 6 common English synonyms
        """

        let trimmedContext = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedContext.isEmpty {
            user = """
            Word to look up:
            \(word)
            """
        } else {
            user = """
            Word to look up:
            \(word)

            Context sentence:
            \(trimmedContext)
            """
        }
    }
}

final class GeminiVocabularyAIProvider: VocabularyLookupAIProvider {

    let name = "Gemini"

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(
        apiKey: String = APIKeyStore.geminiAPIKey,
        model: String = "gemini-3.6-flash",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func lookupWord(
        word: String,
        context: String?
    ) async throws -> AIVocabularyLookupResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = VocabularyLookupPrompt(word: word, context: context)

        let body = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(
                parts: [GeminiPart(text: prompt.system)]
            ),
            contents: [
                GeminiContent(
                    parts: [GeminiPart(text: prompt.user)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Self.responseSchema
            )
        )

        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed(
                provider: name,
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }

        let responseBody = try JSONDecoder()
            .decode(GeminiGenerateContentResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(
                provider: name,
                message: error.message
            )
        }

        guard let content = responseBody.candidates?
            .first?
            .content?
            .parts
            .first?
            .text else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return try AIVocabularyLookupResponse.decodeFromAIContent(content)
    }

    private static let responseSchema = GeminiSchema(
        type: "object",
        required: [
            "word",
            "phonetic",
            "partOfSpeech",
            "vietnameseMeaning",
            "englishDefinition",
            "exampleSentence",
            "synonyms"
        ],
        properties: [
            "word": GeminiSchemaProperty(
                type: "string",
                description: "The English word being defined."
            ),
            "phonetic": GeminiSchemaProperty(
                type: "string",
                description: "IPA phonetic transcription."
            ),
            "partOfSpeech": GeminiSchemaProperty(
                type: "string",
                description: "Part of speech such as noun, verb, adjective."
            ),
            "vietnameseMeaning": GeminiSchemaProperty(
                type: "string",
                description: "Concise Vietnamese meaning."
            ),
            "englishDefinition": GeminiSchemaProperty(
                type: "string",
                description: "Short English definition."
            ),
            "exampleSentence": GeminiSchemaProperty(
                type: "string",
                description: "A natural example sentence using the word."
            ),
            "synonyms": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(type: "string")
            )
        ]
    )
}

final class GroqVocabularyAIProvider: VocabularyLookupAIProvider {

    let name = "Groq"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let endpoint = URL(
        string: "https://api.groq.com/openai/v1/chat/completions"
    )!

    init(
        apiKey: String = APIKeyStore.groqAPIKey,
        model: String = "openai/gpt-oss-20b",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func lookupWord(
        word: String,
        context: String?
    ) async throws -> AIVocabularyLookupResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = VocabularyLookupPrompt(word: word, context: context)

        let body = GroqChatCompletionRequest(
            model: model,
            messages: [
                GroqMessage(
                    role: "system",
                    content: prompt.system + "\n\n" + Self.jsonInstruction
                ),
                GroqMessage(
                    role: "user",
                    content: prompt.user
                )
            ],
            temperature: 0.2
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed(
                provider: name,
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }

        let responseBody = try JSONDecoder()
            .decode(GroqChatCompletionResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(
                provider: name,
                message: error.message
            )
        }

        guard let content = responseBody.choices?
            .first?
            .message
            .content else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return try AIVocabularyLookupResponse.decodeFromAIContent(content)
    }

    private static let jsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "word": "example",
      "phonetic": "/ɪɡˈzɑːm.pəl/",
      "partOfSpeech": "noun",
      "vietnameseMeaning": "ví dụ, mẫu",
      "englishDefinition": "Something that illustrates a general rule or pattern.",
      "exampleSentence": "Can you give me an example of how to use this word?",
      "synonyms": ["instance", "sample", "illustration", "case"]
    }
    """
}

private extension AIVocabularyLookupResponse {

    static func decodeFromAIContent(_ content: String) throws -> AIVocabularyLookupResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder()
            .decode(AIVocabularyLookupResponse.self, from: jsonData)
    }

    static func strippedMarkdownFence(from content: String) -> String {
        guard content.hasPrefix("```") else {
            return content
        }

        var lines = content.components(separatedBy: .newlines)

        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }

        if lines.last?.hasPrefix("```") == true {
            lines.removeLast()
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
