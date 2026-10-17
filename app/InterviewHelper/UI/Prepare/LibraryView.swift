import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var vm = LibraryViewModel()
    @State private var importing = false
    @State private var importMessage: String?
    @State private var pendingURL: URL?
    @State private var showAIConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search", text: $vm.searchText)
                    .accessibilityIdentifier("searchField")
                    .textFieldStyle(.roundedBorder)
                    .padding([.horizontal, .top])
                HStack {
                    Menu {
                        Button("All") { vm.topicFilter = "All" }
                        ForEach(vm.topics(context: context), id: \.name) { topic in
                            Button(topic.name) { vm.topicFilter = topic.name }
                        }
                    } label: {
                        Text(vm.topicFilter).lineLimit(1)
                    }
                    Spacer()
                    Toggle("Needs review", isOn: $vm.showNeedsReviewOnly)
                        .toggleStyle(.switch)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                if vm.entries(context: context).isEmpty {
                    Spacer()
                    Text("No questions yet. Import a .md file to get started.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else {
                    entryList
                }
            }
            .navigationTitle("Library")
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import") { importing = true }
                        .accessibilityIdentifier("importButton")
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if url.pathExtension.lowercased() != "md" {
                        importMessage = "Please choose a .md file."
                        return
                    }
                    handlePicked(url: url)
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
            .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if $0 == false { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .confirmationDialog("Unknown format", isPresented: $showAIConfirm, titleVisibility: .visible) {
                Button("Parse with AI") {
                    if let url = pendingURL {
                        Task { @MainActor in
                            importMessage = await vm.importMarkdown(url: url, context: context, llm: settings.makeLLM())
                        }
                    }
                    pendingURL = nil
                }
                Button("Import without AI") {
                    if let url = pendingURL {
                        Task { @MainActor in
                            importMessage = await vm.importMarkdown(url: url, context: context, llm: nil)
                        }
                    }
                    pendingURL = nil
                }
                Button("Cancel", role: .cancel) { pendingURL = nil }
            } message: {
                Text("This file does not look like a known format. Parse it with AI?")
            }
        }
    }

    private var entryList: some View {
        let results = vm.entries(context: context)
        return List {
            ForEach(results, id: \.persistentModelID) { entry in
                NavigationLink {
                    QADetailView(entry: entry)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.question).lineLimit(2)
                            if let name = entry.topic?.name {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if entry.hasAnswer == false {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .accessibilityIdentifier("qaRow")
            }
            .onDelete { offsets in
                let current = vm.entries(context: context)
                for i in offsets where current.indices.contains(i) {
                    vm.deleteEntry(current[i], context: context)
                }
            }
        }
        .accessibilityIdentifier("libraryList")
        .listStyle(.plain)
    }

    private func handlePicked(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importMessage = "Could not read file."
            return
        }
        let parsed = MarkdownImporter().parse(markdown: text, sourceFile: url.lastPathComponent)
        if parsed.isUnknownFormat, settings.makeLLM() != nil {
            pendingURL = url
            showAIConfirm = true
        } else {
            Task { @MainActor in
                importMessage = await vm.importMarkdown(url: url, context: context, llm: settings.makeLLM())
            }
        }
    }
}
