//
//  ConverstationModel.swift
//  English Corrector
//
//  Created by Long Tran on 16/5/26.
//

import SwiftData
import Foundation

@Model
class ConversationModel {
    var id: UUID = UUID()
    var title: String
    var conversationDescription: String
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \MessageModel.conversation)
    var messages: [MessageModel] = []

    init(
        title: String,
        conversationDescription: String
    ) {
        self.title = title
        self.conversationDescription = conversationDescription
    }
}


@Model
class MessageModel {
    var id: UUID = UUID()
    var text: String
    var isUser: Bool
    var createdAt: Date = Date()

    var conversation: ConversationModel?

    // AI Correction fields
    var fixed: String?
    var natural: String?
    var alternativeExpressions: [String]?
    var explanations: [String]?
    var explanationNoted: [String]?
    var followUpQuestion: String?
    var suggestedReplies: [String]?

    init(
        text: String,
        isUser: Bool,
        fixed: String? = nil,
        natural: String? = nil,
        alternativeExpressions: [String]? = nil,
        explanations: [String]? = nil,
        explanationNoted: [String]? = nil,
        followUpQuestion: String? = nil,
        suggestedReplies: [String]? = nil
    ) {
        self.text = text
        self.isUser = isUser
        self.fixed = fixed
        self.natural = natural
        self.alternativeExpressions = alternativeExpressions
        self.explanations = explanations
        self.explanationNoted = explanationNoted
        self.followUpQuestion = followUpQuestion
        self.suggestedReplies = suggestedReplies
    }
}

@Model
class SavedNoteModel {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String
    var originalText: String?
    var originalContext: String
    var isExplanation: Bool
    var explanationNoted: String?
    var sourceConversationID: UUID?
    var sourceMessageID: UUID?
    var sourceConversationTitle: String?
    var createdAt: Date = Date()

    // Per-note notification time
    var notificationHour: Int?
    var notificationMinute: Int?

    init(
        text: String,
        originalText: String? = nil,
        originalContext: String = "",
        isExplanation: Bool = false,
        explanationNoted: String? = nil,
        sourceConversationID: UUID? = nil,
        sourceMessageID: UUID? = nil,
        sourceConversationTitle: String? = nil
    ) {
        self.text = text
        self.originalText = originalText
        self.originalContext = originalContext
        self.isExplanation = isExplanation
        self.explanationNoted = explanationNoted
        self.sourceConversationID = sourceConversationID
        self.sourceMessageID = sourceMessageID
        self.sourceConversationTitle = sourceConversationTitle
    }
}

@Model
class VocabularyNoteModel {
    @Attribute(.unique) var normalizedWord: String
    var word: String
    var sourceText: String
    var sourceConversationID: UUID?
    var sourceConversationTitle: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // AI Dictionary Lookup fields (cached offline)
    var phonetic: String?
    var partOfSpeech: String?
    var vietnameseMeaning: String?
    var englishDefinition: String?
    var exampleSentence: String?
    var synonyms: [String]?
    var chatTopicsJSON: String?
    var imageURLsJSON: String?

    init(
        word: String,
        sourceText: String = "",
        sourceConversationID: UUID? = nil,
        sourceConversationTitle: String? = nil,
        phonetic: String? = nil,
        partOfSpeech: String? = nil,
        vietnameseMeaning: String? = nil,
        englishDefinition: String? = nil,
        exampleSentence: String? = nil,
        synonyms: [String]? = nil,
        chatTopics: [VocabularyChatTopicSuggestion]? = nil,
        imageURLs: [String]? = nil
    ) {
        self.word = word
        self.normalizedWord = word.normalizedVocabularyWord
        self.sourceText = sourceText
        self.sourceConversationID = sourceConversationID
        self.sourceConversationTitle = sourceConversationTitle
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.vietnameseMeaning = vietnameseMeaning
        self.englishDefinition = englishDefinition
        self.exampleSentence = exampleSentence
        self.synonyms = synonyms
        if let chatTopics,
           let data = try? JSONEncoder().encode(chatTopics),
           let json = String(data: data, encoding: .utf8) {
            self.chatTopicsJSON = json
        }
        if let imageURLs,
           !imageURLs.isEmpty,
           let data = try? JSONEncoder().encode(imageURLs),
           let json = String(data: data, encoding: .utf8) {
            self.imageURLsJSON = json
        }
    }

    var imageURLs: [String] {
        get {
            guard let imageURLsJSON,
                  let data = imageURLsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if !newValue.isEmpty,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                imageURLsJSON = json
            } else {
                imageURLsJSON = nil
            }
        }
    }

    var chatTopics: [VocabularyChatTopicSuggestion] {
        get {
            guard let chatTopicsJSON,
                  let data = chatTopicsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([VocabularyChatTopicSuggestion].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                chatTopicsJSON = json
            } else {
                chatTopicsJSON = nil
            }
        }
    }

    var hasLookupResult: Bool {
        guard let vietnameseMeaning, !vietnameseMeaning.isEmpty else {
            return false
        }
        return true
    }

    var cachedLookupResponse: AIVocabularyLookupResponse? {
        guard let vietnameseMeaning, !vietnameseMeaning.isEmpty else {
            return nil
        }

        return AIVocabularyLookupResponse(
            word: word,
            phonetic: phonetic ?? "",
            partOfSpeech: partOfSpeech ?? "",
            vietnameseMeaning: vietnameseMeaning,
            englishDefinition: englishDefinition ?? "",
            exampleSentence: exampleSentence ?? "",
            synonyms: synonyms ?? [],
            chatTopics: chatTopics
        )
    }
}

@Model
class SituationAskSessionModel {
    var id: UUID = UUID()
    var title: String
    var selectedTone: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SituationAskMessageModel.session)
    var messages: [SituationAskMessageModel] = []

    init(
        title: String = "Hỏi đáp tình huống",
        selectedTone: String = "Tự động"
    ) {
        self.title = title
        self.selectedTone = selectedTone
    }
}

@Model
class SituationAskMessageModel {
    var id: UUID = UUID()
    var text: String
    var toneTag: String?
    var isUser: Bool
    var createdAt: Date = Date()
    var responseJSON: String?

    var session: SituationAskSessionModel?

    init(
        text: String,
        toneTag: String? = nil,
        isUser: Bool,
        response: AISituationAskResponse? = nil
    ) {
        self.text = text
        self.toneTag = toneTag
        self.isUser = isUser
        if let response,
           let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            self.responseJSON = json
        }
    }

    var decodedResponse: AISituationAskResponse? {
        get {
            guard let responseJSON,
                  let data = responseJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AISituationAskResponse.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                responseJSON = json
            } else {
                responseJSON = nil
            }
        }
    }
}

@Model
class SentenceStructureAnalysisModel {
    @Attribute(.unique) var id: UUID = UUID()
    var sentence: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var analysisJSON: String?
    var followUpQAsJSON: String?

    init(
        sentence: String,
        analysis: AISentenceStructureResponse? = nil,
        followUpQAs: [AISentenceStructureFollowUpQA] = []
    ) {
        self.sentence = sentence
        if let analysis,
           let data = try? JSONEncoder().encode(analysis),
           let json = String(data: data, encoding: .utf8) {
            self.analysisJSON = json
        }
        if !followUpQAs.isEmpty,
           let data = try? JSONEncoder().encode(followUpQAs),
           let json = String(data: data, encoding: .utf8) {
            self.followUpQAsJSON = json
        }
    }

    var decodedAnalysis: AISentenceStructureResponse? {
        get {
            guard let analysisJSON,
                  let data = analysisJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AISentenceStructureResponse.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                analysisJSON = json
            } else {
                analysisJSON = nil
            }
        }
    }

    var followUpQAs: [AISentenceStructureFollowUpQA] {
        get {
            guard let followUpQAsJSON,
                  let data = followUpQAsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([AISentenceStructureFollowUpQA].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                followUpQAsJSON = json
            } else {
                followUpQAsJSON = nil
            }
        }
    }
}

@Model
class MistakeSummaryReportModel {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var analyzedCorrectionCount: Int = 0
    var analyzedNoteCount: Int = 0
    var reportJSON: String?
    var categoryRemindersJSON: String?

    init(
        analyzedCorrectionCount: Int = 0,
        analyzedNoteCount: Int = 0,
        report: AIMistakeSummaryResponse? = nil,
        categoryReminders: [String: MistakeCategoryReminderConfig] = [:]
    ) {
        self.analyzedCorrectionCount = analyzedCorrectionCount
        self.analyzedNoteCount = analyzedNoteCount
        if let report,
           let data = try? JSONEncoder().encode(report),
           let json = String(data: data, encoding: .utf8) {
            self.reportJSON = json
        }
        if !categoryReminders.isEmpty,
           let data = try? JSONEncoder().encode(categoryReminders),
           let json = String(data: data, encoding: .utf8) {
            self.categoryRemindersJSON = json
        }
    }

    var decodedReport: AIMistakeSummaryResponse? {
        get {
            guard let reportJSON,
                  let data = reportJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AIMistakeSummaryResponse.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                reportJSON = json
            } else {
                reportJSON = nil
            }
        }
    }

    var categoryReminders: [String: MistakeCategoryReminderConfig] {
        get {
            guard let categoryRemindersJSON,
                  let data = categoryRemindersJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: MistakeCategoryReminderConfig].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if !newValue.isEmpty,
               let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                categoryRemindersJSON = json
            } else {
                categoryRemindersJSON = nil
            }
        }
    }
}


extension String {
    var normalizedVocabularyWord: String {
        lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
