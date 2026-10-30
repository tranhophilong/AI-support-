//
//  VocabularyNoteStore.swift
//  English Corrector
//

import Foundation
import SwiftData

final class VocabularyNoteStore {
    private init() {}

    @discardableResult
    static func save(
        word: String,
        sourceText: String,
        sourceConversation: ConversationModel? = nil,
        in context: ModelContext
    ) throws -> VocabularyNoteModel? {
        let normalizedWord = word.normalizedVocabularyWord
        guard !normalizedWord.isEmpty else { return nil }

        let descriptor = FetchDescriptor<VocabularyNoteModel>(
            predicate: #Predicate { item in
                item.normalizedWord == normalizedWord
            }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.word = word
            existing.sourceText = sourceText
            existing.sourceConversationID = sourceConversation?.id
            existing.sourceConversationTitle = sourceConversation?.title
            existing.updatedAt = Date()
            try context.save()
            return existing
        }

        let note = VocabularyNoteModel(
            word: word,
            sourceText: sourceText,
            sourceConversationID: sourceConversation?.id,
            sourceConversationTitle: sourceConversation?.title
        )
        context.insert(note)
        try context.save()
        return note
    }

    static func save(
        words: Set<String>,
        sourceText: String,
        sourceConversation: ConversationModel? = nil,
        in context: ModelContext
    ) throws {
        for word in words {
            _ = try save(
                word: word,
                sourceText: sourceText,
                sourceConversation: sourceConversation,
                in: context
            )
        }
    }

    @discardableResult
    static func saveLookupResult(
        word: String,
        lookup: AIVocabularyLookupResponse,
        sourceText: String? = nil,
        sourceConversation: ConversationModel? = nil,
        imageURLs: [String]? = nil,
        in context: ModelContext
    ) throws -> VocabularyNoteModel? {
        let normalizedWord = word.normalizedVocabularyWord
        guard !normalizedWord.isEmpty else { return nil }

        let descriptor = FetchDescriptor<VocabularyNoteModel>(
            predicate: #Predicate { item in
                item.normalizedWord == normalizedWord
            }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.phonetic = lookup.phonetic
            existing.partOfSpeech = lookup.partOfSpeech
            existing.vietnameseMeaning = lookup.vietnameseMeaning
            existing.englishDefinition = lookup.englishDefinition
            existing.exampleSentence = lookup.exampleSentence
            existing.synonyms = lookup.synonyms
            if let chatTopics = lookup.chatTopics, !chatTopics.isEmpty {
                existing.chatTopics = chatTopics
            }
            if let imageURLs, !imageURLs.isEmpty {
                existing.imageURLs = imageURLs
            }
            if let sourceText, !sourceText.isEmpty, existing.sourceText.isEmpty {
                existing.sourceText = sourceText
            }
            if let sourceConversation, existing.sourceConversationID == nil {
                existing.sourceConversationID = sourceConversation.id
                existing.sourceConversationTitle = sourceConversation.title
            }
            existing.updatedAt = Date()
            try context.save()
            return existing
        }

        let note = VocabularyNoteModel(
            word: lookup.word.isEmpty ? word : lookup.word,
            sourceText: sourceText ?? lookup.exampleSentence,
            sourceConversationID: sourceConversation?.id,
            sourceConversationTitle: sourceConversation?.title,
            phonetic: lookup.phonetic,
            partOfSpeech: lookup.partOfSpeech,
            vietnameseMeaning: lookup.vietnameseMeaning,
            englishDefinition: lookup.englishDefinition,
            exampleSentence: lookup.exampleSentence,
            synonyms: lookup.synonyms,
            chatTopics: lookup.chatTopics,
            imageURLs: imageURLs
        )
        context.insert(note)
        try context.save()
        return note
    }

    static func updateImageURLs(
        for word: String,
        imageURLs: [String],
        in context: ModelContext
    ) {
        let normalizedWord = word.normalizedVocabularyWord
        guard !normalizedWord.isEmpty, !imageURLs.isEmpty else { return }

        let descriptor = FetchDescriptor<VocabularyNoteModel>(
            predicate: #Predicate { item in
                item.normalizedWord == normalizedWord
            }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.imageURLs = imageURLs
            try? context.save()
        }
    }

    @discardableResult
    static func saveQuickLookupResult(
        word: String,
        quickLookup: AIQuickWordLookupResponse,
        sourceText: String,
        in context: ModelContext
    ) throws -> VocabularyNoteModel? {
        let normalizedWord = word.normalizedVocabularyWord
        guard !normalizedWord.isEmpty else { return nil }

        let descriptor = FetchDescriptor<VocabularyNoteModel>(
            predicate: #Predicate { item in
                item.normalizedWord == normalizedWord
            }
        )

        if let existing = try context.fetch(descriptor).first {
            if (existing.phonetic ?? "").isEmpty && !quickLookup.phonetic.isEmpty {
                existing.phonetic = quickLookup.phonetic
            }
            if (existing.partOfSpeech ?? "").isEmpty && !quickLookup.partOfSpeech.isEmpty {
                existing.partOfSpeech = quickLookup.partOfSpeech
            }
            if (existing.vietnameseMeaning ?? "").isEmpty && !quickLookup.contextualMeaning.isEmpty {
                existing.vietnameseMeaning = quickLookup.contextualMeaning
            }
            if existing.sourceText.isEmpty && !sourceText.isEmpty {
                existing.sourceText = sourceText
            }
            existing.updatedAt = Date()
            try context.save()
            return existing
        }

        let displayWord = quickLookup.word.isEmpty ? word.trimmingCharacters(in: .punctuationCharacters) : quickLookup.word
        let note = VocabularyNoteModel(
            word: displayWord,
            sourceText: sourceText,
            phonetic: quickLookup.phonetic,
            partOfSpeech: quickLookup.partOfSpeech,
            vietnameseMeaning: quickLookup.contextualMeaning,
            englishDefinition: quickLookup.grammarRoleInSentence,
            exampleSentence: sourceText
        )
        context.insert(note)
        try context.save()
        return note
    }

}
