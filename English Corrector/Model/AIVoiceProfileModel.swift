//
//  AIVoiceProfileModel.swift
//  English Corrector
//

import Foundation
import SwiftUI
import AVFoundation

public enum AIVoiceType: String, Codable, CaseIterable {
    case elevenLabsCustom = "eleven_custom"
    case elevenLabsCurated = "eleven_curated"
    case appleSystem = "apple_system"

    public var displayName: String {
        switch self {
        case .elevenLabsCustom: return "Giọng tùy chỉnh"
        case .elevenLabsCurated: return "ElevenLabs Bản xứ"
        case .appleSystem: return "Apple Enhanced"
        }
    }
}

public enum AIVoiceGender: String, Codable, CaseIterable {
    case female = "female"
    case male = "male"
    case neutral = "neutral"

    public var displayName: String {
        switch self {
        case .female: return "Nữ"
        case .male: return "Nam"
        case .neutral: return "Trung tính"
        }
    }

    public var iconName: String {
        switch self {
        case .female: return "person.crop.circle.badge.fill"
        case .male: return "person.crop.circle"
        case .neutral: return "person.2.circle"
        }
    }
}

public enum AIVoiceAccent: String, Codable, CaseIterable {
    case american = "en-US"
    case british = "en-GB"
    case australian = "en-AU"
    case canadian = "en-CA"
    case other = "other"

    public var displayName: String {
        switch self {
        case .american: return "Mỹ (US)"
        case .british: return "Anh (UK)"
        case .australian: return "Úc (AU)"
        case .canadian: return "Canada (CA)"
        case .other: return "Quốc tế"
        }
    }

    public var flagEmoji: String {
        switch self {
        case .american: return "🇺🇸"
        case .british: return "🇬🇧"
        case .australian: return "🇦🇺"
        case .canadian: return "🇨🇦"
        case .other: return "🌐"
        }
    }
}

public enum VoiceExpressivenessPreset: String, Codable, CaseIterable, Identifiable {
    case conversational = "conversational"
    case teacher = "teacher"
    case dynamic = "dynamic"
    case storyteller = "storyteller"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .conversational: return "Đàm thoại tự nhiên"
        case .teacher: return "Thầy giáo bản xứ"
        case .dynamic: return "Năng động biểu cảm"
        case .storyteller: return "Kể chuyện truyền cảm"
        case .custom: return "Tùy chỉnh sâu"
        }
    }

    public var subtitle: String {
        switch self {
        case .conversational: return "Nhấn nhá vừa phải, phản xạ nói chuyện thoải mái"
        case .teacher: return "Phát âm rõ ràng, chuẩn mực, tốc độ từ tốn dễ nghe"
        case .dynamic: return "Năng lượng cao, giàu cảm xúc, nhấn nhá mạnh mẽ"
        case .storyteller: return "Trầm ấm, giàu nhịp điệu, ngắt nghỉ sâu lắng"
        case .custom: return "Tự điều chỉnh Stability, Style và Similarity"
        }
    }

    public var icon: String {
        switch self {
        case .conversational: return "bubble.left.and.bubble.right.fill"
        case .teacher: return "graduationcap.fill"
        case .dynamic: return "bolt.badge.automatic.fill"
        case .storyteller: return "book.closed.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var stability: Double {
        switch self {
        case .conversational: return 0.50
        case .teacher: return 0.65
        case .dynamic: return 0.35
        case .storyteller: return 0.40
        case .custom: return 0.50
        }
    }

    public var similarityBoost: Double {
        switch self {
        case .conversational: return 0.80
        case .teacher: return 0.85
        case .dynamic: return 0.75
        case .storyteller: return 0.85
        case .custom: return 0.80
        }
    }

    public var style: Double {
        switch self {
        case .conversational: return 0.35
        case .teacher: return 0.20
        case .dynamic: return 0.65
        case .storyteller: return 0.50
        case .custom: return 0.40
        }
    }
}

public struct AIVoiceProfile: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var type: AIVoiceType
    public var voiceId: String
    public var gender: AIVoiceGender
    public var accent: AIVoiceAccent
    public var descriptionText: String
    public var samplePhrase: String
    public var expressivenessPreset: VoiceExpressivenessPreset
    public var stability: Double
    public var similarityBoost: Double
    public var style: Double
    public var useSpeakerBoost: Bool
    public var speed: Double
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: AIVoiceType,
        voiceId: String,
        gender: AIVoiceGender = .neutral,
        accent: AIVoiceAccent = .american,
        descriptionText: String = "",
        samplePhrase: String = "Hello! It is wonderful to practice speaking English together today.",
        expressivenessPreset: VoiceExpressivenessPreset = .conversational,
        stability: Double? = nil,
        similarityBoost: Double? = nil,
        style: Double? = nil,
        useSpeakerBoost: Bool = true,
        speed: Double = 1.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.voiceId = voiceId
        self.gender = gender
        self.accent = accent
        self.descriptionText = descriptionText
        self.samplePhrase = samplePhrase
        self.expressivenessPreset = expressivenessPreset
        self.stability = stability ?? expressivenessPreset.stability
        self.similarityBoost = similarityBoost ?? expressivenessPreset.similarityBoost
        self.style = style ?? expressivenessPreset.style
        self.useSpeakerBoost = useSpeakerBoost
        self.speed = speed
        self.createdAt = createdAt
    }

    // MARK: - Curated Voices

    public static let curatedElevenLabsVoices: [AIVoiceProfile] = [
        AIVoiceProfile(
            id: "eleven_adam",
            name: "Adam (Warm Narrator)",
            type: .elevenLabsCurated,
            voiceId: "pNInz6obpgDQGcFmaJgB",
            gender: .male,
            accent: .american,
            descriptionText: "Giọng nam Mỹ trầm ấm, tự nhiên, nhịp điệu từ tốn thân thiện.",
            samplePhrase: "Hello! Practice makes progress. I am here to chat with you anytime.",
            expressivenessPreset: .conversational
        ),
        AIVoiceProfile(
            id: "eleven_rachel",
            name: "Rachel (Calm & Clear)",
            type: .elevenLabsCurated,
            voiceId: "21m00Tcm4TlvDq8ikWAM",
            gender: .female,
            accent: .american,
            descriptionText: "Giọng nữ Mỹ truyền cảm, rõ âm, ngữ điệu dịu dàng dễ nghe.",
            samplePhrase: "Hi there! Let's talk about your day in English. How are you feeling?",
            expressivenessPreset: .conversational
        ),
        AIVoiceProfile(
            id: "eleven_george",
            name: "George (British Gentleman)",
            type: .elevenLabsCurated,
            voiceId: "JBFqnCBsd6RMkjVDRZzb",
            gender: .male,
            accent: .british,
            descriptionText: "Giọng quý ông Anh quốc thanh lịch, phát âm chuẩn Received Pronunciation.",
            samplePhrase: "Good day! It is truly a pleasure to converse in English with you.",
            expressivenessPreset: .teacher
        ),
        AIVoiceProfile(
            id: "eleven_alice",
            name: "Alice (British Educator)",
            type: .elevenLabsCurated,
            voiceId: "Xb7hH8MSUJpSbSDYk0k2",
            gender: .female,
            accent: .british,
            descriptionText: "Giọng cô giáo Anh quốc ấm áp, nhấn nhá rõ ràng, chuẩn ngữ âm sư phạm.",
            samplePhrase: "Welcome back! Remember, making mistakes is simply how we master fluency.",
            expressivenessPreset: .teacher
        ),
        AIVoiceProfile(
            id: "eleven_charlie",
            name: "Charlie (Australian Buddy)",
            type: .elevenLabsCurated,
            voiceId: "IKne3meq5aSn9XLyUdCD",
            gender: .male,
            accent: .australian,
            descriptionText: "Giọng nam Úc thân thiện, hào sảng, ngữ điệu đàm thoại hằng ngày.",
            samplePhrase: "G'day mate! Ready to sharpen your English speaking skills today?",
            expressivenessPreset: .dynamic
        ),
        AIVoiceProfile(
            id: "eleven_liam",
            name: "Liam (Youthful & Energetic)",
            type: .elevenLabsCurated,
            voiceId: "TX3LPaxmHKxFdv7VOQHJ",
            gender: .male,
            accent: .american,
            descriptionText: "Giọng nam trẻ Mỹ năng động, phản xạ nhanh, tràn đầy hứng khởi.",
            samplePhrase: "Hey! What's up? Let's dive right into our conversation!",
            expressivenessPreset: .dynamic
        )
    ]

    public static let curatedAppleVoices: [AIVoiceProfile] = [
        AIVoiceProfile(
            id: "apple_samantha",
            name: "Samantha (Apple US Female)",
            type: .appleSystem,
            voiceId: "com.apple.voice.compact.en-US.Samantha",
            gender: .female,
            accent: .american,
            descriptionText: "Giọng nữ Mỹ tiêu chuẩn của iOS, phát âm chuẩn xác, rõ ràng.",
            samplePhrase: "Hello! I am ready to converse and practice speaking English with you.",
            expressivenessPreset: .conversational
        ),
        AIVoiceProfile(
            id: "apple_aaron",
            name: "Aaron (Apple US Male)",
            type: .appleSystem,
            voiceId: "com.apple.ttsbundle.siri_Aaron_en-US_compact",
            gender: .male,
            accent: .american,
            descriptionText: "Giọng nam Mỹ Siri tự nhiên, giọng trầm nam tính, phát âm chuẩn xác.",
            samplePhrase: "Hey there! Ready to practice your English conversational skills today?",
            expressivenessPreset: .conversational
        ),
        AIVoiceProfile(
            id: "apple_daniel",
            name: "Daniel (Apple UK Male)",
            type: .appleSystem,
            voiceId: "com.apple.voice.compact.en-GB.Daniel",
            gender: .male,
            accent: .british,
            descriptionText: "Giọng nam Anh quốc chuẩn phát âm British RP, ngữ điệu lịch thiệp.",
            samplePhrase: "Good day. Shall we practice speaking some English together now?",
            expressivenessPreset: .teacher
        ),
        AIVoiceProfile(
            id: "apple_karen",
            name: "Karen (Apple AU Female)",
            type: .appleSystem,
            voiceId: "com.apple.voice.compact.en-AU.Karen",
            gender: .female,
            accent: .australian,
            descriptionText: "Giọng nữ Úc tự nhiên, ngữ điệu thân thiện tích hợp sẵn trên iOS.",
            samplePhrase: "G'day! Let's get started with your English speaking practice.",
            expressivenessPreset: .conversational
        ),
        AIVoiceProfile(
            id: "apple_gordon",
            name: "Gordon (Apple AU Male)",
            type: .appleSystem,
            voiceId: "com.apple.ttsbundle.siri_Gordon_en-AU_compact",
            gender: .male,
            accent: .australian,
            descriptionText: "Giọng nam Úc Siri tự nhiên, thân thiện và năng động.",
            samplePhrase: "G'day mate! Let's practice speaking fluent English together.",
            expressivenessPreset: .dynamic
        )
    ]

    public static var defaultVoice: AIVoiceProfile {
        // If ElevenLabs API Key exists, default to Adam (ElevenLabs US Native); otherwise Samantha (Apple US Native)
        if !APIKeyStore.elevenLabsAPIKey.isEmpty {
            return curatedElevenLabsVoices[0]
        }
        return curatedAppleVoices[0]
    }
}

// MARK: - Voice Storage Manager

public final class VoiceProfileStorage {
    private static let selectedVoiceKey = "selected_ai_voice_profile_id"
    private static let customVoicesKey = "user_custom_ai_voice_profiles_data"

    public static func loadSelectedVoice() -> AIVoiceProfile {
        let selectedId = UserDefaults.standard.string(forKey: selectedVoiceKey) ?? ""
        let all = loadAllVoices()
        return all.first(where: { $0.id == selectedId }) ?? AIVoiceProfile.defaultVoice
    }

    public static func saveSelectedVoice(_ voice: AIVoiceProfile) {
        UserDefaults.standard.set(voice.id, forKey: selectedVoiceKey)
        NotificationCenter.default.post(name: .aiVoiceProfileDidChange, object: voice)
    }

    public static func loadCustomVoices() -> [AIVoiceProfile] {
        guard let data = UserDefaults.standard.data(forKey: customVoicesKey),
              let list = try? JSONDecoder().decode([AIVoiceProfile].self, from: data) else {
            return []
        }
        return list
    }

    public static func saveCustomVoices(_ voices: [AIVoiceProfile]) {
        if let data = try? JSONEncoder().encode(voices) {
            UserDefaults.standard.set(data, forKey: customVoicesKey)
        }
    }

    public static func addCustomVoice(_ voice: AIVoiceProfile) {
        var current = loadCustomVoices()
        current.removeAll(where: { $0.id == voice.id })
        current.insert(voice, at: 0)
        saveCustomVoices(current)
    }

    public static func deleteCustomVoice(id: String) {
        var current = loadCustomVoices()
        current.removeAll(where: { $0.id == id })
        saveCustomVoices(current)

        let selected = loadSelectedVoice()
        if selected.id == id {
            saveSelectedVoice(AIVoiceProfile.defaultVoice)
        }
    }

    public static func loadAllVoices() -> [AIVoiceProfile] {
        let custom = loadCustomVoices()
        return custom + AIVoiceProfile.curatedElevenLabsVoices + AIVoiceProfile.curatedAppleVoices
    }
}

public extension Notification.Name {
    static let aiVoiceProfileDidChange = Notification.Name("aiVoiceProfileDidChange")
}
