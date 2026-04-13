import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メインウィンドウへの弱参照（"詳細を開く" が新規作成せず前面表示するために使用）
    weak var mainWindow: NSWindow?

    /// 初回起動時の非表示処理を済ませたか（ユーザーが明示的に開く場合は抑制しない）
    var didSuppressInitialWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
