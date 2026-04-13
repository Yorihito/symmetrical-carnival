import SwiftUI

@main
struct DenonControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        // ── Main Window（Window = シングルトン、openWindow は既存を前面に出すだけ）──
        Window("Denon Controller", id: "main") {
            ContentView()
                .environment(vm)
                .environment(\.locale, appLocale)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .help) {
                Link("Denon AVR プロトコルリファレンス",
                     destination: URL(string: "https://www.denon.com")!)
            }
        }

        // ── Menu Bar Extra ─────────────────────────────────────────────
        MenuBarExtra("Denon Controller", systemImage: "hifispeaker.fill") {
            MenuBarPopoverView()
                .environment(vm)
                .environment(\.locale, appLocale)
        }
        .menuBarExtraStyle(.window)

        // ── Settings ───────────────────────────────────────────────────
        Settings {
            SettingsView()
                .environment(vm)
                .environment(\.locale, appLocale)
        }
    }
}
