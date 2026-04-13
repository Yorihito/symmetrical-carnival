import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メインウィンドウへの強参照。
    /// orderOut 後も SwiftUI がウィンドウを解放しないよう strong で保持する。
    var mainWindow: NSWindow?

    /// 初回起動時の非表示処理を済ませたか（ユーザーが明示的に開く場合は抑制しない）
    var didSuppressInitialWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
