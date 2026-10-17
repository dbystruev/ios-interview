import SwiftData
import SwiftUI

/// Glanceable Listen screen: a large single scrolling line of what is being
/// said, with relevant answers stacked below. Tab labels disappear while
/// talking so the full screen belongs to the answer. The Stop button appears
/// only after 2s of silence and vanishes the moment talk resumes.
struct ListeningView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var viewModel: ListeningViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isListening || !vm.feed.isEmpty || !vm.currentUtterance.isEmpty || !vm.lastSaidPhrases.isEmpty {
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
                // Top line: single running line of what is being said right now,
                // scrolling left when it runs out of space.
                let displayText = vm.currentUtterance.isEmpty
                    ? (vm.lastSaidPhrases.isEmpty ? "Listening…" : vm.lastSaidPhrases)
                    : vm.currentUtterance
                MarqueeText(text: displayText, font: .largeTitle)
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
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss the keyboard when tapping anywhere outside an input field.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

/// A single-line text that scrolls left when it is wider than the available space.
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            // Measure the rendered text width.
            Text(text)
                .font(font)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { textWidth = geo.size.width }
                            .onChange(of: geo.size.width) { textWidth = geo.size.width }
                    }
                )

            GeometryReader { geo in
                let containerWidth = geo.size.width
                let overflow = textWidth > containerWidth

                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .offset(x: scrollOffset)
                    .animation(
                        overflow ? .linear(duration: Double(max(textWidth, containerWidth)) / 40.0)
                            .repeatForever(autoreverses: false)
                        : .none,
                        value: scrollOffset
                    )
                    .onAppear {
                        self.containerWidth = containerWidth
                        if overflow {
                            scrollOffset = -textWidth
                            scrollTask = Task {
                                // Restart the marquee loop when the text changes.
                                while !Task.isCancelled {
                                    try? await Task.sleep(for: .seconds(2))
                                    if Task.isCancelled { break }
                                    scrollOffset = containerWidth
                                    try? await Task.sleep(for: .seconds(Double(textWidth) / 40.0))
                                    scrollOffset = -textWidth
                                }
                            }
                        }
                    }
                    .onChange(of: text) {
                        scrollOffset = containerWidth
                    }
                    .onDisappear { scrollTask?.cancel() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
