import Foundation

/// 「使った量」を、接続の回数ではなく利用日数（接続に成功した日の数）で数える。
/// 同じ日に何度接続しても 1 日と数える。機種ごとの利用日数、初回利用日、直近の失敗時刻も記録する。
/// UserDefaults ベース。表示や判定は行わない（`PromptCoordinator` / 各 `...RequestManager` が使う）。
/// 設計: docs/in-app-prompts-design.md 2.2, 2.6
enum UsageTracker {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    private static let activeDaysKey = "usageActiveDays"
    private static let lastActiveDateKey = "usageLastActiveDate"
    private static let firstUseDateKey = "usageFirstUseDate"
    private static let lastFailureDateKey = "usageLastFailureDate"
    private static let perModelActiveDaysKey = "usagePerModelActiveDays"
    private static let perModelLastActiveDateKey = "usagePerModelLastActiveDate"

    // MARK: - "今日"（DEBUG の確認用に差し替え可能）

    #if DEBUG
    /// `-promptDate yyyy-MM-dd` が指定されていれば、それを「今日」として使う。
    /// お願いの間隔・利用日数のしきい値を、実際に何日も待たずに確認するための起動引数。
    static var debugDateOverride: Date? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-promptDate"), i + 1 < args.count else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: args[i + 1])
    }
    #endif

    /// 「今」。DEBUG ビルドで `-promptDate` があればそれを使う。
    static var now: Date {
        #if DEBUG
        debugDateOverride ?? Date()
        #else
        Date()
        #endif
    }

    // MARK: - 全体

    /// 接続に成功した日の数
    static var activeDays: Int {
        migrateIfNeeded()
        return defaults.integer(forKey: activeDaysKey)
    }

    /// 初めて使った日
    static var firstUseDate: Date? {
        migrateIfNeeded()
        return defaults.object(forKey: firstUseDateKey) as? Date
    }

    /// 初回利用からの経過日数（暦日ベース）
    static func daysSinceFirstUse(now: Date = UsageTracker.now) -> Int {
        guard let first = firstUseDate else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: first),
            to: cal.startOfDay(for: now)
        ).day ?? 0
    }

    /// 直近の失敗（接続失敗・ポーリング断・コマンド失敗）の時刻
    static var lastFailureDate: Date? { defaults.object(forKey: lastFailureDateKey) as? Date }

    /// 過去 `interval` 以内に失敗があったか（デフォルト 24 時間）
    static func hadRecentFailure(within interval: TimeInterval = 24 * 3600, now: Date = UsageTracker.now) -> Bool {
        guard let last = lastFailureDate else { return false }
        return now.timeIntervalSince(last) < interval
    }

    /// 接続に成功したときに呼ぶ。利用日数は日付が変わったときだけ増やす。機種ごとの利用日数も記録する。
    static func recordSuccessfulConnection(brand: ReceiverBrand, model: String, now: Date = UsageTracker.now) {
        migrateIfNeeded()
        if defaults.object(forKey: firstUseDateKey) == nil {
            defaults.set(now, forKey: firstUseDateKey)
        }
        let cal = Calendar.current
        if let last = defaults.object(forKey: lastActiveDateKey) as? Date, cal.isDate(last, inSameDayAs: now) {
            // 同じ日なので増やさない
        } else {
            defaults.set(defaults.integer(forKey: activeDaysKey) + 1, forKey: activeDaysKey)
            defaults.set(now, forKey: lastActiveDateKey)
        }
        recordModelActiveDay(brand: brand, model: model, now: now)
    }

    /// 接続失敗・切断・コマンド失敗を記録する（直近 24 時間の見送り判定に使う）
    static func recordFailure(now: Date = UsageTracker.now) {
        defaults.set(now, forKey: lastFailureDateKey)
    }

    // MARK: - 機種ごと

    private static func modelKey(_ brand: ReceiverBrand, _ model: String) -> String {
        "\(brand.rawValue):\(model.lowercased())"
    }

    /// その機種での利用日数
    static func activeDays(brand: ReceiverBrand, model: String) -> Int {
        let dict = defaults.dictionary(forKey: perModelActiveDaysKey) as? [String: Int] ?? [:]
        return dict[modelKey(brand, model)] ?? 0
    }

    private static func recordModelActiveDay(brand: ReceiverBrand, model: String, now: Date) {
        guard !model.isEmpty else { return }
        let key = modelKey(brand, model)
        let cal = Calendar.current
        var lastDates = defaults.dictionary(forKey: perModelLastActiveDateKey) as? [String: Date] ?? [:]
        if let last = lastDates[key], cal.isDate(last, inSameDayAs: now) { return }
        lastDates[key] = now
        defaults.set(lastDates, forKey: perModelLastActiveDateKey)

        var counts = defaults.dictionary(forKey: perModelActiveDaysKey) as? [String: Int] ?? [:]
        counts[key] = (counts[key] ?? 0) + 1
        defaults.set(counts, forKey: perModelActiveDaysKey)
    }

    // MARK: - 1.1.x からの移行（設計 2.6）

    /// 1.1.x では接続回数を `ReviewRequestManager` が記録していた。利用日数の記録がまだなければ、
    /// `min(接続成功回数, 初回成功からの日数 + 1)` を初期値として引き継ぐ。
    /// `activeDaysKey` が書き込まれた時点で以後は何もしない（一度だけ行う）。
    private static func migrateIfNeeded() {
        guard defaults.object(forKey: activeDaysKey) == nil else { return }

        guard let firstSuccess = ReviewRequestManager.firstSuccessDate else {
            // 1.1.x を使っていなかった（新規インストール）。まだ利用日数がないだけなので、
            // 次の実際の接続成功で `recordSuccessfulConnection` が初期化する。
            return
        }
        let successCount = ReviewRequestManager.successCount
        guard successCount > 0 else { return }

        let cal = Calendar.current
        let daysSinceFirstSuccess = max(
            0,
            cal.dateComponents([.day], from: cal.startOfDay(for: firstSuccess), to: cal.startOfDay(for: now)).day ?? 0
        )
        let seededActiveDays = min(successCount, daysSinceFirstSuccess + 1)

        defaults.set(seededActiveDays, forKey: activeDaysKey)
        defaults.set(firstSuccess, forKey: firstUseDateKey)
    }

    #if DEBUG
    /// テスト用: 利用実績の記録を全部消す（`-promptReset` から呼ばれる）
    static func debugReset() {
        for key in [activeDaysKey, lastActiveDateKey, firstUseDateKey, lastFailureDateKey,
                    perModelActiveDaysKey, perModelLastActiveDateKey] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
