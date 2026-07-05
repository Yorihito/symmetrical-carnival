@preconcurrency import Foundation
import Observation
import Darwin
import Network

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Sendable {
    let id: String      // IP アドレス（ユニークキー）
    let name: String    // Deviceinfo.xml から取得したモデル名
    let host: String    // IPv4 アドレス
    let port: Int       // 接続用ポート (8080, 10101 等)
    let macAddress: String  // DHCP で IP が変わっても同一機体か判定するための安定 ID（取得できない場合は空）
}

// MARK: - MDNSDiscovery

/// Denon / HEOS デバイスを LAN 上で検出する。
/// iOSの実機で動作させるため、BSD ソケットではなく NetServiceBrowser (Bonjour) を使用します。
@Observable
@MainActor
final class MDNSDiscovery {

    var devices: [DiscoveredDevice] = []
    var isSearching = false
    var scanLog: [String] = []   // 診断ログ

    private var scanTask: Task<Void, Never>?

    func start() {
        guard !isSearching else { return }
        isSearching = true
        devices = []
        scanLog = []

        scanTask = Task { [weak self] in
            let (found, log) = await MDNSScanner.scan()
            await MainActor.run { [weak self] in
                self?.devices = found
                self?.scanLog = log
                self?.isSearching = false
            }
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        isSearching = false
    }
}

// MARK: - MDNSScanner

@MainActor
enum MDNSScanner {
    static func scan() async -> (devices: [DiscoveredDevice], log: [String]) {
        var log: [String] = []
        log.append("Starting NWBrowser scan...")

        let (pairs, innerLog): ([(String, String, Int)], [String]) = await withCheckedContinuation { cont in
            let scanner = NWDiscoveryScanner()
            scanner.start(timeout: 5.0) { results, innerLog in
                _ = scanner // keep alive
                cont.resume(returning: (results, innerLog))
            }
        }

        log.append(contentsOf: innerLog)
        log.append("Bonjour resolved devices: \(pairs.count)")
        
        // HTTP で Denon デバイスか確認してデバイス情報を取得
        var seen = Set<String>()
        var devices: [DiscoveredDevice] = []
        await withTaskGroup(of: (DiscoveredDevice?, String).self) { group in
            for (ip, hint, port) in pairs where !ip.isEmpty && !seen.contains(ip) {
                seen.insert(ip)
                group.addTask { await verifyDenon(ip: ip, nameHint: hint, port: port) }
            }
            for await (d, verifyLog) in group {
                log.append(verifyLog)
                if let d { devices.append(d) }
            }
        }
        log.append("Verified Denon AVR devices: \(devices.count)")
        return (devices.sorted { $0.name < $1.name }, log)
    }

    // MARK: - HTTP 確認（Denon か検証、デバイス名取得）

    private static func verifyDenon(ip: String, nameHint: String, port: Int) async -> (DiscoveredDevice?, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: verifyDenonBlocking(ip: ip, nameHint: nameHint, port: port))
            }
        }
    }

    /// I/O を伴うため非隔離（MainActor 外）で実行する
    nonisolated private static func verifyDenonBlocking(ip: String, nameHint: String, port: Int) -> (DiscoveredDevice?, String) {
        print("[DenonLog] Verifying device: \(ip) (hint: \(nameHint), port: \(port))")
        var debugLog = "Verifying \(ip)..."
        
        // 試行するポートのリスト（Bonjour 通知ポートを最優先、次に 8080, 80）
        var portsToTry = [port]
        if !portsToTry.contains(8080) { portsToTry.append(8080) }
        if !portsToTry.contains(80)   { portsToTry.append(80) }

        for p in portsToTry {
            let result = tryVerify(ip: ip, port: p, nameHint: nameHint)
            if let device = result.0 {
                print("[DenonLog]   -> Success on port \(p)")
                return (device, debugLog + " " + result.1)
            }
            print("[DenonLog]   -> Port \(p) failed: \(result.1)")
            debugLog += " (p:\(p) failed: \(result.1))"
        }
        
        print("[DenonLog]   -> All ports failed for \(ip)")
        return (nil, debugLog)
    }

    nonisolated private static func tryVerify(ip: String, port: Int, nameHint: String) -> (DiscoveredDevice?, String) {
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(port).bigEndian

        var hints = addrinfo(ai_flags: AI_DEFAULT, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        let gaiRet = getaddrinfo(ip, String(port), &hints, &res)
        guard gaiRet == 0, let first = res else { return (nil, "DNS Error") }
        defer { freeaddrinfo(res) }
        let targetAddrIn = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        addr.sin_addr = targetAddrIn.sin_addr

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return (nil, "Socket Error") }
        defer { Darwin.close(fd) }

        #if os(iOS)
        if var ifIdx = interfaceIndex(forTargetIP: addr.sin_addr.s_addr), ifIdx > 0 {
            // iOS 実機ではインターフェースバインドが必須
            if setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIdx, socklen_t(MemoryLayout<UInt32>.size)) < 0 {
                print("[DenonLog]   ! Interface bind failed (ifIdx: \(ifIdx))")
            }
        }
        #endif

        let tv = timeval(tv_sec: 5, tv_usec: 0)
        withUnsafePointer(to: tv) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        let connectResult = withUnsafeMutablePointer(to: &addr) { sockaddrInPtr in
            sockaddrInPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            return (nil, "Connect timeout")
        }

        let req = "GET /goform/Deviceinfo.xml HTTP/1.0\r\nHost: \(ip)\r\nConnection: close\r\n\r\n"
        let reqBytes = Array(req.utf8)
        Darwin.send(fd, reqBytes, reqBytes.count, 0)

        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 2048)
        while responseData.count < 10000 {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buf[0..<n])
        }

        guard let text = String(data: responseData, encoding: .utf8) ?? String(data: responseData, encoding: .isoLatin1),
              text.contains("200 OK") else { return (nil, "No XML API") }

        let name = xmlValue(text, "FriendlyName") ?? xmlValue(text, "ModelName") ?? nameHint
        let mac = xmlValue(text, "MacAddress").map { DeviceInfo.normalizedMac($0) } ?? ""
        return (DiscoveredDevice(id: ip, name: name.isEmpty ? ip : name, host: ip, port: port, macAddress: mac), "OK")
    }

    nonisolated private static func xmlValue(_ text: String, _ tag: String) -> String? {
        guard let s = text.range(of: "<\(tag)>"),
              let e = text.range(of: "</\(tag)>", range: s.upperBound..<text.endIndex)
        else { return nil }
        let v = String(text[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    /// ターゲット IP と同じサブネットを持つインターフェースのインデックスを返す
    nonisolated private static func interfaceIndex(forTargetIP targetIP: in_addr_t) -> UInt32? {
        var ifList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifList) == 0 else { return nil }
        defer { freeifaddrs(ifList) }

        var bestIdx: UInt32?
        var bestMask: UInt32 = 0

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
                let maskHBO = UInt32(bigEndian: mask)
                if maskHBO > bestMask {
                    bestMask = maskHBO
                    if let ifName = p.pointee.ifa_name {
                        bestIdx = if_nametoindex(ifName)
                    }
                }
            }
        }
        return bestIdx
    }
}

// MARK: - NWDiscoveryScanner

@MainActor
private class NWDiscoveryScanner: NSObject {
    private let types = ["_denon-heos._tcp", "_heos-audio._tcp", "_http._tcp"]
    private var browsers: [NWBrowser] = []
    private var resolvedPairs: [String: (name: String, port: Int)] = [:] // IP -> (Name, Port)
    private var scanLog: [String] = []
    private var completion: (([(String, String, Int)], [String]) -> Void)?
    
    // アドレス解決のための NetService を保持
    private var resolvers: [NetService] = []

    func start(timeout: TimeInterval, completion: @escaping ([(String, String, Int)], [String]) -> Void) {
        self.completion = completion
        self.scanLog.append("Starting NWBrowsers...")
        
        for type in types {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: NWParameters.tcp)
            
            browser.stateUpdateHandler = { state in
                Task { @MainActor in
                    self.scanLog.append("  Browser (\(type)) state: \(state)")
                }
            }
            
            browser.browseResultsChangedHandler = { results, changes in
                Task { @MainActor in
                    for result in results {
                        if case let .service(name, serviceType, _, _) = result.endpoint {
                            self.handleDiscoveredService(name: name, type: serviceType)
                        }
                    }
                }
            }
            
            browser.start(queue: .main)
            browsers.append(browser)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            self.stopAndComplete()
        }
    }
    
    private func handleDiscoveredService(name: String, type: String) {
        // すでに解決中、または解決済みならスキップ
        if resolvers.contains(where: { $0.name == name }) || resolvedPairs.values.contains(where: { $0.name == name }) {
            return
        }
        
        scanLog.append("Found via NWBrowser: \(name) (\(type))")
        
        // IP を取得するために NetService で解決する
        let service = NetService(domain: "local.", type: type, name: name)
        service.delegate = self
        service.resolve(withTimeout: 4.0)
        resolvers.append(service)
    }
    
    private func stopAndComplete() {
        for browser in browsers { browser.cancel() }
        for res in resolvers { res.stop() }
        
        let results = resolvedPairs.map { ($0.key, $0.value.name, $0.value.port) }
        completion?(results, scanLog)
        completion = nil
    }
}

extension NWDiscoveryScanner: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let port = sender.port
        let addresses = sender.addresses ?? []
        
        Task { @MainActor in
            for data in addresses {
                var hostname = [CChar](repeating: 0, count: 1025)
                data.withUnsafeBytes { ptr in
                    guard let sockaddrPtr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                    if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                        let addrLen = socklen_t(data.count)
                        if getnameinfo(sockaddrPtr, addrLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = hostname.withUnsafeBufferPointer { bufPtr in
                                String(cString: bufPtr.baseAddress!)
                            }
                            // ホスト名 (.local) は不安定なことがあるため、常に IP アドレスを優先して解決済リストに入れる
                            resolvedPairs[ip] = (name: name, port: port)
                            scanLog.append("  -> Resolved \(name) -> \(ip):\(port)")
                        }
                    }
                }
            }
        }
    }
    
    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let name = sender.name
        Task { @MainActor in
            scanLog.append("Failed to resolve \(name)")
        }
    }
}
