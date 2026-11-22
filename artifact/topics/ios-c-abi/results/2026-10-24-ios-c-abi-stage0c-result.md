# 段階 0c の結果: サンプルの UI テスト

- 記録日: 2026-10-24
- 実施日: 2026-10-18（前半）、2026-10-19（後半）、2026-10-24（M1・M2 と、実機の区分の無い 19 件。どちらも段階 0d の中で行った）
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 0c、`designs/2026-10-18-ios-c-abi-ui-test-design.md` の 3〜7 章と 8.1
- ブランチ: `feature/NTKIT-18`
- 判定: **シミュレーターでは完了**。実機（iPhone XS、iOS 18.7.2）では、区分の無い 19 件だけを流した。**区分の要る 80 件の実機の実行と、人の確認の手順書（HC1・HC4・HC7・HC8）が残る**（5 章、7 章）
- 作業の記録: `results/2026-10-18-ios-c-abi-stage0c-working-notes.md`（前半・後半）、`results/2026-10-24-ios-c-abi-stage0d-working-notes.md`（M1・M2、I1 の直し、実機の 3 回）

## 1. 結論

設計書 3.6 の 99 件（新しい 77 件と、既存の Clipboard の 22 件）を、すべてテストにした。通知からのコールドスタート（N30〜N33）も含む。iOS 26.2 のシミュレーター（iPhone 17、en）では、クラスごとに 3 回ずつ流して通った。段階 0d の全件の実行（基準）でも、99 件のうち 98 件が通り、1 件（U10b）は意図した skip だった。

実機は利用者の私物なので、区分の無い 19 件だけを流した。19/19 が通るまでに 2 回落ち、テストの側（I1 の戻るボタン）と流し方（集中モード）を直した（0d の結果の 6 章）。区分の要るテストの実機の実行は、区分ごとに利用者の許可を得て行う（7 章）。

`ios/IosLibrary` は変えていない。サンプルは、返信の placeholder の 1 か所だけを変えた（0d のレビュー v2 の R-21。0b の結果の 5 章）。

## 2. テストの一覧

テストのターゲット `IosLibraryExampleUITests` に、11 クラス 99 件がある。区分は宣言の表（`Support/DeviceRequirements.json`）の値。

| クラス | 機能 | 件数 | ID | 宣言の区分 | 流し方 |
|---|---|---|---|---|---|
| `NavigationUITests` | Common | 2 | M1、M2 | なし | クラスごと（0d で足した） |
| `IdentifierInventoryUITests` | Common | 4 | I1a〜I1d | I1a〜I1c はなし。I1d は `clipboard` | クラスごと |
| `DialogUITests` | Dialog | 15 | D1〜D15 | D11〜D13・D15 は `credentials`。ほかはなし | クラスごと |
| `NotificationPermissionUITests` | Notification | 2 | NP1、NP2 | `reinstall`、`systemui` | 権限の段（削除 → NP2 → 削除 → NP1） |
| `NotificationUITests` | Notification | 23 | N1〜N22、N34 | N1・N21・N22 はなし。ほかは `systemui` | クラスごと |
| `NotificationEventUITests` | Notification | 7 | N23〜N29 | `systemui` | クラスごと |
| `NotificationColdStartUITests` | Notification | 4 | N30〜N33 | `systemui` | クラスごと |
| `ShareUITests` | Share | 16 | S1〜S16 | `sharesheet`。S1・S4・S6・S10 は `clipboard` も、S8・S9 は `files` も | クラスごと |
| `ClipboardUITests`（既存） | Clipboard | 22 | U1〜U21（U10 は U10a と U10b） | `clipboard`。U10a は `systemui` も | クラスごと |
| `ClipboardPasteUITests` | Clipboard | 3 | CB1、CB3、CB4 | `clipboard`。CB1 は `systemui` も | クラスごと |
| `ClipboardPasteDenyUITests` | Clipboard | 1 | CB2 | `clipboard`、`systemui` | CB2 の段（単独） |
| 計 | | 99 | | | |

機能ごとの件数は、Common 6、Dialog 15、Notification 36、Share 16、Clipboard 26。区分ごとの件数は 7 章。

ほかに足したもの・変えたもの:

| 所 | 中身 |
|---|---|
| `Support/` の 8 ファイル（信頼する部分） | 基底 `SampleUITestCase`、`SampleApp`、`Springboard`、`ShareSheet`、`RunnerPasteboard`、`UnexpectedAlertGuard`、`NotificationCleanup`、`SystemLabels`。中身は `scripts/ios_ui_runner.py` の `TRUSTED_FILES` にハッシュで固定した（0d の結果の 2.3） |
| `Support/DeviceRequirements.json` | 宣言の表。99 件 |
| `IosLibraryExampleUITests.swift` | 雛形のクラスを消し、`final class ClipboardUITests: SampleUITestCase` にした。setUp と tearDown を `setUpAfterGate()` / `tearDownAfterGate()` に改名した。本体は変えていない。ファイルのハッシュを固定した |
| `IosLibraryExampleUITestsLaunchTests.swift` | 消した（雛形の `testLaunch`） |

雛形の 3 件（`testExample`、`testLaunchPerformance`、`testLaunch`）を消したので、UI テストは 25 件から 99 件になった。

## 3. 確かめたこと

**シミュレーター**（iPhone 17、iOS 26.2、en、Xcode 26.3）:

| 実行 | 結果 |
|---|---|
| クラスごとに 3 回（0c の前半・後半） | Dialog 15、識別子 4、権限 2、Notification 23、Event 7、ColdStart 4、Share 16、ClipboardPaste 3、CB2 1 が、3 回とも通った。Share は 2 回目に S9 が 1 回落ち、直した後に 3/3（S8・S9 だけでもさらに 3/3）。N11・N19 は直した後にさらに 3/3 |
| `NavigationUITests` を 3 回（0d） | 3 回とも 2/2 |
| 既存の `ClipboardUITests` | 0c の載せ替えの後は U1〜U3 だけを流した（3/3）。22 件は 0d の全件の実行で流した（21 件が通り、U10b は意図した skip） |
| `--feature Notification --name-each-test`（0d。1 件ずつ名指し） | 1 回目 40/42（N29・N32 が返信の欄の照合で落ちた。直した）、2 回目 42/42 |
| 0d の全件の実行（基準） | UI テスト 99 件のうち 98 件が通り、U10b は意図した skip。押したボタンの照合（3.7）も通った |
| 18.3.1 のシミュレーター（iPhone 16、ja） | 0d で I1 を直した後に、I1a〜I1d が 4/4。基準にはしない（U-16） |

1 回の時間（0c の実測）: Dialog 約 200 秒、識別子 約 28 秒、Notification 1053〜1066 秒、Event 465〜470 秒、ColdStart 202〜207 秒、Share 183〜191 秒、ClipboardPaste 約 75 秒、CB2 約 23 秒。全件の時間は 0d の結果の 5 章。

0d の作業の記録 11.3 で、N32 が 1 回だけ「返信の欄が出ない」で落ちた（placeholder を変えた直後。前の category が OS に残っていたためと見ている。確かめてはいない）。押さずに失敗する形なので、安全の側。その後の N32 は通っている。

**実機**（iPhone XS、iOS 18.7.2、ja）: 区分の無い 19 件（M1、M2、I1a〜I1c、D1〜D10・D14、N1・N21・N22）を 3 回流した。1 回目 16/19、2 回目 18/19、3 回目 19/19。原因と直しは 0d の結果の 6 章。

**8.1 の実測**（0c の作業の記録の 3 章・7.2、0d の作業の記録の 12・13 章の要約）:

| 項目 | 結果 | 環境 |
|---|---|---|
| I1 の集め方 | スクロールせずに 1 回の snapshot で全ボタンが取れた（Dialog 6、Notification 25、Share 14、Clipboard 54）。位置ごとの和集合は要らない | シミュレーター。実機は I1a〜I1c が通った |
| ナビゲーションバーの戻るボタン | 26.2 は identifier `BackButton`。iOS 18（実機 18.7.2、シミュレーター 18.3.1）は identifier が空で、ラベルが `Main Menu` | 両方 |
| Dialog が出ている間に、後ろの結果の行を読めるか | 読める（D1・D2・D6） | 両方（実機は D1・D2・D6 が通った） |
| action sheet の取り消し | 26.2 は Popover で `Cancel` が無く、`PopoverDismissRegion` で閉じる。iOS 18 は `Cancel` を押す | 両方（実機は D7 が通った） |
| 通知のバナーが監視に来るか | 来る。`systemui` のテストで `false` を返すと、既定のハンドラはバナーが消えるのを最大 15 秒待って、操作を続ける | シミュレーター |
| springboard を明示して待って押す操作 | 監視を起こさない | シミュレーター |
| ダイアログのラベルのサンプルの名前（en） | 権限、貼り付けともに `“IosLibraryExample”` が入る | シミュレーター。ja は確かめていない |
| 広げた通知の要素 | 長押しで `notification-expanded-view` が出る。アクションのボタンはその中、返信の欄と Send はその外の別の window にある | シミュレーター |
| 同じ id の更新（N10） | `count: 1` のまま | シミュレーター |
| 同じファイルを 2 回添付（N5） | 2 回とも成功 | シミュレーター |
| 前面のバナーのタップ（N26） | 0.3 秒以内にイベントが来る | シミュレーター |
| 背景で起動したプロセス（N32・N33） | `activate` まで残り、イベントを読めた | シミュレーター |
| 設定の App（N3） | 約 0.55 秒で前面に来る | シミュレーター |
| カレンダーの +1 分（N7） | 約 73 秒で発火した（待ちは 90 秒のまま） | シミュレーター |
| アイコンのバッジ（N34） | value が 1 で `1 new item`、0 で空 | シミュレーター |
| 位置の予約（N8・N18） | 成功の文言を返し、予約の一覧に入る | シミュレーター |
| category の反映（N23・N24） | 削除の後は 3 秒間アクションが無く、登録の後は約 1.1 秒で出る | シミュレーター |
| Share のプレビューの題（S5） | `LP.CaptionBar.TopCaption` で読める | シミュレーター |
| 複数の Copy と Save to Files（S6・S9・S10） | どれも `completed=true` | シミュレーター |
| 貼り付けの許可のダイアログ（CB2） | ランナーが新しい内容を書くたびに出る。アプリの削除は要らない | シミュレーター |
| 画像だけの貼り付け（CB4） | `items=1, failures=0`。ダイアログは出ない | シミュレーター |

確かめていないもの（実機の区分の要る実行で確かめる）: 実機のバナーのラベルの区切り、ja の権限と貼り付けのダイアログのラベル（CB1 の出どころの判定を含む）、Universal Clipboard と `changeCount`、写真とローカルネットワークの権限のダイアログ、実機のログインの保存の確認と AutoFill、返信の予測の候補、実機での HC3・HC5・HC6・HC9 の要否。

## 4. 設計書から変えたこと

設計書の 8.6（0c）と 8.7（0d）に書いた。主なもの:

| 所 | 実際 | 書いた所 |
|---|---|---|
| 基底の入口 | async の形は上書きしない（上書きすると、XCTest の中の失敗のたびにランナーが落ちた）。子の上書きは閉じた形の規則で止める | 8.6 |
| 最後のイベントの `userText` | テキストの無いアクションでは `-` | 8.6 |
| N6、N13・N20、N11・N19 | N6 は発火の前の `count: 1` を N7 に任せる。N13・N20 は +1 分のカレンダーを使う。N11・N19 は窓の後に GetDelivered が空であることも確かめる | 8.6 |
| CB2 | `reinstall` を宣言しない | 8.6 |
| Share | 開いた印に `ActivityListView`。Copy はセルだけ。Save は Files のピッカーが落ち着いてから押す | 8.6 |
| springboard のアラートの数 | `SampleApp.remainingAlertCount` は印を取らずに数だけを読む（読むだけの例外） | 8.6 |
| M1・M2 | 0c で書かれておらず、0d で足した。M2 の `HasPermission` は `true` と `false` のどちらかの全文と比べる | 8.7 |
| 返信の欄と Send | 根がちょうど 1 つで、サンプルの題と本文であることを、押す前・入力の前・Send の前に取り直して確かめる。サンプルの placeholder を `IosLibraryExample reply` に変えた | 8.7 |
| CB1 の Allow Paste | 引用がちょうど 2 つで、出どころがランナーかサンプル自身のときだけ押す | 8.7 |
| I1 の戻るボタン | `BackButton`、または identifier が空でラベルが `Main Menu` のボタンが、ちょうど 1 つ | 8.7 |

監視が「押さずに止める」経路は、設計（包む関数が throw する）と違い、XCTest 自身の「no longer valid after interruption handling」で止まる。どちらでもテストは止まる（安全の側）が、失敗の文に監視の内容は残らない（0c の作業の記録の 2 章）。実機の 2 回目の M2 は、この形で止まった。

## 5. 人の確認（computer use）

0c の実測で、自動から人の確認に移したケースは無い。

| ID | 対象 | 状態 |
|---|---|---|
| HC1 | 通知の添付の画像 | 残る。手順書はまだ無く、行っていない |
| HC2 | 通知の音 | 欠番（対象外。U-19） |
| HC3 | アイコンのバッジ | シミュレーターでは要らない（N34 を自動にできた）。実機は N34 を流してから決める |
| HC4 | 通知センターからの起動と、消したときのイベント | 残る（区切りのとき。0g の後と 1b の後）。手順書はまだ無い |
| HC5 | コールドスタートの返信と Delete | シミュレーターでは要らない（N32・N33 が安定した）。実機は流してから決める |
| HC6 | Share のプレビューの題 | シミュレーターでは要らない（S5 で読めた）。実機は流してから決める |
| HC7 | Share の画像の中身（シミュレーターだけ） | 残る。手順書はまだ無い |
| HC8 | ShareMultiple の中身（シミュレーターだけ） | 残る。受け手がシミュレーターにあるかは確かめていない。手順書はまだ無い |
| HC9 | 複数のファイルの Save to Files | シミュレーターでは要らない（S9 を自動にできた）。実機は流してから決める |

手順書の置き場所（`ios/IosLibraryExample/ComputerUse/`。U-19、設計の 4 章）は、まだ作っていない。

## 6. 変異（シミュレーターだけ。どれも戻した）

| 壊したもの | 落ちたテスト・止まった所 |
|---|---|
| 宣言の表から D1 の行を消す | 0c では D1 が setUp で落ちた。0d では列挙と表の照合で止まった |
| 表のキーを重複させる | setUp で落ちた |
| D12 の宣言を `[]` にする | `credentialsToken()` が throw して落ちた（二段目） |
| Confirm の確認のボタンが `onCancel` を呼ぶ | D2（D3 は通った。予想どおり） |
| `onLogin` を 2 回呼ぶ | D15 |
| showAlert で `onButton` を 2 回呼び、completion を呼ばない | D1、D14 |
| 識別子の無いボタン、間接の補助で一覧に無い識別子を付けたボタン、識別子の重複 | どれも I1a |
| 子が `setUpWithError` や `setUp(completion:)` を上書きする | ビルドが通らない |
| 子が `setUp() async throws` などを上書きする | ビルドは通る。閉じた形の規則で止める（0d） |
| テストのファイルに `#if` を足す | 閉じた形の規則で止まった（ビルドの前。0d） |
| `foregroundPresentationOptions` を空にする | N4、N26 |
| `cancel` を何もしない形にする | N11（最初は生き残ったので、テストを強めた） |
| `removeDelivered` を何もしない形にする | N14 |
| `didReceive` で、アクションの id の代わりに通知の id を渡す | N25、N27、N28 |
| `registerCategory` で `setNotificationCategories` を呼ばない | N23 |
| `ShareSheetPresenter` で completed をいつも true にする | S2、S3 |
| サンプルの除外のリストを空にする | S12 |
| `onPaste` で貼り付けの結果を変えない | CB3 |
| 読み込みの失敗を成功（✅）として表示する | CB2 |
| I1 の判定を identifier の `BackButton` だけに戻す（0d） | 18.3.1 で I1a（実機と同じ `[""]`） |
| サンプルの題を `Main Menu 2` にする（0d） | 18.3.1 で I1a。26.2 は identifier で見分けるので通った |
| Dialog の画面のナビゲーションバーにボタンを 1 つ足す（0d） | 18.3.1 と 26.2 の両方で I1a（ボタンの数） |

ランナーの側の変異（設計の 7 章の柱 1〜3、結果の読み方、片付け）は 0d の結果の 3 章。全ボタン（3.7）の行は、ランナーの自己テスト（`test_two_attachments_or_broken_json_fail` など）で確かめた。

設計の 7 章のうち、作業の記録に結果が無い変異: Dialog の completion を 2 回呼ぶ（D1、D14）、`isEnabled` の行を消す（D8）、action sheet の取り消しが nil（D7）、受け手の登録と `setup()` を `onAppear` に移す（N30、N31）、入れ物を main に積むだけにする（N32、N33）、`UNTextInputNotificationResponse` を見分けない（N29）、`update` で別の id（N9）、`ScheduleTimeInterval` を 30 秒（N16）、`makeURL` の scheme（S14）、`ShareError` の文言（S13）、二段目の N4 の宣言（代わりに D12 で確かめた）、表を引く処理の `XCTFail`、`gatePassed` を見ない片付け、割り込みの監視の 2 行。

## 7. 残り: 実機の区分の要るテスト

区分の要るテストは 80 件。実機で流すときは、区分ごとに `--dry-run` の一覧を利用者に見せ、許可を得て `--approved` で流す（毎回新しい許可。0d の結果の 2.2）。

どの実行の前にも、設計の 6.5 の知らせをし、次の準備を頼む:

- 自動ロックを「なし」にし、給電する
- **集中モードを入れ、サンプル（IosLibraryExample）の通知だけを許す**（2026-10-24、利用者の決定。実機の 2 回目の M2 の失敗から）
- 終わったら戻してもらう設定を知らせる

| 区分 | 件数 | テスト | 前提・注意 |
|---|---|---|---|
| `systemui` | 31 | N2〜N20、N23〜N34 | 通知のバナー、ホーム、設定の App が画面に出る。プレビューの表示、バナーのスタイル（一時的）、時刻指定要約を確かめてもらう（6.5） |
| `reinstall`、`systemui` | 2 | NP1、NP2 | サンプルを削除して入れ直す（サンプルのデータが消える）。基準を取るときだけ |
| `sharesheet` | 10 | S2、S3、S5、S7、S11〜S16 | Share のシートに連絡先と実在のアプリが出る。押すのは閉じる操作だけ |
| `sharesheet`、`clipboard` | 4 | S1、S4、S6、S10 | 下の `clipboard` の前提も要る |
| `sharesheet`、`files` | 2 | S8、S9 | Files の「このiPhone内」に写しが増える |
| `clipboard` | 24 | U1〜U9、U10b、U11〜U21、CB3、CB4、I1d | **流す間、Handoff を切る**（切ってもらえなければ `clipboard` を許さない。U-10）。一般のクリップボードが上書きされ、元に戻らない |
| `clipboard`、`systemui` | 3 | U10a、CB1、CB2 | Handoff を切る。CB1・CB2 は貼り付けの許可のダイアログを押す。ja のラベルでの出どころの判定（0d のレビュー v1 の R-3）は、実機で初めて確かめる |
| `credentials` | 4 | D11〜D13、D15 | **先に、利用者が見ている前で、パスワードの保存の確認や AutoFill の候補が出るかを手で確かめる**（8.1）。確かめるまで許さない |
| 計 | 80 | | |

ほかの残り:

- 人の確認の手順書（HC1、HC4、HC7、HC8）を `ios/IosLibraryExample/ComputerUse/` に書き、行う
- 実機の区分の要る実行の結果から、HC3・HC5・HC6・HC9 が実機で要るかを決める
- 区分の要る実行の後、実機の基準（今は区分の無い 19 件だけ）を取り直すかを決める
