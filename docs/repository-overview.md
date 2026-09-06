# リポジトリ調査結果（現状スナップショット）

調査日: 2026-09-04

対象ブランチ: `main`

対象コミット: `1ab02ab` (`Update design doc: problem report now uses the Worker proxy pattern`)

## 1. 概要

このリポジトリは、同一 LAN 上の Denon / Marantz 製 AV レシーバー（AVR）を操作する
「AVR Controller」のソースコードと、その配布・サポートに必要な資材を管理している。

主な成果物は次の3つである。

1. iOS / iPadOS アプリ（リリース対象）
2. macOS アプリ（通常ウィンドウおよびメニューバー常駐。**凍結中、リリース対象外**）
3. ヘルプサイトおよび問題報告用 Cloudflare Worker

> **macOS アプリの凍結について（2026-09-06 決定）**
> macOS 版はリリースしない方針となり、現時点で開発を凍結している。ビルド・動作確認・機能追加の
> 対象外とし、検証は iOS ターゲット（`DenonControllerMobile`）のみで行う。macOS 固有コード
> （`DenonController/App/`、`Views/MainWindow/`、`Views/Settings/`）は共有コードと同居しているため
> 削除せずそのまま残すが、iOS への機能追加時に追随させる必要はない。App Store 関連の作業
> （審査メモ、プライバシーポリシー、スクリーンショット）も iOS のみを対象とする。

アプリは Swift 6 / SwiftUI で実装され、外部パッケージには依存していない。実装とドキュメント上の
主な確認対象機種は Denon AVR-X3800H である。

## 2. 現在のリポジトリ状態

調査時点では作業ツリーに未コミットの変更はない。ローカルの `main` は `origin/main` より2コミット
先行しており、先行分は問題報告機能を Cloudflare Worker プロキシ方式へ変更した実装と、その設計資料の
更新である。

なお、Git の状態確認時に fsmonitor IPC の警告が表示されたが、`git status` 自体は取得できており、
作業ツリーの差分は検出されなかった。

## 3. 技術構成

| 項目 | 内容 |
|---|---|
| 言語 | Swift 6、JavaScript（Cloudflare Worker）、HTML / CSS |
| UI | SwiftUI |
| 状態管理 | Observation（`@Observable`） |
| 設計 | MVVM |
| macOS 最小バージョン | macOS 14.0 |
| iOS / iPadOS 最小バージョン | iOS 17.0 |
| プロジェクト生成 | XcodeGen (`DenonController/project.yml`) |
| 外部依存 | なし |
| 永続化 | `UserDefaults` |
| AVR 検出 | Bonjour / mDNS |
| AVR 操作・状態取得 | HTTP、Telnet |
| テスト | テストターゲットなし。実機または UI の手動確認が前提 |

Swift ソースは調査時点で50ファイル、合計約8,500行である。

## 4. ディレクトリ構成

```text
symmetrical-carnival/
├── DenonController/
│   ├── project.yml                 # XcodeGen定義（macOS/iOS両ターゲット）
│   ├── DenonController/            # macOSアプリと共有コード
│   │   ├── App/                    # macOSエントリポイント、AppDelegate
│   │   ├── Core/                   # 通信、モデル、永続化、診断など
│   │   ├── ViewModels/             # MainViewModel
│   │   ├── Views/                  # macOS固有および共有View
│   │   └── Resources/Localization/ # 日英ローカライズ
│   └── DenonController.xcodeproj/  # 生成済みXcodeプロジェクト
├── DenonControllerMobile/          # iOS/iPadOS固有コードとアセット
├── help/                           # GitHub Pages向け日英ヘルプサイト
├── server/                         # 問題報告用Cloudflare Worker
├── docs/                           # 設計・App Store提出関連資料
├── REQUIREMENTS.md                 # 当初の要件定義
└── README.md                       # プロジェクト紹介
```

`DenonControllerMobile` ターゲットは、ルート直下の iOS 固有コードに加え、macOS側のディレクトリにある
`Core/`、`ViewModels/`、`Views/Shared/`、ローカライズ資材を共有する。この包含関係は
`DenonController/project.yml` が定義している。

## 5. アプリケーションアーキテクチャ

中心となるデータフローは次のとおりである。

```text
SwiftUI Views
    ↓ @Environment
MainViewModel (@Observable, @MainActor)
    ├── AVRHTTPClient (actor)
    │   ├── HTTPコマンド送信
    │   └── XMLステータスのポーリング
    ├── TelnetClient (actor)
    │   └── AVRからのリアルタイム通知受信
    ├── MDNSDiscovery / MDNSScanner
    │   └── LAN上のAVR検出
    ├── AVRState
    │   └── 画面表示に使う現在状態
    ├── PresetStore
    └── InputNameStore
```

`MainViewModel` が接続管理とすべての AVR 操作の窓口であり、各 SwiftUI View は原則として
`MainViewModel` を環境から取得する。

### 5.1 HTTP通信

`AVRHTTPClient` は Denon の HTTP API を担当する。デフォルトの接続ポートは8080で、主に次の処理を行う。

- `/goform/Deviceinfo.xml` による機種情報取得
- `/goform/formiPhoneAppDirect.xml?<COMMAND>` によるコマンド送信
- Main Zone / Zone 2 の XML ステータス取得
- Zone 3 対応可否の確認
- チューナー情報とプリセット情報の取得
- 操作直後は高頻度、その後は状況に応じて間隔を調整するポーリング

通信には `URLSession` や `NWConnection` ではなく BSD ソケットを直接使用している。これはインターネットに
到達できないローカル Wi-Fi や複数インターフェース環境で、Apple のネットワーク到達性判定に通信を
阻害されないための意図的な設計である。

### 5.2 Telnet通信

`TelnetClient` は TCP 23番ポートへ接続し、主にサラウンドモードやチューナー状態の変更通知を受け取る。
HTTP接続の成立がアプリ上の主接続であり、Telnet接続の失敗は補助機能の失敗として扱われる。

### 5.3 状態同期

UI操作時は `AVRState` を先に更新する楽観的更新を行い、その直後のポーリング結果によって古い状態へ
戻されないよう、操作種別ごとに短時間の同期抑止を設けている。

接続失敗時には、保存済み MAC アドレスを手掛かりとして mDNS 再検索を行い、DHCPによってIPアドレスが
変わった同一AVRへの再接続を試みる。再検索は多重実行と過剰な再試行を避けるため制限されている。

## 6. 実装済みの主な機能

- AVRの自動検出およびIPアドレス手動指定
- 接続、切断、自動接続、IP変更時の自動復旧
- Main Zoneの電源、音量、ミュート
- Main Zone音量のスライダー／回転ダイアル切り替え（初期値はスライダー）
- 入力ソース切り替えと表示名のカスタマイズ
- サラウンドモード切り替え
- Zone 2 / Zone 3の電源・音量等の操作
- AVRのOSD方向キー、決定、戻る、情報、オプション、セットアップ操作
- FM / AMチューナー操作
- 1〜56番のチューナープリセット走査、保存、重複・指定周波数の除外
- 入力、音量、サラウンドモードをまとめたアプリ内プリセット
- macOSメニューバーからのクイック操作
- 日本語・英語ローカライズとアプリ内言語切り替え
- 診断情報付きの問題報告・機能リクエスト
- 接続実績に基づくApp Storeレビュー依頼
- 接続成功後に1回だけ表示する音量ダイアル紹介

## 7. プラットフォーム別UI

### macOS（凍結中）

リリース対象外であり、開発を凍結している。以下は参考情報である。
通常のメインウィンドウと `MenuBarExtra` の両方を提供する。メニューバー専用モードでは SwiftUI の
ウィンドウ管理と衝突しないよう、ウィンドウを閉じるのではなく透明化して操作対象から外す実装を採用して
いる。また、Dock表示の有無に応じてアプリの activation policy を切り替える。

### iPhone

ホーム、チューナー、入力ソース、リモコン、ゾーン、設定を `TabView` で切り替える。

### iPad

`NavigationSplitView` を使ったサイドバー形式で、主要画面を切り替える。

## 8. ローカライズ

開発言語は日本語である。Swiftコード内の日本語リテラルをキーとして使用し、
`en.lproj/Localizable.strings` で英訳する方式を採っている。設定値 `appLanguage` が `ja` / `en` /
`system` のいずれかを保持し、SwiftUIの locale と参照Bundleを切り替える。

## 9. ヘルプサイト

`help/` には日本語版、`help/en/` には英語版の次のページがある。

- かんたんガイド
- 詳細ガイド
- プライバシーポリシー

`.github/workflows/pages.yml` は、`main` の `help/**` 更新時に `help/` を GitHub Pages へ公開する。
設計資料によると、サイトは `https://yorihito.github.io/symmetrical-carnival/` で公開済みである。

## 10. 問題報告機能とCloudflare Worker

アプリ内の問題報告画面は、カテゴリ、タイトル、本文、PIIを除いた診断情報をまとめて送信する。診断ログは
リングバッファで保持し、IPv4、IPv6、MACアドレスをマスクする。

送信経路は次の2段構成である。

1. `AVRReportEndpoint` が設定されている場合、Cloudflare WorkerへJSONをPOSTする
2. 未設定または送信失敗時、入力済み内容を使ってGitHubのIssue作成画面をブラウザで開く

Workerは受信した報告から公開GitHub Issueを作成する。GitHubトークンはWorkerのsecretにのみ保存し、
アプリには含めない。Worker側には次の対策がある。

- タイトル・本文長の制限
- 実受信バイト数に基づくリクエストサイズ制限
- 固定されたカテゴリ／ラベル対応表
- 送信元IP単位および全体の時間当たりレート制限
- 生のIPアドレスを保存しない、ソルト付きハッシュキー
- 必須secretやKVがない場合のfail closed

### 調査時点のデプロイ状態

Workerはまだ利用可能な構成になっていない。

- `server/wrangler.toml` の KV namespace ID は `REPLACE_WITH_KV_NAMESPACE_ID` のまま
- macOS / iOS双方の `Info.plist` にある `AVRReportEndpoint` は空文字
- `GITHUB_TOKEN` と `RATE_SALT` はCloudflare上で設定する必要がある

したがって、現時点のアプリはブラウザでGitHub Issue作成画面を開くフォールバック経路を使用する。

## 11. ビルドと検証

Swiftファイルを追加または削除した場合は、先にXcodeGenでプロジェクトを再生成する。

```bash
cd DenonController
xcodegen generate
```

ビルド対象は iOS ターゲットのみである（macOS は凍結中のためビルド不要）。リポジトリルートからの
基本的なビルドコマンドは次のとおりである。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild -project ./DenonController/DenonController.xcodeproj \
  -scheme DenonControllerMobile \
  -destination 'generic/platform=iOS' build

# 署名チーム未設定で上記が失敗する場合は、シミュレータ向けにコンパイル確認する
xcodebuild -project ./DenonController/DenonController.xcodeproj \
  -scheme DenonControllerMobile -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

macOS ターゲット（`DenonController` scheme）のビルドコマンドは参考として残す。

```bash
# 参考のみ。macOS 版は凍結中のため検証には使わない
xcodebuild -project ./DenonController/DenonController.xcodeproj \
  -scheme DenonController \
  -destination 'platform=macOS,arch=arm64' build
```

テストターゲットとアプリ本体のビルドCIは存在しない。現在のGitHub Actionsはヘルプサイトの
GitHub Pages公開のみである。今回の調査ではコードの読み取りを目的とし、ビルドは実行していない。

## 12. ドキュメントの位置付けと差異

`README.md` と `REQUIREMENTS.md` には初期構想や古い情報が一部残っている。例えばHTTPポート、対応OS、
ロードマップのチェック状態などは現行実装と一致しない箇所がある。

今後の実装判断では、次の順に現状を確認するのが安全である。

1. 現行ソースコード
2. `DenonController/project.yml`
3. ルートの `CLAUDE.md`
4. `docs/` 内の個別設計資料
5. `README.md` / `REQUIREMENTS.md` の初期資料

## 13. 現時点で把握している未完了事項

- Cloudflare WorkerのKV作成、secret設定、デプロイ
- デプロイ後の `AVRReportEndpoint` 設定
- App Store審査用の実機デモ動画作成
- App Store Connect上のSupport URL / Privacy Policy URL確認
- 収益化方式、テレメトリ、追加アクセシビリティ対応の判断
- 自動テストおよびアプリ本体のCI整備

## 14. 主要ファイル

| ファイル | 役割 |
|---|---|
| `DenonController/project.yml` | 両アプリターゲット、共有ソース、ビルド設定の基準 |
| `DenonController/DenonController/ViewModels/MainViewModel.swift` | 接続・状態同期・AVR操作の中枢 |
| `DenonController/DenonController/Core/Network/AVRHTTPClient.swift` | HTTP API、XML解析、ポーリング、BSDソケット通信 |
| `DenonController/DenonController/Core/Network/TelnetClient.swift` | Telnet接続と通知ストリーム |
| `DenonController/DenonController/Core/Network/MDNSDiscovery.swift` | Bonjour / mDNSデバイス検出 |
| `DenonController/DenonController/Core/Models/AVRState.swift` | AVRの表示状態モデル |
| `DenonController/DenonController/App/DenonControllerApp.swift` | macOSアプリのScene定義 |
| `DenonControllerMobile/App/DenonControllerMobileApp.swift` | iOS / iPadOSアプリのエントリポイント |
| `DenonController/DenonController/Core/Diagnostics/ProblemReporter.swift` | 問題報告本文生成、Worker送信、ブラウザフォールバック |
| `server/worker.js` | GitHub Issue作成プロキシ |
| `.github/workflows/pages.yml` | ヘルプサイトのGitHub Pages公開 |
| `docs/playbook-alignment.md` | 配布・運用改善の計画と進捗 |

---

この文書は調査時点の実装を記録したスナップショットである。機能追加、ターゲット設定変更、Workerの
デプロイなどを行った場合は、対象コミットと「未完了事項」を更新する必要がある。
