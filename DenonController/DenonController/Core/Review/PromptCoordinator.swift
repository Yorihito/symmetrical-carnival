import Foundation

/// 全体の間隔と順番を管理し、次に出してよいお願い・案内を 1 つ返す。表示は行わない。
/// 呼び出し側（`ContentView`）が「接続後、操作が 1 回以上あってから 5 秒間操作がない」という
/// 区切りのタイミングで `next(context:)` を呼び、返ってきたものを実際に出してから
/// `markShown` / `markDismissed` を呼ぶ。
/// 設計: docs/in-app-prompts-design.md 2, 3
@MainActor
enum PromptCoordinator {
    private nonisolated(unsafe) static let defaults = UserDefaults.standard
    private static let lastShownDateKey = "promptLastShownDate"
    private static let seededKey = "promptLastShownDateSeeded"
    private static let volumeDialIntroKey = "hasShownVolumeDialIntroductionV1"

    /// この起動ですでに何か出したか（プロセスが生きている間だけ有効。再起動でリセットされる）
    private static var hasShownThisLaunch = false

    private static let cooldown: TimeInterval = 7 * 86400
    private static let featureIntroCooldown: TimeInterval = 2 * 86400
    private static let minActiveDaysForAsks = 3

    /// `next(context:)` に渡す状況
    struct Context {
        var brand: ReceiverBrand
        var model: String
        /// シートやアラートなど、画面に何か出ているか（出ていれば見送る）
        var hasPresentedUI: Bool
        var now: Date = UsageTracker.now
    }

    /// 今出してよいものを 1 つ返す（なければ nil）。表示はしない。
    static func next(context: Context) -> InAppPrompt? {
        seedLastShownDateIfNeeded()

        guard !hasShownThisLaunch else {
            log("none (already shown this launch)")
            return nil
        }
        guard !context.hasPresentedUI else {
            log("none (UI already presented)")
            return nil
        }

        #if DEBUG
        if let forced = debugForcedPrompt() {
            log("\(describe(forced)) (debug forced)")
            return forced
        }
        #endif

        guard !UsageTracker.hadRecentFailure(now: context.now) else {
            log("none (recent failure)")
            return nil
        }

        // 新機能の案内は例外: 利用 3 日目より前でも出せて、間隔も 2 日でよい
        if let intro = nextFeatureIntro(now: context.now) {
            log(describe(.featureIntro(intro)))
            return .featureIntro(intro)
        }

        guard sinceLastShown(context.now) >= cooldown else {
            log("none (cooldown)")
            return nil
        }
        guard UsageTracker.activeDays >= minActiveDaysForAsks else {
            log("none (too new)")
            return nil
        }

        // 順番: 動作報告 → 評価 → 応援
        if CompatibilityPromptPolicy.isEligible(brand: context.brand, model: context.model, now: context.now) {
            log("compatibility")
            return .compatibility
        }
        if ReviewRequestManager.shouldRequest(brand: context.brand, model: context.model, now: context.now) {
            log("review")
            return .review
        }
        if SupportRequestManager.shouldRequest(now: context.now) {
            log("support")
            return .support
        }
        log("none (no eligible prompt)")
        return nil
    }

    /// 実際に出したときに呼ぶ
    static func markShown(_ prompt: InAppPrompt, context: Context) {
        hasShownThisLaunch = true
        defaults.set(context.now, forKey: lastShownDateKey)
        switch prompt {
        case .featureIntro:
            // 保存キー（`hasShownVolumeDialIntroductionV1`）は呼び出し側の @AppStorage が持つ
            break
        case .compatibility:
            CompatibilityPromptPolicy.markShown(brand: context.brand, model: context.model)
        case .review:
            ReviewRequestManager.markRequested(now: context.now)
        case .support:
            SupportRequestManager.markRequested(now: context.now)
        }
    }

    /// 動作報告の案内を閉じた（✕ を押した）ときに呼ぶ
    static func markDismissed(_ prompt: InAppPrompt, context: Context) {
        guard case .compatibility = prompt else { return }
        CompatibilityPromptPolicy.markDismissed(brand: context.brand, model: context.model, now: context.now)
    }

    // MARK: - Feature intros

    private static func nextFeatureIntro(now: Date) -> FeatureIntro? {
        guard !defaults.bool(forKey: volumeDialIntroKey) else { return nil }
        // 何かを一度でも出していれば、案内どうしの間隔として 2 日空ける。まだ何も出していなければ、
        // 利用 3 日目を待たずに出してよい（新しいバージョンへの更新直後に知らせるため）。
        if lastShownDate != nil, sinceLastShown(now) < featureIntroCooldown { return nil }
        return .volumeDial
    }

    // MARK: - Timing helpers

    private static var lastShownDate: Date? { defaults.object(forKey: lastShownDateKey) as? Date }

    private static func sinceLastShown(_ now: Date) -> TimeInterval {
        guard let last = lastShownDate else { return .infinity }
        return now.timeIntervalSince(last)
    }

    /// 1.1.x からの更新時、「最後に何かを出した日」の初期値を、評価・応援のお願いを出した日の
    /// 新しいほうにする（設計 2.6）。一度だけ行う。
    private static func seedLastShownDateIfNeeded() {
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)
        guard defaults.object(forKey: lastShownDateKey) == nil else { return }
        let candidates = [ReviewRequestManager.lastRequestDate, SupportRequestManager.shownDate].compactMap { $0 }
        if let latest = candidates.max() {
            defaults.set(latest, forKey: lastShownDateKey)
        }
    }

    // MARK: - Logging

    private static func describe(_ prompt: InAppPrompt) -> String {
        switch prompt {
        case .featureIntro(let intro): "featureIntro(\(intro.rawValue))"
        case .compatibility: "compatibility"
        case .review: "review"
        case .support: "support"
        }
    }

    /// 区切りのたびに判定するので、同じ結果が続くときは記録しない（診断ログが同じ行で埋まらないように）
    private static var lastLogged = ""

    private static func log(_ message: String) {
        guard message != lastLogged else { return }
        lastLogged = message
        DiagnosticsLog.shared.record("prompt: \(message)")
    }

    // MARK: - DEBUG

    #if DEBUG
    private static func debugForcedPrompt() -> InAppPrompt? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-promptNow"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "review":        return .review
        case "support":       return .support
        case "compatibility": return .compatibility
        case "intro":         return .featureIntro(.volumeDial)
        default:              return nil
        }
    }

    /// `-promptReset` があれば、起動時にお願い・利用実績の記録を全部消す
    static func debugResetIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-promptReset") else { return }
        UsageTracker.debugReset()
        CompatibilityPromptPolicy.debugReset()
        CompatibilityReportLog.debugClear()
        let keys = [
            "reviewSuccessCount", "reviewFirstSuccessDate", "reviewRequestedVersion", "reviewLastRequestDate",
            "supportRequestShownDate", lastShownDateKey, seededKey, volumeDialIntroKey,
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        hasShownThisLaunch = false
        DiagnosticsLog.shared.record("prompt: reset (-promptReset)")
    }
    #endif
}
