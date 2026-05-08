import Foundation

enum LocalFallbackCatalog {
    static func response(focus: String? = nil) -> RecommendationsResponse {
        let products = sampleProducts(focus: focus)
        return RecommendationsResponse(
            hero: products.first,
            routine: Array(products.prefix(5)),
            products: products,
            explanation: focus == nil ? "Показана сохранённая подборка по Beauty ID." : "Подборка уточнена под «\(focus ?? "")».",
            disclaimer: "Косметический подбор, не медицинская рекомендация.",
            generatedAt: Date()
        )
    }

    static func sampleProducts(focus: String? = nil) -> [RecommendationProduct] {
        let base = [
            make("LUMA-001", "Lumiere Daily", "Everyday Skin Foundation LIGHT NEUTRAL", "foundation", "makeup", 890, "budget", 94, "тон", "натуральный сатиновый тон выравнивает оттенок; совпадение 94 из 100", ["complexion", "shade-match", "buildable"], ["glycerin", "squalane"]),
            make("LUMA-002", "Lumiere Daily", "Bright Flex Concealer LIGHT NEUTRAL", "concealer", "makeup", 1190, "budget", 92, "консилер", "лёгкое наслаиваемое покрытие для зоны под глазами; совпадение 92 из 100", ["complexion", "brightening", "buildable"], ["glycerin", "squalane"]),
            make("LUMA-003", "Lumiere Daily", "Soft Set Loose Powder TRANSLUCENT", "powder", "makeup", 1290, "budget", 91, "пудра", "фиксирует тон и мягко блюрит текстуру; совпадение 91 из 100", ["set", "blur", "soft-focus"], ["mica", "silica"]),
            make("LUMA-004", "Lumiere Daily", "Blurring Pact Powder LIGHT", "powder", "makeup", 990, "budget", 90, "пудра", "быстрый матирующий шаг для T-зоны; совпадение 90 из 100", ["set", "blur", "soft-focus"], ["mica", "silica"]),
            make("LUMA-005", "Color Atelier", "Soft Nude Palette", "eyeshadow_palette", "makeup", 1090, "budget", 88, "палетка теней", "нейтральные оттенки для мягкого дневного макияжа; совпадение 88 из 100", ["palette", "blendable", "color"], ["mica", "silica"]),
            make("LUMA-006", "Face Poetry", "Cloud Flush Blush PEACH", "blush", "makeup", 990, "budget", 86, "румяна", "свежий персиковый акцент без перегруза; совпадение 86 из 100", ["cheek", "blendable", "soft-color"], ["mica", "silica"])
        ]
        if focus?.lowercased().contains("дешев") == true {
            return base.sorted { $0.priceValue < $1.priceValue }
        }
        return base
    }

    private static func make(_ sku: String, _ brand: String, _ name: String, _ category: String, _ domain: String, _ price: Int, _ segment: String, _ score: Int, _ step: String, _ reason: String, _ tags: [String], _ ingredients: [String]) -> RecommendationProduct {
        RecommendationProduct(
            sku: sku,
            sourceSku: sku,
            catalogNumber: nil,
            brand: brand,
            name: name,
            variant: nil,
            displayName: "\(brand) \(name)",
            category: category,
            domain: domain,
            priceSegment: segment,
            priceValue: price,
            currency: "RUB",
            imageUrl: nil,
            gallery: [],
            availability: true,
            inventoryStatus: "in_stock",
            skinTypes: ["combination", "normal", "sensitive"],
            concerns: ["dryness", "dullness"],
            tags: tags,
            ingredients: ingredients,
            ingredientHighlights: Array(ingredients.prefix(3)),
            exclusions: [],
            finishes: tags.filter { ["radiant", "satin", "matte", "glow"].contains($0) },
            coverageLevels: tags.contains("light coverage") ? ["light"] : [],
            colorFamilies: [],
            texture: category == "serum" ? "gel-serum" : "cream",
            rating: nil,
            reviewCount: nil,
            warnings: [],
            source: "local_seed",
            assetSource: nil,
            cardImageUrl: nil,
            productType: category,
            categoryGroup: domain,
            updatedAt: Date(),
            matchScore: score,
            reason: reason,
            routineStep: step,
            alternatives: []
        )
    }
}
