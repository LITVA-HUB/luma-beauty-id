import Foundation

enum RuntimeEnvironment: String, Codable {
    case development
    case staging
    case production

    var isProduction: Bool { self == .production }
    var allowsDevelopmentFeatures: Bool {
        #if DEBUG
        return self == .development
        #else
        return false
        #endif
    }
}

struct AppEnvironment {
    let baseURL: URL
    let appName: String = "Luma Beauty ID"
    let runtime: RuntimeEnvironment
    let isDebug: Bool
    let configurationError: String?

    init(baseURL: URL, runtime: RuntimeEnvironment, isDebug: Bool, configurationError: String? = nil) {
        self.baseURL = baseURL
        self.runtime = runtime
        self.isDebug = isDebug
        self.configurationError = configurationError
    }

    var canShowDevLogin: Bool { isDebug && runtime.allowsDevelopmentFeatures }
    var usesReleaseAPI: Bool { runtime == .staging || runtime == .production }
    var canUseAPI: Bool { configurationError == nil }

    static var current: AppEnvironment {
        let rawURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let rawEnv = Bundle.main.object(forInfoDictionaryKey: "APP_ENVIRONMENT") as? String
        let runtimeFromPlist = RuntimeEnvironment(rawValue: rawEnv ?? "development") ?? .development

        #if DEBUG
        let isDebug = true
        let runtime = runtimeFromPlist
        let fallbackURL = "http://127.0.0.1:8010"
        let configurationError: String? = nil
        #else
        let isDebug = false
        let runtime = runtimeFromPlist == .development ? RuntimeEnvironment.staging : runtimeFromPlist
        let fallbackURL = "https://staging-api-url-required.invalid"
        let configurationError = Self.releaseConfigurationError(rawURL)
        #endif

        let configured = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedURL = configured.isEmpty || configurationError != nil ? fallbackURL : configured
        let url = URL(string: selectedURL) ?? URL(string: fallbackURL)!
        return AppEnvironment(baseURL: url, runtime: runtime, isDebug: isDebug, configurationError: configurationError)
    }

    private static func releaseConfigurationError(_ rawURL: String?) -> String? {
        let configured = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else {
            return "Сервис временно недоступен. Staging API URL не настроен."
        }
        let lower = configured.lowercased()
        if lower.contains("127.0.0.1") || lower.contains("localhost") || lower.contains("api.example.com") || lower.contains("staging-api-url-required.invalid") {
            return "Сервис временно недоступен. Staging API URL не настроен."
        }
        guard let url = URL(string: configured), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return "Сервис временно недоступен. Staging API URL не настроен."
        }
        return nil
    }
}
