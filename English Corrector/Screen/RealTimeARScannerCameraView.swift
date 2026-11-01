//
//  RealTimeARScannerCameraView.swift
//  English Corrector
//
//  Created by Antigravity on 2026-11-01.
//  Real-Time AR Camera Scanner View (30-60 FPS on Apple Neural Engine)
//

import SwiftUI
import AVFoundation
import PhotosUI
import SwiftData

// MARK: - Camera Preview Layer (UIKit Representable)

public struct CameraPreviewUIView: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }

    public class PreviewContainerView: UIView {
        public override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        public var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Real-Time AR Scanner Camera View

public struct RealTimeARScannerCameraView: View {
    @Binding var selectedImage: UIImage?
    var isPresented: Binding<Bool>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var cameraManager = RealTimeCameraManager()
    @State private var showPhotoLibrary = false
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var isCapturing = false
    @State private var activeSpeakingWord: String? = nil
    @State private var savedWordsSet: Set<String> = []
    @State private var toastMessage: String? = nil

    public init(selectedImage: Binding<UIImage?>, isPresented: Binding<Bool>? = nil) {
        self._selectedImage = selectedImage
        self.isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Live Camera Feed or Simulator Fallback
                if cameraManager.isCameraAvailable {
                    CameraPreviewUIView(session: cameraManager.session)
                        .ignoresSafeArea()
                } else {
                    simulatorMockCameraView(geometry: geometry)
                }

                // 2. Real-Time AR Overlay (Detected Objects)
                if cameraManager.isARScanningEnabled {
                    arOverlayLayer(containerSize: geometry.size)
                }

                // 3. Top HUD Toolbar
                VStack {
                    topHUDToolbar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top : 20)
                        .padding(.horizontal, 16)

                    if let toast = toastMessage {
                        toastBannerView(message: toast)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    // 4. Bottom Capture & Mode Controls
                    bottomControlBar
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom : 20)
                }
            }
        }
        .onAppear {
            cameraManager.configureSession()
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
            SpeechSynthesizerManager.shared.stop()
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $photosPickerItem, matching: .images)
        .onChange(of: photosPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = uiImage
                        closeCamera()
                    }
                }
            }
        }
    }

    // MARK: - AR Overlay Layer

    @ViewBuilder
    private func arOverlayLayer(containerSize: CGSize) -> some View {
        ZStack {
            ForEach(cameraManager.detectedObjects) { item in
                ARScannedTargetOverlay(
                    item: item,
                    containerSize: containerSize,
                    isSpeaking: activeSpeakingWord == item.word,
                    isSaved: savedWordsSet.contains(item.word),
                    onSpeak: { speakWord(item.word) },
                    onSave: { quickSaveWord(item) }
                )
            }
        }
    }

    // MARK: - Top HUD Toolbar

    private var topHUDToolbar: some View {
        HStack {
            // Close Button
            Button {
                closeCamera()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()

            // Live AI Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(cameraManager.isARScanningEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .shadow(color: cameraManager.isARScanningEnabled ? Color.green.opacity(0.8) : .clear, radius: 4)

                Text(cameraManager.isARScanningEnabled ? "AR Vision • \(cameraManager.detectedObjects.count) vật thể" : "Camera thường")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
            }

            Spacer()

            HStack(spacing: 12) {
                // Torch Button
                if cameraManager.isCameraAvailable {
                    Button {
                        cameraManager.toggleTorch()
                    } label: {
                        Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(cameraManager.isTorchOn ? AppTheme.Semantic.warning : .white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Flip Camera Button
                    Button {
                        cameraManager.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bottom Controls Bar

    private var bottomControlBar: some View {
        VStack(spacing: 16) {
            // Mode Switcher: Quét AR vs Chụp thường
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        cameraManager.isARScanningEnabled = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("Quét AR Real-time")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(cameraManager.isARScanningEnabled ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(cameraManager.isARScanningEnabled ? AppTheme.Semantic.warning : Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(AppTheme.Semantic.warning.opacity(0.8), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        cameraManager.isARScanningEnabled = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Chụp thường")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(!cameraManager.isARScanningEnabled ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(!cameraManager.isARScanningEnabled ? AppTheme.Semantic.warning : Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(AppTheme.Semantic.warning.opacity(0.8), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            // Capture Controls
            HStack(spacing: 40) {
                // Photo Library Button
                Button {
                    showPhotoLibrary = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                        Text("Thư viện")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)

                // Shutter Button
                Button {
                    takePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)

                        Circle()
                            .fill(isCapturing ? AppTheme.Semantic.warning : Color.white)
                            .frame(width: 62, height: 62)
                            .scaleEffect(isCapturing ? 0.88 : 1.0)
                    }
                    .shadow(color: AppTheme.Semantic.warning.opacity(0.4), radius: 10)
                }
                .buttonStyle(.plain)
                .disabled(isCapturing)

                // Placeholder Spacer to balance Shutter
                Color.clear
                    .frame(width: 46, height: 46)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Simulator Fallback View

    private func simulatorMockCameraView(geometry: GeometryProxy) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 54, weight: .thin))
                    .foregroundStyle(AppTheme.Semantic.warning)

                Text("Giả lập Camera Real-Time (Simulator)")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Trên iPhone thật, camera quét thời gian thực 30-60 FPS với Apple Neural Engine. Bạn có thể chọn ảnh từ thư viện để trải nghiệm ngay.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    showPhotoLibrary = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.fill")
                        Text("Chọn ảnh từ thư viện để thử")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppTheme.Semantic.warning)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func takePhoto() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.1)) {
            isCapturing = true
        }

        if cameraManager.isCameraAvailable {
            cameraManager.capturePhoto { image in
                isCapturing = false
                if let image {
                    selectedImage = image
                    closeCamera()
                }
            }
        } else {
            isCapturing = false
            showPhotoLibrary = true
        }
    }

    private func speakWord(_ word: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeSpeakingWord = word
        SpeechSynthesizerManager.shared.speak(word)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if activeSpeakingWord == word {
                activeSpeakingWord = nil
            }
        }
    }

    private func quickSaveWord(_ item: ARScannedItem) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        do {
            _ = try VocabularyNoteStore.save(
                word: item.word,
                sourceText: "Phát hiện qua AR Camera: \(item.vietnameseMeaning)",
                in: modelContext
            )
            savedWordsSet.insert(item.word)
            showToast("Đã lưu từ '\(item.word)' vào sổ tay ghi nhớ")
        } catch {
            showToast("Lỗi lưu từ vựng: \(error.localizedDescription)")
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    private func toastBannerView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .font(.system(size: 13, weight: .bold))
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.5), radius: 6)
    }

    private func closeCamera() {
        if let isPresented {
            isPresented.wrappedValue = false
        } else {
            dismiss()
        }
    }
}

// MARK: - Extracted Component for Fast Compiler Type-Checking

private struct ARScannedTargetOverlay: View {
    let item: ARScannedItem
    let containerSize: CGSize
    let isSpeaking: Bool
    let isSaved: Bool
    let onSpeak: () -> Void
    let onSave: () -> Void

    private var targetRect: CGRect {
        CGRect(
            x: item.boundingBox.origin.x * containerSize.width,
            y: item.boundingBox.origin.y * containerSize.height,
            width: max(80, item.boundingBox.width * containerSize.width),
            height: max(80, item.boundingBox.height * containerSize.height)
        )
    }

    var body: some View {
        ZStack {
            // 1. Viewfinder Brackets around object
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSpeaking ? AppTheme.Semantic.warning : Color.white.opacity(0.8),
                        lineWidth: isSpeaking ? 2.5 : 1.5
                    )
                    .frame(width: targetRect.width, height: targetRect.height)
                    .shadow(
                        color: isSpeaking ? AppTheme.Semantic.warning.opacity(0.8) : Color.black.opacity(0.4),
                        radius: 6
                    )

                ViewfinderCornerBracketsView(
                    color: isSpeaking ? AppTheme.Semantic.warning : .white
                )
                .frame(width: targetRect.width + 6, height: targetRect.height + 6)
            }
            .position(x: targetRect.midX, y: targetRect.midY)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: item.boundingBox)

            // 2. Floating AR Badge
            Button(action: onSpeak) {
                HStack(spacing: 7) {
                    Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Semantic.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(item.word)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            if !item.phonetic.isEmpty {
                                Text(item.phonetic)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.7))
                            }
                        }

                        Text(item.vietnameseMeaning)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.Semantic.warning)
                    }

                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSaved ? AppTheme.Semantic.warning : Color.white.opacity(0.8))
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.78))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSpeaking ? AppTheme.Semantic.warning : Color.white.opacity(0.25),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .position(
                x: min(max(targetRect.midX, 130), containerSize.width - 130),
                y: max(60, targetRect.minY - 32)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: item.boundingBox)
        }
    }
}
