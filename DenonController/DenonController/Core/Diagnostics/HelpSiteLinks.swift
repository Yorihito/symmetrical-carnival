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

    static func privacyPolicy(locale: Locale) -> URL {
        URL(string: isEnglish(locale) ? "\(base)/en/privacy.html" : "\(base)/privacy.html")!
    }
}
