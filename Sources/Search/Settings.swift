import SwiftUI

/// Everything there is to set. Pages down the left, one page at a time on
/// the right, each a short list of lines with a hairline between them —
/// nothing to scroll through, nothing to hunt for. The same white and
/// hairline as the rest of the app; the same pill for the page you are on
/// as for the tab you are on.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var shield = Shield.shared
    @State private var isDefault = Links.isDefault
    /// A site shortcut being written, kept out of Preferences until it's saved.
    @State private var draft: Keyword?
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "") ?? .general

    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, shortcuts, extensions, passwords, downloads, privacy, ai, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return L("settings.page.general")
            case .tabs: return L("settings.page.tabs")
            case .shortcuts: return L("settings.page.shortcuts")
            case .extensions: return L("settings.page.extensions")
            case .passwords: return L("settings.page.passwords")
            case .downloads: return L("settings.page.downloads")
            case .privacy: return L("settings.page.privacy")
            case .ai: return L("settings.page.ai")
            case .about: return L("settings.page.about")
            }
        }
        var icon: String {
            switch self {
            case .general: return "macwindow"
            case .tabs: return "rectangle.split.3x1"
            case .shortcuts: return "keyboard"
            case .extensions: return "puzzlepiece.extension"
            case .passwords: return "key"
            case .downloads: return "arrow.down.circle"
            case .privacy: return "hand.raised"
            case .ai: return "sparkles"
            case .about: return "info.circle"
            }
        }
    }

    private static let rail: CGFloat = 168
    private static let width: CGFloat = 660
    private static let height: CGFloat = 500

    private func sideEdge(_ position: SidebarPosition) -> String {
        position == .left ? L("settings.tabs.edge.left") : L("settings.tabs.edge.right")
    }

    var body: some View {
        HStack(spacing: 0) {
            pages
            Rectangle().fill(Palette.hairline).frame(width: 1)
            content
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
    }

    // MARK: - the rail

    private var pages: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("settings.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            ForEach(Page.allCases) { item in
                PageRow(page: item, on: page == item) { page = item }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SettingsPanel.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.wash.opacity(0.45), in: Rectangle())
    }

    private struct PageRow: View {
        let page: Page
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(page.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - the page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Door(icon: "xmark", help: L("settings.done")) { browser.tuning = false }
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: general
                    case .tabs:
                        tabs
                        if !prefs.sidebar { toolbar }
                    case .shortcuts: ShortcutsPage(browser: browser, store: .shared)
                    case .extensions: ExtensionsPage(browser: browser)
                    case .passwords: passwords
                    case .downloads: downloads
                    case .privacy: privacy
                    case .ai: AISettings(browser: browser, prefs: prefs)
                    case .about: about
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - general

    private var general: some View {
        Card {
            Line(
                L("settings.general.openLinks.title"),
                isDefault ? L("settings.general.openLinks.detailDefault") : L("settings.general.openLinks.detailOther")
            ) {
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                } else {
                    Pill(L("settings.general.makeDefault"), filled: true) {
                        Links.becomeDefault { worked in
                            isDefault = Links.isDefault
                            browser.announce(worked && isDefault ? L("announce.linksNowOpenHere") : L("announce.macosDidntChange"))
                        }
                    }
                }
            }
            Rule()
            // Coming from another browser, now or any time later: the same
            // sheet as File › Bring Things Over… and the Welcome's.
            Line(L("settings.general.bringThings.title"), L("settings.general.bringThings.detail")) {
                Pill(L("settings.general.bringThings.pill")) {
                    browser.tuning = false
                    browser.bringingIn = ""
                }
            }
            Rule()
            Line(L("settings.general.searchWith.title"), searchDetail) {
                Picker("", selection: $prefs.engine) {
                    ForEach(Engine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if prefs.engine == .custom {
                ZStack(alignment: .leading) {
                    if prefs.customEngine.isEmpty {
                        Text("https://example.com/search?q=%s")
                            .foregroundStyle(Palette.muted.opacity(0.8))
                    }
                    TextField("", text: $prefs.customEngine)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
            Rule()
            Line(L("settings.general.siteShortcuts.title"), keywordDetail) {
                if draft == nil {
                    Pill(L("settings.general.add")) { draft = Keyword() }
                } else {
                    HStack(spacing: 6) {
                        Pill(L("settings.general.cancel")) { draft = nil }
                        Pill(L("settings.general.save"), filled: true) { saveDraft() }
                            .disabled(draftProblem != nil)
                            .opacity(draftProblem == nil ? 1 : 0.4)
                    }
                }
            }
            if let current = draft {
                HStack(spacing: 8) {
                    TextField("yt", text: Binding(
                        get: { current.keyword },
                        set: { draft?.keyword = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .frame(width: 50)
                    Text("→").foregroundStyle(Palette.muted)
                    TextField("https://www.youtube.com/results?search_query=%s", text: Binding(
                        get: { current.template },
                        set: { draft?.template = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .onSubmit(saveDraft)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            ForEach(prefs.keywords) { entry in
                HStack(spacing: 8) {
                    Text(entry.keyword)
                        .frame(width: 50, alignment: .leading)
                    Text("→").foregroundStyle(Palette.muted)
                    Text(entry.template)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        prefs.keywords.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            Rule()
            Line(L("settings.general.appearance.title"), L("settings.general.appearance.detail")) {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            Rule()
            Line(L("settings.general.pageZoom.title"), L("settings.general.pageZoom.detail")) {
                // The number itself takes it back to 100%.
                Steps(stops: Preferences.zooms, value: $prefs.pageZoom, home: 1) { "\(Int(($0 * 100).rounded()))%" }
            }
            Rule()
            Line(L("settings.general.autocorrect.title"), L("settings.general.autocorrect.detail")) {
                Switch(on: $prefs.autocorrect)
            }
            Rule()
            Line(L("settings.general.peek.title"), L("settings.general.peek.detail")) {
                Switch(on: $prefs.peeksLinks)
            }
            Rule()
            Line(L("settings.general.littleLinks.title"), L("settings.general.littleLinks.detail")) {
                Switch(on: $prefs.littleLinks)
            }
            Rule()
            Line(L("settings.general.commandBar.title"), L("settings.general.commandBar.detail")) {
                Switch(on: $prefs.commandBar)
            }
            Rule()
            Line(L("settings.general.showsLinks.title"), L("settings.general.showsLinks.detail")) {
                Switch(on: $prefs.showsLinks)
            }
            Rule()
            Line(L("settings.general.autoScroll.title"), L("settings.general.autoScroll.detail")) {
                Switch(on: $prefs.autoScroll)
            }
            Rule()
            Line(L("settings.general.fastPages.title"), L("settings.general.fastPages.detail")) {
                Switch(on: $prefs.fastPages)
            }
            Rule()
            Line(L("settings.general.holdsHistory.title"), L("settings.general.holdsHistory.detail")) {
                Switch(on: $prefs.holdsHistory)
            }
            Rule()
            Line(L("settings.general.floatFlicks.title"), L("settings.general.floatFlicks.detail")) {
                Switch(on: $prefs.floatFlicks)
            }
            Rule()
            Line(L("settings.general.waitsForPlay.title"), L("settings.general.waitsForPlay.detail")) {
                Switch(on: $prefs.waitsForPlay)
            }
            Rule()
            Line(L("settings.general.floatsOnLeave.title"), L("settings.general.floatsOnLeave.detail")) {
                Switch(on: $prefs.floatsOnLeave)
            }
            Rule()
            Line(L("settings.general.floatsAway.title"), L("settings.general.floatsAway.detail")) {
                Switch(on: $prefs.floatsAway)
            }
            Rule()
            Line(L("settings.general.bench.title"), L("settings.general.bench.detail")) {
                Switch(on: $prefs.bench)
            }
        }
    }

    /// Checked when it's saved, not as it's typed into the list: a shortcut
    /// only exists once its address is one it's safe to send words to.
    private var draftProblem: String? {
        guard let draft else { return nil }
        return Keyword.problem(word: draft.keyword, template: draft.template, among: prefs.keywords)
    }

    private var keywordDetail: String {
        guard let draft else {
            return L("settings.general.siteShortcuts.detail")
        }
        if draft.keyword.isEmpty, draft.template.isEmpty {
            return L("settings.general.siteShortcuts.detailEmpty")
        }
        return draftProblem ?? L(
            "settings.general.siteShortcuts.detailDraft",
            draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            draft.name
        )
    }

    private func saveDraft() {
        guard let current = draft, draftProblem == nil else { return }
        prefs.keywords.append(Keyword(
            keyword: current.keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            template: current.template.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        draft = nil
    }

    private var searchDetail: String {
        guard prefs.engine == .custom else { return L("settings.general.searchWith.detail") }
        guard Engine.accepts(prefs.customEngine) else {
            return L("settings.general.searchWith.detailCustomBad")
        }
        return L("settings.general.searchWith.detailCustom", prefs.engine.name(custom: prefs.customEngine))
    }

    // MARK: - tabs

    /// Where back, forward and reload sit with the tabs across the top. With
    /// the sidebar they are already beside the window's buttons: nothing to
    /// move, and the line isn't shown.
    private var toolbar: some View {
        Card {
            Line(L("settings.tabs.navLeft.title"), L("settings.tabs.navLeft.detail")) {
                Switch(on: $prefs.navigationLeft)
            }
        }
    }

    private var tabs: some View {
        Card {
            Line(L("settings.tabs.sidebar.title"), L("settings.tabs.sidebar.detail", sideEdge(prefs.sidePosition))) {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.glide) { prefs.sidebar = on } }
                ))
            }
            if prefs.sidebar {
                Rule()
                Line(L("settings.tabs.position.title"), L("settings.tabs.position.detail", sideEdge(prefs.sidePosition))) {
                    Segmented(options: SidebarPosition.allCases.map { ($0, $0.title) }, selection: $prefs.sidePosition)
                }
                Rule()
                Line(L("settings.tabs.sideHides.title"), L("settings.tabs.sideHides.detail", sideEdge(prefs.sidePosition))) {
                    Switch(on: $prefs.sideHides)
                }
            }
            Rule()
            Line(L("settings.tabs.glyph.title"), L("settings.tabs.glyph.detail")) {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            Rule()
            Line(L("settings.tabs.bookmarksBar.title"), L("settings.tabs.bookmarksBar.detail")) {
                Switch(on: $prefs.bookmarksBar)
            }
            Rule()
            Line(L("settings.tabs.reading.title"), L("settings.tabs.reading.detail")) {
                Switch(on: $prefs.showsReading)
            }
            Rule()
            Line(L("settings.tabs.sleep.title"), L("settings.tabs.sleep.detail")) {
                Switch(on: $prefs.sleepsTabs)
            }
            Rule()
            Line(L("settings.tabs.lazy.title"), L("settings.tabs.lazy.detail")) {
                Switch(on: $prefs.lazyTabs)
            }
            Rule()
            Line(L("settings.tabs.siteSearch.title"), L("settings.tabs.siteSearch.detail")) {
                Switch(on: $prefs.searchesSites)
            }
            Rule()
            Line(L("settings.tabs.fresh.title"), L("settings.tabs.fresh.detail")) {
                Switch(on: $prefs.startsFresh)
            }
            Rule()
            Line(L("settings.tabs.spaces.title"), L("settings.tabs.spaces.detail")) {
                Switch(on: $prefs.usesSpaces)
            }
            Rule()
            Line(L("settings.tabs.groups.title"), L("settings.tabs.groups.detail")) {
                Switch(on: $prefs.usesTabGroups)
            }
            Rule()
            Line(L("settings.tabs.split.title"), L("settings.tabs.split.detail")) {
                Switch(on: $prefs.splitView)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return L("settings.passwords.offer.taken", name)
        }
        return L("settings.passwords.offer.detail")
    }

    private var passkeysDetail: String {
        if !prefs.passkeysPossible { return L("settings.passwords.passkeys.noEntitlement") }
        if Passkeys.access == .denied { return L("settings.passwords.passkeys.denied") }
        return L("settings.passwords.passkeys.ok")
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L("settings.passwords.yours.title"), L("settings.passwords.yours.detail")) {
                    Pill(L("settings.passwords.open")) {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line(L("settings.passwords.offer.title"), savingDetail) {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line(L("settings.passwords.fill.title"), L("settings.passwords.fill.detail")) {
                    Switch(on: $prefs.fillsPasswords)
                }
                Rule()
                Line(L("settings.passwords.passkeys.title"), passkeysDetail) {
                    Switch(on: $prefs.passkeys)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line(L("settings.passwords.never.title"), L("settings.passwords.never.detail", Vault.never.count)) {
                        Pill(L("settings.passwords.forget")) {
                            Vault.never = []
                            browser.announce(L("announce.everySiteCanAsk"))
                        }
                    }
                }
            }
            Card {
                Line(L("settings.passwords.bring.title"), L("settings.passwords.bring.detail")) {
                    Pill(L("settings.passwords.import")) {
                        browser.tuning = false
                        browser.bringingIn = ""
                    }
                }
            }
        }
    }

    // MARK: - downloads

    private var downloads: some View {
        Card {
            Line(L("settings.downloads.saveTo"), prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Pill(L("settings.downloads.change")) { chooseFolder() }
            }
            Rule()
            Line(L("settings.downloads.ask.title")) {
                Switch(on: $prefs.asksWhereToSave)
            }
            Rule()
            Line(L("settings.downloads.alwaysButton.title"), L("settings.downloads.alwaysButton.detail")) {
                Switch(on: $prefs.alwaysShowsDownloads)
            }
        }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L("settings.privacy.shield.title"), shield.trouble ?? L("settings.privacy.shield.detail")) {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, L("settings.privacy.shield.broken")) {
                        Pill(L("settings.privacy.tryAgain")) { shield.compile() }
                    }
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line(L("settings.privacy.blockOnHost.title", host), L("settings.privacy.blockOnHost.detail")) {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line(L("settings.privacy.tracking.title"), L("settings.privacy.tracking.detail")) {
                    Switch(on: Binding(get: { !prefs.keepsSignIns }, set: { prefs.keepsSignIns = !$0 }))
                }
                Rule()
                Line(L("settings.privacy.capture.title"), L("settings.privacy.capture.detail")) {
                    Pill(L("settings.privacy.forgetChoices")) { browser.forgetCaptureChoices() }
                }
                Rule()
                Line(L("settings.privacy.notifications.title"), L("settings.privacy.notifications.detail")) {
                    Switch(on: $prefs.siteNotifications)
                }
                NotificationSites()
            }
            Card {
                Line(L("settings.privacy.history.title"), L("settings.privacy.history.detail")) {
                    Pill(L("settings.privacy.clear")) { browser.clearHistory() }
                }
                Rule()
                Line(L("settings.privacy.cookies.title"), L("settings.privacy.cookies.detail")) {
                    Pill(L("settings.privacy.signOutAll")) { browser.clearSites() }
                }
                Rule()
                Line(L("settings.privacy.cache.title"), L("settings.privacy.cache.detail")) {
                    Pill(L("settings.privacy.clear")) { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Logomark()
                    .fill(Palette.ink, style: FillStyle(eoFill: true))
                    .aspectRatio(Logomark.canvas.width / Logomark.canvas.height, contentMode: .fit)
                    .frame(height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("settings.about.brand"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(L("settings.about.byline", Updater.version))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)

            Card {
                Line(versionTitle, versionDetail) { versionControl }
                Rule()
                Line(L("settings.about.autoUpdate.title"), L("settings.about.autoUpdate.detail")) {
                    Switch(on: $prefs.installsUpdates)
                }
                Rule()
                Line(L("settings.about.feedback.title"), L("settings.about.feedback.detail")) {
                    Pill(L("settings.about.feedback.pill")) { Links.writeFeedback() }
                }
                Rule()
                Line(L("settings.about.whatsNew.title"), L("settings.about.whatsNew.detail")) {
                    Pill(L("settings.about.whatsNew.pill")) { browser.notesShowing = true }
                }
            }

            Card {
                Shortcut("⌘L", L("settings.about.shortcut.address"))
                Rule()
                Shortcut("⌘K", L("settings.about.shortcut.switchTab"))
                Rule()
                Shortcut("⌘T  ⌘W  ⇧⌘T", L("settings.about.shortcut.tabOps"))
                Rule()
                Shortcut("⇧⌘V", L("settings.about.shortcut.pasteGo"))
                Rule()
                Shortcut("⇧⌘C", L("settings.about.shortcut.copyAddress"))
                Rule()
                Shortcut("⌃⇥  ⌘1–9", L("settings.about.shortcut.nextTab"))
                Rule()
                Shortcut("⇧⌘S", L("settings.about.shortcut.sidebar"))
                Rule()
                Shortcut("⌘S", L("settings.about.shortcut.fold"))
                Rule()
                Shortcut("⇧⌘R", L("settings.about.shortcut.reader"))
                Rule()
                Shortcut("⇧⌘H", L("settings.about.shortcut.hide"))
                Rule()
                Shortcut("⇧⌘P", L("settings.about.shortcut.float"))
                Rule()
                Shortcut("⇧⌘⌫", L("settings.about.shortcut.clear"))
            }
        }
    }

    /// The version line follows the newer build from found to fetched to
    /// in place; with none, it is simply this one.
    private var versionTitle: String {
        switch updater.stage {
        case .none: return L("settings.about.updates")
        case .fetching(let next): return L("settings.about.downloading", next.version)
        case .ready(let next): return L("settings.about.ready", next.version)
        case .offered(let next), .waiting(let next): return L("settings.about.isOut", next.version)
        }
    }

    private var versionDetail: String {
        switch updater.stage {
        case .none:
            return updater.lastChecked.map { L("settings.about.checkedRelative", $0.formatted(.relative(presentation: .named))) }
                ?? L("settings.about.checkedHourly")
        case .fetching(let next):
            return next.notes ?? L("settings.about.fetchingNote")
        case .ready(let next):
            return next.notes ?? L("settings.about.readyNote")
        case .offered(let next):
            return next.notes ?? L("settings.about.offeredNote")
        case .waiting(let next):
            return next.notes ?? L("settings.about.waitingNote")
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? L("settings.about.checking") : L("settings.about.checkNow")) {
                updater.check { found in
                    if found == nil { browser.announce(L("announce.latestOne")) }
                }
            }
            .disabled(updater.checking)
        case .fetching:
            Ring(size: 12)
        case .ready:
            Pill(L("settings.about.relaunch"), filled: true) { updater.relaunch() }
        case .offered:
            Pill(updater.fetchingDisk ? L("settings.about.downloadingPill") : L("settings.about.download"), filled: true) { updater.openDisk() }
                .disabled(updater.fetchingDisk)
        case .waiting:
            Pill(L("settings.about.install"), filled: true) { updater.install() }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = L("settings.downloads.useFolder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces

    /// A keystroke and what it does.
    private struct Shortcut: View {
        let keys: String
        let does: String
        init(_ keys: String, _ does: String) { self.keys = keys; self.does = does }

        var body: some View {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// True when the control has the whole width to itself, so the choices
    /// share it evenly instead of each taking only what its word needs.
    var wide = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosen", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(Motion.settle) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.ink : Palette.faint)
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.settle) { on.toggle() } }
            .animation(Motion.settle, value: on)
    }
}

/// A value moved one stop at a time: − and + either side of it, in the same
/// outlined capsule as a pill. Pressing the value itself takes it home.
struct Steps: View {
    let stops: [Double]
    @Binding var value: Double
    let home: Double
    let label: (Double) -> String

    /// The nearest stop either way — a value between stops, from before
    /// there were stops, still moves to a round one.
    private var below: Double? { stops.last { $0 < value - 0.001 } }
    private var above: Double? { stops.first { $0 > value + 0.001 } }

    var body: some View {
        HStack(spacing: 0) {
            Step(icon: "minus", to: below) { value = $0 }
            Button { value = home } label: {
                Text(label(value))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to \(label(home))")
            Step(icon: "plus", to: above) { value = $0 }
        }
        .padding(.horizontal, 2)
        .frame(height: 24)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private struct Step: View {
        let icon: String
        let to: Double?
        let act: (Double) -> Void
        @State private var hovering = false

        var body: some View {
            Button { if let to { act(to) } } label: {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(to == nil ? Palette.faint : Palette.ink)
                    .frame(width: 20, height: 20)
                    .background(hovering && to != nil ? Palette.hover : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(to == nil)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// Settings › Privacy: the sites allowed to send notifications, each with a
/// way to take it back.
private struct NotificationSites: View {
    @ObservedObject private var notifications = SiteNotifications.shared

    var body: some View {
        let sites = SiteNotifications.allowed
        if !sites.isEmpty {
            ForEach(sites, id: \.self) { site in
                Rule()
                Line(URL(string: site).map(SiteCard.site) ?? site, "Can send notifications") {
                    Pill(L("settings.extensions.remove")) { SiteNotifications.forget(site) }
                }
            }
        }
    }
}
