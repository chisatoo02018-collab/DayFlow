import SwiftUI
import GoogleSignInSwift

struct SettingsView: View {
    @Environment(GoogleAuthManager.self) private var authManager
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Google連携") {
                    if let email = authManager.userEmail {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("連携済み")
                                    .font(.subheadline.weight(.semibold))
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("連携を解除", role: .destructive) {
                            authManager.signOut()
                        }
                    } else {
                        GoogleSignInButton(scheme: .light, style: .wide) {
                            signIn()
                        }
                        .disabled(isSigningIn)
                        .listRowInsets(EdgeInsets())
                        .padding(8)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Google CalendarとGoogle Tasksの予定・タスクを読み込み、Appleのカレンダー/リマインダーと統合して表示します。タスクの完了/未完了の切り替えにも対応しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }

    private func signIn() {
        guard let rootVC = UIApplication.shared.rootViewController else { return }
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signIn(presenting: rootVC)
            } catch {
                errorMessage = "連携に失敗しました: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }
}
