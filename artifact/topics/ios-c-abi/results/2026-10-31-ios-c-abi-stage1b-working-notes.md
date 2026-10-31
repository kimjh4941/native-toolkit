# 段階 1b の作業の記録（Swift の API の補完）

- 記録日: 2026-10-31
- 段階: 1b（`README.md` の 5 章の 1b の行。設計書は `designs/2026-10-31-ios-c-abi-swift-api-design.md`。以下「設計書」）
- ブランチ: `feature/NTKIT-18`（C1 は HEAD `f3c289d7` の上の未コミットの変更で、`584ec55c` でコミットした。C2 は `584ec55c` の上の未コミットの変更）
- 環境: Xcode 26.3（17C529、Swift 6.2.4、`xcode-select` のまま）。0 件の警告の確かめだけ Xcode 26.6（17F113、Swift 6.3.3）でも組んだ（`DEVELOPER_DIR` でコマンドごとに選んだ）。シミュレーターは iPhone 17（iOS 26.2）、iPhone 16（iOS 18.3.1）、iPad Pro 11-inch (M4)（iOS 18.3.1）だけ。**実機には触れていない**
- 章: コミットごとに 1 章（設計書 15.1 の C1〜C7）。この版は C1（1〜3 章）と C2（4〜6 章）

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

## 4. C2 Dialog（T-06〜T-09、T-22）

- 状態: ライブラリ・単体テスト・壊して確かめる・シミュレーターでの単体テストの全件と Dialog の UI テスト（今の 21 件）は済んだ。コードのレビューの指摘を直した（6 章）。コミットはしていない
- **追記（6 章）**: 利用者の承認で、信頼する部分を含む patch をリポジトリに当て、レビューの指摘をその上で直した。信頼する部分のハッシュ（`scripts/ios_ui_runner.py` の `TRUSTED_FILES`）は、直した後の信頼する部分を別のモデルが再レビューしてから更新する。それまでランナーは信頼する部分が変わったと警告し、実機では流さない（下の「止めたところ」の段落は patch を当てる前の記録）
- **止めたところ**: 新しいボタン（SA-01〜SA-05）を UI テストから押すには、UI テストの信頼する部分（`Support/SampleApp.swift` の `DialogButton` と、D22 の Control Center の操作を足す `Support/Springboard.swift`）を変える必要がある（UI テストの設計書 U-17: サンプルの識別子の文字列は信頼する部分にしか書けない。I1a は `DialogButton.allCases` と照らす）。信頼する部分の変更は別のモデルのレビューとハッシュの更新が要るので、**リポジトリには入れず**、変更一式（サンプルの SA-01〜SA-05、信頼する部分の 2 ファイル、D16〜D23、`DeviceRequirements.json`、UI テストの設計書 5.1 の一覧）を patch にまとめ、リポジトリを写した使い捨ての場所でだけ当てて流した（4.8）。patch と記録は scratchpad に置いた
- リポジトリに入れたもの: ライブラリ、テストのホストのアプリ、単体テスト、SA-16（ログインの結果の行のパスワードを長さだけにする）と D12 の期待値、swiftinterface、この章

### 4.1 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| Domain（T-06） | `Dialog/Domain/Model/DialogRequest.swift`（新、public） | 6 種の要求（付録 A の既定のとおり）。internal の `kindName`（ログ用） |
| Domain（T-06） | `Dialog/Domain/Model/DialogAnswer.swift`（新、public） | `Button`（`primary`・`cancel`・`destructive`・`option(index:)`）、`button`・`title`・`input`。`public init(button:title:input:)`（5 章の 3 の決定で足した） |
| Domain（T-06） | `Dialog/Domain/Model/DialogInput.swift`（新、public） | `text(String)`・`login(username:password:)`。`description` は長さだけ（`text(length: 5)`、`login(username: length 4, password: length 7)`） |
| Domain（T-06） | `Dialog/Domain/Model/DialogError.swift`（新、public） | 5 つの case と英語の固定の `errorDescription` |
| Application（T-06） | `Dialog/Application/Port/DialogPresenting.swift`（新、public） | port。外の実装者向けの約束（完了は main で 1 回、呼び出しの中で呼ばない、出す前に `box.isClosed` を見て閉じていれば出さずに `.failure(.canceled)`）と、ライブラリの実装だけが持つもの（`cancel(_:)` で閉じる、UseCase の使い回しの検査）を DocC に書いた（6 章の B1） |
| Application（T-06） | `Dialog/Application/UseCase/ShowDialogUseCase.swift`（新、public） | 箱が既に別の要求に付いていれば port を呼ばず `invalidRequest`（main に積む）。付いていなければ port を呼ぶ |
| Presentation（T-07） | `Dialog/Presentation/AlertDialogPresenter.swift`（新、internal） | `AlertSpec`（要求か今の口の引数から作る見た目）、`DialogSession`（alert を `weak` で持ち、observer の token を持ち、取り消しで閉じる。表示の途中の取り消しは `present` の完了で閉じる）、`AlertDialogPresenter<Environment>`（port の実装と、今の口の入口 `presentLegacy`）、internal の protocol `DialogPresentationCore` |
| Manager（T-08） | `Dialog/IosDialogManager.swift` | `show(_:presenter:requestBox:completion:)`、`show(_:presenter:) async throws`、`cancel(_:)`、`foregroundViewController()` を足し、今の 7 つの口を `presentLegacy` に載せ直した（形は変えない）。DocC の「既知の穴」を新しい振る舞いに書き直した |
| 共通（C1 の直し） | `Common/Application/RequestBox.swift` | internal の `isAttached`（UseCase の使い回しの検査）。DocC の「後のコミット」の注を Dialog の分だけ直した |
| 共通（C1 の直し） | `Common/Presentation/PresentationProcedure.swift` | `present` と `PresentationEnvironment.present` に `animated` を足した（今の `showDialog`・`showActionSheet` の `animated` を保つため）。補いの注に MS-01 の結果を書いた |
| 共通（C1 の直し） | `Common/Domain/PresenterSelection.swift` | DocC の「後のコミット」の注を Dialog の分だけ直した |
| テストのホスト | `IosLibraryTestHost/TestHostAppDelegate.swift`（新）、`IosLibrary.xcodeproj/project.pbxproj` | 1.11 の申し送り。ターゲット `IosLibraryTestHost`（app。scene の manifest を生成し delegate なし、window なし。`IosLibrary.framework` を埋め込む）を足し、`IosLibraryTests` に `TEST_HOST`・`BUNDLE_LOADER` と依存を足した。scheme は変えていない |
| テスト | `IosLibraryTests/Dialog/` の 3 ファイル（新）と `IosDialogManagerTests.swift`、`Common/Support/HostAppSupport.swift`（新）、`FakePresentationEnvironment.swift`、`ForegroundLocatorTests.swift`、`LibraryLogPrivacyTests.swift` | 4.5 |
| サンプル（SA-16） | `IosLibraryExample/DialogSampleView.swift` | ログインの結果の行を `password: <length=7>` にした |
| UI テスト（13.3） | `IosLibraryExampleUITests/DialogUITests.swift` | D12 の期待値を `password: <length=7>` にした |
| 公開 API | `results/swiftinterface/IosLibrary-after-1b-c2.swiftinterface`、`2026-10-31-stage1b-c2.diff` | 4.6 |

### 4.2 公開 API（付録 A の Dialog との照合）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public enum DialogRequest: Sendable, Equatable`（6 case と既定） | 同じ | 一致 |
| `public struct DialogAnswer: Sendable, Equatable`（`Button`、`button`・`title`・`input`） | 同じ。5 章の 3 の決定で `public init(button:title:input:)` を足した（付録 A に追記） | 一致 |
| `public enum DialogInput: Sendable, Equatable, CustomStringConvertible` | 同じ | 一致 |
| `public enum DialogError: Error, Sendable, Equatable, LocalizedError` | 同じ。payload の無い enum なので `Hashable` が自動で付き、swiftinterface に `extension DialogError : Swift.Hashable {}` が出る | 一致（自動の準拠だけ多い） |
| `public protocol DialogPresenting: Sendable { func present(_:presenter:box:completion:) }` | 同じ | 一致 |
| `public struct ShowDialogUseCase: Sendable { init(presenter:); execute(_:presenter:box:completion:) }` | 同じ | 一致 |
| `@discardableResult show(_:presenter: = .firstActiveScene, requestBox: = nil, completion:) -> RequestBox` | 同じ | 一致 |
| `show(_:presenter: = .firstActiveScene) async throws -> DialogAnswer` | 同じ。5 章の 4 の決定で `@discardableResult` を付けた（付録 A に追記） | 一致 |
| `cancel(_ box: RequestBox)` | 同じ（どのスレッドからでも、待たない） | 一致 |
| `@MainActor foregroundViewController() -> UIViewController?` | 同じ | 一致 |

今の 7 つの口と `getRootViewController()` の宣言は swiftinterface で 1 文字も変わっていない（C1 の swiftinterface の行がすべて C2 にある。並びだけ変わった）。公開の記号にはすべて DocC を付けた。`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` は足していない（P1-17 の一覧の外のものは 0）。

### 4.3 今の利用者から見て変わる動作（3.3 の Dialog の 2 行の中身）

| 口 | 前 | 後 |
|---|---|---|
| `showLoginDialog` の失敗 | `onLogin(nil, nil, nil, false, "Failed to get root view controller")`、`completion` は来ない | `completion(false, "Failed to get root view controller")`、`onLogin` は来ない |
| 7 つの口で UIKit が表示を断った（前面の ViewController がもう別のものを出している、閉じかけの ViewController の上に出そうとした、など） | 何も来ない | `completion(false, "Failed to present the dialog")` が 1 回 |
| 外から閉じた、scene が切れた | 何も来ない | 何も来ない（変わらない。DocC に書いた） |
| 循環参照・observer | 確定ボタンの handler と observer が alert を強く持ち、observer は外れない | 弱く持ち、どの終わり方でも閉じたときに外す（UT-14） |
| ログ | - | 失敗のログは `[<口の名前>] Failed to get root view controller`（`.error`）。入力の値は出さない |
| ボタンの callback の時機 | ボタンの handler の中で直に呼んだ | handler は箱を閉じ（`box.close`）、callback は main の次の回（`DispatchQueue.main.async`）に呼ぶ。main で 1 回は変わらない。ボタンを押した直後に同じ回の中で callback が来たことに頼るコードは、1 回分遅れる |

単体テスト（4.5）で次の状況だけ挙動が変わった: 前のアラートを閉じた直後（閉じる処理の途中）に次の `show...` を呼ぶと、前は UIKit が黙って断り何も来なかったが、今は `completion(false, "Failed to present the dialog")` が来る。上の 2 行目と同じ変更で、3.3 の「UIKit が表示を断ったときに `completion(false, …)` が 1 回来る」に当たる。今の UI テスト（D1〜D15）はこの状況を作らないので結果は変わらない（4.8）。

### 4.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | 6.1 に `IosLibrary.xcodeproj` の変更はプライバシーマニフェストだけ。13 章は「UIKit を要るものはテストのホストのアプリの上で動かす」 | `IosLibraryTestHost` のターゲットを足し `IosLibraryTests` のホストにした | 本物のアラートを出す UT-08・UT-09・UT-14・UT-15 の Dialog の分と、`NotificationRepositoryImpl` を本物の center で通す UT-15（1.11 の申し送り）にホストが要る。ホストは window を持たないので、今の「前面が見つからない」経路のテストはそのまま通る。window を作るテストと「window が無い」ことに頼るテストは `withHostScreen`（1 つずつ通す鍵）の中で動く |
| 2 | 6.3.2 は付ける処理だけ | `RequestBox` に internal の `isAttached` | UseCase が「箱の使い回し」を port を呼ぶ前に検査するため（8.1.1）。付ける処理そのものも 2 つ目を断るので、同時に 2 つ渡した場合も `invalidRequest` |
| 3 | 6.3.3 の段に `animated` は無い | `PresentationProcedure.present` と環境の `present` に `animated`（既定 `true`） | 今の `showDialog(animated:)`・`showActionSheet(animated:)` の値を保つため（S-P5「形は今のまま」） |
| 4 | 8.1.1 の Presentation は `AlertDialogPresenter` だけ | `AlertDialogPresenter` を `PresentationEnvironment` で generic にし、今の口の入口を internal の protocol `DialogPresentationCore`（`presentLegacy`）に置いた。要求ごとの状態は `DialogSession` | UIKit が断る経路（補いと見張り）と「断ったのに完了も呼ぶ UIKit」を、本物の UIKit で作れないので偽の環境で確かめるため（UT-10）。Manager はこの protocol の値を持ち、テストは internal の `init(core:)` で差し替える |
| 5 | 8.1.4「今の口のボタンの callback は今と同じ値」 | 同じ値。ただし `showTextInputDialog` の `onConfirm` の入力と、`showLoginDialog` の `onLogin` のユーザー名・パスワードは、`UITextField.text` が `nil` のとき `""`（前は `nil`）。`UITextField.text` は空でも `""` を返すので、実際には同じ | 新しい芯の `DialogInput.text`・`DialogInput.login` が `String` のため |
| 6 | MS-01 の「表示の途中の `dismiss` が無視されるか」（R4-2 の前提） | 無視されなかった（4.7）が、`present` の完了で閉じる形は残した | 無視されない環境でも完了の後に閉じれば同じ結果になり、無視される OS（R4-2 の見込み）でも閉じられる。このため M13（4.5）は捕まらない |
| 7 | G-6 の「`isKeyWindow` が真の window がアプリで 1 つ」 | iPad / 18.3 で 2 つの scene を並べると、どちらも `foregroundActive` で key window が 2 つになった（4.7）。`.foreground` は C1 のまま（active を先に、2 つ以上なら `.info`。どちらを選ぶかは `connectedScenes` の順） | P1-11 の「成り立たなければ `foregroundActive` だけにする」は、この崩れ方（両方 active）を直さない。利用者に決めてもらう（5 章の 2） |
| 8 | 12 章の SA-01 は `show(_:presenter:.foreground)` のボタン | SA-01 は `async` 版、SA-02〜SA-05 は callback 版（patch の中） | `ios.md` の「新しく足すボタンは `async` 版」。SA-03 は箱が要り、箱は callback 版にしか渡せない |
| 9 | 13.2 D23 は「D6 と SA-01 のアクションシート」 | D23 を 1 つのテストにし、どの端末でも今の口と新しい口のアクションシートを 1 回ずつ出す（patch の中） | iPad だけで動くテストにすると skip が意図した skip の一覧（ランナー）に要る。iPhone でも同じ確かめになり害がない |
| 10 | 12 章の SA-03・SA-04 は「1 秒後」 | 3 秒後（patch の中）。`showAfter3Seconds` の結果の行に要求の時点の scene の状態を足した（`[show.alert@foregroundInactive] …`） | 1 秒では UI テストが Dialog の出たことを確かめる前に消えた（4.8）。状態は D22 が Control Center を本当に引き出せたかを確かめるため（引き出せていなくても Dialog は出るので、それだけでは G-6 を確かめられない）。レビューの後、SA-03・SA-04 は取り消す・外から閉じる時点で Dialog が出ていたかも結果の行に足した（`shown=true`・`covered=true`。6 章の B2）ので、テストは Dialog を時間内に捕まえなくてよい。3 秒は残した |
| 11 | 13.2 D23「iPad で D6 が落ちずに出る」 | サンプルの今の口のアクションシートの基点を view の中央の点にした（patch の中） | 4.8 の iPad の行。ライブラリの今の口の基点の規則（`sourceRect ?? sourceView.bounds`）は変えていない（S-P5・S-P6） |
| 12 | `ios.md` の「callback の新しい口は既定を持たない」 | callback の `show(_:presenter:requestBox:completion:)` は既定 `.firstActiveScene` を持つ（付録 A のまま） | 既定を持たない規則は、今の callback の口と引数のラベルだけで呼び分けが決まる Share（S-P18）のため。Dialog の今の口は名前が別（`showAlert` など）なので、既定があっても呼び分けは崩れない。`ios.md` に例外として書いた（6 章の C1） |

### 4.5 単体テストと壊して確かめたこと

| ID | ファイル | 件数 | 中身 |
|---|---|---|---|
| UT-07 | `Dialog/ShowDialogUseCaseTests.swift` の `DialogRequestTests`・`ShowDialogUseCaseTests` | 3 + 5 | 既定の文言、`DialogInput` の説明が長さだけ（`String(reflecting:)` と答えの説明でも）、エラーの文言、port に渡る値、port の結果、使い回しの箱は port を呼ばず main で `invalidRequest`（呼び出しの中では来ない）、付ける前に閉じた箱は断らない |
| UT-08 | `Dialog/AlertDialogPresenterTests.swift` | 7（6 章で 8） | 6 種の組み立て（ボタンの題・style、入力欄の数、style）、入力欄の placeholder・secure・content type、`.primary` の入力と `.cancel` の `nil`（テキスト入力とログイン）、選択肢と destructive の答え、入力が要るときの確定ボタンの有効・無効、アクションシートの基点（popover があれば表示元の view の中央。iPad では popover が必ずある）、window が無いと `notForeground`、付いた箱は出さずに `invalidRequest` |
| UT-09 | 同上 | 5 | 開く前、表示の途中（`present` の完了で閉じる）、表示の後（背景のスレッドから取り消す）、上に重なったとき（閉じない、残ったボタンは効かない）、答えの後（何もしない） |
| UT-14 | 同上 | 1 | ログイン（入力が要る形）を、ボタンと取り消しのそれぞれで閉じた後、alert が解放され、observer の token が NotificationCenter から外れる（`weak` で確かめる）。TSan の回は skip（6.3.4） |
| MS-01 | 同上 | 2 | UIKit は `present` の中で `presentingViewController` を設定し、`transitionCoordinator` があり、既に出している ViewController への 2 つ目の `present` を断って完了を呼ばない。同じ回の 2 つの要求（`.foreground`）が 2 つとも出て、2 つ目が上 |
| UT-10 | `Dialog/IosDialogManagerTests.swift`（今の 9 件） | 9 | 今の 8 件はそのまま（`withHostScreen` の中で動くようにしただけ）。`showLoginDialogFailsThroughOnLogin…` を `showLoginDialogFailsThroughCompletion…` に替えた（失敗は `completion` だけ、`onLogin` は来ない） |
| UT-10 | `Dialog/IosDialogManagerShownTests.swift` | 6 | 6 つの口のボタンの callback の値が今と同じ（`showAlert`・確認の Yes と No・destructive・アクションシートの選択肢とキャンセル・テキスト入力の確定とキャンセル・ログインのログインとキャンセル）、`completion(true, nil)` が先に 1 回、`showDialog` は渡した action と入力欄をそのまま使い、無ければ OK、UIKit が断ると `completion(false, "Failed to present the dialog")` が 1 回（断ったのに完了も呼ぶ UIKit でも 1 回）、外から閉じると今の口は何も呼ばず新しい口は `dismissedBySystem`（TSan の回は skip） |
| UT-11 ほか | 同上 | 6 | 新しい口: 渡した箱を返す・作った箱を返す・使い回しは `invalidRequest` で最初の要求は続く・完了は main で 1 回。`foregroundViewController()`。`async` 版: 答えを返す、`DialogError` を投げる、`Task` の取り消しで箱を取り消し `CancellationError` と Dialog を閉じる、呼ぶ前に取り消された `Task` は何も出さない |
| UT-02（見直し） | `Common/ForegroundLocatorTests.swift` | 1 → 2 | `withoutScenesBothSearchesFindNothing` を `withoutAKeyWindowBothSearchesFindNothing` にした（ホストには scene が 1 つあり window が無い）。本物の scene の上で、閉じかけの ViewController を今の探し方はたどり新しい定義は止まることを足した |
| UT-15 | `Common/LibraryLogPrivacyTests.swift` | +2 | Dialog: 新しい口と今の口のテキスト入力・ログインに番兵の値を入れて確定し、ライブラリのログに番兵が無い（読めていることを `#require`）。通知: `NotificationRepositoryImpl` を本物の center で（1 時間後の予約、すぐ取り消す）番兵の題・副題・本文・userInfo の値で通し、ログに番兵が無い（1.11 の申し送り）。それぞれ自分の番兵を使う（前のテストのログが読み取りの窓に入るため） |

C2 で足したのは 38 件、名前を替えたのが 2 件（上の 2 つ）。`IosLibraryTests` は 308 件（C1 の 270 件 + 38）。6 章のレビューの直しで 6 件足し、314 件になった。

壊して確かめたこと（壊した版で組んで該当の suite を流し、落ちることを見てから戻した。差分とログは scratchpad）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M9 | UT-07 | 既定の文言を変える（`"OK"` → `"Ok"`） | `defaultTextsAreTheOnesOfTheShowMethods` |
| M10 | UT-07 | 使い回しの検査を外す | `aBoxThatAnotherRequestUsesIsRefusedWithoutCallingThePort`、`theRefusalIsNeverDeliveredInsideTheCall`。**最初の版は Mock が答えないので止まった**（終わらない待ち）。待ちに 5 秒の上限を付け直してから落ちることを確かめた |
| M11 | UT-08 | キャンセルでも入力を返す | `thePrimaryButtonReportsTheInputAndCancelReportsNone` |
| M12 | UT-09 | 重なっていても閉じる | `cancelledUnderAnotherViewControllerItStays`。**最初の版（0.5 秒見る）では落ちなかった**。下調べで、重なった alert の `dismiss` は上の画面を約 0.2〜0.5 秒で消すと分かったので、1.5 秒見る形にしてから落ちることを確かめた |
| M13 | UT-09 | 表示の途中の取り消しで、`present` の完了を待たずにその場で閉じる | **落ちない**。この環境の UIKit は表示の途中の `dismiss` を無視せず、完了の後に閉じる（4.7）ので、どちらの形でも同じ結果になる。待つ形は R4-2 の守りとして残す（4.4 の 6） |
| M14 | UT-10 | ログインの失敗を `onLogin` にも返す | `showLoginDialogFailsThroughCompletionOnTheMainThreadExactlyOnce` |
| M15 | UT-11 | `Task` の取り消しで箱を閉じない | `cancellingTheTaskCancelsTheRequest`、`aTaskCancelledBeforeTheCallShowsNothing`（どちらも待ちに上限を付け、止まらずに落ちる） |
| M16 | UT-14 | ボタンの handler が alert を強く持つ | `theAlertAndItsObserversAreFreedAfterItCloses` |
| M17 | UT-14 | observer を外さない | 同上 |
| M18 | UT-14 | 形だけ変える: handler が alert を配列に入れて持つ（間接参照を 1 つ挟む） | 同上 |
| M19 | UT-15 | ボタンのログに入力欄の値を `.public` で入れる | `dialogInputsNeverReachTheLog` |
| M20 | UT-10 | 今の口の失敗の文言を変える | `aDeclinedPresentationFailsThroughTheCompletionOnce` |
| M21 | UT-10 | 失敗の後の `present` の完了でも `completion(true, nil)` を出す | **最初は落ちなかった**（偽の UIKit が完了を呼ばない形だけだった）。断ったのに完了も呼ぶ偽の UIKit のテスト（`aDeclinedPresentationWhoseCompletionStillComesFailsOnce`）を足してから落ちることを確かめた |

### 4.6 公開 API（swiftinterface）

- 組み方: C1 と同じ（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）
- 足したファイル: `IosLibrary-after-1b-c2.swiftinterface`、差分 `2026-10-31-stage1b-c2.diff`（`after-1b-c1` が基準）
- 差分の中身: `DialogRequest`・`DialogAnswer`・`DialogInput`・`DialogError`（と自動の `Hashable`）・`DialogPresenting`・`ShowDialogUseCase` と、`IosDialogManager` の `show` 2 つ・`cancel(_:)`・`foregroundViewController()` が増えた。C1 の行で消えたものは無い（今の口は並びが変わっただけ）
- `swift-frontend -typecheck-module-from-interface`（Xcode 26.3）で型検査が通った

### 4.7 シミュレーターで測ったこと（C2 に付いた MS-01・MS-02 と MS-03 の Dialog の分）

| ID | 環境 | 方法 | 結果 |
|---|---|---|---|
| MS-01 | iPhone 17 / 26.2、iPhone 16 / 18.3.1 | ホストのアプリの単体テスト（使い捨ての下調べと、残した `uikitBehavesAsThePresentationProcedureAssumes`・`twoRequestsInTheSameTurnAreBothShown`） | `present` の直後に `presentingViewController` が設定される（**補いは残す**）。直後に `transitionCoordinator` がある。`present` の完了の中ではまだ coordinator があり落ち着いていない（次の回に確かめる 5.13.2 の段 5 のとおり）。既に出している ViewController への 2 つ目の `present` は断られ、完了は呼ばれない。同じ回の 2 つの要求（`.foreground`）は 2 つとも出て、2 つ目が 1 つ目の上（D17 の期待値のとおり）。**表示の途中の `dismiss` は無視されず、表示の後に閉じた**（4 通り、両方の OS）。最初の下調べで 1 度だけ「残った」が、直前のアラートを閉じる処理と重なった形で、組み直した下調べでは再現しなかった |
| MS-02（G-6 の 1） | iPhone 17 / 26.2 | D22（patch の中、4.8）。サンプルは要求の時点の scene の状態を結果の行に出す（`[show.alert@<状態>]`） | Control Center を引き出した間（`foregroundInactive`）に `.foreground` の要求が出て、閉じた後に答えられた。**G-6 の 1 つ目（inactive の間も表示できる）は成り立つ**。後ろにいる間（D21）は `background` で `notForeground` |
| MS-02（G-6 の 2） | iPad Pro 11-inch (M4) / 18.3.1、iPad (A16) / 26.2 | ホストのアプリから 2 つ目の scene を開き、両方の scene に window を作って `makeKeyAndVisible` | 18.3: 2 つの scene が並び、**どちらも `foregroundActive` で、key window が 2 つ**。`.foreground` と今の探し方は同じ方を選び、アクションシートはそこに出た。26.2: 2 つ目の scene が前に出て 1 つ目は `background`。key window は 2 つ（1 つは後ろの scene）で、`.foreground` は前の scene を選んだ。→ G-6 の「key window がアプリで 1 つ」は iPad で成り立たない（4.4 の 7、5 章の 2） |
| MS-03（Dialog） | iPad Pro 11-inch (M4) / 18.3.1、iPad (A16) / 26.2、iPhone 17 / 26.2 | ホストのアプリで `.foreground` の alert を外から `dismiss(animated: true)`（5 回）。iPhone は D20 | 0.41〜0.45 秒で解放され、見張りが `dismissedBySystem` で閉じた（申し送り 1 の約 0.5 秒と同じ）。D20（サンプルが外から閉じる）も `dismissedBySystem` が 1 回 |

### 4.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPad Pro 11-inch (M4) / 18.3.1、iPhone 16 / 18.3.1。`xcodebuild test -parallel-testing-enabled NO`） | どれも 308/308。skip は 0（UT-14 などの TSan の skip は通常の回では効かない）。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）の `IosLibraryTests` 211 件のうち消えたのは名前を替えた `IosDialogManagerTests/showLoginDialogFailsThroughOnLoginOnTheMainThreadExactlyOnce` の 1 件だけで、ほかは同じ名前で成功 |
| `scripts/test_ios.sh --feature Dialog`（iPhone 17 / 26.2、リポジトリ） | 21/21 成功（Navigation 2、IdentifierInventory 4、Dialog D1〜D15）。基準との比べ合わせは `changed=0, added=0, removed=0`。D12 は期待値を変えて成功。信頼する部分のハッシュの照合は通った（警告なし） |
| 同じもの（patch を当てた使い捨ての写し、iPhone 17 / 26.2） | 29/29 成功（Navigation 2、IdentifierInventory 4、Dialog D1〜D23）。基準との比べ合わせは `changed=0, added=8, removed=0`（足したのは D16〜D23）。I1a は 17 のボタンで一致した。ランナーは信頼する部分の 2 ファイルが変わったと警告した（シミュレーターでは流れる）。**最初の回は D18・D20 が落ちた**（1 秒後に閉じる Dialog を、ボタンの位置までスクロールして押す間に見逃した）。サンプルの待ちを 3 秒にして通した（4.4 の 10） |
| D23 ほか（patch、iPad Pro 11-inch (M4) / 18.3.1。`xcodebuild test -only-testing` で D6・D7・D14・D16・D23） | 落ちる例外（`NSGenericException`）は 1 度も出ない。D16（新しい口の 6 種。アクションシートを含む）は成功。**今の口のアクションシート（D6、D23 の前半）は選択肢が出なかった**: サンプルが `sourceView: rootVC.view, sourceRect: nil` を渡し、今の口は `sourceRect` が `nil` なら `sourceView.bounds` を基点にする（1b の前から同じ）ので、画面全体を基点にした popover に置き場が無い。1b の前のコード（HEAD）でも D6 は同じく落ちた（C2 の後退ではない）。サンプルの基点を view の中央の点にすると（patch の中）、iPad で D6・D14・D23 が成功し、iPhone 17 / 26.2 でも D6・D7・D14・D23 が成功した。D7 は iPad では落ちる（D7 は OS の版で「iOS 18 はキャンセルのボタンがある」と決めているが、iPad の 18 は popover。D23 の範囲の外で、0c からの D7 の前提） |

### 4.9 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6 | どちらもエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ。ホストのアプリが増えた分も同じ） |
| patch を当てた写しの `IosLibraryExample` の scheme（Xcode 26.3） | エラー 0、警告 0 |

### 4.10 後のコミットへの申し送り

| 項目 | 内容 |
|---|---|
| ホストのアプリ（C3〜C6） | 本物の UI を出すテストは `withHostWindow`、window が無いことに頼るテストは `withHostScreen` の中に置く（`Common/Support/HostAppSupport.swift`）。Share の `ShareSheetPresenter` の UT-12 もホストで本物のシートを出せる |
| 信頼する部分（C3〜C6） | Share・Clipboard・通知の新しいボタンも `SampleApp.swift` の列挙に足す必要がある。C2 の patch のレビューのときに、残りのコミットの分をまとめてレビューするか決める（5 章の 1） |
| `presentLegacy` | Share の今の口も同じ形（`FirstActiveScenePolicy.requireLegacyStability`）で載せ直せる |

## 5. 利用者に決めてもらうこと（C2）

**決定（2026-10-31、利用者）: 5 つとも推奨のとおり。** 3・4 は `DialogAnswer` の `public init` と `async` 版の `@discardableResult` を足し、付録 A に書いた。2 は `PresenterSelection.foreground` の DocC に `- Important:` を足した（マニュアルは段階 4、C ABI のヘッダーは 2a で書く）。1 は C2 のコードのレビューに patch を含めて出す

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | D16〜D23 と SA-01〜SA-05 には UI テストの信頼する部分（`SampleApp.swift` の `DialogButton` の 11 個と `DialogCover`、`Springboard.swift` の Control Center の 2 つの操作）の変更が要る。patch は用意し、写しで 29/29 通した | **patch を別のモデルのレビューに出し、通ったらリポジトリに当ててハッシュを更新し、C2 のコミットに入れる**。C3〜C6 も同じ変更が要るので、レビューの観点（識別子を足すだけか、操作を足すか）を先に決めておくと速い |
| 2 | G-6 の 2 つ目の前提（key window がアプリで 1 つ）は iPad で崩れる（両方の scene が active で key window が 2 つ）。`.foreground` はどちらかを選ぶ（順は決まらない） | **今の形のまま（active を先に、2 つ以上なら `.info`）にし、複数の window の iPad では `.viewController(_:)` で表示元を渡すことを DocC・マニュアル・C ABI のヘッダーに書く**。P1-11 の代わりの案（`foregroundActive` だけ）はこの崩れ方を直さない。第 1 部の G-6 と README は C7（T-20）で直す |
| 3 | `DialogAnswer` の `init` が公開されていない（付録 A のとおり）ので、公開の port `DialogPresenting` を自分で実装する利用者は成功の答えを作れない | **`public init(button:title:input:)` を足す**（付録 A の追加。破壊的でない）。決まるまでは付録 A のとおり internal |
| 4 | `show(_:presenter:) async throws -> DialogAnswer` に `@discardableResult` が無い（付録 A のとおり）。`ios.md` は「`async throws` 版には付ける」 | **付ける**（`_ = try await` を書かずにアラートを出せる）。付録 A を直す |
| 5 | iPad で今の口のアクションシートに `sourceRect` を渡さないと、選択肢の無い popover になる（1b の前から。4.8） | **ライブラリの今の口は変えず（S-P5）、サンプルの基点を中央の点にする**（patch に入れた）。DocC の `sourceRect` の説明に「`nil` は `sourceView` 全体で、iPad では大きな view に向かない」と書くのは C3 の Share と合わせて決める |

## 6. C2 のレビューと直したこと

コードのレビュー（Codex の A、Claude と Codex の B・C）の指摘と、直したこと。利用者の承認で、信頼する部分を含む patch（4 章の「止めたところ」）をリポジトリに当ててから直した。信頼する部分のハッシュは、直した後の信頼する部分を別のモデルが再レビューしてから更新した（この章の終わりの「信頼する部分の再レビュー」）。

| 指摘 | 直したこと |
|---|---|
| Codex A: `Springboard.openControlCenter()`・`closeControlCenter()` が決まった座標をドラッグするだけで、何も確かめない。D22 の宣言は `systemui` だけなので、`--device-allow systemui` で私物の iPhone でもドラッグし、コントロールに当たって設定を変えうる | 2 層にした。(1) 信頼する部分の `Support/Springboard.swift`: 2 つとも、実機（`session.isDevice`）なら操作の前に throw する（文言に system のラベルは無い）。(2) `scripts/ios_ui_runner.py` に、`--device-allow` が何であっても実機の一覧に入れないテストの表 `SIMULATOR_ONLY_TESTS` を足した（D22 と、C10 の D17・D20・D21・D23）。選ぶ所（`select_tests`。一覧に `simulator only` と出る）、計画を作る所（`make_plan`）、実機の名指しの直前（`only-testing`）の 3 か所で照らす。表のキーが宣言に無ければ（名前を変えたら）2 の照合で止まる。`simulator-only` は区分ではないので `--device-allow` に書けない。UI テストの設計書（6.1 の `Springboard` の行、6.3 の 3）と `agent-rules/device-testing.md` に書いた |
| B1: `DialogPresenting` の DocC が、外の実装者にできないこと（`RequestBox` の close・attach・outcome は internal、UseCase の使い回しの検査は `isAttached` 頼み）を約束している | 外の実装者向けに書き直した: 完了は main で 1 回・呼び出しの中で呼ばない、出す前に `box.isClosed` を見て閉じていれば出さずに `.failure(.canceled)`、ボタンは `DialogAnswer(button:title:input:)` で返す。`cancel(_:)` で閉じる・使い回しの検査はライブラリの実装だけで効く（自分の実装では `cancel(_:)` は箱を閉じるだけ）と書いた。`ShowDialogUseCase` の DocC にも 1 文足した。公開の API は足していない |
| B2: D18・D20（と D19 の上の画面）が、決まった時間のタイマーと XCUITest が Dialog を見つけるのとの競争になっている | サンプルが、取り消す・外から閉じる時点の状態を結果の行に足す: SA-03（`showThenCancel`）と SA-04 は `shown=<前面が UIAlertController か>`、上に重ねる方は `covered=<上の画面が Dialog の上にあり前面か>`。テストは Dialog を時間内に捕まえず、結果の行の `shown=true`・`covered=true` を比べる。D19 は、サンプルが上の画面を閉じた後に Dialog が残っていること（`waitShown`）を見る（Dialog を閉じていれば上の画面ごと消える）。識別子は信頼する部分の外に増やしていない（U-17） |
| B3: D22 が `Thread.sleep(5)` の後に `alert.exists` | `alert.waitShown(timeout: SampleApp.dialogTimeout + 3)` にした（要求はタップの 3 秒後）。D21 の後ろでの 5 秒の待ちは避けられない（後ろにいる間は結果の行を読めない）ので、UI テストの設計書の U-14 の例外に足し、テストにも注を書いた |
| C1: callback の `show` が既定 `presenter: .firstActiveScene` を持つが、`ios.md` は「callback の新しい口は既定を持たない」 | コードは付録 A のまま。`ios.md` に例外と理由（既定を持たない規則は Share の S-P18 の呼び分けのため。Dialog の今の口は名前が別）を書き、4.4 の 12 に足した |
| C2: `show` の先頭のログに題と本文が無い。`AlertDialogPresenter.result(of:)` に先頭のログが無い。`presentLegacy` のログが `style` だけ | `show`（callback と `async`）、`ShowDialogUseCase.execute`、`AlertDialogPresenter.present` の先頭のログに題と本文を `.private` で足した（internal の `DialogRequest.logTitle`・`logMessage`）。`result(of:)` に先頭のログ。`presentLegacy` は題・本文（`.private`）と、文言を除く全部（style、ボタンと入力欄の数、入力、入力が要るか、基点の有無と矢印、`animated`。`AlertSpec.logSummary`、`.public`）を出す |
| C3: `show` の DocC | 既定の `.firstActiveScene` では表示の途中の 2 つ目はたぶん `presentationFailed`、閉じかけの Dialog を待つと下の ViewController から出す（「上に」ではない）、scene が切れて Dialog が解放されない場合（R4-4）は約束の外、`invalidRequest` で返る箱は最初の要求の箱なので `cancel` に渡すと最初の要求を取り消す、`canceled` の行に `async` 版は `CancellationError` を投げる、を書いた |
| C4: 先頭の DocC（「`isSuccess=false` は前提の失敗」）がボタンの callback と合わない | ボタンの callback は押されたときだけ `(題, true, nil)`、失敗は `completion` だけ、に書き直した |
| C5: 4.3 と 4.4 の 5 | 4.3 に「ボタンの callback が main の 1 回分遅れる」の行を足し、4.4 の 5 に `showLoginDialog` のユーザー名とパスワードを足した |
| C6: `AlertDialogPresenterTests` の注が「UIKit は表示の途中の dismiss を無視する（MS-01）」 | MS-01 の結果（無視しない）と、それが M13 が落ちない理由であることに書き直した。`DialogSession` の同じ注も直した |
| C7: 単体テストの穴 | 6 件足した（下の表）。どれも壊した版で落ちることを確かめてから戻した（M22〜M30） |
| C8: 4 章の古い記述 | 4.1 と 4.2 の `init`・`@discardableResult`、4.5 の件数（38 件。UT-08 は 7）を直した |
| C9: iPad の 2 つの scene の注 | `PresenterSelection.firstActiveScene` に `- Important:`、`getRootViewController()` と `foregroundViewController()` の DocC にも足した |
| C10: D17・D20 は設計書 13.2 で「シミュレーター」なのに `DeviceRequirements.json` は `[]`。`showAfter3Seconds` は `#if DEBUG` で、信頼する部分の `DialogButton` は無条件 | 設計書 13.2 の環境が「シミュレーター」の D17・D20・D21・D22・D23 を `SIMULATOR_ONLY_TESTS` に入れた（D16・D18・D19 は「両方」で実機でも流れる）。`SampleApp.swift` の `showAfter3Seconds` に「UI テストは Debug のビルドだけ」の注を足した。`test_ios.sh` の `build-for-testing` はシミュレーターも実機も `-configuration` を渡さず、scheme の TestAction（`buildConfiguration = "Debug"`）で組むことを確かめた |

足した単体テスト（C7）と、壊して確かめたこと:

| # | テスト | 壊し方 | 結果 |
|---|---|---|---|
| M22 | `IosDialogManagerShownTests.theAnimatedArgumentReachesThePresentation`（`showDialog`・`showActionSheet` の `animated: false` が `present` に届き、ほかは `true`。UIKit を包んで `animated` を記録する環境） | `AlertDialogPresenter.run` が `animated: true` を渡す | 落ちた（`[true, true, true, true]`） |
| M23 | `PresentationProcedureTests.theAnimatedArgumentReachesThePresentOfEveryPath`（`.firstActiveScene`、`.foreground` のその場、待った後。偽の環境の `presentationAnimations` を初めて照らす） | 手順の `show` が `animated: true` を渡す | 落ちた |
| M24〜M26 | `IosDialogManagerShownTests.theAnchorArgumentsOfTheShowMethodsReachThePopover`（`showDialog` の `sourceView`・`sourceRect`・`permittedArrowDirections`、`showActionSheet` の `sourceRect: nil` は view の bounds、`showDialog` の `barButtonItem`。popover のある環境（iPad と iOS 26 の iPhone）で照らす） | `sourceRect` を無視（M24）、矢印を無視（M25）、`barButtonItem` を無視（M26） | 3 つとも落ちた |
| M27 | `AlertDialogPresenterTests.thePrimaryButtonFollowsTheFieldsWhenInputIsRequired` に、新しい口のテキスト入力（`enableConfirmWhenEmpty: false`）を足した | `AlertSpec(request:)` のテキスト入力で `requiresInput: false` | 落ちた |
| M28 | `AlertDialogPresenterTests.theViewControllerSelectionPresentsFromTheReturnedViewController`（2 つ目の window の root から出る、`nil` を返すと `notForeground` で何も出さない） | `present` が `.foreground` で出す | 落ちた |
| M29 | `IosDialogManagerShownTests.theAsyncFormReturnsTheAnswerWhenTheTaskIsCancelledAfterTheButton`（ボタンの後、答えが届く前に `Task` を取り消しても答えを返す） | `async` 版の最後に `try Task.checkCancellation()` | 落ちた（`CancellationError`） |
| M30 | `IosDialogManagerShownTests.showDialogIgnoresTheTextFieldsOfAnActionSheet` | `showDialog` がアクションシートにも入力欄を足す | 落ちた（UIKit の `NSInternalInconsistencyException` でホストが落ちる） |

ランナーの自己テスト（`scripts/tests/test_ios_ui_runner.py`）に `SimulatorOnly` の 9 件を足した: 表の中身（5 件）、全区分を許しても実機では選ばれず `simulator only` で除かれる（近い外れ: D16・D18 は選ばれる）、`--device-allow systemui` で D22 が除かれ D19 は選ばれる、シミュレーターでは流れる、`simulator-only` は許せない、名前を変えると照合で止まる、選び方が漏らしても計画で止まる、実機の名指しの直前で止まる（種類が分からない計画も止まる）、計画・許可の一覧・表示・基準の範囲での扱い。あわせて、patch で古くなった自己テストを直した: 列挙と実機のバイナリの fixture（`enumeration.json`、`otool-ov-device.txt`、`otool-l-device.txt`）を、0d と同じ取り方（Xcode 26.3。列挙は iPhone 17 / 26.2 のシミュレーター、バイナリは `generic/platform=iOS` で署名なし。端末は使っていない）で取り直し（UI テストは 107 件）、サンプルのボタンの数を 56 にした。`scripts/tests/ios_ui_runner_mutations.py` に、表の 3 か所の照らしを壊す変異など 5 件を足した。

信頼する部分の変更（`ios/IosLibraryExample/IosLibraryExampleUITests/Support/`。HEAD からの差分。別のモデルの再レビューに出す）:

| ファイル | 中身 |
|---|---|
| `SampleApp.swift` | `DialogButton` に SA-01〜SA-05 の 11 個（`showRequestLogin` は `credentials` の印が要る）、`DialogCover.identifier`（`dialog.cover`）と `dialogCoverExists`（数が 1 か。ラベルは読まない）。`showAfter3Seconds` に Debug のビルドだけの注 |
| `Springboard.swift` | `openControlCenter()`（右上 `(0.95, 0.005)` から `(0.95, 0.6)` へ 0.1 秒押してドラッグ）と `closeControlCenter()`（`(0.5, 0.95)` から `(0.5, 0.2)` へ）。どちらも先頭で `session.isDevice` なら何もせずに throw し、操作の後に割り込みの印を読む |

再レビューの後に固定するハッシュ（`python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests`。ほかの 6 ファイルと `FROZEN_CLIPBOARD_SHA256` は変わらない）:

| ファイル | 今の固定 | 新しい値 |
|---|---|---|
| `Support/SampleApp.swift` | `63edf06e…a3d4` | `9f51a9475348ad661f454fcbaad27078259d3294a19bedd14cc2ec3538cb2b44` |
| `Support/Springboard.swift` | `725c9cea…6d15` | `7c642008fdc5a532e1d1bb235702c7526669f5b1023aeae25a579f44e9c0daba` |

直した後の確かめ（Xcode 26.3。シミュレーターだけ。実機には触れていない）:

| 実行 | 結果 |
|---|---|
| 2 つの scheme の clean・whole-module のビルド（`generic/platform=iOS Simulator`） | Xcode 26.3 と 26.6 の両方でエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| `IosLibraryTests` の全件（iPhone 17 / 26.2、`-parallel-testing-enabled NO`） | 314/314（4.8 の 308 + 6）。skip 0 |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | リポジトリ: 141 件のうち 5 件が落ちる（どれも信頼する部分のハッシュが固定と違うことによるもの: `SourceRules` の 2 件、`Commands` の 1 件、`EndToEnd` の 2 件）。ハッシュを固定した使い捨ての写し: 141/141、`scripts/tests` の全体も 349 件成功（skip 27） |
| ランナーの変異（`ios_ui_runner_mutations.py --only`、写し） | 足した 5 件はすべて捕まり、変異なしは残った。本物の台帳は変わらない |
| `scripts/test_ios.sh --feature Dialog`（iPhone 17 / 26.2、ハッシュを固定した写し） | 29/29 成功（Navigation 2、IdentifierInventory 4、Dialog D1〜D23）。基準との比べ合わせは `changed=0, added=8, removed=0`（足したのは D16〜D23）。信頼する部分の警告なし。D18・D19・D20 は `shown=true`・`covered=true` の結果の行で通った |
| `scripts/test_ios.sh --dry-run --device-allow systemui`（写し。`--udid` はどの端末でもない値、列挙は iPhone 17 / 26.2。`--baseline` なし） | 実機に触れない（シミュレーターで組んで列挙し、計画と許可の一覧を書いて止まる。devicectl も実機の xcodebuild も呼ばない）。107 件のうち 52 件を選び 55 件を除いた。D22 は `[systemui] simulator only` で除かれ、D17・D20・D21・D23 も `simulator only`。Dialog で選ばれたのは D1〜D10、D14、D18、D19 の 13 件 |
| swiftinterface（4.6 と同じ組み方） | `IosLibrary-after-1b-c2.swiftinterface` と `2026-10-31-stage1b-c2.diff` を取り直した。前の版からの違いは `DialogAnswer.init(button:title:input:)` と `async` の `show` の `@discardableResult` だけ（5 章の決定）。`swift-frontend -typecheck-module-from-interface` は通った |

信頼する部分の再レビュー（2026-10-31、Codex。設定のモデル。読むだけのコマンドで静的に見た）: 指摘は A・B・C とも無し。(a) Control Center の 2 つの操作は、実機では座標も操作も作る前に throw し、ほかに操作する経路は無い。(b) ランナーの simulator-only の除外は閉じた側に倒れる（名前を変えたキー、名指し、`--device-allow` の値、`-only-testing` の直前の確かめ）。U-9 の 3 つの柱は弱まらない。(c) 2 ファイルの差分で実機に届く新しい操作はサンプルの中だけで、ログインは `credentials` の印のまま。システムのラベルや個人のデータは読まない。U-17 と I1a は合う。(d) D16〜D23 の区分は正しい。2 つのハッシュは上の新しい値と一致したので、`TRUSTED_FILES` に固定した。固定した後、リポジトリで確かめた: ランナーの自己テストは 141/141、`scripts/test_ios.sh --feature Dialog`（iPhone 17 / 26.2）は 29/29 成功で、基準との比べ合わせは `changed=0, added=8, removed=0`（D16〜D23）。

残ること:

- `SIMULATOR_ONLY_TESTS` に D23 を入れたのは設計書 13.2（「iPad のシミュレーター」）に従ったため。D23 はアクションシートを出して選ぶだけで、実機でも私物に触れないので、実機の基準に入れたいなら外してよい（外すなら設計書 13.2 と 6.3 の 3 を直す）
