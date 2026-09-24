import Foundation

/// 開発支援のお願いの条件だけを持つ（全体の間隔・順番は `PromptCoordinator` が持つ）。
/// 設計: docs/in-app-prompts-design.md 2.4, 4
enum SupportRequestManager {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard
    private static let shownDateKey = "supportRequestShownDate"

    private static let minActiveDays = 10
    private static let minDaysSinceFirstUse = 30
    private static let minDaysSinceReview: TimeInterval = 14 * 86400

    /// お願いを出した日時（まだなら nil）
    static var shownDate: Date? { defaults.object(forKey: shownDateKey) as? Date }

    /// 今このタイミングで支援のお願いを出してよいかを判定する。
    /// 条件: まだ一度も出しておらず、まだ支援しておらず、利用 10 日以上、初回利用から 30 日以上、
    /// 評価のお願いを出していれば、そこから 14 日以上。
    static func shouldRequest(now: Date = UsageTracker.now) -> Bool {
        guard shownDate == nil, !SupporterRecord.isSupporter else { return false }
        guard UsageTracker.activeDays >= minActiveDays,
              UsageTracker.daysSinceFirstUse(now: now) >= minDaysSinceFirstUse
        else { return false }
        if let reviewed = ReviewRequestManager.lastRequestDate,
           now.timeIntervalSince(reviewed) < minDaysSinceReview {
            return false
        }
        return true
    }

    /// お願いを出したときに呼ぶ（二度と出さない）。
    static func markRequested(now: Date = UsageTracker.now) {
        defaults.set(now, forKey: shownDateKey)
    }
}
