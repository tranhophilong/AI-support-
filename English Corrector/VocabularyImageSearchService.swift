//
//  VocabularyImageSearchService.swift
//  English Corrector
//

import Foundation
import SwiftUI
import UIKit
import WebKit

enum VocabularyImageSearchMode: String, CaseIterable, Identifiable {
    case realPhoto = "real"
    case illustration = "illustration"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realPhoto:
            return "Ảnh thực tế"
        case .illustration:
            return "Minh hoạ nghĩa"
        }
    }

    var icon: String {
        switch self {
        case .realPhoto:
            return "photo.on.rectangle.angled"
        case .illustration:
            return "paintbrush.pointed.fill"
        }
    }

    func buildQuery(for word: String) -> String {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .realPhoto:
            return "\(cleaned) english vocabulary"
        case .illustration:
            return "\(cleaned) meaning illustration flashcard"
        }
    }
}

@MainActor
final class VocabularyImageCache {
    static let shared = VocabularyImageCache()
    private var storage: [String: [String]] = [:]

    private init() {}

    private func makeKey(word: String, mode: VocabularyImageSearchMode) -> String {
        "\(word.normalizedVocabularyWord)|\(mode.rawValue)"
    }

    func get(word: String, mode: VocabularyImageSearchMode) -> [String]? {
        storage[makeKey(word: word, mode: mode)]
    }

    func set(_ urls: [String], word: String, mode: VocabularyImageSearchMode) {
        guard !urls.isEmpty else { return }
        storage[makeKey(word: word, mode: mode)] = urls
    }
}

final class VocabularyImageSearchService {
    static let shared = VocabularyImageSearchService()

    private init() {}

    func googleImagesWebURL(for word: String, mode: VocabularyImageSearchMode) -> URL? {
        let query = mode.buildQuery(for: word)
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    /// Fetches the first 4 to 5 images for the given word.
    /// Uses fast HTTP image search + Google Images WKWebView scraper + Wikimedia fallback so 4-5 images always load reliably by default.
    func fetchImages(
        for word: String,
        mode: VocabularyImageSearchMode = .realPhoto,
        maxCount: Int = 5
    ) async throws -> [String] {
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedWord.isEmpty else { return [] }

        let query = mode.buildQuery(for: cleanedWord)

        // 1. Try fast HTTP image search first (returns 4-5 high-res CDN thumbnails in ~300ms)
        if let fastURLs = try? await fetchFastSearchImages(query: query, maxCount: maxCount),
           fastURLs.count >= 4 {
            return Array(fastURLs.prefix(maxCount))
        }

        // 2. Try Google Images via offscreen WKWebView (executes Google's JS challenge natively)
        let googleWebViewURLs = await GoogleImagesWebViewExtractor.shared.extractTopImages(
            query: query,
            maxCount: maxCount
        )
        if googleWebViewURLs.count >= 4 {
            return Array(googleWebViewURLs.prefix(maxCount))
        }

        // 3. Combine any partial results with Wikimedia Commons
        let wikiURLs = (try? await fetchFromWikimedia(query: cleanedWord, maxCount: maxCount)) ?? []
        var combined: [String] = []
        for item in (googleWebViewURLs + wikiURLs) where !combined.contains(item) {
            combined.append(item)
            if combined.count >= maxCount {
                break
            }
        }

        return Array(combined.prefix(maxCount))
    }

    private func fetchFastSearchImages(query: String, maxCount: Int) async throws -> [String] {
        var components = URLComponents(string: "https://www.bing.com/images/async")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "first", value: "0"),
            URLQueryItem(name: "count", value: "12"),
            URLQueryItem(name: "adlt", value: "strict")
        ]

        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let rawHTML = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        let unescaped = rawHTML
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        var results: [String] = []
        var seen = Set<String>()

        // Prefer CDN thumbnail URLs (`turl`) first because they are guaranteed fast, high-res HTTPS images without hotlink blocking
        let turlPattern = #""turl":"(https://[^"]+)""#
        if let regex = try? NSRegularExpression(pattern: turlPattern) {
            let matches = regex.matches(in: unescaped, range: NSRange(unescaped.startIndex..., in: unescaped))
            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: unescaped) {
                    let candidate = String(unescaped[range])
                    if !seen.contains(candidate) {
                        seen.insert(candidate)
                        results.append(candidate)
                        if results.count >= maxCount {
                            return results
                        }
                    }
                }
            }
        }

        // Also check `murl` if needed
        let murlPattern = #""murl":"(https://[^"]+)""#
        if let regex = try? NSRegularExpression(pattern: murlPattern) {
            let matches = regex.matches(in: unescaped, range: NSRange(unescaped.startIndex..., in: unescaped))
            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: unescaped) {
                    let candidate = String(unescaped[range])
                    if !seen.contains(candidate) {
                        seen.insert(candidate)
                        results.append(candidate)
                        if results.count >= maxCount {
                            return results
                        }
                    }
                }
            }
        }

        return results
    }

    private func fetchFromWikimedia(query: String, maxCount: Int) async throws -> [String] {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "filetype:bitmap \(query)"),
            URLQueryItem(name: "gsrlimit", value: "\(maxCount * 2)"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url"),
            URLQueryItem(name: "iiurlwidth", value: "500"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("EnglishCorrectorApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryDict = json["query"] as? [String: Any],
              let pages = queryDict["pages"] as? [String: Any] else {
            return []
        }

        var urls: [String] = []
        for (_, pageValue) in pages {
            if let page = pageValue as? [String: Any],
               let imageInfo = page["imageinfo"] as? [[String: Any]],
               let firstInfo = imageInfo.first,
               let thumbURL = (firstInfo["thumburl"] as? String) ?? (firstInfo["url"] as? String),
               thumbURL.hasPrefix("https://") {
                urls.append(thumbURL)
                if urls.count >= maxCount {
                    break
                }
            }
        }
        return urls
    }
}

// MARK: - Offscreen WKWebView Extractor for Google Images

@MainActor
final class GoogleImagesWebViewExtractor: NSObject, WKNavigationDelegate {
    static let shared = GoogleImagesWebViewExtractor()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String], Never>?
    private var maxCount: Int = 5
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func extractTopImages(query: String, maxCount: Int = 5) async -> [String] {
        // Cancel any previous in-flight extraction
        finish(with: [])

        self.maxCount = maxCount

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "safe", value: "active")
        ]

        guard let url = components?.url else { return [] }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        wv.navigationDelegate = self
        self.webView = wv

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        wv.load(request)

        return await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            self.continuation = cont
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                await self.pollDOMForImages(isFinalAttempt: true)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.pollDOMForImages(isFinalAttempt: false)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: [])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: [])
    }

    private func pollDOMForImages(isFinalAttempt: Bool) async {
        guard let webView, continuation != nil else { return }

        let js = """
        (function() {
            const imgs = Array.from(document.querySelectorAll('img'));
            const results = [];
            for (const img of imgs) {
                const src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-iurl') || '';
                if (!src) continue;
                const w = img.naturalWidth || img.width || 0;
                const h = img.naturalHeight || img.height || 0;
                if (w > 0 && w < 45 && h > 0 && h < 45) continue;
                const lower = src.toLowerCase();
                if (lower.includes('googlelogo') || lower.includes('branding') || lower.includes('favicon') || lower.endsWith('.svg')) continue;
                if (src.startsWith('https://') || (src.startsWith('data:image/') && src.length > 1200)) {
                    if (!results.includes(src)) {
                        results.push(src);
                    }
                }
                if (results.length >= \(maxCount)) break;
            }
            return results;
        })();
        """

        if let urls = try? await webView.evaluateJavaScript(js) as? [String],
           urls.count >= 4 {
            finish(with: Array(urls.prefix(maxCount)))
            return
        }

        if isFinalAttempt {
            let fallbackUrls = (try? await webView.evaluateJavaScript(js) as? [String]) ?? []
            finish(with: Array(fallbackUrls.prefix(maxCount)))
        }
    }

    private func finish(with urls: [String]) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        if let cont = continuation {
            continuation = nil
            cont.resume(returning: urls)
        }
    }
}

// MARK: - Reusable Image View Supporting Both HTTPS URLs & Inline Base64 Data URLs

struct VocabularyRemoteImageView: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    private var decodedDataImage: UIImage? {
        guard urlString.hasPrefix("data:image/"),
              let commaIndex = urlString.firstIndex(of: ",") else {
            return nil
        }
        let base64Part = String(urlString[urlString.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64Part, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    var body: some View {
        if let uiImage = decodedDataImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    ZStack {
                        AppTheme.Surface.cardMuted
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n400)
                    }
                case .empty:
                    ZStack {
                        AppTheme.Surface.cardMuted
                        ProgressView()
                            .controlSize(.small)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            ZStack {
                AppTheme.Surface.cardMuted
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n400)
            }
        }
    }
}
