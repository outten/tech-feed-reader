import SwiftUI

struct AccountView: View {
    @EnvironmentObject var auth: AuthViewModel

    @State private var account: AccountInfo?
    @State private var passkeys: [Passkey] = []
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var newRecoveryCodes: [String]?
    @State private var showingCalendarSheet = false
    @State private var showingDeleteConfirm = false
    @State private var deleteConfirmText = ""

    @State private var exportFileURL: URL?
    @State private var isExporting = false

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let account {
                Section("Profile") {
                    Text("Username: \(account.username)").foregroundStyle(.secondary)
                    TextField("Display name", text: $displayName)
                        .onSubmit { Task { await saveDisplayName() } }
                }
                Section("Recovery Codes") {
                    Text("\(account.recoveryCodesRemaining) remaining")
                    Button("Regenerate Codes") { Task { await regenerateCodes() } }
                }
                Section("Passkeys (\(account.passkeyCount))") {
                    ForEach(passkeys) { passkey in
                        Text(passkey.label ?? "\(passkey.credentialId.prefix(12))…")
                    }
                    .onDelete(perform: revokePasskeys)
                }
                Section("Calendar") {
                    Button("Add Sports Schedule to Calendar") { showingCalendarSheet = true }
                }
                Section("Your Data") {
                    if let exportFileURL {
                        ShareLink("Share Export", item: exportFileURL)
                    } else {
                        Button {
                            Task { await exportData() }
                        } label: {
                            if isExporting { ProgressView() } else { Text("Export My Data") }
                        }
                        .disabled(isExporting)
                    }
                }
                Section {
                    Button("Delete Account", role: .destructive) { showingDeleteConfirm = true }
                }
            }
        }
        .navigationTitle("Account")
        .overlay {
            if isLoading && account == nil { ProgressView() }
        }
        .task { await load() }
        .alert("New Recovery Codes", isPresented: Binding(
            get: { newRecoveryCodes != nil }, set: { if !$0 { newRecoveryCodes = nil } }
        )) {
            Button("Done") { newRecoveryCodes = nil }
        } message: {
            Text((newRecoveryCodes ?? []).joined(separator: "\n") + "\n\nSave these now — they won't be shown again.")
        }
        .sheet(isPresented: $showingCalendarSheet) {
            if let account, let url = URL(string: account.calendarUrl) {
                SafariView(url: url)
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteConfirm) {
            TextField("Type your username to confirm", text: $deleteConfirmText)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { deleteConfirmText = "" }
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently deletes your account and all your data. Type your username (\(account?.username ?? "")) to confirm.")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let accountResult = APIClient.shared.fetchAccount()
            async let passkeysResult = APIClient.shared.fetchPasskeys()
            account = try await accountResult
            passkeys = try await passkeysResult
            displayName = account?.displayName ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDisplayName() async {
        do {
            try await APIClient.shared.updateDisplayName(displayName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func regenerateCodes() async {
        do {
            newRecoveryCodes = try await APIClient.shared.regenerateRecoveryCodes()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revokePasskeys(at offsets: IndexSet) {
        let toRevoke = offsets.map { passkeys[$0] }
        Task {
            for passkey in toRevoke {
                do {
                    try await APIClient.shared.revokePasskey(credentialId: passkey.credentialId)
                    await load()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await APIClient.shared.fetchAccountExportData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("feeder-export-\(account?.username ?? "account").json")
            try data.write(to: url, options: .atomic)
            exportFileURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        do {
            try await APIClient.shared.deleteAccount(confirmUsername: deleteConfirmText)
            await auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
            deleteConfirmText = ""
        }
    }
}
