# Xcode なしで、配る .dmg を作る

Xcode の無い Mac で LaneKeep.app を作り、ほかの人に渡す .dmg にまとめる手順です。Xcode があるなら `make build` が正式です。

## 一度だけ

```sh
bash Tools/release/make_cert.sh   # 署名用の自作の証明書「LaneKeep Self-Signed」（10 年）をログインのキーチェーンに作る
```

初めて署名するとき、macOS が「codesign がキーを使う」許可を聞いてきます。ログインのパスワードを入れて「常に許可」を押します。
画面の出せない環境（サンドボックスの中など）では、この確認が出せずに `errSecInternalComponent` で止まります。

## 作るたびに

```sh
bash Tools/release/build_app.sh   # ~/Library/Caches/LaneKeep-build/out/LaneKeep.app（Apple シリコンと Intel の両方入り）
bash Tools/release/make_dmg.sh    # build/dist/LaneKeep_<版>_universal.dmg と、照合用の .sha256
```

版は `Config/LaneKeep.xcconfig` の `MARKETING_VERSION` から取ります。ビルドの作業場所はプロジェクトの外（`~/Library/Caches/LaneKeep-build`）です。

## Xcode で作るものとの違い

- 色（Assets.xcassets）は、同じ値をコードにして使います（色を読む道具 actool が Xcode にしか無いため）。全体の差し色（AccentColor）は効かないので、ラジオボタンなど macOS 標準の部品はシステムの色になります。
- KeyboardShortcuts は 2.4.0 を写して直して使います（Xcode にしか無いプレビュー用の記述を外す・文言をアプリの中から読む）。
- 署名は自作の証明書です。作り直してもアクセシビリティの許可が引き継がれます（macOS が照らし合わせる条件が「識別子＋証明書」になる）。
- Apple の公証はしていないので、ほかの Mac では初回に「このまま開く」が要ります。手順は .dmg の窓の絵と `dmg/はじめに読む.txt` にあります。

## .dmg の窓

- 絵の元は `dmg/background.html` です。直したら `bash Tools/release/dmg/render_background.sh` で描き直します（Google Chrome を使います）。
- 2〜5 の画面の写真（`dmg/shots/`）は、2026-10-17 に macOS 26.2 で撮った本物です。押す所の丸の位置は、写真の中のボタンの位置から割合で決めています。
- 「アプリケーション」と「設定を開く」はシンボリックリンクです。macOS 26 では Finder がアイコンを描かないことがあるという報告がありますが（作った Mac でも空の四角に見えました）、エイリアスにすると別の Mac で行き先が見つからないおそれがあるため、確実に動くほうを選んでいます。
