import Foundation

#if os(iOS)
import UIKit
#endif

/// 「問題を報告」機能の報告種別。GitHub の既定ラベルにそのまま対応させる。
enum ProblemReportCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case feature
    case other

    var id: String { rawValue }

    var githubLabel: String {
        switch self {
        case .bug:     "bug"
        case .feature: "enhancement"
        case .other:   "question"
        }
    }
}

/// バグ報告・機能リクエストを GitHub Issue としてブラウザ経由で送信するためのヘルパー。
///
/// バックエンドや GitHub トークンを持たない構成のため、`issues/new` の事前入力 URL を組み立てて
/// ブラウザ（Safari 等）で開くフォールバック方式のみを使う。IP アドレスなどのネットワーク情報は
/// 診断情報に含めない（`defaultHost` はユーザーのローカル AVR アドレスであり、公開 Issue に
/// 載せるべきではないため意図的に除外している）。
enum ProblemReporter {
    private static let repoURL = "https://github.com/Yorihito/symmetrical-carnival"

    static var repoIssuesURL: URL { URL(string: "\(repoURL)/issues")! }

    /// 端末・アプリの診断情報（PII を含まない）を組み立てる。
    static func diagnosticsSummary(connectedModel: String? = nil) -> String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        var lines = [
            "- App version: \(version) (\(build))",
            "- Platform: \(platformDescription())",
            "- Locale: \(Locale.current.identifier)",
        ]
        if let connectedModel, !connectedModel.isEmpty {
            lines.append("- Connected AVR model: \(connectedModel)")
        }
        return lines.joined(separator: "\n")
    }

    #if os(iOS)
    private static func platformDescription() -> String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) / \(device.model)"
    }
    #elseif os(macOS)
    private static func platformDescription() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    #endif

    /// GitHub の `issues/new` 事前入力 URL を生成する。
    static func issueURL(
        category: ProblemReportCategory,
        title: String,
        body: String,
        includeDiagnostics: Bool,
        connectedModel: String? = nil
    ) -> URL? {
        var fullBody = body
        if includeDiagnostics {
            fullBody += "\n\n---\n" + diagnosticsSummary(connectedModel: connectedModel)
        }

        var components = URLComponents(string: "\(repoURL)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: fullBody),
            URLQueryItem(name: "labels", value: category.githubLabel),
        ]
        return components?.url
    }
}
