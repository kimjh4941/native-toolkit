# レビュー結果

- 日付: 2026-10-18
- 対象ファイル: `artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md`（初版。コミット前）
- トピック名: ios-c-abi（UI テストの設計書。段階 0）
- 対象 OS: iOS 18 以降
- 判定: **要修正**（区分 A が残るので、設計書を直して再レビューする）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）
- 機械照合: `check_design_consistency.py` は FAIL 0（下書きのときに実行）

区分: A = 書かれたとおりだと、テスト・サンプル・契約が誤るか、私物の端末に対して安全でない、B = 確かめる手段、C = 記述。

## 強み

- 0a の実測（`NotificationShortLookView`、1.5 秒の長押し、返信の TextView、`PopoverDismissRegion`、Files の場所の選び直し、通知センターを使わない）を忠実に反映している（両方）
- サンプルのボタンの数（Dialog 6、Notification 25、Share 14）、id、結果の文字列、気になる動作の棚卸しがコードと一致する（両方）
- 私物の端末を区分で許可し、既定は何も流さない骨格は妥当（両方）
- `-only-testing`、`TEST_RUNNER_` の渡り方（Xcode 26.3 の man page）、`XCTSkip` の方式は成り立つ（Codex）

## 事実の照合（抜粋）

| 主張 | 結果 | 根拠 |
|---|---|---|
| ボタンの数、id、category、結果の文字列、D1〜D13・NP・N・S の期待値 | 一致 | 各 SampleView、`NotificationSampleView.swift:8-10,336-360` |
| サンプルの気になる動作（パスワードの平文、RequestPermission のエラーを捨てる、`NotificationError` が `LocalizedError` でない、取り消し・category が非同期、cancel 系が同じ処理） | 一致 | `DialogSampleView.swift:157-159`、`NotificationSampleView.swift:32-42`、`NotificationError.swift:9-27`、`IosNotificationManager.swift:179-231,306-316` |
| U-17「Clipboard の形 = ボタンの文言の lowerCamelCase」 | 不正確。Clipboard の id は marker（`loadText` など） | `ClipboardSampleView.swift:16,993` |
| 「README の 0b は『見た目も動作も変えない』」 | 古い。README は既に最後のイベントの表示を含む。残るのは U-3 だけ | `README.md` の 0b の行 |
| 5.1 の識別子の一覧 | Clipboard の画面の既存の id（`clipboard.result` など約 55）が入っていない | `ClipboardSampleView.swift:9-90` |

## 指摘と対応

### 区分 A

| ID | 出典 | 対象 | 指摘 | 対応 |
|---|---|---|---|---|
| A-1 | 両方 | U-9・U-10・6.1・7 章 | 「区分の確かめの書き忘れを構造で起こせない」は成り立たない。Share のシートは `share.button.*` を押すだけで開く（連絡先と実在のアプリが出る）。`XCUIDevice.shared.press(.home)`、設定のアプリ（N3）は印が要らない。今の Clipboard のテストはアプリのボタンで一般のクリップボードを消せる。印が区分ごとの型でなく、clipboard の印で springboard を作れる。N1・N13・N17・N20・N21・N22 と片付けは springboard を使うのに区分が無い | 区分を基底クラスの宣言（テストごとの網羅的な表。表に無いテストは失敗）で持ち、`setUpWithError` の最初に評価する。印を区分ごとの型にし、シートを開くボタン、ホーム、設定のアプリ、Copy（`sharesheet` + `clipboard`）、Save（`files`）、springboard は、印を引数に取る API だけで行う。Clipboard のクラスは全体を `clipboard` 必須にする。片付けをアプリの中と springboard に分ける。ソースの検査（grep）の対象に `XCUIApplication(bundleIdentifier:`、`XCUIDevice.shared.press`、`UIPasteboard` を足し、変異は「区分を消すとソースの検査が落ちる」形にする |
| A-2 | 両方 | I1・7 章 | 識別子を付けずに足したボタンは `<画面>.` で始まる要素に入らないので、I1 は落ちない。Clipboard の画面の既存の id が一覧に無いので、I1 は初日から落ちる | 画面の `app.buttons` を全部集め（戻るなどは明示して除く）、すべてが `<画面>.button.` の id を持つことと件数の一致を照らす。Clipboard の既存の id を一覧に入れる。スクロールせず 1 回の snapshot で集める（VStack は遅延でない） |
| A-3 | Codex | 3.0 の共通の前提 | `notDetermined` のとき setUp が RequestPermission と Allow を行うので、`systemui` を許していない実機でも権限のダイアログを操作する | 実機の通常のテストでは、`notDetermined` を「前提の不成立」として gated skip にする。Allow を押すのは `systemui` を宣言したテストだけ |
| A-4 | Codex | U-4・N28・N29・N32・N33 | 最後のイベントを main に非同期で積むだけだと、背景の Delete・返信で `completionHandler` の後にプロセスが止まり、保存の前に失われうる | 受け手の中で、ロックで守ったアプリ全体の入れ物に同期で保存し、画面への通知だけを main に送る。コールドスタートの画面は保存済みの snapshot を読む。SwiftUI の再描画（Observation）の持ち方も書く |
| A-5 | 両方 | U-8 | `addUIInterruptionMonitor` で何も押さずに `true` を返すのは約束に反する（XCTest は元の操作をやり直し、同じアラートに塞がれる）。通知のバナーも割り込みとして扱われうるので、サンプルのバナーで監視が失敗を記録しうる。私物の通知のラベルを失敗の文に書くおそれもある | `.alert` だけを対象にし、既知の安全な否定のボタン（許可しない、今はしない、キャンセル）だけを押して `true` を返し、失敗を記録する。閉じられない未知のアラートはアプリを止めて以後の操作をしない。バナーは `false` を返す。実機では失敗の文にラベルを書かない。パスワードの保存・AutoFill・写真・ローカルネットワークが監視に来るかは、確かめるまで D11〜D13 を実機で `systemui` 扱いにする |
| A-6 | Codex | U-12・CB2 | アプリを止めて起動し直しても、別の xcodebuild で流しても、OS の貼り付けの許可の状態は初めに戻らない（0a で、許可 → 別のテスト → 拒否でダイアログが出なかった） | 0c の最初に、シミュレーターと実機で出る条件を確かめる。要るなら `reinstall` の区分を求め、アプリを削除してから単独で流す。安定しなければ人の確認にする |
| A-7 | 両方 | N9・N23・N24・7 章 | ①`registerCategory` / `removeCategory` は fire-and-forget なので、直後に即時の通知を出すと反映の前に出うる。②変異「update で予約を消さない」は、同じ id の add を OS が置き換えるので生き残る。③変異「registerCategory で設定しない」は、category が OS に残るので生き残る | ①N23・N24 は 5 秒の予約の通知を使うか、自動化から外す。②変異を変える（別の id で add する、trigger を渡さない）か、OS が保証するので検出できないと書いて外す。③N23 は先に RemoveCategory で消えたことを確かめ、Register の後に出ることを前後の差で確かめる |
| A-8 | Codex | N22 | ホームのアイコンのバッジを読むのは springboard の操作なのに、`systemui` が付いていない | 自動で読むなら `systemui` を付ける。許可が無ければ結果の行だけを確かめ、HC3 に回す |
| A-9 | Claude | U-10・区分 `clipboard` | 実機の一般のクリップボードへの書き込みは、Universal Clipboard で利用者の Mac などにも届く。流している間に利用者が Mac でコピーすると端末の側が書き換わり、外から来た内容を読むので「ペーストを許可」が出る（監視が無ければ既定のハンドラが自動で許可する）。許可を求める説明にほかの端末への影響が入っていない | 許可を求める文に「同じ Apple ID のほかの端末のクリップボードも上書きされうる」ことを入れ、流す間は Handoff を切るかを利用者に尋ねる。今の 22 件にも U-8 の監視を付ける（U-10 の「1 行だけ」を改める） |

### 区分 B

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| B-1 | Codex | N24 は「広げられなかった」と「アクションが無い」を区別できない | 広げた状態に固有の要素を両方の OS で確かめてから採る。確かめられなければ人の確認にする |
| B-2 | Codex | S9 の「だめなら cancel」では、2 つのファイルを渡せることも保存の成功も確かめない | 成功の経路を確かめられた環境だけ自動にし、ほかは人の確認に移す |
| B-3 | 両方 | Dialog の変異の期待の誤り（確認のボタンが `onCancel` を呼ぶ変異で落ちるのは D2）。D14 の「回数 2」は、callback 2 回で completion 0 回でも通る。Dialog が出ている間に後ろの結果の行を読めるかは 0a で試していない | 変異の表を直す。U-3 の値を種類ごとの回数（`completion=1,callback=1`）にし、D14 は各 Dialog の前からの増分で判定する。D1・D2・D6 の「出ている間の結果の行」は 0c の最初に確かめる |
| B-4 | Claude | 実機の私物の設定（集中モード、通知のプレビュー「しない」、バナーの種類「持続的」、通知の要約）でバナーの判定が崩れうる。私物の通知のバナーが押す対象に重なりうる | 流す前の確認項目に足す。サンプルだけを許可する集中モードで流す案を利用者に示す |
| B-5 | Claude | 錨が足りない: アプリの名前を `CONTAINS[c]` で選んでいる（私物の通知に名前が入りうる）。`springboard.buttons["Open"]` などの範囲が限られていない。Copy や「“ファイル”に保存」は私物のショートカットと重なりうる | `BEGINSWITH[c] 'IosLibraryExample, '` にする。広げたサンプルの通知の中に範囲を限る。ちょうど 1 件（`.element`）でなければ押さずに失敗する |
| B-6 | Claude | 変異「setup() を onAppear へ移す」で N30 が落ちる保証が無い（iOS が起動のきっかけの応答を後で渡すことがある） | 「結果を記録する」にし、決まって落ちる変異（受け手を画面の onAppear で登録する）を使う |
| B-7 | Claude | 6.3 の UI_CLASSES の照合は、基底クラスを継承したクラスを正規表現で拾えない | `-enumerate-tests` かビルドしたバンドルから導く |
| B-8 | Claude | 各ボタンを少なくとも 1 件のテストが押すことを確かめる仕組みが無い（`common.md` の「全ボタンが報告する」） | `SampleApp` が押した id を記録し、終わりに一覧と照らす |
| B-9 | Claude | U-6 の集合の比較で、`count:` と ids の個数と重複を照らす規定が無い | 3 つとも照らすと書く |
| B-10 | Claude | 私物の端末の向きで座標とスクロールが崩れる | setUp で縦向きにする |
| B-11 | Claude | N28 の座標のドラッグは、バナーが消えた後だと実機で Spotlight（私物の候補）を開きうる | 実機は長押しだけにする |

### 区分 C

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| C-1 | Codex | SwiftUI では、`Button` の中の `Text` に識別子を付けると、子の static text に付きうる | `Button(...).accessibilityIdentifier(...)` と Button そのものに付けると書く（Clipboard と同じ） |
| C-2 | Codex | 6.3 で、権限のクラスが通常のクラスの繰り返しでもう一度流れるように読める | 権限のクラスを UI_CLASSES から除き、メソッドごとに `-only-testing` で流すと書く |
| C-3 | Codex | `TEST_RUNNER_` を build setting で渡すのか環境変数で渡すのかが不明 | `TEST_RUNNER_NTK_DEVICE_ALLOW=... xcodebuild ...` の形で書く |
| C-4 | Claude | U-17 の「Clipboard の形」は marker で付けている。README の 0b の記述が古い | 直す。README に足すのは U-3 だけ |
| C-5 | Claude | U-14 の固定の待ちの表に、NP2 のバナーが出ないこと、N28 の前面に来ないこと、D14 の 2 秒が無い | 足す |
| C-6 | Claude | Share の準備の失敗の文言と N5 の添付が黙って無くなる経路を「テストに入れないもの」に。N8・N18 の成功の文字列を書く | 足す |
| C-7 | Claude | `--udid` は xcodebuild 用のハードウェアの UDID と devicectl の識別子の 2 つが要る | 書く |
| C-8 | Claude | 実機で流す前の知らせに、自動ロックと給電、毎回の上書きの入れ直し、Files の写しが増えること、キーボードが入力した語を学習することを入れる | 足す |
| C-9 | Claude | 7 章の変異はシミュレーターだけで流すと書く | 書く |
| C-10 | Claude | U-3 の回数は `resultText` と同じ `main.async` の中で増やし、`@State` に置く | 書く |
