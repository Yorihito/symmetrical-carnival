import Foundation

// Yamaha の AV レシーバーを YXC（Yamaha Extended Control、HTTP で JSON をやり取りする方式）で操作する。
// YXC にないリモコン画面の操作は、使える機種なら旧 XML API（YNC、/YamahaRemoteControl/ctrl）で行う。
// 設計: docs/yamaha-support-design.md
// 参考: Yamaha Extended Control API Specification (Basic) / 非公式にまとめられた仕様 Rev 2.00

/// 状態の取得結果（ポーリング 1 回分）
struct YamahaSnapshot: Sendable {
    var isPoweredOn = false
    var volumeDB: Double = -60
    var isMuted = false
    var input = ""
    var soundProgram = ""
    var pureDirect = false

    var hasZone2 = false
    var zone2Power = false
    var zone2VolumeDB: Double = -40
    var zone2Muted = false
    var zone2Input = ""

    var tunerFetched = false
    var tunerBand: TunerBand = .fm
    var tunerFrequency = ""
    var tunerPreset = 0
}

enum YamahaError: LocalizedError, Sendable {
    /// 機器が response_code 0 以外を返した（例: 5 = 今の状態では操作できない）
    case rejected(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rejected(let code): String(localized: "AVR が操作を受け付けませんでした。") + " (\(code))"
        case .badResponse:        String(localized: "AVR からの応答を読み取れませんでした。")
        }
    }
}

/// 機器を判定したときの情報（検出と接続で使う）
struct YamahaIdentity: Sendable {
    var modelName: String
    var networkName: String
    var macAddress: String
    var apiVersion: String
    var systemVersion: String
    var destination: String
}

/// dB と YXC の音量値の換算
struct YamahaVolumeScale: Sendable {
    var minStep = 0
    var maxStep = 161
    var stepSize = 1
    /// 音量値 0 のときの dB。RX-V 系は -80.5 dB と考えられる（接続時に YNC の dB 値で確かめ直す）
    var dbAtZero = -80.5
    var dbPerStep = 0.5
    /// `actual_volume` が使える機種は dB で直接やり取りする
    var usesActualDB = false
    var actualRange: ClosedRange<Double>?

    func db(fromStep v: Int) -> Double { dbAtZero + Double(v) * dbPerStep }

    func step(forDB db: Double) -> Int {
        let raw = Int(((db - dbAtZero) / dbPerStep).rounded())
        let snapped = (raw / max(stepSize, 1)) * max(stepSize, 1)
        return min(maxStep, max(minStep, snapped))
    }

    var rangeDB: ClosedRange<Double> {
        if usesActualDB, let actualRange { return actualRange }
        return db(fromStep: minStep)...db(fromStep: maxStep)
    }
}

actor YamahaClient {
    static let port = 80
    private let base = "/YamahaExtendedControl/v1"

    private var host = ""
    private(set) var scale = YamahaVolumeScale()
    private var hasZone2 = false
    private var tunerInputID: String?
    private var presetBandMode = "common"   // "common" or "separate"
    private var presetCount = 40
    /// YXC の controlCursor / controlMenu が使えるか（2020 年以降の機種）
    private var yxcCursor = false
    private var yxcMenu = false
    /// YNC でカーソル・メニューを送るときの XML の入れ子（desc.xml から読む）
    private var yncCursorPath: [String]?
    private var yncMenuPath: [String]?

    private var lastMainVolumeStep: Int?
    /// dB で直接やり取りする機種で、最後に分かっているメインゾーンの音量
    private var lastMainVolumeDB: Double?
    private var lastZone2VolumeStep: Int?

    private var pollTask: Task<Void, Never>?
    private var continuation: AsyncStream<YamahaSnapshot>.Continuation?
    private var lastActivity = Date()
    private var interval = 1.5
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3
    private var lastChangeKey = ""

    // MARK: - Identify

    /// 指定アドレスが Yamaha（YXC 対応機）かを確かめ、機種名と MAC アドレスを返す。違えば nil
    static func identify(host: String, timeout: Int = 3) async -> YamahaIdentity? {
        guard let info = try? await getJSON(host: host, path: "/YamahaExtendedControl/v1/system/getDeviceInfo", timeout: timeout),
              (info["response_code"] as? Int) == 0 else { return nil }
        let network = try? await getJSON(host: host, path: "/YamahaExtendedControl/v1/system/getNetworkStatus", timeout: timeout)
        var mac = ""
        if let macs = network?["mac_address"] as? [String: Any] {
            let connection = network?["connection"] as? String ?? ""
            mac = (macs[connection] as? String)
                ?? (macs["wired_lan"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (macs["wireless_lan"] as? String) ?? ""
        }
        return YamahaIdentity(
            modelName: info["model_name"] as? String ?? "",
            networkName: network?["network_name"] as? String ?? "",
            macAddress: DeviceInfo.normalizedMac(mac),
            apiVersion: numberString(info["api_version"]),
            systemVersion: numberString(info["system_version"]),
            destination: info["destination"] as? String ?? ""
        )
    }

    // MARK: - Connect

    func connect(host: String) async throws -> (DeviceInfo, ReceiverCapabilities, YamahaIdentity, AsyncStream<YamahaSnapshot>) {
        // 接続中のリクエストは引数の host だけを使う。起動直後は自動接続と復帰時の再接続が重なることがあり、
        // その間に別の接続の disconnect() が self.host を消しても、この接続が壊れないようにするため
        guard let identity = await Self.identify(host: host, timeout: 5) else {
            throw AVRError.connectionFailed(String(localized: "AVR から正常応答がありません"))
        }
        let features = try await Self.getJSON(host: host, path: base + "/system/getFeatures", timeout: 5)
        let names = try? await Self.getJSON(host: host, path: base + "/system/getNameText", timeout: 5)
        let caps = await buildCapabilities(host: host, features: features, names: names)
        await calibrateVolumeIfPossible(host: host)
        self.host = host

        var info = DeviceInfo()
        info.modelName = identity.modelName
        info.brandName = ReceiverBrand.yamaha.displayName
        info.hasZone2 = caps.hasZone2
        info.hasZone3 = caps.hasZone3
        info.macAddress = identity.macAddress
        info.firmwareVersion = identity.systemVersion
        info.apiVersion = identity.apiVersion
        info.region = identity.destination

        let stream = startPolling()
        return (info, caps, identity, stream)
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        continuation?.finish()
        continuation = nil
        host = ""
    }

    func isReachable(host: String) async -> Bool {
        let info = try? await Self.getJSON(host: host, path: base + "/system/getDeviceInfo", timeout: 5)
        return (info?["response_code"] as? Int) == 0
    }

    func pollNow() {
        guard continuation != nil, !host.isEmpty else { return }
        lastActivity = Date()
        interval = 1.5
        restartPollLoop()
    }

    // MARK: - Capabilities

    private func buildCapabilities(host: String, features: [String: Any], names: [String: Any]?) async -> ReceiverCapabilities {
        let system = features["system"] as? [String: Any] ?? [:]
        let zones = features["zone"] as? [[String: Any]] ?? []
        let main = zones.first { ($0["id"] as? String) == "main" } ?? [:]
        let zoneIDs = Set(zones.compactMap { $0["id"] as? String })
        let zoneNum = system["zone_num"] as? Int ?? zones.count
        hasZone2 = zoneIDs.contains("zone2") || zoneNum >= 2

        let mainFuncs = Set(main["func_list"] as? [String] ?? [])
        yxcCursor = mainFuncs.contains("cursor")
        yxcMenu = mainFuncs.contains("menu")

        // 音量の範囲
        for r in main["range_step"] as? [[String: Any]] ?? [] {
            let id = r["id"] as? String ?? ""
            if id == "volume" {
                scale.minStep = r["min"] as? Int ?? scale.minStep
                scale.maxStep = r["max"] as? Int ?? scale.maxStep
                scale.stepSize = max(1, r["step"] as? Int ?? 1)
            } else if id == "actual_volume_db", let lo = Self.number(r["min"]), let hi = Self.number(r["max"]), lo < hi {
                scale.actualRange = lo...hi
            }
        }
        scale.usesActualDB = mainFuncs.contains("actual_volume") && scale.actualRange != nil

        // 本体で付けた名前
        var inputNames: [String: String] = [:]
        var programNames: [String: String] = [:]
        for item in names?["input_list"] as? [[String: Any]] ?? [] {
            if let id = item["id"] as? String, let text = item["text"] as? String { inputNames[id] = text }
        }
        for item in names?["sound_program_list"] as? [[String: Any]] ?? [] {
            if let id = item["id"] as? String, let text = item["text"] as? String { programNames[id] = text }
        }

        let hiddenInputs: Set<String> = ["mc_link", "main_sync", "none"]
        let inputIDs = (main["input_list"] as? [String])
            ?? (system["input_list"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let inputs = inputIDs.filter { !hiddenInputs.contains($0) }
            .map { YamahaCatalog.input(id: $0, customName: inputNames[$0]) }
        tunerInputID = inputIDs.contains("tuner") ? "tuner" : nil

        var modes = (main["sound_program_list"] as? [String] ?? [])
            .map { YamahaCatalog.soundProgram(id: $0, customName: programNames[$0]) }
        if mainFuncs.contains("pure_direct") { modes.append(YamahaCatalog.pureDirect) }

        // チューナー
        let tuner = features["tuner"] as? [String: Any] ?? [:]
        let tunerFuncs = Set(tuner["func_list"] as? [String] ?? [])
        var bands: [TunerBand] = []
        if tunerFuncs.contains("fm") { bands.append(.fm) }
        if tunerFuncs.contains("am") { bands.append(.am) }
        if let preset = tuner["preset"] as? [String: Any] {
            presetBandMode = preset["type"] as? String ?? "common"
            presetCount = preset["num"] as? Int ?? presetCount
        }

        // リモコン画面: YXC で送れなければ YNC を調べる
        if !yxcCursor { await loadYNCPaths(host: host) }
        let remote = yxcCursor || yncCursorPath != nil

        return ReceiverCapabilities(
            brand: .yamaha,
            inputs: inputs,
            soundModes: modes,
            volumeRangeDB: scale.rangeDB,
            showsNativeVolumeScale: false,
            hasZone2: hasZone2,
            hasZone3: zoneIDs.contains("zone3"),
            tunerInputID: tunerInputID,
            tunerBands: bands.isEmpty ? [.fm, .am] : bands,
            tunerPresetsNeedScan: false,
            tunerPresetCount: presetCount,
            supportsRemote: remote
        )
    }

    /// YNC の説明ファイルから、メインゾーンのカーソル・メニュー操作の XML の入れ子を読む。
    /// 例: `Main_Zone,Cursor_Control,Cursor` → `<Main_Zone><Cursor_Control><Cursor>Up</Cursor>…`
    private func loadYNCPaths(host: String) async {
        guard let res = try? await LocalHTTP.get(host: host, port: Self.port, path: "/YamahaRemoteControl/desc.xml", timeout: 5),
              res.status == 200, let xml = String(data: res.body, encoding: .utf8) else { return }
        var cursor: [String]?
        var menu: [String]?
        var search = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<Define", range: search),
              let gt = xml.range(of: ">", range: open.upperBound..<xml.endIndex),
              let close = xml.range(of: "</Define>", range: gt.upperBound..<xml.endIndex) {
            let path = xml[gt.upperBound..<close.lowerBound].split(separator: ",").map(String.init)
            if path.first == "Main_Zone" {
                if cursor == nil, path.last == "Cursor", path.contains("Cursor_Control") { cursor = path }
                if menu == nil, path.last == "Menu_Control" { menu = path }
            }
            search = close.upperBound..<xml.endIndex
        }
        yncCursorPath = cursor
        yncMenuPath = menu
    }

    /// YXC の音量値と dB の対応を、YNC の dB 表示で確かめる（YNC がない機種では既定値のまま）
    private func calibrateVolumeIfPossible(host: String) async {
        guard !scale.usesActualDB else { return }
        let body = #"<YAMAHA_AV cmd="GET"><Main_Zone><Basic_Status>GetParam</Basic_Status></Main_Zone></YAMAHA_AV>"#
        guard let res = try? await LocalHTTP.post(host: host, port: Self.port, path: "/YamahaRemoteControl/ctrl", body: body, timeout: 5),
              res.status == 200, let xml = String(data: res.body, encoding: .utf8),
              let lvl = xml.range(of: "<Lvl>"),
              let val = Self.tag("Val", in: xml, from: lvl.upperBound).flatMap(Double.init),
              let exp = Self.tag("Exp", in: xml, from: lvl.upperBound).flatMap(Double.init),
              let status = try? await Self.getJSON(host: host, path: base + "/main/getStatus", timeout: 5),
              let step = status["volume"] as? Int
        else { return }
        let db = val / pow(10, exp)
        let atZero = db - Double(step) * scale.dbPerStep
        // 明らかにおかしい値（読み取りの行き違いなど）は使わない
        if (-100.0 ... -60.0).contains(atZero) { scale.dbAtZero = atZero }
    }

    // MARK: - Commands

    func setPower(zone: String, on: Bool) async throws {
        try await command("/\(zone)/setPower?power=\(on ? "on" : "standby")")
    }

    func setMute(zone: String, on: Bool) async throws {
        try await command("/\(zone)/setMute?enable=\(on)")
    }

    func setVolume(zone: String, db: Double) async throws {
        if zone == "main", scale.usesActualDB {
            let clamped = min(scale.rangeDB.upperBound, max(scale.rangeDB.lowerBound, db))
            try await command("/main/setActualVolume?mode=db&value=\(String(format: "%.1f", clamped))")
            lastMainVolumeDB = clamped
            return
        }
        let v = scale.step(forDB: db)
        try await command("/\(zone)/setVolume?volume=\(v)")
        if zone == "main" { lastMainVolumeStep = v } else { lastZone2VolumeStep = v }
    }

    /// 1 段階上げ下げする。API 1.17 より前の機種にも対応するため、今の値から計算して送る
    func stepVolume(zone: String, up: Bool) async throws {
        if zone == "main", scale.usesActualDB, let db = lastMainVolumeDB {
            try await setVolume(zone: "main", db: db + (up ? 0.5 : -0.5))
            return
        }
        let current = zone == "main" ? lastMainVolumeStep : lastZone2VolumeStep
        guard let current else {
            try await command("/\(zone)/setVolume?volume=\(up ? "up" : "down")")
            return
        }
        let next = min(scale.maxStep, max(scale.minStep, current + (up ? scale.stepSize : -scale.stepSize)))
        try await command("/\(zone)/setVolume?volume=\(next)")
        if zone == "main" { lastMainVolumeStep = next } else { lastZone2VolumeStep = next }
    }

    func setInput(zone: String, id: String) async throws {
        try await command("/\(zone)/setInput?input=\(id)")
    }

    func setSoundMode(id: String) async throws {
        if id == YamahaCatalog.pureDirectID {
            try await command("/main/setPureDirect?enable=true")
        } else {
            // ピュアダイレクト中はサウンドプログラムが効かないので先に解除する（未対応の機種ではエラーを無視）
            try? await command("/main/setPureDirect?enable=false")
            try await command("/main/setSoundProgram?program=\(id)")
        }
    }

    enum RemoteKey: Sendable { case up, down, left, right, enter, back, info, option, setup }

    func remote(_ key: RemoteKey) async throws {
        let yxc: (String, String)
        let ync: String
        switch key {
        case .up:     yxc = ("controlCursor", "cursor=up");       ync = "Up"
        case .down:   yxc = ("controlCursor", "cursor=down");     ync = "Down"
        case .left:   yxc = ("controlCursor", "cursor=left");     ync = "Left"
        case .right:  yxc = ("controlCursor", "cursor=right");    ync = "Right"
        case .enter:  yxc = ("controlCursor", "cursor=select");   ync = "Sel"
        case .back:   yxc = ("controlCursor", "cursor=return");   ync = "Return"
        case .info:   yxc = ("controlMenu", "menu=display");      ync = "Display"
        case .option: yxc = ("controlMenu", "menu=option");       ync = "Option"
        case .setup:  yxc = ("controlMenu", "menu=on_screen");    ync = "On Screen"
        }
        let isMenu = yxc.0 == "controlMenu"
        if isMenu ? yxcMenu : yxcCursor {
            try await command("/main/\(yxc.0)?\(yxc.1)")
            return
        }
        // YNC: メニュー系は Menu_Control があればそちら、なければカーソルの一種として送る
        guard let path = (isMenu ? (yncMenuPath ?? yncCursorPath) : yncCursorPath) else {
            throw YamahaError.rejected(3)
        }
        var inner = ync
        for tag in path.reversed() { inner = "<\(tag)>\(inner)</\(tag)>" }
        let body = #"<YAMAHA_AV cmd="PUT">"# + inner + "</YAMAHA_AV>"
        let res = try await LocalHTTP.post(host: host, port: Self.port, path: "/YamahaRemoteControl/ctrl", body: body)
        guard res.status == 200 else { throw YamahaError.rejected(res.status) }
        if let xml = String(data: res.body, encoding: .utf8), xml.contains("RC=\""), !xml.contains("RC=\"0\"") {
            throw YamahaError.rejected(4)
        }
        noteActivity()
    }

    // MARK: - Tuner

    func setTunerBand(_ band: TunerBand) async throws {
        try await command("/tuner/setBand?band=\(band.rawValue.lowercased())")
    }

    func stepTunerFrequency(band: TunerBand, up: Bool) async throws {
        try await command("/tuner/setFreq?band=\(band.rawValue.lowercased())&tuning=\(up ? "up" : "down")")
    }

    /// プリセットを呼び出す。`id` は fetchTunerPresets が返した ID（バンド別の機種では AM に 1000 を足している）
    func recallPreset(id: Int) async throws {
        if presetBandMode == "separate" {
            let band = id > 1000 ? "am" : "fm"
            try await command("/tuner/recallPreset?zone=main&band=\(band)&num=\(id > 1000 ? id - 1000 : id)")
        } else {
            try await command("/tuner/recallPreset?zone=main&band=common&num=\(id)")
        }
    }

    /// 登録済みのプリセットを一度に読む（空きは除く）
    func fetchTunerPresets() async -> [TunerPreset]? {
        let bands: [(String, Int)] = presetBandMode == "separate" ? [("fm", 0), ("am", 1000)] : [("common", 0)]
        var result: [TunerPreset] = []
        for (band, offset) in bands {
            guard let info = try? await get("/tuner/getPresetInfo?band=\(band)") else { return nil }
            for (index, item) in (info["preset_info"] as? [[String: Any]] ?? []).enumerated() {
                let kHz = item["number"] as? Int ?? 0
                guard kHz > 0, let b = TunerBand(rawValue: (item["band"] as? String ?? band).uppercased()) else { continue }
                result.append(TunerPreset(id: offset + index + 1, band: b,
                                          frequency: Self.frequencyString(kHz: kHz, band: b), stationName: ""))
            }
        }
        return result
    }

    /// 診断用: チューナーと状態の生の応答
    func diagnostics() async -> String {
        var out = ""
        for path in ["/system/getDeviceInfo", "/system/getFeatures", "/main/getStatus",
                     "/tuner/getPlayInfo", "/tuner/getPresetInfo?band=common"] {
            out += "== \(path)\n"
            if let res = try? await LocalHTTP.get(host: host, port: Self.port, path: base + path) {
                out += (String(data: res.body, encoding: .utf8) ?? "(binary)") + "\n"
            } else {
                out += "(failed)\n"
            }
        }
        return out
    }

    // MARK: - Polling

    private func startPolling() -> AsyncStream<YamahaSnapshot> {
        pollTask?.cancel()
        continuation?.finish()
        let (stream, cont) = AsyncStream<YamahaSnapshot>.makeStream()
        continuation = cont
        consecutiveFailures = 0
        restartPollLoop()
        return stream
    }

    private func restartPollLoop() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let (ok, changed) = await self.poll()
                guard !Task.isCancelled else { break }
                if await self.endStreamIfUnreachable(ok) { break }
                let wait = await self.nextInterval(ok: ok, changed: changed)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func endStreamIfUnreachable(_ ok: Bool) -> Bool {
        if ok { consecutiveFailures = 0; return false }
        consecutiveFailures += 1
        guard consecutiveFailures >= maxConsecutiveFailures else { return false }
        consecutiveFailures = 0
        continuation?.finish()
        continuation = nil
        return true
    }

    private func nextInterval(ok: Bool, changed: Bool) -> Double {
        let now = Date()
        if changed || now.timeIntervalSince(lastActivity) < 10 {
            if changed { lastActivity = now }
            interval = 1.5
        } else if !ok {
            interval = min(interval + 5, 30)
        } else {
            interval = min(600, interval * 1.5)
        }
        return interval
    }

    private func noteActivity() {
        lastActivity = Date()
        interval = 1.5
        restartPollLoop()
    }

    private func poll() async -> (Bool, Bool) {
        guard let main = try? await get("/main/getStatus") else { return (false, false) }
        var snap = YamahaSnapshot()
        snap.isPoweredOn = (main["power"] as? String) == "on"
        snap.isMuted = main["mute"] as? Bool ?? false
        snap.input = main["input"] as? String ?? ""
        snap.soundProgram = main["sound_program"] as? String ?? ""
        snap.pureDirect = main["pure_direct"] as? Bool ?? false
        if let actual = main["actual_volume"] as? [String: Any], (actual["unit"] as? String) == "dB",
           let value = Self.number(actual["value"]) {
            snap.volumeDB = value
            lastMainVolumeDB = value
        } else if let v = main["volume"] as? Int {
            snap.volumeDB = scale.db(fromStep: v)
        }
        lastMainVolumeStep = main["volume"] as? Int ?? lastMainVolumeStep

        if hasZone2, let z2 = try? await get("/zone2/getStatus") {
            snap.hasZone2 = true
            snap.zone2Power = (z2["power"] as? String) == "on"
            snap.zone2Muted = z2["mute"] as? Bool ?? false
            snap.zone2Input = z2["input"] as? String ?? ""
            if let v = z2["volume"] as? Int {
                snap.zone2VolumeDB = scale.db(fromStep: v)
                lastZone2VolumeStep = v
            }
        }

        if snap.isPoweredOn, let tunerInputID, snap.input == tunerInputID,
           let play = try? await get("/tuner/getPlayInfo") {
            let bandName = play["band"] as? String ?? "fm"
            let band = TunerBand(rawValue: bandName.uppercased()) ?? .fm
            let detail = play[bandName] as? [String: Any] ?? [:]
            snap.tunerFetched = true
            snap.tunerBand = band
            if let kHz = detail["freq"] as? Int, kHz > 0 {
                snap.tunerFrequency = Self.frequencyString(kHz: kHz, band: band)
            }
            snap.tunerPreset = detail["preset"] as? Int ?? 0
            if presetBandMode == "separate", band == .am, snap.tunerPreset > 0 { snap.tunerPreset += 1000 }
        }

        let key = "\(snap.isPoweredOn)|\(snap.volumeDB)|\(snap.input)|\(snap.isMuted)|\(snap.soundProgram)|\(snap.pureDirect)"
        let changed = key != lastChangeKey
        lastChangeKey = key
        continuation?.yield(snap)
        return (true, changed)
    }

    // MARK: - HTTP

    private func get(_ path: String) async throws -> [String: Any] {
        try await Self.getJSON(host: host, path: base + path, timeout: 5)
    }

    /// 操作を送り、response_code が 0 でなければ `YamahaError.rejected` を投げる
    private func command(_ path: String) async throws {
        let json = try await get(path)
        let code = json["response_code"] as? Int ?? -1
        guard code == 0 else { throw YamahaError.rejected(code) }
        noteActivity()
    }

    private static func getJSON(host: String, path: String, timeout: Int) async throws -> [String: Any] {
        let res = try await LocalHTTP.get(host: host, port: port, path: path, timeout: timeout)
        guard res.status == 200,
              let object = try? JSONSerialization.jsonObject(with: res.body) as? [String: Any]
        else { throw YamahaError.badResponse }
        return object
    }

    // MARK: - Parsing helpers

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func numberString(_ any: Any?) -> String {
        guard let d = number(any) else { return "" }
        return String(format: "%.2f", d)
    }

    private static func tag(_ name: String, in xml: String, from start: String.Index) -> String? {
        guard let open = xml.range(of: "<\(name)>", range: start..<xml.endIndex),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
    }

    /// kHz を表示用の文字列にする（FM は MHz。87.5 → "87.5"、87.55 → "87.55"）
    static func frequencyString(kHz: Int, band: TunerBand) -> String {
        guard band == .fm else { return String(kHz) }
        return kHz % 100 == 0 ? String(format: "%.1f", Double(kHz) / 1000) : String(format: "%.2f", Double(kHz) / 1000)
    }
}
