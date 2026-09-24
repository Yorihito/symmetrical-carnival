import Foundation

/// ヘルプサイト（GitHub Pages）への導線 URL。端末言語に応じて `/` (日本語) か `/en/` を出し分ける。
enum HelpSiteLinks {
    private static let base = "https://yorihito.github.io/symmetrical-carnival"

    private static func isEnglish(_ locale: Locale) -> Bool {
        locale.identifier.lowercased().hasPrefix("en")
    }

    static func guide(locale: Locale) -> URL {
        URL(string: isEnglish(locale) ? "\(base)/en/index.html" : "\(base)/index.html")!
    }

    /// 対応機種の一覧（動作報告から自動で作るページ）
    static func compatibility(locale: Locale) -> URL {
        URL(string: isEnglish(locale) ? "\(base)/en/compatibility.html" : "\(base)/compatibility.html")!
    }

    static func privacyPolicy(locale: Locale) -> URL {
        URL(string: isEnglish(locale) ? "\(base)/en/privacy.html" : "\(base)/privacy.html")!
    }
}

/// App Store への導線。
enum AppStoreLinks {
    /// App Store Connect のこのアプリの Apple ID
    static let appID = "6766823418"

    /// レビューを書く画面を直接開く。設定の「レビューを書く」ボタンから使う。
    /// `requestReview()` は OS が年 3 回までに制限していて、ボタンから呼ぶと何も出ないことがあるため。
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
}
