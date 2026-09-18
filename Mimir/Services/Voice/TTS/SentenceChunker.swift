import Foundation

/// 把流式到达的文本按句子切开，凑齐一句就交给语音合成为播放队列。
///
/// 目的是让语音尽早开口，而不是等整段回答写完。
struct SentenceChunker {

    private var buffer = ""
    private let maximumLength: Int
    private let minimumLength: Int

    init(minimumLength: Int = 6, maximumLength: Int = 90) {
        self.minimumLength = minimumLength
        self.maximumLength = maximumLength
    }

    /// 追加增量文本，返回可以立即播报的完整句子。
    mutating func append(_ chunk: String) -> [String] {
        buffer += chunk

        var sentences: [String] = []
        while let cut = nextBoundary() {
            let sentence = buffer[buffer.startIndex..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex..<cut)
            if sentence.count >= minimumLength {
                sentences.append(sentence)
            }
        }

        // 长句切不开时按上限强制切分，避免一直不发声。
        while buffer.count > maximumLength {
            let cutIndex = buffer.index(buffer.startIndex, offsetBy: maximumLength)
            let head = buffer[buffer.startIndex..<cutIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex..<cutIndex)
            if !head.isEmpty { sentences.append(head) }
        }

        return sentences
    }

    /// 生成结束时冲刷剩余内容。
    mutating func flush() -> [String] {
        let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard remainder.count >= 2 else { return [] }
        return [remainder]
    }

    mutating func reset() {
        buffer = ""
    }

    /// 找到最近一个句末标点或换行的位置（越过该标点）。
    private func nextBoundary() -> String.Index? {
        let terminators: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            if terminators.contains(character) {
                let next = buffer.index(after: index)
                // 省略号、连续标点一起吞掉。
                var cursor = next
                while cursor < buffer.endIndex, terminators.contains(buffer[cursor]) {
                    cursor = buffer.index(after: cursor)
                }
                return cursor
            }
            index = buffer.index(after: index)
        }
        return nil
    }
}
