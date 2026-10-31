# iOS ライブラリ Swift の API の補完 設計書（段階 1b）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/ios-c-abi/README.md`（以下「README」。1.2、1.3、1.4、4 章、4.1、5 章の 1b の行、8.1、8.2.1、8.6） |
| 対象段階 | 段階 1b（Swift の API の補完）の前 |
| 対象 OS | iOS 18.0 以降（D-15） |
| 作成日 | 2026-10-31（第 4 版） |
| 状態 | **決定（2026-10-31、利用者）。S-P1〜S-P28 はすべて推奨のとおり。レビュー v1〜v3**。同じ日に P1-23 を決め直した（2 回目の申し送りは設計の決定を待たずに出してよい。守るのは C5・C6 を U-3・U-4 の結果の後にすること。S-P24） |
| 改訂 | **v4（2026-10-31）: レビュー v3（`reviews/2026-10-31-ios-c-abi-swift-api-design-review-v3.md`。SR3-1〜SR3-7。A 1・C 6）を反映した**。A: このプロジェクトは `NONISOLATED_NONSENDING_BY_DEFAULT` を `NO` にしているので、nonisolated の `async` の関数は本体の前に汎用の executor へ移り、`async` 版の積みは呼んだ時点にならない（SR3-1）。両方の直しを入れた: (1) C ABI の受け口は category の callback 版を main のブロックの中で呼ぶ（同期に積む）。(2) category の 2 つの `async` 版を `nonisolated(nonsending)` で宣言し、最初の中断の前に積む。8.5.6 の「順」、8.9、9 章の UseCase の列、UT-28、付録 A を直した。C: SR3-2〜SR3-7 をすべて直した<br>**v3（2026-10-31）: レビュー v2（`reviews/2026-10-31-ios-c-abi-swift-api-design-review-v2.md`。SR2-1〜SR2-11。A 1・B 5・C 5）を反映した**。A: category の列をどの層に置き、Manager が呼んだ順に同期で積めるかを新しい S-P28 にした。推奨は、port と UseCase に同期で積む口を足し、port には今の `async` の口へ委ねる既定の実装を付ける形（今の実装者のソースは組める）。`async` 版は `withCheckedContinuation` で同期の積みを包む（SR2-1）。B: 取り出しの始めと終わりを 1 つの `Mutex` の中で決める（SR2-2）、サンプルの試験の形をファイルに残してコールドスタートでも読み、通った経路を結果に出す（SR2-3）、今の辞書を Foundation の型で作り直し `init` の扱いを決める（SR2-4）、logger の宣言を組める形に直す（SR2-5）、`Log` の中身を `print` のままにする（SR2-6。S-P21）。C は SR2-7〜SR2-11 をすべて直した<br>**v2（2026-10-31）: レビュー v1（`reviews/2026-10-31-ios-c-abi-swift-api-design-review-v1.md`。SR-1〜SR-25。A 2・B 9・C 14）を反映した**。A: category の更新を Manager の同期の受け付けで FIFO に積み、1 つの処理が読み取りから確認までを終えてから次へ進む形にした（SR-1。S-P14、8.5.6）。一覧の型を `Sendable` にし、`async` の結果が隔離の境界を越えられるようにした（SR-2。新しい S-P25）。B: 箱の閉じたときの処理の隔離（SR-3）、`async` 版の追加で今の呼び出しが組めなくなること（SR-4。新しい S-P26）、`PresenterSelection` を struct に（SR-5）、ログの案 D と `Log` の deprecated（SR-6。S-P21 を書き直し、P1-18 は変えない）、Share の文言とログ（SR-7）、port の破壊的変更と `NotificationPermissionHelper`（SR-8。新しい S-P27）、`update` の検査の位置（SR-9）、識別子の照合と今の受け手の経路（SR-10。S-P23）、`.providesAppNotificationSettings`（SR-11）。C は SR-13 の typealias のほかすべて直した（理由はレビューの「対応」の列）。v1 の「8.9 の申し送り」の節が無かったので 8.9 を足した。あわせて、1 回目の申し送りの雛形でシミュレーターで測った結果（`results/2026-10-31-ios-c-abi-unity-handoff-1.md` の 6 章。起動の直後と同じ回の 2 つのアラート、外から閉じたアラートの解放と TSan の版、外から閉じた Share に完了が来ないこと、iPad の基点）を 6.3、8.2、13.2、14 章と RK-11 に入れた |
| ブランチ | `feature/NTKIT-18`（HEAD `fbb03f70`） |
| 前段階 | 段階 0a〜0g は完了（実機の 39 件と人の確認の手順書は残る）。段階 1a のシミュレーターの下調べは完了（README 8.2.1）。C ABI の設計書の第 1 部は決定（2026-10-31） |
| 元にした文書 | C ABI の設計書の第 1 部（`designs/2026-10-31-ios-c-abi-c-abi-design.md`。以下「第 1 部」）の 9.1（S-1〜S-16）・5.12・5.13・8 章、1a の作業の記録 2 つ（`results/2026-10-31-ios-c-abi-stage1a-entry-working-notes.md`。以下「1a 入口」、`results/2026-10-31-ios-c-abi-stage1a-delegate-working-notes.md`。以下「1a delegate」）、UI テストの設計書（`designs/2026-10-18-ios-c-abi-ui-test-design.md`。以下「UI テストの設計書」）、ブリッジのテストの記録（`results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md`）、0f の公開 API（`results/swiftinterface/IosLibrary-after-0f.swiftinterface`）、Android の Kotlin の API の設計書（`artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`。以下「Android の 1b」）とそのレビュー（`android-c-abi/reviews/2026-10-04-android-c-abi-kotlin-api-design-review-v1.md`〜`-v6.md`、`2026-10-05-android-c-abi-stage1b-implementation-feature-review-v1.md`）、今のコード（`ios/IosLibrary/`、`ios/UnityIosPlugin/`、`ios/IosLibraryExample/`）、`agent-rules/coding-rules/{common,ios}.md` |
| 後に続く文書 | C ABI の設計書の第 2 部（2b の前。この設計書の口を C の関数に写す。8.9 の申し送り）、サンプルの設計（12 章の範囲を `design-sample-app` で細かくするなら） |
| レビュー | v1（`reviews/2026-10-31-ios-c-abi-swift-api-design-review-v1.md`。要修正。v2 で反映）、v2（`-v2.md`。要修正。v3 で反映）、v3（`-v3.md`。要修正。v4 で反映。これ以上のレビューの回は予定しない）。README 5.1 のとおり、別のモデルのレビューを通してから着手する |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない型と関数（`PresenterSelection`、`RequestBox`、`DialogRequest`、`NotificationEventHub`、`installDelegate()` など）を定める。名前が実装に存在するかの照合は 1b の実装の後に行う（17 章）

## 0. この文書の読み方

| 印 | 意味 |
|---|---|
| D-n | README 8.1 の決定。この文書では変えない |
| 1a-n | README 8.2.1 の段階 1a の決定。この文書では変えない |
| P1-n | 第 1 部の決定（2026-10-31、利用者）。この文書では変えない |
| S-n | 第 1 部 9.1 の、Swift の API が満たす条件。11 章で 1 つずつ照らす |
| G-n | 第 1 部 4.4 の不足前提。1b で測るもの（14 章） |
| **S-Pn** | **この文書の提案**。3.2 の表に、案・推奨・理由を置く。2026-10-31 に利用者がすべて推奨のとおり決めた（推奨の欄に「決定」） |
| UT-n / UI テストの ID | 13 章のテスト。UI テストは UI テストの設計書の番号を続ける（D16〜、N34〜、S17〜、CB5〜） |
| SA-n | 12 章のサンプルに足すもの |
| MS-n | 14 章の、1b でシミュレーターで測ること |

本文の「〜する」は、決定（D-n、1a-n、P1-n）に基づくものと、提案（S-Pn）に基づくものがある。提案に基づく文には S-Pn を付ける。

約束の範囲は第 1 部 0.1 と同じにする（ホストと利用者が契約を守る場合だけを約束する）。Swift の API でも、表示中に window・root・scene を差し替える、表示した ViewController を持ち続ける、前の delegate へ非同期に転送する delegate の上で入れ直す、は約束の外である。

## 1. 設計目的

- 今はブリッジ（`ios/UnityIosPlugin`）にしか無いロジック（README 1.2）を `IosLibrary` へ移し、**Swift の利用者が Swift だけで全機能を使えるようにする**（README 4 章）
- 足す口の形を、C ABI の要求（第 1 部 9.1 の S-1〜S-16）に合わせる。C ABI の受け口は `IosLibrary` の公開 API だけを呼ぶ（P1-2）ので、C ABI が要る口はすべて公開の口として足す（S-9）
- README 1.4 の不備を直す。Dialog を Domain・Application・Presentation に分ける。エラーを安定した case にする。通知の delegate を転送する形にし、イベントの口を足す。ログで秘密を伏せる。プライバシーマニフェストを入れる
- **README 5 章の 1b の行に挙げたもののほかは、Swift の利用者から見た今の動作を変えない**。新しい意味は新しい口（引数を足した形を含む）に置き、今の口は今の動作を保つ。変えるものは 3.3 にすべて挙げる（README 4.1 と移行の手引きの元）

## 2. スコープ

### 2.1 in

| 機能 | 足す・直すもの |
|---|---|
| 共通 | 表示元の選び方（`PresenterSelection`）、要求の箱（`RequestBox`）、表示の手順（前面の新しい定義、落ち着きの確かめ、1 回だけの待ち）、解放の見張り、エラーの詳細（`FailureDetail`）、`Log` の `os.Logger` 化と秘密を伏せる補助、プライバシーマニフェスト |
| Dialog | 3 層に分ける。1 つの要求の型（`DialogRequest`）と 1 つの結果（`Result<DialogAnswer, DialogError>`）の口、要求ごとの取り消し、新しい定義の前面を返す口。今の 7 つの口を新しい芯の上に載せ直し、循環参照・observer・失敗の返し方を直す |
| Share | `presenter` を取る口、安定したエラー、要求の箱と解放の見張り、continuation を漏らさないこと |
| Notification | delegate を入れる口（`installDelegate()`）と入れたかを読む口、転送の proxy（5.12 のすべて）、印の付け外しと予約したキー、イベントの口（複数の受け手、受け手が 0 の間は保つ）、起動のきっかけ、`openSettingsFor` のイベント、安定したエラーと `async throws` の口、権限の要求と設定の画面の `presenter`、category の直列化と完了、userInfo の検査 |
| Clipboard | 読み込み（`loadItem`）の要求の箱と、どのスレッドからでも呼べる取り消し。DocC の直し |
| 規則 | `agent-rules/coding-rules/ios.md` のログの規則の例外（8.7）。**この設計書の決定と同じ PR で直す**（README 8.6 は「直してから 1b に入る」） |
| サンプル | 新しい口を使う画面とボタン、起動の処理の書き換え、結果の行で秘密を出さないこと（12 章） |

### 2.2 out

- C ABI の関数・型・エラーの番号（第 2 部）。この設計書が決めるのは、Swift のエラーの case と、それを C の値に写す規則まで（10 章）
- ブリッジ（`ios/UnityIosPlugin`）の変更（README 4 章、D-22。段階 3 で消す）。ブリッジのログ（パスワードを出す）は直さない。ブリッジは 2.0.0 に出ない
- JSON の解析と組み立て（README 1.2 の「共通」。C ABI では型にするので移さずに捨てる）
- `IosLibrary` にあってブリッジに無い機能の C ABI（D-5 の B）
- 1.x（1.13.0 のサンプル）からの更新のテストの設計（UI テストの設計書 8.4。1b の後に別に設計する。ここでは 8.5.6 の扱いだけを決める）
- macOS（D-1）

## 3. 前提と決定

### 3.1 企画書と第 1 部から来る前提

| 前提 | 出典 |
|---|---|
| 1.2 のロジックを `IosLibrary` へ移す。ブリッジには手を入れない | README 4 章、D-22 |
| 1b で変わる動作は、1.4 の不備の直し、通知の delegate の転送、エラーの case、表示の完了が来なかった経路を閉じる、同じ回の 2 つ目の Dialog が待って出る（新しい定義の前面を選んだとき）、通知の印と予約したキー、`openSettingsFor` のイベント、`presenter` と取り消しの口の追加。それ以外は変えない | README 5 章の 1b の行、4.1 |
| C ABI の受け口は `IosLibrary` の公開 API だけを呼ぶ。`@_spi` も `@testable` も使わない | P1-2、S-9 |
| C ABI の受け口は main キューに積んだブロックの中で `MainActor.assumeIsolated` を使って `IosLibrary` を呼ぶ | P1-4 |
| 入れる関数は main スレッドだけ、同期、待たない、冪等、差し替えの後は入れ直す、起動の後もログを出して成功 | D-4、D-6、1a-9〜1a-11、第 1 部 1.4 |
| 転送の規則、印、1 回だけ通す包み、循環の防止、起動のきっかけの見分け方、受け手が 0 の間の保ち方 | D-7、1a-6〜1a-12、P1-9、P1-10、P1-21、P1-22、第 1 部 5.12 |
| `NOT_INITIALIZED` は、proxy がこのプロセスで一度も入っていないときの、通知のイベントの受け手の登録と起動のきっかけの取得だけ | P1-6 |
| 前面の新しい定義、`presenter` の 3 つの値、表示の手順、要求の箱、解放の見張り、取り消し | P1-11〜P1-15、P1-24、第 1 部 5.13 |
| `@unchecked Sendable` と `nonisolated(unsafe)` を使ってよいもの（`CompletionOnce`、要求の箱と解放の見張り、関連オブジェクトの鍵） | P1-17、S-16 |
| 新しいコードは Swift 6 / complete。`IosLibrary` の manager は `Sendable` で、`shared` に `@MainActor` を付けない（`IosClipboardManager` は前から `@MainActor`） | D-14、README 4.1 の 0f の行 |
| 秘密の値は、パスワード、入力欄、通知の返信、クリップボードの本文、通知と Share の内容 | README 1.4、8.6 |
| プライバシーマニフェストは `IosLibrary` に入れる。FileTimestamp の理由は C617.1 の見込み | D-18 |

### 3.2 この設計書の提案（S-Pn。2026-10-31 に利用者がすべて推奨のとおり決定）

| ID | 決めること | 案 | 推奨 | 理由 |
|---|---|---|---|---|
| S-P1 | 表示元の選び方の型（S-6。**v2 で形を直した**。SR-5） | A: **`public struct PresenterSelection: Sendable` を `Common/Domain/` に置き、中に internal な enum を持つ。値は static な `.firstActiveScene`（既定。今の探し方）と `.foreground`（新しい定義の前面）、static な関数 `.viewController(_:)`（`@MainActor @Sendable () -> UIViewController?` を受ける。UIKit を使う `Common/Presentation/` の extension に置く）。呼ぶ側の書き方は enum と同じ** / B: `case viewController(UIViewController)` を持つ enum（`Sendable` にならない）/ C: 表示の口ごとに `presenter: UIViewController?` を足す | **A**（決定） | どの表示の口もどのスレッドからでも呼べる（README 4.1 の 0e）ので、引数は `Sendable` が要る。ViewController を返す closure なら `Sendable` で、main で 1 回だけ呼んで最新の ViewController を得られる。Domain のファイルは UIKit を import せず、closure は `AnyObject` で持つ（common.md の Domain の規則）。v1 の「public の enum に internal の case」は組めない（SR-5。型検査で確かめた）ので struct にした。struct なら後から値を足しても利用者の `switch` を壊さない。B は any スレッドの口に渡せない。C は 3 つの値のうち 2 つ（既定と新しい前面）を表せない |
| S-P2 | 要求の箱の公開の形（S-15） | A: **`public final class RequestBox: Sendable`。公開するのは `init()` と `isClosed` だけ。取り消しは機能の Manager の口（`IosDialogManager.cancel(_:)`、`IosClipboardManager.cancelLoad(_:)`）から行う。1 つの箱は 1 つの要求にしか使えない（2 回目は `invalidRequest` で完了）** / B: 箱に `cancel()` を公開する / C: Clipboard の今の `ClipboardLoadToken` を広げて使う | **A**（決定） | C ABI の受け口は受け付けの時点で箱を作る必要がある（第 1 部 5.7 の手順 4、R4-1）ので、公開の型で、表示の口を呼ぶ前から作れる形が要る。取り消しを Manager の口にすれば、common.md の「機能の公開の入口は Manager」に合う。B は取り消しの入口が 2 つになる。C の `ClipboardLoadToken` は `@MainActor` で、開始の後にしか得られない |
| S-P3 | 新しい定義の前面を返す公開の口（S-6） | A: **`IosDialogManager.foregroundViewController()`（`@MainActor`）。今の `getRootViewController()` の隣に置き、DocC で違いを書く。実装は `Common/Presentation/` の 1 か所で、Share・Notification も使う** / B: 新しい型（`IosForeground` など）に置く | **A**（決定） | 比べる相手（`getRootViewController()`）と同じ所にあると、DocC で違いを読み比べられる。新しい公開の型を増やさない |
| S-P4 | Dialog の新しい口の形（S-5、S-6） | A: **`DialogRequest`（6 種の enum）を 1 つ取る `show(_:presenter:requestBox:completion:)`（結果は `Result<DialogAnswer, DialogError>`。main で 1 回）と `show(_:presenter:) async throws -> DialogAnswer`。取り消しは `cancel(_ box:)`** / B: 種類ごとに `showAlert(request:)` などを足す / C: 今の 7 つの口に引数を足す | **A**（決定） | README 1.2 の「3 つのコールバックを 1 つの結果にまとめる」をライブラリが持つ。C ABI の 6 種の関数は 1 つの口に写せる（第 2 部）。Android の `AndroidDialogManager.show(request, onResult)` と同じ形。C は結果の型を変えられない |
| S-P5 | 今の Dialog の 7 つの口（`showDialog`、`showAlert` など） | A: 今のまま残す / B: 今の実装のまま、1.4 の不備だけを直す / C: **形は今のまま、中を新しい芯（8.1 の Presentation）の上に載せ直す。1.4 の不備を直し、失敗はすべて `completion(false, …)` で返す（`showLoginDialog` の失敗も `onLogin` でなく `completion`）。UIKit が表示を断ったときも `completion(false, …)` を 1 回呼ぶ** | **C**（決定） | 表示の処理を 1 か所にし、循環参照と observer の直しを両方の口に効かせる（common.md の「ロジックを重複させない」）。失敗の返し方をそろえるのは README 4 章の表の項目。今の DocC も「Dialog の結果の型を直すまで残す既知の穴」と書いている。A は 1.4 の不備が残る。B は同じ表示の処理が 2 つになる。変わる動作は 3.3 に書く |
| S-P6 | アクションシートの基点（新しい口） | A: **新しい口は基点を受けない。いつも表示元の view の中央（P1-13 と同じ）。今の `showActionSheet(sourceView:)` は今のまま残す** / B: 新しい口に省略できる基点（view を返す closure と矩形）を足す | **A**（決定） | C ABI も 2.0.0 では矩形を受けない（P1-13）。基点が要る Swift の利用者は今の口を使える。後から引数を足しても互換は壊れない |
| S-P7 | エラーの安定した case（S-7） | A: **任意の `Error` を持つ case を、正規化した値 `FailureDetail`（`domain` と `code`。`Common/Domain/`）を持つ case に直す。使われていない case（`NotificationError.unknown`・`permissionNotDetermined`・`attachmentInvalidURL`、`ShareError.unknown`）を消す（v2 で `attachmentInvalidURL` を足した。SR-13）。`NotificationError` を `LocalizedError` にし、文言を英語の固定にする。`ShareError` の今の文言は変えない** / B: 詳細を持たない（ログだけ）/ C: Clipboard の `ClipboardFailureDetail` をほかの機能でも使う | **A**（決定） | common.md は「system の `Error` を正規化せず Domain に保持しない」とし、Clipboard は既に正規化した詳細を持つ。Swift の利用者は詳細で原因を見分けられ、C ABI は詳細を出さない（`system_code` は 0。D-13）。C は名前が機能に合わない。`ClipboardFailureDetail` を `FailureDetail` の typealias にする案も比べたが、`ClipboardFailureDetail` は internal の `debugMessage` と、それを取る public の `init(domain:code:debugMessage:)` を持ち、形が違うので採らない（SR-13）。`ShareError` の文言は S13〜S16 の UI テストが全文で比べる（URL とパスを含むので、文言はログに出さない。SR-7） |
| S-P8 | 通知の今の受け手（`onActionReceived`、`onTextInputActionReceived`）と `setup()` | A: **残して `@available(*, deprecated)` にする。`setup()` は `installDelegate()` を呼ぶだけにする。今の受け手は、イベントの口の受け手とは別に、配るときに main で呼ぶ（保ちと受け手の数には関わらない。`NOT_INITIALIZED` も返さない）** / B: 2.0.0 で消す / C: イベントの口の受け手の 1 つとして中で登録する | **A**（決定） | 今の利用者のソースは組めたまま動く。C は、受け手を設定しただけで「受け手がいる」ことになり、保ちが効かなくなる。B は移行の手間だけが増える。今の受け手とイベントの口の両方を使うと同じイベントを 2 度受けるので、DocC に書く。今の受け手だけを使う利用者では、イベントの口が 32 件を保ち続ける（上限があるのでメモリは増えない）。捨てたときのログは、プロセスで最初の 1 回だけ `.info`、以後は `.debug` にする（SR-23） |
| S-P9 | `IosNotificationManager` の公開の `UNUserNotificationCenterDelegate` への準拠 | A: **外す。delegate は内部の proxy だけが持つ** / B: 残し、各メソッドを proxy に委ねる | **A**（決定） | common.md の「system の Delegate は 1 クラスだけが持つ」。残すと、利用者が manager を自分で delegate に入れる経路ができ、転送・印・保ちのどれも効かない。ホストから応答を渡してもらう関数は 2.0.0 では足さない（1a-13） |
| S-P10 | イベントの口の形と保つ規則（S-4、README 8.6） | A: **イベントの種類ごとの `@MainActor` の `NotificationEventHub<Event>`。受け手の足し外しは main だけ。受け手には登録を引数で渡す。受け手が 0 の間は保つ: 32 件（超えたら古いものから捨ててログ）、期限なし（プロセスの寿命）、受けた順、重複を除かない。保ったものは次に足された 1 人目に、足す呼び出しの中で受けた順に渡す** / B: `AsyncStream` で配る / C: `NotificationCenter` で配る | **A**（決定） | Android の `EventHub`（Android の 1b 8.4、KA-5）と同じ規則で、C ABI の受け口が「その種類の最初の登録の挿入のブロックの中で保ったものを受け取る」（第 1 部 5.12.7、S-4）をそのまま満たす。B は main で同期に渡せず、受け手が 0 の判定ができない。C は型が無く保てない |
| S-P11 | イベントの userInfo の形 | A: **`Sendable` の値の木 `NotificationUserInfoValue`（文字列・符号つき整数・符号なし整数・実数・真偽値・日時・バイト列・配列・辞書）。印は外す。property list に無い値は来ない（OS が保存しない）。`NSNumber` の振り分けは、(1) 真偽値（`CFGetTypeID` が `CFBooleanGetTypeID()`）なら `bool`、(2) 実数（`CFNumberIsFloatType`）なら `double`、(3) `Int64` に入れば `integer`、(4) 入らない正の値は `unsignedInteger`（`UInt64`）、の順に見る（実数を整数より先に見る。SR-24、SR2-11）** / B: `[AnyHashable: Any]` を写して `@unchecked Sendable` で運ぶ / C: property list の `Data` で運ぶ | **A**（決定） | イベントは nonisolated の proxy から main へ渡るので `Sendable` が要る。B は P1-17 の一覧に無い `@unchecked` を足すことになる。値の木なら C ABI の第 2 部が JSON にもキーと値の組にもできる。README 1.4 の「userInfo を JSON にする前に確かめていない」も、型で起きなくなる |
| S-P12 | 起動のきっかけの通知の取り方（S-4、P1-22） | A: **イベントに `isLaunchResponse` の印を付け、別に `launchResponse()`（`@MainActor`。入れていなければ `delegateNotInstalled` を投げる）で取れる。値は、プロセスで最初の `didBecomeActive` の後に決まる** / B: 取得の口だけ / C: 印だけ | **A**（決定） | 起動のきっかけは、取得の口と保ったイベントの両方で届く（第 1 部 5.12.7）。印があれば、利用者は二重に処理しない書き方ができる。C ABI の第 2 部はどちらの形にも写せる **P1-22 を絞った（2026-10-31）**: `isLaunchResponse` と `launchResponse()` は、アプリを前面に出す応答だけ。背景のアクションの起動は含めない（`results/2026-10-31-ios-c-abi-unity-handoff-2-results.md` の H2-1） |
| S-P13 | 通知の操作のネイティブ版 | A: **完了で返す今の操作（`show`・`update`・`schedule`・`setBadgeCount`・`requestPermission` など）に `async throws`（`NotificationError`）の版を足す。今の callback 版は形を変えず、`errorMessage` を英語の固定の文言にする。`async` 版の名前は S-P26** / B: `Result` の callback 版を足す | **A**（決定） | `ios.md` は「Manager は callback 版と `async throws` 版」を求めるが、`IosNotificationManager` には `async` 版が無い。C ABI の受け口は型のあるエラーが要り（第 1 部 5.10 の「1 つの case に 1 つの値」）、main actor の `Task` の中で `async` 版を待てる（第 1 部 5.6）。B は口が 3 つになる |
| S-P14 | category の登録と削除（README 1.4。**v2 で直列の形を直し、v3 で列の始めと終わりの手順を決めた**。SR-1、SR-18、SR2-2） | A: **プロセスで 1 つの `NotificationCategoryQueue`（Data）に、要求を呼んだ時点で同期に FIFO の末尾に積む。取り出すのは 1 つの処理だけで、1 つの要求の読み取り・変更・書き戻し・確認を終えてから次を取り出す。取り出しの始めと終わりは、積むのと同じ `Mutex` の中で決める（8.5.6）。完了は main に 1 回だけ積む。`registerCategory(_:completion:)`・`removeCategory(identifier:completion:)`（`completion` は既定 `nil`）と `async` 版を足す。列をどの層に置き、Manager からどう同期に届かせるかは S-P28** / B: actor で直列にする（v1 の案）/ C: 直列にするだけで完了は足さない | **A**（決定） | ブリッジは登録の前に成功を返していた（README 1.4）。C ABI は完了を返すので、Swift にも完了の口が要る。actor は `await notificationCategories()` の間に別の要求を入れる（再入）ので、2 つの要求が同じ古い集合を読み、後の書き戻しが前の変更を消す（SR-1）。今の Manager の要求ごとの `Task` も、呼んだ順を保たない。呼んだ時点で同期に積めば、同じスレッドから呼んだ順と、`Mutex` を取った順が反映の順になる。`NotificationRepositoryImpl` は public の `init` で何個でも作れるので、列はプロセスで 1 つにする（SR-18）。確認で読み直すかは MS-09 で測って決める |
| S-P15 | userInfo の検査 | A: **表示・予約・更新の前に、userInfo が property list にできるかを確かめ、できなければ `invalidUserInfo` で失敗する（予約したキーの拒否と同じ所）** / B: 確かめない | **A**（決定） | property list でない値を入れると、`add` の中で例外か黙った欠落になりうる（Apple の文書は property list の型を求める）。拒否を先にそろえれば、C ABI でも入口の戻り値で返せる |
| S-P16 | `cancel` と `cancelScheduled` が同じ、`content.id` が `schedule`・`update` で使われない（README 1.4） | A: **動作は変えない。DocC に「同じ処理」「`identifier` が使われ `content.id` は使わない」を書き、違うときはログに出す** / B: `cancel` を表示済みも消す意味に変える / C: `identifier` の引数を消す | **A**（決定） | 今の UI テスト（N12、N20）は今の動作を期待値にしている（UI テストの設計書 8.5）。意味を変えると、1b の「それ以外は変えない」に反する。C ABI では 2 つの関数を同じ口に写す（第 2 部） |
| S-P17 | 1.x の通知（印が無い）の扱い（S-12、README 8.6） | A: **何もしない。予約・表示中の 1.x の通知は、取り消し・一覧で今と同じに扱う。タップは 5.12.3 のとおり（ホストの delegate が `didReceive` を持てばホスト、無ければライブラリ）。移行の手引きに書き、更新のテストで確かめる** / B: 初めて入れたときに、予約済みの印の無い要求に印を付けて入れ直す | **A**（決定） | 1.x の通知とホストの通知は見分けられない（1a delegate 3.5）ので、B はホストの予約まで書き換える。category は OS に残り、bundle id の変更（D-12）はライブラリのコードが使わない（grep で 0 件） |
| S-P18 | Share の口（S-6） | A: **`share(content:presenter:completion:)`（`presenter` は既定を持たない。結果は `Result<ShareResult, ShareError>`）を足し、`share(content:presenter:) async throws` の `presenter` に既定 `.firstActiveScene` を足す。今の callback 版（4 つの値）は形を変えない** / B: 今の callback 版に `presenter` を足す | **A**（決定） | C ABI は型のあるエラーが要る。`presenter` に既定を持たせないと、今の `share(content:completion:)` との呼び分けが引数ラベルで決まる。B は結果の型を変えられない |
| S-P19 | 権限の要求と設定の画面の口（S-6、S-13） | A: **`requestPermission(options:presenter:completion:)`（`Result<Bool, NotificationError>`。`false` は拒否で、失敗ではない）と `openNotificationSettings(presenter:completion:)`（`Result<Void, NotificationError>`）を足し、どちらも `async throws` 版を持つ。`presenter` が `.firstActiveScene` なら前面を確かめない（今と同じ）。前面の判定は Presentation の部品（8.5.4）が行い、UseCase はデータの操作だけ（SR-17）** / B: 今の口に `presenter` を足す | **A**（決定） | 今の `requestPermission` の完了は拒否を「失敗」として文字列で返す（`permissionDenied`）。新しい口は C ABI の結果（許可の真偽と、前面でない・失敗の別）に合う。今の口は今のまま残す |
| S-P20 | 転送の delegate のテストのしかた（第 1 部 6 章、1a delegate 8 章） | A: **判定（見分け方・転送の規則・循環・起動のきっかけ）を、通知を表す小さな値（identifier、date、userInfo、push か、action）と、前の delegate を呼ぶ closure の上の純粋な型 `NotificationDelegateRouter` に分け、単体テストで全組み合わせを確かめる。`UNUserNotificationCenterDelegate` を実装する proxy は値を作って router を呼ぶだけにし、シミュレーターの UI テストで確かめる** / B: proxy をそのままテストする | **A**（決定） | `UNUserNotificationCenter` と `UNNotification` はテストから作れない。router に分ければ、1a delegate 3 章の表（メソッド 3 つ × 前の delegate の振る舞い 9 つ × 通知の種類 4 つ）を単体テストにできる |
| S-P21 | `IosLibrary` のログの形と `Log` の扱い（S-11、README 8.6。**v2 で書き直し、v3 で宣言の形と `Log` の中身を直した**。SR-6、SR2-5、SR2-6） | ログの出し方: A: `Log`（文字列を受ける）を `os.Logger` に替え、メッセージを `.public` で出し、秘密の値を入れない（v1 の案）/ B: `print` のまま中だけ直す / C: `print` のまま `#if DEBUG` で囲む / **D: `os.Logger` を呼ぶ所で直に呼び、補間ごとに `privacy:` を付ける。logger はファイルの `private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "<型名>")` で持つ（generic の型と `@MainActor` の型でも組め、`nonisolated` の関数や `deinit` からも使える。generic でない型の中に置くなら `nonisolated private static let`。generic の型（`NotificationEventHub<Event>` など）はファイルの `private let` だけ（SR3-2））。カテゴリは型名の文字列（今のインスタンスの `TAG` は static でないので使えない）。関数名・識別子・件数・列挙・真偽値・エラーの case は `.public`、そのほかの利用者の値は `.private`、秘密の値は出さない（長さだけ）。P1-18 の capi の規則と同じ** / `Log` の扱い: X: `internal` にする（2.0.0 の破壊的変更）/ **Y1: `public` のまま `@available(*, deprecated)` にし、中身は今の `print` のまま変えない（見え方も今と同じ）。ライブラリの中では使わない** / Y2: deprecated にし、中を `os.Logger` へ `.private` で送る（`d`→`.debug`、`i`→`.info`、`w`→`.default`、`e`→`.error`）/ Y3: deprecated にし、中を `os.Logger` へ `.public` で送る（v2 の Y） | **D と Y1**（決定） | 第 1 部 P1-18（capi は `os.Logger` を直に呼び、利用者の値を `.private`）は決定で、capi は `Log` を使わないので変えずに済む（v1 の「文字列を受けるので付けられない」は capi には当たらない。SR-6）。D なら `IosLibrary` も同じ規則にでき、S-11 の「capi の規則と合わせる」を満たす。呼ぶ所は 33 ファイルの 164 か所（`grep` で数えた）で、T-02 で書き換える。v2 の `private static let logger`（`category: TAG`）は、`TAG` がインスタンスの値で、generic の型と `@MainActor` の型で組めない（SR2-5。型検査で確かめた）ので、ファイルの `private let` にした。A は 1 か所で済むが、識別子と利用者の値の privacy を分けられない。B は Release でも Console で選べない。C は配る Release のバイナリで全員のログが消える。Y1 は `IosLibrary.Log` を使う利用者（サンプルも）のソースと見え方を今のまま保つ。Y3 は利用者が `Log` に渡した値が統合ログに入り、Console や sysdiagnose から読めるようになる（今の `print` より見えやすい。SR2-6）。Y2 は利用者の値が見えなくなり、`Log` を使う意味が無くなる。X は移行の手間だけが増える |
| S-P22 | Clipboard の要求ごとの取り消し（S-15、P1-24） | A: **`loadItem(_:scope:requestBox:completion:)` を足し、`nonisolated cancelLoad(_ box:)` で取り消す。取り消すと箱を閉じ、読み込みの取り消しを main に積み、完了は `ClipboardError.cancelled` で 1 回。開始の前に閉じた箱なら、読み込まずに `cancelled` で完了する。token の操作と完了は main で行う（箱の閉じたときの処理は main に積むだけ。6.3.2。SR-3）。変更の監視（1 人の受け手）は変えない** / B: 今の `ClipboardLoadToken` の `cancel()` を nonisolated にする | **A**（決定） | 今の token は開始の後にしか得られず、`@MainActor` の中でしか取り消せない。C ABI は受け付けの時点で箱を作り、どのスレッドからでも取り消す（第 1 部 5.7）。監視の受け手を複数にするかは第 2 部の形（`add` / `remove`）で決め、受け口が分配できる |
| S-P23 | サンプルの書き換えの範囲（12 章。**v2 で今の受け手の経路を足した**。SR-10） | A: **今のボタンと結果の行はそのまま残し（0c の UI テストの基準）、新しい口を使うボタンを機能ごとに足す。起動の処理は既定で `installDelegate()` とイベントの口に書き換え、試験の形（今の受け手の経路、受け手を遅らせる）で今の受け手（`onActionReceived`・`onTextInputActionReceived`）と `setup()` の経路に切り替えられるようにする。試験の形は起動の引数で渡し、サンプルがアプリのコンテナのファイルに残して、引数の無い起動（バナーのタップでシステムが起こすコールドスタート）でも読む。UI テストは起動のたびに形を引数で明示する（無しの形も明示して消す）。どの経路でイベントを受けたかを結果に出し、テストで確かめる（12 章の SA-18。SR2-3）。N25〜N33 は既定の経路で流し、今の受け手の経路は N25・N30・N29 を同じ手順で流す（N43〜N45）。足す識別子は UI テストの設計書 5.1 の一覧と I1a〜I1d の照合に足す。ログインの結果の行はパスワードを出さず長さだけにする。サンプルのログは自分の `os.Logger` にする** / B: すべてを新しい口に書き換える / C: A で今の受け手の経路を N25〜N33 の全件で流す | **A**（決定） | 0c の UI テスト（99 件）で「1b の前後で今の口の動作が変わらない」ことを確かめる（README 7.1）。起動の処理を替えると N25〜N33 が今の受け手を通らなくなるので、引数で今の経路を残す（SR-10）。今の経路を全件で流すと、遅い通知のテストが 9 件増える。タップ・テキスト入力・コールドスタートの 3 件で、今の受け手の配り方（main、印を外す）を守れる。サンプルの今の口の結果の行を callback 版のまま残すのは `ios.md` の「サンプルは `async throws` 版を使う」の例外として書く（SR-22） |
| S-P24 | 1b の作業の順とコミット（15 章） | A: **共通 → Dialog → Share → Clipboard → 通知の delegate とイベント → 通知の操作、の 6 つの機能ごとのコミット（各コミットにライブラリ・単体テスト・サンプル・UI テスト）と、最後の測りの記録と全体の実行のコミット** / B: 層ごと（Domain をまとめて、など） | **A**（決定） | 利用者は Android と同じく機能ごとのコミットを望んでいる。通知を後にするのは、2 回目の申し送り（U-3・U-4）の結果が 1a-13 と通知の口を変えうるため（P1-23）。C6 は C5 の印（8.3.3）とサンプルの起動の処理に依存するので、C5 の後にコミットする（v1 の「C6 を先にしてよい」は誤り。SR-14） |
| S-P25 | 予約済み・表示済みの一覧の型（`ScheduledNotification`・`ActiveNotification`）を、隔離の境界を越えられる形にする（**v2 で足した**。SR-2） | A: **userInfo を値の木（S-P11）で持ち、型を `Sendable` にする。`userInfo: [AnyHashable: Any]` は値の木から作る計算プロパティにして読み方を今のまま保ち、値の木を `userInfoValues` で公開する。作り直す辞書は Foundation の型で作る: 真偽値は `kCFBooleanTrue`・`kCFBooleanFalse`、数は `NSNumber`、文字列は `NSString`、日時は `NSDate`、バイト列は `NSData`、配列は `NSArray`、辞書は `NSDictionary`（今と同じく `as? Int`・`as? Double`・`as? Bool` で読める。Swift の `Int64` などで作ると `nil` になる。SR2-4）。deprecated の今の受け手に渡す辞書も同じに作る。public の `init` は今の引数（`[AnyHashable: Any]`）のまま、中で値の木に変え、property list の型でない値と `String` でないキーは捨てて、捨てた件数（キーと値は出さない）をログに出す（落ちない。SR2-4）** / B: 型は今のまま、`sending` の戻り値を port・UseCase・Manager の全部に付ける / C: 一覧には `async` 版を足さず、C ABI の受け口は callback 版を使う | **A**（決定） | C ABI の受け口は main actor の `Task` から `async` 版を待つ（第 1 部 5.6）。今の 2 つの型は `[AnyHashable: Any]` を持ち `Sendable` でないので、nonisolated の `async` の結果を main actor へ返せない（SR-2）。A なら読み方の互換を保ち、C ABI も値の木を使える（JSON の前の検査が型で要らなくなる）。B は利用者が port を実装していれば全部に `sending` が要り、値を作る所が 1 か所でも結び付くと組めない。C は `ios.md` の「Manager は `async throws` 版を持つ」に反する。ほかの `async` の結果（`DialogAnswer`、`ShareResult`、`Bool`、`NotificationAuthorizationStatus`）は既に `Sendable` |
| S-P26 | `async` 版を足すと、`async` の文脈にある今の呼び出しが `async` 版に決まって組めなくなる（**v2 で足した**。SR-4） | A: **同じ名前の `async` 版を足し、ソースの破壊的変更として 3.3 に書く**。`completion` を書いた呼び出しは今のまま callback 版に決まる。`completion` を書かずに `async` の文脈（`async` の関数と、`await` を含む `Task` などの closure の中）から呼んでいた所（`setBadgeCount(1)`、`registerCategory(c)`、`removeCategory(identifier:)`、`trigger` を書いた `show(content:trigger:)`、`update`、`schedule`、`requestPermission()`・`requestPermission(options:)`）は、`await`（と `try`）が無いと組めなくなる（黙って意味は変わらない）。`trigger` を書かない `show(content:)` は、`async` 版の `trigger` に既定が無いので callback 版に決まり、壊れない（SR2-7）/ B: `async` 版の名前を分ける（`showAsync` など）/ C: `async` 版の引数ラベルを分ける（`show(_ content:trigger:)` のように）/ D: `async` 版を足さず、`Result` の callback 版だけを足す | **A**（決定） | 2.0.0 は破壊的変更の版で、同じ名前の `async` の重ね（Apple の SDK と同じ作法）が Swift の利用者にいちばん自然。組めなくなる所はコンパイラーがすべて示し、直しは `await` を足すか `completion` を書くだけ。B は Swift の API の名前の作法（`Async` の接尾辞を付けない）に反し、名前が 2 倍になる。C は同じ操作のラベルが版で違い、読み違えやすい。D は `ios.md` に反し、S-P25 の目的（`async` 版の結果を C ABI で使う）も満たさない。`requestPermission()` は `async` 版で拒否が `false`（失敗でない）になるので、移行の手引きに書く。13 章の UT-31 で、今の呼び出しを `async` の文脈に置いて型検査し、組める形と組めない形を固定する |
| S-P27 | 公開の `NotificationPermissionHelper`（**v2 で足した**。SR-8） | A: **残して `@available(*, deprecated)` にする。`requestPermission` は今のまま（拒否を `permissionDenied` で投げる。DocC から消す `.unknown` を `authorizationFailed` に直す）。`openNotificationSettings()` は同期の形のまま、中で `Task` を起こして port の `async` の口を呼び、結果を捨てる（今と同じく結果を返さない）。新しい口は Manager の `requestPermission(options:presenter:…)` と `openNotificationSettings(presenter:…)`。**Manager は中で helper を使わない**: 今の `requestPermission(options:completion:)` は `RequestNotificationPermissionUseCase` を呼び、拒否のときは `NotificationError.permissionDenied` の文言で `(false, <文言>)` を返す（今と同じ値。拒否を失敗に写すのは Manager の今の口の中だけ）。helper は deprecated の印のある型を中から呼ばないので、ライブラリの中に警告が出ない（SR2-9）。`IosNotificationManager` の `private let permissionHelper` と internal の `init(repository:permissionHelper:)` の引数は消し（deprecated の型の名前を使うと警告が出る）、テストは `init(repository:)` で Mock の repository を渡す形に直す（`IosNotificationManagerTests`・`NotificationPermissionHelperTests` の作り方。SR3-4）** / B: 2.0.0 で消す / C: deprecated にせず残す | **A**（決定） | 公開の型で、今の利用者のソースを組めたままにする。Manager の新しい口と役が重なるので、勧める入口を 1 つにする（common.md の「機能の公開の入口は Manager」）。port の `openNotificationSettings()` が `async -> Bool` になっても、helper の同期の口は `Task` で包めば組める |
| S-P28 | category の列をどの層に置き、Manager が呼んだ順に同期で積めるようにするか（**v3 で足し、v4 で `async` 版と C ABI の呼び方を直した**。SR2-1、SR3-1） | **A: port と UseCase に同期で積む口を足す。`NotificationRepository` に `enqueueCategoryChange(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void)`（同期。積んで戻る）を足し、protocol extension の既定の実装は今の `registerCategory(_:) async`・`removeCategory(identifier:) async` を `Task` で呼んで `completion` を呼ぶ（順は保たない。DocC に書く）。`NotificationRepositoryImpl` はこれを `NotificationCategoryQueue` に同期で積む形で実装する。`RegisterNotificationCategoryUseCase`・`RemoveNotificationCategoryUseCase` に同期の `enqueue(_:completion:)` を足す。Manager の callback 版はそれを同期に呼び、完了を main に積む。`async` 版（`registerCategory(_:) async`・`removeCategory(identifier:) async`）は **`nonisolated(nonsending)`** で宣言し（呼んだ側の executor のまま本体を始める。このプロジェクトは `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = NO` なので、印が無いと本体の前に汎用の executor へ移る）、最初の中断の前に `withCheckedContinuation` の本体（同期に動く）で同じ積みを呼び、`completion` で再開する。**C ABI の受け口は、category では `async` 版でなく callback 版を main のブロックの中で呼ぶ**（同期に積む。SR3-1）。順は積んだ時点で決まる** / B: Manager が列を直に持つ（Manager → UseCase → Repository の規則の例外として `ios.md` に書く）/ C: v2 のまま（列は Data にあるが、Manager → UseCase → port は `async` で、積むのが `Task` の中になる） | **A**（決定） | C は呼んだ順を保てず、`async` 版の完了を列の完了に結び付けられない（SR2-1。SR-1 の原因が残る）。`nonisolated(nonsending)` が無いと、main の `Task` を続けて起こして `async` 版を待つ形で、300 回のうち 257 回順が入れ替わった（レビュー v3 の型検査と実行。付けると 0 回）。A は層の規則（Manager は UseCase 経由で Data に届く）を保ち、列を Data に閉じたまま、呼んだ時点で同期に積める。既定の実装があるので、port を自分で実装した利用者のソースは組めたまま（その実装では順を保たないことを DocC に書く）。B は層の規則に例外を作り、Data の部品（center を読んで書き戻す処理）が Manager に入る |

### 3.3 1b で Swift の利用者に見える変更（README 4.1 と移行の手引きの元）

README 4.1 の 1b の 3 行（印と予約したキー、`openSettingsFor`、`presenter` と取り消しの口）に、次を足す。決まったら README 4.1 に写す（18.2）。

| 変更 | 種類 | 出どころ |
|---|---|---|
| `NotificationError` と `ShareError` の case が変わる（任意の `Error` を持つ case が `FailureDetail` を持つ case になる、`unknown` などを消す、新しい case を足す）。網羅した `switch` は組めなくなる | 破壊的 | S-P7、README 4 章 |
| `IosNotificationManager` が `UNUserNotificationCenterDelegate` に準拠しなくなる | 破壊的 | S-P9 |
| `Log` が deprecated になる（中身は今の `print` のまま。見え方は変わらない）。ライブラリは `Log` を使わず `os.Logger` で出す（ライブラリのログの出る所が Xcode のコンソールの `print` から統合ログに変わり、利用者の値は `.private` で伏せて見える） | 非推奨・動作 | S-P21 |
| `async` 版を足したので、`completion` を書かずに `async` の文脈（`async` の関数と、`await` を含む `Task` などの closure の中）から呼んでいた `setBadgeCount`・`registerCategory`・`removeCategory`・`trigger` を書いた `show`・`update`・`schedule`・`requestPermission` が、`await`（と `try`）を足さないと組めなくなる（`trigger` を書かない `show(content:)` は壊れない） | 破壊的（ソース） | S-P26 |
| public の port の形が変わる: `ShareRepository.present(content:)` が `present(content:presenter:)` に、`NotificationRepository.openNotificationSettings()` が `openNotificationSettings() async -> Bool` になる。port を自分で実装した利用者は組めなくなる | 破壊的 | 8.2、8.5.5、RK-06 |
| `ScheduledNotification`・`ActiveNotification` が `Sendable` になり、`userInfo` が計算プロパティになる（値の木 `userInfoValues` を足す）。読み方は今と同じ（作り直す辞書は `NSNumber` などの Foundation の型）。`init` に渡した、property list の型でない値と `String` でないキーは捨て、件数をログに出す | 動作・追加 | S-P25 |
| `NotificationPermissionHelper` が deprecated になる（動作は今のまま） | 非推奨 | S-P27 |
| `NotificationRepository`（public の port）に `enqueueCategoryChange(_:completion:)` を足す。既定の実装があるので、自分で実装した port は組めたまま（その port では category の要求の順を保たない） | 追加 | S-P28 |
| 通知の delegate を `installDelegate()` で入れ、前の delegate に転送する。ライブラリの通知でないものは、前の delegate がそのメソッドを持てば前の delegate に渡り、ライブラリの受け手（今の受け手を含む）に届かない。持たなければ今と同じくライブラリが受ける | 動作 | D-7、1a-6、1a-7、第 1 部 5.12.3 |
| 今の受け手（`onActionReceived`・`onTextInputActionReceived`）は、main で、`didReceive` から戻った後に呼ばれる（前は system のスレッドで同期に）。userInfo から印が外れる | 動作 | 1a-12、P1-9、S-P8 |
| `setup()`・`onActionReceived`・`onTextInputActionReceived` が deprecated になる。`setup()` を main 以外から呼ぶと delegate を入れずにログを出す（前はどのスレッドからでも入れた） | 非推奨・動作 | D-6、S-P8 |
| Dialog の今の口: `showLoginDialog` の失敗が `onLogin(nil, nil, nil, false, …)` でなく `completion(false, …)` で来る。UIKit が表示を断ったときに `completion(false, …)` が 1 回来る（前は何も来なかった） | 動作 | S-P5、README 1.4 |
| Dialog の今の口: ボタンの handler と observer が Dialog を強く持たなくなり、閉じた後に observer が外れる | 動作（直し） | README 1.4 |
| Share の今の口: 表示した Share のシートが完了の handler なしに解放されたとき（外から閉じた・scene が切れた）、完了が `(false, false, nil, "<固定の文言>")` で 1 回来る（前は来なかった） | 動作 | P1-14、P1-15 |
| Share の今の口の `errorMessage`: 落ち着かない・UIKit が断ったときは `"Failed to present the share sheet."`（前は後ろに system の `localizedDescription` が付いた）。活動の失敗（`completionWithItemsHandler` の `error`）は新しい固定の文言（前は表示の失敗と同じ文言）。ほかの 5 つの文言は変えない | 動作 | S-P7、SR-21 |
| `registerCategory`・`removeCategory` が呼んだ順に反映される（前は別々の `Task` で、片方の変更が失われえた） | 動作（直し） | S-P14、README 1.4 |
| 表示・予約・更新が、userInfo の予約したキーと property list にできない値を拒む | 動作 | P1-9、S-P15 |
| 通知の操作の `errorMessage` が英語の固定の文言になる（前は OS の言語の汎用の文） | 動作 | S-P7 |
| ログが `os.Logger` になり、秘密の値（パスワード、入力欄、通知の返信と内容、Share の内容）を出さない | 動作 | S-P21、README 1.4 |
| 足す口: `PresenterSelection`、`RequestBox`、`FailureDetail`、Dialog の `DialogRequest`・`DialogAnswer`・`DialogInput`・`DialogError`・`show`・`cancel`・`foregroundViewController()`、Share の `presenter` を取る口、通知の `installDelegate()`・`isDelegateInstalled`・`responses`・`settingsRequests`・`launchResponse()`・`async throws` 版・`presenter` を取る権限の要求と設定の画面・完了つきの category、Clipboard の `loadItem(_:scope:requestBox:completion:)`・`cancelLoad(_:)` | 追加 | 付録 A |
| `IosLibrary.framework` に `PrivacyInfo.xcprivacy` が入る | 追加 | D-18 |

### 3.4 1b で直さないもの

| 項目 | 理由 | 扱い |
|---|---|---|
| `cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理。`schedule`・`update` が `content.id` を使わない | 今の UI テストの期待値。意味を変えると 1b の範囲を超える | S-P16。DocC に書く |
| Clipboard の変更の監視が 1 人の受け手（2 回目の開始で前の受け手が止まる） | README 4 章の表に無い。C ABI の形は第 2 部 | C ABI の受け口が分配できる（S-P22） |
| 戻り値の無い通知の操作（`cancel*`、`remove*`、`removeDelivered`）に完了を足すか | 第 2 部で決める（README 6 章、8.6）。足すときは `async` 版の追加で互換を壊さない | 第 2 部の後に足す |
| 新しい口のアクションシートの基点 | S-P6 | 今の `showActionSheet(sourceView:)` |
| ブリッジのログ・不備 | D-22。段階 3 で消す | - |
| `cancelAll`・`cancelAllScheduled`・`removeAllDelivered` は、転送を入れた後もホスト（Unity の通知パッケージなど）の通知まで消す（`UNUserNotificationCenter` の全件を消す API のため） | 今の動作で、印で絞ると意味が変わる。C ABI もブリッジの振る舞いを写す | DocC と移行の手引きに書く（SR-25）。印のある通知だけを消す口が要れば、2.0.0 の後に足す |

### 3.5 不足前提

| 項目 | 扱い |
|---|---|
| 2 回目の申し送り（通知の雛形。U-3・U-4・U-6・U-7）の結果がまだ無い。U-3・U-4 の結果は 1a-13（ホストから応答を渡してもらう関数）を変えうる（P1-23） | 通知の作業を最後にし（S-P24）、結果が出たら 8.3・8.4 を見直す。足す場合も関数の追加で、この設計書の口は変えない見込み |
| G-4・G-6・G-7・G-8・G-9（第 1 部 4.4）は測っていない | 14 章。MS-01・MS-02 は Dialog のサンプルのボタン（SA-02・SA-03）を使うので、C2 の最初に測る（SR-14）。G-6 が成り立たなければ `.foreground` の定義を `foregroundActive` だけにする（P1-11）。G-7 で外から閉じた Dialog が解放されないと分かれば、その経路を約束の外に移す（P1-14） |
| `openSettingsFor` をシステムから呼ばせられるか（Xcode で組んだサンプルなら設定の App の一覧に出る見込み。1a delegate 3.4） | MS-07 |
| アーカイブのプライバシーのレポートを、署名なしのアーカイブで作れるか | MS-10。作れなければ `unity-native-plugin` の agent の Release のアーカイブ（1a-4）で確かめる |

## 4. 方針の適用の確かめ

### 4.1 共通の方針（`common.md`）

| 方針 | 適合 | この設計での扱い |
|---|---|---|
| 層とモジュールの対応（Manager 層までネイティブのライブラリ） | 適合 | 移すロジックはすべて `IosLibrary`（6.1） |
| 機能の公開の入口は Manager（C ABI は入口だけを呼ぶ） | 適合 | 取り消しも Manager の口（S-P2）。共通の型（`PresenterSelection`・`RequestBox`）は引数として渡すだけ |
| Manager の置き場所（機能のフォルダの直下） | 適合 | 今のまま（`Dialog/IosDialogManager.swift` など） |
| Domain に任意の system `Error` を持たない | **直す** | S-P7（README 1.4 の「規則」） |
| Port はドメイン型だけ | 適合 | Dialog の port は `DialogRequest`・`PresenterSelection`・`RequestBox` だけを使う（UIKit の型を持たない。S-P1） |
| Manager → UseCase → Repository、1 操作 1 UseCase | 適合 | Dialog に `ShowDialogUseCase` を置く。Data 層に届かない口（受け手の登録、取り消し、前面の問い合わせ、delegate を入れる口）は UseCase を置かない（Android の 1b 6.3 の条件と同じ。`ios.md` に書く） |
| Manager の公開 API（callback 版と `async throws` 版） | **直す** | 通知の操作に `async throws` 版を足す（S-P13）。Dialog の新しい口も両方を持つ |
| 同期 control の例外 | 適合 | `cancel(_:)`、`cancelLoad(_:)`、`installDelegate()`、受け手の足し外し、`foregroundViewController()` は同期の 1 つだけ |
| Delegate の所有 | **直す** | proxy（`Notification/Presentation/`）が 1 つだけ持ち、manager は準拠を外す（S-P9） |
| テスト（Swift Testing、Mock は Port を実装） | 適合 | 13 章。UI テストは XCUITest |
| 検査の書き方（壊して確かめる） | 適合 | 13 章の各テストに壊し方を書く |

### 4.2 iOS の方針（`ios.md`）

| 方針 | 適合 | この設計での扱い |
|---|---|---|
| 全メソッドの先頭で全パラメータの `Log.d` | **直す** | 秘密の値を伏せる例外を足す（8.7） |
| Manager の callback 版 + `async throws` 版 | **直す** | S-P13 |
| `public` に DocC | 適合 | 足す口すべて。今の DocC の古い記述（Unity のブリッジだけがどのスレッドからも呼べる、など）も直す（18.1 の 8） |
| Objective-C の節 | 対象外 | 段階 3 で消す（D-10）。1b は Objective-C を書かない |

`ios.md` に足すもの（この設計書の決定と同じ PR）: (1) 8.7 のログの規則の例外と書き方（案 D。logger はファイルの `private let` か、generic でない型の中なら `nonisolated private static let` で持つ。generic の型はファイルの `private let` だけ。SR2-5、SR3-2）、(2) UseCase を置かない口の条件（受け手の登録・解除、取り消し、前面の問い合わせ、delegate を入れる口、純粋な関数）、(3) `PresenterSelection` を取る口の書き方（既定 `.firstActiveScene` は今の動作のまま）、(4) 「ネイティブ版は必ず `async throws`」の例外: system の API が失敗を返さない問い合わせ（一覧、権限の状態、category の登録と削除）は投げない `async` にする。「サンプルは `async throws` 版を使う」の例外: 0c の UI テストの基準の今のボタンは callback 版のまま残す（SR-22）。

## 5. 既存実装の差分

### 5.1 ブリッジにしか無いもの（README 1.2）と移す先

| # | 機能 | ブリッジの中身（ファイル） | 移す先 / 扱い |
|---|---|---|---|
| B1 | 共通 | JSON の解析と組み立て（`*JsonParser.swift`） | 移さない（README 1.2）。C ABI では型にする |
| B2 | Clipboard | main actor への受け渡し（`UnityIosClipboardManager.swift` の `Task { @MainActor }`） | C ABI の受け口が積む（P1-4）。`IosLibrary` には足さない |
| B3 | Clipboard | 「append は options を受けない」の検査（`containsOptionsKey`） | Swift の `append` は options を取らない形なので要らない。C の形は第 2 部 |
| B4 | Clipboard | 読み込みの一括の取り消し（`cancelLoads`） | 要求ごとの取り消し（S-P22）。一括は Unity の包みが ID を覚えて繰り返す（P1-24） |
| B5 | Dialog | 3 つのコールバック（onButton / onCancel / completion）を 1 つの handler にまとめる（`UnityIosDialogManager.swift`） | `show(_:)` の `Result<DialogAnswer, DialogError>`（S-P4。8.1） |
| B6 | Dialog | キャンセルしたときの入力を `nil` にする | `DialogAnswer.input` はキャンセルのボタンでは `nil`（8.1） |
| B7 | Dialog | アクションシートの基点（`getRootViewController().view`） | 新しい口が表示元の view の中央に置く（S-P6、P1-13） |
| B8 | Dialog | 引数を省いたときの既定（`enableConfirmWhenEmpty` などの既定が `false`、placeholder が `""`） | Swift の新しい口は今のライブラリの既定（`true`、`nil`）を持つ。C の 0 で埋めた構造体の意味は第 2 部（18.1 の 5） |
| B9 | Notification | 予約済み・表示済みの一覧と日時（ISO 8601）の変換 | 型（`ScheduledNotification`、`ActiveNotification` の `Date`）は既にある。C の日時の形は第 2 部 |
| B10 | Notification | 権限の状態の文字列化 | `NotificationAuthorizationStatus` は既に列挙。C の値は第 2 部 |
| B11 | Notification | userInfo の JSON への変換 | イベントは値の木（S-P11）。一覧の userInfo から印を外す（P1-9） |
| B12 | Notification | sound が無いときの `.default` | `NotificationContent.init` の既定が既に `.default`。C の 0 の意味は第 2 部 |
| B13 | Notification | 受け手を static の変数 1 つに持つ（`s_actionReceivedCallback` など） | イベントの口（S-P10）。C の受け口は `user_data` ごとの登録（第 1 部 5.7） |
| B14 | Notification | `registerCategory` を登録の前に成功で返す | 完了つきの口（S-P14） |
| B15 | Share | 要素の種類（text、url、image、file）から `ShareItem` への変換 | `ShareItem` は既に列挙。C の受け口の型の変換 |
| B16 | Notification | JSON に無いときの既定（trigger の `repeats=false`、位置の `notifyOnEntry=true`・`notifyOnExit=false`、知らない `interruptionLevel` を `.active`）（`UnityIosNotificationJsonParser.swift`） | Swift の型は既定を持たない（`NotificationTrigger` の case は値を全部取る）。C の 0 で埋めた構造体と知らない値の意味は第 2 部（8.9。SR-12） |

### 5.2 README 1.4 の不備と、この設計での扱い

| 不備（README 1.4） | 場所 | 扱い |
|---|---|---|
| `Log` が `print` で Release でも出る。秘密の値を出す | `Common/Log.swift`、各所 | S-P21、8.7。直すログの一覧は 8.7.2 |
| `setup()` が delegate を無条件に上書きし、転送しない。`willPresent` にすべて自分で応える | `IosNotificationManager.swift:172-175, 389-396` | proxy（8.3） |
| 権限の問い合わせの受け手が static の 1 つ | ブリッジの `.m`（`s_hasPermissionCallback`）。ライブラリの口は呼び出しごとの完了で、重ねても上書きされない | ライブラリは直すものが無い。C ABI は `user_data` で要求ごと（18.1 の 3） |
| `registerCategory` が登録の前に成功を返す。読み書きが別々の `Task` | ブリッジ、`NotificationRepositoryImpl.swift:179-191` | S-P14 |
| `cancel` と `cancelScheduled` が同じ。`content.id` を使わない | `NotificationRepositoryImpl.swift` | S-P16（直さない。DocC） |
| userInfo を JSON にする前に確かめない | ブリッジ | S-P11（型で起きない）、S-P15 |
| Dialog の完了が来ない経路 2 つ（ログインの失敗、UIKit が断った） | `IosDialogManager.swift:460-465, 190-192` | S-P5、8.1.4、解放の見張り（6.3.4） |
| Dialog の循環参照の見込み（確定ボタンの handler と observer が `alert` を強く持つ） | `IosDialogManager.swift:396-417, 469-516` | 弱い参照にする（8.1.4）。UT-14 で解放を確かめる |
| observer を外していない | 同上 | 閉じたときに外す（8.1.4） |
| 失敗の返し方がログインとテキスト入力で違う | 同上 | S-P5 |
| ブリッジの `.m` がコールバックの `NULL` を確かめない、必須の引数の `NULL` | ブリッジ | 直さない（D-22）。C ABI の入口の検査（第 1 部 5.9） |
| `NotificationError`・`ShareError` が任意の `Error` を持つ | `Domain/Model/*Error.swift` | S-P7 |
| プライバシーマニフェストが無い | - | 8.8 |
| Share の continuation が、完了の handler が来ないと再開しない | `ShareSheetPresenter.swift:66-96` | 要求の箱が閉じたときの 1 回の処理にする（第 1 部 5.13.1。8.2） |

## 6. 実装アーキテクチャ

### 6.1 足すファイルと可視性

`ios/IosLibrary/IosLibrary/` の下。可視性の `public` は付録 A に宣言を置く。

| ファイル | 中身 | 可視性 |
|---|---|---|
| `Common/Log.swift` | (直す) deprecated にする。中身は今の `print` のまま（S-P21 の Y1）。ライブラリの中では使わない | public（今と同じ。deprecated） |
| ログを出す 33 ファイル | (直す) ファイルの `private let logger = Logger(subsystem:category: "<型名>")`（1 つのファイルに型が複数あれば型ごとに名前を分ける）を持ち、`Log.d` の 164 か所を `logger` の直の呼び出しと `privacy:` に書き換える（S-P21 の D。SR2-5） | private |
| `Common/LogRedaction.swift` | 秘密の値の長さ・有無だけを返す補助（`LogRedaction.length(_:)` など）。秘密の値を補間に入れないための形 | internal |
| `Common/Domain/PresenterSelection.swift` | 表示元の選び方（UIKit を import しない。S-P1） | public |
| `Common/Domain/FailureDetail.swift` | 正規化したエラーの詳細（`domain`、`code`） | public |
| `Common/Application/RequestBox.swift` | 要求の箱（`Mutex`。P1-17 の (4)） | public（`init`・`isClosed` だけ。閉じる処理は internal） |
| `Common/Presentation/PresenterSelection+UIKit.swift` | `PresenterSelection.viewController(_:)` | public |
| `Common/Presentation/ForegroundLocator.swift` | 今の探し方と新しい定義の前面（第 1 部 5.13 の定義） | internal |
| `Common/Presentation/PresentationProcedure.swift` | 表示の手順（第 1 部 5.13.2 の段 1〜6、`presenter` ごとの段） | internal、`@MainActor` |
| `Common/Presentation/ReleaseWatch.swift` | 解放の見張りと関連オブジェクトの鍵（P1-17 の (4)・(5)） | internal |
| `Dialog/Domain/Model/DialogRequest.swift` | 6 種の要求 | public |
| `Dialog/Domain/Model/DialogAnswer.swift` | 押したボタンと入力（`DialogInput` は説明で値を伏せる） | public |
| `Dialog/Domain/Model/DialogError.swift` | 安定した case | public |
| `Dialog/Application/Port/DialogPresenting.swift` | port | public |
| `Dialog/Application/UseCase/ShowDialogUseCase.swift` | 箱の使い回しの検査と port の呼び出し | public |
| `Dialog/Presentation/AlertDialogPresenter.swift` | port の実装（`UIAlertController` の組み立て、handler、observer、取り消し、見張り）と、今の `showDialog(actions:textFields:)` の組み立て | internal |
| `Dialog/IosDialogManager.swift` | (直す) 新しい口と、今の 7 つを新しい芯に載せ直したもの | public（今と同じ） |
| `Share/Domain/Model/ShareError.swift` | (直す) S-P7 | public |
| `Share/Presentation/ShareSheetPresenter.swift` | (直す) 表示の手順・箱・見張り。重複した `getRootViewController()` を消し `ForegroundLocator` を使う | internal（今と同じ） |
| `Share/Application/Port/ShareRepository.swift`、`Share/Data/Repository/ShareRepositoryImpl.swift`、`Share/Application/UseCase/ShareUseCases.swift` | (直す) `presenter` を渡す（8.2） | 今と同じ |
| `Share/IosShareManager.swift` | (直す) S-P18 | public |
| `Notification/Domain/Model/NotificationError.swift` | (直す) S-P7 | public |
| `Notification/Domain/Model/NotificationEvents.swift` | `NotificationResponseEvent`、`NotificationSettingsRequest`、`NotificationUserInfoValue` | public |
| `Notification/Domain/Model/NotificationMarker.swift` | 印のキーと値（P1-9）、付ける・外す・予約したキーの検査 | internal |
| `Notification/Presentation/Delegate/NotificationDelegateRouter.swift` | 見分け方・転送の規則・循環・起動のきっかけの判定（S-P20） | internal |
| `Notification/Presentation/Delegate/NotificationDelegateProxy.swift` | `UNUserNotificationCenterDelegate` を実装する proxy、KVO、`didBecomeActive` の受け手 | internal |
| `Notification/Presentation/Delegate/CompletionOnce.swift` | 1 回だけ通す包み（P1-17 の (3)、第 1 部 5.12.4） | internal |
| `Notification/Presentation/Delegate/NotificationDelegateInstaller.swift` | 入れる処理、入れた印（`Atomic`。S-14） | internal |
| `Notification/Presentation/Event/NotificationEventHub.swift` | イベントの口と登録（S-P10） | public |
| `Notification/Data/Repository/NotificationCategoryQueue.swift` | category の要求の FIFO と 1 つの取り出し（プロセスで 1 つ。`Mutex`。S-P14）。center は internal の抽象 `NotificationCategoryCenter`（`categories() async`、`setCategories(_:)`）で受け、本番は `UNUserNotificationCenter.current()` を包み、テストは偽物を渡す（SR2-10） | internal |
| `Notification/Domain/Model/NotificationCategoryChange.swift` | (新) `register(NotificationCategory)` / `remove(identifier: String)` の要求の値（S-P28） | public |
| `Notification/Data/Repository/NotificationRepositoryImpl.swift` | (直す) 印の付け外し、userInfo の検査（入口の最初。8.3.3）、エラーの正規化、category を列に委ねる、設定の画面の結果 | public（今と同じ） |
| `Notification/Application/Port/NotificationRepository.swift` | (直す) `openNotificationSettings` の形（8.5.5）、`enqueueCategoryChange(_:completion:)` と既定の実装（S-P28） | public（今と同じ） |
| `Notification/Application/UseCase/*.swift` | (直す) 上に合わせる | public（今と同じ） |
| `Notification/Application/UseCase/NotificationPermissionUseCases.swift` | (新) `RequestNotificationPermissionUseCase`（要求して許可の真偽を返す）、`OpenNotificationSettingsUseCase`（開けたかを返す）（SR-17） | public |
| `Notification/Presentation/Permission/NotificationPresentationGate.swift` | (新) 権限の要求と設定の画面の前面の判定（第 1 部 5.13.2 の「表示しない」の列）。状態を読み、要るときだけ前面を確かめてから UseCase を呼ぶ（SR-17） | internal、`@MainActor` |
| `Notification/Presentation/Permission/NotificationPermissionHelper.swift` | (直す) deprecated（S-P27）。`openNotificationSettings()` は `Task` で port の `async` の口を呼ぶ | public（今と同じ） |
| `Notification/Domain/Model/ScheduledNotification.swift`、`ActiveNotification.swift` | (直す) userInfo を値の木で持ち `Sendable` に。`userInfo` は計算プロパティ（S-P25） | public |
| `Notification/IosNotificationManager.swift` | (直す) 新しい口、delegate の準拠を外す、今の受け手を deprecated に | public |
| `Clipboard/IosClipboardManager.swift` | (直す) `loadItem(_:scope:requestBox:completion:)`、`cancelLoad(_:)`、DocC | public |
| `PrivacyInfo.xcprivacy` | (新) 8.8 | 配布物 |

ほかに:

| ファイル | 変更 |
|---|---|
| `ios/IosLibrary/IosLibrary.xcodeproj/project.pbxproj` | `PrivacyInfo.xcprivacy` を framework の Resources に入れる |
| `agent-rules/coding-rules/ios.md` | 4.2 の 4 つ。**この設計書の決定と同じ PR** |
| `ios/IosLibraryExample/` | 12 章 |

### 6.2 スレッドの規則（Swift の API）

| 規則 | 内容 |
|---|---|
| 呼べるスレッド | `IosDialogManager`・`IosShareManager`・`IosNotificationManager` の操作、`cancel(_:)`、`cancelLoad(_:)` は、どのスレッドからでも呼べる。**main actor だけの口**: `IosClipboardManager`（今と同じ）、`getRootViewController()`・`foregroundViewController()`、`NotificationEventHub` の受け手の足し外し、`launchResponse()`。**main スレッドだけの口**: `installDelegate()`（main 以外では何もせず `.notMainThread` を返す。`pthread_main_np()` で見る。第 1 部 1.3） |
| 待たない | どの口も main を待たない（`DispatchQueue.main.sync`、セマフォ、main を待つロックを書かない。D-6） |
| 完了 | 完了つきの口の完了は、すべて main で、ちょうど 1 回、呼び出しの中では呼ばない（main から呼んでも後で来る）。型は `@MainActor @Sendable`（README 4.1 の 0e と同じ） |
| イベント | イベントの口の受け手は main で呼ぶ。**例外は受け手を足す呼び出しの中で、保っていたイベントを渡すこと**（S-P10。第 1 部 S-4。Android の 1b 6.2 の例外と同じ） |
| ロック | 受け手・完了・前の delegate・system の completion を呼ぶ間、ライブラリのロックを持たない（S-8。第 1 部 5.12.1） |
| 例外 | 利用者のコールバックは Swift の `throws` を持たないので、投げる経路が無い。Objective-C・C++ の例外は捕まえない（P1-16） |
| 箱の閉じたときの処理 | nonisolated の `@Sendable` の closure で、main に積むことだけをする（6.3.2。SR-3） |
| main への積み方 | ライブラリの中でも、main で動かす処理は `DispatchQueue.main.async` で積み、ブロックの中で `MainActor.assumeIsolated` を使う（P1-4 と同じ。積んだ順に動く）。今の `Task { @MainActor in }` の所（通知の完了など）は、順序を約束していない所だけそのまま残す |

### 6.3 共通の部品

#### 6.3.1 `PresenterSelection`（S-P1、S-6）

| 値 | 意味 | 使う所 |
|---|---|---|
| `.firstActiveScene`（既定） | 今の探し方: `connectedScenes` の最初の `foregroundActive` の `UIWindowScene` の key window の `rootViewController` から `presentedViewController` をたどる。1 回探して、待たない（第 1 部 5.13.2 の「既定」の行） | 今のすべての口と、新しい口の既定 |
| `.foreground` | 新しい定義の前面: `foregroundActive` か `foregroundInactive` の scene のうち key window を持つもの。`isBeingDismissed` でない `presentedViewController` をたどった最上位（第 1 部 5.13）。段 1〜6 | C ABI の受け口が渡す（P1-11） |
| `.viewController(_:)` | 呼び出し側が渡す closure を main で 1 回呼んで得た ViewController。段 1、3〜6。`nil` なら前面でない | ゲームの画面の上など、利用者が表示元を決めたいとき |

- 型は `public struct`（中は internal の enum）。`.firstActiveScene` と `.foreground` は static な値、`.viewController(_:)` は static な関数なので、呼ぶ側は enum と同じに書ける（SR-5）。値の比べは公開しない（closure を比べられないため）
- 実装は `ForegroundLocator`（6.1）の 1 か所に置き、Dialog・Share・権限の要求・設定の画面が使う。`ShareSheetPresenter` の重複した `getRootViewController()` は消す
- G-6 が成り立たなければ、`.foreground` の定義を `foregroundActive` だけに直す（P1-11 の条件。MS-02）。1 回目の申し送りの雛形では、`didFinishLaunching` の中（scene が `foregroundInactive`）から出したアラートが iPhone 17 / 26.2 で出た（`results/2026-10-31-ios-c-abi-unity-handoff-1.md` の 6 章。以下「申し送り 1」）。iPad の複数の window はまだ測っていない

#### 6.3.2 `RequestBox`（S-P2、S-15、第 1 部 5.13.1）

| 規則 | 内容 |
|---|---|
| 状態 | 開いている / 閉じた。`Mutex` で守る。`isClosed` はどのスレッドからでも読める |
| 作る | 利用者か C ABI の受け口が `RequestBox()` で作る。渡されなければ口が作る |
| 閉じたときの処理の隔離 | **nonisolated の `@Sendable` の closure** にし、中では結果を `DispatchQueue.main.async` に積むことだけをする（main actor を継がない。背景のスレッドから取り消しで閉じても止まらない。SR-3）。token の操作（Clipboard の `cancel()`）、Dialog を閉じる処理、利用者の完了は、積んだ main のブロックの中で `MainActor.assumeIsolated` を使って行う |
| 付ける | 口が箱に「閉じたときの処理」を 1 回だけ付ける（internal。main から）。**付けるのは 1 つの要求だけ**。既に付いた箱を渡すと、その要求は `invalidRequest` で完了する（Dialog）、`ClipboardError.invalidRequest` で完了する（Clipboard） |
| 閉じる | 最初に閉じたものだけが効く（結果、取り消し、表示の失敗、見張り）。閉じた後に、結果を main に積んで完了へ渡す |
| 取り消し | `IosDialogManager.cancel(_:)`・`IosClipboardManager.cancelLoad(_:)` が、どのスレッドからでも、待たずに、箱を取り消しで閉じ、閉じる・止める処理を main に積む。既に閉じた箱、付いていない箱は、取り消しで閉じたことだけを覚える。**閉じた箱に後から処理を付けたときも、同じ経路を通る**（付ける関数が閉じた結果を読み、閉じたときの処理を鍵の外で 1 回呼び、それが main に積む。完了は呼び出しの中では来ない） |
| `@unchecked Sendable` | P1-17 の (4)。可変の状態は `Mutex` の中だけ。閉じたときの処理は鍵の外で 1 回だけ呼ぶ。TSan のテストを持つ（UT-03） |

#### 6.3.3 表示の手順（第 1 部 5.13.2）

`PresentationProcedure`（`@MainActor`、internal）が、`presenter` の値ごとに第 1 部 5.13.2 の段を行う。Dialog・Share は「表示する」の列、権限の要求と設定の画面は「表示しない」の列。

| 段 | Swift での形 |
|---|---|
| 1 | 箱を使う。閉じていれば何もしない（完了は閉じたときに積んである） |
| 2 | `ForegroundLocator` で探す。見つからなければ `notForeground` で箱を閉じる |
| 3 | 落ち着いていれば、基点を設定し（アクションシートと Share は必ず。P1-13、第 1 部 5.11）、見張りを付けて `present` する。補いとして、`present` を呼んだ直後に表示する ViewController の `presentingViewController` が `nil` なら、UIKit が断ったとみなして `presentationFailed` で閉じる（第 1 部 5.13.1。直後に設定されることを MS-01 で確かめ、されなければこの補いを外して見張りだけにする。SR-16） |
| 4〜5 | 落ち着いていなければ、`transitionCoordinator` の completion を 1 回だけ待ち（無ければ待たない）、main キューの次の回に積んで、箱が開いていれば 1 回だけやり直す |
| 6 | 2 回目も落ち着かなければ `presentationFailed` で閉じる |

- `.firstActiveScene` は今のまま（段 2・3 だけ。落ち着いていなければ今の口ごとの動作: Dialog は `present` を呼ぶ、Share は `presentationFailed`）。箱と見張りは付ける
- 表示の途中（`isBeingPresented`、`present` の完了の前）の取り消しは、`present` の完了の中で閉じる（R4-2。G-4 を MS-01 で測る）
- 申し送り 1 の雛形（同じ手順を capi の中に持つ）では、同じ main の回の 2 つのアラートが 2 つとも出て、2 つ目が上に出た。表示の前と後の取り消しも完了が 1 回ずつ来た

#### 6.3.4 解放の見張り（P1-14、第 1 部 5.13.1）

- 表示する ViewController に、箱を強く持つ小さなオブジェクトを `objc_setAssociatedObject` で結び付ける。その `deinit`（nonisolated。ViewController にも main の状態にも触れない）が箱を閉じる。`present` の完了が来ていなければ `presentationFailed`、来ていれば `dismissedBySystem`
- 前提: ライブラリは表示した ViewController を `weak` で持つ。handler と observer は ViewController を強く捕まえない（8.1.4）
- 申し送り 1 で測ったこと（シミュレーター）: 外から `dismiss` したアラートは、通常と ASan の版では約 0.5 秒で解放され、見張りが `dismissedBySystem` で閉じた。**TSan の版では 15 秒たっても解放されず、完了が来なかった**。外から閉じた Share のシートでは `completionWithItemsHandler` が呼ばれず、見張りの無い雛形では完了が来なかった。したがって **Share にも見張りが要る**（8.2）
- 残る G-7（MS-03）: 外から閉じた Share の ViewController がいつ解放されるか、UIKit が表示を断った ViewController がいつ解放されるか（SR-16）、TSan の版で解放されないのはなぜか（TSan が何かを持ち続けるのか）。通常の版で解放されない経路が見つかれば、その経路を約束の外に移す（P1-14）。TSan の版の遅れは約束の範囲に入れない（テストの組み方の問題として扱い、見張りに頼るテストは TSan の回で skip し、理由を書く）

#### 6.3.5 `FailureDetail`（S-P7）

`public struct FailureDetail: Sendable, Equatable { public let domain: String; public let code: Int }`。`init(systemError:)` は `NSError` に橋渡しして `domain` と `code` だけを取る（Clipboard の `ClipboardFailureDetail(systemError:)` と同じ作り）。`localizedDescription` は持たない（文言は利用者の言語で変わり、入力の値を含みうる）。

## 7. 今のブリッジの約束の対応表（README 5.1）

「C ABI / 包み」は、Swift の API では持たず、C ABI の受け口（第 2 部）か Unity の包み（2c）が持つもの。

| ブリッジの約束（関数） | 新しい Swift の API | 違い |
|---|---|---|
| Dialog の 6 種（`showDialog`、`showConfirmDialog`、`showDestructiveDialog`、`showActionSheet`、`showTextInputDialog`、`showLoginDialog`）を 1 つの handler `(button, …, isSuccess, errorMessage)` で返す | `IosDialogManager.show(_:presenter:requestBox:completion:)` の `Result<DialogAnswer, DialogError>` | 失敗は文字列でなく case。外から閉じた・取り消し・前面でないが別の case |
| Dialog の失敗 `"Failed to get root view controller"` | `.firstActiveScene` では `DialogError.notForeground`、`.foreground` では `notForeground` か `presentationFailed` | 文言は持たない |
| アクションシートの基点（root の view） | 新しい口が表示元の view の中央に置く | iPad の iOS 18 で落ちない（第 1 部 5.11） |
| Dialog の取り消し（ブリッジに無い） | `IosDialogManager.cancel(_:)` | 追加（P1-24） |
| 通知の `notificationSetup` | `IosNotificationManager.installDelegate()` | main だけ、転送する（D-4、D-7） |
| `setNotificationActionReceivedCallback`・`setNotificationTextInputActionReceivedCallback`（static の 1 つに差し替え） | `responses.addListener(_:)` と登録の `remove()` | 足す・外す形。受け手が 0 の間は保つ。差し替えは Unity の包み（第 1 部 C-7） |
| アクションの userInfo を JSON の文字列で渡す | `NotificationResponseEvent.userInfo`（値の木。印を外す） | JSON は C ABI / 包み |
| 起動のきっかけ（ブリッジに無い） | `isLaunchResponse` と `launchResponse()` | 追加（D-7） |
| `openSettingsFor` で設定の App を開く | `settingsRequests` のイベント | 意味を直す（P1-10） |
| `showNotification`・`updateNotification`・`scheduleNotification` の `(isSuccess, errorMessage)` | 今の callback 版（文言は固定）と `async throws` 版（`NotificationError`） | 型のあるエラーは `async throws` 版 |
| `cancel*`・`remove*`・`removeNotificationCategory`（戻り値なし） | 今の口（`removeCategory` は完了つきの形も） | 完了を返すかは第 2 部 |
| `getScheduledNotifications`・`getDeliveredNotifications` の JSON（ISO 8601 の日時） | 今の `getScheduled`・`getDelivered`（userInfo から印を外す） | JSON と日時の形は C ABI |
| `requestNotificationPermission` の `(isSuccess, errorMessage)`（拒否も失敗） | `requestPermission(options:presenter:completion:)` の `Result<Bool, NotificationError>` | 拒否は `.success(false)`。前面でないは `notForeground` |
| `getNotificationAuthorizationStatus` の文字列 | `authorizationStatus(completion:)`（列挙。今と同じ） | 文字列は C ABI |
| `hasNotificationPermission`（static の受け手） | `hasPermission(completion:)`（今と同じ） | 受け手の上書きはブリッジだけの不備 |
| `openNotificationSettings`（戻り値なし） | `openNotificationSettings(presenter:completion:)` | 開けたか・前面でないを返す |
| `setNotificationBadgeCount` | 今の口と `async throws` 版 | - |
| `registerNotificationCategory`（登録の前に成功） | `registerCategory(_:completion:)` と `async` 版 | 反映を確かめてから完了（S-P14） |
| Share の `shareContent` の `(isSuccess, completed, activityType, errorMessage)` | `share(content:presenter:completion:)` の `Result<ShareResult, ShareError>` | 失敗は case |
| Clipboard の 13 の操作の `(isSuccess, errorCode, errorMessage)` と JSON | 今の `IosClipboardManager` の口（`ClipboardError` は既に安定） | JSON は C ABI |
| `clipboardCancelLoads`（一括） | `cancelLoad(_:)`（要求ごと） | 一括は Unity の包み（P1-24） |
| `clipboardStartObserving` / `clipboardStopObserving` | 今の `startObserving` / `stopObserving` | 分配は C ABI の受け口（S-P22） |
| すべての完了を main で返す（Clipboard・Share）、返さない（通知） | 6.2 | 通知も main（0e で済み） |

## 8. 機能別の詳細設計

### 8.1 Dialog（S-P3〜S-P6、S-5、S-6、S-15、README 4 章）

#### 8.1.1 層

| 層 | 型 | 中身 |
|---|---|---|
| Domain | `DialogRequest`、`DialogAnswer`、`DialogInput`、`DialogError` | 値だけ。UIKit を import しない |
| Application | `DialogPresenting`（port）、`ShowDialogUseCase` | UseCase は箱の使い回しを検査し、port を呼ぶ |
| Presentation | `AlertDialogPresenter` | `UIAlertController` を組み、`PresentationProcedure` で出す。handler、observer、取り消し、見張り |
| Manager | `IosDialogManager` | 新しい口、今の 7 つの口、`getRootViewController()`、`foregroundViewController()`、`cancel(_:)` |

`cancel(_:)` と `foregroundViewController()` は Data 層に届かないので UseCase を置かない（4.1）。

#### 8.1.2 要求と答え

| 要求（`DialogRequest`） | 項目（既定） | 押せるボタン（`DialogAnswer.Button`） |
|---|---|---|
| `.alert` | `title`、`message`、`buttonTitle`（`"OK"`） | `.primary` |
| `.confirm` | `title`、`message`、`confirmTitle`（`"OK"`）、`cancelTitle`（`"Cancel"`） | `.primary`、`.cancel` |
| `.destructive` | `title`、`message`、`destructiveTitle`（`"Delete"`）、`cancelTitle`（`"Cancel"`） | `.destructive`、`.cancel` |
| `.actionSheet` | `title`、`message`、`options`（文字列の配列）、`cancelTitle`（`"Cancel"`） | `.option(index:)`、`.cancel` |
| `.textInput` | `title`、`message`、`placeholder`（`nil`）、`confirmTitle`（`"OK"`）、`cancelTitle`（`"Cancel"`）、`enableConfirmWhenEmpty`（`true`） | `.primary`（入力 `.text`）、`.cancel` |
| `.login` | `title`、`message`、`usernamePlaceholder`（`"Username"`）、`passwordPlaceholder`（`"Password"`）、`loginTitle`（`"Login"`）、`cancelTitle`（`"Cancel"`）、`enableLoginWhenEmpty`（`true`） | `.primary`（入力 `.login`）、`.cancel` |

- 既定の文言は今の `IosDialogManager` の既定と同じ（README 4 章）
- `DialogAnswer` は `button`、`title`（押したボタンの表示の文字）、`input`（`.textInput` と `.login` の `.primary` だけ。**キャンセルのボタンでは `nil`**。B6）を持つ
- `DialogInput` の `description` は値を伏せる（`text(length: 5)` の形）。`Equatable` は値で比べる
- アクションシートにテキスト入力は、型の上で書けない（第 1 部 5.11 の「書けない形にできればそうする」）。アクションシートの iPad の基点は表示元の view の中央（S-P6）

#### 8.1.3 結果と完了

| 終わり方 | 結果 | 約束 |
|---|---|---|
| ボタンを押した | `.success(DialogAnswer)` | する |
| `cancel(_:)` | `.failure(.canceled)`。上に別の画面が重なっていれば Dialog は閉じない（残ったボタンは閉じた箱に当たり効かない。P1-24） | する |
| 表示の手順の失敗（前面が無い、2 回目も落ち着かない） | `.failure(.notForeground)`、`.failure(.presentationFailed)` | する |
| UIKit が表示を断った | 見張りが `.failure(.presentationFailed)` | する |
| 外から `dismiss` された、scene が切れて解放された | 見張りが `.failure(.dismissedBySystem)` | G-7 で解放を確かめる（MS-03） |
| 使い回した箱を渡した | `.failure(.invalidRequest)` | する |
| 表示中に画面の構成を変えた（0.1） | 来ないことがある（取り消せば来る） | 約束の外 |

- 完了は main で 1 回、`show` の中では呼ばない
- `async throws` 版は、`Task` が取り消されると箱を取り消し、`CancellationError` を投げる（Swift の決まり）。ほかの失敗は `DialogError` を投げる

#### 8.1.4 今の 7 つの口（S-P5）

| 口 | 形 | 1b の後の中身 |
|---|---|---|
| `showAlert`・`showConfirmDialog`・`showDestructiveDialog`・`showActionSheet`・`showTextInputDialog`・`showLoginDialog` | 今のまま（引数・既定・コールバックの型） | 新しい芯（`AlertDialogPresenter`）で出し、結果を今のコールバックに写す。`presenter` は `.firstActiveScene`。ボタンの callback は今と同じ値（例: キャンセルは `(cancelTitle, true, nil)`）。`completion(true, nil)` は `present` の完了で 1 回 |
| `showDialog(actions:textFields:…)` | 今のまま | 利用者の `UIAlertAction` をそのまま足す組み立ては `AlertDialogPresenter` の別の入口に置く（新しい要求の型では表せない）。表示の部分と見張りは共通 |
| 失敗 | - | すべて `completion(false, <文言>)` で 1 回。`showLoginDialog` も同じ（`onLogin` は失敗では呼ばない）。前面が見つからないときの文言は今の `"Failed to get root view controller"` のまま。UIKit が断ったとき（見張りか補い）は新しい固定の文言 `"Failed to present the dialog"` で 1 回（SR-20） |
| 外から閉じた・scene が切れた | - | 見張りが箱を閉じるが、今の口には結果の通り道が無いので**何も呼ばない**（`completion(true, nil)` は表示したときに済んでいて、ボタンの callback は押されていないので呼ばない）。DocC に書く（SR-20） |
| 循環参照と observer | - | 確定ボタンの handler と observer は `alert`・`confirmAction`・`textField` を `weak` で捕まえる。observer の token を持ち、どの終わり方でも閉じたときに `NotificationCenter.default.removeObserver(token)` で外す |
| ログ | - | 入力の値を出さない（8.7.2） |

`getRootViewController()` は今のまま残す（`@MainActor`。今の探し方）。DocC に、`foregroundViewController()` との違い（`foregroundInactive` の scene を含むか、閉じかけの ViewController をたどるか）を書く。

### 8.2 Share（S-P18、S-6）

| 項目 | 決め方 |
|---|---|
| 新しい口 | `share(content:presenter:completion:)`（`presenter` は既定なし。`Result<ShareResult, ShareError>`）。`share(content:presenter:) async throws -> ShareResult`（今の口に `presenter` を既定つきで足す） |
| 今の口 | `share(content:completion:)`（4 つの値）は形を変えない。中は `.firstActiveScene` で新しい手順を通る |
| 表示の手順 | 6.3.3 の「表示する」の列。`.firstActiveScene` では今と同じく、落ち着いていなければ `presentationFailed` |
| 箱 | 要求ごとに口が作る（Share は取り消しを出さない。P1-24）。`completionWithItemsHandler`、表示の失敗、見張りのどれかが 1 回閉じる |
| 見張り | **必ず付ける**。申し送り 1 で、外から閉じた Share のシートは `completionWithItemsHandler` を呼ばず、見張りの無い形では完了が来なかった。見張りが閉じると、新しい口は `.failure(.dismissedBySystem)`、今の口は `(false, false, nil, "<固定の文言>")`（3.3） |
| iPad の基点 | 表示元の view の中央（P1-13）。申し送り 1 で iPad Pro 11-inch (M4) / 18.3 で落ちないことを確かめた |
| continuation | 箱が閉じたときの 1 回の処理で再開する。見張りで閉じたときも再開し、漏らさない（第 1 部 5.13.1） |
| 結果 | `completionWithItemsHandler` の `completed` と `activityType` は今と同じ `ShareResult`。`error` があれば `activityFailed(FailureDetail)` |
| 層 | `ShareRepository.present(content:presenter:)` に `presenter` を足す（public の port。利用者が実装していれば組めなくなる。3.3 の破壊的の行に入れた。SR-8） |
| ログ | `IosShareManager.swift:81` の `Log.e(TAG, "[share] error: \(error)")` は `ShareError` の値（URL・パス）を出すので、case の名前だけにする（8.7.2。SR-7） |

### 8.3 通知の delegate（S-1、S-2、S-3、S-10、S-14、第 1 部 5.12）

#### 8.3.1 入れる口

```swift
public enum NotificationDelegateInstallResult: Sendable { case installed, notMainThread }
extension IosNotificationManager {
    @discardableResult public static func installDelegate() -> NotificationDelegateInstallResult
    public static var isDelegateInstalled: Bool { get }   // Atomic: true once installed in this process
}
```

| 項目 | 振る舞い | 出典 |
|---|---|---|
| main 以外 | すぐ `.notMainThread`。何も変えない。ログを出す | D-6、1a-9 |
| main | 戻る前に proxy を `UNUserNotificationCenter.current().delegate` に設定する | D-4 |
| 冪等 | 今の delegate が proxy なら何もしない | 第 1 部 5.12.6 |
| 差し替えの後 | 今の delegate を新しい前の delegate にし、入れ直す。ログを出す | 1a-10 |
| 起動の後 | 入れる。`applicationState == .active` のときだけ「起動の後かもしれない」のログ | 1a-11、R-36 |
| 初めて入れたとき | `isDelegateInstalled` を立て（`Atomic`。C の口でも Swift の口でも同じ印）、`UIApplication.didBecomeActiveNotification` の受け手を登録する。既に `active` なら起動のきっかけは無しと決める | P1-6、P1-22、S-14 |
| C の `ntk_notification_install` | この口を呼び、結果を `NONE` / `WRONG_THREAD` に写すだけ | 第 1 部 1.4 |
| `setup()` | deprecated。`installDelegate()` を呼ぶだけ（S-P8） | S-P8 |

#### 8.3.2 proxy と router（S-P20、S-2）

| 部品 | 受け持ち |
|---|---|
| `NotificationDelegateProxy`（`NSObject`、`UNUserNotificationCenterDelegate`、nonisolated、`Sendable`。状態は `Mutex`） | 3 つのメソッドを常に実装する。`UNNotification` から小さな値（`identifier`、`date`、`userInfo`、push か、`actionIdentifier`、`userText`）を作り、router に渡す。前の delegate は `weak` で持ち、`responds(to:)` を呼ぶたびに見る。KVO で差し替えをログに出す（自動では入れ直さない） |
| `NotificationDelegateRouter`（値型、純粋） | 第 1 部 5.12.2 の見分け方（push はライブラリの通知でない → 印があればライブラリ → ほか）、5.12.3 の転送の規則、5.12.5 の循環の防止（転送の呼び出しの間だけ鍵を集合に入れる）、P1-22 の起動のきっかけの判定。結果は「ライブラリが扱う（表示の選択肢 / イベント）」「前の delegate へ渡す」の 2 つ |
| `CompletionOnce` | 第 1 部 5.12.4 のとおり。nonisolated で `@Sendable` の closure を前の delegate に渡す（R-4） |

- `willPresent` でライブラリが扱うときは、`foregroundPresentationOptions`（既定 `[.banner, .list, .sound, .badge]`。今と同じ）で 1 回完了する。イベントは出さない
- `didReceive` でライブラリが扱うときは、イベントを main に積み、そのブロックの中で受け手に渡すか保つか（8.4）した後、今の受け手（S-P8）を呼び、最後に system の completion を 1 回呼ぶ（1a-12）
- `openSettingsFor` でライブラリが扱うときは、`settingsRequests` のイベントを積む（P1-10）。設定の App は開かない
- `Mutex` を持ったまま、前の delegate・system の completion・受け手のどれも呼ばない（S-8）
- proxy は `IosNotificationManager` の `static let` で強く持ち、解放しない（第 1 部 5.12.1、5.14）

#### 8.3.3 印（S-3、P1-9）

| 場面 | 振る舞い |
|---|---|
| `show`・`schedule`・`update` | **入口の最初に**（`update` は今の予約を `removePendingNotificationRequests` で消すより前に）、利用者の userInfo にキー `com.jonghyunkim.nativetoolkit` があれば `NotificationError.reservedUserInfoKey`、property list にできなければ `invalidUserInfo` で失敗する（何も消さず、`add` も呼ばない。SR-9）。通れば値 `1`（整数）を足して `add` する |
| `getScheduled`・`getDelivered`・イベント・今の受け手 | 利用者に返す userInfo から印を外す |
| push | 印があってもライブラリの通知としない（1a-12。router） |

### 8.4 通知のイベントの口（S-4、S-P10〜S-P12、README 8.6）

#### 8.4.1 口と型

| 口 | 型 | 保つ |
|---|---|---|
| `IosNotificationManager.responses` | `NotificationEventHub<NotificationResponseEvent>`（タップ、アクション、テキスト入力、消したとき） | 32 件 |
| `IosNotificationManager.settingsRequests` | `NotificationEventHub<NotificationSettingsRequest>`（`openSettingsFor`） | 32 件 |

`NotificationResponseEvent` は `notificationIdentifier`、`actionIdentifier`（既定のアクションと消したときは OS の定数）、`categoryIdentifier`、`userText`（テキスト入力だけ。説明では長さだけ）、`userInfo`（`[String: NotificationUserInfoValue]`。印を外す）、`isLaunchResponse` を持つ。`NotificationSettingsRequest` は `notificationIdentifier: String?`（`nil` は通知の無い要求）を持つ。どちらも `Sendable`・`Equatable`。

#### 8.4.2 足す・外す・配る（Android の 1b 8.4 と同じ規則）

| 出来事 | 振る舞い |
|---|---|
| 足す（`addListener`。`@MainActor`） | `isDelegateInstalled` が偽なら `NotificationError.delegateNotInstalled` を投げる（P1-6）。登録を作って並びの末尾に足す。保ちが空でなければ、保ちを外してから、この呼び出しの中で受けた順に、足した受け手に渡す |
| 受け手が渡す途中で自分を外した | まだ渡していない残りは、並びに残っている最も古い受け手に続けて渡す（受け手の中で足された受け手を含む）。残る受け手が無ければ、保ちの先頭に戻す |
| 配る（main） | 並びが空なら保ちの末尾に足す（32 を超えたら古いものから捨てる。捨てたログはプロセスで最初の 1 回だけ `.info`、以後は `.debug`。SR-23）。空でなければ、並びの写しを取り、各受け手を呼ぶ直前に外されていないかを見てから呼ぶ（全員に配る） |
| 外す（登録の `remove()`。`@MainActor`） | その場で並びから外す。2 回目は何もしない |
| 期限・重複 | 期限なし（プロセスの寿命。ディスクに書かない）。重複を除かない（system は応答を 2 度渡さない。2 回のタップは 2 つのイベント） |

- 保ちが溜まるのは受け手が 0 の間だけなので、受け取るのは次に足された 1 人目（第 1 部 5.12.7 の「誰に渡すか」）
- C ABI の受け口は、その種類の最初の C の登録の挿入のブロック（main）の中で `addListener` を呼び、以後は外さない。C の登録が 0 件の間は受け口が保つ（第 1 部 5.12.7）
- 今の受け手（S-P8）は保ちにも並びにも関わらず、配るたびに呼ぶ

#### 8.4.3 起動のきっかけ（S-P12、P1-22）

| 項目 | 振る舞い |
|---|---|
| 見分け方 | router がプロセスで最初の `didReceive`（転送したものも数える）を見て、最初の `didBecomeActive` より前で、ライブラリが扱った（ライブラリの通知か誰も受けない通知）なら起動のきっかけとする。ホストへ転送したなら無し。循環で止めたものは無し（R4-3）。入れたときに既に `active` なら無し |
| 印 | そのイベントの `isLaunchResponse` を真にする（保ったイベントとしても配る） |
| `launchResponse()`（`@MainActor`、`throws`） | 入れていなければ `delegateNotInstalled`。起動のきっかけのイベントを返す（無ければ `nil`）。値は最初の `didBecomeActive` の後に決まり、その前は `nil` が後で値に変わりうる（DocC に書く） |

### 8.5 通知の操作（S-P13〜S-P17、S-P19、S-13）

#### 8.5.1 エラー（S-P7）

10 章の表のとおり。`NotificationError` は `LocalizedError` で、`errorDescription` は英語の固定の文言（入力の値を含めない）。今の callback 版の `errorMessage` はこの文言になる。

#### 8.5.2 `async throws` 版（S-P13）

`show`・`update`・`schedule`・`setBadgeCount`・`requestPermission(options:presenter:)`・`openNotificationSettings(presenter:)` に `async throws`（`NotificationError`）を、`getScheduled`・`getDelivered`・`hasPermission`・`authorizationStatus`・`registerCategory`・`removeCategory` に `async`（投げない）を足す。どれも UseCase をそのまま公開する薄い包み（`ios.md`）。今の callback 版は形を変えない。

- 結果はすべて `Sendable`（一覧は S-P25 で `Sendable` にする。SR-2）。C ABI の受け口は main actor の `Task` の中で待てる
- 同じ名前の `async` 版を足すので、`completion` を書かずに `async` の文脈（`await` を含む closure を含む）から呼んでいた所は組めなくなる（S-P26。3.3）
- 投げない `async` は `ios.md` の「必ず `async throws`」の例外として書く（4.2 の (4)。SR-22）

#### 8.5.3 userInfo の検査（S-P15）

`PropertyListSerialization.propertyList(_:isValidFor: .binary)` で確かめる。だめなら `invalidUserInfo`。置く所は 8.3.3 と同じ入口の最初で、予約したキーの検査の後、`update` の今の予約を消す前（SR-9）。

#### 8.5.4 権限の要求（S-P19、S-13）

| `presenter` | 振る舞い |
|---|---|
| 今の口（`requestPermission(options:completion:)`） | 今のまま（拒否は `(false, "<文言>")`）。前面を見ない |
| `.firstActiveScene` | 前面を見ずに要求する。`.success(granted)` |
| `.foreground`・`.viewController` | 先に状態を読む。`notDetermined` でなければ要求せずに今の状態で完了（`authorized`・`provisional`・`ephemeral` は `true`）。`notDetermined` なら前面を確かめ（落ち着きは求めない。第 1 部 5.13.2）、前面でなければ `notForeground`、前面なら要求する |
| 失敗 | `requestAuthorization` の `Error` は `authorizationFailed(FailureDetail)` |
| 重ねた呼び出し | それぞれの完了をそれぞれに返す（今と同じ） |
| 判定する所 | Manager は `NotificationPresentationGate`（Presentation、`@MainActor`）に委ねる。gate が main で状態を読み（`GetAuthorizationStatusUseCase`）、要るときだけ前面を確かめ、`RequestNotificationPermissionUseCase` を呼ぶ。UseCase はデータの操作だけで前面を知らない（SR-17） |
| 選択肢 | 既定は今と同じ `[.alert, .sound, .badge]`。システムが設定の App にアプリ内の通知の設定へのリンクを出すのは `.providesAppNotificationSettings` を付けて求めたアプリだけなので、`openSettingsFor` を確かめるサンプルのボタン（SA-13）はこれを付けて求める（SR-11） |

#### 8.5.5 設定の画面と port の形

- `openNotificationSettings(presenter:completion:)`: `.firstActiveScene` は前面を確かめずに開く（今の `openNotificationSettings()` と同じ）。`.foreground`・`.viewController` は前面でなければ `notForeground`（判定は 8.5.4 と同じ gate。SR-17）。開くのは `UIApplication.open(openNotificationSettingsURLString)`。`false` が返れば `openSettingsFailed`。今の `openNotificationSettings()` は今のまま（結果を捨てる）
- `NotificationRepository`（public の port）の `openNotificationSettings()` を `openNotificationSettings() async -> Bool` に、`registerCategory`・`removeCategory` は形を変えず中を store に委ねる。port の形が変わるので、利用者が実装していれば組めなくなる（3.3 の破壊的の行。README 4.1 の 0e と同じ扱い。SR-8）
- `NotificationPermissionHelper`（public）は deprecated にし、今の動作のまま残す（S-P27）。DocC の `NotificationError.unknown` を `authorizationFailed` に直す

#### 8.5.6 category（S-P14）と 1.x の通知（S-P17）

- `NotificationCategoryQueue`（プロセスで 1 つの `static let`。`NotificationRepositoryImpl` をいくつ作っても同じ列を使う。SR-18）の規則（SR-1）:

| 規則 | 内容 |
|---|---|
| 届き方 | Manager の `registerCategory`・`removeCategory`（今の口も新しい口も）→ UseCase の同期の `enqueue(_:completion:)` → port の同期の `enqueueCategoryChange(_:completion:)` → 列、と呼び出しの中で同期に届く（S-P28。SR2-1）。`Task` を要求ごとに起こさない。`async` 版は `nonisolated(nonsending)` で、最初の中断の前に `withCheckedContinuation` の本体で同じ積みを呼び、`completion` で再開する（SR3-1） |
| 積む | 1 回の `Mutex` の中で、(1) 要求（`NotificationCategoryChange` と完了）を列の末尾に足し、(2) 取り出しの印（走っているか）を見て、(3) 走っていなければ印を立てて「起こす権利」を取る。`Mutex` の外で、権利を取ったときだけ 1 つの `Task` を起こす（SR2-2） |
| 取り出す | 起きた `Task` は、1 回の `Mutex` の中で、列が空なら印を下ろして終わり、空でなければ先頭を外す。`Mutex` の外で 1 件を処理し、これを繰り返す。空を見ることと印を下ろすことが同じ `Mutex` の中なので、終わり際に積まれた要求は、積む側が印の下りたのを見て新しく起こすか、取り出し側が次の回で拾うかのどちらかになる（残らない）。処理の途中で積まれた要求は、印が立っているので新しい `Task` を起こさない（2 つ目の取り出しは起きない。SR2-2） |
| 1 件の処理 | `notificationCategories()` を読む → 足すか外す → `setNotificationCategories` で書き戻す → 読み直して反映を確かめる。**この 4 つが終わるまで次の要求を取り出さない**（間に別の要求が入らない） |
| 完了 | 1 件の処理が終わったら、列は port の `completion`（`@Sendable`。どのスレッドからでも呼ばれる）を 1 回呼ぶ。**Manager がそれを受けて `DispatchQueue.main.async` で利用者の完了を 1 回積む**（`async` 版は continuation を再開するだけ）（SR3-6） |
| 順 | callback 版は呼んだ時点で積むので、同じスレッドから呼んだ順と、別のスレッドからは `Mutex` を取った順が反映の順になる。`async` 版は `nonisolated(nonsending)` なので、呼んだ側の executor の上で、その executor で呼んだ順に積む（同じ `Task` の中では `await` した順。main の `Task` を続けて起こしたときは main で動いた順）。C ABI は callback 版を main のブロックの中で呼ぶので、C から呼んだ順が main に積まれた順のまま反映の順になる（SR3-1） |
| 確認 | 読み直して反映が読めるまでの時間は MS-09 で測る。読み直しで確かめられなければ「書き戻した後」を完了にする（RK-10） |
- 1.x の通知は何もしない（S-P17）。予約・表示中のものは `identifier` で取り消せ、一覧に印の無い userInfo のまま出る。タップの行き先は 5.12.3（3.3 の動作の行）

### 8.6 Clipboard（S-P22、S-15）

| 項目 | 決め方 |
|---|---|
| 新しい口 | `loadItem(_:scope:requestBox:completion:)`（`@MainActor`。完了は今の 4 つの値の形）。箱を付け、今の読み込みを始め、今の token を箱の「閉じたときの処理」に入れる |
| 取り消し | `nonisolated public func cancelLoad(_ box: RequestBox)`。箱を取り消しで閉じ、token の `cancel()` を main に積む。完了は `(false, nil, "CLIPBOARD_CANCELLED", <文言>)` で 1 回。遅れて来た結果は閉じた箱に当たって捨てる |
| 開始の前に閉じた箱 | 読み込まずに `cancelled` で完了する（main で後で） |
| 今の口 | `loadItem(_:scope:completion:) -> ClipboardLoadToken`、`async` 版、`cancelAllLoads()` は今のまま |
| DocC | 「Unity のブリッジだけがどのスレッドからも呼べる入口」を、C ABI の受け口が main に積んでから呼ぶ形に直す（第 1 部 11.1 の 8） |
| 後ろにいるとき | C ABI も判定しない（第 1 部 5.13 の表）。OS の振る舞いを MS-08 で記録する |

### 8.7 ログ（S-P21、S-11、README 8.6）

#### 8.7.1 規則（`ios.md` に足す）

| 項目 | 規則 |
|---|---|
| 出し方 | ファイルの `private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "<型名>")`（generic でない型の中に置くなら `nonisolated private static let`。generic の型（`NotificationEventHub<Event>` など）はファイルの `private let` だけ（SR3-2））を持ち、呼ぶ所で直に呼ぶ（S-P21 の D）。generic の型、`@MainActor` の型、`nonisolated` の関数、`deinit` から使える形にする（SR2-5）。`Log` はライブラリの中では使わない |
| privacy | 補間ごとに付ける。関数名・識別子（通知・category・アクションの id）・件数・長さ・列挙・真偽値・エラーの case・`FailureDetail` は `.public`、そのほかの利用者の値は `.private`（P1-18 の capi の規則と同じ）。秘密の値は `.private` でも出さない |
| 伏せる値 | パスワード、Dialog の入力欄の値、通知の返信（`userText`）、通知の内容（`title`、`subtitle`、`body`、userInfo の値。キーは出す）、Share の内容（テキスト、URL、件名、題、ファイルの名前）、クリップボードの本文（今の `ClipboardRedaction` のまま） |
| 書き方 | `LogRedaction.redact(value)` で `<redacted, length=N>`（`nil` は `nil`）か、長さ・件数・種類だけ。今の公開の型の `description` は変えず、ログの所で伏せる。新しい型（`DialogInput`、`NotificationResponseEvent`）は `description` で伏せてよい |
| 出してよい値 | 長さ、件数、識別子（通知・category・アクションの id）、種類、列挙、真偽値、エラーの case と `FailureDetail` |
| 先頭の `Log.d` | 残す。伏せる値を持つ引数は `redact` を通すか長さだけ |
| Release | `#if DEBUG` で消さない。`.debug` は OS が保存しない |
| C ABI | P1-18 のまま（同じ規則なので直さない。SR-6） |
| 確かめ | 秘密の値は `LogRedaction` の長さ・有無だけを補間に入れる形にし、生の値を入れていないかを `grep` の照合（T-02）と UT-15 で見る。UT-15 は `OSLogStore`（今のプロセス）で読んだメッセージに番兵が無いことを見るので、`.private` で入れた秘密は見つけられない（伏せて見えるため）。その分は `grep` の照合とレビューで守る |

#### 8.7.2 1b で直す今のログ

| 場所 | 今 | 直し方 |
|---|---|---|
| `IosDialogManager` の先頭のログ（`title`・`message`・placeholder は出してよい。入力の値は今は出していない） | 出していない | 新しい芯の入力の値を出さないことを UT-15 で確かめる |
| サンプルの `IosLibraryExampleApp`・`NotificationEventLog`（`userText`） | 返信の全文 | 長さだけ（サンプルの直し。SA-07） |
| `ShareRepositoryImpl.present`（`subject`） | 件名の全文 | 有る・無しと長さ |
| `NotificationRepositoryImpl` の `show`・`schedule`（`trigger` は出してよい） | 内容は出していない | userInfo の値を出さないことを UT-15 で確かめる |
| `IosShareManager.swift:81`（`Log.e(TAG, "[share] error: \(error)")`） | `ShareError` の値（URL・パス） | case の名前だけ（SR-7） |
| サンプルの `DialogSampleView.swift:169`（テキスト入力の値）と `:198`（ユーザー名とパスワード） | 入力の全文とパスワード | 長さだけ（サンプルの直し。SA-16。SR-7） |
| `Log.d` の全呼び出し（33 ファイル、164 か所） | - | 案 D の書き換えと同時に、上の伏せる値の名前が補間に入っていないかを `grep` の照合で洗う（T-02） |

### 8.8 プライバシーマニフェスト（D-18）

#### 8.8.1 使っている理由の申告が要る API の棚卸し

`ios/IosLibrary/IosLibrary/` を Apple の一覧（ファイルの時刻、システムの起動からの時間、ディスクの空き、有効なキーボード、`UserDefaults`）で `grep` した結果（2026-10-31）。

| API の種類 | 使っている所 | 理由 |
|---|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `Clipboard/Data/File/ClipboardTemporaryFileStore.swift:92,96`（`.contentModificationDateKey`。`FileManager.temporaryDirectory` の下の自分のフォルダ） | `C617.1`（アプリのコンテナの中のファイルの時刻） |
| `NSPrivacyAccessedAPICategorySystemBootTime` | 無し | - |
| `NSPrivacyAccessedAPICategoryDiskSpace` | 無し | - |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | 無し | - |
| `NSPrivacyAccessedAPICategoryUserDefaults` | 無し | - |

#### 8.8.2 中身と確かめ

- `NSPrivacyTracking` は `false`、`NSPrivacyTrackingDomains` は空、`NSPrivacyCollectedDataTypes` は空（ライブラリは利用者のデータを集めない）、`NSPrivacyAccessedAPITypes` は上の 1 つ
- `plutil -lint` を通す。サンプルのアーカイブのプライバシーのレポートに、`IosLibrary` の FileTimestamp と C617.1 が出ることを確かめる（MS-10）
- 棚卸しの `grep` を 1b の終わり（T-21）にもう一度流し、増えていないことを結果に書く。照合の自動化は 2b の `check_ios_dist.py`（README 7.3）

### 8.9 第 2 部への申し送り

| 項目 | 内容 |
|---|---|
| 呼ぶ先 | C ABI の受け口は機能ごとの Manager（`IosDialogManager`・`IosShareManager`・`IosNotificationManager`・`IosClipboardManager`）だけを呼ぶ。取り消しは `cancel(_:)`・`cancelLoad(_:)`。箱は受け付けの時点で `RequestBox()` で作る |
| `presenter` | Dialog・Share・権限の要求・設定の画面には `.foreground` を渡す（P1-11） |
| 完了の形 | Dialog・Share・権限・設定の画面は `Result` の callback 版、通知の操作は `async throws` 版を main actor の `Task` で待つ（第 1 部 5.6）。**例外は category の登録と削除で、callback 版（`registerCategory(_:completion:)`・`removeCategory(identifier:completion:)`）を main のブロックの中で呼ぶ**（同期に積み、C から呼んだ順を保つ。SR3-1）。一覧は `Sendable` の型（S-P25）で、userInfo は `userInfoValues` の値の木を使う |
| エラーの写し | 10 章の表の case と名前。番号は `scripts/c_abi_error_numbers.json`（P1-7） |
| 既定の値 | 0 で埋めた構造体の意味: Dialog の `enableConfirmWhenEmpty` などの向き（18.1 の 5）、通知の `repeats`・`notifyOnEntry`・`notifyOnExit`・`interruptionLevel`（B16）、sound（B12） |
| イベント | `responses`・`settingsRequests` に種類ごとに 1 つの受け手を足し、外さない（第 1 部 5.12.7） |
| 監視 | Clipboard の変更の監視の分配（S-P22） |
| 戻り値の無い操作 | 完了を返す形にするなら、`IosLibrary` に `async` 版を足す（3.4） |
| 全件の消去 | `cancelAll`・`removeAllDelivered` はホストの通知まで消す（3.4。SR-25）。C のヘッダーの Doxygen に書く |

## 9. API の一覧と同期・非同期のレイヤー対応表

足す口と、形を変える口だけを挙げる。「C ABI」の列は第 2 部の受け口がどう呼ぶか。

| 操作 | System API と実行方式 | Repository / 実装 | UseCase | Manager callback | Manager native | C ABI | thread | 取り消し・資源の持ち主 | 方式を変える理由 |
|---|---|---|---|---|---|---|---|---|---|
| Dialog を出す | `present`（main、非同期の完了） | `AlertDialogPresenter` | `ShowDialogUseCase` | `IosDialogManager.show(_:presenter:requestBox:completion:)`（main で 1 回） | `show(_:presenter:) async throws -> DialogAnswer` | 完了つきの操作（受け付けで箱を作る） | どれでも、完了は main | `cancel(_:)`、箱 | 利用者の操作を待つ |
| Dialog の取り消し | `dismiss`（main） | 箱の閉じたときの処理 | 置かない | - | `cancel(_:)`（同期、積む） | 取り消し | どれでも | 箱 | 即時の control |
| 新しい定義の前面 | `connectedScenes`（同期、main） | `ForegroundLocator` | 置かない | - | `foregroundViewController()` | 使わない（`presenter` を渡す） | main actor | - | - |
| Share | `present` と `completionWithItemsHandler` | `ShareSheetPresenter` | `ShareContentUseCase` | `share(content:presenter:completion:)` | `share(content:presenter:) async throws` | 完了つきの操作 | どれでも、完了は main | 箱（取り消しは出さない） | - |
| delegate を入れる | `UNUserNotificationCenter.delegate`（同期） | `NotificationDelegateInstaller` | 置かない | - | `installDelegate()`（同期） | `ntk_notification_install` | main スレッドだけ | proxy（解放しない） | D-4 の同期の例外 |
| 入れたか | - | `Atomic` | 置かない | - | `isDelegateInstalled` | `NOT_INITIALIZED` の判定 | どれでも | - | - |
| 通知のイベント | delegate（スレッドは文書に無い） | proxy、router | 置かない | `responses`・`settingsRequests` の受け手 | - | イベントの登録 | main | 登録の `remove()` | - |
| 起動のきっかけ | delegate | router | 置かない | - | `launchResponse()` | 取得（形は第 2 部） | main actor | - | - |
| 通知の表示・更新・予約 | `add`（async throws） | `NotificationRepositoryImpl` | 今の UseCase | 今の口（文言は固定） | 新しい `async throws` | 完了つきの操作 | どれでも、完了は main | - | 型のあるエラー（S-P13） |
| 権限の要求 | `requestAuthorization`（async throws） | 同上と `NotificationPresentationGate`（前面の判定） | `RequestNotificationPermissionUseCase`（新） | `requestPermission(options:presenter:completion:)` | `requestPermission(options:presenter:) async throws -> Bool` | 完了つきの操作 | 同上 | 取り消しは出さない | 前面の判定（S-13） |
| 設定の画面 | `UIApplication.open`（async） | 同上 | `OpenNotificationSettingsUseCase`（新） | `openNotificationSettings(presenter:completion:)` | `openNotificationSettings(presenter:) async throws` | 完了つきの操作 | 同上 | - | 開けたかを返す |
| category の登録・削除 | `notificationCategories`（async）と `setNotificationCategories`（同期） | `NotificationCategoryQueue`（プロセスで 1 つの FIFO）と port の同期の `enqueueCategoryChange` | 今の UseCase に同期の `enqueue(_:completion:)` を足したもの（S-P28） | `registerCategory(_:completion:)`・`removeCategory(identifier:completion:)`（呼んだ時点で積む） | `nonisolated(nonsending)` の `async` 版（最初の中断の前に積む） | 完了つきの操作。callback 版を main のブロックの中で呼ぶ | どれでも（同期に積む）、完了は main | 1 つの取り出しで直列 | 反映の後に完了、呼んだ順を保つ（S-P14、S-P28） |
| Clipboard の読み込み | `NSItemProvider` の読み込み（非同期） | `ClipboardItemLoaderImpl` | `LoadItemUseCase` | `loadItem(_:scope:requestBox:completion:)` | 今の `async` 版 | 完了つきの操作 | main actor、完了は main | `cancelLoad(_:)`、箱 | 要求ごとの取り消し（P1-24） |

## 10. ドメインエラーの一覧と C ABI への写しの規則

### 10.1 安定した case（S-7、S-P7）

| 型 | case | 出る場面 | 写す C の値の名前（番号は第 2 部） |
|---|---|---|---|
| `DialogError` | `canceled` | `cancel(_:)` | `CANCELED` |
| `DialogError` | `dismissedBySystem` | 見張り（外から閉じた、scene が切れた） | `CANCELED_BY_SYSTEM` |
| `DialogError` | `notForeground` | 前面が無い | `NOT_FOREGROUND` |
| `DialogError` | `presentationFailed` | 2 回目も落ち着かない、UIKit が断った | 表示の失敗（Android の `SHOW_FAILED` に合わせるかは第 2 部） |
| `DialogError` | `invalidRequest` | 使い回した箱 | `INVALID_PARAMETER`（C の受け口は箱を使い回さないので届かない） |
| `ShareError` | `noValidItems`、`invalidURL(String)`、`imageLoadFailed(path:)`、`fileNotFound(path:)` | 今と同じ | 入力の誤り（受け付けの後に分かるので完了の値。名前は第 2 部） |
| `ShareError` | `noRootViewController` | `.firstActiveScene` で見つからない（今と同じ） | `NOT_FOREGROUND` |
| `ShareError` | `notForeground` | `.foreground`・`.viewController` で前面が無い | `NOT_FOREGROUND` |
| `ShareError` | `presentationFailed` | 落ち着かない、UIKit が断った（前は `presentationFailed(Error)`） | 表示の失敗 |
| `ShareError` | `dismissedBySystem` | 見張り | `CANCELED_BY_SYSTEM` |
| `ShareError` | `activityFailed(FailureDetail)` | `completionWithItemsHandler` の `error`（前は `presentationFailed(Error)`） | 活動の失敗（名前は第 2 部） |
| `NotificationError` | `permissionDenied` | 今の `NotificationPermissionHelper.requestPermission`（今と同じ） | `PERMISSION_DENIED` |
| `NotificationError` | `attachmentLoadFailed(identifier: String, detail: FailureDetail)` | 添付を作れない（前は `attachmentLoadFailed(Error)`） | 添付の失敗（名前は第 2 部） |
| `NotificationError` | `addRequestFailed(FailureDetail)` | `add` の失敗（前は `addRequestFailed(Error)`） | 要求の失敗（名前は第 2 部） |
| `NotificationError` | `setBadgeCountFailed(FailureDetail)` | バッジ（前は `setBadgeCountFailed(Error)`） | バッジの失敗 |
| `NotificationError` | `authorizationFailed(FailureDetail)` | `requestAuthorization` の失敗（前は `unknown(Error)`） | 権限の要求の失敗 |
| `NotificationError` | `reservedUserInfoKey` | 印のキー（P1-9） | `INVALID_PARAMETER`（C では入口の戻り値。第 1 部 R-32） |
| `NotificationError` | `invalidUserInfo` | property list にできない（S-P15） | `INVALID_PARAMETER` |
| `NotificationError` | `notForeground` | 権限の要求（未決）と設定の画面 | `NOT_FOREGROUND` |
| `NotificationError` | `openSettingsFailed` | 設定の画面を開けない | 開けない（名前は第 2 部） |
| `NotificationError` | `delegateNotInstalled` | 受け手の登録と起動のきっかけ（P1-6） | `NOT_INITIALIZED` |
| `ClipboardError` | 今の 24 case（変えない） | 今と同じ | 1 対 1（第 2 部） |

消す case: `NotificationError.permissionNotDetermined`・`attachmentInvalidURL`（どこからも投げていない。v2 で足した。SR-13）、`NotificationError.unknown(Error)`、`ShareError.unknown(Error)`（どこからも投げていない）。

`ShareError` の `invalidURL`・`imageLoadFailed`・`fileNotFound` の `errorDescription` は、今と同じく URL とパスを含む（S13〜S16 の UI テストが全文で比べる）。Share の内容は秘密の値なので、この文言はログに出さず、ログには case の名前だけを出す（8.7.2。SR-7）。

### 10.2 写しの規則

| 規則 | 内容 | 出典 |
|---|---|---|
| 1 つの case に 1 つの値 | 上の表のどの case も、ちょうど 1 つの C の値に写す。表に無いものだけ `UNKNOWN`。Swift の `CancellationError` は C の値に写さない: Dialog・Share・権限・設定の画面は C の受け口が `Result` の callback 版を使い、通知の操作の `async throws` 版は C の受け口が `Task` を取り消さないので来ない（8.9。SR2-11） | 第 1 部 5.10 |
| 詳細は出さない | `FailureDetail`・パス・URL は C に渡さず、`os_log` に出す。`system_code` は 0 | D-13 |
| 文言は出さない | `errorDescription` は Swift の利用者とログのためだけ | 第 1 部 5.10 |
| 入口と完了 | Swift では、受け付けた後に分かるものはすべて完了の失敗。C の受け口は、同じ検査（予約したキー、userInfo の型）を入口で先に行い戻り値で返してよい | AP-19 |
| 番号 | `scripts/c_abi_error_numbers.json` と第 2 部（P1-7） | P1-7 |

## 11. 第 1 部 9.1 の条件との照合

| # | 条件 | この設計書 |
|---|---|---|
| S-1 | delegate を入れる公開の口（main だけ、同期、待たない、冪等、入れ直し、結果を返す、初めて入れたときに `didBecomeActive` の受け手） | 8.3.1 |
| S-2 | 転送の delegate（強く持つ、前を weak、3 つを常に実装、`responds(to:)`、見分け方、転送の規則、包み、循環の防止、KVO、`Mutex` の中で外を呼ばない） | 8.3.2、S-P20 |
| S-3 | 印を付ける、同じキーを拒む、返す userInfo から外す | 8.3.3 |
| S-4 | イベントの口（複数の受け手、保つ規則、起動のきっかけ、main に積む、completion は渡すか保つかの後、C の受け口が最初の登録の挿入のブロックで受け取れる） | 8.4、S-P10〜S-P12 |
| S-5 | 完了がちょうど 1 回（ボタン、取り消し、表示の失敗、UIKit が知らせる終わり方、`showLoginDialog` の失敗、循環参照の直し、ViewController を強く持たない） | 8.1.3、8.1.4、6.3.4 |
| S-6 | `presenter` の 3 つの値、要求の箱の引数、新しい定義の前面を返す別の名前の口、表示の手順を 1 か所、基点、前面でない・表示の失敗・外から閉じたを別の case | 6.3、8.1、8.2、S-P1〜S-P4。**違い**: 箱の引数は取り消しのある Dialog（と Clipboard の読み込み）だけに付け、Share・権限の要求・設定の画面には付けない。取り消しを出さない（P1-24）ので外から箱を渡す理由が無く、口の中で箱を作る（第 1 部 5.13.1 の「渡されなければ口が作る」。SR-19） |
| S-7 | 安定した case、C の値に 1 対 1 | 10 章 |
| S-8 | 受け手やコールバックを呼ぶ間に鍵を持たない | 6.2、8.3.2 |
| S-9 | C ABI が要る口はすべて公開（`@_spi` なし） | 付録 A |
| S-10 | `openSettingsFor` をイベントに | 8.3.2、8.4.1 |
| S-11 | ログの規則（秘密を伏せる）を capi と合わせる | 8.7、S-P21 |
| S-12 | 1.x の通知の扱いと更新のテスト | 8.5.6、S-P17、13.4 |
| S-13 | 権限の要求も `presenter`。未決のときだけ前面を要し、落ち着きは求めない。重ねても上書きされない | 8.5.4 |
| S-14 | proxy が一度でも入ったかを読む公開の口 | 8.3.1 |
| S-15 | Dialog を要求ごとに閉じる、Clipboard の読み込みを要求ごとに取り消す。箱は呼ぶ前から作れ、取り消しはどのスレッドからでも待たずに閉じ、閉じる処理を main に積む。表示の途中なら `present` の完了の中で閉じる。上に画面が重なっていれば閉じない | 6.3.2、8.1.3、8.6、S-P2、S-P22 |
| S-16 | `CompletionOnce`・要求の箱と見張り・関連オブジェクトの鍵を P1-17 の一覧に入れ、理由と TSan のテスト。前の delegate に渡す closure は `@unchecked` にしない | 6.3.2、6.3.4、8.3.2、UT-03、UT-21。ほかに `@unchecked` は足さない（proxy は `Mutex` だけを持つ `Sendable`、イベントは値の木。S-P11） |

## 12. サンプルアプリ（S-P23、README 5 章の 1b の行）

今のボタンと結果の行は変えずに残す（0c の UI テストの基準）。足すボタンと結果の行の識別子は、UI テストの設計書 5.1 の一覧に足し、I1a〜I1d の照合（一覧と完全に一致するか）を通す（13.3。SR-10）。新しい口のボタンは、画面の中の新しい節（「Swift API (2.0.0)」）に置き、識別子は今の接頭辞（`dialog.button.`、`notification.button.`、`share.button.`、`clipboard.`）に続ける。入力欄は足さない（`common.md`）。細かい画面の設計が要れば `design-sample-app` で書く。

| ID | 画面 | 足すもの | 確かめること |
|---|---|---|---|
| SA-01 | Dialog | 6 種の `show(_:presenter:.foreground)` のボタンと、結果の行（`[show.<種類>] success button=<…> title=<…> input=<長さ>` / `failure <case>`） | 新しい口の結果（D16） |
| SA-02 | Dialog | 「同じ回に 2 つ」（1 つのボタンで 2 回 `show`） | P1-12（D17） |
| SA-03 | Dialog | 「出して 1 秒後に取り消し」と「出して、上に別の画面を重ねてから取り消し」 | P1-24（D18、D19） |
| SA-04 | Dialog | 「出して 1 秒後にサンプルが外から `dismiss`」 | G-7、`dismissedBySystem`（D20） |
| SA-05 | 全機能 | `#if DEBUG` の「3 秒後に出す」（後ろにいるまま操作を起こすテスト専用の口。第 1 部 6 章） | `notForeground`（D21、S18、N42） |
| SA-06 | Notification | 起動の処理を既定で `installDelegate()` → `responses.addListener` に替える。試験の形 `legacyReceivers`（SA-18）で、今の受け手と `setup()` の経路にする（SR-10、SR2-3）。最後のイベントの表示を今のまま保つ（`NotificationEventLog`）。2 人目の受け手を足す・外すボタンと、受け手ごとの受けた回数 | N25〜N33 が今のまま通る、今の受け手の経路（N43〜N45）、複数の受け手（N35） |
| SA-07 | Notification | 返信の全文をログに出さない（長さだけ）。最後のイベントの表示は今のまま（UI テストが `userText` を読む） | 8.7.2 |
| SA-08 | Notification | 試験の形「受け手を遅らせる」（SA-18）で、受け手を足すのを 3 秒遅らせる。起動のきっかけ（`launchResponse()` と `isLaunchResponse`）の表示 | 保ち（N36）、起動のきっかけ（N37） |
| SA-09 | Notification | 予約したキーを入れた通知、property list でない userInfo の通知のボタン | P1-9、S-P15（N38） |
| SA-10 | Notification | `registerCategory(_:completion:)` で、完了の後に結果の行を出すボタン | S-P14（N39） |
| SA-11 | Notification | `settingsRequests` の最後のイベントの表示 | P1-10（N40。MS-07） |
| SA-12 | Notification | 起動の引数 `-ntkSampleHostDelegate`（SA-18 の形と同じくファイルに残す）で、ライブラリより前にホストの delegate（`didReceive` と `willPresent` を実装し、ホストの印の通知を受けたら結果の行に出す）を入れる。ホストの通知を出すボタン | 転送（N41） |
| SA-13 | Notification | `requestPermission(options: [.alert, .sound, .badge, .providesAppNotificationSettings], presenter: .foreground)` と `openNotificationSettings(presenter: .foreground)` のボタン。MS-07 と N40 は、新しく入れたアプリでこのボタンから先に求める（SR-11） | S-13（N42）、N40 |
| SA-14 | Share | `share(content:presenter:.foreground)` のボタン、外から閉じるボタン | S17〜S19 |
| SA-15 | Clipboard | `loadItem(_:scope:requestBox:completion:)` で読み、すぐ `cancelLoad` するボタンと、開始の前に取り消した箱で読むボタン | P1-24（CB5、CB6） |
| SA-16 | Dialog | ログインの結果の行でパスワードを出さず長さだけにする（今の口のボタン） | README 1.4（D12 の期待値を変える） |
| SA-17 | 全体 | サンプルのログを自分の `os.Logger` に替える（`Log` が deprecated になるため。S-P21） | S-P21 |
| SA-18 | Notification | 試験の形（`none`・`legacyReceivers`・`delayListener`）を起動の引数 `-ntkSampleTestMode <形>` で受け、アプリのコンテナ（Application Support）の小さなファイルに書く。引数の無い起動ではファイルを読む。最後のイベントの表示に、受けた経路（`path=hub` / `path=legacy`）と、そのプロセスが読んだ形を `accessibilityValue` で足す（見た目は変えない）。UI テストの基底は起動のたびに形を明示する（`none` も書いてファイルを直す）。基底を通らない起動（Clipboard のテストの `XCUIApplication().launch()`、人がホームから起動したとき）は前に残した形を読むので、通知のテストは後片付け（`tearDown`）で `none` の形で 1 回起動し直してファイルを戻す（SR3-5）。`UserDefaults` は使わない（サンプルに理由の申告が要る API を増やさない）（SR2-3） | N36、N43〜N45 が狙った経路を通ったこと |

## 13. テストの設計

`IosLibraryTests` は Swift Testing（`@Test`、`common.md`）。UIKit を要るものはテストのホストのアプリの上で動かす。新しく足すテストは、守る対象を壊すと落ちることを確かめる（`common.md` の「検査の書き方」）。「壊し方」の列は確かめに使う変異。

### 13.1 単体テスト（`IosLibraryTests`）

| ID | 対象 | 中身 | 壊し方 |
|---|---|---|---|
| UT-01 | `PresenterSelection` | 3 つの値の区別。`.viewController` の closure を main で 1 回だけ呼ぶ | closure を 2 回呼ぶ |
| UT-02 | `ForegroundLocator` | 今の探し方が今の `getRootViewController()` と同じ結果。新しい定義が `foregroundInactive` と閉じかけの ViewController を扱う（偽の scene の値で） | `isBeingDismissed` の確かめを外す |
| UT-03 | `RequestBox` | 最初に閉じたものだけ、2 つ目の付けで `invalidRequest`、付ける前の取り消し、8 スレッド × 25 回の閉じる競合（TSan でも流す） | `Mutex` の外で読む |
| UT-04 | `PresentationProcedure` | 第 1 部 5.13.2 の `presenter` ごとの段（前面なし、落ち着き、待ち 1 回、2 回目の失敗、待つ間の取り消しで出さない、表示しない口は落ち着きを求めない）。UIKit を差し替えられる形にしたもの | 待ちを 2 回にする |
| UT-05 | `ReleaseWatch` | 解放で 1 回閉じる。`present` の完了の前は `presentationFailed`、後は `dismissedBySystem`。普通の結果を上書きしない。ViewController の解放に頼る組み合わせは TSan の回で skip し、理由を書く（申し送り 1 で TSan の版は解放されなかった） | 箱が閉じていても閉じる |
| UT-06 | `FailureDetail` | `NSError` の domain と code だけを取る | `localizedDescription` を入れる |
| UT-07 | `ShowDialogUseCase` と `DialogRequest` | 既定の文言、箱の使い回し、port に渡す値（Mock の port） | 既定を変える |
| UT-08 | `AlertDialogPresenter`（ホストのアプリの上） | 6 種の組み立て（ボタンの数・style・入力欄）、`.primary` の入力、`.cancel` の `input == nil`、アクションシートの基点が必ず設定される | キャンセルで入力を返す |
| UT-09 | Dialog の取り消し | 開く前・表示の途中・表示の後・上に重なったとき（閉じない）・完了の後（何もしない） | 重なっても閉じる |
| UT-10 | `IosDialogManager` の今の 7 つの口 | 今のテスト 9 件をそのまま通す。失敗が `completion(false, …)` だけで 1 回（ログインも）。ボタンの callback の値が今と同じ | `onLogin` にも失敗を返す |
| UT-11 | Dialog の `async throws` 版 | 答え、`DialogError` を投げる、`Task` の取り消しで `CancellationError` と箱の取り消し | 取り消しで箱を閉じない |
| UT-12 | `ShareSheetPresenter` | 箱が閉じたときに continuation を 1 回再開する（見張り、失敗、handler）。`activityFailed` | 見張りで再開しない |
| UT-13 | `IosShareManager` | `presenter` が渡る。今の callback 版の値が今と同じ（今のテスト 8 件）。`Result` 版の case | 今の口で `presenter` を変える |
| UT-14 | 循環参照 | Dialog を閉じた後に `UIAlertController` と observer が解放される（`weak` の参照が `nil` になる） | handler で `alert` を強く持つ |
| UT-15 | ログ | 番兵の値（パスワード、入力、返信、通知の題と本文と userInfo の値、Share のテキスト・URL・パス）で各口を呼び、`OSLogStore(scope: .currentProcessIdentifier)` で読んだこのプロセスのメッセージに番兵が無い。`.debug` が読めるかは MS-13 で確かめ、読めなければテストの間だけ `.info` に上げる口（`#if DEBUG`）を持つ。`.private` で入れた秘密は見つけられないので、`grep` の照合（T-02）が受け持つ | 1 か所で値を `.public` で補間する |
| UT-16 | `NotificationError`・`ShareError` | `NotificationError` の全 case と、`ShareError` の値を持たない case の `errorDescription` が固定で、入力の値を含まない。**例外**: `ShareError` の `invalidURL`・`imageLoadFailed`・`fileNotFound` は今と同じく URL とパスを含み、`noValidItems` を合わせた 4 つの文言が今と同じ（S13〜S16 の基準。SR-7） | 文言を変える |
| UT-17 | 印 | 付ける、外す、予約したキーを拒む（`add` を呼ばない）。**`update` で拒んだとき、今の予約が消えていない**（SR-9）。push は印があってもライブラリの通知でない（Mock の repository と router） | 消してから検査する |
| UT-18 | userInfo の検査と値の木 | property list でない値を拒む（`update` は今の予約を消さない）。値の木への変換（真偽値・実数・整数の区別と順、`Int64` を超える `UInt64`、日時、バイト列、入れ子）。往復: `ScheduledNotification`・`ActiveNotification` の `userInfo` の計算プロパティと今の受け手の辞書で、`as? Int`・`as? Double`・`as? Bool`・`as? String`・`as? Date`・`as? Data`・`as? [Any]`・`as? [String: Any]` が今と同じ値を返す。`init` が property list でない値と `String` でないキーを捨て、落ちない（SR2-4） | 作り直しを Swift の `Int64`・`Bool` にする |
| UT-19 | `NotificationDelegateRouter` | 1a delegate 3 章の組み合わせの表（メソッド 3 つ × 前の delegate の振る舞い（無し、実装しない、同期、非同期 main、非同期 背景、2 回、呼ばない、持ち続ける）× 通知の種類（ライブラリ、ホスト、1.x、push））。各組み合わせで system の completion が多くても 1 回 | 2 回目を通す |
| UT-20 | 循環の防止 | 3 つのメソッドで、最初の転送の呼び出しの中の同期の戻りを止め「誰も受けない」で扱う（`didReceive` はイベントを出す）。同じ identifier で `date` の違う配信は止めない。`openSettingsFor` の `nil` | 鍵に `date` を入れない |
| UT-21 | `CompletionOnce` | 背景のキューから呼んでも止まらない、2 回目を捨てる、呼ばれずに解放されても何もしない（TSan でも流す） | closure を main actor の文脈で書く |
| UT-22 | 起動のきっかけ | P1-22 の規則（最初の `didReceive` が最初の `didBecomeActive` より前でライブラリが扱った、ホストへ転送した、循環、入れたときに `active`） | 転送したものを起動のきっかけにする |
| UT-23 | `NotificationEventHub` | 保つ（32 を超えたら古いものから）、1 人目にだけ足す呼び出しの中で渡す、受け手の中で自分を外す（残りが次へ、無ければ保ちへ）、全員に配る、`remove` 2 回、入れていないと `delegateNotInstalled` | 足す前に保ちを外さない |
| UT-24 | 入れる口 | main 以外で `.notMainThread`（delegate が変わらない）、2 回目で前の delegate が proxy 自身にならない、差し替えの後の入れ直し、`isDelegateInstalled` | 2 回目に前の delegate を上書き |
| UT-25 | 今の受け手（deprecated） | 配るたびに呼ばれ、保ちと並びに関わらない | 今の受け手を並びに入れる |
| UT-26 | 権限の要求 | `presenter` ごとの表（8.5.4）。未決でないときは要求しない。重ねても各完了 | 未決でなくても前面を求める |
| UT-27 | 設定の画面 | 前面でない、開けない、開けた | 結果を捨てる |
| UT-28 | `NotificationCategoryQueue` | 列に internal の `NotificationCategoryCenter` の偽物を渡す（SR2-10）。8 スレッドからの並行の登録と削除で変更が失われない。同じスレッドから呼んだ順に反映される。1 件の処理の読み取りと書き戻しの間に次の要求が入らない（偽物の `categories()` を止めて、その間に 2 件目を積む）。**処理の途中で積んでも 2 つ目の取り出しが起きない**（起きた `Task` の数を数える）。**終わり際に積んでも残らない**（取り出しが空を見る直前と直後に積む形を、偽物の中の待ち合わせで作る）。完了が反映の後に main で 1 回。Manager の `async` 版を続けて 2 回待つと、呼んだ順に反映される。**main の `Task` を 8 つ続けて起こし、それぞれで `async` 版の登録と削除を呼ぶと、起こした順に反映される（300 回繰り返す）**。C ABI の形（main のブロックの中で callback 版を続けて呼ぶ）でも呼んだ順（SR3-1）。`NotificationRepositoryImpl` を 2 つ作っても同じ列（SR-1、SR-18、SR2-1、SR2-2） | 空を見るのと印を下ろすのを別の `Mutex` の区間にする。`async` 版の `nonisolated(nonsending)` を外す |
| UT-29 | `async throws` 版の通知の操作 | 委ねる UseCase と同じ結果とエラー | エラーを写し違える |
| UT-30 | Clipboard の箱 | `cancelLoad` で `cancelled` が 1 回、遅れた結果を捨てる、開始の前の取り消し、背景のスレッドからの取り消し（TSan でも流し、閉じたときの処理が main actor を継がないこと。SR-3） | 遅れた結果を通す |
| UT-31 | 今の呼び出しの型検査（S-P26） | テストのソースに、`async` の関数の中から今の口を `completion` を書いて呼ぶ形（組める）を置く。`completion` を書かない形が組めないことは、`swiftc -typecheck` に渡す小さなファイルで確かめ、その一覧を 3.3 と移行の手引きに写す（T-21） | `completion` の既定の `nil` を外す |
| UT-32 | `Sendable` の結果（S-P25） | main actor の `Task` から、`getScheduled()`・`getDelivered()`・`requestPermission(options:presenter:)` などの `async` 版を待つテストが Swift 6 で組めて通る（SR-2） | 一覧の型の `Sendable` を外す |

- 移すロジックに当たるブリッジのテスト（ブリッジのテストの記録）の扱い: JSON の解析のテスト（Clipboard 26 件、Notification 41 件、Share 7 件）は移すロジックが無いので書き直さない（README 1.2。JSON は捨てる）。`UnityIosClipboardManagerCallbackContractTests` の 9 件（main で 1 回、不正な要求も 1 回）は C ABI のテスト（2b）で置き換える。`parseContentNoSoundDefaultsToDefault` は `NotificationContentTests` に既定の確かめがあるかを見て、無ければ足す。対応を 1b の結果に書く

### 13.2 UI テスト（`IosLibraryExampleUITests`）

番号は UI テストの設計書に続ける。区分（`systemui`、`sharesheet`、`clipboard`）は UI テストの設計書の U-9 の決まりで宣言する。

| ID | 操作 | 確かめる内容 | 環境 |
|---|---|---|---|
| D16 | SA-01 の 6 種を 1 回ずつ（アラートは OK、確認は Yes と No、アクションシートは選択肢、テキスト入力は文字を入れて OK、ログインは `credentials`） | 結果の行が `success` で、`input` は長さだけ | 両方 |
| D17 | SA-02 | 1 つ目を閉じると（または上に重なって）2 つ目も出て、2 つとも結果の行が 1 回ずつ（G-4 で重なり方を確かめる） | シミュレーター（両方の OS） |
| D18 | SA-03（1 秒後に取り消し） | Dialog が消え、`failure canceled` が 1 回 | 両方 |
| D19 | SA-03（上に重ねてから取り消し） | 上の画面は残り、Dialog も残り、`failure canceled` が 1 回。残った Dialog のボタンを押しても結果の行が増えない | 両方 |
| D20 | SA-04 | `failure dismissedBySystem` が 1 回（申し送り 1 で通常と ASan の版は約 0.5 秒で来た。TSan の回では流さない） | シミュレーター |
| D21 | SA-05 → ホーム | `failure notForeground` が 1 回 | シミュレーター（`systemui`） |
| D22 | Control Center を引き出した間に `.foreground` の Dialog（SA-05 の遅れを使う） | 出る（G-6。MS-02） | シミュレーター（`systemui`） |
| D23 | iPad Pro 11-inch (M4) / 18.3 で D6 と SA-01 のアクションシート | 落ちずに出る（基点。P1-20） | iPad のシミュレーター |
| N34 | 起動 | 結果の行に `installDelegate: installed` | 両方 |
| N35 | SA-06 で 2 人目を足す → N25 と同じ操作 | 2 人とも 1 回ずつ受ける。外した後は 1 人だけ | 両方（`systemui`） |
| N36 | 試験の形 `delayListener`（SA-18）で起動して N30 と同じコールドスタート | 受け手を足した後に 1 回だけ届き、`isLaunchResponse=true`。システムが起こしたプロセスが `delayListener` を読んだこと（SA-18 の `accessibilityValue`） | 両方（`systemui`） |
| N37 | N36 の後 | `launchResponse()` の表示が同じ通知。普通の起動では `nil` | 両方（`systemui`） |
| N38 | SA-09 | どちらも `❌` と case の名前（`reservedUserInfoKey`、`invalidUserInfo`）。通知は出ない | 両方 |
| N39 | SA-10 → 完了の後すぐ ShowImmediate → 長押し | 5 秒の予約を使わなくてもアクションが出る（MS-09 で反映を確かめた場合） | 両方（`systemui`） |
| N40 | 設定の App のサンプルの通知の設定から「アプリ内の通知の設定」を開く | `settingsRequests` の最後のイベントが出る（MS-07 でシステムから呼ばせられた場合。だめなら人の確認 HC10 を足す） | シミュレーター |
| N41 | `-ntkSampleHostDelegate` で起動 → ホストの通知とライブラリの通知を出してタップ | ホストの通知はホストの結果の行だけ、ライブラリの通知はライブラリの最後のイベントだけ | 両方（`systemui`） |
| N42 | SA-05 → ホーム（権限が未決の新しいインストール、`reinstall`） | `failure notForeground`。ダイアログは出ない | シミュレーター（`systemui`、`reinstall`） |
| S17 | SA-14 → Copy | `success completed=true` | 両方（`sharesheet`、`clipboard`） |
| S18 | SA-05（Share）→ ホーム | `failure notForeground` | シミュレーター |
| S19 | SA-14 の外から閉じる | `failure dismissedBySystem` が 1 回（申し送り 1 で `completionWithItemsHandler` は呼ばれなかったので、見張りだけが閉じる。解放までの時間は MS-03） | シミュレーター |
| N43 | 試験の形 `legacyReceivers` で N25 と同じ操作 | 今の受け手の経路で最後のイベントが N25 と同じで、`path=legacy`（SR-10、SR2-3） | 両方（`systemui`） |
| N44 | 試験の形 `legacyReceivers` で N29 と同じ操作 | `kind=textInput`、`userText=hello reply`、`path=legacy` | 両方（`systemui`） |
| N45 | 試験の形 `legacyReceivers` で起動してから N30 と同じコールドスタート | 今の受け手の経路で N30 と同じで、システムが起こしたプロセスが `legacyReceivers` を読み、`path=legacy`（ファイルに残した形が引数の無い起動で効いたことを確かめる。MS-14） | 両方（`systemui`） |
| CB5 | SA-15（すぐ取り消し） | `CLIPBOARD_CANCELLED` が 1 回 | 両方（`clipboard`） |
| CB6 | SA-15（開始の前の取り消し） | 読み込まずに `CLIPBOARD_CANCELLED` が 1 回 | 両方（`clipboard`） |

### 13.3 変える今の期待値

| ID | 今の期待値 | 1b の後 | 理由 |
|---|---|---|---|
| D12 | 結果の行にパスワードが平文 | `password: <length=7>` | SA-16、README 1.4（UI テストの設計書の D12 の注） |
| N25〜N33 | 今の受け手で記録 | 同じ内容（記録の元をイベントの口に替える） | SA-06。期待値は変えない |
| 通知の操作のエラーの経路 | `❌` と `[marker] error: ` までを比べる | 同じ（文言は固定になるが、比べ方は変えない） | S-P7 |
| I1a〜I1d（識別子の一覧と完全に一致するか） | UI テストの設計書 5.1 の一覧 | SA-01〜SA-16 で足す識別子を、UI テストの設計書 5.1 の一覧（と `ClipboardSampleIdentifiers` などの定数）に足す。一覧を直すのは UI テストの設計書の側（README ではない） | SR-10 |
| 3.7 の「全ボタンが押されること」 | 0c のボタン | 足したボタンも、どれかの UI テストが押すことを照らす（押さないボタンを足さない） | SR-10 |

ほかの 0c の UI テスト（Dialog の D1〜D15、Share の S1〜S16、Clipboard の 26 件、通知の残り）は期待値を変えない。

### 13.4 全体の実行と更新のテスト

- 各コミットの後は、ビルドと単体テストと、直した機能の UI テストだけをシミュレーターで流す（README 7 章、利用者の決まり）
- 1b の終わり（T-21）に、シミュレーター（iPhone 17 / 26.2）で全件を流し、0g の後の基準（320 件成功、意図した skip 1 件）と比べる。足したテストと期待値を変えたテストは理由を書く
- 実機（iPhone XS / 18.7.2）の 60 件の基準の取り直しは、**毎回利用者の許可を得てから**行う（`agent-rules/device-testing.md`）。この設計書は実機での実行を前提にしない
- 更新のテスト（README 7 章。1.13.0 のサンプルから 2.0.0 へ）は 1b の後に別に設計する（UI テストの設計書 8.4）。S-P17 の扱いをその期待値にする

## 14. 1b でシミュレーターで測ること（第 1 部 G-4・G-6・G-7 など）

結果は 1b の作業の記録（`results/`）に書き、決まりが変わるものは README と第 1 部に反映する。

| ID | 測ること | 環境 | 方法 | 結果で変わるもの |
|---|---|---|---|---|
| MS-01 | G-4: `present` の直後の `presentingViewController`（6.3.3 の補い。SR-16）、`transitionCoordinator` が取れるか、coordinator の completion の中で落ち着いているか、表示の途中の `dismiss` が無視されるか。**申し送り 1 で済んだもの**: 起動の直後（`didFinishLaunching` の中）の表示は出た、同じ回の 2 つは 2 つ目が上に出た（`IosLibrary` の手順で 1 回だけ確かめ直す） | iPhone 17 / 26.2、iPhone 16 / 18.3 | サンプルの SA-02・SA-03 と小さなテスト | 6.3.3 の待ちと補い（`presentingViewController` が直後に設定されないなら補いを外す）。D17 の期待値 |
| MS-02 | G-6: `foregroundInactive` の間に `UIAlertController` と `UIActivityViewController` を出せるか（アラートは申し送り 1 の `didFinishLaunching` の中で出た。Share と、Control Center を引き出した間はまだ）。`isKeyWindow` が真の window がアプリで 1 つか（iPad の複数の window） | iPhone 17 / 26.2、iPad Pro 11-inch (M4) / 18.3、iPad (A16) / 26.2 | D22 と、iPad で 2 つの window を開く | 成り立たなければ `.foreground` を `foregroundActive` だけにし、P1-11 と 6.3.1 を直す |
| MS-03 | G-7: **申し送り 1 で済んだもの**: 外から閉じたアラートは通常と ASan で約 0.5 秒で解放、TSan で 15 秒たっても解放されない。外から閉じた Share は `completionWithItemsHandler` が呼ばれない。**残り**: 外から閉じた Share の ViewController がいつ解放されるか、UIKit が表示を断った ViewController がいつ解放されるか（SR-16）、handler のスレッド、Share で活動を選んだ間に解放されないか、scene を切ったときの handler と解放、TSan で解放されない理由 | iPhone 17 / 26.2、iPad / 18.3 | SA-04、SA-14、iPad で scene を閉じる | 解放されない経路を約束の外に移す（P1-14）。D20・S19 の期待値 |
| MS-04 | G-7: 後ろから `UIApplication.open` を呼んだとき、権限が未決で後ろにいるときの `requestAuthorization` | iPhone 17 / 26.2 | SA-05 | 8.5.4・8.5.5 の判定 |
| MS-05 | G-7: scene のアプリでの `UIApplication.didBecomeActiveNotification` の順（P1-22） | iPhone 17 / 26.2、iPhone 16 / 18.3（サンプルは scene を使う） | N36 と記録のログ | P1-22 の規則（scene の通知を見るか） |
| MS-06 | R-23: main スレッドの上の `DispatchQueue(label:).sync` の中で `MainActor.assumeIsolated` が止まらないか（26.x） | iPhone 17 / 26.2 | 小さな単体テスト | 第 1 部 1.3 の判定の書き方 |
| MS-07 | `openSettingsFor` をシステムから呼ばせられるか（Xcode で組んだサンプル。新しく入れたアプリで、SA-13 のボタンから `.providesAppNotificationSettings` を付けて先に求める。SR-11） | iPhone 17 / 26.2 | N40 | 呼ばせられなければ HC10（人の確認）と router の単体テストだけにする |
| MS-08 | 後ろにいるときの `UIPasteboard` の読み込み（第 1 部 5.13 の Clipboard の行） | iPhone 17 / 26.2 | SA-05 と CB の操作 | 記録だけ |
| MS-09 | `setNotificationCategories` の後の `notificationCategories()` に反映が読めるまでの時間 | iPhone 17 / 26.2、iPhone 16 / 18.3 | UT-28 と N39 | S-P14 の完了の時期 |
| MS-10 | 署名なしのアーカイブ（`CODE_SIGNING_ALLOWED=NO`）でサンプルのプライバシーのレポートを作れるか、`IosLibrary` の FileTimestamp が出るか | Xcode 26.6 | `xcodebuild archive` と Organizer | 作れなければ `unity-native-plugin` の agent の Release のアーカイブで確かめる（1a-4） |
| MS-11 | G-8: 利用者のコールバックの Objective-C の例外が Swift のフレームを越えるときの振る舞い（1 回） | iPhone 17 / 26.2 | 小さなテスト（意図して落とし、crash report を写して消す） | 記録だけ（P1-16 は変えない） |
| MS-12 | G-9: `UIApplicationMain` の前に `installDelegate()` を呼んだときの振る舞い（1 回） | iPhone 17 / 26.2 | 小さなアプリ | マニュアルに書く |
| MS-13 | `os.Logger` の `.public` のメッセージが Xcode のコンソールと `log stream` に出ること、`.private` の値の見え方、`.debug` が Release で保存されないこと、`OSLogStore` で今のプロセスの `.debug` を読めるか（UT-15） | iPhone 17 / 26.2 | サンプルの Release ビルド | 8.7.1 の書き方 |
| MS-14 | バナーのタップで `terminate()` の後にシステムがサンプルを起こしたとき、`launchArguments` が渡らないこと、SA-18 のファイルに残した形が読めること（1 回） | iPhone 17 / 26.2 | N45 の前に 1 回 | 渡らなければ SA-18 のファイルで足りる。渡るなら記録だけ |

実機と Unity でしか確かめられないもの（背景のアクションの completion の時期、背景に移った直後の `willPresent`、Unity の起動の順と通知のパッケージ）は、2 回目の申し送り（U-3・U-4・U-6・U-7）に任せる（P1-23）。

## 15. 作業の順番とタスク（S-P24）

### 15.1 コミットの分け方

| コミット | 中身 | タスク |
|---|---|---|
| C1 共通 | `ios.md` の規則、ログの案 D の書き換えと `Log` の deprecated、サンプルのログ、プライバシーマニフェスト、`PresenterSelection`・`RequestBox`・`FailureDetail`・表示の手順・見張り | T-01〜T-05 |
| C2 Dialog | 3 層、新しい口、今の口の載せ直し、テスト、サンプル、MS-01・MS-02（SA-02・SA-03 を使うのでここで最初に測る。結果で C1 の `.foreground` の定義や補いを直すときは、この C2 のコミットで直す。SR-14）、UI テスト | T-06〜T-09、T-22 |
| C3 Share | エラー、`presenter`、箱と見張り、テスト、サンプル、UI テスト | T-10、T-11 |
| C4 Clipboard | 箱と取り消し、DocC、テスト、サンプル、UI テスト | T-12 |
| C5 通知の delegate とイベント | router、包み、循環、proxy、入れる口、印、イベントの口、起動のきっかけ、今の受け手、サンプルの起動の処理、UI テスト | T-13〜T-16 |
| C6 通知の操作 | エラー、`async throws`、userInfo の検査、権限と設定の画面、category の列、サンプル、UI テスト | T-17〜T-19、T-23 |
| C7 測りの記録と全体 | 14 章の記録、全体の実行、README の直し | T-20、T-21 |

- 各コミットの本文は箇条書きにし、コミットの前に対象のファイルと差分を見せる（利用者の決まり。コミットは `commit-msg` の手順だけ）
- C5 は 2 回目の申し送りの結果（U-3・U-4）を見てから始める。C6 は C5 の印（8.3.3）とサンプルの起動の処理（SA-06）に依存するので、**C5 の後にコミットする**。結果を待つ間に T-17・T-18（ライブラリの部分）を先に作っておいてよいが、コミットは C5 の後の C6 にまとめる（v1 の「C6 を先にしてよい」は T-19 の依存と合わなかった。SR-14）

### 15.2 タスク

| ID | 内容 | 見積 | 依存 |
|---|---|---|---|
| T-01 | `ios.md` の 4 つの書き足し（文書）、`Log` の deprecated（中身は `print` のまま。S-P21 の Y1）、`LogRedaction`、サンプルの `os.Logger`（SA-17） | 1.0日 | - |
| T-02 | 33 ファイル 164 か所の案 D の書き換えと `privacy:`、8.7.2 の直し、`grep` の照合、UT-15 | 1.5日 | T-01 |
| T-03 | `PrivacyInfo.xcprivacy` と棚卸し、MS-10 | 0.5日 | - |
| T-04 | `PresenterSelection`・`RequestBox`・`FailureDetail` と UT-01・UT-03・UT-06 | 1.0日 | - |
| T-05 | `ForegroundLocator`・`PresentationProcedure`（補いを含む）・`ReleaseWatch` と UT-02・UT-04・UT-05 | 1.5日 | T-04 |
| T-06 | Dialog の Domain と Application（`DialogRequest`・`DialogAnswer`・`DialogInput`・`DialogError`・port・`ShowDialogUseCase`）と UT-07 | 1.0日 | T-04 |
| T-07 | `AlertDialogPresenter`（組み立て、handler、observer の解除、`weak`、取り消し、見張り）と UT-08・UT-09・UT-14 | 1.5日 | T-05、T-06 |
| T-08 | `IosDialogManager`（新しい口、`cancel`、`foregroundViewController`、今の 7 つの載せ直し）と UT-10・UT-11 | 1.5日 | T-07 |
| T-09 | Dialog のサンプル（SA-01〜SA-05、SA-16）、MS-01・MS-02、MS-03 の Dialog の分。結果で 6.3 を直す | 1.5日 | T-08 |
| T-22 | Dialog の UI テスト（D16〜D23、D12 の期待値、I1a〜I1d の一覧） | 1.0日 | T-09 |
| T-10 | `ShareError`、`ShareSheetPresenter` の手順・箱・見張り・continuation と UT-12・UT-16 の Share の分 | 1.0日 | T-05 |
| T-11 | `IosShareManager` の口、port、UT-13、サンプル（SA-14）、UI テスト（S17〜S19）、MS-03 の Share の分 | 1.0日 | T-10 |
| T-12 | Clipboard の `loadItem(…requestBox:)`・`cancelLoad`、DocC、UT-30、サンプル（SA-15）、UI テスト（CB5・CB6）、MS-08 | 1.0日 | T-04 |
| T-13 | `NotificationDelegateRouter`・`CompletionOnce`・循環の防止・起動のきっかけと UT-19〜UT-22 | 1.5日 | T-04 |
| T-14 | proxy、`installDelegate`・`isDelegateInstalled`、KVO、`didBecomeActive`、delegate の準拠を外す、UT-24、MS-05・MS-06・MS-12 | 1.5日 | T-13 |
| T-15 | 印（8.3.3）、値の木、`NotificationEventHub`、`responses`・`settingsRequests`・`launchResponse`、UT-17・UT-18・UT-23 | 1.5日 | T-14 |
| T-16 | 今の受け手と `setup()` の deprecated、UT-25、サンプルの起動の処理と試験の形（SA-06〜SA-08、SA-11、SA-12、SA-18）、MS-14、UI テスト（N25〜N37、N40、N41、N43〜N45）、MS-07 | 1.5日 | T-15 |
| T-17 | `NotificationError`、`async throws` 版、一覧の型の `Sendable`（S-P25）、userInfo の検査（入口の最初）と UT-16 の通知の分・UT-18 の一覧の分・UT-29・UT-32 | 1.5日 | T-04 |
| T-18 | 権限の要求と設定の画面の `presenter`（gate と 2 つの UseCase）、Manager の今の `requestPermission` を UseCase に替える、`NotificationPermissionHelper` の deprecated、UT-26・UT-27、MS-04 | 1.0日 | T-05、T-17 |
| T-23 | `NotificationCategoryQueue`（始めと終わりの手順、center の抽象）、port と UseCase の同期の積みと既定の実装、Manager の callback 版と `async` 版、UT-28、MS-09 | 1.0日 | T-17 |
| T-19 | 通知の操作のサンプル（SA-09、SA-10、SA-13）と UI テスト（N38、N39、N42） | 1.0日 | T-16、T-18、T-23 |
| T-20 | 14 章の記録（MS-11・MS-13 を含む）と README・第 1 部への反映 | 1.0日 | T-09、T-11、T-12、T-16、T-19、T-22 |
| T-21 | 全体の実行と基準との比べ合わせ、棚卸しの `grep` の流し直し、ブリッジのテストとの対応の記録、UT-31 の組めない形の一覧、Xcode 26.3 の `swift-frontend -typecheck-module-from-interface` で 26.6 で組んだ `IosLibrary` の swiftinterface（型つきの throws を含む）を 3 つのスライスで読む（SR-15）、1b の結果のファイル | 1.5日 | T-02、T-03、T-20 |

合計見積: 約 28.0 日

## 16. リスクと緩和策

| ID | リスク | 緩和策 |
|---|---|---|
| RK-01 | 今の Dialog の口を新しい芯に載せ直したことで、今の口の動作が変わる | 結果を今のコールバックに写す表（8.1.4）と、D1〜D15 の UI テスト・UT-10 で前後を比べる |
| RK-02 | 新しい定義の前面の前提（G-6）が成り立たない | MS-02 を最初に測り、成り立たなければ `foregroundActive` だけにする（P1-11） |
| RK-03 | 外から閉じた ViewController が解放されず、完了が来ない | MS-03。解放されない経路は約束の外に移し、DocC とマニュアルに書く（P1-14） |
| RK-04 | 2 回目の申し送りの結果で 1a-13 の関数が要ると分かる | 通知を最後にする（S-P24）。足すのは関数の追加で、この設計書の口は変えない見込み |
| RK-05 | 今の受け手（deprecated）とイベントの口の両方を使うと、同じイベントを 2 度受ける | DocC と移行の手引きに書く。サンプルはイベントの口だけを使う |
| RK-06 | `NotificationRepository`・`ShareRepository` の形を変え、利用者の実装が組めなくなる | 3.3 の破壊的に書く（0e の `Sendable` と同じ扱い） |
| RK-07 | 案 D の 164 か所の書き換えで、秘密の値を `.private` のまま補間に入れる（`.private` は UT-15 で見つけられない） | `LogRedaction` の長さ・有無だけを入れる形と `grep` の照合（T-02）、レビュー。`Log` は deprecated で残すので利用者のソースは組める |
| RK-08 | `foregroundInactive` の間に表示が出て、後ろに回る途中に Dialog が残る | 表示は残り、戻ったときに選べる（P1-15）。D22 で確かめる |
| RK-09 | 値の木で userInfo の型（`NSNumber` の真偽値と整数）を取り違える | UT-18。`CFBoolean` を先に見る |
| RK-10 | category の反映が読み直しで確かめられない | MS-09 の結果で完了の時期を「書き戻した後」にする |
| RK-11 | 解放の見張りが ViewController の解放の時期に頼り、環境（TSan の版など）で遅れる、来ない | 通常の版で来ない経路は約束の外に移す（P1-14）。TSan の回では見張りに頼るテストを skip し、理由を書く。Dialog は取り消せば来る |
| RK-12 | `async` 版の追加で、利用者の `async` の文脈の呼び出しが組めなくなる | 3.3 と移行の手引きに一覧（UT-31）。組めなくなるだけで、黙って意味は変わらない |

## 17. Definition of Done

- [ ] 6.1 のファイルと可視性、付録 A の宣言があり、8 章の振る舞い、6.2 のスレッド、取り消しの契約と一致している
- [ ] `PLANNED_SYMBOLS_EXEMPT` の名前を実装と照合した
- [ ] 5.1 のロジックがすべて `IosLibrary` にあるか、C ABI / 包みの受け持ちと決めている（7 章）
- [ ] 5.2 の README 1.4 の不備が直っているか、3.4 に理由つきで残している
- [ ] `ios.md` に 4.2 の 4 つの書き足しがあり、UT-15 が通る
- [ ] `PrivacyInfo.xcprivacy` があり、棚卸し（8.8.1）と一致し、アーカイブのプライバシーのレポートで確かめた（MS-10）
- [ ] 13 章のテストがシミュレーターで通り、全件が 0g の後の基準と同じ（足したテストと変えた期待値は理由を記録）。足したテストは壊すと落ちることを確かめた
- [ ] 14 章の MS-01〜MS-14 を記録し、決まりが変わるものを README と第 1 部に反映した
- [ ] 第 1 部 9.1 の S-1〜S-16 を 11 章の表で確かめた
- [ ] Xcode 26.6 で組んだ `IosLibrary` の swiftinterface を、利用者の下限の Xcode 26.3 で 3 つのスライスとも読めた（型つきの throws を含む。SR-15）
- [ ] UT-31 の組めなくなる呼び出しの一覧を 3.3 と移行の手引きの元に写した
- [ ] README の 4 章・4.1・5 章の 1b の行・8.6・9 章を直した（18.2）

## 18. 入力の食い違いと、README を直す所

### 18.1 入力の食い違い

| # | 食い違い | どちらに合わせるか | 状態 |
|---|---|---|---|
| 1 | 第 1 部 P1-18 は「`IosLibrary` の `Log` は `internal` で capi から呼べない」とするが、今の `Log` は `public @objcMembers`（0f の swiftinterface の 522 行。サンプルとブリッジが使う） | コードが正しい。capi が `Log` を使わない結論は変わらない。S-P21 で `Log` は public のまま deprecated にする | 済み（S-P21） |
| 2 | 第 1 部 S-15・P1-24 と README 4 章は、Clipboard の読み込みの取り消しは「今は `cancelAllLoads` だけ」とする。今の `loadItem(_:scope:completion:)` は `ClipboardLoadToken` を返し、要求ごとに `cancel()` できる（`@MainActor` だけ、開始の後だけ）。`async` 版も `Task` の取り消しで止まる | コードが正しい。足りないのは「受け付けの時点で作れる箱」と「どのスレッドからでも取り消せること」で、S-P22 はそれを足す | 済み（S-P22） |
| 3 | README 1.4 と 4 章は「権限の問い合わせの受け手が static の 1 つ」「重ねて呼んでも上書きされない形にする」を `Notification/` の直しとする。static の受け手はブリッジの `.m`（`hasNotificationPermission` の `s_hasPermissionCallback`）だけで、ライブラリの口は呼び出しごとの完了 | ライブラリは直すものが無い（5.2）。C ABI は `user_data` ごとの完了で起きない | 済み（README 1.4・4 章） |
| 4 | README 4 章は「権限の状態を列挙にする」とするが、`NotificationAuthorizationStatus` は既に列挙（文字列にしていたのはブリッジ） | 直すものは無い（B10） | 済み（README 4 章） |
| 5 | README 4 章は「引数を省いたときの既定の文言は今のライブラリの既定。C ABI では 0 で埋めた構造体のときの既定」とする。ライブラリの `enableConfirmWhenEmpty`・`enableLoginWhenEmpty` の既定は `true`、ブリッジの既定は `false`、C の 0 は偽。placeholder の既定もライブラリは `nil`、ブリッジは `""` | Swift の新しい口はライブラリの既定。第 2 部で、0 が「ライブラリの既定」になる項目の向き（`require_input` のように 0 が `true` の既定に当たる名前）を決める | 第 2 部 |
| 6 | README 1.4 は「Dialog のテストはどのターゲットにも無い」とするが、0e で `IosDialogManagerTests`（9 件）を足した | 記録が古いだけ。UT-10 はこの 9 件を守る | 済み（README 1.4） |
| 7 | README 5 章の 1a の行・P1-23・README の状態の行は「2 回目の申し送り（通知の雛形）は Swift の API の設計書を書く前に出す」とする。2 回目はまだ出ていない（1 回目の雛形を別の agent が作っている） | この設計書は通知の口を、U-3・U-4 の結果で変わりうるもの（1a-13）として書き、作業を最後にした（S-P24、RK-04）。利用者に順を確かめる | 済み（P1-23 の決め直し、2026-10-31） |
| 8 | README 8.6 と 1.4 は「通知と Share の内容」を秘密の値とする。Android の `android.md` は通知のタイトルとメッセージを「出してよい値」とする | iOS は README に合わせる（8.7.1）。OS で違うことを `ios.md` に書く | 済み（README 8.6 のまま。`ios.md` に書いた） |
| 9 | `common.md` は「iOS 18+ は Swift Testing。XCTest は使わない」とする。README 7 章と第 1 部 6 章は `IosLibraryCApiTests` を XCTest で書く（C の関数を呼ぶため） | この設計書のテストは Swift Testing（UI テストは XCUITest）。C ABI のテストの例外は 2b の前に `common.md` に書く | 2b の前（`common.md`） |
| 10 | 第 1 部 P1-18 は capi のログで「利用者の値は `.private`」とする。v1 は「`Log` は文字列を受けるので付けられない」として P1-18 を決め直そうとしたが、capi は `Log` を使わず `os.Logger` を直に呼ぶので当たらない（レビュー v1 の SR-6） | P1-18 は変えない。`IosLibrary` も案 D で同じ規則にする（S-P21） | 済み（S-P21。P1-18 は変えない） |
| 11 | `IosNotificationManager` の DocC は「Unity の相互運用のために `(isSuccess, errorMessage)` にする」、`IosClipboardManager` の DocC は「Unity のブリッジだけがどのスレッドからも呼べる入口」とする（第 1 部 11.1 の 8） | 1b で DocC を直す（T-12、T-17） | 1b（T-12、T-17） |
| 12 | 第 1 部 S-6 は「表示の口すべてに要求の箱の引数を足す」とするが、取り消しの無い Share・権限の要求・設定の画面に外から箱を渡す理由が無い | 箱の引数は Dialog と Clipboard の読み込みだけ（11 章の S-6。SR-19） | 済み（11 章） |

### 18.2 決まった後に README で直す所（2026-10-31 に直した）

| README の所 | 直し | 状態 |
|---|---|---|
| 4 章の表 | 置き場所の案を 6.1 のファイルに。権限の行を 18.1 の 3・4 のとおりに | 済み（2026-10-31） |
| 4.1 の 1b の行 | 3.3 の表を写す | 済み（2026-10-31） |
| 5 章の 1b の行 | 3.3 の動作の変更と、C1〜C7 のコミット | 済み（2026-10-31） |
| 8.6 | 「イベントを保つ件数」「1.x の扱い」「エラーの case」「ログの規則」「プライバシーマニフェスト」の行を、この設計書の節で済みにする | 済み（2026-10-31） |
| 9 章の DoD | 1b の行に、この設計書の 17 章を指す | 済み（2026-10-31） |
| 状態の行 | Swift の API の設計書の状態 | 済み（2026-10-31） |
| 1b の行・4.1 | 申し送り 1 の G-7 の測りの結果（外から閉じた Share に完了が来ない → 1b で見張りを足す）を、第 1 部 G-7 の記録と合わせる | 済み（2026-10-31） |

## 19. 付録 A: 公開の宣言

**擬似宣言**: 本体を省いた宣言で、そのままではコンパイルしない。DocC は省く。今の口のうち形を変えないものは載せない。

```swift
// Common
public struct PresenterSelection: Sendable {
    // internal enum: firstActiveScene, foreground, provided(@MainActor @Sendable () -> AnyObject?)
    public static let firstActiveScene: PresenterSelection   // default: the current search, no waiting
    public static let foreground: PresenterSelection         // active or inactive scene with the key window (part 1, 5.13); iPad with 2 active scenes: pass viewController(_:) (1b C2, MS-02)
}
extension PresenterSelection {           // Common/Presentation (imports UIKit)
    public static func viewController(_ provider: @escaping @MainActor @Sendable () -> UIViewController?) -> PresenterSelection
}
public final class RequestBox: Sendable { // @unchecked internally (P1-17 (4))
    public init()
    public var isClosed: Bool { get }
}
public struct FailureDetail: Sendable, Equatable {
    public let domain: String
    public let code: Int
    public init(domain: String, code: Int)
    public init(systemError: any Error)
}

// Dialog
public enum DialogRequest: Sendable, Equatable {
    case alert(title: String?, message: String?, buttonTitle: String = "OK")
    case confirm(title: String?, message: String?, confirmTitle: String = "OK", cancelTitle: String = "Cancel")
    case destructive(title: String?, message: String?, destructiveTitle: String = "Delete", cancelTitle: String = "Cancel")
    case actionSheet(title: String?, message: String?, options: [String], cancelTitle: String = "Cancel")
    case textInput(title: String?, message: String?, placeholder: String? = nil, confirmTitle: String = "OK",
                   cancelTitle: String = "Cancel", enableConfirmWhenEmpty: Bool = true)
    case login(title: String?, message: String?, usernamePlaceholder: String = "Username", passwordPlaceholder: String = "Password",
               loginTitle: String = "Login", cancelTitle: String = "Cancel", enableLoginWhenEmpty: Bool = true)
}
public struct DialogAnswer: Sendable, Equatable {
    public enum Button: Sendable, Equatable { case primary, cancel, destructive, option(index: Int) }
    public let button: Button
    public let title: String?
    public let input: DialogInput?        // nil for the cancel button
    public init(button: Button, title: String?, input: DialogInput?)   // 1b C2: for your own DialogPresenting
}
public enum DialogInput: Sendable, Equatable, CustomStringConvertible {   // description redacts the values
    case text(String)
    case login(username: String, password: String)
}
public enum DialogError: Error, Sendable, Equatable, LocalizedError {
    case canceled, dismissedBySystem, notForeground, presentationFailed, invalidRequest
}
public protocol DialogPresenting: Sendable {
    func present(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                 completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void)
}
public struct ShowDialogUseCase: Sendable {
    public init(presenter: any DialogPresenting)
    public func execute(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                        completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void)
}
extension IosDialogManager {
    @discardableResult
    public func show(_ request: DialogRequest, presenter: PresenterSelection = .firstActiveScene, requestBox: RequestBox? = nil,
                     completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void) -> RequestBox
    @discardableResult                                                    // 1b C2 (ios.md)
    public func show(_ request: DialogRequest, presenter: PresenterSelection = .firstActiveScene) async throws -> DialogAnswer
    public func cancel(_ box: RequestBox)                                  // any thread, does not wait
    @MainActor public func foregroundViewController() -> UIViewController?
}

// Share
public enum ShareError: Error, Sendable, Equatable, LocalizedError {
    case noValidItems, invalidURL(String), imageLoadFailed(path: String), fileNotFound(path: String)
    case noRootViewController, notForeground, presentationFailed, dismissedBySystem, activityFailed(FailureDetail)
}
public protocol ShareRepository: Sendable {                                // changed port
    func present(content: ShareContent, presenter: PresenterSelection) async throws -> ShareResult
}
extension IosShareManager {
    public func share(content: ShareContent, presenter: PresenterSelection,
                      completion: @escaping @MainActor @Sendable (Result<ShareResult, ShareError>) -> Void)
    @discardableResult
    public func share(content: ShareContent, presenter: PresenterSelection = .firstActiveScene) async throws -> ShareResult
}

// Notification
public enum NotificationError: Error, Sendable, Equatable, LocalizedError {
    case permissionDenied
    case attachmentLoadFailed(identifier: String, detail: FailureDetail)
    case addRequestFailed(FailureDetail), setBadgeCountFailed(FailureDetail), authorizationFailed(FailureDetail)
    case reservedUserInfoKey, invalidUserInfo, notForeground, openSettingsFailed, delegateNotInstalled
}
public indirect enum NotificationUserInfoValue: Sendable, Equatable {
    case string(String), integer(Int64), unsignedInteger(UInt64), double(Double), bool(Bool), date(Date), data(Data)
    case array([NotificationUserInfoValue]), dictionary([String: NotificationUserInfoValue])
}
public struct NotificationResponseEvent: Sendable, Equatable, CustomStringConvertible {
    public let notificationIdentifier: String
    public let actionIdentifier: String
    public let categoryIdentifier: String
    public let userText: String?                                            // description shows the length only
    public let userInfo: [String: NotificationUserInfoValue]                // without the library marker
    public let isLaunchResponse: Bool
}
public struct NotificationSettingsRequest: Sendable, Equatable {
    public let notificationIdentifier: String?
}
public struct ScheduledNotification: Sendable {                            // was not Sendable (S-P25)
    public let identifier: String, title: String, subtitle: String?, body: String?, categoryIdentifier: String
    public let userInfoValues: [String: NotificationUserInfoValue]          // without the library marker
    public var userInfo: [AnyHashable: Any] { get }                         // computed from userInfoValues
    public init(identifier: String, title: String, subtitle: String?, body: String?, categoryIdentifier: String,
                userInfo: [AnyHashable: Any])                               // same parameters as today
}
// ActiveNotification: the same change (plus `date`)
public enum NotificationCategoryChange: Sendable {
    case register(NotificationCategory)
    case remove(identifier: String)
}
public protocol NotificationRepository: Sendable {                         // changed port
    func openNotificationSettings() async -> Bool                           // was: func openNotificationSettings()
    func enqueueCategoryChange(_ change: NotificationCategoryChange,        // new (S-P28): synchronous, enqueue and return
                               completion: @escaping @Sendable () -> Void)
    // ... other requirements unchanged ...
}
extension NotificationRepository {
    public func enqueueCategoryChange(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void)
    // default: Task { await registerCategory / removeCategory; completion() } (order not kept)
}
extension RegisterNotificationCategoryUseCase {
    public func enqueue(_ category: NotificationCategory, completion: @escaping @Sendable () -> Void)
}
extension RemoveNotificationCategoryUseCase {
    public func enqueue(identifier: String, completion: @escaping @Sendable () -> Void)
}
@available(*, deprecated, message: "Use IosNotificationManager.requestPermission(options:presenter:)")
public final class NotificationPermissionHelper: Sendable { /* unchanged members */ }
@MainActor public final class NotificationEventHub<Event: Sendable> {
    public func addListener(_ listener: @escaping @MainActor (Event, NotificationEventRegistration) -> Void)
        throws(NotificationError) -> NotificationEventRegistration           // delegateNotInstalled
}
@MainActor public final class NotificationEventRegistration {
    public func remove()
}
public enum NotificationDelegateInstallResult: Sendable { case installed, notMainThread }
extension IosNotificationManager {                                         // no longer a UNUserNotificationCenterDelegate
    @discardableResult public static func installDelegate() -> NotificationDelegateInstallResult
    public static var isDelegateInstalled: Bool { get }
    public var responses: NotificationEventHub<NotificationResponseEvent> { get }
    public var settingsRequests: NotificationEventHub<NotificationSettingsRequest> { get }
    @MainActor public func launchResponse() throws(NotificationError) -> NotificationResponseEvent?
    public func show(content: sending NotificationContent, trigger: NotificationTrigger?) async throws
    public func update(identifier: String, content: sending NotificationContent, trigger: NotificationTrigger?) async throws
    public func schedule(content: sending NotificationContent, trigger: NotificationTrigger, identifier: String) async throws
    public func setBadgeCount(_ count: Int) async throws
    public func getScheduled() async -> [ScheduledNotification]
    public func getDelivered() async -> [ActiveNotification]
    public func hasPermission() async -> Bool
    public func authorizationStatus() async -> NotificationAuthorizationStatus
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .sound, .badge], presenter: PresenterSelection,
                                  completion: @escaping @MainActor @Sendable (Result<Bool, NotificationError>) -> Void)
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .sound, .badge],
                                  presenter: PresenterSelection = .firstActiveScene) async throws -> Bool
    public func openNotificationSettings(presenter: PresenterSelection,
                                         completion: @escaping @MainActor @Sendable (Result<Void, NotificationError>) -> Void)
    public func openNotificationSettings(presenter: PresenterSelection = .firstActiveScene) async throws
    public func registerCategory(_ category: NotificationCategory, completion: (@MainActor @Sendable () -> Void)? = nil)
    nonisolated(nonsending) public func registerCategory(_ category: NotificationCategory) async      // enqueues before the first suspension
    public func removeCategory(identifier: String, completion: (@MainActor @Sendable () -> Void)? = nil)
    nonisolated(nonsending) public func removeCategory(identifier: String) async                      // enqueues before the first suspension
    @available(*, deprecated, message: "Use installDelegate()") public static func setup()
    @available(*, deprecated, message: "Use responses") public var onActionReceived: NotificationActionHandler? { get set }
    @available(*, deprecated, message: "Use responses") public var onTextInputActionReceived: NotificationTextInputActionHandler? { get set }
}

// Logging (S-P21 Y)
@available(*, deprecated, message: "Use os.Logger")
@objcMembers public class Log: NSObject { /* d, i, w, e unchanged; still print (S-P21 Y1) */ }

// Clipboard
extension IosClipboardManager {
    @MainActor public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general, requestBox: RequestBox,
                                    completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void)
    nonisolated public func cancelLoad(_ box: RequestBox)                   // any thread, does not wait
}
```

- `registerCategory(_:completion:)` と `removeCategory(identifier:completion:)` は、今の `registerCategory(_:)`・`removeCategory(identifier:)` に既定 `nil` の引数を足したもの。同期の文脈の今の呼び方は組めるが、`async` の文脈で `completion` を書かずに呼んでいた所は `async` 版に決まり、`await` が要る（S-P26）
- `throws(NotificationError)` の型つきの throws は Swift 6 の機能で、利用者の下限の Xcode 26.3（Swift 6.2.4）で読める（swiftinterface を 26.3 で読めることは 1a 入口 3 章で確かめた形に入る。1b で `typecheck-module-from-interface` を流す）
