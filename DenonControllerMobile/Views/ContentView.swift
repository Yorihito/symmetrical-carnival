import SwiftUI

struct ContentView: View {
    @Environment(MainViewModel.self) private var vm
    @State private var showConnection = false
    @AppStorage("appLanguage") private var appLanguage = "system"

    private var appLocale: Locale {
        switch appLanguage {
        case "ja": Locale(identifier: "ja")
        case "en": Locale(identifier: "en")
        default:   .autoupdatingCurrent
        }
    }

    private var lBundle: Bundle { makeLocalizedBundle(for: appLocale) }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadLayout
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
                .sheet(isPresented: $showConnection) {
                    ConnectionView()
                        .environment(\.locale, appLocale)
                        .environment(\.localizedBundle, lBundle)
                }
                .onAppear { autoConnect() }
        } else {
            iPhoneLayout
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
                .sheet(isPresented: $showConnection) {
                    ConnectionView()
                        .environment(\.locale, appLocale)
                        .environment(\.localizedBundle, lBundle)
                }
                .onAppear { autoConnect() }
        }
    }

    private func autoConnect() {
        let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
        let auto = UserDefaults.standard.bool(forKey: "autoConnect")
        if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
            Task { await vm.connect(host: host) }
        }
    }

    // MARK: - iPhone: Tab Bar

    private var iPhoneLayout: some View {
        TabView {
            NavigationStack {
                DashboardView(showConnection: $showConnection)
            }
            .tabItem { 
                Label { Text("ホーム", bundle: lBundle) } icon: { Image(systemName: "house.fill") }
            }

            NavigationStack { TunerView() }
            .tabItem { 
                Label { Text("チューナー", bundle: lBundle) } icon: { Image(systemName: "antenna.radiowaves.left.and.right") }
            }

            NavigationStack { InputView() }
            .tabItem { 
                Label { Text("入力ソース", bundle: lBundle) } icon: { Image(systemName: "rectangle.on.rectangle.angled") }
            }

            NavigationStack { RemoteView() }
            .tabItem { 
                Label { Text("リモコン", bundle: lBundle) } icon: { Image(systemName: "dpad") }
            }

            NavigationStack { ZoneView() }
            .tabItem { 
                Label { Text("ゾーン", bundle: lBundle) } icon: { Image(systemName: "square.split.2x1.fill") }
            }

            NavigationStack { SettingsView(showConnection: $showConnection) }
            .tabItem { 
                Label { Text("設定", bundle: lBundle) } icon: { Image(systemName: "gear") }
            }
        }
    }

    // MARK: - iPad: Split View

    enum SidebarItem: String, CaseIterable, Hashable {
        case dashboard = "ダッシュボード"
        case tuner     = "チューナー"
        case presets   = "プリセット"
        case zone      = "ゾーン"
        case remote    = "リモコン"
        case settings  = "設定"

        var systemImage: String {
            switch self {
            case .dashboard: "house.fill"
            case .tuner:     "radio.fill"
            case .presets:   "star.fill"
            case .zone:      "speaker.2.fill"
            case .remote:    "dpad"
            case .settings:  "gear"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = .dashboard

    private var iPadLayout: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedItem) { item in
                Label(LocalizedStringKey(item.rawValue), systemImage: item.systemImage)
            }
            .navigationTitle("Denon Controller")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { connectionFooter }
        } detail: {
            iPadDetail(item: selectedItem ?? .dashboard)
        }
    }

    @ViewBuilder
    private func iPadDetail(item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView(showConnection: $showConnection)
        case .tuner:     TunerView()
        case .presets:   PresetView()
        case .zone:      ZoneView()
        case .remote:    RemoteView()
        case .settings:  SettingsView(showConnection: $showConnection)
        }
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(vm.connectionStatus.label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { showConnection = true } label: {
                Image(systemName: "network").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:            .green
        case .connecting:           .orange
        case .disconnected, .error: .red
        }
    }
}
