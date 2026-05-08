import SwiftUI

struct AdvisorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            PremiumBackground()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                            introCard
                            refineChips
                            routineBuilder
                            whyThisWorksCard
                            messageList
                        }
                        .padding(BeautySpacing.md)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isComposerFocused = false
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: appState.advisorMessages.count) { _, _ in
                        if let last = appState.advisorMessages.last?.id {
                            withAnimation(.easeOut) { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                composer
            }
        }
        .navigationTitle("Советник")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !appState.advisorMessages.isEmpty {
                    Button("Очистить") {
                        isComposerFocused = false
                        Task { await appState.clearAdvisorHistory() }
                    }
                    .font(BeautyFont.caption)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    isComposerFocused = false
                }
                .font(BeautyFont.callout.weight(.semibold))
            }
        }
        .task {
            await appState.loadAdvisorHistory(silent: true)
            if appState.advisorMessages.isEmpty {
                appState.advisorMessages.append(AdvisorMessage(role: "assistant", text: "Я рядом. Могу собрать утреннюю рутину, сделать подборку дешевле, убрать отдушки или объяснить, почему конкретный продукт подходит.", createdAt: Date()))
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text("Beauty-консьерж")
                        .font(BeautyFont.title2)
                    Text("Знает каталог, отвечает кратко и не ставит диагнозы.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
                Spacer()
                Image("beauty_id_abstract")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
                    .accessibilityHidden(true)
            }
            if let hero = appState.recommendations.hero {
                ProductMiniRow(product: hero)
            }
        }
        .beautyCard()
    }

    private var refineChips: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            Text("Быстро уточнить")
                .font(BeautyFont.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BeautySpacing.sm) {
                    ForEach(appState.quickActions, id: \.self) { chip in
                        BeautyChip(title: chip) {
                            Task { await appState.sendAdvisorMessage(chip) }
                        }
                    }
                }
                .padding(.horizontal, BeautySpacing.md)
            }
            .padding(.horizontal, -BeautySpacing.md)
        }
    }

    private var routineBuilder: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                SectionHeader(title: "Сборка рутины", subtitle: "Текущий набор с учётом каталога")
                Spacer()
                Button("Сохранить") { Task { await appState.saveCurrentRoutine() } }
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(BeautyColor.limeSoft, in: Capsule())
            }
            VStack(spacing: BeautySpacing.sm) {
                ForEach(appState.recommendations.routine.prefix(5)) { product in
                    NavigationLink { ProductDetailView(product: product) } label: {
                        ProductMiniRow(product: product)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .beautyCard()
    }

    private var whyThisWorksCard: some View {
        Group {
            if !appState.advisorWhyThisWorks.isEmpty || !appState.advisorRoutineSteps.isEmpty || appState.advisorProviderNote != nil {
                VStack(alignment: .leading, spacing: BeautySpacing.md) {
                    SectionHeader(title: "Почему это подходит", subtitle: "Beauty-логика по каталогу, не медицинская рекомендация.")
                    if let note = appState.advisorProviderNote {
                        Text(note)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.taupe)
                            .padding(10)
                            .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.sm, style: .continuous))
                    }
                    ForEach(appState.advisorWhyThisWorks, id: \.self) { item in
                        Label(item, systemImage: "sparkle")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.ink)
                    }
                    if !appState.advisorRoutineSteps.isEmpty {
                        Divider().overlay(BeautyColor.line)
                        ForEach(appState.advisorRoutineSteps, id: \.self) { step in
                            Text(step)
                                .font(BeautyFont.caption)
                                .foregroundStyle(BeautyColor.taupe)
                        }
                    }
                }
                .beautyCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Объяснение советника")
            }
        }
    }

    private var messageList: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            if appState.isAdvisorHistoryLoading {
                HStack(spacing: BeautySpacing.sm) {
                    ProgressView().tint(BeautyColor.lime)
                    Text("Загружаю прошлый диалог")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
                .padding(.vertical, BeautySpacing.sm)
            }
            if let historyError = appState.advisorHistoryError {
                ErrorBanner(message: historyError)
            }
            ForEach(appState.advisorMessages) { message in
                AdvisorBubble(message: message)
                    .id(message.id)
            }
            if appState.isBusy {
                HStack(spacing: BeautySpacing.sm) {
                    ProgressView().tint(BeautyColor.lime)
                    Text("Советник уточняет рутину")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
                .padding(.vertical, BeautySpacing.sm)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: BeautySpacing.sm) {
            TextField("Попросите сияние, SPF, дешевле...", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .focused($isComposerFocused)
                .padding(.horizontal, BeautySpacing.md)
                .padding(.vertical, 12)
                .background(BeautyColor.milk, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
            Button {
                let text = draft
                draft = ""
                Task { await appState.sendAdvisorMessage(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 44, height: 44)
                    .background(BeautyColor.lime, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Отправить сообщение советнику")
        }
        .padding(BeautySpacing.md)
        .background(BeautyColor.ivory.shadow(.drop(color: .black.opacity(0.08), radius: 10, y: -3)))
    }
}

private struct AdvisorBubble: View {
    let message: AdvisorMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }
            Text(message.text)
                .font(BeautyFont.body)
                .foregroundStyle(isUser ? BeautyColor.ink : BeautyColor.ink)
                .padding(BeautySpacing.md)
                .background(isUser ? BeautyColor.limeSoft : BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(isUser ? 0.0 : 0.5), lineWidth: 1))
            if !isUser { Spacer(minLength: 44) }
        }
    }
}
