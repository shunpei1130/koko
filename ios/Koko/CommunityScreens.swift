import SwiftUI

@MainActor
struct CreateRunView: View {
    @ObservedObject var model: CommunityModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RunDraft()
    @State private var eventId = UUID()
    @State private var saved = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if saved {
                    Section {
                        Text("募集を公開しました。").font(.headline)
                        ShareLink("招待リンクを共有", item: API.site.appending(path: "invite").appending(path: eventId.uuidString.lowercased()))
                    }
                } else {
                    Section("集合") {
                        Picker("日時", selection: $draft.time) {
                            ForEach(RunTime.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("集合エリア", selection: $draft.zone) {
                            ForEach(RunDraft.zones.indices, id: \.self) { index in
                                Text(RunDraft.zones[index].1).tag(RunDraft.zones[index].0)
                            }
                        }
                        Picker("ご褒美カフェ", selection: $draft.cafe) {
                            ForEach(RunDraft.cafes, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("雰囲気", selection: $draft.vibe) {
                            ForEach(RunDraft.vibes, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("参加条件") {
                        Stepper("定員（主催者を含む）：\(draft.capacity)人", value: $draft.capacity, in: 2...6)
                        Toggle("女性限定", isOn: $draft.womenOnly)
                        Toggle("ひとり参加歓迎", isOn: $draft.soloWelcome)
                        Toggle("初参加歓迎", isOn: $draft.firstTimeWelcome)
                        Toggle("毎週同じ曜日・時間", isOn: $draft.weekly)
                    }
                    if let error { Text(error).foregroundStyle(.secondary) }
                    Button("募集を公開する") { publish() }.disabled(working)
                }
            }
            .disabled(working)
            .navigationTitle("ゆるランをたてる")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "完了" : "閉じる") { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func publish() {
        working = true
        Task {
            defer { working = false }
            do {
                let token = try await model.requiredToken()
                do { try await model.api.createRun(draft, id: eventId, token: token) }
                catch APIError.rejected(409, _) {
                    await model.load()
                    guard model.runs.contains(where: { $0.id == eventId && $0.isHost }) else { throw APIError.unexpected }
                }
                await model.load()
                saved = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor
struct BlockedUsersView: View {
    @ObservedObject var model: CommunityModel
    @State private var people: [BlockedPerson]?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary) }
            if people == nil && error == nil { ProgressView() }
            if let people, people.isEmpty { Text("ブロックしたユーザーはいません。") }
            ForEach(people ?? []) { person in
                HStack {
                    Text(person.name)
                    Spacer()
                    Button("解除する") { unblock(person) }.disabled(busy)
                }
            }
        }
        .navigationTitle("ブロックしたユーザー")
        .task { await load() }
    }

    private func load() async {
        do {
            people = try await model.api.read("koko_blocked_users", token: try await model.requiredToken())
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func unblock(_ person: BlockedPerson) {
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await model.api.rpc("koko_block_user",
                    ["target_user": person.id.uuidString.lowercased(), "enabled": false],
                    token: try await model.requiredToken())
                await load()
                await model.load()
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor
struct RequestsView: View {
    @ObservedObject var model: CommunityModel
    let run: Run

    @State private var applicants: [Applicant]?
    @State private var error: String?
    @State private var working = false
    @State private var weekly = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary) }
            if let applicants, applicants.isEmpty { Text("参加申請はまだありません。") }
            if applicants == nil && error == nil { ProgressView() }
            ForEach(applicants ?? []) { applicant in
                Section(applicant.avatarEmoji + " " + applicant.displayName) {
                    Text(["pending": "承認待ち", "approved": "承認済み", "declined": "見送り"][applicant.status] ?? "")
                    if applicant.status == "pending" {
                        Button("参加を承認する") { decide(applicant, true) }.disabled(working)
                        Button("見送る") { decide(applicant, false) }.disabled(working)
                    }
                    SafetyMenu(model: model, user: applicant.userId, event: run.id) { await load() }
                }
            }
            if weekly, let series = run.seriesId {
                Button("次回以降の自動募集を止める", role: .destructive) {
                    Task {
                        working = true
                        defer { working = false }
                        do {
                            _ = try await model.api.rpc("koko_stop_weekly",
                                ["series": series.uuidString.lowercased()], token: try await model.requiredToken())
                            weekly = false
                            await model.load()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(working)
            }
        }
        .navigationTitle("参加申請")
        .task { weekly = run.weeklyActive; await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            applicants = try await model.api.read("koko_event_requests",
                ["target_event": run.id.uuidString.lowercased()], token: try await model.requiredToken())
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func decide(_ applicant: Applicant, _ approve: Bool) {
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await model.api.rpc("decide_koko_request", [
                    "target_event": run.id.uuidString.lowercased(),
                    "applicant": applicant.id.uuidString.lowercased(),
                    "approve": approve
                ], token: try await model.requiredToken())
                await load()
                await model.load()
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor
struct StampView: View {
    @ObservedObject var model: CommunityModel
    let onSignIn: () -> Void
    @State private var people: [StampPeer]?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        List {
            if model.session == nil {
                Button("ログインしてスタンプを送る", action: onSignIn)
            } else {
                if let error { Text(error).foregroundStyle(.secondary) }
                if let people, people.isEmpty { Text("一緒に走った仲間がここに表示されます。") }
                if people == nil && error == nil { ProgressView() }
                ForEach(people ?? []) { person in
                    Section(person.emoji + " " + person.name) {
                        Text(person.context).font(.footnote)
                        ForEach(Stamp.allCases) { stamp in
                            let sent = person.sentStamps.contains(stamp.rawValue)
                            Button(sent ? stamp.label + "（送信済み）" : stamp.label) { send(stamp, to: person) }
                                .disabled(working || sent)
                        }
                        if let ig = person.ig, !ig.isEmpty {
                            Link("Instagramを開く", destination: URL(string: "https://www.instagram.com")!.appending(path: ig))
                        }
                        SafetyMenu(model: model, user: person.id) { await load() }
                    }
                }
            }
        }
        .navigationTitle("おつラン！")
        .task(id: model.session != nil) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard model.session != nil else { people = nil; return }
        do {
            people = try await model.api.read("koko_otsurun", token: try await model.requiredToken())
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func send(_ stamp: Stamp, to person: StampPeer) {
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await model.api.rpc("send_koko_stamp", [
                    "recipient": person.id.uuidString.lowercased(), "encounter_day": person.runDate, "stamp": stamp.rawValue
                ], token: try await model.requiredToken())
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor
struct SafetyMenu: View {
    @ObservedObject var model: CommunityModel
    let user: UUID
    var event: UUID? = nil
    let onBlock: () async -> Void

    @State private var reporting = false
    @State private var blocking = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Menu("安全メニュー", systemImage: "shield") {
            Button("通報する", systemImage: "flag") { reporting = true }
            Button("ブロックする", systemImage: "hand.raised", role: .destructive) { blocking = true }
        }
        .disabled(busy)
        .confirmationDialog("通報理由を選択", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.label) { update(reason: reason) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("通報は運営が確認します。")
        }
        .alert("このユーザーをブロックしますか？", isPresented: $blocking) {
            Button("ブロックする", role: .destructive) { update() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("お互いの募集やスタンプが表示されなくなります。")
        }
        if let message { Text(message).font(.footnote) }
    }

    private func update(reason: ReportReason? = nil) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let token = try await model.requiredToken()
                var payload: [String: Any] = ["target_user": user.uuidString.lowercased()]
                if let reason {
                    payload["reason_key"] = reason.rawValue
                    if let event { payload["target_event"] = event.uuidString.lowercased() }
                    _ = try await model.api.rpc("koko_report_user", payload, token: token)
                    message = "通報を受け付けました。"
                } else {
                    payload["enabled"] = true
                    _ = try await model.api.rpc("koko_block_user", payload, token: token)
                    await onBlock()
                    await model.load()
                }
            } catch { message = error.localizedDescription }
        }
    }
}
