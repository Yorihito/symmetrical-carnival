import Foundation
import Observation

/// AVR-X3800H のリアルタイム状態を保持する Observable モデル。
/// TelnetClient からのレスポンス行を apply(_:) で適用する。
@Observable
@MainActor
final class AVRState {

    // MARK: - Connection
    var isConnected = false

    // MARK: - Main Zone
    var isPoweredOn   = false
    var volume: Double = 50   // Denon units (0–98, step 0.5)
    var isMuted       = false
    var input: InputSource   = .hdmi1
    var surroundMode: SurroundMode = .auto

    // MARK: - Zone 2
    var zone2Power:  Bool   = false
    var zone2Volume: Double = 50
    var zone2Mute:   Bool   = false
    var zone2Input:  InputSource = .hdmi1

    // MARK: - Zone 3
    var zone3Power:  Bool   = false
    var zone3Volume: Double = 50
    var zone3Mute:   Bool   = false

    // MARK: - Computed

    /// 表示用 dB 文字列（例: "−30.0 dB"）
    var volumeDBString: String {
        let db = volume - 80
        if volume.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f dB", db)
        } else {
            return String(format: "%.1f dB", db)
        }
    }

    var zone2VolumeDBString: String {
        let db = zone2Volume - 80
        return String(format: "%.0f dB", db)
    }

    // MARK: - Apply response

    /// AVR からのレスポンス行を解析して状態を更新する。
    func apply(_ response: String) {
        // ── Main Zone ──────────────────────────────────
        if response.hasPrefix("PW") {
            isPoweredOn = (response == "PWON")

        } else if response.hasPrefix("MVMAX") {
            // "MVMAX 98" などの最大音量通知 — 無視
            return

        } else if response.hasPrefix("MV") {
            parseVolume(String(response.dropFirst(2)), target: \.volume)

        } else if response.hasPrefix("MU") {
            isMuted = (response == "MUON")

        } else if response.hasPrefix("SI") {
            let code = String(response.dropFirst(2))
            if let src = InputSource(rawCode: code) { input = src }

        } else if response.hasPrefix("MS") {
            let code = String(response.dropFirst(2))
            if let mode = SurroundMode(rawCode: code) { surroundMode = mode }

        // ── Zone 2 ────────────────────────────────────
        } else if response == "Z2ON"  { zone2Power = true
        } else if response == "Z2OFF" { zone2Power = false
        } else if response.hasPrefix("Z2MU") {
            zone2Mute = response.hasSuffix("ON")
        } else if response.hasPrefix("Z2") {
            // Could be Z2<input> or Z2<volume>
            let rest = String(response.dropFirst(2))
            if let src = InputSource(rawCode: rest) {
                zone2Input = src
            } else {
                parseVolume(rest, target: \.zone2Volume)
            }

        // ── Zone 3 ────────────────────────────────────
        } else if response == "Z3ON"  { zone3Power = true
        } else if response == "Z3OFF" { zone3Power = false
        } else if response.hasPrefix("Z3MU") {
            zone3Mute = response.hasSuffix("ON")
        } else if response.hasPrefix("Z3") {
            let rest = String(response.dropFirst(2))
            parseVolume(rest, target: \.zone3Volume)
        }
    }

    /// "50" → 50.0, "505" → 50.5 のように Denon 音量値をパース
    private func parseVolume(_ str: String, target: ReferenceWritableKeyPath<AVRState, Double>) {
        guard let intVal = Int(str) else { return }
        if str.count == 3 {
            self[keyPath: target] = Double(intVal) / 10.0
        } else {
            self[keyPath: target] = Double(intVal)
        }
    }

    // MARK: - Query commands (接続直後に送信して状態を同期)
    static let queryCommands: [String] = [
        "PW?", "MV?", "MU?", "SI?", "MS?",
        "Z2?", "Z3?"
    ]
}
