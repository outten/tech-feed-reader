import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isSignedIn: Bool
    @Published var errorMessage: String?
    @Published var isBusy = false

    init() {
        isSignedIn = KeychainStore.loadToken() != nil
    }

    func logIn(recoveryCode: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let token = try await APIClient.shared.logIn(recoveryCode: recoveryCode)
            KeychainStore.saveToken(token)
            isSignedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        // Best-effort server-side revoke — a network failure shouldn't
        // block the user from signing out of the app locally.
        try? await APIClient.shared.signOut()
        KeychainStore.deleteToken()
        isSignedIn = false
    }
}
