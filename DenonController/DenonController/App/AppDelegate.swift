import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowObserver: Any?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "menuBarOnly") else { return }

        // SwiftUI の Window シーンがいつ makeKeyAndOrderFront を呼ぶか不定のため、
        // 「最初にメインウィンドウがキーになった瞬間」を通知で捕まえて即座に隠す
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self,
                  let window = notif.object as? NSWindow,
                  window.canBecomeMain,
                  !(window is NSPanel) else { return }
            // 一度だけ実行して解除
            if let obs = windowObserver {
                NotificationCenter.default.removeObserver(obs)
                windowObserver = nil
            }
            window.orderOut(nil)
            window.alphaValue = 1   // 次回表示のために alpha を戻す
        }
    }
}
