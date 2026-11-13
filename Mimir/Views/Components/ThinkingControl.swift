import SwiftUI

/// 输入框上方的「思考强度」入口。
///
/// 折叠态只是一条低矮的横条（弱化到不会和输入框抢注意力）；
/// 点开后弹出一个面板：上半部是标题与当前档位，中间可以点开模型列表换模型，
/// 下半部是矩形分段控件——四档思考深度在这里一次点中，不再需要拖滑块。
struct ThinkingControl: View {

    @Binding var mode: ThinkingMode
    let modelID: String
    let options: [ModelCatalog.Option]
    var onSelectModel: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.selectionChanged()
            showSheet = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "brain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)

                Text("思考强度")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppUI.label2)
                    .fixedSize()

                Spacer(minLength: 4)

                Text(mode.segmentLabel)
                    .font(AppUI.mono(11, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "chevron.up")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(AppUI.label3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .sheet(isPresented: $showSheet) {
            panel
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .accessibilityLabel("思考强度，当前 \(mode.heroTitle)")
    }

    // MARK: - 面板

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 上半部：标题 + 当前档位
            HStack(alignment: .firstTextBaseline) {
                Text("思考强度")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppUI.label)

                Spacer()

                Text(mode.heroTitle)
                    .font(AppUI.mono(12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppUI.selectionFill(scheme: scheme))
                    )
            }

            // 中间：模型切换（点开系统的模型列表）
            Menu {
                ForEach(options, id: \.id) { option in
                    Button {
                        onSelectModel(option.id)
                    } label: {
                        if option.id == modelID {
                            Label(ModelCatalog.cardLabel(for: option.id), systemImage: "checkmark")
                        } else {
                            Text(ModelCatalog.cardLabel(for: option.id))
                        }
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppUI.label2)

                    Text("模型")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppUI.label2)
                        .fixedSize()

                    Spacer(minLength: 6)

                    Text(ModelCatalog.cardLabel(for: modelID))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppUI.label3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppUI.fill)
                )
            }
            .buttonStyle(.plain)

            // 下半部：矩形分段控件
            segmentStrip

            Text("档位决定推理深度与输出上限；「关闭」表示不走深度思考。")
                .font(.system(size: 10.5))
                .foregroundStyle(AppUI.label3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .background(AppUI.canvas)
    }

    private var segmentStrip: some View {
        HStack(spacing: 0) {
            ForEach(ThinkingMode.allCases) { item in
                let isSelected = item == mode
                Button {
                    Haptics.selectionChanged()
                    withAnimation(.easeOut(duration: 0.18)) {
                        mode = item
                    }
                } label: {
                    Text(item.segmentLabel)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : AppUI.label2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(accent)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.segmentLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppUI.fill)
        )
    }
}
