import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: String? = nil
    @State private var showingComparison = false
    @State private var showingPurchaseBlockers = false
    @State private var blockerNote: String?

    private let columns = [GridItem(.adaptive(minimum: 164), spacing: BeautySpacing.md)]
    private var currentVariant: RoutineVariant? { appState.currentRoutineVariant }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    header
                    filterRail
                    if appState.isBusy {
                        LoadingStateView()
                    }
                    if let hero = appState.recommendations.hero {
                        heroCard(hero)
                    }
                    personalRoutineSection
                    routineSet
                    if let blockerNote {
                        StatusBanner(message: blockerNote, systemImage: "info.circle")
                    }
                    productGrid
                    Text(appState.recommendations.disclaimer)
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.warmGray)
                        .padding(.bottom, BeautySpacing.lg)
                }
                .padding(BeautySpacing.md)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Подбор")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if appState.recommendations.products.isEmpty {
                await appState.loadRecommendations(focus: filter, silent: true)
            }
            appState.generateRoutineVariantsFromCurrentRecommendations()
        }
        .sheet(isPresented: $showingComparison) {
            RoutineComparisonSheet(comparison: appState.activeComparison)
        }
        .sheet(isPresented: $showingPurchaseBlockers) {
            PurchaseBlockerSheet { blocker in
                showingPurchaseBlockers = false
                handleBlocker(blocker)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            SectionHeader(title: headerTitle, subtitle: appState.recommendations.explanation)
            if appState.usesLocalFallback {
                ErrorBanner(message: "Не удалось обновить подборку. Показана сохранённая безопасная подборка.")
            }
        }
    }

    private var headerTitle: String {
        if let scenario = appState.selectedScenario {
            return scenario == .underBudget ? "Набор в рамках бюджета" : "Ваш \(scenario.displayTitle.lowercased())"
        }
        return "Персональные рекомендации"
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeautySpacing.sm) {
                ForEach(["сияние", "дешевле", "без отдушек", "SPF", "K-beauty", "матовый финиш", "вечерний образ"], id: \.self) { item in
                    BeautyChip(title: item, isSelected: filter == item) {
                        filter = item
                        Task {
                            await appState.loadRecommendations(focus: item)
                            appState.generateRoutineVariantsFromCurrentRecommendations()
                        }
                    }
                }
            }
            .padding(.horizontal, BeautySpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var personalRoutineSection: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            if let variant = currentVariant {
                RoutineVariantSummaryCard(
                    variant: variant,
                    ownedRoles: appState.ownedRoles,
                    onCheaper: { selectVariant(.cheaper) },
                    onMinimal: { selectVariant(.minimal) },
                    onPremium: { selectVariant(.premium) },
                    onCompare: { openComparison() },
                    onSave: {
                        appState.selectRoutineVariant(variant)
                        Task { await appState.saveSelectedRoutineVariant() }
                    },
                    onPurchaseIntent: {
                        appState.recordPurchaseIntentClicked(context: "recommendations")
                        showingPurchaseBlockers = true
                    }
                )

                ForEach(variant.whatChanged.filter { $0.contains("не добавили") || $0.contains("пропустили") }, id: \.self) { change in
                    StatusBanner(message: change, systemImage: "info.circle")
                }

                VStack(spacing: BeautySpacing.sm) {
                    ForEach(variant.products) { product in
                        NavigationLink { ProductDetailView(product: product) } label: {
                            RoutineVariantProductRow(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                EmptyStateView(title: "Набор пока не собран", subtitle: "Выберите сценарий на главной или обновите Beauty ID.")
            }
        }
    }

    private var routineSet: some View {
        RoutinePlanCard(
            title: "Текущий набор",
            subtitle: "Только товары, которые вы или советник явно добавили.",
            products: Array(appState.activeSelection.recommendations.prefix(4)),
            primaryTitle: "Сохранить набор",
            secondaryTitle: "Сделать дешевле",
            primaryAction: { Task { await appState.saveCurrentRoutine() } },
            secondaryAction: {
                appState.selectedTab = .advisor
                Task { await appState.sendAdvisorMessage("Сделай этот набор дешевле") }
            }
        )
    }

    private var productGrid: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Альтернативы для замены", subtitle: "Показываем только товары demo-каталога")
            if appState.recommendations.products.isEmpty {
                EmptyStateView(title: "Нет уверенных совпадений", subtitle: "Обновите Beauty ID или уберите часть исключённых ингредиентов.")
            } else {
                LazyVGrid(columns: columns, spacing: BeautySpacing.md) {
                    ForEach(appState.recommendations.products.filter { candidate in
                        !(currentVariant?.products.map(\.sku).contains(candidate.sku) ?? false)
                    }) { product in
                        NavigationLink { ProductDetailView(product: product) } label: {
                            ProductCard(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func selectVariant(_ type: RoutineVariantType) {
        appState.generateRoutineVariantsFromCurrentRecommendations()
        if let variant = appState.routineVariants.first(where: { $0.type == type }) {
            appState.selectRoutineVariant(variant)
        }
    }

    private func openComparison() {
        appState.generateRoutineVariantsFromCurrentRecommendations()
        let left = appState.routineVariants.first(where: { $0.type == .minimal }) ?? appState.routineVariants.first(where: { $0.type == .original })
        let right = appState.routineVariants.first(where: { $0.type == .balanced }) ?? appState.routineVariants.first(where: { $0.type == .cheaper })
        if let left, let right {
            _ = appState.compareRoutineVariants(left.type == .minimal ? .minimalVsBalanced : .originalVsCheaper, left: left, right: right)
            showingComparison = true
        }
    }

    private func handleBlocker(_ blocker: PurchaseBlocker) {
        appState.selectPurchaseBlocker(blocker)
        switch blocker {
        case .tooExpensive:
            blockerNote = "Показала более дешёвый вариант без скидок и промо — только цены demo-каталога."
        case .tooManyProducts:
            blockerNote = "Показала минимум: меньше шагов, но меньше дополнительных эффектов."
        case .wantsToCompare:
            openComparison()
        case .wantsReviews:
            blockerNote = "Отзывы пока не подключены в demo-каталоге. Сигнал сохранён как причина сомнения."
        case .wantsToSeeInStore:
            blockerNote = "Наличие в магазине пока не подключено. Сигнал сохранён как причина сомнения."
        case .shadeConcern:
            blockerNote = "В demo-каталоге оттенок нужно проверить отдельно перед покупкой."
        case .notSure:
            blockerNote = "Проверьте роль продукта, оттенок и комфорт текстуры: это косметический подбор, не гарантия результата."
        case .wantsReplacement:
            blockerNote = "Отметила первый товар как «нужна замена» — будущие варианты будут учитывать этот сигнал."
        case .buyLater:
            blockerNote = "Товары варианта отмечены как «куплю позже» на вашей полке."
        case .nothingBlocking:
            blockerNote = "Сильное намерение купить сохранено в демо-профиле."
        }
    }
}

private struct RoutineVariantSummaryCard: View {
    let variant: RoutineVariant
    let ownedRoles: Set<RoutineRole>
    let onCheaper: () -> Void
    let onMinimal: () -> Void
    let onPremium: () -> Void
    let onCompare: () -> Void
    let onSave: () -> Void
    let onPurchaseIntent: () -> Void

    private var consideredText: String {
        var values: [String] = []
        if let scenario = variant.scenario { values.append(scenario.displayTitle.lowercased()) }
        if !ownedRoles.isEmpty { values.append("\(ownedRoles.map(\.displayTitle).sorted().joined(separator: ", ")) уже есть") }
        values.append("demo-каталог")
        return values.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack(alignment: .top, spacing: BeautySpacing.md) {
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text(variant.title)
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                    Text("\(variant.productCount.productWord) · \(variant.totalPrice.rub) · \(variant.type.displayTitle)")
                        .font(BeautyFont.callout.weight(.semibold))
                        .foregroundStyle(BeautyColor.taupe)
                }
                Spacer()
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 42, height: 42)
                    .background(BeautyColor.limeSoft, in: Circle())
            }

            Text("Учли: \(consideredText)")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
                .lineLimit(3)

            Text(variant.explanation)
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 8)], alignment: .leading, spacing: 8) {
                actionButton("Сделать дешевле", icon: "rublesign.circle", action: onCheaper)
                actionButton("Минимум", icon: "rectangle.compress.vertical", action: onMinimal)
                actionButton("Премиум", icon: "sparkles", action: onPremium)
                actionButton("Сравнить", icon: "rectangle.split.2x1", action: onCompare)
                actionButton("Сохранить", icon: "bookmark", action: onSave)
                actionButton("Я бы купила", icon: "handbag", action: onPurchaseIntent)
            }

            Text("Косметический подбор, не медицинская рекомендация. В demo-каталоге нет реальных отзывов, наличия, скидок или оплаты.")
                .font(BeautyFont.caption2)
                .foregroundStyle(BeautyColor.warmGray)
        }
        .beautyCard()
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 10)
                .background(BeautyColor.milk, in: Capsule())
                .overlay(Capsule().stroke(BeautyColor.line.opacity(0.68), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct RoutineVariantProductRow: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct

    private var role: RoutineRole { RoutineRole.from(product: product) }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            HStack(alignment: .center, spacing: BeautySpacing.md) {
                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku, compact: true)
                }
                .frame(width: 68, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.displayTitle)
                        .font(BeautyFont.caption2)
                        .foregroundStyle(BeautyColor.taupe)
                        .textCase(.uppercase)
                    Text("\(product.brand) \(product.name)")
                        .font(BeautyFont.callout.weight(.semibold))
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(2)
                    Text("Для текущего набора")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                Text(product.priceValue.rub)
                    .font(BeautyFont.caption.weight(.bold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                shelfButton("Уже есть") { appState.markProductOwned(product, source: "recommendation_card") }
                shelfButton("Хочу") { appState.markProductWanted(product, source: "recommendation_card") }
                shelfButton("Куплю позже") { appState.markProductBuyLater(product, source: "recommendation_card") }
                shelfButton("Не моё") { appState.markProductDidNotFit(product, reason: .notInterested, source: "recommendation_card") }
            }
        }
        .padding(12)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
    }

    private func shelfButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BeautyFont.caption2.weight(.semibold))
                .foregroundStyle(BeautyColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(BeautyColor.milk, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct RoutineComparisonSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let comparison: RoutineComparison?

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                        if let comparison {
                            SectionHeader(title: "Сравнение вариантов", subtitle: comparison.summary)
                            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                                RoutineVariantColumn(variant: comparison.leftVariant)
                                RoutineVariantColumn(variant: comparison.rightVariant)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                                Text("Что меняется")
                                    .font(BeautyFont.headline)
                                    .foregroundStyle(BeautyColor.ink)
                                Text("Цена: \(comparison.priceDelta >= 0 ? "+" : "")\(comparison.priceDelta.rub) · товаров: \(comparison.productCountDelta >= 0 ? "+" : "")\(comparison.productCountDelta)")
                                    .font(BeautyFont.callout)
                                    .foregroundStyle(BeautyColor.taupe)
                                ForEach(comparison.keyChanges, id: \.self) { change in
                                    Label(change, systemImage: "checkmark.circle")
                                        .font(BeautyFont.caption)
                                        .foregroundStyle(BeautyColor.ink)
                                }
                            }
                            .beautyCard()
                        } else {
                            EmptyStateView(title: "Сравнение пока не открыто", subtitle: "Сначала создайте варианты рутины.")
                        }
                    }
                    .padding(BeautySpacing.md)
                }
            }
            .navigationTitle("Сравнить")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

private struct RoutineVariantColumn: View {
    @EnvironmentObject private var appState: AppState
    let variant: RoutineVariant

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Text(variant.title)
                .font(BeautyFont.headline)
                .foregroundStyle(BeautyColor.ink)
            Text("\(variant.productCount.productWord) · \(variant.totalPrice.rub)")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
            Text("Плюсы")
                .font(BeautyFont.caption.weight(.bold))
            ForEach(variant.benefits.prefix(3), id: \.self) { Text($0).font(BeautyFont.caption2).foregroundStyle(BeautyColor.taupe) }
            Text("Компромисс")
                .font(BeautyFont.caption.weight(.bold))
            ForEach(variant.tradeoffs.prefix(3), id: \.self) { Text($0).font(BeautyFont.caption2).foregroundStyle(BeautyColor.taupe) }
            Button("Выбрать этот вариант") { appState.selectRoutineVariant(variant) }
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.limeInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(BeautyColor.lime, in: Capsule())
            Button("Сохранить") {
                appState.selectRoutineVariant(variant)
                Task { await appState.saveSelectedRoutineVariant() }
            }
            .font(BeautyFont.caption)
            .foregroundStyle(BeautyColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(BeautyColor.milk, in: Capsule())
            Button("Добавить в набор") {
                Task { await appState.addRoutineVariantToActiveSelection(variant) }
            }
            .font(BeautyFont.caption)
            .foregroundStyle(BeautyColor.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
    }
}

private struct PurchaseBlockerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PurchaseBlocker) -> Void

    private let blockers: [PurchaseBlocker] = [
        .tooExpensive, .wantsReviews, .notSure, .shadeConcern, .wantsToCompare,
        .wantsToSeeInStore, .tooManyProducts, .wantsReplacement, .buyLater, .nothingBlocking
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BeautySpacing.md) {
                        SectionHeader(title: "Что нужно, чтобы вы действительно купили этот набор?")
                        ForEach(blockers) { blocker in
                            Button {
                                onSelect(blocker)
                                dismiss()
                            } label: {
                                HStack(spacing: BeautySpacing.md) {
                                    Image(systemName: icon(for: blocker))
                                        .foregroundStyle(BeautyColor.limeInk)
                                        .frame(width: 34, height: 34)
                                        .background(BeautyColor.limeSoft, in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(blocker.displayTitle)
                                            .font(BeautyFont.callout.weight(.semibold))
                                            .foregroundStyle(BeautyColor.ink)
                                        if let subtitle = blocker.subtitle {
                                            Text(subtitle)
                                                .font(BeautyFont.caption)
                                                .foregroundStyle(BeautyColor.taupe)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(BeautySpacing.md)
                }
            }
            .navigationTitle("Покупка")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func icon(for blocker: PurchaseBlocker) -> String {
        switch blocker {
        case .tooExpensive: return "rublesign.circle"
        case .notSure: return "questionmark.circle"
        case .shadeConcern: return "eyedropper"
        case .wantsReviews: return "text.bubble"
        case .wantsToCompare: return "rectangle.split.2x1"
        case .wantsToSeeInStore: return "mappin.and.ellipse"
        case .tooManyProducts: return "rectangle.compress.vertical"
        case .wantsReplacement: return "arrow.triangle.2.circlepath"
        case .buyLater: return "clock"
        case .nothingBlocking: return "checkmark.seal"
        }
    }
}
