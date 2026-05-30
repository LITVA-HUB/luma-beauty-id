import Foundation

// Pure recommendation/selection math extracted from the AppState monolith.
// These are stateless helpers (no @Published access), the first step of the
// staged AppState decomposition described in docs/maturity-pass-2026-05-29.md.
extension AppState {
    static func mergedRecommendations(existing: RecommendationsResponse, incoming: [RecommendationProduct]) -> (response: RecommendationsResponse, addedCount: Int, duplicateCount: Int) {
        var products = existing.products
        var routine = existing.routine
        var seenProducts = Set(products.map(\.sku))
        var seenRoutine = Set(routine.map(\.sku))
        var added = 0
        var duplicates = 0

        for product in incoming {
            let alreadyInProducts = seenProducts.contains(product.sku)
            if let index = products.firstIndex(where: { $0.sku == product.sku }) {
                products[index] = product
                duplicates += 1
            } else {
                products.append(product)
                seenProducts.insert(product.sku)
                if !alreadyInProducts { added += 1 }
            }

            if let index = routine.firstIndex(where: { $0.sku == product.sku }) {
                routine[index] = product
            } else if !seenRoutine.contains(product.sku) {
                routine.append(product)
                seenRoutine.insert(product.sku)
            }
        }

        let hero = existing.hero.flatMap { hero in products.first(where: { $0.sku == hero.sku }) } ?? products.first
        return (
            response: RecommendationsResponse(
                hero: hero,
                routine: routine,
                products: products,
            explanation: "Советник добавил новые варианты к текущему набору.",
                disclaimer: existing.disclaimer,
                generatedAt: Date()
            ),
            addedCount: added,
            duplicateCount: duplicates
        )
    }

    static func recommendationsResponse(from products: [RecommendationProduct], explanation: String) -> RecommendationsResponse {
        let unique = uniqueProducts(products)
        return RecommendationsResponse(
            hero: unique.first,
            routine: unique,
            products: unique,
            explanation: explanation,
            disclaimer: "Косметический подбор, не медицинская рекомендация.",
            generatedAt: Date()
        )
    }

    static func uniqueProducts(_ products: [RecommendationProduct]) -> [RecommendationProduct] {
        var seen: Set<String> = []
        return products.filter { product in
            guard !seen.contains(product.sku) else { return false }
            seen.insert(product.sku)
            return true
        }
    }

    static func uniqueSkus(_ skus: [String]) -> [String] {
        var seen: Set<String> = []
        return skus.compactMap { raw in
            let sku = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sku.isEmpty, !seen.contains(sku) else { return nil }
            seen.insert(sku)
            return sku
        }
    }

    static func selectionNotice(added: Int, duplicates: Int) -> String? {
        if added > 0 && duplicates > 0 { return "Добавлено \(added.productWord), \(duplicates) уже были в наборе" }
        if added > 0 { return "Добавлено \(added.productWord) в набор" }
        if duplicates > 0 { return "\(duplicates) уже были в наборе" }
        return nil
    }

    static func isExecutableAdvisorAction(_ type: String) -> Bool {
        [
            "add_products",
            "add_products_to_selection",
            "remove_products_from_selection",
            "clear_selection",
            "replace_product_confirmed",
            "add_current_routine_to_shelf",
            "add_product_to_shelf",
            "mark_product_wanted",
            "mark_product_owned",
            "mark_product_buy_later",
            "mark_product_did_not_fit",
            "add_products_to_cart",
            "add_current_routine_to_cart",
            "remove_products_from_cart",
            "clear_cart",
            "move_selection_to_cart",
            "add_selection_to_cart",
            "save_selection_as_routine",
            "save_current_routine"
        ].contains(type)
    }
}
