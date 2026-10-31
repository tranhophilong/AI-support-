//
//  IOSObjectDetectorService.swift
//  English Corrector
//
//  Created by Antigravity on 2026-10-31.
//

import UIKit
import Vision
import CoreGraphics

/// Result of on-device iOS object detection and intelligent cropping
struct IOSDetectedObjectResult: Sendable {
    /// The high-resolution cropped image isolating the targeted object
    let croppedImage: UIImage

    /// Compressed JPEG data (~25-60KB) ready for multimodal AI vision analysis
    let croppedImageData: Data

    /// Refined center point (0...100%) in UIKit coordinates (top-left is 0,0)
    /// This snaps the target pin directly onto the true center of the object
    let refinedCenterPercent: CGPoint

    /// Bounding box (0...100%) in UIKit coordinates (x, y, width, height)
    let boundingBoxPercent: CGRect

    /// Visual grounding bounding box formatted as [ymin, xmin, ymax, xmax] (0...100%)
    var box2dGrounding: [Double] {
        [
            boundingBoxPercent.minY,
            boundingBoxPercent.minX,
            boundingBoxPercent.maxY,
            boundingBoxPercent.maxX
        ]
    }

    /// On-device classification keywords detected by Apple Vision Neural Engine (e.g. ["mug", "coffee cup"])
    let onDeviceLabels: [String]

    /// Whether Apple Vision detected a distinct physical object (true) or used smart focus crop (false)
    let isSaliencyMatched: Bool
}

final class IOSObjectDetectorService: Sendable {
    static let shared = IOSObjectDetectorService()

    private init() {}

    /// Detects the object at (xPercent, yPercent), refines its center, and crops the object using Apple Vision.
    func detectAndCropObject(
        from image: UIImage,
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

        // 2. Convert UIKit coordinates (0...100, origin top-left) to normalized (0...1)
        let clampedX = max(0.01, min(0.99, xPercent / 100.0))
        let clampedY = max(0.01, min(0.99, yPercent / 100.0))

        // Vision framework uses lower-left as (0,0)
        let visionPoint = CGPoint(x: clampedX, y: 1.0 - clampedY)

        // 3. Run Apple Vision Objectness Saliency Request
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        try? handler.perform([saliencyRequest])

        var matchedVisionBox: CGRect? = nil
        var isSaliencyMatched = false

        if let observation = saliencyRequest.results?.first,
           let salientObjects = observation.salientObjects,
           !salientObjects.isEmpty {

            // Step A: Check if any salient object bounding box directly encloses visionPoint
            let containingBoxes = salientObjects
                .map(\.boundingBox)
                .filter { $0.contains(visionPoint) }

            if let mostSpecific = containingBoxes.min(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
                matchedVisionBox = mostSpecific
                isSaliencyMatched = true
            } else {
                // Step B: Find the closest salient object within a 22% proximity threshold
                let closest = salientObjects.compactMap { obj -> (CGRect, CGFloat)? in
                    let box = obj.boundingBox
                    let centerX = box.midX
                    let centerY = box.midY
                    let dx = centerX - visionPoint.x
                    let dy = centerY - visionPoint.y
                    let dist = sqrt(dx * dx + dy * dy)
                    return (dist <= 0.22) ? (box, dist) : nil
                }.min(by: { $0.1 < $1.1 })

                if let closestBox = closest?.0 {
                    matchedVisionBox = closestBox
                    isSaliencyMatched = true
                }
            }
        }

        // 4. Resolve UIKit normalized bounding box & center
        let uiBox: CGRect
        let refinedCenterPercent: CGPoint

        if let vBox = matchedVisionBox, isSaliencyMatched {
            // Convert Vision (bottom-left) to UIKit (top-left)
            let uiX = vBox.origin.x
            let uiY = 1.0 - (vBox.origin.y + vBox.size.height)
            let uiW = vBox.size.width
            let uiH = vBox.size.height

            uiBox = CGRect(
                x: max(0.0, min(0.95, uiX)),
                y: max(0.0, min(0.95, uiY)),
                width: max(0.05, min(1.0, uiW)),
                height: max(0.05, min(1.0, uiH))
            )

            refinedCenterPercent = CGPoint(
                x: max(2.0, min(98.0, (uiBox.midX) * 100.0)),
                y: max(2.0, min(98.0, (uiBox.midY) * 100.0))
            )
        } else {
            // Fallback: Smart adaptive square focus window centered at touch point
            let focusDimension: CGFloat = 0.28
            let originX = max(0.0, min(1.0 - focusDimension, clampedX - focusDimension / 2.0))
            let originY = max(0.0, min(1.0 - focusDimension, clampedY - focusDimension / 2.0))
            uiBox = CGRect(x: originX, y: originY, width: focusDimension, height: focusDimension)

            refinedCenterPercent = CGPoint(x: xPercent, y: yPercent)
        }

        // 5. Expand bounding box by 12% padding for visual surrounding context
        let padX = uiBox.width * 0.12
        let padY = uiBox.height * 0.12
        let paddedMinX = max(0.0, uiBox.minX - padX)
        let paddedMinY = max(0.0, uiBox.minY - padY)
        let paddedMaxX = min(1.0, uiBox.maxX + padX)
        let paddedMaxY = min(1.0, uiBox.maxY + padY)

        let paddedBox = CGRect(
            x: paddedMinX,
            y: paddedMinY,
            width: max(0.05, paddedMaxX - paddedMinX),
            height: max(0.05, paddedMaxY - paddedMinY)
        )

        // 6. Crop CGImage with pixel precision
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
        guard let jpegData = croppedUIImage.jpegData(compressionQuality: 0.82) else {
            throw AIServiceError.apiError(provider: "Vision", message: "Lỗi nén ảnh vật thể")
        }

        // 7. Fast On-Device Classification (runs in <15ms on Neural Engine)
        let onDeviceLabels = detectOnDeviceLabels(for: croppedCG)

        let boundingBoxPercent = CGRect(
            x: uiBox.origin.x * 100.0,
            y: uiBox.origin.y * 100.0,
            width: uiBox.size.width * 100.0,
            height: uiBox.size.height * 100.0
        )

        return IOSDetectedObjectResult(
            croppedImage: croppedUIImage,
            croppedImageData: jpegData,
            refinedCenterPercent: refinedCenterPercent,
            boundingBoxPercent: boundingBoxPercent,
            onDeviceLabels: onDeviceLabels,
            isSaliencyMatched: isSaliencyMatched
        )
    }

    // MARK: - Private Helpers

    /// Runs fast local classification on the cropped object
    private func detectOnDeviceLabels(for cgImage: CGImage) -> [String] {
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([classifyRequest])) != nil,
              let observations = classifyRequest.results else {
            return []
        }

        let relevant = observations
            .filter { $0.confidence >= 0.08 }
            .prefix(4)
            .map { observation -> String in
                // Clean identifier, e.g. "kitchen > espresso_maker" -> "espresso maker"
                let raw = observation.identifier
                let lastPart = raw.components(separatedBy: ">").last ?? raw
                return lastPart.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

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
