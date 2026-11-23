import AppKit
import SwiftUI
import UniformTypeIdentifiers

let routerID = "de.local.browserweiche"
private let browserWeicheGreen = Color(red: 0.30, green: 0.60, blue: 0.19)
private let preferenceKey = "BrowserRoutingV2"

enum Rule: Codable, Equatable {
    case browser(String)
    case ask
}

enum Destination: Equatable {
    case browser(String)
    case ask
}

struct RoutingPreferences: Codable {
    static let initial = RoutingPreferences(defaultBrowser: nil, rules: [:])

    var defaultBrowser: String?
    var rules: [String: Rule]

    func destination(for sender: String?, available: [String]) -> Destination? {
        let eligible = available.filter { $0 != routerID }
        let fallback = defaultBrowser.flatMap { eligible.contains($0) ? $0 : nil } ?? eligible.first
        if let sender, let rule = rules[sender] {
            switch rule {
            case .ask:
                return eligible.isEmpty ? nil : .ask
            case .browser(let browser) where eligible.contains(browser):
                return .browser(browser)
            default:
                break
            }
        }
        return fallback.map(Destination.browser)
    }
}

struct Browser: Identifiable {
    let id: String
    let name: String
    let url: URL

    static func installed() -> [Browser] {
        let workspace = NSWorkspace.shared
        let candidates = workspace.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        // An HTTPS handler alone can be an app that delegates browsing elsewhere.
        let htmlViewers = Set(workspace.urlsForApplications(toOpen: .html).compactMap {
            Bundle(url: $0)?.bundleIdentifier
        })
        var seen = Set<String>()
        return candidates.compactMap { url -> Browser? in
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  id != routerID, htmlViewers.contains(id), seen.insert(id).inserted else { return nil }
            return Browser(id: id, name: FileManager.default.displayName(atPath: url.path), url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class Settings: ObservableObject {
    @Published var preferences: RoutingPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: preferenceKey)
            }
        }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "AppLanguage") }
    }

    @Published private(set) var browsers: [Browser] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: "AppLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .system
        preferences = defaults.data(forKey: preferenceKey)
            .flatMap { try? JSONDecoder().decode(RoutingPreferences.self, from: $0) } ?? .initial
    }

    func refresh() {
        browsers = Browser.installed()
    }

    func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return id
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

@MainActor
private final class FirstRunSelection: ObservableObject {
    @Published var browser: String?
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let chooseApplication: (Rule) -> Void
    let confirmDefaultBrowser: (String) -> Void

    @StateObject private var firstRun = FirstRunSelection()

    private var fixedApps: [String] {
        settings.preferences.rules.keys.filter { settings.preferences.rules[$0] != .ask }
            .sorted { settings.name(for: $0).localizedStandardCompare(settings.name(for: $1)) == .orderedAscending }
    }

    private var askApps: [String] {
        settings.preferences.rules.keys.filter { settings.preferences.rules[$0] == .ask }
            .sorted { settings.name(for: $0).localizedStandardCompare(settings.name(for: $1)) == .orderedAscending }
    }

    private var suggestedBrowser: Browser? {
        settings.browsers.first { $0.id != settings.preferences.defaultBrowser } ?? settings.browsers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)
                Text("Browser Switchboard").font(.title2.bold())
                Spacer()
                Button { settings.refresh() } label: {
                    Label(settings.language.text("Refresh browser list"), systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help(settings.language.text("Refresh browser list"))
            }
            .padding(22)
            Divider()
            Form {
                Picker(settings.language.text("Language"), selection: $settings.language) {
                    Text(settings.language.text("System language")).tag(AppLanguage.system)
                    Text(AppLanguage.english.label).tag(AppLanguage.english)
                    Text(AppLanguage.german.label).tag(AppLanguage.german)
                }
                if settings.preferences.defaultBrowser == nil {
                    Section(settings.language.text("Choose your default browser")) {
                        Text(settings.language.text("Switchboard uses this browser for links without a matching app rule."))
                        Picker(settings.language.text("Browser"), selection: $firstRun.browser) {
                            Text(settings.language.text("Select a browser")).tag(nil as String?)
                            ForEach(settings.browsers) { browser in
                                Text(browser.name).tag(Optional(browser.id))
                            }
                        }
                        if settings.browsers.isEmpty {
                            Text(settings.language.text("No browser available")).foregroundStyle(.secondary)
                        }
                        Button(settings.language.text("Continue")) {
                            if let id = firstRun.browser { confirmDefaultBrowser(id) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!settings.browsers.contains { $0.id == firstRun.browser })
                    }
                } else {
                    routingSections
                }
            }
            .formStyle(.grouped)
        }
        .tint(browserWeicheGreen)
        .frame(minWidth: 570, idealWidth: 650, minHeight: 420, idealHeight: 510)
    }

    @ViewBuilder private var routingSections: some View {
        Section(settings.language.text("Default browser")) {
            browserPicker(settings.language.text("Browser"), selection: defaultBrowserSelection)
            Text(settings.language.text("For apps without a rule and links from an unknown source."))
                .font(.callout).foregroundStyle(.secondary)
        }
        Section(settings.language.text("Fixed browser per app")) {
            ForEach(fixedApps, id: \.self) { id in
                HStack {
                    appLabel(id)
                    Spacer()
                    browserPicker(settings.language.text("Browser for %@", settings.name(for: id)), selection: fixedBrowser(id))
                        .labelsHidden()
                        .frame(width: 190)
                    removeRule(id)
                }
            }
            addButton(settings.language.text("Add app with a fixed browser"), rule: suggestedBrowser.map { .browser($0.id) })
        }
        Section(settings.language.text("Ask for every link")) {
            ForEach(askApps, id: \.self) { id in
                HStack {
                    appLabel(id)
                    Spacer()
                    removeRule(id)
                }
            }
            addButton(settings.language.text("Add app to ask each time"), rule: .ask)
        }
    }

    private var defaultBrowserSelection: Binding<String> {
        Binding {
            settings.preferences.defaultBrowser ?? ""
        } set: { browser in
            settings.preferences.defaultBrowser = browser
        }
    }

    private func appLabel(_ id: String) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(settings.name(for: id)).lineLimit(1).help(id)
        }
    }

    private func browserPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            if !settings.browsers.contains(where: { $0.id == selection.wrappedValue }) {
                Text(settings.language.text("Unavailable")).tag(selection.wrappedValue)
            }
            ForEach(settings.browsers) { browser in
                Text(browser.name).tag(browser.id)
            }
        }
        .disabled(settings.browsers.isEmpty)
    }

    private func fixedBrowser(_ id: String) -> Binding<String> {
        Binding {
            if case .browser(let browser) = settings.preferences.rules[id] { return browser }
            return settings.preferences.defaultBrowser ?? ""
        } set: { browser in
            settings.preferences.rules[id] = .browser(browser)
        }
    }

    private func removeRule(_ id: String) -> some View {
        Button {
            settings.preferences.rules.removeValue(forKey: id)
        } label: {
            Label(settings.language.text("Remove rule for %@", settings.name(for: id)), systemImage: "minus.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(settings.language.text("Remove rule"))
    }

    private func addButton(_ title: String, rule: Rule?) -> some View {
        Button {
            if let rule { chooseApplication(rule) }
        } label: {
            Label(title, systemImage: "plus")
        }
        .disabled(rule == nil)
    }
}

@MainActor
final class BrowserPrompt: NSObject, NSWindowDelegate, ObservableObject {
    private let browsers: [Browser]
    @Published var selection: String?
    private let detail: String
    private let language: AppLanguage
    private var window: NSPanel?
    private var reply: CheckedContinuation<Browser?, Never>?

    init(browsers: [Browser], defaultBrowser: String?, detail: String, language: AppLanguage) {
        self.browsers = browsers
        selection = browsers.first { $0.id == defaultBrowser }?.id ?? browsers.first?.id
        self.detail = detail
        self.language = language
    }

    func choose() async -> Browser? {
        await withCheckedContinuation { (reply: CheckedContinuation<Browser?, Never>) in
            self.reply = reply
            let view = BrowserPromptView(
                browsers: browsers,
                detail: detail,
                language: language,
                prompt: self
            ) { [weak self] browser in
                self?.finish(browser)
            }
            let panel = NSPanel(contentViewController: NSHostingController(rootView: view))
            panel.title = language.text("Choose a browser")
            panel.styleMask = [.titled, .closable]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center()
            window = panel
            panel.makeKeyAndOrderFront(nil)
            if #available(macOS 14, *) { NSApp.activate() }
            else { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil, close: false)
    }

    private func finish(_ browser: Browser?, close: Bool = true) {
        guard let reply else { return }
        self.reply = nil
        let panel = window
        window = nil
        if close { panel?.close() }
        reply.resume(returning: browser)
    }
}

private struct BrowserPromptView: View {
    let browsers: [Browser]
    let detail: String
    let language: AppLanguage
    @ObservedObject var prompt: BrowserPrompt
    let finish: (Browser?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Which browser should open this link?")).font(.headline)
            Text(detail).foregroundStyle(.secondary)
            List(browsers, selection: $prompt.selection) { browser in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path))
                        .resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                    Text(browser.name)
                }
                .tag(browser.id)
            }
            .listStyle(.bordered)
            .frame(height: min(max(CGFloat(browsers.count) * 34, 86), 240))
            .accessibilityLabel(language.text("Available browsers"))
            HStack {
                Spacer()
                Button(language.text("Cancel")) { finish(nil) }.keyboardShortcut(.cancelAction)
                Button(language.text("Open")) { finish(browsers.first { $0.id == prompt.selection }) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.selection == nil)
            }
        }
        .padding(20)
        .tint(browserWeicheGreen)
        .frame(width: 420)
    }
}
