import SwiftUI

/// 550C 冷启动自检：终端逐行字符自检 + 扫描线 + 550C 标识。
///
/// 设计约束：
/// - 全程约 2.1 秒，点击屏幕任意位置立刻跳过；
/// - 不读磁盘、不建索引，纯表现层动画，绝不拖慢冷启动；
/// - 结束后自行淡出并回调 `onFinish`，真实加载逻辑仍在 `RootView.task` 里异步跑。
struct BootSequenceView: View {

    var onFinish: () -> Void

    @Environment(\.appAccent) private var accent

    @State private var typedCount = 0
    @State private var progress: Double = 0
    @State private var scanOffset: CGFloat = -0.2
    @State private var isClosing = false
    @State private var didFinish = false

    private let rows: [(String, String)] = [
        ("BIOS 550C-01", "MIMIR KERNEL v2.4"),
        ("MEM CHECK", "OK"),
        ("VECTOR STORE", "OK · 512d"),
        ("KEYCHAIN LINK", "OK"),
        ("WORKSPACE INDEX", "OK"),
        ("TOOL RUNTIME", "OK"),
        ("ALL SYSTEMS", "NOMINAL")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "050B14"), Color(hex: "03060C")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ConsoleGridOverlay(spacing: 32)
                    .opacity(0.7)

                // 扫描线：一道极淡冷光自上而下扫过
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                accent.opacity(0.16),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 120)
                    .blur(radius: 6)
                    .offset(y: scanOffset * geo.size.height)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 18)
                    logBlock
                    Spacer(minLength: 18)
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 46)
            }
            .opacity(isClosing ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture { finish(immediately: true) }
        }
        .task {
            animateScanline()
            await runSequence()
        }
    }

    // MARK: - 区段

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("550C")
                    .font(AppUI.mono(34, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text("SELF TEST")
                    .font(AppUI.mono(10.5, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(accent.opacity(0.55), lineWidth: 0.5)
                    )
            }

            Rectangle()
                .fill(accent.opacity(0.30))
                .frame(height: 0.5)
        }
    }

    private var logBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.prefix(typedCount).enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(AppUI.mono(10))
                        .foregroundStyle(Color.white.opacity(0.28))

                    Text(row.0)
                        .font(AppUI.mono(11.5, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5)

                    Text(row.1)
                        .font(AppUI.mono(11.5, weight: .semibold))
                        .foregroundStyle(row.0 == "ALL SYSTEMS" ? .white : accent)
                }
                .transition(.opacity)
            }

            // 光标：自检进行中一直在闪
            Rectangle()
                .fill(accent)
                .frame(width: 7, height: 13)
                .opacity(typedCount >= rows.count ? 0 : 1)
                .modifier(CursorBlink())
                .padding(.top, 2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent)
                        .frame(width: max(2, geo.size.width * progress))
                }
            }
            .frame(height: 2)

            HStack {
                Text(typedCount >= rows.count ? "READY" : "LOADING")
                    .font(AppUI.mono(10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(AppUI.mono(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("点击跳过")
                    .font(AppUI.mono(9.5))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.leading, 10)
            }
        }
    }

    // MARK: - 驱动

    private func animateScanline() {
        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
            scanOffset = 1.2
        }
    }

    private func runSequence() async {
        for step in 0..<rows.count {
            if didFinish { return }
            try? await Task.sleep(for: .milliseconds(step == 0 ? 260 : 210))
            if didFinish { return }
            withAnimation(.easeOut(duration: 0.16)) {
                typedCount = step + 1
                progress = Double(step + 1) / Double(rows.count)
            }
        }
        try? await Task.sleep(for: .milliseconds(320))
        finish(immediately: false)
    }

    private func finish(immediately: Bool) {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: immediately ? 0.16 : 0.34)) {
            progress = 1
            typedCount = rows.count
            isClosing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(immediately ? 170 : 350))
            onFinish()
        }
    }
}

/// 终端光标闪烁。
private struct CursorBlink: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
