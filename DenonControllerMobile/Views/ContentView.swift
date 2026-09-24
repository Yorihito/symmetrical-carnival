import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(MainViewModel.self) private var vm
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConnection = false
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("volumeControlStyle") private var volumeControlStyle = "slider"
    @AppStorage("hasShownVolumeDialIntroductionV1") private var hasShownVolumeDialIntroduction = false
    @State private var showingVolumeDialIntroduction = false
    @Environment(SupportStore.self) private var supportStore
    @State private var showingSupportRequest = false
    @State private var showingSupportSheet = false
    @State private var selectedTab = ContentView.initialTab

    // MARK: - In-app prompts (お願い・案内の調整。設計: docs/in-app-prompts-design.md)
    @State private var showingCompatibilityBanner = false
    @State private var showingCompatibilityReportSheet = false
    @State private var connectedAt: Date?
    @State private var lastEvaluatedOperationAt: Date?
    @State private var pauseWatchTask: Task<Void, Never>?
    @State private var compatBannerAutoHideTask: Task<Void, Never>?

    /// 起動時に選ぶタブ。DEBUG ビルドのスクリーンショット撮影では起動引数 `-uiDemoTab` で指定する
    nonisolated private static var initialTab: String {
        #if DEBUG
        if let tab = MainViewModel.screenshotDemoTab, tab != "connection" { return tab }
        #endif
        return "home"
    }

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
            } else if let key = vm.transientNoticeKey {
                // 自動再接続などの一時的なお知らせ（エラー表示があるときはそちらを優先）
                noticeOverlay(key: key)
                    .zIndex(3)
            }

            // 動作報告の案内（ダッシュボード下部の小さな表示。モーダルではない）
            if showingCompatibilityBanner {
                compatibilityBannerOverlay
                    .zIndex(4)
            }
        }
        .animation(.spring(), value: vm.errorMessage)
        .animation(.spring(), value: vm.transientNoticeKey)
        .animation(.spring(), value: showingCompatibilityBanner)
        .onAppear {
            #if DEBUG
            // テスト用: お願い・利用実績の記録を全部消してから起動する（起動引数 -promptReset）
            PromptCoordinator.debugResetIfRequested()
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isSplashScreenActive = false
                }
            }
            #if DEBUG
            // App Store 用スクリーンショット撮影用: 接続中の画面を再現する（scripts/capture-screenshots.sh）
            if MainViewModel.isScreenshotDemo { vm.applyScreenshotDemoState() }
            if MainViewModel.screenshotDemoTab == "connection" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { showConnection = true }
            }
            #endif
            // スクリーンショット撮影用: スプラッシュが消えたら「開発を応援する」を開く
            // （DEBUG ビルドの起動引数 -uiDemoSupport。scripts/capture-screenshots.sh）
            if SupportView.isScreenshotDemo {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    showingSupportSheet = true
                }
            }
        }
        .onChange(of: vm.connectionStatus) { _, status in
            guard status == .connected else {
                pauseWatchTask?.cancel()
                pauseWatchTask = nil
                connectedAt = nil
                lastEvaluatedOperationAt = nil
                return
            }
            #if DEBUG
            if MainViewModel.isScreenshotDemo { return }   // 撮影中は接続時のダイアログを出さない
            #endif
            connectedAt = Date()
            lastEvaluatedOperationAt = nil

            // 音量ダイアルの案内だけは例外: 操作を待たず、接続直後に出す
            // （新しいバージョンへの更新直後に知らせたいため。設計: in-app-prompts-design.md 2.1）
            let delay = isSplashScreenActive ? 1.7 : 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                presentVolumeDialIntroIfNeeded()
                startPauseWatch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pauseWatchTask?.cancel()
                pauseWatchTask = nil
            } else if vm.connectionStatus == .connected, connectedAt != nil {
                startPauseWatch()
            }
        }
        .sheet(isPresented: $showingCompatibilityReportSheet) {
            CompatibilityReportView()
                .environment(vm)
                .environment(\.locale, appLocale)
                .environment(\.localizedBundle, lBundle)
        }
        .alert(Text("開発を応援しませんか？", bundle: lBundle), isPresented: $showingSupportRequest) {
            Button(LS("応援する", lBundle)) { showingSupportSheet = true }
            Button(LS("今はしない", lBundle), role: .cancel) { }
        } message: {
            Text("いつも AVR Controller をお使いいただきありがとうございます。すべての機能を無料で提供しています。気に入っていただけたら、開発を応援していただけるとうれしいです。応援してくださった方のご要望は優先的に検討します。", bundle: lBundle)
        }
        .sheet(isPresented: $showingSupportSheet) {
            NavigationStack {
                SupportView(isModal: true)
            }
            .environment(supportStore)
            .environment(\.locale, appLocale)
            .environment(\.localizedBundle, lBundle)
        }
        .alert(Text("新しい音量ダイアル", bundle: lBundle), isPresented: $showingVolumeDialIntroduction) {
            Button(LS("ダイアルを試す", lBundle)) {
                volumeControlStyle = "dial"
                hasShownVolumeDialIntroduction = true
            }
            Button(LS("スライダーを使い続ける", lBundle), role: .cancel) {
                volumeControlStyle = "slider"
                hasShownVolumeDialIntroduction = true
            }
        } message: {
            Text("アプリアイコンのようなダイアルを回して、音量を細かく調整できるようになりました。設定からいつでも切り替えられます。", bundle: lBundle)
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
                
                Text("AVR Controller")
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

    private func noticeOverlay(key: String) -> some View {
        VStack {
            Label {
                Text(LocalizedStringKey(key), bundle: lBundle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.9), in: Capsule())
            .shadow(radius: 4)
            .padding(.top, 50)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 動作報告の案内。既存の一時的なお知らせ（`noticeOverlay`）と同じ色調で、画面下部に出す。
    /// モーダルではないので、他の操作を妨げない。
    private var compatibilityBannerOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .padding(.top, 2)
                Text("この機種はまだ動作確認されていません。動いたかどうか教えてください", bundle: lBundle)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    Button {
                        compatBannerAutoHideTask?.cancel()
                        showingCompatibilityBanner = false
                        showingCompatibilityReportSheet = true
                    } label: {
                        Text("報告する", bundle: lBundle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        dismissCompatibilityBanner()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - In-app prompts

    /// シートやアラートなど、画面に何か出ているか(出ていれば見送る。設計: in-app-prompts-design.md 2.1)
    private var hasPresentedUI: Bool {
        showConnection || showingSupportRequest || showingSupportSheet
            || showingVolumeDialIntroduction || showingCompatibilityReportSheet
    }

    private func promptContext() -> PromptCoordinator.Context {
        PromptCoordinator.Context(
            brand: vm.capabilities.brand,
            model: vm.avr.deviceInfo.modelName,
            hasPresentedUI: hasPresentedUI
        )
    }

    /// 音量ダイアルの案内だけは、操作の区切りを待たず接続直後に出す(既存の挙動を維持)。
    private func presentVolumeDialIntroIfNeeded() {
        #if DEBUG
        if MainViewModel.isScreenshotDemo { return }
        #endif
        guard !hasShownVolumeDialIntroduction, !hasPresentedUI else { return }
        let context = promptContext()
        guard case .featureIntro(let intro) = PromptCoordinator.next(context: context) else { return }
        PromptCoordinator.markShown(.featureIntro(intro), context: context)
        switch intro {
        case .volumeDial: showingVolumeDialIntroduction = true
        }
    }

    /// 接続後、操作が 1 回以上あってから 5 秒間操作がない「区切り」を待って、お願い・案内を出す。
    /// 1 秒ごとにポーリングし、同じ操作に対して 2 回出さないよう `lastEvaluatedOperationAt` で覚えておく。
    private func startPauseWatch() {
        pauseWatchTask?.cancel()
        pauseWatchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard vm.connectionStatus == .connected else { return }
                guard let connectedAt, let lastOp = vm.lastUserOperationAt, lastOp > connectedAt else { continue }
                guard lastOp != lastEvaluatedOperationAt else { continue }
                guard Date().timeIntervalSince(lastOp) >= 5 else { continue }
                lastEvaluatedOperationAt = lastOp
                presentNextPromptAfterPause()
            }
        }
    }

    private func presentNextPromptAfterPause() {
        #if DEBUG
        if MainViewModel.isScreenshotDemo { return }
        #endif
        guard !hasPresentedUI else { return }
        let context = promptContext()
        guard let prompt = PromptCoordinator.next(context: context) else { return }
        present(prompt, context: context)
    }

    private func present(_ prompt: InAppPrompt, context: PromptCoordinator.Context) {
        switch prompt {
        case .featureIntro(let intro):
            PromptCoordinator.markShown(prompt, context: context)
            switch intro {
            case .volumeDial: showingVolumeDialIntroduction = true
            }
        case .review:
            requestReview()
            PromptCoordinator.markShown(prompt, context: context)
        case .support:
            PromptCoordinator.markShown(prompt, context: context)
            showingSupportRequest = true
        case .compatibility:
            PromptCoordinator.markShown(prompt, context: context)
            showingCompatibilityBanner = true
            scheduleCompatibilityBannerAutoHide()
        }
    }

    private func dismissCompatibilityBanner() {
        compatBannerAutoHideTask?.cancel()
        showingCompatibilityBanner = false
        PromptCoordinator.markDismissed(.compatibility, context: promptContext())
    }

    /// 20 秒で自動的に隠す。閉じた(✕)ときとは違い、機種ごとの 30 日クールダウンは掛けない
    /// (「出した」扱いのまま。設計: in-app-prompts-design.md 3.3)
    private func scheduleCompatibilityBannerAutoHide() {
        compatBannerAutoHideTask?.cancel()
        compatBannerAutoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            showingCompatibilityBanner = false
        }
    }

    private func autoConnect() {
        #if DEBUG
        if MainViewModel.isScreenshotDemo { return }   // 撮影中は実機の AVR に接続しない
        #endif
        let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
        let auto = UserDefaults.standard.bool(forKey: "autoConnect")
        if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
            // 保存済みアドレスで失敗したら MAC による再検出・スキャンまで行う connectAutomatic() を使う
            Task { await vm.connectAutomatic() }
        }
    }

    // MARK: - iPhone: Tab Bar

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(showConnection: $showConnection)
            }
            .tabItem { 
                Label { Text("ホーム", bundle: lBundle) } icon: { Image(systemName: "house.fill") }
            }
            .tag("home")

            NavigationStack { TunerView() }
            .tabItem { 
                Label { Text("チューナー", bundle: lBundle) } icon: { Image(systemName: "antenna.radiowaves.left.and.right") }
            }
            .tag("tuner")

            NavigationStack { InputView() }
            .tabItem { 
                Label { Text("入力ソース", bundle: lBundle) } icon: { Image(systemName: "rectangle.on.rectangle.angled") }
            }
            .tag("input")

            NavigationStack { RemoteView() }
            .tabItem { 
                Label { Text("リモコン", bundle: lBundle) } icon: { Image(systemName: "dpad") }
            }
            .tag("remote")

            NavigationStack { ZoneView() }
            .tabItem { 
                Label { Text("ゾーン", bundle: lBundle) } icon: { Image(systemName: "square.split.2x1.fill") }
            }
            .tag("zone")

            NavigationStack { SettingsView(showConnection: $showConnection) }
            .tabItem { 
                Label { Text("設定", bundle: lBundle) } icon: { Image(systemName: "gear") }
            }
            .tag("settings")
        }
    }

    // MARK: - iPad: Split View

    enum SidebarItem: String, CaseIterable, Hashable {
        case dashboard = "ダッシュボード"
        case tuner     = "チューナー"
        case zone      = "ゾーン"
        case remote    = "リモコン"
        case settings  = "設定"

        var systemImage: String {
            switch self {
            case .dashboard: "house.fill"
            case .tuner:     "radio.fill"
            case .zone:      "speaker.2.fill"
            case .remote:    "dpad"
            case .settings:  "gear"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = ContentView.initialSidebarItem

    /// iPad の初期選択（撮影時の `-uiDemoTab` に対応。iPad に無い「入力ソース」はダッシュボード）
    nonisolated private static var initialSidebarItem: SidebarItem {
        switch initialTab {
        case "tuner":    .tuner
        case "remote":   .remote
        case "zone":     .zone
        case "settings": .settings
        default:         .dashboard
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedItem) { item in
                Label {
                    Text(LocalizedStringKey(item.rawValue), bundle: lBundle)
                } icon: {
                    Image(systemName: item.systemImage)
                }
            }
            .navigationTitle("AVR Controller")
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
