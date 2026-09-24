import Foundation

/// アプリが自分から知らせる新機能の案内。案内ごとに一度だけ出す。
enum FeatureIntro: String, Sendable {
    case volumeDial
}

/// アプリが自分から出すお願い・案内。1 回の起動で出すのは 1 つまで（`PromptCoordinator` が管理）。
/// 設計: docs/in-app-prompts-design.md
enum InAppPrompt: Equatable, Sendable {
    case featureIntro(FeatureIntro)
    case compatibility
    case review
    case support
}
