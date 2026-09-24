import Foundation
import Observation

/// 对话自动清理策略。
enum RetentionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case thirtyDays
    case oneYear
    case forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyDays: return "30 天"
        case .oneYear: return "1 年"
        case .forever: return "永久保留"
        }
    }

    var detail: String {
        switch self {
        case .thirtyDays: return "超过 30 天的对话会自动删除"
        case .oneYear: return "超过 1 年的对话会自动删除"
        case .forever: return "对话一直保留，直到你手动删除"
        }
    }

    /// 早于该时刻的对话应当被清理；永久保留返回 nil。
    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .forever: return nil
        }
    }
}

/// 全局设置。敏感信息（API Key）落在 Keychain，其余落在 UserDefaults。
@Observable
final class AppSettings {

    private enum Key {
        static let credential = "settings.credential.v1"
        static let parameters = "settings.parameters.v1"
        static let voice = "settings.voice.v1"
        static let retention = "settings.retention.v1"
        static let onboarding = "settings.onboarding.completed.v1"
        static let autoSummarize = "settings.auto.summarize.v1"
        static let memoryEnabled = "settings.memory.enabled.v1"
        static let backgroundReview = "settings.memory.background.review.v1"
        static let liveActivity = "settings.live.activity.v1"
        static let suggestionsEnabled = "settings.suggestions.enabled.v1"
        static let selectedAgent = "settings.agent.selected.v1"
        static let customModels = "settings.custom.models.v1"
        static let webSearch = "settings.websearch.v1"
        static let appearance = "settings.appearance.v1"
        static let accent = "settings.accent.v1"
        static let secretAccount = "app.api.key"
        static let webSearchSecretAccount = "websearch.api.key"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainService

    // MARK: - 公开状态

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }

    var credential: APICredential {
        didSet { persistCredential() }
    }

    var parameters: ModelParameters {
        didSet { persist(parameters, forKey: Key.parameters) }
    }

    var voice: VoicePreferences {
        didSet { persist(voice, forKey: Key.voice) }
    }

    var retention: RetentionPolicy {
        didSet { defaults.set(retention.rawValue, forKey: Key.retention) }
    }

    var autoSummarizeEnabled: Bool {
        didSet { defaults.set(autoSummarizeEnabled, forKey: Key.autoSummarize) }
    }

    var memoryEnabled: Bool {
        didSet { defaults.set(memoryEnabled, forKey: Key.memoryEnabled) }
    }

    var backgroundMemoryReview: Bool {
        didSet { defaults.set(backgroundMemoryReview, forKey: Key.backgroundReview) }
    }

    var liveActivitiesEnabled: Bool {
        didSet { defaults.set(liveActivitiesEnabled, forKey: Key.liveActivity) }
    }

    var suggestionsEnabled: Bool {
        didSet { defaults.set(suggestionsEnabled, forKey: Key.suggestionsEnabled) }
    }

    var selectedAgentName: String {
        didSet { defaults.set(selectedAgentName, forKey: Key.selectedAgent) }
    }

    var customModels: [CustomModelEntry] {
        didSet { persist(customModels, forKey: Key.customModels) }
    }

    var webSearch: WebSearchConfiguration {
        didSet { persist(webSearch, forKey: Key.webSearch) }
    }

    /// 外观模式（系统 / 浅色 / 深色）。
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// 全应用强调色。
    var accent: AppAccent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    var hasUsableCredential: Bool {
        !credential.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 初始化

    init(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        self.defaults = defaults
        self.keychain = keychain

        self.hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        self.parameters = Self.load(ModelParameters.self, from: defaults, key: Key.parameters)
            ?? ModelParameters()
        self.voice = Self.load(VoicePreferences.self, from: defaults, key: Key.voice)
            ?? VoicePreferences()
        self.retention = RetentionPolicy(rawValue: defaults.string(forKey: Key.retention) ?? "")
            ?? .forever
        self.autoSummarizeEnabled = defaults.object(forKey: Key.autoSummarize) as? Bool ?? true
        self.memoryEnabled = defaults.object(forKey: Key.memoryEnabled) as? Bool ?? true
        self.backgroundMemoryReview = defaults.object(forKey: Key.backgroundReview) as? Bool ?? true
        self.liveActivitiesEnabled = defaults.object(forKey: Key.liveActivity) as? Bool ?? true
        self.suggestionsEnabled = defaults.object(forKey: Key.suggestionsEnabled) as? Bool ?? true
        self.selectedAgentName = defaults.string(forKey: Key.selectedAgent) ?? ""
        self.customModels = Self.load([CustomModelEntry].self, from: defaults, key: Key.customModels) ?? []
        self.webSearch = Self.load(WebSearchConfiguration.self, from: defaults, key: Key.webSearch)
            ?? WebSearchConfiguration()
        self.appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "")
            ?? .system
        self.accent = AppAccent(rawValue: defaults.string(forKey: Key.accent) ?? "")
            ?? .blue

        var stored = Self.load(APICredential.self, from: defaults, key: Key.credential)
            ?? APICredential.placeholder
        stored.key = keychain.string(for: Key.secretAccount) ?? ""
        self.credential = stored
    }

    // MARK: - 凭据

    /// 首次引导校验通过后写入。
    func storeCredential(_ value: APICredential) throws {
        let trimmed = value.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.remove(account: Key.secretAccount)
        } else {
            try keychain.setString(trimmed, for: Key.secretAccount)
        }
        var sanitized = value
        sanitized.key = ""
        credential = sanitized
        parameters.modelID = value.modelID
    }

    func signOut() {
        try? keychain.remove(account: Key.secretAccount)
        credential = APICredential.placeholder
        hasCompletedOnboarding = false
    }

    /// 供网络层使用的完整凭据（含明文 Key，仅存在于内存中）。
    var resolvedCredential: APICredential {
        var value = credential
        value.key = keychain.string(for: Key.secretAccount) ?? ""
        if value.baseURL.isEmpty { value.baseURL = value.format.defaultBaseURL }
        if value.modelID.isEmpty { value.modelID = value.format.defaultModelID }
        return value
    }

    // MARK: - 联网搜索密钥

    /// 搜索服务的密钥，同样只放钥匙串。
    var resolvedWebSearchKey: String? {
        let value = keychain.string(for: Key.webSearchSecretAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    func storeWebSearchKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.remove(account: Key.webSearchSecretAccount)
        } else {
            try keychain.setString(trimmed, for: Key.webSearchSecretAccount)
        }
    }

    // MARK: - 私有

    private func persistCredential() {
        var sanitized = credential
        sanitized.key = ""
        persist(sanitized, forKey: Key.credential)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
