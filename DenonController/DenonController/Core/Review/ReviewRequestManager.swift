import Foundation

/// レビュー依頼を出すタイミングの判定・状態管理のみを行う。
/// 実際の `requestReview()` 呼び出しは SwiftUI の `\.requestReview` 環境値経由で View 層から行う
/// （macOS/iOS 双方で `RequestReviewAction` が使え、OS 側のスロットリングにも従うため）。
enum ReviewRequestManager {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard
    private static let successCountKey = "reviewSuccessCount"
    private static let firstSuccessDateKey = "reviewFirstSuccessDate"
    private static let requestedVersionKey = "reviewRequestedVersion"

    private static let minSuccessCount = 3
    private static let minDaysSinceFirstSuccess: TimeInterval = 2

    /// 「良い体験」（AVR への接続成功など）があった際に呼ぶ。
    static func recordSuccess() {
        defaults.set(defaults.integer(forKey: successCountKey) + 1, forKey: successCountKey)
        if defaults.object(forKey: firstSuccessDateKey) == nil {
            defaults.set(Date(), forKey: firstSuccessDateKey)
        }
    }

    /// 今このタイミングでレビューを依頼してよいかを判定する。
    /// 条件: 接続成功が一定回数に達し、初回成功から数日経過し、同一バージョンでまだ依頼していない。
    static func shouldRequest() -> Bool {
        guard defaults.integer(forKey: successCountKey) >= minSuccessCount else { return false }

        guard let firstSuccess = defaults.object(forKey: firstSuccessDateKey) as? Date,
              Date().timeIntervalSince(firstSuccess) >= minDaysSinceFirstSuccess * 86400 else {
            return false
        }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard defaults.string(forKey: requestedVersionKey) != currentVersion else { return false }

        return true
    }

    /// 依頼ダイアログを表示した後に呼ぶ（同一バージョンでの再表示を防ぐ）。
    static func markRequested() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        defaults.set(currentVersion, forKey: requestedVersionKey)
    }
}
