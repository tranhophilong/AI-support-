//
//  IOSObjectDetectorService.swift
//  English Corrector
//
//  Created by Antigravity on 2026-10-31.
//  Reference: Apple Vision Framework - Detecting Objects in Still Images
//

import UIKit
import Vision
import CoreGraphics
import CoreImage

/// Result of on-device iOS object detection, intelligent cropping, and contour boundary extraction
struct IOSDetectedObjectResult: Sendable {
    /// The high-resolution cropped image isolating the targeted object
    let croppedImage: UIImage

    /// Isolated cutout with background removed (transparent background) if foreground instance masking succeeded
    let cutoutImage: UIImage?

    /// Compressed JPEG data (~25-60KB) ready for multimodal AI vision analysis
    let croppedImageData: Data

    /// Refined center point (0...100%) in UIKit coordinates (top-left is 0,0)
    /// Snapped directly to the true center (tâm) of the cutoff object
    let refinedCenterPercent: CGPoint

    /// Bounding box (0...100%) in UIKit coordinates (x, y, width, height) of the detected subject
    let boundingBoxPercent: CGRect

    /// Bounding box with context padding (0...100%) matching croppedImage and cutoutImage dimensions
    let paddedBoxPercent: CGRect

    /// Visual grounding bounding box formatted as [ymin, xmin, ymax, xmax] (0...100%)
    var box2dGrounding: [Double] {
        [
            boundingBoxPercent.minY,
            boundingBoxPercent.minX,
            boundingBoxPercent.maxY,
            boundingBoxPercent.maxX
        ]
    }

    /// Detected curved and rounded border contour loops of the object in normalized 0...1 Vision space
    let contourLoops: [[CGPoint]]

    /// Confident on-device classification keywords (confidence >= 0.55), empty if uncertain
    let onDeviceLabels: [String]

    /// Whether Apple Vision detected a distinct physical object (true) or used smart focus crop (false)
    let isObjectMatched: Bool
}

/// Metrics describing the geometry and center of mass of a cutoff object
struct CutoutMetrics: Sendable {
    /// Weighted center of mass of the non-transparent cutout pixels in normalized 0...1 space (0,0 is top-left)
    let center: CGPoint
    /// Tight bounding box around non-transparent cutout pixels in normalized 0...1 space (0,0 is top-left)
    let bounds: CGRect
}

/// Lightweight summary of an object detected on-device
struct IOSDetectedObjectSummary: Sendable {
    let word: String
    let xPercent: Double
    let yPercent: Double
    let box2d: [Double]
}

final class IOSObjectDetectorService: Sendable {
    static let shared = IOSObjectDetectorService()

    private init() {}

    // Generic taxonomy words that do NOT represent specific physical everyday objects
    private static let genericTaxonomyBlacklist: Set<String> = [
        "artifact", "room", "indoor", "outdoor", "object", "device", "goods",
        "structure", "material", "equipment", "instrument", "furnishing",
        "tableware", "container", "consumer goods", "commodity", "entity",
        "mammal", "animal", "vertebrate", "invertebrate", "living thing",
        "part", "feature", "surface", "background", "foreground", "scene",
        "decoration", "decoration item", "item", "holding", "covering"
    ]

    /// Detects the specific physical object at (xPercent, yPercent) in accordance with Apple's Vision Object Detection guidelines.
    /// Supports user-drawn custom bounding boxes (lasso/swipe gesture around an item) to crop and cutoff with pixel precision.
    func detectAndCropObject(
        from image: UIImage,
        inCustomBoxPercent customBox: CGRect? = nil,
        atXPercent xPercent: Double,
        yPercent: Double
    ) async throws -> IOSDetectedObjectResult {
        // 1. Ensure image is normalized with orientation .up
        let normalizedImage = normalizeImageOrientation(image)
        guard let cgImage = normalizedImage.cgImage else {
            throw AIServiceError.apiError(provider: "Vision", message: "Không thể xử lý dữ liệu ảnh")
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        guard imageWidth > 10 && imageHeight > 10 else {
            throw AIServiceError.apiError(provider: "Vision", message: "Kích thước ảnh không hợp lệ")
        }

        let clampedX = max(0.01, min(0.99, xPercent / 100.0))
        let clampedY = max(0.01, min(0.99, yPercent / 100.0))
        let visionPoint = CGPoint(x: clampedX, y: 1.0 - clampedY)

        let normalizedCustomBox: CGRect? = customBox.map { box in
            let minX = max(0.0, min(0.96, box.minX / 100.0))
            let minY = max(0.0, min(0.96, box.minY / 100.0))
            let maxX = max(minX + 0.03, min(1.0, box.maxX / 100.0))
            let maxY = max(minY + 0.03, min(1.0, box.maxY / 100.0))
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 2. High-precision instance segmentation (iOS 17+)
        // Directly isolate the targeted object at (clampedX, clampedY) or within user-swiped customBox
        if #available(iOS 17.0, *) {
            let maskRequest = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([maskRequest])) != nil,
               let observation = maskRequest.results?.first,
               !observation.allInstances.isEmpty {
                let targetInstances = findInstanceIndices(
                    in: observation,
                    customBox: normalizedCustomBox,
                    atX: clampedX,
                    y: clampedY
                )
                if !targetInstances.isEmpty,
                   let maskedBuffer = try? observation.generateMaskedImage(
                    ofInstances: targetInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                   ) {
                    let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
                    let ciContext = CIContext(options: nil)
                    if let outputCG = ciContext.createCGImage(ciImage, from: ciImage.extent),
                       let metrics = computeCutoutMetrics(from: outputCG) {
                        // Allow larger foreground objects (especially when user explicitly swiped customBox around a large item)
                        let maxAllowedArea: CGFloat = (normalizedCustomBox != nil) ? 0.96 : 0.85
                        if metrics.bounds.width >= 0.015 && metrics.bounds.height >= 0.015 &&
                            (metrics.bounds.width * metrics.bounds.height) < maxAllowedArea {

                            // Combine Vision instance bounds with user-swiped customBox so neither clips the bottom of large objects
                            let itemBox: CGRect
                            let didMaskClipBottom: Bool
                            if let userBox = normalizedCustomBox {
                                itemBox = metrics.bounds.union(userBox)
                                didMaskClipBottom = (userBox.maxY - metrics.bounds.maxY) > max(0.05, userBox.height * 0.16)
                            } else {
                                itemBox = metrics.bounds
                                didMaskClipBottom = false
                            }

                            let padX = max(0.014, itemBox.width * 0.16)
                            let padTop = max(0.014, itemBox.height * 0.16)
                            let padBottom = max(0.020, itemBox.height * 0.20)
                            let pMinX = max(0.0, itemBox.minX - padX)
                            let pMinY = max(0.0, itemBox.minY - padTop)
                            let pMaxX = min(1.0, itemBox.maxX + padX)
                            let pMaxY = min(1.0, itemBox.maxY + padBottom)

                            let paddedBox = CGRect(
                                x: pMinX,
                                y: pMinY,
                                width: max(0.03, pMaxX - pMinX),
                                height: max(0.03, pMaxY - pMinY)
                            )

                            let pixelRect = CGRect(
                                x: paddedBox.origin.x * imageWidth,
                                y: paddedBox.origin.y * imageHeight,
                                width: paddedBox.size.width * imageWidth,
                                height: paddedBox.size.height * imageHeight
                            ).integral

                            if let croppedCG = cgImage.cropping(to: pixelRect) {
                                let croppedUIImage = UIImage(cgImage: croppedCG)
                                let cutoutCG = outputCG.cropping(to: pixelRect)
                                let cutoutUIImage: UIImage?
                                if didMaskClipBottom {
                                    // Re-extract cutout directly from full croppedCG (including all instances) so bottom is never cut off
                                    let (fallbackCutout, fallbackMetrics) = extractForegroundCutout(
                                        for: croppedCG,
                                        includeAllInstances: true
                                    )
                                    if let fbMetrics = fallbackMetrics, fbMetrics.bounds.maxY >= 0.78 {
                                        cutoutUIImage = fallbackCutout
                                    } else {
                                        cutoutUIImage = nil
                                    }
                                } else {
                                    cutoutUIImage = cutoutCG != nil ? UIImage(cgImage: cutoutCG!) : nil
                                }

                                let jpegData = croppedUIImage.jpegData(compressionQuality: 0.85) ?? Data()
                                let contourLoops = extractContourLoops(for: (didMaskClipBottom ? nil : cutoutCG) ?? croppedCG)
                                let onDeviceLabels = detectOnDeviceLabels(for: croppedCG, animalLabel: nil)

                                let finalCenterPercent = CGPoint(
                                    x: max(2.0, min(98.0, itemBox.midX * 100.0)),
                                    y: max(2.0, min(98.0, itemBox.midY * 100.0))
                                )
                                let finalBoundingBoxPercent = CGRect(
                                    x: itemBox.minX * 100.0,
                                    y: itemBox.minY * 100.0,
                                    width: max(2.0, itemBox.width * 100.0),
                                    height: max(2.0, itemBox.height * 100.0)
                                )
                                let paddedBoxPercent = CGRect(
                                    x: paddedBox.minX * 100.0,
                                    y: paddedBox.minY * 100.0,
                                    width: paddedBox.width * 100.0,
                                    height: paddedBox.height * 100.0
                                )

                                return IOSDetectedObjectResult(
                                    croppedImage: croppedUIImage,
                                    cutoutImage: cutoutUIImage,
                                    croppedImageData: jpegData,
                                    refinedCenterPercent: finalCenterPercent,
                                    boundingBoxPercent: finalBoundingBoxPercent,
                                    paddedBoxPercent: paddedBoxPercent,
                                    contourLoops: contourLoops,
                                    onDeviceLabels: onDeviceLabels,
                                    isObjectMatched: true
                                )
                            }
                        }
                    }
                }
            }
        }

        // If user swiped around a specific region, directly prioritize the user's circled box
        if let uiBox = normalizedCustomBox {
            let padX = max(0.015, uiBox.width * 0.12)
            let padTop = max(0.015, uiBox.height * 0.12)
            let padBottom = max(0.022, uiBox.height * 0.18)
            let pMinX = max(0.0, uiBox.minX - padX)
            let pMinY = max(0.0, uiBox.minY - padTop)
            let pMaxX = min(1.0, uiBox.maxX + padX)
            let pMaxY = min(1.0, uiBox.maxY + padBottom)

            let paddedBox = CGRect(
                x: pMinX,
                y: pMinY,
                width: max(0.04, pMaxX - pMinX),
                height: max(0.04, pMaxY - pMinY)
            )

            let pixelRect = CGRect(
                x: paddedBox.origin.x * imageWidth,
                y: paddedBox.origin.y * imageHeight,
                width: paddedBox.size.width * imageWidth,
                height: paddedBox.size.height * imageHeight
            ).integral

            if let croppedCG = cgImage.cropping(to: pixelRect) {
                let croppedUIImage = UIImage(cgImage: croppedCG)
                let jpegData = croppedUIImage.jpegData(compressionQuality: 0.85) ?? Data()
                let contourLoops = extractContourLoops(for: croppedCG)
                let (rawCutoutImage, cutoutMetrics) = extractForegroundCutout(
                    for: croppedCG,
                    includeAllInstances: true
                )
                // Keep cutout only if it doesn't chop off the bottom of the swiped object
                let cutoutImage: UIImage?
                if let metrics = cutoutMetrics, metrics.bounds.maxY < 0.75 && uiBox.height > 0.25 {
                    cutoutImage = nil
                } else {
                    cutoutImage = rawCutoutImage
                }
                let onDeviceLabels = detectOnDeviceLabels(for: croppedCG, animalLabel: nil)

                let finalCenterPercent: CGPoint
                let finalBoundingBoxPercent: CGRect

                if let metrics = cutoutMetrics, cutoutImage != nil {
                    let metricBoxInFull = CGRect(
                        x: paddedBox.minX + metrics.bounds.minX * paddedBox.width,
                        y: paddedBox.minY + metrics.bounds.minY * paddedBox.height,
                        width: metrics.bounds.width * paddedBox.width,
                        height: metrics.bounds.height * paddedBox.height
                    ).union(uiBox)

                    finalCenterPercent = CGPoint(
                        x: max(2.0, min(98.0, metricBoxInFull.midX * 100.0)),
                        y: max(2.0, min(98.0, metricBoxInFull.midY * 100.0))
                    )
                    finalBoundingBoxPercent = CGRect(
                        x: metricBoxInFull.minX * 100.0,
                        y: metricBoxInFull.minY * 100.0,
                        width: max(2.0, metricBoxInFull.width * 100.0),
                        height: max(2.0, metricBoxInFull.height * 100.0)
                    )
                } else {
                    finalCenterPercent = CGPoint(
                        x: max(2.0, min(98.0, uiBox.midX * 100.0)),
                        y: max(2.0, min(98.0, uiBox.midY * 100.0))
                    )
                    finalBoundingBoxPercent = CGRect(
                        x: uiBox.origin.x * 100.0,
                        y: uiBox.origin.y * 100.0,
                        width: uiBox.size.width * 100.0,
                        height: uiBox.size.height * 100.0
                    )
                }

                let paddedBoxPercent = CGRect(
                    x: paddedBox.origin.x * 100.0,
                    y: paddedBox.origin.y * 100.0,
                    width: paddedBox.size.width * 100.0,
                    height: paddedBox.size.height * 100.0
                )

                return IOSDetectedObjectResult(
                    croppedImage: croppedUIImage,
                    cutoutImage: cutoutImage,
                    croppedImageData: jpegData,
                    refinedCenterPercent: finalCenterPercent,
                    boundingBoxPercent: finalBoundingBoxPercent,
                    paddedBoxPercent: paddedBoxPercent,
                    contourLoops: contourLoops,
                    onDeviceLabels: onDeviceLabels,
                    isObjectMatched: true
                )
            }
        }

        // 3. Fallback Multi-request pipeline: Rectangle detection + Animal recognition + Saliency objectness
        // Reduced rectangle minimum size to 0.01 to capture small items (pens, cards, phones, etc.)
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumConfidence = 0.40
        rectRequest.minimumSize = 0.01

        let animalRequest = VNRecognizeAnimalsRequest()
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()

        try? handler.perform([rectRequest, animalRequest, saliencyRequest])

        // 4. Collect candidate bounding boxes that strictly contain visionPoint
        var candidateBoxes: [CGRect] = []
        var detectedAnimalLabel: String? = nil

        // A. Animals (e.g. Dog, Cat)
        if let animalObs = animalRequest.results {
            for obs in animalObs where obs.confidence >= 0.60 {
                let box = obs.boundingBox
                if box.contains(visionPoint) {
                    candidateBoxes.append(box)
                    if let topLabel = obs.labels.first(where: { $0.confidence >= 0.60 }) {
                        detectedAnimalLabel = topLabel.identifier.capitalized
                    }
                }
            }
        }

        // B. Rectangular objects (phones, monitors, books, cards, papers, boxes, keyboards, pens)
        if let rectObs = rectRequest.results {
            for obs in rectObs where obs.confidence >= 0.40 {
                let box = obs.boundingBox
                if box.contains(visionPoint) && (box.width * box.height) < 0.60 {
                    candidateBoxes.append(box)
                }
            }
        }

        // C. Salient object regions (only accept if smaller than 0.20 area to prevent capturing whole room/table)
        if let saliencyObs = saliencyRequest.results?.first,
           let salientObjects = saliencyObs.salientObjects {
            for obj in salientObjects {
                let box = obj.boundingBox
                if box.contains(visionPoint) && (box.width * box.height) < 0.20 {
                    candidateBoxes.append(box)
                }
            }
        }

        var matchedVisionBox: CGRect? = nil
        var isObjectMatched = false

        // Pick the most specific (smallest area) box that directly contains the touched point
        if let mostSpecific = candidateBoxes.min(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
            matchedVisionBox = mostSpecific
            isObjectMatched = true
        }

        // 5. Resolve UIKit bounding box & refined center
        let uiBox: CGRect
        let refinedCenterPercent: CGPoint

        if let vBox = matchedVisionBox, isObjectMatched {
            let uiX = vBox.origin.x
            let uiY = 1.0 - (vBox.origin.y + vBox.size.height)
            let uiW = vBox.size.width
            let uiH = vBox.size.height

            uiBox = CGRect(
                x: max(0.0, min(0.95, uiX)),
                y: max(0.0, min(0.95, uiY)),
                width: max(0.03, min(1.0, uiW)),
                height: max(0.03, min(1.0, uiH))
            )

            refinedCenterPercent = CGPoint(
                x: max(2.0, min(98.0, uiBox.midX * 100.0)),
                y: max(2.0, min(98.0, uiBox.midY * 100.0))
            )
        } else {
            // Adaptive compact focus window for small items in zoomed-out view (12% of image, not 26%)
            let focusDimension: CGFloat = 0.12
            let originX = max(0.0, min(1.0 - focusDimension, clampedX - focusDimension / 2.0))
            let originY = max(0.0, min(1.0 - focusDimension, clampedY - focusDimension / 2.0))
            uiBox = CGRect(x: originX, y: originY, width: focusDimension, height: focusDimension)

            refinedCenterPercent = CGPoint(x: xPercent, y: yPercent)
        }

        // 6. Expand bounding box by moderate padding (12%) for context
        let padX = uiBox.width * 0.12
        let padY = uiBox.height * 0.12
        let paddedMinX = max(0.0, uiBox.minX - padX)
        let paddedMinY = max(0.0, uiBox.minY - padY)
        let paddedMaxX = min(1.0, uiBox.maxX + padX)
        let paddedMaxY = min(1.0, uiBox.maxY + padY)

        let paddedBox = CGRect(
            x: paddedMinX,
            y: paddedMinY,
            width: max(0.03, paddedMaxX - paddedMinX),
            height: max(0.03, paddedMaxY - paddedMinY)
        )

        // 7. Crop CGImage with pixel precision
        let pixelRect = CGRect(
            x: paddedBox.origin.x * imageWidth,
            y: paddedBox.origin.y * imageHeight,
            width: paddedBox.size.width * imageWidth,
            height: paddedBox.size.height * imageHeight
        ).integral

        guard let croppedCG = cgImage.cropping(to: pixelRect) else {
            throw AIServiceError.apiError(provider: "Vision", message: "Không thể cắt vùng ảnh vật thể")
        }

        let croppedUIImage = UIImage(cgImage: croppedCG)
        guard let jpegData = croppedUIImage.jpegData(compressionQuality: 0.85) else {
            throw AIServiceError.apiError(provider: "Vision", message: "Lỗi nén ảnh vật thể")
        }

        // 8. Extract Object Curves & Contours
        let contourLoops = extractContourLoops(for: croppedCG)

        // 9. Extract Foreground Subject Cutout
        let (cutoutImage, cutoutMetrics) = extractForegroundCutout(for: croppedCG)

        // 10. Local Classification
        let onDeviceLabels = detectOnDeviceLabels(for: croppedCG, animalLabel: detectedAnimalLabel)

        let paddedBoxPercent = CGRect(
            x: paddedBox.origin.x * 100.0,
            y: paddedBox.origin.y * 100.0,
            width: paddedBox.size.width * 100.0,
            height: paddedBox.size.height * 100.0
        )

        let finalCenterPercent: CGPoint
        let finalBoundingBoxPercent: CGRect

        if let metrics = cutoutMetrics {
            finalCenterPercent = CGPoint(
                x: max(2.0, min(98.0, (paddedBox.minX + metrics.center.x * paddedBox.width) * 100.0)),
                y: max(2.0, min(98.0, (paddedBox.minY + metrics.center.y * paddedBox.height) * 100.0))
            )
            finalBoundingBoxPercent = CGRect(
                x: (paddedBox.minX + metrics.bounds.minX * paddedBox.width) * 100.0,
                y: (paddedBox.minY + metrics.bounds.minY * paddedBox.height) * 100.0,
                width: max(2.0, metrics.bounds.width * paddedBox.width * 100.0),
                height: max(2.0, metrics.bounds.height * paddedBox.height * 100.0)
            )
        } else {
            finalCenterPercent = refinedCenterPercent
            finalBoundingBoxPercent = CGRect(
                x: uiBox.origin.x * 100.0,
                y: uiBox.origin.y * 100.0,
                width: uiBox.size.width * 100.0,
                height: uiBox.size.height * 100.0
            )
        }

        return IOSDetectedObjectResult(
            croppedImage: croppedUIImage,
            cutoutImage: cutoutImage,
            croppedImageData: jpegData,
            refinedCenterPercent: finalCenterPercent,
            boundingBoxPercent: finalBoundingBoxPercent,
            paddedBoxPercent: paddedBoxPercent,
            contourLoops: contourLoops,
            onDeviceLabels: onDeviceLabels,
            isObjectMatched: isObjectMatched
        )
    }

    /// Scans the full image with Apple Vision to pre-detect physical objects and their visual coordinates.
    /// Captures small individual items accurately across the entire image.
    func scanAllObjectsInImage(from image: UIImage) -> [IOSDetectedObjectSummary] {
        let normalizedImage = normalizeImageOrientation(image)
        guard let cgImage = normalizedImage.cgImage else { return [] }

        var candidateBoxes: [(box: CGRect, label: String)] = []
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1. Discover individual small and medium instances via Instance Masking (iOS 17+)
        if #available(iOS 17.0, *) {
            let maskRequest = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([maskRequest])) != nil,
               let observation = maskRequest.results?.first,
               !observation.allInstances.isEmpty {
                for instId in observation.allInstances.prefix(12) {
                    if let masked = try? observation.generateMaskedImage(
                        ofInstances: IndexSet(integer: instId),
                        from: handler,
                        croppedToInstancesExtent: false
                    ) {
                        let ci = CIImage(cvPixelBuffer: masked)
                        let ctx = CIContext(options: nil)
                        if let outCG = ctx.createCGImage(ci, from: ci.extent),
                           let metrics = computeCutoutMetrics(from: outCG) {
                            let b = metrics.bounds
                            if b.width >= 0.02 && b.height >= 0.02 && (b.width * b.height) < 0.45 {
                                let visionBox = CGRect(
                                    x: b.minX,
                                    y: 1.0 - (b.minY + b.height),
                                    width: b.width,
                                    height: b.height
                                )
                                let pixelRect = CGRect(
                                    x: b.minX * CGFloat(cgImage.width),
                                    y: b.minY * CGFloat(cgImage.height),
                                    width: b.width * CGFloat(cgImage.width),
                                    height: b.height * CGFloat(cgImage.height)
                                ).integral
                                var label = "item"
                                if pixelRect.width > 20 && pixelRect.height > 20,
                                   let cropped = cgImage.cropping(to: pixelRect) {
                                    let localLabels = detectOnDeviceLabels(for: cropped, animalLabel: nil)
                                    if let first = localLabels.first {
                                        label = first
                                    }
                                }
                                candidateBoxes.append((visionBox, label))
                            }
                        }
                    }
                }
            }
        }

        // 2. Rectangle & Animal detection
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumConfidence = 0.45
        rectRequest.minimumSize = 0.02

        let animalRequest = VNRecognizeAnimalsRequest()
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()

        try? handler.perform([rectRequest, animalRequest, saliencyRequest])

        if let animalObs = animalRequest.results {
            for obs in animalObs where obs.confidence >= 0.65 {
                let name = obs.labels.first?.identifier.capitalized ?? "Pet"
                candidateBoxes.append((obs.boundingBox, name))
            }
        }

        if let rectObs = rectRequest.results {
            for obs in rectObs where obs.confidence >= 0.45 {
                if (obs.boundingBox.width * obs.boundingBox.height) < 0.50 {
                    let isWide = obs.boundingBox.width > obs.boundingBox.height
                    candidateBoxes.append((obs.boundingBox, isWide ? "laptop" : "book"))
                }
            }
        }

        if let saliencyObs = saliencyRequest.results?.first,
           let salientObjects = saliencyObs.salientObjects {
            for obj in salientObjects {
                let b = obj.boundingBox
                if b.width >= 0.03 && b.height >= 0.03 && (b.width * b.height) < 0.30 {
                    candidateBoxes.append((b, "item"))
                }
            }
        }

        // Deduplicate overlapping boxes
        var uniqueBoxes: [(box: CGRect, label: String)] = []
        for candidate in candidateBoxes.prefix(12) {
            let isOverlapping = uniqueBoxes.contains { existing in
                let intersection = existing.box.intersection(candidate.box)
                let unionArea = (existing.box.width * existing.box.height) + (candidate.box.width * candidate.box.height) - (intersection.width * intersection.height)
                return unionArea > 0 && (intersection.width * intersection.height) / unionArea > 0.45
            }
            if !isOverlapping {
                uniqueBoxes.append(candidate)
            }
        }

        var summaries: [IOSDetectedObjectSummary] = []
        for item in uniqueBoxes.prefix(8) {
            let vBox = item.box
            let uiX = vBox.origin.x
            let uiY = 1.0 - (vBox.origin.y + vBox.size.height)
            let uiW = vBox.size.width
            let uiH = vBox.size.height

            let xPercent = max(2.0, min(98.0, (uiX + uiW / 2.0) * 100.0))
            let yPercent = max(2.0, min(98.0, (uiY + uiH / 2.0) * 100.0))
            let box2d: [Double] = [
                Double(uiY * 100.0),
                Double(uiX * 100.0),
                Double((uiY + uiH) * 100.0),
                Double((uiX + uiW) * 100.0)
            ]

            summaries.append(IOSDetectedObjectSummary(
                word: item.label,
                xPercent: Double(xPercent),
                yPercent: Double(yPercent),
                box2d: box2d
            ))
        }

        return summaries
    }

    // MARK: - Foreground Instance Lookup

    /// Collects all foreground instance indices for a user-swiped customBox (including lower base/parts of large objects)
    /// or finds the single targeted instance at (x, y) when customBox is nil.
    @available(iOS 17.0, *)
    private func findInstanceIndices(
        in observation: VNInstanceMaskObservation,
        customBox: CGRect?,
        atX x: Double,
        y: Double
    ) -> IndexSet {
        var indices = IndexSet()

        if let box = customBox {
            let pixelBuffer = observation.instanceMask
            if CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess {
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

                    let insetX = box.width * 0.12
                    let insetTop = box.height * 0.08
                    let insetBottom = box.height * 0.04
                    let minPX = max(0, min(width - 1, Int((box.minX + insetX) * CGFloat(width))))
                    let maxPX = max(minPX, min(width - 1, Int((box.maxX - insetX) * CGFloat(width))))
                    let minPY = max(0, min(height - 1, Int((box.minY + insetTop) * CGFloat(height))))
                    let maxPY = max(minPY, min(height - 1, Int((box.maxY - insetBottom) * CGFloat(height))))

                    let stepX = max(1, (maxPX - minPX) / 10)
                    let stepY = max(1, (maxPY - minPY) / 14)

                    for py in stride(from: minPY, through: maxPY, by: stepY) {
                        for px in stride(from: minPX, through: maxPX, by: stepX) {
                            let val = Int(buffer[py * bytesPerRow + px])
                            if val > 0 && observation.allInstances.contains(val) {
                                indices.insert(val)
                            }
                        }
                    }
                }
            }
        }

        if let primary = findInstanceIndex(in: observation, atX: x, y: y) {
            indices.insert(primary)
        }

        return indices
    }

    /// Finds the individual foreground instance index at normalized coordinates (0...1, top-left origin)
    @available(iOS 17.0, *)
    private func findInstanceIndex(
        in observation: VNInstanceMaskObservation,
        atX x: Double,
        y: Double
    ) -> Int? {
        let pixelBuffer = observation.instanceMask
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let centerX = max(0, min(width - 1, Int(x * Double(width))))
        let centerY = max(0, min(height - 1, Int(y * Double(height))))

        // 1. Direct hit at touched pixel
        let directVal = Int(buffer[centerY * bytesPerRow + centerX])
        if directVal > 0 && observation.allInstances.contains(directVal) {
            return directVal
        }

        // 2. Expanding radial search to catch touches on borders/rims of small items (up to 20 pixels in mask space)
        let maxRadius = min(20, min(width / 4, height / 4))
        for r in 1...maxRadius {
            for dy in -r...r {
                for dx in -r...r {
                    if abs(dx) != r && abs(dy) != r { continue }
                    let px = centerX + dx
                    let py = centerY + dy
                    if px >= 0 && px < width && py >= 0 && py < height {
                        let val = Int(buffer[py * bytesPerRow + px])
                        if val > 0 && observation.allInstances.contains(val) {
                            return val
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Contour & Silhouette Detection

    /// Detects the curved borders, corners, and contours of the physical object inside the cropped image
    private func extractContourLoops(for cgImage: CGImage) -> [[CGPoint]] {
        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 1.6
        contourRequest.detectsDarkOnLight = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([contourRequest])) != nil,
              let observation = contourRequest.results?.first else {
            return []
        }

        var loops: [[CGPoint]] = []

        for top in observation.topLevelContours {
            let box = top.normalizedPath.boundingBox
            if box.width > 0.94 && box.height > 0.94 {
                for child in top.childContours {
                    if child.pointCount >= 8 {
                        let pts = child.normalizedPoints.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
                        loops.append(pts)
                    }
                }
            } else if top.pointCount >= 8 {
                let pts = top.normalizedPoints.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
                loops.append(pts)
            }
        }

        return Array(loops.prefix(3))
    }

    /// Separates the subject from the background using Apple Foreground Instance Masking (iOS 17+)
    /// and extracts geometric metrics (center of mass and tight bounding box) of the cutoff subject.
    /// Prioritizes the central item in the crop over any surrounding background items.
    private func extractForegroundCutout(
        for cgImage: CGImage,
        includeAllInstances: Bool = false
    ) -> (image: UIImage?, metrics: CutoutMetrics?) {
        if #available(iOS 17.0, *) {
            let maskRequest = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            guard (try? handler.perform([maskRequest])) != nil,
                  let result = maskRequest.results?.first,
                  !result.allInstances.isEmpty else {
                return (nil, nil)
            }

            // When user swiped a lasso around a large object, include all instances inside the crop so the bottom part is never cut off
            let selectedInstances: IndexSet
            if includeAllInstances {
                selectedInstances = result.allInstances
            } else if let centerInstance = findInstanceIndex(in: result, atX: 0.5, y: 0.5) {
                selectedInstances = IndexSet(integer: centerInstance)
            } else {
                selectedInstances = result.allInstances
            }

            guard let maskedBuffer = try? result.generateMaskedImage(
                ofInstances: selectedInstances,
                from: handler,
                croppedToInstancesExtent: false
            ) else {
                return (nil, nil)
            }

            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let ciContext = CIContext(options: nil)
            if let outputCG = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                let metrics = computeCutoutMetrics(from: outputCG)
                return (UIImage(cgImage: outputCG), metrics)
            }
        }
        return (nil, nil)
    }

    /// Computes the true center of mass (tâm) and tight bounding box of the non-transparent pixels in the cutoff image.
    private func computeCutoutMetrics(from cgImage: CGImage) -> CutoutMetrics? {
        let width = 128
        let height = 128
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // In CoreGraphics bitmap contexts, ctx.draw(cgImage, in:) already writes the top of cgImage into row 0 of pixels
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var sumX: Double = 0
        var sumY: Double = 0
        var totalWeight: Double = 0

        for y in 0..<height {
            let rowStart = y * width * 4
            for x in 0..<width {
                let offset = rowStart + (x * 4)
                let alpha = pixels[offset + 3]
                if alpha > 30 {
                    let w = Double(alpha)
                    sumX += Double(x) * w
                    sumY += Double(y) * w
                    totalWeight += w

                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard totalWeight > 0, minX <= maxX, minY <= maxY else { return nil }

        let center = CGPoint(
            x: (sumX / totalWeight) / Double(width),
            y: (sumY / totalWeight) / Double(height)
        )
        let normMinX = CGFloat(minX) / CGFloat(width)
        let normMaxX = CGFloat(maxX + 1) / CGFloat(width)
        let normMinY = CGFloat(minY) / CGFloat(height)
        let normMaxY = CGFloat(maxY + 1) / CGFloat(height)

        let bounds = CGRect(
            x: normMinX,
            y: normMinY,
            width: max(0.01, normMaxX - normMinX),
            height: max(0.01, normMaxY - normMinY)
        )

        return CutoutMetrics(center: center, bounds: bounds)
    }

    // MARK: - Local Classification

    /// Runs local classification on the cropped object, strictly requiring confidence >= 0.55 and rejecting generic taxonomy words
    private func detectOnDeviceLabels(for cgImage: CGImage, animalLabel: String?) -> [String] {
        if let animal = animalLabel, !animal.isEmpty {
            return [animal]
        }

        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([classifyRequest])) != nil,
              let observations = classifyRequest.results else {
            return []
        }

        let relevant = observations
            .filter { $0.confidence >= 0.55 }
            .prefix(2)
            .map { observation -> String in
                let raw = observation.identifier
                let lastPart = raw.components(separatedBy: ">").last ?? raw
                return lastPart.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { label in
                !label.isEmpty && !Self.genericTaxonomyBlacklist.contains(label)
            }

        return Array(relevant)
    }

    /// Normalizes UIImage orientation to .up
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
