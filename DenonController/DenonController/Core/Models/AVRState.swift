import Foundation
import Observation

/// AVR-X3800H のリアルタイム状態を保持する Observable モデル。
/// HTTP ポーリングで得た AVRStatusSnapshot を apply(_:) で適用する。
@Observable
@MainActor
final class AVRState {

    // MARK: - Connection
    var isConnected = false

    // MARK: - Main Zone
    var isPoweredOn   = false
    var volumeDB:  Double = -60.0   // 実際の dB 値（-80 〜 +18）
    var isMuted       = false
    var input: InputSource   = .hdmi1
    var surroundMode: SurroundMode = .auto   // HTTP では取得不可 → コマンド送信時に追跡

    // MARK: - Zone 2
    var zone2Power:    Bool   = false
    var zone2VolumeDB: Double = -40.0
    var zone2Mute:     Bool   = false
    var zone2Input:    InputSource = .hdmi1

    // MARK: - Zone 3（HTTP API では音量のみポーリング不可 → コマンドのみ）
    var zone3Power:    Bool   = false
    var zone3VolumeDB: Double = -40.0
    var zone3Mute:     Bool   = false

    // MARK: - Computed

    /// 表示用 dB 文字列（例: "−30.0 dB"）
    var volumeDBString: String {
        if volumeDB.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f dB", volumeDB)
        } else {
            return String(format: "%.1f dB", volumeDB)
        }
    }

    var zone2VolumeDBString: String {
        String(format: "%.0f dB", zone2VolumeDB)
    }

    var zone3VolumeDBString: String {
        String(format: "%.0f dB", zone3VolumeDB)
    }

    // MARK: - Apply HTTP snapshot

    func apply(_ snap: AVRStatusSnapshot) {
        isPoweredOn  = snap.isPoweredOn
        volumeDB     = snap.volumeDB
        isMuted      = snap.isMuted

        if let src = InputSource(rawCode: snap.inputCode) {
            input = src
        }

        zone2Power    = snap.zone2Power
        zone2VolumeDB = snap.zone2VolumeDB
        zone2Mute     = snap.zone2Muted

        if let src = InputSource(rawCode: snap.zone2InputCode) {
            zone2Input = src
        }
    }

    // MARK: - Volume command helpers

    /// dB 値を Denon コマンド文字列に変換（例: -30.0 → "MV50", -30.5 → "MV495"）
    static func volumeCommand(forDB db: Double) -> String {
        let unit = db + 80.0   // -80dB → 0, 0dB → 80, +18dB → 98
        let clamped = max(0.0, min(98.0, unit))
        if clamped.truncatingRemainder(dividingBy: 1) == 0 {
            return "MV\(Int(clamped))"
        } else {
            // 例: 49.5 → "MV495"
            return "MV\(Int(clamped * 10))"
        }
    }
}
