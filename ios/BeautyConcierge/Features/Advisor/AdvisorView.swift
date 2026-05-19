import SwiftUI

struct AdvisorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var isRoutineExpanded = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                AdvisorHeader(
                    messageCount: appState.advisorMessages.count,
                    isBusy: appState.isBusy,
                    onClear: clearHistory
                )

                AdvisorQuickRefinementChips(actions: appState.quickActions) { action in
                    isComposerFocused = false
                    Task { await appState.sendAdvisorMessage(action) }
                }

                AdvisorMessageList(
                    messages: appState.advisorMessages,
                    isLoadingHistory: appState.isAdvisorHistoryLoading,
                    historyError: appState.advisorHistoryError,
                    isBusy: appState.isBusy,
                    bottomPadding: isComposerFocused ? 104 : (isRoutineExpanded ? 356 : 190),
                    productsBySku: productsBySku
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = false
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AdvisorBottomBar(
                draft: $draft,
                isComposerFocused: $isComposerFocused,
                isRoutineExpanded: $isRoutineExpanded,
                products: appState.activeSelection.recommendations,
                selectionNotice: appState.advisorSelectionNotice,
                actions: appState.advisorActions,
                canReplaceSelection: appState.advisorCanReplaceSelection,
                isBusy: appState.isBusy,
                onSend: sendDraft,
                onOpenRecommendations: { appState.selectedTab = .recommendations },
                onSave: { Task { await appState.saveCurrentRoutine() } },
                onMakeCheaper: { Task { await appState.sendAdvisorMessage("Сделай набор дешевле") } },
                onReplaceSelection: { appState.replaceSelectionWithLastAdvisorRecommendations() }
            )
            .environmentObject(appState)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await appState.loadAdvisorHistory(silent: true)
            if appState.advisorMessages.isEmpty {
                appState.advisorMessages.append(AdvisorMessage(role: "assistant", text: "Я рядом. Могу собрать утренний набор, сделать его дешевле, убрать отдушки или объяснить роль товара.", createdAt: Date()))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var productsBySku: [String: RecommendationProduct] {
        var result: [String: RecommendationProduct] = [:]
        (appState.recommendations.products + appState.recommendations.routine + appState.activeSelection.recommendations)
            .forEach { result[$0.sku] = $0 }
        return result
    }

    private func clearHistory() {
        isComposerFocused = false
        isRoutineExpanded = false
        Task { await appState.clearAdvisorHistory() }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isRoutineExpanded = false
        Task { await appState.sendAdvisorMessage(text) }
    }
}

private struct AdvisorHeader: View {
    let messageCount: Int
    let isBusy: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Советник")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(BeautyColor.ink)
                Text(statusText)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }

            Spacer()

            if messageCount > 0 {
                Button("Очистить", action: onClear)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(BeautyColor.milk.opacity(0.78), in: Capsule())
                    .overlay(Capsule().stroke(BeautyColor.line.opacity(0.62), lineWidth: 1))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить чат советника")
            }
        }
        .padding(.horizontal, BeautySpacing.md)
        .padding(.top, BeautySpacing.md)
        .padding(.bottom, BeautySpacing.sm)
        .background(
            BeautyColor.ivory
                .opacity(0.96)
                .shadow(.drop(color: .black.opacity(0.05), radius: 12, y: 4))
        )
    }

    private var statusText: String {
        if isBusy { return "Собираю ответ по Beauty ID и каталогу" }
        if messageCount == 0 { return "Задайте вопрос или уточните текущий набор" }
        return "\(messageCount) сообщений · текущий набор снизу"
    }
}

private struct AdvisorQuickRefinementChips: View {
    let actions: [String]
    let onSelect: (String) -> Void

    private var shownActions: [String] {
        let preferred = ["дешевле", "сияние", "без отдушек", "spf", "на лето"]
        let existing = actions.filter { preferred.contains($0.lowercased()) }
        return existing.isEmpty ? preferred : Array(existing.prefix(6))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shownActions, id: \.self) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        Text(action.advisorChipTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BeautyColor.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(BeautyColor.card.opacity(0.86), in: Capsule())
                            .overlay(Capsule().stroke(BeautyColor.line.opacity(0.56), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeautySpacing.md)
            .padding(.vertical, 10)
        }
        .background(BeautyColor.ivory.opacity(0.84))
    }
}

private struct AdvisorMessageList: View {
    let messages: [AdvisorMessage]
    let isLoadingHistory: Bool
    let historyError: String?
    let isBusy: Bool
    let bottomPadding: CGFloat
    let productsBySku: [String: RecommendationProduct]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BeautySpacing.sm) {
                    AdvisorConversationIntro()

                    if isLoadingHistory {
                        AdvisorInlineStatus(title: "Загружаю прошлый диалог", subtitle: "Секунду, поднимаю контекст.", systemImage: "clock")
                    }

                    if let historyError {
                        ErrorBanner(message: historyError)
                    }

                    ForEach(messages) { message in
                        AdvisorBubble(
                            message: message,
                            products: message.recommendedSkus.compactMap { productsBySku[$0] }
                        )
                            .id(message.id)
                    }

                    if isBusy {
                        AdvisorTypingView()
                            .id("advisor-typing")
                    }
                }
                .padding(.horizontal, BeautySpacing.md)
                .padding(.top, BeautySpacing.sm)
                .padding(.bottom, bottomPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isBusy) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.26)) {
                if isBusy {
                    proxy.scrollTo("advisor-typing", anchor: .bottom)
                } else if let last = messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

private struct AdvisorConversationIntro: View {
    var body: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeautyColor.limeInk)
                .frame(width: 30, height: 30)
                .background(BeautyColor.lime.opacity(0.95), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Персональный beauty-консьерж")
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                Text("Пишите как человеку: бюджет, сезон, текстура, SPF или ограничения. Набор всегда под рукой снизу.")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct AdvisorBottomBar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var draft: String
    var isComposerFocused: FocusState<Bool>.Binding
    @Binding var isRoutineExpanded: Bool
    let products: [RecommendationProduct]
    let selectionNotice: String?
    let actions: [AdvisorAction]
    let canReplaceSelection: Bool
    let isBusy: Bool
    let onSend: () -> Void
    let onOpenRecommendations: () -> Void
    let onSave: () -> Void
    let onMakeCheaper: () -> Void
    let onReplaceSelection: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            if !isComposerFocused.wrappedValue {
                AdvisorRoutineTray(
                    isExpanded: $isRoutineExpanded,
                    products: products,
                    selectionNotice: selectionNotice,
                    canReplaceSelection: canReplaceSelection,
                    onOpenRecommendations: onOpenRecommendations,
                    onSave: onSave,
                    onMakeCheaper: onMakeCheaper,
                    onReplaceSelection: onReplaceSelection
                )
                .environmentObject(appState)

                if !actions.isEmpty {
                    AdvisorActionCards(actions: actions) { action in
                        Task { await appState.applyAdvisorAction(action) }
                    }
                }
            }

            AdvisorComposer(
                draft: $draft,
                isFocused: isComposerFocused,
                isBusy: isBusy,
                onSend: onSend
            )
        }
        .padding(.horizontal, BeautySpacing.md)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [
                    BeautyColor.ivory.opacity(0.02),
                    BeautyColor.ivory.opacity(0.92),
                    BeautyColor.ivory
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct AdvisorRoutineTray: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isExpanded: Bool
    let products: [RecommendationProduct]
    let selectionNotice: String?
    let canReplaceSelection: Bool
    let onOpenRecommendations: () -> Void
    let onSave: () -> Void
    let onMakeCheaper: () -> Void
    let onReplaceSelection: () -> Void

    private var shownProducts: [RecommendationProduct] { Array(products.prefix(4)) }
    private var total: Int { shownProducts.reduce(0) { $0 + $1.priceValue } }
    private var averageMatch: Int {
        guard !shownProducts.isEmpty else { return 0 }
        return shownProducts.reduce(0) { $0 + $1.matchScore } / shownProducts.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: BeautySpacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Текущий набор")
                            .font(BeautyFont.callout.weight(.semibold))
                            .foregroundStyle(BeautyColor.ink)
                        Text(summaryText)
                            .font(BeautyFont.caption)
                            .foregroundStyle(BeautyColor.taupe)
                            .lineLimit(1)
                    }

                    Spacer()

                    if averageMatch > 0 {
                        Text("\(averageMatch)%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BeautyColor.limeInk)
                            .frame(width: 46, height: 30)
                            .background(BeautyColor.limeSoft, in: Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BeautyColor.taupe)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Свернуть текущий набор" : "Развернуть текущий набор")

            if let selectionNotice {
                Text(selectionNotice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)
                    .transition(.opacity)
            }

            if isExpanded {
                VStack(spacing: BeautySpacing.sm) {
                    Divider()
                        .overlay(BeautyColor.line.opacity(0.45))
                        .padding(.top, 12)

                    if shownProducts.isEmpty {
                        Text("После Beauty ID здесь появится текущий набор.")
                            .font(BeautyFont.callout)
                            .foregroundStyle(BeautyColor.taupe)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, BeautySpacing.sm)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(shownProducts.enumerated()), id: \.element.id) { index, product in
                                NavigationLink {
                                    ProductDetailView(product: product)
                                } label: {
                                    AdvisorRoutineProductRow(index: index + 1, product: product)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        AdvisorTrayAction(title: "Открыть", systemImage: "square.grid.2x2", isPrimary: false, action: onOpenRecommendations)
                        AdvisorTrayAction(title: "Сохранить", systemImage: "bookmark", isPrimary: true, action: onSave)
                        AdvisorTrayAction(title: "Дешевле", systemImage: "arrow.down.circle", isPrimary: false, action: onMakeCheaper)
                        if canReplaceSelection {
                            AdvisorTrayAction(title: "Заменить", systemImage: "arrow.triangle.2.circlepath", isPrimary: false, action: onReplaceSelection)
                        }
                    }
                    .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BeautyColor.line.opacity(0.48), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private var summaryText: String {
        guard !shownProducts.isEmpty else { return "Пока нет сохранённых шагов" }
        return "\(shownProducts.count.stepWord) · \(total.rub)"
    }
}

private struct AdvisorActionCards: View {
    let actions: [AdvisorAction]
    let onApply: (AdvisorAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions.prefix(4)) { action in
                    Button {
                        onApply(action)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: action))
                                .font(.system(size: 13, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(action.subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(BeautyColor.taupe)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(BeautyColor.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(BeautyColor.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BeautyColor.line.opacity(0.48), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func icon(for action: AdvisorAction) -> String {
        switch action.type {
        case "add_products", "add_products_to_selection": return "plus.circle"
        case "add_current_routine_to_shelf", "add_product_to_shelf", "mark_product_wanted", "mark_product_owned", "mark_product_buy_later", "mark_product_did_not_fit": return "tray.full"
        case "add_products_to_cart", "add_current_routine_to_cart", "add_selection_to_cart", "move_selection_to_cart": return "bag.badge.plus"
        case "clear_cart", "remove_products_from_cart": return "bag.badge.minus"
        case "clear_selection", "remove_products_from_selection": return "minus.circle"
        case "suggest_replace_product", "replace_product", "replace_product_confirmed": return "arrow.triangle.2.circlepath"
        case "show_alternatives": return "square.stack.3d.up"
        case "save_routine_suggestion", "save_selection_as_routine", "save_current_routine": return "bookmark"
        default: return "sparkles"
        }
    }
}

private struct AdvisorRoutineProductRow: View {
    @EnvironmentObject private var appState: AppState
    let index: Int
    let product: RecommendationProduct

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(BeautyFont.caption.weight(.bold))
                .foregroundStyle(BeautyColor.limeInk)
                .frame(width: 24, height: 24)
                .background(BeautyColor.limeSoft, in: Circle())

            CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                ProductVisual(sku: product.sku, compact: true)
            }
            .frame(width: 42, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.routineStep.beautyLabel)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(product.name)
                    .font(BeautyFont.caption.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .lineLimit(1)
                Text(product.brand)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(product.priceValue.rub)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.ink)
                Text("\(product.matchScore)%")
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .padding(8)
        .background(BeautyColor.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AdvisorTrayAction: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isPrimary ? BeautyColor.limeInk : BeautyColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isPrimary ? BeautyColor.lime : BeautyColor.milk.opacity(0.82), in: Capsule())
                .overlay(Capsule().stroke(isPrimary ? Color.clear : BeautyColor.line.opacity(0.58), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct AdvisorComposer: View {
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let isBusy: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: BeautySpacing.sm) {
            TextField("Спросите про SPF, бюджет или текстуру", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused(isFocused)
                .font(BeautyFont.callout)
                .padding(.horizontal, BeautySpacing.md)
                .padding(.vertical, 13)
                .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(BeautyColor.line.opacity(0.54), lineWidth: 1))
                .submitLabel(.send)
                .onSubmit {
                    if canSend { onSend() }
                }

            Button(action: onSend) {
                Image(systemName: isBusy ? "hourglass" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 46, height: 46)
                    .background(canSend ? BeautyColor.lime : BeautyColor.line.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Отправить сообщение советнику")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct AdvisorInlineStatus: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: BeautySpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(BeautyColor.taupe)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                Text(subtitle)
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
            Spacer()
        }
        .padding(BeautySpacing.md)
        .background(BeautyColor.card.opacity(0.72), in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
    }
}

private struct AdvisorTypingView: View {
    var body: some View {
        HStack(alignment: .top, spacing: BeautySpacing.sm) {
            ProgressView().tint(BeautyColor.lime)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Luma подбирает текстуры")
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                Text("Сверяю Beauty ID и каталог.")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
            Spacer()
        }
        .padding(BeautySpacing.md)
        .background(BeautyColor.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
    }
}

private extension String {
    var advisorChipTitle: String {
        [
            "дешевле": "Дешевле",
            "сияние": "Больше сияния",
            "без отдушек": "Без отдушки",
            "spf": "SPF",
            "на лето": "На лето",
            "быстро утром": "Быстро утром",
            "премиальнее": "Премиальнее",
            "легче текстура": "Легче текстура",
            "для чувствительной кожи": "Для чувствительной кожи",
        ][lowercased()] ?? prefix(1).uppercased() + String(dropFirst())
    }
}

private struct AdvisorBubble: View {
    @EnvironmentObject private var appState: AppState
    let message: AdvisorMessage
    let products: [RecommendationProduct]
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 54) }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(BeautyFont.body)
                    .foregroundStyle(BeautyColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !isUser && !products.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(products.prefix(3)) { product in
                            AdvisorMiniProductCard(product: product)
                                .environmentObject(appState)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(bubbleStroke, lineWidth: 1))
            .accessibilityLabel(isUser ? "Вы: \(message.text)" : "Советник: \(message.text)")

            if !isUser { Spacer(minLength: 34) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubbleFill: Color {
        isUser ? BeautyColor.limeSoft.opacity(0.72) : BeautyColor.card.opacity(0.82)
    }

    private var bubbleStroke: Color {
        isUser ? BeautyColor.lime.opacity(0.28) : BeautyColor.line.opacity(0.48)
    }
}

private struct AdvisorMiniProductCard: View {
    @EnvironmentObject private var appState: AppState
    let product: RecommendationProduct
    private var role: RoutineRole { RoutineRole.from(product: product) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CachedRemoteImage(url: appState.absoluteURL(for: product.preferredImagePath)) {
                    ProductVisual(sku: product.sku, compact: true)
                }
                .frame(width: 54, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.displayTitle)
                        .font(BeautyFont.caption2.weight(.semibold))
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(1)
                    Text(product.brand)
                        .font(BeautyFont.caption.weight(.semibold))
                        .foregroundStyle(BeautyColor.ink)
                        .lineLimit(1)
                    Text(product.name)
                        .font(BeautyFont.caption)
                        .foregroundStyle(BeautyColor.taupe)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(product.priceValue.rub)
                        Text("\(product.matchScore)% совп.")
                    }
                    .font(BeautyFont.caption2.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                }

            Spacer(minLength: 4)
        }
        .padding(8)
        .background(BeautyColor.milk.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 7)], spacing: 7) {
                miniAction("Хочу") { appState.markProductWanted(product, source: "advisor_card") }
                miniAction("Есть") { appState.markProductOwned(product, source: "advisor_card") }
                miniAction("Купить") { Task { await appState.addToCart(product) } }
                miniAction("Заменить") { appState.markProductNeedsReplacement(product, reason: .similarButDifferent, source: "advisor_card") }
            }
        }
    }

    private func miniAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BeautyColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(BeautyColor.card.opacity(0.78), in: Capsule())
                .overlay(Capsule().stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
        }
        .frame(minWidth: 0)
        .buttonStyle(.plain)
    }
}
