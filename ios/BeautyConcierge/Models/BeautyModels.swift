import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct Account: Codable, Equatable {
    let accountId: String
    let name: String
    let email: String?
    var phoneNumber: String? = nil
    var isGuest: Bool? = nil
    let createdAt: Date?

    var isGuestAccount: Bool { isGuest ?? false }
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date?
    let refreshExpiresAt: Date?
    let account: Account
    let devMode: Bool?
    let provider: String?
}

struct TokenRefreshRequest: Codable {
    let refreshToken: String
}

struct LogoutRequest: Codable {
    let refreshToken: String?
}

struct LoginRequest: Codable {
    var phone: String? = nil
    var email: String? = nil
    var password: String? = nil
}

struct RegisterRequest: Codable {
    let name: String
    var phone: String? = nil
    var email: String? = nil
    var password: String? = nil
    let consent: Bool
}

struct LinkPhoneRequest: Codable {
    let phone: String
    var name: String? = nil
    var password: String? = nil
}

struct BeautyID: Codable, Equatable {
    var skinType: String?
    var concerns: [String] = []
    var sensitivity: String?
    var fragranceSensitivity: String?
    var preferredFinish: [String] = []
    var makeupPreferences: [String] = []
    var budget: String = "mid"
    var ingredientExclusions: [String] = []
    var routineComplexity: String = "balanced"
    var styleTags: [String] = []
    var consent: Bool = false
    var updatedAt: Date?

    var isUsable: Bool { consent && (!concerns.isEmpty || skinType != nil || !preferredFinish.isEmpty) }
}

struct BeautyIDReveal: Identifiable, Equatable {
    let id = UUID()
    let beautyID: BeautyID
}

struct BeautyIDResponse: Codable, Equatable {
    let beautyId: BeautyID
    let completion: Double
    let tags: [String]
    let privacyNote: String?
}

struct Product: Codable, Identifiable, Equatable, Hashable {
    var id: String { sku }
    let sku: String
    let sourceSku: String?
    let catalogNumber: Int?
    let brand: String
    let name: String
    let variant: String?
    let displayName: String?
    let category: String
    let domain: String
    let priceSegment: String
    let priceValue: Int
    let currency: String
    let imageUrl: String?
    let gallery: [String]
    let availability: Bool
    let inventoryStatus: String
    let skinTypes: [String]
    let concerns: [String]
    let tags: [String]
    let ingredients: [String]
    let ingredientHighlights: [String]
    let exclusions: [String]
    let finishes: [String]
    let coverageLevels: [String]
    let colorFamilies: [String]
    let texture: String?
    let rating: Double?
    let reviewCount: Int?
    let warnings: [String]
    let source: String?
    let assetSource: String?
    let cardImageUrl: String?
    let productType: String?
    let categoryGroup: String?
    let updatedAt: Date?

    init(
        sku: String,
        sourceSku: String? = nil,
        catalogNumber: Int? = nil,
        brand: String,
        name: String,
        variant: String? = nil,
        displayName: String? = nil,
        category: String,
        domain: String,
        priceSegment: String,
        priceValue: Int,
        currency: String,
        imageUrl: String?,
        gallery: [String],
        availability: Bool,
        inventoryStatus: String,
        skinTypes: [String],
        concerns: [String],
        tags: [String],
        ingredients: [String],
        ingredientHighlights: [String],
        exclusions: [String],
        finishes: [String],
        coverageLevels: [String],
        colorFamilies: [String],
        texture: String?,
        rating: Double?,
        reviewCount: Int?,
        warnings: [String],
        source: String?,
        assetSource: String? = nil,
        cardImageUrl: String? = nil,
        productType: String? = nil,
        categoryGroup: String? = nil,
        updatedAt: Date?
    ) {
        self.sku = sku
        self.sourceSku = sourceSku
        self.catalogNumber = catalogNumber
        self.brand = brand
        self.name = name
        self.variant = variant
        self.displayName = displayName
        self.category = category
        self.domain = domain
        self.priceSegment = priceSegment
        self.priceValue = priceValue
        self.currency = currency
        self.imageUrl = imageUrl
        self.gallery = gallery
        self.availability = availability
        self.inventoryStatus = inventoryStatus
        self.skinTypes = skinTypes
        self.concerns = concerns
        self.tags = tags
        self.ingredients = ingredients
        self.ingredientHighlights = ingredientHighlights
        self.exclusions = exclusions
        self.finishes = finishes
        self.coverageLevels = coverageLevels
        self.colorFamilies = colorFamilies
        self.texture = texture
        self.rating = rating
        self.reviewCount = reviewCount
        self.warnings = warnings
        self.source = source
        self.assetSource = assetSource
        self.cardImageUrl = cardImageUrl
        self.productType = productType
        self.categoryGroup = categoryGroup
        self.updatedAt = updatedAt
    }
}

struct RecommendationProduct: Codable, Identifiable, Equatable, Hashable {
    var id: String { sku }
    let sku: String
    let sourceSku: String?
    let catalogNumber: Int?
    let brand: String
    let name: String
    let variant: String?
    let displayName: String?
    let category: String
    let domain: String
    let priceSegment: String
    let priceValue: Int
    let currency: String
    let imageUrl: String?
    let gallery: [String]
    let availability: Bool
    let inventoryStatus: String
    let skinTypes: [String]
    let concerns: [String]
    let tags: [String]
    let ingredients: [String]
    let ingredientHighlights: [String]
    let exclusions: [String]
    let finishes: [String]
    let coverageLevels: [String]
    let colorFamilies: [String]
    let texture: String?
    let rating: Double?
    let reviewCount: Int?
    let warnings: [String]
    let source: String?
    let assetSource: String?
    let cardImageUrl: String?
    let productType: String?
    let categoryGroup: String?
    let updatedAt: Date?
    let matchScore: Int
    let reason: String
    let routineStep: String
    let alternatives: [String]

    var asProduct: Product {
        Product(
            sku: sku,
            sourceSku: sourceSku,
            catalogNumber: catalogNumber,
            brand: brand,
            name: name,
            variant: variant,
            displayName: displayName,
            category: category,
            domain: domain,
            priceSegment: priceSegment,
            priceValue: priceValue,
            currency: currency,
            imageUrl: imageUrl,
            gallery: gallery,
            availability: availability,
            inventoryStatus: inventoryStatus,
            skinTypes: skinTypes,
            concerns: concerns,
            tags: tags,
            ingredients: ingredients,
            ingredientHighlights: ingredientHighlights,
            exclusions: exclusions,
            finishes: finishes,
            coverageLevels: coverageLevels,
            colorFamilies: colorFamilies,
            texture: texture,
            rating: rating,
            reviewCount: reviewCount,
            warnings: warnings,
            source: source,
            assetSource: assetSource,
            cardImageUrl: cardImageUrl,
            productType: productType,
            categoryGroup: categoryGroup,
            updatedAt: updatedAt
        )
    }
}

struct RecommendationsRequest: Codable {
    let beautyId: BeautyID?
    let focus: String?
    let limit: Int
    let filters: [String: String]
}

struct RecommendationsResponse: Codable, Equatable {
    let hero: RecommendationProduct?
    let routine: [RecommendationProduct]
    let products: [RecommendationProduct]
    let explanation: String
    let disclaimer: String
    let generatedAt: Date?

    static let empty = RecommendationsResponse(
        hero: nil,
        routine: [],
        products: [],
        explanation: "Рекомендации появятся после Beauty ID.",
        disclaimer: "Косметический подбор, не медицинская рекомендация.",
        generatedAt: nil
    )
}


struct ScanStatus: Codable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let isDone: Bool
}

struct ScanResult: Codable, Equatable {
    let scanId: String
    let summary: String
    let signals: [String]
    let limitations: [String]
    let statuses: [ScanStatus]
    let recommendations: RecommendationsResponse
    let retentionPolicy: String?
    let deletionUrl: String?
    let disclaimer: String
}

struct AdvisorRequest: Codable {
    let message: String
    let beautyId: BeautyID?
    let currentSkus: [String]
    let currentSelection: [AdvisorSelectionProduct]
    let currentCart: [AdvisorSelectionProduct]
}

struct AdvisorAction: Codable, Identifiable, Equatable {
    var id: String { "\(type)-\(oldSku ?? "")-\(newSku ?? "")-\(skus.joined(separator: ","))" }
    let type: String
    let skus: [String]
    let oldSku: String?
    let newSku: String?
    let reason: String?
    let requiresConfirmation: Bool?
    let metadata: [String: JSONValue]?

    var title: String {
        switch type {
        case "add_products", "add_products_to_selection": return skus.count > 1 ? "Добавить \(skus.count.productWord)" : "Добавить товар"
        case "remove_products_from_selection": return "Убрать из набора"
        case "clear_selection": return "Очистить набор"
        case "add_current_routine_to_shelf", "add_product_to_shelf", "mark_product_wanted": return "Добавить в полку"
        case "mark_product_owned": return "Уже есть"
        case "mark_product_buy_later": return "Куплю позже"
        case "mark_product_did_not_fit": return "Не подошло"
        case "add_products_to_cart", "add_current_routine_to_cart", "add_selection_to_cart", "move_selection_to_cart": return "Добавить в корзину"
        case "remove_products_from_cart": return "Убрать из корзины"
        case "clear_cart": return "Очистить корзину"
        case "suggest_replace_product", "replace_product", "replace_product_confirmed": return "Заменить товар"
        case "show_alternatives": return "Показать альтернативы"
        case "refine_budget": return "Уточнить бюджет"
        case "refine_fragrance_free": return "Без отдушки"
        case "refine_lighter_texture": return "Легче текстура"
        case "refine_more_glow": return "Больше сияния"
        case "refine_premium": return "Премиальнее"
        case "save_routine_suggestion", "save_selection_as_routine", "save_current_routine": return "Сохранить набор"
        case "load_saved_routine": return "Открыть сохранённую"
        case "replace_saved_routine_confirmed": return "Заменить сохранённую"
        default: return "Действие"
        }
    }

    var subtitle: String {
        switch type {
        case "add_current_routine_to_shelf":
            return "Сохранить текущий набор как «Хочу попробовать»"
        case "add_product_to_shelf", "mark_product_wanted":
            return "Добавить товар в «Хочу попробовать»"
        case "mark_product_owned":
            return "Учесть товар как уже имеющийся"
        case "mark_product_buy_later":
            return "Оставить товар на потом"
        case "mark_product_did_not_fit":
            return "Учесть негативный сигнал"
        case "add_current_routine_to_cart", "add_selection_to_cart", "move_selection_to_cart":
            return "Перенести текущий набор в список к покупке"
        case "add_products_to_cart":
            return "Добавить товар в список к покупке"
        case "save_routine_suggestion", "save_selection_as_routine", "save_current_routine":
            return "Вернуться к этому набору позже"
        case "refine_budget":
            return "Собрать более доступный вариант"
        case "suggest_replace_product", "replace_product", "replace_product_confirmed":
            return "Подобрать альтернативу в той же роли"
        default:
            return reason ?? "Действие с текущим набором"
        }
    }
}

struct AdvisorSelectionProduct: Codable, Equatable {
    let sku: String
    let brand: String
    let name: String
    let category: String
    let productType: String?
    let priceValue: Int
    let currency: String
    let routineStep: String?
}

extension AdvisorSelectionProduct {
    init(product: RecommendationProduct) {
        self.init(
            sku: product.sku,
            brand: product.brand,
            name: product.name,
            category: product.category,
            productType: product.productType,
            priceValue: product.priceValue,
            currency: product.currency,
            routineStep: product.routineStep
        )
    }

    init(product: Product) {
        self.init(
            sku: product.sku,
            brand: product.brand,
            name: product.name,
            category: product.category,
            productType: product.productType,
            priceValue: product.priceValue,
            currency: product.currency,
            routineStep: nil
        )
    }
}

struct AdvisorMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    let text: String
    let createdAt: Date?
    let recommendedSkus: [String]

    init(id: UUID = UUID(), role: String, text: String, createdAt: Date?, recommendedSkus: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.recommendedSkus = recommendedSkus
    }

    enum CodingKeys: String, CodingKey {
        case id, role, text, content, createdAt, recommendedSkus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawId = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: rawId.replacingOccurrences(of: "msg_", with: "")) {
            id = uuid
        } else {
            id = UUID()
        }
        role = try container.decode(String.self, forKey: .role)
        if let decodedText = try? container.decode(String.self, forKey: .text) {
            text = decodedText
        } else {
            text = try container.decode(String.self, forKey: .content)
        }
        createdAt = try? container.decode(Date.self, forKey: .createdAt)
        recommendedSkus = (try? container.decode([String].self, forKey: .recommendedSkus)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(recommendedSkus, forKey: .recommendedSkus)
    }
}

struct AdvisorHistoryResponse: Codable, Equatable {
    let messages: [AdvisorMessage]
}

struct AdvisorResponse: Codable, Equatable {
    let answer: String
    let messages: [AdvisorMessage]
    let quickActions: [String]
    let actions: [AdvisorAction]?
    let recommendations: [RecommendationProduct]
    let recommendedSkus: [String]
    let routineSteps: [String]
    let whyThisWorks: String?
    let safetyNote: String?
    let fallbackReason: String?
    let promptVersion: String?
    let provider: String?
}

struct CartItem: Codable, Identifiable, Equatable {
    var id: String { sku }
    let sku: String
    let product: Product
    var quantity: Int
}

struct CartResponse: Codable, Equatable {
    let items: [CartItem]
    let totalItems: Int
    let subtotal: Int
    let currency: String
    let checkoutMode: String

    static let empty = CartResponse(items: [], totalItems: 0, subtotal: 0, currency: "RUB", checkoutMode: "unavailable")
}

struct SavedRoutineRequest: Codable {
    let skus: [String]
}

struct SavedRoutineResponse: Codable, Equatable {
    let skus: [String]
    let products: [Product]
    let updatedAt: Date?
}

struct ActiveSelectionItemRequest: Codable {
    let sku: String
    let source: String
    let routineStep: String?
    let reason: String?
    let matchScore: Int?
    let locked: Bool
    let metadata: [String: JSONValue]?

    init(product: RecommendationProduct, source: String = "manual", locked: Bool = false) {
        self.sku = product.sku
        self.source = source
        self.routineStep = product.routineStep
        self.reason = product.reason
        self.matchScore = product.matchScore
        self.locked = locked
        self.metadata = nil
    }
}

struct ActiveSelectionPutRequest: Codable {
    let items: [ActiveSelectionItemRequest]
}

struct ActiveSelectionPatchRequest: Codable {
    let items: [ActiveSelectionItemRequest]
}

struct ActiveSelectionItem: Codable, Identifiable, Equatable {
    var id: String { sku }
    let sku: String
    let product: Product
    let source: String
    let routineStep: String?
    let reason: String?
    let matchScore: Int?
    let addedAt: Date?
    let updatedAt: Date?
    let locked: Bool?
    let metadata: [String: JSONValue]?
}

struct ActiveSelectionResponse: Codable, Equatable {
    let items: [ActiveSelectionItem]
    let skus: [String]
    let count: Int
    let totalPrice: Int
    let currency: String
    let averageMatch: Double?
    let updatedAt: Date?
    let sourceSummary: [String: Int]
    let addedCount: Int?
    let alreadyInSelectionCount: Int?

    static let empty = ActiveSelectionResponse(items: [], skus: [], count: 0, totalPrice: 0, currency: "RUB", averageMatch: nil, updatedAt: nil, sourceSummary: [:], addedCount: nil, alreadyInSelectionCount: nil)
}

struct AddCartItemRequest: Codable {
    let sku: String
    let quantity: Int
}

struct UpdateCartItemRequest: Codable {
    let quantity: Int
}

struct CheckoutResponse: Codable, Equatable {
    let status: String
    let handoffUrl: String?
    let message: String
    let cart: CartResponse
}

struct EnvironmentResponse: Codable, Equatable {
    let appEnv: String
    let mode: [String: JSONValue]
    let releaseCandidate: Bool
}

struct PrivacyRequestResponse: Codable, Equatable {
    let requestId: String
    let status: String
    let message: String
}

struct FeedbackRequest: Codable {
    let rating: Int
    let message: String
    let context: String?
    let appVersion: String?
    let build: String?
}

struct FeedbackResponse: Codable, Equatable {
    let id: String
    let createdAt: Date?
    let message: String
}

struct EventRequest: Codable {
    let eventName: String
    let payload: [String: JSONValue]
    let appVersion: String?
    let build: String?
    let platform: String?
}

struct EventResponse: Codable, Equatable {
    let id: String
    let createdAt: Date?
}

struct JSONValue: Codable, Equatable, Hashable {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { description = value }
        else if let value = try? container.decode(Int.self) { description = String(value) }
        else if let value = try? container.decode(Double.self) { description = String(value) }
        else if let value = try? container.decode(Bool.self) { description = value ? "true" : "false" }
        else if let value = try? container.decode([String].self) { description = value.joined(separator: ", ") }
        else { description = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

struct ProfileResponse: Codable, Equatable {
    let account: Account
    let beautyId: BeautyIDResponse?
    let savedRoutines: [SavedRoutineResponse]?
    let recommendationHistory: [[String: JSONValue]]?
    let orderHistory: [[String: JSONValue]]?
    let privacy: [String: JSONValue]?
}

enum LifeScenario: String, CaseIterable, Identifiable, Codable, Equatable {
    case morning
    case evening
    case underBudget
    case gift
    case replaceOneProduct
    case travel
    case minimalRoutine
    case premiumRoutine

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .morning: return "Утренний уход"
        case .evening: return "Вечерний уход"
        case .underBudget: return "В рамках бюджета"
        case .gift: return "Подарок"
        case .replaceOneProduct: return "Заменить один товар"
        case .travel: return "В поездку"
        case .minimalRoutine: return "Минимальный набор"
        case .premiumRoutine: return "Премиальный набор"
        }
    }

    var subtitle: String {
        switch self {
        case .morning: return "Быстро, легко, с SPF"
        case .evening: return "Очищение и комфорт"
        case .underBudget: return "Собрать набор в рамках суммы"
        case .gift: return "Универсальнее и безопаснее"
        case .replaceOneProduct: return "Если закончилось или не подошло"
        case .travel: return "Компактно и без лишних шагов"
        case .minimalRoutine: return "Оставить только главное"
        case .premiumRoutine: return "Более выразительные формулы"
        }
    }

    var recommendationFocus: String {
        switch self {
        case .morning: return "утро SPF лёгкий набор"
        case .evening: return "вечер очищение комфорт"
        case .underBudget: return "дешевле до бюджета"
        case .gift: return "подарок меньше риска"
        case .replaceOneProduct: return "заменить один товар"
        case .travel: return "поездка компактно"
        case .minimalRoutine: return "минимальный набор"
        case .premiumRoutine: return "премиум набор"
        }
    }

    var rolePriorities: [RoutineRole] {
        switch self {
        case .morning: return [.spf, .cleanser, .serum, .foundationTint, .lip]
        case .evening: return [.cleanser, .serum, .moisturizer, .mask, .lip]
        case .underBudget: return [.spf, .cleanser, .moisturizer, .serum, .lip]
        case .gift: return [.serum, .mask, .lip, .moisturizer, .spf]
        case .replaceOneProduct: return [.spf, .moisturizer, .serum, .cleanser, .foundationTint, .lip]
        case .travel: return [.cleanser, .spf, .moisturizer, .lip]
        case .minimalRoutine: return [.cleanser, .spf, .moisturizer]
        case .premiumRoutine: return [.serum, .spf, .foundationTint, .lip, .mascara]
        }
    }

    var defaultCopy: String {
        switch self {
        case .morning:
            return "Luma оставляет быстрые дневные шаги и не дублирует то, что уже есть."
        case .evening:
            return "Фокус на очищении, комфорте и спокойном восстановлении без медицинских обещаний."
        case .underBudget:
            return "Подбор показывает цену набора и честный компромисс по шагам."
        case .gift:
            return "Больше универсальных категорий и меньше оттеночного риска."
        case .replaceOneProduct:
            return "Ищем альтернативу тому, что закончилось, не подошло или стало слишком дорогим."
        case .travel:
            return "Компактный набор без лишних банок."
        case .minimalRoutine:
            return "Только базовые шаги, чтобы не перегрузить уход."
        case .premiumRoutine:
            return "Премиальные альтернативы без обещаний результата."
        }
    }
}

enum RoutineRole: String, CaseIterable, Identifiable, Codable, Equatable, Hashable {
    case cleanser
    case moisturizer
    case spf
    case serum
    case toner
    case mask
    case foundationTint
    case concealer
    case powder
    case mascara
    case lip
    case blush
    case brow
    case makeupRemover
    case bodyCare
    case giftSafe
    case unknown

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .cleanser: return "Очищение"
        case .moisturizer: return "Крем / увлажнение"
        case .spf: return "SPF"
        case .serum: return "Сыворотка"
        case .toner: return "Тонер"
        case .mask: return "Маска"
        case .foundationTint: return "Тон / tint"
        case .concealer: return "Консилер"
        case .powder: return "Пудра"
        case .mascara: return "Тушь"
        case .lip: return "Средство для губ"
        case .blush: return "Румяна"
        case .brow: return "Брови"
        case .makeupRemover: return "Демакияж"
        case .bodyCare: return "Уход для тела"
        case .giftSafe: return "Подарочный шаг"
        case .unknown: return "Другое"
        }
    }

    static func from(product: RecommendationProduct) -> RoutineRole {
        let values = [
            product.category,
            product.productType ?? "",
            product.categoryGroup ?? "",
            product.routineStep,
            product.tags.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        return from(category: values)
    }

    static func from(product: Product) -> RoutineRole {
        let values = [
            product.category,
            product.productType ?? "",
            product.categoryGroup ?? "",
            product.tags.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        return from(category: values)
    }

    static func from(category: String) -> RoutineRole {
        let text = category.lowercased()
        if text.contains("cleanser") || text.contains("очищ") { return .cleanser }
        if text.contains("makeup_remover") || text.contains("демакияж") { return .makeupRemover }
        if text.contains("moisturizer") || text.contains("cream") || text.contains("крем") || text.contains("увлаж") { return .moisturizer }
        if text.contains("spf") || text.contains("sunscreen") { return .spf }
        if text.contains("serum") || text.contains("сывор") { return .serum }
        if text.contains("toner") || text.contains("тонер") { return .toner }
        if text.contains("mask") || text.contains("маска") { return .mask }
        if text.contains("foundation") || text.contains("skin_tint") || text.contains("tint") || text.contains("тон") { return .foundationTint }
        if text.contains("concealer") || text.contains("консил") { return .concealer }
        if text.contains("powder") || text.contains("пудр") { return .powder }
        if text.contains("mascara") || text.contains("туш") { return .mascara }
        if text.contains("lip") || text.contains("губ") || text.contains("помад") || text.contains("бальзам") { return .lip }
        if text.contains("blush") || text.contains("румян") { return .blush }
        if text.contains("brow") || text.contains("бров") { return .brow }
        if text.contains("body") || text.contains("тело") { return .bodyCare }
        return .unknown
    }
}

enum ShelfStatus: String, CaseIterable, Identifiable, Codable, Equatable {
    case owned
    case wanted
    case buyLater
    case didNotFit
    case empty
    case likes
    case needsReplacement

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .owned: return "Уже есть"
        case .wanted: return "Хочу попробовать"
        case .buyLater: return "Куплю позже"
        case .didNotFit: return "Не подошло"
        case .empty: return "Закончилось"
        case .likes: return "Нравится"
        case .needsReplacement: return "Нужна замена"
        }
    }

    var businessMeaning: String {
        switch self {
        case .owned: return "не дублировать роль без запроса"
        case .wanted: return "товары, которые хочется попробовать"
        case .buyLater: return "тёплое намерение купить позже"
        case .didNotFit: return "негативный сигнал по товару"
        case .empty: return "возможность пополнения или замены"
        case .likes: return "положительный сигнал вкуса"
        case .needsReplacement: return "явный запрос на замену"
        }
    }
}

enum ShelfIssueReason: String, CaseIterable, Identifiable, Codable, Equatable {
    case fragrance
    case texture
    case price
    case shade
    case tooHeavy
    case tooDrying
    case didNotTrust
    case notInterested
    case other

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .fragrance: return "Запах / отдушка"
        case .texture: return "Текстура"
        case .price: return "Цена"
        case .shade: return "Оттенок"
        case .tooHeavy: return "Слишком тяжёлый"
        case .tooDrying: return "Сушит"
        case .didNotTrust: return "Не доверяю"
        case .notInterested: return "Неинтересно"
        case .other: return "Другое"
        }
    }
}

enum ReplacementReason: String, CaseIterable, Identifiable, Codable, Equatable {
    case cheaper
    case fragranceFree
    case lighterTexture
    case premiumUpgrade
    case similarButDifferent
    case lessRisk
    case other

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .cheaper: return "Дешевле"
        case .fragranceFree: return "Без отдушки"
        case .lighterTexture: return "Легче текстура"
        case .premiumUpgrade: return "Премиальнее"
        case .similarButDifferent: return "Похожий, но другой"
        case .lessRisk: return "Меньше риска"
        case .other: return "Другое"
        }
    }
}

struct ShelfItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var sku: String?
    var product: RecommendationProduct?
    var brand: String?
    var name: String
    var displayName: String?
    var category: String?
    var priceValue: Int?
    var currency: String?
    var imageUrl: String?
    var cardImageUrl: String?
    var role: RoutineRole
    var status: ShelfStatus
    var issueReason: ShelfIssueReason?
    var replacementReason: ReplacementReason?
    var createdAt: Date
    var updatedAt: Date
    var source: String

    init(product: RecommendationProduct, status: ShelfStatus, issueReason: ShelfIssueReason? = nil, replacementReason: ReplacementReason? = nil, source: String) {
        self.sku = product.sku
        self.product = product
        self.brand = product.brand
        self.name = product.name
        self.displayName = product.displayName
        self.category = product.category
        self.priceValue = product.priceValue
        self.currency = product.currency
        self.imageUrl = product.imageUrl
        self.cardImageUrl = product.cardImageUrl
        self.role = RoutineRole.from(product: product)
        self.status = status
        self.issueReason = issueReason
        self.replacementReason = replacementReason
        self.createdAt = Date()
        self.updatedAt = Date()
        self.source = source
    }

    init(role: RoutineRole, status: ShelfStatus, source: String) {
        self.sku = nil
        self.product = nil
        self.brand = nil
        self.name = role.displayTitle
        self.displayName = role.displayTitle
        self.category = role.analyticsValue
        self.priceValue = nil
        self.currency = nil
        self.imageUrl = nil
        self.cardImageUrl = nil
        self.role = role
        self.status = status
        self.issueReason = nil
        self.replacementReason = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.source = source
    }
}

enum RoutineVariantType: String, CaseIterable, Identifiable, Codable, Equatable {
    case original
    case cheaper
    case minimal
    case balanced
    case premium
    case fragranceFree

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .original: return "Исходный"
        case .cheaper: return "Дешевле"
        case .minimal: return "Минимум"
        case .balanced: return "Баланс"
        case .premium: return "Премиум"
        case .fragranceFree: return "Без отдушки"
        }
    }
}

struct RoutineVariant: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let type: RoutineVariantType
    let title: String
    let subtitle: String?
    let scenario: LifeScenario?
    let products: [RecommendationProduct]
    let totalPrice: Int
    let currency: String
    let productCount: Int
    let whatChanged: [String]
    let benefits: [String]
    let tradeoffs: [String]
    let explanation: String
    let generatedAt: Date
    let sourceRoutineId: UUID?
}

enum RoutineComparisonType: String, CaseIterable, Identifiable, Codable, Equatable {
    case originalVsCheaper
    case minimalVsBalanced
    case balancedVsPremium

    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .originalVsCheaper: return "Исходный vs дешевле"
        case .minimalVsBalanced: return "Минимум и баланс"
        case .balancedVsPremium: return "Баланс и премиум"
        }
    }
}

struct RoutineComparison: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let leftVariant: RoutineVariant
    let rightVariant: RoutineVariant
    let comparisonType: RoutineComparisonType
    let summary: String
    let priceDelta: Int
    let productCountDelta: Int
    let keyChanges: [String]
    let recommendedChoice: RoutineVariantType?
    let createdAt: Date
}

enum PurchaseBlocker: String, CaseIterable, Identifiable, Codable, Equatable {
    case tooExpensive
    case notSure
    case shadeConcern
    case wantsReviews
    case wantsToCompare
    case wantsToSeeInStore
    case tooManyProducts
    case wantsReplacement
    case buyLater
    case nothingBlocking

    var id: String { rawValue }
    var analyticsValue: String { rawValue }

    var displayTitle: String {
        switch self {
        case .tooExpensive: return "Сделать дешевле"
        case .notSure: return "Не уверена"
        case .shadeConcern: return "Не уверена в оттенке"
        case .wantsReviews: return "Хочу отзывы"
        case .wantsToCompare: return "Хочу сравнить"
        case .wantsToSeeInStore: return "Хочу посмотреть в магазине"
        case .tooManyProducts: return "Слишком много товаров"
        case .wantsReplacement: return "Хочу заменить один товар"
        case .buyLater: return "Куплю позже"
        case .nothingBlocking: return "Ничего, набор подходит"
        }
    }

    var subtitle: String? {
        switch self {
        case .tooExpensive: return "Покажем более доступный вариант"
        case .tooManyProducts: return "Оставим только главное"
        case .wantsReviews: return "В каталоге отзывы не подключены"
        case .wantsToSeeInStore: return "Наличие в магазине пока не подключено"
        case .nothingBlocking: return "Сохраним сильное намерение купить"
        default: return nil
        }
    }

    var actionType: String {
        switch self {
        case .tooExpensive: return "show_cheaper_routine"
        case .tooManyProducts: return "show_minimal_routine"
        case .wantsToCompare: return "open_comparison"
        case .wantsReplacement: return "start_replacement"
        case .buyLater: return "mark_buy_later"
        case .shadeConcern: return "show_shade_warning"
        case .wantsReviews: return "record_reviews_blocker"
        case .wantsToSeeInStore: return "record_store_blocker"
        case .notSure: return "show_explanation"
        case .nothingBlocking: return "record_strong_intent"
        }
    }
}

enum PurchaseIntentLevel: String, CaseIterable, Identifiable, Codable, Equatable {
    case low
    case medium
    case high
    case veryHigh

    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .low: return "низкий"
        case .medium: return "средний"
        case .high: return "высокий"
        case .veryHigh: return "очень высокий"
        }
    }
}

struct PurchaseIntentProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let createdAt: Date
    let scenario: LifeScenario?
    let budget: String
    let constraintsSummary: String
    let ownedRoles: [RoutineRole]
    let shelfSignalsSummary: String
    let routineVariantType: RoutineVariantType?
    let routineTotalPrice: Int?
    let productCount: Int?
    let productsOpened: [String]
    let productsReplaced: [String]
    let comparisonOpened: Bool
    let selectedVariant: RoutineVariantType?
    let savedRoutine: Bool
    let purchaseIntentClicked: Bool
    let selectedBlocker: PurchaseBlocker?
    let actionAfterBlocker: String?
    let intentLevel: PurchaseIntentLevel
    let businessSummary: String
}

extension Product {
    var isUnavailable: Bool { !availability || inventoryStatus == "out_of_stock" }
    var isLocalSeed: Bool { (source ?? "").contains("local") }
    var preferredImagePath: String? { imageUrl ?? cardImageUrl }
}

extension RecommendationProduct {
    var isUnavailable: Bool { !availability || inventoryStatus == "out_of_stock" }
    var isLocalSeed: Bool { (source ?? "").contains("local") }
    var preferredImagePath: String? { imageUrl ?? cardImageUrl }
}

extension ActiveSelectionItem {
    var asRecommendation: RecommendationProduct {
        RecommendationProduct(
            sku: product.sku,
            sourceSku: product.sourceSku,
            catalogNumber: product.catalogNumber,
            brand: product.brand,
            name: product.name,
            variant: product.variant,
            displayName: product.displayName,
            category: product.category,
            domain: product.domain,
            priceSegment: product.priceSegment,
            priceValue: product.priceValue,
            currency: product.currency,
            imageUrl: product.imageUrl,
            gallery: product.gallery,
            availability: product.availability,
            inventoryStatus: product.inventoryStatus,
            skinTypes: product.skinTypes,
            concerns: product.concerns,
            tags: product.tags,
            ingredients: product.ingredients,
            ingredientHighlights: product.ingredientHighlights,
            exclusions: product.exclusions,
            finishes: product.finishes,
            coverageLevels: product.coverageLevels,
            colorFamilies: product.colorFamilies,
            texture: product.texture,
            rating: product.rating,
            reviewCount: product.reviewCount,
            warnings: product.warnings,
            source: product.source,
            assetSource: product.assetSource,
            cardImageUrl: product.cardImageUrl,
            productType: product.productType,
            categoryGroup: product.categoryGroup,
            updatedAt: product.updatedAt,
            matchScore: matchScore ?? 72,
            reason: reason ?? "добавлено в текущую подборку",
            routineStep: routineStep ?? product.category.beautyLabel,
            alternatives: []
        )
    }
}

extension ActiveSelectionResponse {
    var recommendations: [RecommendationProduct] {
        items.map(\.asRecommendation)
    }

    func asRecommendationsResponse(disclaimer: String = "Косметический подбор, не медицинская рекомендация.") -> RecommendationsResponse {
        let products = recommendations
        return RecommendationsResponse(
            hero: products.first,
            routine: products,
            products: products,
            explanation: "Текущая активная подборка Luma.",
            disclaimer: disclaimer,
            generatedAt: updatedAt ?? Date()
        )
    }
}

struct BeautyArchetype: Equatable {
    let name: String
    let tagline: String
}

extension BeautyID {
    /// Короткий «beauty-тип» по ответам анкеты — это и есть герой «вау»-экрана.
    /// Порядок проверок = приоритет: сначала самые определяющие черты.
    var archetype: BeautyArchetype {
        let concernSet = Set(concerns)
        let finishSet = Set(preferredFinish)
        if sensitivity == "high" || fragranceSensitivity == "avoid" {
            return BeautyArchetype(name: "Спокойный комфорт", tagline: "Бережный уход без отдушек и резких формул.")
        }
        if budget == "premium" || budget == "luxury" {
            return BeautyArchetype(name: "Тихий люкс", tagline: "Премиальные текстуры без лишнего шума.")
        }
        if finishSet.contains("radiant") || finishSet.contains("glow") || concernSet.contains("dullness") {
            return BeautyArchetype(name: "Тёплое сияние", tagline: "Свежесть и мягкий свет кожи каждый день.")
        }
        if finishSet.contains("matte") || concernSet.contains("shine") {
            return BeautyArchetype(name: "Свежая матовость", tagline: "Ровный тон и комфорт без пересушивания.")
        }
        if routineComplexity == "minimal" || budget == "entry" {
            return BeautyArchetype(name: "Мягкий минимализм", tagline: "Только нужное — ничего лишнего.")
        }
        return BeautyArchetype(name: "Естественная гармония", tagline: "Сбалансированный уход под твой ритм.")
    }

    var dashboardTitle: String {
        if let skinType { return "\(skinType.beautyLabel.capitalized) кожа" }
        if let firstConcern = concerns.first { return "Фокус: \(firstConcern.beautyLabel)" }
        return "Профиль предпочтений"
    }

    var dashboardSubtitle: String {
        let finish = preferredFinish.first?.beautyLabel ?? "естественный финиш"
        let complexity = routineComplexity.beautyLabel
        return "\(complexity) · \(finish) · \(budget.beautyLabel)"
    }

    var summaryChips: [String] {
        var values: [String] = []
        if let skinType { values.append(skinType.beautyLabel) }
        values.append(contentsOf: concerns.prefix(2).map(\.beautyLabel))
        values.append(contentsOf: preferredFinish.prefix(1).map(\.beautyLabel))
        if let fragranceSensitivity { values.append(fragranceSensitivity.beautyLabel) }
        values.append(budget.beautyLabel)
        values.append(routineComplexity.beautyLabel)
        return Array(NSOrderedSet(array: values).compactMap { $0 as? String }).filter { !$0.isEmpty }.prefix(6).map { $0 }
    }
}

extension String {
    var beautyLabel: String {
        [
            "dry": "сухая",
            "oily": "жирная",
            "combination": "комбинированная",
            "normal": "нормальная",
            "sensitive": "чувствительная",
            "low": "низкая чувствительность",
            "medium": "средняя чувствительность",
            "high": "высокая чувствительность",
            "dryness": "сухость",
            "dullness": "тусклость",
            "texture": "рельеф",
            "redness": "покраснение",
            "pores": "поры",
            "shine": "блеск",
            "longwear": "стойкость",
            "comfort": "комфорт",
            "natural": "естественный финиш",
            "radiant": "сияющий финиш",
            "matte": "матовый финиш",
            "satin": "сатиновый финиш",
            "glow": "сияние",
            "tone": "тон",
            "conceal": "маскировка",
            "blush": "румянец",
            "lips": "губы",
            "quick": "быстро",
            "editorial": "акцентный образ",
            "avoid": "без отдушки",
            "light_ok": "лёгкая отдушка ок",
            "no_preference": "отдушка не важна",
            "entry": "базовый бюджет",
            "mid": "средний бюджет",
            "premium": "премиум",
            "luxury": "люкс",
            "minimal": "минимальный набор",
            "balanced": "сбалансированный набор",
            "extended": "расширенный набор",
            "cleanser": "очищение",
            "serum": "сыворотка",
            "moisturizer": "крем",
            "cream": "крем",
            "spf": "SPF",
            "lip tint": "тинт",
            "mascara": "тушь",
            "foundation": "тон",
            "skin_tint": "тинт",
            "tint": "тинт",
            "soft luxury": "мягкий люкс",
            "k-beauty": "K-beauty",
            "clean": "clean",
            "office": "офис",
            "evening": "вечер",
        ][self] ?? replacingOccurrences(of: "_", with: " ")
    }
}

extension Int {
    var rub: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        let value = formatter.string(from: NSNumber(value: self)) ?? String(self)
        return "\(value) ₽"
    }

    var productWord: String {
        "\(self) \(Self.russianPlural(self, one: "товар", few: "товара", many: "товаров"))"
    }

    var stepWord: String {
        "\(self) \(Self.russianPlural(self, one: "шаг", few: "шага", many: "шагов"))"
    }

    var profileWord: String {
        "\(self) \(Self.russianPlural(self, one: "профиль", few: "профиля", many: "профилей"))"
    }

    var categoryWord: String {
        "\(self) \(Self.russianPlural(self, one: "категория", few: "категории", many: "категорий"))"
    }

    private static func russianPlural(_ count: Int, one: String, few: String, many: String) -> String {
        let value = abs(count)
        let mod100 = value % 100
        if (11...14).contains(mod100) { return many }
        switch value % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
