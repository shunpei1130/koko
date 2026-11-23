import Foundation
import Security

struct Run: Decodable, Identifiable {
    let id: UUID
    let startsAt: Date
    let meetZoneId: String
    let cafeName: String
    let vibeTag: String
    let womenOnly: Bool
    let spotsLeft: Int
    let hostName: String
    let hostEmoji: String
    let isHost: Bool
    let participation: String?
    let soloWelcome: Bool
    let firstTimeWelcome: Bool
    let weeklyActive: Bool
    let seriesId: UUID?
    let followed: Bool
    let canCheckIn: Bool

    var zone: String {
        [
            "takebashi": "竹橋", "hirakawamon": "平川門", "otemachi": "大手町",
            "nijubashi": "二重橋前", "sakuradamon": "桜田門", "iwatabashi": "祝田橋",
            "hanzomon": "半蔵門", "chidorigafuchi": "千鳥ヶ淵"
        ][meetZoneId] ?? meetZoneId
    }

    var invite: URL { API.site.appending(path: "invite").appending(path: id.uuidString.lowercased()) }

    var dateLabel: String {
        var style = Date.FormatStyle().month().day().weekday(.abbreviated).hour().minute()
        style.locale = Locale(identifier: "ja_JP")
        style.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return startsAt.formatted(style)
    }
}

struct ArrivalMember: Decodable {
    let name: String
    let emoji: String
    let isSelf: Bool
}

struct Session: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decode(String.self, forKey: .refreshToken)
        expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? values.decodeIfPresent(TimeInterval.self, forKey: .expiresIn).map { Date().addingTimeInterval($0) }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accessToken, forKey: .accessToken)
        try values.encode(refreshToken, forKey: .refreshToken)
        try values.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

enum APIError: LocalizedError {
    case missingKey, rejected(Int, String), unexpected, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .missingKey: return "アプリの接続設定が必要です。"
        case .rejected(_, "event_full"): return "この募集は満席になったよ。"
        case .rejected(_, "event_unavailable"): return "この募集の受付は終了したよ。"
        case .rejected(429, _): return "少し時間を空けてから試してね。"
        case .rejected(401, _): return "もう一度ログインしてね。"
        default: return "うまくつながらなかったよ。もう一度試してね。"
        }
    }
}

struct API {
    static let site = URL(string: "https://koko-mu-orcin.vercel.app")!
    static let base = URL(string: "https://uineosvdldnurtaemnrk.supabase.co")!
    private var key: String {
        Bundle.main.object(forInfoDictionaryKey: "KokoSupabasePublishableKey") as? String ?? ""
    }

    func request(_ path: String, payload: [String: Any], token: String? = nil, query: URLQueryItem? = nil, prefer: String? = nil) async throws -> Data {
        guard key.hasPrefix("sb_publishable_") else { throw APIError.missingKey }
        var components = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        components.path = path
        if let query { components.queryItems = [query] }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.unexpected }
        guard (200..<300).contains(response.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError.rejected(response.statusCode, json?["message"] as? String ?? "")
        }
        return data
    }

    func runs(token: String? = nil) async throws -> [Run] {
        let data = try await request("/rest/v1/rpc/koko_community_events", payload: [:], token: token)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = parser.date(from: value) { return date }
            parser.formatOptions = [.withInternetDateTime]
            guard let date = parser.date(from: value) else { throw APIError.unexpected }
            return date
        }
        return try decoder.decode([Run].self, from: data)
    }

    func sendCode(_ email: String) async throws {
        _ = try await request("/auth/v1/otp", payload: ["email": email, "create_user": true])
    }

    func verify(_ email: String, code: String) async throws -> Session {
        let data = try await request("/auth/v1/verify", payload: ["type": "email", "email": email, "token": code])
        return try decodeSession(data)
    }

    func refresh(_ session: Session) async throws -> Session {
        let data = try await request("/auth/v1/token", payload: ["refresh_token": session.refreshToken],
            query: URLQueryItem(name: "grant_type", value: "refresh_token"))
        return try decodeSession(data)
    }

    func join(_ id: UUID, token: String) async throws {
        _ = try await request("/rest/v1/rpc/request_koko_event", payload: ["target_event": id.uuidString.lowercased()], token: token)
    }

    func follow(_ id: UUID, enabled: Bool, token: String) async throws {
        _ = try await request("/rest/v1/rpc/koko_follow_weekly",
            payload: ["series": id.uuidString.lowercased(), "enabled": enabled], token: token)
    }

    func arrivals(_ id: UUID, token: String) async throws -> [ArrivalMember] {
        let data = try await request("/rest/v1/rpc/koko_arrivals",
            payload: ["target_event": id.uuidString.lowercased()], token: token)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ArrivalMember].self, from: data)
    }

    func setArrival(_ id: UUID, arrived: Bool, token: String) async throws {
        _ = try await request("/rest/v1/rpc/koko_set_arrived",
            payload: ["target_event": id.uuidString.lowercased(), "arrived": arrived], token: token)
    }

    func signOut(_ token: String) async throws {
        _ = try await request("/auth/v1/logout", payload: [:], token: token,
            query: URLQueryItem(name: "scope", value: "local"))
    }

    private func decodeSession(_ data: Data) throws -> Session {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Session.self, from: data)
    }
}

enum SessionStorage {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.koko.community") + ".session",
        kSecAttrAccount as String: "supabase"
    ]

    static func read() -> Session? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func write(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw APIError.keychain(update) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIError.keychain(status) }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain(status) }
    }
}
