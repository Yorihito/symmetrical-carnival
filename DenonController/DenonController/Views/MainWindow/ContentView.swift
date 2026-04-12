import SwiftUI

enum NavSection: String, Hashable, CaseIterable {
    case dashboard = "ダッシュボード"
    case input     = "入力ソース"
    case surround  = "サラウンド"
    case zone      = "ゾーン"
    case presets   = "プリセット"

    var systemImage: String {
        switch self {
        case .dashboard: "house.fill"
        case .input:     "rectangle.on.rectangle.angled"
        case .surround:  "speaker.wave.3.fill"
        case .zone:      "square.split.2x1.fill"
        case .presets:   "star.fill"
        }
    }
}

struct ContentView: View {
    @State private var vm = MainViewModel()
    @State private var selectedSection: NavSection? = .dashboard
    @State private var showingConnection = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 500)
        .environment(vm)
        .sheet(isPresented: $showingConnection) {
            ConnectionView()
                .environment(vm)
        }
        .onAppear {
            // Auto-connect if configured
            let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
            let auto = UserDefaults.standard.bool(forKey: "autoConnect")
            if auto && !host.isEmpty {
                Task { await vm.connect(host: host) }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(NavSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .listStyle(.sidebar)

            Divider()

            // Connection status footer
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(vm.connectionStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingConnection = true
                } label: {
                    Image(systemName: vm.connectionStatus.isConnected
                          ? "network.badge.shield.half.filled"
                          : "network")
                    .foregroundStyle(vm.connectionStatus.isConnected ? .green : .secondary)
                }
                .help(vm.connectionStatus.isConnected ? "接続済み — クリックで再設定" : "AVR に接続")
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSection ?? .dashboard {
        case .dashboard: DashboardView()
        case .input:     InputView()
        case .surround:  SurroundView()
        case .zone:      ZoneView()
        case .presets:   PresetView()
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:    .green
        case .connecting:   .orange
        case .disconnected, .error: .red
        }
    }
}
