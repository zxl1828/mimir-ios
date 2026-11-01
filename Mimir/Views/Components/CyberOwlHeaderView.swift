import SwiftUI

/// 主屏品牌区。只保留 64~80pt 静态品牌图标和清晰状态，不在内容区绘制轨道、粒子或背景光晕。
struct CyberOwlHeaderView: View {
    let mascotSize: CGFloat
    let isCompact: Bool
    var onSelectNode: ((RAGOrbitalNode) -> Void)? = nil

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            MimirMascot(size: min(max(mascotSize * 0.56, 64), 80), mood: .calm)
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text(greeting)
                    .font(.system(size: isCompact ? 20 : 24, weight: .bold))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("可以直接提问，也可以打开项目文件开始编程")
                    .font(.system(size: 13))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var greeting: String {
        let name = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "你好，我是 Mimir" : "你好，\(name)"
    }
}
