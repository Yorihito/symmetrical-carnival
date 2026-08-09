import Foundation

/// In-app ring buffer of recent diagnostic lines, attached to a user-submitted
/// problem report. Kept in memory only (not persisted) and capped in size.
///
/// Privacy: callers must never record host names, IP/MAC addresses, or other
/// network identifiers directly (`defaultHost` in particular, since it's the
/// user's local AVR address). As a defense-in-depth backstop, `record(_:)`
/// also redacts anything that *looks* like an IP or MAC address.
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()

    private let capacity: Int
    private let lock = NSLock()
    private var lines: [String] = []
    private let timestamp: DateFormatter

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        self.timestamp = f
    }

    /// Append one timestamped, PII-redacted line. Safe to call from any thread.
    func record(_ line: String) {
        let entry = "\(timestamp.string(from: Date())) \(Self.redact(line))"
        lock.lock()
        lines.append(entry)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        lock.unlock()
    }

    /// The current buffer as newline-joined text (oldest first).
    func export() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock(); lines.removeAll(); lock.unlock()
    }

    // MARK: - Redaction

    /// Replaces anything that looks like an IPv4/IPv6 or MAC address with a
    /// placeholder, so accidental PII never reaches a public issue.
    static func redact(_ s: String) -> String {
        var out = s
        for (pattern, replacement) in redactions {
            out = pattern.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: replacement)
        }
        return out
    }

    private static let redactions: [(NSRegularExpression, String)] = {
        func rx(_ p: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
        }
        return [
            // MAC (aa:bb:cc:dd:ee:ff or with '-'). Run before IPv6 so its colons
            // are consumed here first.
            (rx("\\b([0-9a-f]{2}[:-]){5}[0-9a-f]{2}\\b"), "[mac]"),
            // IPv4
            (rx("\\b(\\d{1,3}\\.){3}\\d{1,3}\\b"), "[ip]"),
            // IPv6 — full form (4+ colon groups) or any '::' compressed form.
            (rx("\\b([0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}\\b"), "[ip6]"),
            (rx("\\b([0-9a-f]{1,4})?::[0-9a-f:]*[0-9a-f]\\b"), "[ip6]"),
        ]
    }()
}
