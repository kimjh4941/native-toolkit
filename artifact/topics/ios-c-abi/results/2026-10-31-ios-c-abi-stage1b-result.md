# 段階 1b の結果: Swift の API の補完

- 記録日: 2026-11-01
- 実施日: 2026-10-31〜2026-11-01
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 1b、`designs/2026-10-31-ios-c-abi-swift-api-design.md`（以下「設計書」。T-01〜T-23、15 章の C1〜C7）
- ブランチ: `feature/NTKIT-18`（C1〜C6 は `584ec55c`〜`97c95c71` でコミットした。C7 はその上の未コミットの変更）
- 判定: **完了（シミュレーター）**。ただし、MS-10 のプライバシーのレポート（利用者が Xcode の Organizer で作る。作業の記録 20.9）と、実機が要る項目（作業の記録 20.10。どれも利用者の許可が要る）が残る
- 作業の記録: `results/2026-10-31-ios-c-abi-stage1b-working-notes.md`（以下「記録」。コミットごとに 1 章。C7 は 20〜22 章。22 章は C7 のレビュー）
- レビュー: 設計書は `reviews/2026-10-31-ios-c-abi-swift-api-design-review-v1.md`〜`v3.md`。コードのレビューは C1〜C6 の各コミットの前に行い、記録の 3・6・9・12・16・19 章に指摘と直しを書いた。信頼する部分（UI テストの `Support/`）の変更は、どのコミットでも別のモデル（Codex）のレビューの後にハッシュを固定した

## 1. 結論

ブリッジ（`UnityIosPlugin`）にしか無かったロジックを `IosLibrary` に移し、ネイティブの利用者が Swift だけで全機能を使えるようにした（設計書 5.1、7 章）。C ABI の第 1 部が `IosLibrary` に求める条件（第 1 部 9.1 の S-1〜S-16）を満たす口を足した: 表示の口の `presenter` と要求の箱、Dialog と Clipboard の読み込みの要求ごとの取り消し、解放の見張り、通知の delegate の proxy と前の delegate への転送、イベントの口と保ち方、起動のきっかけ、安定したエラーの case、`async throws` 版、category の FIFO、ログの規則（`os.Logger`）、プライバシーマニフェスト。

C7 の作業ツリーで全体を流した（シミュレーター iPhone 17 / 26.2、`scripts/test_ios.sh`）: 678 件（`IosLibraryTests` 543、`IosLibraryExampleTests` 10、UI テスト 124、ボタンの網羅の 1 行 `IosLibraryExampleUITests#buttonCoverage`）のうち 677 件が成功し（ボタンの網羅の 1 行を含む）、skip の 1 件は基準と同じ意図した U10b。0g の後の基準との差は、足した 361 件（単体テスト 336、UI テスト 25）と、1b で名前を替えた・消したと記録した 4 件だけで、結果が変わったテストは 0 件。`IosLibraryTests` は iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3 と、TSan（iPhone 17 / 26.2）の全件で 543/543。TSan の回の skip は C7 で外せた（TSan の版でも見張りは働いた）。

## 2. コミット

| コミット | 中身 | 記録 |
|---|---|---|
| C1 `584ec55c` | `ios.md` のログの規則、`os.Logger` への書き換え（32 ファイル 160 か所）と `Log` の deprecated、プライバシーマニフェスト、`PresenterSelection`・`RequestBox`・`FailureDetail`・表示の手順・解放の見張り | 1〜3 章 |
| C2 `da620c67` | Dialog の 3 層、`show`・`cancel`・`foregroundViewController()`、今の 7 つの口の載せ直し、テストのホストのアプリ、SA-01〜SA-05・SA-16、D16〜D23 | 4〜6 章 |
| C3 `637b1078` | Share のエラー・`presenter`・箱と見張り・`Result` 版、SA-14、S17〜S19 | 7〜9 章 |
| C4 `747897de` | Clipboard の `loadItem(…requestBox:…)`・`cancelLoad(_:)`、DocC、SA-15、CB5・CB6 | 10〜12 章 |
| C5 `b80399eb` | 通知の delegate の router・proxy・入れる口・印・イベントの口・起動のきっかけ・今の受け手の deprecated、サンプルの起動の処理と試験の形、N34b・N35〜N37・N41・N43〜N45 | 13〜16 章 |
| C6 `97c95c71` | 通知のエラー・`async throws` 版・一覧の型の `Sendable`・userInfo の検査・権限と設定の画面の gate・category の列、SA-05・SA-09・SA-10・SA-13、N38〜N40・N42 | 17〜19 章 |
| C7（未コミット） | 14 章の測りの記録（MS-11・MS-13 の残り・無い添付）、TSan の skip を外す、UT-31 のテストと一覧、ブリッジのテストとの対応の 1 件、README・第 1 部・付録 A の直し、全体の実行、この文書 | 20〜22 章 |

## 3. 公開 API

- 差分は `results/swiftinterface/` の `IosLibrary-before-1b-f3c289d7.swiftinterface`（1b の前）から `IosLibrary-after-1b-c6.swiftinterface` まで、コミットごとの `2026-10-31-stage1b-c<n>.diff`（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）。C7 はライブラリのコードを変えていないので、C7 の作業ツリーを同じ組み方で組んだ swiftinterface は `after-1b-c6` と 1 文字も違わない（取り直していない）
- 利用者に見える変更は README 4.1 の 1b の行（移行の手引きの元）と設計書 3.3。付録 A の宣言と実装は一致している（記録の各章の照合。C7 で `addListener(_:)` と `async` の `requestPermission(options:presenter:)` の `@discardableResult` を付録 A に足した）
- **Xcode 26.3 で読めること（SR-15）**: Xcode 26.6（Swift 6.3.3）で組んだ `IosLibrary` の swiftinterface を、Xcode 26.3（Swift 6.2.4）の `swift-frontend -typecheck-module-from-interface` で 3 つのスライス（`arm64-apple-ios`、`arm64-apple-ios-simulator`、`x86_64-apple-ios-simulator`）の public と private の 6 つとも型検査した。どれも終了 0、出力 0 行。型つきの throws（`throws(IosLibrary.NotificationError)` が 3 か所）と `nonisolated(nonsending)` を含む。型を壊した写し（`NotificationError` を無い型に替えた）は 8 件のエラーで落ちたので、型検査は中身を読んでいる
- **組めなくなる今の呼び出し（UT-31、S-P26）**: `async` の関数（と `await` を含む `Task` の closure）の中で `completion` を書かずに呼んでいた 9 つの形: `setBadgeCount(_:)`、`registerCategory(_:)`、`removeCategory(identifier:)`、`trigger` を書いた `show(content:trigger:)`・`update(identifier:content:trigger:)`・`schedule(content:trigger:identifier:)`、`requestPermission()`、`requestPermission(options:)`、`openNotificationSettings()`。`await`（`try` も要るものは `try await`）を足せば組める。黙って意味が変わる形は無い。`swiftc -typecheck` で Swift 5 と 6 の言語モード、Xcode 26.3 と 26.6 で確かめた（記録 20.6）

## 4. テストと基準

| 実行 | 結果 |
|---|---|
| `IosLibraryTests`（iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1。Xcode 26.6） | どれも 543/543（1b の前は 211） |
| `IosLibraryTests` の TSan（iPhone 17 / 26.2） | 543/543、skip 0、報告 0 件。D20・S19 もサンプルを TSan で組んで通った |
| `scripts/test_ios.sh`（iPhone 17 / 26.2、Xcode 26.3、全体） | 678 件: 成功 677、skip 1（意図した U10b）。678 = `IosLibraryTests` 543 + `IosLibraryExampleTests` 10 + UI テスト 124（1b の前は 99）+ ボタンの網羅の 1 行（`results.jsonl` の `IosLibraryExampleUITests#buttonCoverage`）。成功の 677 はボタンの網羅の 1 行を含む（記録 20.7） |
| 0g の後の基準（320 件）との比べ合わせ | `changed=0, added=361, removed=4`。removed の 4 件は名前を替えた・消したテスト（記録 20.7）。このため `test_ios.sh` の終了の値は 1（基準を取り直すまで続く。記録 21 章の 2） |
| 機能ごとの UI テストの差 | Dialog +8（D16〜D23）、Notification +12（N34b・N35〜N45）、Share +3（S17〜S19）、Clipboard +2（CB5・CB6）。変えた結果は 0、消したテストは 0。D12 は期待値を変えた（パスワードを長さだけに。設計書 13.3） |
| ランナーの自己テスト / `scripts/tests` の全体 | 144/144 / 352/352 |
| 警告 | 2 つの scheme の clean・whole-module のビルドで、Xcode 26.3 と 26.6 ともエラー 0、警告 0 |
| 壊して確かめたこと | M1〜M160（記録の各章の表。UI テストの変異は流していない） |

設計書 13.3 の「変える今の期待値」は D12 だけで、ほかの 0c の UI テストは期待値を変えずに通った。N25〜N33 は記録の元をイベントの口に替えて同じ期待値で通り、経路（`path=hub`）の確かめを足した。

## 5. 測ったこと（設計書 14 章）

MS-01〜MS-14 の結果と反映した所は記録 20.3 の表。要点:

- 前面（G-6）: `foregroundInactive` の間も Dialog と Share は出る。iPad の複数の window では key window が 2 つになり、前面の探し方はどちらかを選ぶ。Swift の利用者は表示元を `.viewController(_:)` で渡せる。C ABI は前面を探すだけ（第 1 部 P1-11 の C）で、どちらの window に出すかは決まらない。C に表示元を渡す口を足すかは第 2 部で決める（記録 21 章の 6。第 1 部 5.13、README 3.1）
- 解放（G-7）: 外から閉じた Dialog は約 0.4 秒、Share は約 0.55 秒で解放され、見張りが `dismissedBySystem` で閉じる（Share の handler は呼ばれない）。TSan の版でも同じで、C7 で TSan の skip を外した
- 後ろ（G-7）: 後ろからの `UIApplication.open` は `false`。後ろで未決の権限を求めると OS は見えないままダイアログを出す。後ろの Clipboard は、ほかのアプリの内容でダイアログが出て、同期の読み出しは main を止める
- 通知: scene のアプリでも最初の `didBecomeActive` はコールドスタートの応答の後。`openSettingsFor` は設定の App のリンクから呼ばせられる（26.2）。category の反映は書き戻しの後の最初の読み直しで読める
- 例外（G-8）: 利用者の完了の中の `NSException` は巻き戻しを始めずにその場で `abort` した（MS-11、1 回。C++ の例外は試していない）
- 無い添付: `add` が `UNErrorDomain` の 100 で断り、通知は出ない（`addRequestFailed`）。入口で確かめるかは記録 21 章の 1
- ログ（MS-13）: シミュレーターでは `.private` も平文で見える。実機の見え方は実機の区切りで見る（記録 2 章の 2）
- プライバシーのレポート（MS-10）: **未**。利用者の手順は記録 20.9

## 6. マニュアル（段階 4）の元

1b の記録から、マニュアル（と移行の手引き）に書くと決めたもの。**決定待ち**と書いた行は、記録 21 章の決定で書くかどうか・書き方が決まる。移行の手引きの変更の一覧は README 4.1 の 1b の行。

| 書くこと | 出どころ |
|---|---|
| 通知の delegate は起動の処理で `installDelegate()` を呼んで入れる。UIKit のアプリは `application(_:didFinishLaunchingWithOptions:)`、SwiftUI は `UIApplicationDelegateAdaptor` の同じ所か `App.init`（`UIApplication.shared` がまだ無い時期は「まだ active でない」とみなすので、起動のきっかけが取れる）。`UIApplicationMain` の前は契約の外 | 記録 13.7（MS-12）、15 章の 1、16 章の B-4 |
| 前の delegate は 1 つだけ。ホスト（Unity の通知パッケージなど）が後から delegate を差し替えたら、`installDelegate()` / `ntk_notification_install` をもう一度呼ぶ（パッケージの `AuthorizationRequest` の後など）。ライブラリは差し替えを `.error` のログで知らせるが、自動では入れ直さない | 記録 13.10 の H2-3 |
| `launchResponse()`: custom のアクションが前面に出す応答かはアプリの状態で見分ける。iOS 18.3 では背景のアクションの直後（約 0.2 秒以内）にアプリを開くと、それを起動のきっかけと取りうる | 記録 14 章の 1 |
| 今の受け手（deprecated）とイベントの口を両方使うと同じイベントを 2 度受ける | 設計書 RK-05 |
| 複数の window を開ける iPad では、Swift の利用者は Dialog・Share・権限の要求に表示元を渡す（`.viewController(_:)`）。前面の探し方は key window が 2 つのときどちらを選ぶか決まらない（C ABI の利用者に表示元を渡す口を設けるかは**決定待ち**。記録 21 章の 6） | 記録 5 章の 2、第 1 部 G-6 |
| Clipboard の同期の読み出しは、ほかのアプリの内容なら利用者が貼り付けを許すまで main を止める（後ろにいる間も）。止めたくなければ非同期の読み込みを使う | 記録 11 章の 5、10.7 |
| 権限の要求の選択肢（`.providesAppNotificationSettings` など）は最初の要求に入れる。`.foreground`・`.viewController` では、決まった後は求め直さない | 記録 18 章の 2 |
| `cancelAll`・`cancelAllScheduled`・`removeAllDelivered` はホストの通知まで消す | 設計書 3.4（SR-25） |
| Share は 2 つの要求の表示の順を約束しない。取り消せない。表示元の scene が切れても window が残ればシートは解放されず完了しない | 記録 7.4 の 10、7.11 |
| 外から閉じた Dialog・Share は約束の内（見張りで `dismissedBySystem`）。ホストが表示中に window や root を差し替える・表示した ViewController を持ち続けると完了が来ないことがある | 第 1 部 0.1、5.13.1 |
| userInfo は property list の値だけ（`NSNull`・`NSURL` は拒む）。キー `com.jonghyunkim.nativetoolkit` は予約 | 記録 18 章の 6、設計書 8.3.3 |
| 無いファイルの添付は通知ごと断られる（`add` が断り `addRequestFailed`。`update` では今の予約も消える）。`update` は、添付を作れない（`attachmentLoadFailed`）ときは今の予約を消さない。書き方は**決定待ち**（記録 21 章の 1 で入口で確かめると決まれば変わる） | 記録 20.4 の 3、19 章の L-B1 |
| **決定待ち**（記録 21 章の 5。推奨は DocC とマニュアルに書く）: Dialog の今の口の `sourceRect` は `nil` なら `sourceView` 全体（iPad の大きな view では選択肢の無い popover になる） | 記録 5 章の 5、21 章の 5 |
| ライブラリのログは統合ログ（`os.Logger`、subsystem `com.jonghyunkim.nativetoolkit.IosLibrary`）。利用者の値は `.private` で、秘密の値は長さだけ。ふつうのログは `.debug` で Release では保存されない | 設計書 8.7、記録 1.7 |

## 7. 第 2 部（2a）への申し送り

| 項目 | 内容 | 出どころ |
|---|---|---|
| 呼ぶ先と完了の形 | 設計書 8.9 のとおり。Dialog・Share・権限・設定の画面は `Result` の callback 版に `.foreground`、通知の操作は `async throws` 版を main actor の `Task` で、category は callback 版を main のブロックの中で（呼んだ順を保つ。UT-28 の `callsInsideAMainQueueBlockKeepTheirOrder`） | 設計書 8.9、記録 17.11 |
| Clipboard の取り消し | 受け付けの時点で `RequestBox()` を作り、main のブロックの中で `loadItem(_:scope:requestBox:completion:)`。取り消しの関数は main で受け取った Manager の参照を持つか、同じモジュールの中なので箱を直接閉じる（`shared` は main の actor でしか読めない）。取り消しに負けた `.file` はライブラリが消す | 記録 10.11、12 章の B-1 |
| Share | 2 つの要求の表示の順を約束しない（ヘッダーに書く）。外から閉じたシートは約 0.55 秒後に `CANCELED_BY_SYSTEM` | 記録 7.11 |
| エラー | `NotificationError` の 10 の case と C の値（設計書 10 章）。`attachmentLoadFailed` の識別子は C に渡さない（D-13）。`ShareError`・`DialogError` も 10 章 | 記録 17.11 |
| userInfo の `null` | C ABI で JSON の `null`（`NSNull`）を落とすか断るかを決める（`IosLibrary` は断る） | 記録 18 章の 6 |
| 権限の求め直し | `.foreground` で権限が決まっていると求め直さない。ヘッダーに「選択肢は最初の要求に入れる」 | 記録 18 章の 2 |
| 同期の読み出し | Clipboard の同期の読み出しの関数のヘッダーに、main が止まりうることを書く | 記録 11 章の 5 |
| iPad の表示元 | C から表示元を渡す口を設けるか（P1-11 の C の決め直しになるので利用者が決める。推奨は設けずにヘッダーに「どちらの window に出すかは決まらない」と書く）、複数の window の iPad での既定の選び方をヘッダーに書く | 記録 5 章の 2、21 章の 6 |
| `ntk_notification_install` の時期 | `UIApplicationMain` の前は契約の外。SwiftUI の `App.init` は「まだ active でない」とみなす | 第 1 部 1.3.3、G-9 |
| 例外 | 利用者のコールバックの中の `NSException` は、巻き戻しを始めずにその場で `abort` した（G-8、MS-11。測ったのは `NSException` の 1 回だけで、C++ の例外は試していない）。ヘッダーの「コールバックは例外を外へ出さない」の根拠 | 第 1 部 5.11、記録 20.4 の 1 |
| 0 で埋めた構造体の既定 | Dialog の `enableConfirmWhenEmpty` などの向き、通知の `repeats`・`notifyOnEntry`・`notifyOnExit`・`interruptionLevel`、sound（ブリッジの JSON の既定のテストは書き直していない。記録 20.8） | 設計書 8.9、18.1 の 5 |
| C ABI のテストで置き換えるもの | ブリッジの `UnityIosClipboardManagerCallbackContractTests` の 9 件と `UnityIosShareManagerTests` の 1 件（main で 1 回、不正な要求も 1 回） | 記録 20.8 |

## 8. 残り

| 項目 | 扱い |
|---|---|
| MS-10 のプライバシーのレポート | 利用者が Xcode の Organizer で作る（記録 20.9 の手順）。結果は記録 20.9 の表に書く |
| 実機の項目（`.private` の見え方、MS-08 の前面と実機、1b の UI テストの実機の回と実機の基準、0c の残りの 39 件と人の確認、配布用の署名） | どれも利用者の許可を得てから（記録 20.10、21 章の 3） |
| 利用者の決定 | 記録 21 章（無い添付の入口の確かめ、基準の取り直し、実機の回の時期、D23 の simulator only、`sourceRect` の DocC、C ABI から表示元を渡す口） |
| 更新のテスト（1.13.0 のサンプルから 2.0.0 へ） | 1b の後に別に設計する（設計書 13.4、UI テストの設計書 8.4） |
| ブリッジ | 変えていない。1b でブリッジは `openSettingsFor` で設定の App を開かなくなり、JSON の `null` を含む userInfo は `invalidUserInfo` で失敗する（段階 3 で消す） |
