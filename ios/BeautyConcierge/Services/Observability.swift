import Foundation

enum AnalyticsEvent: String {
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case authStarted = "auth_started"
    case authCompleted = "auth_completed"
    case beautyIDStarted = "beauty_id_started"
    case beautyIDCompleted = "beauty_id_completed"
    case homeViewed = "home_viewed"
    case scenarioSelected = "scenario_selected"
    case ownedItemsSelected = "owned_items_selected"
    case budgetSelected = "budget_selected"
    case fragrancePreferenceSelected = "fragrance_preference_selected"
    case routineComplexitySelected = "routine_complexity_selected"
    case scanStarted = "scan_started"
    case scanCompleted = "scan_completed"
    case advisorMessageSent = "advisor_message_sent"
    case recommendationViewed = "recommendation_viewed"
    case recommendationGenerated = "recommendation_generated"
    case recommendationAdjustedDueToOwned = "recommendation_adjusted_due_to_owned"
    case routineMadeCheaper = "routine_made_cheaper"
    case routineMinimalCreated = "routine_minimal_created"
    case routinePremiumCreated = "routine_premium_created"
    case productOpened = "product_opened"
    case productMarkedOwned = "product_marked_owned"
    case productMarkedWanted = "product_marked_wanted"
    case productMarkedBuyLater = "product_marked_buy_later"
    case productMarkedNotFit = "product_marked_not_fit"
    case shelfOpened = "shelf_opened"
    case shelfItemAdded = "shelf_item_added"
    case shelfItemStatusChanged = "shelf_item_status_changed"
    case shelfItemRemoved = "shelf_item_removed"
    case shelfItemMarkedOwned = "shelf_item_marked_owned"
    case shelfItemMarkedWanted = "shelf_item_marked_wanted"
    case shelfItemMarkedBuyLater = "shelf_item_marked_buy_later"
    case shelfItemMarkedDidNotFit = "shelf_item_marked_did_not_fit"
    case shelfItemMarkedEmpty = "shelf_item_marked_empty"
    case shelfReplacementRequested = "shelf_replacement_requested"
    case comparisonOpened = "comparison_opened"
    case comparisonTypeSelected = "comparison_type_selected"
    case comparisonVariantSelected = "comparison_variant_selected"
    case comparisonVariantSaved = "comparison_variant_saved"
    case addToCart = "add_to_cart"
    case checkoutStarted = "checkout_started"
    case purchaseIntent = "purchase_intent"
    case purchaseBlockerPromptShown = "purchase_blocker_prompt_shown"
    case purchaseBlockerSelected = "purchase_blocker_selected"
    case blockerActionStarted = "blocker_action_started"
    case blockerActionCompleted = "blocker_action_completed"
    case intentProfileCreated = "intent_profile_created"
    case analyticsDashboardOpened = "analytics_dashboard_opened"
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
