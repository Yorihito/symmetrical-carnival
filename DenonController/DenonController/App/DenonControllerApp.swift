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

    private var lBundle: Bundle { makeLocalizedBundle(for: appLocale) }

    var body: some Scene {
        // ── Main Window ────────────────────────────────────────────────
        WindowGroup(id: "main") {
            ContentView()
                .environment(vm)
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
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
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(vm)
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        // ── Settings ───────────────────────────────────────────────────
        Settings {
            SettingsView()
                .environment(vm)
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
        }
    }
}
