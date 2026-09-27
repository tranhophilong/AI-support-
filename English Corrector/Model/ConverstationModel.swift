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
