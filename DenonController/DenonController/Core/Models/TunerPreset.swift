import Foundation

// MARK: - TunerBand

enum TunerBand: String, Codable, CaseIterable, Sendable {
    case fm  = "FM"
    case am  = "AM"
    case dab = "DAB"

    var displayName: String { rawValue }

    /// チューナーバンド切替コマンド
    var selectCommand: String {
        switch self {
        case .fm:  "TMANFM"
        case .am:  "TMANAM"
        case .dab: "TMANDAB"
        }
    }

    /// 周波数単位
    var freqUnit: String {
        switch self {
        case .fm:  "MHz"
        case .am:  "kHz"
        case .dab: ""
        }
    }

    /// 周波数アップコマンド
    var freqUpCommand: String {
        switch self {
        case .fm:  "TFANUP"
        case .am:  "TMANUP"
        case .dab: "TFANUP"
        }
    }

    /// 周波数ダウンコマンド
    var freqDownCommand: String {
        switch self {
        case .fm:  "TFANDOWN"
        case .am:  "TMANDOWN"
        case .dab: "TFANDOWN"
        }
    }
}

// MARK: - TunerPreset

/// AVR 内蔵チューナーのプリセット（スキャンで取得）。
/// AVR コントローラーの Preset（入力+音量+サラウンド）とは別物。
struct TunerPreset: Identifiable, Equatable, Codable, Sendable {
    let id: Int              // AVR プリセット番号（1–56）
    let band: TunerBand
    let frequency: String    // "87.50"（FM）/ "558"（AM）
    let stationName: String  // AVR に登録されていれば非空

    var displayFrequency: String {
        band.freqUnit.isEmpty ? frequency : "\(frequency) \(band.freqUnit)"
    }

    /// リスト表示用名称。ステーション名があればそちらを優先。
    var displayName: String {
        stationName.isEmpty ? displayFrequency : stationName
    }
}
