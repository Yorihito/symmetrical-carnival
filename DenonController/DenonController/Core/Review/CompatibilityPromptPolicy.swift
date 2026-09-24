import Foundation

/// 動作報告の案内（ダッシュボード下部の小さな表示）を出すかどうかの判定と、機種ごとの記録。
/// 設計: docs/in-app-prompts-design.md 2.4, docs/compatibility-reports-design.md 3.1
@MainActor
enum CompatibilityPromptPolicy {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard
    private static let shownCountKey = "compatPromptShownCount"       // [String: Int]
    private static let dismissedDateKey = "compatPromptDismissedDate" // [String: Date]

    private static let minActiveDays = 3
    private static let maxShownCount = 2
    private static let dismissCooldown: TimeInterval = 30 * 86400

    private static func modelKey(_ brand: ReceiverBrand, _ model: String) -> String {
        "\(brand.rawValue):\(model.lowercased())"
    }

    /// この機種の案内をこれまでに出した回数
    static func shownCount(brand: ReceiverBrand, model: String) -> Int {
        let dict = defaults.dictionary(forKey: shownCountKey) as? [String: Int] ?? [:]
        return dict[modelKey(brand, model)] ?? 0
    }

    /// この機種の案内を最後に閉じた（✕）日時
    static func dismissedDate(brand: ReceiverBrand, model: String) -> Date? {
        let dict = defaults.dictionary(forKey: dismissedDateKey) as? [String: Date] ?? [:]
        return dict[modelKey(brand, model)]
    }

    /// 動作報告の案内を今出してよいか（全体の間隔・順番は `PromptCoordinator` が別途見る）。
    /// 条件（設計 2.4 / compatibility-reports-design.md 3.1）:
    /// - 接続中の機種が未確認（開発者確認済みでも、報告済み [問題なく使えるが 3 件以上] でもない）
    /// - その機種での利用が 3 日以上
    /// - この端末からその機種の動作報告をまだ送っていない
    /// - 案内は機種ごとに最大 2 回。閉じたら同じ機種には 30 日空ける
    static func isEligible(brand: ReceiverBrand, model: String, now: Date = UsageTracker.now) -> Bool {
        guard !model.isEmpty else { return false }
        guard !CompatibilityDirectory.shared.status(brand: brand, model: model).isConfirmed else { return false }
        guard UsageTracker.activeDays(brand: brand, model: model) >= minActiveDays else { return false }
        guard !CompatibilityReportLog.hasReported(brand: brand, model: model) else { return false }
        guard shownCount(brand: brand, model: model) < maxShownCount else { return false }
        if let dismissed = dismissedDate(brand: brand, model: model),
           now.timeIntervalSince(dismissed) < dismissCooldown {
            return false
        }
        return true
    }

    /// 動作報告の「答えが出ている」か（評価のお願いを進めてよいかの判定に使う。設計 2.3 / 3.3.1）。
    /// 次のどれかなら true: 確認済みの機種／この端末から報告した／案内を 2 回出した／案内を閉じたことがある。
    /// 機種が分からない（未接続など）ときはブロックせず true を返す。
    static func isResolved(brand: ReceiverBrand, model: String) -> Bool {
        guard !model.isEmpty else { return true }
        if CompatibilityDirectory.shared.status(brand: brand, model: model).isConfirmed { return true }
        if CompatibilityReportLog.hasReported(brand: brand, model: model) { return true }
        if shownCount(brand: brand, model: model) >= maxShownCount { return true }
        if dismissedDate(brand: brand, model: model) != nil { return true }
        return false
    }

    /// 案内を出したときに呼ぶ
    static func markShown(brand: ReceiverBrand, model: String) {
        guard !model.isEmpty else { return }
        var dict = defaults.dictionary(forKey: shownCountKey) as? [String: Int] ?? [:]
        let key = modelKey(brand, model)
        dict[key] = (dict[key] ?? 0) + 1
        defaults.set(dict, forKey: shownCountKey)
    }

    /// 案内を閉じた（✕）ときに呼ぶ
    static func markDismissed(brand: ReceiverBrand, model: String, now: Date = UsageTracker.now) {
        guard !model.isEmpty else { return }
        var dict = defaults.dictionary(forKey: dismissedDateKey) as? [String: Date] ?? [:]
        dict[modelKey(brand, model)] = now
        defaults.set(dict, forKey: dismissedDateKey)
    }

    #if DEBUG
    /// テスト用: 機種ごとの案内の記録を全部消す（`-promptReset` から呼ばれる）
    static func debugReset() {
        defaults.removeObject(forKey: shownCountKey)
        defaults.removeObject(forKey: dismissedDateKey)
    }
    #endif
}
