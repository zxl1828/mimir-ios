import SwiftUI

/// 代码重构行差异种类
public enum ASTDiffKind: Sendable {
    case unchanged
    case deleted
    case added
}

/// 一行差异呈现数据
public struct ASTDiffLine: Identifiable, Sendable {
    public let id = UUID()
    public let kind: ASTDiffKind
    public let text: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
}

/// 语音代码重构差异计算器
public enum ASTDiffEngine {
    public static func computeDiff(original: String, refactored: String) -> [ASTDiffLine] {
        let oldLines = original.components(separatedBy: "\n")
        let newLines = refactored.components(separatedBy: "\n")

        var result: [ASTDiffLine] = []
        var oldIdx = 0
        var newIdx = 0

        // 简易稳定快速逐行双指针差异比对
        while oldIdx < oldLines.count && newIdx < newLines.count {
            let oldL = oldLines[oldIdx]
            let newL = newLines[newIdx]

            if oldL == newL {
                result.append(ASTDiffLine(
                    kind: .unchanged,
                    text: oldL,
                    oldLineNumber: oldIdx + 1,
                    newLineNumber: newIdx + 1
                ))
                oldIdx += 1
                newIdx += 1
            } else {
                // 探测下一行是否一致
                let nextOldMatches = (newIdx + 1 < newLines.count && oldL == newLines[newIdx + 1])
                let nextNewMatches = (oldIdx + 1 < oldLines.count && oldLines[oldIdx + 1] == newL)

                if nextOldMatches {
                    // 新增了一行
                    result.append(ASTDiffLine(
                        kind: .added,
                        text: newL,
                        oldLineNumber: nil,
                        newLineNumber: newIdx + 1
                    ))
                    newIdx += 1
                } else if nextNewMatches {
                    // 删除了一行
                    result.append(ASTDiffLine(
                        kind: .deleted,
                        text: oldL,
                        oldLineNumber: oldIdx + 1,
                        newLineNumber: nil
                    ))
                    oldIdx += 1
                } else {
                    // 替换行：先标红删除，再标绿添加
                    result.append(ASTDiffLine(
                        kind: .deleted,
                        text: oldL,
                        oldLineNumber: oldIdx + 1,
                        newLineNumber: nil
                    ))
                    result.append(ASTDiffLine(
                        kind: .added,
                        text: newL,
                        oldLineNumber: nil,
                        newLineNumber: newIdx + 1
                    ))
                    oldIdx += 1
                    newIdx += 1
                }
            }
        }

        // 剩余旧行作为删除
        while oldIdx < oldLines.count {
            result.append(ASTDiffLine(
                kind: .deleted,
                text: oldLines[oldIdx],
                oldLineNumber: oldIdx + 1,
                newLineNumber: nil
            ))
            oldIdx += 1
        }

        // 剩余新行作为新增
        while newIdx < newLines.count {
            result.append(ASTDiffLine(
                kind: .added,
                text: newLines[newIdx],
                oldLineNumber: nil,
                newLineNumber: newIdx + 1
            ))
            newIdx += 1
        }

        return result
    }
}

/// 专用于代码视窗的原地高架浮动 Diff 遮罩（Voice-to-AST Floating Diff Overlay）
public struct VoiceCodeRefactorOverlay: View {

    public let prompt: String
    public let originalCode: String
    public let refactoredCode: String
    public let onCommit: () -> Void
    public let onReject: () -> Void

    @Environment(\.colorScheme) private var scheme
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")
    private let paleLavender = Color(hex: "F8F6FD")
    private let deletedTint = Color(hex: "FF453A")
    private let addedTint = Color(hex: "30D158")

    @State private var diffLines: [ASTDiffLine] = []

    public init(
        prompt: String,
        originalCode: String,
        refactoredCode: String,
        onCommit: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.originalCode = originalCode
        self.refactoredCode = refactoredCode
        self.onCommit = onCommit
        self.onReject = onReject
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ① 顶栏：指示徽章与操作指令
            diffHeader

            Divider()
                .overlay(irisViolet.opacity(0.35))

            // ② 差异比对核心滚动视图
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(diffLines) { line in
                        diffLineRow(line)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: "0E0A17").opacity(0.95))

            Divider()
                .overlay(Color.white.opacity(0.12))

            // ③ 底栏：操作按钮（Accept & Commit / Reject）
            diffActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: 420)
        // 刚性高架浮动玻璃面板（#120D1D 85% + ultraThinMaterial，无缩放无形变）
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(deepPlumBase.opacity(0.88))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    irisViolet.opacity(0.65),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
                .shadow(color: irisViolet.opacity(0.30), radius: 26, y: 12)
                .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14)
        .task {
            diffLines = ASTDiffEngine.computeDiff(original: originalCode, refactored: refactoredCode)
        }
    }

    // MARK: - 顶栏

    private var diffHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(irisViolet.opacity(0.25)).frame(width: 26, height: 26)
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(irisViolet)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("VOICE-TO-AST REFACTOR")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(irisViolet)

                    let addCount = diffLines.filter { $0.kind == .added }.count
                    let delCount = diffLines.filter { $0.kind == .deleted }.count

                    Text("+\(addCount) -\(delCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                }

                Text(prompt.isEmpty ? "语音重构建议已就绪" : "「\(prompt)」")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(RigidActionButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 逐行差异行

    private func diffLineRow(_ line: ASTDiffLine) -> some View {
        HStack(spacing: 6) {
            // 行号标记
            Text(line.newLineNumber.map { String(format: "%3d", $0) } ?? (line.oldLineNumber.map { String(format: "%3d", $0) } ?? "   "))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 28, alignment: .trailing)

            // +/- 指示符
            Text(indicator(for: line.kind))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(indicatorColor(for: line.kind))
                .frame(width: 12, alignment: .center)

            // 代码正文
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(textColor(for: line.kind))
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(for: line.kind))
    }

    private func indicator(for kind: ASTDiffKind) -> String {
        switch kind {
        case .unchanged: return " "
        case .deleted: return "-"
        case .added: return "+"
        }
    }

    private func indicatorColor(for kind: ASTDiffKind) -> Color {
        switch kind {
        case .unchanged: return Color.clear
        case .deleted: return deletedTint
        case .added: return addedTint
        }
    }

    private func textColor(for kind: ASTDiffKind) -> Color {
        switch kind {
        case .unchanged: return Color.white.opacity(0.85)
        case .deleted: return deletedTint.opacity(0.92)
        case .added: return addedTint.opacity(0.95)
        }
    }

    private func rowBackground(for kind: ASTDiffKind) -> Color {
        switch kind {
        case .unchanged:
            return Color.clear
        case .deleted:
            return deletedTint.opacity(0.15)
        case .added:
            return addedTint.opacity(0.15)
        }
    }

    // MARK: - 底栏动作

    private var diffActionBar: some View {
        HStack(spacing: 12) {
            Button(action: onReject) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                    Text("放弃修改")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(RigidActionButtonStyle())

            Button(action: onCommit) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Accept & Commit")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(addedTint.opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.9)
                        )
                        .shadow(color: addedTint.opacity(0.40), radius: 8, y: 2)
                )
            }
            .buttonStyle(RigidActionButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(deepPlumBase.opacity(0.70))
    }
}

private struct RigidActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1.0)
    }
}
