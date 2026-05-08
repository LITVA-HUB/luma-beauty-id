import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    hero
                    quickActions
                    if let scan = appState.scanResult {
                        scanSummary(scan)
                    }
                    HorizontalProductRail(title: "Ваша рутина", products: Array(appState.recommendations.routine.prefix(6)))
                    privacyCard
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle("Luma")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadRecommendations(focus: nil, silent: true) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            Image("luma_home_hero")
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                Text("Личный beauty-консьерж")
                    .font(BeautyFont.title)
                    .foregroundStyle(BeautyColor.ink)
                Text("Beauty ID, анкета, советник и подбор косметики в одном спокойном iPhone-сценарии.")
                    .font(BeautyFont.body)
                    .foregroundStyle(BeautyColor.taupe)
                if appState.usesLocalFallback {
                    Label("Показана сохранённая подборка", systemImage: "wifi.slash")
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.orange)
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Начните здесь")
            HStack(spacing: BeautySpacing.md) {
                NavigationLink { PhotoScanView() } label: {
                    actionTile(title: "Анкета или фото", subtitle: "Фото необязательно", icon: "camera.viewfinder")
                }
                NavigationLink { AdvisorView() } label: {
                    actionTile(title: "Спросить советника", subtitle: "Уточнить рутину", icon: "message")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func actionTile(title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(BeautyColor.ink)
                .frame(width: 46, height: 46)
                .background(BeautyColor.lime, in: Circle())
            Text(title).font(BeautyFont.headline).foregroundStyle(BeautyColor.ink)
            Text(subtitle).font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .beautyCard()
    }

    private func scanSummary(_ scan: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: "Последний beauty-контекст", subtitle: scan.summary)
            ForEach(scan.signals.prefix(3), id: \.self) { signal in
                Label(signal, systemImage: "sparkle")
                    .font(BeautyFont.callout)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .beautyCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Label("Только про красоту", systemImage: "checkmark.seal")
                .font(BeautyFont.headline)
            Text("Luma не диагностирует и не лечит кожу. Приложение помогает с предпочтениями, текстурами, финишем и подбором продуктов.")
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
        }
        .beautyCard()
    }
}
