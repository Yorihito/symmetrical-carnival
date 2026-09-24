import SwiftUI

@main
struct DenonControllerMobileApp: App {
    @State private var vm = MainViewModel()
    @State private var supportStore = SupportStore()
    @AppStorage("appLanguage") private var appLanguage = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            "autoConnect": true
        ])
    }

    private var appLocale: Locale {
        switch appLanguage {
        case "ja": Locale(identifier: "ja")
        case "en": Locale(identifier: "en")
        default:   .autoupdatingCurrent
        }
    }

    var body: some Scene {
        WindowGroup {
            let locale = appLocale
            ContentView()
                .id(appLanguage)
                .environment(vm)
                .environment(supportStore)
                .environment(\.locale, locale)
                .environment(\.localizedBundle, makeLocalizedBundle(for: locale))
                .onAppear { applyWindowBackground() }
                // 取引の監視は起動直後から行う（承認待ちだった投げ銭の完了を取りこぼさないため）
                .task { await supportStore.start() }
                #if DEBUG
                .task {
                    if let target = MainViewModel.debugConnectHost {
                        // "host" または "host:port"（ポートを付けると Denon として接続する）
                        let parts = target.split(separator: ":").map(String.init)
                        let port = parts.count > 1 ? Int(parts[1]) : nil
                        await vm.connect(host: parts[0], port: port, brand: port == nil ? nil : .denon, allowReheal: false)
                        await vm.runDebugExercise()
                    }
                }
                #endif
        }
    }

    private func applyWindowBackground() {
        // iOS 26 の TabView はウィンドウ背景（壁紙）が透けて見えるため、
        // UIWindow の背景色を明示的に設定して壁紙が見えないようにする
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.backgroundColor = .systemBackground }
    }
}
