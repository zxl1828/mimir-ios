import LocalAuthentication
import SwiftUI

@MainActor
enum BiometricAuthenticator {
    static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用设备密码"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解锁 Mimir 以查看你的私人内容"
            )
        } catch {
            return false
        }
    }

    static var methodName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "设备密码"
        }
    }
}

struct PrivacyLockView: View {
    let isAuthenticating: Bool
    let errorMessage: String?
    let onUnlock: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appAccent) private var accent

    var body: some View {
        ZStack {
            AppUI.ambientBackground(scheme: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MimirMascot(size: 104, mood: .calm)
                    .padding(.bottom, 18)

                Text("Mimir 已锁定")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: colorScheme))

                Text("你的对话与本地项目受到设备身份验证保护。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }

                Button(action: onUnlock) {
                    HStack(spacing: 9) {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: BiometricAuthenticator.methodName == "Face ID" ? "faceid" : "touchid")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Text(isAuthenticating ? "正在验证…" : "使用 \(BiometricAuthenticator.methodName) 解锁")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(isAuthenticating)
                .padding(.top, 24)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 34)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.84), accent.opacity(0.34), .white.opacity(0.48)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 32, y: 16)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
    }
}
