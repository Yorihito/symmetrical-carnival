import Foundation

// MARK: - HTTP Status Snapshot

/// HTTP API のポーリングで得られる AVR の現在状態
struct AVRStatusSnapshot: Sendable {
    var isPoweredOn:  Bool   = false
    var volumeDB:     Double = -60.0   // 実際の dB 値（例: -30.0）
    var isMuted:      Bool   = false
    var inputCode:    String = ""      // "HDMI1", "AUX1" etc.

    var zone2Power:   Bool   = false
    var zone2VolumeDB: Double = -40.0
    var zone2Muted:   Bool   = false
    var zone2InputCode: String = ""
}

// MARK: - AVRHTTPClient

/// Denon AVR の HTTP REST API（ポート 8080）を使って制御する。
///
/// コマンド: GET /goform/formiPhoneAppDirect.xml?<COMMAND>
/// ステータス: GET /goform/form<Zone>_<Zone>XmlStatusLite.xml  （1.5秒ポーリング）
actor AVRHTTPClient {

    // MARK: Public stream

    nonisolated let updates: AsyncStream<AVRStatusSnapshot>
    private nonisolated let continuation: AsyncStream<AVRStatusSnapshot>.Continuation

    // MARK: Private state

    private var host: String = ""
    private var port: Int    = 8080
    private var pollTask: Task<Void, Never>?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 3
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    // MARK: Init / Deinit

    init() {
        let (stream, cont) = AsyncStream<AVRStatusSnapshot>.makeStream()
        updates = stream
        continuation = cont
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Connect

    /// AVR の到達確認をしてポーリングを開始する。
    func connect(host: String, port: Int = 8080) async throws {
        self.host = host
        self.port = port

        // 疎通確認
        guard let url = URL(string: "http://\(host):\(port)/goform/Deviceinfo.xml") else {
            throw AVRError.connectionFailed("不正なアドレスです")
        }

        let (_, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AVRError.connectionFailed("AVR から正常応答がありません")
        }

        startPolling()
    }

    // MARK: - Send command

    /// Denon コマンド文字列を送信する（例: "PWON", "MV50", "SIHDMI1"）
    func send(_ command: String) async {
        guard !host.isEmpty else { return }
        // スペースは %20 に変換する必要があるが、Denon コマンドには通常含まれない
        let encoded = command.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? command
        guard let url = URL(string: "http://\(host):\(port)/goform/formiPhoneAppDirect.xml?\(encoded)") else { return }
        _ = try? await session.data(from: url)
    }

    // MARK: - Disconnect

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        host = ""
    }

    // MARK: - Private polling

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
        async let mainXML = fetch(path: "/goform/formMainZone_MainZoneXmlStatusLite.xml")
        async let zone2XML = fetch(path: "/goform/formZone2_Zone2XmlStatusLite.xml")

        let (main, z2) = await (mainXML, zone2XML)

        var snap = AVRStatusSnapshot()

        if let xml = main {
            snap.isPoweredOn = value(in: xml, key: "Power") == "ON"
            snap.volumeDB    = Double(value(in: xml, key: "MasterVolume") ?? "-60") ?? -60
            snap.isMuted     = value(in: xml, key: "Mute") == "on"
            snap.inputCode   = value(in: xml, key: "InputFuncSelect") ?? ""
        }

        if let xml = z2 {
            snap.zone2Power    = value(in: xml, key: "Power") == "ON"
            snap.zone2VolumeDB = Double(value(in: xml, key: "MasterVolume") ?? "-40") ?? -40
            snap.zone2Muted    = value(in: xml, key: "Mute") == "on"
            snap.zone2InputCode = value(in: xml, key: "InputFuncSelect") ?? ""
        }

        continuation.yield(snap)
    }

    private func fetch(path: String) async -> String? {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { return nil }
        guard let data = try? await session.data(from: url).0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `<Key><value>TEXT</value></Key>` から TEXT を抽出する簡易パーサー
    private func value(in xml: String, key: String) -> String? {
        guard
            let keyStart  = xml.range(of: "<\(key)>"),
            let valStart  = xml.range(of: "<value>",  range: keyStart.upperBound..<xml.endIndex),
            let valEnd    = xml.range(of: "</value>", range: valStart.upperBound..<xml.endIndex)
        else { return nil }
        return String(xml[valStart.upperBound..<valEnd.lowerBound])
    }
}
