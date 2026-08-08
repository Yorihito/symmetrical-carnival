# 設計ドキュメント: app-launch-playbook 準拠によるアプリの底上げ

## 実装状況（2026-08-09 時点）

Phase 0 と Phase 1 の主要部分を実装済み。詳細は各セクションのステータス表記を参照。

- **Phase 0**: 完了。`PrivacyInfo.xcprivacy`（両ターゲット）、`ITSAppUsesNonExemptEncryption`、
  審査ノート（`docs/AppStore/ReviewNotes.md`。実機デモ動画リンクのみ TODO）、主要操作への
  `accessibilityLabel` 付与（電源・音量・ミュート・Zone2/3電源・リモコンD-pad・メニューバー主要ボタン）。
- **Phase 1**: ヘルプサイト（`help/` 配下に index/details/privacy を ja/en で作成、GitHub Actions で
  Pages 公開する構成を用意。**Pages の有効化とリポジトリへの push はユーザー確認待ち**）、
  問題報告・機能リクエスト機能（`ProblemReporter`/`ProblemReportView`。バックエンド無しで GitHub
  `issues/new` の事前入力 URL を開くフォールバック方式のみで実装。診断情報から IP アドレス等の
  ネットワーク情報は意図的に除外）、レビュー依頼機能（`ReviewRequestManager` による接続成功3回・
  初回成功から2日経過後の自動プロンプト、および設定画面からの手動「レビューを書く」導線）を追加。
  オンボーディング/What's New は今回のスコープ外（次回以降）。
- **Phase 3（収益化）**: ユーザーと相談中。既存無料機能の有料化はしない方針で合意。**投げ銭型
  （非消耗型 IAP 1点、機能ゲートなし）が候補**として浮上。フリーミアムより実装コストが低く、
  既存ユーザーへの影響もゼロなため有力だが、詳細設計は未着手。

## 背景・目的

`DenonController` / `DenonControllerMobile` は iOS ダウンロード数が 800 を超え、順調に伸びている。
一方で本アプリは「基本機能（AVR 制御ロジック）」の完成度を優先して作られており、その後に作った
アプリ群で確立した [`app-launch-playbook`](https://github.com/Yorihito/app-launch-playbook/blob/main/ios/PLAYBOOK.md)
（個人開発 iOS アプリの「基本機能の外側」＝配布・信頼性・収益化・審査対策のテンプレ）の内容を
まだ反映していない。

本ドキュメントは、プレイブックの各章を本リポジトリの現状と突き合わせ、何を・なぜ・どの順番で
変更するかを設計するもの。プレイブック §9「設計ドキュメントを残す」の作法に従い `docs/` 配下に置く。

**方針**: 800+ の既存ユーザーがいる無料アプリであることを踏まえ、「壊さず・剥がさず」を大前提にする。
プレイブックは新規アプリのローンチ手順としても書かれているため、**既に公開済みで前提が崩れる項目
（デバイスファミリー等）は適用しない**。同様に収益化のような不可逆・ユーザー影響の大きい変更は
「設計止まり」とし、実装は別途合意のうえで着手する。

---

## 現状棚卸し（プレイブック章立て対照表）

コードベースを実査した結果（`grep`/ファイル確認ベース）:

| 章 | 内容 | 現状 | 根拠 |
|---|---|---|---|
| §0 収益モデル/対象 | 方針決定 | 未決定（無料のみで運用中） | IAP 関連コード・`*.storekit` なし |
| §1 ヘルプサイト | 静的サイト＋言語切替 | **不明・要確認** | `privacy.html` は一度コミットされたが現リポジトリには存在しない（削除済み or 別リポ運用） |
| §2 プライバシーポリシー | 必須 | **要確認**（上と同じ理由） | 同上 |
| §3 問題報告 | GitHub Issue 連携 | 未実装 | `DiagnosticsLog`/`ProblemReporter` 該当コードなし |
| §4 テレメトリ | opt-in 既定オフ | 未実装 | 該当コードなし |
| §5 バックエンド (Worker) | 問題報告/テレメトリの受け口 | 未実装 | `server/` ディレクトリなし |
| §6 収益化（フリーミアム） | StoreKit 2 | 未実装 | `StoreManager` 等なし |
| §7 スクショ自動生成 | DEBUG デモモード | 未実装 | `-uiDemo` 起動引数なし |
| §8 メタデータ/コンプラ | 各種 | **部分実装**（詳細は下） | — |
| §9 ビルド運用 | XcodeGen/CLI/テスト常時緑 | **実装済み**（テストは未整備） | `project.yml` 完備、テストターゲットなし |
| §13 設定画面標準項目 | ガイド/言語/Pro/問題報告等 | **部分実装** | `SettingsView.swift`（両ターゲット）に接続/言語/入力ソース/開発者/バージョン/リセットは有、ガイド・Pro・プライバシー導線・問題報告は無 |
| §14 オンボーディング/What's New | 初回導線 | 未実装 | 該当コードなし |
| §15 権限 usage 文言/プライミング | ローカルネットワーク | **usage 文言は実装済み**、プライミング画面は無 | `NSLocalNetworkUsageDescription` あり |
| §16 PrivacyInfo.xcprivacy | 必須級 | **未実装（リスクあり）** | `find . -iname "*.xcprivacy"` 該当なし。`UserDefaults` は 11 ファイルで使用中＝ required reason API 対象 |
| §17 ローカライズ基盤 | 全文言ローカライズ | **実装済み・模範的** | `LocalizationHelper.swift` 等、CLAUDE.md にも設計思想が明文化済み |
| §18 アクセシビリティ | VoiceOver/Dynamic Type | **未着手** | `accessibilityLabel` の使用箇所が**リポジトリ全体で 0 件**。アイコンのみのボタン（`systemImage:`）は 68 箇所 |
| §19.1 起動画面2段 | ランチスクリーン+スプラッシュ | **実装済み（iOS）** | `UILaunchScreen`（`LaunchBackground`/`SplashIcon`）設定済み |
| §22 セキュリティ/ATS | シークレット管理・ATS | 該当なし（LAN 内 HTTP のみ、外部秘密鍵は不使用） | 問題なし |
| §24 TestFlight | 実機ベータ | 運用実態は不明（プロセスとして文書化されていない） | — |
| §25 ASO | ストア最適化 | **高品質に実装済み** | `docs/AppStore/Metadata_{iOS,Mac}.md` が UX 訴求重視で作り込まれている |
| §26 CI | `xcodebuild test` | 未整備（テストターゲット自体が存在しない） | CLAUDE.md に明記 |

### §8 の内訳（メタデータ/コンプライアンス）

- ✅ アプリアイコン 1024×1024: iOS/macOS 双方に存在
- ✅ バージョニング: `git rev-list --count HEAD` によるビルド番号自動採番（`project.yml` に実装済み、プレイブックと同一パターン）
- ❌ `ITSAppUsesNonExemptEncryption`: `Info.plist`（iOS/macOS 両方）に未設定 → 提出のたびに暗号化質問に手動回答している状態
- ⚠️ `TARGETED_DEVICE_FAMILY`: `"1,2"`（ユニバーサル）。プレイブック §0/§8 は「iPhone 専用が最短」を推奨するが、**本アプリは既に iPad 最適化を掲げて公開済み**（README・Metadata_iOS.md に Split View/Stage Manager 訴求あり）。この項目は新規ローンチ向けの助言であり **本アプリには適用しない**。
- ⚠️ 外部ハードウェア依存の審査対策（§8 の実例注記）: 本アプリは「同一 LAN 上の実機 AVR」が前提の Denon/Marantz 専用アプリで、プレイブックが名指しする失敗パターン（TV REMOTE for B, Guideline 2.1, 2026-07-02）と**構造が同一**。現在の Review Notes に実機デモ動画リンクが用意されているかは不明 → 要確認・是正。

---

## 変更方針・フェーズ計画

リスクが低くやるべき順にフェーズ分けする。フェーズ間の依存はあるが、フェーズ内は並行実施可能。

```
Phase 0  審査リスク潰し（必須・低コスト・破壊的変更なし）
   │
Phase 1  ユーザー導線・信頼性の底上げ（設定画面再構成＋問題報告）
   │
Phase 2  ストア提出の安定化・ASO仕上げ（スクショ自動化・レビューノート）
   │
Phase 3  収益化（要判断・任意・既存ユーザーへの影響大）
   │
Phase 4  運用基盤（テレメトリ・CI）（任意・優先度低）
```

---

## Phase 0: 審査リスク潰し（必須）

次回アップデート提出で足を止めうる項目を先に潰す。ユーザー影響もリスクもゼロ。

| 項目 | 変更内容 | 対象ファイル |
|---|---|---|
| プライバシーマニフェスト | `PrivacyInfo.xcprivacy` を両ターゲットに追加。`NSPrivacyAccessedAPICategoryUserDefaults` + reason `CA92.1` を宣言（`PresetStore`/`InputNameStore` 等 11 ファイルが `UserDefaults` を使用） | 新規: `DenonController/DenonController/PrivacyInfo.xcprivacy`, `DenonControllerMobile/PrivacyInfo.xcprivacy`（`project.yml` の `sources` に追加、XcodeGen で自動バンドル） |
| 輸出コンプラ申告の自動化 | `ITSAppUsesNonExemptEncryption` = `false` を追加（標準 TLS のみ・独自暗号なし） | `DenonController/DenonController/Info.plist`, `DenonControllerMobile/App/Info.plist` |
| 審査ノート整備 | 「同一 LAN 上に対応 AVR が必要。無い場合は検出画面で止まるのが仕様」を明記し、実機（iPhone/iPad）+実機 AVR の動作デモ動画（限定公開）へのリンクを追加。プレイブック §8 の実例（TV REMOTE for B, Guideline 2.1）を踏まえた予防措置 | `docs/AppStore/` に `ReviewNotes.md` を新設、次回提出時に ASC の App Review 情報欄へ転記 |
| サポート/プライバシー URL の生存確認 | `privacy.html` が本リポジトリから既に削除されている（別リポ運用の可能性）。ASC に登録中の Support URL / Privacy Policy URL が現在も 200 で応答するか確認。死んでいれば §1/§2 に沿ってヘルプサイトを再構築 | 確認のみ（結果次第で Phase 1 に着手） |
| アクセシビリティの最小ライン | まず主要操作（電源/音量/ミュート/入力切替/リモコン方向パッド）のアイコンのみボタンに `accessibilityLabel` を付与。現状 68 箇所中 0 件対応 | `Views/MainWindow/*.swift`, `Views/Shared/*.swift`, `DenonControllerMobile/Views/*.swift` |

---

## Phase 1: ユーザー導線・信頼性の底上げ

### 1-A. 設定画面の再構成（§13 準拠）

現行の `SettingsView`（macOS/iOS 両方）はセクション自体は良い出来だが、プレイブックが「ほぼ全アプリに
必須」とする導線が抜けている。並び順をプレイブック推奨（ガイド→言語→接続/状態→バージョン→Pro→
プライバシーと改善→問題を報告→機能トグル→管理操作→開発者モード）に寄せつつ、次を追加する。

| 追加セクション | 内容 | 対象ファイル |
|---|---|---|
| ユーザーガイド | ヘルプサイトへのリンク（端末言語で `/` or `/en/` 出し分け） | 両 `SettingsView.swift` |
| プライバシーと改善 | プライバシーポリシーへのリンク（テレメトリは Phase 4 まで見送り、まずはリンクのみ） | 同上 |
| 問題を報告 | 1-B の `ProblemReportView` への導線。「この内容は公開されます」注記付き | 同上 |

Pro 導線は Phase 3 の意思決定後に追加するプレースホルダーとし、今は入れない。

### 1-B. 問題報告・機能リクエスト機能（§3）— 実装済み

現状ユーザーの不具合報告手段が無かったため実装。**プレイブック §3/§5 が前提とする Cloudflare
Worker プロキシ＋GitHub トークンは今回は作らず、`issues/new` の事前入力 URL をブラウザで開く
フォールバック方式のみで実装した**（バックエンド運用コストを避けつつ、バグ報告と機能リクエストを
GitHub Issue として受け取るという目的は満たせるため）。

- `Core/Diagnostics/ProblemReporter.swift`: `ProblemReportCategory`（bug/feature/other、GitHub の
  既定ラベルに対応）と、診断情報（アプリ版・OS・機種・言語・接続中の AVR 機種名）を含めた
  `issues/new` URL を組み立てる。**IP アドレス等のネットワーク情報は意図的に含めない**
  （`defaultHost` はユーザーのローカル AVR アドレスであり、公開 Issue に載せるべきではないため）。
- `Views/Shared/ProblemReportView.swift`: 種類選択・タイトル・本文（カテゴリ別テンプレート）・
  診断情報を含めるトグル・「公開されます／個人情報を書かないで」の警告を表示し、GitHub をブラウザで開く。
- 送信先リポジトリは `https://github.com/Yorihito/symmetrical-carnival`（既存の公開リポジトリ）に
  固定。ユーザー向けの報告先として適切かは要確認（§判断が必要な項目）。
- 将来的にバックエンド経由の自動投稿（§5 のパターン）に切り替えたくなった場合も、
  `ProblemReporter.issueURL` の呼び出し側を差し替えるだけで済む構成にしてある。

### 1-C. オンボーディング / What's New（§14）— 未実装（次回以降）

今回のスコープからは外した。差別化機能（Zone2/3・OSD リモコン・チューナープリセット）を
1〜数枚で見せる初回フローと、`CFBundleShortVersionString` 起点の What's New は次フェーズで着手する。

### 1-D. ヘルプサイトの再確認/再構築（§1・§2）— 実装済み（公開は未実施）

現況確認の結果、`privacy.md`（GitHub の生の blob 表示）が Support/Privacy URL として使われていた
ことが判明。プレイブック標準（静的 HTML・ja/en・index/details/privacy・タブナビ）に合わせて
作り直した。

- `help/`（ja: `index.html`/`details.html`/`privacy.html`）と `help/en/`（英語版）、共通 `style.css`
  を新規作成。過去にコミットされていた `privacy.html`（Apple 風テンプレート）のデザインを踏襲。
- `.github/workflows/pages.yml`: `help/` を GitHub Actions 経由で GitHub Pages にデプロイする構成
  （`actions/upload-pages-artifact` + `actions/deploy-pages`）。プレイブックが推奨する「別リポへ
  ミラー」ではなく、**本リポジトリが既に public なため直接 Pages 化**する方式を採用（別リポ管理の
  手間を避けるため）。
- アプリ側は `Core/Diagnostics/HelpSiteLinks.swift` で `https://yorihito.github.io/symmetrical-carnival/`
  を起点に、端末言語に応じて `/` か `/en/` を出し分けるリンクを生成し、設定画面から参照。
- **Pages の有効化（リポジトリ設定変更）と `help/`・ワークフローの push は未実施**。公開はユーザーの
  明示的な合意を得てから行う（§判断が必要な項目）。

### 1-E. レビュー依頼機能（§6 の一部）— 実装済み

収益化とは独立に、既存ユーザーへのレビュー依頼を追加。

- `Core/Review/ReviewRequestManager.swift`: 接続成功回数・初回成功日を `UserDefaults` に記録し、
  「3回成功」かつ「初回成功から2日経過」かつ「そのバージョンでまだ依頼していない」場合にのみ
  `true` を返す判定ロジック（状態管理のみ、表示はしない）。
- `ContentView`（macOS/iOS）で `\.requestReview`（SwiftUI 標準の `RequestReviewAction`、要 `import
  StoreKit`）を接続成功時に条件付きで呼び出す。OS 側の表示頻度制御にも従う。
- 設定画面に「レビューを書く」ボタンを追加し、いつでも明示的に `requestReview()` を呼べるようにした
  （こちらは頻度制限をかけず、ユーザー主導の操作として毎回呼ぶ）。App Store の商品ページへの直接
  リンク（`?action=write-review`）は Apple 側の数値 App ID が必要なため今回は見送り。

---

## Phase 2: ストア提出の安定化・ASO仕上げ

- **スクリーンショット自動生成**（§7）: `#if DEBUG` 限定の `-uiDemo` / `-uiDemoTab` 起動引数を実装し、
  `activate()`/`refreshStatus()` 等のネットワーク更新を demo 時 no-op 化。`simctl` スクリプトで
  6.9"・ja/en を自動キャプチャ。**現状のスクリーンショットが古い/手動撮影であれば置き換え候補**。
- **ASO の微調整**（§25）: `docs/AppStore/Metadata_*.md` は既に UX 訴求重視で高品質。プレイブックの
  「実在する検索行動の証拠で選ぶ」原則に沿って、キーワードの追加候補があれば裏取りしてから採用する
  軽微なチューニングに留める（作り直しは不要）。
- **提出フロー・頻出ハマりどころの再確認**（§10・§11）: Phase 0 で作成した `ReviewNotes.md` を
  次回提出時に転記する運用を確立。

---

## Phase 3: 収益化（要判断・検討中）

プレイブック §6 はフリーミアム（無料+買い切り Pro）を個人アプリの定石として推奨しているが、
**本アプリは既に無料で 800+ ダウンロードを獲得し、Zone2/3・OSD リモコン・チューナープリセット等の
主要機能を無料開放済み**。この状態から機能を有料化すると既存ユーザーの信頼を損ね、低評価レビューの
リスクが高いため、既存機能の有料化はしない方針で合意済み。

**検討中の方向性: 投げ銭型（非消耗型 IAP 1点、機能ゲートなし）**。「開発者を応援」のような単一の
非消耗型 IAP を設定へのボタンとして置くだけで、購入有無で機能や UI を分岐させるロジックが不要になる
（`isPro` 判定・ペイウォール・トライアル管理が丸ごと不要）。実装コストが最小で、既存ユーザーへの
影響もゼロという利点がある一方、フリーミアムに比べ収益は小さくなりがちというトレードオフがある。

フリーミアム自体を完全に捨てるわけではなく、**今後追加する新規の差別化機能（例: マルチルーム操作の
シーン/マクロ機能、ウィジェット、複数 AVR プロファイル管理など）が生まれた時点で改めて Pro 化を
検討する**余地は残す。StoreKit 2 基盤（`StoreManager`/トライアル/`Products.storekit`/プロモコード）
は §6 のパターンをそのまま踏襲できる。

→ **ユーザー確認事項**: 投げ銭型で進めてよいか（商品名・価格帯・設置場所）。詳細設計は合意後に
着手する。

---

## Phase 4: 運用基盤（任意・優先度低）

- **テレメトリ**（§4）: 本アプリは現状サードパーティ解析 SDK 不使用・栄養ラベルが単純という
  プレイブックが推奨する「良い状態」を既に満たしている。opt-in テレメトリを追加するメリット
  （利用状況の可視化）と複雑性増加を比較すると、**現時点では見送りが妥当**。Phase 1-B で Worker
  基盤を作った後、規模が大きくなった段階で `/telemetry` エンドポイントを足す形で乗せるのが低コスト。
- **CI**（§26）: 現状テストターゲットが存在しない（CLAUDE.md に明記）。CI を組む前提として、まず
  純粋ロジック（`ProblemReporter` の PII マスク、URL エンコード、将来 IAP を入れるなら権利判定等）を
  UI/ネット非依存に切り出し、単体テストを整備する必要がある。CI 自体はテストが揃ってから GitHub
  Actions で `xcodebuild test` を回す最小構成でよい。

---

## 判断が必要な項目（実装着手前にユーザーに確認）

1. **収益化の詳細（Phase 3）**: 投げ銭型の方向で進めてよいか。商品名・価格・設置場所（設定画面内が
   有力）を決める。
2. **ヘルプサイトの公開**: `help/` と `.github/workflows/pages.yml` を push し、GitHub Pages を
   有効化してよいか（リポジトリ設定の変更・公開ページが実際にインターネットに出る操作のため確認）。
   有効化後は ASC の Support URL / Privacy Policy URL を新しい URL に更新する必要がある（手動作業）。
3. **問題報告の送信先リポジトリ**: 現在は `Yorihito/symmetrical-carnival`（このリポジトリ）に固定。
   アプリ名と異なる内部的なリポジトリ名がユーザーに見える点をどう考えるか（専用リポジトリを別途
   作る／このままで良い、のいずれか）。
4. **レビュー導線の App Store 直リンク**: 「レビューを書く」を App Store の商品ページへ直接飛ばす
   実装（`?action=write-review`）には、ASC 上の数値 App ID（iOS 版・Mac 版それぞれ）が必要。
   分かれば追加できる。
5. **テレメトリ導入の要否（Phase 4）**: 見送り推奨だが、利用状況を知りたいニーズがあれば前倒しも可能。
6. **アクセシビリティ対応の範囲**: 今回は主要操作（電源・音量・ミュート・Zone2/3電源・リモコン
   D-pad・メニューバー主要ボタン）のみ対応。残りの入力ソース選択・サラウンドモード選択・プリセット
   カード等への展開は Phase 1 以降に段階実施でよいか。

---

## 実行チェックリスト

- [x] **Phase 0**: `PrivacyInfo.xcprivacy`（両ターゲット）／`ITSAppUsesNonExemptEncryption: false`／
      審査ノート（実機デモ動画リンクのみ TODO）／主要操作の `accessibilityLabel`
- [x] **Phase 1（コード面）**: 設定画面再構成（ガイド/プライバシー/問題報告/レビューのリンク追加）／
      `ProblemReporter`+`ProblemReportView`（バックエンド無しの GitHub prefill 方式）／
      `ReviewRequestManager`＋レビュー依頼導線／ヘルプサイト（`help/`）作成
- [ ] **Phase 1（公開作業・要合意）**: `help/` と Pages ワークフローの push／GitHub Pages 有効化／
      ASC の Support・Privacy URL 更新
- [ ] **Phase 1（次回以降）**: オンボーディング＋What's New
- [ ] **Phase 2**: DEBUG デモモード＋`simctl` スクショ自動化／ASO 微調整／提出フロー運用確立
- [ ] **Phase 3**（検討中）: 投げ銭型 IAP の詳細設計・実装
- [ ] **Phase 4**（任意）: 単体テスト整備 → CI → （必要なら）テレメトリ
