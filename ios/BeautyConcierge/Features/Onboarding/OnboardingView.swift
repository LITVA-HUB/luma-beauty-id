import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(image: "onboarding_visual_1", title: "Beauty ID вместо случайных покупок", subtitle: "Собираем ваши предпочтения по текстурам, финишу, бюджету и уходу без медицинских обещаний."),
        OnboardingPage(image: "hero_beauty_visual", title: "Советник, который знает каталог", subtitle: "Объясняет, почему продукт подходит, предлагает альтернативы и не придумывает товары вне каталога."),
        OnboardingPage(image: "scan_guide", title: "Фото только по вашему выбору", subtitle: "Можно пройти анкету без фото. Снимок помогает с косметическим контекстом и не является диагностикой кожи.")
    ]

    var body: some View {
        ZStack {
            PremiumBackground()
            VStack(spacing: BeautySpacing.lg) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: BeautySpacing.xl) {
                            Image(item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 330)
                                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                                .beautyShadow()
                                .padding(.horizontal, BeautySpacing.md)
                                .accessibilityHidden(true)
                            VStack(spacing: BeautySpacing.md) {
                                Text(item.title)
                                    .font(BeautyFont.title)
                                    .foregroundStyle(BeautyColor.ink)
                                    .multilineTextAlignment(.center)
                                Text(item.subtitle)
                                    .font(BeautyFont.body)
                                    .foregroundStyle(BeautyColor.taupe)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, BeautySpacing.lg)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: BeautySpacing.xs) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? BeautyColor.ink : BeautyColor.line)
                            .frame(width: index == page ? 26 : 8, height: 8)
                    }
                }
                .accessibilityHidden(true)

                VStack(spacing: BeautySpacing.sm) {
                    PrimaryButton(title: page == pages.count - 1 ? "Создать Beauty ID" : "Продолжить", systemImage: "sparkles") {
                        if page < pages.count - 1 {
                            withAnimation(.spring()) { page += 1 }
                            Haptics.tap()
                        } else {
                            appState.finishOnboarding()
                        }
                    }
                    Button("У меня уже есть аккаунт") { appState.finishOnboarding() }
                        .font(BeautyFont.callout.weight(.semibold))
                        .foregroundStyle(BeautyColor.taupe)
                        .padding(.vertical, BeautySpacing.sm)
                }
                .padding(.horizontal, BeautySpacing.md)
                .padding(.bottom, BeautySpacing.lg)
            }
        }
    }
}

private struct OnboardingPage {
    let image: String
    let title: String
    let subtitle: String
}
