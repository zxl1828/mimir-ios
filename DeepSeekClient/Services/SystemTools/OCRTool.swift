import Foundation
import Vision
import UIKit

/// 系统 OCR 工具：全部在本机完成，图片不出设备。
enum OCRTool {

    struct Output: Sendable, Equatable {
        var fullText: String
        var lines: [String]
        var averageConfidence: Double
    }

    enum OCRError: LocalizedError {
        case invalidImage
        case noText

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "这张图片无法解析。"
            case .noText: return "没有在图片里识别到文字。"
            }
        }
    }

    static func recognize(
        imageData: Data,
        languages: [String] = ["zh-Hans", "en-US"],
        accurate: Bool = true
    ) async throws -> Output {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        return try await recognize(cgImage: cgImage, languages: languages, accurate: accurate)
    }

    static func recognize(
        cgImage: CGImage,
        languages: [String] = ["zh-Hans", "en-US"],
        accurate: Bool = true
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [String] = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                guard !lines.isEmpty else {
                    continuation.resume(throwing: OCRError.noText)
                    return
                }

                let confidences = observations.compactMap { observation in
                    observation.topCandidates(1).first.map { Double($0.confidence) }
                }
                let average = confidences.isEmpty
                    ? 0
                    : confidences.reduce(0, +) / Double(confidences.count)

                continuation.resume(
                    returning: Output(
                        fullText: lines.joined(separator: "\n"),
                        lines: lines,
                        averageConfidence: average
                    )
                )
            }

            request.recognitionLevel = accurate ? .accurate : .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
