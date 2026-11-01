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

    // Multi-tier Fallback Vision Models Chain
    // 1. Groq Qwen (27B) -> 2. Groq Llama 3.2 (11B) -> 3. Groq Llama 3.2 (90B)
    private let groqVisionModels: [String] = [
        "qwen/qwen3.8-27b",
        "meta-llama/llama-3.2-11b-vision-preview",
        "meta-llama/llama-3.2-90b-vision-preview"
    ]

    // 4. Gemini 2.5 Flash -> 5. Gemini 2.0 Flash -> 6. Gemini 1.5 Flash
    private let geminiVisionModels: [String] = [
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-1.5-flash"
    ]

    init(
        session: URLSession = .shared
    ) {
        self.session = session
    }

    /// Analyzes a photo using resilient 5-tier AI chain:
    /// Groq (Qwen -> Llama 3.2) -> Gemini (2.5 -> 2.0 -> 1.5) -> Apple Vision (Offline).
    func describeScene(
        imageData: Data,
        userPrompt: String? = nil,
        autoDetectObjects: Bool = false
    ) async throws -> AISceneDescriptionResponse {

        // 0. Pre-detect objects on-device with Apple Vision Neural Engine ONLY IF autoDetectObjects is requested
        var preDetectedObjects: [IOSDetectedObjectSummary] = []
        if autoDetectObjects, let uiImg = UIImage(data: imageData) {
            preDetectedObjects = IOSObjectDetectorService.shared.scanAllObjectsInImage(from: uiImg)
        }

        // 1. Try Groq Vision Models Chain
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            for gModel in groqVisionModels {
                do {
                    return try await describeSceneWithGroq(
                        imageData: imageData,
                        userPrompt: userPrompt,
                        preDetected: preDetectedObjects,
                        autoDetectObjects: autoDetectObjects,
                        model: gModel,
                        apiKey: groqKey
                    )
                } catch {
                    print("DEBUG: Groq Vision (\(gModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // 2. Try Gemini Vision Models Chain
        let geminiKey = APIKeyStore.geminiAPIKey
        if !geminiKey.isEmpty {
            for gmModel in geminiVisionModels {
                do {
                    return try await describeSceneWithGemini(
                        imageData: imageData,
                        userPrompt: userPrompt,
                        preDetected: preDetectedObjects,
                        autoDetectObjects: autoDetectObjects,
                        modelName: gmModel,
                        apiKey: geminiKey
                    )
                } catch {
                    print("DEBUG: Gemini Vision (\(gmModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // 3. Fallback to on-device detected summaries (Offline)
        let offlineItems = preDetectedObjects.map { s in
            let entry = EverydayVocabularyDictionary.lookup(identifier: s.word)
            return AISceneObjectVocabularyItem(
                word: entry?.word ?? s.word.capitalized,
                phonetic: entry?.phonetic ?? "",
                partOfSpeech: entry?.partOfSpeech ?? "Noun",
                vietnameseMeaning: entry?.vietnamese ?? "Vật thể trong ảnh",
                exampleInContext: "Nhận diện tức thì qua Apple Neural Engine [Offline]",
                xPercent: s.xPercent,
                yPercent: s.yPercent,
                box2d: s.box2d,
                isOffline: true
            )
        }
        return AISceneDescriptionResponse(
            sceneOverview: "A photo captured by your device.",
            sceneVietnameseTranslation: "Ảnh được chụp từ thiết bị của bạn (Chế độ nhận diện ngoại tuyến).",
            objectsDetected: offlineItems,
            situationalConversationalPhrases: [
                "What can you see in this photo?",
                "Can you describe this scene in English?"
            ],
            adviceOrCulturalNote: "Hệ thống đang hoạt động ở chế độ ngoại tuyến qua Apple Neural Engine."
        )
    }

    /// On-demand detection of all items in an image using resilient 5-tier AI chain.
    func detectAllObjectsInImage(from image: UIImage) async throws -> [AISceneObjectVocabularyItem] {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            return []
        }

        // 1. Apple Vision on-device scan
        let summaries = IOSObjectDetectorService.shared.scanAllObjectsInImage(from: image)

        // 2. Try Groq Vision Chain
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            for gModel in groqVisionModels {
                do {
                    let response = try await describeSceneWithGroq(
                        imageData: jpegData,
                        userPrompt: "Detect and identify the prominent physical items in this photo for an English vocabulary learner.",
                        preDetected: summaries,
                        autoDetectObjects: true,
                        model: gModel,
                        apiKey: groqKey
                    )
                    if !response.objectsDetected.isEmpty {
                        return response.objectsDetected
                    }
                } catch {
                    print("DEBUG: Groq detectAllObjectsInImage (\(gModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // 3. Try Gemini Vision Chain
        let geminiKey = APIKeyStore.geminiAPIKey
        if !geminiKey.isEmpty {
            for gmModel in geminiVisionModels {
                do {
                    let response = try await describeSceneWithGemini(
                        imageData: jpegData,
                        userPrompt: "Detect and identify the prominent physical items in this photo for an English vocabulary learner.",
                        preDetected: summaries,
                        autoDetectObjects: true,
                        modelName: gmModel,
                        apiKey: geminiKey
                    )
                    if !response.objectsDetected.isEmpty {
                        return response.objectsDetected
                    }
                } catch {
                    print("DEBUG: Gemini detectAllObjectsInImage (\(gmModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // 4. Fallback to on-device detected summaries with EverydayVocabularyDictionary (Offline)
        let filtered = summaries.filter { summary in
            let w = summary.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !w.isEmpty && w != "vật thể đã chọn"
        }
        return filtered.map { summary in
            let entry = EverydayVocabularyDictionary.lookup(identifier: summary.word)
            let word = entry?.word ?? (summary.word.lowercased() == "item" ? "Object" : summary.word.capitalized)
            let phonetic = entry?.phonetic ?? ""
            let vietnamese = entry?.vietnamese ?? "Vật thể trong ảnh (Offline)"
            let pos = entry?.partOfSpeech ?? "Noun"
            return AISceneObjectVocabularyItem(
                word: word,
                phonetic: phonetic,
                partOfSpeech: pos,
                vietnameseMeaning: vietnamese,
                exampleInContext: "Nhận diện tức thì qua Apple Neural Engine [Offline]",
                xPercent: summary.xPercent,
                yPercent: summary.yPercent,
                box2d: summary.box2d,
                isOffline: true
            )
        }
    }

    /// Analyzes an already detected and cropped object with 5-tier AI chain.
    func identifyObject(from detected: IOSDetectedObjectResult) async throws -> AISceneObjectVocabularyItem {
        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            for gModel in groqVisionModels {
                do {
                    return try await identifyCroppedObjectWithGroq(
                        detected: detected,
                        model: gModel,
                        apiKey: groqKey
                    )
                } catch {
                    print("DEBUG: Groq cropped object analysis (\(gModel)) failed: \(error). Trying next model...")
                }
            }
        }

        let geminiKey = APIKeyStore.geminiAPIKey
        if !geminiKey.isEmpty {
            for gmModel in geminiVisionModels {
                do {
                    return try await identifyCroppedObjectWithGemini(
                        detected: detected,
                        modelName: gmModel,
                        apiKey: geminiKey
                    )
                } catch {
                    print("DEBUG: Gemini cropped object analysis (\(gmModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // 3. High-Precision On-Device Offline Fallback (Apple Neural Engine + EverydayVocabularyDictionary)
        let rawLabel = detected.onDeviceLabels.first ?? "item"
        let entry = EverydayVocabularyDictionary.lookup(identifier: rawLabel)
        let resolvedWord = entry?.word ?? (rawLabel == "item" ? "Object" : rawLabel.capitalized)
        let resolvedPhonetic = entry?.phonetic ?? ""
        let resolvedVietnamese = entry?.vietnamese ?? "Vật thể nhận diện trên thiết bị"
        let resolvedPos = entry?.partOfSpeech ?? "Noun"

        return AISceneObjectVocabularyItem(
            word: resolvedWord,
            phonetic: resolvedPhonetic,
            partOfSpeech: resolvedPos,
            vietnameseMeaning: resolvedVietnamese,
            exampleInContext: "Nhận diện tức thì qua Apple Neural Engine [Offline]",
            xPercent: Double(detected.refinedCenterPercent.x),
            yPercent: Double(detected.refinedCenterPercent.y),
            box2d: detected.box2dGrounding,
            isOffline: true
        )
    }

    /// Identifies a specific object located at (xPercent, yPercent) in the image using iOS on-device Vision detection + multimodal AI.
    func identifyObjectWithIOSDetection(
        fullImage: UIImage,
        xPercent: Double,
        yPercent: Double
    ) async throws -> AISceneObjectVocabularyItem {
        // 1. Detect & Crop with Apple Vision on-device
        let detected = try await IOSObjectDetectorService.shared.detectAndCropObject(
            from: fullImage,
            atXPercent: xPercent,
            yPercent: yPercent
        )

        // 2. Multimodal AI Analysis with Groq (fallback to Gemini)
        return try await identifyObject(from: detected)
    }

    /// Backwards compatible method: delegates to iOS Vision detection if UIImage can be parsed from data.
    func identifyObjectAtPoint(
        imageData: Data,
        xPercent: Double,
        yPercent: Double
    ) async throws -> AISceneObjectVocabularyItem {
        if let uiImage = UIImage(data: imageData) {
            return try await identifyObjectWithIOSDetection(
                fullImage: uiImage,
                xPercent: xPercent,
                yPercent: yPercent
            )
        }

        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            for gModel in groqVisionModels {
                do {
                    return try await identifyObjectAtPointWithGroq(
                        imageData: imageData,
                        xPercent: xPercent,
                        yPercent: yPercent,
                        model: gModel,
                        apiKey: groqKey
                    )
                } catch {
                    print("DEBUG: Groq point identification (\(gModel)) failed: \(error). Trying next model...")
                }
            }
        }

        let geminiKey = APIKeyStore.geminiAPIKey
        if !geminiKey.isEmpty {
            for gmModel in geminiVisionModels {
                do {
                    return try await identifyObjectAtPointWithGemini(
                        imageData: imageData,
                        xPercent: xPercent,
                        yPercent: yPercent,
                        modelName: gmModel,
                        apiKey: geminiKey
                    )
                } catch {
                    print("DEBUG: Gemini point identification (\(gmModel)) failed: \(error). Trying next model...")
                }
            }
        }

        // On-Device Fallback
        return AISceneObjectVocabularyItem(
            word: "Object",
            phonetic: "",
            partOfSpeech: "Noun",
            vietnameseMeaning: "Vật thể trong ảnh",
            exampleInContext: "Nhận diện tức thì qua Apple Neural Engine [Offline]",
            xPercent: xPercent,
            yPercent: yPercent,
            box2d: nil,
            isOffline: true
        )
    }

    // MARK: - Groq Vision Implementation

    private func describeSceneWithGroq(
        imageData: Data,
        userPrompt: String?,
        preDetected: [IOSDetectedObjectSummary] = [],
        autoDetectObjects: Bool = false,
        model: String = "qwen/qwen3.8-27b",
        apiKey: String
    ) async throws -> AISceneDescriptionResponse {

        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()
        let dataUri = "data:image/jpeg;base64,\(base64String)"

        let preDetectedBlock = (autoDetectObjects && !preDetected.isEmpty) ? """

        The device Neural Engine identified \(preDetected.count) key visual regions of interest in this image:
        \(preDetected.map { "- Region at coordinates (\(Int($0.xPercent))%, \(Int($0.yPercent))%), bbox: \($0.box2d)" }.joined(separator: "\n"))
        Please inspect what is physically at each of these coordinates, identify the exact English object name, and include them in your objectsDetected array.
        """ : ""

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
        CRITICAL REQUIREMENT:
        \(autoDetectObjects
          ? "Identify 3 to 6 distinct, specific physical objects clearly visible in the image (prioritizing individual items such as cups, pens, phones, books, watches, utensils, or accessories over large broad scene containers or whole rooms), pinpointing their exact center point [x, y] (0-100 scale) and box_2d."
          : "Keep 'objectsDetected' as an empty array [] since the user will manually trigger object detection on demand. Focus on providing a vivid sceneOverview and situational conversational phrases.")
        """ + preDetectedBlock

        let promptText: String
        if let userPrompt, !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = """
            User focus or question: "\(userPrompt)"
            Please analyze this image, address the user focus, and provide situational phrases. \(autoDetectObjects ? "Also identify key objects." : "Leave objectsDetected empty [].")
            """
        } else {
            promptText = autoDetectObjects
                ? "Please analyze this image, describe the scene in English with Vietnamese translation, identify key objects with IPA and Vietnamese meanings, and provide practical conversational phrases."
                : "Please analyze this image, describe the scene in English with Vietnamese translation, and provide practical conversational phrases. Keep objectsDetected as []."
        }

        let requestPayload: [String: Any] = [
            "model": model,
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
        model: String = "qwen/qwen3.8-27b",
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
            "model": model,
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

    private func prepareCleanCutoutOrCroppedData(from detected: IOSDetectedObjectResult) -> Data {
        if let cutout = detected.cutoutImage {
            let size = cutout.size
            if size.width > 20 && size.height > 20 {
                let renderer = UIGraphicsImageRenderer(size: size)
                let composited = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    cutout.draw(in: CGRect(origin: .zero, size: size))
                }
                if let data = composited.jpegData(compressionQuality: 0.85) {
                    return optimizeImageForVision(imageData: data)
                }
            }
        }
        return optimizeImageForVision(imageData: detected.croppedImageData)
    }

    private func identifyCroppedObjectWithGroq(
        detected: IOSDetectedObjectResult,
        model: String = "qwen/qwen3.8-27b",
        apiKey: String
    ) async throws -> AISceneObjectVocabularyItem {
        let processedData = prepareCleanCutoutOrCroppedData(from: detected)
        let base64String = processedData.base64EncodedString()
        let dataUri = "data:image/jpeg;base64,\(base64String)"

        let hintsText = detected.onDeviceLabels.isEmpty
            ? ""
            : "Possible visual hint: \(detected.onDeviceLabels.joined(separator: ", ")). Note: prioritize the visible features in the cropped image."

        let systemInstruction = """
        You are an expert English vocabulary tutor and computer vision analyst.
        The user isolated a specific physical object from their photo (shown in this cropped image).
        \(hintsText)

        PRECISION TARGETING:
        - Identify ONLY the specific item targeted at the center of this crop (including small everyday objects like a pen, mug, wristwatch, mouse, eyeglasses, phone, accessory, cutlery, bottle, etc.).
        - If surrounding items, desk surfaces, or background scenes are partially visible around it, IGNORE all surrounding context and identify strictly the specific targeted object.
        - Be specific, grounded, and accurate. Do not guess obscure or unrelated items.
        Respond ONLY with a valid JSON object strictly matching this schema:
        {
          "word": "Specific, accurate English name of this object",
          "phonetic": "/IPA pronunciation/",
          "partOfSpeech": "Noun",
          "vietnameseMeaning": "Clear, natural Vietnamese translation of this object",
          "exampleInContext": "A natural, helpful English sentence describing this object in everyday context."
        }
        """

        let promptText = "Identify the main object in this cropped photo. Provide its English vocabulary, IPA pronunciation, Vietnamese meaning, and an example sentence."

        let requestPayload: [String: Any] = [
            "model": model,
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

        let parsed = try JSONDecoder().decode(AISceneObjectVocabularyItem.self, from: jsonData)
        let trimmedWord = parsed.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty,
              trimmedWord.lowercased() != "unknown",
              trimmedWord.lowercased() != "none",
              trimmedWord.lowercased() != "object",
              trimmedWord.lowercased() != "item",
              trimmedWord.lowercased() != "vật thể đã chọn" else {
            throw AIServiceError.apiError(provider: "Groq", message: "Can't detect item")
        }

        return AISceneObjectVocabularyItem(
            word: parsed.word,
            phonetic: parsed.phonetic,
            partOfSpeech: parsed.partOfSpeech.isEmpty ? "Noun" : parsed.partOfSpeech,
            vietnameseMeaning: parsed.vietnameseMeaning,
            exampleInContext: parsed.exampleInContext,
            xPercent: Double(detected.refinedCenterPercent.x),
            yPercent: Double(detected.refinedCenterPercent.y),
            box2d: detected.box2dGrounding
        )
    }

    // MARK: - Gemini Vision Fallback

    private func describeSceneWithGemini(
        imageData: Data,
        userPrompt: String?,
        preDetected: [IOSDetectedObjectSummary] = [],
        autoDetectObjects: Bool = false,
        modelName: String = "gemini-2.5-flash",
        apiKey: String
    ) async throws -> AISceneDescriptionResponse {

        let processedData = optimizeImageForVision(imageData: imageData)
        let base64String = processedData.base64EncodedString()

        let preDetectedBlock = (autoDetectObjects && !preDetected.isEmpty) ? """

        The device Neural Engine identified \(preDetected.count) key visual regions of interest in this image:
        \(preDetected.map { "- Region at coordinates (\(Int($0.xPercent))%, \(Int($0.yPercent))%), bbox: \($0.box2d)" }.joined(separator: "\n"))
        Please inspect what is physically at each of these coordinates, identify the exact English object name, and include them in your objectsDetected array.
        """ : ""

        let systemInstruction = """
        You are an expert English language coach analyzing real-world camera photos to help Vietnamese learners discover English vocabulary, natural descriptive sentences, and conversational expressions.

        Always respond with valid JSON matching the required schema:
        - "sceneOverview": A natural, engaging 2-3 sentence English description of what is in the scene (what is happening, the environment, key elements).
        - "sceneVietnameseTranslation": Accurate, natural Vietnamese translation of the scene overview.
        - "objectsDetected": \(autoDetectObjects ? "3 to 6 prominent objects, items, or notable elements detected in the photo." : "Keep as empty array [] by default since the user will manually trigger object detection.")
        - "situationalConversationalPhrases": 2 to 4 natural conversational English phrases or questions someone might say in this situation/setting.
        - "adviceOrCulturalNote": A helpful brief tip in Vietnamese about vocabulary nuance or cultural communication in this setting.
        """ + preDetectedBlock

        let promptText: String
        if let userPrompt, !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = """
            User's specific focus or question regarding this image: "\(userPrompt)"
            Please analyze the image with special attention to the user's question, while still providing the scene overview and conversational phrases. \(autoDetectObjects ? "Identify key objects." : "Keep objectsDetected as [].")
            """
        } else {
            promptText = autoDetectObjects
                ? "Please analyze this image, describe the scene, identify key objects for an English learner, and provide practical conversational phrases."
                : "Please analyze this image, describe the scene, and provide practical conversational phrases. Keep objectsDetected as []."
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
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
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
        modelName: String = "gemini-2.5-flash",
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
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
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

    private func identifyCroppedObjectWithGemini(
        detected: IOSDetectedObjectResult,
        modelName: String = "gemini-2.5-flash",
        apiKey: String
    ) async throws -> AISceneObjectVocabularyItem {
        let processedData = prepareCleanCutoutOrCroppedData(from: detected)
        let base64String = processedData.base64EncodedString()

        let hintsText = detected.onDeviceLabels.isEmpty
            ? ""
            : "Possible visual hint: \(detected.onDeviceLabels.joined(separator: ", ")). Note: prioritize the visible features in the cropped image."

        let systemInstruction = """
        You are an expert English vocabulary tutor and computer vision analyst.
        The user isolated a specific physical object from their photo (shown in this cropped image).
        \(hintsText)

        PRECISION TARGETING:
        - Identify ONLY the specific item targeted at the center of this crop (including small everyday objects like a pen, mug, wristwatch, mouse, eyeglasses, phone, accessory, cutlery, bottle, etc.).
        - If surrounding items, desk surfaces, or background scenes are partially visible around it, IGNORE all surrounding context and identify strictly the specific targeted object.
        - Be specific, grounded, and accurate. Do not guess obscure or unrelated items.
        Respond ONLY with valid JSON strictly matching this schema:
        {
          "word": "Specific, accurate English noun or noun phrase",
          "phonetic": "/IPA pronunciation/",
          "partOfSpeech": "Noun",
          "vietnameseMeaning": "Clear, natural Vietnamese meaning",
          "exampleInContext": "Helpful English sentence using this word in everyday context."
        }
        """

        let promptText = "Identify the main object in this cropped photo. Provide its English vocabulary, IPA, Vietnamese meaning, and context sentence."

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
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
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

        let parsed = try JSONDecoder().decode(AISceneObjectVocabularyItem.self, from: jsonData)
        let trimmedWord = parsed.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty,
              trimmedWord.lowercased() != "unknown",
              trimmedWord.lowercased() != "none",
              trimmedWord.lowercased() != "object",
              trimmedWord.lowercased() != "item",
              trimmedWord.lowercased() != "vật thể đã chọn" else {
            throw AIServiceError.apiError(provider: "Gemini", message: "Can't detect item")
        }

        return AISceneObjectVocabularyItem(
            word: parsed.word,
            phonetic: parsed.phonetic,
            partOfSpeech: parsed.partOfSpeech.isEmpty ? "Noun" : parsed.partOfSpeech,
            vietnameseMeaning: parsed.vietnameseMeaning,
            exampleInContext: parsed.exampleInContext,
            xPercent: Double(detected.refinedCenterPercent.x),
            yPercent: Double(detected.refinedCenterPercent.y),
            box2d: detected.box2dGrounding
        )
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
