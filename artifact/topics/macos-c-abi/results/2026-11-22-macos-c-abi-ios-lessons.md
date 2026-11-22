# iOS の C ABI から引き継ぐ知見

- 記録日: 2026-11-22
- 出典: `artifact/topics/ios-c-abi/`（1.14.0、iOS 2.0.0）の README、設計書、作業の記録、終わりの記録を読んだ調査（`2026-11-22-macos-c-abi-survey-b-ios-carryover.md` の 4 章）。iOS の `results/2026-10-18-ios-c-abi-android-lessons.md`（Android から iOS へ）と同じ形
- 使い方: 企画（`../plans/2026-11-22-macos-c-abi-plan.md`）と決定（`../plans/2026-11-22-macos-c-abi-decisions.md`）が、各項目をどの決定か章で扱うかを示す。「iOS で起きたこと」は記録の事実、「macOS で最初にすること」は提案

| # | 項目 | iOS で起きたこと | macOS で最初にすること | 扱う場所 |
|---|---|---|---|---|
| 1 | 本物のホストでの確かめを先に | Android は smoke だけで確かめて申し送りを誤った。iOS は 1a で `unity-native-plugin` の agent に 2 回の申し送りを出し、`didFinishLaunching` で入れる形、パッケージの入れ直し、起動のきっかけの判定の絞りが決まった | Unity の macOS の書き出しで、(a) プラグインがいつ読み込まれるか、(b) 起動の中で delegate を入れられる口があるか、(c) 通知のクリックでの起動、(d) C# のスレッド、(e) Dialog の間にゲームが止まるか、を最初の申し送りに入れる。結果で D-4・D-8・D-24 が変わる | 決定 8.2 の 1a-9 |
| 2 | 表示の同時の要求と完了の 1 回 | 第 1 部の同時の要求と完了の 1 回はレビューで 4 版かかった。リリースの直前に SH-13（同じ回の 2 つ目の Share の完了が来ない）が報告され、設計メモ 3 版・レビュー 3 本・dist の作り直しになった | 「同じ main の回に同じ表示を 2 回」「表示の途中にもう 1 つ」「外から閉じる」を、Dialog（`runModal`）・ファイルのパネル・Share のピッカーのそれぞれで最初の設計の表に入れ、測ってから決める | 決定 8.2 の 1a-6、8.6 |
| 3 | 循環の防止は範囲を絞る | 通知の delegate の循環の防止は、広い形がレビューのたびに穴を見つけられ、「最初の転送の同期の戻りだけを止め、ほかは契約の外」に絞った | iOS の router と範囲をそのまま写す（作り直さない） | D-7 |
| 4 | 1 秒ごとの階層の見張りは入れない | 見張りが本当の結果を上書きする危険のほうが大きく外した | 解放の見張り（`ReleaseWatch`。UIKit を使わない）の形を写し、AppKit で解放の時期を測る | 8.6 |
| 5 | category の読み書きの競合 | actor の再入で 2 つの要求が同じ古い集合を読み、後の書き戻しが前を消した | macOS はメモリの集合を丸ごと置き換える形なので、iOS の FIFO を写し、最初から直列にする | 企画 4 章 |
| 6 | SwiftUI の `App.init` から入れると `UIApplication.shared` が無い | `sharedApplication` が nil なら「まだ active でない」とする形にした | `NSApp` が無い時期（`App.init`、`NSApplicationMain` の前）を最初の表に入れる | 8.6 |
| 7 | install の中の順番 | `center.delegate = proxy` の後に前の delegate と初回の印を設定していて、その間の呼び出しが古い状態を見た | install の順（前の delegate → 初回の印 → 代入）をテストごと写す | D-7 |
| 8 | Swift 6 の実行時の隔離の検査 | `@MainActor` のクラスを main 以外で手放すと止まり、`isolated deinit` で直した | 0f で、`@MainActor` のクラス（`MacClipboardManager` など）を main 以外で手放す経路を最初に探す | 企画 5 章の 0f |
| 9 | UI テストのターゲットの Swift 6 | complete で 316 件の警告がランナーの信頼する部分に出て、例外にした | 最初から UI テストのターゲットを例外にする | D-14 |
| 10 | `LastUpgradeCheck` の推奨設定 | 推奨の一覧は Xcode の画面でしか見られず、2.0.0 でも反映しないまま残った | 着手の前に、利用者に Xcode の画面で見てもらうか、扱わないと決める | 企画 5 章の 0e |
| 11 | テストのターゲットの最小 OS のずれ | iOS は 18.2 と 18.0 で、0e で直した | macOS はプロジェクトの階層が 15.1 で、テストと UI テストのターゲットが継ぐ（本体とサンプルのアプリはターゲットで 15.0）。`MacLibraryExampleTests` はターゲットにも 15.1 を直に書く。0e でプロジェクトの階層とそのターゲットを直し、実効の値を確かめる | D-15 |
| 12 | 決めたら表をその場で直す | Android で「設計で決める」のままリリースの直前に見つかった。iOS は守ったが、終わりの記録で古い記述の対応の表が要った | 同じ規則を企画に書いた。経過は段階の表に書き足さず作業の記録に書く（`topic-document-size`） | 企画 5.1 |
| 13 | 揺れるテスト | 固定の待ち、文字入力の Dialog、貼り付けのアラートの後始末が揺れた。テストは変えずに流し直した | 固定の待ちを使わない規則を最初から。macOS の Dialog と Share のピッカーは出るまでの時間を先に測る | 0a・UI テストの設計 |
| 14 | 自動の操作が通らないもの | 貼り付けのコントロールが実機で合成のタップを受け付けず、人の確認に回した | macOS の貼り付けのボタン、貼り付け板の確認、Share のピッカーが XCUITest の合成の操作を受け付けるかを 0a で先に確かめる | 0a |
| 15 | dist の探索の前方一致 | `unity-native-plugin` が前方一致で capi を選ぶので、iOS は dist を置く前に 3 つを頼んだ。macOS の固定は入れていない | macOS は今の前方一致（`unity-mac-native-toolkit-`）が新しい名前に当たらず、新しい dist を最新として選んで古い 1.3.0 のまま黙って進む。版の固定は次にどの OS でも dist を作る前に、残り（完全一致、`-debug` の戻り、symlink を保つコピー）は 2b で dist を置く前に頼む | 企画 5 章 |
| 16 | 署名の確かめは早めに決める | 配布用の署名は Program の登録が無く、最後に「行わない」と決めた | macOS は Library Validation と公証が利用者の体験に直に効く。企画の段で「署名しない」と、Developer ID と公証を確かめないことを決める | D-18 |
| 17 | 区切りの全件の時間 | 全件はシミュレーターで約 94 分 → 約 128 分 | macOS は UI テストの間この Mac を使えないので、全件の時刻を利用者と決める。VM で流せるなら VM で（D-21） | D-21、D-23 |
| 18 | ブリッジのために公開した口が残る | `ClipboardRedaction` を消せずに 2.0.0 に入った | `BridgeError`、`IconConfiguration.from(json:)`、`Log`、`ClipboardLog` などを 1b で洗い出し、消すか決める | 企画 4 章 |
| 19 | 申し送りの数え違い | Android は JSON のテストの数を実物と違えて書いた。iOS は実物を数えてから書いた | `unity-native-plugin` の macOS のテストを実物で数えてから対応表を書く | 8.6 |
| 20 | マニュアルの見出しのアンカー | 同じページの `### C ABI` が増えるとずれ、検査 8 を足した | 検査 8 はもうある。macOS の節を足しても通ることを段階 4 で見る | 段階 4 |

## macOS で新しく分かったこと（iOS に無かったもの）

企画の調査で分かった、iOS の経験からは見えなかった落とし穴。

| 項目 | 分かったこと | 扱う場所 |
|---|---|---|
| 版付きの framework のヘッダー | iOS と同じ設定では最上位の `Headers` のリンクが作られず、自分の module map が解けない | D-10、1a-1 |
| Library Validation | ad-hoc＋Hardened Runtime では、同じアプリの中で署名し直した framework も読まれない | D-18、企画 3.1 |
| 署名しない framework | 外側のアプリだけを署名しようとすると `codesign` が止まる。利用者は framework を署名し直す | D-18、企画 3.1 |
| 貼り付け板の `detect*` | `detectPatterns`・`detectMetadata` は内容を読まないが、`detectValues` は値を読み、拒まれると完了にエラーを返す（SDK の `NSPasteboard.h`）。調査 C の 5 章は `detect` 系をまとめて「内容を読まない」と書いた（日付の記録として残す。レビュー v1 の RA-5） | 決定の文書の 8.6 |
| `runModal` と main キュー | main キューのブロックの中の入れ子の run loop では main キューが捌かれない見込みがあり、Dialog が開いている間ほかの全機能の完了が止まりうる（レビュー v1 の RA-1。確かめていない） | D-8、1a-6 |
| `Contents/PlugIns` からの読み込み | 兄弟の framework を解くには rpath に `@loader_path/../../..` が要る | D-11、1a-3 |
| bundle の無いプロセス | `UNUserNotificationCenter.current()` が例外で落ちる | D-4、1a-5 |
| 今の dist の symlink | `rsync -aL` で実体に置き換わり、`codesign --verify` が通らない | D-9、企画 1.4 |
| テストの場所 | シミュレーターが無く、すべてのテストがこの Mac の上で私物に触れうる | D-21、D-23 |
