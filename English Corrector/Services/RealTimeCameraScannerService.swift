//
//  RealTimeCameraScannerService.swift
//  English Corrector
//
//  Created by Antigravity on 2026-11-01.
//  Real-Time Camera Scanner using AVFoundation & Apple Vision Neural Engine (30-60 FPS)
//

import Foundation
import UIKit
import AVFoundation
import Vision
import Combine

// MARK: - AR Scanned Vocabulary Item Model

public struct ARScannedItem: Identifiable, Equatable {
    public let id: UUID
    public let word: String
    public let phonetic: String
    public let vietnameseMeaning: String
    public let partOfSpeech: String
    public var boundingBox: CGRect // Normalized 0...1 UIKit coordinates (x, y, w, h)
    public let confidence: Float
    public var lastSeen: Date

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String,
        vietnameseMeaning: String,
        partOfSpeech: String = "Noun",
        boundingBox: CGRect,
        confidence: Float,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.vietnameseMeaning = vietnameseMeaning
        self.partOfSpeech = partOfSpeech
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.lastSeen = lastSeen
    }

    public static func == (lhs: ARScannedItem, rhs: ARScannedItem) -> Bool {
        lhs.id == rhs.id && lhs.word == rhs.word && lhs.boundingBox == rhs.boundingBox
    }
}

// MARK: - Everyday Objects Vocabulary Knowledge Base

public struct EverydayVocabularyDictionary {
    public struct Entry {
        public let word: String
        public let phonetic: String
        public let vietnamese: String
        public let partOfSpeech: String
    }

    private static let entries: [String: Entry] = [
        // Tech & Workspace
        "laptop": Entry(word: "Laptop", phonetic: "/ˈlæp.tɑːp/", vietnamese: "Máy tính xách tay", partOfSpeech: "Noun"),
        "notebook computer": Entry(word: "Laptop", phonetic: "/ˈlæp.tɑːp/", vietnamese: "Máy tính xách tay", partOfSpeech: "Noun"),
        "computer keyboard": Entry(word: "Keyboard", phonetic: "/ˈkiː.bɔːrd/", vietnamese: "Bàn phím", partOfSpeech: "Noun"),
        "keyboard": Entry(word: "Keyboard", phonetic: "/ˈkiː.bɔːrd/", vietnamese: "Bàn phím", partOfSpeech: "Noun"),
        "computer mouse": Entry(word: "Mouse", phonetic: "/maʊs/", vietnamese: "Chuột máy tính", partOfSpeech: "Noun"),
        "mouse": Entry(word: "Mouse", phonetic: "/maʊs/", vietnamese: "Chuột máy tính", partOfSpeech: "Noun"),
        "monitor": Entry(word: "Computer Monitor", phonetic: "/ˈmɑː.nə.t̬ɚ/", vietnamese: "Màn hình máy tính", partOfSpeech: "Noun"),
        "screen": Entry(word: "Screen", phonetic: "/skriːn/", vietnamese: "Màn hình", partOfSpeech: "Noun"),
        "cellular telephone": Entry(word: "Smartphone", phonetic: "/ˈsmɑːrt.foʊn/", vietnamese: "Điện thoại di động", partOfSpeech: "Noun"),
        "mobile phone": Entry(word: "Smartphone", phonetic: "/ˈsmɑːrt.foʊn/", vietnamese: "Điện thoại thông minh", partOfSpeech: "Noun"),
        "phone": Entry(word: "Phone", phonetic: "/foʊn/", vietnamese: "Điện thoại", partOfSpeech: "Noun"),
        "headphone": Entry(word: "Headphones", phonetic: "/ˈhed.foʊnz/", vietnamese: "Tai nghe trùm đầu", partOfSpeech: "Noun"),
        "earphone": Entry(word: "Earphones", phonetic: "/ˈɪr.foʊnz/", vietnamese: "Tai nghe nhét tai", partOfSpeech: "Noun"),
        "tablet": Entry(word: "Tablet", phonetic: "/ˈtæb.lət/", vietnamese: "Máy tính bảng", partOfSpeech: "Noun"),
        "watch": Entry(word: "Watch", phonetic: "/wɑːtʃ/", vietnamese: "Đồng hồ đeo tay", partOfSpeech: "Noun"),
        "wrist watch": Entry(word: "Wristwatch", phonetic: "/ˈrɪst.wɑːtʃ/", vietnamese: "Đồng hồ đeo tay", partOfSpeech: "Noun"),
        "smartwatch": Entry(word: "Smartwatch", phonetic: "/ˈsmɑːrt.wɑːtʃ/", vietnamese: "Đồng hồ thông minh", partOfSpeech: "Noun"),
        "clock": Entry(word: "Clock", phonetic: "/klɑːk/", vietnamese: "Đồng hồ treo tường", partOfSpeech: "Noun"),

        // Study & Office
        "book": Entry(word: "Book", phonetic: "/bʊk/", vietnamese: "Quyển sách", partOfSpeech: "Noun"),
        "notebook": Entry(word: "Notebook", phonetic: "/ˈnoʊt.bʊk/", vietnamese: "Sổ tay ghi chép", partOfSpeech: "Noun"),
        "pen": Entry(word: "Pen", phonetic: "/pen/", vietnamese: "Bút viết", partOfSpeech: "Noun"),
        "ballpoint": Entry(word: "Ballpoint Pen", phonetic: "/ˈbɑːl.pɔɪnt/", vietnamese: "Bút bi", partOfSpeech: "Noun"),
        "pencil": Entry(word: "Pencil", phonetic: "/ˈpen.səl/", vietnamese: "Bút chì", partOfSpeech: "Noun"),
        "backpack": Entry(word: "Backpack", phonetic: "/ˈbæk.pæk/", vietnamese: "Ba lô", partOfSpeech: "Noun"),
        "bag": Entry(word: "Bag", phonetic: "/bæɡ/", vietnamese: "Túi xách", partOfSpeech: "Noun"),
        "desk": Entry(word: "Desk", phonetic: "/desk/", vietnamese: "Bàn làm việc", partOfSpeech: "Noun"),
        "chair": Entry(word: "Chair", phonetic: "/tʃer/", vietnamese: "Cái ghế", partOfSpeech: "Noun"),
        "paper": Entry(word: "Paper Sheet", phonetic: "/ˈpeɪ.pɚ/", vietnamese: "Tờ giấy", partOfSpeech: "Noun"),
        "glasses": Entry(word: "Glasses", phonetic: "/ˈɡlæs.ɪz/", vietnamese: "Kính mắt", partOfSpeech: "Noun"),
        "sunglasses": Entry(word: "Sunglasses", phonetic: "/ˈsʌnˌɡlæs.ɪz/", vietnamese: "Kính râm", partOfSpeech: "Noun"),

        // Drink & Dining
        "cup": Entry(word: "Cup", phonetic: "/kʌp/", vietnamese: "Cái cốc / tách", partOfSpeech: "Noun"),
        "coffee cup": Entry(word: "Coffee Cup", phonetic: "/ˈkɑː.fi kʌp/", vietnamese: "Tách cà phê", partOfSpeech: "Noun"),
        "mug": Entry(word: "Mug", phonetic: "/mʌɡ/", vietnamese: "Cốc uống nước có quai", partOfSpeech: "Noun"),
        "bottle": Entry(word: "Bottle", phonetic: "/ˈbɑː.t̬əl/", vietnamese: "Chai nước", partOfSpeech: "Noun"),
        "water bottle": Entry(word: "Water Bottle", phonetic: "/ˈwɑː.t̬ɚ ˌbɑː.t̬əl/", vietnamese: "Bình đựng nước", partOfSpeech: "Noun"),
        "glass": Entry(word: "Glass", phonetic: "/ɡlæs/", vietnamese: "Ly thuỷ tinh", partOfSpeech: "Noun"),
        "plate": Entry(word: "Plate", phonetic: "/pleɪt/", vietnamese: "Cái đĩa", partOfSpeech: "Noun"),
        "bowl": Entry(word: "Bowl", phonetic: "/boʊl/", vietnamese: "Cái bát / tô", partOfSpeech: "Noun"),
        "fork": Entry(word: "Fork", phonetic: "/fɔːrk/", vietnamese: "Cái dĩa", partOfSpeech: "Noun"),
        "spoon": Entry(word: "Spoon", phonetic: "/spuːn/", vietnamese: "Cái thìa / muỗng", partOfSpeech: "Noun"),

        // Food & Snacks
        "apple": Entry(word: "Apple", phonetic: "/ˈæp.əl/", vietnamese: "Quả táo", partOfSpeech: "Noun"),
        "banana": Entry(word: "Banana", phonetic: "/bəˈnæn.ə/", vietnamese: "Quả chuối", partOfSpeech: "Noun"),
        "orange": Entry(word: "Orange", phonetic: "/ˈɔːr.ɪndʒ/", vietnamese: "Quả cam", partOfSpeech: "Noun"),
        "bread": Entry(word: "Bread", phonetic: "/bred/", vietnamese: "Bánh mì", partOfSpeech: "Noun"),
        "coffee": Entry(word: "Coffee", phonetic: "/ˈkɑː.fi/", vietnamese: "Cà phê", partOfSpeech: "Noun"),

        // Personal & Accessories
        "shoes": Entry(word: "Shoes", phonetic: "/ʃuːz/", vietnamese: "Đôi giày", partOfSpeech: "Noun"),
        "sneakers": Entry(word: "Sneakers", phonetic: "/ˈsniː.kɚz/", vietnamese: "Giày thể thao", partOfSpeech: "Noun"),
        "wallet": Entry(word: "Wallet", phonetic: "/ˈwɑː.lɪt/", vietnamese: "Cái ví tiền", partOfSpeech: "Noun"),
        "key": Entry(word: "Key", phonetic: "/kiː/", vietnamese: "Chìa khóa", partOfSpeech: "Noun"),
        "hat": Entry(word: "Hat", phonetic: "/hæt/", vietnamese: "Cái mũ", partOfSpeech: "Noun"),

        // Living & Nature
        "dog": Entry(word: "Dog", phonetic: "/dɔːɡ/", vietnamese: "Con chó", partOfSpeech: "Noun"),
        "cat": Entry(word: "Cat", phonetic: "/kæt/", vietnamese: "Con mèo", partOfSpeech: "Noun"),
        "plant": Entry(word: "Houseplant", phonetic: "/ˈhaʊs.plænt/", vietnamese: "Cây cảnh trong nhà", partOfSpeech: "Noun"),
        "flower": Entry(word: "Flower", phonetic: "/ˈflaʊ.ɚ/", vietnamese: "Bông hoa", partOfSpeech: "Noun"),
        "window": Entry(word: "Window", phonetic: "/ˈwɪn.doʊ/", vietnamese: "Cửa sổ", partOfSpeech: "Noun"),
        "door": Entry(word: "Door", phonetic: "/dɔːr/", vietnamese: "Cánh cửa", partOfSpeech: "Noun"),
        "car": Entry(word: "Car", phonetic: "/kɑːr/", vietnamese: "Xe ô tô", partOfSpeech: "Noun"),
        "bicycle": Entry(word: "Bicycle", phonetic: "/ˈbaɪ.sə.kəl/", vietnamese: "Xe đạp", partOfSpeech: "Noun"),
        "person": Entry(word: "Person", phonetic: "/ˈpɝː.sən/", vietnamese: "Người", partOfSpeech: "Noun")
    ]

    public static func lookup(identifier: String) -> Entry? {
        let clean = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = entries[clean] {
            return exact
        }
        for (key, entry) in entries {
            if clean.contains(key) || key.contains(clean) {
                return entry
            }
        }
        return nil
    }
}

// MARK: - Real-Time Camera Manager (AVFoundation + Vision 30-60 FPS)

public final class RealTimeCameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {

    @Published public var detectedObjects: [ARScannedItem] = []
    @Published public var isRunning: Bool = false
    @Published public var isTorchOn: Bool = false
    @Published public var isUsingFrontCamera: Bool = false
    @Published public var isARScanningEnabled: Bool = true
    @Published public var fpsDisplay: String = "30 FPS"
    @Published public var isCameraAvailable: Bool = true

    public let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "vn.golabs.camera.sessionQueue")
    private let visionQueue = DispatchQueue(label: "vn.golabs.camera.visionQueue", qos: .userInteractive)

    private var currentDevice: AVCaptureDevice?
    private var lastAnalysisTimestamp: TimeInterval = 0
    private let analysisThrottleInterval: TimeInterval = 0.12 // ~8-10 scans/sec for peak efficiency

    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    public override init() {
        super.init()
        checkCameraAvailability()
    }

    public func checkCameraAvailability() {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        isCameraAvailable = (device != nil)
    }

    public func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Setup Video Input
            let position: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                DispatchQueue.main.async { self.isCameraAvailable = false }
                self.session.commitConfiguration()
                return
            }
            self.currentDevice = videoDevice

            guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoDeviceInput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(videoDeviceInput)

            // Setup Video Data Output (Real-time Frames)
            self.videoDataOutput.videoSettings = [
                (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.visionQueue)

            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
                if let connection = self.videoDataOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = self.isUsingFrontCamera
                    }
                }
            }

            // Setup Photo Output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
            }

            self.session.commitConfiguration()
        }
    }

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    public func toggleTorch() {
        guard let device = currentDevice, device.hasTorch else { return }
        try? device.lockForConfiguration()
        if device.torchMode == .on {
            device.torchMode = .off
            isTorchOn = false
        } else {
            try? device.setTorchModeOn(level: 1.0)
            isTorchOn = true
        }
        device.unlockForConfiguration()
    }

    public func switchCamera() {
        isUsingFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            // Remove existing inputs
            for input in self.session.inputs {
                self.session.removeInput(input)
            }

            let position: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            if let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let newInput = try? AVCaptureDeviceInput(device: newDevice),
               self.session.canAddInput(newInput) {
                self.currentDevice = newDevice
                self.session.addInput(newInput)

                if let connection = self.videoDataOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = self.isUsingFrontCamera
                    }
                }
            }

            self.session.commitConfiguration()
        }
    }

    public func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.photoCaptureCompletion = completion
        sessionQueue.async { [weak self] in
            guard let self else { return }
            var settings = AVCapturePhotoSettings()
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            settings.isHighResolutionPhotoEnabled = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.photoCaptureCompletion?(nil)
            }
            return
        }

        // Fix orientation if needed
        let fixed = Self.normalizeImage(image)
        DispatchQueue.main.async {
            self.photoCaptureCompletion?(fixed)
        }
    }

    private static func normalizeImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isARScanningEnabled else {
            DispatchQueue.main.async {
                if !self.detectedObjects.isEmpty { self.detectedObjects = [] }
            }
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastAnalysisTimestamp >= analysisThrottleInterval else { return }
        lastAnalysisTimestamp = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Run On-Device Vision Requests
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        var itemsFound: [ARScannedItem] = []

        // 1. Detect Animals (Dogs, Cats) with Bounding Boxes
        let animalRequest = VNRecognizeAnimalsRequest()
        if (try? handler.perform([animalRequest])) != nil, let results = animalRequest.results {
            for animal in results.prefix(2) where animal.confidence > 0.6 {
                let label = animal.labels.first?.identifier ?? "animal"
                if let entry = EverydayVocabularyDictionary.lookup(identifier: label) {
                    let box = convertVisionRectToUIKit(animal.boundingBox)
                    itemsFound.append(
                        ARScannedItem(
                            word: entry.word,
                            phonetic: entry.phonetic,
                            vietnameseMeaning: entry.vietnamese,
                            partOfSpeech: entry.partOfSpeech,
                            boundingBox: box,
                            confidence: animal.confidence
                        )
                    )
                }
            }
        }

        // 2. Detect Screens, Books, Tablets, Cards with Rectangles
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.maximumObservations = 2
        rectRequest.minimumConfidence = 0.65
        rectRequest.minimumSize = 0.15
        if (try? handler.perform([rectRequest])) != nil, let rects = rectRequest.results {
            for r in rects where itemsFound.count < 3 {
                let box = convertVisionRectToUIKit(r.boundingBox)
                // If it's a large horizontal rectangle, likely laptop or screen; if smaller, notebook/book
                let isWide = box.width > box.height
                let wordKey = isWide ? "laptop" : "book"
                if let entry = EverydayVocabularyDictionary.lookup(identifier: wordKey) {
                    itemsFound.append(
                        ARScannedItem(
                            word: entry.word,
                            phonetic: entry.phonetic,
                            vietnameseMeaning: entry.vietnamese,
                            partOfSpeech: entry.partOfSpeech,
                            boundingBox: box,
                            confidence: r.confidence
                        )
                    )
                }
            }
        }

        // 3. Classify Image Semantics to identify specific objects
        let classifyRequest = VNClassifyImageRequest()
        if (try? handler.perform([classifyRequest])) != nil, let observations = classifyRequest.results {
            for obs in observations.prefix(15) where obs.confidence > 0.45 {
                let cleanID = obs.identifier
                if let entry = EverydayVocabularyDictionary.lookup(identifier: cleanID) {
                    // Check if already detected
                    if !itemsFound.contains(where: { $0.word == entry.word }) {
                        // Position in comfortable center focal area if box is not explicitly geometric
                        let centerBox = CGRect(x: 0.25, y: 0.35, width: 0.50, height: 0.30)
                        itemsFound.append(
                            ARScannedItem(
                                word: entry.word,
                                phonetic: entry.phonetic,
                                vietnameseMeaning: entry.vietnamese,
                                partOfSpeech: entry.partOfSpeech,
                                boundingBox: centerBox,
                                confidence: obs.confidence
                            )
                        )
                    }
                    if itemsFound.count >= 4 { break }
                }
            }
        }

        // Merge & Publish smoothly on Main Thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.detectedObjects = itemsFound
        }
    }

    /// Vision bounding boxes have (0,0) at bottom-left; UIKit has (0,0) at top-left.
    private func convertVisionRectToUIKit(_ visionRect: CGRect) -> CGRect {
        return CGRect(
            x: max(0.02, min(0.96, visionRect.origin.x)),
            y: max(0.02, min(0.96, 1.0 - visionRect.origin.y - visionRect.height)),
            width: max(0.05, min(0.95, visionRect.width)),
            height: max(0.05, min(0.95, visionRect.height))
        )
    }
}
