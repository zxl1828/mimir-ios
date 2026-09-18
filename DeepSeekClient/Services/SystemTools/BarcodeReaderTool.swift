import Foundation
import Vision
import UIKit

/// 条码 / 二维码识别，同样完全在本机完成。
enum BarcodeReaderTool {

    struct Code: Sendable, Equatable {
        var value: String
        var symbology: String
    }

    static func detect(in imageData: Data) async throws -> [Code] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (request.results as? [VNBarcodeObservation]) ?? []
                let codes = results.compactMap { observation -> Code? in
                    guard let value = observation.payloadStringValue, !value.isEmpty else { return nil }
                    return Code(
                        value: value,
                        symbology: observation.symbology.rawValue
                    )
                }
                continuation.resume(returning: codes)
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
