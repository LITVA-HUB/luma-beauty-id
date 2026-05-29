import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct
    @State private var showingWhy = false
    @State private var showingIssueReasons = false
    @State private var showingReplacementReasons = false

    private var cartQuantity: Int { appState.cartQuantity(for: product.sku) }
    private var shelfStatus: ShelfStatus? { appState.shelfStatus(for: product.sku) }

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
                            Text("Отзывы каталога не подключены")
                                .font(BeautyFont.caption)
                                .foregroundStyle(BeautyColor.taupe)
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
                    shelfActionsSection

                    VStack(spacing: BeautySpacing.sm) {
                        PrimaryButton(title: primaryButtonTitle, systemImage: primaryButtonIcon) {
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
        .confirmationDialog("Почему не подошло?", isPresented: $showingIssueReasons, titleVisibility: .visible) {
            ForEach(ShelfIssueReason.allCases) { reason in
                Button(reason.displayTitle) { appState.markProductDidNotFit(product, reason: reason) }
            }
        }
        .confirmationDialog("Какую замену искать?", isPresented: $showingReplacementReasons, titleVisibility: .visible) {
            ForEach(ReplacementReason.allCases) { reason in
                Button(reason.displayTitle) { appState.markProductNeedsReplacement(product, reason: reason) }
            }
        }
    }

    private var primaryButtonTitle: String {
        if product.isUnavailable { return "Сейчас недоступно" }
        if cartQuantity > 1 { return "В корзине \(cartQuantity)" }
        if cartQuantity == 1 { return "Добавлено" }
        return "Добавить в корзину"
    }

    private var primaryButtonIcon: String {
        if product.isUnavailable { return "exclamationmark.circle" }
        return cartQuantity > 0 ? "checkmark" : "bag"
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

    private var shelfActionsSection: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(
                title: "Моя полка",
                subtitle: shelfStatus.map { "Текущий статус: \($0.displayTitle)" } ?? "Отметьте сигнал, чтобы следующие подборки стали точнее."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                shelfButton("Уже есть", icon: "checkmark.circle") { appState.markProductOwned(product) }
                shelfButton("Хочу", icon: "sparkles") { appState.markProductWanted(product) }
                shelfButton("Куплю позже", icon: "clock") { appState.markProductBuyLater(product) }
                shelfButton("Не подошло", icon: "hand.thumbsdown") { showingIssueReasons = true }
                shelfButton("Закончилось", icon: "drop.degreesign") { appState.markProductEmpty(product) }
                shelfButton("Хочу замену", icon: "arrow.triangle.2.circlepath") { showingReplacementReasons = true }
            }
        }
        .beautyCard()
    }

    private func shelfButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(BeautyColor.milk, in: Capsule())
                .overlay(Capsule().stroke(BeautyColor.line.opacity(0.68), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
