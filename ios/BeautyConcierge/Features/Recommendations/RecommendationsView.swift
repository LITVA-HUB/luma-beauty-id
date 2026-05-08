import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 164), spacing: BeautySpacing.md)]

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    header
                    filterRail
                    if appState.isBusy {
                        LoadingStateView()
                    }
                    if let hero = appState.recommendations.hero {
                        heroCard(hero)
                    }
                    routineSet
                    productGrid
                    Text(appState.recommendations.disclaimer)
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.warmGray)
                        .padding(.bottom, BeautySpacing.lg)
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle("Подбор")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if appState.recommendations.products.isEmpty {
                await appState.loadRecommendations(focus: filter, silent: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            SectionHeader(title: "Персональные рекомендации", subtitle: appState.recommendations.explanation)
            if appState.usesLocalFallback {
                ErrorBanner(message: "Не удалось обновить подборку. Показана сохранённая безопасная подборка.")
            }
        }
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeautySpacing.sm) {
                ForEach(["сияние", "дешевле", "без отдушек", "SPF", "K-beauty", "матовый финиш", "вечерний образ"], id: \.self) { item in
                    BeautyChip(title: item, isSelected: filter == item) {
                        filter = item
                        Task { await appState.loadRecommendations(focus: item) }
                    }
                }
            }
            .padding(.horizontal, BeautySpacing.md)
        }
        .padding(.horizontal, -BeautySpacing.md)
    }

    private func heroCard(_ product: RecommendationProduct) -> some View {
        NavigationLink { ProductDetailView(product: product) } label: {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                ZStack(alignment: .topTrailing) {
                    CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                        ProductVisual(sku: product.sku)
                    }
                    .frame(height: 230)
                    if product.isUnavailable {
                        Text("Нет в наличии")
                            .font(BeautyFont.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BeautyColor.milk, in: Capsule())
                            .padding(BeautySpacing.md)
                    } else {
                        MatchBadge(score: product.matchScore)
                            .padding(BeautySpacing.md)
                    }
                }
                VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                    Text("Главное совпадение")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .textCase(.uppercase)
                        .tracking(1.4)
                    Text("\(product.brand) \(product.name)")
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                    Text(product.reason)
                        .font(BeautyFont.body)
                        .foregroundStyle(BeautyColor.taupe)
                    HStack {
                        Text(product.priceValue.rub).font(BeautyFont.headline)
                        Spacer()
                        Label("Почему подходит", systemImage: "chevron.right")
                            .font(BeautyFont.caption)
                    }
                }
            }
            .beautyCard()
        }
        .buttonStyle(.plain)
    }

    private var routineSet: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                SectionHeader(title: "Набор рутины", subtitle: "Шаги по порядку для утра или быстрого макияжа")
                Spacer()
                Button("Сохранить") { Task { await appState.saveCurrentRoutine() } }
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(BeautyColor.limeSoft, in: Capsule())
            }
            ForEach(appState.recommendations.routine.prefix(7)) { product in
                NavigationLink { ProductDetailView(product: product) } label: { ProductMiniRow(product: product) }
                    .buttonStyle(.plain)
            }
        }
        .beautyCard()
    }

    private var productGrid: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Все варианты", subtitle: "Альтернативы остаются внутри текущего каталога")
            if appState.recommendations.products.isEmpty {
                EmptyStateView(title: "Нет уверенных совпадений", subtitle: "Обновите Beauty ID или уберите часть исключённых ингредиентов.")
            } else {
                LazyVGrid(columns: columns, spacing: BeautySpacing.md) {
                    ForEach(appState.recommendations.products) { product in
                        NavigationLink { ProductDetailView(product: product) } label: {
                            ProductCard(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
