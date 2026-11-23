import AppKit
import CoreServices
import os
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: routerID, category: "Routing")

private func webURL(_ value: String) -> URL? {
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          let host = url.host, !host.isEmpty else { return nil }
    return url
}

@MainActor
private final class Router: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var settingsWindow: NSWindow?
    private var receivedOpenRequest = false
    private var routing = false
    private var pending: [(url: URL, sender: String?)] = []

    func register() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(receive(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Give Launch Services time to deliver the triggering URL on a cold launch.
            try? await Task.sleep(for: .milliseconds(350))
            if !receivedOpenRequest { showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        receivedOpenRequest = true
        showSettings()
        return false
    }

    private func showSettings() {
        settings.refresh()
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, chooseApplication: { [weak self] rule in
                self?.chooseApplication(for: rule)
            }, confirmDefaultBrowser: { [weak self] browser in
                self?.settings.preferences.defaultBrowser = browser
                self?.drainPendingLinks()
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Browser Switchboard"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 650, height: 510))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        activate()
    }

    private func chooseApplication(for rule: Rule) {
        guard let settingsWindow else { return }
        let panel = NSOpenPanel()
        panel.title = settings.language.text("Choose an app")
        panel.prompt = settings.language.text("Select")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: settingsWindow) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let id = Bundle(url: url)?.bundleIdentifier, id != routerID else { return }
            if case .browser = rule, case .browser = settings.preferences.rules[id] {
                return
            }
            settings.preferences.rules[id] = rule
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        receivedOpenRequest = true
        enqueue(filenames.map { (URL(fileURLWithPath: $0), nil) })
        application.reply(toOpenOrPrint: .success)
    }

    @objc private func receive(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = webURL(value) else {
            logger.error("Discarded invalid URL event")
            return
        }
        receivedOpenRequest = true
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? 0
        let sender = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
        logger.notice("Source=\(sender ?? "unknown", privacy: .public) PID=\(pid)")
        enqueue([(url, sender)])
    }

    private func enqueue(_ requests: [(URL, String?)]) {
        pending.append(contentsOf: requests)
        drainPendingLinks()
    }

    private func drainPendingLinks() {
        guard settings.preferences.defaultBrowser != nil else {
            showSettings()
            return
        }
        guard !routing else { return }
        routing = true
        Task {
            while !pending.isEmpty {
                let request = pending.removeFirst()
                await route(request.url, sender: request.sender)
            }
            routing = false
        }
    }

    private func route(_ url: URL, sender: String?) async {
        settings.refresh()
        let browsers = settings.browsers
        let requested = settings.preferences.destination(for: sender, available: browsers.map(\.id))
        let browser: Browser?
        switch requested {
        case .browser(let id):
            browser = browsers.first { $0.id == id }
        case .ask:
            guard let chosen = await chooseBrowser(from: browsers, for: url, sender: sender) else { return }
            browser = chosen
        case nil:
            browser = nil
        }
        guard let browser else {
            showError(settings.language.text("No browser available"), detail: settings.language.text("Install a browser that can open HTTP and HTTPS links."))
            return
        }
        logger.notice("Destination=\(browser.id, privacy: .public)")
        do {
            let opened = try await NSWorkspace.shared.open([url], withApplicationAt: browser.url,
                                                            configuration: NSWorkspace.OpenConfiguration())
            logger.notice("Opened=\(opened.bundleIdentifier ?? browser.id, privacy: .public)")
        } catch {
            logger.error("Failed to open: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
            showError(settings.language.text("Could not open the link"), detail: browser.name)
        }
    }

    private func chooseBrowser(from browsers: [Browser], for url: URL, sender: String?) async -> Browser? {
        let app = sender.map { settings.name(for: $0) } ?? settings.language.text("Unknown app")
        let prompt = BrowserPrompt(
            browsers: browsers,
            defaultBrowser: settings.preferences.defaultBrowser,
            detail: settings.language.text("%1$@ wants to open a link to %2$@.", app, url.host ?? settings.language.text("the web")),
            language: settings.language
        )
        defer { withExtendedLifetime(prompt) {} }
        return await prompt.choose()
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        activate()
        alert.runModal()
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    let chrome = "com.google.Chrome"
    let safari = "com.apple.Safari"
    let teams = "com.microsoft.teams2"
    let fixture = [chrome, safari, routerID]
    var preferences = RoutingPreferences.initial
    precondition(preferences.defaultBrowser == nil)
    precondition(preferences.rules.isEmpty)
    preferences.defaultBrowser = chrome
    preferences.rules[teams] = .browser(safari)
    precondition(preferences.destination(for: teams, available: fixture) == .browser(safari))
    precondition(preferences.destination(for: nil, available: fixture) == .browser(chrome))
    precondition(preferences.destination(for: teams, available: [chrome]) == .browser(chrome))
    preferences.rules[teams] = .ask
    precondition(preferences.destination(for: teams, available: fixture) == .ask)
    precondition(preferences.destination(for: teams, available: [routerID]) == nil)
    preferences.defaultBrowser = safari
    precondition(preferences.destination(for: "com.apple.TextEdit", available: fixture) == .browser(safari))
    preferences.rules[teams] = .browser(routerID)
    precondition(preferences.destination(for: teams, available: fixture) == .browser(safari))
    let suite = "de.local.browserweiche.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    precondition(Settings(defaults: defaults).preferences.defaultBrowser == nil)
    precondition(Settings(defaults: defaults).preferences.rules.isEmpty)
    Settings(defaults: defaults).preferences = preferences
    precondition(Settings(defaults: defaults).preferences.rules == preferences.rules)
    precondition(Settings(defaults: defaults).preferences.defaultBrowser == safari)
    precondition(webURL("HTTPS://example.com/a?q=1#test") != nil)
    precondition(webURL("http://example.com") != nil)
    precondition(webURL("https:/missing-host") == nil)
    precondition(webURL("file:///tmp/test") == nil)
    precondition(AppLanguage.preferred(from: ["de-DE", "en-US"]) == .german)
    precondition(AppLanguage.preferred(from: ["fr-FR", "en-US", "de-DE"]) == .english)
    precondition(AppLanguage.preferred(from: ["fr-FR"]) == .english)
    precondition(AppLanguage.german.text("Choose a browser") == "Browser auswählen")
    precondition(AppLanguage.english.text("Choose a browser") == "Choose a browser")
    precondition(AppLanguage.german.text("%1$@ wants to open a link to %2$@.", "Test", "example.com")
        == "Test möchte einen Link zu example.com öffnen.")
    let languageSettings = Settings(defaults: defaults)
    precondition(languageSettings.language == .system)
    languageSettings.language = .english
    precondition(Settings(defaults: defaults).language == .english)
    print("25 checks passed")
} else if arguments == ["--status"] {
    for scheme in ["http", "https"] {
        let url = URL(string: "\(scheme)://example.com")!
        print("\(scheme) default: \(NSWorkspace.shared.urlForApplication(toOpen: url)?.path ?? "unknown")")
    }
    for browser in Browser.installed() { print("\(browser.name) [\(browser.id)]") }
} else {
    let app = NSApplication.shared
    let router = Router()
    app.delegate = router
    router.register()
    withExtendedLifetime(router) { app.run() }
}
