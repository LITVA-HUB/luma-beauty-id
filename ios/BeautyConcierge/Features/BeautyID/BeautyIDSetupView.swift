import SwiftUI

struct BeautyIDSetupView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = BeautyID(consent: true)
    @State private var step = 0
    @State private var exclusionText = ""

    private let steps = ["Ощущения", "Предпочтения", "Бюджет", "Согласие"]

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
            Text("Создать Beauty ID")
                .font(BeautyFont.title)
                .foregroundStyle(BeautyColor.ink)
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
            StepCard(title: "Как обычно ощущается кожа?", subtitle: "Выберите ближайший вариант. Идеальная точность не нужна.") {
                ChipGrid(options: ["dry", "oily", "combination", "normal", "sensitive"], selected: draft.skinType.map { [$0] } ?? []) { value in draft.skinType = value }
                Divider().padding(.vertical, BeautySpacing.sm)
                Text("Уровень чувствительности").font(BeautyFont.headline)
                ChipGrid(options: ["low", "medium", "high"], selected: draft.sensitivity.map { [$0] } ?? []) { value in draft.sensitivity = value }
                Text("Фокус подбора")
                    .font(BeautyFont.headline)
                    .padding(.top, BeautySpacing.sm)
                MultiChipGrid(options: ["dryness", "dullness", "texture", "redness", "pores", "shine", "longwear", "comfort"], selected: $draft.concerns)
            }
        case 1:
            StepCard(title: "Текстура, финиш и настроение макияжа", subtitle: "Так рекомендации ощущаются личными, а не случайными.") {
                Text("Желаемый финиш").font(BeautyFont.headline)
                MultiChipGrid(options: ["natural", "radiant", "matte", "satin", "glow"], selected: $draft.preferredFinish)
                Text("Предпочтения в макияже").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                MultiChipGrid(options: ["tone", "conceal", "blush", "lips", "longwear", "quick", "editorial"], selected: $draft.makeupPreferences)
                Text("Отдушка").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                ChipGrid(options: ["avoid", "light_ok", "no_preference"], selected: draft.fragranceSensitivity.map { [$0] } ?? []) { value in draft.fragranceSensitivity = value }
            }
        case 2:
            StepCard(title: "Бюджет и формат рутины", subtitle: "Сохраняем премиальное ощущение, но не игнорируем цену.") {
                Text("Бюджет").font(BeautyFont.headline)
                ChipGrid(options: ["entry", "mid", "premium", "luxury"], selected: [draft.budget]) { value in draft.budget = value }
                Text("Сложность рутины").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                ChipGrid(options: ["minimal", "balanced", "extended"], selected: [draft.routineComplexity]) { value in draft.routineComplexity = value }
                Text("Стиль").font(BeautyFont.headline).padding(.top, BeautySpacing.sm)
                MultiChipGrid(options: ["soft luxury", "k-beauty", "clean", "glow", "office", "evening", "minimal"], selected: $draft.styleTags)
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text("Ингредиенты, которые исключить")
                        .font(BeautyFont.headline)
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
            StepCard(title: "Приватность и согласие", subtitle: "Beauty ID нужен для подбора продуктов, его можно изменить позже.") {
                VStack(alignment: .leading, spacing: BeautySpacing.md) {
                    Toggle(isOn: $draft.consent) {
                        Text("Сохранить мой Beauty ID для рекомендаций")
                            .font(BeautyFont.headline)
                    }
                    .tint(BeautyColor.lime)
                    Text("Luma Beauty ID не ставит диагнозы. Фото необязательно, а исходные снимки не сохраняются по умолчанию.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                    Text("Предпочтения можно обновить, а экспорт или удаление данных запросить в настройках.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
            }
        }
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
                }
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
