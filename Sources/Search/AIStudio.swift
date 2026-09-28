import SwiftUI
import Foundation

// AI Extension Studio: a right-hand column that asks a model for a Chrome MV3
// extension, shows the files, and installs or reloads them through WebKit.

@MainActor
final class AIStudio: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let prompt: String
        var answer = ""
        var package: ExtensionPackage?
        var error: String?
        var outcome: String?
        var done = false
    }

    static let width: CGFloat = 340

    @Published var draft = ""
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var busy = false
    @Published var previewPath: String?
    @Published private(set) var engineOK = true

    private var task: Task<Void, Never>?
    private weak var browser: Browser?

    init(browser: Browser) {
        self.browser = browser
        if #unavailable(macOS 15.4) {
            engineOK = false
        }
    }

    var pageURL: URL? { browser?.active?.pageAddress }
    var pageTitle: String { browser?.active?.title ?? "" }
    var originMatch: String? { ExtensionPackageGate.originMatch(for: pageURL) }

    func stop() {
        task?.cancel()
        task = nil
        busy = false
    }

    func submit() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy, let browser else { return }
        draft = ""

        guard engineOK else {
            turns.append(Turn(prompt: prompt, error: "Chrome extensions need macOS 15.4 or later.", done: true))
            return
        }
        guard browser.prefs.ai, let provider = browser.prefs.aiProvider else {
            browser.settingsPage = .ai
            browser.tuning = true
            browser.announce(browser.prefs.ai ? "Choose where the AI runs" : "Turn on AI in Settings › AI")
            return
        }
        let shy = browser.active.map { tab in
            tab.shy || tab.built.map { !$0.configuration.websiteDataStore.isPersistent } == true
        } ?? false
        if shy && !provider.isLocal {
            turns.append(Turn(prompt: prompt, error: "In a private tab, only an AI on this Mac.", done: true))
            return
        }
        if shy {
            turns.append(Turn(prompt: prompt, error: "AI-made extensions aren't installed from a private tab.", done: true))
            return
        }
        if provider == .thisMac, AIEngine.shared.state != .ready {
            browser.settingsPage = .ai
            browser.tuning = true
            browser.announce("The model isn't on this Mac yet")
            return
        }
        let model = browser.prefs.aiModel(for: provider)
        guard !model.isEmpty else {
            browser.settingsPage = .ai
            browser.tuning = true
            browser.announce("Choose a model for \(provider.name)")
            return
        }
        guard provider.isLocal || AIKeys.hint(for: provider) != nil else {
            browser.settingsPage = .ai
            browser.tuning = true
            browser.announce("No key for \(provider.name) yet")
            return
        }

        let turn = Turn(prompt: prompt)
        turns.append(turn)
        let index = turns.count - 1
        busy = true
        let pageURL = self.pageURL
        let pageTitle = self.pageTitle
        let match = originMatch
        let key = AIKeys.key(for: provider)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.busy = false
                self.task = nil
            }
            do {
                let raw = try await Self.generate(
                    provider: provider, model: model, key: key,
                    prompt: prompt, pageURL: pageURL, pageTitle: pageTitle, match: match
                ) { piece in
                    Task { @MainActor [weak self] in
                        guard let self, self.turns.indices.contains(index) else { return }
                        self.turns[index].answer += piece
                    }
                }
                guard !Task.isCancelled else { return }
                switch Self.parse(raw, fallbackMatch: match) {
                case .failure(let error):
                    self.turns[index].error = error.localizedDescription
                    self.turns[index].done = true
                case .success(let package):
                    self.turns[index].package = package
                    self.previewPath = package.files.keys.sorted().first
                    if package.asksBroadHosts {
                        self.turns[index].outcome = "Warning: this extension asks for every site. You'll confirm permissions on install."
                    }
                    let outcome = await ExtensionDeployer.deploy(package, confirm: true)
                    switch outcome {
                    case .installed(let id):
                        self.turns[index].outcome = "Installed (\(id)). Reload the page if the script doesn't run yet."
                        browser.announce("Extension installed")
                    case .reloaded(let id):
                        self.turns[index].outcome = "Reloaded (\(id)). Refresh the page to pick up changes."
                        browser.announce("Extension reloaded")
                    case .cancelled:
                        self.turns[index].outcome = "Install cancelled — permissions weren't accepted."
                    case .unavailable:
                        self.turns[index].error = "Chrome extensions need macOS 15.4 or later."
                    case .failed(let why):
                        self.turns[index].error = why
                    }
                    self.turns[index].done = true
                }
            } catch is CancellationError {
                self.turns[index].error = "Stopped."
                self.turns[index].done = true
            } catch {
                self.turns[index].error = error.localizedDescription
                self.turns[index].done = true
            }
        }
    }

    func uninstallLatest() {
        guard let package = turns.reversed().compactMap(\.package).first else { return }
        ExtensionDeployer.uninstall(slug: package.slug)
        browser?.announce("Removed \(package.slug)")
        if let index = turns.lastIndex(where: { $0.package?.slug == package.slug }) {
            turns[index].outcome = "Uninstalled."
        }
    }

    // MARK: - model

    private static func generate(
        provider: AIProvider, model: String, key: String?,
        prompt: String, pageURL: URL?, pageTitle: String, match: String?,
        onPiece: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let system = """
        You write Chrome Manifest V3 extensions for a WebKit browser.
        Reply with ONLY a single JSON object (no markdown fences), shape:
        {"slug":"short-kebab-name","files":{"manifest.json":"...","content.js":"..."}}
        Rules:
        - manifest_version must be 3
        - Include content_scripts that run on the page; prefer match pattern \(match.map { "\"\($0)\"" } ?? "\"https://*/*\"") when possible — never use <all_urls> unless the user insists
        - Keep the extension small: content script (+ optional background service_worker). No remote code. No eval.
        - File contents are strings. Escape properly for JSON.
        - Do not wrap the JSON in prose.
        """
        let page = [
            pageURL.map { "URL: \($0.absoluteString)" },
            pageTitle.isEmpty ? nil : "Title: \(pageTitle)",
            match.map { "Preferred matches: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
        let user = page.isEmpty ? prompt : "Current page:\n\(page)\n\nRequest:\n\(prompt)"
        var collected = ""
        for try await piece in AIClient.shared.stream(provider, model: model, system: system,
                                                      messages: [AIMessage(role: .user, text: user)], key: key) {
            if Task.isCancelled { throw CancellationError() }
            collected += piece
            onPiece(piece)
        }
        return collected
    }

    private static func parse(_ raw: String, fallbackMatch: String?) -> Result<ExtensionPackage, ExtensionPackageError> {
        let jsonText = unwrapJSON(raw)
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesAny = root["files"] as? [String: Any]
        else {
            return .failure(.badJSON("expected {\"slug\",\"files\"}"))
        }
        var files: [String: String] = [:]
        for (path, value) in filesAny {
            if let text = value as? String {
                files[path] = text
            } else if let object = value as? [String: Any],
                      let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                      let text = String(data: pretty, encoding: .utf8) {
                files[path] = text
            }
        }
        // If the model put the manifest object at the top level under files as a dict already handled.
        if files["manifest.json"] == nil, let manifest = root["manifest"] as? [String: Any],
           let pretty = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            files["manifest.json"] = text
        }
        // Tighten matches when the model left them broad and we know the origin.
        if let match = fallbackMatch, let manifestText = files["manifest.json"],
           let mdata = manifestText.data(using: .utf8),
           var manifest = try? JSONSerialization.jsonObject(with: mdata) as? [String: Any] {
            if var scripts = manifest["content_scripts"] as? [[String: Any]] {
                for i in scripts.indices {
                    let matches = (scripts[i]["matches"] as? [String]) ?? []
                    let broad = matches.contains { $0 == "<all_urls>" || $0.contains("*://*/*") }
                    if matches.isEmpty || broad {
                        scripts[i]["matches"] = [match]
                    }
                }
                manifest["content_scripts"] = scripts
            }
            if let hosts = manifest["host_permissions"] as? [String],
               hosts.contains(where: { $0 == "<all_urls>" || $0.contains("*://*/*") }) {
                manifest["host_permissions"] = [match]
            }
            if let pretty = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                files["manifest.json"] = text
            }
        }
        let slug = (root["slug"] as? String) ?? "ai-extension"
        let package = ExtensionPackage(slug: slug, files: files)
        return ExtensionPackageGate.validate(package)
    }

    private static func unwrapJSON(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            if let end = text.range(of: "```", options: .backwards) {
                text = String(text[..<end.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") , start < end {
            return String(text[start...end])
        }
        return text
    }
}

// MARK: - browser

extension Browser {
    func toggleStudio() {
        withAnimation(Motion.glide) {
            if studioShowing {
                studioShowing = false
            } else {
                openStudio()
            }
        }
    }

    func openStudio() {
        if studio == nil { studio = AIStudio(browser: self) }
        studioShowing = true
    }

    func closeStudio() {
        studio?.stop()
        studioShowing = false
    }
}

// MARK: - sidebar UI

struct AIStudioSide: View {
    @ObservedObject var browser: Browser
    @ObservedObject var studio: AIStudio
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.hairline).frame(height: 1)
            context
            Rectangle().fill(Palette.hairline).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !studio.engineOK {
                        Text("Chrome extensions need macOS 15.4 or later on this Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                    }
                    ForEach(studio.turns) { turn in
                        turnBlock(turn)
                    }
                }
                .padding(.vertical, 12)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            composer
        }
        .frame(width: AIStudio.width)
        .frame(maxHeight: .infinity)
        .background(Palette.ground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.hairline).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Text("Extension Studio")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            if studio.turns.contains(where: { $0.package != nil }) {
                Door(icon: "trash", help: "Uninstall latest AI extension") {
                    studio.uninstallLatest()
                }
            }
            Door(icon: "xmark", help: "Close") { browser.closeStudio() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(studio.pageTitle.isEmpty ? "No page" : studio.pageTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(studio.pageURL?.absoluteString ?? "Open a web page, then describe an extension.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
            if let match = studio.originMatch {
                Text("matches → \(match)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func turnBlock(_ turn: AIStudio.Turn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.prompt)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.ink)
            if let package = turn.package {
                filesList(package)
            } else if !turn.answer.isEmpty, !turn.done {
                Text(turn.answer)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(8)
            }
            if let error = turn.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.unsafe)
            }
            if let outcome = turn.outcome {
                Text(outcome)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            if studio.busy, turn.id == studio.turns.last?.id, !turn.done {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
    }

    private func filesList(_ package: ExtensionPackage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.slug)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.ink)
            ForEach(package.files.keys.sorted(), id: \.self) { path in
                Button {
                    studio.previewPath = studio.previewPath == path ? nil : path
                } label: {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(studio.previewPath == path ? Palette.ink : Palette.muted)
                }
                .buttonStyle(.plain)
                if studio.previewPath == path, let body = package.files[path] {
                    Text(body)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.wash)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .lineLimit(24)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $studio.draft,
                      prompt: Text("Describe an extension…").foregroundStyle(Palette.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .focused($typing)
                .onSubmit { studio.submit() }
                .disabled(!studio.engineOK || studio.busy)
            Button(studio.busy ? "…" : "Make") { studio.submit() }
                .font(.system(size: 12, weight: .semibold))
                .disabled(!studio.engineOK || studio.busy
                          || studio.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { typing = true }
    }
}
