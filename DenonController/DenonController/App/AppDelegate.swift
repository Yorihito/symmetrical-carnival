import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メインウィンドウへの強参照
    var mainWindow: NSWindow?

    /// 初回起動時の非表示処理を済ませたか
    var didSuppressInitialWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // menuBarOnly モードでは起動時に .accessory に設定することで
        // SwiftUI の WindowGroup ウィンドウが自動表示されるのを防ぐ。
        // "詳細を開く" 時に .regular へ戻す。
        if UserDefaults.standard.bool(forKey: "menuBarOnly") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
