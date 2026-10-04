import Foundation
#if os(macOS)
import AppKit
import Sparkle
#endif

@Observable
@MainActor
final class AppUpdater {
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var isEnabled: Bool { Self.shouldCheckForUpdates }

    #if os(macOS)
    private let sparkleDelegate = SparkleDelegate()
    private let controller: SPUStandardUpdaterController?
    #endif

    init() {
        #if os(macOS)
        if Self.shouldCheckForUpdates {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: sparkleDelegate,
                userDriverDelegate: nil
            )
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
        guard isEnabled, let controller else { return }
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
