import CharlieLLM
import SwiftUI

/// "Subtitle Tutor" and "Model" sections of the Settings tab.
struct SubtitleAndModelSettings: View {
    var subtitleTutor: SubtitleTutorController
    @Bindable var llm: LLMSettingsStore
    @State private var apiKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Subtitle Tutor")
            row("Explain Subtitles", "captions.bubble") {
                Toggle("", isOn: Binding(get: { subtitleTutor.isRunning }, set: { $0 ? subtitleTutor.start() : subtitleTutor.stop() }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            divider
            row("Subtitle Region", "rectangle.dashed") {
                Button(subtitleTutor.region == nil ? "Select…" : "Reselect…") { subtitleTutor.pickRegion() }
                    .controlSize(.small)
            }
            divider
            row("Panel Position", "arrow.up.and.down.and.arrow.left.and.right") {
                Button("Back Above Subtitle") { subtitleTutor.resetPanel() }.controlSize(.small)
            }
            divider
            row("Cache", "archivebox") {
                Text("\(subtitleTutor.cacheCount) lines").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Clear") { subtitleTutor.clearCache() }.controlSize(.small)
            }
            footer(subtitleTutor.lastError.map { "⚠️ \($0)" }
                   ?? subtitleTutor.lastLatencyMs.map { "Last subtitle → first character: \($0) ms" }
                   ?? "Drag the panel to move it, drag an edge to resize. Seeking back shows cached explanations instantly.")
            Divider().padding(.horizontal, 12).padding(.bottom, 4)

            header("Model")
            row("Preset", "sparkles") {
                Picker("", selection: Binding(
                    get: { llm.matchingPresetId ?? "custom" },
                    set: { id in if let p = llm.presets.first(where: { $0.id == id }) { llm.apply(p); apiKeyDraft = llm.apiKey } }
                )) {
                    ForEach(llm.presets) { p in Text(p.note.isEmpty ? p.label : "\(p.label) · \(p.note)").tag(p.id) }
                    if llm.matchingPresetId == nil { Text("Custom").tag("custom") }
                }
                .pickerStyle(.menu).controlSize(.small).frame(maxWidth: 190)
            }
            divider
            row("Provider", "server.rack") {
                Picker("", selection: $llm.config.kind) {
                    Text("AWS Bedrock").tag(LLMProviderKind.bedrock)
                    Text("Anthropic API").tag(LLMProviderKind.anthropic)
                    Text("OpenAI-compatible").tag(LLMProviderKind.openAICompatible)
                }
                .pickerStyle(.menu).controlSize(.small).frame(maxWidth: 190)
            }
            divider
            field("Model", "cpu", text: $llm.config.model, placeholder: "model id")
            if llm.config.kind == .bedrock {
                divider
                field("AWS Profile", "person.badge.key", text: $llm.config.awsProfile, placeholder: "claude-code")
                divider
                field("AWS Region", "globe.asia.australia", text: $llm.config.awsRegion, placeholder: "us-west-2")
            } else {
                divider
                field("Base URL", "link", text: $llm.config.baseURL,
                      placeholder: llm.config.kind == .anthropic ? "https://api.anthropic.com" : "https://…/v1")
                divider
                row("API Key", "key") {
                    SecureField("stored in Keychain", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder).controlSize(.small).frame(maxWidth: 190)
                        .onSubmit { llm.apiKey = apiKeyDraft }
                        .onChange(of: apiKeyDraft) { _, v in llm.apiKey = v }
                }
            }
            divider
            row("Latency Test", "stopwatch") {
                Button(llm.isBenchmarking ? "Testing…" : "Test") { llm.runBenchmark() }
                    .controlSize(.small).disabled(llm.isBenchmarking)
            }
            footer(llm.benchmark ?? "Changes apply the next time Subtitle Tutor starts.")
            Divider().padding(.horizontal, 12).padding(.bottom, 4)
        }
        .onAppear { apiKeyDraft = llm.apiKey }
        .onChange(of: llm.config.kind) { _, _ in apiKeyDraft = llm.apiKey }
    }

    private var divider: some View { Divider().padding(.horizontal, 12) }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func row<Trailing: View>(_ title: String, _ icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 12))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func field(_ title: String, _ icon: String, text: Binding<String>, placeholder: String) -> some View {
        row(title, icon) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder).controlSize(.small).frame(maxWidth: 190)
        }
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
