import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    @State private var showingBeautyIDEdit = false

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    profileHeader
                    beautyIDCard
                    savedRoutineCard
                    historyCard
                    privacyCard
                    Button { appState.logout() } label: {
                        Text("Выйти")
                            .font(BeautyFont.callout.weight(.semibold))
                            .foregroundStyle(BeautyColor.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(BeautyColor.milk, in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.danger.opacity(0.34), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Выйти из аккаунта")
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") } } }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingBeautyIDEdit) { NavigationStack { BeautyIDSetupView() } }
    }

    private var profileHeader: some View {
        HStack(spacing: BeautySpacing.md) {
            Image("beauty_id_abstract")
                .resizable()
                .scaledToFill()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                Text(appState.account?.name ?? "Клиент Luma")
                    .font(BeautyFont.title2)
                Text(appState.account?.email ?? "вход не выполнен")
                    .font(BeautyFont.callout)
                    .foregroundStyle(BeautyColor.taupe)
                if appState.usesLocalFallback && appState.environment.runtime == .development {
                    Text("Локальный режим")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.orange)
                }
            }
            Spacer()
        }
        .beautyCard()
    }

    private var beautyIDCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                SectionHeader(title: "Beauty ID", subtitle: "Предпочтения для подбора, не медицинский профиль.")
                Spacer()
                Button("Изменить") { showingBeautyIDEdit = true }
                    .font(BeautyFont.caption.weight(.semibold))
            }
            let tags = beautyTags
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(beautyLabel(tag))
                        .font(BeautyFont.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BeautyColor.limeSoft.opacity(0.75), in: Capsule())
                }
            }
        }
        .beautyCard()
    }

    private var beautyTags: [String] {
        guard let beautyID = appState.beautyID else { return ["Не заполнено"] }
        var tags: [String] = []
        if let skinType = beautyID.skinType { tags.append(skinType) }
        tags.append(contentsOf: beautyID.concerns.prefix(4))
        tags.append(contentsOf: beautyID.preferredFinish.prefix(2))
        tags.append(beautyID.budget)
        if beautyID.fragranceSensitivity == "avoid" { tags.append("без отдушек") }
        return tags.isEmpty ? ["Мягкая рутина"] : tags
    }

    private var savedRoutineCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Сохранённая рутина", subtitle: appState.savedRoutineSkus.isEmpty ? "Сохраните рутину из советника или подбора." : "\(appState.savedRoutineSkus.count) шагов сохранено")
            if appState.savedRoutineSkus.isEmpty {
                EmptyStateView(title: "Рутины пока нет", subtitle: "Соберите рутину с советником и сохраните её здесь.")
            } else {
                Text(appState.savedRoutineSkus.joined(separator: " · "))
                    .font(BeautyFont.callout)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .beautyCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "История", subtitle: "История рекомендаций хранится в API; история заказов зависит от подключённого оформления.")
            HStack {
                Label("История рекомендаций", systemImage: "clock")
                Spacer()
                Text("сохраняется")
                    .foregroundStyle(BeautyColor.taupe)
            }
            .font(BeautyFont.callout)
            HStack {
                Label("Заказы", systemImage: "shippingbox")
                Spacer()
                Text("в бете недоступны")
                    .foregroundStyle(BeautyColor.taupe)
            }
            .font(BeautyFont.callout)
        }
        .beautyCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Приватность")
            Text("Фото необязательно. Исходные снимки не сохраняются по умолчанию. Экспорт и запрос удаления доступны в настройках.")
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
            NavigationLink { SettingsView() } label: {
                Label("Открыть настройки", systemImage: "chevron.right")
                    .font(BeautyFont.callout.weight(.semibold))
            }
        }
        .beautyCard()
    }
}

private func beautyLabel(_ value: String) -> String {
    [
        "dry": "сухая",
        "oily": "жирная",
        "combination": "комбинированная",
        "normal": "нормальная",
        "sensitive": "чувствительная",
        "dryness": "сухость",
        "dullness": "тусклость",
        "texture": "рельеф",
        "redness": "покраснение",
        "pores": "поры",
        "shine": "блеск",
        "natural": "естественный финиш",
        "radiant": "сияющий финиш",
        "matte": "матовый финиш",
        "satin": "сатиновый финиш",
        "mid": "средний бюджет",
        "entry": "базовый бюджет",
        "premium": "премиум",
        "luxury": "люкс",
    ][value] ?? value.replacingOccurrences(of: "_", with: " ")
}
