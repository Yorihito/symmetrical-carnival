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

    @State private var isSplashScreenActive = true

    var body: some View {
        ZStack {
            if isSplashScreenActive {
                splashView
                    .transition(.opacity)
                    .zIndex(2)
            }
            
            mainContent
                .zIndex(1)
            
            // 共通エラー通知オーバーレイ
            if let msg = vm.errorMessage {
                errorOverlay(msg: msg)
                    .zIndex(3)
            }
        }
        .animation(.spring(), value: vm.errorMessage)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isSplashScreenActive = false
                }
            }
        }
    }

    private var mainContent: some View {
        Group {
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
    }

    private var splashView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 背景に薄いグラデーションで高級感を出す
            RadialGradient(
                gradient: Gradient(colors: [Color.accentColor.opacity(0.15), .black]),
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image("SplashIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 20)
                
                Text("Denon Controller")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(1.0)
            }
        }
    }

    private func errorOverlay(msg: String) -> some View {
        VStack {
            Text(msg)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.9), in: Capsule())
                .shadow(radius: 4)
                .padding(.top, 50)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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
                Label {
                    Text(LocalizedStringKey(item.rawValue), bundle: lBundle)
                } icon: {
                    Image(systemName: item.systemImage)
                }
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
            Text(LS(vm.connectionStatus.label, lBundle)).font(.caption).foregroundStyle(.secondary)
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
