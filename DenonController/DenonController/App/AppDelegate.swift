import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// NSApp.delegate as? AppDelegate のキャストが SwiftUI 経由で失敗するケースがあるため
    /// static shared でシングルトンアクセスする
    nonisolated(unsafe) static weak var shared: AppDelegate?

    var mainWindow: NSWindow?
    var didSuppressInitialWindow = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "menuBarOnly") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
