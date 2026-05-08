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
    }
}

struct ServiceUnavailableView: View {
    let message: String

    var body: some View {
        ZStack {
            PremiumBackground()
            VStack(spacing: BeautySpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 34, weight: .semibold))
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
                Image("beauty_id_abstract")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: BeautySpacing.xs) {
                    Text("Luma")
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
        .tint(BeautyColor.lime)
    }
}
