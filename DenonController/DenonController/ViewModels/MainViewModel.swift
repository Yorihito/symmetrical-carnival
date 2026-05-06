import SwiftUI

// MARK: - ConnectionStatus

enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: LocalizedStringKey {
        switch self {
        case .disconnected: "未接続"
        case .connecting:   "接続中..."
        case .connected:    "接続済み"
        case .error:        "エラー"
        }
    }

    var isConnected: Bool { self == .connected }
}

// MARK: - MainViewModel

/// UI と AVRHTTPClient を繋ぐ ViewModel。すべての AVR 操作はここ経由で行う。
@Observable
@MainActor
final class MainViewModel {

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

    init() {
        // 前回フェッチしたプリセットを復元する
        if let data = UserDefaults.standard.data(forKey: "savedTunerPresets"),
           let saved = try? JSONDecoder().decode([TunerPreset].self, from: data) {
            tunerAllPresets = saved
        }
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
        connectingDetail = "デバイスを検索中..."

        let (found, _) = await MDNSScanner.scan()
        guard let device = found.first else {
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

    func connect(host: String, port: Int? = nil) async {
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

        do {
            connectionLog.append("Step 2: Connecting via HTTP to port \(targetPort)...")
            let (info, updates) = try await client.connect(host: host, port: targetPort) { [weak self] step in
                Task { @MainActor [weak self] in
                    self?.connectingDetail = step
                    self?.connectionLog.append("  -> HTTP: \(step)")
                }
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
                    self.avr.apply(snapshot)
                }
                print("[DenonLog] [\(connectionID.uuidString.prefix(4))] Update loop finished (Stream ended)")
                self.connectionLog.append("!!! Update loop ended (ID: \(connectionID.uuidString.prefix(4)))")
                if self.currentConnectionID == connectionID {
                    self.handleDisconnect()
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
            connectionStatus = .error(error.localizedDescription)
            avr.isConnected = false
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
        connectionStatus = .disconnected
        avr.isConnected = false
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

    func setPower(_ on: Bool) { send(on ? "PWON" : "PWSTANDBY") }
    func togglePower()        { setPower(!avr.isPoweredOn) }

    // MARK: - Volume

    func volumeUp()   { send("MVUP") }
    func volumeDown() { send("MVDOWN") }
    func setVolume(_ db: Double) { 
        avr.volumeDB = db
        send(AVRState.volumeCommand(forDB: db)) 
    }
    func setMute(_ on: Bool)    { send(on ? "MUON" : "MUOFF") }
    func toggleMute()           { setMute(!avr.isMuted) }

    // MARK: - Input

    func setInput(_ input: InputSource) { send(input.command) }

    // MARK: - Surround（HTTP では取得不可 → ローカル追跡 + Telnet 通知で補正）

    func setSurroundMode(_ mode: SurroundMode) {
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
    /// 未スキャンなら単純に +1。
    func tunerPresetUp() {
        if tunerPresets.isEmpty {
            let next = avr.tunerPreset > 0 ? min(56, avr.tunerPreset + 1) : 1
            selectTunerPreset(next)
        } else {
            let cur = avr.tunerPreset
            if let idx = tunerPresets.firstIndex(where: { $0.id == cur }) {
                selectTunerPreset(tunerPresets[(idx + 1) % tunerPresets.count].id)
            } else {
                selectTunerPreset(tunerPresets[0].id)
            }
        }
    }

    /// プリセット ↓（同上）。
    func tunerPresetDown() {
        if tunerPresets.isEmpty {
            let prev = avr.tunerPreset > 1 ? avr.tunerPreset - 1 : 1
            selectTunerPreset(prev)
        } else {
            let cur = avr.tunerPreset
            if let idx = tunerPresets.firstIndex(where: { $0.id == cur }) {
                selectTunerPreset(tunerPresets[(idx - 1 + tunerPresets.count) % tunerPresets.count].id)
            } else {
                selectTunerPreset(tunerPresets[tunerPresets.count - 1].id)
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
        avr.tunerStationName = ""   // Telnet からの更新を待つ
    }

    // MARK: - Tuner Preset Scan

    /// スキャン生データ（フィルタ前）
    var tunerAllPresets: [TunerPreset] = []

    /// 除外する周波数（カンマ区切り MHz、例: "90.0" or "90.0, 85.0"）
    var tunerSkipFrequencies: String = UserDefaults.standard.string(forKey: "tunerSkipFrequencies") ?? "90.0"

    /// 除外周波数を適用したプリセット一覧（表示・ナビゲーション用）
    var tunerPresets: [TunerPreset] {
        let skipSet = skipFreqSet(from: tunerSkipFrequencies)
        guard !skipSet.isEmpty else { return tunerAllPresets }
        return tunerAllPresets.filter { p in
            guard let f = Double(p.frequency) else { return true }
            return !skipSet.contains(f)
        }
    }

    /// 除外周波数を保存する
    func setTunerSkipFrequencies(_ value: String) {
        tunerSkipFrequencies = value
        UserDefaults.standard.set(value, forKey: "tunerSkipFrequencies")
    }

    private func skipFreqSet(from raw: String) -> Set<Double> {
        Set(raw.components(separatedBy: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
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
            if let xmlPresets = await client.fetchTunerPresetsFromXml(), !Task.isCancelled {
                tunerScanProgress = 56
                tunerAllPresets = xmlPresets
                saveTunerPresets()
                isScanningTuner = false
                return
            }

            // ── Phase 2: Telnet ベーススキャン（フォールバック）───────────
            // 周波数変化で登録済みスロットを判定する。
            // 空スロットは同じプレースホルダー周波数（例: 90.0 MHz）になるため
            // freqChanged が false になり追加されない。
            // プレースホルダーが初回だけ変化して入る場合は tunerSkipFrequencies で除外する。
            var found: [TunerPreset] = []
            var prevFreq = avr.tunerFrequency
            var prevBand = avr.tunerBand

            for i in 1...56 {
                if Task.isCancelled { break }
                tunerScanProgress = i

                selectTunerPreset(i)
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { break }

                let newFreq = avr.tunerFrequency
                let newBand = avr.tunerBand
                let name    = avr.tunerStationName

                guard !newFreq.isEmpty else { prevFreq = newFreq; prevBand = newBand; continue }

                let freqChanged = newFreq != prevFreq || newBand != prevBand
                // P01 は比較対象の前スロットがないため freqChanged に関わらず追加する
                if freqChanged || i == 1 {
                    found.append(TunerPreset(
                        id: i, band: newBand, frequency: newFreq, stationName: name
                    ))
                }
                prevFreq = newFreq
                prevBand = newBand
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
            // Telnet 接続中なら Telnet を優先（スペース含むコマンドも正しく送信できる）
            do {
                try await telnet.send(command)
            } catch {
                // Telnet 未接続 or 失敗 → HTTP フォールバック
                await client.send(command)
            }
        }
    }
}
