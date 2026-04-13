import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// メインウィンドウへの弱参照（"詳細を開く" が新規作成せず前面表示するために使用）
    weak var mainWindow: NSWindow?

    /// 初回起動時の非表示処理を済ませたか（ユーザーが明示的に開く場合は抑制しない）
    var didSuppressInitialWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI の WindowGroup はこの時点ではウィンドウをまだ生成していないため、
        // 1 run loop 後に処理する（WindowGroup の初期ウィンドウ生成を待つ）
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: {
                !($0 is NSPanel) && $0.canBecomeMain
            }) else { return }

            self.mainWindow = window

            if UserDefaults.standard.bool(forKey: "menuBarOnly") {
                window.alphaValue = 0      // 既に表示されていてもちらつきなく隠す
                window.orderOut(nil)
                window.alphaValue = 1      // 次回表示のために戻す
                self.didSuppressInitialWindow = true
            }
        }
    }
}
