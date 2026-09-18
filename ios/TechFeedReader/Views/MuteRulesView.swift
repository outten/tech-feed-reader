import SwiftUI

struct MuteRulesView: View {
    @State private var rules: [MuteRule] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddRule = false
    @State private var newKind = "keyword"
    @State private var newValue = ""

    private let kinds = ["keyword", "author", "feed"]

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(rules) { rule in
                HStack {
                    Text(rule.kind.capitalized).font(.caption).foregroundStyle(.secondary)
                    Text(rule.value)
                }
            }
            .onDelete(perform: removeRules)
        }
        .navigationTitle("Mute Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddRule = true } label: { Image(systemName: "plus") }
            }
        }
        .overlay {
            if isLoading && rules.isEmpty { ProgressView() }
            if !isLoading && rules.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Mute Rules", systemImage: "speaker.slash")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingAddRule) {
            NavigationStack {
                Form {
                    Picker("Kind", selection: $newKind) {
                        ForEach(kinds, id: \.self) { Text($0.capitalized) }
                    }
                    TextField("Value", text: $newValue)
                        .textInputAutocapitalization(.never)
                }
                .navigationTitle("Add Mute Rule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddRule = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { Task { await addRule() } }
                            .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rules = try await APIClient.shared.fetchMuteRules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addRule() async {
        let value = newValue.trimmingCharacters(in: .whitespaces)
        do {
            try await APIClient.shared.addMuteRule(kind: newKind, value: value)
            showingAddRule = false
            newValue = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRules(at offsets: IndexSet) {
        let toRemove = offsets.map { rules[$0] }
        rules.remove(atOffsets: offsets)
        Task {
            for rule in toRemove {
                try? await APIClient.shared.removeMuteRule(kind: rule.kind, value: rule.value)
            }
        }
    }
}
