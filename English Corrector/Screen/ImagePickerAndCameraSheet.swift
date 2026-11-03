//
//  ImagePickerAndCameraSheet.swift
//  English Corrector
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

// MARK: - Camera Permission Helper

final class CameraPermissionHelper {
    enum CameraStatus {
        case available
        case notAvailable
        case permissionDenied
        case needsPermission
    }

    static func checkStatus() -> CameraStatus {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .notAvailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .available
        case .notDetermined:
            return .needsPermission
        case .denied, .restricted:
            return .permissionDenied
        @unknown default:
            return .permissionDenied
        }
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

// MARK: - Camera Picker View (Real-Time AR Scanner Camera)

struct CameraPickerView: View {
    @Binding var selectedImage: UIImage?
    var isPresented: Binding<Bool>?

    init(selectedImage: Binding<UIImage?>, isPresented: Binding<Bool>? = nil) {
        self._selectedImage = selectedImage
        self.isPresented = isPresented
    }

    var body: some View {
        RealTimeARScannerCameraView(selectedImage: $selectedImage, isPresented: isPresented)
    }
}

// MARK: - Input Bar Image Preview

struct InputBarImagePreviewView: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "camera.viewfinder")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                    Text("Ảnh mô tả cảnh vật")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                }

                Text("AI sẽ bóc tách từ vựng & câu giao tiếp từ ảnh này")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n500)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.Neutral.n400)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Primary.p300, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Scene Description Card View (Reusable in Ask AI & Chat)

struct SceneDescriptionCardView: View {
    let scene: AISceneDescriptionResponse
    var imageData: Data? = nil
    var onUpdateScene: ((AISceneDescriptionResponse) -> Void)? = nil
    let onSaveWord: ((AISceneObjectVocabularyItem) -> Void)?
    var isWordSaved: ((String) -> Bool)? = nil
    var messageID: UUID? = nil
    var pickingTarget: WordPickTarget? = nil
    var savedWords: Set<String> = []
    var isHighlightedMessage: Bool = false
    var highlightedWord: String? = nil
    var highlightedSourceText: String? = nil
    var onSaveNote: ((String, Bool, String?) -> Void)? = nil
    var onCopy: ((String) -> Void)? = nil
    var onSaveVocabulary: ((String, String) -> Void)? = nil
    var onStartPickingWords: ((WordPickTarget) -> Void)? = nil
    var onStopPickingWords: (() -> Void)? = nil
    var onFollowUp: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showInteractiveViewer = false
    @State private var detailedObjectItem: AISceneObjectVocabularyItem? = nil

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
        VStack(alignment: .leading, spacing: 14) {
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

            headerSection

            if let imageData, let uiImage = UIImage(data: imageData) {
                photoBannerSection(uiImage: uiImage)
            }

            overviewSection

            if !scene.objectsDetected.isEmpty {
                objectsSection
            } else if imageData != nil {
                detectItemsQuickButton
            }

            if !scene.situationalConversationalPhrases.isEmpty {
                phrasesSection
            }

            if let note = scene.adviceOrCulturalNote, !note.isEmpty {
                adviceSection(note)
            }

            if let onFollowUp {
                quickFollowUpSection(onFollowUp: onFollowUp)
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
        }
        .sheet(item: $detailedObjectItem) { targetItem in
            CroppedObjectDetailSheet(
                item: targetItem,
                objectImage: (imageData != nil && UIImage(data: imageData!) != nil) ? cropImageFromFull(image: UIImage(data: imageData!)!, item: targetItem) : nil,
                fullImage: imageData.flatMap { UIImage(data: $0) },
                isSaved: isWordSaved?(targetItem.word) ?? false,
                onSaveWord: onSaveWord
            )
        }
    }

    // MARK: - Subviews

    private var detectItemsQuickButton: some View {
        Button {
            showInteractiveViewer = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Accent.a500.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Accent.a600)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhận diện item trong ảnh")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.Neutral.n900)
                    Text("Bấm để khám phá từ vựng theo vị trí các vật thể")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Neutral.n500)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Mở ảnh")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Primary.p500)
                }
            }
            .padding(10)
            .background(AppTheme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppTheme.Accent.a500.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func photoBannerSection(uiImage: UIImage) -> some View {
        Button {
            showInteractiveViewer = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
                    }

                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text(scene.objectsDetected.isEmpty
                         ? "Nhận diện item trong ảnh"
                         : "Xem từ vựng theo đồ vật (\(scene.objectsDetected.count))")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.Neutral.n900.opacity(0.85))
                .clipShape(Capsule())
                .padding(10)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showInteractiveViewer) {
            InteractiveSceneImageViewerSheet(
                image: uiImage,
                scene: scene,
                onSaveWord: onSaveWord,
                isWordSaved: isWordSaved,
                onUpdateScene: onUpdateScene
            )
        }
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(AppTheme.Primary.p50)
                    .frame(width: 32, height: 32)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Primary.p500)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Phân tích cảnh vật từ ảnh")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.Neutral.n900)
                Text("Scene & Vocabulary Discovery")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }

            Spacer()
        }
    }

    private var overviewSection: some View {
        let baseTarget = messageID.map { WordPickTarget(messageID: $0, section: "scene-overview") }
        let isHighlighted = isSectionHighlighted(scene.sceneOverview)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Mô tả cảnh vật", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.Primary.p500)

                Spacer()

                SpeakButton(
                    text: scene.sceneOverview,
                    font: .caption,
                    activeColor: AppTheme.Primary.p500
                )

                if let onSaveNote {
                    Button {
                        onSaveNote(scene.sceneOverview, false, scene.sceneVietnameseTranslation)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n500)
                    }
                    .buttonStyle(.plain)
                }

                if let onFollowUp {
                    Button {
                        onFollowUp("Giải thích chi tiết hơn về bức ảnh và mô tả này: \"\(scene.sceneOverview)\"")
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Primary.p500)
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                if let activeTarget = pickingTarget, let base = baseTarget, activeTarget.matchesSection(base) {
                    WordPickerText(
                        text: scene.sceneOverview,
                        mode: activeTarget.mode,
                        foregroundStyle: AppTheme.Neutral.n900,
                        chipBackground: AppTheme.Surface.card,
                        modeBackground: AppTheme.Accent.a50,
                        savedWords: savedWords,
                        onPick: { word in
                            onSaveVocabulary?(word, scene.sceneOverview)
                        },
                        onDone: {
                            onStopPickingWords?()
                        }
                    )
                } else {
                    vocabularyHighlightedText(
                        scene.sceneOverview,
                        targetWord: highlightedWord,
                        defaultColor: AppTheme.Neutral.n900
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .messageActions(
                        speakText: scene.sceneOverview,
                        onCopy: {
                            onCopy?(scene.sceneOverview)
                        },
                        onPickWords: {
                            if let messageID {
                                onStartPickingWords?(WordPickTarget(messageID: messageID, section: "scene-overview", mode: .pickWord))
                            }
                        },
                        onLightPickWords: {
                            if let messageID {
                                onStartPickingWords?(WordPickTarget(messageID: messageID, section: "scene-overview", mode: .lightPickWord))
                            }
                        },
                        onFollowUp: {
                            onFollowUp?(scene.sceneOverview)
                        },
                        onDelete: onDelete
                    )
                }
            }

            if !scene.sceneVietnameseTranslation.isEmpty {
                Text(scene.sceneVietnameseTranslation)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Neutral.n700)
            }
        }
        .padding(12)
        .background(AppTheme.Primary.p50.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHighlighted ? AppTheme.Accent.a500 : AppTheme.Primary.p300,
                    lineWidth: isHighlighted ? 1.5 : 0.5
                )
        }
    }

    private var objectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Từ vựng các đồ vật trong ảnh:", systemImage: "sparkles")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.Neutral.n500)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(scene.objectsDetected) { item in
                    objectItemRow(item)
                }
            }
        }
    }

    private func cropImageFromFull(image: UIImage, item: AISceneObjectVocabularyItem) -> UIImage? {
        let normalizedImage: UIImage
        if image.imageOrientation == .up {
            normalizedImage = image
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            normalizedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        guard let cgImage = normalizedImage.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        if let box = item.box2d, box.count >= 4 {
            let norm = { (v: Double) -> CGFloat in
                if v > 100.0 { return CGFloat(max(0.0, min(1.0, v / 1000.0))) }
                if v <= 1.0 && v > 0.0 { return CGFloat(max(0.0, min(1.0, v))) }
                return CGFloat(max(0.0, min(1.0, v / 100.0)))
            }
            let minY = norm(box[0])
            let minX = norm(box[1])
            let maxY = norm(box[2])
            let maxX = norm(box[3])
            let w = max(0.04, maxX - minX)
            let h = max(0.04, maxY - minY)
            let padX = w * 0.14
            let padTop = h * 0.14
            let padBottom = h * 0.18
            let pMinX = max(0.0, minX - padX)
            let pMinY = max(0.0, minY - padTop)
            let pMaxX = min(1.0, maxX + padX)
            let pMaxY = min(1.0, maxY + padBottom)
            let cropRect = CGRect(
                x: pMinX * imgW,
                y: pMinY * imgH,
                width: max(20, (pMaxX - pMinX) * imgW),
                height: max(20, (pMaxY - pMinY) * imgH)
            ).integral
            if let croppedCg = cgImage.cropping(to: cropRect) {
                return UIImage(cgImage: croppedCg)
            }
        }

        let boxW = min(imgW, max(60, imgW * 0.35))
        let boxH = min(imgH, max(60, imgH * 0.35))
        let rawX = CGFloat(item.xPercent ?? 50.0) / 100.0
        let rawY = CGFloat(item.yPercent ?? 50.0) / 100.0
        let originX = max(0, min(imgW - boxW, rawX * imgW - boxW / 2.0))
        let originY = max(0, min(imgH - boxH, rawY * imgH - boxH / 2.0))
        let cropRect = CGRect(x: originX, y: originY, width: boxW, height: boxH).integral
        if let croppedCg = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCg)
        }
        return nil
    }

    private func objectItemRow(_ item: AISceneObjectVocabularyItem) -> some View {
        let isSaved = isWordSaved?(item.word) ?? false

        return HStack(alignment: .center, spacing: 8) {
            Button {
                detailedObjectItem = item
            } label: {
                HStack(spacing: 8) {
                    if let imageData, let fullImg = UIImage(data: imageData), let thumb = cropImageFromFull(image: fullImg, item: item) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(AppTheme.Semantic.warning.opacity(0.8), lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.word)
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Neutral.n900)

                            if !item.phonetic.isEmpty {
                                Text(item.phonetic)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n500)
                            }

                            Text(item.partOfSpeech)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.Accent.a600)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppTheme.Accent.a50)
                                .clipShape(Capsule())
                        }

                        Text(item.vietnameseMeaning)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Neutral.n700)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                detailedObjectItem = item
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppTheme.Neutral.n500)
            }
            .buttonStyle(.plain)

            SpeakButton(
                text: item.word,
                font: .caption,
                activeColor: AppTheme.Primary.p500
            )

            if let onSaveWord {
                Button {
                    onSaveWord(item)
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.caption)
                        .foregroundStyle(isSaved ? AppTheme.Primary.p500 : AppTheme.Neutral.n400)
                        .padding(6)
                        .background(isSaved ? AppTheme.Primary.p50 : AppTheme.Surface.cardMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(AppTheme.Surface.cardMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
        }
        .contextMenu {
            Button {
                detailedObjectItem = item
            } label: {
                Label("Xem chi tiết", systemImage: "magnifyingglass")
            }

            Button {
                onCopy?(item.word)
            } label: {
                Label("Sao chép từ", systemImage: "doc.on.doc")
            }

            if !item.exampleInContext.isEmpty {
                Button {
                    StructureNavigationCoordinator.shared.openAndAnalyze(item.exampleInContext)
                } label: {
                    Label("Phân tích câu ví dụ", systemImage: "rectangle.3.group.fill")
                }
            }

            if let onFollowUp {
                Button {
                    onFollowUp("Giải thích thêm về từ '\(item.word)' và cách dùng trong ngữ cảnh ảnh này.")
                } label: {
                    Label("Hỏi thêm AI về từ này", systemImage: "arrowshape.turn.up.left")
                }
            }
        }
    }

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mẫu câu giao tiếp trong hoàn cảnh này:", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.Primary.p500)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(Array(scene.situationalConversationalPhrases.enumerated()), id: \.offset) { index, phrase in
                    let baseTarget = messageID.map { WordPickTarget(messageID: $0, section: "scene-phrase-\(index)") }
                    let isHighlighted = isSectionHighlighted(phrase)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Cách nói \(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.Primary.p500)

                            Spacer()

                            SpeakButton(
                                text: phrase,
                                font: .caption,
                                activeColor: AppTheme.Primary.p500
                            )

                            if let onSaveNote {
                                Button {
                                    onSaveNote(phrase, false, "Mẫu câu giao tiếp theo ngữ cảnh ảnh")
                                } label: {
                                    Image(systemName: "plus.square.on.square")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Neutral.n500)
                                }
                                .buttonStyle(.plain)
                            }

                            if let onFollowUp {
                                Button {
                                    onFollowUp("Giải thích cách dùng và tình huống thực tế của câu: \"\(phrase)\"")
                                } label: {
                                    Image(systemName: "arrowshape.turn.up.left")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Primary.p500)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Group {
                            if let activeTarget = pickingTarget, let base = baseTarget, activeTarget.matchesSection(base) {
                                WordPickerText(
                                    text: phrase,
                                    mode: activeTarget.mode,
                                    foregroundStyle: AppTheme.Neutral.n900,
                                    chipBackground: AppTheme.Surface.card,
                                    modeBackground: AppTheme.Accent.a50,
                                    savedWords: savedWords,
                                    onPick: { word in
                                        onSaveVocabulary?(word, phrase)
                                    },
                                    onDone: {
                                        onStopPickingWords?()
                                    }
                                )
                            } else {
                                vocabularyHighlightedText(
                                    phrase,
                                    targetWord: highlightedWord,
                                    defaultColor: AppTheme.Neutral.n900
                                )
                                .font(.subheadline)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .messageActions(
                                    speakText: phrase,
                                    onCopy: {
                                        onCopy?(phrase)
                                    },
                                    onPickWords: {
                                        if let messageID {
                                            onStartPickingWords?(WordPickTarget(messageID: messageID, section: "scene-phrase-\(index)", mode: .pickWord))
                                        }
                                    },
                                    onLightPickWords: {
                                        if let messageID {
                                            onStartPickingWords?(WordPickTarget(messageID: messageID, section: "scene-phrase-\(index)", mode: .lightPickWord))
                                        }
                                    },
                                    onFollowUp: {
                                        onFollowUp?(phrase)
                                    },
                                    onDelete: onDelete
                                )
                            }
                        }
                    }
                    .padding(10)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isHighlighted ? AppTheme.Accent.a500 : AppTheme.Surface.border,
                                lineWidth: isHighlighted ? 1.5 : 0.5
                            )
                    }
                }
            }
        }
    }

    private func adviceSection(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.Accent.a600)
                .padding(.top, 2)

            Text(note)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n700)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = note
                    } label: {
                        Label("Sao chép lời khuyên", systemImage: "doc.on.doc")
                    }

                    if let onFollowUp {
                        Button {
                            onFollowUp("Giải thích thêm về lưu ý văn hóa này: \"\(note)\"")
                        } label: {
                            Label("Hỏi thêm AI", systemImage: "arrowshape.turn.up.left")
                        }
                    }
                }
        }
        .padding(10)
        .background(AppTheme.Accent.a50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.Accent.a500.opacity(0.3), lineWidth: 0.5)
        }
    }

    private func quickFollowUpSection(onFollowUp: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Gợi ý hỏi tiếp AI:", systemImage: "sparkles")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.Neutral.n500)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        onFollowUp("Gợi ý thêm 3 câu giao tiếp tự nhiên về hoàn cảnh trong ảnh này.")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.bubble.fill")
                                .font(.caption2)
                            Text("Gợi ý thêm câu nói")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(AppTheme.Primary.p500)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Primary.p50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onFollowUp("Dịch và phân tích các cấu trúc ngữ pháp dùng trong mô tả ảnh này.")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.caption2)
                            Text("Phân tích ngữ pháp mô tả")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(AppTheme.Accent.a600)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Accent.a50)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Interactive Scene Image Viewer Sheet

struct InteractiveSceneImageViewerSheet: View {
    let image: UIImage
    let scene: AISceneDescriptionResponse
    let onSaveWord: ((AISceneObjectVocabularyItem) -> Void)?
    var isWordSaved: ((String) -> Bool)? = nil
    var onUpdateScene: ((AISceneDescriptionResponse) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var currentScene: AISceneDescriptionResponse
    @State private var selectedObject: AISceneObjectVocabularyItem?
    @State private var showAllLabels: Bool = true
    @State private var pulse: Bool = false

    // Long-Press AI Object Detection States
    @State private var isDetectingObject: Bool = false
    @State private var isScanningAllItems: Bool = false
    @State private var detectingPoint: CGPoint? = nil
    @State private var hasTriggeredLongPress: Bool = false
    @State private var activeLiftedCrop: LiftedCropState? = nil
    @State private var objectThumbnails: [String: UIImage] = [:]
    @State private var detailedObjectItem: AISceneObjectVocabularyItem? = nil
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    // Zoom, Pan & Interactive Dismiss States
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dismissDragOffsetY: CGFloat = 0

    // Lasso / Swiping Gesture States for Object Cutoff
    @State private var isLassoModeEnabled: Bool = false
    @State private var lassoPoints: [CGPoint] = []
    @State private var isDrawingLasso: Bool = false
    @State private var longPressDetectionTask: Task<Void, Never>? = nil

    init(
        image: UIImage,
        scene: AISceneDescriptionResponse,
        onSaveWord: ((AISceneObjectVocabularyItem) -> Void)?,
        isWordSaved: ((String) -> Bool)? = nil,
        onUpdateScene: ((AISceneDescriptionResponse) -> Void)? = nil
    ) {
        self.image = image
        self.scene = scene
        self.onSaveWord = onSaveWord
        self.isWordSaved = isWordSaved
        self.onUpdateScene = onUpdateScene
        self._currentScene = State(initialValue: scene)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black
                    .opacity(max(0.3, 1.0 - Double(dismissDragOffsetY / 450.0)))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    canvasArea

                    bottomArea
                }
                .offset(y: max(0, dismissDragOffsetY))
                .scaleEffect(max(0.88, 1.0 - (dismissDragOffsetY / 1500.0)))

                if let message = toastMessage {
                    toastBannerView(message: message)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(200)
                }
            }
            .navigationTitle("Khám phá từ vựng theo đồ vật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    toggleLabelsButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
            .sheet(item: $detailedObjectItem) { targetItem in
                CroppedObjectDetailSheet(
                    item: targetItem,
                    objectImage: objectThumbnails[targetItem.id] ?? cropImage(for: targetItem),
                    fullImage: image,
                    isSaved: isWordSaved?(targetItem.word) ?? false,
                    onSaveWord: onSaveWord
                )
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
                if selectedObject == nil, let first = currentScene.objectsDetected.first {
                    selectedObject = first
                }
            }
        }
    }

    private var toggleLabelsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAllLabels.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showAllLabels ? "eye.fill" : "eye.slash.fill")
                    .font(.caption)
                Text(showAllLabels ? "Ẩn nhãn" : "Hiện tất cả nhãn")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let fittedRect = calculateFittedRect(imageSize: image.size, containerSize: geometry.size)

            ZStack {
                Color.clear

                // Zoomable & Pannable Canvas Content (Image + Pins + Arrows + Badges + Detecting Radar)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    guard isLassoModeEnabled else {
                                        // Normal Mode: Touch & hold handles radar long press detection
                                        if lassoPoints.isEmpty {
                                            longPressDetectionTask?.cancel()
                                            let startLoc = value.startLocation
                                            longPressDetectionTask = Task {
                                                try? await Task.sleep(nanoseconds: 350_000_000)
                                                guard !Task.isCancelled else { return }
                                                await MainActor.run {
                                                    if !hasTriggeredLongPress && !isDetectingObject {
                                                        hasTriggeredLongPress = true
                                                        handleLongPress(at: startLoc, in: fittedRect.size)
                                                    }
                                                }
                                            }
                                        }
                                        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                                        if dist > 10 {
                                            longPressDetectionTask?.cancel()
                                        }
                                        return
                                    }

                                    // Lasso Mode: Draw glowing laser line to circle and cut out items
                                    if !isDrawingLasso {
                                        isDrawingLasso = true
                                        lassoPoints = [value.startLocation, value.location]
                                        activeLiftedCrop = nil
                                        selectedObject = nil
                                    } else {
                                        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                                        if dist > 4 {
                                            lassoPoints.append(value.location)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    longPressDetectionTask?.cancel()

                                    if hasTriggeredLongPress {
                                        hasTriggeredLongPress = false
                                        return
                                    }

                                    guard isLassoModeEnabled else {
                                        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                                        if dist < 12 {
                                            withAnimation {
                                                selectedObject = nil
                                            }
                                        }
                                        return
                                    }

                                    let capturedPoints = lassoPoints
                                    lassoPoints = []
                                    isDrawingLasso = false

                                    let xs = capturedPoints.map { $0.x }
                                    let ys = capturedPoints.map { $0.y }
                                    let rawMinX = xs.min() ?? 0
                                    let rawMaxX = xs.max() ?? 0
                                    let rawMinY = ys.min() ?? 0
                                    let rawMaxY = ys.max() ?? 0
                                    let rawBoxW = rawMaxX - rawMinX
                                    let rawBoxH = rawMaxY - rawMinY
                                    let totalDist = zip(capturedPoints, capturedPoints.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }

                                    if totalDist < 16 || (rawBoxW < 12 && rawBoxH < 12) {
                                        withAnimation {
                                            selectedObject = nil
                                        }
                                    } else {
                                        let minX = max(0, min(fittedRect.width, rawMinX))
                                        let maxX = max(minX + 1, min(fittedRect.width, rawMaxX))
                                        let minY = max(0, min(fittedRect.height, rawMinY))
                                        // Allow slightly generous bottom bound when user swipes around a large object
                                        let maxY = max(minY + 1, min(fittedRect.height, rawMaxY + max(8, rawBoxH * 0.06)))
                                        let boxW = maxX - minX
                                        let boxH = maxY - minY
                                        let midX = (minX + maxX) / 2.0
                                        let midY = (minY + maxY) / 2.0
                                        let boxPercent = CGRect(
                                            x: (minX / fittedRect.width) * 100.0,
                                            y: (minY / fittedRect.height) * 100.0,
                                            width: max(2.0, (boxW / fittedRect.width) * 100.0),
                                            height: max(2.0, (boxH / fittedRect.height) * 100.0)
                                        )
                                        let lassoPercent = capturedPoints.map { pt in
                                            CGPoint(
                                                x: max(0.0, min(100.0, (pt.x / fittedRect.width) * 100.0)),
                                                y: max(0.0, min(100.0, (pt.y / fittedRect.height) * 100.0))
                                            )
                                        }
                                        handleLassoCircle(
                                            boxPercent: boxPercent,
                                            lassoPointsPercent: lassoPercent,
                                            centerPoint: CGPoint(x: midX, y: midY),
                                            in: fittedRect.size
                                        )
                                    }
                                }
                        )

                    // Real-time glowing laser stroke when user swipes around an item
                    if !lassoPoints.isEmpty {
                        LassoPathOverlay(points: lassoPoints)
                    }

                    if isDrawingLasso, let tip = lassoPoints.last {
                        Circle()
                            .fill(AppTheme.Semantic.warning)
                            .frame(width: 8, height: 8)
                            .shadow(color: AppTheme.Semantic.warning, radius: 4)
                            .position(tip)
                            .allowsHitTesting(false)
                    }

                    // 1. Curved leader arrows connecting badge to target
                    ForEach(Array(currentScene.objectsDetected.enumerated()), id: \.element.id) { index, item in
                        let isSelected = (selectedObject?.id == item.id)
                        if showAllLabels || isSelected {
                            let layout = computePinLayout(for: item, index: index, imageSize: fittedRect.size)
                            let accentColor = isSelected ? AppTheme.Semantic.warning : AppTheme.Primary.p500

                            CurvedLeaderArrowView(
                                startPoint: layout.startPoint,
                                endPoint: layout.targetPoint,
                                controlPoint: layout.controlPoint,
                                color: accentColor,
                                isSelected: isSelected
                            )
                        }
                    }

                    // 2. Object Bullseye Target Dots
                    ForEach(Array(currentScene.objectsDetected.enumerated()), id: \.element.id) { index, item in
                        let isSelected = (selectedObject?.id == item.id)
                        let layout = computePinLayout(for: item, index: index, imageSize: fittedRect.size)

                        targetDotView(isSelected: isSelected)
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                            .position(layout.targetPoint)
                            .allowsHitTesting(!isLassoModeEnabled && !isDetectingObject)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedObject = item
                                }
                            }
                    }

                    // 3. Floating Vocabulary Callout Badges
                    ForEach(Array(currentScene.objectsDetected.enumerated()), id: \.element.id) { index, item in
                        let isSelected = (selectedObject?.id == item.id)
                        if showAllLabels || isSelected {
                            let layout = computePinLayout(for: item, index: index, imageSize: fittedRect.size)
                            let accentColor = isSelected ? AppTheme.Semantic.warning : AppTheme.Primary.p500

                            calloutBadge(item: item, isSelected: isSelected, accentColor: accentColor)
                                .position(layout.badgeCenter)
                                .allowsHitTesting(!isLassoModeEnabled && !isDetectingObject)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        selectedObject = item
                                    }
                                }
                        }
                    }

                    // 3.5. Animated Crop-Out / Lifted Object Cutout
                    if let lifted = activeLiftedCrop {
                        LiftedCropObjectOverlayView(
                            cropState: lifted,
                            accentColor: AppTheme.Semantic.warning,
                            onOpenDetail: {
                                if let sel = selectedObject {
                                    detailedObjectItem = sel
                                }
                            }
                        )
                    }

                    // 4. Interactive Long-Press Detection Radar Ring
                    if let point = detectingPoint, isDetectingObject, activeLiftedCrop == nil {
                        detectingRadarView
                            .position(point)
                    }
                }
                .frame(width: fittedRect.width, height: fittedRect.height)
                .position(x: fittedRect.midX, y: fittedRect.midY)
                .scaleEffect(scale)
                .offset(offset)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(doubleTapGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(panOrDismissGesture(fittedRect: fittedRect))
            .overlay(alignment: .top) {
                if !isDetectingObject {
                    actionBannerOverlay
                        .zIndex(100)
                }
            }
            .overlay(alignment: .topTrailing) {
                if scale > 1.05 {
                    zoomResetBadge
                        .padding(14)
                        .zIndex(101)
                }
            }
        }
    }

    private var actionBannerOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    detectAllItems()
                } label: {
                    HStack(spacing: 6) {
                        if isScanningAllItems {
                            ProgressView()
                                .scaleEffect(0.65)
                                .tint(.white)
                            Text("Đang quét...")
                                .font(.system(size: 11, weight: .bold))
                        } else {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppTheme.Semantic.warning)
                            Text("Quét tất cả")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Semantic.warning.opacity(0.85), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 5)
                }
                .buttonStyle(.plain)
                .disabled(isScanningAllItems)

                // Nút bật/tắt chế độ vuốt để detect item
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isLassoModeEnabled.toggle()
                        if isLassoModeEnabled {
                            selectedObject = nil
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLassoModeEnabled ? "lasso.badge.sparkles" : "lasso")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isLassoModeEnabled ? .black : AppTheme.Semantic.warning)
                        Text(isLassoModeEnabled ? "Đang vuốt" : "Vuốt khoanh vùng")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(isLassoModeEnabled ? .black : .white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(isLassoModeEnabled ? AppTheme.Semantic.warning : Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppTheme.Semantic.warning, lineWidth: 1)
                    }
                    .shadow(color: isLassoModeEnabled ? AppTheme.Semantic.warning.opacity(0.4) : .black.opacity(0.5), radius: 5)
                }
                .buttonStyle(.plain)

                if !currentScene.objectsDetected.isEmpty {
                    toggleLabelsButton
                }
            }
            .padding(.top, 10)

            if !isScanningAllItems {
                HStack(spacing: 5) {
                    Image(systemName: isLassoModeEnabled ? "lasso.badge.sparkles" : "hand.tap.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Semantic.warning)
                    Text(isLassoModeEnabled
                         ? "Chế độ vuốt đang bật: Khoanh vòng quanh đồ vật để tách nền"
                         : (scale > 1.05
                            ? "Kéo 1 ngón để di chuyển ảnh • Bấm 'Vuốt khoanh vùng' để cắt đồ vật"
                            : (currentScene.objectsDetected.isEmpty
                               ? "Bấm 'Vuốt khoanh vùng' hoặc nhấn đè đồ vật để AI nhận diện"
                               : "Bấm 'Vuốt khoanh vùng' để khoanh thêm đồ vật")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
            }
        }
    }

    private var zoomResetBadge: some View {
        Button {
            resetZoom()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.caption)
                Text(String(format: "%.1fx", scale))
                    .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            scale = 1.0
            baseScale = 1.0
            offset = .zero
            baseOffset = .zero
        }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if scale > 1.05 {
                        scale = 1.0
                        baseScale = 1.0
                        offset = .zero
                        baseOffset = .zero
                    } else {
                        scale = 2.5
                        baseScale = 2.5
                        offset = .zero
                        baseOffset = .zero
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Cancel and clear lasso stroke immediately when pinching
                lassoPoints = []
                isDrawingLasso = false
                longPressDetectionTask?.cancel()
                hasTriggeredLongPress = false

                let newScale = baseScale * value
                scale = max(0.85, min(4.5, newScale))
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if scale < 1.05 {
                        scale = 1.0
                        baseScale = 1.0
                        offset = .zero
                        baseOffset = .zero
                    } else {
                        scale = min(4.0, scale)
                        baseScale = scale
                    }
                }
            }
    }

    private func panOrDismissGesture(fittedRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isDrawingLasso && !isLassoModeEnabled else { return }

                if scale > 1.05 {
                    offset = CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    )
                } else if value.translation.height > 0 {
                    dismissDragOffsetY = value.translation.height
                }
            }
            .onEnded { value in
                guard !isDrawingLasso && !isLassoModeEnabled else { return }

                if scale > 1.05 {
                    let maxPanX = max(0, (fittedRect.width * (scale - 1.0)) / 2.0 + 40)
                    let maxPanY = max(0, (fittedRect.height * (scale - 1.0)) / 2.0 + 40)
                    let clampedX = min(maxPanX, max(-maxPanX, offset.width))
                    let clampedY = min(maxPanY, max(-maxPanY, offset.height))
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = CGSize(width: clampedX, height: clampedY)
                        baseOffset = offset
                    }
                } else if scale <= 1.05 {
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dismissDragOffsetY = 0
                        }
                    }
                }
            }
    }

    private var detectingRadarView: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(time * 120).truncatingRemainder(dividingBy: 100)

            ZStack {
                // Running circular laser pulse around the touch point
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.Semantic.warning.opacity(0.2),
                                AppTheme.Semantic.warning,
                                .white,
                                AppTheme.Semantic.warning
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.8, dash: [18, 12], dashPhase: -phase)
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: AppTheme.Semantic.warning.opacity(0.85), radius: 6)

                Circle()
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 22, height: 22)

                ProgressView()
                    .scaleEffect(0.65)
                    .tint(.white)

                HStack(spacing: 5) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 8, weight: .bold))
                    Text("Đang bóc tách viền...")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.88))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(AppTheme.Semantic.warning.opacity(0.7), lineWidth: 0.5)
                }
                .shadow(radius: 4)
                .offset(y: -36)
            }
        }
    }

    private func toastBannerView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.Semantic.warning)

            Text(message)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(AppTheme.Semantic.warning.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            toastMessage = message
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }

    private func handleDetectionFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        showToast("Can't detect item")
        withAnimation(.easeOut(duration: 0.3)) {
            isDetectingObject = false
            detectingPoint = nil
            activeLiftedCrop = nil
        }
    }

    private func detectAllItems() {
        guard !isScanningAllItems else { return }
        isScanningAllItems = true

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let items = try await SceneVisionAIService.shared.detectAllObjectsInImage(from: image)
                await MainActor.run {
                    isScanningAllItems = false
                    if items.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        showToast("Can't detect item")
                    } else {
                        currentScene.objectsDetected = items
                        selectedObject = items.first
                        showAllLabels = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onUpdateScene?(currentScene)
                    }
                }
            } catch {
                await MainActor.run {
                    isScanningAllItems = false
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showToast("Can't detect item")
                }
            }
        }
    }

    private func handleLongPress(at location: CGPoint, in imageSize: CGSize) {
        processObjectCropAndDetection(customBox: nil, at: location, in: imageSize)
    }

    private func handleLassoCircle(
        boxPercent: CGRect,
        lassoPointsPercent: [CGPoint],
        centerPoint: CGPoint,
        in imageSize: CGSize
    ) {
        processObjectCropAndDetection(
            customBox: boxPercent,
            lassoPointsPercent: lassoPointsPercent,
            at: centerPoint,
            in: imageSize
        )
    }

    private func processObjectCropAndDetection(
        customBox: CGRect?,
        lassoPointsPercent: [CGPoint]? = nil,
        at location: CGPoint,
        in imageSize: CGSize
    ) {
        guard !isDetectingObject, imageSize.width > 0, imageSize.height > 0 else { return }

        let clampedX = max(1.0, min(99.0, (location.x / imageSize.width) * 100.0))
        let clampedY = max(1.0, min(99.0, (location.y / imageSize.height) * 100.0))

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            detectingPoint = location
            isDetectingObject = true
        }

        Task {
            do {
                // 1. Instant on-device Apple Vision detection + customBox crop & cutoff
                let detected = try await IOSObjectDetectorService.shared.detectAndCropObject(
                    from: image,
                    inCustomBoxPercent: customBox,
                    lassoPointsPercent: lassoPointsPercent,
                    atXPercent: clampedX,
                    yPercent: clampedY
                )

                // 2. Animate Laser Contour Border & Lift Cutout (NO PRELIMINARY DUMMY TAG CREATED)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lassoPoints = []
                        isDrawingLasso = false
                    }

                    let box = detected.paddedBoxPercent
                    let rect = CGRect(
                        x: (box.origin.x / 100.0) * imageSize.width,
                        y: (box.origin.y / 100.0) * imageSize.height,
                        width: (box.size.width / 100.0) * imageSize.width,
                        height: (box.size.height / 100.0) * imageSize.height
                    )
                    let refined = CGPoint(
                        x: (detected.refinedCenterPercent.x / 100.0) * imageSize.width,
                        y: (detected.refinedCenterPercent.y / 100.0) * imageSize.height
                    )

                    detectingPoint = refined

                    activeLiftedCrop = LiftedCropState(
                        image: detected.croppedImage,
                        cutoutImage: detected.cutoutImage,
                        rect: rect,
                        refinedCenter: refined,
                        isLifted: false,
                        isAICompleted: false,
                        detectedLabels: detected.onDeviceLabels,
                        contourLoops: detected.contourLoops
                    )

                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

                    withAnimation(.spring(response: 0.38, dampingFraction: 0.65)) {
                        activeLiftedCrop?.isLifted = true
                    }
                }

                // 3. Multimodal AI Object Identification
                let newItem = try await SceneVisionAIService.shared.identifyObject(from: detected)

                await MainActor.run {
                    let trimmed = newItem.word.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          trimmed.lowercased() != "unknown",
                          trimmed.lowercased() != "none",
                          trimmed.lowercased() != "object",
                          trimmed.lowercased() != "item",
                          trimmed.lowercased() != "vật thể đã chọn" else {
                        handleDetectionFailure()
                        return
                    }

                    UINotificationFeedbackGenerator().notificationOccurred(.success)

                    // Add verified item to detected list
                    currentScene.objectsDetected.append(newItem)
                    selectedObject = newItem

                    // Save cropped/cutout thumbnail for persistent display in vocabulary card
                    objectThumbnails[newItem.id] = detected.cutoutImage ?? detected.croppedImage

                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        activeLiftedCrop?.isLifted = false
                        activeLiftedCrop?.isAICompleted = true
                        isDetectingObject = false
                        detectingPoint = nil
                    }

                    // Keep cropped overlay briefly for settling before removing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            activeLiftedCrop = nil
                        }
                    }

                    onUpdateScene?(currentScene)
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        lassoPoints = []
                        isDrawingLasso = false
                    }
                    handleDetectionFailure()
                }
            }
        }
    }

    private struct PinLayout {
        let targetPoint: CGPoint
        let badgeCenter: CGPoint
        let startPoint: CGPoint
        let controlPoint: CGPoint
    }

    private func computePinLayout(
        for item: AISceneObjectVocabularyItem,
        index: Int,
        imageSize: CGSize
    ) -> PinLayout {
        let coords = resolvedCoordinates(for: item, index: index, total: currentScene.objectsDetected.count)
        let targetX = imageSize.width * (coords.x / 100.0)
        let targetY = imageSize.height * (coords.y / 100.0)
        let targetPoint = CGPoint(x: targetX, y: targetY)

        let isRightSide = (coords.x >= 50.0)
        let dx: CGFloat = isRightSide ? -75.0 : 75.0

        let isTopHalf = (coords.y >= 35.0)
        let stagger: CGFloat = (index % 2 == 0) ? 0 : (isTopHalf ? -16.0 : 16.0)
        let dy: CGFloat = (isTopHalf ? -55.0 : 55.0) + stagger

        let badgeX = min(imageSize.width + 25, max(-25, targetX + dx))
        let badgeY = min(imageSize.height + 20, max(-20, targetY + dy))
        let badgeCenter = CGPoint(x: badgeX, y: badgeY)

        let startPoint: CGPoint
        if badgeX < targetX - 15 {
            startPoint = CGPoint(x: badgeX + 38, y: badgeY)
        } else if badgeX > targetX + 15 {
            startPoint = CGPoint(x: badgeX - 38, y: badgeY)
        } else {
            startPoint = CGPoint(x: badgeX, y: (badgeY < targetY) ? badgeY + 16 : badgeY - 16)
        }

        let controlPoint = CGPoint(
            x: startPoint.x + (targetPoint.x - startPoint.x) * 0.85,
            y: startPoint.y + (targetPoint.y - startPoint.y) * 0.15
        )

        return PinLayout(
            targetPoint: targetPoint,
            badgeCenter: badgeCenter,
            startPoint: startPoint,
            controlPoint: controlPoint
        )
    }

    private func targetDotView(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppTheme.Semantic.warning : AppTheme.Primary.p300, lineWidth: 1.5)
                .frame(width: isSelected ? 24 : 18, height: isSelected ? 24 : 18)
                .scaleEffect(pulse ? 1.3 : 0.9)
                .opacity(pulse ? 0.25 : 0.8)

            Circle()
                .fill(isSelected ? AppTheme.Semantic.warning : .white)
                .frame(width: isSelected ? 11 : 9, height: isSelected ? 11 : 9)
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? Color.black.opacity(0.8) : AppTheme.Primary.p500, lineWidth: 1.5)
                }
        }
    }

    private func calloutBadge(
        item: AISceneObjectVocabularyItem,
        isSelected: Bool,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "tag.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isSelected ? .black : Color.white.opacity(0.85))

            Text(item.word)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .black : .white)

            if item.isOffline == true {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isSelected ? .black : AppTheme.Semantic.warning)
            }

            if isSelected && !item.phonetic.isEmpty {
                Text(item.phonetic)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.Neutral.n700)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(accentColor.opacity(isSelected ? 1.0 : 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)
        .scaleEffect(isSelected ? 1.12 : 1.0)
    }

    private var bottomArea: some View {
        VStack(spacing: 12) {
            if let item = selectedObject {
                selectedObjectCard(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            objectsCarouselStrip
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(
            Color.black.opacity(0.88)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func cropImage(for item: AISceneObjectVocabularyItem) -> UIImage? {
        if let existing = objectThumbnails[item.id] {
            return existing
        }
        let normalizedImage: UIImage
        if image.imageOrientation == .up {
            normalizedImage = image
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            normalizedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        guard let cgImage = normalizedImage.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        let cropRect: CGRect
        if let box = item.box2d, box.count >= 4 {
            let norm = { (v: Double) -> CGFloat in
                if v > 100.0 { return CGFloat(max(0.0, min(1.0, v / 1000.0))) }
                if v <= 1.0 && v > 0.0 { return CGFloat(max(0.0, min(1.0, v))) }
                return CGFloat(max(0.0, min(1.0, v / 100.0)))
            }
            let minY = norm(box[0])
            let minX = norm(box[1])
            let maxY = norm(box[2])
            let maxX = norm(box[3])
            let w = max(0.04, maxX - minX)
            let h = max(0.04, maxY - minY)
            let padX = w * 0.14
            let padTop = h * 0.14
            let padBottom = h * 0.18
            let pMinX = max(0.0, minX - padX)
            let pMinY = max(0.0, minY - padTop)
            let pMaxX = min(1.0, maxX + padX)
            let pMaxY = min(1.0, maxY + padBottom)
            cropRect = CGRect(
                x: pMinX * imgW,
                y: pMinY * imgH,
                width: max(20, (pMaxX - pMinX) * imgW),
                height: max(20, (pMaxY - pMinY) * imgH)
            ).integral
        } else {
            let coords = resolvedCoordinates(for: item, index: 0, total: 1)
            let boxW = min(imgW, max(60, imgW * 0.35))
            let boxH = min(imgH, max(60, imgH * 0.35))
            let originX = max(0, min(imgW - boxW, (CGFloat(coords.x) / 100.0) * imgW - boxW / 2.0))
            let originY = max(0, min(imgH - boxH, (CGFloat(coords.y) / 100.0) * imgH - boxH / 2.0))
            cropRect = CGRect(x: originX, y: originY, width: boxW, height: boxH).integral
        }

        if let croppedCg = cgImage.cropping(to: cropRect) {
            let cropped = UIImage(cgImage: croppedCg)
            DispatchQueue.main.async {
                self.objectThumbnails[item.id] = cropped
            }
            return cropped
        }
        return nil
    }

    private func selectedObjectCard(_ item: AISceneObjectVocabularyItem) -> some View {
        let isSaved = isWordSaved?(item.word) ?? false
        let thumb = objectThumbnails[item.id] ?? cropImage(for: item)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                if let thumb {
                    Button {
                        detailedObjectItem = item
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(AppTheme.Semantic.warning.opacity(0.85), lineWidth: 1.5)
                                }

                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Circle())
                                .offset(x: -2, y: -2)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    detailedObjectItem = item
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.word)
                                .font(.headline.bold())
                                .foregroundStyle(.white)

                            if item.isOffline == true {
                                HStack(spacing: 3) {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Offline")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(AppTheme.Semantic.warning)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppTheme.Semantic.warning.opacity(0.18))
                                .clipShape(Capsule())
                            }

                            if !item.phonetic.isEmpty {
                                Text(item.phonetic)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Neutral.n400)
                            }

                            Text(item.partOfSpeech)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.Accent.a600)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Accent.a50)
                                .clipShape(Capsule())
                        }

                        Text(item.vietnameseMeaning)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Semantic.warning)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    detailedObjectItem = item
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2.bold())
                        Text("Chi tiết")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                SpeakButton(
                    text: item.word,
                    font: .subheadline,
                    activeColor: AppTheme.Primary.p300
                )

                if let onSaveWord {
                    Button {
                        onSaveWord(item)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.subheadline)
                            .foregroundStyle(isSaved ? AppTheme.Primary.p300 : .white)
                            .padding(8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !item.exampleInContext.isEmpty {
                Text("• \(item.exampleInContext)")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.white.opacity(0.85))
            } else if item.vietnameseMeaning.contains("AI đang") {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(AppTheme.Accent.a500)
                    Text("AI đang bổ sung phiên âm IPA & câu ví dụ...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.Neutral.n400)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.Semantic.warning.opacity(0.6), lineWidth: 0.5)
        }
    }

    private var objectsCarouselStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentScene.objectsDetected) { item in
                    let isSelected = (selectedObject?.id == item.id)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedObject = item
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isSelected ? AppTheme.Semantic.warning : AppTheme.Primary.p500)
                                .frame(width: 6, height: 6)

                            Text(item.word)
                                .font(.caption.bold())
                                .foregroundStyle(isSelected ? .black : .white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                            ? AppTheme.Semantic.warning
                            : Color.white.opacity(0.15)
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func calculateFittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let xOffset = (containerSize.width - scaledWidth) / 2.0
        let yOffset = (containerSize.height - scaledHeight) / 2.0
        return CGRect(x: xOffset, y: yOffset, width: scaledWidth, height: scaledHeight)
    }

    private func normalizeCoord(_ val: Double) -> Double {
        if val > 100.0 {
            return max(0.0, min(100.0, val / 10.0))
        } else if val <= 1.0 && val > 0.0 {
            return max(0.0, min(100.0, val * 100.0))
        } else {
            return max(0.0, min(100.0, val))
        }
    }

    private func resolvedCoordinates(for item: AISceneObjectVocabularyItem, index: Int, total: Int) -> (x: Double, y: Double) {
        if let rawX = item.xPercent, let rawY = item.yPercent {
            let x = normalizeCoord(rawX)
            let y = normalizeCoord(rawY)
            if (0...100).contains(x) && (0...100).contains(y) && (x > 0 || y > 0) {
                return (x, y)
            }
        }
        if let box = item.box2d, box.count >= 4 {
            let midX = normalizeCoord((box[1] + box[3]) / 2.0)
            let midY = normalizeCoord((box[0] + box[2]) / 2.0)
            if (0...100).contains(midX) && (0...100).contains(midY) && (midX > 0 || midY > 0) {
                return (midX, midY)
            }
        }
        let cols = min(3, max(1, total))
        let col = index % cols
        let row = index / cols
        let x = 20.0 + Double(col) * (60.0 / max(1.0, Double(cols - 1)))
        let y = 25.0 + Double(row) * 18.0
        return (x, min(80.0, y))
    }
}

// MARK: - Curved Leader Arrow View

struct CurvedLeaderArrowView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let controlPoint: CGPoint
    let color: Color
    let isSelected: Bool

    var body: some View {
        Canvas { context, _ in
            let tdx = endPoint.x - controlPoint.x
            let tdy = endPoint.y - controlPoint.y
            let len = sqrt(tdx * tdx + tdy * tdy)
            let angle = atan2(tdy, tdx)

            let dotRadius: CGFloat = isSelected ? 8.0 : 6.0
            let tipPoint: CGPoint
            if len > 0.001 {
                tipPoint = CGPoint(
                    x: endPoint.x - (tdx / len) * dotRadius,
                    y: endPoint.y - (tdy / len) * dotRadius
                )
            } else {
                tipPoint = endPoint
            }

            var curvePath = Path()
            curvePath.move(to: startPoint)
            curvePath.addQuadCurve(to: tipPoint, control: controlPoint)

            context.stroke(
                curvePath,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: isSelected ? 2.0 : 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            let arrowLength: CGFloat = isSelected ? 9.0 : 7.5
            let arrowWidth: CGFloat = isSelected ? 5.5 : 4.5

            let wing1 = CGPoint(
                x: tipPoint.x - arrowLength * cos(angle) + arrowWidth * sin(angle),
                y: tipPoint.y - arrowLength * sin(angle) - arrowWidth * cos(angle)
            )
            let wing2 = CGPoint(
                x: tipPoint.x - arrowLength * cos(angle) - arrowWidth * sin(angle),
                y: tipPoint.y - arrowLength * sin(angle) + arrowWidth * cos(angle)
            )

            var arrowHead = Path()
            arrowHead.move(to: tipPoint)
            arrowHead.addLine(to: wing1)
            arrowHead.addLine(to: wing2)
            arrowHead.closeSubpath()

            context.fill(arrowHead, with: .color(color))
        }
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Lifted Crop Cutout & Viewfinder Views

struct LiftedCropState: Equatable, Identifiable {
    var id: String { "\(rect.origin.x)-\(rect.origin.y)" }
    let image: UIImage
    let cutoutImage: UIImage?
    let rect: CGRect
    let refinedCenter: CGPoint
    var isLifted: Bool = false
    var isAICompleted: Bool = false
    var detectedLabels: [String] = []
    var contourLoops: [[CGPoint]] = []
}

struct RunningContourLaserBorderView: View {
    let loops: [[CGPoint]]
    let accentColor: Color

    var body: some View {
        TimelineView(.animation) { (context: TimelineViewDefaultContext) in
            borderContent(at: context.date)
        }
    }

    @ViewBuilder
    private func borderContent(at date: Date) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        let phase = CGFloat(time * 120).truncatingRemainder(dividingBy: 140)
        let secPhase = CGFloat(time * 70).truncatingRemainder(dividingBy: 140)

        ZStack {
            if !loops.isEmpty {
                ContourSilhouettePathShape(loops: loops)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1.5)

                ContourSilhouettePathShape(loops: loops)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.2),
                                accentColor,
                                .white,
                                AppTheme.Accent.a500,
                                accentColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(
                            lineWidth: 3.5,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [42, 28],
                            dashPhase: -phase
                        )
                    )
                    .shadow(color: accentColor.opacity(0.95), radius: 8, x: 0, y: 0)
                    .shadow(color: .white.opacity(0.9), radius: 3, x: 0, y: 0)

                ContourSilhouettePathShape(loops: loops)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 2.2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [14, 56],
                            dashPhase: -secPhase
                        )
                    )
                    .shadow(color: .white, radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(accentColor.opacity(0.3), lineWidth: 1.5)

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.2),
                                accentColor,
                                .white,
                                AppTheme.Accent.a500,
                                accentColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(
                            lineWidth: 3.5,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [42, 28],
                            dashPhase: -phase
                        )
                    )
                    .shadow(color: accentColor.opacity(0.95), radius: 8, x: 0, y: 0)
                    .shadow(color: .white.opacity(0.9), radius: 3, x: 0, y: 0)

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 2.2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [14, 56],
                            dashPhase: -secPhase
                        )
                    )
                    .shadow(color: .white, radius: 4)
            }
        }
    }
}

struct LiftedCropObjectOverlayView: View {
    let cropState: LiftedCropState
    let accentColor: Color
    var onOpenDetail: (() -> Void)? = nil

    @State private var pulseGlow: Bool = false

    var body: some View {
        let displayImage = cropState.cutoutImage ?? cropState.image
        let isLargeObject = cropState.rect.height > 200 || cropState.rect.width > 200
        let liftedScale: CGFloat = isLargeObject ? 1.03 : 1.08

        ZStack {
            // 1. Cutout / Cropped Object Image with smooth rounded frame
            Image(uiImage: displayImage)
                .resizable()
                .frame(width: max(20, cropState.rect.width), height: max(20, cropState.rect.height))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenDetail?()
                }
                // 2. High-Tech Animated Laser Border RUNNING AROUND THE ITEM
                .overlay {
                    RunningContourLaserBorderView(
                        loops: cropState.contourLoops,
                        accentColor: accentColor
                    )
                }
                // 3. Viewfinder Corner Brackets
                .overlay {
                    ViewfinderCornerBracketsView(color: accentColor)
                        .padding(-3)
                }
                // Elevation shadow & halo
                .shadow(
                    color: Color.black.opacity(cropState.isLifted ? 0.7 : 0.2),
                    radius: cropState.isLifted ? 16 : 4,
                    x: 0,
                    y: cropState.isLifted ? 10 : 2
                )
                .shadow(
                    color: accentColor.opacity(pulseGlow ? 0.6 : 0.2),
                    radius: cropState.isLifted ? 10 : 3,
                    x: 0,
                    y: 0
                )
                .scaleEffect(cropState.isLifted ? liftedScale : 0.96)

            // Floating status badge above the lifted object
            if !cropState.isAICompleted {
                HStack(spacing: 5) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accentColor)

                    Text(cropState.detectedLabels.first != nil
                         ? "Đã bóc tách viền: \(cropState.detectedLabels.first!.capitalized)"
                         : "Đã bóc tách viền vật thể...")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)

                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.88))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.8), lineWidth: 0.8)
                }
                .shadow(radius: 6)
                .offset(y: -(cropState.rect.height / 2.0) - 26)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .position(x: cropState.rect.midX, y: cropState.rect.midY)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseGlow = true
            }
        }
    }
}

// MARK: - Contour Silhouette Shape

struct ContourSilhouettePathShape: Shape {
    let loops: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for loop in loops {
            guard let first = loop.first else { continue }
            let start = CGPoint(
                x: rect.minX + CGFloat(first.x) * rect.width,
                y: rect.minY + (1.0 - CGFloat(first.y)) * rect.height
            )
            path.move(to: start)

            for pt in loop.dropFirst() {
                let p = CGPoint(
                    x: rect.minX + CGFloat(pt.x) * rect.width,
                    y: rect.minY + (1.0 - CGFloat(pt.y)) * rect.height
                )
                path.addLine(to: p)
            }
            path.closeSubpath()
        }

        return path
    }
}

struct ViewfinderCornerBracketsView: View {
    let color: Color
    let length: CGFloat = 10
    let thickness: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                // Top-Left
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))

                // Top-Right
                path.move(to: CGPoint(x: w - length, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: length))

                // Bottom-Left
                path.move(to: CGPoint(x: 0, y: h - length))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: length, y: h))

                // Bottom-Right
                path.move(to: CGPoint(x: w - length, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cropped Object Detail Sheet (Xem chi tiết ảnh đã nhấn đè)

struct CroppedObjectDetailSheet: View {
    let item: AISceneObjectVocabularyItem
    let objectImage: UIImage?
    let fullImage: UIImage?
    let isSaved: Bool
    let onSaveWord: ((AISceneObjectVocabularyItem) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // 1. Phóng to ảnh vật thể đã nhấn đè / bóc tách
                        if let objectImage {
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: objectImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(maxHeight: 280)
                                        .scaleEffect(zoomScale)
                                        .gesture(
                                            MagnificationGesture()
                                                .onChanged { val in
                                                    zoomScale = max(0.9, min(3.5, baseZoomScale * val))
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                        if zoomScale < 1.05 {
                                                            zoomScale = 1.0
                                                            baseZoomScale = 1.0
                                                        } else {
                                                            baseZoomScale = zoomScale
                                                        }
                                                    }
                                                }
                                        )
                                        .simultaneousGesture(
                                            TapGesture(count: 2).onEnded {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    zoomScale = (zoomScale > 1.1) ? 1.0 : 2.2
                                                    baseZoomScale = zoomScale
                                                }
                                            }
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            AppTheme.Semantic.warning,
                                                            .white.opacity(0.8),
                                                            AppTheme.Primary.p300
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        }
                                        .shadow(color: AppTheme.Semantic.warning.opacity(0.35), radius: 14)

                                    HStack(spacing: 5) {
                                        Image(systemName: "camera.viewfinder")
                                            .font(.caption2.bold())
                                            .foregroundStyle(AppTheme.Semantic.warning)
                                        Text("Ảnh bóc tách")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.85))
                                    .clipShape(Capsule())
                                    .padding(12)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 10)

                                Text("Chụm 2 ngón tay hoặc chạm đúp để phóng to ảnh")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Neutral.n400)
                            }
                        }

                        // 2. Thẻ chi tiết từ vựng và ngữ cảnh
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(item.word)
                                            .font(.title2.bold())
                                            .foregroundStyle(.white)

                                        Text(item.partOfSpeech)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(AppTheme.Accent.a600)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(AppTheme.Accent.a50)
                                            .clipShape(Capsule())
                                    }

                                    if !item.phonetic.isEmpty {
                                        Text(item.phonetic)
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.Neutral.n400)
                                    }
                                }

                                Spacer()

                                SpeakButton(
                                    text: item.word,
                                    font: .title3,
                                    activeColor: AppTheme.Primary.p300
                                )
                            }

                            Divider().background(Color.white.opacity(0.15))

                            // Nghĩa tiếng Việt
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nghĩa tiếng Việt")
                                    .font(.caption2.bold())
                                    .foregroundStyle(AppTheme.Neutral.n400)
                                    .textCase(.uppercase)

                                Text(item.vietnameseMeaning)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.Semantic.warning)
                            }

                            // Câu ví dụ trong ngữ cảnh
                            if !item.exampleInContext.isEmpty {
                                Divider().background(Color.white.opacity(0.15))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Câu ví dụ trong ngữ cảnh ảnh")
                                        .font(.caption2.bold())
                                        .foregroundStyle(AppTheme.Neutral.n400)
                                        .textCase(.uppercase)

                                    HStack(alignment: .top, spacing: 8) {
                                        Text("“\(item.exampleInContext)”")
                                            .font(.subheadline)
                                            .italic()
                                            .foregroundStyle(.white.opacity(0.95))

                                        Spacer()

                                        SpeakButton(
                                            text: item.exampleInContext,
                                            font: .caption,
                                            activeColor: AppTheme.Primary.p300
                                        )
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        }
                        .padding(.horizontal, 16)

                        // 3. Nút lưu vào sổ từ vựng
                        if let onSaveWord {
                            Button {
                                onSaveWord(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                        .font(.headline)
                                    Text(isSaved ? "Đã lưu vào sổ từ vựng" : "Lưu vào sổ từ vựng cá nhân")
                                        .font(.headline.bold())
                                }
                                .foregroundStyle(isSaved ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isSaved ? AppTheme.Primary.p500 : AppTheme.Semantic.warning)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(radius: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Chi tiết ảnh & từ vựng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }
}

// MARK: - Lasso / Gesture Circling Overlay

private struct LassoPathOverlay: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }

            // Outer wide ambient laser glow
            context.stroke(
                path,
                with: .color(AppTheme.Semantic.warning.opacity(0.4)),
                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
            )

            // Inner crisp glowing laser stroke
            context.stroke(
                path,
                with: .color(AppTheme.Semantic.warning),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }
}


