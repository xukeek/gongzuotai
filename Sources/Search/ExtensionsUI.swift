import SwiftUI
import WebKit

/// Settings › Extensions: what is installed, and the two ways in — a Chrome
/// Web Store link, or a folder.
struct ExtensionsPage: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *) {
            Installer(browser: browser, extensions: .shared)
        } else {
            Card {
                Line(L("settings.extensions.unsupported.title"), L("settings.extensions.unsupported.detail")) { EmptyView() }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Installer: View {
        @ObservedObject var browser: Browser
        @ObservedObject var extensions: Extensions
        @State private var link = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L("settings.extensions.addFromStore"))
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Pill(L("settings.extensions.openStore")) {
                                browser.tuning = false
                                browser.open(Browser.webStore, foreground: true)
                            }
                        }
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                if link.isEmpty {
                                    Text(L("settings.extensions.chromeStore.detail"))
                                        .foregroundStyle(Palette.muted.opacity(0.8))
                                }
                                TextField("", text: $link)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Palette.ink)
                                    .onSubmit(add)
                            }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            if extensions.busy != nil {
                                Ring(size: 12)
                            } else {
                                Pill(L("settings.general.add"), filled: true, action: add)
                                    .disabled(Crx.id(in: link) == nil)
                            }
                        }
                        Text(L("settings.extensions.chromeStore.footer"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }

                Card {
                    Line(L("settings.extensions.bringOver.title"), L("settings.extensions.bringOver.detail")) {
                        Pill(L("settings.extensions.bringOver.pill")) {
                            browser.tuning = false
                            browser.bringingExtensions = true
                            browser.bringingIn = ""
                        }
                    }
                }

                Card {
                    Line(L("settings.extensions.allowPrivate"), L("settings.extensions.allowPrivate.detail")) {
                        Switch(on: Binding(
                            get: { browser.prefs.extensionsInPrivate },
                            set: { browser.prefs.extensionsInPrivate = $0 }
                        ))
                    }
                }

                if extensions.installed.isEmpty {
                    Card { Nothing(L("settings.extensions.none")) }
                } else {
                    Card {
                        ForEach(Array(extensions.installed.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Rule() }
                            Row(item: item, extensions: extensions)
                        }
                    }
                }

                Recorders()

                Card {
                    Line(L("settings.extensions.fromFolder.title"), L("settings.extensions.fromFolder.detailLong")) {
                        Pill(L("settings.extensions.choose")) { extensions.installFolder() }
                    }
                }
            }
        }

        private func add() {
            guard Crx.id(in: link) != nil else { return }
            extensions.install(from: link)
            link = ""
        }
    }

    /// The extensions you let record your screen, each one to take back.
    @available(macOS 15.4, *)
    private struct Recorders: View {
        @ObservedObject private var capture = ExtensionCapture.shared

        var body: some View {
            let ids = ExtensionCapture.allowedIDs
            if !ids.isEmpty {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                            if index > 0 { Rule() }
                            Line(Browser.extensionName(id), L("settings.extensions.capture.detail")) {
                                Pill(L("settings.extensions.remove")) { ExtensionCapture.forget(id) }
                            }
                        }
                    }
                }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Row: View {
        let item: Installed
        @ObservedObject var extensions: Extensions
        @State private var hovering = false

        var body: some View {
            let context = extensions.contexts[item.id]
            HStack(spacing: 12) {
                Group {
                    if let icon = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(detail(context))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .help(item.source ?? "")
                }
                Spacer(minLength: 8)
                if hovering {
                    Quick(item.pinned == true ? L("settings.extensions.unpin") : L("settings.extensions.pin")) {
                        extensions.setPinned(item.id, !(item.pinned ?? false))
                    }
                    if context?.overrideNewTabPageURL != nil {
                        let on = Store.settings.object(forKey: "extensions.newtab.\(item.id)") as? Bool == true
                        Quick(on ? L("settings.extensions.stopNewTabs") : L("settings.extensions.showNewTabs")) {
                            Store.settings.set(!on, forKey: "extensions.newtab.\(item.id)")
                            extensions.objectWillChange.send()
                        }
                    }
                    if item.source != nil || !item.fromStore {
                        Quick(L("settings.extensions.reload")) { extensions.reload(item.id) }
                    }
                    if context?.optionsPageURL != nil {
                        Quick(L("settings.extensions.options")) { extensions.openOptions(item.id) }
                    }
                    Quick(L("settings.extensions.remove"), tint: .red.opacity(0.75)) { extensions.remove(item.id) }
                }
                Switch(on: Binding(get: { item.enabled }, set: { extensions.setEnabled(item.id, $0) }))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(hovering ? Palette.hover : .clear)
            .onHover { hovering = $0 }
        }

        /// Where it was loaded from, by the folder's name — the whole path
        /// is in the tooltip.
        private var folder: String {
            item.source.map { L("settings.extensions.fromNamedFolder", URL(fileURLWithPath: $0).lastPathComponent) }
                ?? L("settings.extensions.fromAFolder")
        }

        private func detail(_ context: WKWebExtensionContext?) -> String {
            var parts = [L("settings.extensions.version", item.version),
                         item.fromStore ? L("settings.extensions.chromeWebStore") : folder]
            if item.enabled, context == nil { parts.append(L("settings.extensions.couldntStart")) }
            if context?.overrideNewTabPageURL != nil, Store.settings.object(forKey: "extensions.newtab.\(item.id)") as? Bool == true {
                parts.append(L("settings.extensions.showsInNewTabs"))
            }
            if let errors = context?.errors, !errors.isEmpty {
                let n = Int64(errors.count)
                parts.append(n == 1 ? L("settings.extensions.warning", n) : L("settings.extensions.warnings", n))
            }
            return parts.joined(separator: " · ")
        }
    }
}

/// On an extension's page in the Chrome Web Store, the offer to add it —
/// where the store's own button only says "Switch to Chrome".
struct StoreOffer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *), let tab = browser.active {
            Watch(tab: tab, extensions: .shared)
        }
    }

    @available(macOS 15.4, *)
    private struct Watch: View {
        @ObservedObject var tab: Tab
        @ObservedObject var extensions: Extensions

        var body: some View {
            // Only where the page's own "Add to Search" isn't in place — a
            // store that has changed its markup still gets a way in.
            if let url = tab.address, let id = Crx.storeID(of: url),
               tab.storePlaced != id, !extensions.installed.contains(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Text(extensions.busy == id ? L("chrome.storeOffer.adding") : L("chrome.storeOffer.add"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink)
                    if extensions.busy == id {
                        Ring(size: 10)
                    } else {
                        Button(L("settings.general.add")) { extensions.install(from: id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.ground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Palette.ink, in: Capsule())
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 9)
                .background(Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    static func isStorePage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return false }
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com"
            || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }
}
