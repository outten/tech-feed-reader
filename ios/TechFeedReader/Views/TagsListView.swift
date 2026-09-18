import SwiftUI

struct TagsListView: View {
    @State private var tags: [Tag] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var showingAddTag = false
    @State private var newName = ""
    @State private var newValue = ""
    @State private var newMatchKind = "keyword"
    private let matchKinds = ["keyword", "regex", "feed_id"]

    var body: some View {
        List {
            ForEach(tags) { tag in
                NavigationLink(tag.name, value: tag)
            }
            .onDelete(perform: removeTags)
        }
        .navigationTitle("Tags")
        .navigationDestination(for: Tag.self) { tag in
            ArticlesListView(title: tag.name, emptyTitle: "No Articles For This Tag") {
                try await APIClient.shared.fetchArticles(tagId: tag.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddTag = true } label: { Image(systemName: "plus") }
            }
        }
        .overlay {
            if isLoading && tags.isEmpty { ProgressView() }
            if !isLoading && tags.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Tags Yet", systemImage: "tag")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Tags", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingAddTag) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    Picker("Match Kind", selection: $newMatchKind) {
                        ForEach(matchKinds, id: \.self) { Text($0.capitalized) }
                    }
                    TextField(matchValuePlaceholder, text: $newValue)
                        .textInputAutocapitalization(.never)
                }
                .navigationTitle("Add Tag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { resetForm() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { Task { await addTag() } }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var matchValuePlaceholder: String {
        switch newMatchKind {
        case "regex": return "Regular expression"
        case "feed_id": return "Feed ID"
        default: return "Keyword"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tags = try await APIClient.shared.fetchTags()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addTag() async {
        do {
            let tag = try await APIClient.shared.createTag(
                name: newName.trimmingCharacters(in: .whitespaces),
                matchKind: newMatchKind,
                matchValue: newValue.trimmingCharacters(in: .whitespaces)
            )
            tags.append(tag)
            resetForm()
        } catch {
            errorMessage = error.localizedDescription
            resetForm()
        }
    }

    private func resetForm() {
        showingAddTag = false
        newName = ""
        newValue = ""
        newMatchKind = "keyword"
    }

    private func removeTags(at offsets: IndexSet) {
        let toRemove = offsets.map { tags[$0] }
        tags.remove(atOffsets: offsets)
        Task {
            for tag in toRemove {
                try? await APIClient.shared.deleteTag(id: tag.id)
            }
        }
    }
}
