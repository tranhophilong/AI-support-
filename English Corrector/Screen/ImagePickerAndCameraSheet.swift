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

// MARK: - Camera Picker View (UIImagePickerController)

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var isPresented: Binding<Bool>?
    @Environment(\.dismiss) private var dismiss

    init(selectedImage: Binding<UIImage?>, isPresented: Binding<Bool>? = nil) {
        self._selectedImage = selectedImage
        self.isPresented = isPresented
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                let fixed = Self.fixOrientation(image)
                parent.selectedImage = fixed
            }
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if let isPresented = self.parent.isPresented {
                    isPresented.wrappedValue = false
                } else {
                    self.parent.dismiss()
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if let isPresented = self.parent.isPresented {
                    isPresented.wrappedValue = false
                } else {
                    self.parent.dismiss()
                }
            }
        }

        private static func fixOrientation(_ image: UIImage) -> UIImage {
            if image.imageOrientation == .up { return image }
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalized ?? image
        }
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

    @State private var showInteractiveViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if let imageData, let uiImage = UIImage(data: imageData) {
                photoBannerSection(uiImage: uiImage)
            }

            overviewSection
            if !scene.objectsDetected.isEmpty {
                objectsSection
            }
            if !scene.situationalConversationalPhrases.isEmpty {
                phrasesSection
            }
            if let note = scene.adviceOrCulturalNote, !note.isEmpty {
                adviceSection(note)
            }
        }
        .padding(14)
        .background(AppTheme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
        }
    }

    // MARK: - Subviews

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
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2.bold())
                    Text("Bấm vào ảnh xem từ vựng bên cạnh đồ vật (\(scene.objectsDetected.count))")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(scene.sceneOverview)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Neutral.n900)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SpeakButton(
                    text: scene.sceneOverview,
                    font: .caption,
                    activeColor: AppTheme.Primary.p500
                )
            }

            Text(scene.sceneVietnameseTranslation)
                .font(.caption)
                .foregroundStyle(AppTheme.Neutral.n700)
        }
        .padding(12)
        .background(AppTheme.Primary.p50.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.Primary.p300, lineWidth: 0.5)
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

    private func objectItemRow(_ item: AISceneObjectVocabularyItem) -> some View {
        let isSaved = isWordSaved?(item.word) ?? false

        return HStack(alignment: .center, spacing: 8) {
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

                if !item.exampleInContext.isEmpty {
                    Text("• \(item.exampleInContext)")
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(AppTheme.Neutral.n500)
                }
            }

            Spacer()

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
    }

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mẫu câu giao tiếp trong hoàn cảnh này:", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.Primary.p500)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                ForEach(scene.situationalConversationalPhrases, id: \.self) { phrase in
                    HStack(spacing: 8) {
                        Text(phrase)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Neutral.n900)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        SpeakButton(
                            text: phrase,
                            font: .caption,
                            activeColor: AppTheme.Primary.p500
                        )
                    }
                    .padding(10)
                    .background(AppTheme.Secondary.s50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(AppTheme.Surface.border, lineWidth: 0.5)
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
        }
        .padding(10)
        .background(AppTheme.Accent.a50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.Accent.a500.opacity(0.3), lineWidth: 0.5)
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
    @State private var detectingPoint: CGPoint? = nil
    @State private var detectionErrorMessage: String? = nil
    @State private var hasTriggeredLongPress: Bool = false
    @State private var activeLiftedCrop: LiftedCropState? = nil
    @State private var objectThumbnails: [String: UIImage] = [:]

    // Zoom, Pan & Interactive Dismiss States
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dismissDragOffsetY: CGFloat = 0

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
            ZStack {
                Color.black
                    .opacity(max(0.3, 1.0 - Double(dismissDragOffsetY / 450.0)))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    canvasArea

                    bottomArea
                }
                .offset(y: max(0, dismissDragOffsetY))
                .scaleEffect(max(0.88, 1.0 - (dismissDragOffsetY / 1500.0)))
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
                        .onTapGesture {
                            withAnimation {
                                selectedObject = nil
                            }
                        }
                        .gesture(
                            LongPressGesture(minimumDuration: 0.45)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onChanged { value in
                                    switch value {
                                    case .second(true, let drag):
                                        if !hasTriggeredLongPress, let drag = drag {
                                            hasTriggeredLongPress = true
                                            handleLongPress(at: drag.location, in: fittedRect.size)
                                        }
                                    default:
                                        break
                                    }
                                }
                                .onEnded { _ in
                                    hasTriggeredLongPress = false
                                }
                        )

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
                            accentColor: AppTheme.Semantic.warning
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

                // Hint Pill: "Nhấn đè vào đồ vật để AI nhận diện thêm"
                if !isDetectingObject && currentScene.objectsDetected.count < 15 {
                    VStack {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.Accent.a600)
                            Text("Nhấn đè vào đồ vật bất kỳ để AI nhận diện thêm")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        }
                        .padding(.top, 10)

                        Spacer()
                    }
                }

                // Error message banner
                if let msg = detectionErrorMessage {
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Semantic.warning)
                            Text(msg)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .shadow(radius: 6)
                        .padding(.top, 14)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Quick Reset Zoom Indicator Badge
                if scale > 1.05 {
                    VStack {
                        HStack {
                            Spacer()
                            zoomResetBadge
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(doubleTapGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(panOrDismissGesture(fittedRect: fittedRect))
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
                if scale > 1.05 {
                    offset = CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    )
                } else {
                    if value.translation.height > 0 {
                        dismissDragOffsetY = value.translation.height
                    }
                }
            }
            .onEnded { value in
                if scale > 1.05 {
                    let maxPanX = max(0, (fittedRect.width * (scale - 1.0)) / 2.0 + 40)
                    let maxPanY = max(0, (fittedRect.height * (scale - 1.0)) / 2.0 + 40)
                    let clampedX = min(maxPanX, max(-maxPanX, offset.width))
                    let clampedY = min(maxPanY, max(-maxPanY, offset.height))

                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = CGSize(width: clampedX, height: clampedY)
                        baseOffset = offset
                    }
                } else {
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
        ZStack {
            Circle()
                .stroke(AppTheme.Semantic.warning, lineWidth: 2)
                .frame(width: 48, height: 48)
                .scaleEffect(pulse ? 1.35 : 0.85)
                .opacity(pulse ? 0.25 : 0.85)

            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 22, height: 22)

            ProgressView()
                .scaleEffect(0.65)
                .tint(.white)

            HStack(spacing: 5) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 8, weight: .bold))
                Text("Apple Vision & AI...")
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
            .offset(y: -32)
        }
    }

    private func handleLongPress(at location: CGPoint, in imageSize: CGSize) {
        guard !isDetectingObject, imageSize.width > 0, imageSize.height > 0 else { return }

        let clampedX = max(1.0, min(99.0, (location.x / imageSize.width) * 100.0))
        let clampedY = max(1.0, min(99.0, (location.y / imageSize.height) * 100.0))

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            detectingPoint = location
            isDetectingObject = true
            detectionErrorMessage = nil
        }

        Task {
            var createdItemId: String? = nil

            do {
                // 1. Instant on-device Apple Vision detection (~15ms)
                let detected = try await IOSObjectDetectorService.shared.detectAndCropObject(
                    from: image,
                    atXPercent: clampedX,
                    yPercent: clampedY
                )

                // 2. NHẬN BIẾT VẬT THỂ TRƯỚC (On-Device Instant Recognition) & Animate Crop/Lift
                await MainActor.run {
                    let box = detected.boundingBoxPercent
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

                    // Hiển thị từ vựng tin cậy từ Apple Vision hoặc placeholder chuẩn
                    let onDeviceWord: String
                    if let confident = detected.onDeviceLabels.first, !confident.isEmpty {
                        onDeviceWord = confident.capitalized
                    } else {
                        onDeviceWord = "Vật thể đã chọn"
                    }

                    let preliminaryItem = AISceneObjectVocabularyItem(
                        word: onDeviceWord,
                        phonetic: "",
                        partOfSpeech: "Noun",
                        vietnameseMeaning: "AI đang phân tích chính xác đồ vật...",
                        exampleInContext: "",
                        xPercent: Double(detected.refinedCenterPercent.x),
                        yPercent: Double(detected.refinedCenterPercent.y),
                        box2d: detected.box2dGrounding
                    )

                    createdItemId = preliminaryItem.id
                    currentScene.objectsDetected.append(preliminaryItem)
                    selectedObject = preliminaryItem
                    objectThumbnails[preliminaryItem.id] = detected.cutoutImage ?? detected.croppedImage

                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

                    withAnimation(.spring(response: 0.38, dampingFraction: 0.65)) {
                        activeLiftedCrop?.isLifted = true
                    }
                }

                // 3. ĐƯA CHO AI NHẬN BIẾT & LÀM GIÀU DỮ LIỆU SAU (Background Multimodal AI Enrichment)
                let newItem = try await SceneVisionAIService.shared.identifyObject(from: detected)

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)

                    // Cập nhật item sơ bộ bằng dữ liệu AI hoàn chỉnh
                    if let targetId = createdItemId,
                       let idx = currentScene.objectsDetected.firstIndex(where: { $0.id == targetId }) {
                        currentScene.objectsDetected[idx] = newItem
                        if selectedObject?.id == targetId {
                            selectedObject = newItem
                        }
                    } else {
                        currentScene.objectsDetected.append(newItem)
                        selectedObject = newItem
                    }

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
                    // Nếu AI lỗi mạng, người dùng vẫn giữ nguyên vật thể đã nhận biết từ máy!
                    if let targetId = createdItemId,
                       let idx = currentScene.objectsDetected.firstIndex(where: { $0.id == targetId }) {
                        let current = currentScene.objectsDetected[idx]
                        let fallbackItem = AISceneObjectVocabularyItem(
                            word: current.word,
                            phonetic: "",
                            partOfSpeech: current.partOfSpeech,
                            vietnameseMeaning: "Đã nhận diện từ thiết bị (AI tạm ngưng kết nối)",
                            exampleInContext: "",
                            xPercent: current.xPercent,
                            yPercent: current.yPercent,
                            box2d: current.box2d
                        )
                        currentScene.objectsDetected[idx] = fallbackItem
                        if selectedObject?.id == targetId {
                            selectedObject = fallbackItem
                        }
                    }

                    withAnimation {
                        isDetectingObject = false
                        detectingPoint = nil
                        activeLiftedCrop = nil
                    }
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

    private func selectedObjectCard(_ item: AISceneObjectVocabularyItem) -> some View {
        let isSaved = isWordSaved?(item.word) ?? false

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                if let thumb = objectThumbnails[item.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(AppTheme.Semantic.warning.opacity(0.8), lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.word)
                            .font(.headline.bold())
                            .foregroundStyle(.white)

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
                }

                Spacer()

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

struct LiftedCropObjectOverlayView: View {
    let cropState: LiftedCropState
    let accentColor: Color

    @State private var shimmerPhase: CGFloat = -1.2
    @State private var pulseGlow: Bool = false

    var body: some View {
        let displayImage = cropState.cutoutImage ?? cropState.image

        ZStack {
            // 1. Cutout / Cropped Object Image with smooth rounded frame
            Image(uiImage: displayImage)
                .resizable()
                .scaledToFill()
                .frame(width: max(20, cropState.rect.width), height: max(20, cropState.rect.height))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                // 2. Exact Detected Contour Silhouette Outline (tracing the real object curves & corners)
                .overlay {
                    if !cropState.contourLoops.isEmpty {
                        ContourSilhouettePathShape(loops: cropState.contourLoops)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        accentColor,
                                        .white,
                                        AppTheme.Primary.p300,
                                        accentColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: accentColor.opacity(pulseGlow ? 0.9 : 0.45), radius: 8, x: 0, y: 0)
                            .shadow(color: .white.opacity(0.85), radius: 3, x: 0, y: 0)
                    } else {
                        // Smooth rounded contour boundary fallback
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        accentColor,
                                        .white,
                                        AppTheme.Primary.p300,
                                        accentColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: cropState.isLifted ? 2.5 : 1.5
                            )
                    }
                }
                // 3. Scanning light sweep across the object
                .overlay {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(0.45),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .rotationEffect(.degrees(25))
                            .offset(x: shimmerPhase * geo.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                // 4. Viewfinder Corner Brackets
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
                .scaleEffect(cropState.isLifted ? 1.08 : 0.95)

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
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.2
            }
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
