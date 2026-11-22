# 段階 4 の結果: マニュアル、API リファレンス、見出しのアンカーの検査

- 実施日: 2026-11-21
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 4
- ブランチ: `feature/NTKIT-18`
- 判定: **完了**（2026-11-21）。リリース（ルートの README の版、ドキュメントの公開、マージとタグ）は、利用者の指示（「2.0.0 のリリース以外の作業を推奨順で」）で行っていない。新しい画面の写真は利用者に残す（5 章）

## 1. 決めたこと（利用者の指示「判断が要る場合は推奨案で」による）

| # | 決定 | 理由 |
|---|---|---|
| M-1 | マニュアルの版は **1.14.0**（2b で決めたリリース版）、iOS のライブラリは 2.0.0 | 段階 2b の決定（作業の記録 17.13） |
| M-2 | **Swift の API を本文、C ABI を各機能の章の `### C ABI`**、1.x からの移行と組み込みは index に書く | Android の M-2・Windows の F-3 と同じ。コード例をサンプルと一致させられる |
| M-3 | C ABI のヘッダーの API リファレンスを **Doxygen** で作り、生成物（`ios/IosLibraryCApi/docs/html`）をリポジトリに入れる。`publish_docs.sh` が作り直して `docs/<版>/ios/IosLibraryCApi` に写す | Android の M-3 と同じ |
| M-4 | **Unity の記載はこのリポジトリのマニュアルと README に書かない**（Android の M-4 をそのまま） | Unity の使い方は `unity-native-plugin` が書く。DocC の表紙の「C# (Unity included)」も外した |
| M-5 | **見出しの付け方**: `### C ABI`・`### Setup` などは OS の節ごとに同じ名前のまま付け、GitHub の `-1`・`-2` の番号を目次で正しく使う。正しさは `verify_manual.sh` の新しい検査 8（止める項目）で守る | 名前を変えて避ける案は、C の例の照合が `### C ABI` だけを C ABI の節と読むので取れない（Android の段階 4 の 5 章）。明示のアンカー（`<a id>`）は、GitHub と公開のどちらでも効くかが確かでない。検査なら、ずれを作った時点で止まる |
| M-6 | ヘッダーのコメントは **Doxygen が拾う形**にそろえる（関数・typedef・構造体・列挙に `/** */`、項目に `/**< */`、まとめた説明はメンバーグループ）。宣言は変えない。そろえた後に `dist/1.14.0/ios` を作り直す | 134 関数のうち 64 が Doxygen の説明に出ていなかった（全体で 205 か所）。dist のヘッダーはソースと同じことを照合している（`check_ios_dist.py`）ので、作り直しが要る。動くコードは変わらない |
| M-7 | Swift の公開の doc コメント（DocC と swiftinterface に出る）から、設計書の番号・日本語の文・消したブリッジの記述を外す。コメントだけ | M-6 で dist を作り直すので同じ回に入れる |
| M-8 | D-17 の選択肢 B（`dist/` に path の `binaryTarget` を持つ `Package.swift`）は**足さない** | 組み込みは 2 つの XCFramework を Embed & Sign するだけで、手順は短い（Framework Search Paths も要らない。レビュー K-C2） |

## 2. したこと

| 対象 | 内容 | コミット |
|---|---|---|
| C のヘッダー（5 本） | Doxygen の警告 205 → 0（関数 64、typedef 35、構造体 10、項目 92、マクロ 4）。宣言はコメントを除いた比較で同一。あわせて 3 つの記述を直した: ログインの placeholder は NULL で "Username"/"Password"、`ntk_dialog_cancel`・`ntk_clipboard_cancel_load` はいつも NONE、`NTK_NOTIFICATION_CATEGORY_ALLOW_ANNOUNCEMENT` は効果なし。スナップショットの型は「最初の項目の」 | `d5c9889b` |
| Swift の doc コメント（31 ファイル） | 設計書の番号・日本語・ブリッジの記述を外し、`ShareError`・`PresenterSelection` に SH-13 の失敗の場合、`ClipboardChangeEvent.changedDetectedOnForeground` に 2.0.0 では届かないこと、`ClipboardError` の case の説明を足した。DocC の警告 37 → 1（残りは AppIntents の知らせ）。変わった行はすべて `///` | `d5c9889b` |
| DocC の表紙 | 1.x の Dialog だけの説明から、4 機能・スレッド・エラー・presenter と要求の箱・通知の delegate とイベント・Clipboard の注意・C ABI への案内・Topics に書き直した（警告 7 → 0。すぐ使える例は Swift 6 で型を照合した） | `d5c9889b` |
| Doxygen | `ios/IosLibraryCApi/Doxyfile`（Android のものを元に）、生成物、`publish_docs.sh`・`docs/README.md`・ルートの README（3 言語）の手順 | `d5c9889b` |
| 規則 | `ios.md` の「C ABI の置き方」: ヘッダーの説明は Doxygen が拾う形で書き、警告 0 件を保つ | `d5c9889b` |
| `dist/1.14.0/ios` | Xcode 26.6 で作り直した（ビルド番号 IosLibrary 19 → 20、capi 3 → 4）。`check_ios_dist.py 1.14.0` は FAIL・SKIP 0、`check_c_abi_contract_ios.py --library` は両スライスで 134、smoke は Xcode 26.6 と 26.3 でシミュレーターの 16 段が通る。`unity-native-plugin` にコメントだけの作り直しと伝えた | `68ca7674` |
| マニュアル（英語） | 4 機能の章の iOS を 2.0.0 の Swift の API で書き直し、`### C ABI` を足した（サブエージェント 4 本が並行で書いた）。index: 成果物の場所（1.14.0）、版、iOS の機能の一覧と C ABI に無いもの、iOS の組み込み（2 つの XCFramework、手順、プライバシーマニフェスト、通知の delegate、C ABI、2.0.0 への移行の表）。1.14.0 の `dist/1.13.0/` の道をすべて `dist/1.14.0/` にした | `2d69622c` |
| 検査 | `verify_manual.sh` に検査 8「anchors in OS sections」（目次で OS の項目の下にあるリンクが、その OS の `## ` の節の中の見出しを指すか。目次の見出しは英語・日本語・韓国語）。write-manual と verify-manual の手順に書いた | `2d69622c` と次のコミット |
| マニュアル（日本語・韓国語） | レビューの直しの後に、5 本のサブエージェントで訳した（4 章と index。index の見出しの訳は先に決めて、ページ間のリンクをそろえた） | 次のコミット |

## 3. レビュー

`reviews/2026-11-21-ios-c-abi-stage4-manual-review-v1.md`。英語の版を 3 つの観点（Swift の API、C ABI と組み込み、全体の正しさと手順どおりに成功するか）で見て、A は 0 件、B が 7 件、C が 16 件。すべて直した（K-C8 は別の形で）。主なもの:

- 移行の表の抜け: 自分で実装した `NotificationRepository`・`ShareRepository` が組めなくなる変更、`getRootViewController()` の `@MainActor`、`content` の `sending`、非推奨、`errorMessage`
- そのままでは組めない Swift の例が 4 つ（`catch` が網羅していない、前の例の `content` を使い回す、`Task` が無い、`try` が `do` の外）
- 「C ABI に無いもの」の書き漏らし（provisional の許可、年〜秒のほかの暦の条件）
- `ntk_clipboard_detect_values_async` の JSON の形

訳した後に、訳したサブエージェントの指摘で英語を 4 か所直した（`centre` の綴り、Share の対応表の書き方、通知の入れ直しの約束の文、manager の `throws` の注）。

## 4. 確かめたこと

- `check_manual_c_examples_ios.py 1.14.0 --require-examples --require-compile`: coverage（134）、symbols、parity（3 言語）、compile（18 の例、Xcode の clang と iOS の SDK、`-Wall -Wextra -Werror`）がすべて OK
- `check_manual_c_examples_android.py 1.14.0 --require-examples`（155、17 の例）、`check_manual_c_examples_windows.py 1.14.0`（105。compile は Windows でしか流せず SKIP）も OK
- `verify_manual.sh 1.14.0`: 止まる失敗は画像の 30 件だけ（1.12.0 から引き継いだ macOS の通知の画像と index の Android の画像。`manual-integrity`）。警告は言語差分の 14 件（同じ macOS の画像）と、macOS の Share の 1 件。どちらも 1.13.0 と同じ
- 検査 8 は、1.13.0 で 22 件（英語 7 件と日本語・韓国語）のずれを見つける。1.14.0 は 0 件。試しのページで、ずれると落ち、直すと通ることを確かめた
- マニュアルの照合の自己テスト 67 件が通る
- Doxygen の警告 0 件、生成物に手元の道を含まない

## 5. 残すこと

- **画面の写真**（マニュアルは今ある写真だけを使い、無い写真は参照していない）: 
  - Clipboard: 「Swift API (2.0.0)」のボタン（Load Text, Then Cancel at Once ほか）
  - Dialog: 2.0.0 の要求のダイアログ（Request Alert ほか 6 つ）と、同じターンに 2 つを重ねる例
  - Notification: 2.0.0 の画面の全体（1.x の `Example_IosNotificationManager.png` は外した）、「Swift API (2.0.0)」の節
  - Share: `ShareRequestText`。`Example_IosShareManager.png` は画面の上だけなので、撮り直してもよい
- ~~HC13（Clipboard の CB1 の人の確認）~~: 2026-11-22 に利用者が行い合格（段階 2 の作業の記録 17.17）
- リリース（README 5.3）: ルートの README（3 言語）の版と配布物の一覧、`publish_docs.sh 1.14.0`、PR とマージとタグ
- 範囲外で見つけたもの（直していない）: 1.13.0 以前のマニュアルの目次のずれ（検査 8 が見つける）、macOS の Share の例のリテラル
