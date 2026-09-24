# Yamaha AV レシーバー対応 — 方針と設計

作成: 2026-09-23 / 対象: 次のバージョン（1.2.0 想定）/ iOS・iPadOS のみ（macOS は凍結中）

1.1.0 でストア上の名前からメーカー名を外したのを機に、Denon / Marantz 専用だったアプリを
Yamaha の AV レシーバーでも使えるようにする。この文書は、調査結果・方針・設計・進め方をまとめたもの。

各項目の確度を次の記号で示す。

- **[仕様]** Yamaha の公開仕様書で確認した
- **[実装]** オープンソースの Yamaha 制御ライブラリの実装から読み取った（公式仕様には載っていない）
- **[要実機]** 手元のテスト機で確かめるまで分からない

---

## 0. テスト機

**RX-V581**（2016 年発売、MusicCast 対応）。型番は本体で確認済み（2026-09-23）。
YXC と、旧 XML API（YNC）の両方が使える世代にあたる。

2016 年の機種なので、実機の API バージョンが 1.17 より古い可能性がある。その場合、次の操作が使えない。
何が使えるかは、段階 0 で `getDeviceInfo` の `api_version` を見て確かめる。
- 音量の up/down 指定（`setVolume?volume=up`）
- プリセットの前後送り（`switchPreset`）
- `device_id`

Zone 2（Zone B）があるかどうかも、`getFeatures` の `zone_num` で確かめる。

---

## 1. 調査結果

### 1.1 Yamaha のネットワーク制御は 2 系統ある

| | YXC（Yamaha Extended Control） | YNC（YamahaRemoteControl、旧 XML API） |
|---|---|---|
| 対象 | MusicCast 対応機（2016 年以降） | 2010 年ごろ〜の LAN 対応機。MusicCast 機にも残っている **[仕様]** |
| 形式 | `GET http://{ip}/YamahaExtendedControl/v1/...`、応答は JSON | `POST http://{ip}/YamahaRemoteControl/ctrl`、XML を送って XML で返る |
| ポート | 80 | 80 |
| 公開仕様 | あり（Basic / Advanced、2016） | 公式の公開仕様はない。ライブラリ（rxv など）で広く使われている |
| 状態変化の通知 | UDP で届く（10 章 Events） **[仕様]** | なし（ポーリングのみ） |
| リモコン画面（OSD）のカーソル操作 | **公開仕様にない** | `Cursor_Control`（Up/Down/Left/Right/Sel/Return）、`Menu_Control`（On Screen/Option など） **[実装]** |
| 音量 | 整数の段階値（範囲は機器が返す） **[仕様]** | dB で取得・設定できる（`Val` / `Exp` / `Unit`） **[実装]** |

MusicCast 機の機器記述（device description）には、YXC の URL と YNC の説明ファイル
（`/YamahaRemoteControl/desc.xml`）の両方が載っている **[仕様]**。
つまり RX-V581 なら、両方の API を使える見込みが高い **[要実機]**。

### 1.2 YXC で使う API（すべて GET）[仕様]

| 目的 | API |
|---|---|
| 機種名・API バージョン | `/v1/system/getDeviceInfo`（`model_name`、`api_version`、`device_id`※1.17 以降） |
| 機能一覧 | `/v1/system/getFeatures`（ゾーン数、入力一覧、サウンドプログラム一覧、音量の範囲、チューナーのプリセット数など） |
| MAC アドレス・機器名 | `/v1/system/getNetworkStatus`（`mac_address.wired_lan` / `wireless_lan`、`network_name`） |
| 入力の表示名 | `/v1/system/getNameText` **[実装]** |
| ゾーンの状態 | `/v1/{main\|zone2}/getStatus`（power、volume、mute、input、sound_program、pure_direct など） |
| 電源 | `/v1/{zone}/setPower?power=on\|standby\|toggle` |
| 音量 | `/v1/{zone}/setVolume?volume=N`、`volume=up\|down&step=N`（up/down は API 1.17 以降） |
| ミュート | `/v1/{zone}/setMute?enable=true\|false` |
| 入力切替 | `/v1/{zone}/setInput?input=hdmi1` |
| サウンドプログラム | `/v1/{zone}/setSoundProgram?program=straight` |
| ピュアダイレクト | `/v1/{zone}/setPureDirect?enable=true` **[実装]** |
| チューナーの状態 | `/v1/tuner/getPlayInfo`（band、周波数は kHz、preset 番号） |
| プリセット一覧 | `/v1/tuner/getPresetInfo?band=common`（全件が一度に返る。Denon のような 1 件ずつの取得は不要） |
| プリセット呼び出し | `/v1/tuner/recallPreset?zone=main&band=common&num=N`、`/v1/tuner/switchPreset?dir=next\|previous`（1.17 以降） |
| 選局 | `/v1/tuner/setFreq?band=fm&tuning=up\|down\|direct&num=kHz` |

- 応答には必ず `response_code` が入る。0 が成功。3 は存在しない API、4 はパラメータ誤り、5 は今の状態では操作できない **[仕様]**。
- どのリクエストにも `X-AppName: MusicCast/…` と `X-AppPort: <UDP ポート>` のヘッダーを付けると、その後 10 分間、状態変化が UDP で届く。10 分以内に次のリクエストを送れば延長される **[仕様]**。

### 1.3 機器の見つけ方

- Yamaha 公式の手順は **SSDP**（UPnP の M-SEARCH をマルチキャストで送る）。
  見つかった機器の記述に `Yamaha Corporation` と `yamaha:X_yxcControlURL` が含まれていれば対象 **[仕様]**。
- **iOS でマルチキャストを送るには、Apple に申請して `com.apple.developer.networking.multicast` 権限をもらう必要がある。**
  今のアプリにはこの権限がない（entitlements は空）。申請には審査期間がかかり、通るとは限らない。
- 今のアプリは Bonjour（`_denon-heos._tcp`、`_heos-audio._tcp`、`_http._tcp`）で見つけて、
  見つかった IP に `/goform/Deviceinfo.xml` を問い合わせて確かめている。Bonjour には特別な権限が要らない。
- RX-V581 は AirPlay に対応しているので、`_airplay._tcp` や `_raop._tcp` で見つかる可能性が高い **[要実機]**。

### 1.4 最新の機種との違い

| | RX-V581（2016） | 2020 年以降（RX-V6A、RX-A2A〜A8A） |
|---|---|---|
| YNC（旧 XML API） | 使える見込み | **使えない**（Home Assistant の旧 Yamaha 連携が動かなくなったという報告あり） |
| YXC | 初期の版 | 新しい版（非公式にまとめられた仕様 Rev 2.00） |
| リモコン画面の操作 | YXC にない。YNC で行う | YXC の `controlCursor` / `controlMenu` **[実装]** |
| 音量の dB 指定 | できない。段階値から換算する | YXC の `setActualVolume` **[実装]** |
| シーンの呼び出し | なし | `recallScene` **[実装]** |

- 新しい API は、`getFeatures` の `func_list` に `cursor`、`actual_volume` などがあるときだけ使える。
- 2026 年 5 月に発表された RX300A は Bluetooth だけで、ネットワーク制御ができない（対応外）。
- RX500A はネットワーク対応だが、MusicCast（YXC）で操作できるかは発表資料からは分からない。

**設計への影響**: 機能ごとに、次の順で使う方法を選ぶ。

1. YXC の新しい API（`func_list` にあれば）
2. YNC（`desc.xml` があれば）
3. どちらもなければ、その機能を隠す

RX-V581 は回り道が必要な側の機種になる。新しい機種向けの処理は実機で確かめられないため、
[動作報告の仕組み](compatibility-reports-design.md)で持ち主に報告してもらって確かめる。

### 1.5 今のコードで Denon に依存しているところ

抽象化の層は **ない**。`MainViewModel` が `AVRHTTPClient`（HTTP）と `TelnetClient` を直接持っていて、
Denon のコマンド文字列（`PWON`、`MV50`、`SIHDMI1`、`MSMOVIE`、`MNCUP` など）を ViewModel の中で組み立てている。

| 場所 | Denon 依存の中身 |
|---|---|
| `Core/Network/AVRHTTPClient.swift`（732 行） | `/goform/...` の URL、XML の解析、ポーリング（1.5 秒〜最大 600 秒の可変間隔、3 回連続失敗でストリーム終了） |
| `Core/Network/TelnetClient.swift`（195 行） | ポート 23。サラウンドモードとチューナーの状態だけ Telnet の応答から読む |
| `ViewModels/MainViewModel.swift`（886 行） | 全コマンドの組み立て、56 件のプリセットを 1 件ずつ取得する処理、Telnet 応答の解析、接続・自動再接続 |
| `Core/Models/InputSource.swift` | enum の `rawValue` が Denon の入力コード（`BD`、`SAT/CBL`、`HDMI1`…） |
| `Core/Models/SurroundMode.swift` | enum の `rawValue` が Denon のモード名 |
| `Core/Models/AVRState.swift` | 音量は dB で保持。表示用に「Denon 単位 ＝ dB ＋ 80」、コマンド用に 0〜98 の変換 |
| `Core/Network/MDNSDiscovery.swift` | Bonjour の種類、`/goform/Deviceinfo.xml` に 200 が返れば Denon とみなす |
| 画面 | 音量 −80〜+18 dB、「Vol 47.5」の副表示、入力・サラウンドは固定の一覧、チューナーのスロット 56 と「スキップ周波数 90.0」、リモコン画面は `MN*` 前提 |
| 保存データ | 入力の名前変更・非表示（`InputSource.rawValue` がキー）、プリセット（`Preset` が `InputSource` と `SurroundMode` の rawValue を Codable で保存） |

---

## 2. 方針

1. **YXC を主に使い、YNC は YXC にない機能（リモコン画面の操作）だけに使う。**
   YXC は公式仕様があり、今後の機種でも使える。YNC だけで作ると、YXC しかない新しい機種で使えなくなる。
2. **まずメーカーごとの違いを「ドライバー」に閉じ込める作り直しを、Denon だけで行う。** その後に Yamaha を足す。
   作り直しの段階では動作を変えず、X3800H で今と同じに動くことを確かめてから次へ進む。
3. **機能の有無は機器に聞いて決める。**
   ゾーン数・入力一覧・サウンドプログラム・音量の範囲・プリセット数は Yamaha なら `getFeatures` で分かる。
   画面は「この機器に何ができるか（capabilities）」を見て、ボタンの出し分けをする。
4. **見つけ方はまず Bonjour と手入力で対応し、SSDP は後回しにする。**
   マルチキャスト権限の申請は、Bonjour で見つからない機種が実際に出てから考える。
5. **ストアとヘルプの書き方は 1.1.0 と同じ方針にする。**
   名前・サブタイトル・キーワード・スクリーンショットに Yamaha / MusicCast を入れない。
   説明文の【対応機種】に動作確認済みの機種を足すかどうかは、1.1.0 の審査結果を見て決める
   （説明文の機種名も指摘された場合は、ヘルプサイトにだけ書く）。
6. **Yamaha で使えない機能は隠す。** 灰色で押せないボタンは出さない。

---

## 3. 設計

### 3.1 全体の構成

```
Views ──► MainViewModel（メーカーを意識しない）
             │  状態: AVRState（dB、入力 ID、サウンドモード ID …）
             │  操作: ReceiverCommand（電源、音量、入力 …）
             ▼
        ReceiverDriver（protocol）
          ├─ DenonDriver ── AVRHTTPClient（/goform）＋ TelnetClient（ポート 23）
          └─ YamahaDriver ─ YXCClient（JSON）＋ YNCClient（XML、リモコン画面用）＋ YXCEventListener（UDP、後の段階）
             ▲
        ReceiverProbe（IP を受け取り、Denon か Yamaha かを判定して Driver を作る）
```

HTTP の送受信は、今の `AVRHTTPClient` にある BSD ソケットの GET / POST をそのまま切り出して共通化する
（`LocalHTTP`）。ローカル専用の Wi-Fi で URLSession が失敗する問題を避けるため、という理由は Yamaha でも変わらない。

### 3.2 ドライバーの約束事

```swift
protocol ReceiverDriver: Actor {
    /// 接続して機器情報と機能一覧を返し、状態の更新を流し始める
    func connect(host: String, port: Int?) async throws
        -> (DeviceInfo, ReceiverCapabilities, AsyncStream<ReceiverSnapshot>)
    func disconnect() async
    func pollNow() async
    func isReachable(host: String) async -> Bool
    func perform(_ command: ReceiverCommand) async throws
    func fetchTunerPresets() async -> [TunerPreset]?
}

enum ReceiverCommand {
    case power(Zone, on: Bool)
    case volumeStep(Zone, up: Bool)
    case volumeDB(Zone, Double)
    case mute(Zone, Bool)
    case input(Zone, InputID)
    case soundMode(SoundModeID)
    case pureDirect(Bool)
    case cursor(RemoteKey)          // up/down/left/right/enter/back
    case menu(RemoteMenu)           // setup/option/info
    case tunerBand(TunerBand)
    case tunerFrequencyStep(up: Bool)
    case tunerPreset(Int)
    case tunerPresetStep(next: Bool)
}

enum Zone { case main, zone2, zone3 }
```

- `ReceiverSnapshot` は今の `AVRStatusSnapshot` を広げたもの。入力はメーカー固有の ID 文字列で持ち、
  サウンドモード・Zone 3 の状態も入れられるようにする（Denon でも今は取れていない項目がある）。
- 今 `MainViewModel` にある Denon のコマンド組み立て、Telnet 応答の解析、56 件のプリセットの 1 件ずつの取得は、
  すべて `DenonDriver` に移す。ViewModel に残すのは「操作 → `perform`」と、今ある操作直後 3 秒の同期抑止、
  それに接続と自動再接続の流れだけ。

### 3.3 機能一覧（capabilities）

```swift
struct ReceiverCapabilities {
    var brand: ReceiverBrand                 // .denon / .marantz / .yamaha
    var zones: [Zone]                        // Yamaha は getFeatures の zone_num
    var inputs: [ReceiverInput]              // id・表示名・アイコン
    var soundModes: [SoundMode]              // id・表示名
    var supportsPureDirect: Bool
    var volumeRangeDB: ClosedRange<Double>   // Denon −80…+18、Yamaha は機器の値から計算
    var volumeStepDB: Double                 // どちらも 0.5 の見込み
    var nativeVolumeLabel: ((Double) -> String)?  // Denon の「Vol 47.5」。Yamaha は nil（表示しない）
    var tuner: TunerCapabilities?            // バンド、プリセット数、一括取得できるか
    var remote: Set<RemoteKey>               // リモコン画面のボタン。空ならリモコンのタブを隠す
}
```

| 画面 | 変えること |
|---|---|
| ダッシュボード | 音量スライダーの範囲を `volumeRangeDB` にする。「Vol 47.5」は `nativeVolumeLabel` が nil なら出さない。入力・サラウンドのボタンを capabilities の一覧から作る |
| 入力 | 同上。Yamaha は `getNameText` の名前をそのまま出す（本体で付けた名前が見える） |
| チューナー | 一括取得できる機器（Yamaha）では「スキャン」「スキップ周波数」「スロット n / 56」を出さない。プリセット数は機器の値 |
| ゾーン | `zones` にあるゾーンだけ出す |
| リモコン | `remote` が空ならタブごと隠す。Yamaha で YNC が使えればカーソルと Enter / Back / Option / 画面表示を出す |
| 設定 | 入力の名前変更・非表示の一覧を capabilities の入力から作る |

### 3.4 入力とサウンドモードを「ID 文字列」にする（保存データの移行）

- `InputSource` enum は、Denon の入力 ID と表示名・アイコンの対応表として残す。
  状態と保存には `InputID`（`String`）を使い、Yamaha は `hdmi1`、`av1`、`tuner`、`net_radio`、`bluetooth` などの
  YXC の ID をそのまま使う。Yamaha の ID → アイコンの対応表を新しく作る。
- サウンドモードも同様。Yamaha は `getFeatures` の `sound_program_list`（`straight`、`surr_decoder`、`2ch_stereo`、
  `7ch_stereo`、`standard`、`sci-fi`、`drama`、`music_video` など）を並べ、よく使うものには日英の表示名を付ける。
  名前を付けていない ID は、そのまま読みやすく整形して出す。
- **保存データ**:
  - 入力の名前変更と非表示（`customInputNames` / `hiddenInputSources`）は、キーを「機器ごと」にする
    （例: MAC アドレスを先頭に付ける）。既存のデータは、最初に Denon の機器へ接続したときにその機器のキーへ移す。
  - `Preset` は `InputSource` / `SurroundMode` の代わりに ID 文字列とメーカーを保存する。
    古い形式のデータは Denon のものとして読み込めるよう、デコードで両方に対応する。
    ほかのメーカーの機器に接続しているときは、そのメーカーのプリセットだけを出す。
  - `defaultHost` などに加えて、`defaultBrand` を保存する。

### 3.5 Yamaha ドライバーの中身

**接続**
1. `getDeviceInfo`: `response_code == 0` を確かめ、機種名と `api_version` を得る。
2. `getFeatures`、`getNetworkStatus`（MAC）、`getNameText` を読み、`ReceiverCapabilities` を作る。
3. YNC が使えるかを `GET /YamahaRemoteControl/desc.xml` で確かめる。使えればリモコン画面のボタンを capabilities に入れる。

**状態の取得**
- 第 1 段階は、Denon と同じ可変間隔のポーリングで作る（`main/getStatus`、Zone 2 があれば `zone2/getStatus`、
  入力がチューナーのときだけ `tuner/getPlayInfo`）。3 回連続で失敗したらストリームを終え、今ある自動再接続に任せる。
- 第 2 段階で UDP のイベント受信（`YXCEventListener`）を足す。
  - 受信用の UDP ソケットを開き、そのポートを `X-AppPort` で知らせる。
  - 10 分で切れるので、ポーリングか操作のたびにヘッダーを付けて延長する。
  - イベントが来たらすぐ画面に反映し、ポーリング間隔を長めにできる。
  - UDP を受けるだけならマルチキャスト権限は不要（ローカルネットワークの許可だけでよい）。

**音量（dB への換算）**
- `func_list` に `actual_volume` がある機種は、dB で直接やり取りする（換算は不要）。以下はそれがない機種の場合。
- YXC の音量は整数の段階値で、範囲は `getFeatures` の `range_step`（id が `volume`）で分かる **[仕様]**。
- RX-V 系では「0〜161 の段階値、1 段階が 0.5 dB、0 が −80.5 dB」と考えられる。
  ただし公式仕様に dB との対応は書かれていない **[要実機]**。
- 実機で YNC の dB 値（`Val`/`Exp`）と YXC の段階値を並べて読み、対応を確かめてから換算式を決める。
  合わなければ、音量だけ YNC で dB を直接やり取りする。
- アプリ内の状態は今と同じ dB のまま。ドライバーの出入り口で換算する。

**リモコン画面**
- `func_list` に `cursor` がある機種（2020 年以降）は、YXC の `controlCursor` / `controlMenu` を使う。以下はそれがない機種（RX-V581 など）で YNC を使う場合。
- 送るのは `<YAMAHA_AV cmd="PUT"><Main_Zone><Cursor_Control><Cursor>Up</Cursor></Cursor_Control></Main_Zone></YAMAHA_AV>` のような XML **[実装]**。
- 使えるボタンの種類は `desc.xml` に書かれているので、そこから `remote` を作る **[実装]**。
- RX-V581 が本体のメニュー（セットアップ）操作まで受け付けるかは **[要実機]**。
  受け付けなければ、リモコンのタブは Yamaha では出さない。

**チューナー**
- `getPresetInfo?band=common` で全プリセットを一度に取得する。周波数は kHz なので、FM は MHz に直して表示する。
- 選局は `setFreq`、プリセットの前後は `switchPreset`。API 1.17 より古い機器なら、番号を計算して `recallPreset` を送る。

**電源オン**
- スタンバイ中にネットワークから電源を入れるには、本体側で「ネットワークスタンバイ」を有効にする必要がある。
- 無効のまま電源を切ると、アプリから電源を入れられない。
- この場合の案内を接続画面とヘルプに書く。

### 3.6 機器の判定と検出

- `ReceiverProbe.identify(ip:)` で、次の 2 つを **並行して** 問い合わせる。
  - Denon: `/goform/Deviceinfo.xml`（8080 → 80）。応答の中身（`ModelName` など）まで確かめる。今は「200 が返れば Denon」なので、ほかの機器を誤判定しうる。
  - Yamaha: `/YamahaExtendedControl/v1/system/getDeviceInfo`（80）で、`response_code == 0` を確かめる。
- Bonjour で探す種類に `_airplay._tcp` と `_raop._tcp` を足す（`Info.plist` の `NSBonjourServices` にも足す）。
  見つかった IP はすべて `identify` にかけ、Apple TV などのほかの機器を除外する。
- IP アドレスを手入力した場合も `identify` でメーカーを判定する（ユーザーにメーカーを選ばせない）。
- 自動再接続（IP が変わったとき）は、今と同じく MAC アドレスで照合する。Yamaha の MAC は `getNetworkStatus` で取る。
- SSDP（マルチキャスト）は、Bonjour で見つからない機種があると分かった段階で、権限の申請を含めて検討する。

---

## 4. 進め方

| 段階 | 内容 | 確認方法 |
|---|---|---|
| 0. 実機調査 | RX-V581 で、下の「実機で読むもの」の応答を保存する | 応答ファイル一式 |
| 1. 作り直し（Denon のみ） | `LocalHTTP` の切り出し、`ReceiverDriver` と `DenonDriver`、入力とサウンドモードの ID 化、保存データの移行 | X3800H で全機能が今と同じに動く。1.1.0 の保存データ（プリセット、入力名、チューナー）が引き継がれる |
| 2. Yamaha の基本操作 | 接続（手入力）、電源、音量、ミュート、入力、サウンドプログラム、ピュアダイレクト、Zone 2、チューナー | 実機で各操作と、本体を直接操作したときの画面への反映 |
| 3. 検出と自動再接続 | Bonjour の種類を追加、`identify`、MAC による再接続 | 自動検出で見つかる。ルーターで IP を変えても再接続する |
| 4. リモコン画面とイベント | YNC のカーソル操作、UDP イベント | 実機でメニュー操作ができる。本体での操作が 1 秒以内に反映される |
| 5. 公開準備 | ヘルプ（対応機種と「ネットワークスタンバイ」の案内）、説明文、スクリーンショット、審査メモ、What's New | 1.1.0 と同じチェックリスト |

段階 1 だけでも独立して出せる（動作は変わらない）。段階 2〜3 で 1.2.0 として出し、4 は 1.2.x で足してもよい。

### 実機で読むもの（段階 0）

テスト機の IP を `IP` に入れて、Mac のターミナルで実行する。読み取りだけで、機器の設定は変わらない。

```bash
IP=192.168.x.x
B="http://$IP/YamahaExtendedControl/v1"
for p in system/getDeviceInfo system/getFeatures system/getNetworkStatus \
         "system/getNameText" main/getStatus zone2/getStatus \
         tuner/getPlayInfo "tuner/getPresetInfo?band=common"; do
  echo "== $p"; curl -s -m 5 "$B/$p"; echo
done
curl -s -m 5 "http://$IP/YamahaRemoteControl/desc.xml" | head -c 2000; echo
curl -s -m 5 -X POST -H 'Content-Type: text/xml' \
  -d '<YAMAHA_AV cmd="GET"><Main_Zone><Basic_Status>GetParam</Basic_Status></Main_Zone></YAMAHA_AV>' \
  "http://$IP/YamahaRemoteControl/ctrl"; echo
dns-sd -B _airplay._tcp local. & sleep 5; kill $!
```

- 応答には MAC アドレスや機器 ID が含まれる。リポジトリ（公開）に置くときは、これらを伏せる。
- 最後の `dns-sd` で、テスト機が Bonjour（AirPlay）で見つかるかが分かる。

---

## 5. リスクと未確定事項

| 項目 | 影響 | 対応 |
|---|---|---|
| テスト機の API バージョン | 1.17 より古いと、音量の up/down とプリセット送りを自前で計算する必要がある | 段階 0 で `api_version` を確認 |
| 音量の dB 換算 | 表示と操作の値がずれる | 段階 0 で YNC の dB と突き合わせる |
| Bonjour で見つからない | 自動検出と、IP が変わったときの再接続が効かない | 手入力で使える状態を先に作る。必要ならマルチキャスト権限を申請して SSDP |
| YNC がない、または OSD を受け付けない | リモコン画面が使えない | Yamaha ではタブを隠す |
| 新しい機種で試せない | 新しい API（`controlCursor` など）の処理が未確認のまま出る | TestFlight と[動作報告](compatibility-reports-design.md)で持ち主に確かめてもらう |
| 機種やファームウェアによる API の差（1.17 以前など） | 一部の操作が失敗する | `api_version` と `func_list` を見て分岐する。失敗は `response_code` で判別する |
| 作り直しによる Denon 側の退行 | 既存ユーザーへの影響 | 段階 1 を単独で実機確認してから進める。自動テストがないので、確認項目の一覧を作る |
| ストア審査（商標） | 1.1.0 と同じ理由で却下 | メタデータにメーカー名を入れない。審査メモには事実を正直に書く |
| Yamaha 公式アプリとの同時利用 | UDP イベントの受信先が上書きされることがある | イベントを当てにしすぎず、ポーリングを残す |

---

## 6. 参考資料

- Yamaha Extended Control API Specification (Basic), (Advanced) — Yamaha, 2016
  （[pyamaha リポジトリ内の PDF](https://github.com/rsc-dev/pyamaha/tree/master/doc)）
- [aiomusiccast](https://github.com/vigonotion/aiomusiccast) — Home Assistant の MusicCast 連携で使われている YXC のライブラリ
- [rxv](https://github.com/wuub/rxv) — YNC（YamahaRemoteControl）のライブラリ。カーソル操作と dB での音量の扱い
- [yamaha-extended-control-openapi](https://github.com/opctim/yamaha-extended-control-openapi) — 非公式の YXC 仕様（Rev 2.00 ベース）。`controlCursor`、`setActualVolume` など
- [Home Assistant Community: New range of Yamaha receivers working?](https://community.home-assistant.io/t/new-range-of-yamaha-receivers-working/293692) — 2020 年の世代で YNC が使えなくなった報告
- [Yamaha RX300A / RX500A の発表（2026-05）](https://www.prnewswire.com/news-releases/yamaha-debuts-rx300a-and-rx500a-home-theater-av-receivers-302768806.html)
- [Yamaha RX-V581 製品ページ](https://jp.yamaha.com/products/audio_visual/av_receivers_amps/rx-v581_black__j/index.html)
