import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var notifications = false
    @State private var routineReminders = true
    @State private var allowAnalytics = false
    @State private var showingFeedback = false

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                Form {
                    Section("Внешний вид") {
                        Picker("Тема", selection: Binding(get: { appState.appTheme }, set: { appState.setTheme($0) })) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Уведомления") {
                        Toggle("Напоминания о рутине", isOn: $routineReminders)
                        Toggle("Новые подборки", isOn: $notifications)
                    }
                    Section("Приватность") {
                        Toggle("Отправлять анонимную аналитику продуктов", isOn: $allowAnalytics)
                        Text("Аналитика должна учитывать согласие и не включать email, фото, сырой Beauty ID или свободный текст из советника.")
                            .font(.caption)
                            .foregroundStyle(BeautyColor.taupe)
                        Button("Экспортировать мои данные") {
                            appState.privacyMessage = "Экспорт данных будет подготовлен в безопасном формате."
                        }
                        Button("Запросить удаление аккаунта", role: .destructive) {
                            Task { await appState.requestPrivacyDeletion() }
                        }
                        if let message = appState.privacyMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(BeautyColor.taupe)
                        }
                    }
                    Section("Поддержка") {
                        Button {
                            showingFeedback = true
                        } label: {
                            Label("Оставить отзыв", systemImage: "bubble.left.and.bubble.right")
                        }
                        Label("support@lumabeautyid.app", systemImage: "envelope")
                        Label(versionLabel, systemImage: "info.circle")
                    }
                    Section("Документы") {
                        if let url = AppEnvironment.privacyPolicyURL {
                            Link(destination: url) {
                                Label("Политика конфиденциальности", systemImage: "lock.doc")
                            }
                        }
                        if let url = AppEnvironment.supportURL {
                            Link(destination: url) {
                                Label("Помощь и поддержка", systemImage: "questionmark.circle")
                            }
                        }
                        if let url = AppEnvironment.accountDeletionURL {
                            Link(destination: url) {
                                Label("Удаление аккаунта и данных", systemImage: "trash")
                            }
                        }
                    }
                    if appState.environment.isDebug {
                        Section("Среда") {
                            Label(environmentTitle(appState.environment.runtime.rawValue), systemImage: "server.rack")
                            Label(appState.environment.baseURL.absoluteString, systemImage: "link")
                                .font(.caption)
                        }
                    }
                    Section("Безопасность") {
                        Text("Luma Beauty ID — beauty-советник для подбора косметики. Он не диагностирует состояние кожи, не лечит симптомы и не заменяет консультацию специалиста.")
                            .font(.caption)
                            .foregroundStyle(BeautyColor.taupe)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .sheet(isPresented: $showingFeedback) {
                FeedbackSheet(isPresented: $showingFeedback)
                    .environmentObject(appState)
            }
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Версия \(version) (\(build))"
    }

    private func environmentTitle(_ value: String) -> String {
        switch value {
        case "development": return "Разработка"
        case "staging": return "Проверочный стенд"
        case "production": return "Продакшен"
        default: return value
        }
    }
}

private struct FeedbackSheet: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var rating = 5
    @State private var message = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(title: "Оставить отзыв", subtitle: "Что понравилось, что мешает, чего не хватило?")
                    HStack(spacing: BeautySpacing.sm) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                rating = value
                            } label: {
                                Text("\(value)")
                                    .font(BeautyFont.headline)
                                    .foregroundStyle(rating == value ? BeautyColor.limeInk : BeautyColor.ink)
                                    .frame(width: 44, height: 44)
                                    .background(rating == value ? BeautyColor.lime : BeautyColor.milk, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Оценка \(value) из 5")
                        }
                    }
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .padding(BeautySpacing.sm)
                        .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.55), lineWidth: 1))
                    if let feedbackMessage = appState.feedbackMessage {
                        Text(feedbackMessage)
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                    }
                    PrimaryButton(title: "Отправить", systemImage: "paperplane", isLoading: isSending) {
                        Task {
                            isSending = true
                            let didSubmit = await appState.submitFeedback(rating: rating, message: message, context: "settings")
                            isSending = false
                            if didSubmit { isPresented = false }
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(BeautySpacing.md)
            }
            .navigationTitle("Отзыв")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { isPresented = false } } }
        }
    }
}
