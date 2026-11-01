//
//  ChatMessageBubbles.swift
//  English Corrector
//

import SwiftUI
import UIKit

struct UserBubble: View {

    let id: UUID
    let text: String
    var imageData: Data? = nil
    var sceneForImage: AISceneDescriptionResponse? = nil
    var onSaveWord: ((AISceneObjectVocabularyItem) -> Void)? = nil
    var isWordSaved: ((String) -> Bool)? = nil
    var onUpdateScene: ((AISceneDescriptionResponse) -> Void)? = nil
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    let onCopy: () -> Void
    let onSaveVocabulary: (String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: () -> Void
    let onDelete: () -> Void

    @State private var showViewer = false

    var body: some View {
        let baseTarget = WordPickTarget(messageID: id, section: "message")

        HStack {

            Spacer(minLength: UIScreen.main.bounds.width * 0.25)

            VStack(alignment: .trailing, spacing: 6) {
                if isHighlightedMessage, let highlightedWord, !highlightedWord.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.bold))
                        Text("Từ vựng: \"\(highlightedWord)\"")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Accent.a500, lineWidth: 0.5)
                    }
                }

                if let imageData, let uiImage = UIImage(data: imageData) {
                    Button {
                        showViewer = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 220, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                                }

                            HStack(spacing: 4) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 9))
                                Text(sceneForImage?.objectsDetected.isEmpty == false
                                     ? "Từ vựng (\(sceneForImage!.objectsDetected.count))"
                                     : "Nhận diện item")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.Neutral.n900.opacity(0.8))
                            .clipShape(Capsule())
                            .padding(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .fullScreenCover(isPresented: $showViewer) {
                        InteractiveSceneImageViewerSheet(
                            image: uiImage,
                            scene: sceneForImage ?? AISceneDescriptionResponse(
                                sceneOverview: "Ảnh tải lên",
                                sceneVietnameseTranslation: "Ảnh tải lên",
                                objectsDetected: [],
                                situationalConversationalPhrases: [],
                                adviceOrCulturalNote: nil
                            ),
                            onSaveWord: onSaveWord,
                            isWordSaved: isWordSaved,
                            onUpdateScene: onUpdateScene
                        )
                    }
                }

                if !text.isEmpty {
                    Group {
                    if let activeTarget = pickingTarget, activeTarget.matchesSection(baseTarget) {
                        WordPickerText(
                            text: text,
                            mode: activeTarget.mode,
                            foregroundStyle: .white,
                            chipBackground: AppTheme.Primary.p700,
                            modeBackground: AppTheme.Primary.p700.opacity(0.38),
                            savedWords: savedWords,
                            onPick: onSaveVocabulary,
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            text,
                            targetWord: highlightedWord,
                            defaultColor: .white,
                            highlightColor: AppTheme.Semantic.warning
                        )
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .messageActions(
                            speakText: text,
                            onCopy: onCopy,
                            onPickWords: {
                                onStartPickingWords(WordPickTarget(messageID: id, section: "message", mode: .pickWord))
                            },
                            onLightPickWords: {
                                onStartPickingWords(WordPickTarget(messageID: id, section: "message", mode: .lightPickWord))
                            },
                            onFollowUp: onFollowUp,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.Primary.p500)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                            lineWidth: isHighlightedMessage ? 1.5 : 0.5
                        )
                }
                .shadow(
                    color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.35) : .clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
                }
            }
        }
    }
}

struct AIBubble: View {

    let messageID: UUID
    let original: String
    let fixed: String
    let natural: String
    var alternativeExpressions: [String] = []
    let explanations: [String]
    let explanationNoted: [String]
    let followUpQuestion: String?
    let suggestedReplies: [String]
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    let onSave: (String, Bool, String?) -> Void
    let onCopy: (String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: (String) -> Void
    let onDelete: () -> Void

    private func isSectionHighlighted(_ sectionText: String) -> Bool {
        guard isHighlightedMessage else { return false }
        let trimmedSection = sectionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedSection.isEmpty else { return false }

        if let source = highlightedSourceText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !source.isEmpty {
            if trimmedSection == source || trimmedSection.contains(source) || source.contains(trimmedSection) {
                return true
            }
        }

        if let word = highlightedWord?.normalizedVocabularyWord, !word.isEmpty {
            return sectionText
                .split(whereSeparator: \.isWhitespace)
                .contains { String($0).normalizedVocabularyWord == word }
        }

        return false
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 16) {

            if isHighlightedMessage {
                HStack(spacing: 6) {
                    if let highlightedWord, !highlightedWord.isEmpty {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.bold))
                        Text("Từ vựng đã lưu: \"\(highlightedWord)\"")
                            .font(.caption.weight(.bold))
                    } else {
                        Image(systemName: "note.text")
                            .font(.caption2.weight(.bold))
                        Text("Vị trí ghi chú đã lưu")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(AppTheme.Accent.a600)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.Accent.a50)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.Accent.a500, lineWidth: 0.5)
                }
            }

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 10) {
                    Label("Fixed", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Semantic.success)

                    Spacer()

                    SpeakButton(
                        text: fixed,
                        font: .caption,
                        activeColor: AppTheme.Semantic.success
                    )

                    Button {
                        onSave(fixed, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let fixedTarget = WordPickTarget(messageID: messageID, section: "fixed")
                let fixedHighlighted = isSectionHighlighted(fixed)

                Group {
                    if let activeTarget = pickingTarget, activeTarget.matchesSection(fixedTarget) {
                        WordPickerText(
                            text: fixed,
                            mode: activeTarget.mode,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, fixed)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        highlightedText(original: original, revised: fixed)
                            .font(.body)
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: fixed,
                                onCopy: {
                                    onCopy(fixed)
                                },
                                onPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "fixed", mode: .pickWord))
                                },
                                onLightPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "fixed", mode: .lightPickWord))
                                },
                                onFollowUp: {
                                    onFollowUp(fixed)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                    .padding(12)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                fixedHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                lineWidth: fixedHighlighted ? 1.5 : 0.5
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 10) {
                    Label("Natural", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    Spacer()

                    SpeakButton(
                        text: natural,
                        font: .caption,
                        activeColor: AppTheme.Primary.p500
                    )

                    Button {
                        onSave(natural, false, nil)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                }

                let naturalTarget = WordPickTarget(messageID: messageID, section: "natural")
                let naturalHighlighted = isSectionHighlighted(natural)

                Group {
                    if let activeTarget = pickingTarget, activeTarget.matchesSection(naturalTarget) {
                        WordPickerText(
                            text: natural,
                            mode: activeTarget.mode,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, natural)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            natural,
                            targetWord: highlightedWord,
                            defaultColor: AppTheme.Neutral.n900
                        )
                            .font(.body)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: natural,
                                onCopy: {
                                    onCopy(natural)
                                },
                                onPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "natural", mode: .pickWord))
                                },
                                onLightPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "natural", mode: .lightPickWord))
                                },
                                onFollowUp: {
                                    onFollowUp(natural)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                    .padding(12)
                    .background(AppTheme.Primary.p50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                naturalHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                lineWidth: naturalHighlighted ? 1.5 : 0.5
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            let validAlternatives = alternativeExpressions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !validAlternatives.isEmpty {
                alternativeExpressionsSection(validAlternatives)
            }

            if !explanations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Explanations")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Accent.a600)

                    ForEach(Array(explanations.enumerated()), id: \.offset) { index, item in
                        let noted = (index < explanationNoted.count) ? explanationNoted[index] : nil
                        let explanationTarget = WordPickTarget(messageID: messageID, section: "explanation-\(index)")
                        let expHighlighted = isSectionHighlighted(item)
                        HStack(alignment: .top, spacing: 8) {
                            Group {
                                if let activeTarget = pickingTarget, activeTarget.matchesSection(explanationTarget) {
                                    WordPickerText(
                                        text: item,
                                        mode: activeTarget.mode,
                                        foregroundStyle: AppTheme.Neutral.n700,
                                        chipBackground: AppTheme.Surface.cardMuted,
                                        modeBackground: AppTheme.Accent.a50,
                                        savedWords: savedWords,
                                        onPick: { word in
                                            onSaveVocabulary(word, item)
                                        },
                                        onDone: onStopPickingWords
                                    )
                                } else {
                                    (Text("• ") + explanationText(item, highlight: noted))
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.Neutral.n700)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .messageActions(
                                            speakText: item,
                                            onCopy: {
                                                onCopy(item)
                                            },
                                            onPickWords: {
                                                onStartPickingWords(WordPickTarget(messageID: messageID, section: "explanation-\(index)", mode: .pickWord))
                                            },
                                            onLightPickWords: {
                                                onStartPickingWords(WordPickTarget(messageID: messageID, section: "explanation-\(index)", mode: .lightPickWord))
                                            },
                                            onFollowUp: {
                                                onFollowUp(item)
                                            },
                                            onDelete: onDelete
                                        )
                                }
                            }
                            .layoutPriority(1)

                            Button {
                                onSave(item, true, noted)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }
                        .padding(expHighlighted ? 8 : 0)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(expHighlighted ? AppTheme.Accent.a50 : Color.clear)
                        )
                        .overlay {
                            if expHighlighted {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(AppTheme.Accent.a500, lineWidth: 0.5)
                            }
                        }
                    }
                }
            }

            // KEEP CHATTING: FOLLOW-UP QUESTION & SUGGESTED REPLIES
            let trimmedQuestion = followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let validReplies = suggestedReplies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !trimmedQuestion.isEmpty || !validReplies.isEmpty {
                Divider()
                    .overlay(AppTheme.Surface.border)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Label("Keep Chatting", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.Primary.p500)

                        Spacer()

                        if !trimmedQuestion.isEmpty {
                            SpeakButton(
                                text: trimmedQuestion,
                                font: .caption,
                                activeColor: AppTheme.Primary.p500
                            )

                            Button {
                                onSave(trimmedQuestion, false, nil)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }
                        }
                    }

                    if !trimmedQuestion.isEmpty {
                        let followUpTarget = WordPickTarget(messageID: messageID, section: "followUp")
                        let questionHighlighted = isSectionHighlighted(trimmedQuestion)

                        Group {
                            if let activeTarget = pickingTarget, activeTarget.matchesSection(followUpTarget) {
                                WordPickerText(
                                    text: trimmedQuestion,
                                    mode: activeTarget.mode,
                                    foregroundStyle: AppTheme.Neutral.n900,
                                    chipBackground: AppTheme.Surface.card,
                                    modeBackground: AppTheme.Accent.a50,
                                    savedWords: savedWords,
                                    onPick: { word in
                                        onSaveVocabulary(word, trimmedQuestion)
                                    },
                                    onDone: onStopPickingWords
                                )
                            } else {
                                vocabularyHighlightedText(
                                    trimmedQuestion,
                                    targetWord: highlightedWord,
                                    defaultColor: AppTheme.Neutral.n900
                                )
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .messageActions(
                                        speakText: trimmedQuestion,
                                        onCopy: {
                                            onCopy(trimmedQuestion)
                                        },
                                        onPickWords: {
                                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "followUp", mode: .pickWord))
                                        },
                                        onLightPickWords: {
                                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "followUp", mode: .lightPickWord))
                                        },
                                        onFollowUp: {
                                            onFollowUp(trimmedQuestion)
                                        },
                                        onDelete: onDelete
                                    )
                            }
                        }
                        .padding(12)
                        .background(AppTheme.Accent.a50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    questionHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                    lineWidth: questionHighlighted ? 1.5 : 0.5
                                )
                        }
                    }

                    if !validReplies.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested replies (tap to edit & send):")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.Neutral.n500)

                            ForEach(Array(validReplies.enumerated()), id: \.offset) { index, reply in
                                let replyTarget = WordPickTarget(messageID: messageID, section: "reply-\(index)")
                                let replyHighlighted = isSectionHighlighted(reply)

                                if let activeTarget = pickingTarget, activeTarget.matchesSection(replyTarget) {
                                    WordPickerText(
                                        text: reply,
                                        mode: activeTarget.mode,
                                        foregroundStyle: AppTheme.Neutral.n900,
                                        chipBackground: AppTheme.Surface.card,
                                        modeBackground: AppTheme.Accent.a50,
                                        savedWords: savedWords,
                                        onPick: { word in
                                            onSaveVocabulary(word, reply)
                                        },
                                        onDone: onStopPickingWords
                                    )
                                } else {
                                    HStack(alignment: .center, spacing: 8) {
                                        Button {
                                            onFollowUp(reply)
                                        } label: {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "arrow.turn.down.right")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(AppTheme.Primary.p500)
                                                    .padding(.top, 2)

                                                vocabularyHighlightedText(
                                                    reply,
                                                    targetWord: highlightedWord,
                                                    defaultColor: AppTheme.Neutral.n900
                                                )
                                                    .font(.subheadline)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        SpeakButton(
                                            text: reply,
                                            font: .caption,
                                            activeColor: AppTheme.Primary.p500
                                        )
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.Surface.cardMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                replyHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                                lineWidth: replyHighlighted ? 1.5 : 0.5
                                            )
                                    }
                                    .messageActions(
                                        speakText: reply,
                                        onCopy: {
                                            onCopy(reply)
                                        },
                                        onPickWords: {
                                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "reply-\(index)", mode: .pickWord))
                                        },
                                        onLightPickWords: {
                                            onStartPickingWords(WordPickTarget(messageID: messageID, section: "reply-\(index)", mode: .lightPickWord))
                                        },
                                        onFollowUp: {
                                            onFollowUp(reply)
                                        },
                                        onDelete: onDelete
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                    lineWidth: isHighlightedMessage ? 1.5 : 0.5
                )
        }
        .shadow(
            color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.28) : AppTheme.Shadow.card,
            radius: 12,
            x: 0,
            y: 6
        )
    }

    @ViewBuilder
    private func alternativeExpressionsSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cách nói khác (Other ways to say)", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.Accent.a600)

            ForEach(Array(items.enumerated()), id: \.offset) { index, alt in
                alternativeExpressionRow(index: index, text: alt)
            }
        }
    }

    @ViewBuilder
    private func alternativeExpressionRow(index: Int, text: String) -> some View {
        let baseTarget = WordPickTarget(messageID: messageID, section: "alt-\(index)")
        let activeMode: WordInteractionMode? = (pickingTarget?.matchesSection(baseTarget) == true) ? pickingTarget?.mode : nil
        let isAltHighlighted = isSectionHighlighted(text)

        if let activeMode {
            WordPickerText(
                text: text,
                mode: activeMode,
                foregroundStyle: AppTheme.Neutral.n900,
                chipBackground: AppTheme.Surface.card,
                modeBackground: AppTheme.Accent.a50,
                savedWords: savedWords,
                onPick: { word in
                    onSaveVocabulary(word, text)
                },
                onDone: onStopPickingWords
            )
        } else {
            HStack(alignment: .center, spacing: 8) {
                vocabularyHighlightedText(
                    text,
                    targetWord: highlightedWord,
                    defaultColor: AppTheme.Neutral.n900
                )
                .font(.subheadline.weight(.medium))
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)

                SpeakButton(
                    text: text,
                    font: .caption,
                    activeColor: AppTheme.Accent.a600
                )

                Button {
                    onSave(text, false, nil)
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.Accent.a50.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isAltHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                        lineWidth: isAltHighlighted ? 1.5 : 0.5
                    )
            }
            .messageActions(
                speakText: text,
                onCopy: {
                    onCopy(text)
                },
                onPickWords: {
                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "alt-\(index)", mode: .pickWord))
                },
                onLightPickWords: {
                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "alt-\(index)", mode: .lightPickWord))
                },
                onFollowUp: {
                    onFollowUp(text)
                },
                onDelete: onDelete
            )
        }
    }

    private func explanationText(_ text: String, highlight: String? = nil) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var resultText = Text("")

        let highlightKeywords = ["formal", "suitable", "natural", "better", "correct", "native", "instead", "grammar", "mistake"]
        let targetVocab = highlightedWord?.normalizedVocabularyWord ?? ""

        // Prepare specific highlight words if provided
        let specificHighlights = highlight?.lowercased().split(separator: " ").map(String.init) ?? []

        // Combine punctuation and quotes into a single CharacterSet
        var trimSet = CharacterSet.punctuationCharacters
        trimSet.insert(charactersIn: "'\"")

        for word in words {
            let cleanWord = word.lowercased().trimmingCharacters(in: trimSet)
            let inQuotes = word.contains("'") || word.contains("\"")

            let isTargetVocab = !targetVocab.isEmpty && word.normalizedVocabularyWord == targetVocab
            let isSpecificHighlight = specificHighlights.contains(cleanWord)
            let isGeneralKeyword = highlightKeywords.contains(cleanWord)

            if isTargetVocab {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Accent.a600)
                    .fontWeight(.heavy)
                    .underline(true, color: AppTheme.Accent.a600)
            } else if inQuotes || isSpecificHighlight || isGeneralKeyword {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Semantic.success)
                    .fontWeight(.bold)
            } else {
                resultText = resultText + Text(word + " ")
            }
        }

        return resultText
    }

    private func highlightedText(original: String, revised: String) -> Text {
        let originalWords = original.lowercased().split(separator: " ").map(String.init)
        let revisedWords = revised.split(separator: " ").map(String.init)
        let targetVocab = highlightedWord?.normalizedVocabularyWord ?? ""

        var resultText = Text("")

        for word in revisedWords {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let isTargetVocab = !targetVocab.isEmpty && word.normalizedVocabularyWord == targetVocab
            let isChanged = !originalWords.contains(cleanWord)

            if isTargetVocab {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Accent.a600)
                    .fontWeight(.heavy)
                    .underline(true, color: AppTheme.Accent.a600)
            } else if isChanged {
                resultText = resultText + Text(word + " ")
                    .foregroundColor(AppTheme.Semantic.success)
                    .fontWeight(.bold)
            } else {
                resultText = resultText + Text(word + " ")
            }
        }

        return resultText
    }
}

struct StarterAIBubble: View {

    let messageID: UUID
    let text: String
    let suggestedReplies: [String]
    let pickingTarget: WordPickTarget?
    let savedWords: Set<String>
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    let onCopy: (String) -> Void
    let onSaveVocabulary: (String, String) -> Void
    let onStartPickingWords: (WordPickTarget) -> Void
    let onStopPickingWords: () -> Void
    let onFollowUp: (String) -> Void
    let onDelete: () -> Void

    private var validReplies: [String] {
        suggestedReplies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let target = WordPickTarget(messageID: messageID, section: "message")

        HStack {
            VStack(alignment: .leading, spacing: 12) {
                if isHighlightedMessage, let highlightedWord, !highlightedWord.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.bold))
                        Text("Từ vựng đã lưu: \"\(highlightedWord)\"")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.Accent.a600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Accent.a50)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Accent.a500, lineWidth: 0.5)
                    }
                }

                HStack(spacing: 10) {
                    Label("AI Coach", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)

                    Spacer()

                    SpeakButton(
                        text: text,
                        font: .caption,
                        activeColor: AppTheme.Primary.p500
                    )
                }

                Group {
                    if let activeTarget = pickingTarget, activeTarget.matchesSection(target) {
                        WordPickerText(
                            text: text,
                            mode: activeTarget.mode,
                            foregroundStyle: AppTheme.Neutral.n900,
                            chipBackground: AppTheme.Surface.card,
                            modeBackground: AppTheme.Accent.a50,
                            savedWords: savedWords,
                            onPick: { word in
                                onSaveVocabulary(word, text)
                            },
                            onDone: onStopPickingWords
                        )
                    } else {
                        vocabularyHighlightedText(
                            text,
                            targetWord: highlightedWord,
                            defaultColor: AppTheme.Neutral.n900
                        )
                            .font(.subheadline.weight(.medium))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .messageActions(
                                speakText: text,
                                onCopy: {
                                    onCopy(text)
                                },
                                onPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "message", mode: .pickWord))
                                },
                                onLightPickWords: {
                                    onStartPickingWords(WordPickTarget(messageID: messageID, section: "message", mode: .lightPickWord))
                                },
                                onFollowUp: {
                                    onFollowUp(text)
                                },
                                onDelete: onDelete
                            )
                    }
                }
                .padding(12)
                .background(AppTheme.Accent.a50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                }

                if !validReplies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested replies (tap to edit & send):")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.Neutral.n500)

                        ForEach(Array(validReplies.enumerated()), id: \.offset) { index, reply in
                            let replyTarget = WordPickTarget(messageID: messageID, section: "starter-reply-\(index)")

                            if let activeTarget = pickingTarget, activeTarget.matchesSection(replyTarget) {
                                WordPickerText(
                                    text: reply,
                                    mode: activeTarget.mode,
                                    foregroundStyle: AppTheme.Neutral.n900,
                                    chipBackground: AppTheme.Surface.card,
                                    modeBackground: AppTheme.Accent.a50,
                                    savedWords: savedWords,
                                    onPick: { word in
                                        onSaveVocabulary(word, reply)
                                    },
                                    onDone: onStopPickingWords
                                )
                            } else {
                                HStack(alignment: .center, spacing: 8) {
                                    Button {
                                        onFollowUp(reply)
                                    } label: {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "arrow.turn.down.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AppTheme.Primary.p500)
                                                .padding(.top, 2)

                                            vocabularyHighlightedText(
                                                reply,
                                                targetWord: highlightedWord,
                                                defaultColor: AppTheme.Neutral.n900
                                            )
                                                .font(.subheadline)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    SpeakButton(
                                        text: reply,
                                        font: .caption,
                                        activeColor: AppTheme.Primary.p500
                                    )
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.Surface.cardMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                                }
                                .messageActions(
                                    speakText: reply,
                                    onCopy: {
                                        onCopy(reply)
                                    },
                                    onPickWords: {
                                        onStartPickingWords(WordPickTarget(messageID: messageID, section: "starter-reply-\(index)", mode: .pickWord))
                                    },
                                    onLightPickWords: {
                                        onStartPickingWords(WordPickTarget(messageID: messageID, section: "starter-reply-\(index)", mode: .lightPickWord))
                                    },
                                    onFollowUp: {
                                        onFollowUp(reply)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isHighlightedMessage ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                        lineWidth: isHighlightedMessage ? 1.5 : 0.5
                    )
            }
            .shadow(
                color: isHighlightedMessage ? AppTheme.Accent.a500.opacity(0.28) : AppTheme.Shadow.card,
                radius: 10,
                x: 0,
                y: 4
            )

            Spacer(minLength: 10)
        }
    }
}

struct MessageActionsModifier: ViewModifier {
    let speakText: String?
    let onCopy: () -> Void
    let onPickWords: (() -> Void)?
    let onLightPickWords: (() -> Void)?
    let onFollowUp: () -> Void
    let onDelete: (() -> Void)?

    @State private var showLightAnalysis = false

    private var trimmedSpeakText: String {
        speakText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !trimmedSpeakText.isEmpty {
                    Button {
                        SpeechSynthesizerManager.shared.toggleSpeak(trimmedSpeakText)
                    } label: {
                        Label("Speak", systemImage: "speaker.wave.2.fill")
                    }
                }

                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if let onPickWords {
                    Button {
                        onPickWords()
                    } label: {
                        Label("Pick word", systemImage: "hand.tap")
                    }
                }

                if let onLightPickWords {
                    Button {
                        onLightPickWords()
                    } label: {
                        Label("Light pick word", systemImage: "character.book.closed.fill")
                    }
                }

                if !trimmedSpeakText.isEmpty {
                    Button {
                        showLightAnalysis = true
                    } label: {
                        Label("Light analysis", systemImage: "sparkles.rectangle.stack.fill")
                    }

                    Button {
                        StructureNavigationCoordinator.shared.openAndAnalyze(trimmedSpeakText)
                    } label: {
                        Label("Phân tích cấu trúc", systemImage: "rectangle.3.group.fill")
                    }
                }

                Button {
                    onFollowUp()
                } label: {
                    Label("Follow up", systemImage: "arrowshape.turn.up.left")
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Xoá", systemImage: "trash")
                    }
                }
            }
            .popover(
                isPresented: $showLightAnalysis,
                attachmentAnchor: .rect(.bounds)
            ) {
                QuickSentenceAnalysisPopoverView(
                    sentence: trimmedSpeakText,
                    onOpenFullAnalysis: {
                        showLightAnalysis = false
                        StructureNavigationCoordinator.shared.openAndAnalyze(trimmedSpeakText)
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
    }
}

extension View {

    func messageActions(
        speakText: String? = nil,
        onCopy: @escaping () -> Void,
        onPickWords: (() -> Void)? = nil,
        onLightPickWords: (() -> Void)? = nil,
        onFollowUp: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(
            MessageActionsModifier(
                speakText: speakText,
                onCopy: onCopy,
                onPickWords: onPickWords,
                onLightPickWords: onLightPickWords,
                onFollowUp: onFollowUp,
                onDelete: onDelete
            )
        )
    }
}
