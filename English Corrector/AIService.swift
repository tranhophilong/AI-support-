//
//  AIService.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import Foundation

protocol EnglishCorrectionAIProvider {

    var name: String { get }

    func improveEnglish(
        userInput: String,
        context: String
    ) async throws -> AICorrectionResponse
}

final class AIService {

    private let provider: EnglishCorrectionAIProvider

    init(provider: EnglishCorrectionAIProvider = GroqAIProvider()) {
        self.provider = provider
    }

    func improveEnglish(
        userInput: String,
        context: String
    ) async throws -> AICorrectionResponse {
        try await provider.improveEnglish(
            userInput: userInput,
            context: context
        )
    }
}

enum AIModelOption: String, CaseIterable, Identifiable {

    case groqGPTOSS20B
    case groqGPTOSS120B
    case geminiFlash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groqGPTOSS20B:
            return "Groq GPT OSS 20B"
        case .groqGPTOSS120B:
            return "Groq GPT OSS 120B"
        case .geminiFlash:
            return "Gemini Flash"
        }
    }

    var subtitle: String {
        switch self {
        case .groqGPTOSS20B:
            return "Fast and lightweight"
        case .groqGPTOSS120B:
            return "Better quality"
        case .geminiFlash:
            return "Google Gemini"
        }
    }

    var providerName: String {
        switch self {
        case .groqGPTOSS20B, .groqGPTOSS120B:
            return "Groq"
        case .geminiFlash:
            return "Gemini"
        }
    }

    var modelID: String {
        switch self {
        case .groqGPTOSS20B:
            return "openai/gpt-oss-20b"
        case .groqGPTOSS120B:
            return "openai/gpt-oss-120b"
        case .geminiFlash:
            return "gemini-3.6-flash"
        }
    }

    func makeProvider() -> EnglishCorrectionAIProvider {
        switch self {
        case .groqGPTOSS20B, .groqGPTOSS120B:
            return GroqAIProvider(model: modelID)
        case .geminiFlash:
            return GeminiAIProvider(model: modelID)
        }
    }
}

struct EnglishCorrectionPrompt {

    let system: String
    let user: String

    init(userInput: String, context: String) {
        system = """
        You are an English speaking coach helping Vietnamese users improve daily conversational English.

        Your tasks:
        - Fix grammar mistakes
        - Make sentence sound natural
        - Keep original meaning
        - Explain corrections simply and friendly
        - For each explanation, provide a "explanation_noted" field with the specific grammatical terms or keywords that should be highlighted (e.g., "past tense", "comma", "compound word", "grammar").
        """

        user = """
        Context:
        \(context)

        User sentence:
        \(userInput)
        """
    }
}

final class GeminiAIProvider: EnglishCorrectionAIProvider {

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

    func improveEnglish(
        userInput: String,
        context: String
    ) async throws -> AICorrectionResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = EnglishCorrectionPrompt(
            userInput: userInput,
            context: context
        )

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
        request.addValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
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

        print("AI CONTENT STRING:")
        print(content)

        return try AICorrectionResponse.decodeFromAIContent(content)
    }
}

final class GroqAIProvider: EnglishCorrectionAIProvider {

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

    func improveEnglish(
        userInput: String,
        context: String
    ) async throws -> AICorrectionResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = EnglishCorrectionPrompt(
            userInput: userInput,
            context: context
        )

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
        request.addValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.addValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
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

        print("AI CONTENT STRING:")
        print(content)

        return try AICorrectionResponse.decodeFromAIContent(content)
    }
}

private extension GroqAIProvider {

    static let jsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "fixed": "Corrected sentence",
      "natural": "Natural conversational sentence",
      "explanations": [
        {
          "text": "Simple explanation",
          "explanation_noted": "grammar keyword"
        }
      ],
      "corrections": [
        {
          "wrong": "wrong text",
          "correct": "correct text"
        }
      ]
    }
    """
}

private extension GeminiAIProvider {

    static let responseSchema = GeminiSchema(
        type: "object",
        required: ["fixed", "natural", "explanations", "corrections"],
        properties: [
            "fixed": GeminiSchemaProperty(
                type: "string",
                description: "The grammatically corrected sentence."
            ),
            "natural": GeminiSchemaProperty(
                type: "string",
                description: "A natural conversational version of the sentence."
            ),
            "explanations": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "text": GeminiSchemaProperty(
                            type: "string",
                            description: "A simple explanation of one correction."
                        ),
                        "explanation_noted": GeminiSchemaProperty(
                            type: "string",
                            description: "Grammar keyword to highlight."
                        )
                    ],
                    required: ["text", "explanation_noted"]
                )
            ),
            "corrections": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "wrong": GeminiSchemaProperty(type: "string"),
                        "correct": GeminiSchemaProperty(type: "string")
                    ],
                    required: ["wrong", "correct"]
                )
            )
        ]
    )
}

enum APIKeyStore {

    static var groqAPIKey: String {
        if let key = value(
            for: "GROQ_API_KEY",
            placeholder: "YOUR_GROQ_API_KEY",
            configFileName: "GroqConfig"
        ) {
            return key
        }

        print("GROQ_API_KEY missing from Info.plist, GroqConfig.plist, and environment")
        return ""
    }

    static var geminiAPIKey: String {
        if let key = value(
            for: "GEMINI_API_KEY",
            placeholder: "YOUR_GEMINI_API_KEY",
            configFileName: "GeminiConfig"
        ) {
            return key
        }

        print("GEMINI_API_KEY missing from Info.plist, GeminiConfig.plist, and environment")
        return ""
    }

    private static func value(
        for keyName: String,
        placeholder: String,
        configFileName: String
    ) -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: keyName) as? String,
           let cleanKey = normalizedAPIKey(
            key,
            keyName: keyName,
            placeholder: placeholder
           ) {
            print("\(keyName) loaded from Info.plist")
            return cleanKey
        }

        if let key = valueFromConfigFile(
            keyName: keyName,
            fileName: configFileName
        ),
           let cleanKey = normalizedAPIKey(
            key,
            keyName: keyName,
            placeholder: placeholder
           ) {
            print("\(keyName) loaded from \(configFileName).plist")
            return cleanKey
        }

        if let key = ProcessInfo.processInfo.environment[keyName],
           let cleanKey = normalizedAPIKey(
            key,
            keyName: keyName,
            placeholder: placeholder
           ) {
            print("\(keyName) loaded from environment")
            return cleanKey
        }

        return nil
    }

    private static func valueFromConfigFile(
        keyName: String,
        fileName: String
    ) -> String? {
        guard let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "plist"
        ),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ) as? [String: Any] else {
            return nil
        }

        return plist[keyName] as? String
    }

    private static func normalizedAPIKey(
        _ key: String,
        keyName: String,
        placeholder: String
    ) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty,
              trimmedKey != "$(\(keyName))",
              trimmedKey != placeholder else {
            return nil
        }

        return trimmedKey
    }
}

private extension AICorrectionResponse {

    static func decodeFromAIContent(_ content: String) throws -> AICorrectionResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder()
            .decode(AICorrectionResponse.self, from: jsonData)
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

enum AIServiceError: LocalizedError {

    case missingAPIKey(provider: String, keyName: String)
    case emptyResponse(provider: String)
    case apiError(provider: String, message: String)
    case requestFailed(provider: String, statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider, let keyName):
            return "Missing \(keyName) for \(provider). Add it to config, Info.plist, or the Xcode scheme environment variables."
        case .emptyResponse(let provider):
            return "\(provider) returned an empty response."
        case .apiError(_, let message):
            return message
        case .requestFailed(let provider, let statusCode, let message):
            return "\(provider) request failed with status \(statusCode): \(message ?? "No response body")"
        }
    }
}
