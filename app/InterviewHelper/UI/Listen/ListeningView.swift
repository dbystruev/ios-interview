import SwiftData
import SwiftUI

/// Glanceable Listen screen: a large running line of what is being said,
/// with relevant answers stacked below. Tab labels disappear while talking
/// so the full screen belongs to the answer. The Stop button appears only
/// after 2s of silence and vanishes the moment talk resumes.
struct ListeningView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: ListeningViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isListening || !vm.feed.isEmpty || !vm.runningTranscript.isEmpty {
                        listeningContent(vm: vm)
                    } else {
                        startView(vm: vm)
                    }
                } else {
                    ProgressView("Preparing…")
                }
            }
            .toolbar(tabBarVisibility, for: .tabBar)
            .task {
                if viewModel == nil {
                    let vm = ListeningViewModel(context: context, settings: settings)
                    vm.refreshIndex(context: context)
                    viewModel = vm
                    // Device-diagnostics hook: launch with --auto-listen to start
                    // the microphone without tapping (used for on-device log runs).
                    if CommandLine.arguments.contains("--auto-listen") {
                        vm.toggle()
                    }
                }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK") { viewModel?.errorMessage = nil }
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
        }
    }

    private var tabBarVisibility: Visibility {
        guard let vm = viewModel else { return .visible }
        return (vm.isListening && !vm.showStop) ? .hidden : .visible
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.errorMessage != nil },
            set: { if $0 == false { viewModel?.errorMessage = nil } }
        )
    }

    private func startView(vm: ListeningViewModel) -> some View {
        VStack {
            Spacer()
            Button("Start") { vm.toggle() }
                .accessibilityIdentifier("listenToggle")
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .font(.largeTitle)
            Spacer()
        }
        .padding()
    }

    private func listeningContent(vm: ListeningViewModel) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                // Top line: running transcript of what is being said.
                Text(vm.runningTranscript.isEmpty ? "Listening…" : vm.runningTranscript)
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                if vm.showStop {
                    Button("Stop") { vm.toggle() }
                        .accessibilityIdentifier("stopButton")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                }

                // Relevant answers below.
                if vm.feed.isEmpty && vm.aiAnswer == nil {
                    Text("No relevant answers yet.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.feed) { item in
                            answerRow(item: item)
                                .padding(.horizontal)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .onChange(of: vm.feed) {
                if let last = vm.feed.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func answerRow(item: ListeningViewModel.FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((try? AttributedString(markdown: item.text)) ?? AttributedString(item.text))
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isAI {
                HStack {
                    Text("AI-generated · verify")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        Task { @MainActor in
                            await viewModel?.saveAIAnswer(topic: "General")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
