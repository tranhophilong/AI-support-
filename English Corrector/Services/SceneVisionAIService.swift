//
//  SceneVisionAIService.swift
//  English Corrector
//

import Foundation
import UIKit

// MARK: - Gemini Vision Multimodal Types

struct GeminiVisionContentRequest: Codable {
    let systemInstruction: GeminiVisionContent?
    let contents: [GeminiVisionContent]
    let generationConfig: GeminiVisionGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

struct GeminiVisionContent: Codable {
    let parts: [GeminiVisionPart]
}

struct GeminiVisionPart: Codable {
    let text: String?
    let inlineData: GeminiVisionInlineData?

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(inlineData: GeminiVisionInlineData) {
        self.text = nil
        self.inlineData = inlineData
    }
}

struct GeminiVisionInlineData: Codable {
    let mimeType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

struct GeminiVisionGenerationConfig: Codable {
    let responseMimeType: String?
    let responseSchema: GeminiSchema?
}

// MARK: - Scene Vision AI Service

final class SceneVisionAIService {

    static let shared = SceneVisionAIService()

    private let session: URLSession
    private let groqVisionModel: String

    init(
        groqVisionModel: String = "qwen/qwen3.8-27b",
        session: URLSession = .shared
    ) {
        self.groqVisionModel = groqVisionModel
        self.session = session
    }

    /// Analyzes a photo using Groq Vision (qwen/qwen3.8-27b) with automatic fallback to Gemini.
    func describeScene(
        imageData: Data,
        userPrompt: String? = nil
    ) async throws -> AISceneDescriptionResponse {

        // 1. Try Groq Vision first
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            do {
                return try await describeSceneWithGroq(
                    imageData: imageData,
                    userPrompt: userPrompt,
                    apiKey: groqKey
                )
            } catch {
                print("DEBUG: Groq Vision request failed: \(error). Falling back to Gemini Vision...")
            }
        }

        // 2. Fallback to Gemini Vision
        let geminiKey = APIKeyStore.geminiAPIKey
        guard !geminiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "Groq", keyName: "GROQ_API_KEY")
        }

        return try await describeSceneWithGemini(
            imageData: imageData,
            userPrompt: userPrompt,
            apiKey: geminiKey
        )
    }

    /// Identifies a specific object located at (xPercent, yPercent) in the image when user long-presses.
    func identifyObjectAtPoint(
        imageData: Data,
        xPercent: Double,
        yPercent: Double
    ) async throws -> AISceneObjectVocabularyItem {
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            do {
                return try await identifyObjectAtPointWithGroq(
                    imageData: imageData,
                    xPercent: xPercent,
                    yPercent: yPercent,
                    apiKey: groqKey
                )
            } catch {
                print("DEBUG: Groq point identification failed: \(error). Falling back to Gemini...")
            }
        }

        let geminiKey = APIKeyStore.geminiAPIKey
        guard !geminiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider: "Groq", keyName: "GROQ_API_KEY")
        }

        return try await identifyObjectAtPointWithGemini(
            imageData: imageData,
            xPercent: xPercent,
            yPercent: yPercent,
            apiKey: geminiKey
        )
    }

    // MARK: - Groq Vision Implementation (qwen/qwen3.8-27b)

    private func describeSceneWithGroq(
        imageData: Data,
        userPrompt: String?,
        apiKey: String
    ) async throws -> AISceneDescriptionResponse {

        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()
        let dataUri = "data:image/jpeg;base64,\(base64String)"

        let systemInstruction = """
        You are an expert English language coach analyzing real-world camera photos to help Vietnamese learners discover English vocabulary, natural descriptive sentences, and conversational expressions.

        Respond ONLY with a valid JSON object strictly matching this schema:
        {
          "sceneOverview": "A natural, engaging 2-3 sentence English description of the scene.",
          "sceneVietnameseTranslation": "Accurate, natural Vietnamese translation of the scene overview.",
          "objectsDetected": [
            {
              "word": "English noun or noun phrase",
              "point": [x, y],
              "box_2d": [ymin, xmin, ymax, xmax],
              "phonetic": "/IPA pronunciation/",
              "partOfSpeech": "Noun/Verb/etc",
              "vietnameseMeaning": "Clear Vietnamese meaning",
              "exampleInContext": "Short practical English sentence using this word in the context of the photo."
            }
          ],
          "situationalConversationalPhrases": [
            "Conversational English phrase 1",
            "Conversational English phrase 2"
          ],
          "adviceOrCulturalNote": "Brief tip in Vietnamese about vocabulary nuance or cultural communication in this setting."
        }
        CRITICAL ACCURACY REQUIREMENT FOR OBJECT TARGETING:
        For every object detected, you MUST pinpoint its exact location:
        - "point": [x, y] is the EXACT physical center of that object on the image, where x is percentage (0-100) from left to right, and y is percentage (0-100) from top to bottom.
        - "box_2d": [ymin, xmin, ymax, xmax] is the bounding box coordinates on a 0-1000 scale.
        Be extremely precise so the leader pointer points directly at the object.
        """

        let promptText: String
        if let userPrompt, !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = """
            User focus or question: "\(userPrompt)"
            Please analyze this image, address the user focus, identify 4 to 8 key objects with phonetic IPA and Vietnamese meanings, and provide situational phrases.
            """
        } else {
            promptText = "Please analyze this image, describe the scene in English with Vietnamese translation, identify 4 to 8 key objects with IPA and Vietnamese meanings, and provide practical conversational phrases."
        }

        let requestPayload: [String: Any] = [
            "model": groqVisionModel,
            "messages": [
                [
                    "role": "system",
                    "content": systemInstruction
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": promptText
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": dataUri
                            ]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0.2
        ]

        guard let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("EnglishCorrector/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestPayload)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8)
            throw AIServiceError.requestFailed(
                provider: "Groq",
                statusCode: httpResponse.statusCode,
                message: errorMsg
            )
        }

        let responseBody = try JSONDecoder().decode(GroqChatCompletionResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: "Groq", message: error.message)
        }

        guard let rawText = responseBody.choices?.first?.message.content else {
            throw AIServiceError.emptyResponse(provider: "Groq")
        }

        let cleaned = Self.strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(AISceneDescriptionResponse.self, from: jsonData)
    }

    private func identifyObjectAtPointWithGroq(
        imageData: Data,
        xPercent: Double,
        yPercent: Double,
        apiKey: String
    ) async throws -> AISceneObjectVocabularyItem {
        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()
        let dataUri = "data:image/jpeg;base64,\(base64String)"

        let roundedX = Int(round(xPercent))
        let roundedY = Int(round(yPercent))

        let systemInstruction = """
        You are an expert English vocabulary tutor and computer vision analyst.
        The user has touched a specific location on the photo: horizontal position \(roundedX)% (from left: 0% to right: 100%) and vertical position \(roundedY)% (from top: 0% to bottom: 100%).
        Identify the exact physical object, item, or distinctive element that the user is pointing at or touching at (\(roundedX)%, \(roundedY)%).

        Respond ONLY with a valid JSON object strictly matching this schema:
        {
          "word": "English name of this object (e.g., 'ceramic mug', 'laptop trackpad', 'houseplant', 'vintage watch')",
          "point": [\(roundedX), \(roundedY)],
          "box_2d": [ymin, xmin, ymax, xmax],
          "phonetic": "/IPA pronunciation/",
          "partOfSpeech": "Noun",
          "vietnameseMeaning": "Clear, natural Vietnamese translation of this object",
          "exampleInContext": "A natural, helpful English sentence describing this object in this photo."
        }
        """

        let promptText = "What is the specific object at coordinate (\(roundedX)%, \(roundedY)%) in this image? Provide its English vocabulary, IPA, Vietnamese meaning, and context sentence."

        let requestPayload: [String: Any] = [
            "model": groqVisionModel,
            "messages": [
                [
                    "role": "system",
                    "content": systemInstruction
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": promptText
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": dataUri
                            ]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0.1
        ]

        guard let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestPayload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Groq error"
            throw AIServiceError.requestFailed(
                provider: "Groq",
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500,
                message: errorMsg
            )
        }

        let responseBody = try JSONDecoder().decode(GroqChatCompletionResponse.self, from: data)
        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: "Groq", message: error.message)
        }

        guard let rawText = responseBody.choices?.first?.message.content else {
            throw AIServiceError.emptyResponse(provider: "Groq")
        }

        let cleaned = Self.strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        var item = try JSONDecoder().decode(AISceneObjectVocabularyItem.self, from: jsonData)
        if item.xPercent == nil || item.yPercent == nil {
            item = AISceneObjectVocabularyItem(
                word: item.word,
                phonetic: item.phonetic,
                partOfSpeech: item.partOfSpeech,
                vietnameseMeaning: item.vietnameseMeaning,
                exampleInContext: item.exampleInContext,
                xPercent: xPercent,
                yPercent: yPercent,
                box2d: item.box2d
            )
        }
        return item
    }

    // MARK: - Gemini Vision Fallback (gemini-2.5-flash)

    private func describeSceneWithGemini(
        imageData: Data,
        userPrompt: String?,
        apiKey: String
    ) async throws -> AISceneDescriptionResponse {

        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()

        let systemInstruction = """
        You are an expert English language coach analyzing real-world camera photos to help Vietnamese learners discover English vocabulary, natural descriptive sentences, and conversational expressions.

        Always respond with valid JSON matching the required schema:
        - "sceneOverview": A natural, engaging 2-3 sentence English description of what is in the scene (what is happening, the environment, key elements).
        - "sceneVietnameseTranslation": Accurate, natural Vietnamese translation of the scene overview.
        - "objectsDetected": 4 to 8 prominent objects, items, or notable elements detected in the photo. Each object must have:
          * "word": The English noun or noun phrase (e.g., "laptop stand", "espresso cup", "potted succulent", "traffic light").
          * "box_2d": [ymin, xmin, ymax, xmax] on a 0-1000 scale pinpointing the exact location of the object.
          * "xPercent": Approximate horizontal center location of the object in percentage from 0 (left) to 100 (right).
          * "yPercent": Approximate vertical center location of the object in percentage from 0 (top) to 100 (bottom).
          * "phonetic": Accurate IPA pronunciation (e.g., "/ˈlæp.tɒp stænd/").
          * "partOfSpeech": Part of speech (e.g., "Noun", "Compound Noun").
          * "vietnameseMeaning": Clear, accurate Vietnamese meaning (e.g., "giá đỡ máy tính xách tay").
          * "exampleInContext": A short, practical English sentence using this word in the context of the photo.
        - "situationalConversationalPhrases": 2 to 4 natural conversational English phrases or questions someone might say in this situation/setting.
        - "adviceOrCulturalNote": A helpful brief tip in Vietnamese about vocabulary nuance or cultural communication in this setting.
        """

        let promptText: String
        if let userPrompt, !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = """
            User's specific focus or question regarding this image: "\(userPrompt)"
            Please analyze the image with special attention to the user's question, while still providing the comprehensive learning breakdown (scene overview, detected objects vocabulary, and conversational phrases).
            """
        } else {
            promptText = "Please analyze this image, describe the scene, identify key objects for an English learner, and provide practical conversational phrases."
        }

        let body = GeminiVisionContentRequest(
            systemInstruction: GeminiVisionContent(
                parts: [GeminiVisionPart(text: systemInstruction)]
            ),
            contents: [
                GeminiVisionContent(
                    parts: [
                        GeminiVisionPart(text: promptText),
                        GeminiVisionPart(
                            inlineData: GeminiVisionInlineData(
                                mimeType: "image/jpeg",
                                data: base64String
                            )
                        )
                    ]
                )
            ],
            generationConfig: GeminiVisionGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Self.responseSchema
            )
        )

        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed(
                provider: "Gemini",
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }

        let responseBody = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)

        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: "Gemini", message: error.message)
        }

        guard let rawText = responseBody.candidates?.first?.content?.parts.first?.text else {
            throw AIServiceError.emptyResponse(provider: "Gemini")
        }

        let cleaned = Self.strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(AISceneDescriptionResponse.self, from: jsonData)
    }

    private func identifyObjectAtPointWithGemini(
        imageData: Data,
        xPercent: Double,
        yPercent: Double,
        apiKey: String
    ) async throws -> AISceneObjectVocabularyItem {
        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()

        let roundedX = Int(round(xPercent))
        let roundedY = Int(round(yPercent))

        let systemInstruction = """
        You are an expert English vocabulary tutor.
        The user has touched a specific location on the photo: horizontal position \(roundedX)% (0-100 from left to right) and vertical position \(roundedY)% (0-100 from top to bottom).
        Identify the exact physical object, item, or distinctive feature that the user touched at (\(roundedX)%, \(roundedY)%).

        Respond ONLY with valid JSON strictly matching this schema:
        {
          "word": "English noun or noun phrase",
          "point": [\(roundedX), \(roundedY)],
          "box_2d": [ymin, xmin, ymax, xmax],
          "phonetic": "/IPA pronunciation/",
          "partOfSpeech": "Noun",
          "vietnameseMeaning": "Clear, natural Vietnamese meaning",
          "exampleInContext": "Helpful English sentence using this word in the photo context."
        }
        """

        let promptText = "Identify the specific object at (\(roundedX)%, \(roundedY)%) in this photo."

        let body = GeminiVisionContentRequest(
            systemInstruction: GeminiVisionContent(
                parts: [GeminiVisionPart(text: systemInstruction)]
            ),
            contents: [
                GeminiVisionContent(
                    parts: [
                        GeminiVisionPart(text: promptText),
                        GeminiVisionPart(
                            inlineData: GeminiVisionInlineData(
                                mimeType: "image/jpeg",
                                data: base64String
                            )
                        )
                    ]
                )
            ],
            generationConfig: GeminiVisionGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: nil
            )
        )

        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw AIServiceError.requestFailed(
                provider: "Gemini",
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }

        let responseBody = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        if let error = responseBody.error {
            throw AIServiceError.apiError(provider: "Gemini", message: error.message)
        }

        guard let rawText = responseBody.candidates?.first?.content?.parts.first?.text else {
            throw AIServiceError.emptyResponse(provider: "Gemini")
        }

        let cleaned = Self.strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        var item = try JSONDecoder().decode(AISceneObjectVocabularyItem.self, from: jsonData)
        if item.xPercent == nil || item.yPercent == nil {
            item = AISceneObjectVocabularyItem(
                word: item.word,
                phonetic: item.phonetic,
                partOfSpeech: item.partOfSpeech,
                vietnameseMeaning: item.vietnameseMeaning,
                exampleInContext: item.exampleInContext,
                xPercent: xPercent,
                yPercent: yPercent,
                box2d: item.box2d
            )
        }
        return item
    }

    private static func strippedMarkdownFence(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)

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

    // MARK: - Image Optimization

    private func optimizeImageForVision(imageData: Data) -> Data {
        guard let originalImage = UIImage(data: imageData) else {
            return imageData
        }

        let maxDimension: CGFloat = 1024
        let size = originalImage.size

        var targetSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let ratio = size.width / size.height
            if ratio > 1 {
                targetSize = CGSize(width: maxDimension, height: maxDimension / ratio)
            } else {
                targetSize = CGSize(width: maxDimension * ratio, height: maxDimension)
            }
        }

        // Groq requires at least 32px
        targetSize.width = max(targetSize.width, 32)
        targetSize.height = max(targetSize.height, 32)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            originalImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.8) ?? imageData
    }

    // MARK: - Schema

    private static let responseSchema = GeminiSchema(
        type: "object",
        required: [
            "sceneOverview",
            "sceneVietnameseTranslation",
            "objectsDetected",
            "situationalConversationalPhrases"
        ],
        properties: [
            "sceneOverview": GeminiSchemaProperty(
                type: "string",
                description: "Natural 2-3 sentence English description of the scene."
            ),
            "sceneVietnameseTranslation": GeminiSchemaProperty(
                type: "string",
                description: "Vietnamese translation of the scene overview."
            ),
            "objectsDetected": GeminiSchemaProperty(
                type: "array",
                description: "Key objects detected in the photo for English vocabulary learning.",
                items: GeminiSchemaProperty(
                    type: "object",
                    items: nil,
                    properties: [
                        "word": GeminiSchemaProperty(type: "string", description: "English noun or noun phrase."),
                        "xPercent": GeminiSchemaProperty(type: "number", description: "Horizontal position 0-100."),
                        "yPercent": GeminiSchemaProperty(type: "number", description: "Vertical position 0-100."),
                        "phonetic": GeminiSchemaProperty(type: "string", description: "IPA pronunciation."),
                        "partOfSpeech": GeminiSchemaProperty(type: "string", description: "Part of speech."),
                        "vietnameseMeaning": GeminiSchemaProperty(type: "string", description: "Vietnamese meaning."),
                        "exampleInContext": GeminiSchemaProperty(type: "string", description: "Short practical sentence.")
                    ],
                    required: ["word", "phonetic", "partOfSpeech", "vietnameseMeaning", "exampleInContext"]
                )
            ),
            "situationalConversationalPhrases": GeminiSchemaProperty(
                type: "array",
                description: "Practical conversational phrases.",
                items: GeminiSchemaProperty(type: "string")
            ),
            "adviceOrCulturalNote": GeminiSchemaProperty(
                type: "string",
                description: "Helpful tip in Vietnamese about vocabulary or culture."
            )
        ]
    )
}
