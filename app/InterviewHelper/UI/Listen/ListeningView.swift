import SwiftData
import SwiftUI

struct ListeningView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: ListeningViewModel?
    @State private var typedText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    listeningContent(vm: vm)
                } else {
                    ProgressView("Preparing…")
                }
            }
            .navigationTitle("Listen")
        }
        .task {
            if viewModel == nil {
                let vm = ListeningViewModel(context: context, settings: settings)
                vm.refreshIndex(context: context)
                viewModel = vm
            }
        }
    }

    private func listeningContent(vm: ListeningViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(vm.isListening ? "Listening" : "Paused")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("listenStatus")
                    Spacer()
                    Button(vm.isListening ? "Stop" : "Start") { vm.toggle() }
                        .accessibilityIdentifier("listenToggle")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                DisclosureGroup("Transcript") {
                    Text(vm.transcriptPreview.isEmpty ? "No transcript yet." : vm.transcriptPreview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Matches").font(.headline)
                    if vm.cards.isEmpty {
                        Text("No matches yet. Speak or type a question below.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(vm.cards.indices, id: \.self) { i in
                                QACardView(scored: vm.cards[i])
                            }
                        }
                        .accessibilityIdentifier("cardsList")
                    }
                }
                if let answer = vm.aiAnswer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI-generated • verify")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(answer.text)
                        Button("Save to Library") {
                            Task { @MainActor in
                                await vm.saveAIAnswer(topic: "General")
                            }
                        }
                        .accessibilityIdentifier("saveAIButton")
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else if vm.aiBusy {
                    ProgressView("Thinking…")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type transcript (testing)").font(.headline)
                    TextField("Type what was said…", text: $typedText)
                        .accessibilityIdentifier("typedTranscript")
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Button("Match") { vm.injectTestTranscript(typedText) }
                        .accessibilityIdentifier("matchButton")
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .alert("Error", isPresented: errorBinding(vm: vm)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func errorBinding(vm: ListeningViewModel) -> Binding<Bool> {
        Binding(
            get: { vm.errorMessage != nil },
            set: { if $0 == false { vm.errorMessage = nil } }
        )
    }
}
