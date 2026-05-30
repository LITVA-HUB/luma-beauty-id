import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case home, advisor, recommendations, cart, profile
    }

    @Published var isLaunching = true
    @Published var hasSeenOnboarding: Bool
    /// Account IDs that have completed the mandatory onboarding face photo.
    @Published var faceScanAccountIds: Set<String>
    @Published var account: Account?
    @Published var beautyID: BeautyID?
    @Published var recommendations: RecommendationsResponse = .empty
    @Published var activeSelection: ActiveSelectionResponse = .empty
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
    @Published var advisorSelectionNotice: String?
    @Published var advisorActions: [AdvisorAction] = []
    @Published var advisorCanReplaceSelection = false
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
    @Published var beautyIDReveal: BeautyIDReveal?
    @Published var selectedScenario: LifeScenario?
    @Published var ownedRoles: Set<RoutineRole>
    @Published var shelfItems: [ShelfItem]
    @Published var routineVariants: [RoutineVariant]
    @Published var selectedRoutineVariant: RoutineVariant?
    @Published var activeComparison: RoutineComparison?
    @Published var selectedPurchaseBlocker: PurchaseBlocker?
    @Published var latestIntentProfiles: [PurchaseIntentProfile]
    @Published var productOpenedSkus: Set<String>
    @Published var replacedProductSkus: Set<String>
    @Published var comparisonOpenedThisSession = false
    @Published var purchaseIntentClickedThisSession = false
    @Published var savedRoutineThisSession = false
    @Published var recentRecommendationActions: [String]

    let environment: AppEnvironment
    let api: APIClient
    private let sessionStore: SessionStore
    private let analytics: AnalyticsService
    private let crashReporter: CrashReporter
    private var lastAdvisorRecommendations: [RecommendationProduct] = []

    enum AdvisorActionApplyResult: Equatable {
        case success(String)
        case alreadyDone(String)
        case needsConfirmation(String)
        case failed(String)
    }

    private enum Keys {
        static let onboarding = "hasSeenOnboarding"
        static let faceScanAccounts = "faceScanAccountIds"
        static let savedProducts = "savedProducts"
        static let savedRoutineSkus = "savedRoutineSkus"
        static let appTheme = "appTheme"
        static let selectedScenario = "selectedScenario"
        static let ownedRoles = "ownedRoles"
        static let shelfItems = "shelfItems"
        static let latestIntentProfiles = "latestIntentProfiles"
    }

    init(
        environment: AppEnvironment = .current,
        keychain: KeychainStore = .shared,
        analytics: AnalyticsService = NoOpAnalyticsService(),
        crashReporter: CrashReporter = NoOpCrashReporter()
    ) {
        self.environment = environment
        let api = APIClient(baseURL: environment.baseURL)
        self.api = api
        self.sessionStore = SessionStore(api: api, tokenStore: keychain)
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: Keys.onboarding)
        self.faceScanAccountIds = Set(UserDefaults.standard.stringArray(forKey: Keys.faceScanAccounts) ?? [])
        self.savedProducts = Set(UserDefaults.standard.stringArray(forKey: Keys.savedProducts) ?? [])
        self.savedRoutineSkus = UserDefaults.standard.stringArray(forKey: Keys.savedRoutineSkus) ?? []
        self.appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.appTheme) ?? "") ?? .system
        self.selectedScenario = Self.loadRawValue(LifeScenario.self, key: Keys.selectedScenario)
        self.ownedRoles = Set(Self.loadArray(RoutineRole.self, key: Keys.ownedRoles))
        self.shelfItems = Self.loadArray(ShelfItem.self, key: Keys.shelfItems)
        self.routineVariants = []
        self.selectedRoutineVariant = nil
        self.activeComparison = nil
        self.selectedPurchaseBlocker = nil
        self.latestIntentProfiles = Self.loadArray(PurchaseIntentProfile.self, key: Keys.latestIntentProfiles)
        self.productOpenedSkus = []
        self.replacedProductSkus = []
        self.recentRecommendationActions = []
        if !hasSeenOnboarding { analytics.track(.onboardingStarted, properties: ["runtime": environment.runtime.rawValue]) }
        api.onUnauthorized = { [weak self] in
            await self?.refreshExpiredSession() ?? false
        }
    }

    /// Вызывается автоматически, когда сервер ответил 401 (access-токен истёк).
    /// Пробует продлить сессию по refresh-токену. true — сессия продлена, запрос повторится сам.
    private func refreshExpiredSession() async -> Bool {
        guard let refresh = sessionStore.refreshToken else { return false }
        do {
            try await sessionStore.refreshSession(refreshToken: refresh)
            return true
        } catch {
            return false
        }
    }

    private static func loadRawValue<T: RawRepresentable>(_ type: T.Type, key: String) -> T? where T.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }

    private static func loadArray<T: Decodable>(_ type: T.Type, key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func persistArray<T: Encodable>(_ values: [T], key: String) {
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func persistOwnedRoles() {
        Self.persistArray(Array(ownedRoles).sorted { $0.rawValue < $1.rawValue }, key: Keys.ownedRoles)
    }

    private func persistShelfItems() {
        Self.persistArray(shelfItems, key: Keys.shelfItems)
    }

    private func persistIntentProfiles() {
        Self.persistArray(latestIntentProfiles, key: Keys.latestIntentProfiles)
    }

    func boot() async {
        try? await Task.sleep(nanoseconds: 420_000_000)
        if environment.configurationError != nil {
            isLaunching = false
            return
        }
        guard sessionStore.restoreAccessToken() != nil else {
            isLaunching = false
            return
        }
        do {
            try await loadProfileAndSessionData()
        } catch {
            var didRefresh = false
            if let refresh = sessionStore.refreshToken {
                do {
                    try await sessionStore.refreshSession(refreshToken: refresh)
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
        // Аккаунты, заполнившие анкету до появления обязательного фото, не гоняем через гейт повторно.
        if profile.beautyId?.beautyId.isUsable == true { markFaceScanCompleted() }
        applySavedRoutine(profile.savedRoutines?.first)
        await loadCart(silent: true)
        await loadAdvisorHistory(silent: true)
        await loadSavedRoutine(silent: true)
        await loadActiveSelection(silent: true)
        if activeSelection.items.isEmpty {
            await loadRecommendations(focus: nil, silent: true)
        }
    }

    func finishOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: Keys.onboarding)
        analytics.track(.onboardingCompleted, properties: ["runtime": environment.runtime.rawValue])
        Haptics.success()
    }

    /// Регистрация прошла, но обязательное фото профиля ещё не сделано.
    var needsFaceScan: Bool {
        guard let id = account?.accountId else { return false }
        return !faceScanAccountIds.contains(id)
    }

    /// Отмечает, что текущий аккаунт прошёл обязательное фото профиля, и сохраняет это локально.
    func markFaceScanCompleted() {
        guard let id = account?.accountId else { return }
        guard faceScanAccountIds.insert(id).inserted else { return }
        UserDefaults.standard.set(Array(faceScanAccountIds), forKey: Keys.faceScanAccounts)
    }

    func register(name: String, phone: String, password: String?) async {
        analytics.track(.authStarted, properties: ["mode": "register"])
        // Анкета проходится до регистрации (гостем). Сохраняем её ответы,
        // чтобы перенести их в новый аккаунт после успешной регистрации.
        let pendingBeautyID = beautyID
        let pass = (password?.isEmpty ?? true) ? nil : password
        await authTask {
            let response: AuthSession = try await api.post("/v1/auth/register", body: RegisterRequest(name: name, phone: phone, password: pass, consent: true))
            try persist(session: response)
            if let pendingBeautyID, pendingBeautyID.isUsable {
                beautyID = pendingBeautyID
                let saved: BeautyIDResponse = try await api.put("/v1/beauty-id", body: pendingBeautyID)
                beautyID = saved.beautyId
            }
            analytics.track(.authCompleted, properties: ["mode": "register", "provider": response.provider ?? "unknown"])
            await trackBackendEvent("registered", payload: ["provider": JSONValue(response.provider ?? "unknown")])
        }
    }

    func login(phone: String, password: String?) async {
        analytics.track(.authStarted, properties: ["mode": "login"])
        let pendingBeautyID = beautyID
        let pass = (password?.isEmpty ?? true) ? nil : password
        await authTask {
            let response: AuthSession = try await api.post("/v1/auth/login", body: LoginRequest(phone: phone, password: pass))
            try persist(session: response)
            if let pendingBeautyID, pendingBeautyID.isUsable {
                beautyID = pendingBeautyID
            }
            // Если у аккаунта уже есть Beauty ID — берём его с сервера.
            // Если нет, а гость только что прошёл анкету — переносим её ответы.
            let profile: ProfileResponse = try await api.get("/v1/profile/me")
            if let serverBeautyID = profile.beautyId?.beautyId {
                beautyID = serverBeautyID
            } else if let pendingBeautyID, pendingBeautyID.isUsable {
                let saved: BeautyIDResponse = try await api.put("/v1/beauty-id", body: pendingBeautyID)
                beautyID = saved.beautyId
            }
            analytics.track(.authCompleted, properties: ["mode": "login", "provider": response.provider ?? "unknown"])
            await trackBackendEvent("logged_in", payload: ["provider": JSONValue(response.provider ?? "unknown")])
        }
    }

    func continueInDevelopmentMode() async {
        guard environment.canShowDevLogin else {
            errorMessage = "Вход недоступен в этой сборке."
            return
        }
        let pendingBeautyID = beautyID
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: AuthSession = try await api.post("/v1/auth/dev-login", body: EmptyBody())
            try persist(session: response)
            usesLocalFallback = false
            if let pendingBeautyID, pendingBeautyID.isUsable {
                beautyID = pendingBeautyID
                if let saved: BeautyIDResponse = try? await api.put("/v1/beauty-id", body: pendingBeautyID) {
                    beautyID = saved.beautyId
                }
            }
            await loadCart(silent: true)
            await loadAdvisorHistory(silent: true)
            await loadActiveSelection(silent: true)
            if activeSelection.items.isEmpty {
                await loadRecommendations(focus: nil, silent: true)
            }
            Haptics.success()
        } catch {
            guard environment.runtime == .development else {
                errorMessage = userFacing(error)
                crashReporter.record(error: error, context: ["flow": "dev_login"])
                return
            }
            usesLocalFallback = true
            account = Account(accountId: "local-development", name: "Клиент Золотого Яблока", email: "development@example.com", phoneNumber: nil, isGuest: false, createdAt: Date())
            beautyID = BeautyID(skinType: "combination", concerns: ["dryness"], sensitivity: "medium", fragranceSensitivity: "avoid", preferredFinish: ["radiant"], makeupPreferences: ["tone"], budget: "mid", ingredientExclusions: [], routineComplexity: "balanced", styleTags: ["soft luxury"], consent: true, updatedAt: Date())
            recommendations = LocalFallbackCatalog.response()
            activeSelection = .empty
            cart = .empty
            Haptics.warning()
        }
    }

    /// «Продолжить без регистрации»: создаёт временный гостевой аккаунт на сервере
    /// и проводит пользователя по стандартному потоку (фото → анкета → главная).
    func continueAsGuest() async {
        analytics.track(.authStarted, properties: ["mode": "guest"])
        let pendingBeautyID = beautyID
        await authTask {
            let response: AuthSession = try await api.post("/v1/auth/guest", body: EmptyBody())
            try persist(session: response)
            if let pendingBeautyID, pendingBeautyID.isUsable {
                beautyID = pendingBeautyID
                if let saved: BeautyIDResponse = try? await api.put("/v1/beauty-id", body: pendingBeautyID) {
                    beautyID = saved.beautyId
                }
            }
            analytics.track(.authCompleted, properties: ["mode": "guest", "provider": response.provider ?? "guest"])
            await trackBackendEvent("guest_started", payload: [:])
        }
    }

    /// Привязывает номер телефона к гостевому аккаунту (апгрейд гостя до полноценного).
    func linkPhone(phone: String, name: String?, password: String?) async {
        let pass = (password?.isEmpty ?? true) ? nil : password
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response: AuthSession = try await api.post(
                "/v1/auth/link-phone",
                body: LinkPhoneRequest(phone: phone, name: (trimmedName?.isEmpty ?? true) ? nil : trimmedName, password: pass)
            )
            account = try sessionStore.persist(session: response)
            await trackBackendEvent("phone_linked", payload: [:])
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "link_phone"])
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
            await loadActiveSelection(silent: true)
            if activeSelection.items.isEmpty {
                await loadRecommendations(focus: nil, silent: true)
            }
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "auth"])
            Haptics.warning()
        }
    }

    private func persist(session: AuthSession) throws {
        resetAccountScopedState(clearAccount: true, clearPersistentCaches: true)
        account = try sessionStore.persist(session: session)
        usesLocalFallback = false
    }

    func logout() {
        let refresh = sessionStore.refreshToken
        if sessionStore.hasAccessToken {
            Task { await sessionStore.sendLogout(refreshToken: refresh) }
        }
        clearSession()
        Haptics.tap()
    }

    func deleteAccount() async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let _: EmptyResponse = try await api.delete("/v1/account/me")
            clearSession()
            Haptics.success()
            return true
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "delete_account"])
            Haptics.warning()
            return false
        }
    }

    private func clearSession() {
        sessionStore.clearSession()
        resetAccountScopedState(clearAccount: true, clearPersistentCaches: true)
        selectedTab = .home
        usesLocalFallback = false
        crashReporter.setUserContext(nil)
    }

    private func resetAccountScopedState(clearAccount: Bool, clearPersistentCaches: Bool) {
        if clearAccount {
            account = nil
        }
        beautyID = nil
        recommendations = .empty
        advisorMessages = []
        advisorWhyThisWorks = []
        advisorRoutineSteps = []
        advisorProviderNote = nil
        cart = .empty
        scanResult = nil
        scanStatuses = []
        activeSelection = .empty
        selectedScenario = nil
        ownedRoles = []
        shelfItems = []
        routineVariants = []
        selectedRoutineVariant = nil
        activeComparison = nil
        selectedPurchaseBlocker = nil
        latestIntentProfiles = []
        productOpenedSkus = []
        replacedProductSkus = []
        comparisonOpenedThisSession = false
        purchaseIntentClickedThisSession = false
        savedRoutineThisSession = false
        recentRecommendationActions = []
        savedProducts = []
        savedRoutineSkus = []
        if clearPersistentCaches {
            UserDefaults.standard.removeObject(forKey: Keys.savedRoutineSkus)
            UserDefaults.standard.removeObject(forKey: Keys.savedProducts)
            UserDefaults.standard.removeObject(forKey: Keys.selectedScenario)
            UserDefaults.standard.removeObject(forKey: Keys.ownedRoles)
            UserDefaults.standard.removeObject(forKey: Keys.shelfItems)
            UserDefaults.standard.removeObject(forKey: Keys.latestIntentProfiles)
        }
        advisorHistoryError = nil
        isAdvisorHistoryLoading = false
        advisorSelectionNotice = nil
        advisorActions = []
        advisorCanReplaceSelection = false
        lastAdvisorRecommendations = []
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
            // Гость проходит анкету до регистрации: Beauty ID держим на устройстве,
            // на сервер он уедет после регистрации/входа. Вошедшему пользователю без
            // сети локальное сохранение доступно только в dev-сборке.
            let isGuest = api.accessToken == nil
            guard isGuest || environment.runtime == .development else {
                errorMessage = "Beauty ID не удалось сохранить, потому что API недоступен."
                return
            }
            beautyID = value
            if isGuest {
                // Гость: тянем настоящую подборку с сервера без аккаунта,
                // чтобы «вау»-экран показывал реальный каталог. Если сервер
                // недоступен — мягко откатываемся на локальную заглушку.
                do {
                    let body = RecommendationsRequest(beautyId: value, focus: nil, limit: 16, filters: [:])
                    let preview: RecommendationsResponse = try await api.post("/v1/recommendations/preview", body: body)
                    recommendations = preview
                } catch {
                    recommendations = LocalFallbackCatalog.response()
                }
            } else {
                recommendations = LocalFallbackCatalog.response()
            }
            beautyIDReveal = BeautyIDReveal(beautyID: value)
            Haptics.success()
            return
        }
        do {
            let response: BeautyIDResponse = try await api.put("/v1/beauty-id", body: value)
            beautyID = response.beautyId
            await loadRecommendations(focus: nil, silent: true)
            beautyIDReveal = BeautyIDReveal(beautyID: response.beautyId)
            await trackBackendEvent("beauty_id_completed", payload: ["completion": JSONValue(String(response.completion))])
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
            if environment.runtime == .development {
                let fallback = LocalFallbackCatalog.response(focus: focus)
                if focus == nil {
                    recommendations = fallback
                } else {
                    let merge = Self.mergedRecommendations(existing: recommendations, incoming: fallback.products)
                    recommendations = merge.response
                    advisorSelectionNotice = Self.selectionNotice(added: merge.addedCount, duplicates: merge.duplicateCount)
                }
            }
            return
        }
        do {
            let response: RecommendationsResponse = try await api.post("/v1/recommendations", body: body)
            if focus == nil {
                recommendations = response
            } else {
                let merge = Self.mergedRecommendations(existing: recommendations, incoming: response.products)
                recommendations = merge.response
                advisorSelectionNotice = Self.selectionNotice(added: merge.addedCount, duplicates: merge.duplicateCount)
            }
            analytics.track(.recommendationViewed, properties: ["focus": focus ?? "default", "count": "\(response.products.count)"])
        } catch {
            if environment.runtime == .development {
                let fallback = LocalFallbackCatalog.response(focus: focus)
                if focus == nil {
                    recommendations = fallback
                } else {
                    let merge = Self.mergedRecommendations(existing: recommendations, incoming: fallback.products)
                    recommendations = merge.response
                    advisorSelectionNotice = Self.selectionNotice(added: merge.addedCount, duplicates: merge.duplicateCount)
                }
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
            activeSelection = Self.localActiveSelectionResponse(from: response.routine)
            if imageData != nil { markFaceScanCompleted() }
            selectedTab = .advisor
            Haptics.success()
            return
        }
        do {
            let result = try await api.uploadPhotoScan(imageData: imageData, source: source, beautyID: beautyID)
            scanResult = result
            recommendations = result.recommendations
            await replaceActiveSelection(with: result.recommendations.routine, source: "scan", silent: true)
            if imageData != nil { markFaceScanCompleted() }
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
                activeSelection = Self.localActiveSelectionResponse(from: response.routine)
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
        if let localAction = localAdvisorControlAction(for: clean) {
            let result = await applyAdvisorAction(localAction, automatic: true)
            advisorMessages.append(AdvisorMessage(
                role: "assistant",
                text: localAdvisorReply(for: localAction, result: result),
                createdAt: Date(),
                recommendedSkus: localAction.skus.isEmpty ? currentRoutineActionProducts(for: localAction).map(\.sku) : localAction.skus
            ))
            advisorActions = []
            return
        }
        isBusy = true
        defer { isBusy = false }
        let context = advisorContext()
        guard !usesLocalFallback, api.accessToken != nil else {
            if environment.runtime == .development { appendFallbackAdvisorReply(for: clean) }
            else { errorMessage = "Советник недоступен, потому что API-сессия не активна." }
            return
        }
        do {
            let request = makeAdvisorRequest(for: clean, context: context)
            let response: AdvisorResponse = try await api.post("/v1/advisor/message", body: request)
            if !looksLikeInternalPrompt(response.answer) {
                advisorMessages.append(AdvisorMessage(role: "assistant", text: response.answer, createdAt: Date(), recommendedSkus: response.recommendations.map(\.sku)))
            } else {
                advisorHistoryError = "Ответ советника скрыт: сервер вернул служебный текст."
            }
            quickActions = response.quickActions
            advisorWhyThisWorks = response.whyThisWorks.map { [$0] } ?? []
            advisorRoutineSteps = response.routineSteps
            advisorProviderNote = response.fallbackReason != nil || response.safetyNote == "advisor_provider_fallback" ? "Сейчас не удалось получить обновлённый ответ. Показала безопасную подборку по каталогу." : nil
            if !response.recommendations.isEmpty {
                lastAdvisorRecommendations = response.recommendations
                advisorCanReplaceSelection = true
                let merge = Self.mergedRecommendations(existing: recommendations, incoming: response.recommendations)
                recommendations = merge.response
                if advisorSelectionNotice == nil {
                    advisorSelectionNotice = Self.selectionNotice(added: merge.addedCount, duplicates: merge.duplicateCount)
                }
            }
            let actions = response.actions ?? []
            let automaticActions = actions.filter { !($0.requiresConfirmation ?? false) && Self.isExecutableAdvisorAction($0.type) }
            advisorActions = actions.filter { ($0.requiresConfirmation ?? false) || !Self.isExecutableAdvisorAction($0.type) }
            for action in automaticActions {
                _ = await applyAdvisorAction(action, automatic: true)
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
        Task { await trackBackendEvent("theme_changed", payload: ["theme": JSONValue(theme.rawValue)]) }
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

    private func localAdvisorControlAction(for message: String) -> AdvisorAction? {
        let lower = message.lowercased()
        let wantsAdd = ["добав", "закин", "полож", "сохрани"].contains { lower.contains($0) }
        guard wantsAdd else { return nil }
        let skus = currentRoutineActionProducts(for: nil).map(\.sku)
        if lower.contains("полк") || lower.contains("хочу попробовать") || lower.contains("на пробу") {
            return AdvisorAction(type: "add_current_routine_to_shelf", skus: skus, oldSku: nil, newSku: nil, reason: "добавить текущий набор в полку", requiresConfirmation: false, metadata: nil)
        }
        if lower.contains("корзин") || lower.contains("к покупке") || lower.contains("список к покупке") {
            return AdvisorAction(type: "add_current_routine_to_cart", skus: skus, oldSku: nil, newSku: nil, reason: "добавить текущий набор в корзину", requiresConfirmation: false, metadata: nil)
        }
        if lower.contains("набор") || lower.contains("рут") || lower.contains("подбор") {
            return AdvisorAction(type: "save_current_routine", skus: skus, oldSku: nil, newSku: nil, reason: "сохранить набор", requiresConfirmation: false, metadata: nil)
        }
        return nil
    }

    private func localAdvisorReply(for action: AdvisorAction, result: AdvisorActionApplyResult) -> String {
        let suffix: String
        switch result {
        case .success(let message), .alreadyDone(let message), .needsConfirmation(let message), .failed(let message):
            suffix = message
        }
        switch action.type {
        case "add_current_routine_to_shelf":
            return "Добавлю текущий набор в вашу полку как «Хочу попробовать». \(suffix)"
        case "add_current_routine_to_cart":
            return "Добавлю товары в список к покупке. \(suffix)"
        case "save_current_routine":
            return "Сохраню набор, чтобы вы могли вернуться к нему позже. \(suffix)"
        default:
            return suffix
        }
    }

    func replaceCurrentSelection(with products: [RecommendationProduct], explanation: String = "Советник заменил подборку по вашему явному запросу.") {
        recommendations = Self.recommendationsResponse(from: products, explanation: explanation)
        activeSelection = Self.localActiveSelectionResponse(from: products)
        advisorSelectionNotice = "Подборка заменена"
        advisorCanReplaceSelection = false
        lastAdvisorRecommendations = []
        Task { await replaceActiveSelection(with: products, source: "advisor", silent: true) }
        Haptics.success()
    }

    func replaceSelectionWithLastAdvisorRecommendations() {
        guard !lastAdvisorRecommendations.isEmpty else {
            advisorSelectionNotice = "Сначала попросите советника предложить замену"
            return
        }
        replaceCurrentSelection(with: lastAdvisorRecommendations)
    }

    @discardableResult
    func applyAdvisorAction(_ action: AdvisorAction, automatic: Bool = false) async -> AdvisorActionApplyResult {
        if action.requiresConfirmation == true && automatic {
            advisorSelectionNotice = "Подтвердите действие"
            return .needsConfirmation("Подтвердите действие")
        }
        let result: AdvisorActionApplyResult
        switch action.type {
        case "add_products", "add_products_to_selection":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Эти товары уже учтены в наборе"
                result = .alreadyDone("Эти товары уже учтены в наборе")
                break
            }
            await mergeActiveSelection(products: products, source: "advisor")
            advisorSelectionNotice = "Добавлено в текущий набор"
            result = .success("Добавлено в текущий набор")
        case "remove_products_from_selection":
            for sku in action.skus { await removeActiveSelectionItem(sku: sku, silent: true) }
            advisorSelectionNotice = action.skus.count > 1 ? "Товары убраны из набора" : "Товар убран из набора"
            result = .success(advisorSelectionNotice ?? "Набор обновлён")
        case "clear_selection":
            await clearActiveSelection()
            advisorSelectionNotice = "Текущий набор очищен"
            result = .success("Текущий набор очищен")
        case "add_current_routine_to_shelf":
            let products = currentRoutineActionProducts(for: action)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Текущий набор пуст. Сначала соберите товары."
                result = .failed("Текущий набор пуст. Сначала соберите товары.")
                break
            }
            products.forEach { markProductWanted($0, source: "advisor") }
            advisorSelectionNotice = "\(products.count.productWord) добавлены в «Хочу попробовать»."
            result = .success(advisorSelectionNotice ?? "Товары добавлены в «Хочу попробовать».")
        case "add_product_to_shelf", "mark_product_wanted":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Не нашла товар для полки"
                result = .failed("Не нашла товар для полки")
                break
            }
            products.forEach { markProductWanted($0, source: "advisor") }
            advisorSelectionNotice = "\(products.count.productWord) добавлены в «Хочу попробовать»."
            result = .success(advisorSelectionNotice ?? "Добавлено в «Хочу попробовать».")
        case "mark_product_owned":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Не нашла товар для полки"
                result = .failed("Не нашла товар для полки")
                break
            }
            products.forEach { markProductOwned($0, source: "advisor") }
            advisorSelectionNotice = "\(products.count.productWord) отмечены как «Уже есть»."
            result = .success(advisorSelectionNotice ?? "Учла как «Уже есть».")
        case "mark_product_buy_later":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Не нашла товар для полки"
                result = .failed("Не нашла товар для полки")
                break
            }
            products.forEach { markProductBuyLater($0, source: "advisor") }
            advisorSelectionNotice = "\(products.count.productWord) отмечены как «Куплю позже»."
            result = .success(advisorSelectionNotice ?? "Сохранено как «Куплю позже».")
        case "mark_product_did_not_fit":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Не нашла товар для полки"
                result = .failed("Не нашла товар для полки")
                break
            }
            products.forEach { markProductDidNotFit($0, reason: .other, source: "advisor") }
            advisorSelectionNotice = "\(products.count.productWord) отмечены как «Не подошло»."
            result = .success(advisorSelectionNotice ?? "Учла как «Не подошло».")
        case "add_products_to_cart":
            let products = products(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Не нашла товар для корзины"
                result = .failed("Не нашла товар для корзины")
                break
            }
            for product in products { await addToCart(product) }
            advisorSelectionNotice = "Товары добавлены в корзину."
            result = .success("Товары добавлены в корзину.")
        case "add_current_routine_to_cart":
            let products = currentRoutineActionProducts(for: action)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Текущий набор пуст. Сначала добавьте товары."
                result = .failed("Текущий набор пуст. Сначала добавьте товары.")
                break
            }
            for product in products { await addToCart(product) }
            advisorSelectionNotice = "Товары добавлены в корзину."
            result = .success("Товары добавлены в корзину.")
        case "add_selection_to_cart", "move_selection_to_cart":
            let products = activeSelectionProducts(for: action.skus)
            guard !products.isEmpty else {
                advisorSelectionNotice = "Текущий набор пуст. Сначала добавьте товары."
                result = .failed("Текущий набор пуст. Сначала добавьте товары.")
                break
            }
            for product in products { await addToCart(product) }
            advisorSelectionNotice = "Товары добавлены в корзину."
            result = .success("Товары добавлены в корзину.")
        case "remove_products_from_cart":
            for sku in action.skus { await updateCartItem(sku: sku, quantity: 0) }
            advisorSelectionNotice = action.skus.count > 1 ? "Товары убраны из корзины" : "Товар убран из корзины"
            result = .success(advisorSelectionNotice ?? "Корзина обновлена")
        case "clear_cart":
            await clearCart()
            advisorSelectionNotice = "Корзина очищена"
            result = .success("Корзина очищена")
        case "suggest_replace_product", "replace_product", "replace_product_confirmed":
            if action.requiresConfirmation == true && action.type != "replace_product_confirmed" {
                advisorSelectionNotice = "Подтвердите замену"
                result = .needsConfirmation("Подтвердите замену")
                break
            }
            guard let oldSku = action.oldSku, let newSku = action.newSku,
                  let replacement = products(for: [newSku]).first else {
                advisorSelectionNotice = "Замена пока недоступна"
                result = .failed("Замена пока недоступна")
                break
            }
            await removeActiveSelectionItem(sku: oldSku, silent: true)
            await mergeActiveSelection(products: [replacement], source: "advisor")
            advisorSelectionNotice = "Товар заменён"
            result = .success("Товар заменён")
        case "save_routine_suggestion", "save_selection_as_routine", "save_current_routine":
            await saveCurrentRoutine()
            advisorSelectionNotice = "Набор сохранён в профиле"
            result = .success("Набор сохранён в профиле.")
        case "refine_budget":
            advisorSelectionNotice = "Напишите советнику: «Сделай набор дешевле»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "refine_fragrance_free":
            advisorSelectionNotice = "Напишите советнику: «Подбери варианты без отдушки»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "refine_lighter_texture":
            advisorSelectionNotice = "Напишите советнику: «Подбери более лёгкие текстуры»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "refine_more_glow":
            advisorSelectionNotice = "Напишите советнику: «Добавь больше сияния»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "refine_premium":
            advisorSelectionNotice = "Напишите советнику: «Покажи более премиальные варианты»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "show_alternatives":
            advisorSelectionNotice = "Напишите советнику: «Покажи альтернативы для текущего набора»"
            result = .needsConfirmation(advisorSelectionNotice ?? "Нужно уточнение")
        case "load_saved_routine":
            await loadSavedRoutine()
            advisorSelectionNotice = "Сохранённый набор загружен"
            result = .success("Сохранённый набор загружен")
        default:
            advisorSelectionNotice = action.reason ?? "Советник учёл текущий набор"
            result = .success(advisorSelectionNotice ?? "Готово")
        }
        await trackBackendEvent("advisor_action_applied", payload: ["type": JSONValue(action.type)])
        return result
    }

    func makeAdvisorRequest(for message: String) -> AdvisorRequest {
        makeAdvisorRequest(for: message, context: advisorContext())
    }

    private func makeAdvisorRequest(
        for message: String,
        context: (currentSkus: [String], currentSelection: [AdvisorSelectionProduct], currentCart: [AdvisorSelectionProduct])
    ) -> AdvisorRequest {
        AdvisorRequest(
            message: message,
            beautyId: beautyID,
            currentSkus: context.currentSkus,
            currentSelection: context.currentSelection,
            currentCart: context.currentCart
        )
    }

    private func advisorContext() -> (currentSkus: [String], currentSelection: [AdvisorSelectionProduct], currentCart: [AdvisorSelectionProduct]) {
        let selection = Self.uniqueProducts(activeSelection.recommendations)
        let cartProducts = cart.items.map(\.product)
        let currentSkus = Self.uniqueSkus(selection.map(\.sku) + cart.items.map(\.sku))
        return (
            currentSkus: currentSkus,
            currentSelection: selection.map { AdvisorSelectionProduct(product: $0) },
            currentCart: cartProducts.map { AdvisorSelectionProduct(product: $0) }
        )
    }

    private func products(for skus: [String]) -> [RecommendationProduct] {
        let ordered = Self.uniqueSkus(skus)
        let candidates = Self.uniqueProducts(activeSelection.recommendations + recommendations.routine + recommendations.products + lastAdvisorRecommendations)
        return ordered.compactMap { sku in candidates.first(where: { $0.sku == sku }) }
    }

    private func activeSelectionProducts(for skus: [String]) -> [RecommendationProduct] {
        let selection = Self.uniqueProducts(activeSelection.recommendations)
        guard !selection.isEmpty else { return [] }
        let ordered = Self.uniqueSkus(skus)
        guard !ordered.isEmpty else { return selection }
        return ordered.compactMap { sku in selection.first(where: { $0.sku == sku }) }
    }

    private func currentRoutineActionProducts(for action: AdvisorAction?) -> [RecommendationProduct] {
        if let action, !action.skus.isEmpty {
            let selected = activeSelectionProducts(for: action.skus)
            if !selected.isEmpty { return selected }
            let matched = products(for: action.skus)
            if !matched.isEmpty { return matched }
        }
        let selected = activeSelectionProducts(for: [])
        if !selected.isEmpty { return selected }
        return currentVariantProducts()
    }

    private static func localActiveSelectionResponse(from products: [RecommendationProduct]) -> ActiveSelectionResponse {
        let items = uniqueProducts(products).map {
            ActiveSelectionItem(
                sku: $0.sku,
                product: $0.asProduct,
                source: "manual",
                routineStep: $0.routineStep,
                reason: $0.reason,
                matchScore: $0.matchScore,
                addedAt: Date(),
                updatedAt: Date(),
                locked: false,
                metadata: nil
            )
        }
        let scores = items.compactMap(\.matchScore)
        let average = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
        return ActiveSelectionResponse(
            items: items,
            skus: items.map(\.sku),
            count: items.count,
            totalPrice: items.reduce(0) { $0 + $1.product.priceValue },
            currency: "RUB",
            averageMatch: average,
            updatedAt: Date(),
            sourceSummary: ["manual": items.count],
            addedCount: nil,
            alreadyInSelectionCount: nil
        )
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

    func loadActiveSelection(silent: Bool = false) async {
        guard !usesLocalFallback, api.accessToken != nil else {
            return
        }
        do {
            let response: ActiveSelectionResponse = try await api.get("/v1/selection/current")
            applyActiveSelection(response)
            if !silent, response.count > 0 { advisorSelectionNotice = "Текущий набор обновлён" }
            await trackBackendEvent("active_selection_loaded", payload: ["count": JSONValue(String(response.count))])
        } catch {
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "active_selection_load"])
        }
    }

    private func replaceActiveSelection(with products: [RecommendationProduct], source: String, silent: Bool = false) async {
        let unique = Self.uniqueProducts(products)
        guard !unique.isEmpty else { return }
        if usesLocalFallback || api.accessToken == nil {
            activeSelection = Self.localActiveSelectionResponse(from: unique)
            return
        }
        do {
            let request = ActiveSelectionPutRequest(items: unique.map { ActiveSelectionItemRequest(product: $0, source: source) })
            let response: ActiveSelectionResponse = try await api.put("/v1/selection/current", body: request)
            applyActiveSelection(response)
            await trackBackendEvent("active_selection_item_added", payload: ["count": JSONValue(String(response.count)), "source": JSONValue(source)])
        } catch {
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "active_selection_replace"])
        }
    }

    private func mergeActiveSelection(products: [RecommendationProduct], source: String, silent: Bool = false) async {
        let unique = Self.uniqueProducts(products)
        guard !unique.isEmpty else { return }
        if usesLocalFallback || api.accessToken == nil {
            let merge = Self.mergedRecommendations(existing: recommendations, incoming: unique)
            activeSelection = Self.localActiveSelectionResponse(from: merge.response.routine)
            return
        }
        do {
            let request = ActiveSelectionPatchRequest(items: unique.map { ActiveSelectionItemRequest(product: $0, source: source) })
            let response: ActiveSelectionResponse = try await api.patch("/v1/selection/current/items", body: request)
            applyActiveSelection(response)
            let added = response.addedCount ?? 0
            let duplicate = response.alreadyInSelectionCount ?? 0
            advisorSelectionNotice = Self.selectionNotice(added: added, duplicates: duplicate) ?? advisorSelectionNotice
            await trackBackendEvent("active_selection_item_added", payload: ["added": JSONValue(String(added)), "duplicate": JSONValue(String(duplicate)), "source": JSONValue(source)])
        } catch {
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "active_selection_merge"])
        }
    }

    private func removeActiveSelectionItem(sku: String, silent: Bool = false) async {
        if usesLocalFallback || api.accessToken == nil {
            let remaining = activeSelection.recommendations.filter { $0.sku != sku }
            activeSelection = Self.localActiveSelectionResponse(from: remaining)
            return
        }
        do {
            var pathAllowed = CharacterSet.urlPathAllowed
            pathAllowed.remove(charactersIn: "/")
            guard let encodedSku = sku.addingPercentEncoding(withAllowedCharacters: pathAllowed) else {
                if !silent { errorMessage = "Не удалось удалить товар из набора." }
                return
            }
            let response: ActiveSelectionResponse = try await api.delete("/v1/selection/current/items/\(encodedSku)")
            applyActiveSelection(response)
            await trackBackendEvent("active_selection_item_removed", payload: ["sku": JSONValue(sku)])
        } catch {
            if !silent { errorMessage = userFacing(error) }
            crashReporter.record(error: error, context: ["flow": "active_selection_remove"])
        }
    }

    private func clearActiveSelection() async {
        if usesLocalFallback || api.accessToken == nil {
            activeSelection = .empty
            return
        }
        do {
            let response: ActiveSelectionResponse = try await api.delete("/v1/selection/current")
            applyActiveSelection(response)
            await trackBackendEvent("active_selection_item_removed", payload: ["scope": JSONValue("all")])
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "active_selection_clear"])
            Haptics.warning()
        }
    }

    func saveCurrentRoutine() async {
        let skus = activeSelection.skus
        await saveRoutine(skus: skus, successMessage: "Набор сохранён в профиле.")
    }

    private func saveRoutine(skus: [String], successMessage: String) async {
        let cleanSkus = Array(NSOrderedSet(array: skus).compactMap { $0 as? String }).filter { !$0.isEmpty }
        guard !cleanSkus.isEmpty else {
            checkoutMessage = "Сначала добавьте товары в текущий набор."
            return
        }
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else {
                errorMessage = "Не удалось сохранить набор. Войдите в аккаунт и попробуйте снова."
                return
            }
            savedRoutineSkus = cleanSkus
            UserDefaults.standard.set(cleanSkus, forKey: Keys.savedRoutineSkus)
            savedRoutineThisSession = true
            checkoutMessage = successMessage
            Haptics.success()
            return
        }
        do {
            let response: SavedRoutineResponse = try await api.put("/v1/routines/current", body: SavedRoutineRequest(skus: cleanSkus))
            applySavedRoutine(response)
            savedRoutineThisSession = true
            checkoutMessage = successMessage
            await trackBackendEvent("routine_saved", payload: ["count": JSONValue(String(cleanSkus.count))])
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

    private func applyActiveSelection(_ response: ActiveSelectionResponse) {
        activeSelection = response
    }

    func productOpened(_ product: RecommendationProduct) {
        productOpenedSkus.insert(product.sku)
        analytics.track(.productOpened, properties: ["sku": product.sku, "source": product.source ?? "unknown"])
        Task { await trackBackendEvent("product_opened", payload: ["sku": JSONValue(product.sku), "source": JSONValue(product.source ?? "unknown")]) }
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
            await trackBackendEvent("product_added_to_cart", payload: ["sku": JSONValue(product.sku), "mode": JSONValue("development")])
            Haptics.success()
            return
        }
        do {
            let response: CartResponse = try await api.post("/v1/cart/items", body: AddCartItemRequest(sku: product.sku, quantity: quantity))
            cart = response
            analytics.track(.addToCart, properties: ["sku": product.sku, "mode": cart.checkoutMode])
            await trackBackendEvent("product_added_to_cart", payload: ["sku": JSONValue(product.sku), "mode": JSONValue(cart.checkoutMode)])
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

    func clearCart() async {
        if usesLocalFallback || api.accessToken == nil {
            guard environment.runtime == .development else { return }
            cart = .empty
            Haptics.success()
            return
        }
        do {
            let response: CartResponse = try await api.delete("/v1/cart")
            cart = response
            await trackBackendEvent("cart_cleared", payload: [:])
            Haptics.success()
        } catch {
            errorMessage = userFacing(error)
            crashReporter.record(error: error, context: ["flow": "cart_clear"])
            Haptics.warning()
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
        await saveRoutine(skus: cart.items.map(\.sku), successMessage: "Набор сохранён в профиле. Заказ и оплата пока не создаются.")
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
            await trackBackendEvent("feedback_submitted", payload: ["context": JSONValue(context ?? "unknown")])
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

    private func trackBackendEvent(_ name: String, payload: [String: JSONValue] = [:]) async {
        guard !usesLocalFallback, api.accessToken != nil else { return }
        let request = EventRequest(eventName: name, payload: payload, appVersion: appVersion, build: buildNumber, platform: "ios")
        let _: EventResponse? = try? await api.post("/v1/events", body: request)
    }

    func selectScenario(_ scenario: LifeScenario) {
        selectedScenario = scenario
        UserDefaults.standard.set(scenario.rawValue, forKey: Keys.selectedScenario)
        analytics.track(.scenarioSelected, properties: ["scenario": scenario.analyticsValue])
        recentRecommendationActions.insert("scenario:\(scenario.analyticsValue)", at: 0)
        if !recommendations.products.isEmpty || !activeSelection.items.isEmpty {
            generateRoutineVariantsFromCurrentRecommendations()
        }
    }

    func updateOwnedRoles(_ roles: Set<RoutineRole>, source: String) {
        ownedRoles = roles.filter { $0 != .unknown && $0 != .giftSafe }
        persistOwnedRoles()
        analytics.track(.ownedItemsSelected, properties: ["source": source, "roles": ownedRoles.map(\.analyticsValue).sorted().joined(separator: ",")])
        if !recommendations.products.isEmpty || !activeSelection.items.isEmpty {
            generateRoutineVariantsFromCurrentRecommendations()
        }
    }

    func addOrUpdateShelfItem(
        product: RecommendationProduct,
        status: ShelfStatus,
        issueReason: ShelfIssueReason? = nil,
        replacementReason: ReplacementReason? = nil,
        source: String
    ) {
        var item = ShelfItem(product: product, status: status, issueReason: issueReason, replacementReason: replacementReason, source: source)
        if let index = shelfItems.firstIndex(where: { $0.sku == product.sku }) {
            item.id = shelfItems[index].id
            item.createdAt = shelfItems[index].createdAt
            shelfItems[index] = item
        } else {
            shelfItems.insert(item, at: 0)
        }
        if status == .needsReplacement {
            replacedProductSkus.insert(product.sku)
        }
        persistShelfItems()
        analytics.track(.shelfItemAdded, properties: shelfPayload(item, source: source))
        generateRoutineVariantsFromCurrentRecommendations()
        Haptics.tap()
    }

    func removeShelfItem(_ item: ShelfItem) {
        shelfItems.removeAll { $0.id == item.id }
        persistShelfItems()
        analytics.track(.shelfItemRemoved, properties: ["status": item.status.analyticsValue, "role": item.role.analyticsValue])
    }

    func recordShelfOpened(source: String) {
        analytics.track(.shelfOpened, properties: ["source": source, "count": "\(shelfItems.count)"])
    }

    func recordAnalyticsDashboardOpened() {
        analytics.track(.analyticsDashboardOpened, properties: ["profiles": "\(latestIntentProfiles.count)", "shelfItems": "\(shelfItems.count)"])
    }

    func changeShelfStatus(_ item: ShelfItem, status: ShelfStatus) {
        guard let index = shelfItems.firstIndex(where: { $0.id == item.id }) else { return }
        shelfItems[index].status = status
        shelfItems[index].updatedAt = Date()
        persistShelfItems()
        analytics.track(.shelfItemStatusChanged, properties: shelfPayload(shelfItems[index], source: "shelf"))
        generateRoutineVariantsFromCurrentRecommendations()
    }

    func shelfStatus(for sku: String) -> ShelfStatus? {
        shelfItems.first(where: { $0.sku == sku })?.status
    }

    func isOwnedRole(_ role: RoutineRole) -> Bool {
        effectiveOwnedRoles.contains(role)
    }

    func markProductOwned(_ product: RecommendationProduct, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .owned, source: source)
        analytics.track(.shelfItemMarkedOwned, properties: ["sku": product.sku, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "\(RoutineRole.from(product: product).displayTitle) учтён как уже имеющийся"
    }

    func markProductWanted(_ product: RecommendationProduct, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .wanted, source: source)
        analytics.track(.shelfItemMarkedWanted, properties: ["sku": product.sku, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "Добавлено в «хочу попробовать»"
    }

    func markProductBuyLater(_ product: RecommendationProduct, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .buyLater, source: source)
        analytics.track(.shelfItemMarkedBuyLater, properties: ["sku": product.sku, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "Сохранено как «куплю позже»"
    }

    func markProductDidNotFit(_ product: RecommendationProduct, reason: ShelfIssueReason, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .didNotFit, issueReason: reason, source: source)
        analytics.track(.shelfItemMarkedDidNotFit, properties: ["sku": product.sku, "reason": reason.analyticsValue, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "Сигнал учтён: \(reason.displayTitle.lowercased())"
    }

    func markProductEmpty(_ product: RecommendationProduct, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .empty, source: source)
        analytics.track(.shelfItemMarkedEmpty, properties: ["sku": product.sku, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "Учту как закончившийся продукт"
    }

    func markProductNeedsReplacement(_ product: RecommendationProduct, reason: ReplacementReason, source: String = "product_detail") {
        addOrUpdateShelfItem(product: product, status: .needsReplacement, replacementReason: reason, source: source)
        replacedProductSkus.insert(product.sku)
        analytics.track(.shelfReplacementRequested, properties: ["sku": product.sku, "reason": reason.analyticsValue, "role": RoutineRole.from(product: product).analyticsValue])
        advisorSelectionNotice = "Подберём замену: \(reason.displayTitle.lowercased())"
    }

    func generateRoutineVariantsFromCurrentRecommendations() {
        let variants = [
            makeOriginalRoutine(),
            makeCheaperRoutine(),
            makeMinimalRoutine(),
            makeBalancedRoutine(),
            makePremiumRoutine()
        ].compactMap { $0 }
        routineVariants = uniqueVariants(variants)
        if let selectedRoutineVariant, routineVariants.contains(where: { $0.id == selectedRoutineVariant.id }) == false {
            self.selectedRoutineVariant = routineVariants.first
        }
        analytics.track(.recommendationGenerated, properties: [
            "scenario": selectedScenario?.analyticsValue ?? "none",
            "variantCount": "\(routineVariants.count)"
        ])
    }

    func makeOriginalRoutine() -> RoutineVariant? {
        let scenario = selectedScenario
        let built = buildRoutine(type: .original, scenario: scenario, maxCount: maxCount(for: scenario, fallback: 4), strategy: .baseline)
        guard !built.products.isEmpty else { return nil }
        return makeVariant(
            type: .original,
            title: scenario.map { "Ваш \($0.displayTitle.lowercased())" } ?? "Ваш персональный набор",
            subtitle: scenario?.subtitle,
            scenario: scenario,
            products: built.products,
            whatChanged: built.changes,
            benefits: built.benefits,
            tradeoffs: built.tradeoffs,
            explanation: built.explanation
        )
    }

    func makeCheaperRoutine() -> RoutineVariant? {
        let original = makeOriginalRoutine()
        let source = original?.products ?? buildRoutine(type: .original, scenario: selectedScenario, maxCount: 4, strategy: .baseline).products
        guard !source.isEmpty else { return nil }
        let candidates = pilotCandidates()
        var products: [RecommendationProduct] = []
        var changes: [String] = []
        for product in source {
            let role = RoutineRole.from(product: product)
            let cheaper = candidates
                .filter { RoutineRole.from(product: $0) == role && $0.priceValue <= product.priceValue }
                .sorted { lhs, rhs in lhs.priceValue == rhs.priceValue ? lhs.matchScore > rhs.matchScore : lhs.priceValue < rhs.priceValue }
                .first ?? product
            if cheaper.sku != product.sku {
                changes.append("\(role.displayTitle): \(product.priceValue.rub) → \(cheaper.priceValue.rub)")
            }
            products.append(cheaper)
        }
        let unique = uniqueProducts(products)
        let originalTotal = source.reduce(0) { $0 + $1.priceValue }
        let newTotal = unique.reduce(0) { $0 + $1.priceValue }
        if changes.isEmpty {
            changes.append("В каталоге не нашлось заметно более дешёвой замены для выбранных ролей.")
        }
        return makeVariant(
            type: .cheaper,
            title: "Дешевле",
            subtitle: "Сохраняет ключевые роли и снижает сумму, где каталог позволяет.",
            scenario: selectedScenario,
            products: unique,
            whatChanged: changes,
            benefits: ["Цена набора \(newTotal.rub)", "Роли остаются привязанными к сценарию"],
            tradeoffs: newTotal < originalTotal ? ["Может быть меньше премиальной сенсорности."] : ["Цена не снизилась: каталог ограничен по альтернативам."],
            explanation: "Вариант «дешевле» не использует скидки или промо: только реальные цены каталога."
        )
    }

    func makeMinimalRoutine() -> RoutineVariant? {
        let original = makeOriginalRoutine()
        let source = original?.products ?? buildRoutine(type: .original, scenario: selectedScenario, maxCount: 4, strategy: .baseline).products
        guard !source.isEmpty else { return nil }
        let targetCount = source.count > 1 ? max(1, min(2, source.count - 1)) : 1
        let priority = selectedScenario?.rolePriorities ?? [.cleanser, .spf, .moisturizer, .serum]
        let selected = source.sorted { lhs, rhs in
            (priority.firstIndex(of: RoutineRole.from(product: lhs)) ?? 99) < (priority.firstIndex(of: RoutineRole.from(product: rhs)) ?? 99)
        }.prefix(targetCount)
        let products = Array(selected)
        return makeVariant(
            type: .minimal,
            title: "Минимум",
            subtitle: "Меньше шагов, только основа сценария.",
            scenario: selectedScenario,
            products: products,
            whatChanged: ["Убрали \(max(0, source.count - products.count)) шагов, которые не являются обязательными для сценария."],
            benefits: ["Меньше товаров", "Проще решиться и повторять"],
            tradeoffs: ["Меньше дополнительных эффектов: сияние, стойкость или акценты могут быть слабее."],
            explanation: "Минимум не добавляет товары в текущий набор, пока вы явно не сохраните вариант."
        )
    }

    func makeBalancedRoutine() -> RoutineVariant? {
        let built = buildRoutine(type: .balanced, scenario: selectedScenario, maxCount: 4, strategy: .balanced)
        guard !built.products.isEmpty else { return nil }
        return makeVariant(
            type: .balanced,
            title: "Баланс",
            subtitle: "Закрывает больше задач без длинной полки.",
            scenario: selectedScenario,
            products: built.products,
            whatChanged: built.changes.isEmpty ? ["Собрали умеренное количество шагов под сценарий."] : built.changes,
            benefits: ["Больше задач закрыто одним набором", "Цена и количество шагов видны до покупки"],
            tradeoffs: ["Дороже минимума и требует больше привычки."],
            explanation: built.explanation
        )
    }

    func makePremiumRoutine() -> RoutineVariant? {
        let original = makeOriginalRoutine()
        let source = original?.products ?? buildRoutine(type: .original, scenario: selectedScenario, maxCount: 4, strategy: .baseline).products
        guard !source.isEmpty else { return nil }
        let candidates = pilotCandidates()
        var products: [RecommendationProduct] = []
        var changes: [String] = []
        for product in source {
            let role = RoutineRole.from(product: product)
            let premium = candidates
                .filter { RoutineRole.from(product: $0) == role && ($0.priceSegment == "premium" || $0.priceSegment == "luxury" || $0.priceValue >= product.priceValue) }
                .sorted { lhs, rhs in lhs.priceValue == rhs.priceValue ? lhs.matchScore > rhs.matchScore : lhs.priceValue > rhs.priceValue }
                .first ?? product
            if premium.sku != product.sku {
                changes.append("\(role.displayTitle): премиум-альтернатива \(premium.priceValue.rub)")
            }
            products.append(premium)
        }
        if changes.isEmpty {
            changes.append("Премиальная альтернатива ограничена текущим каталогом.")
        }
        return makeVariant(
            type: .premium,
            title: "Премиум",
            subtitle: "Более дорогие альтернативы без обещаний результата.",
            scenario: selectedScenario,
            products: uniqueProducts(products),
            whatChanged: changes,
            benefits: ["Больше премиальной сенсорности там, где она есть в каталоге"],
            tradeoffs: ["Дороже базового варианта", "Не использует реальные отзывы, наличие или скидки"],
            explanation: "Премиум выбирает только товары из загруженного каталога и не нарушает сигналы по полке и отдушке."
        )
    }

    func compareRoutineVariants(_ type: RoutineComparisonType, left: RoutineVariant, right: RoutineVariant) -> RoutineComparison {
        comparisonOpenedThisSession = true
        recentRecommendationActions.insert("compare:\(type.rawValue)", at: 0)
        let priceDelta = right.totalPrice - left.totalPrice
        let countDelta = right.productCount - left.productCount
        let keyChanges = Array((right.whatChanged + right.benefits + right.tradeoffs).prefix(6))
        let recommended: RoutineVariantType? = priceDelta <= 0 && right.productCount <= left.productCount ? right.type : left.type
        let comparison = RoutineComparison(
            leftVariant: left,
            rightVariant: right,
            comparisonType: type,
            summary: "\(left.title): \(left.productCount.productWord) · \(left.totalPrice.rub). \(right.title): \(right.productCount.productWord) · \(right.totalPrice.rub).",
            priceDelta: priceDelta,
            productCountDelta: countDelta,
            keyChanges: keyChanges.isEmpty ? ["Сравнение показывает цену, количество и компромисс без отзывов и скидок."] : keyChanges,
            recommendedChoice: recommended,
            createdAt: Date()
        )
        activeComparison = comparison
        analytics.track(.comparisonOpened, properties: ["type": type.rawValue, "priceDelta": "\(priceDelta)", "productCountDelta": "\(countDelta)"])
        return comparison
    }

    func selectRoutineVariant(_ variant: RoutineVariant) {
        selectedRoutineVariant = variant
        recentRecommendationActions.insert("variant_selected:\(variant.type.analyticsValue)", at: 0)
        analytics.track(.comparisonVariantSelected, properties: ["routineVariantType": variant.type.analyticsValue, "totalPrice": "\(variant.totalPrice)", "productCount": "\(variant.productCount)"])
        advisorSelectionNotice = "Выбран вариант \(variant.type.displayTitle). Сохраните его, чтобы вернуться к набору позже."
    }

    func saveSelectedRoutineVariant() async {
        guard let selectedRoutineVariant else {
            checkoutMessage = "Сначала выберите вариант набора."
            return
        }
        savedRoutineThisSession = true
        await saveRoutine(skus: selectedRoutineVariant.products.map(\.sku), successMessage: "Вариант \(selectedRoutineVariant.type.displayTitle) сохранён.")
        analytics.track(.comparisonVariantSaved, properties: ["routineVariantType": selectedRoutineVariant.type.analyticsValue, "totalPrice": "\(selectedRoutineVariant.totalPrice)"])
        _ = generatePurchaseIntentProfile(trigger: "variant_saved")
    }

    func addRoutineVariantToActiveSelection(_ variant: RoutineVariant) async {
        guard !variant.products.isEmpty else { return }
        await mergeActiveSelection(products: variant.products, source: "routine_variant:\(variant.type.analyticsValue)")
        checkoutMessage = "Вариант \(variant.type.displayTitle) добавлен в текущий набор."
        Haptics.success()
    }

    func addProductToActiveSelection(_ product: RecommendationProduct, source: String) async {
        await mergeActiveSelection(products: [product], source: source)
        checkoutMessage = "\(product.name) добавлен в текущий набор."
        Haptics.success()
    }

    func recordPurchaseIntentClicked(context: String) {
        purchaseIntentClickedThisSession = true
        analytics.track(.purchaseIntent, properties: ["source": context, "scenario": selectedScenario?.analyticsValue ?? "none", "routineVariantType": selectedRoutineVariant?.type.analyticsValue ?? "none"])
        analytics.track(.purchaseBlockerPromptShown, properties: ["source": context])
    }

    func selectPurchaseBlocker(_ blocker: PurchaseBlocker) {
        selectedPurchaseBlocker = blocker
        analytics.track(.purchaseBlockerSelected, properties: ["blocker": blocker.analyticsValue, "actionType": blocker.actionType])
        handlePurchaseBlockerAction(blocker)
        _ = generatePurchaseIntentProfile(trigger: "blocker:\(blocker.analyticsValue)")
    }

    func handlePurchaseBlockerAction(_ blocker: PurchaseBlocker) {
        analytics.track(.blockerActionStarted, properties: ["blocker": blocker.analyticsValue, "actionType": blocker.actionType])
        switch blocker {
        case .tooExpensive:
            if let variant = makeCheaperRoutine() {
                selectedRoutineVariant = variant
                upsertVariant(variant)
                recentRecommendationActions.insert("cheaper", at: 0)
                advisorSelectionNotice = "Показала более доступный вариант."
            }
        case .tooManyProducts:
            if let variant = makeMinimalRoutine() {
                selectedRoutineVariant = variant
                upsertVariant(variant)
                recentRecommendationActions.insert("minimal", at: 0)
                advisorSelectionNotice = "Оставила минимальный набор."
            }
        case .wantsToCompare:
            generateRoutineVariantsFromCurrentRecommendations()
            if let minimal = routineVariants.first(where: { $0.type == .minimal }),
               let balanced = routineVariants.first(where: { $0.type == .balanced }) {
                _ = compareRoutineVariants(.minimalVsBalanced, left: minimal, right: balanced)
            }
        case .wantsReplacement:
            if let product = selectedRoutineVariant?.products.first ?? recommendations.routine.first ?? recommendations.products.first {
                markProductNeedsReplacement(product, reason: .similarButDifferent, source: "purchase_blocker")
            }
        case .buyLater:
            let products = currentVariantProducts()
            products.forEach { markProductBuyLater($0, source: "purchase_blocker") }
            checkoutMessage = "Сохранила сигнал «куплю позже» для текущего набора."
        case .shadeConcern:
            checkoutMessage = "В каталоге оттенок нужно проверить отдельно перед покупкой."
        case .wantsReviews:
            checkoutMessage = "Отзывы пока не подключены в каталоге. Сигнал сохранён как причина сомнения."
        case .wantsToSeeInStore:
            checkoutMessage = "Наличие в магазине пока не подключено. Сигнал сохранён как причина сомнения."
        case .notSure:
            checkoutMessage = "Проверьте оттенок, текстуру, отдушку и роль каждого товара перед покупкой."
        case .nothingBlocking:
            checkoutMessage = "Отлично, Золотое Яблоко сохранило сильное намерение купить набор."
        }
        analytics.track(.blockerActionCompleted, properties: ["blocker": blocker.analyticsValue, "actionType": blocker.actionType])
    }

    func generatePurchaseIntentProfile(trigger: String) -> PurchaseIntentProfile {
        let variant = selectedRoutineVariant ?? routineVariants.first(where: { $0.type == .original })
        let shelfSummary = shelfSignalSummary()
        let profile = PurchaseIntentProfile(
            createdAt: Date(),
            scenario: selectedScenario,
            budget: beautyID?.budget ?? "unknown",
            constraintsSummary: constraintsSummary(),
            ownedRoles: Array(effectiveOwnedRoles).sorted { $0.rawValue < $1.rawValue },
            shelfSignalsSummary: shelfSummary,
            routineVariantType: variant?.type,
            routineTotalPrice: variant?.totalPrice,
            productCount: variant?.productCount,
            productsOpened: Array(productOpenedSkus).sorted(),
            productsReplaced: Array(replacedProductSkus).sorted(),
            comparisonOpened: comparisonOpenedThisSession,
            selectedVariant: selectedRoutineVariant?.type,
            savedRoutine: savedRoutineThisSession || !savedRoutineSkus.isEmpty,
            purchaseIntentClicked: purchaseIntentClickedThisSession,
            selectedBlocker: selectedPurchaseBlocker,
            actionAfterBlocker: selectedPurchaseBlocker?.actionType,
            intentLevel: intentLevelForCurrentSession(),
            businessSummary: businessSummary(variant: variant, shelfSummary: shelfSummary, trigger: trigger)
        )
        latestIntentProfiles.insert(profile, at: 0)
        latestIntentProfiles = Array(latestIntentProfiles.prefix(20))
        persistIntentProfiles()
        analytics.track(.intentProfileCreated, properties: ["intentLevel": profile.intentLevel.rawValue, "trigger": trigger, "scenario": selectedScenario?.analyticsValue ?? "none"])
        return profile
    }

    func intentLevelForCurrentSession() -> PurchaseIntentLevel {
        if selectedPurchaseBlocker == .nothingBlocking { return .veryHigh }
        if purchaseIntentClickedThisSession, selectedPurchaseBlocker != nil { return .veryHigh }
        if savedRoutineThisSession, selectedRoutineVariant?.type != nil, selectedRoutineVariant?.type != .original { return .veryHigh }
        if savedRoutineThisSession || !savedRoutineSkus.isEmpty || purchaseIntentClickedThisSession { return .high }
        if shelfItems.contains(where: { $0.status == .buyLater || $0.status == .wanted }) { return .high }
        if !productOpenedSkus.isEmpty || comparisonOpenedThisSession || !replacedProductSkus.isEmpty || routineVariants.contains(where: { [.cheaper, .minimal, .premium].contains($0.type) }) { return .medium }
        return .low
    }

    var currentRoutineVariant: RoutineVariant? {
        selectedRoutineVariant ?? routineVariants.first(where: { $0.type == .original }) ?? makeOriginalRoutine()
    }

    private enum RoutineBuildStrategy {
        case baseline, balanced
    }

    private struct RoutineBuildResult {
        let products: [RecommendationProduct]
        let changes: [String]
        let benefits: [String]
        let tradeoffs: [String]
        let explanation: String
    }

    private var effectiveOwnedRoles: Set<RoutineRole> {
        ownedRoles.union(shelfItems.filter { $0.status == .owned }.map(\.role))
    }

    private func shelfPayload(_ item: ShelfItem, source: String) -> [String: String] {
        [
            "sku": item.sku ?? "role:\(item.role.analyticsValue)",
            "role": item.role.analyticsValue,
            "shelfStatus": item.status.analyticsValue,
            "issueReason": item.issueReason?.analyticsValue ?? "",
            "replacementReason": item.replacementReason?.analyticsValue ?? "",
            "source": source
        ]
    }

    private func currentVariantProducts() -> [RecommendationProduct] {
        if let selectedRoutineVariant { return selectedRoutineVariant.products }
        if let original = routineVariants.first(where: { $0.type == .original }) { return original.products }
        return activeSelection.recommendations.isEmpty ? recommendations.routine : activeSelection.recommendations
    }

    private func pilotCandidates() -> [RecommendationProduct] {
        let rejectedSkus = Set(shelfItems.compactMap { $0.status == .didNotFit ? $0.sku : nil })
        let avoidFragrance = beautyID?.fragranceSensitivity == "avoid" || shelfItems.contains(where: { $0.issueReason == .fragrance })
        return uniqueProducts(activeSelection.recommendations + recommendations.routine + recommendations.products + lastAdvisorRecommendations)
            .filter { product in
                guard !product.isUnavailable else { return false }
                guard !rejectedSkus.contains(product.sku) else { return false }
                if avoidFragrance && hasFragranceRisk(product) { return false }
                return true
            }
    }

    private func buildRoutine(type: RoutineVariantType, scenario: LifeScenario?, maxCount: Int, strategy: RoutineBuildStrategy) -> RoutineBuildResult {
        let candidates = pilotCandidates()
        guard !candidates.isEmpty else {
            return RoutineBuildResult(products: [], changes: ["Каталог не дал доступных кандидатов."], benefits: [], tradeoffs: ["Нужен подключенный каталог для более точного набора."], explanation: "Нет доступных товаров для варианта.")
        }
        let scenario = scenario ?? selectedScenario
        let owned = effectiveOwnedRoles
        let baseRoles = scenario?.rolePriorities ?? orderedRoles(from: recommendations.routine + recommendations.products)
        let priorities = baseRoles + orderedRoles(from: candidates).filter { !baseRoles.contains($0) }
        var products: [RecommendationProduct] = []
        var usedRoles: Set<RoutineRole> = []
        var changes: [String] = []
        for role in priorities {
            guard role != .unknown, products.count < maxCount else { continue }
            if owned.contains(role) && scenario != .replaceOneProduct {
                changes.append("\(role.displayTitle) не добавили: вы отметили, что этот шаг уже есть.")
                continue
            }
            if scenario == .gift && [.foundationTint, .concealer, .powder].contains(role) {
                changes.append("\(role.displayTitle) пропустили: для подарка это оттеночный риск.")
                continue
            }
            guard !usedRoles.contains(role) else { continue }
            let roleCandidates = candidates.filter { RoutineRole.from(product: $0) == role }
            guard let selected = pickProduct(from: roleCandidates, strategy: type == .premium ? .premium : (scenario == .underBudget || type == .cheaper ? .cheaper : .baseline)) else { continue }
            products.append(selected)
            usedRoles.insert(role)
        }
        if products.isEmpty {
            products = Array(candidates.prefix(max(1, min(maxCount, candidates.count))))
        }
        let benefits = [
            "\(products.count.productWord) из каталога",
            "Общая сумма \(products.reduce(0) { $0 + $1.priceValue }.rub)",
            scenario.map { "Сценарий: \($0.displayTitle.lowercased())" } ?? "Учитывает текущий Beauty ID"
        ].compactMap { $0 }
        let tradeoffs = changes.isEmpty ? ["Вариант не использует реальные отзывы, скидки или наличие магазина."] : ["Учтены сигналы полки, поэтому некоторые роли могли быть пропущены."]
        let explanation = scenario.map { "\($0.defaultCopy) Косметический подбор, не медицинская рекомендация." } ?? "Подбор основан на Beauty ID и каталоге."
        return RoutineBuildResult(products: uniqueProducts(products), changes: changes, benefits: benefits, tradeoffs: tradeoffs, explanation: explanation)
    }

    private enum ProductPickStrategy {
        case baseline, cheaper, premium
    }

    private func pickProduct(from products: [RecommendationProduct], strategy: ProductPickStrategy) -> RecommendationProduct? {
        switch strategy {
        case .baseline:
            let bestScore = products.map(\.matchScore).max() ?? 0
            return products.first { $0.matchScore == bestScore } ?? products.first
        case .cheaper:
            return products.sorted { lhs, rhs in lhs.priceValue == rhs.priceValue ? lhs.matchScore > rhs.matchScore : lhs.priceValue < rhs.priceValue }.first
        case .premium:
            return products.sorted { lhs, rhs in
                let lhsPremium = (lhs.priceSegment == "premium" || lhs.priceSegment == "luxury") ? 1 : 0
                let rhsPremium = (rhs.priceSegment == "premium" || rhs.priceSegment == "luxury") ? 1 : 0
                if lhsPremium != rhsPremium { return lhsPremium > rhsPremium }
                return lhs.priceValue > rhs.priceValue
            }.first
        }
    }

    private func makeVariant(type: RoutineVariantType, title: String, subtitle: String?, scenario: LifeScenario?, products: [RecommendationProduct], whatChanged: [String], benefits: [String], tradeoffs: [String], explanation: String) -> RoutineVariant {
        let uniqueProducts = uniqueProducts(products)
        return RoutineVariant(
            type: type,
            title: title,
            subtitle: subtitle,
            scenario: scenario,
            products: uniqueProducts,
            totalPrice: uniqueProducts.reduce(0) { $0 + $1.priceValue },
            currency: uniqueProducts.first?.currency ?? "RUB",
            productCount: uniqueProducts.count,
            whatChanged: whatChanged.isEmpty ? ["Собрано из доступных товаров каталога."] : whatChanged,
            benefits: benefits.isEmpty ? ["Каталог-grounded подбор без выдуманных товаров."] : benefits,
            tradeoffs: tradeoffs.isEmpty ? ["Каталог не содержит реальные отзывы, скидки или наличие."] : tradeoffs,
            explanation: explanation,
            generatedAt: Date(),
            sourceRoutineId: nil
        )
    }

    private func upsertVariant(_ variant: RoutineVariant) {
        if let index = routineVariants.firstIndex(where: { $0.type == variant.type }) {
            routineVariants[index] = variant
        } else {
            routineVariants.append(variant)
        }
    }

    private func uniqueVariants(_ variants: [RoutineVariant]) -> [RoutineVariant] {
        var seen: Set<RoutineVariantType> = []
        return variants.filter { variant in
            guard !seen.contains(variant.type) else { return false }
            seen.insert(variant.type)
            return true
        }
    }

    private func uniqueProducts(_ products: [RecommendationProduct]) -> [RecommendationProduct] {
        var seen: Set<String> = []
        return products.filter { product in
            guard !seen.contains(product.sku) else { return false }
            seen.insert(product.sku)
            return true
        }
    }

    private func orderedRoles(from products: [RecommendationProduct]) -> [RoutineRole] {
        var seen: Set<RoutineRole> = []
        return products.compactMap { product in
            let role = RoutineRole.from(product: product)
            guard role != .unknown, !seen.contains(role) else { return nil }
            seen.insert(role)
            return role
        }
    }

    private func maxCount(for scenario: LifeScenario?, fallback: Int) -> Int {
        switch scenario {
        case .morning, .evening: return 3
        case .underBudget, .gift, .minimalRoutine: return 3
        case .replaceOneProduct: return 2
        case .travel: return 3
        case .premiumRoutine: return 4
        case .none: return fallback
        }
    }

    private func hasFragranceRisk(_ product: RecommendationProduct) -> Bool {
        let text = (product.tags + product.ingredients + product.warnings + [product.name, product.category]).joined(separator: " ").lowercased()
        return ["fragrance", "perfume", "parfum", "scented", "отдуш", "аромат"].contains { text.contains($0) }
    }

    private func constraintsSummary() -> String {
        var parts: [String] = []
        if let fragrance = beautyID?.fragranceSensitivity { parts.append("отдушка: \(fragrance.beautyLabel)") }
        if let complexity = beautyID?.routineComplexity { parts.append("сложность: \(complexity.beautyLabel)") }
        if let exclusions = beautyID?.ingredientExclusions, !exclusions.isEmpty { parts.append("исключить: \(exclusions.prefix(3).joined(separator: ", "))") }
        if let budget = beautyID?.budget { parts.append("бюджет: \(budget.beautyLabel)") }
        return parts.isEmpty ? "без явных ограничений" : parts.joined(separator: "; ")
    }

    private func shelfSignalSummary() -> String {
        guard !shelfItems.isEmpty else { return "полка пока пустая" }
        let grouped = Dictionary(grouping: shelfItems, by: \.status)
        return ShelfStatus.allCases.compactMap { status in
            guard let count = grouped[status]?.count, count > 0 else { return nil }
            return "\(status.displayTitle): \(count)"
        }.joined(separator: "; ")
    }

    private func businessSummary(variant: RoutineVariant?, shelfSummary: String, trigger: String) -> String {
        var pieces: [String] = []
        if let selectedScenario { pieces.append("Пользователь выбрал сценарий «\(selectedScenario.displayTitle.lowercased())»") }
        else { pieces.append("Пользователь смотрит персональный beauty-набор") }
        if let budget = beautyID?.budget { pieces.append("бюджет: \(budget.beautyLabel)") }
        let owned = Array(effectiveOwnedRoles).map(\.displayTitle).sorted()
        if !owned.isEmpty { pieces.append("уже есть: \(owned.joined(separator: ", "))") }
        if let variant { pieces.append("выбран вариант \(variant.type.displayTitle): \(variant.productCount.productWord) · \(variant.totalPrice.rub)") }
        if !productOpenedSkus.isEmpty { pieces.append("открыто товаров: \(productOpenedSkus.count)") }
        if comparisonOpenedThisSession { pieces.append("сравнение открыто") }
        if savedRoutineThisSession || !savedRoutineSkus.isEmpty { pieces.append("набор сохранён") }
        if let selectedPurchaseBlocker { pieces.append("причина сомнения: \(selectedPurchaseBlocker.displayTitle)") }
        pieces.append("полка: \(shelfSummary)")
        pieces.append("уровень намерения: \(intentLevelForCurrentSession().displayTitle)")
        pieces.append("событие профиля: \(trigger)")
        return pieces.joined(separator: ". ") + "."
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
