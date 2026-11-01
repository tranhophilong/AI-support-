//
//  EnglishNewsService.swift
//  English Corrector
//

import Foundation
import UIKit

// MARK: - News Categories

enum NewsCategory: String, CaseIterable, Identifiable, Codable {
    case top = "top"
    case sports = "sports"
    case tech = "tech"
    case world = "world"
    case business = "business"
    case science = "science"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Nóng nhất"
        case .sports: return "Thể thao"
        case .tech: return "Công nghệ & AI"
        case .world: return "Thế giới"
        case .business: return "Kinh doanh"
        case .science: return "Khoa học & Đời sống"
        }
    }

    var englishName: String {
        switch self {
        case .top: return "Top Headlines"
        case .sports: return "Sports"
        case .tech: return "Tech & AI"
        case .world: return "World News"
        case .business: return "Business"
        case .science: return "Science & Life"
        }
    }

    var iconName: String {
        switch self {
        case .top: return "flame.fill"
        case .sports: return "soccerball"
        case .tech: return "cpu.fill"
        case .world: return "globe.americas.fill"
        case .business: return "chart.line.uptrend.xyaxis"
        case .science: return "atom"
        }
    }

    var feedURLs: [String] {
        switch self {
        case .top:
            return ["https://feeds.bbci.co.uk/news/rss.xml"]
        case .sports:
            return [
                "https://feeds.bbci.co.uk/sport/rss.xml",
                "https://www.espn.com/espn/rss/news"
            ]
        case .tech:
            return [
                "https://techcrunch.com/feed/",
                "https://feeds.bbci.co.uk/news/technology/rss.xml"
            ]
        case .world:
            return ["https://feeds.bbci.co.uk/news/world/rss.xml"]
        case .business:
            return ["https://feeds.bbci.co.uk/news/business/rss.xml"]
        case .science:
            return ["https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"]
        }
    }
}

// MARK: - News Article Item

struct NewsArticleItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let link: String
    let description: String
    let pubDate: Date?
    let pubDateString: String
    let source: String
    let imageURL: String?
    let category: NewsCategory

    var timeAgoDisplay: String {
        guard let pubDate else { return pubDateString }
        let interval = Date().timeIntervalSince(pubDate)
        if interval < 60 {
            return "Vừa xong"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) phút trước"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) giờ trước"
        } else {
            let days = Int(interval / 86400)
            return "\(days) ngày trước"
        }
    }
}

// MARK: - AI Summary & Vocabulary Models

struct NewsKeyVocabularyItem: Identifiable, Hashable, Codable {
    var id: String { word }
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let vietnameseMeaning: String
    let contextExplanation: String
}

struct NewsAISummary: Codable, Equatable {
    let englishTakeaways: [String]
    let vietnameseTakeaways: [String]
    let cefrLevel: String
    let keyVocabulary: [NewsKeyVocabularyItem]
    let shortDiscussionPrompt: String?
}

// MARK: - English News Service

final class EnglishNewsService {
    static let shared = EnglishNewsService()

    private let session: URLSession
    private var memoryCache: [NewsCategory: (items: [NewsArticleItem], timestamp: Date)] = [:]
    private var articleContentCache: [String: [String]] = [:]
    private var summaryCache: [String: NewsAISummary] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch RSS Feeds

    func fetchArticles(
        for category: NewsCategory,
        forceRefresh: Bool = false
    ) async throws -> [NewsArticleItem] {
        if !forceRefresh,
           let cached = memoryCache[category],
           Date().timeIntervalSince(cached.timestamp) < 600 { // 10 mins cache
            return cached.items
        }

        var allItems: [NewsArticleItem] = []

        for feedURLString in category.feedURLs {
            guard let feedURL = URL(string: feedURLString) else { continue }

            var request = URLRequest(url: feedURL)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )

            do {
                let (data, response) = try await session.data(for: request)
                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    let sourceName: String = {
                        if feedURLString.contains("techcrunch") { return "TechCrunch" }
                        if feedURLString.contains("espn") { return "ESPN" }
                        if feedURLString.contains("bbci.co.uk/sport") { return "BBC Sport" }
                        return "BBC News"
                    }()
                    let parsedItems = parseRSS(data: data, sourceName: sourceName, category: category)
                    allItems.append(contentsOf: parsedItems)
                }
            } catch {
                // If one feed fails, continue with others
                continue
            }
        }

        // Deduplicate and sort by date descending
        var seenIDs = Set<String>()
        var uniqueItems: [NewsArticleItem] = []

        for item in allItems {
            if !seenIDs.contains(item.id) && !seenIDs.contains(item.title) {
                seenIDs.insert(item.id)
                seenIDs.insert(item.title)
                uniqueItems.append(item)
            }
        }

        uniqueItems.sort { ($0.pubDate ?? Date.distantPast) > ($1.pubDate ?? Date.distantPast) }

        if !uniqueItems.isEmpty {
            memoryCache[category] = (uniqueItems, Date())
        }

        return uniqueItems
    }

    // MARK: - Fetch & Clean Full Article Content

    func fetchArticleContent(for article: NewsArticleItem) async -> [String] {
        if let cached = articleContentCache[article.link], !cached.isEmpty {
            return cached
        }

        guard let url = URL(string: article.link) else {
            return fallbackParagraphs(for: article)
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode),
                  let htmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return fallbackParagraphs(for: article)
            }

            let extracted = extractCleanParagraphs(from: htmlString)
            if extracted.count >= 2 {
                articleContentCache[article.link] = extracted
                return extracted
            } else {
                return fallbackParagraphs(for: article)
            }
        } catch {
            return fallbackParagraphs(for: article)
        }
    }

    private func fallbackParagraphs(for article: NewsArticleItem) -> [String] {
        if !article.description.isEmpty {
            return [article.description]
        }
        return []
    }

    private func extractCleanParagraphs(from html: String) -> [String] {
        var contentHTML = html

        // 1. Narrow scope to the main article container
        let containerPatterns = [
            "<article[^>]*>(.*?)</article>",
            "<(div|main)[^>]*(class=\"[^\"]*(entry-content|article__body|story-body|article-body|post-content)[^\"]*\"|id=\"(main-content|maincontent)\")[^>]*>(.*?)</\\1>"
        ]

        for pat in containerPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: (html as NSString).length)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                let candidate = (html as NSString).substring(with: range)
                if candidate.contains("<p") {
                    contentHTML = candidate
                    break
                }
            }
        }

        var paragraphs: [String] = []

        // 2. Match standard <p>...</p> tags
        let pattern = "<p[^>]*>(.*?)</p>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let nsString = contentHTML as NSString
        let matches = regex.matches(in: contentHTML, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let pRange = match.range(at: 1)
            let pContent = nsString.substring(with: pRange)

            let cleaned = cleanHTML(pContent)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out junk, disclaimers, cookie notices, and very short lines
            if trimmed.count >= 35 && !isDisallowedContent(trimmed) {
                paragraphs.append(trimmed)
            }
        }

        return paragraphs
    }

    private func cleanHTML(_ raw: String) -> String {
        // Strip inner tags
        var cleaned = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )

        // Decode HTML entities
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&mdash;": " — ",
            "&ndash;": " – ",
            "&hellip;": "...",
            "&nbsp;": " ",
            "&#8217;": "'",
            "&#8216;": "'",
            "&#8220;": "\"",
            "&#8221;": "\"",
            "&#8212;": " — "
        ]

        for (entity, replacement) in entities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode any other decimal numeric entities &#NNN;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = cleaned as NSString
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                if let code = Int(ns.substring(with: match.range(at: 1))),
                   let scalar = UnicodeScalar(code) {
                    cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }

        // Clean extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDisallowedContent(_ text: String) -> Bool {
        let lower = text.lowercased()

        // Ignore photo credits, captions, disclaimers
        if lower.hasPrefix("image source") ||
           lower.hasPrefix("image caption") ||
           lower.hasPrefix("media caption") ||
           lower.hasPrefix("photo:") ||
           lower.hasPrefix("credit:") ||
           lower.hasPrefix("epa,") ||
           lower.hasPrefix("getty images") {
            return true
        }

        let forbidden = [
            "bbc homepage", "skip to content", "accessibility help", "cookie",
            "privacy policy", "terms of use", "copyright", "all rights reserved",
            "subscribe to", "advertisement", "sign up for", "follow us on",
            "download the app", "newsletter", "listen to the podcast",
            "share this story", "related topics", "more on this story", "click here to"
        ]
        return forbidden.contains { lower.contains($0) }
    }

    // MARK: - AI Summary & Key Vocabulary Generation

    func generateAISummary(
        title: String,
        content: String
    ) async throws -> NewsAISummary {
        let cacheKey = "\(title)-\(content.prefix(150))"
        if let cached = summaryCache[cacheKey] {
            return cached
        }

        let groqKey = APIKeyStore.groqAPIKey
        if !groqKey.isEmpty {
            do {
                let summary = try await generateAISummaryWithGroq(title: title, content: content, apiKey: groqKey)
                summaryCache[cacheKey] = summary
                return summary
            } catch {
                // Fallback to Gemini below
            }
        }

        let geminiKey = APIKeyStore.geminiAPIKey
        if !geminiKey.isEmpty {
            let summary = try await generateAISummaryWithGemini(title: title, content: content, apiKey: geminiKey)
            summaryCache[cacheKey] = summary
            return summary
        }

        // Offline mock fallback if no API keys
        return NewsAISummary(
            englishTakeaways: [
                "Key event reported in \(title).",
                "Important developments and background context.",
                "Potential implications for the industry and readers."
            ],
            vietnameseTakeaways: [
                "Sự kiện quan trọng được đưa tin trong tiêu đề.",
                "Các diễn biến chính và bối cảnh xung quanh.",
                "Ý nghĩa và tác động của tin tức đối với người quan tâm."
            ],
            cefrLevel: "B1 - Intermediate",
            keyVocabulary: [],
            shortDiscussionPrompt: "What do you think about this news story?"
        )
    }

    private func generateAISummaryWithGroq(
        title: String,
        content: String,
        apiKey: String
    ) async throws -> NewsAISummary {
        let systemPrompt = """
        You are an expert English language reading tutor. Analyze the following news article and produce a structured JSON summary strictly adhering to this schema:
        {
          "englishTakeaways": [
            "Concise takeaway point 1 in English",
            "Concise takeaway point 2 in English",
            "Concise takeaway point 3 in English"
          ],
          "vietnameseTakeaways": [
            "Điểm tóm tắt 1 bằng tiếng Việt",
            "Điểm tóm tắt 2 bằng tiếng Việt",
            "Điểm tóm tắt 3 bằng tiếng Việt"
          ],
          "cefrLevel": "B1 - Intermediate",
          "keyVocabulary": [
            {
              "word": "target word",
              "phonetic": "/IPA/",
              "partOfSpeech": "Noun/Verb/etc",
              "vietnameseMeaning": "Nghĩa tiếng Việt chuẩn",
              "contextExplanation": "How it is used in this article"
            }
          ],
          "shortDiscussionPrompt": "An engaging English question asking the learner's opinion on this news story."
        }
        Provide 3 to 5 key vocabulary words from the article that are useful for learners.
        """

        let prompt = """
        Article Title: "\(title)"
        Article Excerpt:
        \"\"\"
        \(content.prefix(2500))
        \"\"\"
        """

        let payload: [String: Any] = [
            "model": "openai/gpt-oss-120b",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2
        ]

        guard let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIServiceError.requestFailed(provider: "Groq", statusCode: http.statusCode, message: nil)
        }

        let respBody = try JSONDecoder().decode(GroqChatCompletionResponse.self, from: data)
        guard let rawText = respBody.choices?.first?.message.content else {
            throw AIServiceError.emptyResponse(provider: "Groq")
        }

        let cleaned = strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(NewsAISummary.self, from: jsonData)
    }

    private func generateAISummaryWithGemini(
        title: String,
        content: String,
        apiKey: String
    ) async throws -> NewsAISummary {
        let systemPrompt = """
        You are an expert English reading tutor. Analyze the following news article and output valid JSON:
        - "englishTakeaways": 3 concise bullet points in English summarizing key facts.
        - "vietnameseTakeaways": 3 corresponding bullet points in Vietnamese.
        - "cefrLevel": CEFR reading level (e.g., A2, B1, B2, C1).
        - "keyVocabulary": 3-5 useful words from the text with "word", "phonetic", "partOfSpeech", "vietnameseMeaning", "contextExplanation".
        - "shortDiscussionPrompt": An engaging reflection question in English.
        """

        let prompt = "Title: \(title)\n\nContent:\n\(content.prefix(2500))"

        let requestBody = GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: systemPrompt)]),
            contents: [GeminiContent(parts: [GeminiPart(text: prompt)])],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: GeminiSchema(
                    type: "object",
                    required: ["englishTakeaways", "vietnameseTakeaways", "cefrLevel", "keyVocabulary"],
                    properties: [
                        "englishTakeaways": GeminiSchemaProperty(type: "array", items: GeminiSchemaProperty(type: "string")),
                        "vietnameseTakeaways": GeminiSchemaProperty(type: "array", items: GeminiSchemaProperty(type: "string")),
                        "cefrLevel": GeminiSchemaProperty(type: "string"),
                        "shortDiscussionPrompt": GeminiSchemaProperty(type: "string"),
                        "keyVocabulary": GeminiSchemaProperty(
                            type: "array",
                            items: GeminiSchemaProperty(
                                type: "object",
                                properties: [
                                    "word": GeminiSchemaProperty(type: "string"),
                                    "phonetic": GeminiSchemaProperty(type: "string"),
                                    "partOfSpeech": GeminiSchemaProperty(type: "string"),
                                    "vietnameseMeaning": GeminiSchemaProperty(type: "string"),
                                    "contextExplanation": GeminiSchemaProperty(type: "string")
                                ],
                                required: ["word", "phonetic", "partOfSpeech", "vietnameseMeaning"]
                            )
                        )
                    ]
                )
            )
        )

        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=\(apiKey)"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIServiceError.requestFailed(provider: "Gemini", statusCode: http.statusCode, message: nil)
        }

        let respBody = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        guard let rawText = respBody.candidates?.first?.content?.parts.first?.text else {
            throw AIServiceError.emptyResponse(provider: "Gemini")
        }

        let cleaned = strippedMarkdownFence(from: rawText)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(NewsAISummary.self, from: jsonData)
    }

    private func strippedMarkdownFence(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() }
        if !lines.isEmpty && lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - RSS XML Parser

    private func parseRSS(data: Data, sourceName: String, category: NewsCategory) -> [NewsArticleItem] {
        let parser = RSSParser(data: data, sourceName: sourceName, category: category)
        return parser.parse()
    }
}

// MARK: - RSS Parser Delegate

private final class RSSParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let sourceName: String
    private let category: NewsCategory

    private var items: [NewsArticleItem] = []
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentImageURL: String? = nil
    private var isInsideItem = false

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "EEE, dd MMM yyyy HH:mm Z"
    ]

    init(data: Data, sourceName: String, category: NewsCategory) {
        self.parser = XMLParser(data: data)
        self.sourceName = sourceName
        self.category = category
        super.init()
        self.parser.delegate = self
    }

    func parse() -> [NewsArticleItem] {
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()

        if currentElement == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentImageURL = nil
        }

        if isInsideItem {
            // Check for image in attributes: <media:thumbnail url="..."> or <enclosure url="...">
            if currentElement == "media:thumbnail" || currentElement == "media:content" || currentElement == "enclosure" {
                if let url = attributeDict["url"], !url.isEmpty, currentImageURL == nil {
                    // Check if it's an image
                    let type = attributeDict["type"] ?? ""
                    if type.isEmpty || type.contains("image") || url.contains(".jpg") || url.contains(".png") || url.contains(".jpeg") {
                        currentImageURL = url
                    }
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }

        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description":
            currentDescription += string
        case "pubdate", "dc:date":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard isInsideItem else { return }
        if let string = String(data: CDATABlock, encoding: .utf8) {
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                currentLink += string
            case "description":
                currentDescription += string
            default:
                break
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "item" {
            isInsideItem = false

            let cleanTitle = cleanRSSString(currentTitle)
            let cleanDesc = cleanRSSString(currentDescription)
            let cleanLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract image from description HTML if not found in tags
            var finalImage = currentImageURL
            if finalImage == nil {
                finalImage = extractImageURLFromHTML(currentDescription)
            }

            guard !cleanTitle.isEmpty, !cleanLink.isEmpty else { return }

            let parsedDate = parseDate(currentPubDate)

            let id = cleanLink
            let item = NewsArticleItem(
                id: id,
                title: cleanTitle,
                link: cleanLink,
                description: cleanDesc,
                pubDate: parsedDate,
                pubDateString: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                source: sourceName,
                imageURL: finalImage,
                category: category
            )
            items.append(item)
        }
    }

    private func cleanRSSString(_ raw: String) -> String {
        var str = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&mdash;": " — ",
            "&ndash;": " – ",
            "&hellip;": "...",
            "&nbsp;": " "
        ]
        for (k, v) in entities {
            str = str.replacingOccurrences(of: k, with: v)
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImageURLFromHTML(_ html: String) -> String? {
        let pattern = "src=[\"'](https?://[^\"']+\\.(?:jpg|jpeg|png|webp))[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return (html as NSString).substring(with: match.range(at: 1))
    }

    private func parseDate(_ dateStr: String) -> Date? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in Self.dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}
