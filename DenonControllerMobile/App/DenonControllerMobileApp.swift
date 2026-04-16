import SwiftUI

@main
struct DenonControllerMobileApp: App {
    @State private var vm = MainViewModel()
    @AppStorage("appLanguage") private var appLanguage = "system"

    private var appLocale: Locale {
        switch appLanguage {
        case "ja": Locale(identifier: "ja")
        case "en": Locale(identifier: "en")
        default:   .autoupdatingCurrent
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vm)
                .environment(\.locale, appLocale)
                .onAppear { applyWindowBackground() }
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
