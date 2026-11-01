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

    func quickLookupWord(
        word: String,
        sentence: String
    ) async throws -> AIQuickWordLookupResponse
}

@MainActor
final class QuickWordLookupCache {
    static let shared = QuickWordLookupCache()
    private var storage: [String: AIQuickWordLookupResponse] = [:]

    private init() {}

    private func makeKey(word: String, sentence: String) -> String {
        "\(word.normalizedVocabularyWord)|\(sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    func get(word: String, sentence: String) -> AIQuickWordLookupResponse? {
        storage[makeKey(word: word, sentence: sentence)]
    }

    func set(_ response: AIQuickWordLookupResponse, word: String, sentence: String) {
        storage[makeKey(word: word, sentence: sentence)] = response
    }
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
        do {
            return try await provider.lookupWord(
                word: word,
                context: context
            )
        } catch {
            print("DEBUG: Primary vocabulary provider \(provider.name) failed: \(error). Falling back to backup provider...")
            if provider.name == "Groq" && !APIKeyStore.geminiAPIKey.isEmpty {
                for gm in ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash"] {
                    if let res = try? await GeminiVocabularyAIProvider(model: gm).lookupWord(word: word, context: context) {
                        return res
                    }
                }
            } else if !APIKeyStore.groqAPIKey.isEmpty {
                for gr in ["openai/gpt-oss-120b", "openai/gpt-oss-20b"] {
                    if let res = try? await GroqVocabularyAIProvider(model: gr).lookupWord(word: word, context: context) {
                        return res
                    }
                }
            }
            throw error
        }
    }

    func quickLookupWord(
        word: String,
        sentence: String
    ) async throws -> AIQuickWordLookupResponse {
        do {
            return try await provider.quickLookupWord(
                word: word,
                sentence: sentence
            )
        } catch {
            if provider.name == "Groq" && !APIKeyStore.geminiAPIKey.isEmpty {
                if let res = try? await GeminiVocabularyAIProvider(model: "gemini-3.8-flash").quickLookupWord(word: word, sentence: sentence) {
                    return res
                }
            } else if !APIKeyStore.groqAPIKey.isEmpty {
                if let res = try? await GroqVocabularyAIProvider(model: "openai/gpt-oss-120b").quickLookupWord(word: word, sentence: sentence) {
                    return res
                }
            }
            throw error
        }
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
        You are an expert English-Vietnamese dictionary, vocabulary coach, and idiom/phrase specialist.
        Given an English word or multi-word phrase (and optional context sentence where it appeared), provide:
        - "word": the base or normalized form of the target word or phrase (e.g. "look forward to", "take into account", "resilient")
        - "phonetic": accurate IPA pronunciation
        - "partOfSpeech": grammatical category (e.g. "Phrasal verb", "Idiom", "Collocation", "Noun", "Verb", "Adjective", "Adverb")
        - "vietnameseMeaning": clear, concise, natural Vietnamese meaning appropriate for the context
        - "englishDefinition": short, easy-to-understand English definition
        - "exampleSentence": one natural English example sentence using the word or phrase
        - "synonyms": 3 to 6 common English synonyms or related expressions
        - "chatTopics": 2 to 3 engaging daily conversation topics related to the word or phrase so the user can practice using it in a real chat. Each topic must include:
          1. "title": short topic title (3 to 6 words)
          2. "contextDescription": 1 to 2 sentences describing the conversation scenario and instructing the AI coach to help the user practice using the word or phrase naturally
          3. "starterQuestion": a friendly opening question in English from the coach that invites the user to reply using the word or phrase
          4. "sampleReplies": 2 to 3 natural English reply sentences that answer the starterQuestion and actively use the target word or phrase
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

struct QuickWordLookupPrompt {

    let system: String
    let user: String

    init(word: String, sentence: String) {
        system = """
        You are an English-Vietnamese dictionary and syntax coach.
        Given a selected English word or multi-word phrase and the exact sentence where it appears, provide a fast, concise breakdown in Vietnamese:
        - "word": the exact word or phrase as it appears (without leading/trailing punctuation)
        - "baseForm": the dictionary base form / lemma of the word or phrase (e.g. "look forward to", "take into account")
        - "phonetic": IPA pronunciation (e.g. "/rɪˌkəˈmend/")
        - "partOfSpeech": short part of speech or phrase type in this sentence (e.g. "verb", "noun", "phrasal verb", "idiom", "collocation", "noun phrase", "adjective")
        - "contextualMeaning": concise Vietnamese meaning of this word or phrase specifically in the context of the sentence (1 short line)
        - "grammarRoleInSentence": concise Vietnamese explanation (1 to 2 sentences) of what grammatical role this word or phrase plays in the sentence (e.g. "Cụm động từ chính trong mệnh đề, đi kèm giới từ 'to' + danh từ", or "Động từ chính chia ở quá khứ đơn trong mệnh đề quan hệ")
        - "structurePattern": if the word or phrase is part of a notable collocation, phrasal verb, or grammar pattern in this sentence, write that pattern (e.g. "recommend something to someone", "perspective on + N", "take a rain check"); otherwise return ""
        """

        user = """
        Selected word/phrase: "\(word)"
        Full sentence: "\(sentence)"
        """
    }
}

final class GeminiVocabularyAIProvider: VocabularyLookupAIProvider {

    let name = "Gemini"

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(
        apiKey: String = APIKeyStore.geminiAPIKey,
        model: String = "gemini-3.8-flash",
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

    func quickLookupWord(
        word: String,
        sentence: String
    ) async throws -> AIQuickWordLookupResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = QuickWordLookupPrompt(word: word, sentence: sentence)

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
                responseSchema: Self.quickLookupSchema
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

        return try AIQuickWordLookupResponse.decodeFromAIContent(content)
    }

    private static let quickLookupSchema = GeminiSchema(
        type: "object",
        required: [
            "word",
            "baseForm",
            "phonetic",
            "partOfSpeech",
            "contextualMeaning",
            "grammarRoleInSentence",
            "structurePattern"
        ],
        properties: [
            "word": GeminiSchemaProperty(type: "string"),
            "baseForm": GeminiSchemaProperty(type: "string"),
            "phonetic": GeminiSchemaProperty(type: "string"),
            "partOfSpeech": GeminiSchemaProperty(type: "string"),
            "contextualMeaning": GeminiSchemaProperty(type: "string"),
            "grammarRoleInSentence": GeminiSchemaProperty(type: "string"),
            "structurePattern": GeminiSchemaProperty(type: "string")
        ]
    )

    private static let responseSchema = GeminiSchema(
        type: "object",
        required: [
            "word",
            "phonetic",
            "partOfSpeech",
            "vietnameseMeaning",
            "englishDefinition",
            "exampleSentence",
            "synonyms",
            "chatTopics"
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
            ),
            "chatTopics": GeminiSchemaProperty(
                type: "array",
                description: "2 to 3 conversation topics to practice using the vocabulary word.",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "title": GeminiSchemaProperty(
                            type: "string",
                            description: "Short 3 to 6 word conversation topic title."
                        ),
                        "contextDescription": GeminiSchemaProperty(
                            type: "string",
                            description: "1 to 2 sentence AI context describing the conversation topic and target vocabulary word."
                        ),
                        "starterQuestion": GeminiSchemaProperty(
                            type: "string",
                            description: "A friendly opening question from the coach related to the topic."
                        ),
                        "sampleReplies": GeminiSchemaProperty(
                            type: "array",
                            description: "2 to 3 natural English replies that answer the starterQuestion using the target vocabulary word.",
                            items: GeminiSchemaProperty(type: "string")
                        )
                    ],
                    required: ["title", "contextDescription", "starterQuestion", "sampleReplies"]
                )
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

    func quickLookupWord(
        word: String,
        sentence: String
    ) async throws -> AIQuickWordLookupResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = QuickWordLookupPrompt(word: word, sentence: sentence)

        let body = GroqChatCompletionRequest(
            model: model,
            messages: [
                GroqMessage(
                    role: "system",
                    content: prompt.system + "\n\n" + Self.quickJsonInstruction
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

        return try AIQuickWordLookupResponse.decodeFromAIContent(content)
    }

    private static let quickJsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "word": "recommended",
      "baseForm": "recommend",
      "phonetic": "/ˌrek.əˈmend/",
      "partOfSpeech": "verb",
      "contextualMeaning": "giới thiệu, khuyên dùng",
      "grammarRoleInSentence": "Động từ chính chia ở thì quá khứ đơn (V2/ed) trong mệnh đề quan hệ 'that you recommended yesterday' bổ nghĩa cho danh từ 'The book'.",
      "structurePattern": "recommend something (to someone)"
    }
    """

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
      "synonyms": ["instance", "sample", "illustration", "case"],
      "chatTopics": [
        {
          "title": "Learning New Skills",
          "contextDescription": "Practice casual English conversation about learning new skills and using the word 'example' naturally.",
          "starterQuestion": "What is a skill you learned recently? Can you share an example of how you practice it?",
          "sampleReplies": [
            "For example, I practice speaking English every evening.",
            "A good example is cooking, which I started learning last month.",
            "My favorite example is learning to play guitar from online videos."
          ]
        }
      ]
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

private extension AIQuickWordLookupResponse {

    static func decodeFromAIContent(_ content: String) throws -> AIQuickWordLookupResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = AIVocabularyLookupResponse.strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder()
            .decode(AIQuickWordLookupResponse.self, from: jsonData)
    }
}
