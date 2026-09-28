import Foundation

// An MV3 Chrome extension as a folder of files, as the AI Extension Studio
// writes and validates it. WebKit loads it through Extensions.installFolder.

struct ExtensionPackage: Equatable {
    /// Short folder name under AIExtensions/.
    var slug: String
    /// path → file contents (UTF-8 text). Must include manifest.json.
    var files: [String: String]

    var manifestJSON: String? { files["manifest.json"] }

    /// Host / match patterns implied by the manifest, for the permission dialog.
    var hostHints: [String] {
        guard let data = manifestJSON?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var hosts: [String] = []
        if let perms = root["host_permissions"] as? [String] { hosts.append(contentsOf: perms) }
        if let scripts = root["content_scripts"] as? [[String: Any]] {
            for script in scripts {
                if let matches = script["matches"] as? [String] { hosts.append(contentsOf: matches) }
            }
        }
        return Array(Set(hosts)).sorted()
    }

    var asksBroadHosts: Bool {
        hostHints.contains { hint in
            let h = hint.lowercased()
            return h == "<all_urls>" || h.contains("*://*/*") || h == "*://*/*"
        }
    }
}

enum ExtensionPackageError: LocalizedError, Equatable {
    case empty
    case noManifest
    case badJSON(String)
    case notMV3
    case noContentScripts
    case badPath(String)
    case emptyFile(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "The model returned no files."
        case .noManifest: return "There's no manifest.json."
        case .badJSON(let why): return "manifest.json isn't valid JSON (\(why))."
        case .notMV3: return "Only Manifest V3 extensions are supported."
        case .noContentScripts: return "Add at least one content_scripts entry so the page can be changed."
        case .badPath(let path): return "Refuse path “\(path)”."
        case .emptyFile(let path): return "“\(path)” is empty."
        }
    }
}

enum ExtensionPackageGate {
    /// Paths must stay inside the package folder: no `..`, no absolute paths.
    static func safePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("\0") else { return false }
        let parts = trimmed.split(separator: "/")
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9._\-/]+$"#, options: .regularExpression) != nil
    }

    static func validate(_ package: ExtensionPackage) -> Result<ExtensionPackage, ExtensionPackageError> {
        guard !package.files.isEmpty else { return .failure(.empty) }
        for (path, body) in package.files {
            guard safePath(path) else { return .failure(.badPath(path)) }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptyFile(path))
            }
        }
        guard let raw = package.manifestJSON else { return .failure(.noManifest) }
        guard let data = raw.data(using: .utf8) else { return .failure(.badJSON("encoding")) }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.badJSON("not an object"))
            }
            root = object
        } catch {
            return .failure(.badJSON(error.localizedDescription))
        }
        let version = root["manifest_version"] as? Int
            ?? (root["manifest_version"] as? NSNumber)?.intValue
        guard version == 3 else { return .failure(.notMV3) }
        let scripts = root["content_scripts"] as? [[String: Any]] ?? []
        guard !scripts.isEmpty else { return .failure(.noContentScripts) }
        var cleaned = package
        cleaned.slug = slugify(package.slug.isEmpty
            ? (root["name"] as? String) ?? "ai-extension"
            : package.slug)
        return .success(cleaned)
    }

    static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        var slug = String(mapped)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "ai-extension" }
        return String(slug.prefix(40))
    }

    /// Prefer matches narrowed to the page the user is on.
    static func originMatch(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return "\(scheme)://\(host)/*"
    }
}
