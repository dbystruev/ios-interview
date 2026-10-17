import SwiftData
import SwiftUI

/// Glanceable answer feed: large answers only, auto-scrolling as topics change.
/// The Stop button appears only after 2s of silence and hides on speech.
struct ListeningView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: ListeningViewModel?
    @State private var typedText = ""
    @State private var showTestInput = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isListening || !vm.feed.isEmpty {
                        answerFeed(vm: vm)
                    } else {
                        startView(vm: vm)
                    }
                } else {
                    ProgressView("Preparing…")
                }
            }
            .toolbar(tabBarVisibility, for: .tabBar)
        }
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.errorMessage != nil },
            set: { if $0 == false { viewModel?.errorMessage = nil } }
        )
    }

    private var tabBarVisibility: Visibility {
        guard let vm = viewModel else { return .visible }
        // Full screen for the answer while talking; tabs return with Stop.
        return (vm.isListening && !vm.showStop) ? .hidden : .visible
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
            testInput(vm: vm)
        }
        .padding()
    }

    private func answerFeed(vm: ListeningViewModel) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !vm.isListening {
                            Button("Start") { vm.toggle() }
                                .accessibilityIdentifier("listenToggle")
                                .buttonStyle(.bordered)
                        }
                        ForEach(vm.feed) { item in
                            feedRow(item: item, vm: vm)
                                .id(item.id)
                        }
                        testInput(vm: vm)
                    }
                    .padding()
                }
                .accessibilityIdentifier("cardsList")
                .onChange(of: vm.feed.count) {
                    if let last = vm.feed.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if vm.isListening, vm.showStop {
                    Button("Stop") { vm.toggle() }
                        .accessibilityIdentifier("stopButton")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.showStop)
        }
    }

    private func feedRow(item: ListeningViewModel.FeedItem, vm: ListeningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((try? AttributedString(markdown: item.text)) ?? AttributedString(item.text))
                .font(.largeTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isAI {
                HStack {
                    Text("AI-generated · verify")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        Task { @MainActor in
                            await vm.saveAIAnswer(topic: "General")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func testInput(vm: ListeningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Test input") { showTestInput.toggle() }
                .accessibilityIdentifier("testInputToggle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if showTestInput {
                TextField("Type what was said…", text: $typedText)
                    .accessibilityIdentifier("typedTranscript")
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Match") { vm.injectTestTranscript(typedText) }
                    .accessibilityIdentifier("matchButton")
                    .buttonStyle(.bordered)
            }
        }
    }
}
