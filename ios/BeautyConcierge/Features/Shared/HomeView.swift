import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    private var activeRoutine: [RecommendationProduct] {
        appState.activeSelection.recommendations
    }

    private var alternativeProducts: [RecommendationProduct] {
        let activeSkus = Set(activeRoutine.map(\.sku))
        return Array((appState.recommendations.routine + appState.recommendations.products).filter { !activeSkus.contains($0.sku) }.prefix(8))
    }

    private var hasCurrentSet: Bool { !activeRoutine.isEmpty }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    HomeHeroCard(isFallback: appState.usesLocalFallback)

                    if hasCurrentSet {
                        CurrentRoutineSummaryCard(
                            products: activeRoutine,
                            savedRoutineSkus: appState.savedRoutineSkus,
                            selectionNotice: appState.advisorSelectionNotice,
                            onOpen: { appState.selectedTab = .recommendations },
                            onAdvisor: { appState.selectedTab = .advisor },
                            onSave: { Task { await appState.saveCurrentRoutine() } }
                        )
                    }

                    scenarioSection

                    BeautyIDSummaryCard(
                        beautyID: appState.beautyID,
                        onUpdate: { appState.selectedTab = .profile }
                    )

                    NavigationLink {
                        MyShelfView()
                    } label: {
                        MyShelfEntryCard(items: appState.shelfItems, ownedRoles: appState.ownedRoles)
                    }
                    .buttonStyle(.plain)

                    if !hasCurrentSet {
                        CurrentRoutineSummaryCard(
                            products: activeRoutine,
                            savedRoutineSkus: appState.savedRoutineSkus,
                            selectionNotice: appState.advisorSelectionNotice,
                            onOpen: { appState.selectedTab = .recommendations },
                            onAdvisor: { appState.selectedTab = .advisor },
                            onSave: { Task { await appState.saveCurrentRoutine() } }
                        )
                    }

                    if hasCurrentSet {
                        QuickActionsSection(
                            cartCount: appState.cart.totalItems,
                            onAdvisor: { appState.selectedTab = .advisor },
                            onRecommendations: { appState.selectedTab = .recommendations },
                            onCart: { appState.selectedTab = .cart }
                        )
                    }

                    if let notice = appState.advisorSelectionNotice {
                        AdvisorUpdateCard(
                            notice: notice,
                            onOpenAdvisor: { appState.selectedTab = .advisor }
                        )
                    }

                    if let scan = appState.scanResult {
                        HomeScanContextCard(scan: scan)
                    }

                    if !alternativeProducts.isEmpty {
                        HomeProductCarouselSection(
                            title: "Альтернативы для замены",
                            subtitle: "Товары demo-каталога вне текущего набора.",
                            products: alternativeProducts,
                            onOpenRecommendations: { appState.selectedTab = .recommendations }
                        )
                    }

                    HomeTrustFooter()
                }
                .padding(.horizontal, BeautySpacing.md)
                .padding(.top, BeautySpacing.md)
                .padding(.bottom, BeautySpacing.xl + 88)
            }
        }
        .navigationTitle("Luma")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if appState.recommendations.products.isEmpty {
                await appState.loadRecommendations(focus: nil, silent: true)
            }
        }
    }

    private var scenarioSection: some View {
        HomeScenarioSection(
            selectedScenario: appState.selectedScenario,
            ownedRoles: appState.ownedRoles,
            onSelect: { scenario in
                appState.selectScenario(scenario)
                Task {
                    await appState.loadRecommendations(focus: scenario.recommendationFocus)
                    appState.generateRoutineVariantsFromCurrentRecommendations()
                    appState.selectedTab = .recommendations
                }
            }
        )
    }
}

private struct HomeHeroCard: View {
    let isFallback: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("luma_home_hero")
                .resizable()
                .scaledToFill()
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                Text("Соберём beauty-набор под вас")
                    .font(BeautyFont.title)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                Text("Начните со сценария — Luma сузит выбор под бюджет и то, что уже есть.")
                    .font(BeautyFont.callout)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isFallback {
                    Label("Показана сохранённая подборка", systemImage: "wifi.slash")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.limeInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BeautyColor.limeSoft, in: Capsule())
                        .padding(.top, 2)
                }
            }
            .padding(BeautySpacing.md)
        }
        .overlay(
            RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous)
                .stroke(BeautyColor.line.opacity(0.28), lineWidth: 1)
        )
        .beautyShadow()
    }
}

private struct HomeScenarioSection: View {
    let selectedScenario: LifeScenario?
    let ownedRoles: Set<RoutineRole>
    let onSelect: (LifeScenario) -> Void

    private let scenarios: [LifeScenario] = [.morning, .evening, .underBudget, .gift, .replaceOneProduct]
    private let columns = [GridItem(.adaptive(minimum: 154), spacing: 10)]

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                SectionHeader(
                    title: "Что хотите собрать сегодня?",
                    subtitle: selectedScenario?.defaultCopy ?? "Luma начинает не с каталога, а с вашего сценария, Beauty ID и того, что уже есть."
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(scenarios) { scenario in
                        Button {
                            onSelect(scenario)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: icon(for: scenario))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(BeautyColor.limeInk)
                                        .frame(width: 30, height: 30)
                                        .background(BeautyColor.limeSoft, in: Circle())
                                    Spacer()
                                    if selectedScenario == scenario {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(BeautyColor.limeInk)
                                    }
                                }
                                Text(scenario.displayTitle)
                                    .font(BeautyFont.callout.weight(.semibold))
                                    .foregroundStyle(BeautyColor.ink)
                                    .lineLimit(2)
                                Text(scenario.subtitle)
                                    .font(BeautyFont.caption)
                                    .foregroundStyle(BeautyColor.taupe)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                            .padding(12)
                            .background(selectedScenario == scenario ? BeautyColor.limeSoft.opacity(0.72) : BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                                    .stroke(selectedScenario == scenario ? BeautyColor.lime.opacity(0.72) : BeautyColor.line.opacity(0.55), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if ownedRoles.isEmpty {
                    Label("Укажите, что уже есть — Luma не добавит лишнее.", systemImage: "square.stack.3d.up")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Уже учли: \(ownedRoles.map(\.displayTitle).sorted().joined(separator: ", "))")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(2)
                }
            }
        }
    }

    private func icon(for scenario: LifeScenario) -> String {
        switch scenario {
        case .morning: return "sun.max"
        case .evening: return "moon.stars"
        case .underBudget: return "rublesign.circle"
        case .gift: return "gift"
        case .replaceOneProduct: return "arrow.triangle.2.circlepath"
        case .travel: return "suitcase"
        case .minimalRoutine: return "rectangle.compress.vertical"
        case .premiumRoutine: return "sparkles"
        }
    }
}

private struct MyShelfEntryCard: View {
    let items: [ShelfItem]
    let ownedRoles: Set<RoutineRole>

    private var statusSummary: String {
        guard !items.isEmpty else {
            return ownedRoles.isEmpty ? "Полка пока пустая" : "\(ownedRoles.count.categoryWord) из Beauty ID"
        }
        let grouped = Dictionary(grouping: items, by: \.status)
        return ShelfStatus.allCases.compactMap { status in
            guard let count = grouped[status]?.count, count > 0 else { return nil }
            return "\(status.displayTitle.lowercased()): \(count)"
        }.joined(separator: " · ")
    }

    var body: some View {
        HomeSurfaceCard {
            HStack(alignment: .center, spacing: BeautySpacing.md) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 42, height: 42)
                    .background(BeautyColor.limeSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Моя полка")
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                    Text(statusSummary)
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(BeautyFont.caption.weight(.bold))
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
    }
}

struct MyShelfView: View {
    @EnvironmentObject private var appState: AppState

    private let sections: [ShelfStatus] = [.owned, .wanted, .buyLater, .didNotFit, .empty, .needsReplacement]

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(
                        title: "Моя полка",
                        subtitle: "Luma помнит, что уже есть, что хочется попробовать, что не подошло и что нужно заменить."
                    )

                    if appState.shelfItems.isEmpty && appState.ownedRoles.isEmpty {
                        EmptyStateView(
                            title: "Полка пока пустая",
                            subtitle: "Отметьте продукты в карточках или добавьте категории через Beauty ID, чтобы будущие наборы не дублировали лишние шаги."
                        )
                    }

                    if !appState.ownedRoles.isEmpty {
                        roleSignalCard
                    }

                    ForEach(sections, id: \.self) { status in
                        let items = appState.shelfItems.filter { $0.status == status }
                        if !items.isEmpty {
                            ShelfStatusSection(status: status, items: items)
                        }
                    }

                    HStack(spacing: BeautySpacing.sm) {
                        Button("Перейти к подборке") { appState.selectedTab = .recommendations }
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.limeInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BeautyColor.lime, in: Capsule())
                        Button("Указать, что уже есть") { appState.selectedTab = .profile }
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BeautyColor.milk, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.65), lineWidth: 1))
                    }
                }
                .padding(BeautySpacing.md)
                .padding(.bottom, 88)
            }
        }
        .navigationTitle("Моя полка")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appState.recordShelfOpened(source: "home") }
    }

    private var roleSignalCard: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                Text("Категории, которые уже есть")
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(appState.ownedRoles).sorted { $0.rawValue < $1.rawValue }, id: \.self) { role in
                        Text(role.displayTitle)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BeautyColor.milk, in: Capsule())
                    }
                }
                Text("Это сигнал категории, без выдуманного конкретного товара.")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
    }
}

private struct ShelfStatusSection: View {
    @EnvironmentObject private var appState: AppState
    let status: ShelfStatus
    let items: [ShelfItem]

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: status.displayTitle, subtitle: status.businessMeaning)
            VStack(spacing: BeautySpacing.sm) {
                ForEach(items) { item in
                    ShelfItemRow(item: item)
                }
            }
        }
    }
}

private struct ShelfItemRow: View {
    @EnvironmentObject private var appState: AppState
    let item: ShelfItem

    var body: some View {
        HStack(alignment: .center, spacing: BeautySpacing.md) {
            if let product = item.product {
                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku, compact: true)
                }
                .frame(width: 58, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))
            } else {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 58, height: 68)
                    .background(BeautyColor.limeSoft, in: RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(brandText)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                Text(item.displayName ?? item.name)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(2)
                Text("\(item.role.displayTitle) · \(reasonText)")
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Menu {
                ForEach(ShelfStatus.allCases) { status in
                    Button(status.displayTitle) { appState.changeShelfStatus(item, status: status) }
                }
                if let product = item.product {
                    Button("В подборку") { Task { await appState.addProductToActiveSelection(product, source: "shelf") } }
                }
                Button("Удалить", role: .destructive) { appState.removeShelfItem(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(BeautyColor.ink)
                    .frame(width: 36, height: 36)
                    .background(BeautyColor.milk, in: Circle())
            }
        }
        .padding(12)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
    }

    private var reasonText: String {
        if let reason = item.issueReason { return reason.displayTitle }
        if let reason = item.replacementReason { return reason.displayTitle }
        return item.status.displayTitle
    }

    private var brandText: String {
        guard let brand = item.brand, !brand.isEmpty else { return item.role.displayTitle }
        return brand.uppercased()
    }
}

private struct BeautyIDSummaryCard: View {
    let beautyID: BeautyID?
    let onUpdate: () -> Void

    private var chips: [String] {
        beautyID?.summaryChips ?? ["профиль", "предпочтения", "подбор"]
    }

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                        Text("Ваш Beauty ID")
                            .font(BeautyFont.title2)
                            .foregroundStyle(BeautyColor.ink)
                        Text(beautyID?.dashboardSubtitle ?? "Заполните профиль, чтобы подбор стал точнее.")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: beautyID?.isUsable == true ? "checkmark.seal.fill" : "person.text.rectangle")
                        .font(.title3)
                        .foregroundStyle(beautyID?.isUsable == true ? BeautyColor.lime : BeautyColor.taupe)
                        .frame(width: 38, height: 38)
                        .background(BeautyColor.milk, in: Circle())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .padding(.horizontal, 10)
                            .background(BeautyColor.milk, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.58), lineWidth: 1))
                    }
                }

                Button(action: onUpdate) {
                    Label(beautyID == nil ? "Заполнить Beauty ID" : "Уточнить профиль", systemImage: "slider.horizontal.3")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(BeautyColor.milk, in: Capsule())
                        .overlay(Capsule().stroke(BeautyColor.line.opacity(0.72), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CurrentRoutineSummaryCard: View {
    let products: [RecommendationProduct]
    let savedRoutineSkus: [String]
    let selectionNotice: String?
    let onOpen: () -> Void
    let onAdvisor: () -> Void
    let onSave: () -> Void

    private var previewProducts: [RecommendationProduct] { Array(products.prefix(4)) }
    private var total: Int { products.reduce(0) { $0 + $1.priceValue } }
    private var averageMatch: Int {
        guard !products.isEmpty else { return 0 }
        return products.reduce(0) { $0 + $1.matchScore } / products.count
    }
    private var isSaved: Bool {
        !products.isEmpty && Set(products.map(\.sku)) == Set(savedRoutineSkus)
    }

    var body: some View {
        HomeSurfaceCard(tint: BeautyColor.featuredCard, borderOpacity: 0.42) {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                        Text("Ваш персональный набор")
                            .font(BeautyFont.title2)
                            .foregroundStyle(BeautyColor.ink)
                        Text(products.isEmpty ? "После Beauty ID здесь появится рабочий набор." : "\(products.count.stepWord) · \(total.rub)")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                    }
                    Spacer()
                    if !products.isEmpty {
                        HomeMetricPill(value: "\(averageMatch)%", label: "совп.")
                    }
                }

                if let selectionNotice {
                    Label(selectionNotice, systemImage: "sparkles")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if previewProducts.isEmpty {
                    Text("Luma соберёт короткий набор из каталога и будет дополнять его по вашим уточнениям.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                        .padding(BeautySpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BeautyColor.quietCard, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                } else {
                    VStack(spacing: BeautySpacing.sm) {
                        ForEach(Array(previewProducts.enumerated()), id: \.element.id) { index, product in
                            HomeRoutinePreviewRow(index: index + 1, product: product)
                        }
                    }
                }

                HStack(spacing: BeautySpacing.sm) {
                    Button(action: onOpen) {
                        Text("Открыть набор")
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.limeInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(BeautyColor.lime, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onAdvisor) {
                        Image(systemName: "message")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BeautyColor.ink)
                            .frame(width: 42, height: 42)
                            .background(BeautyColor.quietCard, in: Circle())
                            .overlay(Circle().stroke(BeautyColor.line.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Спросить советника")

                    Button(action: onSave) {
                        Image(systemName: isSaved ? "checkmark" : "bookmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BeautyColor.ink)
                            .frame(width: 42, height: 42)
                            .background(BeautyColor.quietCard, in: Circle())
                            .overlay(Circle().stroke(BeautyColor.line.opacity(0.55), lineWidth: 1))
                    }
                    .disabled(products.isEmpty)
                    .opacity(products.isEmpty ? 0.45 : 1)
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? "Набор сохранён" : "Сохранить текущий набор")
                }
            }
        }
    }
}

private struct HomeRoutinePreviewRow: View {
    @EnvironmentObject private var appState: AppState
    let index: Int
    let product: RecommendationProduct

    var body: some View {
        NavigationLink {
            ProductDetailView(product: product)
        } label: {
            HStack(spacing: BeautySpacing.sm) {
                Text("\(index)")
                    .font(BeautyFont.caption.weight(.bold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 28, height: 28)
                    .background(BeautyColor.limeSoft, in: Circle())

                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku, compact: true)
                }
                .frame(width: 54, height: 62)
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
                    Text(product.brand)
                        .font(BeautyFont.caption2)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(product.priceValue.rub)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(10)
            .background(BeautyColor.quietCard, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                    .stroke(BeautyColor.line.opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionsSection: View {
    let cartCount: Int
    let onAdvisor: () -> Void
    let onRecommendations: () -> Void
    let onCart: () -> Void

    private let columns = [GridItem(.flexible(), spacing: BeautySpacing.sm), GridItem(.flexible(), spacing: BeautySpacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Быстрые действия", subtitle: "Короткие входы в основные сценарии.")

            LazyVGrid(columns: columns, spacing: BeautySpacing.sm) {
                NavigationLink {
                    PhotoScanView()
                } label: {
                    HomeQuickActionTile(title: "Анкета / фото", subtitle: "Обновить контекст", icon: "camera.viewfinder")
                }
                .buttonStyle(.plain)

                Button(action: onAdvisor) {
                    HomeQuickActionTile(title: "Советник", subtitle: "Уточнить подбор", icon: "message")
                }
                .buttonStyle(.plain)

                Button(action: onRecommendations) {
                    HomeQuickActionTile(title: "Подбор", subtitle: "Открыть рутину", icon: "sparkles")
                }
                .buttonStyle(.plain)

                Button(action: onCart) {
                    HomeQuickActionTile(title: "Корзина", subtitle: cartCount == 0 ? "Пока пусто" : "\(cartCount) товаров", icon: "bag")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HomeQuickActionTile: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BeautyColor.limeInk)
                .frame(width: 38, height: 38)
                .background(BeautyColor.limeSoft, in: Circle())
            Spacer(minLength: 0)
            Text(title)
                .font(BeautyFont.callout.weight(.semibold))
                .foregroundStyle(BeautyColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(subtitle)
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(BeautySpacing.md)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                .stroke(BeautyColor.line.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct AdvisorUpdateCard: View {
    let notice: String
    let onOpenAdvisor: () -> Void

    var body: some View {
        HomeSurfaceCard {
            HStack(alignment: .center, spacing: BeautySpacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 42, height: 42)
                    .background(BeautyColor.limeSoft, in: Circle())
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text("Советник обновил подборку")
                        .font(BeautyFont.headline)
                        .foregroundStyle(BeautyColor.ink)
                    Text(notice)
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onOpenAdvisor) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BeautyColor.limeInk)
                        .frame(width: 36, height: 36)
                        .background(BeautyColor.lime, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть советника")
            }
        }
    }
}

private struct HomeScanContextCard: View {
    let scan: ScanResult

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                SectionHeader(title: "Последний beauty-контекст", subtitle: scan.summary)
                HStack(spacing: BeautySpacing.sm) {
                    ForEach(Array(scan.signals.prefix(3)), id: \.self) { signal in
                        Text(signal.beautyLabel)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(BeautyColor.milk, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct HomeProductCarouselSection: View {
    let title: String
    let subtitle: String
    let products: [RecommendationProduct]
    let onOpenRecommendations: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title, subtitle: subtitle)
                Button("Все") { onOpenRecommendations() }
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(BeautyColor.milk, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    ForEach(products) { product in
                        HomeProductTile(product: product)
                            .frame(width: 174, height: 304)
                    }
                }
                .padding(.horizontal, BeautySpacing.md)
            }
            .padding(.horizontal, -BeautySpacing.md)
        }
    }
}

private struct HomeProductTile: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct

    private var isInCart: Bool { appState.cartQuantity(for: product.sku) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            NavigationLink {
                ProductDetailView(product: product)
            } label: {
                VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                    CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                        ProductVisual(sku: product.sku)
                    }
                    .frame(height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        MatchBadge(score: product.matchScore)
                            .scaleEffect(0.86)
                            .padding(6)
                    }

                    Text(product.brand.uppercased())
                        .font(BeautyFont.caption2)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                    Text(product.name)
                        .font(BeautyFont.callout.weight(.semibold))
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.priceValue.rub)
                        .font(BeautyFont.caption.weight(.bold))
                        .foregroundStyle(BeautyColor.ink)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                Task { await appState.addToCart(product) }
            } label: {
                Label(isInCart ? "Добавлено" : "Добавить", systemImage: isInCart ? "checkmark" : "plus")
                    .font(BeautyFont.caption)
                    .foregroundStyle(product.isUnavailable ? BeautyColor.ink : BeautyColor.limeInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(product.isUnavailable ? BeautyColor.line : (isInCart ? BeautyColor.limeSoft : BeautyColor.lime), in: Capsule())
            }
            .disabled(product.isUnavailable)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                .stroke(BeautyColor.line.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct HomeTrustFooter: View {
    var body: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BeautyColor.taupe)
                .frame(width: 28, height: 28)
            Text("Luma помогает с предпочтениями, текстурами, финишем и подбором продуктов. Это не медицинская диагностика.")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BeautySpacing.xs)
    }
}

private struct HomeMetricPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
            Text(label)
                .font(BeautyFont.caption2)
        }
        .foregroundStyle(BeautyColor.limeInk)
        .frame(width: 58, height: 42)
        .background(BeautyColor.limeSoft, in: Capsule())
    }
}

private struct HomeSurfaceCard<Content: View>: View {
    var tint: Color = BeautyColor.card
    var borderOpacity: Double = 0.42
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(BeautySpacing.md)
            .background(tint, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous)
                    .stroke(BeautyColor.line.opacity(borderOpacity), lineWidth: 1)
            )
    }
}
