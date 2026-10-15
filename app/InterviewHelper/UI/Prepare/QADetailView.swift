import SwiftData
import SwiftUI

struct QADetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    let entry: QAEntry
    @State private var vm = LibraryViewModel()
    @State private var busy = false
    @State private var safariURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if entry.needsReview {
                    Text("Needs review")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                Text(entry.question)
                    .font(.title3.bold())
                if let name = entry.topic?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if entry.isAIGenerated {
                    Text("AI-generated • verify")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                if entry.isFollowUp {
                    Text("Follow-up question")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if entry.hasAnswer == false || entry.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Answer missing").foregroundStyle(.secondary)
                    Button(busy ? "Working…" : "Generate with AI") {
                        Task { @MainActor in
                            busy = true
                            await vm.generateAnswer(entry, llm: settings.makeLLM(), context: context, registry: makeRegistry())
                            busy = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || settings.makeLLM() == nil)
                } else {
                    AnswerMarkdown(text: entry.answer)
                }
                if entry.citations.isEmpty == false {
                    Text("Sources").font(.headline)
                    ForEach(entry.citations, id: \.self) { citation in
                        Button(citation.title) { safariURL = citation.url }
                            .font(.subheadline)
                    }
                }
                if entry.sourceFiles.isEmpty == false {
                    Text("Imported from").font(.headline)
                    ForEach(entry.sourceFiles, id: \.self) { file in
                        Text(file).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(busy ? "Working…" : "Clean with AI") {
                    Task { @MainActor in
                        busy = true
                        await vm.cleanEntry(entry, llm: settings.makeLLM(), context: context)
                        busy = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(busy || settings.makeLLM() == nil)
            }
            .padding()
        }
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if $0 == false { safariURL = nil } })) {
            if let url = safariURL {
                SafariView(url: url)
            }
        }
    }

    private func makeRegistry() -> SourceRegistry {
        SourceRegistry(seed: SourceRegistry.loadSeed(bundle: .main), customHosts: settings.customSourceHosts)
    }
}

private struct AnswerMarkdown: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}
