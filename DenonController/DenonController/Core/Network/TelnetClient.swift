import Foundation
import Darwin

// MARK: - TelnetClient
//
// NWConnection はローカル WiFi 専用ネットワークで「インターネット到達性チェック」に
// 失敗するため、AVRHTTPClient と同じく BSD ソケットで直接接続する。

actor TelnetClient {

    // MARK: Public stream

    nonisolated let updates: AsyncStream<String>
    private nonisolated let continuation: AsyncStream<String>.Continuation

    // MARK: Private state

    private var fd: Int32 = -1
    private var receiveTask: Task<Void, Never>?

    // MARK: Init / Deinit

    init() {
        let (stream, cont) = AsyncStream<String>.makeStream()
        updates = stream
        continuation = cont
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
        continuation.finish()
    }

    // MARK: - Connect

    func connect(host: String, port: UInt16 = 23) async throws {
        await internalDisconnect()

        // sockaddr_in を構築
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(port).bigEndian
        guard inet_aton(host, &addr.sin_addr) != 0 else {
            throw AVRError.connectionFailed("無効な IP アドレス: \(host)")
        }

        let newFd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard newFd >= 0 else {
            throw AVRError.connectionFailed("socket() 失敗 errno=\(errno)")
        }

        // マルチ NIC 対策: ターゲットと同じサブネットの IF に固定
        if var ifIdx = Self.interfaceIndex(forTargetIP: addr.sin_addr.s_addr), ifIdx > 0 {
            setsockopt(newFd, IPPROTO_IP, IP_BOUND_IF, &ifIdx, socklen_t(MemoryLayout<UInt32>.size))
        }

        // 接続タイムアウト 5 秒
        var tvSend = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(newFd, SOL_SOCKET, SO_SNDTIMEO, &tvSend, socklen_t(MemoryLayout<timeval>.size))

        let ret = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = withUnsafePointer(to: addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(newFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if r == 0 {
                    cont.resume(returning: r)
                } else {
                    Darwin.close(newFd)
                    cont.resume(throwing: AVRError.connectionFailed(
                        "Telnet 接続失敗 \(host):23 — \(String(cString: strerror(errno)))"
                    ))
                }
            }
        }
        _ = ret

        // 受信タイムアウト: 100 ms（recv がブロックしすぎない）
        var tvRecv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(newFd, SOL_SOCKET, SO_RCVTIMEO, &tvRecv, socklen_t(MemoryLayout<timeval>.size))

        fd = newFd
        startReceiving()
    }

    // MARK: - Send

    func send(_ command: String) async throws {
        guard fd >= 0 else { throw AVRError.notConnected }
        let bytes = Array((command + "\r").utf8)
        let currentFd = fd
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let sent = Darwin.send(currentFd, bytes, bytes.count, 0)
                if sent == bytes.count {
                    cont.resume()
                } else {
                    cont.resume(throwing: AVRError.connectionFailed("Telnet 送信失敗"))
                }
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        await internalDisconnect()
    }

    private func internalDisconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        receiveTask?.cancel()
        let currentFd = fd
        let cont = continuation

        receiveTask = Task.detached(priority: .background) {
            var buf = [UInt8](repeating: 0, count: 4096)
            var buffer = ""

            while !Task.isCancelled {
                let n = Darwin.recv(currentFd, &buf, buf.count, 0)
                if n > 0 {
                    let str = String(bytes: buf[0..<n], encoding: .ascii) ?? ""
                    buffer += str
                    // Denon は \r を行末として使用
                    let parts = buffer.components(separatedBy: "\r")
                    buffer = parts.last ?? ""
                    for line in parts.dropLast() {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { cont.yield(trimmed) }
                    }
                } else if n == 0 {
                    break   // 接続終了
                }
                // n < 0: SO_RCVTIMEO による EAGAIN → ループ継続してキャンセルを確認
            }
        }
    }

    // MARK: - Interface Index Helper

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
            if (ifAddr & mask) == (targetIP & mask) { return if_nametoindex(p.pointee.ifa_name) }
        }
        return nil
    }
}
