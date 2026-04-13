import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メインウィンドウへの強参照
    var mainWindow: NSWindow?

    /// 起動時の抑制を済ませたか（true なら以降のウィンドウは抑制しない）
    var didSuppressInitialWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
