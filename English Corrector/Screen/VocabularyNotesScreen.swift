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

struct VocabularyConversationDestination: Identifiable, Hashable {
    let id = UUID()
    let conversation: ConversationModel
    let highlightedWord: String?
    let highlightedSourceText: String?
}

struct VocabularyNotesScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VocabularyNoteModel.updatedAt, order: .reverse) private var words: [VocabularyNoteModel]
    @Query private var conversations: [ConversationModel]

    @AppStorage("selectedAIModel") private var selectedAIModelRawValue = AIModelOption.groqGPTOSS20B.rawValue

    @State private var searchText = ""
    @State private var activeLookupTarget: VocabularyLookupTarget?
    @State private var selectedDestination: VocabularyConversationDestination?

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
                                            selectedDestination = VocabularyConversationDestination(
                                                conversation: conv,
                                                highlightedWord: item.word,
                                                highlightedSourceText: item.sourceText
                                            )
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
            .navigationDestination(item: $selectedDestination) { destination in
                ChatScreen(
                    conversation: destination.conversation,
                    highlightedWord: destination.highlightedWord,
                    highlightedSourceText: destination.highlightedSourceText
                )
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
                                selectedDestination = VocabularyConversationDestination(
                                    conversation: conv,
                                    highlightedWord: target.word,
                                    highlightedSourceText: target.contextSentence
                                )
                            }
                        }
                    },
                    onStartTopicConversation: { newConversation in
                        activeLookupTarget = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedDestination = VocabularyConversationDestination(
                                conversation: newConversation,
                                highlightedWord: target.word,
                                highlightedSourceText: nil
                            )
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
    @Environment(\.modelContext) private var context

    let item: VocabularyNoteModel
    let onLookup: () -> Void
    let onOpenConversation: (() -> Void)?

    @State private var rowImages: [String] = []

    private var displayedImages: [String] {
        !item.imageURLs.isEmpty ? item.imageURLs : rowImages
    }

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

                    SpeakButton(
                        text: item.word,
                        font: .caption.weight(.semibold),
                        activeColor: AppTheme.Primary.p500,
                        showBackground: true
                    )

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

                if !displayedImages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(displayedImages.prefix(5).enumerated()), id: \.offset) { _, urlString in
                            VocabularyRemoteImageView(urlString: urlString, contentMode: .fill)
                                .frame(width: 54, height: 54)
                                .background(AppTheme.Surface.cardMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.8)
                                }
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 10) {
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

                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.caption2)
                        Text(displayedImages.isEmpty ? "Đang tải ảnh..." : "\(displayedImages.count) ảnh")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.Primary.p500)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Primary.p50)
                    .clipShape(Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.caption2)
                        Text(item.chatTopics.isEmpty ? "Gợi ý chat" : "Luyện chat (\(item.chatTopics.count))")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())

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
        .task(id: item.word) {
            guard item.imageURLs.isEmpty else { return }
            if let cached = VocabularyImageCache.shared.get(word: item.word, mode: .realPhoto), !cached.isEmpty {
                rowImages = cached
                VocabularyNoteStore.updateImageURLs(for: item.word, imageURLs: cached, in: context)
                return
            }
            if let fetched = try? await VocabularyImageSearchService.shared.fetchImages(
                for: item.word,
                mode: .realPhoto,
                maxCount: 5
            ), !fetched.isEmpty {
                rowImages = fetched
                VocabularyImageCache.shared.set(fetched, word: item.word, mode: .realPhoto)
                VocabularyNoteStore.updateImageURLs(for: item.word, imageURLs: fetched, in: context)
            }
        }
    }
}

private struct VocabularyDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let initialTarget: VocabularyLookupTarget
    let savedWords: [VocabularyNoteModel]
    let selectedAIModel: AIModelOption
    let onOpenConversation: (UUID) -> Void
    let onStartTopicConversation: (ConversationModel) -> Void

    @State private var currentWord: String = ""
    @State private var currentContext: String?
    @State private var wordHistory: [String] = []


    @State private var lookupResult: AIVocabularyLookupResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var imageURLs: [String] = []
    @State private var isLoadingImages = false
    @State private var imageSearchMode: VocabularyImageSearchMode = .realPhoto
    @State private var selectedLightboxIndex: Int?

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
                        let spokenWord = lookupResult?.word.isEmpty == false ? lookupResult!.word : currentWord

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(spokenWord)
                                        .font(.title2.bold())
                                        .foregroundStyle(AppTheme.Neutral.n900)

                                    HStack(spacing: 8) {
                                        if let phonetic = lookupResult?.phonetic, !phonetic.isEmpty {
                                            Text(phonetic)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.Neutral.n500)
                                        }

                                        SpeakButton(
                                            text: spokenWord,
                                            slow: false,
                                            font: .subheadline.weight(.semibold),
                                            activeColor: AppTheme.Primary.p500,
                                            showBackground: true
                                        )

                                        SpeakButton(
                                            text: spokenWord,
                                            slow: true,
                                            font: .subheadline.weight(.semibold),
                                            activeColor: AppTheme.Accent.a600,
                                            showBackground: true
                                        )

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
                                    HStack {
                                        Text("Ngữ cảnh xuất hiện")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(AppTheme.Neutral.n500)

                                        Spacer()

                                        SpeakButton(
                                            text: contextText,
                                            font: .caption,
                                            activeColor: AppTheme.Primary.p500
                                        )
                                    }

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

                        // GOOGLE IMAGES CARD (4-5 IMAGES)
                        googleImagesCard(for: spokenWord)

                        if isLoading {
                            VStack(spacing: 12) {
                                AppThemeLoadingView(customSize: 32)
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
                                    HStack {
                                        Label("Giải thích tiếng Anh", systemImage: "text.alignleft")
                                            .font(.caption.bold())
                                            .foregroundStyle(AppTheme.Secondary.s600)

                                        Spacer()

                                        SpeakButton(
                                            text: result.englishDefinition,
                                            font: .caption,
                                            activeColor: AppTheme.Secondary.s600
                                        )
                                    }

                                    Text(result.englishDefinition)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Neutral.n700)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if !result.exampleSentence.isEmpty {
                                    Divider()
                                        .overlay(AppTheme.Surface.border)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 10) {
                                            Label("Ví dụ", systemImage: "quote.opening")
                                                .font(.caption.bold())
                                                .foregroundStyle(AppTheme.Accent.a600)

                                            Spacer()

                                            SpeakButton(
                                                text: result.exampleSentence,
                                                slow: false,
                                                font: .caption,
                                                activeColor: AppTheme.Accent.a600
                                            )

                                            SpeakButton(
                                                text: result.exampleSentence,
                                                slow: true,
                                                font: .caption,
                                                activeColor: AppTheme.Accent.a600
                                            )
                                        }

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

                            if let topics = result.chatTopics, !topics.isEmpty {
                                chatTopicsCard(topics: topics, lookup: result)
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
                        loadGoogleImages(for: currentWord, mode: imageSearchMode, forceRefresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Tra cứu lại bằng AI")
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { selectedLightboxIndex != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedLightboxIndex = nil
                    }
                }
            )
        ) {
            if let initialIndex = selectedLightboxIndex, !imageURLs.isEmpty {
                VocabularyImageLightboxView(
                    word: lookupResult?.word.isEmpty == false ? lookupResult!.word : currentWord,
                    meaning: lookupResult?.vietnameseMeaning ?? savedNoteForCurrentWord?.vietnameseMeaning,
                    imageURLs: imageURLs,
                    initialIndex: initialIndex,
                    googleImagesWebURL: VocabularyImageSearchService.shared.googleImagesWebURL(
                        for: currentWord,
                        mode: imageSearchMode
                    ),
                    onClose: {
                        selectedLightboxIndex = nil
                    }
                )
            }
        }
        .onAppear {
            currentWord = initialTarget.word
            currentContext = initialTarget.contextSentence
            performLookup(for: initialTarget.word, contextSentence: initialTarget.contextSentence, forceRefresh: false)
            loadGoogleImages(for: initialTarget.word, mode: imageSearchMode, forceRefresh: false)
        }
        .onDisappear {
            SpeechSynthesizerManager.shared.stop()
        }
    }

    @ViewBuilder
    private func googleImagesCard(for word: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Hình ảnh minh hoạ (Google)", systemImage: "photo.on.rectangle.angled")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Spacer()

                Button {
                    loadGoogleImages(for: word, mode: imageSearchMode, forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Neutral.n500)
                        .padding(6)
                        .background(AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoadingImages)

                if let webURL = VocabularyImageSearchService.shared.googleImagesWebURL(for: word, mode: imageSearchMode) {
                    Link(destination: webURL) {
                        HStack(spacing: 4) {
                            Text("Google Images")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                }
            }

            // Mode Toggle: Ảnh thực tế vs Minh hoạ nghĩa
            HStack(spacing: 8) {
                ForEach(VocabularyImageSearchMode.allCases) { mode in
                    let isSelected = (imageSearchMode == mode)
                    Button {
                        guard imageSearchMode != mode else { return }
                        imageSearchMode = mode
                        loadGoogleImages(for: word, mode: mode, forceRefresh: false)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.caption2)
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isSelected ? .white : AppTheme.Neutral.n700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? AppTheme.Primary.p500 : AppTheme.Surface.cardMuted)
                        .clipShape(Capsule())
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if isLoadingImages {
                HStack(spacing: 10) {
                    AppThemeLoadingView(customSize: 18)
                    Text("Đang tổng hợp 4–5 hình ảnh từ Google...")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 26)
            } else if imageURLs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(AppTheme.Neutral.n400)
                    Text("Chưa tải được hình ảnh. Bấm tải lại hoặc mở Google Images.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            } else {
                googleImagesGridView
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

    @ViewBuilder
    private var googleImagesGridView: some View {
        let topImages = Array(imageURLs.prefix(2).enumerated())
        let bottomImages = Array(imageURLs.dropFirst(2).prefix(3).enumerated())

        VStack(spacing: 8) {
            // Top Row: 2 larger images
            HStack(spacing: 8) {
                ForEach(topImages, id: \.offset) { idx, urlString in
                    imageThumbnailButton(urlString: urlString, index: idx, height: 120)
                }
            }

            // Bottom Row: 2-3 images
            if !bottomImages.isEmpty {
                HStack(spacing: 8) {
                    ForEach(bottomImages, id: \.offset) { offset, urlString in
                        imageThumbnailButton(urlString: urlString, index: offset + 2, height: 96)
                    }
                }
            }

            Text("Chạm vào ảnh bất kỳ để phóng to")
                .font(.caption2)
                .foregroundStyle(AppTheme.Neutral.n400)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func imageThumbnailButton(urlString: String, index: Int, height: CGFloat) -> some View {
        Button {
            selectedLightboxIndex = index
        } label: {
            GeometryReader { geo in
                VocabularyRemoteImageView(urlString: urlString, contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func chatTopicsCard(topics: [VocabularyChatTopicSuggestion], lookup: AIVocabularyLookupResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Gợi ý chủ đề luyện Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Spacer()

                Text("Bấm để bắt đầu chat")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            ForEach(topics) { topic in
                Button {
                    startTopicConversation(topic, lookup: lookup)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(topic.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.Neutral.n900)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            HStack(spacing: 4) {
                                Text("Bắt đầu chat")
                                    .font(.caption2.weight(.semibold))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption)
                            }
                            .foregroundStyle(AppTheme.Primary.p500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.Primary.p50)
                            .clipShape(Capsule())
                        }

                        Text(topic.starterQuestion)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let firstReply = topic.sampleReplies.first, !firstReply.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Accent.a600)

                                Text("Mẫu: \"\(firstReply)\"")
                                    .font(.caption2)
                                    .italic()
                                    .foregroundStyle(AppTheme.Neutral.n500)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Surface.cardMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
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

    private func startTopicConversation(_ topic: VocabularyChatTopicSuggestion, lookup: AIVocabularyLookupResponse) {
        let newConversation = ConversationModel(
            title: topic.title,
            conversationDescription: topic.contextDescription
        )
        context.insert(newConversation)

        let starterMessage = MessageModel(
            text: topic.starterQuestion,
            isUser: false,
            followUpQuestion: topic.starterQuestion,
            suggestedReplies: topic.sampleReplies
        )
        starterMessage.conversation = newConversation
        context.insert(starterMessage)

        do {
            _ = try VocabularyNoteStore.saveLookupResult(
                word: currentWord,
                lookup: lookup,
                sourceText: currentContext,
                sourceConversation: newConversation,
                in: context
            )
            try context.save()
        } catch {
            print("DEBUG: Failed to create vocabulary topic conversation: \(error)")
        }

        onStartTopicConversation(newConversation)
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
        loadGoogleImages(for: trimmed, mode: imageSearchMode, forceRefresh: false)
    }

    private func goBackToPreviousWord() {
        guard let previous = wordHistory.popLast() else { return }
        currentWord = previous
        currentContext = wordHistory.isEmpty ? initialTarget.contextSentence : nil
        performLookup(for: previous, contextSentence: currentContext, forceRefresh: false)
        loadGoogleImages(for: previous, mode: imageSearchMode, forceRefresh: false)
    }

    private func saveCurrentLookup(_ lookup: AIVocabularyLookupResponse) {
        do {
            _ = try VocabularyNoteStore.saveLookupResult(
                word: currentWord,
                lookup: lookup,
                sourceText: currentContext,
                imageURLs: imageURLs.isEmpty ? nil : imageURLs,
                in: context
            )
        } catch {
            print("DEBUG: Failed to save vocabulary lookup result: \(error)")
        }
    }

    private func loadGoogleImages(
        for word: String,
        mode: VocabularyImageSearchMode,
        forceRefresh: Bool
    ) {
        let normalized = word.normalizedVocabularyWord
        guard !normalized.isEmpty else { return }

        if !forceRefresh {
            if let memCached = VocabularyImageCache.shared.get(word: word, mode: mode), !memCached.isEmpty {
                imageURLs = memCached
                return
            }
            if mode == .realPhoto,
               let existing = savedWords.first(where: { $0.normalizedWord == normalized }),
               !existing.imageURLs.isEmpty {
                imageURLs = existing.imageURLs
                VocabularyImageCache.shared.set(existing.imageURLs, word: word, mode: mode)
                return
            }
        }

        isLoadingImages = true
        Task {
            let fetched = (try? await VocabularyImageSearchService.shared.fetchImages(
                for: word,
                mode: mode,
                maxCount: 5
            )) ?? []

            await MainActor.run {
                guard currentWord.normalizedVocabularyWord == normalized,
                      imageSearchMode == mode else {
                    return
                }
                imageURLs = fetched
                isLoadingImages = false

                if !fetched.isEmpty {
                    VocabularyImageCache.shared.set(fetched, word: word, mode: mode)
                    VocabularyNoteStore.updateImageURLs(for: word, imageURLs: fetched, in: context)
                }
            }
        }
    }

    private func performLookup(for word: String, contextSentence: String?, forceRefresh: Bool) {
        errorMessage = nil

        if !forceRefresh,
           let existing = savedWords.first(where: { $0.normalizedWord == word.normalizedVocabularyWord }),
           let cached = existing.cachedLookupResponse,
           !(cached.chatTopics ?? []).isEmpty {
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

private struct VocabularyImageLightboxView: View {
    let word: String
    let meaning: String?
    let imageURLs: [String]
    let initialIndex: Int
    let googleImagesWebURL: URL?
    let onClose: () -> Void

    @State private var currentIndex: Int = 0
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { idx, urlString in
                    ZStack {
                        VocabularyRemoteImageView(urlString: urlString, contentMode: .fit)
                            .scaleEffect(currentIndex == idx ? zoomScale : 1.0)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = min(max(value, 1.0), 3.0)
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring()) {
                                            zoomScale = 1.0
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    zoomScale = zoomScale > 1.0 ? 1.0 : 2.0
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .onChange(of: currentIndex) { _, _ in
                zoomScale = 1.0
            }

            VStack {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word)
                            .font(.headline.bold())
                            .foregroundStyle(.white)

                        if let meaning, !meaning.isEmpty {
                            Text(meaning)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let googleImagesWebURL {
                        Link(destination: googleImagesWebURL) {
                            HStack(spacing: 4) {
                                Text("Mở Google")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.18))
                            .clipShape(Capsule())
                        }
                    }

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.22))
                            .clipShape(Circle())
                            .frame(width: 60, height: 60)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng xem ảnh")
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.top, 8)

                Spacer()

                Text("Ảnh \(currentIndex + 1) / \(imageURLs.count) • Chạm đúp để phóng to")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            currentIndex = min(max(initialIndex, 0), max(imageURLs.count - 1, 0))
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
