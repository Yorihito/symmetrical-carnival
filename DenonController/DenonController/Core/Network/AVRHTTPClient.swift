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
}

// MARK: - AVRHTTPClient

/// Denon AVR-X3800H の HTTP API（ポート 8080）を制御する。
///
/// URLSession / NWConnection はどちらも「インターネット到達性チェック」を行い、
/// 有線 + WiFi 混在の Mac 環境でローカル WiFi への接続に失敗することがある。
/// そのため curl と同じ BSD ソケット API を直接使用し、
/// OS ルーティングテーブル通りに接続する。
actor AVRHTTPClient {

    nonisolated let updates: AsyncStream<AVRStatusSnapshot>
    private nonisolated let continuation: AsyncStream<AVRStatusSnapshot>.Continuation

    private var host: String = ""
    private var port: Int    = 8080
    private var pollTask: Task<Void, Never>?

    init() {
        let (stream, cont) = AsyncStream<AVRStatusSnapshot>.makeStream()
        updates = stream
        continuation = cont
    }

    deinit { continuation.finish() }

    // MARK: - Connect

    func connect(
        host: String,
        port: Int = 8080,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> DeviceInfo {
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
        startPolling()
        return info
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

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
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
        continuation.yield(snap)
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
    /// 有線 + WiFi 混在環境で正しいインターフェース（WiFi 側）を選択するために使う。
    private static func interfaceIndex(forTargetIP targetIP: in_addr_t) -> UInt32? {
        var ifList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifList) == 0 else { return nil }
        defer { freeifaddrs(ifList) }

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
                return if_nametoindex(p.pointee.ifa_name)
            }
        }
        return nil
    }

    /// ブロッキング BSD ソケットで HTTP/1.0 GET を実行する。
    /// IP_BOUND_IF でターゲットサブネットのインターフェースに固定し、
    /// マルチ NIC 環境でも正しいインターフェース経由で接続する。
    private static func bsdGETBlocking(host: String, port: Int, path: String) throws -> (Data, Int) {

        // ─── sockaddr_in を直接構築（IPv4 決め打ち）──────────────────────
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(port).bigEndian
        guard inet_aton(host, &addr.sin_addr) != 0 else {
            throw AVRError.connectionFailed("無効な IP アドレス: \(host)")
        }
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
