//
//  AIService.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import Foundation
import UIKit

protocol EnglishCorrectionAIProvider {


    var name: String { get }

    func improveEnglish(
        userInput: String,
        context: String,
        recentHistory: [String]
    ) async throws -> AICorrectionResponse

    func suggestNextWords(
        currentInput: String,
        context: String,
        lastQuestion: String?
    ) async throws -> [String]
}

final class AIService {

    private let provider: EnglishCorrectionAIProvider

    init(provider: EnglishCorrectionAIProvider = GroqAIProvider()) {
        self.provider = provider
    }

    func improveEnglish(
        userInput: String,
        context: String,
        recentHistory: [String] = []
    ) async throws -> AICorrectionResponse {
        try await provider.improveEnglish(
            userInput: userInput,
            context: context,
            recentHistory: recentHistory
        )
    }

    func suggestNextWords(
        currentInput: String,
        context: String,
        lastQuestion: String? = nil
    ) async throws -> [String] {
        try await provider.suggestNextWords(
            currentInput: currentInput,
            context: context,
            lastQuestion: lastQuestion
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

    init(userInput: String, context: String, recentHistory: [String] = []) {
        system = """
        You are an English speaking coach helping Vietnamese users improve daily conversational English.

        Your tasks:
        - Fix grammar mistakes in "fixed"
        - Rewrite the user's sentence like a native speaker in "natural", suggesting alternative natural ways to say it (e.g., if the user says "Hello", suggest natural alternatives like "Hi! / Hey there! / How's it going?")
        - Keep original meaning
        - In "explanations", ALWAYS include:
          1. Simple, friendly explanations of any grammar or word-choice corrections
          2. Suggestions for alternative words, synonyms, or other natural ways to express the user's sentence (e.g., suggesting "Hi", "Hey", or "What's up?" as casual alternatives to "Hello"), even when the user's sentence has no grammar mistakes
        - For each explanation, provide an "explanation_noted" field with the specific suggested words, phrases, or grammatical terms that should be highlighted (e.g., "Hi", "Hey there", "past tense", "grammar").
        - Provide a "followUpQuestion": 1 friendly, natural English follow-up question that continues the conversation based on the user's sentence and recent conversation history.
        - Provide "suggestedReplies": 2 to 3 natural English reply sentences that the user could use or adapt to answer your followUpQuestion.
        - Provide a "conversationTitle": a short, natural title (3 to 6 words) reflecting the overall topic of the conversation.
        - Provide an "updatedContext": a concise rolling summary (1 to 3 sentences) of the whole conversation so far, combining the previous context with the recent conversation history and the user's latest message.
        """

        let historySection: String
        if recentHistory.isEmpty {
            historySection = ""
        } else {
            historySection = """

            Recent conversation history:
            \(recentHistory.joined(separator: "\n"))
            """
        }

        user = """
        Previous AI Context:
        \(context.isEmpty ? "New conversation" : context)\(historySection)

        Latest user sentence:
        \(userInput)
        """
    }
}

struct NextWordSuggestionPrompt {

    let system: String
    let user: String

    init(currentInput: String, context: String, lastQuestion: String?) {
        let endsWithSpace = currentInput.last?.isWhitespace == true
        system = """
        You are a real-time English predictive keyboard assistant helping a Vietnamese user write natural conversational English.

        Rules:
        - Suggest 4 to 5 natural continuations (each 1 to 3 words long) that directly follow or complete what the user is typing.
        - Do NOT repeat the entire sentence the user already typed.
        - \(endsWithSpace
            ? "The user finished their last word (ended with a space). Return ONLY the next 1 to 3 words that naturally follow after their text."
            : "If the last word looks incomplete, include completions of that word (optionally with 1-2 following words) OR the next 1 to 3 words that follow after the last word.")
        - Keep suggestions casual, natural, and relevant to the conversation context and coach's last question.
        """

        let questionLine = (lastQuestion?.isEmpty == false)
            ? "\nCoach's last question: \(lastQuestion!)"
            : ""

        user = """
        Conversation context: \(context.isEmpty ? "Casual daily English conversation" : context)\(questionLine)
        User is currently typing: "\(currentInput)"
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
        context: String,
        recentHistory: [String] = []
    ) async throws -> AICorrectionResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = EnglishCorrectionPrompt(
            userInput: userInput,
            context: context,
            recentHistory: recentHistory
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

    func suggestNextWords(
        currentInput: String,
        context: String,
        lastQuestion: String? = nil
    ) async throws -> [String] {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = NextWordSuggestionPrompt(
            currentInput: currentInput,
            context: context,
            lastQuestion: lastQuestion
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
                responseSchema: Self.nextWordSchema
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
            throw AIServiceError.apiError(provider: name, message: error.message)
        }

        guard let content = responseBody.candidates?
            .first?
            .content?
            .parts
            .first?
            .text else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return try AINextWordSuggestionResponse.decodeFromAIContent(content).suggestions
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
        context: String,
        recentHistory: [String] = []
    ) async throws -> AICorrectionResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = EnglishCorrectionPrompt(
            userInput: userInput,
            context: context,
            recentHistory: recentHistory
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

    func suggestNextWords(
        currentInput: String,
        context: String,
        lastQuestion: String? = nil
    ) async throws -> [String] {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = NextWordSuggestionPrompt(
            currentInput: currentInput,
            context: context,
            lastQuestion: lastQuestion
        )

        let body = GroqChatCompletionRequest(
            model: model,
            messages: [
                GroqMessage(
                    role: "system",
                    content: prompt.system + "\n\n" + Self.nextWordJsonInstruction
                ),
                GroqMessage(
                    role: "user",
                    content: prompt.user
                )
            ],
            temperature: 0.3
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
            throw AIServiceError.apiError(provider: name, message: error.message)
        }

        guard let content = responseBody.choices?
            .first?
            .message
            .content else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return try AINextWordSuggestionResponse.decodeFromAIContent(content).suggestions
    }
}

private extension GroqAIProvider {

    static let jsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "fixed": "Corrected sentence",
      "natural": "More natural or alternative ways to say the sentence (e.g. 'Hi! / Hey, how's it going?')",
      "explanations": [
        {
          "text": "Simple explanation of grammar correction OR suggestion of alternative ways to say it (e.g. You can also say 'Hi' or 'Hey' in casual conversation)",
          "explanation_noted": "suggested alternative word or grammar keyword to highlight"
        }
      ],
      "corrections": [
        {
          "wrong": "wrong text",
          "correct": "correct text"
        }
      ],
      "followUpQuestion": "A friendly follow-up question to keep the conversation going",
      "suggestedReplies": [
        "First natural reply option",
        "Second natural reply option",
        "Third natural reply option"
      ],
      "conversationTitle": "Short topic title of the conversation",
      "updatedContext": "Concise summary of the entire conversation so far"
    }
    """

    static let nextWordJsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "suggestions": [
        "next 1-3 words",
        "another natural continuation",
        "third option",
        "fourth option"
      ]
    }
    """
}

private extension GeminiAIProvider {

    static let nextWordSchema = GeminiSchema(
        type: "object",
        required: ["suggestions"],
        properties: [
            "suggestions": GeminiSchemaProperty(
                type: "array",
                description: "4 to 5 natural 1-to-3 word continuations or word completions following the user's current input.",
                items: GeminiSchemaProperty(type: "string")
            )
        ]
    )

    static let responseSchema = GeminiSchema(
        type: "object",
        required: [
            "fixed",
            "natural",
            "explanations",
            "corrections",
            "followUpQuestion",
            "suggestedReplies",
            "conversationTitle",
            "updatedContext"
        ],
        properties: [
            "fixed": GeminiSchemaProperty(
                type: "string",
                description: "The grammatically corrected sentence."
            ),
            "natural": GeminiSchemaProperty(
                type: "string",
                description: "A natural conversational version and alternative ways to say the user's sentence."
            ),
            "explanations": GeminiSchemaProperty(
                type: "array",
                description: "Explanations of grammar corrections AND suggestions of alternative words/phrases to express the user's sentence (e.g. suggesting 'Hi' or 'Hey' for 'Hello'). Always include at least one item.",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "text": GeminiSchemaProperty(
                            type: "string",
                            description: "A simple explanation of a correction or a suggested alternative way to say the sentence."
                        ),
                        "explanation_noted": GeminiSchemaProperty(
                            type: "string",
                            description: "The suggested alternative word/phrase or grammar keyword to highlight."
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
            ),
            "followUpQuestion": GeminiSchemaProperty(
                type: "string",
                description: "A natural English follow-up question to continue the conversation."
            ),
            "suggestedReplies": GeminiSchemaProperty(
                type: "array",
                description: "2 to 3 natural English replies the user can use to answer the follow-up question.",
                items: GeminiSchemaProperty(type: "string")
            ),
            "conversationTitle": GeminiSchemaProperty(
                type: "string",
                description: "A short 3 to 6 word title summarizing the conversation topic."
            ),
            "updatedContext": GeminiSchemaProperty(
                type: "string",
                description: "A concise 1 to 3 sentence rolling summary of the entire conversation so far."
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

private extension AINextWordSuggestionResponse {

    static func decodeFromAIContent(_ content: String) throws -> AINextWordSuggestionResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = AICorrectionResponse.strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder()
            .decode(AINextWordSuggestionResponse.self, from: jsonData)
    }
}

struct TypingSuggestionItem: Identifiable, Equatable {
    let text: String
    let isAI: Bool

    var id: String { "\(isAI ? "ai" : "local")-\(text.lowercased())" }
}

enum LocalNextWordSuggester {

    private static let textChecker = UITextChecker()

    private static let phraseContinuations: [String: [String]] = [
        "i": ["am", "think", "want to", "usually", "would like to", "have"],
        "i'm": ["doing well", "going to", "not sure", "happy to", "working on"],
        "i am": ["doing well", "going to", "looking for", "interested in", "happy to"],
        "i want": ["to go", "to learn", "to practice", "to try", "to know"],
        "i like": ["to", "playing", "watching", "reading", "listening to"],
        "i think": ["it is", "that", "we should", "it's a good idea"],
        "i have": ["been", "a lot of", "to go", "never tried"],
        "i went": ["to the", "there", "with my friends", "yesterday"],
        "i feel": ["really good", "a bit tired", "excited about", "happy"],
        "my": ["favorite", "friend", "family", "work", "weekend"],
        "we": ["can", "should", "went to", "usually", "are going to"],
        "you": ["are", "can", "know", "think", "have time"],
        "it": ["is", "was really", "makes me", "sounds great", "depends on"],
        "it's": ["really good", "a bit", "pretty nice", "so fun", "important to"],
        "how": ["are you", "is it going", "about you", "do you", "was your day"],
        "what": ["about you", "do you think", "are you doing", "kind of", "is your favorite"],
        "where": ["are you", "did you go", "do you live", "should we"],
        "when": ["i have time", "did you", "are we", "i was"],
        "why": ["do you", "did you", "not", "is it"],
        "thank": ["you", "you so much", "you for asking"],
        "thanks": ["for asking", "a lot", "so much", "for your help"],
        "yes": ["i do", "i would love to", "that sounds great", "of course"],
        "no": ["i haven't", "not really", "thank you", "i don't think so"],
        "in": ["the morning", "my free time", "my opinion", "the future", "general"],
        "on": ["the weekend", "my way", "time", "monday"],
        "at": ["home", "work", "the moment", "night", "school"],
        "to": ["be honest", "go to", "learn more", "hang out", "see you"],
        "for": ["example", "me", "a long time", "lunch", "dinner"],
        "with": ["my friends", "my family", "you", "each other"],
        "because": ["it is", "i want to", "i really like", "it helps me"],
        "usually": ["i go", "spend time", "wake up", "eat"],
        "today": ["i went", "was really", "i am going to", "i feel"]
    ]

    static func suggest(
        for input: String,
        suggestedReplies: [String] = [],
        savedWords: Set<String> = [],
        limit: Int = 6
    ) -> [TypingSuggestionItem] {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let endsWithWhitespace = input.last?.isWhitespace == true
        let tokens = input
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }

        guard let lastRawToken = tokens.last else {
            return []
        }

        let cleanLastToken = lastRawToken
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()

        let cleanLastTwoTokens: String? = tokens.count >= 2
            ? tokens.suffix(2)
                .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
                .joined(separator: " ")
            : nil

        var results: [String] = []

        // 1. Extract continuations from AI suggestedReplies if they match what the user is typing
        let trimmedInputLower = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for reply in suggestedReplies {
            let replyTrimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let replyLower = replyTrimmed.lowercased()

            if replyLower.hasPrefix(trimmedInputLower), replyTrimmed.count > trimmedInputLower.count {
                let remainder = String(replyTrimmed.dropFirst(trimmedInputLower.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let nextWords = remainder
                    .split(whereSeparator: { $0.isWhitespace })
                    .prefix(3)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .punctuationCharacters)
                if !nextWords.isEmpty {
                    results.append(nextWords)
                }
            }
        }

        // 2. If user is typing after a space OR already typed a complete word in our phrase map, suggest next words
        if let twoWordKey = cleanLastTwoTokens,
           let matches = phraseContinuations[twoWordKey] {
            results.append(contentsOf: matches)
        }

        if let oneWordMatches = phraseContinuations[cleanLastToken] {
            results.append(contentsOf: oneWordMatches)
        }

        // 3. If user is in the middle of typing a word (no trailing space), also offer word completions
        if !endsWithWhitespace && cleanLastToken.count >= 2 {
            // Check saved vocabulary words first
            let vocabMatches = savedWords
                .filter { $0.hasPrefix(cleanLastToken) && $0 != cleanLastToken }
                .sorted()
                .prefix(2)
            results.append(contentsOf: vocabMatches)

            // Check UITextChecker completions
            let nsWord = cleanLastToken as NSString
            let range = NSRange(location: 0, length: nsWord.length)
            if let completions = textChecker.completions(
                forPartialWordRange: range,
                in: cleanLastToken,
                language: "en_US"
            ) {
                for word in completions.prefix(4) where word.lowercased() != cleanLastToken {
                    results.append(word)
                }
            }
        }

        // 4. Fallback common connectors if still few results
        let fallbackWords = ["and", "because", "with my", "to the", "really", "very"]
        for word in fallbackWords where word != cleanLastToken {
            results.append(word)
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        var uniqueItems: [TypingSuggestionItem] = []

        for candidate in results {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cleaned.lowercased()
            guard !cleaned.isEmpty,
                  key != cleanLastToken,
                  !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            uniqueItems.append(TypingSuggestionItem(text: cleaned, isAI: false))
            if uniqueItems.count >= limit {
                break
            }
        }

        return uniqueItems
    }

    static func apply(suggestion: String, to currentInput: String) -> String {
        let cleanSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSuggestion.isEmpty else { return currentInput }

        let endsWithWhitespace = currentInput.last?.isWhitespace == true

        if endsWithWhitespace {
            return currentInput + cleanSuggestion + " "
        }

        // Check if the suggestion completes the last partial word (e.g. "I wan" + "want to" -> "I want to ")
        let parts = currentInput.split(whereSeparator: { $0.isWhitespace })
        guard let lastWordSlice = parts.last else {
            return cleanSuggestion + " "
        }

        let lastWord = String(lastWordSlice)
        let lastWordLower = lastWord.lowercased()
        let suggestionLower = cleanSuggestion.lowercased()

        // Also check if the user already typed the first word of a multi-word AI suggestion (e.g. "I want" + "want to go")
        let suggestionFirstWord = suggestionLower.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""

        if (suggestionLower.hasPrefix(lastWordLower) && lastWordLower.count >= 2) || suggestionFirstWord == lastWordLower {
            if let range = currentInput.range(of: lastWord, options: [.backwards]) {
                let prefix = String(currentInput[..<range.lowerBound])
                // Preserve capitalization if the user capitalized the first word
                let formattedSuggestion: String
                if lastWord.first?.isUppercase == true, let firstChar = cleanSuggestion.first {
                    formattedSuggestion = firstChar.uppercased() + cleanSuggestion.dropFirst()
                } else {
                    formattedSuggestion = cleanSuggestion
                }
                return prefix + formattedSuggestion + " "
            }
        }

        return currentInput + " " + cleanSuggestion + " "
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

