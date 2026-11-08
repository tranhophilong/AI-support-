//
//  AudioCacheManager.swift
//  English Corrector
//

import Foundation
import CryptoKit

public final class AudioCacheManager {
    public static let shared = AudioCacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL
    private let maxCacheSizeBytes: Int64 = 120 * 1024 * 1024 // 120 MB max

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectoryURL = caches.appendingPathComponent("AIVoiceAudioCache", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }

    /// Generates a deterministic SHA256 cache key based on voice and generation parameters
    public func cacheKey(
        voiceId: String,
        text: String,
        speed: Double = 1.0,
        stability: Double = 0.5,
        style: Double = 0.4
    ) -> String {
        let raw = "\(voiceId)|\(String(format: "%.2f", speed))|\(String(format: "%.2f", stability))|\(String(format: "%.2f", style))|\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Checks if a cached MP3 file exists for the given key and returns its local file URL
    public func cachedAudioURL(for key: String) -> URL? {
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).mp3")
        if fileManager.fileExists(atPath: fileURL.path) {
            // Touch access date for LRU
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return fileURL
        }
        return nil
    }

    /// Saves audio data into cache and returns the local file URL
    @discardableResult
    public func saveAudio(data: Data, for key: String) -> URL? {
        let fileURL = cacheDirectoryURL.appendingPathComponent("\(key).mp3")
        do {
            try data.write(to: fileURL, options: .atomic)
            cleanupOldFilesIfNeeded()
            return fileURL
        } catch {
            print("DEBUG: Failed to write audio cache: \(error)")
            return nil
        }
    }

    /// Clears the entire audio cache
    public func clearCache() {
        try? fileManager.removeItem(at: cacheDirectoryURL)
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    /// Computes total size of audio cache in bytes
    public func totalCacheSize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    /// Enforces LRU cleanup when cache exceeds max threshold
    private func cleanupOldFilesIfNeeded() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let total = self.totalCacheSize()
            guard total > self.maxCacheSizeBytes else { return }

            guard let files = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { return }

            let sorted = files.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 < d2
            }

            var currentSize = total
            for file in sorted {
                if currentSize <= self.maxCacheSizeBytes / 2 { break }
                let fileSize = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                try? self.fileManager.removeItem(at: file)
                currentSize -= fileSize
            }
        }
    }
}
