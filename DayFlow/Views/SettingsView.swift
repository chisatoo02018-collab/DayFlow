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
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var tokenInput = ""
    @State private var isRequestingHealth = false
    @State private var healthSyncNote: String?

    var body: some View {
        @Bindable var sync = writer.github

        NavigationStack {
            Form {
                healthSection

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
