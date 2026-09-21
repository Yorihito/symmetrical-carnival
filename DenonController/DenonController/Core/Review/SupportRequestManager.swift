import Foundation

/// 開発支援のお願いを一度だけ出すタイミングの判定・状態管理。
///
/// 評価のお願い（`ReviewRequestManager`）と同じ「接続成功」の記録を使い、それよりも長く
/// 使ってくれている人にだけ出す。評価と支援のお願いは同じ日に重ねない。
enum SupportRequestManager {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard
    private static let shownDateKey = "supportRequestShownDate"

    private static let minSuccessCount = 10
    private static let minDaysSinceFirstSuccess: TimeInterval = 14

    /// お願いを出した日時（まだなら nil）
    static var shownDate: Date? { defaults.object(forKey: shownDateKey) as? Date }

    /// 今このタイミングで支援のお願いを出してよいかを判定する。
    /// 条件: まだ一度も出しておらず、まだ支援しておらず、接続成功が 10 回以上、
    /// 初回成功から 14 日以上経過し、今日は評価のお願いを出していない。
    static func shouldRequest() -> Bool {
        guard shownDate == nil, !SupporterRecord.isSupporter else { return false }
        guard ReviewRequestManager.successCount >= minSuccessCount,
              let firstSuccess = ReviewRequestManager.firstSuccessDate,
              Date().timeIntervalSince(firstSuccess) >= minDaysSinceFirstSuccess * 86400
        else { return false }
        if let reviewed = ReviewRequestManager.lastRequestDate, Calendar.current.isDateInToday(reviewed) {
            return false
        }
        return true
    }

    /// お願いを出したときに呼ぶ（二度と出さない）。
    static func markRequested() {
        defaults.set(Date(), forKey: shownDateKey)
    }
}
