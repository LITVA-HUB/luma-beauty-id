import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(image: "onboarding_visual_1", title: "Хватит выбирать косметику наугад", subtitle: "Ответь на пару вопросов о себе — и получи личную подборку под твою кожу, бюджет и стиль. Минута, и без случайных покупок.")
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

                if pages.count > 1 {
                    HStack(spacing: BeautySpacing.xs) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? BeautyColor.ink : BeautyColor.line)
                                .frame(width: index == page ? 26 : 8, height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                }

                VStack(spacing: BeautySpacing.sm) {
                    PrimaryButton(title: page == pages.count - 1 ? "Создать Beauty ID" : "Продолжить", systemImage: "sparkles") {
                        if page < pages.count - 1 {
                            withAnimation(.spring()) { page += 1 }
                            Haptics.tap()
                        } else {
                            appState.finishOnboarding()
                        }
                    }
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
