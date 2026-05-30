import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    @State private var showingBeautyIDEdit = false
    @State private var showingLinkPhone = false
    @State private var showingDeleteConfirm = false

    private var isGuest: Bool { appState.account?.isGuestAccount ?? false }
    private var accountName: String {
        if isGuest { return "Гость" }
        return appState.account?.name ?? "Клиент Luma"
    }
    private var accountEmail: String {
        if isGuest { return "Профиль не сохранён без номера" }
        return appState.account?.phoneNumber ?? appState.account?.email ?? "вход не выполнен"
    }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    ProfileHeader()
                    ProfileIdentityCard(
                        name: accountName,
                        email: accountEmail,
                        isGuest: isGuest,
                        isBeautyIDReady: appState.beautyID?.isUsable == true,
                        isLocalMode: appState.usesLocalFallback && appState.environment.runtime == .development
                    )
                    if isGuest {
                        PrimaryButton(title: "Привязать номер телефона", systemImage: "phone.badge.plus") {
                            showingLinkPhone = true
                        }
                    }
                    ProfileBeautyIDCard(
                        beautyID: appState.beautyID,
                        onEdit: { showingBeautyIDEdit = true }
                    )
                    NavigationLink {
                        MyShelfView()
                    } label: {
                        ProfileShelfCard(itemsCount: appState.shelfItems.count, ownedRolesCount: appState.ownedRoles.count)
                    }
                    .buttonStyle(.plain)
                    ProfileSavedRoutineCard(
                        products: appState.activeSelection.recommendations + appState.recommendations.routine,
                        savedRoutineSkus: appState.savedRoutineSkus,
                        onOpenRoutine: { appState.selectedTab = .recommendations }
                    )
                    ProfileInfoListCard(
                        title: "История и активность",
                        subtitle: "Коротко о том, что хранится в аккаунте.",
                        rows: [
                            ProfileInfoRowModel(
                                icon: "clock",
                                title: "История рекомендаций",
                                subtitle: appState.advisorMessages.isEmpty ? "Появится после общения с советником" : "\(appState.advisorMessages.count) сообщений",
                                value: appState.advisorMessages.isEmpty ? "пусто" : "активна"
                            ),
                            ProfileInfoRowModel(
                                icon: "bag",
                                title: "Корзина",
                                subtitle: appState.cart.totalItems == 0 ? "Список к покупке пока пуст" : "Список к покупке собран",
                                value: appState.cart.totalItems == 0 ? "0" : "\(appState.cart.totalItems)"
                            ),
                            ProfileInfoRowModel(
                                icon: "shippingbox",
                                title: "Заказы",
                                subtitle: "Оформление подключается отдельно",
                                value: "бета"
                            )
                        ]
                    )
                    NavigationLink {
                        BusinessAnalyticsView()
                    } label: {
                        ProfileBusinessPilotCard(
                            profilesCount: appState.latestIntentProfiles.count,
                            shelfCount: appState.shelfItems.count,
                            scenario: appState.selectedScenario
                        )
                    }
                    .buttonStyle(.plain)
                    ProfilePrivacyCard(onOpenSettings: { showingSettings = true })
                    ProfileInfoListCard(
                        title: "Настройки аккаунта",
                        subtitle: "Тема, приватность, уведомления и поддержка.",
                        rows: [
                            ProfileInfoRowModel(icon: "paintpalette", title: "Внешний вид", subtitle: "Текущая тема: \(appState.appTheme.title.lowercased())", value: nil),
                            ProfileInfoRowModel(icon: "lock", title: "Приватность", subtitle: "Экспорт и запрос удаления доступны в настройках", value: nil),
                            ProfileInfoRowModel(icon: "bubble.left.and.bubble.right", title: "Поддержка", subtitle: "Отзыв и информация о версии", value: nil)
                        ],
                        actionTitle: "Открыть настройки",
                        action: { showingSettings = true }
                    )
                    DestructiveActionButton(title: "Выйти из аккаунта") {
                        appState.logout()
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Удалить аккаунт")
                            .font(BeautyFont.headline)
                            .foregroundStyle(BeautyColor.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(appState.isBusy)
                }
                .padding(.horizontal, BeautySpacing.md)
                .padding(.top, BeautySpacing.md)
                .padding(.bottom, BeautySpacing.xl + 88)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingBeautyIDEdit) { NavigationStack { BeautyIDSetupView() } }
        .sheet(isPresented: $showingLinkPhone) { LinkPhoneSheet() }
        .alert("Удалить аккаунт?", isPresented: $showingDeleteConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task { await appState.deleteAccount() }
            }
        } message: {
            Text("Профиль, Beauty ID, история и корзина будут удалены без возможности восстановления.")
        }
    }
}

private struct ProfileHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.xs) {
            Text("Профиль")
                .font(BeautyFont.title)
                .foregroundStyle(BeautyColor.ink)
            Text("Аккаунт, Beauty ID и приватность в одном месте.")
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileIdentityCard: View {
    let name: String
    let email: String
    var isGuest: Bool = false
    let isBeautyIDReady: Bool
    let isLocalMode: Bool

    var body: some View {
        SurfaceCard(tint: BeautyColor.featuredCard) {
            HStack(alignment: .center, spacing: BeautySpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous)
                        .fill(LinearGradient(colors: [BeautyColor.limeSoft, BeautyColor.champagne.opacity(0.58)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(monogram)
                        .font(BeautyFont.sized(25, .semibold))
                        .foregroundStyle(BeautyColor.limeInk)
                }
                .frame(width: 76, height: 82)
                .overlay(
                    RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous)
                        .stroke(BeautyColor.line.opacity(0.42), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text(name)
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(email)
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    HStack(spacing: BeautySpacing.xs) {
                        if isGuest {
                            ProfileStatusPill(title: "Гость", icon: "person.crop.circle.badge.questionmark", tint: BeautyColor.orange.opacity(0.14))
                        }
                        ProfileStatusPill(
                            title: isBeautyIDReady ? "Beauty ID настроен" : "Beauty ID нужно заполнить",
                            icon: isBeautyIDReady ? "checkmark.seal.fill" : "person.text.rectangle"
                        )
                        if isLocalMode {
                            ProfileStatusPill(title: "Локальный режим", icon: "wifi.slash", tint: BeautyColor.orange.opacity(0.14))
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var monogram: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? "L" : value
    }
}

private struct ProfileBeautyIDCard: View {
    let beautyID: BeautyID?
    let onEdit: () -> Void

    private var chips: [String] {
        beautyID?.summaryChips ?? ["не заполнено"]
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                        Text("Beauty ID")
                            .font(BeautyFont.title2)
                            .foregroundStyle(BeautyColor.ink)
                        Text("Предпочтения для подбора, не медицинский профиль.")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onEdit) {
                        Text("Уточнить")
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.limeInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(BeautyColor.lime, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip.beautyLabel)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .padding(.horizontal, 10)
                            .background(BeautyColor.quietCard, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.58), lineWidth: 1))
                    }
                }
            }
        }
    }
}

private struct ProfileShelfCard: View {
    let itemsCount: Int
    let ownedRolesCount: Int

    var body: some View {
        SurfaceCard {
            HStack(spacing: BeautySpacing.md) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 42, height: 42)
                    .background(BeautyColor.limeSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Моя полка")
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                    Text(summary)
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

    private var summary: String {
        var parts = [itemsCount.productWord]
        if ownedRolesCount > 0 { parts.append("\(ownedRolesCount.categoryWord) из Beauty ID") }
        else { parts.append("укажите, что уже есть") }
        return parts.joined(separator: " · ")
    }
}

private struct ProfileSavedRoutineCard: View {
    let products: [RecommendationProduct]
    let savedRoutineSkus: [String]
    let onOpenRoutine: () -> Void

    private var savedPreview: [RecommendationProduct] {
        let saved = Set(savedRoutineSkus)
        let source = saved.isEmpty ? [] : products.filter { saved.contains($0.sku) }
        return Array(source.prefix(3))
    }

    private var stepCount: Int {
        savedRoutineSkus.count
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                        Text("Сохранённый набор")
                            .font(BeautyFont.title2)
                            .foregroundStyle(BeautyColor.ink)
                        Text(stepCount == 0 ? "Сохраните набор из советника или подбора." : "\(stepCount.stepWord) в сохранённом наборе")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                    }
                    Spacer()
                    Text(stepCount == 0 ? "нет" : "\(stepCount)")
                        .font(BeautyFont.sized(15, .bold))
                        .foregroundStyle(BeautyColor.limeInk)
                        .frame(width: 46, height: 36)
                        .background(BeautyColor.limeSoft, in: Capsule())
                }

                if savedPreview.isEmpty {
                    Text("Когда набор появится, здесь будет короткий список товаров.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                        .padding(BeautySpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BeautyColor.quietCard, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                } else {
                    VStack(spacing: BeautySpacing.sm) {
                        ForEach(savedPreview) { product in
                            ProfileRoutineMiniRow(product: product)
                        }
                    }
                }

                Button(action: onOpenRoutine) {
                    Label("Открыть набор", systemImage: "arrow.right")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(BeautyColor.quietCard, in: Capsule())
                        .overlay(Capsule().stroke(BeautyColor.line.opacity(0.62), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ProfileRoutineMiniRow: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct

    var body: some View {
        HStack(spacing: BeautySpacing.sm) {
            CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                ProductVisual(sku: product.sku, compact: true)
            }
            .frame(width: 46, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(product.routineStep.beautyLabel)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .textCase(.uppercase)
                Text(product.name)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
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
        }
        .padding(10)
        .background(BeautyColor.quietCard, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                .stroke(BeautyColor.line.opacity(0.42), lineWidth: 1)
        )
    }
}

private struct ProfileBusinessPilotCard: View {
    let profilesCount: Int
    let shelfCount: Int
    let scenario: LifeScenario?

    var body: some View {
        SurfaceCard(tint: BeautyColor.featuredCard) {
            HStack(spacing: BeautySpacing.md) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 42, height: 42)
                    .background(BeautyColor.limeSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Пилотная аналитика")
                        .font(BeautyFont.title2)
                        .foregroundStyle(BeautyColor.ink)
                    Text("\(profilesCount.profileWord) намерения · \(shelfCount.productWord) на полке · \(scenario?.displayTitle ?? "сценарий не выбран")")
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

private struct BusinessAnalyticsView: View {
    @EnvironmentObject private var appState: AppState

    private var shelfCounts: [(ShelfStatus, Int)] {
        let grouped = Dictionary(grouping: appState.shelfItems, by: \.status)
        return ShelfStatus.allCases.compactMap { status in
            guard let count = grouped[status]?.count, count > 0 else { return nil }
            return (status, count)
        }
    }

    private var blockerCounts: [(PurchaseBlocker, Int)] {
        let grouped = Dictionary(grouping: appState.latestIntentProfiles.compactMap(\.selectedBlocker), by: { $0 })
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    private var ownedRolesText: String {
        let value = appState.ownedRoles.map(\.displayTitle).sorted().joined(separator: ", ")
        return value.isEmpty ? "нет" : value
    }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(
                        title: "Пилотная аналитика",
                        subtitle: "Локальный срез без email, фото и текста из чата. Это не production-дашборд."
                    )

                    analyticsCard(title: "Воронка", rows: [
                        ("Сценарий выбран", appState.selectedScenario?.displayTitle ?? "нет"),
                        ("Открыто товаров", "\(appState.productOpenedSkus.count)"),
                        ("Сравнение открыто", appState.comparisonOpenedThisSession ? "да" : "нет"),
                        ("Намерение купить", appState.purchaseIntentClickedThisSession ? "да" : "нет"),
                        ("Профили намерения", "\(appState.latestIntentProfiles.count)")
                    ])

                    analyticsCard(title: "Сценарий", rows: [
                        ("Текущий сценарий", appState.selectedScenario?.displayTitle ?? "нет"),
                        ("Что уже есть", ownedRolesText)
                    ])

                    analyticsCard(title: "Действия с полкой", rows: shelfCounts.map { ($0.0.displayTitle, "\($0.1)") })
                    analyticsCard(title: "Причины сомнения", rows: blockerCounts.map { ($0.0.displayTitle, "\($0.1)") })
                    analyticsCard(title: "Последние действия", rows: appState.recentRecommendationActions.prefix(10).map { ("действие", $0) })

                    VStack(alignment: .leading, spacing: BeautySpacing.md) {
                        SectionHeader(title: "Профили намерения")
                        if appState.latestIntentProfiles.isEmpty {
                            EmptyStateView(title: "Профилей пока нет", subtitle: "Они появятся после «Я бы купила» и выбора причины сомнения.")
                        } else {
                            ForEach(appState.latestIntentProfiles.prefix(8)) { profile in
                                VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                                    Text(profile.intentLevel.rawValue.uppercased())
                                        .font(BeautyFont.caption.weight(.bold))
                                        .foregroundStyle(BeautyColor.limeInk)
                                    Text(profile.businessSummary)
                                        .font(BeautyFont.callout)
                                        .foregroundStyle(BeautyColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(BeautySpacing.md)
                .padding(.bottom, 88)
            }
        }
        .navigationTitle("Пилотная аналитика")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appState.recordAnalyticsDashboardOpened() }
    }

    private func analyticsCard(title: String, rows: [(String, String)]) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                Text(title)
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                if rows.isEmpty {
                    Text("Пока нет данных")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.0)
                                .font(BeautyFont.caption)
                                .foregroundStyle(BeautyColor.taupe)
                            Spacer()
                            Text(row.1)
                                .font(BeautyFont.caption.weight(.semibold))
                                .foregroundStyle(BeautyColor.ink)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct ProfileInfoListCard: View {
    let title: String
    let subtitle: String
    let rows: [ProfileInfoRowModel]
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                SectionHeader(title: title, subtitle: subtitle)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        ProfileActionRow(model: row)
                        if index < rows.count - 1 {
                            Divider()
                                .background(BeautyColor.line.opacity(0.5))
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(BeautyColor.quietCard, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous)
                        .stroke(BeautyColor.line.opacity(0.42), lineWidth: 1)
                )

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(BeautyColor.milk, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.62), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProfilePrivacyCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        SurfaceCard(tint: BeautyColor.featuredCard) {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                HStack(alignment: .top, spacing: BeautySpacing.md) {
                    Image(systemName: "lock.shield")
                        .font(BeautyFont.sized(19, .semibold))
                        .foregroundStyle(BeautyColor.limeInk)
                        .frame(width: 42, height: 42)
                        .background(BeautyColor.limeSoft, in: Circle())
                    VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                        Text("Приватность")
                            .font(BeautyFont.title2)
                            .foregroundStyle(BeautyColor.ink)
                        Text("Фото необязательно. Снимки по умолчанию не хранятся. Экспорт и запрос удаления доступны в настройках.")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: onOpenSettings) {
                    Label("Открыть настройки", systemImage: "arrow.right")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.limeInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(BeautyColor.lime, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ProfileActionRow: View {
    let model: ProfileInfoRowModel

    var body: some View {
        HStack(alignment: .center, spacing: BeautySpacing.sm) {
            Image(systemName: model.icon)
                .font(BeautyFont.sized(15, .semibold))
                .foregroundStyle(BeautyColor.ink)
                .frame(width: 34, height: 34)
                .background(BeautyColor.card, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(model.subtitle)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let value = model.value {
                Text(value)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(1)
            } else {
                Image(systemName: "chevron.right")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct DestructiveActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BeautyFont.callout.weight(.semibold))
                .foregroundStyle(BeautyColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(BeautyColor.card, in: Capsule())
                .overlay(Capsule().stroke(BeautyColor.danger.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, BeautySpacing.xs)
        .accessibilityLabel(title)
    }
}

private struct ProfileStatusPill: View {
    let title: String
    let icon: String
    var tint: Color = BeautyColor.limeSoft

    var body: some View {
        Label(title, systemImage: icon)
            .font(BeautyFont.caption)
            .foregroundStyle(BeautyColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
    }
}


private struct ProfileInfoRowModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let value: String?
}

private struct LinkPhoneSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var country: PhoneCountry = .defaults.first!
    @State private var nationalDigits = ""
    @State private var name = ""
    @State private var password = ""

    private var e164Phone: String { country.dialCode + nationalDigits }
    private var canSubmit: Bool { nationalDigits.count >= country.minDigits }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                ScrollView {
                    VStack(spacing: BeautySpacing.lg) {
                        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                            Text("Привязать номер")
                                .font(BeautyFont.title2)
                                .foregroundStyle(BeautyColor.ink)
                            Text("Сохраним Beauty ID, рутину и корзину за вашим номером. SMS-код не нужен.")
                                .font(BeautyFont.callout)
                                .foregroundStyle(BeautyColor.taupe)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: BeautySpacing.md) {
                            VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                                Text("Телефон").font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
                                HStack(spacing: BeautySpacing.sm) {
                                    Menu {
                                        ForEach(PhoneCountry.defaults) { item in
                                            Button("\(item.flag)  \(item.id)  \(item.dialCode)") {
                                                country = item
                                                nationalDigits = String(nationalDigits.prefix(item.maxDigits))
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(country.flag)
                                            Text(country.dialCode).font(BeautyFont.body).foregroundStyle(BeautyColor.ink)
                                            Image(systemName: "chevron.down").font(BeautyFont.sized(11, .semibold)).foregroundStyle(BeautyColor.taupe)
                                        }
                                        .padding(.horizontal, BeautySpacing.md)
                                        .frame(height: 52)
                                        .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
                                    }
                                    TextField("000 000-00-00", text: Binding(
                                        get: { country.formatted(nationalDigits) },
                                        set: { nationalDigits = String($0.filter(\.isNumber).prefix(country.maxDigits)) }
                                    ))
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .padding(.horizontal, BeautySpacing.md)
                                    .frame(height: 52)
                                    .frame(maxWidth: .infinity)
                                    .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
                                }
                            }
                            simpleField(title: "Имя (необязательно)", text: $name, secure: false)
                            simpleField(title: "Пароль (необязательно)", text: $password, secure: true)

                            PrimaryButton(title: "Сохранить номер", isLoading: appState.isBusy) {
                                Task {
                                    await appState.linkPhone(phone: e164Phone, name: name, password: password)
                                    if appState.errorMessage == nil { dismiss() }
                                }
                            }
                            .disabled(!canSubmit || appState.isBusy)
                            .opacity(canSubmit ? 1 : 0.55)
                        }
                        .beautyCard()
                    }
                    .padding(BeautySpacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func simpleField(title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: BeautySpacing.xs) {
            Text(title).font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
            Group {
                if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
            }
            .textInputAutocapitalization(secure ? .never : .words)
            .autocorrectionDisabled()
            .padding(.horizontal, BeautySpacing.md)
            .frame(height: 52)
            .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
        }
    }
}
