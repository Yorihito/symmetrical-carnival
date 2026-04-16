import Foundation
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
///
/// NWBrowser は Apple のネットワーク到達性チェックにより
/// インターネット未接続の WiFi では動作しないため、
/// BSD ソケットで直接 mDNS UDP パケットを送受信する。
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

    // MARK: Interface info

    struct InterfaceInfo {
        let name: String
        let ifIndex: UInt32
        let ip: in_addr_t    // ネットワークバイトオーダー
    }

    // MARK: - Entry point

    static func scan() async -> (devices: [DiscoveredDevice], log: [String]) {
        let interfaces = ipv4Interfaces()
        var log: [String] = []

        log.append("Interfaces: \(interfaces.count)")
        for iface in interfaces {
            var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = iface.ip
            inet_ntop(AF_INET, &addr, &ipStr, socklen_t(INET_ADDRSTRLEN))
            log.append("  \(iface.name): \(String(cString: ipStr))")
        }

        // 全インターフェースに PTR クエリを送り、応答を収集
        let (pairs, scanLog) = await withCheckedContinuation { (cont: CheckedContinuation<([(ip: String, name: String)], [String]), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var innerLog: [String] = []
                let result = mdnsScanBlocking(interfaces: interfaces, timeout: 3.0, log: &innerLog)
                cont.resume(returning: (result, innerLog))
            }
        }
        log.append(contentsOf: scanLog)
        log.append("mDNS responses: \(pairs.count)")
        for (ip, name) in pairs { log.append("  IP:\(ip) name:\(name)") }

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
        log.append("Verified devices: \(devices.count)")
        return (devices.sorted { $0.name < $1.name }, log)
    }

    // MARK: - mDNS スキャン（ブロッキング）

    /// インターフェースごとに個別ソケットを作成し、IP_BOUND_IF で固定して送受信する。
    /// IP_MULTICAST_IF はマルチキャストルートが必要で EHOSTUNREACH になることがあるため、
    /// TCP クライアントと同じ IP_BOUND_IF 方式を使う。
    private static func mdnsScanBlocking(
        interfaces: [InterfaceInfo], timeout: Double, log: inout [String]
    ) -> [(ip: String, name: String)] {

        let serviceTypes = [
            "_denon-heos._tcp.local",
            "_heos-audio._tcp.local",
            "_http._tcp.local",
        ]
        let queries = serviceTypes.map { buildPTRQuery(service: $0) }

        var dest = sockaddr_in()
        dest.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port   = in_port_t(5353).bigEndian
        inet_aton("224.0.0.251", &dest.sin_addr)

        // インターフェースごとにソケットを作成
        var activeSockets: [(fd: Int32, name: String)] = []
        var sentCount = 0

        for iface in interfaces {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else {
                log.append("  socket(\(iface.name)) failed errno=\(errno)")
                continue
            }

            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

            // TCP と同じく IP_BOUND_IF でインターフェース固定（マルチキャストルート不要）
            var ifIdx = iface.ifIndex
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIdx, socklen_t(MemoryLayout<UInt32>.size))

            // INADDR_ANY:5353 にバインド
            var bindAddr = sockaddr_in()
            bindAddr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
            bindAddr.sin_family = sa_family_t(AF_INET)
            bindAddr.sin_port   = in_port_t(5353).bigEndian
            bindAddr.sin_addr.s_addr = INADDR_ANY
            let bindRet = withUnsafePointer(to: bindAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            log.append("bind(\(iface.name):5353) → \(bindRet == 0 ? "OK" : "failed errno=\(errno)")")

            // マルチキャストグループに参加（受信用）
            var mreq = ip_mreq()
            mreq.imr_multiaddr.s_addr = inet_addr("224.0.0.251")
            mreq.imr_interface.s_addr = iface.ip
            let joinRet = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP,
                                     &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
            log.append("  multicast join \(iface.name) → \(joinRet == 0 ? "OK" : "failed errno=\(errno)")")

            // クエリ送信
            var ok = false
            for q in queries {
                let sent = withUnsafePointer(to: dest) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, q, q.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if sent > 0 { ok = true }
            }
            log.append("  sendto \(iface.name) → \(ok ? "OK" : "failed errno=\(errno)")")

            if ok {
                sentCount += 1
                // 短い受信タイムアウト（全ソケットをラウンドロビンでポーリング）
                var tv = timeval(tv_sec: 0, tv_usec: 100_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                activeSockets.append((fd: fd, name: iface.name))
            } else {
                Darwin.close(fd)
            }
        }
        log.append("Sent OK: \(sentCount)/\(interfaces.count) interfaces")
        defer { for s in activeSockets { Darwin.close(s.fd) } }

        guard !activeSockets.isEmpty else {
            log.append("Total packets received: 0")
            log.append("PTR records: none (send failed)")
            log.append("Denon candidates: 0")
            return []
        }

        // 全ソケットをラウンドロビンで受信（deadline まで）
        var results: [(String, String)] = []
        var rawPackets = 0
        var allPTRs: [String] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            for (fd, _) in activeSockets {
                let n = Darwin.recv(fd, &buf, buf.count, 0)
                if n > 0 {
                    rawPackets += 1
                    let pkt = Array(buf[0..<n])
                    let (denonPairs, ptrs) = parseDNSPacketVerbose(pkt)
                    results.append(contentsOf: denonPairs)
                    allPTRs.append(contentsOf: ptrs)
                }
            }
        }
        log.append("Total packets received: \(rawPackets)")
        if allPTRs.isEmpty {
            log.append("PTR records: none (Denon may not be responding to mDNS)")
        } else {
            log.append("Found PTR records:")
            for ptr in allPTRs { log.append("  \(ptr)") }
        }
        log.append("Denon candidates: \(results.count)")
        return results
    }

    // MARK: - DNS パケット構築

    private static func buildPTRQuery(service: String = "_denon-heos._tcp.local") -> [UInt8] {
        var pkt: [UInt8] = [
            0x00, 0x00,  // ID（mDNS は 0）
            0x00, 0x00,  // Flags: 標準クエリ
            0x00, 0x01,  // QDCOUNT = 1
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // AN/NS/AR = 0
        ]
        pkt += encodeDNSName(service)
        pkt += [0x00, 0x0C, 0x00, 0x01]  // TYPE=PTR, CLASS=IN
        return pkt
    }

    private static func encodeDNSName(_ name: String) -> [UInt8] {
        var r: [UInt8] = []
        for label in name.split(separator: ".") {
            let b = Array(label.utf8)
            r.append(UInt8(b.count))
            r += b
        }
        r.append(0)
        return r
    }

    // MARK: - DNS レスポンス解析

    /// パケットを解析し、(Denon候補ペア, 全PTR名リスト) を返す。
    private static func parseDNSPacketVerbose(_ pkt: [UInt8]) -> ([(ip: String, name: String)], [String]) {
        guard pkt.count >= 12 else { return ([], []) }

        // mDNS クエリ（QR=0）は無視、レスポンス（QR=1）のみ処理
        guard pkt[2] & 0x80 != 0 else { return ([], []) }

        let qdcount = u16(pkt, 4)
        let ancount = u16(pkt, 6)
        let nscount = u16(pkt, 8)
        let arcount = u16(pkt, 10)

        var pos = 12
        for _ in 0..<qdcount {
            pos = skipName(pkt, pos: pos)
            pos += 4
            guard pos <= pkt.count else { return ([], []) }
        }

        var ptrNames: [String] = []
        var aIPs: [String] = []
        var allPTRs: [String] = []   // 全サービス名（診断用）

        for _ in 0..<(ancount + nscount + arcount) {
            pos = skipName(pkt, pos: pos)
            guard pos + 10 <= pkt.count else { break }

            let rrType = u16(pkt, pos)
            pos += 8  // TYPE(2) + CLASS(2) + TTL(4)
            let rdlen = u16(pkt, pos)
            pos += 2
            let rdEnd = pos + rdlen
            guard rdEnd <= pkt.count else { break }

            switch rrType {
            case 12:  // PTR
                let fullName = readName(pkt, pos: pos)
                allPTRs.append(fullName)
                // Denon/HEOS 関連サービスの場合のみデバイス名として保持
                let isDenonService = fullName.contains("denon") || fullName.contains("heos") || fullName.contains("Denon")
                if isDenonService {
                    if let dot = fullName.firstIndex(of: ".") {
                        let inst = String(fullName[..<dot])
                        if !inst.isEmpty { ptrNames.append(inst) }
                    } else if !fullName.isEmpty {
                        ptrNames.append(fullName)
                    }
                }
            case 1 where rdlen == 4:  // A
                let ip = "\(pkt[pos]).\(pkt[pos+1]).\(pkt[pos+2]).\(pkt[pos+3])"
                aIPs.append(ip)
            default:
                break
            }
            pos = rdEnd
        }

        // Denon関連PTRが見つかった場合はそのIPを返す、
        // そうでなければ全PTRのみ診断用に返す
        let pairs: [(String, String)]
        if !ptrNames.isEmpty && !aIPs.isEmpty {
            let name = ptrNames.first ?? ""
            pairs = aIPs.map { ($0, name) }
        } else {
            pairs = []
        }
        return (pairs, allPTRs)
    }

    private static func u16(_ d: [UInt8], _ i: Int) -> Int {
        guard i + 1 < d.count else { return 0 }
        return Int(d[i]) << 8 | Int(d[i + 1])
    }

    private static func skipName(_ d: [UInt8], pos: Int) -> Int {
        var p = pos
        while p < d.count {
            let len = Int(d[p])
            if len == 0 { return p + 1 }
            if len & 0xC0 == 0xC0 { return p + 2 }
            p += 1 + len
        }
        return p
    }

    private static func readName(_ d: [UInt8], pos: Int) -> String {
        var p = pos
        var labels: [String] = []
        var jumped = false

        while p < d.count {
            let len = Int(d[p])
            if len == 0 { break }
            if len & 0xC0 == 0xC0 {
                guard p + 1 < d.count else { break }
                let offset = ((len & 0x3F) << 8) | Int(d[p + 1])
                if !jumped { jumped = true }
                p = offset
                continue
            }
            p += 1
            guard p + len <= d.count else { break }
            labels.append(String(bytes: d[p..<(p + len)], encoding: .utf8) ?? "")
            p += len
        }
        return labels.joined(separator: ".")
    }

    // MARK: - HTTP 確認（Denon か検証、デバイス名取得）

    private static func verifyDenon(ip: String, nameHint: String) async -> DiscoveredDevice? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: verifyDenonBlocking(ip: ip, nameHint: nameHint))
            }
        }
    }

    private static func verifyDenonBlocking(ip: String, nameHint: String) -> DiscoveredDevice? {
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

        if var ifIdx = interfaceIndex(forTargetIP: addr.sin_addr.s_addr), ifIdx > 0 {
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifIdx, socklen_t(MemoryLayout<UInt32>.size))
        }

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

    // MARK: - ユーティリティ

    static func ipv4Interfaces() -> [InterfaceInfo] {
        var result: [InterfaceInfo] = []
        var ifList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifList) == 0 else { return [] }
        defer { freeifaddrs(ifList) }

        var seen = Set<String>()
        var ptr = ifList
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let sa = p.pointee.ifa_addr,
                  sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = String(cString: p.pointee.ifa_name)
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let idx = if_nametoindex(p.pointee.ifa_name)
            let ifIP = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            if idx > 0 {
                result.append(InterfaceInfo(name: name, ifIndex: idx, ip: ifIP))
            }
        }
        return result
    }

    private static func interfaceIndex(forTargetIP targetIP: in_addr_t) -> UInt32? {
        var ifList: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifList) == 0 else { return nil }
        defer { freeifaddrs(ifList) }

        var bestIdx: UInt32?
        var bestMask: UInt32 = 0
        var ptr = ifList
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let sa = p.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  let nm = p.pointee.ifa_netmask else { continue }
            let ifAddr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask   = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            if (ifAddr & mask) == (targetIP & mask) {
                let maskHBO = UInt32(bigEndian: mask)
                if maskHBO > bestMask {
                    bestMask = maskHBO
                    bestIdx = if_nametoindex(p.pointee.ifa_name)
                }
            }
        }
        return bestIdx
    }

    private static func xmlValue(_ text: String, _ tag: String) -> String? {
        guard let s = text.range(of: "<\(tag)>"),
              let e = text.range(of: "</\(tag)>", range: s.upperBound..<text.endIndex)
        else { return nil }
        let v = String(text[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
