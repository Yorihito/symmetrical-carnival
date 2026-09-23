# App Store Metadata (iOS / iPadOS)

App Store Connect に入力する iOS アプリのメタデータです。1.1.0 以降はこの内容をそのまま使います。

## 商標の方針（2026-09-23 決定）

1.1.0 の初回審査で Guideline 5.2.1（知的財産）と 4.1(a)（コピーキャット）により却下された。
指摘は「メーカーの許可なく、そのメーカーのハードウェアを操作するアプリとして宣伝している」
「メタデータにメーカーを連想させる表記がある（旧名 *AVR Controller for D*）」の 2 点。
メーカーの許可を得るのは現実的でないため、次のようにする。

- **名前・サブタイトル・キーワード・プロモーション用テキスト・スクリーンショット・アプリ内の文言**に
  メーカー名・ブランド名・その略称（"for D" など）を入れない。
- **説明文**には、対応機種の確認のため「動作確認済み機種」を事実として 1 文だけ書き、非提携の注記を添える。
  再度却下された場合は、この 1 文も削除して再提出する（その場合の文面は下の「予備」を使う）。
- ヘルプサイト（サポート URL）も同じ方針。対応機種のページに動作確認済み機種と非提携の注記だけを書く。
- 審査メモ（`ReviewNotes.txt`）には、アプリが実際に何を操作するかを正直に書く（審査員にだけ見える）。
- ロゴ・製品写真などの第三者の素材は使わない。

---

## 日本語 (Japanese)

### 名前 (Name)
**制限: 30文字**
> AVR Controller – AVアンプ リモコン

### サブタイトル (Subtitle)
**制限: 30文字**
> AVレシーバーを音量ダイアルで快適操作

### プロモーション用テキスト (Promotional Text)
**制限: 170文字**
> リモコンを探す必要はもうありません。iPhone と iPad が、すばやく反応する AV レシーバーのコントローラーに。回して操作できる音量ダイアルを新たに搭載しました。

### 説明 (Description)
**制限: 4000文字**
> ネットワーク対応の AV レシーバー（AVR）を、iPhone と iPad から快適に操作できるコントローラーです。
>
> 暗い部屋で物理リモコンを探したり、重いアプリの起動を待ったりする必要はありません。電源・音量・入力の切り替えを、手元ですぐに操作できます。
>
> 【主な機能】
> ・音量ダイアル: つまみを回す感覚で音量を調整できます。スライダー表示にも切り替えられます。
> ・すばやい反応: 同じ Wi-Fi 上の AV レシーバーと直接通信するので、操作がすぐに反映されます。
> ・入力とサラウンドモード: よく使う入力やサラウンドモードをワンタップで切り替えられます。
> ・並べ替えられるホーム画面: 入力・サラウンド・音量などの並び順を、設定から好みに変えられます。
> ・マルチゾーン: 別の部屋（Zone 2 / Zone 3）の電源・音量・入力も操作できます。
> ・チューナー: FM/AM のプリセットをすぐに呼び出せます。
> ・リモコン画面: 画面表示（OSD）のメニュー操作ができます。
> ・自動で再接続: AV レシーバーの IP アドレスが変わっても、自動で見つけ直して接続します。
> ・iPad に最適化: サイドバーのある広いレイアウトで操作できます。
>
> すべての機能を無料で使えます。アプリを気に入っていただけたら、設定の「開発を応援する」から投げ銭で応援していただけるとうれしいです（機能は増えません）。
>
> 【対応機種】
> ネットワーク制御（HTTP / ポート 8080）に対応した AV レシーバーで使えます。動作確認済み機種は Denon AVR-X3800H です。お使いの AV レシーバーがネットワーク制御に対応しているかは、取扱説明書でご確認ください。
>
> ※ 本アプリは個人が開発した非公式アプリで、各メーカーとは提携していません。製品名は対応機種を示す目的でのみ記載しており、各社の商標は各社に帰属します。

### キーワード (Keywords)
**制限: 100文字**（名前・サブタイトルにある語は入れなくても検索対象になる）
> アンプ,レシーバー,ホームシアター,ボリューム,入力切替,サラウンド,チューナー,ラジオ,ゾーン,オーディオ,Hi-Fi,receiver,amp,remote,volume

---

## 英語 (English - U.S.)

### Name
**Limit: 30 chars**
> AVR Controller: Volume Dial

### Subtitle
**Limit: 30 chars**
> AV Receiver Remote Control

### Promotional Text
**Limit: 170 chars**
> Stop searching for the remote. Turn your iPhone and iPad into a fast, responsive controller for your AV receiver, now with a volume dial you can turn.

### Description
**Limit: 4000 chars**
> A fast, easy controller for your network-enabled AV receiver (AVR), on iPhone and iPad.
>
> No more hunting for the remote in a dark room or waiting for a slow app to load. Power, volume, and inputs are right at your fingertips.
>
> FEATURES
> • Volume dial: Turn a knob to set the volume, or switch to a slider if you prefer.
> • Instant response: The app talks directly to your receiver over your Wi-Fi, so changes happen right away.
> • Inputs and surround modes: Switch inputs and surround modes with a single tap.
> • Your layout: Reorder the home screen sections (inputs, surround, volume, and more) in Settings.
> • Multi-zone: Control power, volume, and inputs for other rooms (Zone 2 / Zone 3).
> • Tuner: Recall your FM/AM presets instantly.
> • Remote: Navigate the on-screen (OSD) menus.
> • Automatic reconnect: If your receiver's IP address changes, the app finds it again and reconnects.
> • Built for iPad: A roomy sidebar layout.
>
> Every feature is free. If you enjoy the app, you can leave a tip in Settings > Support Development (tips do not unlock features).
>
> COMPATIBILITY
> Works with AV receivers that support network control (HTTP on port 8080). Verified on the Denon AVR-X3800H. Check your receiver's manual to confirm it supports network control.
>
> This is an unofficial app made by an independent developer and is not affiliated with any manufacturer. Product names are used only to indicate compatibility; trademarks belong to their respective owners.

### Keywords
**Limit: 100 chars** (words already in the name or subtitle are indexed without repeating them)
> amp,amplifier,home theater,surround,knob,input,tuner,radio,zone,audio,hifi,stereo,speaker,music

---

## 予備: 説明文の【対応機種】（再度却下された場合）

日本語:
> 【対応機種】
> ネットワーク制御（HTTP / ポート 8080）に対応した AV レシーバーで使えます。動作確認済みの機種はサポートページをご覧ください。

English:
> COMPATIBILITY
> Works with AV receivers that support network control (HTTP on port 8080). See the support page for tested models.
