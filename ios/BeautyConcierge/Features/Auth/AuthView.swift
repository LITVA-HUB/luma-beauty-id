import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .register
    @State private var name = ""
    @State private var country: PhoneCountry = .defaults.first!
    @State private var nationalDigits = ""
    @State private var password = ""

    private var e164Phone: String { country.dialCode + nationalDigits }
    private var phoneLooksValid: Bool { nationalDigits.count >= country.minDigits }
    private var canSubmit: Bool {
        guard phoneLooksValid else { return false }
        if mode == .register { return !trimmedName.isEmpty || true }
        return true
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(spacing: BeautySpacing.xl) {
                    VStack(alignment: .leading, spacing: BeautySpacing.md) {
                        Text("Добро пожаловать в Luma")
                            .font(BeautyFont.title)
                            .foregroundStyle(BeautyColor.ink)
                            .minimumScaleFactor(0.8)
                            .lineLimit(2)
                        Text("Войдите по номеру телефона, чтобы сохранить Beauty ID, рутину и корзину.")
                            .font(BeautyFont.body)
                            .foregroundStyle(BeautyColor.taupe)
                            .fixedSize(horizontal: false, vertical: true)
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

                        PhoneField(title: "Телефон", country: $country, nationalDigits: $nationalDigits)

                        AuthTextField(
                            title: mode == .register ? "Пароль (необязательно)" : "Пароль",
                            text: $password,
                            contentType: mode == .register ? .newPassword : .password,
                            isSecure: true
                        )

                        PrimaryButton(title: mode == .login ? "Войти" : "Создать аккаунт", isLoading: appState.isBusy) {
                            Task {
                                if mode == .login {
                                    await appState.login(phone: e164Phone, password: password)
                                } else {
                                    await appState.register(name: trimmedName.isEmpty ? "Клиент Luma" : trimmedName, phone: e164Phone, password: password)
                                }
                            }
                        }
                        .disabled(!canSubmit || appState.isBusy)
                        .opacity(canSubmit ? 1 : 0.55)

                        Text(mode == .register ? "Без SMS-кода: указанный номер сохраняется как есть." : "Если пароль не задан — вход по номеру.")
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.warmGray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .beautyCard()

                    Button {
                        Task { await appState.continueAsGuest() }
                    } label: {
                        Text("Продолжить без регистрации")
                            .font(BeautyFont.headline)
                            .foregroundStyle(BeautyColor.limeInk)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(appState.isBusy)

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

struct PhoneCountry: Identifiable, Hashable {
    let id: String
    let flag: String
    let dialCode: String
    let minDigits: Int
    let maxDigits: Int
    let groups: [Int]

    static let defaults: [PhoneCountry] = [
        PhoneCountry(id: "RU", flag: "🇷🇺", dialCode: "+7", minDigits: 10, maxDigits: 10, groups: [3, 3, 2, 2]),
        PhoneCountry(id: "KZ", flag: "🇰🇿", dialCode: "+7", minDigits: 10, maxDigits: 10, groups: [3, 3, 2, 2]),
        PhoneCountry(id: "BY", flag: "🇧🇾", dialCode: "+375", minDigits: 9, maxDigits: 9, groups: [2, 3, 2, 2]),
        PhoneCountry(id: "AM", flag: "🇦🇲", dialCode: "+374", minDigits: 8, maxDigits: 8, groups: [2, 3, 3]),
        PhoneCountry(id: "AE", flag: "🇦🇪", dialCode: "+971", minDigits: 8, maxDigits: 9, groups: [2, 3, 4]),
        PhoneCountry(id: "QA", flag: "🇶🇦", dialCode: "+974", minDigits: 8, maxDigits: 8, groups: [4, 4]),
    ]

    func formatted(_ digits: String) -> String {
        var remaining = Array(digits.prefix(maxDigits))
        var parts: [String] = []
        for size in groups {
            guard !remaining.isEmpty else { break }
            let take = min(size, remaining.count)
            parts.append(String(remaining.prefix(take)))
            remaining.removeFirst(take)
        }
        if !remaining.isEmpty { parts.append(String(remaining)) }
        return parts.joined(separator: " ")
    }
}

private struct PhoneField: View {
    let title: String
    @Binding var country: PhoneCountry
    @Binding var nationalDigits: String

    private var displayBinding: Binding<String> {
        Binding(
            get: { country.formatted(nationalDigits) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                nationalDigits = String(digits.prefix(country.maxDigits))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.xs) {
            Text(title).font(BeautyFont.caption).foregroundStyle(BeautyColor.taupe)
            HStack(spacing: BeautySpacing.sm) {
                Menu {
                    ForEach(PhoneCountry.defaults) { item in
                        Button {
                            country = item
                            nationalDigits = String(nationalDigits.prefix(item.maxDigits))
                        } label: {
                            Text("\(item.flag)  \(item.id)  \(item.dialCode)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(country.flag)
                        Text(country.dialCode).font(BeautyFont.body).foregroundStyle(BeautyColor.ink)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(BeautyColor.taupe)
                    }
                    .padding(.horizontal, BeautySpacing.md)
                    .frame(height: 52)
                    .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("Код страны")

                TextField("000 000-00-00", text: displayBinding)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .padding(.horizontal, BeautySpacing.md)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous).stroke(BeautyColor.line.opacity(0.6), lineWidth: 1))
                    .accessibilityLabel("Номер телефона")
            }
        }
    }
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
