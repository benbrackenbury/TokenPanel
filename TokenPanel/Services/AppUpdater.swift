import Foundation
#if os(macOS)
import AppKit
import Sparkle
#endif

@Observable
@MainActor
final class AppUpdater {
    var currentVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        #if DEBUG
        return "\(version) (debug)"
        #else
        return version
        #endif
    }

    var isEnabled: Bool { Self.shouldCheckForUpdates }

    var disabledReason: String {
        "Update checks are off for local Xcode builds."
    }

    #if os(macOS)
    private let sparkleDelegate = SparkleDelegate()
    private let controller: SPUStandardUpdaterController?
    #endif

    init() {
        #if os(macOS)
        if Self.shouldCheckForUpdates {
            let sparkle = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: sparkleDelegate,
                userDriverDelegate: nil
            )
            controller = sparkle
            // startingUpdater: true shows Sparkle's "failed to start" alert when
            // XPC helpers cannot launch (ad-hoc signed host). Start quietly.
            do {
                try sparkle.updater.start()
            } catch {
                NSLog("Sparkle start failed: \(error.localizedDescription)")
            }
        } else {
            controller = nil
        }
        #endif
    }

    /// Skip Debug and anything launched out of Xcode's build folder.
    static var shouldCheckForUpdates: Bool {
        #if DEBUG
        return false
        #else
        let path = Bundle.main.bundlePath
        if path.contains("/DerivedData/") { return false }
        if path.contains("/Build/Products/") { return false }
        return true
        #endif
    }

    func check() {
        #if os(macOS)
        guard isEnabled, let controller, controller.updater.canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }
}

#if os(macOS)
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
