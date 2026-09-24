import Foundation

// 動作報告（「この機種で動いたか」）のデータ。送信経路は ProblemReporter と同じ Worker。
// 設計: docs/compatibility-reports-design.md

/// 報告する機能。rawValue は Worker と集計スクリプトの許可リストと一致させること
enum CompatibilityFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case discovery, power, volume, mute, input
    case soundMode = "sound_mode"
    case zone2, zone3, tuner, remote, reconnect

    var id: String { rawValue }

    /// 画面に出す名前（ローカライズキー）
    var titleKey: String {
        switch self {
        case .discovery: "自動検出"
        case .power:     "電源"
        case .volume:    "音量"
        case .mute:      "ミュート"
        case .input:     "入力切替"
        case .soundMode: "サウンドモード"
        case .zone2:     "ゾーン 2"
        case .zone3:     "ゾーン 3"
        case .tuner:     "チューナー"
        case .remote:    "リモコン画面"
        case .reconnect: "IP アドレスが変わった後の再接続"
        }
    }

    /// 接続中の機器にある機能だけを並べる
    static func applicable(to caps: ReceiverCapabilities) -> [CompatibilityFeature] {
        allCases.filter { feature in
            switch feature {
            case .zone2:  caps.hasZone2
            case .zone3:  caps.hasZone3
            case .tuner:  caps.tunerInputID != nil
            case .remote: caps.supportsRemote
            default:      true
            }
        }
    }
}

enum CompatibilityOverall: String, CaseIterable, Identifiable, Codable, Sendable {
    case works, partial, fails
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .works:   "問題なく使える"
        case .partial: "一部使えない"
        case .fails:   "使えない"
        }
    }
}

enum CompatibilityFeatureResult: String, Codable, Sendable {
    case ok, ng
}

/// Worker に送る `compat` オブジェクト（schema 1）
struct CompatibilityReport: Codable, Sendable, Equatable {
    var schema = 1
    var brand: String
    var model: String
    var region: String?
    var firmware: String?
    var apiVersion: String?
    var app: String
    var platform: String
    var overall: CompatibilityOverall
    var features: [String: CompatibilityFeatureResult]
}

/// 対応機種の一覧（ヘルプサイトの compatibility.json）での、ある機種の状態
enum CompatibilityModelStatus: String, Sendable {
    case verified, reported, partial, failing, unknown

    /// 動作報告をお願いする必要がない（開発者確認済み、または十分な報告がある）
    var isConfirmed: Bool { self == .verified || self == .reported }
}

/// この端末から動作報告を送った機種の記録（同じ機種に何度もお願いしないため）
enum CompatibilityReportLog {
    private static let key = "compatibilityReportedModels"

    private static func id(_ brand: ReceiverBrand, _ model: String) -> String {
        "\(brand.rawValue):\(model.lowercased())"
    }

    static func hasReported(brand: ReceiverBrand, model: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id(brand, model))
    }

    static func markReported(brand: ReceiverBrand, model: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        let entry = id(brand, model)
        guard !list.contains(entry) else { return }
        list.append(entry)
        UserDefaults.standard.set(list, forKey: key)
    }

    #if DEBUG
    static func debugClear() { UserDefaults.standard.removeObject(forKey: key) }
    #endif
}
