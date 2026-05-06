import SwiftUI
import AppKit

/// viewDidMoveToWindow を使い、ウィンドウへの追加と同時（表示前）に callback を呼ぶ
private final class WindowObserverView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onWindow?(window)
        onWindow = nil  // 一度だけ呼ぶ
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: WindowObserverView, context: Context) {}
}

enum NavSection: String, Hashable, CaseIterable {
    case dashboard = "ダッシュボード"
    case tuner     = "チューナー"
    case input     = "入力ソース"
    case zone      = "ゾーン"
    case remote    = "リモコン"
    case presets   = "プリセット"

    func localizedTitle(bundle: Bundle) -> Text {
        Text(LocalizedStringKey(rawValue), bundle: bundle)
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house.fill"
        case .input:     "rectangle.on.rectangle.angled"
        case .zone:      "square.split.2x1.fill"
        case .tuner:     "antenna.radiowaves.left.and.right"
        case .remote:    "dpad"
        case .presets:   "star.fill"
        }
    }
}

struct ContentView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Environment(\.localizedBundle) private var bundle
    @State private var selectedSection: NavSection? = .dashboard
    @State private var showingConnection = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingConnection = true
                } label: {
                    Label {
                        Text(vm.connectionStatus.isConnected ? "接続済み" : "接続", bundle: bundle)
                    } icon: {
                        Image(systemName: vm.connectionStatus.isConnected
                            ? "network.badge.shield.half.filled"
                            : "network")
                    }
                    .foregroundStyle(
                        vm.connectionStatus.isConnected ? Color.green
                        : vm.connectionStatus == .connecting ? Color.orange
                        : Color.primary
                    )
                }
                .help(Text(vm.connectionStatus.isConnected ? "接続済み — クリックで再設定" : "AVR に接続", bundle: bundle))
            }
        }
        .background(WindowAccessor { window in
            let delegate = AppDelegate.shared
            delegate?.mainWindow = window
            guard UserDefaults.standard.bool(forKey: "menuBarOnly"),
                  !(delegate?.didSuppressInitialWindow ?? false) else { return }
            delegate?.didSuppressInitialWindow = true
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        })
        .onDisappear {
            guard UserDefaults.standard.bool(forKey: "menuBarOnly") else { return }
            NSApp.setActivationPolicy(.accessory)
            AppDelegate.shared?.mainWindow = nil
        }
        .sheet(isPresented: $showingConnection) {
            ConnectionView()
                .environment(\.locale, locale)
                .environment(\.localizedBundle, bundle)
        }
        .onAppear {
            let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
            let auto = UserDefaults.standard.bool(forKey: "autoConnect")
            if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
                Task { await vm.connect(host: host) }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(NavSection.allCases.filter { $0 != .presets }, id: \.self, selection: $selectedSection) { section in
                Label {
                    section.localizedTitle(bundle: bundle)
                } icon: {
                    Image(systemName: section.systemImage)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(vm.connectionStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSection ?? .dashboard {
        case .dashboard: DashboardView()
        case .input:     InputView()
        case .zone:      ZoneView()
        case .tuner:     TunerView()
        case .remote:    RemoteView()
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
