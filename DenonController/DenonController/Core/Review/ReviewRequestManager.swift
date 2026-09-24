import Foundation

/// レビュー依頼の条件だけを持つ（日付の突き合わせ・全体の間隔・順番は `PromptCoordinator` が持つ）。
/// 実際の `requestReview()` 呼び出しは SwiftUI の `\.requestReview` 環境値経由で View 層から行う
/// （macOS/iOS 双方で `RequestReviewAction` が使え、OS 側のスロットリングにも従うため）。
/// 設計: docs/in-app-prompts-design.md 2.4, 3.3.1, 4
enum ReviewRequestManager {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    // 1.1.x 時代のキー。1.2.0 以降はここに書き込まないが、`UsageTracker` の移行（2.6）が読むために残す。
    private static let successCountKey = "reviewSuccessCount"
    private static let firstSuccessDateKey = "reviewFirstSuccessDate"

    private static let requestedVersionKey = "reviewRequestedVersion"
    private static let lastRequestDateKey = "reviewLastRequestDate"

    private static let minActiveDays = 5
    private static let minDaysSinceFirstUse = 7

    /// 1.1.x での接続成功の累計回数（`UsageTracker` の移行専用。1.2.0 以降は増えない）
    static var successCount: Int { defaults.integer(forKey: successCountKey) }

    /// 1.1.x で初めて接続に成功した日時（`UsageTracker` の移行専用）
    static var firstSuccessDate: Date? { defaults.object(forKey: firstSuccessDateKey) as? Date }

    /// 最後に評価のお願いを出した日時
    static var lastRequestDate: Date? { defaults.object(forKey: lastRequestDateKey) as? Date }

    /// 1.1.x 互換用。1.2.0 以降は `MainViewModel` からは呼ばれず、`UsageTracker.recordSuccessfulConnection`
    /// に置き換わっている（利用日数の記録は `UsageTracker` が持つ）。
    static func recordSuccess() {
        defaults.set(defaults.integer(forKey: successCountKey) + 1, forKey: successCountKey)
        if defaults.object(forKey: firstSuccessDateKey) == nil {
            defaults.set(Date(), forKey: firstSuccessDateKey)
        }
    }

    /// 今このタイミングでレビューを依頼してよいかを判定する。
    /// 条件: 利用 5 日以上、初回利用から 7 日以上、バージョンの上 2 桁（メジャー.マイナー）でまだ
    /// 依頼しておらず、接続中の機種の動作報告の答えが出ている（未確認の機種なら報告を待つ。設計 2.3）。
    /// 全体の間隔（7 日、1 回の起動で 1 つまで等）は `PromptCoordinator` が見るので、ここでは見ない。
    @MainActor
    static func shouldRequest(brand: ReceiverBrand, model: String, now: Date = UsageTracker.now) -> Bool {
        guard UsageTracker.activeDays >= minActiveDays else { return false }
        guard UsageTracker.daysSinceFirstUse(now: now) >= minDaysSinceFirstUse else { return false }

        if let requested = defaults.string(forKey: requestedVersionKey),
           Self.majorMinor(of: requested) == Self.currentMajorMinor {
            return false
        }

        guard CompatibilityPromptPolicy.isResolved(brand: brand, model: model) else { return false }

        return true
    }

    /// 依頼ダイアログを表示した後に呼ぶ（バージョンの上 2 桁での再表示を防ぐ）。
    /// 動作報告のお礼の画面から「App Store で評価する」を押したときにも呼ばれる
    /// （その場合は新しいお願いとしては数えないため、`PromptCoordinator` の間隔は更新しない）。
    static func markRequested(now: Date = UsageTracker.now) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        defaults.set(currentVersion, forKey: requestedVersionKey)
        defaults.set(now, forKey: lastRequestDateKey)
    }

    /// `CFBundleShortVersionString` の上 2 桁（メジャー.マイナー）
    private static var currentMajorMinor: String {
        majorMinor(of: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    /// バージョン文字列の上 2 桁だけを取り出す（保存済みの `reviewRequestedVersion` は 1.1.x 時代の
    /// フルバージョン文字列のこともあるため、比較の直前にここで切り詰める）
    private static func majorMinor(of version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }
}
