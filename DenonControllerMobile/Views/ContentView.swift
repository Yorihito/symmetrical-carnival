import SwiftUI

struct ContentView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @State private var showConnection = false

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadLayout
                .sheet(isPresented: $showConnection) { ConnectionView() }
                .onAppear { autoConnect() }
        } else {
            iPhoneLayout
                .sheet(isPresented: $showConnection) { ConnectionView() }
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
            Tab("ホーム", systemImage: "house.fill") {
                NavigationStack {
                    DashboardView(showConnection: $showConnection)
                }
            }
            Tab("チューナー", systemImage: "radio.fill") {
                NavigationStack { TunerView() }
            }
            Tab("プリセット", systemImage: "star.fill") {
                NavigationStack { PresetView() }
            }
            Tab("ゾーン", systemImage: "speaker.2.fill") {
                NavigationStack { ZoneView() }
            }
            Tab("設定", systemImage: "gear") {
                NavigationStack { SettingsView(showConnection: $showConnection) }
            }
        }
    }

    // MARK: - iPad: Split View

    enum SidebarItem: String, CaseIterable, Hashable {
        case dashboard = "ダッシュボード"
        case tuner     = "チューナー"
        case presets   = "プリセット"
        case zone      = "ゾーン"
        case settings  = "設定"

        var systemImage: String {
            switch self {
            case .dashboard: "house.fill"
            case .tuner:     "radio.fill"
            case .presets:   "star.fill"
            case .zone:      "speaker.2.fill"
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
