import Foundation

enum RunTime: String, CaseIterable, Identifiable {
    case tomorrow = "明日 7:30"
    case wednesday = "水曜 19:30"
    case saturday = "土曜 8:30"
    case sunday = "日曜 9:00"
    var id: Self { self }

    func nextDate(after now: Date = .now) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        if self == .tomorrow {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow)
        }
        let timing: (weekday: Int, hour: Int, minute: Int)
        switch self {
        case .tomorrow: return nil
        case .wednesday: timing = (4, 19, 30)
        case .saturday: timing = (7, 8, 30)
        case .sunday: timing = (1, 9, 0)
        }
        return calendar.nextDate(after: now, matching: DateComponents(
            hour: timing.hour, minute: timing.minute, second: 0, weekday: timing.weekday
        ), matchingPolicy: .nextTime)
    }
}

struct RunDraft {
    var time = RunTime.sunday
    var zone = "takebashi"
    var cafe = "丸の内ベーカリー"
    var vibe = "おしゃべりペース"
    var capacity = 4
    var womenOnly = true
    var weekly = false
    var soloWelcome = false
    var firstTimeWelcome = false

    static let zones = [
        ("takebashi", "竹橋"), ("hirakawamon", "平川門"), ("otemachi", "大手町"), ("nijubashi", "二重橋前"),
        ("sakuradamon", "桜田門"), ("iwatabashi", "祝田橋"), ("hanzomon", "半蔵門"), ("chidorigafuchi", "千鳥ヶ淵")
    ]
    static let cafes = ["丸の内ベーカリー", "日比谷スタンドコーヒー", "麹町ドーナツカフェ", "大手町抹茶スタンド"]
    static let vibes = ["おしゃべりペース", "写真メイン", "初心者だけ", "歩き混じりOK"]
}

struct Applicant: Decodable, Identifiable {
    let userId: UUID
    let displayName: String
    let avatarEmoji: String
    let status: String
    var id: UUID { userId }
}

struct StampPeer: Decodable, Identifiable {
    let id: UUID
    let name: String
    let emoji: String
    let context: String
    let runDate: String
    let sentStamps: [String]
    let theySent: Bool
    let ig: String?
}

enum Stamp: String, CaseIterable, Identifiable {
    case otsurun, asakatsu, wear, again
    var id: Self { self }
    var label: String {
        switch self {
        case .otsurun: return "おつラン！✨"
        case .asakatsu: return "朝活えらい☀️"
        case .wear: return "ウェア可愛い🎀"
        case .again: return "また走ろ☕"
        }
    }
}

struct BlockedPerson: Decodable, Identifiable {
    let id: UUID
    let name: String
}

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment, spam, unsafe, other
    var id: Self { self }
    var label: String {
        switch self {
        case .harassment: return "嫌がらせ・不適切な言動"
        case .spam: return "スパム・勧誘"
        case .unsafe: return "危険・安全上の問題"
        case .other: return "その他"
        }
    }
}

extension API {
    static let support = URL(string: "mailto:info.mobbymobbymobby@gmail.com")!
    static var privacy: URL { site.appending(path: "privacy") }
    static var communityRules: URL { site.appending(path: "community-rules") }

    func rpc(_ name: String, _ payload: [String: Any] = [:], token: String) async throws -> Data {
        try await request("/rest/v1/rpc/" + name, payload: payload, token: token)
    }

    func read<T: Decodable>(_ name: String, _ payload: [String: Any] = [:], token: String) async throws -> T {
        let data = try await rpc(name, payload, token: token)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func createRun(_ draft: RunDraft, id: UUID, token: String) async throws {
        guard let start = draft.time.nextDate() else { throw APIError.unexpected }
        let eventId = id.uuidString.lowercased()
        let seriesId: Any = draft.weekly ? eventId as Any : NSNull()
        _ = try await request("/rest/v1/run_events", payload: [
            "id": eventId, "starts_at": ISO8601DateFormatter().string(from: start),
            "meet_zone_id": draft.zone, "cafe_name": draft.cafe, "vibe_tag": draft.vibe,
            "women_only": draft.womenOnly, "max_members": draft.capacity,
            "solo_welcome": draft.soloWelcome, "first_time_welcome": draft.firstTimeWelcome,
            "weekly_active": draft.weekly, "series_id": seriesId
        ], token: token, prefer: "return=minimal")
    }

    func createProfile(_ name: String, emoji: String, token: String) async throws {
        _ = try await request("/rest/v1/profiles", payload: ["display_name": name, "avatar_emoji": emoji],
            token: token, prefer: "return=minimal")
    }
}
