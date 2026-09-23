#!/bin/bash
# App Store と App Review 用のスクリーンショットを撮る。すべてダークモード（既存のストア画像に合わせる）。
#
# 端末（DEVICES で絞れる）:
#   iphone69 … iPhone 17 Pro Max（6.9" / 1320x2868）。6.5" 枠はこれを流用できる
#   iphone63 … iPhone 17 Pro（6.3" / 1206x2622）
#   ipad13   … iPad Pro 13-inch (M5)（13"）
#
# 画面（ファイル名の番号がストアに並べる順番）:
#   dial       … ダッシュボード（音量ダイアル）
#   home       … ダッシュボード（スライダー）
#   input      … 入力ソース（iPhone のみ。iPad はダッシュボードに含まれる）
#   tuner      … チューナー
#   remote     … リモコン
#   settings   … 設定
#   connection … 接続設定（AVR の自動検出）（iPhone のみ）
#   support    … 開発を応援する（App Review 用。6.9" のみ）
#
# DEBUG ビルド限定の起動引数を使う（参照: upgraded-guacamole の scripts/capture-screenshots.sh）。
#   -uiDemo        … AVR が無くても接続中の画面を再現する。通信は一切しない（自動接続も Bonjour 検索もしない）
#   -uiDemoTab X   … 起動時に開くタブ（iPad はサイドバーの項目）
#   -uiDemoSupport … 購入画面を直接開き、StoreKit を使わずに 3 段を並べる
#                    （simctl から起動すると Xcode の StoreKit 設定が効かず、商品を読み込めないため）
#
# 撮影専用のシミュレータ（無ければ作成）で、毎回アプリを入れ直してまっさらな状態から撮る。
# 普段のデバッグ用シミュレータに保存された接続先や設定の影響を受けないようにするため
# （保存済みの接続先があると、LAN 上の実機 AVR に接続してしまう）。
#
# 使い方:
#   scripts/capture-screenshots.sh                          # 全端末・日英
#   LOCALES=en DEVICES="iphone69" scripts/capture-screenshots.sh
# 出力: build/screenshots/<端末>/<言語>/NN-<画面>.png
#
# 撮影後は必ず画像を目で確認すること。起動直後は iOS の通知バナーが写り込むことがある。
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT_DIR="${OUT_DIR:-build/screenshots}"
BUNDLE_ID="cc.nyoyapoya.denoncontroller"
read -r -a LOCALES <<< "${LOCALES:-ja en}"
read -r -a DEVICES <<< "${DEVICES:-iphone69 iphone63 ipad13}"

device_config() {  # 端末 → "シミュレータ名|端末の種類|画面"
  case "$1" in
    iphone69) echo "AVR Screenshots|iPhone 17 Pro Max|dial home input tuner remote settings connection support" ;;
    iphone63) echo "AVR Screenshots 6.3|iPhone 17 Pro|dial home input tuner remote settings connection" ;;
    ipad13)   echo "AVR Screenshots iPad 13|iPad Pro 13-inch (M5)|dial home tuner remote settings" ;;
    *) echo "unknown device: $1" >&2; exit 1 ;;
  esac
}

shot_args() {  # 画面 → 起動引数
  case "$1" in
    dial)       echo "-uiDemo -uiDemoTab home -volumeControlStyle dial" ;;
    home)       echo "-uiDemo -uiDemoTab home -volumeControlStyle slider" ;;
    input)      echo "-uiDemo -uiDemoTab input" ;;
    tuner)      echo "-uiDemo -uiDemoTab tuner" ;;
    remote)     echo "-uiDemo -uiDemoTab remote" ;;
    settings)   echo "-uiDemo -uiDemoTab settings -defaultHost 192.168.1.20" ;;
    connection) echo "-uiDemo -uiDemoTab connection" ;;
    support)    echo "-uiDemo -uiDemoSupport" ;;
    *) echo "unknown shot: $1" >&2; exit 1 ;;
  esac
}

(cd DenonController && xcodegen generate >/dev/null)

echo "== building for simulator =="
xcodebuild -project DenonController/DenonController.xcodeproj -scheme DenonControllerMobile \
  -configuration Debug -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build -quiet
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Denon Controller.app"

for device in "${DEVICES[@]}"; do
  IFS='|' read -r sim_name device_type shots_str <<< "$(device_config "$device")"
  read -r -a shots <<< "$shots_str"

  udid=$(xcrun simctl list devices available | grep "    $sim_name (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)
  if [ -z "$udid" ]; then
    echo "== creating simulator '$sim_name' ($device_type) =="
    udid=$(xcrun simctl create "$sim_name" "$device_type")
  fi

  echo "== $device: booting $sim_name ($udid) =="
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # 撮影用にステータスバーを整える
  xcrun simctl status_bar "$udid" override --time "9:41" \
    --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 \
    --cellularMode notSupported || true
  # 外観を切り替えた直後は端末側の再描画でアプリの起動が遅れるので、切り替えは最初に 1 回だけ行って待つ
  xcrun simctl ui "$udid" appearance dark
  sleep 4

  # まっさらな状態から撮る（撮影専用のシミュレータなので、アプリのデータを消してよい）
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$APP"

  # インストール直後の初回起動は遅く、スプラッシュが写ってしまうので一度起動して温める
  xcrun simctl launch "$udid" "$BUNDLE_ID" -uiDemo >/dev/null
  sleep 15
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true

  # iPad は起動後しばらくステータスバーが表示されないので長めに待つ
  wait_secs=$([ "$device" = ipad13 ] && echo 20 || echo 10)

  for locale in "${LOCALES[@]}"; do
    dir="$OUT_DIR/$device/$locale"
    mkdir -p "$dir"
    region=$([ "$locale" = ja ] && echo JP || echo US)
    n=0
    for shot in "${shots[@]}"; do
      n=$((n + 1))
      read -r -a args <<< "$(shot_args "$shot")"
      xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
      xcrun simctl launch "$udid" "$BUNDLE_ID" "${args[@]}" \
        -AppleLanguages "($locale)" -AppleLocale "${locale}_${region}" >/dev/null
      sleep "$wait_secs"  # 起動画面 → アプリ内スプラッシュ（1.5 秒）→ シートなどの表示が落ち着くまで
      file="$dir/$(printf '%02d' "$n")-$shot.png"
      xcrun simctl io "$udid" screenshot "$file" >/dev/null
      echo "captured $file"
    done
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
done

echo "screenshots in $OUT_DIR"
