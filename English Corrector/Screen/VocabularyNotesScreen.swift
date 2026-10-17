//
//  VocabularyNotesScreen.swift
//  English Corrector
//

import SwiftUI
import SwiftData

struct VocabularyLookupTarget: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let contextSentence: String?
    let sourceConversationID: UUID?
}

struct VocabularyNotesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VocabularyNoteModel.updatedAt, order: .reverse) private var words: [VocabularyNoteModel]
    @Query private var conversations: [ConversationModel]

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var searchText = ""
    @State private var activeLookupTarget: VocabularyLookupTarget?
    @State private var selectedConversation: ConversationModel?

    private var selectedAIModel: AIModelOption {
        AIModelOption(rawValue: selectedAIModelRawValue) ?? .groqGPTOSS20B
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredWords: [VocabularyNoteModel] {
        guard !trimmedSearchText.isEmpty else { return words }
        let query = trimmedSearchText.lowercased()
        return words.filter { item in
            item.word.lowercased().contains(query) ||
            (item.vietnameseMeaning?.lowercased().contains(query) ?? false) ||
            item.sourceText.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    // DICTIONARY SEARCH & QUICK AI LOOKUP BAR
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(AppTheme.Neutral.n500)

                            TextField("Search or look up any English word...", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    triggerSearchLookup()
                                }

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AppTheme.Neutral.n400)
                                }
                            }
                        }
                        .padding(12)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.2)
                        }

                        if !trimmedSearchText.isEmpty {
                            Button {
                                triggerSearchLookup()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.Primary.p500)
                                        .frame(width: 30, height: 30)
                                        .background(AppTheme.Primary.p50)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Tra cứu AI: \"\(trimmedSearchText)\"")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.Neutral.n900)

                                        Text("Xem nghĩa tiếng Việt, phiên âm IPA & từ đồng nghĩa")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(AppTheme.Primary.p500)
                                }
                                .padding(12)
                                .background(AppTheme.Surface.card)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(AppTheme.Primary.p300, lineWidth: 1.2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if words.isEmpty && trimmedSearchText.isEmpty {
                        Spacer()

                        VStack(spacing: 14) {
                            Image(systemName: "textformat.abc")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(AppTheme.Accent.a600)
                                .frame(width: 68, height: 68)
                                .background(AppTheme.Accent.a50)
                                .clipShape(Circle())

                            Text("No vocabulary yet")
                                .font(.headline)
                                .foregroundStyle(AppTheme.Neutral.n900)

                            Text("Search any word above or use Pick word in chat to save vocabulary here.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Neutral.n500)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Spacer()
                    } else {
                        List {
                            ForEach(filteredWords) { item in
                                VocabularyRow(
                                    item: item,
                                    onLookup: {
                                        activeLookupTarget = VocabularyLookupTarget(
                                            word: item.word,
                                            contextSentence: item.sourceText,
                                            sourceConversationID: item.sourceConversationID
                                        )
                                    },
                                    onOpenConversation: conversation(for: item).map { conv in
                                        {
                                            selectedConversation = conv
                                        }
                                    }
                                )
                                .vocabularyListRowStyle()
                                .swipeActions {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(AppTheme.Surface.appBackground)
                    }
                }
            }
            .navigationTitle("Vocabulary")
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .tint(AppTheme.Primary.p500)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AIModelOption.allCases) { option in
                            Button {
                                selectedAIModelRawValue = option.rawValue
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: selectedAIModel == option
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                            }
                        }
                    } label: {
                        Image("swap_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .accessibilityLabel("AI Model: \(selectedAIModel.providerName)")
                    }
                }
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatScreen(conversation: conversation)
            }
            .sheet(item: $activeLookupTarget) { target in
                VocabularyDetailSheet(
                    initialTarget: target,
                    savedWords: words,
                    selectedAIModel: selectedAIModel,
                    onOpenConversation: { conversationID in
                        if let conv = conversations.first(where: { $0.id == conversationID }) {
                            activeLookupTarget = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                selectedConversation = conv
                            }
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func triggerSearchLookup() {
        guard !trimmedSearchText.isEmpty else { return }
        let matchedItem = words.first {
            $0.normalizedWord == trimmedSearchText.normalizedVocabularyWord
        }
        activeLookupTarget = VocabularyLookupTarget(
            word: matchedItem?.word ?? trimmedSearchText,
            contextSentence: matchedItem?.sourceText,
            sourceConversationID: matchedItem?.sourceConversationID
        )
    }

    private func conversation(for item: VocabularyNoteModel) -> ConversationModel? {
        guard let sourceConversationID = item.sourceConversationID else {
            return nil
        }

        return conversations.first { $0.id == sourceConversationID }
    }

    private func delete(_ item: VocabularyNoteModel) {
        context.delete(item)

        do {
            try context.save()
        } catch {
            print("DEBUG: Failed to delete vocabulary note: \(error)")
        }
    }
}

private struct VocabularyRow: View {
    let item: VocabularyNoteModel
    let onLookup: () -> Void
    let onOpenConversation: (() -> Void)?

    var body: some View {
        Button(action: onLookup) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(item.word)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.Accent.a600)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Accent.a50)
                        .clipShape(Capsule())

                    if let partOfSpeech = item.partOfSpeech, !partOfSpeech.isEmpty {
                        Text(partOfSpeech)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Primary.p500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                    }

                    if let phonetic = item.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: item.hasLookupResult ? "book.closed.fill" : "sparkles")
                            .font(.caption2)
                        Text(item.hasLookupResult ? "Chi tiết" : "Tra cứu AI")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.Primary.p500)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())
                }

                if let vietnameseMeaning = item.vietnameseMeaning, !vietnameseMeaning.isEmpty {
                    Text(vietnameseMeaning)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n900)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let synonyms = item.synonyms, !synonyms.isEmpty {
                    HStack(spacing: 6) {
                        Text("Đồng nghĩa:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n500)

                        Text(synonyms.prefix(4).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(AppTheme.Secondary.s600)
                            .lineLimit(1)
                    }
                }

                if !item.sourceText.isEmpty && item.sourceText != item.word {
                    Text(item.sourceText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    if let sourceConversationTitle = item.sourceConversationTitle,
                       !sourceConversationTitle.isEmpty,
                       let onOpenConversation {
                        Button(action: onOpenConversation) {
                            HStack(spacing: 5) {
                                Image(systemName: "message")
                                    .font(.caption2.weight(.semibold))

                                Text("Saved from \(sourceConversationTitle)")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(AppTheme.Accent.a600)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(item.updatedAt, style: .date)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
            }
            .padding(14)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
            }
            .shadow(color: AppTheme.Shadow.card, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct VocabularyDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let initialTarget: VocabularyLookupTarget
    let savedWords: [VocabularyNoteModel]
    let selectedAIModel: AIModelOption
    let onOpenConversation: (UUID) -> Void

    @State private var currentWord: String = ""
    @State private var currentContext: String?
    @State private var wordHistory: [String] = []

    @State private var lookupResult: AIVocabularyLookupResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var savedNoteForCurrentWord: VocabularyNoteModel? {
        let normalized = currentWord.normalizedVocabularyWord
        return savedWords.first { $0.normalizedWord == normalized }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Surface.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // WORD HEADER CARD
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(lookupResult?.word.isEmpty == false ? lookupResult!.word : currentWord)
                                        .font(.title2.bold())
                                        .foregroundStyle(AppTheme.Neutral.n900)

                                    HStack(spacing: 8) {
                                        if let phonetic = lookupResult?.phonetic, !phonetic.isEmpty {
                                            Text(phonetic)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.Neutral.n500)
                                        }

                                        if let partOfSpeech = lookupResult?.partOfSpeech, !partOfSpeech.isEmpty {
                                            Text(partOfSpeech)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AppTheme.Primary.p500)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(AppTheme.Primary.p50)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }

                                Spacer()

                                if let lookupResult {
                                    Button {
                                        saveCurrentLookup(lookupResult)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: savedNoteForCurrentWord != nil ? "checkmark.circle.fill" : "bookmark.fill")
                                            Text(savedNoteForCurrentWord != nil ? "Đã lưu" : "Lưu từ")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(savedNoteForCurrentWord != nil ? AppTheme.Semantic.success : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            savedNoteForCurrentWord != nil
                                            ? AppTheme.Semantic.success.opacity(0.14)
                                            : AppTheme.Primary.p500
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if let contextText = currentContext,
                               !contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               contextText.normalizedVocabularyWord != currentWord.normalizedVocabularyWord {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ngữ cảnh xuất hiện")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.Neutral.n500)

                                    Text(contextText)
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(AppTheme.Neutral.n700)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.Surface.cardMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(16)
                        .background(AppTheme.Surface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                        }

                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(AppTheme.Primary.p500)
                                Text("Đang tra cứu nghĩa & từ đồng nghĩa bằng AI...")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if let errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.Semantic.error)

                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Neutral.n700)
                                    .multilineTextAlignment(.center)

                                Button {
                                    performLookup(for: currentWord, contextSentence: currentContext, forceRefresh: true)
                                } label: {
                                    Label("Thử lại", systemImage: "arrow.clockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.Primary.p500)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.Surface.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                            }
                        } else if let result = lookupResult {
                            // MEANING & DEFINITION CARD
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Nghĩa tiếng Việt", systemImage: "character.book.closed.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.Primary.p500)

                                    Text(result.vietnameseMeaning)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.Neutral.n900)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Divider()
                                    .overlay(AppTheme.Surface.border)

                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Giải thích tiếng Anh", systemImage: "text.alignleft")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.Secondary.s600)

                                    Text(result.englishDefinition)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Neutral.n700)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if !result.exampleSentence.isEmpty {
                                    Divider()
                                        .overlay(AppTheme.Surface.border)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("Ví dụ", systemImage: "quote.opening")
                                            .font(.caption.bold())
                                            .foregroundStyle(AppTheme.Accent.a600)

                                        Text(result.exampleSentence)
                                            .font(.subheadline)
                                            .italic()
                                            .foregroundStyle(AppTheme.Neutral.n900)
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(AppTheme.Accent.a50)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                                            }
                                    }
                                }
                            }
                            .padding(16)
                            .background(AppTheme.Surface.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                            }

                            // SYNONYMS CARD
                            if !result.synonyms.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label("Từ đồng nghĩa (Synonyms)", systemImage: "sparkles")
                                            .font(.caption.bold())
                                            .foregroundStyle(AppTheme.Accent.a600)

                                        Spacer()

                                        Text("Bấm vào từ để tra cứu")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.Neutral.n500)
                                    }

                                    WordPickerFlowLayout(spacing: 8, lineSpacing: 8) {
                                        ForEach(result.synonyms, id: \.self) { synonym in
                                            let isSynonymSaved = savedWords.contains {
                                                $0.normalizedWord == synonym.normalizedVocabularyWord
                                            }

                                            Button {
                                                selectSynonym(synonym)
                                            } label: {
                                                HStack(spacing: 5) {
                                                    if isSynonymSaved {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.caption2)
                                                            .foregroundStyle(AppTheme.Semantic.success)
                                                    }

                                                    Text(synonym)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(AppTheme.Neutral.n900)

                                                    Image(systemName: "magnifyingglass")
                                                        .font(.caption2)
                                                        .foregroundStyle(AppTheme.Primary.p500)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(AppTheme.Primary.p50)
                                                .clipShape(Capsule())
                                                .overlay {
                                                    Capsule()
                                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(AppTheme.Surface.card)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                                }
                            }

                            if let conversationID = initialTarget.sourceConversationID,
                               wordHistory.isEmpty {
                                Button {
                                    onOpenConversation(conversationID)
                                } label: {
                                    HStack {
                                        Image(systemName: "message.fill")
                                        Text("Mở cuộc hội thoại gốc")
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Primary.p500)
                                    .padding(14)
                                    .background(AppTheme.Surface.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Dictionary AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Surface.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let previousWord = wordHistory.last {
                        Button {
                            goBackToPreviousWord()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(previousWord)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Button("Đóng") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        performLookup(for: currentWord, contextSentence: currentContext, forceRefresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Tra cứu lại bằng AI")
                }
            }
        }
        .onAppear {
            currentWord = initialTarget.word
            currentContext = initialTarget.contextSentence
            performLookup(for: initialTarget.word, contextSentence: initialTarget.contextSentence, forceRefresh: false)
        }
    }

    private func selectSynonym(_ synonym: String) {
        let trimmed = synonym.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.normalizedVocabularyWord != currentWord.normalizedVocabularyWord else {
            return
        }
        wordHistory.append(currentWord)
        currentWord = trimmed
        currentContext = nil
        performLookup(for: trimmed, contextSentence: nil, forceRefresh: false)
    }

    private func goBackToPreviousWord() {
        guard let previous = wordHistory.popLast() else { return }
        currentWord = previous
        currentContext = wordHistory.isEmpty ? initialTarget.contextSentence : nil
        performLookup(for: previous, contextSentence: currentContext, forceRefresh: false)
    }

    private func saveCurrentLookup(_ lookup: AIVocabularyLookupResponse) {
        do {
            _ = try VocabularyNoteStore.saveLookupResult(
                word: currentWord,
                lookup: lookup,
                sourceText: currentContext,
                in: context
            )
        } catch {
            print("DEBUG: Failed to save vocabulary lookup result: \(error)")
        }
    }

    private func performLookup(for word: String, contextSentence: String?, forceRefresh: Bool) {
        errorMessage = nil

        if !forceRefresh,
           let existing = savedWords.first(where: { $0.normalizedWord == word.normalizedVocabularyWord }),
           let cached = existing.cachedLookupResponse {
            lookupResult = cached
            return
        }

        isLoading = true
        lookupResult = nil

        Task {
            do {
                let service = VocabularyAIService(
                    provider: selectedAIModel.makeVocabularyProvider()
                )
                let response = try await service.lookupWord(
                    word: word,
                    context: contextSentence
                )

                await MainActor.run {
                    lookupResult = response
                    isLoading = false

                    // Automatically cache into SwiftData if the word is already saved in Vocabulary
                    if savedWords.contains(where: { $0.normalizedWord == word.normalizedVocabularyWord }) {
                        saveCurrentLookup(response)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

private struct VocabularyListRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func vocabularyListRowStyle() -> some View {
        modifier(VocabularyListRowStyle())
    }
}

#Preview {
    VocabularyNotesScreen()
        .modelContainer(for: [VocabularyNoteModel.self, ConversationModel.self], inMemory: true)
}
