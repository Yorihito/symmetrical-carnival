# 動作報告の仕組み — 設計

作成: 2026-09-23 / 対象: 1.2.0 以降 / iOS・iPadOS のみ

ユーザーに「自分の機種で動いた（動かなかった）」を報告してもらい、それを自動で集計して
「動作確認済み機種」を増やしていく仕組み。Denon / Marantz にも Yamaha にも使う。
今ある「ご意見・ご要望を送る」の送信経路（アプリ → Cloudflare Worker → GitHub issue）をそのまま使う。

関連: [yamaha-support-design.md](yamaha-support-design.md)（Yamaha 対応。テストできる実機が RX-V581 しかないので、この仕組みが前提になる）

---

## 1. 目的と方針

- **手間をかけずに送れること。** 機種名・アプリのバージョンは自動で入れる。ユーザーは機能ごとに「動いた / 動かなかった / 使っていない」を選ぶだけ。自由記述は任意。
- **集計は自動、公開はヘルプサイト。** 報告は GitHub issue として溜め、GitHub Actions で機種ごとに集計してヘルプサイトの「対応機種」ページを作り直す。開発者が手で表を直す作業をなくす。
- **App Store のメタデータには載せない。** 1.1.0 の審査で決めた商標の方針のまま。機種名が並ぶのはヘルプサイトだけにする（非提携の注記付き）。
- **個人を特定できる情報は送らない。** IP アドレス・MAC アドレス・機器に付けた名前は含めない（今の報告と同じ扱い）。報告は公開の issue になることを画面に明記する。
- **今の仕組みを壊さない。** 古いバージョンのアプリからの報告は、これまでどおり届く。

---

## 2. 全体の流れ

```
アプリ（動作報告の画面）
   │  POST /report  { category: "compatibility", compat: {...}, body: "任意のコメント" }
   ▼
Cloudflare Worker（server/worker.js）
   │  compat を検証 → タイトルと本文（人が読む表＋機械が読むデータ）を作る
   │  ラベル: compatibility ＋ brand:denon など
   ▼
GitHub issue（公開）
   │
   ▼
GitHub Actions（pages.yml を拡張。issue の作成・編集時と毎日 1 回）
   │  compatibility ラベルの issue を全部読む → 機種ごとに集計
   │  help/compatibility.json と対応機種ページを生成 → GitHub Pages に公開
   │  集計した issue にお礼のコメントを付けて閉じる
   ▼
ヘルプサイト「対応機種」ページ ＋ アプリ（JSON を読み、未確認の機種なら報告をお願いする）
```

---

## 3. アプリ

### 3.1 入口

| 入口 | 内容 |
|---|---|
| 設定 > ヘルプとフィードバック > **「この機種での動作を報告する」** | いつでも開ける。接続中のときだけ有効（機種名が必要なため） |
| ダッシュボードの一度だけの案内 | 次の条件がすべてそろったとき、画面下に小さな案内（アラートではない）を 1 回だけ出す。「この機種はまだ動作確認されていません。動いたかどうか教えてください」 |
| 報告の後 | お礼の画面に「対応機種の一覧」へのリンクを出す |

一度だけの案内を出す条件と、評価・応援のお願いとの順番・間隔は
[アプリ内のお願いの出し方](in-app-prompts-design.md) に従う（動作報告 → 評価 → 応援の順、何かを出したら 7 日空ける）。
動作報告に固有の条件は次のとおり。
- 接続中の機種が、対応機種の一覧（4.4 の JSON）で開発者確認済みでも報告済み（「問題なく使える」が 3 件以上）でもない
- その機種での利用が 3 日以上
- この端末からその機種の動作報告をまだ送っていない
- 案内は機種ごとに最大 2 回。閉じたら同じ機種には 30 日空ける

### 3.2 報告の画面（`CompatibilityReportView`）

「ご意見・ご要望」の画面とは分ける（自由記述ではなく、決まった形で答えてもらうため）。

```
┌ この機種での動作を報告 ────────────────┐
│ ⚠ この内容は GitHub 上で公開されます          │
│                                            │
│ 機種      Yamaha RX-V581（自動）             │
│ アプリ    1.2.0 (190) / iOS 26.0 / iPhone    │
│                                            │
│ 全体として   ● 問題なく使える ○ 一部使えない ○ 使えない │
│                                            │
│ 機能ごと（使った機能だけで大丈夫です）            │
│ 自動検出        [動いた|動かない|使っていない]    │
│ 電源            [ …… ]                      │
│ 音量            [ …… ]                      │
│ ミュート        [ …… ]                      │
│ 入力切替        [ …… ]                      │
│ サウンドモード   [ …… ]                      │
│ ゾーン 2 / 3    [ …… ]   ← 機種にある場合だけ   │
│ チューナー      [ …… ]   ← 機種にある場合だけ   │
│ リモコン画面     [ …… ]   ← 機種にある場合だけ   │
│ IP が変わった後の再接続 [ …… ]                 │
│                                            │
│ コメント（任意）                               │
│ [                                  ]       │
│                                            │
│        [ 送信 ]                             │
└────────────────────────────────────────────┘
```

- 機種名は **編集できない**（集計の表記ゆれを防ぐ）。機器から取れない場合は報告できない。
- 各機能の初期値は「使っていない」。ただし、このセッションでアプリが実際に成功を確認した操作は、「動いた」を初期値にしてもよい。
  - 例: 電源の切り替え後に状態が変わった、音量を変えた後にポーリングで値が返った。
  - アプリは操作の成否を記録しているので、ユーザーが一つずつ思い出さなくて済む。
- 「一部使えない」「使えない」を選んだら、コメント欄の下に「詳しい様子を『ご意見・ご要望』からバグとして送ることもできます」と添える。
- 応援してくれた人の `supporter` ラベルは付けない（動作報告は優先度の話ではないため）。

### 3.3 送るデータ

```swift
struct CompatibilityReport: Codable {
    var schema = 1
    var brand: String         // "denon" / "marantz" / "yamaha"
    var model: String         // 機器が返した機種名（例: "AVR-X3800H"、"RX-V581"）
    var region: String?       // Yamaha の destination（"J" など）。仕向け地で機能が違うことがあるため
    var firmware: String?     // 取れれば。Yamaha は system_version、Denon は取れる範囲で
    var apiVersion: String?   // Yamaha の api_version
    var app: String           // "1.2.0 (190)"
    var platform: String      // "iOS 26.0 / iPhone"
    var overall: Result       // works / partial / fails
    var features: [String: FeatureResult]  // "power": .ok など。使っていない機能は入れない
    // コメントは compat に入れず、今の body フィールドで送る
}
enum Result: String, Codable { case works, partial, fails }
enum FeatureResult: String, Codable { case ok, ng }
```

機能のキーは固定の一覧にする:
`discovery`, `power`, `volume`, `mute`, `input`, `sound_mode`, `zone2`, `zone3`, `tuner`, `remote`, `reconnect`

`ProblemReporter` に `.compatibility` の送信を足し、既存の `submit` と同じ手順で POST する。
Worker に届かないときは、今と同じくブラウザで GitHub の「issue を作成」画面を開く。
そのときも本文の末尾に 4.2 の機械用データを入れておき、集計側で拾えるようにする。

### 3.4 機種名とメーカーの取り方

| | 機種名 | メーカー |
|---|---|---|
| Denon / Marantz | `Deviceinfo.xml` の `ModelName`（なければ `ManualModelName`） | `BrandCode`（今の `DeviceInfo.brandName`） |
| Yamaha | `getDeviceInfo` の `model_name` | ドライバーが Yamaha なら yamaha |

機器に付けた名前（`FriendlyName` など）は、個人名が入ることがあるので送らない。

---

## 4. サーバーと集計

### 4.1 Worker の変更（`server/worker.js`）

- `CATEGORY_LABELS` に `compatibility: "compatibility"` を足す。
- `category === "compatibility"` のときは `compat` を必須にし、次のように検証する（受け取った値をそのまま信用しない）。
  - `brand` は `denon` / `marantz` / `yamaha` のどれか
  - `model` は英数字・ハイフン・スペース・ピリオドのみ、40 文字まで
  - `overall` と各機能の値は決まった値のどれか。機能のキーは決まった一覧にあるものだけ
  - ほかの文字列項目も長さと使える文字を制限する
- **タイトルと本文は Worker が作る**（アプリから来たタイトルは使わない）。
  - タイトル: `[動作報告] Yamaha RX-V581 — 問題なく使える`
  - 本文: 人が読む表 ＋ ユーザーのコメント ＋ 機械が読むデータ（4.2）
- ラベル: `compatibility` と `brand:yamaha` など。GitHub でこれらのラベルを事前に 1 回作っておく。
- レート制限は今の報告と共通（1 時間に IP ごと 5 件、全体で 30 件）。

### 4.2 issue の本文に埋める機械用データ

人が読む部分の後ろに、HTML コメントで JSON を入れる。GitHub の画面には表示されない。

```
<!-- avr-compat
{"schema":1,"brand":"yamaha","model":"RX-V581","region":"J","apiVersion":"1.19",
 "app":"1.2.0 (190)","platform":"iOS 26.0 / iPhone","overall":"works",
 "features":{"power":"ok","volume":"ok","input":"ok","tuner":"ok","remote":"ng"}}
-->
```

集計はこのブロックだけを読む。ユーザーがブラウザ経由で送った場合（ラベルが付かない）も、このブロックがあれば拾う。

### 4.3 集計（GitHub Actions）

`pages.yml` を拡張する。

- **動くきっかけ**: 今の `help/**` の push に加えて、次の 3 つ。
  - `issues`（opened / edited / labeled / closed）
  - `schedule`（毎日 1 回）
  - `workflow_dispatch`
- **集計のスクリプト**: `scripts/aggregate-compat.mjs`（Node の標準機能だけで書く）
  1. `compatibility` ラベルの issue と、本文に `avr-compat` を含む issue を、開いているもの・閉じたものすべて読む。
  2. `invalid` ラベルの issue は除外する（いたずらや誤報告は、このラベルを付けるだけで外せる）。
  3. 機種ごと（brand ＋ model）に、報告数、全体の結果の内訳、機能ごとの ok / ng の数、最新の報告日とアプリのバージョンを出す。
  4. 開発者が実機で確かめた機種は、リポジトリの `help/data/verified.json` に手で書いておき、集計結果と合わせる（`AVR-X3800H`、`RX-V581`）。
  5. `help/compatibility.json`、日本語と英語の対応機種ページ（`help/compatibility.html`、`help/en/compatibility.html`）を生成する。
- **公開**: 生成したものは、デプロイ用の成果物に入れて Pages に公開する。**リポジトリにはコミットしない。**
  - 理由: Actions の標準トークンで push しても、別のワークフロー（Pages のデプロイ）は起動しないため。
- **issue の後片付け**: 集計に使った `compatibility` の issue は、「集計に反映しました。ありがとうございます」とコメントして閉じる。issue の一覧が報告で埋まらないようにするため。閉じても集計には使い続ける。
- 権限: `issues: write`（コメントと閉じる操作）、`contents: read`、`pages: write`。

### 4.4 公開する JSON（アプリも読む）

```json
{
  "generatedAt": "2026-10-01T00:00:00Z",
  "models": [
    {
      "brand": "yamaha", "model": "RX-V581",
      "status": "verified",
      "reports": 4,
      "overall": {"works": 3, "partial": 1, "fails": 0},
      "features": {"power": {"ok": 4, "ng": 0}, "remote": {"ok": 1, "ng": 2}},
      "lastReport": "2026-09-30", "lastApp": "1.2.0"
    }
  ]
}
```

`status` の決め方:

| status | 条件 | ページでの表示 |
|---|---|---|
| `verified` | 開発者が実機で確認した | 開発者確認済み |
| `reported` | 「問題なく使える」の報告が 1 件以上あり、「使えない」より多い | ユーザー報告で動作確認済み（n 件） |
| `partial` | 報告はあるが、一部の機能で動かないという報告が多い | 一部の機能が動かない報告あり（機能名を表示） |
| `failing` | 「使えない」の報告のほうが多い | 動かないという報告あり |

---

## 5. 表示

### 5.1 ヘルプサイトの「対応機種」ページ

- メーカーごとの表で、機種名、状態、報告数、動かない報告がある機能、最新の報告日を出す。
- 詳細ガイド（`details.html`）の「対応機種」から、このページにリンクする。
- ページの先頭に次の 2 点を書く。
  - 非提携の注記
  - 「ユーザーからの報告をもとに自動で作っています。動作を保証するものではありません」

### 5.2 アプリ

- 起動時か接続時に `compatibility.json` を取得して、キャッシュする。取れなくても何も困らないようにする。
- 使い道は 3.1 の「一度だけの案内」を出すかどうかの判断だけ。
- 接続画面に「この機種は動作確認済み」などの表示を出すかどうかは、後で決める。
  - 出せば安心材料になる。
  - 一方で、「確認済みでない」という表示は不安をあおるおそれがある。

---

## 6. プライバシーと審査

- **送る内容は今の「ご意見・ご要望」と同じ範囲**（機種名、アプリと OS のバージョン、任意のコメント）。
  App Privacy の申告（Customer Support、Other Diagnostic Data。どちらも個人と結び付けず、トラッキングもしない）は変えずに済む見込み。
- プライバシーポリシー（`privacy.md`、`help/privacy.html`、`help/en/privacy.html`）に「動作報告」も同じ扱いで送ることを書き足す。
- 報告の画面、ヘルプサイトの対応機種ページ、審査メモのどれにも、メーカー名を App Store のメタデータとして出さない。
  アプリ内に表示される機種名は、機器から返ってきたデータ（接続先の表示と同じ）。

---

## 7. 進め方

| 段階 | 内容 | 出す時期 |
|---|---|---|
| 1 | Worker に `compatibility` を追加し、ラベルを作る（古いアプリには影響なし） | いつでも（アプリの提出と関係なくデプロイできる） |
| 2 | 集計スクリプトと Pages の拡張、`verified.json`、対応機種ページ | 段階 1 の後。テスト用の issue で確かめる |
| 3 | アプリの報告画面と設定の入口 | Denon だけで先に出せる（1.1.x でも可） |
| 4 | 一度だけの案内と `compatibility.json` の取得 | 3 と同時か、その次 |
| 5 | Yamaha 対応（1.2.0）と、TestFlight で Yamaha の持ち主に試してもらう呼びかけ | Yamaha 対応の段階 2 以降 |

Yamaha 対応を待たずに、段階 1〜3 を先に出すのがよい。
今の Denon / Marantz のユーザー（約 1,200 ダウンロード）から X3800H 以外の機種の報告が集まり、
仕組みの動作確認にもなる。

---

## 8. 決めておくこと

- 「一部使えない」の報告を受けたとき、開発者が詳細を聞く方法（issue へのコメントは届くが、報告者が GitHub を見ているとは限らない）
- 接続画面に動作確認の状態を出すか（5.2）
