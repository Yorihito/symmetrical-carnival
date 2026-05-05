@preconcurrency import Foundation
import Observation
import Darwin

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Sendable {
    let id: String      // IP アドレス（ユニークキー）
    let name: String    // Deviceinfo.xml から取得したモデル名
    let host: String    // IPv4 アドレス
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

enum MDNSScanner {
    @MainActor
    static func scan() async -> (devices: [DiscoveredDevice], log: [String]) {
        var log: [String] = []
        log.append("Starting Bonjour network scan...")

        let (pairs, innerLog): ([(String, String)], [String]) = await withCheckedContinuation { cont in
            let scanner = NetServiceScanner()
            scanner.start(timeout: 7.0) { results, innerLog in
                _ = scanner // keep alive
                cont.resume(returning: (results, innerLog))
            }
        }

        log.append(contentsOf: innerLog)
        log.append("Bonjour resolved devices: \(pairs.count)")
        for (ip, name) in pairs { log.append("  IP: \(ip) name: \(name)") }

        // HTTP で Denon デバイスか確認してデバイス情報を取得
        var seen = Set<String>()
        var devices: [DiscoveredDevice] = []
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            for (ip, hint) in pairs where !ip.isEmpty && !seen.contains(ip) {
                seen.insert(ip)
                group.addTask { await verifyDenon(ip: ip, nameHint: hint) }
            }
            for await d in group {
                if let d { devices.append(d) }
            }
        }
        log.append("Verified Denon AVR devices: \(devices.count)")
        return (devices.sorted { $0.name < $1.name }, log)
    }

    // MARK: - HTTP 確認（Denon か検証、デバイス名取得）

    private static func verifyDenon(ip: String, nameHint: String) async -> DiscoveredDevice? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: verifyDenonBlocking(ip: ip, nameHint: nameHint))
            }
        }
    }

    /// I/O を伴うため非隔離（MainActor 外）で実行する
    nonisolated private static func verifyDenonBlocking(ip: String, nameHint: String) -> DiscoveredDevice? {
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(8080).bigEndian
        guard inet_aton(ip, &addr.sin_addr) != 0 else { return nil }

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let ret = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard ret == 0 else { return nil }

        let req = "GET /goform/Deviceinfo.xml HTTP/1.0\r\nHost: \(ip)\r\nAccept: */*\r\nConnection: close\r\n\r\n"
        let reqBytes = Array(req.utf8)
        guard Darwin.send(fd, reqBytes, reqBytes.count, 0) == reqBytes.count else { return nil }

        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            responseData.append(contentsOf: buf[0..<n])
        }

        guard let text = String(data: responseData, encoding: .utf8)
                      ?? String(data: responseData, encoding: .isoLatin1),
              text.contains("200") else { return nil }

        let name = xmlValue(text, "FriendlyName") ?? xmlValue(text, "ModelName") ?? nameHint
        return DiscoveredDevice(id: ip, name: name.isEmpty ? ip : name, host: ip)
    }

    private static func xmlValue(_ text: String, _ tag: String) -> String? {
        guard let s = text.range(of: "<\(tag)>"),
              let e = text.range(of: "</\(tag)>", range: s.upperBound..<text.endIndex)
        else { return nil }
        let v = String(text[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}

// MARK: - NetServiceScanner

@MainActor
private class NetServiceScanner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let types = ["_denon-heos._tcp", "_heos-audio._tcp", "_http._tcp"]
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var resolvedAddresses: [String: String] = [:] // IP -> Name
    private var scanLog: [String] = []
    
    private var completion: (([(String, String)], [String]) -> Void)?
    
    func start(timeout: TimeInterval, completion: @escaping ([(String, String)], [String]) -> Void) {
        self.completion = completion
        self.scanLog.append("Starting Bonjour browsers...")
        
        for (index, type) in types.enumerated() {
            // わずかに開始をずらして衝突を避ける
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                let browser = NetServiceBrowser()
                browser.delegate = self
                browser.schedule(in: .main, forMode: .default)
                // domain: "local." ではなく "" (default) を使用して互換性を高める
                browser.searchForServices(ofType: type, inDomain: "")
                self.browsers.append(browser)
                self.scanLog.append("  -> Browser for \(type) started")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            self.stopAndComplete()
        }
    }
    
    private func stopAndComplete() {
        for browser in browsers { browser.stop() }
        for service in services { service.stop() }
        
        let results = resolvedAddresses.map { ($0.key, $0.value) }
        completion?(results, scanLog)
        completion = nil
    }
    
    // @preconcurrency Foundation により警告抑制を試みる。
    // それでも出る場合は、MainActor.assumeIsolated を維持。
    nonisolated func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        MainActor.assumeIsolated {
            scanLog.append("Browser starting search...")
        }
    }
    
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        MainActor.assumeIsolated {
            scanLog.append("Browser failed to search: \(errorDict)")
        }
    }
    
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        MainActor.assumeIsolated {
            let name = service.name
            let type = service.type
            scanLog.append("Found service: [\(name)] type: [\(type)]")

            let nameLower = name.lowercased()
            let typeLower = type.lowercased()
            let isDenon = typeLower.contains("denon") || typeLower.contains("heos") || 
                          nameLower.contains("denon") || nameLower.contains("heos") || nameLower.contains("marantz")
            
            if isDenon || typeLower.contains("http") {
                scanLog.append("  -> Candidate for resolution: \(name)")
                services.append(service)
                service.delegate = self
                service.schedule(in: .main, forMode: .default)
                service.resolve(withTimeout: 4.0)
            }
        }
    }
    
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        MainActor.assumeIsolated {
            guard let addresses = sender.addresses else { 
                scanLog.append("  -> Resolved \(sender.name) but no addresses found.")
                return 
            }
            for data in addresses {
                var hostname = [CChar](repeating: 0, count: 1025)
                data.withUnsafeBytes { ptr in
                    guard let sockaddrPtr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                    if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                        if getnameinfo(sockaddrPtr, socklen_t(data.count), &hostname, socklen_t(hostname.count), nil, 0, 2) == 0 {
                            let ip = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                            resolvedAddresses[ip] = sender.name
                            scanLog.append("  -> IP Resolved: \(sender.name) -> \(ip)")
                        }
                    }
                }
            }
        }
    }
    
    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        MainActor.assumeIsolated {
            scanLog.append("Failed to resolve \(sender.name)")
        }
    }
}
