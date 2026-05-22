import SwiftUI

struct BeautyIDSetupView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = BeautyID(consent: true)
    @State private var step = 0
    @State private var exclusionText = ""
    @State private var selectedOwnedRoles: Set<RoutineRole> = []
    @State private var ownedChoice: OwnedRolesChoice?

    private let steps = ["Кожа", "Цели", "Образ", "Бюджет", "Стоп-лист", "Что есть"]

    var body: some View {
        ZStack {
            PremiumBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                        heroIllustration
                        content
                    }
                    .padding(BeautySpacing.md)
                }
                footer
            }
        }
        .onAppear {
            appState.startBeautyIDSetup()
            if let existing = appState.beautyID { draft = existing }
            selectedOwnedRoles = appState.ownedRoles
        }
    }

    private var heroIllustration: some View {
        Image("beauty_id_hero_illustration")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
            .accessibilityHidden(true)
    }

    private var heroHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return min(max(screenHeight * 0.21, 156), 218)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Создать Beauty ID")
                    .font(BeautyFont.title)
                    .foregroundStyle(BeautyColor.ink)
                Spacer()
                Button("Войти") { appState.wantsAuthDirectly = true }
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.taupe)
            }
            Text("Короткий профиль предпочтений для подбора косметики. Это не медицинская анкета.")
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
            HStack(spacing: BeautySpacing.xs) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? BeautyColor.lime : BeautyColor.line.opacity(0.55))
                        .frame(height: 6)
                }
            }
            .accessibilityLabel("Шаг \(step + 1) из \(steps.count)")
        }
        .padding(BeautySpacing.md)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            StepCard(title: "Расскажи про свою кожу", subtitle: "Примерно — идеальная точность не нужна. Это не медицинская анкета.") {
                Text("Тип кожи").font(BeautyFont.headline)
                ChipGrid(options: ["dry", "oily", "combination", "normal", "sensitive"], selected: draft.skinType.map { [$0] } ?? []) { value in draft.skinType = value }
                Text("Чувствительность").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                ChipGrid(options: ["low", "medium", "high"], selected: draft.sensitivity.map { [$0] } ?? []) { value in draft.sensitivity = value }
            }
        case 1:
            StepCard(title: "Что хочется улучшить?", subtitle: "Выбери, что для тебя важно — можно несколько.") {
                MultiChipGrid(options: ["dryness", "dullness", "texture", "redness", "pores", "shine", "longwear", "comfort"], selected: $draft.concerns)
            }
        case 2:
            StepCard(title: "Какой результат тебе нравится?", subtitle: "Так подборка будет ощущаться личной, а не случайной.") {
                Text("Желаемый финиш").font(BeautyFont.headline)
                MultiChipGrid(options: ["natural", "radiant", "matte", "satin", "glow"], selected: $draft.preferredFinish)
                Text("Макияж").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                MultiChipGrid(options: ["tone", "conceal", "blush", "lips", "longwear", "quick", "editorial"], selected: $draft.makeupPreferences)
            }
        case 3:
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                microRewardBanner
                StepCard(title: "Сколько готова вкладывать?", subtitle: "И деньгами, и временем — обе шкалы это нормально.") {
                    Text("Бюджет").font(BeautyFont.headline)
                    ChipGrid(options: ["entry", "mid", "premium", "luxury"], selected: [draft.budget]) { value in draft.budget = value }
                    Text("Сложность рутины").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                    ChipGrid(options: ["minimal", "balanced", "extended"], selected: [draft.routineComplexity]) { value in draft.routineComplexity = value }
                }
            }
        case 4:
            StepCard(title: "Чего лучше избегать?", subtitle: "Чтобы не предлагать тебе лишнего.") {
                Text("Отдушка").font(BeautyFont.headline)
                ChipGrid(options: ["avoid", "light_ok", "no_preference"], selected: draft.fragranceSensitivity.map { [$0] } ?? []) { value in draft.fragranceSensitivity = value }
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text("Ингредиенты, которые исключить")
                        .font(BeautyFont.headline)
                        .padding(.top, BeautySpacing.sm)
                    HStack {
                        TextField("например, alcohol denat", text: $exclusionText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Добавить") {
                            let clean = exclusionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            guard !clean.isEmpty else { return }
                            if !draft.ingredientExclusions.contains(clean) { draft.ingredientExclusions.append(clean) }
                            exclusionText = ""
                        }
                    }
                    .padding(BeautySpacing.md)
                    .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                    MultiChipGrid(options: draft.ingredientExclusions, selected: $draft.ingredientExclusions)
                }
            }
        default:
            StepCard(title: "Что у тебя уже есть?", subtitle: "Чтобы Luma не собирала тебя с нуля и не добавила лишний шаг.") {
                OwnedRolesStep(selectedRoles: $selectedOwnedRoles, ownedChoice: $ownedChoice)
            }
        }
    }

    /// Микро-награда: короткая «вспышка радости» в середине анкеты (на 4-м экране).
    /// Показывает, что ответы уже сложились в направление, — мотивирует дойти до конца.
    private var microRewardBanner: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(BeautyColor.limeInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Уже вижу твоё направление")
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                Text(microRewardText)
                    .font(BeautyFont.callout)
                    .foregroundStyle(BeautyColor.taupe)
            }
            Spacer(minLength: 0)
        }
        .padding(BeautySpacing.md)
        .background(BeautyColor.limeSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
    }

    private var microRewardText: String {
        var parts: [String] = []
        if let skin = draft.skinType { parts.append(skin.beautyLabel + " кожа") }
        if let finish = draft.preferredFinish.first { parts.append(finish.beautyLabel) }
        if draft.concerns.contains("dullness") { parts.append("сияние") }
        guard !parts.isEmpty else { return "Собираю твою подборку — осталось пара шагов." }
        return parts.prefix(3).joined(separator: " · ")
    }

    private var footer: some View {
        VStack(spacing: BeautySpacing.sm) {
            PrimaryButton(title: step == steps.count - 1 ? "Сохранить Beauty ID" : "Продолжить", isLoading: appState.isBusy) {
                if step < steps.count - 1 { withAnimation(.spring()) { step += 1 } }
                else {
                    guard draft.consent else {
                        appState.errorMessage = "Чтобы сохранить Beauty ID, нужно согласие. Фото при этом можно не добавлять."
                        return
                    }
                    Task { await appState.saveBeautyID(draft) }
                    switch ownedChoice {
                    case .notSure:
                        break
                    default:
                        appState.updateOwnedRoles(selectedOwnedRoles, source: "beauty_id_owned_step")
                    }
                }
            }
            if step == steps.count - 1 {
                Text("Сохраняя, ты соглашаешься на хранение Beauty ID для подбора. Изменить или удалить — в настройках.")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .multilineTextAlignment(.center)
            }
            HStack {
                if step > 0 {
                    Button("Назад") { withAnimation(.spring()) { step -= 1 } }
                }
                Spacer()
                Button("Пропустить необязательное") {
                    if step < steps.count - 1 { withAnimation(.spring()) { step += 1 } }
                }
            }
            .font(BeautyFont.callout.weight(.semibold))
            .foregroundStyle(BeautyColor.taupe)
        }
        .padding(BeautySpacing.md)
        .background(BeautyColor.ivory)
    }
}

private struct StepCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            SectionHeader(title: title, subtitle: subtitle)
            content
        }
        .beautyCard()
    }
}

private enum OwnedRolesChoice {
    case roles, nothing, notSure
}

private struct OwnedRolesStep: View {
    @Binding var selectedRoles: Set<RoutineRole>
    @Binding var ownedChoice: OwnedRolesChoice?

    private let roles: [RoutineRole] = [.cleanser, .moisturizer, .spf, .serum, .foundationTint, .mascara, .lip]
    private let columns = [GridItem(.adaptive(minimum: 126), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(roles, id: \.self) { role in
                    BeautyChip(title: role.displayTitle, isSelected: selectedRoles.contains(role)) {
                        ownedChoice = .roles
                        if selectedRoles.contains(role) {
                            selectedRoles.remove(role)
                        } else {
                            selectedRoles.insert(role)
                        }
                    }
                }
            }

            HStack(spacing: BeautySpacing.sm) {
                Button {
                    ownedChoice = .nothing
                    selectedRoles.removeAll()
                } label: {
                    ownedShortcutLabel("Ничего", isSelected: ownedChoice == .nothing)
                }
                .buttonStyle(.plain)

                Button {
                    ownedChoice = .notSure
                    selectedRoles.removeAll()
                } label: {
                    ownedShortcutLabel("Не знаю", isSelected: ownedChoice == .notSure)
                }
                .buttonStyle(.plain)
            }

            Text("Если вы отмечаете категорию, Luma хранит только роль, а не придумывает конкретный продукт.")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
        }
    }

    private func ownedShortcutLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(BeautyFont.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(BeautyColor.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isSelected ? BeautyColor.limeSoft.opacity(0.82) : BeautyColor.milk, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? BeautyColor.lime.opacity(0.70) : BeautyColor.line.opacity(0.70), lineWidth: 1))
    }
}

private struct ChipGrid: View {
    let options: [String]
    let selected: [String]
    let onSelect: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                BeautyChip(title: label(option), isSelected: selected.contains(option)) { onSelect(option) }
            }
        }
    }
}

private struct MultiChipGrid: View {
    let options: [String]
    @Binding var selected: [String]

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                BeautyChip(title: label(option), isSelected: selected.contains(option)) {
                    if selected.contains(option) { selected.removeAll { $0 == option } }
                    else { selected.append(option) }
                }
            }
        }
    }
}

private func label(_ value: String) -> String {
    [
        "dry": "сухая",
        "oily": "жирная",
        "combination": "комбинированная",
        "normal": "нормальная",
        "sensitive": "чувствительная",
        "low": "низкая",
        "medium": "средняя",
        "high": "высокая",
        "dryness": "сухость",
        "dullness": "тусклость",
        "texture": "рельеф",
        "redness": "покраснение",
        "pores": "поры",
        "shine": "блеск",
        "longwear": "стойкость",
        "comfort": "комфорт",
        "natural": "естественный",
        "radiant": "сияющий",
        "matte": "матовый",
        "satin": "сатиновый",
        "glow": "сияние",
        "tone": "тон",
        "conceal": "маскировка",
        "blush": "румянец",
        "lips": "губы",
        "quick": "быстро",
        "editorial": "акцентный образ",
        "avoid": "избегать",
        "light_ok": "лёгкая ок",
        "no_preference": "без разницы",
        "entry": "базовый",
        "mid": "средний",
        "premium": "премиум",
        "luxury": "люкс",
        "minimal": "минимальная",
        "balanced": "сбалансированная",
        "extended": "расширенная",
        "soft luxury": "мягкий люкс",
        "k-beauty": "K-beauty",
        "clean": "clean",
        "office": "офис",
        "evening": "вечер",
    ][value] ?? value.replacingOccurrences(of: "_", with: " ")
}
