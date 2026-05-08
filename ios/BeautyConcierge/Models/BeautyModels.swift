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
    let email: String
    let createdAt: Date?
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
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let name: String
    let email: String
    let password: String
    let consent: Bool
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

extension Int {
    var rub: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        let value = formatter.string(from: NSNumber(value: self)) ?? String(self)
        return "\(value) ₽"
    }
}
