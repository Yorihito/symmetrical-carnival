import Foundation

/// 接続後に AVR から取得したデバイス情報
struct DeviceInfo: Sendable {
    var modelName: String    = ""       // 例: "AVR-X3800H"
    var brandName: String    = "Denon"  // "Denon" or "Marantz"
    var categoryName: String = "AV RECEIVER"
    var hasZone2: Bool       = true     // ほぼ全機種あり
    var hasZone3: Bool       = false    // 上位機種のみ
    var macAddress: String   = ""       // DHCP で IP が変わっても同一機体を識別するための安定 ID

    /// コロン・ハイフンを除去し大文字化した MAC アドレス。
    /// 機種・ファームウェアによって表記揺れ（区切り文字の有無）があるため、
    /// 同一性の比較には必ずこの正規化形を使うこと。
    static func normalizedMac(_ raw: String) -> String {
        raw.uppercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// ブランド名 + カテゴリ（例: "Denon AV RECEIVER"）
    var brandCategory: String {
        "\(brandName) \(categoryName)"
    }

    /// 表示用タイトル（モデル名が取得できた場合はそれを、なければブランドカテゴリ）
    var displayTitle: String {
        modelName.isEmpty ? brandCategory : modelName
    }

    /// 接続前のプレースホルダー
    static var unknown: DeviceInfo { DeviceInfo() }
}
