import SwiftUI

/// 「+」按钮弹出的附件菜单。
///
/// 用 `popover` 呈现，锚定在加号按钮上，因此会从按钮位置展开而不是从屏幕中间跳出。
struct AttachmentMenu: View {

    var onPickPhoto: () -> Void
    var onCamera: () -> Void
    var onScan: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(spacing: 2) {
            row(icon: "photo.on.rectangle.angled", title: "从相册选择", tint: accent, action: onPickPhoto)
            row(icon: "camera", title: "拍照", tint: AppUI.neonViolet, action: onCamera)
            row(icon: "doc.viewfinder", title: "扫描文档", tint: AppUI.deepViolet, action: onScan)
        }
        .padding(6)
        .frame(width: 216)
        .liquidGlass(cornerRadius: 22, glowIntensity: 0.28)
    }

    private func row(
        icon: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                Text(title)
                    .font(AppUI.subheadline)
                    .foregroundStyle(AppUI.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
