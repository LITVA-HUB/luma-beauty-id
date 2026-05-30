import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLaunching {
                LaunchView()
            } else if let configurationError = appState.environment.configurationError {
                ServiceUnavailableView(message: configurationError)
            } else if !appState.hasSeenOnboarding {
                OnboardingView()
            } else if appState.account == nil {
                AuthView()
            } else if appState.needsFaceScan {
                FaceGateView()
            } else if appState.beautyID?.isUsable != true {
                BeautyIDSetupView()
            } else {
                MainTabView()
            }
        }
        .background(BeautyColor.ivory.ignoresSafeArea())
        .alert("Нужно внимание", isPresented: Binding(get: { appState.errorMessage != nil }, set: { if !$0 { appState.errorMessage = nil } })) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .sheet(item: $appState.beautyIDReveal) { payload in
            BeautyIDRevealView(
                beautyID: payload.beautyID,
                onRoutine: {
                    appState.beautyIDReveal = nil
                    appState.selectedTab = .recommendations
                },
                onAdvisor: {
                    appState.beautyIDReveal = nil
                    appState.selectedTab = .advisor
                }
            )
        }
    }
}

struct ServiceUnavailableView: View {
    let message: String

    var body: some View {
        ZStack {
            PremiumBackground()
            VStack(spacing: BeautySpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(BeautyFont.sized(34, .semibold))
                    .foregroundStyle(BeautyColor.taupe)
                    .frame(width: 72, height: 72)
                    .background(BeautyColor.milk, in: Circle())
                Text("Сервис временно недоступен")
                    .font(BeautyFont.title2)
                    .foregroundStyle(BeautyColor.ink)
                Text(message)
                    .font(BeautyFont.body)
                    .foregroundStyle(BeautyColor.taupe)
                    .multilineTextAlignment(.center)
            }
            .padding(BeautySpacing.lg)
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            BeautyColor.ivory.ignoresSafeArea()
            VStack(spacing: BeautySpacing.lg) {
                Image("luma_home_hero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: BeautySpacing.xs) {
                    Text("Золотое Яблоко")
                        .font(BeautyFont.display)
                        .foregroundStyle(BeautyColor.ink)
                    Text("Beauty ID")
                        .font(BeautyFont.caption)
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(BeautyColor.taupe)
                }
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "sparkles") }
                .tag(AppState.Tab.home)
            NavigationStack { AdvisorView() }
                .tabItem { Label("Советник", systemImage: "message") }
                .tag(AppState.Tab.advisor)
            NavigationStack { RecommendationsView() }
                .tabItem { Label("Подбор", systemImage: "bag") }
                .tag(AppState.Tab.recommendations)
            NavigationStack { CartView() }
                .tabItem { Label("Корзина", systemImage: "cart") }
                .badge(appState.cart.totalItems)
                .tag(AppState.Tab.cart)
            NavigationStack { ProfileView() }
                .tabItem { Label("Профиль", systemImage: "person") }
                .tag(AppState.Tab.profile)
        }
        .tint(BeautyColor.limeTint)
    }
}

private struct BeautyIDRevealView: View {
    let beautyID: BeautyID
    let onRoutine: () -> Void
    let onAdvisor: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var visibleChipCount = 0
    @State private var cardVisible = false

    private var chips: [String] { beautyID.summaryChips }

    private var topProducts: [RecommendationProduct] {
        Array(appState.recommendations.products.prefix(3))
    }

    @ViewBuilder private func productRow(_ product: RecommendationProduct) -> some View {
        HStack(spacing: BeautySpacing.sm) {
            AsyncImage(url: appState.absoluteURL(for: product.preferredImagePath)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                BeautyColor.milk
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(product.brand)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                Text(product.name)
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
                Text(product.reason)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("\(product.matchScore)%")
                .font(BeautyFont.headline)
                .foregroundStyle(BeautyColor.limeInk)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                ScrollView {
                    VStack(spacing: BeautySpacing.lg) {
                        VStack(spacing: BeautySpacing.sm) {
                            Text("Ваш Beauty ID готов")
                                .font(BeautyFont.title)
                                .foregroundStyle(BeautyColor.ink)
                                .multilineTextAlignment(.center)
                            Text("Собрала профиль предпочтений для спокойного и точного подбора.")
                                .font(BeautyFont.body)
                                .foregroundStyle(BeautyColor.taupe)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, BeautySpacing.xl)

                        VStack(spacing: BeautySpacing.sm) {
                            Text("ТВОЙ BEAUTY-ТИП")
                                .font(BeautyFont.caption)
                                .tracking(1.6)
                                .foregroundStyle(BeautyColor.taupe)
                            Text(beautyID.archetype.name)
                                .font(BeautyFont.display)
                                .foregroundStyle(BeautyColor.ink)
                                .multilineTextAlignment(.center)
                            Text(beautyID.archetype.tagline)
                                .font(BeautyFont.body)
                                .foregroundStyle(BeautyColor.taupe)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .beautyCard()
                        .scaleEffect(cardVisible ? 1 : 0.97)
                        .opacity(cardVisible ? 1 : 0)

                        if !topProducts.isEmpty {
                            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                                Text("Подобрали под тебя")
                                    .font(BeautyFont.title2)
                                    .foregroundStyle(BeautyColor.ink)
                                ForEach(topProducts) { product in
                                    productRow(product)
                                }
                                Text("Совпадение посчитано по твоему Beauty ID и каталогу. Это косметический подбор, не диагностика.")
                                    .font(BeautyFont.caption)
                                    .foregroundStyle(BeautyColor.warmGray)
                            }
                            .beautyCard()
                            .opacity(cardVisible ? 1 : 0)
                        }

                        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                            Text("Твой профиль")
                                .font(BeautyFont.headline)
                                .foregroundStyle(BeautyColor.ink)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(Array(chips.prefix(visibleChipCount)), id: \.self) { chip in
                                    Text(chip)
                                        .font(BeautyFont.caption)
                                        .foregroundStyle(BeautyColor.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(BeautyColor.milk, in: Capsule())
                                        .overlay(Capsule().stroke(BeautyColor.line.opacity(0.58), lineWidth: 1))
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        .beautyCard()
                        .opacity(cardVisible ? 1 : 0)

                        VStack(spacing: BeautySpacing.sm) {
                            if appState.account == nil {
                                PrimaryButton(title: "Сохранить мой Beauty ID", systemImage: "checkmark") { dismiss() }
                                Text("Создай аккаунт, чтобы сохранить свой beauty-тип и подборку и вернуться к ней позже.")
                                    .font(BeautyFont.caption)
                                    .foregroundStyle(BeautyColor.taupe)
                                    .multilineTextAlignment(.center)
                            } else {
                                PrimaryButton(title: "Собрать рутину", systemImage: "sparkles", action: onRoutine)
                                SecondaryButton(title: "Спросить советника", systemImage: "message", action: onAdvisor)
                            }
                        }
                    }
                    .padding(BeautySpacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            Haptics.success()
            withAnimation(.easeOut(duration: 0.38)) { cardVisible = true }
            for index in chips.indices {
                try? await Task.sleep(nanoseconds: 85_000_000)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    visibleChipCount = index + 1
                }
            }
        }
    }
}
