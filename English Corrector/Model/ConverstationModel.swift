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
    var explanations: [String]?
    var explanationNoted: [String]?

    init(
        text: String,
        isUser: Bool,
        fixed: String? = nil,
        natural: String? = nil,
        explanations: [String]? = nil,
        explanationNoted: [String]? = nil
    ) {
        self.text = text
        self.isUser = isUser
        self.fixed = fixed
        self.natural = natural
        self.explanations = explanations
        self.explanationNoted = explanationNoted
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
    var createdAt: Date = Date()

    // Per-note notification time
    var notificationHour: Int?
    var notificationMinute: Int?

    init(text: String, originalText: String? = nil, originalContext: String = "", isExplanation: Bool = false, explanationNoted: String? = nil) {
        self.text = text
        self.originalText = originalText
        self.originalContext = originalContext
        self.isExplanation = isExplanation
        self.explanationNoted = explanationNoted
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
        synonyms: [String]? = nil
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
            synonyms: synonyms ?? []
        )
    }
}

extension String {
    var normalizedVocabularyWord: String {
        lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
