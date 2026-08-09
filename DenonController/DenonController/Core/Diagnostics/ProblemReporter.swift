import Foundation

#if os(iOS)
import UIKit
#endif

/// 「問題を報告」機能の報告種別。GitHub の既定ラベルに対応させる
/// （送信プロキシ側でも同じ対応表でラベルを決めるため、両者を一致させておくこと）。
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

/// バグ報告・機能リクエストを GitHub Issue として送信するためのヘルパー。
///
/// 送信先は Cloudflare Worker のレポートプロキシ（`server/`）。GitHub 書き込みトークンは
/// **サーバ側のシークレットとしてのみ**保持し、アプリには一切埋め込まない。プロキシが
/// 未設定・到達不能な場合は `issues/new` の事前入力 URL を開くフォールバックに切り替える。
enum ProblemReporter {
    /// 報告が届く公開リポジトリ（フォールバック URL の組み立てに使用）。
    static let repo = "Yorihito/symmetrical-carnival"

    struct Report: Equatable {
        var category: ProblemReportCategory
        var title: String
        var body: String
    }

    /// レポート本文に折り込む診断情報。IP アドレス・MAC アドレス・ホスト名などの
    /// ネットワーク識別子は構造上含まれない。`lastError` はバックストップとして
    /// `DiagnosticsLog.redact` を通す。
    struct Context {
        var appVersion: String
        var build: String
        var platform: String
        var locale: String
        var connectedModel: String?
        var lastError: String?
        var logs: String
    }

    static func currentContext(connectedModel: String?, lastError: String?, includeLogs: Bool) -> Context {
        let bundle = Bundle.main
        return Context(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            platform: platformDescription(),
            locale: Locale.current.identifier,
            connectedModel: connectedModel,
            lastError: lastError,
            logs: includeLogs ? DiagnosticsLog.shared.export() : ""
        )
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

    // MARK: - Building

    /// 既定のタイトル＋本文（Markdown）。ユーザーは送信前に自由に編集できる。
    static func makeReport(category: ProblemReportCategory, context: Context) -> Report {
        let title = category == .feature
            ? String(localized: "機能リクエスト")
            : String(localized: "問題を報告")

        var body = template(for: category)
        body += "\n\n---\n"
        body += "- App: \(context.appVersion) (\(context.build))\n"
        body += "- Platform: \(context.platform)\n"
        body += "- Locale: \(context.locale)\n"
        if let model = context.connectedModel, !model.isEmpty {
            body += "- Connected AVR model: \(model)\n"
        }
        if let error = context.lastError, !error.isEmpty {
            body += "- Last error: \(DiagnosticsLog.redact(error))\n"
        }
        if !context.logs.isEmpty {
            body += "\n<details><summary>Recent logs</summary>\n\n```\n\(context.logs)\n```\n</details>\n"
        }
        return Report(category: category, title: title, body: body)
    }

    private static func template(for category: ProblemReportCategory) -> String {
        switch category {
        case .bug:
            String(localized: "起きたこと:\n\n再現手順:\n\n期待した動作:\n")
        case .feature:
            String(localized: "実現したいこと:\n\n背景・理由:\n")
        case .other:
            ""
        }
    }

    // MARK: - Endpoint

    /// レポートプロキシの URL（`project.yml`/`Info.plist` の `AVRReportEndpoint`）。
    /// 未設定（空文字）ならプロキシは使わずフォールバックのみで動作する。
    static func endpoint() -> URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "AVRReportEndpoint") as? String,
              !s.isEmpty, let url = URL(string: s) else { return nil }
        return url
    }

    // MARK: - Submission

    enum SubmitError: LocalizedError {
        case notConfigured
        case server(Int)
        case malformedResponse
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                String(localized: "送信先が設定されていません。")
            case .server(let code):
                String(localized: "送信に失敗しました。") + " (HTTP \(code))"
            case .malformedResponse:
                String(localized: "送信に失敗しました（応答が不正）。")
            case .transport(let message):
                message
            }
        }
    }

    /// プロキシへ POST し、作成された Issue の URL を返す。
    static func submit(_ report: Report, session: URLSession = .shared) async throws -> URL {
        guard let endpoint = endpoint() else { throw SubmitError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": report.title,
            "body": report.body,
            "category": report.category.rawValue,
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SubmitError.malformedResponse }
            guard (200..<300).contains(http.statusCode) else { throw SubmitError.server(http.statusCode) }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = object["url"] as? String,
                  let url = URL(string: urlString) else {
                throw SubmitError.malformedResponse
            }
            return url
        } catch let error as SubmitError {
            throw error
        } catch {
            throw SubmitError.transport(error.localizedDescription)
        }
    }

    // MARK: - Fallback

    /// プロキシが未設定・到達不能なときのフォールバック: GitHub の「Issue を作成」画面を
    /// 事前入力状態で開く URL。GitHub の URL 長制限があるため本文を切り詰める。
    static func prefilledIssueURL(_ report: Report, maxBody: Int = 6000) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")
        let body = report.body.count > maxBody ? String(report.body.prefix(maxBody)) + "\n\n…(truncated)" : report.body
        components?.queryItems = [
            URLQueryItem(name: "title", value: report.title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: report.category.githubLabel),
        ]
        return components?.url
    }
}
