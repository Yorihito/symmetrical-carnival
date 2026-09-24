import SwiftUI
import Network
import Observation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - ConnectionStatus

enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: String(localized: "未接続")
        case .connecting:   String(localized: "接続中...")
        case .connected:    String(localized: "接続済み")
        case .error:        String(localized: "エラー")
        }
    }

    var isConnected: Bool { self == .connected }
}

// MARK: - MainViewModel

/// UI と AVRHTTPClient を繋ぐ ViewModel。すべての AVR 操作はここ経由で行う。
@Observable
@MainActor
final class MainViewModel {
    
    /// ライフサイクル監視用のオブザーバーを安全に保持・破棄するためのコンテナ
    private class ObserverContainer {
        var observers: [any NSObjectProtocol] = []
        deinit {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
    private let observerContainer = ObserverContainer()

    // MARK: - Public state
    let avr = AVRState()
    let presetStore = PresetStore()
    let inputNames = InputNameStore()
    let discovery = MDNSDiscovery()

    var connectionStatus: ConnectionStatus = .disconnected
    var connectingDetail: String = ""
    var connectionLog: [String] = []  // 接続の詳細ログ
    private var currentConnectionID: UUID? // 世代管理用 ID
    var errorMessage: String?
    var lastConnectedHost: String = ""

    /// 接続中の機器でできること（画面の出し分けに使う）。未接続のあいだは Denon のまま
    private(set) var capabilities: ReceiverCapabilities = .denon

    /// この接続で実際に成功した操作（動作報告の画面の初期値に使う）
    private(set) var sessionSucceededFeatures: Set<CompatibilityFeature> = []

    // MARK: - Private
    private let client = AVRHTTPClient()
    private let telnet = TelnetClient()
    private let yamaha = YamahaClient()
    /// 今の接続が Yamaha（YXC）か
    private var usingYamaha = false
    private var updateTask: Task<Void, Never>?
    private var telnetListenTask: Task<Void, Never>?
    
    /// 操作直後にポーリングによる上書きを防ぐためのタイマー
    private var ignoreSyncUntil: [String: Date] = [:]

    /// 自動 IP 復旧（DHCP でアドレスが変わった AVR を再検出する処理）の多重実行防止・throttle 用
    private var isRehealing = false
    private var lastRehealAttempt: Date?
    /// 切断検知・アプリ復帰時の自動復旧（recoverConnection）の多重実行防止
    private var isRecovering = false

    /// 自動再接続でアドレスが変わったことなどを一時的に知らせる通知（ローカライズキー）。数秒で消える。
    var transientNoticeKey: String?
    private var noticeToken = UUID()

    init() {
        // 前回フェッチしたプリセットを復元する
        if let data = UserDefaults.standard.data(forKey: "savedTunerPresets"),
           let saved = try? JSONDecoder().decode([TunerPreset].self, from: data) {
            tunerAllPresets = saved
        }
        
        setupLifecycleObservers()
    }
    
    deinit {
        print("[DenonLog] MainViewModel.deinit")
    }

    // MARK: - Connection

    func connectAutomatic() async {
        guard !connectionStatus.isConnected else { return }

        let savedHost = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
        if !savedHost.isEmpty {
            await connect(host: savedHost)
            // 起動直後は復帰時の自動復旧（recoverConnection）も同じアドレスへ接続しにいく。
            // こちらの接続が後から始まった接続に置き換えられた場合も含め、もう接続済みか接続中なら検索はしない
            if connectionStatus.isConnected || connectionStatus == .connecting { return }
        }

        connectionStatus = .connecting
        connectingDetail = String(localized: "デバイスを検索中...")

        // 保存済みの MAC と一致する機体を優先する。なければ AVR が 1 台だけ見つかったときに限って接続する
        // （複数台ある環境で別の AVR に勝手につながないため）
        let (found, _) = await MDNSScanner.scan()
        let savedMac = DeviceInfo.normalizedMac(UserDefaults.standard.string(forKey: "defaultMacAddress") ?? "")
        let macMatch = savedMac.isEmpty ? nil : found.first(where: { $0.macAddress == savedMac })
        // 検索している間に別の経路で接続できていたら、その状態を上書きしない
        if connectionStatus.isConnected { return }
        guard let device = macMatch ?? (found.count == 1 ? found.first : nil) else {
            DiagnosticsLog.shared.record("autoConnect: fallback scan found \(found.count) AVR(s), none selected")
            connectionStatus = .disconnected
            connectingDetail = ""
            return
        }

        connectingDetail = ""
        await connect(host: device.host, port: device.port, brand: device.brand)
        if connectionStatus.isConnected {
            UserDefaults.standard.set(device.host, forKey: "defaultHost")
            UserDefaults.standard.set(device.port, forKey: "defaultPort")
            recordFeatureSuccess(.discovery)
        }
    }

    /// DHCP でリース更新された AVR を、保存済みの MAC アドレスを手掛かりに LAN 上で再検出する。
    /// 見つかった場合は `defaultHost` / `defaultPort` を新しい値に更新して返す。
    /// 同じアドレスで見つかった場合も返す（復帰直後に Wi-Fi が戻る前の失敗だった可能性があるため）。
    /// 30秒に1回・多重実行なしに制限し、AVR が本当にオフラインのときに無限ループしないようにする。
    private func attemptAutoReheal(failedHost: String) async -> (host: String, port: Int, brand: ReceiverBrand)? {
        guard !isRehealing else { return nil }
        let savedMac = DeviceInfo.normalizedMac(UserDefaults.standard.string(forKey: "defaultMacAddress") ?? "")
        guard !savedMac.isEmpty else {
            DiagnosticsLog.shared.record("reheal: skipped (no saved MAC)")
            return nil
        }
        if let last = lastRehealAttempt, Date().timeIntervalSince(last) < 30 {
            DiagnosticsLog.shared.record("reheal: skipped (throttled)")
            return nil
        }

        isRehealing = true
        lastRehealAttempt = Date()
        defer { isRehealing = false }

        connectionLog.append("Auto-heal: searching for AVR with MAC \(savedMac)...")
        let (found, _) = await MDNSScanner.scan()
        let withMac = found.filter { !$0.macAddress.isEmpty }.count
        DiagnosticsLog.shared.record("reheal: scan found \(found.count) AVR(s), \(withMac) with MAC")
        guard let match = found.first(where: { $0.macAddress == savedMac }) else {
            connectionLog.append("Auto-heal: no matching AVR found on the network")
            DiagnosticsLog.shared.record("reheal: no matching AVR")
            return nil
        }

        let moved = match.host != failedHost
        connectionLog.append("Auto-heal: found AVR at \(match.host) (was \(failedHost))")
        DiagnosticsLog.shared.record(moved ? "reheal: found at a new address" : "reheal: found at the same address")
        UserDefaults.standard.set(match.host, forKey: "defaultHost")
        UserDefaults.standard.set(match.port, forKey: "defaultPort")
        return (match.host, match.port, match.brand)
    }

    /// reheal で見つかったアドレスへ 1 回だけ再接続する（再接続時は reheal しないのでループしない）。
    /// アドレスが実際に変わっていたら通知を出す（参照: upgraded-guacamole 9876d15）。
    /// - Returns: 再接続に成功したら true
    @discardableResult
    private func rehealAndReconnect(failedHost: String) async -> Bool {
        guard let match = await attemptAutoReheal(failedHost: failedHost) else { return false }
        let healLog = connectionLog
        await connect(host: match.host, port: match.port, brand: match.brand, allowReheal: false)
        connectionLog = healLog + connectionLog   // 再接続でリセットされる reheal のログを残す
        guard connectionStatus.isConnected else { return false }
        if match.host != failedHost {
            showNotice("AVR のアドレスが変わったため自動で再接続しました。")
            recordFeatureSuccess(.reconnect)
        }
        return true
    }

    /// - Parameter brand: 検出で分かっていればメーカー。nil なら、前回このアドレスにつないだときのメーカーを使い、
    ///   それも分からなければ Denon として試してから Yamaha かを確かめる（IP アドレスを手入力した場合など）
    func connect(host: String, port: Int? = nil, brand: ReceiverBrand? = nil, allowReheal: Bool = true) async {
        let connectionID = UUID()
        currentConnectionID = connectionID

        print("[DenonLog] [\(connectionID.uuidString.prefix(4))] connect(host: \(host), port: \(port ?? 0)) called")
        connectionLog = ["--- Connection Started ---", "Target: \(host):\(port ?? 0)"]

        // 既存の接続があれば確実に終了するまで待つ
        print("[DenonLog] Step 1: Disconnecting previous sessions...")
        connectionLog.append("Step 1: Disconnecting previous sessions...")
        await disconnect()
        print("[DenonLog] Disconnect complete")

        let savedPort = UserDefaults.standard.integer(forKey: "defaultPort")
        let targetPort = port ?? (savedPort > 0 ? savedPort : 8080)

        connectionStatus = .connecting
        connectingDetail = ""
        errorMessage = nil
        sessionSucceededFeatures = []
        DiagnosticsLog.shared.record("connect: start")

        let knownBrand = brand ?? Self.savedBrand(forHost: host)
        do {
            if knownBrand == .yamaha {
                try await connectYamaha(host: host, connectionID: connectionID)
            } else {
                do {
                    try await connectDenon(host: host, port: targetPort, connectionID: connectionID)
                } catch {
                    // Denon として応答しなかった。メーカーが分からない場合だけ Yamaha かを確かめる
                    guard knownBrand == nil, await YamahaClient.identify(host: host) != nil else { throw error }
                    connectionLog.append("Not a Denon/Marantz receiver; trying Yamaha...")
                    try await connectYamaha(host: host, connectionID: connectionID)
                }
            }
            connectionLog.append("Success: Connection sequence complete.")
            print("[DenonLog] Success: Fully connected to \(host)")

        } catch {
            // 待っている間に新しい接続が始まっていたら、古い接続の失敗で画面の状態を上書きしない
            guard currentConnectionID == connectionID else { return }
            print("[DenonLog] Fatal Error: \(error.localizedDescription)")
            connectionLog.append("Fatal Error: \(error.localizedDescription)")
            connectingDetail = ""
            errorMessage = error.localizedDescription
            connectionStatus = .error(error.localizedDescription)
            avr.isConnected = false
            // record() redacts IPs/MACs as a backstop, but error.localizedDescription
            // can otherwise echo the host we just tried to reach.
            DiagnosticsLog.shared.record("connect: failed - \(error.localizedDescription)")

            // DHCP で AVR の IP が変わった可能性があるので、同じ MAC アドレスの機体を
            // 再検索し、見つかれば新しい IP で 1 回だけ自動的に再接続する。
            if allowReheal {
                await rehealAndReconnect(failedHost: host)
            }
        }
    }

    /// Denon / Marantz（/goform と Telnet）で接続する
    private func connectDenon(host: String, port targetPort: Int, connectionID: UUID) async throws {
        connectionLog.append("Step 2: Connecting via HTTP to port \(targetPort)...")
        let (info, updates) = try await client.connect(host: host, port: targetPort) { @Sendable _ in
            // 進捗更新を一旦無効化して初期化エラーを確実に消す
        }
        connectionLog.append("Step 3: Probing additional zones...")
        var finalInfo = info
        finalInfo.hasZone3 = await client.probeZone3()

        var caps = ReceiverCapabilities.denon
        caps.brand = finalInfo.brand
        caps.hasZone2 = finalInfo.hasZone2
        caps.hasZone3 = finalInfo.hasZone3
        usingYamaha = false
        loadTunerPresets(for: caps.brand)
        connectionLog.append("Step 4: Finalizing app state...")
        didConnect(host: host, info: finalInfo, capabilities: caps)

        // HTTP ポーリング
        connectionLog.append("Step 5: Starting status update loop...")
        updateTask = Task { [weak self] in
            guard let self else { return }
            print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Update loop started")
            for await snapshot in updates {
                // このタスクがまだ有効（最新）かチェック
                if self.currentConnectionID != connectionID {
                    print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Update loop aborted (ID mismatch)")
                    break
                }
                print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Received snapshot: Vol=\(snapshot.volumeDB)")

                // 同期ガードをチェックして、操作直後のプロパティは上書きしない
                if !self.shouldIgnoreSync(for: "power")  { self.avr.isPoweredOn = snapshot.isPoweredOn }
                if !self.shouldIgnoreSync(for: "volume") { self.avr.volumeDB = snapshot.volumeDB }
                if !self.shouldIgnoreSync(for: "mute")   { self.avr.isMuted = snapshot.isMuted }

                if !self.shouldIgnoreSync(for: "input") {
                    let code: String = snapshot.inputCode
                    if InputSource(rawValue: code) != nil {
                        self.avr.inputID = code
                    }
                }

                // チューナー情報は同期ガード対象外（反映に時間がかかるため）
                if snapshot.tunerDataFetched {
                    if let band = TunerBand(rawValue: snapshot.tunerBand) {
                        self.avr.tunerBand = band
                    }
                    self.avr.tunerFrequency = snapshot.tunerFrequency
                    self.avr.tunerPreset = snapshot.tunerPreset
                    self.avr.tunerStationName = snapshot.tunerStationName
                }

                // Zone2, 3 も同様に（必要に応じてガードを広げることも可能）
                self.avr.zone2Power = snapshot.zone2Power
                self.avr.zone2VolumeDB = snapshot.zone2VolumeDB
                self.avr.zone2Mute = snapshot.zone2Muted
                if InputSource(rawCode: snapshot.zone2InputCode) != nil {
                    self.avr.zone2InputID = snapshot.zone2InputCode
                }
            }
            print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Update loop finished (Stream ended)")
            self.connectionLog.append("!!! Update loop ended (ID: \(connectionID.uuidString.prefix(4)))")
            self.streamEnded(connectionID: connectionID)
        }

        // Telnet 接続
        connectionLog.append("Step 6: Connecting to Telnet (port 23)...")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await telnet.connect(host: host, port: 23)
                self.connectionLog.append("  -> Telnet connected successfully")
                startTelnetListening()
            } catch {
                self.connectionLog.append("  -> Telnet failed (optional): \(error.localizedDescription)")
            }
        }
    }

    /// Yamaha（YXC）で接続する
    private func connectYamaha(host: String, connectionID: UUID) async throws {
        connectionLog.append("Step 2: Connecting to Yamaha Extended Control (port \(YamahaClient.port))...")
        let (info, caps, _, updates) = try await yamaha.connect(host: host)
        // 待っている間に新しい接続が始まっていたら、この接続の結果は使わない
        guard currentConnectionID == connectionID else { throw CancellationError() }
        usingYamaha = true
        loadTunerPresets(for: .yamaha)
        connectionLog.append("Step 3: Finalizing app state...")
        didConnect(host: host, info: info, capabilities: caps)

        connectionLog.append("Step 4: Starting status update loop...")
        updateTask = Task { [weak self] in
            guard let self else { return }
            for await snap in updates {
                if self.currentConnectionID != connectionID { break }
                if !self.shouldIgnoreSync(for: "power")  { self.avr.isPoweredOn = snap.isPoweredOn }
                if !self.shouldIgnoreSync(for: "volume") { self.avr.volumeDB = snap.volumeDB }
                if !self.shouldIgnoreSync(for: "mute")   { self.avr.isMuted = snap.isMuted }
                if !self.shouldIgnoreSync(for: "input"), !snap.input.isEmpty { self.avr.inputID = snap.input }
                if !self.shouldIgnoreSync(for: "surround") {
                    let mode = snap.pureDirect ? YamahaCatalog.pureDirectID : snap.soundProgram
                    if !mode.isEmpty { self.avr.soundModeID = mode }
                }
                if snap.tunerFetched {
                    self.avr.tunerBand = snap.tunerBand
                    if !snap.tunerFrequency.isEmpty { self.avr.tunerFrequency = snap.tunerFrequency }
                    self.avr.tunerPreset = snap.tunerPreset
                    self.avr.tunerStationName = ""
                }
                if snap.hasZone2 {
                    self.avr.zone2Power = snap.zone2Power
                    self.avr.zone2VolumeDB = snap.zone2VolumeDB
                    self.avr.zone2Mute = snap.zone2Muted
                    if !snap.zone2Input.isEmpty { self.avr.zone2InputID = snap.zone2Input }
                }
            }
            self.connectionLog.append("!!! Update loop ended (ID: \(connectionID.uuidString.prefix(4)))")
            self.streamEnded(connectionID: connectionID)
        }
    }

    /// 接続できたときの共通の後処理
    private func didConnect(host: String, info: DeviceInfo, capabilities caps: ReceiverCapabilities) {
        capabilities = caps
        connectingDetail = ""
        connectionStatus = .connected
        avr.isConnected = true
        avr.deviceInfo  = info
        lastConnectedHost = host
        Self.saveBrand(caps.brand, forHost: host)
        ReviewRequestManager.recordSuccess()
        DiagnosticsLog.shared.record("connect: success (\(caps.brand.rawValue) \(info.modelName))")

        // MAC アドレスを保存しておく（次回起動時に IP が変わっていても同一機体として再検出できるように）
        if !info.macAddress.isEmpty {
            UserDefaults.standard.set(info.macAddress, forKey: "defaultMacAddress")
        } else {
            DiagnosticsLog.shared.record("connect: AVR reported no MAC address; auto-reheal unavailable")
        }
    }

    /// 状態の取得が止まったとき（ポーリングが連続で失敗した）の共通処理
    private func streamEnded(connectionID: UUID) {
        guard currentConnectionID == connectionID else { return }
        handleDisconnect()
        // キャンセルではなくストリームが閉じた = ポーリングが連続で失敗した。
        // IP が変わった可能性があるので自動復旧に回す（ユーザー操作による切断では走らない）。
        // updateTask は再接続時にキャンセルされるため、復旧は別タスクで行う。
        if !Task.isCancelled {
            DiagnosticsLog.shared.record("poll: AVR unreachable, recovering")
            Task { [weak self] in await self?.recoverConnection(.poll) }
        }
    }

    // MARK: - Brand memory

    /// アドレスごとに、前回つながったメーカーを覚えておく（次回は最初からそのメーカーの方式で接続する）
    private static let brandByHostKey = "receiverBrandByHost"

    private static func savedBrand(forHost host: String) -> ReceiverBrand? {
        let map = UserDefaults.standard.dictionary(forKey: brandByHostKey) as? [String: String] ?? [:]
        return map[host].flatMap(ReceiverBrand.init(rawValue:))
    }

    private static func saveBrand(_ brand: ReceiverBrand, forHost host: String) {
        var map = UserDefaults.standard.dictionary(forKey: brandByHostKey) as? [String: String] ?? [:]
        map[host] = brand.rawValue
        UserDefaults.standard.set(map, forKey: brandByHostKey)
    }

    func disconnect() async {
        updateTask?.cancel()
        updateTask = nil
        telnetListenTask?.cancel()
        telnetListenTask = nil
        
        // 切断処理がハングして次の接続をブロックしないよう、タイムアウト付きで実行
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.client.disconnect() }
            group.addTask { await self.telnet.disconnect() }
            group.addTask { await self.yamaha.disconnect() }
            
            // 最大1秒待って次へ進む
            let timeoutTask = Task { try? await Task.sleep(for: .seconds(1)) }
            await withTaskCancellationHandler {
                _ = await group.next()
            } onCancel: {
                timeoutTask.cancel()
            }
        }
        
        handleDisconnect()
    }

    private func handleDisconnect() {
        print("[DenonLog] handleDisconnect() called")
        if connectionStatus.isConnected {
            DiagnosticsLog.shared.record("disconnect")
        }
        connectionStatus = .disconnected
        avr.isConnected = false
        errorMessage = nil
        connectingDetail = ""
    }

    // MARK: - Telnet Listener

    private func startTelnetListening() {
        telnetListenTask?.cancel()
        telnetListenTask = Task { [weak self] in
            guard let self else { return }
            for await line in telnet.updates {
                parseTelnetLine(line)
            }
        }
    }

    /// Denon Telnet プロトコルのレスポンス行を解析して状態を更新する。
    private func parseTelnetLine(_ line: String) {
        // MS... — サラウンドモード変更通知（AVR 側での変更も追跡できる）
        if line.hasPrefix("MS") {
            let code = String(line.dropFirst(2))
            if let mode = SurroundMode(rawCode: code) {
                avr.surroundMode = mode
            }
            return
        }

        // TPAN01 — プリセット番号
        if line.hasPrefix("TPAN"), line.count >= 6 {
            let digits = String(line.dropFirst(4))
            if let n = Int(digits), n > 0 { avr.tunerPreset = n }
            return
        }
        // TFAN08750 — FM 87.50 MHz (5桁: 周波数 × 100 kHz)
        // バンドは TMANFM / TMANAM レスポンスで確定するため、ここでは周波数のみ更新する。
        // AM切替直後の遅延 TFAN でバンドが FM に戻るのを防ぐ。
        if line.hasPrefix("TFAN"), line.count >= 9 {
            let digits = String(line.dropFirst(4))
            if let val = Double(digits), val > 0 {
                avr.tunerFrequency = formatMHz(val / 100.0)
            }
            return
        }
        // TMANFM / TMANAM — バンド切替レスポンス
        if line == "TMANFM" { avr.tunerBand = .fm; return }
        if line == "TMANAM" { avr.tunerBand = .am; return }
        // TMAN00558 — AM 558 kHz
        if line.hasPrefix("TMAN"), line.count >= 9 {
            let digits = String(line.dropFirst(4))
            if let val = Int(digits), val > 0 {
                avr.tunerBand = .am
                avr.tunerFrequency = String(val)
            }
            return
        }
    }

    private func formatMHz(_ mhz: Double) -> String {
        // 87.5 → "87.5" / 76.1 → "76.1" (小数第1位まで表示)
        String(format: "%.1f", mhz)
    }

    // MARK: - Power

    func setPower(_ on: Bool) {
        markOperation(for: "power")
        avr.isPoweredOn = on
        dispatch(denon: on ? "PWON" : "PWSTANDBY", feature: .power) { try await $0.setPower(zone: "main", on: on) }
    }
    func togglePower()        { setPower(!avr.isPoweredOn) }

    // MARK: - Volume

    func volumeUp() {
        markOperation(for: "volume")
        avr.volumeDB = min(capabilities.volumeRangeDB.upperBound, avr.volumeDB + 0.5)
        dispatch(denon: "MVUP", feature: .volume) { try await $0.stepVolume(zone: "main", up: true) }
    }
    func volumeDown() {
        markOperation(for: "volume")
        avr.volumeDB = max(capabilities.volumeRangeDB.lowerBound, avr.volumeDB - 0.5)
        dispatch(denon: "MVDOWN", feature: .volume) { try await $0.stepVolume(zone: "main", up: false) }
    }
    func setVolume(_ db: Double) {
        markOperation(for: "volume")
        avr.volumeDB = db
        dispatch(denon: AVRState.volumeCommand(forDB: db), feature: .volume) { try await $0.setVolume(zone: "main", db: db) }
    }
    func setMute(_ on: Bool) {
        markOperation(for: "mute")
        avr.isMuted = on
        dispatch(denon: on ? "MUON" : "MUOFF", feature: .mute) { try await $0.setMute(zone: "main", on: on) }
    }
    func toggleMute()           { setMute(!avr.isMuted) }

    // MARK: - Input

    /// 表示中の機器の入力一覧（非表示にしたものを除く）
    var visibleInputs: [ReceiverInput] { inputNames.visible(capabilities.inputs) }

    /// 選択中の入力の表示用情報
    var currentInput: ReceiverInput { capabilities.input(for: avr.inputID) }

    var isTunerInputSelected: Bool { capabilities.isTunerInput(avr.inputID) }

    func setInput(_ input: InputSource) { setInput(id: input.rawValue) }
    func setInput(_ input: ReceiverInput) { setInput(id: input.id) }

    func setInput(id: String) {
        markOperation(for: "input")
        avr.inputID = id   // 楽観的更新（UIへ即時反映）
        dispatch(denon: "SI\(id)", feature: .input) { try await $0.setInput(zone: "main", id: id) }
    }

    /// チューナーに切り替える（チューナー画面の「TUNER に切り替え」）
    func selectTunerInput() {
        guard let id = capabilities.tunerInputID else { return }
        setInput(id: id)
    }

    // MARK: - Surround / Sound mode（Denon は HTTP では取得不可 → ローカル追跡 + Telnet 通知で補正）

    var currentSoundMode: SoundModeOption { capabilities.soundMode(for: avr.soundModeID) }

    func setSurroundMode(_ mode: SurroundMode) { setSoundMode(id: mode.rawValue) }
    func setSoundMode(_ mode: SoundModeOption) { setSoundMode(id: mode.id) }

    func setSoundMode(id: String) {
        markOperation(for: "surround")
        // AVR-X3800H はスペース入りの MS コマンドを受け付けないためスペースを除去する（SurroundMode.command と同じ）
        dispatch(denon: "MS" + id.replacingOccurrences(of: " ", with: ""), feature: .soundMode) {
            try await $0.setSoundMode(id: id)
        }
        avr.soundModeID = id
    }

    /// ゾーンの音量の表示。Denon は本体と同じ目盛り（dB + 80）、ほかのメーカーは dB
    func zoneVolumeLabel(_ db: Double) -> String {
        capabilities.showsNativeVolumeScale ? String(format: "%.1f", db + 80.0) : String(format: "%.1f dB", db)
    }

    // MARK: - Zone 2

    func setZone2Power(_ on: Bool) {
        dispatch(denon: on ? "Z2ON" : "Z2OFF", feature: .zone2) { try await $0.setPower(zone: "zone2", on: on) }
    }
    func zone2VolumeUp() {
        dispatch(denon: "Z2UP", feature: .zone2) { try await $0.stepVolume(zone: "zone2", up: true) }
    }
    func zone2VolumeDown() {
        dispatch(denon: "Z2DOWN", feature: .zone2) { try await $0.stepVolume(zone: "zone2", up: false) }
    }
    func setZone2Mute(_ on: Bool) {
        dispatch(denon: on ? "Z2MUON" : "Z2MUOFF", feature: .zone2) { try await $0.setMute(zone: "zone2", on: on) }
    }

    // MARK: - Zone 3

    func setZone3Power(_ on: Bool) {
        dispatch(denon: on ? "Z3ON" : "Z3OFF", feature: .zone3) { try await $0.setPower(zone: "zone3", on: on) }
    }
    func zone3VolumeUp() {
        dispatch(denon: "Z3UP", feature: .zone3) { try await $0.stepVolume(zone: "zone3", up: true) }
    }
    func zone3VolumeDown() {
        dispatch(denon: "Z3DOWN", feature: .zone3) { try await $0.stepVolume(zone: "zone3", up: false) }
    }

    // MARK: - OSD Navigation

    func cursorUp()     { remote("MNCUP", .up) }
    func cursorDown()   { remote("MNCDN", .down) }
    func cursorLeft()   { remote("MNCLT", .left) }
    func cursorRight()  { remote("MNCRT", .right) }
    func cursorEnter()  { remote("MNENT", .enter) }
    func navBack()      { remote("MNRTN", .back) }
    func infoButton()   { remote("MNINF", .info) }
    func optionButton() { remote("MNOPT", .option) }
    func setupMenu()    { remote("MNMEN ON", .setup) }

    private func remote(_ denon: String, _ key: YamahaClient.RemoteKey) {
        dispatch(denon: denon, feature: .remote) { try await $0.remote(key) }
    }

    // MARK: - Tuner

    func setTunerBand(_ band: TunerBand) {
        avr.tunerBand = band   // 楽観的更新（HTTP ポーリング応答を待たずに即時反映）
        dispatch(denon: band.selectCommand, feature: .tuner) { try await $0.setTunerBand(band) }
    }

    /// プリセット ↑。
    /// 取得済みのリストがあればそのリスト内を循環（空スロット・スキップを自動回避）。
    /// 未取得なら単純に +1 し、最大数を超えたら 1 に戻る。
    func tunerPresetUp() {
        let presets = tunerPresets
        if presets.isEmpty {
            let next = (avr.tunerPreset % maxTunerSlots) + 1
            selectTunerPreset(next)
        } else {
            let cur = avr.tunerPreset
            if let idx = presets.firstIndex(where: { $0.id == cur }) {
                selectTunerPreset(presets[(idx + 1) % presets.count].id)
            } else if let first = presets.first {
                selectTunerPreset(first.id)
            }
        }
    }

    /// プリセット ↓（同上）。
    func tunerPresetDown() {
        let presets = tunerPresets
        if presets.isEmpty {
            let prev = avr.tunerPreset <= 1 ? maxTunerSlots : avr.tunerPreset - 1
            selectTunerPreset(prev)
        } else {
            let cur = avr.tunerPreset
            if let idx = presets.firstIndex(where: { $0.id == cur }) {
                selectTunerPreset(presets[(idx - 1 + presets.count) % presets.count].id)
            } else if let last = presets.last {
                selectTunerPreset(last.id)
            }
        }
    }

    func tunerFreqUp() {
        let band = avr.tunerBand
        dispatch(denon: band.freqUpCommand, feature: .tuner) { try await $0.stepTunerFrequency(band: band, up: true) }
    }
    func tunerFreqDown() {
        let band = avr.tunerBand
        dispatch(denon: band.freqDownCommand, feature: .tuner) { try await $0.stepTunerFrequency(band: band, up: false) }
    }

    /// プリセット選択。
    /// Denon は HTTP では読み返せないのでローカル追跡。Telnet が接続されていれば
    /// 周波数と局名は自動的に更新される。
    func selectTunerPreset(_ n: Int) {
        dispatch(denon: String(format: "TPAN%02d", n), feature: .tuner) { try await $0.recallPreset(id: n) }
        avr.tunerPreset = n
        avr.tunerStationName = ""   // 更新を待つ
        avr.tunerFrequency = ""     // 更新を待つ
    }

    // MARK: - Tuner Preset Scan

    /// スキャン生データ（フィルタ前）
    var tunerAllPresets: [TunerPreset] = []

    /// 最大プリセット数（Denon は 56、Yamaha は機器が返す数）
    var maxTunerSlots: Int { capabilities.tunerPresetCount }

    /// 除外する周波数（カンマ区切り MHz、例: "90.0" or "90.0, 85.0"）
    /// デフォルトは "90.0"（空きスロットの代表値）
    var tunerSkipFrequencies: String = UserDefaults.standard.string(forKey: "tunerSkipFrequencies") ?? "90.0"

    /// 除外周波数を適用し、重複を排除したプリセット一覧。
    /// 除外周波数は、空きスロットも周波数を返す Denon のためのもの。Yamaha は空きを返さないので適用しない
    var tunerPresets: [TunerPreset] {
        let skipSet = capabilities.tunerPresetsNeedScan ? skipFreqSet(from: tunerSkipFrequencies) : []
        var seen = Set<String>()
        return tunerAllPresets.filter { p in
            // 1. 除外周波数チェック
            if let f = Double(p.frequency.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if skipSet.contains(f) { return false }
            }

            // 2. 重複チェック（数値として正規化した周波数 + バンド）
            let freqVal = Double(p.frequency.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            let key = "\(p.band.rawValue)_\(freqVal)"
            if seen.contains(key) { return false }

            seen.insert(key)
            return true
        }
    }

    /// 除外周波数を保存する
    func setTunerSkipFrequencies(_ value: String) {
        tunerSkipFrequencies = value
        UserDefaults.standard.set(value, forKey: "tunerSkipFrequencies")
    }

    private func skipFreqSet(from raw: String) -> Set<Double> {
        Set(raw.components(separatedBy: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    var isScanningTuner = false
    var tunerScanProgress: Int = 0
    private var tunerScanTask: Task<Void, Never>?

    /// チューナープリセット一覧を取得する。
    /// Yamaha は一括で取れる。Denon はまず formTuner_TunerPresetXml.xml を一括取得して試み（高速・移動なし）、
    /// 取得できない場合は Telnet ベーススキャンにフォールバックする。
    func startTunerScan() {
        guard !isScanningTuner else { return }
        isScanningTuner = true
        tunerScanProgress = 0
        tunerAllPresets = []

        tunerScanTask = Task { [weak self] in
            guard let self else { return }

            if usingYamaha {
                let presets = await yamaha.fetchTunerPresets() ?? []
                if Task.isCancelled { return }
                tunerScanProgress = maxTunerSlots
                tunerAllPresets = presets
                if !presets.isEmpty { recordFeatureSuccess(.tuner) }
                saveTunerPresets()
                isScanningTuner = false
                return
            }

            // ── Phase 1: XML 一括取得 ─────────────────────────────────────
            if let xmlPresets = await client.fetchTunerPresetsFromXml(), !xmlPresets.isEmpty, !Task.isCancelled {
                tunerScanProgress = maxTunerSlots
                tunerAllPresets = xmlPresets
                saveTunerPresets()
                isScanningTuner = false
                return
            }

            // ── Phase 2: Telnet ベーススキャン（フォールバック）───────────
            var found: [TunerPreset] = []
            var seen = Set<String>()

            for i in 1...maxTunerSlots {
                if Task.isCancelled { break }
                tunerScanProgress = i

                // 既にそのプリセットを選択している場合、アンプが応答を返さないことがあるため
                // 別の番号を一度選んで状態を強制的に動かす
                if avr.tunerPreset == i {
                    let dummy = (i % maxTunerSlots) + 1
                    selectTunerPreset(dummy)
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { break }
                }

                selectTunerPreset(i)
                
                // 周波数が更新されるのを待つ（最大1.2秒）
                for j in 0..<12 {
                    if !avr.tunerFrequency.isEmpty { break }
                    
                    // 0.4秒待っても来ない場合は、明示的に周波数とプリセットを問い合わせる
                    if j == 4 {
                        send("TF?")
                        send("TP?")
                    }
                    
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { break }
                }
                
                // 確定のため少し待つ
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { break }

                let newFreq = avr.tunerFrequency
                let newBand = avr.tunerBand
                let name    = avr.tunerStationName

                guard !newFreq.isEmpty else { continue }

                let key = "\(newBand.rawValue)_\(newFreq)"
                if !seen.contains(key) {
                    found.append(TunerPreset(
                        id: i, band: newBand, frequency: newFreq, stationName: name
                    ))
                    seen.insert(key)
                }
            }

            tunerAllPresets = found
            saveTunerPresets()
            isScanningTuner = false
        }
    }

    func cancelTunerScan() {
        tunerScanTask?.cancel()
        tunerScanTask = nil
        isScanningTuner = false
    }

    /// 取得したプリセットはメーカーごとに保存する（Denon は 1.1.x までと同じキー）
    private static func tunerPresetsKey(for brand: ReceiverBrand) -> String {
        brand == .yamaha ? "savedTunerPresets.yamaha" : "savedTunerPresets"
    }

    private func saveTunerPresets() {
        if let data = try? JSONEncoder().encode(tunerAllPresets) {
            UserDefaults.standard.set(data, forKey: Self.tunerPresetsKey(for: capabilities.brand))
        }
    }

    /// 接続したメーカーの保存済みプリセットを読み込む
    private func loadTunerPresets(for brand: ReceiverBrand) {
        if let data = UserDefaults.standard.data(forKey: Self.tunerPresetsKey(for: brand)),
           let saved = try? JSONDecoder().decode([TunerPreset].self, from: data) {
            tunerAllPresets = saved
        } else {
            tunerAllPresets = []
        }
    }

    // MARK: - Tuner Diagnostics

    var tunerDiagLog: String = ""
    var isFetchingTunerDiag = false

    func fetchTunerDiagnostics() {
        guard !isFetchingTunerDiag else { return }
        isFetchingTunerDiag = true
        tunerDiagLog = ""
        Task { [weak self] in
            guard let self else { return }
            let log = usingYamaha ? await yamaha.diagnostics() : await client.fetchTunerDiagnostics()
            await MainActor.run { [weak self] in
                self?.tunerDiagLog = log
                self?.isFetchingTunerDiag = false
            }
        }
    }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        guard preset.isUsable(with: capabilities.brand) else { return }
        setInput(id: preset.input)
        setVolume(preset.volumeDB)
        setSoundMode(id: preset.surroundMode)
    }

    func saveCurrentAsPreset(name: String, emoji: String) {
        let preset = Preset(
            name: name, emoji: emoji,
            input: avr.inputID,
            volumeDB: avr.volumeDB,
            surroundMode: avr.soundModeID,
            brand: capabilities.brand
        )
        presetStore.save(preset)
    }

    /// 接続中の機器で使えるプリセット
    var usablePresets: [Preset] {
        presetStore.presets.filter { $0.isUsable(with: capabilities.brand) }
    }

    // MARK: - Private helper

    /// 操作を接続中の機器に送る。Denon / Marantz は Telnet・HTTP のコマンド文字列、Yamaha は YXC
    private func dispatch(denon command: String, feature: CompatibilityFeature,
                          yamaha action: @escaping @Sendable (YamahaClient) async throws -> Void) {
        guard usingYamaha else {
            send(command, feature: feature)
            return
        }
        let client = yamaha
        Task { [weak self] in
            do {
                try await action(client)
                self?.recordFeatureSuccess(feature)
            } catch let error as YamahaError {
                // 機器が操作を断った（今の状態ではできない操作など）。通信は生きているので切断扱いにしない
                DiagnosticsLog.shared.record("yamaha: command rejected (\(feature.rawValue))")
                self?.showCommandError(error.localizedDescription)
            } catch {
                guard let self else { return }
                handleDisconnect()
                showCommandError(String(localized: "通信に失敗しました。ネットワークを確認してください。"))
                await recoverConnection(.command)
            }
        }
    }

    /// 動作報告の画面の初期値に使うため、この接続で成功した操作を記録する
    func recordFeatureSuccess(_ feature: CompatibilityFeature) {
        sessionSucceededFeatures.insert(feature)
    }

    private func send(_ command: String, feature: CompatibilityFeature? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await telnet.send(command)
                if let feature { self.recordFeatureSuccess(feature) }
            } catch {
                // Telnet 未接続 or 失敗 → HTTP フォールバック
                do {
                    try await client.send(command)
                    if let feature { self.recordFeatureSuccess(feature) }
                } catch {
                    print("[DenonLog] All communication failed for command: \(command)")
                    handleDisconnect()
                    showCommandError(String(localized: "通信に失敗しました。ネットワークを確認してください。"))
                    // コマンドの失敗も自動復旧に回す（参照: upgraded-guacamole 2ca9191）
                    await recoverConnection(.command)
                }
            }
        }
    }

    private func showCommandError(_ msg: String) {
        errorMessage = msg
        // 5秒後にエラーを消す
        Task {
            try? await Task.sleep(for: .seconds(5))
            if errorMessage == msg { errorMessage = nil }
        }
    }

    // MARK: - Sync Guard Helper

    private func shouldIgnoreSync(for key: String) -> Bool {
        guard let expiry = ignoreSyncUntil[key] else { return false }
        if Date() < expiry {
            return true
        }
        return false
    }

    private func markOperation(for key: String) {
        // 操作後 3秒間は同期を無視する
        ignoreSyncUntil[key] = Date().addingTimeInterval(3.0)
    }

    // MARK: - Lifecycle

    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        #if os(iOS)
        let foregroundObserver = nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppResume()
        }
        observerContainer.observers.append(foregroundObserver)
        #elseif os(macOS)
        let activeObserver = nc.addObserver(forName: NSApplication.willBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppResume()
        }
        observerContainer.observers.append(activeObserver)
        #endif
    }

    private func handleAppResume() {
        print("[DenonLog] App resumed from background")
        // バックグラウンド中はポーリングが止まるので、「接続済み」表示のままでも AVR に届くとは限らない。
        // 状態に関わらず到達確認から始め、必要なら再接続・reheal まで行う（参照: upgraded-guacamole b95c09e）。
        Task { await recoverConnection(.resume) }
    }

    // MARK: - Auto recovery

    private enum RecoveryTrigger: String {
        case resume, poll, command
    }

    /// 切断を検知したとき・アプリ復帰時の自動復旧。
    /// 1. 前回のアドレスに届くか確認する。復帰直後は Wi-Fi が戻っていないことがあるので、1.5 秒後に 1 回だけ再確認する
    /// 2. 届けばそのアドレスのまま。接続済みなら最新状態を取り直すだけ、切れていれば再接続する
    /// 3. 届かなければ古いアドレスへの接続（5 秒タイムアウト）は繰り返さず、MAC による再検出（reheal）に進む
    private func recoverConnection(_ trigger: RecoveryTrigger) async {
        let savedHost = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
        let host = lastConnectedHost.isEmpty ? savedHost : lastConnectedHost
        guard !isRecovering, !host.isEmpty, connectionStatus != .connecting else { return }
        // このセッションで一度も接続していないなら、自動接続がオンのときだけ保存済みアドレスを試す
        if lastConnectedHost.isEmpty && !UserDefaults.standard.bool(forKey: "autoConnect") { return }

        isRecovering = true
        defer { isRecovering = false }
        DiagnosticsLog.shared.record("recover: start (\(trigger.rawValue))")

        let savedPort = UserDefaults.standard.integer(forKey: "defaultPort")
        let port = savedPort > 0 ? savedPort : 8080
        let isYamaha = (Self.savedBrand(forHost: host) ?? capabilities.brand) == .yamaha
        var reachable = isYamaha ? await yamaha.isReachable(host: host) : await client.isReachable(host: host, port: port)
        if !reachable && trigger == .resume {
            try? await Task.sleep(for: .seconds(1.5))
            reachable = isYamaha ? await yamaha.isReachable(host: host) : await client.isReachable(host: host, port: port)
        }

        if reachable {
            if connectionStatus.isConnected {
                if usingYamaha { await yamaha.pollNow() } else { await client.pollNow() }
                DiagnosticsLog.shared.record("recover: still reachable, refreshed")
            } else {
                await connect(host: host, allowReheal: false)
                DiagnosticsLog.shared.record(connectionStatus.isConnected ? "recover: reconnected" : "recover: reconnect failed")
            }
            return
        }

        // 古いアドレスでのポーリング・Telnet を止め、「接続済み」のまま古い状態を見せないようにする
        await disconnect()
        if await rehealAndReconnect(failedHost: host) {
            DiagnosticsLog.shared.record("recover: reconnected via reheal")
        } else {
            DiagnosticsLog.shared.record("recover: AVR not found")
        }
    }

    /// 一時的な通知を出す（数秒で自動的に消える）。key はローカライズキー。
    private func showNotice(_ key: String) {
        transientNoticeKey = key
        let token = UUID()
        noticeToken = token
        Task {
            try? await Task.sleep(for: .seconds(6))
            if noticeToken == token { transientNoticeKey = nil }
        }
    }

    #if DEBUG
    // MARK: - Screenshot demo

    /// App Store 用スクリーンショット撮影用（DEBUG ビルドで起動引数 `-uiDemo`）。
    /// AVR が無くても接続中のダッシュボードを表示する。通信は一切しない。
    /// 参照: upgraded-guacamole の `-uiDemo`。撮影手順は `scripts/capture-screenshots.sh`
    nonisolated static var isScreenshotDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiDemo")
    }

    /// 撮影する画面（起動引数 `-uiDemoTab <home|input|tuner|remote|zone|settings|connection>`）
    nonisolated static var screenshotDemoTab: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiDemoTab"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 開発用: 起動時に検索も自動復旧もせず、このアドレスにだけ接続する（`-debugConnectHost 127.0.0.1`）。
    /// scripts/mock-yamaha.py などの模擬サーバーで試すときに、LAN 上の実機へつながないようにするため。
    /// 自動接続を止めるため `-autoConnect NO` と一緒に使う
    nonisolated static var debugConnectHost: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugConnectHost"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 開発用: 接続後に一通りの操作を順に送る（`-debugExercise`）。模擬サーバーのログで届いた内容を確かめる
    func runDebugExercise() async {
        guard ProcessInfo.processInfo.arguments.contains("-debugExercise") else { return }
        let steps: [(String, () -> Void)] = [
            ("volume -40", { self.setVolume(-40) }), ("volume up", { self.volumeUp() }),
            ("mute on", { self.setMute(true) }), ("mute off", { self.setMute(false) }),
            ("input hdmi2", { self.setInput(id: self.capabilities.inputs.dropFirst().first?.id ?? "") }),
            ("sound mode", { self.setSoundMode(id: self.capabilities.soundModes.first?.id ?? "") }),
            ("zone2 on", { self.setZone2Power(true) }), ("zone2 up", { self.zone2VolumeUp() }),
            ("tuner", { self.selectTunerInput() }), ("presets", { self.startTunerScan() }),
            ("preset 2", { self.selectTunerPreset(2) }), ("freq up", { self.tunerFreqUp() }),
            ("cursor up", { self.cursorUp() }), ("enter", { self.cursorEnter() }), ("setup", { self.setupMenu() }),
        ]
        for (name, step) in steps {
            print("[DenonLog] debugExercise: \(name)")
            step()
            try? await Task.sleep(for: .milliseconds(700))
        }
        print("[DenonLog] debugExercise: done, succeeded=\(sessionSucceededFeatures.map(\.rawValue).sorted())")
    }

    /// 接続中の見た目にするための固定の状態を入れる
    func applyScreenshotDemoState() {
        var info = DeviceInfo()
        info.modelName = "AV Receiver"
        avr.deviceInfo = info
        avr.isConnected = true
        avr.isPoweredOn = true
        avr.isMuted = false
        avr.volumeDB = -32.5
        // チューナー画面は入力が TUNER のときだけ操作できるので、チューナーを撮るときだけ切り替える
        avr.input = Self.screenshotDemoTab == "tuner" ? .tuner : .bluray
        avr.surroundMode = .movie
        avr.tunerBand = .fm
        avr.tunerFrequency = "80.0"
        avr.tunerPreset = 1
        // 接続設定の画面に出す検出結果（撮影中は実際の検索をしない。ConnectionView を参照）
        discovery.devices = [
            DiscoveredDevice(id: "192.168.1.20", name: "AV Receiver", host: "192.168.1.20", port: 8080, macAddress: "")
        ]
        connectionStatus = .connected
    }
    #endif
}
