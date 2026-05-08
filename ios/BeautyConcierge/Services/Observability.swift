import Foundation

enum AnalyticsEvent: String {
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case authStarted = "auth_started"
    case authCompleted = "auth_completed"
    case beautyIDStarted = "beauty_id_started"
    case beautyIDCompleted = "beauty_id_completed"
    case scanStarted = "scan_started"
    case scanCompleted = "scan_completed"
    case advisorMessageSent = "advisor_message_sent"
    case recommendationViewed = "recommendation_viewed"
    case productOpened = "product_opened"
    case addToCart = "add_to_cart"
    case checkoutStarted = "checkout_started"
    case privacyDeleteRequested = "privacy_delete_requested"
}

protocol AnalyticsService {
    func track(_ event: AnalyticsEvent, properties: [String: String])
}

protocol CrashReporter {
    func record(error: Error, context: [String: String])
    func setUserContext(_ anonymousID: String?)
}

struct NoOpAnalyticsService: AnalyticsService {
    func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        #if DEBUG
        print("analytics", event.rawValue, properties)
        #endif
    }
}

struct NoOpCrashReporter: CrashReporter {
    func record(error: Error, context: [String: String] = [:]) {
        #if DEBUG
        print("crash-hook", error.localizedDescription, context)
        #endif
    }

    func setUserContext(_ anonymousID: String?) {}
}

struct ProductionAnalyticsAdapter: AnalyticsService {
    func track(_ event: AnalyticsEvent, properties: [String: String]) {
        // Contract stub: wire to an approved consent-aware analytics SDK.
        // Do not send email, raw Beauty ID, photo data or free-text advisor messages.
    }
}

struct ProductionCrashReporterAdapter: CrashReporter {
    func record(error: Error, context: [String: String]) {
        // Contract stub: wire to Crashlytics/Sentry or another approved crash pipeline.
        // Context must be non-PII only.
    }

    func setUserContext(_ anonymousID: String?) {
        // Use anonymous account id hash only after privacy review.
    }
}

struct AppLogger {
    static func info(_ message: String) {
        #if DEBUG
        print("[Luma]", message)
        #endif
    }
}
