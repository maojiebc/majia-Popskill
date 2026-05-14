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
        }
        .windowResizability(.contentMinSize)
        .commands {
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
