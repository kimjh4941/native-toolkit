# 段階 1b の作業の記録（Swift の API の補完）

- 記録日: 2026-10-31
- 段階: 1b（`README.md` の 5 章の 1b の行。設計書は `designs/2026-10-31-ios-c-abi-swift-api-design.md`。以下「設計書」）
- ブランチ: `feature/NTKIT-18`（HEAD `f3c289d7` の上の未コミットの変更）
- 環境: Xcode 26.3（17C529、Swift 6.2.4、`xcode-select` のまま）。0 件の警告の確かめだけ Xcode 26.6（17F113、Swift 6.3.3）でも組んだ（`DEVELOPER_DIR` でコマンドごとに選んだ）。シミュレーターは iPhone 17（iOS 26.2）、iPhone 16（iOS 18.3.1）、iPad Pro 11-inch (M4)（iOS 18.3.1）だけ。**実機には触れていない**
- 章: コミットごとに 1 章（設計書 15.1 の C1〜C7）。この版は C1 だけ

## 1. C1 共通（T-01〜T-05）

- 状態: 実装・単体テスト・壊して確かめる・シミュレーターでの全体の実行は済んだ。コミットはしていない
- 測ったログと抜き出した一覧は scratchpad に置き、リポジトリには入れていない

### 1.1 変えたもの

| 区分 | ファイル | 中身 |
|---|---|---|
| 規則（T-01） | `agent-rules/coding-rules/ios.md` | ログの節を `os.Logger` の書き方に書き換えた（logger の持ち方、category、privacy、秘密の値、エラー、型の制約、Release、確かめ）。`PresenterSelection` を取る口の規則を Manager の節に足した。ブリッジの Objective-C は `Log` のままと書いた。4.2 の残りの 2 つ（UseCase を置かない口、`async` の例外）は設計の決定と同じコミット（`ac83ad3b`）で入っていた |
| ログ（T-01） | `Common/Log.swift` | `@available(*, deprecated, message: "Use os.Logger")`。中身は `print` のまま。DocC に移り方を書いた |
| ログ（T-01） | `Common/LogRedaction.swift`（新、internal） | `redact(_:)`（`<redacted, length=N>`、N は UTF-8 のバイト数）、`length(_:)`、`caseName(_:)`（enum の case の名前だけ）、`describe(_:)`（ライブラリの enum のエラーは `<型>.<case>`。関連値が 1 つのエラーだけの case は、その中のエラーの domain と code を足して `<型>.<case>(domain=…, code=…)`。enum でないエラーは `NSError` の domain と code。レビューで直した。3 章） |
| ログ（T-02） | `Common/LogLevel.swift`（新、internal） | `OSLogType.libraryDebug`。Debug ビルドでだけ、UT-15 の間 `.info` に上がる（1.4 の偏り 2） |
| ログ（T-02） | ログを出す 32 ファイル | `Log.d`・`Log.e`・`Log.i`・`Log.w` の 160 か所を、ファイルの `private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "<型名>")` の直の呼び出しにし、補間のすべてに `privacy:` を付けた。型が 2 つあるファイル（`ClipboardProviderLoadExecutor.swift`）は `handleLogger`・`executorLogger` に分けた。`TAG` の定義はすべて消した |
| ログ（8.7.2） | `IosShareManager.swift`、`ShareRepositoryImpl.swift`、`IosNotificationManager.swift`、`NotificationRepositoryImpl.swift`、`NotificationPermissionHelper.swift` | `ShareError` などのエラーは `LogRedaction.describe`（case の名前だけ）。Share の `subject` は `redact`（有無と長さ）。権限の `options` は `rawValue`。presenter は型の名前 |
| サンプル（SA-17） | `IosLibraryExample/` の 6 ファイル | サンプルのログ 53 か所を自分の `os.Logger`（subsystem はサンプルの bundle id）にした。ログの中の秘密の値（テキスト入力の値、ユーザー名とパスワード、通知の返信）は長さだけにした。**結果の行（画面）は変えていない**（SA-16・D12 の期待値の変更は C2、SA-07 の画面は C5） |
| プライバシー（T-03） | `IosLibrary/PrivacyInfo.xcprivacy`（新） | 8.8.2 のとおり（Tracking なし、収集なし、FileTimestamp・C617.1 の 1 つ） |
| 共通の型（T-04） | `Common/Domain/PresenterSelection.swift`（新、public） | struct。中は internal の `Kind`（`firstActiveScene`・`foreground`・`provided(@MainActor @Sendable () -> AnyObject?)`）。UIKit を import しない |
| 共通の型（T-04） | `Common/Presentation/PresenterSelection+UIKit.swift`（新、public） | `viewController(_:)` |
| 共通の型（T-04） | `Common/Domain/FailureDetail.swift`（新、public） | `domain`・`code`・`init(domain:code:)`・`init(systemError:)` |
| 共通の型（T-04） | `Common/Application/RequestBox.swift`（新、public） | 公開は `init()` と `isClosed` だけ。internal に `attach(_:)`・`close(_:)`・`outcome` と `RequestBoxOutcome`（`completed(any Sendable)`・`canceled`・`notForeground`・`presentationFailed`・`dismissedBySystem`） |
| 表示（T-05） | `Common/Presentation/ForegroundLocator.swift`（新、internal） | 2 つの探し方の規則を値（`Scene<Node>`）の上に書き、UIKit の `connectedScenes` から値を作って使う |
| 表示（T-05） | `Common/Presentation/PresentationProcedure.swift`（新、internal） | 第 1 部 5.13.2 の段。`PresentationEnvironment`（UIKit を差し替える protocol）と `UIKitPresentationEnvironment` |
| 表示（T-05） | `Common/Presentation/ReleaseWatch.swift`（新、internal） | 解放の見張り。関連オブジェクトの鍵 |
| Dialog | `Dialog/IosDialogManager.swift` | ログのほか、`getRootViewController()` の中を `ForegroundLocator.firstActiveScene()` を返すだけにした（6.3.1 の「1 か所」。動作は同じ。1.4 の偏り 5） |
| テスト | `IosLibraryTests/Common/` の 9 ファイル（新） | 1.5 |
| 公開 API | `results/swiftinterface/` | 1.6 |

`project.pbxproj` は変えていない。`IosLibrary` のターゲットはフォルダーと同期する形（`PBXFileSystemSynchronizedRootGroup`）で、`PrivacyInfo.xcprivacy` は置いただけで framework の Resources に入った（組んだ `IosLibrary.framework` の直下にあることを Debug と Release で確かめた）。

### 1.2 公開 API（付録 A の Common との照合）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public struct PresenterSelection: Sendable`（中は internal の enum） | 同じ | 一致 |
| `public static let firstActiveScene`、`public static let foreground` | 同じ | 一致 |
| `extension PresenterSelection { public static func viewController(_ provider: @escaping @MainActor @Sendable () -> UIViewController?) -> PresenterSelection }`（`Common/Presentation`） | 同じ | 一致 |
| `public final class RequestBox: Sendable { public init(); public var isClosed: Bool { get } }`（「@unchecked internally」） | 同じ形。**`@unchecked` は付けていない**（`Mutex` は `Sendable` なので、状態を `Mutex` の中だけに置けば普通の `Sendable` で組める） | 一致（`@unchecked` が 1 つ減った） |
| `public struct FailureDetail: Sendable, Equatable { domain, code, init(domain:code:), init(systemError: any Error) }` | 同じ | 一致 |
| `@available(*, deprecated, message: "Use os.Logger") @objcMembers public class Log` | 同じ | 一致 |

ほかの公開の変更は無い（1.6 の差分）。公開の記号には DocC を付けた（型、static の値、関数、`init`、非自明な property）。

`@unchecked Sendable` と `nonisolated(unsafe)`（P1-17）: C1 で足したのは `ReleaseWatch` の関連オブジェクトの鍵の `nonisolated(unsafe) private static let key` の 1 つだけ（P1-17 の (5)）。`RequestBox`（(4)）と `ReleaseWatch`（(4)）は `@unchecked` なしの `Sendable` で組めた（`Mutex` と `Atomic` が `Sendable`）。今までの 5 つの `@unchecked Sendable` と 1 つの `nonisolated(unsafe)`（Clipboard）は変えていない。

### 1.3 ログの書き換えの照合（T-02）

- 書き換えはスクリプトで行い、補間ごとの privacy を表にしてから直した。`.public` は、関数名・識別子（通知・category・アクションの id、ライブラリが作った id）・件数・真偽値・列挙・`redactedDescription` と `ClipboardLog` の伏せた値・`LogRedaction` の値・Clipboard の `errorCode`。`.private` は、Dialog の題・本文・ボタンの文言・placeholder・`sourceView`・`sourceRect`・`barButtonItem`・選んだ選択肢、通知の `trigger`、Clipboard の UTI（呼び出し側が渡す値。`ClipboardProviderLoadExecutor` の注釈と同じ扱い）
- 照合の `grep`（秘密の値の名前 `password`・`userText`・`inputText`・`username`・`subject`・`previewTitle`・`title`・`body`・`subtitle`・`userInfo`・`content`・`text`・`url`・`path`・`plainText`・`html` を含む補間で、`LogRedaction`・長さ・件数を通さないもの）で残ったのは、Dialog の題と本文（`.private`。設計書 8.7.2 で出してよい値）、通知の `content.id`（識別子）、サンプルの Share のサンプル用ファイルの準備の失敗（`.private`。サンプルが自分で作るファイルで、利用者の値ではない）だけ
- 設計書の「33 ファイル、164 か所」は、HEAD では 32 ファイル、160 か所だった（`Common/Log.swift` を除く）

### 1.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | `RequestBox`・見張りは P1-17 の (4) で `@unchecked Sendable` | `@unchecked` なし | `Mutex` と `Atomic` が `Sendable` で、可変の状態はその中だけなので、コンパイラーが確かめる `Sendable` で組めた。P1-17 の一覧より少ないので約束の内側 |
| 2 | 呼ぶ所で `os.Logger` を直に呼ぶ。UT-15 で `.debug` が読めなければ「テストの間だけ `.info` に上げる口（`#if DEBUG`）を持つ」 | ふつうのログは `logger.log(level: .libraryDebug, "...")`。`libraryDebug` は Debug ビルドでは `Atomic` の印を見て `.debug` か `.info`、Release ではいつも `.debug` | MS-13 で `OSLogStore` が `.debug` を返さないと分かった（1.7）。`OSLogMessage` は包みの関数に渡せない（補間は呼ぶ所の文字列でなければ組めない）ので、上げる口は「呼ぶ所でレベルを値で渡す」形しか無い。`os.Logger` を直に呼ぶことと privacy の付け方は変わらない |
| 3 | UT-15 は「`.private` で入れた秘密は見つけられない」 | シミュレーターのテストのプロセスでは `OSLogStore` が `.private` の値も平文で返した（1.7）。UT-15 はそれも捕まえる（M7b）。伏せて見える環境のために、見えたかを記録するテスト（`privateValuesAreVisible`）を置いた | 環境で振る舞いが違うので、見えないときは今の設計書のとおり `grep` の照合が受け持つ |
| 4 | 6.1: `project.pbxproj` で `PrivacyInfo.xcprivacy` を Resources に入れる | 変えていない | フォルダーと同期するターゲットなので自動で入る（1.1） |
| 5 | `getRootViewController()` の中を `ForegroundLocator` にするのは時期を書いていない（6.3.1 は「1 か所に置き」） | C1 で替えた。`ShareSheetPresenter` の重複は 6.1 のとおり C3 で消す | 探し方を 1 か所にし、Dialog の今の UI テスト（D1〜D15）で同じ結果を確かめるため。単体テストのプロセスには scene が無く、偽の scene の値で規則を、UI テストで本物の scene を確かめる |
| 6 | 6.3.3 の表示の手順の形は書いていない | `PresentationProcedure.present(_:presenter:box:firstActiveScenePolicy:environment:onPresented:)` と、表示しない口の `requireForeground(presenter:box:environment:proceed:)`。`.firstActiveScene` で落ち着いていないときの今の口ごとの動作を `FirstActiveScenePolicy`（Dialog は `presentAnyway`、Share は `requireLegacyStability` = 今の Share の 3 つの確かめ）で選ぶ | 6.3.3 の「`.firstActiveScene` は今のまま（Dialog は present を呼ぶ、Share は presentationFailed）」を 1 つの手順で表すため |
| 7 | `.foreground` で key window を持つ前面の scene が 2 つあるときは定めていない（G-6 の前提） | `foregroundActive` を先に選び、2 つ以上あれば `.info` のログを出す | `connectedScenes` は `Set` で順が無いので、前提が崩れたときにも決まった方を選ぶ。G-6（MS-02、C2）で前提が成り立つかを見る |
| 8 | 待ちの completion が来なかったら（段 4） | 1 回だけ通す印を付け、UIKit が待ちを断ったのに completion も呼んだ場合も、やり直しは 1 回 | `animate(alongsideTransition:completion:)` の戻り値と completion の両方に頼らないため（UT-04 の `aTransitionEndReportedTwiceStillChecksOnlyOnce`） |
| 9 | サンプルの秘密の値の直しは SA-07（C5）・SA-16（C2） | サンプルのログの行の秘密の値は C1 で長さだけにした（画面の結果の行は変えていない） | SA-17 でサンプルのログを `os.Logger` に書き換えるとき、秘密の値を `.private` で書き写すと新しく秘密を出す形になるため。UI テストの期待値は変わらない |
| 10 | 0f の swiftinterface（`IosLibrary-after-0f.swiftinterface`）を基準にする | HEAD（`f3c289d7`）を同じ組み方で組んだ `IosLibrary-before-1b-f3c289d7.swiftinterface` を足し、これを C1 の差分の基準にした | リポジトリの `after-0f` は、0f の 4.3 の直し（`IosClipboardManager` の `isolated deinit` を外した）の前に写したもので、HEAD の公開面と違った（`deinit` の 5 行）。0f の記録を直すかは利用者に尋ねる（2 章） |
| 11 | Clipboard の UTI はログで出してよい値（`ClipboardRedaction` の DocC） | `.private`。`ClipboardRedaction` の DocC も直した | 8.7.1 の「そのほかの利用者の値は `.private`」に合わせた。`ClipboardProviderLoadExecutor` の注釈も「type identifier can be caller-supplied data」としている |
| 12 | `getRootViewController()` のログ（設計書に無い） | 前は `IosDialogManager` の `TAG` で、window scene か key window が無いときだけ `Log.e` を出した。今は `IosDialogManager` のカテゴリで先頭の `[getRootViewController]`（`.libraryDebug`）を出し、失敗は `ForegroundLocator` のカテゴリの `.error`（`[firstActiveScene] failed to get window scene or key window`）。key window の `rootViewController` が nil のときも `.error` を出すようになった（前は黙って nil） | 探し方を `ForegroundLocator` の 1 か所に移したため（偏り 5）。戻り値は変わらない |
| 13 | エラーのログは case の名前（8.7.2、SR-7） | 関連値が 1 つのエラーだけの case（`NotificationError.addRequestFailed(Error)`、`ShareError.presentationFailed(Error)` など）は、中のエラーの domain と code も出す | domain と code は 8.7.1・第 1 部 5.15 で出してよい値で、case の名前だけでは原因の system のエラーが分からなくなる（レビュー B-2） |
| 14 | 表示の手順の基点（P1-13） | 基点を付けるときに矢印の向き（`permittedArrowDirections`）を変えない | 今の Share は `.any`、Dialog の今の口は呼び出し側の値を使う。C2・C3 で手順に載せ替えても今の見え方を保つため（レビュー B-3） |

### 1.5 単体テスト（`IosLibraryTests/Common/`）と壊して確かめたこと

| ID | ファイル | 件数 | 中身 |
|---|---|---|---|
| UT-01 | `PresentationProcedureTests.swift` の `PresenterSelectionTests` と `theProvidedViewControllerIsAskedForOnceOnMainAndUsedForTheRetry`・`eachSelectionUsesItsOwnSearch` | 3 + 2 | 3 つの値の区別、値を作っただけでは closure を呼ばない、closure を main で 1 回だけ呼び、やり直しでも同じ ViewController を使う、値ごとに自分の探し方だけを使う |
| UT-02 | `ForegroundLocatorTests.swift` | 8 | 今の探し方（最初の `foregroundActive` で決まる、閉じかけも含めてたどる、inactive を使わない、最初の scene が使えなければ nil）、新しい定義（inactive を受ける、閉じかけを飛ばす、window scene と key window が要る、後ろの scene も見る、active を先に選ぶ）、scene の無いテストのプロセスで両方と `getRootViewController()` が nil |
| UT-03 | `RequestBoxTests.swift` | 7 | 最初に閉じたものだけ、閉じたときの処理は main で 1 回で呼び出しの中では来ない、閉じた箱に付けても同じ経路、2 つ目の付けを断る（開いていても閉じていても）、背景のスレッドから閉じても止まらず main で来る、8 スレッド × 25 回 × 1000 回の競合 |
| UT-04 | `PresentationProcedureTests.swift` の `PresentationProcedureTests` | 22（UT-01 の 2 を含む。うち 1 つは 2 通りの引数） | 前面なし、落ち着いていれば待たずに基点を付けて出す、待ち 1 回と次の回の探し直し、待つものが無いときの次の回、2 回目の失敗、2 回目に前面なし、待ちの完了が 2 回来てもやり直しは 1 回、UIKit が待ちを断ったのに完了も呼ぶ（その場で・後で）ときも探し直し 1 回と表示 1 回、待つ間の取り消しで出さない、閉じた箱は何も見ない、UIKit が断ったら `presentationFailed`、`.firstActiveScene` の 2 つの方針、表示しない口（落ち着きを求めない、前面でなければ失敗、`.firstActiveScene` は今のまま、渡された ViewController は window が要る、閉じた箱） |
| UT-05 | `ReleaseWatchTests.swift` | 8 | 完了の前の解放は `presentationFailed`、後は `dismissedBySystem`、生きている間は閉じない、答えと取り消しを上書きしない、手順を通して出した後の解放、最後の持ち主を背景のスレッドで手放す（止まらず、完了は main で 1 回）、本物の `UIAlertController`（TSan の回は skip） |
| UT-06 | `FailureDetailTests.swift` | 4 | domain と code だけ（保つ値は 2 つ、説明にも userInfo にも番兵が無い）、Swift のエラーの橋渡し、等しさ |
| UT-15 | `LibraryLogPrivacyTests.swift` | 3 + `LogRedactionTests` 4 | Share（本文・URL・ファイルのパス・件名・題、URL を持つエラー）、通知（題・副題・本文・userInfo の値）、Clipboard（本文）を番兵で呼び、`OSLogStore` で読んだライブラリの全メッセージに番兵が無い。読めていることを `#require` で確かめる（上げたふつうのログ、エラーのログ）。エラーは case の名前で出る。**通知は Manager の層だけを通る**（repository は Mock。`NotificationRepositoryImpl` は `UNUserNotificationCenter.current()` を使い、ホストのアプリの無いテストのプロセスでは呼べない）。Share は `ShareRepositoryImpl` まで通る（presenter が Mock）。`LogRedactionTests` は伏せる補助と、中のエラーの domain と code を足す形 |

C1 で足したのは 9 ファイル（うち 2 つは支え: `Support/CommonTestSupport.swift`、`Support/FakePresentationEnvironment.swift`）、最初の版で **56 件**、レビューの後に 3 件を足して **59 件**（3 章）。Dialog の 8.7.2 の「新しい芯の入力の値」は C2 の UT-15 に足す（C1 の Dialog の口は入力の値を受けない）。

壊して確かめたこと（壊した版で組んで該当のテストを流し、落ちることを見てから戻した。差分とログは scratchpad）:

| # | 対象 | 壊し方（設計書 13.1 の列） | 落ちたテスト |
|---|---|---|---|
| M1 | UT-01 | `.viewController` の closure をやり直しのたびに呼ぶ（「closure を 2 回呼ぶ」） | `theProvidedViewControllerIsAskedForOnceOnMainAndUsedForTheRetry` |
| M2 | UT-02 | `foregroundTop` の `isBeingDismissed` の確かめを外す | `foregroundSkipsAViewControllerBeingDismissed` |
| M3 | UT-03 | `close` で、開いているかを別の `Mutex` の区間で読む（「Mutex の外で読む」） | `concurrentClosesLeaveExactlyOneWinner`（1000 回のうち 309 回で勝ちが 2 つ以上）。**最初の版（200 回、揃えずに始める）では落ちなかった**ので、各回のスレッドを揃えてから閉じ始め、回数を 1000 にした |
| M4 | UT-04 | やり直しを `retried: false` で呼ぶ（待ちを 2 回以上にする） | `stillNotSettledAfterTheOneWaitFailsThePresentation`、`aTransitionEndReportedTwiceStillChecksOnlyOnce` |
| M5 | UT-05 | `close` の「閉じていれば何もしない」を外す（「箱が閉じていても閉じる」） | `aNormalResultIsNeverReplaced`、`aCancellationIsNeverReplaced`。`ReleaseWatch` は自分では箱が閉じているかを見ず、`RequestBox.close` の「最初の 1 回だけ」に頼るので、壊したのは `RequestBox.close` の側（`RequestBoxTests` の同じ確かめも落ちる） |
| M6 | UT-06 | `FailureDetail` に `localizedDescription` を持たせる | `keepsNothingElse`、`keepsTheDomainAndTheCodeOfAnNSError` |
| M7a | UT-15 | `IosShareManager` のエラーのログを `\(String(describing: error), privacy: .public)` にする（「1 か所で値を `.public` で補間する」） | `secretValuesNeverReachTheLog`（`error: invalidURL("https://example.com/<番兵>")` を見つけた） |
| M7b | UT-15 | `ShareRepositoryImpl` の件名を `\(content.subject ?? "nil", privacy: .private)` にする | `secretValuesNeverReachTheLog`（この環境では `.private` も見つかる。1.4 の偏り 3） |
| M8 | UT-03 | 閉じたときの処理を main に積まずにその場で呼ぶ | `theCloseHandlerRunsOnceOnMainAfterTheClosingCall`、`attachingToAClosedBoxDeliversTheEarlierOutcomeLater`、`closingFromABackgroundThreadDeliversOnMain`（`MainActor.assumeIsolated` で止まり、テストのプロセスが落ちた） |

M7a の最初の回では、`#require` が「エラーのログが `ShareError.invalidURL` で出る」ことを先に求めていたため、漏れの確かめまで届かずに落ちた。`#require` はエラーのログがあることだけにし、case の名前で出ることは別の `#expect` にして、漏れで落ちることを確かめ直した。

TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2）: `RequestBoxTests`・`ReleaseWatchTests`・`PresentationProcedureTests`・`LibraryLogPrivacyTests` の 38 件が成功、1 件 skip（`aRealViewControllerClosesTheBoxWhenFreed`。理由は申し送り 1 の TSan の版で外から閉じたアラートが 15 秒たっても解放されなかったこと。設計書 6.3.4・RK-11）。TSan の報告は 0 件。

### 1.6 公開 API（swiftinterface）

- 組み方: 0f と同じ（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）。`arm64-apple-ios.swiftinterface` を写した
- 足したファイル: `IosLibrary-before-1b-f3c289d7.swiftinterface`（HEAD。1.4 の偏り 10）、`IosLibrary-after-1b-c1.swiftinterface`、差分 `2026-10-31-stage1b-c1.diff`
- 差分の中身: `import ObjectiveC`・`import os` が増えた、`RequestBox`・`FailureDetail`・`PresenterSelection` と `viewController(_:)` が増えた、`Log` に `@available(*, deprecated, message: "Use os.Logger")` が付いた。ほかは変わらない
- `swift-frontend -typecheck-module-from-interface`（Xcode 26.3）で型検査が通った

### 1.7 シミュレーターで測ったこと（14 章のうち C1 に当たるもの）

C1 のタスク（T-01〜T-05）に付いた測りは MS-10（T-03）。UT-15 が頼る MS-13 の一部（`OSLogStore` で `.debug` を読めるか）も C1 で測った。MS-13 の残りは T-20（C7）だが、同じ回で測れたものを書く。

| ID | 環境 | 方法 | 結果 |
|---|---|---|---|
| MS-13（`OSLogStore`） | iPhone 17 / 26.2、`IosLibraryTests` のプロセス（ホストのアプリ無し、Debug） | 使い捨てのテストで `.debug`・`.info`・`.notice`・`.error` と `.private` の値を出し、`OSLogStore(scope: .currentProcessIdentifier)` で読んだ | `.debug` は返らない。`.info` 以上は返る。**`.private` の値は平文で返った**。→ 1.4 の偏り 2・3 |
| MS-13（Release の見え方） | iPhone 17 / 26.2、サンプルの Release ビルド | 起動の間 `log stream --level debug` を流し、終わってから `log show --info --debug` で読み直した。`simctl launch --console-pty` で標準出力も見た | 起動のライブラリの `.debug`（`[init]`、`[setup]` など 4 件）は `log stream` に出た。`log show` には 0 件（Release で `.debug` は保存されない）。標準出力には出ない（`print` でなくなった）。`xcodebuild` から動かしたテストのプロセスでは、`.error` のメッセージが Xcode の出力（stderr）にも出た |
| MS-13（`.private` の見え方） | iPhone 17 / 26.2、`IosLibraryTests` とサンプル（Debug）の UI テストの間 | 全体の実行の間、`IosDialogManager` のカテゴリを `log stream --level debug` で流した | シミュレーターでは `.private` の値（Dialog の題と本文、ボタンの文言）が `log stream` にも平文で出た（テストのプロセスもサンプルも）。**シミュレーターでは `.private` が伏せて見えることを確かめられない**。実機で 1 回見るかは利用者の許可が要る（2 章） |
| MS-10 | Xcode 26.6 | 1.9 | 1.9 |

ほかの MS（MS-01〜MS-09、MS-11、MS-12、MS-14）は C2 以降のタスクに付いている（設計書 15.2）。

### 1.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2>`（全体。単体テスト、`IosLibraryExampleTests`、UI テスト全件） | 377 件: 成功 376、skip 1。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`、320 件）との比べ合わせは `changed=0, added=56, removed=0`。足した 56 件は 1.5 の単体テスト。skip の 1 件は基準と同じ意図した skip（`ClipboardUITests/testU10b_namedPasteboardAfterProcessTermination`。M-08 がこの環境では決まらない）。ボタンの網羅（45 ボタン、77 テスト）も通った。基準は更新していない（`--baseline` は付けていない） |
| 内訳 | `IosLibraryTests` 267/267（基準 211 + 56）、`IosLibraryExampleTests` 10/10、UI テスト 99 件（権限 2、Navigation 2、IdentifierInventory 4、Dialog 15、Notification 23、NotificationEvent 7、NotificationColdStart 4、Share 16、Clipboard 21 + skip 1、ClipboardPaste 3、ClipboardPasteDeny 1）がすべて基準と同じ結果 |
| UI テストの範囲 | ログの書き換えはすべての機能の Manager・Repository に及ぶので、「直した所に触れる UI テスト」は全件になった。信頼する部分と凍結したファイル（UI テストの設計書 2 章）は変えていない（`test_ios.sh` のハッシュの照合が通った） |
| `IosLibraryTests` の全件（iPad Pro 11-inch (M4) / 18.3.1、iPhone 16 / 18.3.1） | どちらも 267/267。iOS 18 でも `OSLogStore` は `.debug` を返さず、`.private` を平文で返した（UT-15 の `privateValuesAreVisible` の出力）。`-only-testing` で Swift Testing の suite を選ぶと、この 2 つの環境では 0 件しか動かなかった（destination の `arch` が 2 つに合う警告が出た）ので、絞らずに全件を流した |
| TSan | 1.5 の末尾 |

### 1.9 MS-10（プライバシーマニフェストとアーカイブ）

| 項目 | 結果 |
|---|---|
| `plutil -lint` | OK |
| 棚卸しの `grep`（8.8.1 の API の一覧） | 8.8.1 と同じ。使っているのは `ClipboardTemporaryFileStore.swift` の `.contentModificationDateKey`（2 か所。ログの書き換えで行番号が 92・96 から 94・98 にずれた）だけ |
| 組んだ framework | Debug（シミュレーター）と Release（`generic/platform=iOS`）の `IosLibrary.framework` の直下に `PrivacyInfo.xcprivacy` がある |
| 署名なしのアーカイブ | Xcode 26.6 で `xcodebuild archive -scheme IosLibraryExample -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO` が警告 0 件で通った。アーカイブの `IosLibraryExample.app/Frameworks/IosLibrary.framework/PrivacyInfo.xcprivacy` の中身は 8.8.2 のとおり |
| プライバシーのレポート | **作れなかった**。レポートは Xcode の Organizer の「Generate Privacy Report」だけで作れ、コマンドラインの道具は無い（Xcode 26.3・26.6 の `usr/bin` と `xcrun` で探した）。アーカイブは作れるので、Organizer でアーカイブを開いてレポートを作れば確かめられる（2 章） |

### 1.10 警告

| 測り方 | 結果 |
|---|---|
| 0e・0f と同じ（2 つの scheme を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`、5 つのターゲットの診断の和集合）。Xcode 26.3、iPhone 17 / 26.2 | エラー 0、警告 0（ソースの診断以外は前と同じ `appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| 同じものを Xcode 26.6（`generic/platform=iOS Simulator`） | エラー 0、警告 0 |

`ios/UnityIosPlugin`（ワークスペースの外）は組んでいない。ブリッジは `Log` を使うので、組めば deprecated の警告が出る（D-22。段階 3 で消す）。

### 1.11 後のコミットへの申し送り

| 項目 | 内容 |
|---|---|
| 表示の手順を使う形（C2・C3） | `PresentationProcedure.present(vc, presenter:, box:, firstActiveScenePolicy:, environment: UIKitPresentationEnvironment(), onPresented:)`。箱の閉じたときの処理（`attach`）と handler は、表示した ViewController を `weak` で持つこと（見張り → 箱 → 閉じたときの処理 → ViewController の循環を作らない）。表示の途中の取り消し（R4-2）は `onPresented` の中で閉じる |
| 権限の要求・設定の画面（C6） | `PresentationProcedure.requireForeground(presenter:box:environment:proceed:)` |
| 補い（MS-01、C2） | `present` の直後の `presentingViewController` を見る補いは入れてある（`isPresentationAccepted`）。MS-01 で直後に設定されないと分かれば外す |
| 前面の定義（MS-02、C2） | `.foreground` は inactive を受ける形で入れた。G-6 が成り立たなければ `ForegroundLocator.foregroundTop` の条件を `foregroundActive` だけにする |
| UT-15（C2〜C6） | 機能ごとに番兵の呼び出しを `LibraryLogPrivacyTests` に足す（Dialog の新しい芯の入力、通知の返信と userInfo の値、Clipboard の読み込み）。C2 でホストのアプリを足したら、`NotificationRepositoryImpl` を本物の center で番兵の通知を通し、Repository のログも確かめる |
| ホストのアプリ（C2） | UT-08 はホストのアプリが要る。今の `IosDialogManagerTests` と `ForegroundLocatorTests.withoutScenesBothSearchesFindNothing` は「scene が無い」ことを前提にしているので、ホストを足すときは見直す |

## 2. 利用者に決めてもらうこと（C1）

**決定（2026-10-31、利用者）: 4 つとも推奨のとおり。**

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | MS-10 のプライバシーのレポートはコマンドラインで作れない | **C7（T-21）で、利用者が Xcode の Organizer で 1 回レポートを作る**。署名なしのアーカイブは作れることを確かめたので、`unity-native-plugin` の agent に頼む（設計書 3.5 の代わりの道）より手早い |
| 2 | `.private` が伏せて見えることはシミュレーターでは確かめられない（MS-13） | **2.0.0 の前の実機の区切り（DoD）の 1 回にまとめて見る**（Console.app で `IosLibrary` の subsystem を見るだけ。実機での実行は毎回許可が要る）。それまでは `grep` の照合と UT-15 で守る |
| 3 | ふつうのログを `logger.debug` でなく `logger.log(level: .libraryDebug, ...)` で書く（1.4 の偏り 2） | **このままにする**。UT-15 が `.debug` のメッセージを読めるのはこの形だけで、Release は `.debug` のまま |
| 4 | `results/swiftinterface/IosLibrary-after-0f.swiftinterface` は 0f の最後の直しの前の版で、HEAD と違う（1.4 の偏り 10） | **0f の記録はそのままにし、C1 の差分は新しく足した `IosLibrary-before-1b-f3c289d7.swiftinterface` を基準にする**（この記録に理由を書いた）。古いファイルを差し替えると 0f の差分の意味が変わるため |

## 3. C1 のレビューと直したこと

コードのレビュー（Claude の B・C、Codex の C。A は無し）の指摘と、直したこと。

| 指摘 | 直したこと |
|---|---|
| B-1: `Log` の公開の DocC の移り方の例が internal の `.libraryDebug` を使う | `logger.debug("…\(requestID, privacy: .public)")` にした |
| B-2: エラーのログが case の名前だけで、中の system のエラーの domain と code が消える | `LogRedaction.describe` を、関連値が 1 つのエラーだけの case で `<型>.<case>(domain=…, code=…)` にした（1.4 の偏り 13）。`LogRedactionTests.describeAddsTheDomainAndCodeOfAnInnerError` を足した |
| B-3: 基点で `permittedArrowDirections = []` にしている | 消した。矢印の向きは今の値のまま（1.4 の偏り 14） |
| B-4: UT-15 の通知は Manager の層だけ | 1.5 の UT-15 の行と 1.11 に書いた |
| C: 1.5 の UT-02・UT-04 の件数 | 直した（UT-02 は 8、UT-04 は 22） |
| C: `ClipboardRedaction` の DocC が UTI を出してよい値としている | UTI は `.private` で出すと書いた |
| C: `PresenterSelection` の DocC（`.firstActiveScene` で Share は今の確かめで失敗しうる、表示しない口での意味） | 表の `.firstActiveScene` の行に Dialog と Share の違いを書き、表示しない口での 3 つの値の意味を足した |
| C: `RequestBox`・`PresenterSelection` の DocC が C2 以降の口を指す | 残し、「2.0.0 の後のコミットで足す」（`- Note:`）と書いた |
| C: 先頭のログが無い所 | `PresenterSelection.viewController(_:)`、`ForegroundLocator.firstActiveSceneTop`・`foregroundTop`、`UIKitPresentationEnvironment` の全メソッドに足した。`PresentationProcedure.present` の先頭で表示する ViewController の型を出すようにした |
| C: `getRootViewController()` のログの変わり方を 1.4 に書く | 1.4 の偏り 12 |
| C: M5 は `ReleaseWatch` に自分の確かめが無いので `RequestBox.close` を壊している | 1.5 の M5 の行に書いた |
| C: `anchorPopover` で `node.view` を使う、`.provided` の型の変換に失敗したときの黙った `notForeground` に注釈 | `node.view` にし（読み込まれていなければ読み込む）、`present` と `requireForeground` の 2 か所に注釈を足した |
| Codex C: 見張りの最後の持ち主を背景のスレッドで手放すテスト | `ReleaseWatchTests.freedOnABackgroundThreadDeliversOnMainOnce`（箱が閉じ、完了は main で 1 回、止まらない） |
| Codex C: 偽の環境で、待ちを断りながら完了も呼ぶ（その場で・後で） | `FakeViewController.refusedWaitStillCalls` を足し、`aRefusedWaitWhoseCompletionStillComesChecksOnce`（2 通り）で、探し直しが 1 回、表示が 1 回であることを確かめた |

直した後の確かめ（iPhone 17 / 26.2、Xcode 26.3）:

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件 | 270/270（1.8 の 267 + 3） |
| TSan（Common の 8 つの suite） | 59 件のうち 58 件成功、1 件 skip（`aRealViewControllerClosesTheBoxWhenFreed`。1.5 の理由）。TSan の報告は 0 件 |
| 2 つの scheme の clean・whole-module のビルド | Xcode 26.3 と 26.6 の両方でエラー 0、警告 0 |
| UI テスト | 流していない。画面に見える動作は変えていない（ログの文言、DocC、まだどの口も使っていない表示の手順の基点だけ） |
