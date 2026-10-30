//
//  SituationAIService.swift
//  English Corrector
//

import Foundation

protocol SituationAskAIProvider {
    var name: String { get }

    func askHowToSay(
        question: String,
        tonePreference: String,
        recentHistory: [String]
    ) async throws -> AISituationAskResponse
}

final class SituationAIService {

    private let provider: SituationAskAIProvider

    init(provider: SituationAskAIProvider = GroqSituationAIProvider()) {
        self.provider = provider
    }

    func askHowToSay(
        question: String,
        tonePreference: String = "Tự động",
        recentHistory: [String] = []
    ) async throws -> AISituationAskResponse {
        try await provider.askHowToSay(
            question: question,
            tonePreference: tonePreference,
            recentHistory: recentHistory
        )
    }
}

extension AIModelOption {

    func makeSituationProvider() -> SituationAskAIProvider {
        switch self {
        case .groqGPTOSS20B, .groqGPTOSS120B:
            return GroqSituationAIProvider(model: modelID)
        case .geminiFlash:
            return GeminiSituationAIProvider(model: modelID)
        }
    }
}

struct SituationAskPrompt {

    let system: String
    let user: String

    init(question: String, tonePreference: String, recentHistory: [String] = []) {
        system = """
        You are an expert English communication coach helping Vietnamese users know exactly what to say in English in specific real-life or workplace situations.

        Given the user's question or situational description (in Vietnamese or English), provide:
        - "situationTitle": A concise Vietnamese title (3 to 7 words) summarizing this situation/question.
        - "situationAdvice": A brief, friendly explanation or cultural/communication tip in Vietnamese (1 to 3 sentences) about how native speakers handle this situation.
        - "expressions": 3 to 5 natural English expressions/sentences tailored to the situation. Each item must include:
          1. "english": The exact English sentence or phrase to say.
          2. "tone": Short Vietnamese tone label (e.g. "Tự nhiên & Phổ biến", "Trang trọng & Lịch sự", "Thân mật / Bạn bè", "Khéo léo / Tinh tế", "Ngắn gọn").
          3. "vietnameseNuance": Clear Vietnamese explanation of the meaning, nuance, and when/with whom to use this expression.
          4. "exampleExchange": A short 2-line mini dialogue or likely response in English showing how it works in context (e.g. "A: ... — B: ...").
        - "followUpQuestions": 2 to 3 helpful follow-up questions in Vietnamese that the user might want to ask next to explore the situation deeper (e.g. "Nếu đối phương từ chối thì đáp lại sao?", "Cách viết qua email trang trọng hơn?", "Nếu nói với sếp thì nên đổi thế nào?").
        - "practiceScenario": A ready-to-play conversation scenario so the user can practice this exact situation with the AI Coach:
          1. "title": Short English topic title (3 to 6 words)
          2. "contextDescription": 1 to 2 sentences in English instructing the AI Coach to roleplay this situation with the user
          3. "starterQuestion": An opening English line/question from the other person in this situation that invites the user to respond using one of the suggested expressions
          4. "sampleReplies": 2 to 3 natural English replies taken or adapted from the suggested expressions
        """

        let historySection: String
        if recentHistory.isEmpty {
            historySection = ""
        } else {
            historySection = """

            Recent Q&A history in this session:
            \(recentHistory.joined(separator: "\n"))
            """
        }

        let toneLine = (tonePreference.isEmpty || tonePreference == "Tự động")
            ? "Tự động (cung cấp đa dạng sắc thái từ tự nhiên, lịch sự đến thân mật)"
            : tonePreference

        user = """
        Preferred context/tone: \(toneLine)\(historySection)

        User's question / situation:
        \(question)
        """
    }
}

final class GeminiSituationAIProvider: SituationAskAIProvider {

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

    func askHowToSay(
        question: String,
        tonePreference: String,
        recentHistory: [String]
    ) async throws -> AISituationAskResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GEMINI_API_KEY"
            )
        }

        let prompt = SituationAskPrompt(
            question: question,
            tonePreference: tonePreference,
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

        return try AISituationAskResponse.decodeFromAIContent(content)
    }

    private static let responseSchema = GeminiSchema(
        type: "object",
        required: [
            "situationTitle",
            "situationAdvice",
            "expressions",
            "followUpQuestions",
            "practiceScenario"
        ],
        properties: [
            "situationTitle": GeminiSchemaProperty(
                type: "string",
                description: "Short Vietnamese title summarizing the situation."
            ),
            "situationAdvice": GeminiSchemaProperty(
                type: "string",
                description: "Concise Vietnamese explanation and communication tip for this situation."
            ),
            "expressions": GeminiSchemaProperty(
                type: "array",
                description: "3 to 5 natural English expressions for this situation.",
                items: GeminiSchemaProperty(
                    type: "object",
                    properties: [
                        "english": GeminiSchemaProperty(
                            type: "string",
                            description: "Natural English sentence or phrase."
                        ),
                        "tone": GeminiSchemaProperty(
                            type: "string",
                            description: "Vietnamese tone label such as 'Tự nhiên & Phổ biến', 'Trang trọng & Lịch sự', 'Thân mật / Bạn bè'."
                        ),
                        "vietnameseNuance": GeminiSchemaProperty(
                            type: "string",
                            description: "Vietnamese explanation of meaning and when to use it."
                        ),
                        "exampleExchange": GeminiSchemaProperty(
                            type: "string",
                            description: "Short example mini-dialogue in English."
                        )
                    ],
                    required: ["english", "tone", "vietnameseNuance", "exampleExchange"]
                )
            ),
            "followUpQuestions": GeminiSchemaProperty(
                type: "array",
                description: "2 to 3 suggested follow-up questions in Vietnamese.",
                items: GeminiSchemaProperty(type: "string")
            ),
            "practiceScenario": GeminiSchemaProperty(
                type: "object",
                properties: [
                    "title": GeminiSchemaProperty(
                        type: "string",
                        description: "Short 3 to 6 word English topic title."
                    ),
                    "contextDescription": GeminiSchemaProperty(
                        type: "string",
                        description: "1 to 2 sentence English roleplay context description."
                    ),
                    "starterQuestion": GeminiSchemaProperty(
                        type: "string",
                        description: "Opening English line from the coach/partner in the scenario."
                    ),
                    "sampleReplies": GeminiSchemaProperty(
                        type: "array",
                        items: GeminiSchemaProperty(type: "string")
                    )
                ],
                required: ["title", "contextDescription", "starterQuestion", "sampleReplies"]
            )
        ]
    )
}

final class GroqSituationAIProvider: SituationAskAIProvider {

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

    func askHowToSay(
        question: String,
        tonePreference: String,
        recentHistory: [String]
    ) async throws -> AISituationAskResponse {

        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(
                provider: name,
                keyName: "GROQ_API_KEY"
            )
        }

        let prompt = SituationAskPrompt(
            question: question,
            tonePreference: tonePreference,
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
            temperature: 0.25
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

        return try AISituationAskResponse.decodeFromAIContent(content)
    }

    private static let jsonInstruction = """
    Return ONLY valid JSON, without Markdown code fences or extra text.

    JSON shape:
    {
      "situationTitle": "Từ chối khéo lời mời đi ăn",
      "situationAdvice": "Khi từ chối lời mời của đồng nghiệp hoặc bạn bè, người bản xứ thường cảm ơn trước, đưa lý do ngắn gọn và hẹn dịp khác ("rain check") để giữ sự thân thiện.",
      "expressions": [
        {
          "english": "I'd love to, but I already have plans tonight. Can I take a rain check?",
          "tone": "Tự nhiên & Phổ biến",
          "vietnameseNuance": "Cách từ chối rất tự nhiên và lịch sự với đồng nghiệp, cụm 'take a rain check' nghĩa là hẹn dịp khác nhé.",
          "exampleExchange": "A: Want to grab dinner after work? — B: I'd love to, but I already have plans tonight. Can I take a rain check?"
        },
        {
          "english": "Thanks for inviting me! Unfortunately, I have to head home early today, maybe next time?",
          "tone": "Trang trọng & Lịch sự",
          "vietnameseNuance": "Phù hợp khi nói với sếp hoặc đồng nghiệp chưa quá thân.",
          "exampleExchange": "A: We're going out for team drinks, join us! — B: Thanks for inviting me! Unfortunately, I have to head home early today, maybe next time?"
        },
        {
          "english": "I'm gonna pass tonight, I'm totally beat. Let's go next week though!",
          "tone": "Thân mật / Bạn bè",
          "vietnameseNuance": "Dùng với bạn thân hoặc đồng nghiệp thân thiết ('beat' = rất mệt).",
          "exampleExchange": "A: Tacos tonight? — B: I'm gonna pass tonight, I'm totally beat. Let's go next week though!"
        }
      ],
      "followUpQuestions": [
        "Nếu người đó cứ nài nỉ thêm thì từ chối dứt khoát sao cho không mất lòng?",
        "Cách từ chối lời mời qua tin nhắn Slack/Teams ngắn gọn?",
        "Nếu muốn nhận lời nhưng đến trễ 30 phút thì nói thế nào?"
      ],
      "practiceScenario": {
        "title": "Politely Declining an Invitation",
        "contextDescription": "Roleplay a casual office conversation where a coworker invites the user to dinner after work and the user politely declines.",
        "starterQuestion": "Hey! A few of us are heading to that new Italian place after work today. Do you want to join us?",
        "sampleReplies": [
          "I'd love to, but I already have plans tonight. Can I take a rain check?",
          "Thanks for inviting me! Unfortunately, I have to head home early today, maybe next time?",
          "I'm gonna pass tonight, I'm pretty tired. Let's go next week though!"
        ]
      }
    }
    """
}

private extension AISituationAskResponse {

    static func decodeFromAIContent(_ content: String) throws -> AISituationAskResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = strippedMarkdownFence(from: trimmedContent)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder()
            .decode(AISituationAskResponse.self, from: jsonData)
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
