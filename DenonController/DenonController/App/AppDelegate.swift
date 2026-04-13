import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

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
