import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct
    @State private var showingWhy = false

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                        ProductVisual(sku: product.sku)
                    }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if product.isUnavailable {
                            Text("Нет в наличии")
                                .font(BeautyFont.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(BeautyColor.milk, in: Capsule())
                                .padding(BeautySpacing.md)
                        } else {
                            MatchBadge(score: product.matchScore).padding(BeautySpacing.md)
                        }
                    }

                    VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                        Text(product.brand.uppercased())
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.taupe)
                            .tracking(1.2)
                        Text(product.name)
                            .font(BeautyFont.title)
                            .foregroundStyle(BeautyColor.ink)
                        Text(product.priceValue.rub)
                            .font(BeautyFont.headline)
                        HStack(spacing: BeautySpacing.sm) {
                            RoutineStepPill(title: product.routineStep)
                            if !product.isLocalSeed, let rating = product.rating, let count = product.reviewCount {
                                Text("★ \(String(format: "%.1f", rating)) · \(count)")
                                    .font(BeautyFont.caption)
                                    .foregroundStyle(BeautyColor.taupe)
                            }
                        }
                    }
                    .beautyCard()

                    VStack(alignment: .leading, spacing: BeautySpacing.md) {
                        SectionHeader(title: "Почему это подходит")
                        Text(product.reason)
                            .font(BeautyFont.body)
                            .foregroundStyle(BeautyColor.ink)
                        Button("Открыть объяснение") { showingWhy = true }
                            .font(BeautyFont.callout.weight(.semibold))
                            .foregroundStyle(BeautyColor.ink)
                    }
                    .beautyCard()

                    detailSection(title: "Ключевые ингредиенты", items: product.ingredientHighlights.isEmpty ? product.ingredients.prefix(4).map { $0 } : product.ingredientHighlights)
                    if !product.warnings.isEmpty { detailSection(title: "На что обратить внимание", items: product.warnings) }
                    detailSection(title: "Текстура и финиш", items: textureItems)

                    VStack(spacing: BeautySpacing.sm) {
                        PrimaryButton(title: product.isUnavailable ? "Сейчас недоступно" : "Добавить в корзину", systemImage: product.isUnavailable ? "exclamationmark.circle" : "bag") {
                            Task { await appState.addToCart(product) }
                        }
                        .disabled(product.isUnavailable)
                        SecondaryButton(title: appState.savedProducts.contains(product.sku) ? "Сохранено" : "Сохранить продукт", systemImage: appState.savedProducts.contains(product.sku) ? "heart.fill" : "heart") {
                            appState.toggleSaveProduct(product)
                        }
                    }
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle(product.brand)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appState.productOpened(product) }
        .sheet(isPresented: $showingWhy) { whySheet }
    }

    private var textureItems: [String] {
        var values: [String] = []
        if let texture = product.texture { values.append(texture) }
        values.append(contentsOf: product.finishes)
        values.append(contentsOf: product.coverageLevels.map { "\($0) покрытие" })
        return values.isEmpty ? ["Гибкий шаг для рутины"] : values
    }

    private func detailSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item.replacingOccurrences(of: "_", with: " "))
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BeautyColor.milk, in: Capsule())
                }
            }
        }
        .beautyCard()
    }

    private var whySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(title: "Почему это подходит", subtitle: "Объяснение подбора, а не медицинское утверждение.")
                    Text(product.reason)
                        .font(BeautyFont.body)
                    Text("Шаг рутины")
                        .font(BeautyFont.headline)
                    Text(product.routineStep)
                        .font(BeautyFont.body)
                        .foregroundStyle(BeautyColor.taupe)
                    Text("Граница безопасности")
                        .font(BeautyFont.headline)
                    Text("Приложение не диагностирует состояние кожи и не обещает лечение. При сильном раздражении, боли или медицинских симптомах лучше обратиться к специалисту.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
                .padding(BeautySpacing.md)
            }
            .background(PremiumBackground())
            .navigationTitle("Подбор")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { showingWhy = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
