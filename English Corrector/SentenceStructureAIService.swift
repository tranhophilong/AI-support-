//
//  SentenceStructureAIService.swift
//  English Corrector
//

import Foundation

protocol SentenceStructureAIProvider {
    var name: String { get }

    func analyzeSentence(
        sentence: String
    ) async throws -> AISentenceStructureResponse

    func askFollowUp(
        sentence: String,
        analysisSummary: String,
        question: String,
        previousQAs: [AISentenceStructureFollowUpQA]
    ) async throws -> AISentenceStructureFollowUpResponse
}

final class SentenceStructureAIService {

    private let provider: SentenceStructureAIProvider

    init(provider: SentenceStructureAIProvider = GroqSentenceStructureAIProvider()) {
        self.provider = provider
    }

    func analyzeSentence(
        sentence: String
    ) async throws -> AISentenceStructureResponse {
        try await provider.analyzeSentence(sentence: sentence)
    }

    func askFollowUp(
        sentence: String,
        analysisSummary: String,
        question: String,
        previousQAs: [AISentenceStructureFollowUpQA] = []
    ) async throws -> AISentenceStructureFollowUpResponse {
        try await provider.askFollowUp(
            sentence: sentence,
            analysisSummary: analysisSummary,
            question: question,
            previousQAs: previousQAs
        )
    }
}

extension AIModelOption {

    func makeSentenceStructureProvider() -> SentenceStructureAIProvider {
        switch self {
        case .groqGPTOSS20B, .groqGPTOSS120B:
            return GroqSentenceStructureAIProvider(model: modelID)
        case .geminiFlash:
            return GeminiSentenceStructureAIProvider(model: modelID)
        }
    }
}

struct SentenceStructurePrompt {

    let system: String
    let user: String

    init(sentence: String) {
        system = """
        You are an expert English syntax and grammar teacher for Vietnamese learners.
        Given an English sentence, break down its grammatical structure thoroughly and clearly in Vietnamese.

        Provide:
        - "originalSentence": The input sentence.
        - "correctedSentence": If the input sentence has any grammar mistakes, provide the corrected English sentence; if it is already grammatically correct, return an empty string "".
        - "vietnameseTranslation": Natural, accurate Vietnamese translation of the sentence.
        - "tense": The main tense(s) used in the sentence (e.g. "Present Perfect (Hiện tại hoàn thành)", "Past Simple + Past Continuous").
        - "sentenceType": The structural type of sentence in Vietnamese & English (e.g. "Câu phức (Complex Sentence)", "Câu điều kiện loại 2", "Câu đơn mở rộng").
        - "generalFormula": Concise overall grammatical formula of the sentence (e.g. "Adv + S + have/has + V3/ed + O + [Relative Clause: who/that + V]").
        - "components": Break the sentence down in order from left to right into logical syntactic chunks (`S`, `V`, `O`, `C`, `Adv`, `Clause`, `Conj`, `Prep`). Each item must include:
          1. "segment": Exact phrase/chunk from the sentence
          2. "symbol": Short grammatical tag ONLY from: "S", "V", "O", "C", "Adv", "Clause", "Conj", "Prep"
          3. "roleName": Vietnamese + English role name (e.g. "Chủ ngữ (Subject)", "Động từ chính (Main Verb)", "Tân ngữ (Object)", "Mệnh đề quan hệ (Relative Clause)", "Trạng ngữ chỉ thời gian (Adverbial)")
          4. "grammaticalForm": Specific grammatical form (e.g. "Noun Phrase (Cụm danh từ)", "Modal Verb + Bare Infinitive", "Participle Phrase (Cụm phân từ)")
          5. "explanation": Detailed, easy-to-understand Vietnamese explanation of how this chunk is constructed and its role in the sentence.
        - "grammarPatterns": 2 to 4 notable grammar structures, collocations, or idioms used in the sentence. Each item includes:
          1. "pattern": Formula or structure name (e.g. "not only ... but also ...", "have difficulty + (in) + V-ing")
          2. "explanation": Clear Vietnamese explanation of how to use this structure and common mistakes to avoid
          3. "example": Another natural English example sentence applying the same structure.
        - "variations": 2 to 3 ways to rewrite the sentence with equivalent meaning. Each item includes:
          1. "style": Vietnamese label (e.g. "Tự nhiên / Giao tiếp", "Trang trọng / Học thuật", "Rút gọn mệnh đề")
          2. "sentence": The rewritten English sentence
          3. "note": Brief Vietnamese note explaining what grammatical change was made.
        - "suggestedQuestions": 2 to 3 insightful follow-up grammar questions in Vietnamese about this specific sentence that the learner might wonder about (e.g. "Tại sao ở đây dùng V-ing mà không dùng to V?", "Có thể rút gọn mệnh đề quan hệ trong câu này như thế nào?").
        """

        user = """
        Analyze the detailed grammatical structure of this English sentence:
        \(sentence)
        """
    }
}

struct SentenceStructureFollowUpPrompt {

    let system: String
    let user: String

    init(
        sentence: String,
        analysisSummary: String,
        question: String,
        previousQAs: [AISentenceStructureFollowUpQA]
    ) {
        system = """
        You are an expert English grammar teacher answering a Vietnamese learner's follow-up question about a specific English sentence's structure.
        Provide:
        - "answer": Clear, thorough, and friendly explanation in Vietnamese directly addressing the user's grammar question about the sentence.
        - "examples": 1 to 2 short English example sentences illustrating your explanation (with brief Vietnamese translation in parentheses if helpful).
        - "nextQuestions": 2 follow-up grammar questions in Vietnamese the learner might want to ask next.
        """

        let historyText: String
        if previousQAs.isEmpty {
            historyText = ""
        } else {
            let formatted = previousQAs.suffix(5).map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            historyText = "\nPrevious Q&A:\n\(formatted)\n"
        }

        user = """
        Target sentence: "\(sentence)"
        Sentence formula & summary: \(analysisSummary)\(historyText)

        Learner's question:
        \(question)
        """
    }
}

final class GeminiSentenceStructureAIProvider: SentenceStructureAIProvider {

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

    func analyzeSentence(sentence: String) async throws -> AISentenceStructureResponse {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: name, keyName: "GEMINI_API_KEY")
        }

        let prompt = SentenceStructurePrompt(sentence: sentence)

        let body = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: prompt.system)]),
            contents: [GeminiContent(parts: [GeminiPart(text: prompt.user)])],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Self.analysisSchema
            )
        )

        let content = try await sendRequest(body: body)
        return try AISentenceStructureResponse.decodeFromAIContent(content)
    }

    func askFollowUp(
        sentence: String,
        analysisSummary: String,
        question: String,
        previousQAs: [AISentenceStructureFollowUpQA]
    ) async throws -> AISentenceStructureFollowUpResponse {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: name, keyName: "GEMINI_API_KEY")
        }

        let prompt = SentenceStructureFollowUpPrompt(
            sentence: sentence,
            analysisSummary: analysisSummary,
            question: question,
            previousQAs: previousQAs
        )

        let body = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: prompt.system)]),
            contents: [GeminiContent(parts: [GeminiPart(text: prompt.user)])],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Self.followUpSchema
            )
        )

        let content = try await sendRequest(body: body)
        return try AISentenceStructureFollowUpResponse.decodeFromAIContent(content)
    }

    private func sendRequest(body: GeminiGenerateContentRequest) async throws -> String {
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

        let responseBody = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: name, message: error.message)
        }

        guard let content = responseBody.candidates?.first?.content?.parts.first?.text else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return content
    }

    private static let analysisSchema = GeminiSchema(
        type: "object",
        required: [
            "originalSentence",
            "correctedSentence",
            "vietnameseTranslation",
            "tense",
            "sentenceType",
            "generalFormula",
            "components",
            "grammarPatterns",
            "variations",
            "suggestedQuestions"
        ],
        properties: [
            "originalSentence": GeminiSchemaProperty(type: "string"),
            "correctedSentence": GeminiSchemaProperty(type: "string"),
            "vietnameseTranslation": GeminiSchemaProperty(type: "string"),
            "tense": GeminiSchemaProperty(type: "string"),
            "sentenceType": GeminiSchemaProperty(type: "string"),
            "generalFormula": GeminiSchemaProperty(type: "string"),
            "components": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "segment": GeminiSchemaProperty(type: "string"),
                        "symbol": GeminiSchemaProperty(type: "string"),
                        "roleName": GeminiSchemaProperty(type: "string"),
                        "grammaticalForm": GeminiSchemaProperty(type: "string"),
                        "explanation": GeminiSchemaProperty(type: "string")
                    ],
                    required: ["segment", "symbol", "roleName", "grammaticalForm", "explanation"]
                )
            ),
            "grammarPatterns": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "pattern": GeminiSchemaProperty(type: "string"),
                        "explanation": GeminiSchemaProperty(type: "string"),
                        "example": GeminiSchemaProperty(type: "string")
                    ],
                    required: ["pattern", "explanation", "example"]
                )
            ),
            "variations": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "style": GeminiSchemaProperty(type: "string"),
                        "sentence": GeminiSchemaProperty(type: "string"),
                        "note": GeminiSchemaProperty(type: "string")
                    ],
                    required: ["style", "sentence", "note"]
                )
            ),
            "suggestedQuestions": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(type: "string")
            )
        ]
    )

    private static let followUpSchema = GeminiSchema(
        type: "object",
        required: ["answer", "examples", "nextQuestions"],
        properties: [
            "answer": GeminiSchemaProperty(type: "string"),
            "examples": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(type: "string")
            ),
            "nextQuestions": GeminiSchemaProperty(
                type: "array",
                items: GeminiSchemaProperty(type: "string")
            )
        ]
    )
}

final class GroqSentenceStructureAIProvider: SentenceStructureAIProvider {

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

    func analyzeSentence(sentence: String) async throws -> AISentenceStructureResponse {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: name, keyName: "GROQ_API_KEY")
        }

        let prompt = SentenceStructurePrompt(sentence: sentence)

        let body = GroqChatCompletionRequest(
            model: model,
            messages: [
                GroqMessage(
                    role: "system",
                    content: prompt.system + "\n\n" + Self.analysisJsonInstruction
                ),
                GroqMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.2
        )

        let content = try await sendRequest(body: body)
        return try AISentenceStructureResponse.decodeFromAIContent(content)
    }

    func askFollowUp(
        sentence: String,
        analysisSummary: String,
        question: String,
        previousQAs: [AISentenceStructureFollowUpQA]
    ) async throws -> AISentenceStructureFollowUpResponse {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: name, keyName: "GROQ_API_KEY")
        }

        let prompt = SentenceStructureFollowUpPrompt(
            sentence: sentence,
            analysisSummary: analysisSummary,
            question: question,
            previousQAs: previousQAs
        )

        let body = GroqChatCompletionRequest(
            model: model,
            messages: [
                GroqMessage(
                    role: "system",
                    content: prompt.system + "\n\n" + Self.followUpJsonInstruction
                ),
                GroqMessage(role: "user", content: prompt.user)
            ],
            temperature: 0.25
        )

        let content = try await sendRequest(body: body)
        return try AISentenceStructureFollowUpResponse.decodeFromAIContent(content)
    }

    private func sendRequest(body: GroqChatCompletionRequest) async throws -> String {
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

        let responseBody = try JSONDecoder().decode(GroqChatCompletionResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: name, message: error.message)
        }

        guard let content = responseBody.choices?.first?.message.content else {
            throw AIServiceError.emptyResponse(provider: name)
        }

        return content
    }

    private static let analysisJsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "originalSentence": "The book that you recommended yesterday has completely changed my perspective on life.",
      "correctedSentence": "",
      "vietnameseTranslation": "Cuốn sách mà bạn giới thiệu hôm qua đã thay đổi hoàn toàn góc nhìn của tôi về cuộc sống.",
      "tense": "Present Perfect (Hiện tại hoàn thành) + Past Simple (Quá khứ đơn)",
      "sentenceType": "Câu phức có mệnh đề quan hệ (Complex Sentence)",
      "generalFormula": "S [Noun Phrase + Relative Clause] + has/have + Adv + V3/ed + O + Prep Phrase",
      "components": [
        {
          "segment": "The book",
          "symbol": "S",
          "roleName": "Chủ ngữ chính (Main Subject)",
          "grammaticalForm": "Noun Phrase (Cụm danh từ)",
          "explanation": "Danh từ chính làm chủ ngữ của toàn câu, được xác định bởi mạo từ 'The'."
        },
        {
          "segment": "that you recommended yesterday",
          "symbol": "Clause",
          "roleName": "Mệnh đề quan hệ (Relative Clause)",
          "grammaticalForm": "that + S + V2/ed + Adv",
          "explanation": "Mệnh đề phụ bổ nghĩa cho 'The book', giải thích rõ đó là cuốn sách nào."
        },
        {
          "segment": "has completely changed",
          "symbol": "V",
          "roleName": "Cụm động từ chính (Main Verb)",
          "grammaticalForm": "has + Adverb + V3/ed (Hiện tại hoàn thành)",
          "explanation": "Diễn tả hành động đã xảy ra và để lại kết quả ở hiện tại; trạng từ 'completely' đứng giữa trợ động từ 'has' và phân từ hai 'changed' để nhấn mạnh."
        },
        {
          "segment": "my perspective on life",
          "symbol": "O",
          "roleName": "Tân ngữ (Object)",
          "grammaticalForm": "Noun Phrase + Prepositional Phrase",
          "explanation": "Đối tượng chịu tác động của động từ 'changed', mở rộng bằng cụm giới từ 'on life' (về cuộc sống)."
        }
      ],
      "grammarPatterns": [
        {
          "pattern": "has/have + Adverb + V3/ed",
          "explanation": "Trong thì hiện tại hoàn thành, trạng từ chỉ mức độ hoặc cách thức (completely, already, recientemente) thường đứng ngay sau have/has và trước V3/ed.",
          "example": "She hascompletely mastered the new workflow."
        },
        {
          "pattern": "perspective on + Noun / V-ing",
          "explanation": "Cụm danh từ đi với giới từ 'on' mang nghĩa quan điểm, góc nhìn về một vấn đề gì đó.",
          "example": "Traveling abroad gave me a fresh perspective on different cultures."
        }
      ],
      "variations": [
        {
          "style": "Rút gọn đại từ quan hệ",
          "sentence": "The book you recommended yesterday has completely changed my perspective on life.",
          "note": "Lược bỏ đại từ quan hệ 'that' vì nó đóng vai trò làm tân ngữ cho động từ 'recommended'."
        },
        {
          "style": "Tự nhiên / Giao tiếp",
          "sentence": "That book you told me about yesterday totally changed how I look at life.",
          "note": "Dùng 'told me about' và 'how I look at life' nghe gần gũi hơn trong hội thoại hàng ngày."
        }
      ],
      "suggestedQuestions": [
        "Khi nào thì được phép lược bỏ đại từ quan hệ 'that' hoặc 'which'?",
        "Tại sao câu này chia thì hiện tại hoàn thành ('has changed') mặc dù có từ 'yesterday'?"
      ]
    }
    """

    private static let followUpJsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "answer": "Lời giải thích chi tiết bằng tiếng Việt...",
      "examples": [
        "Example sentence 1 (Nghĩa tiếng Việt)",
        "Example sentence 2 (Nghĩa tiếng Việt)"
      ],
      "nextQuestions": [
        "Câu hỏi gợi ý tiếp theo 1?",
        "Câu hỏi gợi ý tiếp theo 2?"
      ]
    }
    """
}

private extension AISentenceStructureResponse {

    static func decodeFromAIContent(_ content: String) throws -> AISentenceStructureResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(AISentenceStructureResponse.self, from: jsonData)
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

private extension AISentenceStructureFollowUpResponse {

    static func decodeFromAIContent(_ content: String) throws -> AISentenceStructureFollowUpResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = AISentenceStructureResponse.strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(AISentenceStructureFollowUpResponse.self, from: jsonData)
    }
}
