import Foundation
import Observation

@MainActor @Observable
final class AppSettings {
    static let keychainService = "com.hurated.interview.openrouter"
    static let keychainAccount = "apiKey"

    static let providerOnDevice = "on-device"
    static let providerOpenRouter = "openrouter"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func getString(_ key: String, fallback: String) -> String {
        defaults.string(forKey: "ih." + key) ?? fallback
    }

    private func getDouble(_ key: String, fallback: Double) -> Double {
        if defaults.object(forKey: "ih." + key) == nil { return fallback }
        return defaults.double(forKey: "ih." + key)
    }

    private func getBool(_ key: String, fallback: Bool) -> Bool {
        if defaults.object(forKey: "ih." + key) == nil { return fallback }
        return defaults.bool(forKey: "ih." + key)
    }

    var providerID: String {
        get { getString("providerID", fallback: Self.providerOnDevice) }
        set { defaults.set(newValue, forKey: "ih.providerID") }
    }

    var openRouterModel: String {
        get { getString("openRouterModel", fallback: "openrouter/free") }
        set { defaults.set(newValue, forKey: "ih.openRouterModel") }
    }

    var matchThreshold: Double {
        get { getDouble("matchThreshold", fallback: 0.35) }
        set { defaults.set(newValue, forKey: "ih.matchThreshold") }
    }

    var aiFallbackEnabled: Bool {
        get { getBool("aiFallbackEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "ih.aiFallbackEnabled") }
    }

    var windowSeconds: Double {
        get { getDouble("windowSeconds", fallback: 60.0) }
        set { defaults.set(newValue, forKey: "ih.windowSeconds") }
    }

    var customSourceHosts: [String] {
        get { defaults.stringArray(forKey: "ih.customSourceHosts") ?? [] }
        set { defaults.set(newValue, forKey: "ih.customSourceHosts") }
    }

    func makeLLM() -> (any LLMService)? {
        if providerID == Self.providerOpenRouter {
            let key = KeychainStore.load(service: Self.keychainService, account: Self.keychainAccount) ?? ""
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return OpenRouterProvider(apiKey: trimmed, model: openRouterModel)
        }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let provider = FoundationModelsProvider()
            if provider.isAvailable { return provider }
        }
        #endif
        return nil
    }
}
