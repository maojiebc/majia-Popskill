import AppKit
#if canImport(Sparkle)
import Sparkle
#endif
import SwiftUI

@main
struct PopskillApp: App {
    @NSApplicationDelegateAdaptor(PopskillAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1180, minHeight: 720)
                // "01 紧凑账本" is a light-only warm-paper design. Pin the window
                // to light so system controls (menus, List selection, fields)
                // render light to match the fixed-light pop* palette instead of
                // clashing under macOS dark mode. The single electric-blue accent
                // drives every system tint (selection / focus ring / links).
                .preferredColorScheme(.light)
                .tint(.popAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // Replace the system About panel with our branded version so it
            // shows the real version + bundle ID instead of the SwiftUI
            // default that ships with $(EXECUTABLE_NAME) placeholders.
            CommandGroup(replacing: .appInfo) {
                Button("About Popskill") {
                    appDelegate.showAboutPanel()
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appDelegate.checkForUpdates()
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
        }
    }
}

final class PopskillAppDelegate: NSObject, NSApplicationDelegate {
#if canImport(Sparkle)
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
#endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }

#if canImport(Sparkle)
        if Self.sparkleConfiguration.isReady {
            updaterController.startUpdater()
        }
#endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            return true
        }

        sender.windows.first?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func showAboutPanel() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? "Copyright © 2026 majia."
        let credits = NSAttributedString(
            string: """
            One control surface for your AI capabilities.

            Built on top of CC Switch's skill store, with a Rust sidecar and \
            SwiftUI front-end. Source: github.com/maojiebc/majia-Popskill
            """,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        // NSApplication.AboutPanelOptionKey on macOS doesn't expose a typed
        // `.copyright`, but the underlying string key is "Copyright". The
        // rawValue init form is the documented escape hatch.
        let copyrightKey = NSApplication.AboutPanelOptionKey(rawValue: "Copyright")
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(version) (build \(build))",
            .applicationName: "Popskill",
            .credits: credits,
            copyrightKey: copyright,
        ])
    }

    func checkForUpdates() {
        guard Self.sparkleConfiguration.isReady else {
            showUpdateAlert(
                title: "Updates are not configured",
                message: "Set SUFeedURL and SUPublicEDKey in the app bundle before enabling Sparkle updates."
            )
            return
        }

#if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
#else
        showUpdateAlert(
            title: "Sparkle is not linked",
            message: "Add the Sparkle SDK dependency before enabling App-internal update checks."
        )
#endif
    }

    static var sparkleConfiguration: SparkleConfiguration {
        SparkleConfiguration(bundle: .main)
    }

    private func showUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

struct SparkleConfiguration: Equatable {
    let feedURL: String?
    let publicEDKey: String?

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        feedURL = Self.nonEmptyInfoValue("SUFeedURL", in: infoDictionary)
        publicEDKey = Self.nonEmptyInfoValue("SUPublicEDKey", in: infoDictionary)
    }

    var isReady: Bool {
        feedURL != nil && publicEDKey != nil
    }

    private static func nonEmptyInfoValue(_ key: String, in infoDictionary: [String: Any]) -> String? {
        guard let value = infoDictionary[key] as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
