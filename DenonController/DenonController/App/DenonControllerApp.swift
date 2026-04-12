import SwiftUI

@main
struct DenonControllerApp: App {

    var body: some Scene {
        // ── Main Window ────────────────────────────────────────────────
        WindowGroup {
            ContentView()
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
            // MenuBarExtra content needs its own ViewModel instance
            MenuBarContent()
        }
        .menuBarExtraStyle(.window)

        // ── Settings ───────────────────────────────────────────────────
        Settings {
            SettingsView()
        }
    }
}

/// Menu bar popover content with its own ViewModel.
/// Shares AVR connection via @AppStorage host preference.
private struct MenuBarContent: View {
    @State private var vm = MainViewModel()

    var body: some View {
        MenuBarPopoverView()
            .environment(vm)
            .onAppear {
                let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
                let auto = UserDefaults.standard.bool(forKey: "autoConnect")
                if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
                    Task { await vm.connect(host: host) }
                }
            }
    }
}
