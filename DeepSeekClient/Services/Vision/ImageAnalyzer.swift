import Foundation
import UIKit

/// 多模态输入的本地预处理。
///
/// 在把图片交给云端模型之前，先用 Vision 在本机把能提取的信息提取出来
/// （文字、条码、尺寸），既能提升问答质量，也能减少上传的数据量。
enum ImageAnalyzer {

    struct Analysis: Sendable, Equatable {
        var ocrText: String
        var barcodes: [String]
        var pixelSize: CGSize
        var isLikelyScreenshot: Bool
        var isLikelyDocument: Bool

        var summaryForModel: String {
            var parts: [String] = []
            if isLikelyScreenshot { parts.append("这是一张屏幕截图。") }
            if isLikelyDocument { parts.append("这看起来是一份文档或扫描件。") }
            if !barcodes.isEmpty {
                parts.append("图中包含条码/二维码：\(barcodes.joined(separator: "、"))。")
            }
            if !ocrText.isEmpty {
                parts.append("本机 OCR 提取到的文字如下：\n\(ocrText)")
            }
            return parts.joined(separator: "\n")
        }
    }

    static func analyze(_ imageData: Data) async -> Analysis {
        let image = UIImage(data: imageData)
        let size = image?.size ?? .zero

        var text = ""
        if let output = try? await OCRTool.recognize(imageData: imageData, accurate: true) {
            text = output.fullText
        }

        var barcodes: [String] = []
        if let codes = try? await BarcodeReaderTool.detect(in: imageData) {
            barcodes = codes.map(\.value)
        }

        let ratio = size.height > 0 ? size.width / size.height : 1
        let isScreenshot = abs(ratio - 9.0 / 19.5) < 0.06 || abs(ratio - 3.0 / 4.0) < 0.03
        let documentKeywords = ["合同", "发票", "证明", "报告", "第", "条", "甲方", "乙方"]
        let isDocument = !text.isEmpty && documentKeywords.contains { text.contains($0) }

        return Analysis(
            ocrText: text,
            barcodes: barcodes,
            pixelSize: size,
            isLikelyScreenshot: isScreenshot,
            isLikelyDocument: isDocument
        )
    }

    /// 压缩图片，降低上传体积（长边不超过 1568px，JPEG 质量 0.8）。
    static func compress(_ imageData: Data, maxDimension: CGFloat = 1_568) -> Data {
        guard let image = UIImage(data: imageData) else { return imageData }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else {
            return image.jpegData(compressionQuality: 0.85) ?? imageData
        }

        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8) ?? imageData
    }
}
