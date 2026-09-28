import Foundation
import WebKit

// Writes an AI-made MV3 folder under Application Support, then installs or
// reloads it through the existing WKWebExtension host (Extensions.swift).

@MainActor
enum ExtensionDeployer {
    private static var mapURL: URL { Store.aiExtensions.appendingPathComponent("map.json") }

    /// slug → installed extension id (local-…).
    private static func loadMap() -> [String: String] {
        guard let data = try? Data(contentsOf: mapURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return object
    }

    private static func saveMap(_ map: [String: String]) {
        try? FileManager.default.createDirectory(at: Store.aiExtensions, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: mapURL, options: .atomic)
    }

    static func folder(for slug: String) -> URL {
        Store.aiExtensions.appendingPathComponent(slug, isDirectory: true)
    }

    static func extensionID(for slug: String) -> String? {
        loadMap()[slug]
    }

    static func forget(slug: String) {
        var map = loadMap()
        map.removeValue(forKey: slug)
        saveMap(map)
    }

    static func forget(extensionID: String) {
        var map = loadMap()
        let keys = map.filter { $0.value == extensionID }.map(\.key)
        guard !keys.isEmpty else { return }
        for key in keys { map.removeValue(forKey: key) }
        saveMap(map)
    }

    /// Write files to disk. Replaces the previous package for this slug.
    static func write(_ package: ExtensionPackage) throws -> URL {
        let root = folder(for: package.slug)
        let files = FileManager.default
        if files.fileExists(atPath: root.path) {
            try files.removeItem(at: root)
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, body) in package.files {
            let url = root.appendingPathComponent(path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = body.data(using: .utf8) else { continue }
            try data.write(to: url, options: .atomic)
        }
        return root
    }

    enum Outcome: Equatable {
        case installed(id: String)
        case reloaded(id: String)
        case cancelled
        case unavailable
        case failed(String)
    }

    /// Install for the first time, or reload when this slug already maps to an id.
    static func deploy(_ package: ExtensionPackage, confirm: Bool = true) async -> Outcome {
        guard #available(macOS 15.4, *) else { return .unavailable }
        let root: URL
        do {
            root = try write(package)
        } catch {
            return .failed(error.localizedDescription)
        }

        let map = loadMap()
        if let id = map[package.slug], Extensions.shared.installed.contains(where: { $0.id == id }) {
            // Keep source pointed at our AI folder so reload copies from here.
            if let index = Extensions.shared.installed.firstIndex(where: { $0.id == id }) {
                var item = Extensions.shared.installed[index]
                if item.source != root.path {
                    item.source = root.path
                    Extensions.shared.replaceInstalled(item)
                }
            }
            Extensions.shared.reload(id)
            return .reloaded(id: id)
        }

        let id = await Extensions.shared.installFolderAwaiting(at: root, confirm: confirm)
        guard let id else { return .cancelled }
        var next = loadMap()
        next[package.slug] = id
        saveMap(next)
        return .installed(id: id)
    }

    static func uninstall(slug: String) {
        guard #available(macOS 15.4, *) else { return }
        if let id = loadMap()[slug] {
            Extensions.shared.remove(id)
        }
        forget(slug: slug)
        try? FileManager.default.removeItem(at: folder(for: slug))
    }
}
