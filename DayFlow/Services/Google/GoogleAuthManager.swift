import Foundation
import GoogleSignIn
import UIKit

enum GoogleAuthError: Error {
    case notSignedIn
}

@Observable
final class GoogleAuthManager {
    private(set) var currentUser: GIDGoogleUser?

    var isSignedIn: Bool { currentUser != nil }
    var userEmail: String? { currentUser?.profile?.email }

    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/tasks"
    ]

    func restorePreviousSignIn() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        let user: GIDGoogleUser? = await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user)
            }
        }
        await MainActor.run { self.currentUser = user }
    }

    @MainActor
    func signIn(presenting viewController: UIViewController) async throws {
        let user: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: Self.scopes
            ) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = signInResult?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: GoogleAuthError.notSignedIn)
                }
            }
        }
        currentUser = user
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }

    /// Returns a valid access token, transparently refreshing it first if it's expired.
    func accessToken() async throws -> String {
        guard let user = currentUser else { throw GoogleAuthError.notSignedIn }
        let refreshed: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let refreshedUser {
                    continuation.resume(returning: refreshedUser)
                } else {
                    continuation.resume(throwing: GoogleAuthError.notSignedIn)
                }
            }
        }
        currentUser = refreshed
        return refreshed.accessToken.tokenString
    }
}

extension UIApplication {
    var rootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
    }
}
