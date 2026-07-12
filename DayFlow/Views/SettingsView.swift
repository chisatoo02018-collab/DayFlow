import SwiftUI
import UniformTypeIdentifiers

/// Obsidian sync setup for DayFlow: pick the local vault folder and/or configure the
/// GitHub mirror. All optional — the 時間割 editor works without any of it.
///
/// The GitHub token is entered by the user directly into the secure field; the app
/// stores it in the Keychain and never displays it back.
struct SettingsView: View {
    @Bindable var writer: VaultWriter
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var tokenInput = ""

    var body: some View {
        @Bindable var sync = writer.github

        NavigationStack {
            Form {
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
            Text("Obsidian Vaultのフォルダを選ぶと、時間割が `TimeLog/年/月/日付.md` に書き出されます。")
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
