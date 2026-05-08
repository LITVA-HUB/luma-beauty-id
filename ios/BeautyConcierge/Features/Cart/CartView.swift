import SwiftUI

struct CartView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(title: "Корзина", subtitle: cartSubtitle)

                    if appState.cart.items.isEmpty {
                        EmptyStateView(title: "Корзина пока пустая", subtitle: "Добавьте продукты из рекомендаций или попросите советника собрать рутину.", actionTitle: "Перейти к подбору") {
                            appState.selectedTab = .recommendations
                        }
                    } else {
                        VStack(spacing: BeautySpacing.md) {
                            ForEach(appState.cart.items) { item in
                                CartItemRow(item: item)
                            }
                        }
                        summaryCard
                    }

                    if let message = appState.checkoutMessage {
                        ErrorBanner(message: message)
                    }
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle("Корзина")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadCart(silent: true) }
    }

    private var cartSubtitle: String {
        "Сохраните подборку, чтобы вернуться к ней после перезапуска."
    }

    private var checkoutNote: String {
        "В бета-версии заказ и оплата не создаются."
    }

    private var checkoutButtonTitle: String {
        "Сохранить подборку"
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                Text("Итого")
                    .font(BeautyFont.headline)
                Spacer()
                Text(appState.cart.subtotal.rub)
                    .font(BeautyFont.title2)
            }
            Text(checkoutNote)
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
            PrimaryButton(title: checkoutButtonTitle, systemImage: "bookmark", isLoading: appState.isBusy) {
                Task { await appState.checkout() }
            }
        }
        .beautyCard()
    }
}

private struct CartItemRow: View {
    @EnvironmentObject private var appState: AppState
    let item: CartItem

    var body: some View {
        HStack(spacing: BeautySpacing.md) {
            CachedRemoteImage(url: appState.absoluteURL(for: item.product.preferredImagePath)) {
                ProductVisual(sku: item.sku, compact: true)
            }
                .frame(width: 82, height: 92)
                .overlay(alignment: .bottom) {
                    if item.product.isUnavailable { Text("Нет").font(BeautyFont.caption2).padding(4).background(BeautyColor.milk, in: Capsule()) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.brand.uppercased())
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                Text(item.product.name)
                    .font(BeautyFont.headline)
                    .lineLimit(2)
                Text(item.product.priceValue.rub)
                    .font(BeautyFont.caption.weight(.bold))
            }
            Spacer()
            VStack(spacing: BeautySpacing.sm) {
                Button { Task { await appState.updateCartItem(sku: item.sku, quantity: item.quantity + 1) } } label: {
                    Image(systemName: "plus").frame(width: 32, height: 32).background(BeautyColor.milk, in: Circle())
                }
                Text("\(item.quantity)").font(BeautyFont.callout.weight(.semibold))
                Button { Task { await appState.updateCartItem(sku: item.sku, quantity: item.quantity - 1) } } label: {
                    Image(systemName: "minus").frame(width: 32, height: 32).background(BeautyColor.milk, in: Circle())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
    }
}
