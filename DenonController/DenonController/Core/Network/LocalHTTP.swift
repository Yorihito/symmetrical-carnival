import Foundation
import Darwin

/// LAN 上の機器へ BSD ソケットで HTTP/1.0 の GET / POST を送る小さなヘルパー。
///
/// URLSession / NWConnection はインターネット到達性チェックでローカル専用の Wi-Fi への接続に
/// 失敗することがあるため、`AVRHTTPClient` と同じく BSD ソケットを直接使う。
/// Denon 側は実績のある `AVRHTTPClient` の実装をそのまま使い、こちらは Yamaha と機器の判定に使う。
enum LocalHTTP {
    struct Response: Sendable {
        var status: Int
        var body: Data
    }

    static func get(host: String, port: Int, path: String,
                    timeout: Int = 5, headers: [String: String] = [:]) async throws -> Response {
        try await run { try request(method: "GET", host: host, port: port, path: path,
                                    body: nil, contentType: nil, timeout: timeout, headers: headers) }
    }

    static func post(host: String, port: Int, path: String, body: String,
                     contentType: String = "text/xml", timeout: Int = 5) async throws -> Response {
        try await run { try request(method: "POST", host: host, port: port, path: path,
                                    body: Data(body.utf8), contentType: contentType, timeout: timeout, headers: [:]) }
    }

    private static func run(_ work: @escaping @Sendable () throws -> Response) async throws -> Response {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try work()) } catch { cont.resume(throwing: error) }
            }
        }
    }

    private static func request(method: String, host: String, port: Int, path: String,
                                body: Data?, contentType: String?, timeout: Int,
                                headers: [String: String]) throws -> Response {
        var hints = addrinfo(ai_flags: AI_DEFAULT, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var resPtr: UnsafeMutablePointer<addrinfo>?
        let gaiRet = getaddrinfo(host, String(port), &hints, &resPtr)
        guard gaiRet == 0, let first = resPtr else {
            throw AVRError.connectionFailed("アドレス解決失敗 (\(host)): \(gaiRet)")
        }
        defer { freeaddrinfo(resPtr) }

        var addr = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        addr.sin_port = in_port_t(port).bigEndian

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw AVRError.connectionFailed("socket() 失敗 errno=\(errno)") }
        defer { Darwin.close(fd) }

        let nosigpipe: Int32 = 1
        withUnsafePointer(to: nosigpipe) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, ptr, socklen_t(MemoryLayout<Int32>.size))
        }
        let tv = timeval(tv_sec: timeout, tv_usec: 0)
        withUnsafePointer(to: tv) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        let connectRet = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectRet == 0 else {
            throw AVRError.connectionFailed("\(host):\(port) — \(String(cString: strerror(errno)))")
        }

        var head = "\(method) \(path) HTTP/1.0\r\nHost: \(host)\r\nAccept: */*\r\nConnection: close\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        if let body {
            head += "Content-Type: \(contentType ?? "application/octet-stream")\r\nContent-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        let bytes = Array(head.utf8) + Array(body ?? Data())
        guard Darwin.send(fd, bytes, bytes.count, 0) == bytes.count else {
            throw AVRError.connectionFailed("HTTP リクエスト送信失敗")
        }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }

        // ヘッダーとボディの境目はバイト列で探す（ボディを文字列に変換すると壊れることがあるため）
        let separator = Data("\r\n\r\n".utf8)
        guard let split = data.range(of: separator),
              let headText = String(data: data[..<split.lowerBound], encoding: .isoLatin1),
              let statusStr = headText.components(separatedBy: "\r\n").first?
                  .components(separatedBy: " ").dropFirst().first,
              let status = Int(statusStr)
        else { throw AVRError.connectionFailed("HTTP レスポンス解析失敗") }
        return Response(status: status, body: Data(data[split.upperBound...]))
    }
}
