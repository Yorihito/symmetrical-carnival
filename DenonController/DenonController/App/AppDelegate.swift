import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 初回ウィンドウ表示の制御を済ませたかどうか（二重実行防止）
    var didHandleInitialWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
