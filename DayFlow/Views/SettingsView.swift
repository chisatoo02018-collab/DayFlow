import SwiftUI
import UniformTypeIdentifiers

/// Obsidian sync setup for DayFlow: pick the local vault folder and/or configure the
/// GitHub mirror. All optional — the 時間割 editor works without any of it.
///
/// The GitHub token is entered by the user directly into the secure field; the app
/// stores it in the Keychain and never displays it back.
struct SettingsView: View {
    @Bindable var writer: VaultWriter
    @Bindable var health: HealthService
    @Bindable var placeStore: PlaceStore
    @Bindable var location: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var tokenInput = ""
    @State private var isRequestingHealth = false
    @State private var healthSyncNote: String?
    @State private var pendingKind: PlaceKind?
    @State private var locationNote: String?

    var body: some View {
        @Bindable var sync = writer.github

        NavigationStack {
            Form {
                healthSection

                locationSection

                vaultSection

                Section {
                    Toggle("GitHubミラーを有効化", isOn: $sync.enabled)
                    if sync.enabled {
                        TextField("オーナー (例: chisatoo)", text: $sync.config.owner)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("リポジトリ (例: YotaBrain)", text: $sync.config.repo)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("ブランチ", text: $sync.config.branch)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()

                        HStack {
                            SecureField(sync.hasToken ? "トークン設定済み（再入力で更新）" : "GitHubトークン",
                                        text: $tokenInput)
                            if !tokenInput.isEmpty {
                                Button("保存") { sync.setToken(tokenInput); tokenInput = "" }
                            }
                        }
                        if sync.hasToken {
                            Button("トークンを削除", role: .destructive) { sync.setToken(nil) }
                        }
                        statusRow(sync: sync)
                    }
                } header: {
                    Text("Obsidian同期（GitHub）")
                } footer: {
                    Text("iPhone単体で正典VaultのGitリポジトリへ直接コミットします。fine-grained PAT（Contents: Read/Write）を発行して貼り付けてください。トークンはKeychainに保存され表示されません。")
                }

                aboutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } }
            }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { writer.selectVault(url) }
            }
        }
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        Section {
            if location.isAuthorizedAlways {
                Label("常に許可済み — 出入りを自動記録します", systemImage: "location.fill")
                    .font(.footnote).foregroundStyle(.green)
            } else {
                Button {
                    location.requestAuthorization()
                } label: {
                    Label("位置情報を「常に許可」にする", systemImage: "location")
                }
                Text("バックグラウンドで自宅・職場の出入りを検知するには「常に許可」が必要です。現在地の登録だけなら使用中の許可でもできます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(PlaceKind.allCases, id: \.self) { kind in
                placeRow(kind)
            }

            if placeStore.isConfigured {
                Toggle("出社・移動を実績リングに自動反映", isOn: $location.importsToRing)
            }
            if let note = locationNote {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("所在地（自宅・職場）")
        } footer: {
            Text("自宅と職場を現在地から登録すると、その出入りを自動で記録します。所在地リングに色分け表示され、職場滞在は「仕事」、自宅↔職場の移動は「移動」として実績リングの空き時間だけを自動で埋めます（手描きは上書きしません）。座標は端末内に保存されます。")
        }
    }

    @ViewBuilder
    private func placeRow(_ kind: PlaceKind) -> some View {
        let isSet = placeStore.places.contains { $0.kind == kind }
        Button {
            setCurrentLocation(as: kind)
        } label: {
            HStack {
                Label(kind.label, systemImage: kind.symbol)
                    .foregroundStyle(kind.color)
                Spacer()
                if pendingKind == kind {
                    ProgressView()
                } else {
                    Text(isSet ? "設定済み・更新" : "現在地を設定")
                        .font(.footnote)
                        .foregroundStyle(isSet ? .secondary : Color.accentColor)
                }
            }
        }
        .disabled(pendingKind != nil)
    }

    /// Requests one location fix and stores it as the given place kind (home/office).
    /// The place keeps the same geofence radius default; the user rarely needs to tune it.
    private func setCurrentLocation(as kind: PlaceKind) {
        pendingKind = kind
        location.onCurrentLocation = { loc in
            let place = Place(
                id: placeStore.places.first { $0.kind == kind }?.id ?? UUID().uuidString,
                name: kind.label, kind: kind,
                latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude
            )
            placeStore.upsert(place)
            location.refreshMonitoring()
            pendingKind = nil
            locationNote = "\(kind.label)を現在地に設定しました。"
            location.onCurrentLocation = nil
        }
        location.requestCurrentLocation()
    }

    // MARK: - Health

    @ViewBuilder
    private var healthSection: some View {
        Section {
            if !health.isAvailable {
                Label("この端末ではヘルスデータを利用できません", systemImage: "heart.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button {
                    isRequestingHealth = true
                    Task {
                        await health.requestAccess()
                        if health.snapshot.hasAnyData {
                            writer.writeHealth(date: Date(), snapshot: health.snapshot)
                        }
                        isRequestingHealth = false
                    }
                } label: {
                    HStack {
                        Label("ヘルスへのアクセスを許可", systemImage: "heart.fill")
                        Spacer()
                        if isRequestingHealth { ProgressView() }
                    }
                }
                .disabled(isRequestingHealth)

                if health.snapshot.hasAnyData {
                    Label("取得済み — 今日のデータを読み込めています", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)

                    Toggle("睡眠を実績リングの正とする", isOn: $health.importsSleepToRing)
                    Toggle("運動を実績リングに反映（タグ）", isOn: $health.importsExerciseToRing)

                    Button {
                        writer.writeHealth(date: Date(), snapshot: health.snapshot)
                        healthSyncNote = writer.isConfigured
                            ? "今日のヘルスをデイリーノートに記録しました。"
                            : "先にローカルVaultかGitHubミラーを設定してください。"
                    } label: {
                        Label("今すぐObsidianに記録", systemImage: "arrow.up.doc")
                    }
                    if let note = healthSyncNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Label("まだデータがありません。許可済みなら『設定 > プライバシーとセキュリティ > ヘルス > DayFlow』で読み取りをオンにしてください。",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple Watch ヘルス連携")
        } footer: {
            Text("Apple Watchの歩数・心拍・睡眠・消費カロリー・運動時間を読み取り、今日タブとデイリーノートの『## ヘルス』に反映します。『睡眠を実績リングの正とする』をオンにすると、実績の睡眠カテゴリをヘルスケアの睡眠から自動で塗ります（手動で塗った他カテゴリは上書きしません）。読み取り専用です。")
        }
    }

    // MARK: - Vault

    private var vaultSection: some View {
        Section {
            if let url = writer.vaultURL {
                LabeledContent("Vault", value: url.lastPathComponent)
                Button("フォルダを変更") { showFolderPicker = true }
                Button("解除", role: .destructive) { writer.resetVault() }
            } else {
                Button("Vaultフォルダを選択") { showFolderPicker = true }
            }
        } header: {
            Text("ローカルVault")
        } footer: {
            Text("Vaultフォルダを選ぶと、詳細な時間割を `inputs/timelog/年/月/日付.md` に保存し、デイリーノートの `## DayFlow` にその日の記録をプロットします。")
        }
    }

    @ViewBuilder
    private func statusRow(sync: GitHubSync) -> some View {
        if let error = sync.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.red)
        } else if !sync.outbox.isEmpty {
            Label("未送信 \(sync.outbox.count) 件（オンライン時に自動送信）", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote).foregroundStyle(.secondary)
        } else if sync.isActive {
            Label("同期準備完了", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        }
    }

    private var aboutSection: some View {
        Section("DayFlowについて") {
            LabeledContent("バージョン", value: Bundle.main.shortVersion)
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}
