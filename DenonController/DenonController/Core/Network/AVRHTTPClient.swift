import Foundation
import Darwin   // BSD socket APIs — curl と同じレイヤーで接続する

// MARK: - Errors

enum AVRError: LocalizedError, Sendable {
    case notConnected
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:              String(localized: "AVR に接続されていません")
        case .connectionFailed(let msg): "\(String(localized: "接続失敗")): \(msg)"
        }
    }
}

// MARK: - HTTP Status Snapshot

struct AVRStatusSnapshot: Sendable {
    var isPoweredOn:  Bool   = false
    var volumeDB:     Double = -60.0
    var isMuted:      Bool   = false
    var inputCode:    String = ""

    var zone2Power:    Bool   = false
    var zone2VolumeDB: Double = -40.0
    var zone2Muted:    Bool   = false
    var zone2InputCode: String = ""

    // Tuner（TUNER 入力選択中のみ有効）
    var tunerDataFetched: Bool   = false   // チューナー XML を実際に取得できたときのみ true
    var tunerBand:        String = "FM"
    var tunerFrequency:   String = ""
    var tunerPreset:      Int    = 0
    var tunerStationName: String = ""
}

// MARK: - AVRHTTPClient

/// Denon AVR-X3800H の HTTP API（ポート 8080）を制御する。
///
/// URLSession / NWConnection はどちらも「インターネット到達性チェック」を行い、
/// 有線 + WiFi 混在の Mac 環境でローカル WiFi への接続に失敗することがある。
/// そのため curl と同じ BSD ソケット API を直接使用し、
/// OS ルーティングテーブル通りに接続する。
actor AVRHTTPClient {

    private var host: String = ""
    private var port: Int    = 8080
    private var pollTask: Task<Void, Never>?
    private var currentContinuation: AsyncStream<AVRStatusSnapshot>.Continuation?

    init() {
        print("[DenonLog] AVRHTTPClient.init")
    }

    deinit {
        print("[DenonLog] AVRHTTPClient.deinit")
        currentContinuation?.finish()
    }

    // MARK: - Connect

    func connect(
        host: String,
        port: Int = 8080,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> (DeviceInfo, AsyncStream<AVRStatusSnapshot>) {
        self.host = host
        self.port = port

        onProgress?("TCP 接続中 (\(host))...")
        let (data, status) = try await bsdGET(path: "/goform/Deviceinfo.xml",
                                              host: host, port: port)

        onProgress?("デバイス確認中...")
        guard status == 200 else {
            throw AVRError.connectionFailed("AVR から正常応答がありません (HTTP \(status))")
        }

        // デバイス情報を解析
        let info = parseDeviceInfo(data: data, host: host, port: port)

        onProgress?("ポーリング開始...")
        let stream = startPolling()
        return (info, stream)
    }

    /// Deviceinfo.xml からモデル名・ブランド・ゾーン数を解析する
    private func parseDeviceInfo(data: Data, host: String, port: Int) -> DeviceInfo {
        guard let xml = String(data: data, encoding: .utf8) else { return .unknown }

        var info = DeviceInfo()

        // モデル名（例: <ModelName>AVR-X3800H</ModelName>）
        if let v = simpleXML(in: xml, tag: "ModelName"), !v.isEmpty { info.modelName = v }
        if info.modelName.isEmpty,
           let v = simpleXML(in: xml, tag: "ManualModelName"), !v.isEmpty { info.modelName = v }

        // ブランド（BrandCode: 0=Denon, 1=Marantz）
        if let code = simpleXML(in: xml, tag: "BrandCode") {
            info.brandName = code == "1" ? "Marantz" : "Denon"
        }

        // カテゴリ（例: <CategoryName>AV RECEIVER</CategoryName>）
        if let v = simpleXML(in: xml, tag: "CategoryName"), !v.isEmpty { info.categoryName = v }

        // ゾーン数（DeviceZones）
        if let z = simpleXML(in: xml, tag: "DeviceZones"), let n = Int(z) {
            info.hasZone2 = n >= 1
        }

        // Zone 3 は XML に明示されないため、Zone3 ステータス XML が返るか試す
        // 同期的に確認するため Task.detached を使わず、フラグは後で更新
        return info
    }

    /// Zone 3 対応確認（接続後に非同期で呼ぶ）
    func probeZone3() async -> Bool {
        guard !host.isEmpty else { return false }
        let (_, status) = (try? await bsdGET(
            path: "/goform/formZone3_Zone3XmlStatusLite.xml",
            host: host, port: port
        )) ?? (Data(), 0)
        return status == 200
    }

    /// タグ `<Tag>value</Tag>` を抽出する簡易パーサー
    private func simpleXML(in xml: String, tag: String) -> String? {
        guard let s = xml.range(of: "<\(tag)>"),
              let e = xml.range(of: "</\(tag)>", range: s.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[s.upperBound..<e.lowerBound])
    }

    /// チューナー XML 用パーサー。
    /// フラット形式 `<Band>FM</Band>` を優先し、
    /// 見つからなければネスト形式 `<Band><value>FM</value></Band>` も試みる。
    private func tunerXML(_ xml: String, _ tag: String) -> String? {
        simpleXML(in: xml, tag: tag) ?? xmlValue(in: xml, key: tag)
    }

    // MARK: - Send command

    func send(_ command: String) async {
        guard !host.isEmpty else { return }
        let enc = command.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? command
        _ = try? await bsdGET(path: "/goform/formiPhoneAppDirect.xml?\(enc)",
                              host: host, port: port)
    }

    // MARK: - Disconnect

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        host = ""
    }

    // MARK: - Polling

    private func startPolling() -> AsyncStream<AVRStatusSnapshot> {
        pollTask?.cancel()
        currentContinuation?.finish()
        
        let (stream, cont) = AsyncStream<AVRStatusSnapshot>.makeStream()
        self.currentContinuation = cont
        
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.poll()
                try? await Task.sleep(for: .seconds(1.5))
            }
            cont.finish()
        }
        return stream
    }

    private func poll() async {
        let h = host; let p = port
        async let mainXML  = try? bsdGET(path: "/goform/formMainZone_MainZoneXmlStatusLite.xml", host: h, port: p).0
        async let zone2XML = try? bsdGET(path: "/goform/formZone2_Zone2XmlStatusLite.xml",       host: h, port: p).0

        let (main, z2) = await (mainXML, zone2XML)
        var snap = AVRStatusSnapshot()

        if let data = main, let xml = String(data: data, encoding: .utf8) {
            snap.isPoweredOn = xmlValue(in: xml, key: "Power") == "ON"
            snap.volumeDB    = Double(xmlValue(in: xml, key: "MasterVolume") ?? "-60") ?? -60
            snap.isMuted     = xmlValue(in: xml, key: "Mute") == "on"
            snap.inputCode   = xmlValue(in: xml, key: "InputFuncSelect") ?? ""
        }
        if let data = z2, let xml = String(data: data, encoding: .utf8) {
            snap.zone2Power     = xmlValue(in: xml, key: "Power") == "ON"
            snap.zone2VolumeDB  = Double(xmlValue(in: xml, key: "MasterVolume") ?? "-40") ?? -40
            snap.zone2Muted     = xmlValue(in: xml, key: "Mute") == "on"
            snap.zone2InputCode = xmlValue(in: xml, key: "InputFuncSelect") ?? ""
        }

        // チューナー XML は TUNER 入力選択中のみ取得
        // チューナー XML は <Band>FM</Band> のフラット形式のため simpleXML を使用する
        if snap.inputCode.trimmingCharacters(in: .whitespaces) == "TUNER" && snap.isPoweredOn {
            if let (data, status) = try? await bsdGET(
                path: "/goform/formTuner_TunerXml.xml", host: h, port: p
            ), status == 200, let xml = String(data: data, encoding: .utf8) {
                snap.tunerDataFetched = true
                snap.tunerBand      = (tunerXML(xml, "Band") ?? "FM")
                    .trimmingCharacters(in: .whitespaces).uppercased()
                snap.tunerFrequency = tunerXML(xml, "Frequency") ?? ""
                let presetStr       = tunerXML(xml, "preset") ?? tunerXML(xml, "Preset") ?? "0"
                snap.tunerPreset    = Int(presetStr.trimmingCharacters(in: .whitespaces)) ?? 0
                snap.tunerStationName = (tunerXML(xml, "StationName") ?? "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        currentContinuation?.yield(snap)
    }

    // MARK: - Tuner Diagnostics

    /// チューナー関連エンドポイントの生レスポンスをすべて返す（デバッグ用）
    func fetchTunerDiagnostics() async -> String {
        guard !host.isEmpty else { return "未接続" }
        var out = ""

        // GET エンドポイント一覧
        let getPaths = [
            "/goform/formTuner_TunerXml.xml",
            "/goform/formTuner_TunerPresetXml.xml",
            "/goform/formMainZone_MainZoneXml.xml",
            "/goform/formMainZone_MainZoneXmlStatusLite.xml",
        ]
        for path in getPaths {
            out += "=== GET \(path) ===\n"
            if let (data, status) = try? await bsdGET(path: path, host: host, port: port) {
                out += "HTTP \(status)\n"
                let body = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? "(decode失敗)"
                // 長すぎる場合は先頭2000文字だけ
                out += body.count > 2000 ? String(body.prefix(2000)) + "\n...(省略)" : body
            } else {
                out += "(接続失敗)"
            }
            out += "\n\n"
        }

        // POST AppCommand.xml でチューナーステータスを取得
        out += "=== POST /goform/AppCommand.xml (GetTunerStatus) ===\n"
        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><tx><cmd id=\"1\">GetTunerStatus</cmd></tx>"
        if let (data, status) = try? await bsdPOST(
            path: "/goform/AppCommand.xml", host: host, port: port, body: body
        ) {
            out += "HTTP \(status)\n"
            out += String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? "(decode失敗)"
        } else {
            out += "(接続失敗)"
        }
        out += "\n"
        return out
    }

    // MARK: - Tuner Preset Fetch (XML one-shot)

    /// formTuner_TunerPresetXml.xml からプリセット一覧を一括取得する。
    /// 未使用スロット（周波数 "0.00" / 空）は除外して返す。
    /// 成功した場合は [TunerPreset]（空配列を含む）、XML が使えない場合は nil を返す。
    func fetchTunerPresetsFromXml() async -> [TunerPreset]? {
        guard !host.isEmpty else { return nil }
        guard let (data, status) = try? await bsdGET(
            path: "/goform/formTuner_TunerPresetXml.xml",
            host: host, port: port
        ), status == 200, let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        var presets: [TunerPreset] = []

        // フォーマット1: <PresetItem index="N">...</PresetItem>
        var searchRange = xml.startIndex..<xml.endIndex
        while let itemStart = xml.range(of: "<PresetItem", range: searchRange) {
            guard let itemEnd = xml.range(of: "</PresetItem>", range: itemStart.upperBound..<xml.endIndex) else { break }
            let itemXml = String(xml[itemStart.lowerBound..<itemEnd.upperBound])
            searchRange = itemEnd.upperBound..<xml.endIndex

            guard let idxStart = itemXml.range(of: "index=\""),
                  let idxEnd   = itemXml.range(of: "\"", range: idxStart.upperBound..<itemXml.endIndex),
                  let idx       = Int(itemXml[idxStart.upperBound..<idxEnd.lowerBound])
            else { continue }

            let freq = (simpleXML(in: itemXml, tag: "Frequency") ?? xmlValue(in: itemXml, key: "Frequency") ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard !freq.isEmpty && freq != "0.00" && freq != "0" else { continue }

            let bandStr = (simpleXML(in: itemXml, tag: "Band") ?? xmlValue(in: itemXml, key: "Band") ?? "FM")
                .trimmingCharacters(in: .whitespaces)
            let name = (simpleXML(in: itemXml, tag: "StationName") ?? xmlValue(in: itemXml, key: "StationName") ?? "")
                .trimmingCharacters(in: .whitespaces)

            let band = TunerBand(rawValue: bandStr.uppercased()) ?? .fm
            presets.append(TunerPreset(id: idx, band: band, frequency: freq, stationName: name))
        }

        // フォーマット2: <Band1>FM</Band1> <Frequency1>87.50</Frequency1> ...
        if presets.isEmpty {
            for i in 1...56 {
                let freq = (simpleXML(in: xml, tag: "Frequency\(i)") ?? "")
                    .trimmingCharacters(in: .whitespaces)
                guard !freq.isEmpty && freq != "0.00" && freq != "0" else { continue }
                let bandStr = (simpleXML(in: xml, tag: "Band\(i)") ?? "FM")
                    .trimmingCharacters(in: .whitespaces)
                let name = (simpleXML(in: xml, tag: "StationName\(i)") ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let band = TunerBand(rawValue: bandStr.uppercased()) ?? .fm
                presets.append(TunerPreset(id: i, band: band, frequency: freq, stationName: name))
            }
        }

        // XML は取得できたが解析できた場合のみ成功とみなす
        // （空配列 = 全スロット未使用として扱う）
        guard xml.contains("Frequency") || xml.contains("frequency") else { return nil }
        return presets
    }

    // MARK: - BSD Socket HTTP GET
    //
    // DispatchQueue.global() でブロッキング I/O を実行し、
    // CheckedContinuation で Swift async に橋渡しする。
    // これにより Apple 独自のネットワーク到達性チェックを完全に回避する。

    private func bsdGET(path: String, host: String, port: Int) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.bsdGETBlocking(host: host, port: port, path: path)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// ターゲット IP と同じサブネットを持つインターフェースのインデックスを返す。
    /// 複数マッチした場合はサブネットマスクが最も狭い（具体的な）ものを優先する。
    /// 例: en0(192.168.1.x/16) と en1(192.168.68.x/24) がともにマッチした場合、
    /// /24 のほうが具体的なため en1 を選択する。
    private static func interfaceIndex(forTargetIP targetIP: in_addr_t) -> UInt32? {
        var ifList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifList) == 0 else { return nil }
        defer { freeifaddrs(ifList) }

        var bestIdx: UInt32?
        var bestMask: UInt32 = 0   // host byte order で比較（大きいほど狭いサブネット）

        var ptr = ifList
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sa = p.pointee.ifa_addr,
                  sa.pointee.sa_family == sa_family_t(AF_INET),
                  let nm = p.pointee.ifa_netmask else { continue }

            let ifAddr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask   = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }

            if (ifAddr & mask) == (targetIP & mask) {
                let maskHBO = UInt32(bigEndian: mask)   // /24 → 0xFFFFFF00, /16 → 0xFFFF0000
                if maskHBO > bestMask {
                    bestMask = maskHBO
                    bestIdx = if_nametoindex(p.pointee.ifa_name)
                }
            }
        }
        return bestIdx
    }

    /// ブロッキング BSD ソケットで HTTP/1.0 GET を実行する。
    /// IP_BOUND_IF でターゲットサブネットのインターフェースに固定し、
    /// マルチ NIC 環境でも正しいインターフェース経由で接続する。
    private static func bsdGETBlocking(host: String, port: Int, path: String) throws -> (Data, Int) {

        // ─── ホスト名または IP を解決 ─────────────────────────────────────
        var hints = addrinfo(ai_flags: AI_DEFAULT, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var resPtr: UnsafeMutablePointer<addrinfo>?
        let gaiRet = getaddrinfo(host, String(port), &hints, &resPtr)
        guard gaiRet == 0, let first = resPtr else {
            throw AVRError.connectionFailed("アドレス解決失敗 (\(host)): \(gaiRet)")
        }
        defer { freeaddrinfo(resPtr) }
        
        let targetAddrIn = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var addr = targetAddrIn
        addr.sin_port = in_port_t(port).bigEndian
        let targetIP = addr.sin_addr.s_addr

        // ─── ソケット作成 ─────────────────────────────────────────────────
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw AVRError.connectionFailed("socket() 失敗 errno=\(errno)")
        }
        defer { Darwin.close(fd) }

        // ─── インターフェース固定（マルチ NIC 対策）─────────────────────
        if var ifIdx = interfaceIndex(forTargetIP: targetIP), ifIdx > 0 {
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF,
                       &ifIdx, socklen_t(MemoryLayout<UInt32>.size))
        }

        // ─── タイムアウト設定 ────────────────────────────────────────────
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // ─── 接続 ────────────────────────────────────────────────────────
        let connectRet = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectRet == 0 else {
            throw AVRError.connectionFailed(
                "\(host):\(port) — \(String(cString: strerror(errno)))"
            )
        }

        // ─── HTTP リクエスト送信 ─────────────────────────────────────────
        let req = "GET \(path) HTTP/1.0\r\nHost: \(host)\r\nAccept: */*\r\nConnection: close\r\n\r\n"
        let reqBytes = Array(req.utf8)
        let sent = Darwin.send(fd, reqBytes, reqBytes.count, 0)
        guard sent == reqBytes.count else {
            throw AVRError.connectionFailed("HTTP リクエスト送信失敗")
        }

        // ─── レスポンス受信 ──────────────────────────────────────────────
        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buf[0..<n])
        }

        // ─── HTTP ステータスコード抽出 ───────────────────────────────────
        guard
            let text      = String(data: responseData, encoding: .utf8)
                            ?? String(data: responseData, encoding: .isoLatin1),
            let firstLine = text.components(separatedBy: "\r\n").first,
            let statusStr = firstLine.components(separatedBy: " ").dropFirst().first,
            let status    = Int(statusStr)
        else {
            throw AVRError.connectionFailed("HTTP レスポンス解析失敗")
        }

        // ヘッダーを除いたボディ部分を返す
        let body: Data
        if let r = text.range(of: "\r\n\r\n") {
            body = Data(text[r.upperBound...].utf8)
        } else {
            body = responseData
        }
        return (body, status)
    }

    // MARK: - BSD Socket HTTP POST

    private func bsdPOST(path: String, host: String, port: Int, body: String) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.bsdPOSTBlocking(host: host, port: port, path: path, body: body)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func bsdPOSTBlocking(host: String, port: Int, path: String, body: String) throws -> (Data, Int) {
        // ─── ホスト名または IP を解決 ─────────────────────────────────────
        var hints = addrinfo(ai_flags: AI_DEFAULT, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var resPtr: UnsafeMutablePointer<addrinfo>?
        let gaiRet = getaddrinfo(host, String(port), &hints, &resPtr)
        guard gaiRet == 0, let first = resPtr else {
            throw AVRError.connectionFailed("アドレス解決失敗 (\(host)): \(gaiRet)")
        }
        defer { freeaddrinfo(resPtr) }
        
        let targetAddrIn = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var addr = targetAddrIn
        addr.sin_port = in_port_t(port).bigEndian
        let targetIP = addr.sin_addr.s_addr

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw AVRError.connectionFailed("socket() 失敗") }
        defer { Darwin.close(fd) }

        if var ifIdx = interfaceIndex(forTargetIP: targetIP), ifIdx > 0 {
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIdx, socklen_t(MemoryLayout<UInt32>.size))
        }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let connectRet = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectRet == 0 else {
            throw AVRError.connectionFailed("\(host):\(port) — \(String(cString: strerror(errno)))")
        }

        let bodyBytes = Array(body.utf8)
        let req = "POST \(path) HTTP/1.0\r\nHost: \(host)\r\nContent-Type: text/xml\r\nContent-Length: \(bodyBytes.count)\r\nConnection: close\r\n\r\n"
        let reqBytes = Array(req.utf8) + bodyBytes
        guard Darwin.send(fd, reqBytes, reqBytes.count, 0) == reqBytes.count else {
            throw AVRError.connectionFailed("POST 送信失敗")
        }

        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buf[0..<n])
        }

        guard let text      = String(data: responseData, encoding: .utf8)
                              ?? String(data: responseData, encoding: .isoLatin1),
              let firstLine = text.components(separatedBy: "\r\n").first,
              let statusStr = firstLine.components(separatedBy: " ").dropFirst().first,
              let status    = Int(statusStr)
        else { throw AVRError.connectionFailed("POST レスポンス解析失敗") }

        let respBody: Data
        if let r = text.range(of: "\r\n\r\n") {
            respBody = Data(text[r.upperBound...].utf8)
        } else {
            respBody = responseData
        }
        return (respBody, status)
    }

    // MARK: - XML Parser

    private func xmlValue(in xml: String, key: String) -> String? {
        guard
            let keyStart = xml.range(of: "<\(key)>"),
            let valStart = xml.range(of: "<value>",  range: keyStart.upperBound..<xml.endIndex),
            let valEnd   = xml.range(of: "</value>", range: valStart.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[valStart.upperBound..<valEnd.lowerBound])
    }
}
