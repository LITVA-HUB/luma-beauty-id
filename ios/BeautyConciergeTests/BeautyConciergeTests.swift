import XCTest
@testable import BeautyConcierge

final class BeautyConciergeTests: XCTestCase {
    func testCurrencyFormatting() {
        XCTAssertEqual(3125.rub, "3 125 ₽")
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
}
