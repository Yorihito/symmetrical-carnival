import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// ContentView の親ウィンドウへの弱参照（複数ウィンドウ防止に使用）
    weak var mainWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "menuBarOnly") else { return }

        // SwiftUI の WindowGroup は applicationDidFinishLaunching の直後のメインキューで
        // ウィンドウを生成するため、async で一周遅らせると確実に存在する
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.canBecomeMain }
                .forEach { $0.orderOut(nil) }
        }
    }
}
