import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(spacing: BeautySpacing.xl) {
                    VStack(alignment: .leading, spacing: BeautySpacing.md) {
                        Text("Добро пожаловать в Luma")
                            .font(BeautyFont.title)
                            .foregroundStyle(BeautyColor.ink)
                        Text("Войдите, чтобы сохранить Beauty ID, уходовую рутину и корзину.")
                            .font(BeautyFont.body)
                            .foregroundStyle(BeautyColor.taupe)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: BeautySpacing.md) {
                        Picker("Режим", selection: $mode) {
                            Text("Войти").tag(AuthMode.login)
                            Text("Создать").tag(AuthMode.register)
                        }
                        .pickerStyle(.segmented)

                        if mode == .register {
                            AuthTextField(title: "Имя", text: $name, contentType: .name)
                        }
                        AuthTextField(title: "Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                        AuthTextField(title: "Пароль", text: $password, contentType: mode == .register ? .newPassword : .password, isSecure: true)

                        PrimaryButton(title: mode == .login ? "Войти" : "Создать аккаунт", isLoading: appState.isBusy) {
                            Task {
                                if mode == .login { await appState.login(email: email, password: password) }
                                else { await appState.register(name: name.isEmpty ? "Клиент Luma" : name, email: email, password: password) }
                            }
                        }
                    }
                    .beautyCard()

                    if appState.environment.canShowDevLogin {
                        VStack(spacing: BeautySpacing.sm) {
                            Text("Локальный режим")
                                .font(BeautyFont.caption)
                                .foregroundStyle(BeautyColor.taupe)
                                .textCase(.uppercase)
                                .tracking(1.4)
                            SecondaryButton(title: "Войти локально", systemImage: "hammer") {
                                Task { await appState.continueInDevelopmentMode() }
                            }
                            Text("Доступно только в локальной сборке.")
                                .font(BeautyFont.caption)
                                .foregroundStyle(BeautyColor.warmGray)
                                .multilineTextAlignment(.center)
                        }
                        .beautyCard()
                    }
                }
                .padding(BeautySpacing.md)
            }
        }
    }
}

private enum AuthMode: Hashable {
    case login, register
}

private struct AuthTextField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.xs) {
            Text(title).font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
            Group {
                if isSecure { SecureField(title, text: $text) }
                else { TextField(title, text: $text) }
            }
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, BeautySpacing.md)
            .frame(height: 52)
            .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
        }
    }
}
