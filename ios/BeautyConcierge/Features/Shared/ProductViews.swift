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

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            ZStack(alignment: .topTrailing) {
                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku)
                }
                .frame(height: 176)
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
                    RoutineStepPill(title: product.routineStep)
                }
                if showsReason {
                    Text(product.reason)
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(3)
                }
            }
            HStack {
                Button {
                    Task { await appState.addToCart(product) }
                } label: {
                    Label(cartButtonTitle, systemImage: cartButtonIcon)
                        .font(BeautyFont.caption)
                        .foregroundStyle(product.isUnavailable ? BeautyColor.ink : BeautyColor.limeInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(product.isUnavailable ? BeautyColor.line : (isInCart ? BeautyColor.limeSoft : BeautyColor.lime), in: Capsule())
                        .overlay(Capsule().stroke(isInCart ? BeautyColor.lime.opacity(0.55) : .clear, lineWidth: 1))
                }
                .disabled(product.isUnavailable)
                .buttonStyle(.plain)
                .accessibilityLabel(cartAccessibilityLabel)

                Button {
                    appState.toggleSaveProduct(product)
                } label: {
                    Image(systemName: appState.savedProducts.contains(product.sku) ? "heart.fill" : "heart")
                        .foregroundStyle(BeautyColor.ink)
                        .frame(width: 36, height: 36)
                        .background(BeautyColor.milk, in: Circle())
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
        return "Добавить"
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
            }
            .padding(.horizontal, -BeautySpacing.md)
        }
    }
}
