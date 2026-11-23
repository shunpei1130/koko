import SwiftUI
import MapKit

@main
@MainActor
struct KokoApp: App {
    var body: some Scene {
        WindowGroup { CommunityView() }
    }
}

@MainActor
final class CommunityModel: ObservableObject {
    @Published var runs: [Run] = []
    @Published var session = SessionStorage.read()
    @Published var error: String?
    @Published var loading = false
    @Published var profileName: String?
    @Published var profileLoaded = false

    let api = API()

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            runs = try await api.runs(token: try await activeToken())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendCode(_ email: String) async throws { try await api.sendCode(email) }

    func signIn(_ email: String, code: String) async throws {
        let next = try await api.verify(email, code: code)
        try SessionStorage.write(next)
        session = next
        await loadProfile()
        await load()
    }

    func signOut() async throws {
        if let token = try await activeToken() { try await api.signOut(token) }
        try SessionStorage.clear()
        session = nil
        profileName = nil
        profileLoaded = false
        runs = []
        await load()
    }

    func loadProfile() async {
        guard session != nil else { return }
        do {
            profileName = try await api.read("koko_my_profile", token: try await requiredToken())
            profileLoaded = true
        } catch {
            profileLoaded = false
        }
    }

    func createProfile(_ name: String, emoji: String) async throws {
        try await api.createProfile(name, emoji: emoji, token: try await requiredToken())
        await loadProfile()
    }

    func deleteAccount() async throws {
        _ = try await api.rpc("koko_delete_account", token: try await requiredToken())
        session = nil
        profileName = nil
        profileLoaded = false
        runs = []
        try SessionStorage.clear()
        await load()
    }

    func join(_ run: Run) async throws {
        let token = try await requiredToken()
        try await api.join(run.id, token: token)
        await load()
    }

    func follow(_ run: Run) async throws {
        guard let series = run.seriesId else { throw APIError.unexpected }
        try await api.follow(series, enabled: !run.followed, token: try await requiredToken())
        await load()
    }

    func arrivals(for run: Run) async throws -> [ArrivalMember] {
        try await api.arrivals(run.id, token: try await requiredToken())
    }

    func setArrival(for run: Run, arrived: Bool) async throws {
        try await api.setArrival(run.id, arrived: arrived, token: try await requiredToken())
    }

    func requiredToken() async throws -> String {
        guard let token = try await activeToken() else { throw APIError.rejected(401, "") }
        return token
    }

    private func activeToken() async throws -> String? {
        guard let current = session else { return nil }
        guard let expiry = current.expiresAt, expiry.timeIntervalSinceNow < 60 else { return current.accessToken }
        do {
            let renewed = try await api.refresh(current)
            try SessionStorage.write(renewed)
            session = renewed
            return renewed.accessToken
        } catch APIError.rejected(let status, _) where status == 400 || status == 401 {
            try SessionStorage.clear()
            session = nil
            profileName = nil
            profileLoaded = false
            return nil
        }
    }
}

enum RunFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case solo = "ひとり参加歓迎"
    case beginner = "初参加歓迎"
    case weekly = "毎週開催"

    var id: Self { self }
    func includes(_ run: Run) -> Bool {
        switch self {
        case .all: return true
        case .solo: return run.soloWelcome
        case .beginner: return run.firstTimeWelcome
        case .weekly: return run.weeklyActive
        }
    }
}

@MainActor
struct CommunityView: View {
    @StateObject private var model = CommunityModel()
    @AppStorage("savedRunIDs") private var savedIDs = ""
    @State private var filter = RunFilter.all
    @State private var showingAccount = false
    @State private var showingCreate = false

    private var saved: Set<String> { Set(savedIDs.split(separator: ",").map(String.init)) }

    var body: some View {
        TabView {
            NavigationStack {
                feed(model.runs.filter(filter.includes), savedOnly: false)
                    .navigationTitle("koko.")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(model.session == nil ? "ログイン" : "アカウント") { showingAccount = true }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("募集作成", systemImage: "plus") {
                                if model.profileName != nil { showingCreate = true }
                                else { showingAccount = true }
                            }
                        }
                    }
            }
            .tabItem { Label("みつける", systemImage: "ticket") }

            NavigationStack {
                feed(model.runs.filter { saved.contains($0.id.uuidString) }, savedOnly: true)
                    .navigationTitle("保存した募集")
            }
            .tabItem { Label("保存", systemImage: "bookmark") }

            NavigationStack {
                ImperialMap()
                    .navigationTitle("集合エリア")
            }
            .tabItem { Label("マップ", systemImage: "map") }

            NavigationStack {
                StampView(model: model) { showingAccount = true }
            }
            .tabItem { Label("おつラン！", systemImage: "sparkles") }
        }
        .tint(Color(red: 0.56, green: 0.20, blue: 0.31))
        .task { await model.load(); await model.loadProfile() }
        .sheet(isPresented: $showingAccount) { AccountView(model: model) }
        .sheet(isPresented: $showingCreate) { CreateRunView(model: model) }
    }

    private func feed(_ runs: [Run], savedOnly: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !savedOnly {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(RunFilter.allCases) { item in
                                Button(item.rawValue) { filter = item }
                                    .buttonStyle(.bordered)
                                    .tint(filter == item ? Color.accentColor : .secondary)
                                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                if let error = model.error {
                    ContentUnavailableView {
                        Label("募集を読み込めませんでした", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("再読み込み") { Task { await model.load() } }
                    }
                } else if model.loading && runs.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if runs.isEmpty {
                    ContentUnavailableView(
                        savedOnly ? "保存した募集はありません" : "募集中のゆるランはありません",
                        systemImage: savedOnly ? "bookmark" : "ticket"
                    )
                }

                ForEach(runs) { run in
                    NavigationLink {
                        RunDetails(model: model, initial: run) { showingAccount = true }
                    } label: {
                        RunCard(run: run)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(saved.contains(run.id.uuidString) ? "保存を解除" : "募集を保存",
                               systemImage: "bookmark") { toggleSave(run.id) }
                        ShareLink(item: run.invite)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            toggleSave(run.id)
                        } label: {
                            Image(systemName: saved.contains(run.id.uuidString) ? "bookmark.fill" : "bookmark")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(saved.contains(run.id.uuidString) ? "保存を解除" : "募集を保存")
                        .buttonStyle(.plain)
                    }
                }

            }
            .padding()
        }
        .background(Color(red: 1, green: 0.98, blue: 0.96))
        .refreshable { await model.load() }
    }

    private func toggleSave(_ id: UUID) {
        var next = saved
        if next.remove(id.uuidString) == nil { next.insert(id.uuidString) }
        savedIDs = next.sorted().joined(separator: ",")
    }
}

struct RunCard: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(run.dateLabel).font(.headline)
            Label(run.zone + "集合", systemImage: "mappin")
            Text("☕ " + run.cafeName)
            Text(run.hostEmoji + " " + run.hostName + " · " + run.vibeTag)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if run.soloWelcome || run.firstTimeWelcome || run.weeklyActive {
                Text([
                    run.soloWelcome ? "ひとり参加歓迎" : nil,
                    run.firstTimeWelcome ? "初参加歓迎" : nil,
                    run.weeklyActive ? "毎週開催" : nil
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.trailing, 33)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(Color.black.opacity(0.86))
    }
}

@MainActor
struct RunDetails: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CommunityModel
    let initial: Run
    let onSignIn: () -> Void
    @State private var working = false
    @State private var status: String?
    @State private var arrivals: [ArrivalMember]?
    @State private var hostId: UUID?

    private var run: Run { model.runs.first { $0.id == initial.id } ?? initial }

    var body: some View {
        List {
            Section {
                Text(run.dateLabel)
                Label(run.zone + "集合", systemImage: "mappin")
                Text("☕ " + run.cafeName)
                Text(run.hostEmoji + " " + run.hostName)
                if run.womenOnly { Text("女性限定") }
                Text("残り " + String(run.spotsLeft) + " 枠")
            }
            Section {
                if run.isHost {
                    Text("あなたの募集")
                    if run.startsAt > .now || run.weeklyActive {
                        NavigationLink("参加申請を管理") { RequestsView(model: model, run: run) }
                    }
                } else if let participation = run.participation {
                    Text(["pending": "承認待ち", "approved": "参加決定", "declined": "招待見送り"][participation] ?? "申請済み")
                } else if run.spotsLeft > 0, run.startsAt > .now {
                    Button("参加リクエスト") { requestJoin() }
                        .disabled(working)
                }
                if let status { Text(status).font(.footnote) }
                if run.weeklyActive && !run.isHost {
                    Button(run.followed ? "定例フォローを解除" : "毎週の募集をフォロー") {
                        perform { try await model.follow(run) }
                    }
                    .disabled(working)
                }
                ShareLink("招待リンクを共有", item: run.invite)
                Link("Webで募集を開く", destination: run.invite)
                if let hostId, !run.isHost, model.profileName != nil {
                    SafetyMenu(model: model, user: hostId, event: run.id) { dismiss() }
                }
            }
            if run.canCheckIn && model.session != nil {
                Section("集合・着いたよ") {
                    Text("当日の主催者と承認済みの参加者に表示されます。").font(.footnote)
                    if let arrivals {
                        ForEach(arrivals.indices, id: \.self) { index in
                            let member = arrivals[index]
                            Text(member.emoji + " " + (member.isSelf ? "あなた" : member.name))
                        }
                        let here = arrivals.contains(where: \.isSelf)
                        Button(here ? "到着を取り消す" : "着いたよ") {
                            perform {
                                try await model.setArrival(for: run, arrived: !here)
                                self.arrivals = try await model.arrivals(for: run)
                            }
                        }
                        .disabled(working)
                    }
                    Button("到着状況を更新") { perform { arrivals = try await model.arrivals(for: run) } }
                        .disabled(working)
                }
            }
        }
        .navigationTitle("ゆるラン")
        .task(id: model.session != nil) {
            hostId = nil
            guard model.session != nil, !run.isHost else { return }
            hostId = try? await model.api.read("koko_event_host",
                ["target_event": run.id.uuidString.lowercased()], token: try await model.requiredToken())
        }
        .task(id: run.canCheckIn && model.session != nil) {
            guard run.canCheckIn && model.session != nil else { arrivals = nil; return }
            do { arrivals = try await model.arrivals(for: run) }
            catch { status = error.localizedDescription }
        }
    }

    private func requestJoin() {
        perform {
            try await model.join(run)
            status = "参加リクエストを送ったよ。"
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard model.profileName != nil else { onSignIn(); return }
        working = true
        status = nil
        Task {
            defer { working = false }
            do { try await action() }
            catch { status = error.localizedDescription }
        }
    }
}

@MainActor
struct AccountView: View {
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var error: String?
    @State private var name = ""
    @State private var emoji = "🎀"
    @State private var agreed = false
    @State private var confirmingDeletion = false
    @AppStorage("savedRunIDs") private var savedIDs = ""

    var body: some View {
        NavigationStack {
            Form {
                if model.session != nil {
                    if let profileName = model.profileName {
                        Text(profileName)
                        NavigationLink("ブロックしたユーザー") { BlockedUsersView(model: model) }
                    } else if model.profileLoaded {
                        TextField("表示名（20文字以内）", text: $name)
                        Picker("アイコン", selection: $emoji) {
                            ForEach(["🎀", "🌷", "🍑", "🥐", "☕", "✨", "🌿", "🫧"], id: \.self) { Text($0).tag($0) }
                        }
                        Button("プロフィールを作成") {
                            perform { try await model.createProfile(name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji); dismiss() }
                        }
                        .disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 20)
                    } else {
                        Button("プロフィールを読み込む") { Task { await model.loadProfile() } }.disabled(working)
                    }
                    Button("ログアウト", role: .destructive) { perform { try await model.signOut(); dismiss() } }
                        .disabled(working)
                    Button("アカウントを削除", role: .destructive) { confirmingDeletion = true }
                        .disabled(working)
                } else {
                    TextField("メールアドレス", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .disabled(codeSent || working)
                    if codeSent {
                        TextField("確認コード", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("ログイン") {
                            perform {
                                try await model.signIn(email, code: code)
                                if model.profileName != nil { dismiss() }
                            }
                        }
                        .disabled(working || code.count < 6)
                        Button("メールアドレスを変更") { codeSent = false; code = ""; error = nil }
                            .disabled(working)
                    } else {
                        Button("コードを送る") {
                            email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            perform { try await model.sendCode(email); codeSent = true }
                        }
                        .disabled(working || !email.contains("@") || !agreed)
                        Toggle("コミュニティルールを確認しました", isOn: $agreed).disabled(working)
                    }
                }
                Section("サポート") {
                    Link("コミュニティルール", destination: API.communityRules)
                    Link("プライバシーポリシー", destination: API.privacy)
                    Link("お問い合わせ", destination: API.support)
                }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle(model.session == nil ? "ログイン" : "アカウント")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .interactiveDismissDisabled(working)
            .alert("アカウントを完全に削除しますか？", isPresented: $confirmingDeletion) {
                Button("削除する", role: .destructive) {
                    perform { try await model.deleteAccount(); savedIDs = ""; dismiss() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("Web版とiOS版で使っている同じアカウント、プロフィール、募集、参加履歴などが削除されます。元には戻せません。")
            }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { try await action() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct ImperialMap: View {
    private struct Point: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D

        init(_ name: String, _ latitude: Double, _ longitude: Double) {
            id = name
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private let center = CLLocationCoordinate2D(latitude: 35.6847, longitude: 139.7528)
    private let meetingPoints: [Point] = [
        Point("竹橋", 35.6905, 139.7565), Point("平川門", 35.6894, 139.7585),
        Point("大手町", 35.6859, 139.7613), Point("二重橋前", 35.6802, 139.7602),
        Point("桜田門", 35.6778, 139.7542), Point("祝田橋", 35.6761, 139.7561),
        Point("半蔵門", 35.6852, 139.7447), Point("千鳥ヶ淵", 35.6908, 139.7479)
    ]

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 2200, longitudinalMeters: 2300))) {
            ForEach(meetingPoints) { point in
                Marker(point.id, coordinate: point.coordinate)
                    .tint(Color(red: 0.56, green: 0.20, blue: 0.31))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("募集に表示された集合エリアを確認できます。")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.regularMaterial)
        }
    }
}
