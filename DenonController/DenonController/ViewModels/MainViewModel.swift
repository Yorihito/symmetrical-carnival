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

    // MARK: - Private
    private let client = AVRHTTPClient()
    private let telnet = TelnetClient()
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
            if connectionStatus.isConnected { return }
        }

        connectionStatus = .connecting
        connectingDetail = String(localized: "デバイスを検索中...")

        // 保存済みの MAC と一致する機体を優先する。なければ AVR が 1 台だけ見つかったときに限って接続する
        // （複数台ある環境で別の AVR に勝手につながないため）
        let (found, _) = await MDNSScanner.scan()
        let savedMac = DeviceInfo.normalizedMac(UserDefaults.standard.string(forKey: "defaultMacAddress") ?? "")
        let macMatch = savedMac.isEmpty ? nil : found.first(where: { $0.macAddress == savedMac })
        guard let device = macMatch ?? (found.count == 1 ? found.first : nil) else {
            DiagnosticsLog.shared.record("autoConnect: fallback scan found \(found.count) AVR(s), none selected")
            connectionStatus = .disconnected
            connectingDetail = ""
            return
        }

        connectingDetail = ""
        await connect(host: device.host, port: device.port)
        if connectionStatus.isConnected {
            UserDefaults.standard.set(device.host, forKey: "defaultHost")
            UserDefaults.standard.set(device.port, forKey: "defaultPort")
        }
    }

    /// DHCP でリース更新された AVR を、保存済みの MAC アドレスを手掛かりに LAN 上で再検出する。
    /// 見つかった場合は `defaultHost` / `defaultPort` を新しい値に更新して返す。
    /// 同じアドレスで見つかった場合も返す（復帰直後に Wi-Fi が戻る前の失敗だった可能性があるため）。
    /// 30秒に1回・多重実行なしに制限し、AVR が本当にオフラインのときに無限ループしないようにする。
    private func attemptAutoReheal(failedHost: String) async -> (host: String, port: Int)? {
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
        return (match.host, match.port)
    }

    /// reheal で見つかったアドレスへ 1 回だけ再接続する（再接続時は reheal しないのでループしない）。
    /// アドレスが実際に変わっていたら通知を出す（参照: upgraded-guacamole 9876d15）。
    /// - Returns: 再接続に成功したら true
    @discardableResult
    private func rehealAndReconnect(failedHost: String) async -> Bool {
        guard let match = await attemptAutoReheal(failedHost: failedHost) else { return false }
        let healLog = connectionLog
        await connect(host: match.host, port: match.port, allowReheal: false)
        connectionLog = healLog + connectionLog   // 再接続でリセットされる reheal のログを残す
        guard connectionStatus.isConnected else { return false }
        if match.host != failedHost {
            showNotice("AVR のアドレスが変わったため自動で再接続しました。")
        }
        return true
    }

    func connect(host: String, port: Int? = nil, allowReheal: Bool = true) async {
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
        DiagnosticsLog.shared.record("connect: start")

        do {
            connectionLog.append("Step 2: Connecting via HTTP to port \(targetPort)...")
            let (info, updates) = try await client.connect(host: host, port: targetPort) { @Sendable _ in
                // 進捗更新を一旦無効化して初期化エラーを確実に消す
            }
            connectionLog.append("Step 3: Probing additional zones...")
            var finalInfo = info
            finalInfo.hasZone3 = await client.probeZone3()

            connectionLog.append("Step 4: Finalizing app state...")
            connectingDetail = ""
            connectionStatus = .connected
            avr.isConnected = true
            avr.deviceInfo  = finalInfo
            lastConnectedHost = host
            ReviewRequestManager.recordSuccess()
            DiagnosticsLog.shared.record("connect: success (\(finalInfo.modelName))")

            // MAC アドレスを保存しておく（次回起動時に IP が変わっていても同一機体として再検出できるように）
            if !finalInfo.macAddress.isEmpty {
                UserDefaults.standard.set(finalInfo.macAddress, forKey: "defaultMacAddress")
            } else {
                DiagnosticsLog.shared.record("connect: AVR reported no MAC address; auto-reheal unavailable")
            }

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
                        if let src: InputSource = InputSource(rawValue: code) {
                            let targetAVR: AVRState = self.avr
                            targetAVR.input = src
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
                    if let src2 = InputSource(rawCode: snapshot.zone2InputCode) {
                        self.avr.zone2Input = src2
                    }
                }
                print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Update loop finished (Stream ended)")
                self.connectionLog.append("!!! Update loop ended (ID: \(connectionID.uuidString.prefix(4)))")
                if self.currentConnectionID == connectionID {
                    self.handleDisconnect()
                    // キャンセルではなくストリームが閉じた = ポーリングが連続で失敗した。
                    // IP が変わった可能性があるので自動復旧に回す（ユーザー操作による切断では走らない）。
                    // updateTask は再接続時にキャンセルされるため、復旧は別タスクで行う。
                    if !Task.isCancelled {
                        DiagnosticsLog.shared.record("poll: AVR unreachable, recovering")
                        Task { [weak self] in await self?.recoverConnection(.poll) }
                    }
                }
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
            connectionLog.append("Success: Connection sequence complete.")
            print("[DenonLog] Success: Fully connected to \(host)")

        } catch {
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

    func disconnect() async {
        updateTask?.cancel()
        updateTask = nil
        telnetListenTask?.cancel()
        telnetListenTask = nil
        
        // 切断処理がハングして次の接続をブロックしないよう、タイムアウト付きで実行
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.client.disconnect() }
            group.addTask { await self.telnet.disconnect() }
            
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
        send(on ? "PWON" : "PWSTANDBY") 
    }
    func togglePower()        { setPower(!avr.isPoweredOn) }

    // MARK: - Volume

    func volumeUp() {
        markOperation(for: "volume")
        avr.volumeDB += 0.5
        send("MVUP")
    }
    func volumeDown() {
        markOperation(for: "volume")
        avr.volumeDB -= 0.5
        send("MVDOWN")
    }
    func setVolume(_ db: Double) { 
        markOperation(for: "volume")
        avr.volumeDB = db
        send(AVRState.volumeCommand(forDB: db)) 
    }
    func setMute(_ on: Bool) { 
        markOperation(for: "mute")
        avr.isMuted = on
        send(on ? "MUON" : "MUOFF") 
    }
    func toggleMute()           { setMute(!avr.isMuted) }

    // MARK: - Input

    func setInput(_ input: InputSource) {
        markOperation(for: "input")
        avr.input = input   // 楽観的更新（UIへ即時反映）
        send(input.command)
    }

    // MARK: - Surround（HTTP では取得不可 → ローカル追跡 + Telnet 通知で補正）

    func setSurroundMode(_ mode: SurroundMode) {
        markOperation(for: "surround")
        send(mode.command)
        avr.surroundMode = mode
    }

    // MARK: - Zone 2

    func setZone2Power(_ on: Bool) { send(on ? "Z2ON" : "Z2OFF") }
    func zone2VolumeUp()           { send("Z2UP") }
    func zone2VolumeDown()         { send("Z2DOWN") }
    func setZone2Mute(_ on: Bool)  { send(on ? "Z2MUON" : "Z2MUOFF") }

    // MARK: - Zone 3

    func setZone3Power(_ on: Bool) { send(on ? "Z3ON" : "Z3OFF") }
    func zone3VolumeUp()           { send("Z3UP") }
    func zone3VolumeDown()         { send("Z3DOWN") }

    // MARK: - OSD Navigation

    func cursorUp()     { send("MNCUP") }
    func cursorDown()   { send("MNCDN") }
    func cursorLeft()   { send("MNCLT") }
    func cursorRight()  { send("MNCRT") }
    func cursorEnter()  { send("MNENT") }
    func navBack()      { send("MNRTN") }
    func infoButton()   { send("MNINF") }
    func optionButton() { send("MNOPT") }
    func setupMenu()    { send("MNMEN ON") }

    // MARK: - Tuner

    func setTunerBand(_ band: TunerBand) {
        avr.tunerBand = band   // 楽観的更新（HTTP ポーリング応答を待たずに即時反映）
        send(band.selectCommand)
    }

    /// プリセット ↑。
    /// スキャン済みリストがあればそのリスト内を循環（空スロット・スキップを自動回避）。
    /// 未スキャンなら単純に +1 し、56 を超えたら 1 に戻る。
    func tunerPresetUp() {
        let presets = tunerPresets
        if presets.isEmpty {
            let next = (avr.tunerPreset % 56) + 1
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
            let prev = avr.tunerPreset <= 1 ? 56 : avr.tunerPreset - 1
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

    func tunerFreqUp()   { send(avr.tunerBand.freqUpCommand) }
    func tunerFreqDown() { send(avr.tunerBand.freqDownCommand) }

    /// プリセット選択。
    /// HTTP では読み返せないのでローカル追跡。Telnet が接続されていれば
    /// 周波数と局名は自動的に更新される。
    func selectTunerPreset(_ n: Int) {
        send(String(format: "TPAN%02d", n))
        avr.tunerPreset = n
        avr.tunerStationName = ""   // 更新を待つ
        avr.tunerFrequency = ""     // 更新を待つ
    }

    // MARK: - Tuner Preset Scan

    /// スキャン生データ（フィルタ前）
    var tunerAllPresets: [TunerPreset] = []
    
    /// 最大プリセット数
    let maxTunerSlots = 56

    /// 除外する周波数（カンマ区切り MHz、例: "90.0" or "90.0, 85.0"）
    /// デフォルトは "90.0"（空きスロットの代表値）
    var tunerSkipFrequencies: String = UserDefaults.standard.string(forKey: "tunerSkipFrequencies") ?? "90.0"

    /// 除外周波数を適用し、重複を排除したプリセット一覧
    var tunerPresets: [TunerPreset] {
        let skipSet = skipFreqSet(from: tunerSkipFrequencies)
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
    /// まず formTuner_TunerPresetXml.xml を一括取得して試み（高速・移動なし）、
    /// 取得できない場合は Telnet ベーススキャンにフォールバックする。
    func startTunerScan() {
        guard !isScanningTuner else { return }
        isScanningTuner = true
        tunerScanProgress = 0
        tunerAllPresets = []

        tunerScanTask = Task { [weak self] in
            guard let self else { return }

            // ── Phase 1: XML 一括取得 ─────────────────────────────────────
            if let xmlPresets = await client.fetchTunerPresetsFromXml(), !xmlPresets.isEmpty, !Task.isCancelled {
                tunerScanProgress = 56
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

    private func saveTunerPresets() {
        if let data = try? JSONEncoder().encode(tunerAllPresets) {
            UserDefaults.standard.set(data, forKey: "savedTunerPresets")
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
            let log = await client.fetchTunerDiagnostics()
            await MainActor.run { [weak self] in
                self?.tunerDiagLog = log
                self?.isFetchingTunerDiag = false
            }
        }
    }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        setInput(preset.input)
        setVolume(preset.volumeDB)
        setSurroundMode(preset.surroundMode)
    }

    func saveCurrentAsPreset(name: String, emoji: String) {
        let preset = Preset(
            name: name, emoji: emoji,
            input: avr.input,
            volumeDB: avr.volumeDB,
            surroundMode: avr.surroundMode
        )
        presetStore.save(preset)
    }

    // MARK: - Private helper

    private func send(_ command: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await telnet.send(command)
            } catch {
                // Telnet 未接続 or 失敗 → HTTP フォールバック
                do {
                    try await client.send(command)
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
        var reachable = await client.isReachable(host: host, port: port)
        if !reachable && trigger == .resume {
            try? await Task.sleep(for: .seconds(1.5))
            reachable = await client.isReachable(host: host, port: port)
        }

        if reachable {
            if connectionStatus.isConnected {
                await client.pollNow()
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
}
