import SwiftUI

struct ProductVisual: View {
    let sku: String
    var compact = false

    private var seed: Int { sku.unicodeScalars.map { Int($0.value) }.reduce(0, +) }
    private var accent: Color {
        switch seed % 4 {
        case 0: return BeautyColor.limeSoft
        case 1: return BeautyColor.blush
        case 2: return BeautyColor.champagne
        default: return BeautyColor.milk
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 18 : 26, style: .continuous)
                .fill(LinearGradient(colors: [BeautyColor.milk, accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "photo")
                .font(.system(size: compact ? 22 : 34, weight: .semibold))
                .foregroundStyle(BeautyColor.taupe)
            Text("Фото")
                .font(BeautyFont.caption2)
                .foregroundStyle(BeautyColor.taupe)
                .offset(y: compact ? 24 : 36)
        }
        .accessibilityHidden(true)
    }
}

struct ProductCard: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct
    var showsReason = true
    private var cartQuantity: Int { appState.cartQuantity(for: product.sku) }
    private var isInCart: Bool { cartQuantity > 0 }
    private var role: RoutineRole { RoutineRole.from(product: product) }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            ZStack(alignment: .topTrailing) {
                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku)
                }
                .frame(height: 168)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                if product.isUnavailable {
                    Text("Нет в наличии")
                        .font(BeautyFont.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BeautyColor.milk, in: Capsule())
                        .padding(10)
                } else {
                    MatchBadge(score: product.matchScore)
                        .padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(product.brand.uppercased())
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(1)
                Text(product.name)
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                HStack(spacing: 8) {
                    Text(product.priceValue.rub).font(.system(size: 16, weight: .bold))
                    RoutineStepPill(title: role.displayTitle)
                }
                if showsReason {
                    Text("Роль: \(role.displayTitle.lowercased())")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Button {
                    Task { await appState.addProductToActiveSelection(product, source: "product_card") }
                } label: {
                    Text("Набор")
                        .font(BeautyFont.caption2.weight(.semibold))
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(BeautyColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await appState.addToCart(product) }
                } label: {
                    Text(cartButtonTitle)
                        .font(BeautyFont.caption2.weight(.semibold))
                        .foregroundStyle(product.isUnavailable ? BeautyColor.ink : BeautyColor.limeInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(product.isUnavailable ? BeautyColor.line : (isInCart ? BeautyColor.limeSoft.opacity(0.82) : BeautyColor.lime), in: Capsule())
                        .overlay(Capsule().stroke(isInCart ? BeautyColor.lime.opacity(0.55) : .clear, lineWidth: 1))
                }
                .disabled(product.isUnavailable)
                .buttonStyle(.plain)
                .accessibilityLabel(cartAccessibilityLabel)

                Button {
                    appState.markProductWanted(product, source: "product_card")
                } label: {
                    Text("Хочу")
                        .font(BeautyFont.caption2.weight(.semibold))
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 48, height: 36)
                        .background(BeautyColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.brand) \(product.name), \(product.priceValue.rub), совпадение \(product.matchScore) процентов")
    }

    private var cartButtonTitle: String {
        if product.isUnavailable { return "Нет в наличии" }
        if cartQuantity > 1 { return "В корзине \(cartQuantity)" }
        if isInCart { return "Добавлено" }
        return "Купить"
    }

    private var cartButtonIcon: String {
        if product.isUnavailable { return "exclamationmark.circle" }
        return isInCart ? "checkmark" : "plus"
    }

    private var cartAccessibilityLabel: String {
        if product.isUnavailable { return "Товар недоступен" }
        if isInCart { return "\(product.name) в корзине, количество \(cartQuantity). Добавить ещё один" }
        return "Добавить \(product.name) в корзину"
    }
}

struct RoutinePlanCard: View {
    let title: String
    var subtitle: String? = nil
    let products: [RecommendationProduct]
    var primaryTitle: String = "Сохранить подборку"
    var secondaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    private var shownProducts: [RecommendationProduct] { Array(products.prefix(4)) }
    private var total: Int { shownProducts.reduce(0) { $0 + $1.priceValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title, subtitle: subtitle)
                Spacer()
                if !shownProducts.isEmpty {
                    Text(total.rub)
                        .font(BeautyFont.headline)
                        .foregroundStyle(BeautyColor.ink)
                }
            }

            if shownProducts.isEmpty {
                Text("Текущая подборка пока пуста. Добавьте товары из советника или карточек рекомендаций.")
                    .font(BeautyFont.callout)
                    .foregroundStyle(BeautyColor.taupe)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BeautySpacing.md)
                    .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
            } else {
                VStack(spacing: BeautySpacing.sm) {
                    ForEach(Array(shownProducts.enumerated()), id: \.element.id) { index, product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            RoutinePlanRow(index: index + 1, product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: BeautySpacing.sm) {
                    if let primaryAction {
                        Button(primaryTitle) { primaryAction() }
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.limeInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(BeautyColor.lime, in: Capsule())
                    }
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle) { secondaryAction() }
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(BeautyColor.milk, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.75), lineWidth: 1))
                    }
                }
            }
        }
        .beautyCard()
    }
}

private struct RoutinePlanRow: View {
    @EnvironmentObject private var appState: AppState
    let index: Int
    let product: RecommendationProduct

    var body: some View {
        HStack(spacing: BeautySpacing.md) {
            Text("\(index)")
                .font(BeautyFont.caption.weight(.bold))
                .foregroundStyle(BeautyColor.limeInk)
                .frame(width: 28, height: 28)
                .background(BeautyColor.limeSoft, in: Circle())

            CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                ProductVisual(sku: product.sku, compact: true)
            }
            .frame(width: 60, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.routineStep.beautyLabel)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .textCase(.uppercase)
                Text(product.name)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(2)
                Text("Роль: \(RoutineRole.from(product: product).displayTitle.lowercased())")
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(product.priceValue.rub)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                Text("\(product.matchScore)%")
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .padding(10)
        .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.42), lineWidth: 1))
    }
}

struct ProductMiniRow: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct

    var body: some View {
        HStack(spacing: BeautySpacing.md) {
            CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                ProductVisual(sku: product.sku, compact: true)
            }
                .frame(width: 82, height: 92)
                .overlay(alignment: .bottom) {
                    if product.isUnavailable { Text("Нет") .font(BeautyFont.caption2).padding(4).background(BeautyColor.milk, in: Capsule()) }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(product.routineStep).font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
                Text(product.brand).font(BeautyFont.caption.weight(.semibold)).foregroundStyle(BeautyColor.ink)
                Text(product.name).font(BeautyFont.callout).lineLimit(2)
                Text(product.priceValue.rub).font(BeautyFont.caption.weight(.bold))
            }
            Spacer()
            MatchBadge(score: product.matchScore)
        }
        .padding(12)
        .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
    }
}

struct HorizontalProductRail: View {
    let title: String
    let products: [RecommendationProduct]

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    ForEach(products) { product in
                        NavigationLink {
                            ProductDetailView(product: product)
                        } label: {
                            ProductCard(product: product, showsReason: false)
                                .frame(width: 210)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BeautySpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
