import SafariServices
import SwiftUI

struct QACardView: View {
    let scored: ScoredEntry
    var citations: [SourceCitation] = []
    var isAIGenerated: Bool = false
    var explicitHasAnswer: Bool?
    var onGenerate: (() -> Void)?

    @State private var safariURL: URL?

    private var answerText: String { scored.entry.answer }

    private var isMissing: Bool {
        if let explicit = explicitHasAnswer { return explicit == false }
        return answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(scored.entry.topicName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.2), in: Capsule())
                Spacer()
                if scored.score > 0 {
                    Text("\(Int((scored.score * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(scored.entry.question)
                .font(.headline)
                .accessibilityIdentifier("card-\(scored.entry.id)")
            if isAIGenerated {
                Text("AI-generated • verify")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            if isMissing {
                Text("Answer missing").foregroundStyle(.secondary)
                if onGenerate != nil {
                    Button("Generate") { onGenerate?() }
                        .buttonStyle(.bordered)
                }
            } else {
                DisclosureGroup("Show answer") {
                    answerMarkdown(answerText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if citations.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(citations, id: \.self) { citation in
                            Button(citation.title) { safariURL = citation.url }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1))
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if $0 == false { safariURL = nil } })) {
            if let url = safariURL {
                SafariView(url: url)
            }
        }
    }

    private func answerMarkdown(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
