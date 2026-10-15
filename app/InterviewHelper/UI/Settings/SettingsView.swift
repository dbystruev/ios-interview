import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var keyInput = ""
    @State private var keyStatus = ""
    @State private var models: [OpenRouterModel] = []
    @State private var modelsError: String?
    @State private var refreshingModels = false
    @State private var newHost = ""
    @State private var showClearConfirm = false
    @State private var notice = ""

    var body: some View {
        @Bindable var binds = settings
        NavigationStack {
            Form {
                Section("LLM provider") {
                    Picker("Provider", selection: $binds.providerID) {
                        Text("On-device").tag(AppSettings.providerOnDevice)
                        Text("OpenRouter").tag(AppSettings.providerOpenRouter)
                    }
                    .pickerStyle(.segmented)
                }
                Section("OpenRouter") {
                    SecureField("API key", text: $keyInput)
                        .accessibilityIdentifier("orKeyField")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("Save key") { saveKey() }
                            .accessibilityIdentifier("orKeySave")
                        Button("Delete key", role: .destructive) { deleteKey() }
                    }
                    if keyStatus.isEmpty == false {
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Model", text: $binds.openRouterModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if models.isEmpty == false {
                        Picker("Free models", selection: $binds.openRouterModel) {
                            ForEach(models, id: \.id) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                    Button(refreshingModels ? "Loading…" : "Refresh free models") { refreshModels() }
                        .accessibilityIdentifier("modelRefresh")
                        .disabled(refreshingModels)
                    if let err = modelsError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Matching") {
                    HStack {
                        Text("Threshold")
                        Slider(value: $binds.matchThreshold, in: 0.0...1.0, step: 0.05)
                        Text(String(format: "%.2f", binds.matchThreshold))
                            .font(.caption)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Stepper("Window: \(Int(binds.windowSeconds))s", value: $binds.windowSeconds, in: 15.0...120.0, step: 5.0)
                    Toggle("AI fallback", isOn: $binds.aiFallbackEnabled)
                }
                sourcesSection
                Section("Data") {
                    Button("Clear AI answers", role: .destructive) { showClearConfirm = true }
                    if notice.isEmpty == false {
                        Text(notice).font(.caption)
                    }
                }
                Section("Privacy") {
                    Text("Transcription stays on-device. Remote LLM is off unless you choose OpenRouter and enable AI features. Use Listening Mode for practice with consent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadKey() }
            .confirmationDialog("Clear AI answers?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) { clearAI() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var sourcesSection: some View {
        Section("Sources") {
            let seed = SourceRegistry.loadSeed(bundle: .main)
            ForEach(seed, id: \.id) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.subheadline)
                    Text("\(source.baseURL)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.customSourceHosts.isEmpty == false {
                ForEach(settings.customSourceHosts, id: \.self) { host in
                    HStack {
                        Text(host).font(.subheadline)
                        Spacer()
                        Button("Delete") {
                            settings.customSourceHosts.removeAll(where: { $0 == host })
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            HStack {
                TextField("Add host (example.com)", text: $newHost)
                    .accessibilityIdentifier("customHostField")
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Add") { addHost() }
            }
        }
    }

    private func loadKey() {
        keyInput = KeychainStore.load(service: AppSettings.keychainService, account: AppSettings.keychainAccount) ?? ""
        keyStatus = keyInput.isEmpty ? "No key stored." : "Key stored."
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keyStatus = "Key is empty."
            return
        }
        do {
            try KeychainStore.save(trimmed, service: AppSettings.keychainService, account: AppSettings.keychainAccount)
            keyStatus = "Key saved."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try KeychainStore.delete(service: AppSettings.keychainService, account: AppSettings.keychainAccount)
            keyInput = ""
            keyStatus = "Key deleted."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func refreshModels() {
        let stored = KeychainStore.load(service: AppSettings.keychainService, account: AppSettings.keychainAccount) ?? ""
        let raw = stored.isEmpty ? keyInput : stored
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            modelsError = "Save an API key first."
            return
        }
        refreshingModels = true
        modelsError = nil
        Task { @MainActor in
            defer { refreshingModels = false }
            do {
                let provider = OpenRouterProvider(apiKey: trimmed, model: settings.openRouterModel)
                let fetched = try await provider.fetchFreeModels()
                models = fetched
                if fetched.isEmpty { modelsError = "No free models found." }
            } catch {
                modelsError = error.localizedDescription
            }
        }
    }

    private func addHost() {
        let host = newHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.isEmpty { return }
        if settings.customSourceHosts.contains(host) == false {
            settings.customSourceHosts.append(host)
        }
        newHost = ""
    }

    private func clearAI() {
        let vm = LibraryViewModel()
        let count = vm.clearAIGenerated(context: context)
        notice = "Cleared \(count) AI answers."
    }
}
