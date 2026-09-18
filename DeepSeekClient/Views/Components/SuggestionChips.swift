import SwiftUI

/// 输入框上方的推荐区：技能推荐胶囊 + 端侧建议回复标签。
/// 淡入、非侵入，用户忽略时自动消失。
struct SuggestionChips: View {

    let skillSuggestions: [Skill]
    let replySuggestions: [String]
    let confidence: Double?
    var onPickSkill: (Skill) -> Void
    var onPickReply: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !skillSuggestions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.brandPurple)

                    ForEach(skillSuggestions) { skill in
                        Button {
                            Haptics.impact(.light)
                            onPickSkill(skill)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: skill.icon)
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(skill.name)
                                    .font(AppFont.chipCompact)
                            }
                            .foregroundStyle(AppColor.brandPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous).fill(AppColor.brandPurple.opacity(0.13)))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    if let confidence, confidence > 0 {
                        Text("\(Int(confidence * 100))%")
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.tertiaryText)
                    }

                    Button {
                        Haptics.impact(.light)
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColor.tertiaryText)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("忽略推荐")

                    Spacer(minLength: 0)
                }
            }

            if !replySuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(replySuggestions.enumerated()), id: \.offset) { _, reply in
                            Button {
                                Haptics.impact(.light)
                                onPickReply(reply)
                            } label: {
                                Text(reply)
                                    .font(AppFont.chipCompact)
                                    .foregroundStyle(AppColor.primaryText)
                                    .lineLimit(1)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(AppColor.secondaryText.opacity(0.10))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(AppColor.separator.opacity(0.25), lineWidth: 0.6)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassClear(cornerRadius: 16)
        .padding(.horizontal, 6)
        .transition(.opacity)
    }
}
