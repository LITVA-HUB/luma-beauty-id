import XCTest
@testable import BeautyConcierge

final class BeautyConciergeTests: XCTestCase {
    func testCurrencyFormatting() {
        XCTAssertEqual(3125.rub, "3 125 ₽")
    }

    func testRussianPluralizationHelpers() {
        XCTAssertEqual(1.productWord, "1 товар")
        XCTAssertEqual(2.productWord, "2 товара")
        XCTAssertEqual(5.productWord, "5 товаров")
        XCTAssertEqual(1.stepWord, "1 шаг")
        XCTAssertEqual(4.stepWord, "4 шага")
        XCTAssertEqual(5.stepWord, "5 шагов")
    }

    func testProductionEnvironmentHidesDevelopmentLogin() {
        let env = AppEnvironment(baseURL: URL(string: "https://api.example.com")!, runtime: .production, isDebug: false)
        XCTAssertFalse(env.canShowDevLogin)
        XCTAssertTrue(env.usesReleaseAPI)
    }

    func testReleaseEnvironmentCanBlockInvalidAPIConfiguration() {
        let env = AppEnvironment(
            baseURL: URL(string: "https://staging-api-url-required.invalid")!,
            runtime: .staging,
            isDebug: false,
            configurationError: "Сервис временно недоступен. Staging API URL не настроен."
        )
        XCTAssertFalse(env.canShowDevLogin)
        XCTAssertTrue(env.usesReleaseAPI)
        XCTAssertFalse(env.canUseAPI)
        XCTAssertNotNil(env.configurationError)
    }

    func testUnavailableProductState() {
        let product = Product(
            sku: "SKU-TEST",
            brand: "Luma",
            name: "Unavailable Test Product",
            category: "serum",
            domain: "skincare",
            priceSegment: "mid",
            priceValue: 1000,
            currency: "RUB",
            imageUrl: nil,
            gallery: [],
            availability: false,
            inventoryStatus: "out_of_stock",
            skinTypes: [],
            concerns: [],
            tags: [],
            ingredients: [],
            ingredientHighlights: [],
            exclusions: [],
            finishes: [],
            coverageLevels: [],
            colorFamilies: [],
            texture: nil,
            rating: nil,
            reviewCount: nil,
            warnings: [],
            source: "test",
            updatedAt: nil
        )
        XCTAssertTrue(product.isUnavailable)
    }

    @MainActor
    func testAdvisorRecommendationsMergeIntoCurrentSelection() {
        let existing = makeRecommendation("SKU-1", name: "Cleanser", category: "cleanser", step: "очищение")
        let incoming = makeRecommendation("SKU-2", name: "SPF", category: "spf", step: "SPF")
        let current = RecommendationsResponse(
            hero: existing,
            routine: [existing],
            products: [existing],
            explanation: "Текущая подборка",
            disclaimer: "Косметический подбор",
            generatedAt: Date()
        )

        let merge = AppState.mergedRecommendations(existing: current, incoming: [incoming])

        XCTAssertEqual(merge.addedCount, 1)
        XCTAssertEqual(merge.duplicateCount, 0)
        XCTAssertEqual(merge.response.products.map(\.sku), ["SKU-1", "SKU-2"])
        XCTAssertEqual(merge.response.routine.map(\.sku), ["SKU-1", "SKU-2"])
    }

    @MainActor
    func testAdvisorRecommendationsDoNotDuplicateSkuAndRefreshMetadata() {
        let existing = makeRecommendation("SKU-1", name: "Old SPF", category: "spf", step: "SPF", reason: "старая причина", matchScore: 70)
        let updated = makeRecommendation("SKU-1", name: "Updated SPF", category: "spf", step: "SPF", reason: "обновлённая причина", matchScore: 91)
        let current = RecommendationsResponse(
            hero: existing,
            routine: [existing],
            products: [existing],
            explanation: "Текущая подборка",
            disclaimer: "Косметический подбор",
            generatedAt: Date()
        )

        let merge = AppState.mergedRecommendations(existing: current, incoming: [updated])

        XCTAssertEqual(merge.addedCount, 0)
        XCTAssertEqual(merge.duplicateCount, 1)
        XCTAssertEqual(merge.response.products.map(\.sku), ["SKU-1"])
        XCTAssertEqual(merge.response.products.first?.reason, "обновлённая причина")
        XCTAssertEqual(merge.response.products.first?.matchScore, 91)
    }

    @MainActor
    func testExplicitReplaceOnlyHappensWhenCalled() {
        let appState = AppState()
        let existing = makeRecommendation("SKU-1", name: "Cleanser", category: "cleanser", step: "очищение")
        let replacement = makeRecommendation("SKU-2", name: "SPF", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(
            hero: existing,
            routine: [existing],
            products: [existing],
            explanation: "Текущая подборка",
            disclaimer: "Косметический подбор",
            generatedAt: Date()
        )

        let merge = AppState.mergedRecommendations(existing: appState.recommendations, incoming: [replacement])
        appState.recommendations = merge.response
        XCTAssertEqual(appState.recommendations.products.map(\.sku), ["SKU-1", "SKU-2"])

        appState.replaceCurrentSelection(with: [replacement])
        XCTAssertEqual(appState.recommendations.products.map(\.sku), ["SKU-2"])
    }

    @MainActor
    func testAdvisorRequestCarriesCurrentSelectionAndCartContext() {
        let appState = AppState()
        let selected = makeRecommendation("SKU-1", name: "Cleanser", category: "cleanser", step: "очищение")
        let cartProduct = makeRecommendation("SKU-2", name: "SPF", category: "spf", step: "SPF")
        appState.savedRoutineSkus = []
        appState.activeSelection = activeSelectionResponse([selected])
        appState.cart = CartResponse(items: [CartItem(sku: cartProduct.sku, product: cartProduct.asProduct, quantity: 1)], totalItems: 1, subtotal: cartProduct.priceValue, currency: "RUB", checkoutMode: "development_handoff")

        let request = appState.makeAdvisorRequest(for: "добавь SPF")

        XCTAssertEqual(request.currentSelection.map(\.sku), ["SKU-1"])
        XCTAssertEqual(request.currentCart.map(\.sku), ["SKU-2"])
        XCTAssertEqual(request.currentSkus, ["SKU-1", "SKU-2"])
    }

    @MainActor
    func testCartIsNotClearedWhenAdvisorSelectionMerges() {
        let appState = AppState()
        let existing = makeRecommendation("SKU-1", name: "Cleanser", category: "cleanser", step: "очищение")
        let cartProduct = makeRecommendation("SKU-2", name: "SPF", category: "spf", step: "SPF")
        let incoming = makeRecommendation("SKU-3", name: "Cream", category: "cream", step: "крем")
        appState.recommendations = RecommendationsResponse(hero: existing, routine: [existing], products: [existing], explanation: "Текущая подборка", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.cart = CartResponse(items: [CartItem(sku: cartProduct.sku, product: cartProduct.asProduct, quantity: 1)], totalItems: 1, subtotal: cartProduct.priceValue, currency: "RUB", checkoutMode: "development_handoff")

        let merge = AppState.mergedRecommendations(existing: appState.recommendations, incoming: [incoming])
        appState.recommendations = merge.response

        XCTAssertEqual(appState.cart.items.map(\.sku), ["SKU-2"])
    }

    @MainActor
    func testAdvisorContextDoesNotTreatSuggestionsAsActiveSelection() {
        let appState = AppState()
        let suggested = makeRecommendation("SKU-1", name: "Suggestion", category: "spf", step: "SPF")
        let saved = makeRecommendation("SKU-2", name: "Saved", category: "cream", step: "крем")
        appState.recommendations = RecommendationsResponse(hero: suggested, routine: [suggested], products: [suggested], explanation: "Suggestions", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.activeSelection = .empty
        appState.savedRoutineSkus = [saved.sku]

        let request = appState.makeAdvisorRequest(for: "что у меня выбрано?")

        XCTAssertEqual(request.currentSelection.map(\.sku), [])
        XCTAssertEqual(request.currentSkus, [])
    }

    @MainActor
    func testLoadingSuggestionsDoesNotCreateActiveSelection() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        appState.activeSelection = .empty

        await appState.loadRecommendations(focus: nil, silent: true)

        XCTAssertFalse(appState.recommendations.products.isEmpty)
        XCTAssertEqual(appState.activeSelection.skus, [])
    }

    @MainActor
    func testAddSelectionToCartIgnoresRecommendationSuggestions() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let suggested = makeRecommendation("SKU-1", name: "Suggestion", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(hero: suggested, routine: [suggested], products: [suggested], explanation: "Suggestions", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.activeSelection = .empty

        let result = await appState.applyAdvisorAction(AdvisorAction(type: "add_selection_to_cart", skus: [suggested.sku], oldSku: nil, newSku: nil, reason: "добавить подборку", requiresConfirmation: false, metadata: nil))

        XCTAssertEqual(result, .failed("Текущий набор пуст. Сначала добавьте товары."))
        XCTAssertEqual(appState.cart.items.map(\.sku), [])
    }

    @MainActor
    func testSaveCurrentRoutineDoesNotSaveSuggestionFallback() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let suggested = makeRecommendation("SKU-1", name: "Suggestion", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(hero: suggested, routine: [suggested], products: [suggested], explanation: "Suggestions", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.activeSelection = .empty
        appState.savedRoutineSkus = []

        await appState.saveCurrentRoutine()

        XCTAssertEqual(appState.savedRoutineSkus, [])
        XCTAssertEqual(appState.checkoutMessage, "Сначала добавьте товары в текущий набор.")
    }

    @MainActor
    func testLogoutClearsAccountScopedLocalState() {
        let appState = AppState()
        let selected = makeRecommendation("SKU-1", name: "Selected", category: "spf", step: "SPF")
        appState.account = Account(accountId: "account-a", name: "A", email: "a@example.com", createdAt: Date())
        appState.recommendations = RecommendationsResponse(hero: selected, routine: [selected], products: [selected], explanation: "Account suggestions", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.activeSelection = activeSelectionResponse([selected])
        appState.cart = CartResponse(items: [CartItem(sku: selected.sku, product: selected.asProduct, quantity: 1)], totalItems: 1, subtotal: selected.priceValue, currency: "RUB", checkoutMode: "development_handoff")
        appState.savedProducts = [selected.sku]
        appState.savedRoutineSkus = [selected.sku]
        appState.advisorMessages = [AdvisorMessage(role: "assistant", text: "old", createdAt: Date())]

        appState.logout()

        XCTAssertNil(appState.account)
        XCTAssertEqual(appState.recommendations.products.map(\.sku), [])
        XCTAssertEqual(appState.activeSelection.skus, [])
        XCTAssertEqual(appState.cart.items.map(\.sku), [])
        XCTAssertEqual(appState.savedProducts, [])
        XCTAssertEqual(appState.savedRoutineSkus, [])
        XCTAssertEqual(appState.advisorMessages, [])
    }

    @MainActor
    func testApplyAdvisorActionAddsActiveSelectionToCart() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let selected = makeRecommendation("SKU-1", name: "SPF", category: "spf", step: "SPF")
        appState.activeSelection = activeSelectionResponse([selected])

        await appState.applyAdvisorAction(AdvisorAction(type: "add_selection_to_cart", skus: [], oldSku: nil, newSku: nil, reason: "добавить подборку", requiresConfirmation: false, metadata: nil))

        XCTAssertEqual(appState.cart.items.map(\.sku), ["SKU-1"])
        XCTAssertEqual(appState.activeSelection.skus, ["SKU-1"])
        XCTAssertEqual(appState.advisorSelectionNotice, "Товары добавлены в корзину.")
    }

    @MainActor
    func testApplyAdvisorActionClearsCartWithoutClearingActiveSelection() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let selected = makeRecommendation("SKU-1", name: "SPF", category: "spf", step: "SPF")
        appState.activeSelection = activeSelectionResponse([selected])
        appState.cart = CartResponse(items: [CartItem(sku: selected.sku, product: selected.asProduct, quantity: 1)], totalItems: 1, subtotal: selected.priceValue, currency: "RUB", checkoutMode: "development_handoff")

        await appState.applyAdvisorAction(AdvisorAction(type: "clear_cart", skus: [], oldSku: nil, newSku: nil, reason: "очистить корзину", requiresConfirmation: false, metadata: nil))

        XCTAssertTrue(appState.cart.items.isEmpty)
        XCTAssertEqual(appState.activeSelection.skus, ["SKU-1"])
        XCTAssertEqual(appState.advisorSelectionNotice, "Корзина очищена")
    }

    @MainActor
    func testAdvisorActionAddsCurrentRoutineToShelfWantedNotCart() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        let cleanser = makeRecommendation("SKU-CL", name: "Cleanser", category: "cleanser", step: "очищение")
        appState.activeSelection = activeSelectionResponse([spf, cleanser])
        appState.shelfItems = []

        let result = await appState.applyAdvisorAction(AdvisorAction(type: "add_current_routine_to_shelf", skus: [], oldSku: nil, newSku: nil, reason: "добавить в полку", requiresConfirmation: false, metadata: nil))

        XCTAssertEqual(result, .success("2 товара добавлены в «Хочу попробовать»."))
        XCTAssertEqual(Set(appState.shelfItems.map(\.sku)), ["SKU-SPF", "SKU-CL"])
        XCTAssertTrue(appState.shelfItems.allSatisfy { $0.status == .wanted })
        XCTAssertTrue(appState.cart.items.isEmpty)
    }

    @MainActor
    func testAdvisorActionAddsCurrentRoutineToCartNotShelf() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.activeSelection = activeSelectionResponse([spf])
        appState.shelfItems = []

        let result = await appState.applyAdvisorAction(AdvisorAction(type: "add_current_routine_to_cart", skus: [], oldSku: nil, newSku: nil, reason: "добавить в корзину", requiresConfirmation: false, metadata: nil))

        XCTAssertEqual(result, .success("Товары добавлены в корзину."))
        XCTAssertEqual(appState.cart.items.map(\.sku), ["SKU-SPF"])
        XCTAssertTrue(appState.shelfItems.isEmpty)
    }

    @MainActor
    func testAdvisorPhraseAddToShelfRoutesToShelfNotCart() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.activeSelection = activeSelectionResponse([spf])
        appState.shelfItems = []

        await appState.sendAdvisorMessage("добавь это все в мою полку")

        XCTAssertEqual(appState.shelfStatus(for: "SKU-SPF"), .wanted)
        XCTAssertTrue(appState.cart.items.isEmpty)
        XCTAssertTrue(appState.advisorMessages.last?.text.contains("полку") == true)
    }

    @MainActor
    func testAdvisorPhraseAddToCartRoutesToCartNotShelf() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.activeSelection = activeSelectionResponse([spf])
        appState.shelfItems = []

        await appState.sendAdvisorMessage("добавь это в корзину")

        XCTAssertEqual(appState.cart.items.map(\.sku), ["SKU-SPF"])
        XCTAssertTrue(appState.shelfItems.isEmpty)
        XCTAssertTrue(appState.advisorMessages.last?.text.contains("список к покупке") == true)
    }

    @MainActor
    func testSavedRoutineUsesMergedSelection() async {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.usesLocalFallback = true
        let existing = makeRecommendation("SKU-1", name: "Cleanser", category: "cleanser", step: "очищение")
        let incoming = makeRecommendation("SKU-2", name: "SPF", category: "spf", step: "SPF")
        let current = RecommendationsResponse(hero: existing, routine: [existing], products: [existing], explanation: "Текущая подборка", disclaimer: "Косметический подбор", generatedAt: Date())
        let merged = AppState.mergedRecommendations(existing: current, incoming: [incoming]).response
        appState.recommendations = merged
        appState.activeSelection = activeSelectionResponse(merged.routine)

        await appState.saveCurrentRoutine()

        XCTAssertEqual(appState.savedRoutineSkus, ["SKU-1", "SKU-2"])
    }

    @MainActor
    func testBeautyScanWarningStateStillAllowsCapture() {
        let viewModel = BeautyScanViewModel()
        let warningState = BeautyScanFaceState(
            faceRect: CGRect(x: 0.18, y: 0.26, width: 0.38, height: 0.38),
            confidence: 0.8,
            guidance: "Лицо почти в кадре",
            detail: "Можно зафиксировать, но лучше чуть ближе.",
            level: .adjust,
            quality: 0.66
        )

        viewModel.update(faceState: warningState)

        XCTAssertTrue(viewModel.canCapture)
    }

    @MainActor
    func testBeautyScanSearchingStateBlocksCapture() {
        let viewModel = BeautyScanViewModel()

        viewModel.update(faceState: .searching)

        XCTAssertFalse(viewModel.canCapture)
    }

    @MainActor
    func testBeautyScanCaptureStateBlocksRepeatCapture() {
        let viewModel = BeautyScanViewModel()
        let readyState = BeautyScanFaceState(
            faceRect: CGRect(x: 0.30, y: 0.26, width: 0.40, height: 0.40),
            confidence: 0.95,
            guidance: "Отлично, можно зафиксировать",
            detail: "Контекст подходит для косметического подбора.",
            level: .aligned,
            quality: 0.92
        )

        viewModel.update(faceState: readyState)
        viewModel.startCapture()

        XCTAssertFalse(viewModel.canCapture)
    }

    @MainActor
    func testOwnedRolePreventsDuplicateRoutineRoleByDefault() {
        let appState = pilotAppState()
        let cream = makeRecommendation("SKU-CREAM", name: "Comfort Cream", category: "moisturizer", step: "крем", priceValue: 1500)
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF", priceValue: 1200)
        appState.recommendations = RecommendationsResponse(hero: spf, routine: [cream, spf], products: [cream, spf], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.selectScenario(.morning)
        appState.updateOwnedRoles([.moisturizer], source: "test")

        appState.generateRoutineVariantsFromCurrentRecommendations()

        let original = tryUnwrap(appState.routineVariants.first { $0.type == .original })
        XCTAssertFalse(original.products.contains { RoutineRole.from(product: $0) == .moisturizer })
        XCTAssertTrue(original.whatChanged.contains { $0.contains("Крем") || $0.contains("увлажнение") })
        XCTAssertEqual(appState.activeSelection.skus, [])
    }

    @MainActor
    func testShelfOwnedStatusAffectsFutureVariantGeneration() {
        let appState = pilotAppState()
        let cream = makeRecommendation("SKU-CREAM", name: "Comfort Cream", category: "moisturizer", step: "крем")
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(hero: cream, routine: [cream, spf], products: [cream, spf], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())

        appState.markProductOwned(cream, source: "test")
        appState.generateRoutineVariantsFromCurrentRecommendations()

        XCTAssertEqual(appState.shelfStatus(for: cream.sku), .owned)
        let original = tryUnwrap(appState.routineVariants.first { $0.type == .original })
        XCTAssertFalse(original.products.map(\.sku).contains(cream.sku))
    }

    @MainActor
    func testChangingShelfOwnedStatusRestoresRoleEligibility() {
        let appState = pilotAppState()
        let cream = makeRecommendation("SKU-CREAM", name: "Comfort Cream", category: "moisturizer", step: "крем")
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(hero: cream, routine: [cream, spf], products: [cream, spf], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())

        appState.markProductOwned(cream, source: "test")
        let ownedItem = tryUnwrap(appState.shelfItems.first { $0.sku == cream.sku })
        appState.changeShelfStatus(ownedItem, status: .wanted)
        appState.generateRoutineVariantsFromCurrentRecommendations()

        XCTAssertFalse(appState.ownedRoles.contains(.moisturizer))
        XCTAssertEqual(appState.shelfStatus(for: cream.sku), .wanted)
        let original = tryUnwrap(appState.routineVariants.first { $0.type == .original })
        XCTAssertTrue(original.products.map(\.sku).contains(cream.sku))
    }

    @MainActor
    func testDidNotFitReasonIsStoredAndSkuIsAvoided() {
        let appState = pilotAppState()
        let serum = makeRecommendation("SKU-SERUM", name: "Glow Serum", category: "serum", step: "сыворотка")
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.recommendations = RecommendationsResponse(hero: serum, routine: [serum, spf], products: [serum, spf], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())

        appState.markProductDidNotFit(serum, reason: .fragrance, source: "test")
        appState.generateRoutineVariantsFromCurrentRecommendations()

        let shelfItem = tryUnwrap(appState.shelfItems.first { $0.sku == serum.sku })
        XCTAssertEqual(shelfItem.status, .didNotFit)
        XCTAssertEqual(shelfItem.issueReason, .fragrance)
        XCTAssertFalse(appState.routineVariants.flatMap(\.products).map(\.sku).contains(serum.sku))
    }

    @MainActor
    func testCheaperMinimalPremiumVariantsAndComparisonAreMeaningful() {
        let appState = pilotAppState()
        let budgetSpf = makeRecommendation("SKU-SPF-B", name: "Budget SPF", category: "spf", step: "SPF", priceSegment: "budget", priceValue: 700)
        let premiumSpf = makeRecommendation("SKU-SPF-P", name: "Premium SPF", category: "spf", step: "SPF", priceSegment: "premium", priceValue: 2200)
        let cleanser = makeRecommendation("SKU-CL", name: "Cleanser", category: "cleanser", step: "очищение", priceSegment: "mid", priceValue: 1100)
        let serum = makeRecommendation("SKU-SE", name: "Serum", category: "serum", step: "сыворотка", priceSegment: "premium", priceValue: 1800)
        appState.recommendations = RecommendationsResponse(hero: premiumSpf, routine: [premiumSpf, cleanser, serum], products: [budgetSpf, premiumSpf, cleanser, serum], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.updateOwnedRoles([.moisturizer], source: "test")

        let original = tryUnwrap(appState.makeOriginalRoutine())
        let cheaper = tryUnwrap(appState.makeCheaperRoutine())
        let minimal = tryUnwrap(appState.makeMinimalRoutine())
        let premium = tryUnwrap(appState.makePremiumRoutine())
        let comparison = appState.compareRoutineVariants(.originalVsCheaper, left: original, right: cheaper)

        XCTAssertLessThanOrEqual(cheaper.totalPrice, original.totalPrice)
        XCTAssertFalse(cheaper.tradeoffs.isEmpty)
        XCTAssertLessThan(minimal.productCount, original.productCount)
        XCTAssertFalse(premium.products.contains { RoutineRole.from(product: $0) == .moisturizer })
        XCTAssertFalse(premium.tradeoffs.isEmpty)
        XCTAssertNotEqual(comparison.priceDelta, 0)
        XCTAssertNotEqual(comparison.productCountDelta, Int.max)
        XCTAssertFalse(comparison.keyChanges.isEmpty)
        XCTAssertFalse(comparison.leftVariant.benefits.isEmpty)
        XCTAssertFalse(comparison.rightVariant.tradeoffs.isEmpty)
    }

    @MainActor
    func testPurchaseBlockersDriveVariantsShelfAndIntentProfile() {
        let appState = pilotAppState()
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF", priceValue: 1200)
        let cleanser = makeRecommendation("SKU-CL", name: "Cleanser", category: "cleanser", step: "очищение", priceValue: 900)
        let serum = makeRecommendation("SKU-SE", name: "Serum", category: "serum", step: "сыворотка", priceValue: 1800)
        appState.recommendations = RecommendationsResponse(hero: spf, routine: [spf, cleanser, serum], products: [spf, cleanser, serum], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())
        appState.selectScenario(.morning)
        appState.productOpened(spf)

        appState.recordPurchaseIntentClicked(context: "test")
        appState.selectPurchaseBlocker(.tooExpensive)
        XCTAssertEqual(appState.selectedRoutineVariant?.type, .cheaper)
        appState.selectPurchaseBlocker(.tooManyProducts)
        XCTAssertEqual(appState.selectedRoutineVariant?.type, .minimal)
        appState.selectPurchaseBlocker(.buyLater)
        XCTAssertTrue(appState.shelfItems.contains { $0.status == .buyLater })

        let profile = tryUnwrap(appState.latestIntentProfiles.first)
        XCTAssertTrue([PurchaseIntentLevel.high, .veryHigh].contains(profile.intentLevel))
        XCTAssertEqual(profile.scenario, .morning)
        XCTAssertTrue(profile.purchaseIntentClicked)
        XCTAssertFalse(profile.businessSummary.isEmpty)
    }

    @MainActor
    func testVariantSelectionDoesNotAutoSaveOrSelectUntilExplicitSave() async {
        let appState = pilotAppState()
        appState.usesLocalFallback = true
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        let cleanser = makeRecommendation("SKU-CL", name: "Cleanser", category: "cleanser", step: "очищение")
        appState.recommendations = RecommendationsResponse(hero: spf, routine: [spf, cleanser], products: [spf, cleanser], explanation: "Baseline", disclaimer: "Косметический подбор", generatedAt: Date())
        let minimal = tryUnwrap(appState.makeMinimalRoutine())

        appState.selectRoutineVariant(minimal)

        XCTAssertEqual(appState.selectedRoutineVariant?.id, minimal.id)
        XCTAssertEqual(appState.activeSelection.skus, [])
        XCTAssertEqual(appState.savedRoutineSkus, [])

        await appState.saveSelectedRoutineVariant()

        XCTAssertEqual(appState.savedRoutineSkus, minimal.products.map(\.sku))
    }

    @MainActor
    func testLogoutClearsShelfOwnedRolesAndIntentProfiles() {
        let appState = pilotAppState()
        let spf = makeRecommendation("SKU-SPF", name: "Daily SPF", category: "spf", step: "SPF")
        appState.account = Account(accountId: "account-a", name: "A", email: "a@example.com", createdAt: Date())
        appState.updateOwnedRoles([.spf], source: "test")
        appState.markProductWanted(spf, source: "test")
        appState.recordPurchaseIntentClicked(context: "test")
        appState.selectPurchaseBlocker(.nothingBlocking)

        appState.logout()

        XCTAssertTrue(appState.ownedRoles.isEmpty)
        XCTAssertTrue(appState.shelfItems.isEmpty)
        XCTAssertTrue(appState.latestIntentProfiles.isEmpty)
        XCTAssertTrue(appState.routineVariants.isEmpty)
    }

    private func makeRecommendation(
        _ sku: String,
        name: String,
        category: String,
        step: String,
        reason: String = "подходит к текущей подборке",
        matchScore: Int = 88,
        priceSegment: String = "mid",
        priceValue: Int = 1200
    ) -> RecommendationProduct {
        RecommendationProduct(
            sku: sku,
            sourceSku: sku,
            catalogNumber: nil,
            brand: "Luma",
            name: name,
            variant: nil,
            displayName: "Luma \(name)",
            category: category,
            domain: "skincare",
            priceSegment: priceSegment,
            priceValue: priceValue,
            currency: "RUB",
            imageUrl: nil,
            gallery: [],
            availability: true,
            inventoryStatus: "in_stock",
            skinTypes: [],
            concerns: [],
            tags: [],
            ingredients: [],
            ingredientHighlights: [],
            exclusions: [],
            finishes: [],
            coverageLevels: [],
            colorFamilies: [],
            texture: nil,
            rating: nil,
            reviewCount: nil,
            warnings: [],
            source: "test",
            assetSource: nil,
            cardImageUrl: nil,
            productType: category,
            categoryGroup: "skincare",
            updatedAt: nil,
            matchScore: matchScore,
            reason: reason,
            routineStep: step,
            alternatives: []
        )
    }

    @MainActor
    private func pilotAppState() -> AppState {
        let appState = AppState(environment: AppEnvironment(baseURL: URL(string: "http://127.0.0.1:8010")!, runtime: .development, isDebug: true))
        appState.ownedRoles = []
        appState.shelfItems = []
        appState.savedProducts = []
        appState.savedRoutineSkus = []
        appState.routineVariants = []
        appState.selectedRoutineVariant = nil
        appState.activeComparison = nil
        appState.selectedPurchaseBlocker = nil
        appState.latestIntentProfiles = []
        appState.productOpenedSkus = []
        appState.replacedProductSkus = []
        appState.purchaseIntentClickedThisSession = false
        appState.comparisonOpenedThisSession = false
        appState.savedRoutineThisSession = false
        appState.beautyID = BeautyID(skinType: "combination", concerns: ["comfort"], sensitivity: "medium", fragranceSensitivity: "avoid", preferredFinish: ["natural"], makeupPreferences: [], budget: "mid", ingredientExclusions: [], routineComplexity: "balanced", styleTags: [], consent: true, updatedAt: Date())
        return appState
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Expected non-nil value")
        }
        return value
    }

    private func activeSelectionResponse(_ products: [RecommendationProduct]) -> ActiveSelectionResponse {
        let items = products.map {
            ActiveSelectionItem(
                sku: $0.sku,
                product: $0.asProduct,
                source: "manual",
                routineStep: $0.routineStep,
                reason: $0.reason,
                matchScore: $0.matchScore,
                addedAt: Date(),
                updatedAt: Date(),
                locked: false,
                metadata: nil
            )
        }
        return ActiveSelectionResponse(
            items: items,
            skus: items.map(\.sku),
            count: items.count,
            totalPrice: items.reduce(0) { $0 + $1.product.priceValue },
            currency: "RUB",
            averageMatch: nil,
            updatedAt: Date(),
            sourceSummary: ["manual": items.count],
            addedCount: nil,
            alreadyInSelectionCount: nil
        )
    }
}
