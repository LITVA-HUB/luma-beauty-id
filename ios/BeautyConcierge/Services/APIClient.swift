import Foundation

struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}

struct APIClientError: LocalizedError, Equatable {
    enum Kind: Equatable {
        case invalidURL
        case unauthorized
        case server(String)
        case decoding(String)
        case transport(String)
    }

    let kind: Kind

    var errorDescription: String? {
        switch kind {
        case .invalidURL:
            return "Некорректный URL API."
        case .unauthorized:
            return "Сессия истекла. Войдите заново."
        case .server(let message):
            return Self.friendlyServerMessage(message)
        case .decoding:
            return "Не удалось обновить данные. Попробуйте ещё раз."
        case .transport:
            return "Не удалось подключиться к сервису. Проверьте соединение и попробуйте снова."
        }
    }

    private static func friendlyServerMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("email or password") { return "Email или пароль указаны неверно." }
        if lower.contains("account with this email") { return "Аккаунт с таким email уже существует." }
        if lower.contains("session expired") || lower.contains("bearer token") { return "Сессия истекла. Войдите заново." }
        if lower.contains("product") && lower.contains("not found") { return "Товар не найден в текущем каталоге." }
        if lower.contains("unavailable") && lower.contains("product") { return "Этот продукт сейчас недоступен." }
        if lower.contains("cart is empty") { return "Корзина пустая." }
        if lower.contains("saved routine") { return "Не удалось сохранить подборку. Обновите товары и попробуйте снова." }
        if lower.contains("validation") { return "Проверьте данные и попробуйте снова." }
        if lower.contains("openrouter") || lower.contains("provider") || lower.contains("configured") || lower.contains("contract") || lower.contains("adapter") || lower.contains("api_key") {
            return "Сервис временно недоступен. Попробуйте позже."
        }
        return "Не удалось выполнить действие. Проверьте соединение и попробуйте снова."
    }
}

final class APIClient {
    let baseURL: URL
    var accessToken: String?

    /// Вызывается, когда сервер ответил 401 (access-токен истёк).
    /// Должен обновить сессию и вернуть true при успехе — тогда запрос повторится автоматически.
    var onUnauthorized: (() async -> Bool)?

    private var refreshTask: Task<Bool, Never>?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.api.date(from: value) { return date }
            if let date = ISO8601DateFormatter.fallback.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
        }
    }

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: "GET", bodyData: nil)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path: path, method: "POST", bodyData: encoder.encode(body))
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path: path, method: "PUT", bodyData: encoder.encode(body))
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path: path, method: "PATCH", bodyData: encoder.encode(body))
    }

    func delete<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: "DELETE", bodyData: nil)
    }

    func uploadPhotoScan(imageData: Data?, source: String, beautyID: BeautyID?, isRetry: Bool = false) async throws -> ScanResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "/v1/photo/scan", relativeTo: baseURL) else { throw APIClientError(kind: .invalidURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        appendField("source", source)
        if let beautyID {
            let beautyData = try encoder.encode(beautyID)
            if let json = String(data: beautyData, encoding: .utf8) { appendField("beauty_id_json", json) }
        }
        if let imageData {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"photo\"; filename=\"beauty-context.jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)--\r\n")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch {
            throw APIClientError(kind: .transport(error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError(kind: .transport("Неожиданный ответ сервера.")) }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                if !isRetry, shouldAttemptRefresh(for: "/v1/photo/scan"), await performRefresh() {
                    return try await uploadPhotoScan(imageData: imageData, source: source, beautyID: beautyID, isRetry: true)
                }
                throw APIClientError(kind: .unauthorized)
            }
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) { throw APIClientError(kind: .server(envelope.error.message)) }
            throw APIClientError(kind: .server("Сервер вернул \(http.statusCode)."))
        }
        do { return try decoder.decode(ScanResult.self, from: data) }
        catch { throw APIClientError(kind: .decoding(error.localizedDescription)) }
    }

    private func request<Response: Decodable>(path: String, method: String, bodyData: Data?, isRetry: Bool = false) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIClientError(kind: .invalidURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError(kind: .transport(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError(kind: .transport("Неожиданный ответ сервера."))
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                if !isRetry, shouldAttemptRefresh(for: path), await performRefresh() {
                    return try await self.request(path: path, method: method, bodyData: bodyData, isRetry: true)
                }
                throw APIClientError(kind: .unauthorized)
            }
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIClientError(kind: .server(envelope.error.message))
            }
            throw APIClientError(kind: .server("Сервер вернул \(http.statusCode)."))
        }

        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError(kind: .decoding(error.localizedDescription))
        }
    }

    /// Запросы к /v1/auth/ (вход, регистрация, обновление токена) не должны вызывать
    /// повторное обновление сессии — иначе при неверном пароле получился бы бесконечный цикл.
    private func shouldAttemptRefresh(for path: String) -> Bool {
        !path.contains("/v1/auth/")
    }

    /// Обновляет сессию один раз, даже если 401 пришёл сразу от нескольких запросов.
    private func performRefresh() async -> Bool {
        guard let onUnauthorized else { return false }
        if let refreshTask { return await refreshTask.value }
        let task = Task { await onUnauthorized() }
        refreshTask = task
        let success = await task.value
        refreshTask = nil
        return success
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let code: String
    let message: String
    let requestId: String?
}

private extension ISO8601DateFormatter {
    static let api: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}


private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
