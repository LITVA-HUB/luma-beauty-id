import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case home, advisor, recommendations, cart, profile
    }

    @Published var isLaunching = true
    @Published var hasSeenOnboarding: Bool
    @Published var account: Account?
    @Published var beautyID: BeautyID?
    @Published var recommendations: RecommendationsResponse = LocalFallbackCatalog.response()
    @Published var cart: CartResponse = .empty
    @Published var scanResult: ScanResult?
    @Published var scanStatuses: [ScanStatus] = []
    @Published var advisorMessages: [AdvisorMessage] = []
    @Published var isAdvisorHistoryLoading = false
    @Published var advisorHistoryError: String?
    @Published var quickActions: [String] = ["дешевле", "сияние", "без отдушек", "SPF", "быстро утром"]
    @Published var advisorWhyThisWorks: [String] = []
    @Published var advisorRoutineSteps: [String] = []
    @Published var advisorProviderNote: String?
    @Published var selectedTab: Tab = .home
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var usesLocalFallback = false
    @Published var checkoutMessage: String?
    @Published var privacyMessage: String?
    @Published var feedbackMessage: String?
    @Published var savedProducts: Set<String>
    @Published var savedRoutineSkus: [String]
    @Published var appTheme: AppTheme

    let environment: AppEnvironment
    let api: APIClient
    private let keychain: KeychainStore
    private let analytics: AnalyticsService
    private let crashReporter: CrashReporter

    private enum Keys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let onboarding = "hasSeenOnboarding"
        static let savedProducts = "savedProducts"
        static let savedRoutineSkus = "savedRoutineSkus"
        static let appTheme = "appTheme"
    }

    init(
        environment: AppEnvironment = .current,
        keychain: KeychainStore = .shared,
        analytics: AnalyticsService = NoOpAnalyticsService(),
        crashReporter: CrashReporter = NoOpCrashReporter()
    ) {
        self.environment = environment
        self.api = APIClient(baseURL: environment.baseURL)
        self.keychain = keychain
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: Keys.onboarding)
        self.savedProducts = Set(UserDefaults.standard.stringArray(forKey: Keys.savedProducts) ?? [])
        self.savedRoutineSkus = UserDefaults.standard.stringArray(forKey: Keys.savedRoutineSkus) ?? []
        self.appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.appTheme) ?? "") ?? .system
        if !hasSeenOnboarding { analytics.track(.onboardingStarted, properties: ["runtime": environment.runtime.rawValue]) }
    }

    func boot() async {
        try? await Task.sleep(nanoseconds: 420_000_000)
        if environment.configurationError != nil {
            isLaunching = false
            return
        }
        guard let access = keychain.read(Keys.accessToken) else {
            isLaunching = false
            return
        }
        api.accessToken = access
        do {
            try await loadProfileAndSessionData()
        } catch {
            var didRefresh = false
            if let refresh = keychain.read(Keys.refreshToken) {
                do {
                    try await refreshSession(refreshToken: refresh)
                    didRefresh = true
                } catch {
                    didRefresh = false
                }
            }
            if didRefresh { try? await loadProfileAndSessionData() }
            else { clearSession() }
        }
        isLaunching = false
    }

    private func loadProfileAndSessionData() async throws {
        let profile: ProfileResponse = try await api.get("/v1/profile/me")
        account = profile.account
        crashReporter.setUserContext(profile.account.accountId)
        beautyID = profile.beautyId?.beautyId
        applySavedRoutine(profile.savedRoutines?.first)
        await loadCart(silent: true)
        await loadAdvisorHistory(silent: true)
        await loadSavedRoutine(silent: true)
        await loadRecommendations(focus: nil, silent: true)
    }

    private func refreshSession(refreshToken: String) async throws {
        let response: AuthSession = try await api.post("/v1/auth/refresh", body: TokenRefreshRequest(refreshToken: refreshToken))
        try persist(session: response)
    }

    func finishOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Keys.onboarding)
        analytics.track(.onboardingCompleted, properties: ["runtime": environment.runtime.rawValue])
        Haptics.success()
    }

    func register(name: String, email: String, password: String) async {
        analytics.track(.authStarted, properties: ["mode": "register"])
        await authTask {
            let response: AuthSession = try await api.post("/v1/auth/register", body: RegisterRequest(name: name, email: email, password: password, consent: true))
            try persist(session: response)
            analytics.track(.authCompleted, properties: ["mode": "register", "provider": response.provider ?? "unknown"])
        }
    }

    func login(email: String, password: String) async {
        analytics.track(.authStarted, properties: ["mode": "login"])
        await authTask {
            let response: AuthSession = try await api.post("/v1/auth/login", body: LoginRequest(email: email, password: password))
            try persist(session: response)
            analytics.track(.authCompleted, properties: ["mode": "login", "provider": response.provider ?? "unknown"])
        }
    }

    func continueInDevelopmentMode() async {
        guard environment.canShowDevLogin else {
            errorMessage = "Вход недоступен в этой сборке."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: AuthSession = try await api.post("/v1/auth/dev-login", body: EmptyBody())
            try persist(session: response)
            usesLocalFallback = false
            await loadCart(silent: true)
            await loadAdvisorHistory(silent: true)
            await loadRecommendations(focus: nil, silent: true)
            Haptics.success()
        } catch {
            guard environment.runtime == .development else {
                errorMessage = userFacing(error)
                crashReporter.record(error: error, context: ["flow": "dev_login"])
                return
            }
            usesLocalFallback = true
            account = Account(accountId: "local-development", name: "Клиент Luma", email: "development@example.com", createdAt: Date())
            beautyID = BeautyID(skinType: "combination", concerns: ["dryness"], sensitivity: "medium", fragranceSensitivity: "avoid", preferredFinish: ["radiant"], makeupPreferences: ["tone"], budget: "mid", ingredientExclusions: [], routineComplexity: "balanced", styleTags: ["soft luxury"], consent: true, updatedAt: Date())
            recommendations = LocalFallbackCatalog.response()
            cart = .empty
            Haptics.warning()
        }
    }

    private func authTask(_ operation: () async throws -> Void) async {
        if let configurationError = environment.configurationError {
            errorMessage = configurationError
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            await loadCart(silent: true)
            await loadAdvisorHistory(silent: true)
            await loadSavedRoutine(silent: true)
            await loadRecommendations(focus: nil, silent: true)
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "auth"])
            Haptics.warning()
        }
    }

    private func persist(session: AuthSession) throws {
        account = session.account
        api.accessToken = session.accessToken
        usesLocalFallback = false
        try keychain.save(session.accessToken, for: Keys.accessToken)
        try keychain.save(session.refreshToken, for: Keys.refreshToken)
    }

    func logout() {
        let refresh = keychain.read(Keys.refreshToken)
        if api.accessToken != nil {
            Task {
                let _: EmptyResponse? = try? await api.post("/v1/auth/logout", body: LogoutRequest(refreshToken: refresh))
            }
        }
        clearSession()
        Haptics.tap()
    }

    private func clearSession() {
        keychain.delete(Keys.accessToken)
        keychain.delete(Keys.refreshToken)
        api.accessToken = nil
        account = nil
        beautyID = nil
        advisorMessages = []
        cart = .empty
        scanResult = nil
        savedRoutineSkus = []
        UserDefaults.standard.removeObject(forKey: Keys.savedRoutineSkus)
        advisorHistoryError = nil
        isAdvisorHistoryLoading = false
        selectedTab = .home
        usesLocalFallback = false
        crashReporter.setUserContext(nil)
    }

    func startBeautyIDSetup() {
        analytics.track(.beautyIDStarted, properties: ["runtime": environment.runtime.rawValue])
    }

    func saveBeautyID(_ value: BeautyID) async {
        analytics.track(.beautyIDCompleted, properties: ["complexity": value.routineComplexity])
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else {
                errorMessage = "Beauty ID не удалось сохранить, потому что API недоступен."
                return
            }
            beautyID = value
            recommendations = LocalFallbackCatalog.response()
            Haptics.success()
            return
        }
        do {
            let response: BeautyIDResponse = try await api.put("/v1/beauty-id", body: value)
            beautyID = response.beautyId
            await loadRecommendations(focus: nil, silent: true)
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "beauty_id_save"])
            Haptics.warning()
        }
    }

    func loadRecommendations(focus: String?, silent: Bool = false) async {
        if !silent { isBusy = true }
        defer { if !silent { isBusy = false } }
        let body = RecommendationsRequest(beautyId: beautyID, focus: focus, limit: 16, filters: [:])
        guard !usesLocalFallback, api.accessToken != nil else {
            if environment.runtime == .development { recommendations = LocalFallbackCatalog.response(focus: focus) }
            return
        }
        do {
            let response: RecommendationsResponse = try await api.post("/v1/recommendations", body: body)
            recommendations = response
            analytics.track(.recommendationViewed, properties: ["focus": focus ?? "default", "count": "\(response.products.count)"])
        } catch {
            if environment.runtime == .development {
                recommendations = LocalFallbackCatalog.response(focus: focus)
                usesLocalFallback = true
                if !silent { errorMessage = "Не удалось обновить подборку. Показана сохранённая безопасная подборка." }
            } else if !silent {
                errorMessage = userFacing(error)
            }
            crashReporter.record(error: error, context: ["flow": "recommendations"])
        }
    }

    func performScan(imageData: Data?, source: String) async {
        analytics.track(.scanStarted, properties: ["source": source, "has_photo": imageData == nil ? "false" : "true"])
        isBusy = true
        errorMessage = nil
        scanStatuses = [
            ScanStatus(key: "preparing", label: "Подготовка", isDone: false),
            ScanStatus(key: "uploading", label: imageData == nil ? "Фото пропущено" : "Загрузка", isDone: false),
            ScanStatus(key: "analyzing", label: "Косметический контекст", isDone: false),
            ScanStatus(key: "matching", label: "Подбор", isDone: false),
            ScanStatus(key: "ready", label: "Готово", isDone: false)
        ]

        for index in scanStatuses.indices {
            scanStatuses[index] = ScanStatus(key: scanStatuses[index].key, label: scanStatuses[index].label, isDone: true)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        defer { isBusy = false }
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else {
                errorMessage = "Скан недоступен, потому что API-сессия не активна."
                return
            }
            let response = LocalFallbackCatalog.response(focus: "рутина после анкеты")
            scanResult = ScanResult(scanId: UUID().uuidString, summary: "Beauty ID собран. Фото не отправлялось.", signals: beautyID?.concerns ?? [], limitations: ["Фото не обрабатывалось."], statuses: scanStatuses, recommendations: response, retentionPolicy: "Фото не загружалось.", deletionUrl: nil, disclaimer: "Косметический подбор, не диагностика кожи.")
            recommendations = response
            selectedTab = .advisor
            Haptics.success()
            return
        }
        do {
            let result = try await api.uploadPhotoScan(imageData: imageData, source: source, beautyID: beautyID)
            scanResult = result
            recommendations = result.recommendations
            selectedTab = .advisor
            analytics.track(.scanCompleted, properties: ["source": source, "status": "ready"])
            Haptics.success()
        } catch is CancellationError {
            errorMessage = "Загрузка отменена."
        } catch {
            if environment.runtime == .development {
                let response = LocalFallbackCatalog.response(focus: "рутина после анкеты")
                scanResult = ScanResult(scanId: UUID().uuidString, summary: "Не удалось обновить фото-контекст. Показана подборка по Beauty ID.", signals: beautyID?.concerns ?? [], limitations: ["Анализ фото не выполнялся."], statuses: scanStatuses, recommendations: response, retentionPolicy: "Фото не загружалось.", deletionUrl: nil, disclaimer: "Косметический подбор, не диагностика кожи.")
                recommendations = response
                usesLocalFallback = true
                selectedTab = .advisor
            }
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "scan"])
        }
    }

    func sendAdvisorMessage(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if looksLikeInternalPrompt(clean) {
            #if DEBUG
            assertionFailure("Internal prompt-looking text must not be rendered or sent as a user message.")
            #endif
            advisorHistoryError = "Служебный текст не отправлен в чат."
            return
        }
        let userMessage = AdvisorMessage(role: "user", text: clean, createdAt: Date())
        advisorMessages.append(userMessage)
        analytics.track(.advisorMessageSent, properties: ["length_bucket": clean.count < 40 ? "short" : "long"])
        isBusy = true
        defer { isBusy = false }
        let currentSkus = recommendations.products.map(\.sku)
        guard !usesLocalFallback, api.accessToken != nil else {
            if environment.runtime == .development { appendFallbackAdvisorReply(for: clean) }
            else { errorMessage = "Советник недоступен, потому что API-сессия не активна." }
            return
        }
        do {
            let request = AdvisorRequest(message: clean, beautyId: beautyID, currentSkus: currentSkus)
            let response: AdvisorResponse = try await api.post("/v1/advisor/message", body: request)
            if !looksLikeInternalPrompt(response.answer) {
                advisorMessages.append(AdvisorMessage(role: "assistant", text: response.answer, createdAt: Date()))
            } else {
                advisorHistoryError = "Ответ советника скрыт: сервер вернул служебный текст."
            }
            quickActions = response.quickActions
            advisorWhyThisWorks = response.whyThisWorks.map { [$0] } ?? []
            advisorRoutineSteps = response.routineSteps
            advisorProviderNote = response.fallbackReason != nil || response.safetyNote == "advisor_provider_fallback" ? "Сейчас не удалось получить обновлённый ответ. Показала безопасную подборку по каталогу." : nil
            if !response.recommendations.isEmpty {
                recommendations = RecommendationsResponse(hero: response.recommendations.first, routine: response.recommendations, products: response.recommendations, explanation: "Советник уточнил подборку по вашему сообщению.", disclaimer: "Косметический подбор, не медицинская рекомендация.", generatedAt: Date())
            }
            advisorHistoryError = nil
        } catch {
            if environment.runtime == .development {
                appendFallbackAdvisorReply(for: clean)
                usesLocalFallback = true
            } else {
                errorMessage = userFacing(error)
            }
            advisorHistoryError = "Не удалось сохранить ответ советника на сервере."
            crashReporter.record(error: error, context: ["flow": "advisor"])
        }
    }

    func loadAdvisorHistory(silent: Bool = false) async {
        guard !usesLocalFallback, api.accessToken != nil else { return }
        if !silent { isAdvisorHistoryLoading = true }
        defer { if !silent { isAdvisorHistoryLoading = false } }
        do {
            let response: AdvisorHistoryResponse = try await api.get("/v1/advisor/history")
            advisorMessages = response.messages.filter { !looksLikeInternalPrompt($0.text) }
            advisorHistoryError = nil
        } catch {
            advisorHistoryError = "Историю советника не удалось загрузить."
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "advisor_history"])
        }
    }

    func clearAdvisorHistory() async {
        guard !usesLocalFallback, api.accessToken != nil else {
            advisorMessages = []
            return
        }
        do {
            let response: AdvisorHistoryResponse = try await api.delete("/v1/advisor/history")
            advisorMessages = response.messages.filter { !looksLikeInternalPrompt($0.text) }
            advisorHistoryError = nil
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "advisor_history_clear"])
            Haptics.warning()
        }
    }

    func setTheme(_ theme: AppTheme) {
        appTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Keys.appTheme)
        Haptics.tap()
    }

    private func looksLikeInternalPrompt(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "контекст предыдущего диалога",
            "новое сообщение пользователя",
            "ответь именно",
            "allowed_products",
            "internal context",
            "developer message",
            "prompt_version"
        ].contains { lower.contains($0) }
    }

    private func appendFallbackAdvisorReply(for message: String) {
        let lower = message.lowercased()
        let answer: String
        if lower.contains("диагноз") || lower.contains("розаце") || lower.contains("леч") {
            answer = "Я не могу ставить диагнозы или назначать лечение. Могу помочь только с косметической рутиной по ощущениям, текстурам и предпочтениям; при сильном раздражении лучше обратиться к специалисту."
        } else if lower.contains("spf") {
            answer = "Я бы держала SPF финальным утренним шагом. Это не медицинский совет, а аккуратная beauty-привычка: лёгкая текстура, затем тон или тинт при желании."
        } else if let hero = recommendations.hero {
            answer = "Я бы оставила в центре \(hero.brand) \(hero.name): \(hero.reason). Могу сделать набор дешевле, мягче по отдушкам или более сияющим."
        } else {
            answer = "Я рядом. Уточните бюджет, финиш и есть ли ингредиенты, которые лучше исключить — соберу короткий набор без лишнего."
        }
        advisorMessages.append(AdvisorMessage(role: "assistant", text: answer, createdAt: Date()))
        advisorWhyThisWorks = recommendations.products.prefix(3).map { $0.reason }
        advisorRoutineSteps = recommendations.routine.prefix(5).map { $0.routineStep }
    }

    func toggleSaveProduct(_ product: RecommendationProduct) {
        if savedProducts.contains(product.sku) { savedProducts.remove(product.sku) }
        else { savedProducts.insert(product.sku) }
        UserDefaults.standard.set(Array(savedProducts), forKey: Keys.savedProducts)
        Haptics.tap()
    }

    func loadSavedRoutine(silent: Bool = false) async {
        guard !usesLocalFallback, api.accessToken != nil else { return }
        do {
            let response: SavedRoutineResponse = try await api.get("/v1/routines/current")
            applySavedRoutine(response)
        } catch {
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "routine_load"])
        }
    }

    func saveCurrentRoutine() async {
        let skus = recommendations.routine.map(\.sku)
        await saveRoutine(skus: skus, successMessage: "Подборка сохранена.")
    }

    private func saveRoutine(skus: [String], successMessage: String) async {
        let cleanSkus = Array(NSOrderedSet(array: skus).compactMap { $0 as? String }).filter { !$0.isEmpty }
        guard !cleanSkus.isEmpty else {
            checkoutMessage = "Сначала добавьте продукты в подборку."
            return
        }
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else {
                errorMessage = "Не удалось сохранить подборку. Войдите в аккаунт и попробуйте снова."
                return
            }
            savedRoutineSkus = cleanSkus
            UserDefaults.standard.set(cleanSkus, forKey: Keys.savedRoutineSkus)
            checkoutMessage = successMessage
            Haptics.success()
            return
        }
        do {
            let response: SavedRoutineResponse = try await api.put("/v1/routines/current", body: SavedRoutineRequest(skus: cleanSkus))
            applySavedRoutine(response)
            checkoutMessage = successMessage
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "routine_save"])
            Haptics.warning()
        }
    }

    private func applySavedRoutine(_ response: SavedRoutineResponse?) {
        let skus = response?.skus ?? []
        savedRoutineSkus = skus
        UserDefaults.standard.set(skus, forKey: Keys.savedRoutineSkus)
    }

    func productOpened(_ product: RecommendationProduct) {
        analytics.track(.productOpened, properties: ["sku": product.sku, "source": product.source ?? "unknown"])
    }

    func cartQuantity(for sku: String) -> Int {
        cart.items.first(where: { $0.sku == sku })?.quantity ?? 0
    }

    func addToCart(_ product: RecommendationProduct, quantity: Int = 1) async {
        guard !product.isUnavailable else {
            errorMessage = "Этот продукт сейчас недоступен."
            Haptics.warning()
            return
        }
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else {
                errorMessage = "Корзина недоступна, потому что API-сессия не активна."
                return
            }
            var items = cart.items
            if let index = items.firstIndex(where: { $0.sku == product.sku }) {
                items[index].quantity += quantity
            } else {
                items.append(CartItem(sku: product.sku, product: product.asProduct, quantity: quantity))
            }
            cart = CartResponse(items: items, totalItems: items.reduce(0) { $0 + $1.quantity }, subtotal: items.reduce(0) { $0 + $1.product.priceValue * $1.quantity }, currency: "RUB", checkoutMode: "development_handoff")
            analytics.track(.addToCart, properties: ["sku": product.sku, "mode": "development"])
            Haptics.success()
            return
        }
        do {
            let response: CartResponse = try await api.post("/v1/cart/items", body: AddCartItemRequest(sku: product.sku, quantity: quantity))
            cart = response
            analytics.track(.addToCart, properties: ["sku": product.sku, "mode": cart.checkoutMode])
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "cart_add"])
            Haptics.warning()
        }
    }

    func updateCartItem(sku: String, quantity: Int) async {
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else { return }
            var items = cart.items
            if let index = items.firstIndex(where: { $0.sku == sku }) {
                if quantity <= 0 { items.remove(at: index) } else { items[index].quantity = quantity }
            }
            cart = CartResponse(items: items, totalItems: items.reduce(0) { $0 + $1.quantity }, subtotal: items.reduce(0) { $0 + $1.product.priceValue * $1.quantity }, currency: "RUB", checkoutMode: "development_handoff")
            return
        }
        do {
            let response: CartResponse = try await api.patch("/v1/cart/items/\(sku)", body: UpdateCartItemRequest(quantity: quantity))
            cart = response
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "cart_update"])
        }
    }

    func loadCart(silent: Bool = false) async {
        guard !usesLocalFallback, api.accessToken != nil else { return }
        do {
            let response: CartResponse = try await api.get("/v1/cart")
            cart = response
        } catch {
            if !silent { errorMessage = userFacing(error) }
        }
    }

    func checkout() async {
        analytics.track(.checkoutStarted, properties: ["mode": cart.checkoutMode])
        isBusy = true
        defer { isBusy = false }
        await saveRoutine(skus: cart.items.map(\.sku), successMessage: "Подборка сохранена. В бета-версии заказ и оплата не создаются.")
    }

    func requestPrivacyDeletion() async {
        analytics.track(.privacyDeleteRequested, properties: [:])
        do {
            let response: PrivacyRequestResponse = try await api.post("/v1/privacy/delete-request", body: EmptyBody())
            privacyMessage = response.message
        } catch {
            errorMessage = userFacing(error)
        }
    }

    func submitFeedback(rating: Int, message: String, context: String?) async -> Bool {
        guard message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            feedbackMessage = "Добавьте пару слов к отзыву."
            return false
        }
        guard !usesLocalFallback, api.accessToken != nil else {
            feedbackMessage = "Отзыв можно отправить после входа в аккаунт."
            return false
        }
        do {
            let request = FeedbackRequest(rating: rating, message: message, context: context, appVersion: appVersion, build: buildNumber)
            let response: FeedbackResponse = try await api.post("/v1/feedback", body: request)
            feedbackMessage = response.message
            Haptics.success()
            return true
        } catch {
            feedbackMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "feedback"])
            Haptics.warning()
            return false
        }
    }

    func absoluteURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: path, relativeTo: environment.baseURL)?.absoluteURL
    }

    private func userFacing(_ error: Error) -> String {
        if let apiError = error as? APIClientError { return apiError.localizedDescription }
        return error.localizedDescription
    }

    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
