import Foundation

/// 接続後に AVR から取得したデバイス情報
struct DeviceInfo: Sendable {
    var modelName: String    = ""       // 例: "AVR-X3800H"
    var brandName: String    = "Denon"  // "Denon" or "Marantz"
    var categoryName: String = "AV RECEIVER"
    var hasZone2: Bool       = true     // ほぼ全機種あり
    var hasZone3: Bool       = false    // 上位機種のみ

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
