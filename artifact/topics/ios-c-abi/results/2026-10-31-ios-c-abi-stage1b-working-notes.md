# 段階 1b の作業の記録（Swift の API の補完）

- 記録日: 2026-10-31
- 段階: 1b（`README.md` の 5 章の 1b の行。設計書は `designs/2026-10-31-ios-c-abi-swift-api-design.md`。以下「設計書」）
- ブランチ: `feature/NTKIT-18`（C1 は HEAD `f3c289d7` の上の未コミットの変更で、`584ec55c` でコミットした。C2 は `584ec55c` の上の未コミットの変更で、`da620c67` でコミットした。C3 は `da620c67` の上の未コミットの変更で、`637b1078` でコミットした。C4 は `637b1078` の上の未コミットの変更で、`747897de` でコミットした。C5 は `747897de` の上の未コミットの変更で、前半（T-13・T-14）と後半（T-15・T-16）が入っており、`b80399eb` でコミットした。C6 は `b80399eb` の上の未コミットの変更で、`97c95c71` でコミットした。C7 は `97c95c71` の上の未コミットの変更で、まだコミットしていない）
- 環境: Xcode 26.3（17C529、Swift 6.2.4、`xcode-select` のまま）。C5 のレビューの直しと C6 の単体テストは Xcode 26.6 で流した（17.8）。0 件の警告の確かめだけ Xcode 26.6（17F113、Swift 6.3.3）でも組んだ（`DEVELOPER_DIR` でコマンドごとに選んだ）。シミュレーターは iPhone 17（iOS 26.2）、iPhone 16（iOS 18.3.1）、iPad Pro 11-inch (M4)（iOS 18.3.1）、C2 の MS-02 の iPad (A16)（iOS 26.2）、C6 の変異の iPhone 16（iOS 26.2）、C7 の測りと変異の iPhone 17 Pro（iOS 26.2）だけ。**実機には触れていない**
- 章: コミットごとに 1 章（設計書 15.1 の C1〜C7）。この版は C1（1〜3 章）、C2（4〜6 章）、C3（7〜9 章）、C4（10〜12 章。2026-11-01）、C5（13〜15 章。2026-11-01。前半は 13.1〜13.10 と 14 章、後半は 13.11〜13.21 と 15 章。16 章は C5 のレビュー）、C6（17〜19 章。2026-11-01）、C7（20〜22 章。22 章は C7 のレビュー。2026-11-01）、1b の後の小さな直し（23 章。21 章の 1・5。2026-11-01）

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

## 7. C3 Share（T-10、T-11）

- 状態: ライブラリ・単体テスト・壊して確かめる・サンプル・UI テスト（S17〜S19）・MS-03 の Share の分は済んだ。コミットはしていない
- 信頼する部分（`Support/SampleApp.swift`）の変更はリポジトリの作業ツリーに入れた（利用者の承認、C3〜C6 は C2 と同じ扱い）。**ハッシュは固定していない**（別のモデルのレビューの後に固定する）。そのため、リポジトリではランナーが「信頼する部分が変わった」と警告し、実機では流れない。UI テストとランナーの自己テストは、ハッシュだけを直した使い捨ての写し（scratchpad）で流した（7.8）
- 測ったログ・下調べのテスト・変異の差分は scratchpad に置き、リポジトリには入れていない

### 7.1 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| Domain（T-10） | `Share/Domain/Model/ShareError.swift` | S-P7: `Error, Sendable, Equatable`（`LocalizedError` は今と同じく extension）。`presentationFailed(Error)` を値の無い `presentationFailed` に、`unknown(Error)` を消し、`notForeground`・`dismissedBySystem`・`activityFailed(FailureDetail)` を足した。文言は英語の固定（7.3）。DocC に case ごとの場面の表 |
| Domain | `Share/Domain/Model/ShareContent.swift` | internal の `logSummary`（種類ごとの件数、件名と題の有無と長さ、除く活動の件数。中身は出さない） |
| Application（T-11） | `Share/Application/Port/ShareRepository.swift` | `present(content:presenter:)`（付録 A）。DocC を外の実装者が守れる約束に書き直した（終わったら返す・`ShareError` だけを投げる・ずっと止まったままにしない。`presenter` は外から値を読めない、外から閉じたときの `dismissedBySystem` はライブラリの実装だけ） |
| Application | `Share/Application/UseCase/ShareUseCases.swift` | `execute(content:presenter:)` を足し、今の `execute(content:)` は `.firstActiveScene` で委ねる（付録 A に無い。8 章の 2） |
| Data | `Share/Data/Repository/ShareRepositoryImpl.swift` | `present(content:presenter:)`。先頭のログを `logSummary` に |
| Presentation（T-10） | `Share/Presentation/ShareSheetPresenter.swift` | 作り直した。`PresentationEnvironment` で generic の struct（`AlertDialogPresenter` と同じ形）。要求ごとに `RequestBox` を作り、箱の閉じたときの処理（1 回だけ、main）だけが continuation を再開する。`completionWithItemsHandler` は nonisolated に作り、呼ばれたスレッドでその場で箱を閉じる（シートが先に解放されて見張りに取られないため）。表示は `PresentationProcedure`（`.firstActiveScene` は `requireLegacyStability`、`declineCheck: .releaseWatchOnly`。7.4 の 1）。重複していた `getRootViewController()` と `PresentationUnavailableError` を消した（6.1） |
| Manager（T-11） | `Share/IosShareManager.swift` | `share(content:presenter:completion:)`（`Result<ShareResult, ShareError>`、既定なし）を足し、`async` 版に `presenter: = .firstActiveScene` を足した。今の callback 版は形を変えず `.firstActiveScene` で同じ芯を通る。DocC に終わり方の表（新しい口と今の口の値）、約束の外、取り消せないこと、2 つの要求の順を約束しないことを書いた |
| 共通 | `Common/Presentation/PresentationProcedure.swift` | `DeclineCheck`（`rightAfterPresent` が既定、`releaseWatchOnly`）を足した。`present` の完了の closure が見張りを弱く持つようにした（7.4 の 2） |
| 共通 | `Common/LogRedaction.swift` | `describe` が、関連値が 1 つの `FailureDetail` の case にも domain と code を足す（`ShareError.activityFailed(domain=…, code=…)`） |
| 共通 | `Common/Domain/PresenterSelection.swift` | DocC の「後のコミット」の注を Share の分だけ直した |
| テスト | `IosLibraryTests/Share/` の 2 ファイル（新）と 5 ファイル、`Common/LibraryLogPrivacyTests.swift`、`Common/PresentationProcedureTests.swift` | 7.5 |
| サンプル（SA-14・SA-05） | `IosLibraryExample/ShareSampleView.swift` | 節「Swift API (2.0.0)」（`share.section.swiftAPI`）とボタン 3 つ: `ShareRequestText`（`async` 版、`.foreground`）、`ShareThenDismissFromOutside`（`Result` の callback 版、3 秒後にサンプルが外から `dismiss`。結果の行に `shown=<その時シートが前面か>`）、`ShareAfter3Seconds`（`#if DEBUG`。3 秒後に `Result` の callback 版、結果の行に要求の時点の scene の状態）。結果の行は `[<印>] success completed=…` / `[<印>] failure <case>`。今の 14 のボタンと結果の行は変えていない |
| UI テスト | `IosLibraryExampleUITests/ShareUITests.swift`、`Support/DeviceRequirements.json` | S17〜S19 と宣言（7.8） |
| UI テスト（信頼する部分） | `Support/SampleApp.swift` | 7.10 |
| ランナー | `scripts/ios_ui_runner.py` | `SIMULATOR_ONLY_TESTS` に S18・S19 を足した（7 件）。ハッシュの表は変えていない |
| ランナーの自己テスト | `scripts/tests/test_ios_ui_runner.py`、`scripts/tests/ios_ui_runner_mutations.py`（S19 を表から落とす変異を 1 件）、`scripts/tests/fixtures/ios_ui_runner/enumeration.json`・`otool-ov-device.txt`・`otool-l-device.txt` | 7.8 |
| 文書 | `designs/2026-10-18-ios-c-abi-ui-test-design.md` | 5.1 の一覧（Share の節 1・ボタン 3）、U-14 の例外に S18、6.3 の 3 の simulator only を 7 件に |
| 公開 API | `results/swiftinterface/IosLibrary-after-1b-c3.swiftinterface`、`2026-10-31-stage1b-c3.diff` | 7.6 |

### 7.2 公開 API（付録 A の Share との照合）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public enum ShareError: Error, Sendable, Equatable, LocalizedError`（9 case） | 同じ 9 case。`LocalizedError` は今と同じ extension で付けた（swiftinterface では `extension ShareError : Foundation.LocalizedError`）。`FailureDetail` が `Hashable` でないので自動の `Hashable` は付かない | 一致 |
| `public protocol ShareRepository: Sendable { func present(content:presenter:) async throws -> ShareResult }` | 同じ | 一致 |
| `share(content:presenter:completion:)`（`presenter` に既定なし、`@escaping @MainActor @Sendable (Result<ShareResult, ShareError>) -> Void`） | 同じ | 一致 |
| `@discardableResult share(content:presenter: = .firstActiveScene) async throws -> ShareResult` | 同じ（今の `share(content:)` に既定つきの引数を足した形。今の呼び方は組める） | 一致 |
| （付録 A に無い） | `ShareContentUseCase.execute(content:presenter:)` を足した（今の `execute(content:)` は残した） | **付録 A に無い追加**（8 章の 2） |

今の口（`share(content:completion:)`、`ShareContent`・`ShareItem`・`ShareResult`、`ShareContentUseCase.init`・`execute(content:)`）の宣言は swiftinterface で変わっていない。公開の記号にはすべて DocC を付けた。`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` は足していない（P1-17 の一覧の外は 0 のまま）。

### 7.3 今の利用者から見て変わる動作（3.3 の Share の 3 行の中身）

| 口 | 前 | 後 |
|---|---|---|
| `share(content:completion:)` で、表示したシートが handler なしに解放された（外から閉じた、scene が切れて解放された） | 何も来ない | `(false, false, nil, "The share sheet was dismissed without a result.")` が 1 回（約 0.55 秒後。7.7） |
| `share(content:)` `async` 版の同じ場面 | 戻らない（continuation が漏れる） | `ShareError.dismissedBySystem` を投げる |
| 落ち着かない（`.firstActiveScene` の今の確かめ） | `(false, false, nil, "Failed to present the share sheet: The root view controller is not in a stable state to present the share sheet..")` | `(false, false, nil, "Failed to present the share sheet.")`、`async` 版は `presentationFailed` |
| UIKit が表示を断った | 何も来ない（戻らない） | 見張りが `presentationFailed`（解放まで約 0.03〜0.04 秒。7.7） |
| 活動の失敗（`completionWithItemsHandler` の `error`） | `"Failed to present the share sheet: <system の文>."`、`async` 版は `presentationFailed(error)` | `"The share activity failed."`、`async` 版は `activityFailed(FailureDetail)` |
| ほかの 5 つの文言（`noValidItems`・`invalidURL`・`imageLoadFailed`・`fileNotFound`・`noRootViewController`） | - | 変わらない（S13〜S16 が全文で比べる） |
| `ShareError` の case | `presentationFailed(Error)`・`unknown(Error)` | 値の無い `presentationFailed`、`unknown` は無い、3 つ足した（網羅した `switch` は組めなくなる。3.3 の破壊的の行） |
| `ShareRepository` を自分で実装した利用者 | `present(content:)` | `present(content:presenter:)` が要る（組めなくなる。3.3 の破壊的の行） |
| handler の結果の届き方 | handler の中で `Task { @MainActor }` に積んでから continuation を再開 | handler の中で箱を閉じ、閉じたときの処理（`DispatchQueue.main.async`）で再開。完了が main で 1 回は変わらない |
| ログ | 件名を長さだけ、エラーは case の名前（C1） | 先頭のログが種類ごとの件数・件名と題の長さ・除く活動の件数になった。活動の種類は `.private` |

今の UI テスト（S1〜S16）はこれらの場面を作らないので結果は変わらない（7.8）。

### 7.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | 6.3.3 の段 3 の補い（`present` の直後に `presentingViewController` が `nil` なら断ったとみなす）。「直後に設定されることを MS-01 で確かめ、されなければこの補いを外して見張りだけにする」 | Share は補いを使わない（`PresentationProcedure` に `DeclineCheck` を足し、Share は `.releaseWatchOnly`。Dialog は今のまま `.rightAfterPresent`） | MS-03（7.7）で、`UIActivityViewController` の `presentingViewController` は `present` から戻った後（0.05〜0.9 秒）にしか設定されないと分かった。補いを残すと表示したシートがすべて `presentationFailed` になった（最初の版の単体テストで 14 件が落ちた）。UIKit が断ったシートは約 0.03〜0.04 秒で解放されるので、見張りだけで `presentationFailed` が来る |
| 2 | 6.3.4「表示する ViewController に、箱を強く持つ小さなオブジェクトを結び付ける」（持ち主は ViewController だけ） | `PresentationProcedure.show` の `present` の完了の closure が見張りを `weak` で持つようにした（C1 の部分） | 前は強く持っていたので、UIKit が完了の closure を持ち続けたまま断ると、ViewController が解放されても見張りが生き残る。Share は補いが無いのでこの経路が開く。偽の UIKit で確かめた（M48） |
| 3 | 付録 A は `ShareContentUseCase` を変えない。6.1 は UseCase も「`presenter` を渡す」 | `execute(content:presenter:)` を足し、`execute(content:)` を残した | Manager → UseCase → Repository の規則（common.md）で、`presenter` を Repository に届けるには UseCase の口が要る。今の宣言は変えない。付録 A に足すかは利用者に尋ねる（8 章の 2） |
| 4 | 12 章の SA-14「`share(content:presenter:.foreground)` のボタン、外から閉じるボタン」 | `ShareRequestText` は `async` 版、`ShareThenDismissFromOutside` と `ShareAfter3Seconds` は `Result` の callback 版 | `ios.md` の「新しく足すボタンは `async` 版」。callback 版は C ABI の受け口が使う形（8.9）なので、UI テストで一度は通す（C2 の SA-02〜SA-05 と同じ） |
| 5 | SA-14 の外から閉じる時機は書いていない。SA-05 は「3 秒後」 | どちらも 3 秒後。結果の行に `shown=` と scene の状態を足した | C2 の 4.4 の 10・6 章の B2 と同じ（UI テストがシートを時間内に捕まえなくてよい。U-14） |
| 6 | 6.3.4・RK-11「見張りに頼るテストは TSan の回で skip」 | Share の見張りのテストは TSan の回でも skip しない | MS-03（7.7）で、TSan の版でも外から閉じたシートは約 0.55 秒で解放され、`dismissedBySystem` が来た（5 回とも）。同じ回で、`IosLibrary` の手順で出したアラートも約 0.45 秒で解放された（申し送り 1 の雛形とは違う）。C1・C2 の skip は変えていない（8 章の 4） |
| 7 | 8.2 は `async` 版のエラーの写しを書いていない | `Result` の callback 版は `ShareError` でないエラーを `presentationFailed` に写し、`async` 版は投げられたものをそのまま投げる | `async` 版は今も型の無い `throws` で、そのまま投げるのが今の動作。ライブラリの Repository は `ShareError` しか投げず、Manager に別の Repository を渡せるのは internal の `init(repository:)`（テスト）だけなので、利用者には違いが出ない |
| 8 | 8.7.1 の privacy | 活動の種類（`activityType`）は `.private` | 利用者が選んだ先（入れているアプリ）を表しうるため。秘密の値の一覧には無いので長さにはしていない |
| 9 | P1-13 の基点 | iPhone 17 / 26.2 では、ライブラリが付けた基点（表示元の view の中央）を UIKit が表示のときに自分の transition view に替える。単体テストは `present` を呼ぶ時点の基点を照らす | 1b の前の Share も同じ基点を付けていた（見え方は変わらない）。iPad は付けた基点のまま（iPad Pro 11-inch (M4) / 18.3.1 で確かめた） |
| 10 | 6.2 の「main への積み方」 | Manager の callback 版は今と同じ `Task { @MainActor }` で UseCase を待つ。2 つの共有を続けて求めたときの表示の順は約束しない（DocC に書いた） | port が `async`（付録 A）で、nonisolated の `async` の UseCase と Repository は汎用の executor を通るので、呼んだ順は保てない。Share に順の約束は無い（P1-12 は Dialog の D17）。第 2 部への申し送り（7.11） |
| 11 | U-14 の例外は D21 だけ | S18 も同じ例外（ホームに移ってから 5 秒の決まった待ち）にし、UI テストの設計書の U-14 に足した | D21 と同じ理由（後ろにいる間は結果の行を読めない）。結果の行に要求の時点の scene の状態（`@background`）が出るので、待ちが足りずに前面で要求しても通らない |
| 12 | U-9（実機で安全にできない操作は信頼する部分でも閉じる） | 信頼する部分に `session.isDevice` の確かめは足していない | S18・S19 は設計書 13.2 で環境が「シミュレーター」なので `SIMULATOR_ONLY_TESTS` に入れたが、使う操作はサンプルのボタン（`ShareSheetToken`）とホームへの移動（`SystemUIToken`、今の `goHome`）だけで、決まった座標の操作も実在の共有先に触れる操作も無い。C2 の D17・D20・D21・D23 と同じ扱い |

### 7.5 単体テストと壊して確かめたこと

| ID | ファイル | 件数 | 中身 |
|---|---|---|---|
| UT-12 | `Share/Presentation/ShareSheetPresenterTests.swift`（新、ホストのアプリ） | 15 | handler の結果（完了・閉じた・活動のエラーは `activityFailed`）、最初の終わりだけ（handler 2 回と外から閉じて解放）、handler は呼ばれたスレッドでその場で箱を閉じる、外から閉じたシートは見張りが `dismissedBySystem`、前面なしは選び方ごとの case（`.firstActiveScene` は `noRootViewController`）、偽の UIKit が断ると `presentationFailed`、本物の UIKit が断ると（既に別のものを出している）見張りが `presentationFailed`、表示の途中（`presentingViewController` がまだ無い）を失敗にしない、`.firstActiveScene` は今の確かめで出さずに失敗し `.foreground` は出す、`.viewController` の ViewController から出す、除く活動がシートに届く、基点（`present` の時点で表示元の view の中央、矢印は `.any`、iPad では表示後も）、`Task` の取り消しで終わらない（表示中と、handler の直後の取り消し） |
| UT-13 | `Share/Presentation/IosShareManagerPresenterTests.swift`（新） | 12 | 今の口は `.firstActiveScene`、`Result` 版と `async` 版は `presenter` を渡し `async` 版の既定は `.firstActiveScene`、`Result` 版の結果（main、呼び出しの中では来ない）、`ShareError` の全 case がそのまま、項目なしは Repository を呼ばない、`ShareError` でないエラー（`Result` 版は `presentationFailed`、`async` 版はそのまま）、背景のスレッドから呼んでも main、`async` 版は `ShareError` を投げる、今の口の新しい終わり方の文言、本物の Presenter を通して外から閉じたシートが今の口と `Result` 版で 1 回ずつ、今の口で handler の結果の値 |
| UT-13 | `Share/Presentation/IosShareManagerTests.swift`（今の 8 件） | 8 | 変えずに通る（Mock の Repository の形だけ直した） |
| UT-13 | `Share/Application/ShareContentUseCaseTests.swift`、`Share/Data/ShareRepositoryImplTests.swift` | +3、+2 | UseCase の `presenter` の受け渡しと既定、項目なし。Repository が `presenter` を Presenter に渡す、変換できない項目では出さない |
| UT-16 | `Share/Domain/ShareErrorTests.swift` | 9（前は 7。消した 2 件、足した 4 件） | 今の 5 つの文言（4 つは S13〜S16 の基準）、新しい 4 つの固定の文言、活動の失敗の文言に domain と code が出ない、全 case に別々の文言（網羅の `switch` で case の足し忘れを組めなくする）、`Equatable`。消した case の 2 件（`presentationFailed(Error)`・`unknown(Error)` の前置き）は消した |
| UT-15 | `Common/LibraryLogPrivacyTests.swift` | +1 | Share を Manager の 3 つの口・本物の Repository・本物の Presenter（ホストのアプリ）で、番兵のテキスト・URL・件名・題・除く活動・ファイルのパス・URL を持つエラー・活動のエラーの文で通し、ログに番兵が無い（読めていることを `#require`、活動の失敗の domain と code が出ること） |
| UT-04 | `Common/PresentationProcedureTests.swift` | +2 | `releaseWatchOnly` では直後に受け取られていなくても失敗にしない、完了を UIKit が持ち続けても断った ViewController の解放で箱が閉じる |
| LogRedaction | `Common/LibraryLogPrivacyTests.swift` の `LogRedactionTests` | 0（1 件を直した） | `ShareError.presentationFailed(inner)` の確かめを `ShareError.activityFailed(FailureDetail)` の domain と code に替えた |

`IosLibraryTests` は 351 件（C2 の 314 件に 39 件を足し、`ShareErrorTests` の 2 件（`presentationFailedDescriptionContainsUnderlyingMessage`・`unknownDescriptionContainsUnderlyingMessage`。消した case の確かめ）を消した）。

壊して確かめたこと（壊した版で組んで該当のテストを流し、落ちることを見てから戻した。`mutate_c3.py` と差分・ログは scratchpad）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M31 | UT-12 | 箱が `dismissedBySystem` で閉じたときに continuation を再開しない（設計書 13.1「見張りで再開しない」） | `aSheetDismissedFromOutsideEndsAsDismissedBySystem`（待ちに上限があり、止まらずに落ちる） |
| M32 | UT-12 | handler が箱を閉じるのを `DispatchQueue.main.async` に積む（形の変更: その場で閉じない） | `theHandlerClosesTheBoxOnItsOwnThreadAtOnce` |
| M33 | UT-12 | handler の `error` を見ない | `anActivityErrorEndsTheShareAsActivityFailed` |
| M34 | UT-12 | Share でも補いを使う（`declineCheck: .rightAfterPresent`） | `aSheetThatIsStillBeingPresentedIsNotFailed` |
| M35 | UT-12 | `.firstActiveScene` の方針を `presentAnyway` にする | `firstActiveSceneKeepsTheLegacyStabilityCheck` |
| M36 | UT-12 | 前面なしの写しで `.firstActiveScene` と `.foreground` を取り違える | `withoutAViewControllerEachSelectionReportsItsError` |
| M37 | UT-12 | 除く活動をシートに渡さない | `theExcludedActivityTypesReachTheSheet` |
| M38 | UT-12 | 戻る前に `Task.checkCancellation()`（取り消しで終わる） | `cancellingTheTaskDoesNotEndTheShare` |
| M39 | UT-12 | 形の変更: 手順の前にシートへ別の基点を付ける（間接の 1 段） | `thePopoverIsAnchoredAtTheCentreOfThePresentingView` |
| M40 | UT-13 | 今の口で `presenter` を変える（`.foreground`。設計書 13.1） | `theFormFromBefore1bUsesFirstActiveScene` |
| M41 | UT-13 | `Result` 版が `presenter` を捨てる | `theResultFormPassesThePresenterOn` |
| M42 | UT-13 | `async` 版の既定を `.foreground` にする | `theAsyncFormDefaultsToFirstActiveSceneAndPassesThePresenterOn` |
| M43 | UT-13 | UseCase の `execute(content:)` が `.foreground` を渡す | `executeWithoutAPresenterUsesFirstActiveScene` |
| M44 | UT-13 | 今の口の文言を `String(describing:)` にする | `theFormFromBefore1bReportsTheNewEndsWithFixedMessages` |
| M45 | UT-16 | `presentationFailed` の文言を変える（設計書 13.1「文言を変える」） | `theNewCasesHaveFixedTexts` |
| M46 | UT-16 | 活動の失敗の文言に domain と code を入れる | `theActivityFailureTextHoldsNoDetail` |
| M47 | UT-15 | `logSummary` に件名をそのまま入れる | `shareContentThroughTheRealPresenterNeverReachesTheLog` |
| M48 | UT-04 | `present` の完了が見張りを強く持つ（7.4 の 2 の前の形） | `aDeclinedViewControllerIsWatchedEvenWhileItsCompletionIsKept` |
| M49 | UT-04 | `declineCheck` を見ずにいつも補いを使う | `withTheReleaseWatchOnlyAPresentationNotTakenAtOnceIsNotFailed` |

19 件とも落ち、戻した版で通ることを確かめた（全件の実行、7.8）。最初の版で気づいたこと: (1) 本物のシートを記録するテストの補助（`SheetRecorder`）がシートを強く持っていたので、見張りが働かず外から閉じたテストが 15 秒待って落ちた。`weak` で持つ形に直した（7.11）。(2) 補いを残した最初の版は、表示したシートがすべて `presentationFailed` になった（7.4 の 1）。

TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2）: `ShareSheetPresenterTests`・`IosShareManagerPresenterTests`・`IosShareManagerTests`・`LibraryLogPrivacyTests`・`RequestBoxTests`・`ReleaseWatchTests`・`PresentationProcedureTests` が成功（Share の見張りのテストは skip せずに通った。7.4 の 6）。TSan の報告は 0 件。C1 の `aRealViewControllerClosesTheBoxWhenFreed` は今のとおり skip。

### 7.6 公開 API（swiftinterface）

- 組み方: C1・C2 と同じ（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）。`arm64-apple-ios.swiftinterface` を写した
- 足したファイル: `IosLibrary-after-1b-c3.swiftinterface`、差分 `2026-10-31-stage1b-c3.diff`（`after-1b-c2` が基準）
- 差分の中身: `ShareRepository.present(content:)` → `present(content:presenter:)`、`ShareContentUseCase.execute(content:presenter:)` の追加、`ShareError` が `Sendable, Equatable` になり（`==` が出る）`presentationFailed(any Error)`・`unknown(any Error)` が消え `notForeground`・`presentationFailed`・`dismissedBySystem`・`activityFailed(FailureDetail)` が増えた、`IosShareManager.share(content:presenter:completion:)` の追加、`async` の `share(content:)` が `share(content:presenter: = .firstActiveScene)` になった。ほかは変わらない（今の `share(content:completion:)` も同じ行のまま）
- `swift-frontend -typecheck-module-from-interface`（Xcode 26.3、Swift 6.2.4）で public と private の 2 つとも型検査が通った（出力 0 行）

### 7.7 シミュレーターで測ったこと（C3 に付いた MS-03 の Share の分）

使い捨ての下調べのテスト（ホストのアプリ。scratchpad の `ProbeC3Tests.swift`。リポジトリには入れていない）と、UI テストの間の `log stream`。

| 測ったこと（設計書 14 章の MS-03 の「残り」） | iPhone 17 / 26.2 | iPad Pro 11-inch (M4) / 18.3.1 |
|---|---|---|
| `present` の直後の `presentingViewController`（6.3.3 の補い） | 直後は `nil`。animated で 0.08〜0.9 秒後、animated でなければ約 0.05〜0.07 秒後に設定され、完了はその後（0.65〜1.46 秒 / 0.06〜0.08 秒） | 同じ（0.53 秒 / 0.05 秒） → **Share は補いを外し見張りだけ**（7.4 の 1） |
| 外から閉じたシートの handler と解放 | handler は呼ばれない（申し送り 1 と同じ）。解放は約 0.55〜0.59 秒後。ライブラリの手順で出したシートは 5 回とも 0.56〜0.59 秒で `dismissedBySystem` | 同じ（解放 0.56〜0.58 秒、`dismissedBySystem` 0.55〜0.57 秒、5 回） |
| UIKit が表示を断ったシート（既に別のものを出している ViewController に出す）の解放（SR-16） | 完了は来ず、約 0.04 秒で解放 | 約 0.03 秒で解放 |
| handler のスレッド | Copy と閉じる（S1・S2・S17 など）で main（`[completionWithItemsHandler] … isMainThread: true`）。ライブラリはスレッドに頼らない（その場で箱を閉じる） | 測っていない（UI テストは iPhone だけ） |
| 活動を選んだ間に解放されないか | S8・S9（Save to Files のピッカーを開いて保存）が今の口で `completed=true` のまま通った（見張りが先に閉じれば `(false, …)` になる） | - |
| scene を切ったときの handler と解放 | - | 2 つ目の scene でシートを出し `requestSceneSessionDestruction` で切ると、handler は来ず、15 秒たっても完了が来なかった（下調べがその scene の window を持ち続けたため、シートが解放されない）。window を手放すとすぐ（約 0.005 秒）`dismissedBySystem` が来た。**システムが scene を切っても表示元が残ればシートは解放されない**: 第 1 部 0.1 の「約束の外」（R4-4）のとおり |
| TSan の版で解放されない理由 | **TSan の版でも外から閉じたシートは約 0.55〜0.60 秒で解放され、`dismissedBySystem` が来た**（5 回）。同じ回で `IosLibrary` の手順で出したアラートも約 0.45 秒で解放された（3 回）。申し送り 1 の「TSan の版では 15 秒たっても解放されない」は雛形（capi の中の手順）の振る舞いで、`IosLibrary` の手順では再現しなかった。理由（雛形の何が持っていたか）は調べていない | - |

あわせて: iPhone 17 / 26.2 では、ライブラリが付けた基点を UIKit が表示のときに替える（7.4 の 9）。

MS-02 の Share の分（C2 の 4.7 で「まだ」だったもの。写しに置いた使い捨ての UI テスト、iPhone 17 / 26.2）: `ShareAfter3Seconds` を押して Control Center を引き出すと、`foregroundInactive` の間に `.foreground` のシートが出た。Control Center を閉じてもシートは残り、閉じると `[shareAfter3Seconds@foregroundInactive] success completed=false`。**G-6 の 1 つ目（inactive の間も表示できる）は Share でも成り立つ**。

### 7.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPad Pro 11-inch (M4) / 18.3.1、iPhone 16 / 18.3.1。`-parallel-testing-enabled NO`） | どれも 351/351。skip 0。C2 の 314 件の名前との比べ合わせは、足した 39 件と、消した 2 件（7.5）だけ |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Share`（ハッシュを固定した写し） | 25/25 成功（Navigation 2、IdentifierInventory 4、Share S1〜S19）。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）との比べ合わせは `changed=0, added=3, removed=0`（足したのは S17〜S19）。S1〜S16 は今の期待値のまま通った（今の口の結果の行は変わらない）。I1c は Share の 17 のボタンと節 7 で一致した。信頼する部分の警告なし |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | 写し: 142/142（C2 の 141 + `test_systemui_and_sharesheet_leave_s18_and_s19_out`）。`scripts/tests` の全体も 350 件成功（skip 27）。リポジトリ: 142 件のうち 4 件が落ちる（どれも `SampleApp.swift` のハッシュが固定と違うことによるもの: `SourceRules.test_the_real_tree_passes`、`Commands.test_preflight_refuses_the_device_when_the_trusted_part_changed`、`EndToEnd` の 2 件） |
| 自己テストの fixture | 列挙（`enumeration.json`）は写しの `--feature Share` の回の列挙（iPhone 17 / 26.2、Xcode 26.3、flat）をそのまま写した。前の fixture との差は S17〜S19 の 3 行だけ（UI テストは 110 件）。実機のバイナリ（`otool-ov-device.txt`・`otool-l-device.txt`）は写しを `generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組んだ UI テストのバンドルから取った（端末は使っていない）。どれにもローカルのパスは入っていない。数を照らす自己テスト（107 → 110、サンプルのボタン 56 → 59）と simulator only の表のテストを直した |
| ランナーの変異（`ios_ui_runner_mutations.py --only simulator`、写し） | 足した 1 件（S19 を表から落とす）と既存の simulator only の 6 件がすべて捕まり、変異なしは残った。本物の台帳は変わらない |
| `scripts/test_ios.sh --dry-run --device-allow systemui,sharesheet,clipboard`（写し。`--udid` はどの端末でもない値、`--enumerate-udid` は iPhone 17 / 26.2。`--baseline` なし） | 実機に触れない（`--dry-run` は計画と許可の一覧を書いた所で `exit 0` し、devicectl と実機の xcodebuild の前に止まることをスクリプトで確かめた。`--devicectl-id` も渡していない）。110 件のうち 94 件を選び 16 件を除いた。**S18（`[sharesheet,systemui]`）と S19（`[sharesheet]`）は `simulator only` で除かれた**（D17・D20〜D23 も同じ）。S17 は選ばれ、S8・S9 は `missing files`。写しには未コミットの変更があるので、実機の回は断ると表示した |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2 は UI テストの前に自分で起動し、終わった後に止めた。iPad Pro 11-inch (M4) / 18.3.1 と iPhone 16 / 18.3.1 は xcodebuild が起動し、終わった後は止まっていた。最後にどれも起動していないことを確かめた |

### 7.9 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |

### 7.10 信頼する部分の変更とハッシュ

`ios/IosLibraryExample/IosLibraryExampleUITests/Support/`。HEAD（`da620c67`）からの差分。別のモデルの再レビューに出す。

| ファイル | 操作 |
|---|---|
| `SampleApp.swift` | (1) `ShareButton` に `shareRequestText`・`shareThenDismissFromOutside`・`shareAfter3Seconds` の 3 つを足した（`shareAfter3Seconds` に Debug のビルドだけの注）。押す口は今の `tap(_ button: ShareButton, _ token: ShareSheetToken)` だけで、`ShareSheetToken` が要る（U-9）。(2) I1c の一覧（`SampleInventory.expectedNonButtons(.share)`）に `share.section.swiftAPI` を足した。**新しい操作・新しい要素の読み方は無い**（識別子を足しただけ） |
| `Springboard.swift`、`ShareSheet.swift`、ほかの 6 ファイル | 変えていない（S18 は今の `goHome()`、S17 は今の `copy(_:)`、S19 は今の `waitClosed()` を使う） |

守り: S18（`sharesheet`・`systemui`）と S19（`sharesheet`）は `SIMULATOR_ONLY_TESTS` に入れたので、`--device-allow` に何を渡しても実機の一覧に入らない（一覧に `simulator only`）。S17 は `sharesheet`・`clipboard` で、実機では両方を許したときだけ流れる（S1 と同じ Copy だけを押す）。識別子の文字列は信頼する部分の中だけにある（U-17。`ShareUITests.swift` は `ShareButton` の case だけを使う）。信頼する部分に `session.isDevice` の確かめは足していない（7.4 の 12）。

再レビューの後に固定するハッシュ（`python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests`。ほかの 7 ファイルと `FROZEN_CLIPBOARD_SHA256` は変わらない）:

| ファイル | 今の固定 | 新しい値 |
|---|---|---|
| `Support/SampleApp.swift` | `9f51a947…2b44` | `9b1da32b2c56fa5c82fa6a1ab879157d4cc87bfa584e864d37e640e190a8b9fc` |

### 7.11 後のコミットへの申し送り（C4〜C6）

| 項目 | 内容 |
|---|---|
| 補い（C6） | 権限の要求と設定の画面は表示しない口（`requireForeground`）なので補いは関わらない。新しく ViewController を出す口を足すときは、`presentingViewController` が `present` の中で設定されるかを先に測り、されなければ `DeclineCheck.releaseWatchOnly` を渡す |
| ホストのアプリ（C4〜C6） | 本物の UI を記録するテストの補助は ViewController を `weak` で持つ（`SheetRecorder`）。強く持つと見張りが働かず、外から閉じたテストが止まる（C3 の最初の版でそうなった） |
| TSan（C7） | `IosLibrary` の手順で出したアラートとシートは TSan の版でも解放された（7.7）。C1・C2 の TSan の skip（`aRealViewControllerClosesTheBoxWhenFreed`、UT-14、`aDialogDismissedFromOutsideCallsNothingButTheNewAPIIsTold`、D20）を外せるかを C7 の全体の TSan の回で確かめる（8 章の 4） |
| `-only-testing`（C4〜C7） | iOS 18.3 のシミュレーターで `-only-testing` が 0 件になるのは、destination が 2 つの arch に合うため。`-destination 'platform=iOS Simulator,id=<udid>,arch=arm64'` と書けば Swift Testing の suite を選んで流せる（C1 の 1.8 の注を直す情報） |
| 第 2 部（2a） | Share は 2 つの要求の表示の順を約束しない（7.4 の 10）。C のヘッダーに書く。外から閉じたシートは約 0.55 秒後に `CANCELED_BY_SYSTEM`。表示元の scene が切れても window が残ればシートは解放されず完了しない（約束の外。R4-4） |
| 信頼する部分（C4〜C6） | C3 は識別子を足しただけ。C4 の Clipboard の新しいボタン（SA-15）は `ClipboardButton` か新しい列挙、C5・C6 の通知は `NotificationButton` に足す |

## 8. 利用者に決めてもらうこと（C3）

**決定（2026-11-01、利用者）: 5 つとも推奨のとおり。** 1 は 9 章の Codex のレビューの後に固定した。2 は付録 A に足した。3 は `DialogPresenting` の DocC に足した。4・5 は C7 で行う

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | 信頼する部分（`SampleApp.swift`）の変更（7.10。識別子の 3 つと I1c の 1 つ）と S18・S19 の simulator only を、別のモデルのレビューに出してからハッシュを固定する | **C2 と同じく別のモデル（Codex）に `SampleApp.swift` の差分と `SIMULATOR_ONLY_TESTS`・`DeviceRequirements.json` の 3 行を見せ、通ったら 7.10 の値を固定して C3 のコミットに入れる**。新しい操作が無いので観点は「識別子を足しただけか、区分が正しいか」の 2 つで足りる |
| 2 | 付録 A に `ShareContentUseCase.execute(content:presenter:)` が無い（7.4 の 3）。`presenter` を Repository に届けるのに要るので足した | **付録 A に足す**（追加で破壊的でない。今の `execute(content:)` は残した）。消すと Manager が Repository を直に呼ぶことになり common.md に反する |
| 3 | `PresenterSelection` は値を読む公開の口が無いので、公開の port（`ShareRepository`・`DialogPresenting`）を自分で実装する利用者は `presenter` に従えない。Share の port の DocC にはそう書いた（7.1）。Dialog の port の DocC（C2）は「`presenter` が選ぶ ViewController から出す」のまま | **C3 のコミットで `DialogPresenting` の DocC にも同じ 1 文を足す**（公開の API は足さない）。値を読む口（`@MainActor func resolve()` など）が要るとの声があれば 2.0.0 の後に足す |
| 4 | TSan の版でも `IosLibrary` の手順で出したアラートとシートは解放された（7.7）。C1・C2 は申し送り 1 の結果から見張りに頼るテストを TSan の回で skip している | **C7 の全体の TSan の回で skip を外して流し、通れば外して設計書 6.3.4・RK-11 を直す**。C3 の Share のテストは skip を付けずに TSan で通した |
| 5 | MS-02 の残り（`foregroundInactive` の間に `UIActivityViewController` を出せるか）は C3 のタスクに無い | **記録だけでよい**（C3 のついでに測った: 7.7 の最後の行）。`foregroundInactive` の間（Control Center を引き出した間）に `.foreground` で `UIActivityViewController` が出た。C7（T-20）で第 1 部の G-6 の記録に Share の分として足す |

## 9. C3 のレビューと直したこと

コードのレビューを 2 者で並行に行った。Claude のサブエージェント（設計との一致と正しさ）は A 0・B 1・C 6。ハッシュを合わせた写しで `--feature Dialog` 29/29（`changed=0, added=8`）と `--feature Share` 25/25（`changed=0, added=3`）を流し、共通の部分の変更が Dialog を壊していないことも確かめた。Codex（設定のモデル。並行・寿命と実機の安全。読むだけ）は A・B・C とも無し: どの終わり方でも完了は 1 回、見張りは `present` の前に付き弱く持っても外れる隙間は無い、Dialog の経路は変わらない、`Task` の取り消しが効かないのは P1-24 のとおり、`SampleApp.swift` の差分は識別子だけ、S17 は今の Copy の操作だけ、区分と simulator only は正しい。

| 指摘 | 直したこと |
|---|---|
| B-1: 公開の port `ShareRepository` の DocC が「`ShareError` 以外は Manager が `presentationFailed` で返す」と書く（外の実装は Manager に渡せず、UseCase はそのまま投げ直す。C2 の B1 と同じ種類） | port の DocC を「`ShareContentUseCase` は投げられたものをそのまま投げ直し、呼び出し側は `ShareError` を前提にするので `ShareError` だけを投げる」にし、UseCase の 2 つの Throws を「repository が投げたものをそのまま（ライブラリの repository なら `ShareError`）」に直した |
| C-1: 付録 A に無い `execute(content:presenter:)` | 8 章の 2 の決定で付録 A に足した。理由に「公開の port が `presenter` を取るので、UseCase に `presenter` の口が無いと外で組み立てても port の引数がいつも `.firstActiveScene` になる」も加わる |
| C-2: `aSheetThatIsStillBeingPresentedIsNotFailed` は表示の終わりを待ってから見る。`PresentationLog` の上の DocC は `UnstableForLegacyEnvironment` のもの | テストの名前を `aPresentedSheetIsNotFailed` にして注を直した。DocC を正しい型の上に移し、`PresentationLog` には自分の 1 行を付けた |
| C-3: `everyCaseHasItsOwnDescription` は配列の書き漏らしを捕まえない | 網羅の `switch` で case ごとに番号を返し、配列の番号が 0〜8 をちょうど 1 回ずつ持つことを確かめる形にした |
| C-4: `LibraryLogPrivacyTests` の Share の注が「外から閉じる」を通るとする | 注を「2 つとも handler で終わり、後の `dismiss` は片付けだけ（外から閉じる経路は通らない）」に直した |
| C-5: `present` の `onPresented` の注が、見張りを弱く持つようにした後も「見張りが記した後」とする。表示のアニメーションの間に外から閉じられ完了より先に解放されたシートは `presentationFailed` になりうる | `onPresented` の注に「見張りがまだ生きていれば（そこでは弱く持つ）」を足し、`IosShareManager` の DocC の表の `presentationFailed` の行に「表示が終わる前にシートが解放された（アニメーションの間に外から閉じられた）」を足した |
| C-6: 8 章の 3 | `DialogPresenting` の DocC の「ライブラリの実装だけが行うこと」に、`presenter` は値を読めないので外の実装は自分の方法で選ぶ、を足した |

信頼する部分: Codex のレビューの後、`TRUSTED_FILES` の `Support/SampleApp.swift` を 7.10 の値（`9b1da32b2c56fa5c82fa6a1ab879157d4cc87bfa584e864d37e640e190a8b9fc`）に固定した。固定した後、リポジトリでランナーの自己テスト 142/142、直したファイルに関わる単体テスト（Dialog・Share の 10 の suite と `LibraryLogPrivacyTests`・`PresentationProcedureTests`）138/138 を iPhone 17 / 26.2 で流した。警告は `appintentsmetadataprocessor` の「Metadata extraction skipped」だけ。直したのは DocC・テストの名前と注・1 つのテストの確かめ方なので、UI テストは流し直していない（レビューの写しの 25/25 と 29/29 のまま）

## 10. C4 Clipboard（T-12）

- 状態: ライブラリ・単体テスト（UT-30 と UT-15 の Clipboard の読み込み）・壊して確かめる・サンプル（SA-15）・UI テスト（CB5・CB6）・MS-08 は済んだ。コミットはしていない
- 信頼する部分（`Support/SampleApp.swift`）の変更は C3 と同じくリポジトリの作業ツリーに入れ、**ハッシュは固定していない**（別のモデルのレビューの後に固定する）。UI テストとランナーの自己テストは、ハッシュだけを直した使い捨ての写し（scratchpad）で流した（10.8）
- 測ったログ・下調べのサンプルとテスト・変異の差分は scratchpad に置き、リポジトリには入れていない
- C1〜C3 のレビューで出た指摘（外の実装者が守れる DocC、先頭のログの全引数と伏せ方、DocC の表とコードの経路の一致、取り消しの約束、Swift 6 の `isolated deinit` の罠、壊して確かめる、決まった待ちを使わずサンプルが状態を結果の行に出す、凍結したファイルに触れない、区分の宣言）を最初から当てた

### 10.1 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| Manager | `Clipboard/IosClipboardManager.swift` | `loadItem(_:scope:requestBox:completion:)` と `nonisolated cancelLoad(_:)` を足した。箱と 1 つの読み込みを結ぶ private の `ClipboardBoxedLoad`（`@MainActor` の普通の Swift のクラス。利用者の `@Sendable` でない完了を持ち、箱の閉じたときの処理から 1 回だけ呼ぶ）。型の DocC の「Threading」を直し（Unity のブリッジの記述を消し、C ABI の受け口が main に積んで呼ぶ形と、`cancelLoad` だけが nonisolated であることを書いた。設計書 18.1 の 11）、「Cancelling a load」の表（4 つの取り消し方）を足した。今の `loadItem` 2 つと `cancelAllLoads()` に DocC を書き、DocC の無かったほかの公開の口（`copy`・`append`・`read`・`readData`・`snapshot`・`clear`・`createPasteboard`・`removePasteboard`・`detectPatterns`・`detectValues` の各 2 つ、`stopObserving`・`checkForegroundChange`）にも短い DocC を付けた。今の `loadItem` 2 つの先頭のログに `request` の種類と UTI（`.private`）を足した |
| Data | `Clipboard/Data/File/ClipboardTemporaryFileStore.swift` | internal の `static discardUndelivered(_:fileManager:)`: 取り消しに負けて誰にも渡らなかった `.file` の結果の要求のフォルダを消す。ストアの形（`<temporary>/IosLibraryClipboard/<session>/<request>/<file>`）のときだけ消し、ほかの URL には触れない（10.4 の 1） |
| ログ | `Clipboard/Common/ClipboardLog.swift` | internal の `ClipboardLoadRequest.logKind`・`logTypeIdentifier` と `Result<ClipboardLoadedItem, ClipboardError>.logKind`（`success(<種類>)` / `failure(<errorCode>)`。読み込んだ値・UTI・ファイルの URL は出さない） |
| 共通 | `Common/Application/RequestBox.swift` | DocC の表に Clipboard の行を足し、「後のコミットで足す」の注を消した |
| テスト | `IosLibraryTests/Clipboard/Presentation/IosClipboardManagerRequestBoxTests.swift`（新）、`Common/LibraryLogPrivacyTests.swift` | 10.5 |
| サンプル（SA-15） | `IosLibraryExample/ClipboardSampleView.swift` | 節「Swift API (2.0.0)」（`clipboard.section.swiftAPI`、画面の最後）とボタン 2 つ: `loadTextThenCancel`（箱で読み、呼んだ直後に `cancelLoad`）、`loadTextWithCancelledBox`（`cancelLoad` してから、その箱で読む）。識別子は `ClipboardSampleIdentifiers.SwiftAPIAction`。結果の行は `<種類> #<n> [<印>] <中身>, calls=<その要求の完了の回数>, closedAtCancel=<cancelLoad から戻った時点で箱が閉じていたか>`。今の 54 のボタンと結果の行は変えていない |
| UI テスト | `IosLibraryExampleUITests/ClipboardPasteUITests.swift`、`Support/DeviceRequirements.json` | CB5・CB6 と宣言（どちらも `clipboard`。10.8） |
| UI テスト（信頼する部分） | `Support/SampleApp.swift` | 10.10 |
| ランナーの自己テスト | `scripts/tests/test_ios_ui_runner.py`、`scripts/tests/fixtures/ios_ui_runner/enumeration.json`・`otool-ov-device.txt`・`otool-l-device.txt` | 数（110 → 112）と冒頭の注、fixture の取り直し（10.8） |
| 文書 | `designs/2026-10-18-ios-c-abi-ui-test-design.md` | 3.5 に CB5・CB6 の置き場所、5.1 の一覧（Clipboard の節 1・ボタン 2、数）、U-14 の例外に CB5・CB6 |
| 公開 API | `results/swiftinterface/IosLibrary-after-1b-c4.swiftinterface`、`2026-10-31-stage1b-c4.diff` | 10.6 |

`ios/IosLibrary/IosLibrary.xcodeproj` は変えていない（フォルダーと同期するターゲット）。ランナー（`scripts/ios_ui_runner.py`）の表も変えていない（CB5・CB6 は `ClipboardPasteUITests` に入れたので、クラスの下限 `clipboard` がそのまま効く。`SIMULATOR_ONLY_TESTS` には入れない: 10.4 の 4）。

### 10.2 公開 API（付録 A の Clipboard との照合）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `@MainActor public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general, requestBox: RequestBox, completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void)` | 同じ（戻り値なし。`@MainActor` のクラスの本体に置いた。付録 A は `extension` と書くが、公開の形は同じ） | 一致 |
| `nonisolated public func cancelLoad(_ box: RequestBox)`（any thread, does not wait） | 同じ | 一致 |

ほかの公開の変更は無い（10.6 の差分は 2 行だけ）。今の口（`loadItem(_:scope:completion:) -> any ClipboardLoadToken`、`loadItem(_:scope:) async throws`、`cancelAllLoads()`、port の `ClipboardItemLoader`・`ClipboardLoadToken`、`LoadItemUseCase`）の宣言は swiftinterface で 1 文字も変わっていない。公開の記号にはすべて DocC を付けた（10.1 の Manager の行）。`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` は足していない（P1-17 の一覧の外は 0 のまま。`IosClipboardManager` の `@unchecked Sendable` と `ClipboardCancellationBox`・`ClipboardTemporaryFileStore` の既存のものは変えていない）。`ClipboardBoxedLoad` は `@MainActor` の普通のクラスで、`deinit` を持たない（0f の `ClipboardManagerCleanup` の形を崩していない。`IosClipboardManager` にも `deinit` を足していない）。

付録 A は今の口が `ClipboardUseCases`（public）から組める port を変えないので、箱は UseCase でなく Manager の層で結んだ（`ios.md` の「UseCase を置かない口」の「要求の取り消し」。読み込み自体は今の `LoadItemUseCase.execute` を通る）。付録 A に足すものは無い。

### 10.3 今の利用者から見て変わる動作

| 口 | 前 | 後 |
|---|---|---|
| `loadItem(_:scope:completion:)`（token を返す口） | - | 変わらない（読み込み・完了の時期・token の `cancel()` とも。UT-30 の `theTokenFormIsUnchanged`、今の `loadItemCallbackReturnsSuccessValue`） |
| `loadItem(_:scope:) async throws` | - | 変わらない（`Task` の取り消しで `ClipboardError.cancelled`。UT-30 の `theAsyncFormIsUnchanged`） |
| `cancelAllLoads()` | 2 つの形の読み込みを取り消す | 新しい箱の形の読み込みも取り消す（その完了も `CLIPBOARD_CANCELLED` で 1 回、箱は閉じる）。今の 2 つの形の動作は変わらない |
| ログ | `[loadItem] scope: …` | `[loadItem] request: <種類>, utType: <.private>, scope: …, completion: provided`。`async` 版は `[loadItem async]`。読み込んだ値は前と同じく出さない |
| DocC | 「Unity のブリッジだけがどのスレッドからも呼べる入口」 | 18.1 の 11 のとおり直した。ほかの口の DocC は足しただけ |

3.3 の表の Clipboard の行（追加: `loadItem(_:scope:requestBox:completion:)`・`cancelLoad(_:)`）のほかに、利用者に見える変更は無い。今の UI テスト（Clipboard の 26 件）は期待値を変えずに通った（10.8）。

### 10.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | 8.6「遅れて来た結果は閉じた箱に当たって捨てる」 | 捨てる結果が `.file` なら、その要求のフォルダを消す（`discardUndelivered`。ストアの形の URL だけ） | `.file` の結果は受け取った人がファイルを消す約束（今の DocC）。取り消した後に届いた結果は誰にも渡らないので、消さないと一時フォルダに残る。今の口では loader の gate が同じことをする（`ClipboardProviderLoadHandle.finish`）が、箱の形では「箱が閉じた（どのスレッドでも）」と「main で token を止める」の間に結果が着く隙間がある。M56・M57 で確かめた |
| 2 | 6.3.2 の閉じた理由は Dialog・Share の分も持つ（`notForeground` など） | Clipboard の箱がそれで閉じることは無い（それらで閉じる口は先に箱を付けるので、Clipboard は `invalidRequest` で断る）が、来たら読み込みを止めて `CLIPBOARD_CANCELLED` で返し、`.error` のログを出す | 網羅の `switch` のため。届かない経路なのでテストは無い |
| 3 | 13.2 は CB5・CB6 のクラスを書いていない | `ClipboardPasteUITests` に足した | UI テストの設計書 U-10・3.5 は「新しい Clipboard のテストは新しいクラス（`ClipboardPasteUITests` など）に書く」とし、凍結した `ClipboardUITests` には足せない。`ClipboardPasteUITests` はクラスの下限（`clipboard`）とランナーの実行の表に既にあり、新しいクラスを作るとランナーの `UI_CLASSES`・`CLASS_MINIMUMS` と自己テストを変えることになる。別のクラスにするかは利用者に尋ねる（11 章の 2） |
| 4 | 13.2 の環境はどちらも「両方」 | `SIMULATOR_ONLY_TESTS` には入れず、`clipboard` だけを宣言した。信頼する部分に `session.isDevice` の確かめは足していない | 使う操作はサンプルのボタン（`ClipboardToken` が要る）とランナーの一般のクリップボードへの書き込み（今の `RunnerPasteboard`、`requireUnchanged` で確かめる）だけで、決まった座標の操作も私物に触れる操作も無い。CB5 はサンプル自身の文字列を一般のクリップボードに書いて読む（U2・U14 と同じ）。CB6 はランナーが書いた文字列の上で何も読まない。実機では `clipboard` を許したとき（Handoff を切る前提。U-10・6.5）だけ流れる |
| 5 | SA-15「読み、すぐ cancelLoad するボタン」 | ボタンは箱で読んで同じ main の回の中で `cancelLoad` する。CB5 は先に `copyPlainText`（今のボタン）でサンプル自身の文字列を置く | 読み込みを始めると `NSItemProvider` の読み込みが動くので、ほかのアプリの内容なら貼り付けのダイアログが出うる。サンプル自身の内容にすればダイアログは出ず、取り消しだけを確かめられる。同じ回の中で取り消すので、結果（後の回にしか来ない）との競争は無い（決まった時間との競争をしない。C2 の 6 章の B2） |
| 6 | CB6「読み込まずに」 | ランナー（ほかのアプリ）が書いた文字列の上で、開始の前に取り消した箱で読み、貼り付けのダイアログが 2 秒出ないことと、完了が 1 回だけであることを見る | 読み込んだかどうかはサンプルから見えない。ほかのアプリの内容を読めばダイアログが出る（CB1 と同じ）ので、出ないことが「読んでいない」の印になる。壊した版（開始の前に閉じた箱でも読む）で CB6 が落ちることを確かめた（10.8） |
| 7 | 12 章の SA-05「全機能」の 3 秒後のボタンと MS-08 の「SA-05 と CB の操作」 | Clipboard のサンプルには 3 秒後のボタンを足さず、MS-08 は使い捨ての写しにだけ足した下調べのボタンと UI テストで測った（10.7） | 13.2 に Clipboard の後ろにいるときの UI テストが無く、13.3 は「押さないボタンを足さない」。C ABI も Clipboard は後ろにいるかを判定しない（第 1 部 5.13）ので、測るのは記録だけ（14 章）。サンプルに残すかは利用者に尋ねる（11 章の 1） |
| 8 | 8.6「DocC」 | 18.1 の 11 の直しに加え、DocC の無かった公開の口すべてに DocC を付けた | 「公開の記号には DocC」（`ios.md`）を Manager の全体で満たすため。動作は変えていない |
| 9 | 3.4・8.6「変更の監視（1 人の受け手）は変えない」 | 変えていない | - |

### 10.5 単体テストと壊して確かめたこと

| ID | ファイル | 件数 | 中身 |
|---|---|---|---|
| UT-30 | `Clipboard/Presentation/IosClipboardManagerRequestBoxTests.swift`（新） | 20 | 取り消し: 読み込み中の取り消しは `CLIPBOARD_CANCELLED` が 1 回で、箱は呼び出しの中で閉じ、完了と token の `cancel()` は後の main の回（`aCancelledLoad…`）、取り消しの後に届いた結果を捨てる（`aResultThatArrives…`）、開始の前に取り消した箱は読まない（loader を呼ばない）、結果の後の取り消しは何も変えない（token も止めない）、2 回の取り消しで 1 回、背景のスレッドからの取り消しが main を待たない（main を止めたまま 5 秒以内に戻る）で完了は main、背景のスレッドの取り消しと main の結果の競争 200 回で各 1 回（どちらが勝つかはその回しだい。下調べで 54/146、3/197）。箱: loader が呼び出しの中で結果を返しても完了は呼び出しの中で来ない、使い回しの箱は 2 つ目だけ `CLIPBOARD_INVALID_REQUEST`（呼び出しの中で来ない、最初の要求は続く）、終わった要求の箱も断る、Dialog が使った箱も断る、失敗の `errorCode`。ファイル: 取り消しの後に届いた `.file` は消す、渡したファイルは残す、ストアの形でない URL と浅い URL は消さない。ほかの取り消し方: `cancelAllLoads()` は箱の形も取り消す（今の形は前と同じく loader の呼び出しの中で返る）、`cancelLoad` は今の形の読み込みに触れない、今の token の形と `async` の形は変わらない。本物の loader と一意の pasteboard（`.general` には触れない）で、同じ回に取り消した読み込みは `CLIPBOARD_CANCELLED`、取り消さない読み込みは本文 |
| UT-15 | `Common/LibraryLogPrivacyTests.swift` | +1 | 本物の Manager と loader と一意の pasteboard で、番兵の本文を箱の形（成功と、すぐ取り消し）・token の形・`async` の形で読み、ライブラリのログに番兵が無い（読めていることを `#require`: `[ClipboardBoxedLoad] [report] result: success(text)` と `failure(CLIPBOARD_CANCELLED)`）。番兵は本文だけに入れた（UTI は `.private` で出してよく、この環境では `.private` も平文で見えるため） |

`IosLibraryTests` は 372 件（C3 の 351 件 + 21）。レビューで UT-30 に 1 件足し、373 件になった（12 章）。

壊して確かめたこと（`mutate_c4.py` で 1 つずつ当てて該当の suite を流し、落ちることを見てから戻した。差分とログは scratchpad）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M50 | UT-30 | 取り消しの後に届いた結果を利用者に渡す（設計書 13.1「遅れた結果を通す」） | `aResultThatArrivesAfterTheCancellationIsDropped`、`aFileThatArrivesAfterTheCancellationIsDeleted`、`aCancellationRacingTheResultReportsExactlyOnce` |
| M51 | UT-30 | `cancelLoad` が箱を後の main の回で閉じる | `aCancelledLoad…`、`aCancellationFromAnotherThread…`、`aBoxCancelledBeforeTheCallReadsNothing`、`aResultThatArrives…`、`aFileThatArrives…` |
| M52 | UT-30 | 開始の前に閉じた箱でも読む | `aBoxCancelledBeforeTheCallReadsNothing` |
| M53 | UT-30 | 取り消しで token を止めない | `aCancelledLoad…`、`cancellingTwiceReportsOnce`、`aCancellationFromAnotherThread…`、`aCancellationRacing…` |
| M54 | UT-30 | 使い回しの箱の失敗を呼び出しの中で返す | `aBoxThatAnotherRequestUsesFailsOnlyTheSecondRequest` |
| M55 | UT-30 | 使い回しの箱で最初の要求も取り消す | 同上 |
| M56 | UT-30 | 取り消しの後に届いたファイルを消さない | `aFileThatArrivesAfterTheCancellationIsDeleted` |
| M57 | UT-30 | ファイルを消す前に、ストアの root の下かだけを見る（形を見ない） | `discardingLeavesAFileOutsideTheStoreAlone`（浅い URL でセッションのフォルダを消した） |
| M58 | UT-30 | loader の完了の中で、箱を通さずにその場で利用者に渡す | `theCompletionNeverComesInsideTheCall`、`aResultThatArrives…`、`aFileThatArrives…`、`aCancellationRacing…` |
| M59 | UT-30 | `cancelLoad` が main 以外から呼ばれたら `DispatchQueue.main.sync` で閉じる（main を待つ） | `aCancellationFromAnotherThreadDoesNotWaitAndReportsOnMain`（5 秒の上限で戻り、止まらずに落ちた） |
| M60 | UT-30 | 今の token の形の失敗の `errorCode` を変える | `theTokenFormIsUnchanged`、`cancelAllLoadsCancelsABoxedLoadToo` |
| M61 | UT-15 | 完了のログに結果を `.public` で入れる（設計書 13.1「1 か所で値を `.public` で補間する」） | `clipboardLoadsNeverPutTheLoadedTextInTheLog` |

12 件とも落ち、戻した版で通ることを確かめた（全件の実行、10.8）。

TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2）: `IosClipboardManagerRequestBoxTests`・`IosClipboardManagerTests`・`RequestBoxTests`・`LibraryLogPrivacyTests` の 47 件が成功。TSan の報告は 0 件。箱の閉じたときの処理は main に積むだけなので、背景のスレッドの `cancelLoad` で止まらない（SR-3。`aCancellationFromAnotherThread…` と競争のテストを TSan でも流した）。

### 10.6 公開 API（swiftinterface）

- 組み方: C1〜C3 と同じ（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）。`arm64-apple-ios.swiftinterface` を写した
- 足したファイル: `IosLibrary-after-1b-c4.swiftinterface`、差分 `2026-10-31-stage1b-c4.diff`（`after-1b-c3` が基準）
- 差分の中身: `IosClipboardManager` に `loadItem(_:scope:requestBox:completion:)`（今の token の形と同じ `#if compiler(>=5.3) && $NonescapableTypes` の中）と `nonisolated final public func cancelLoad(_ box: RequestBox)` の 2 つが増えた。ほかは変わらない
- `swift-frontend -typecheck-module-from-interface`（Xcode 26.3、Swift 6.2.4）で public と private の 2 つとも型検査が通った（出力 0 行）

### 10.7 シミュレーターで測ったこと（C4 に付いた MS-08）

MS-08（後ろにいるときの `UIPasteboard` の読み込み。第 1 部 5.13 の Clipboard の行。記録だけ）。iPhone 17 / 26.2 のシミュレーター。使い捨ての写しにだけ、3 秒後に読むボタン 2 つ（箱の形の `loadItem(.text)` と、同期の `read`。結果の行に要求の時点と完了の時点のアプリの状態、かかった時間）と、下調べの UI テスト（`ProbeMS08UITests`。押して、ホームに移り、8 秒待ち、サンプルを前に戻して結果の行を読む）を足して測った（`apply_ms08_probe.py`。リポジトリには入れていない）。

| # | 読み方 | 一般のクリップボードの中身 | 結果 |
|---|---|---|---|
| P1 | `loadItem(_:scope:requestBox:completion:)`（`NSItemProvider`、非同期） | サンプル自身が書いた文字列 | 後ろ（`background`）のまま読めた。貼り付けのダイアログは出ない。完了まで約 60 ms で、完了の時点も `background` |
| P2 | 同上 | ランナー（ほかのアプリ）が書いた文字列 | **サンプルが後ろにいる間に貼り付けのダイアログが springboard の上に出た**。読み込みはダイアログの答えを待ち、サンプルを前に戻して「Allow Paste」を押すと成功した（要求から約 9 秒、完了の時点は `inactive`） |
| P3 | `read(scope:completion:)`（同期の `UIPasteboard` の読み出し） | サンプル自身が書いた文字列 | 後ろのまま読めた（約 21 ms）。ダイアログは出ない |
| P4 | 同上 | ランナーが書いた文字列 | **後ろにいる間に貼り付けのダイアログが出て、サンプルの main スレッドが答えを待って止まった**。XCUITest はサンプルを前に戻せず（`Unable to perform work on main run loop, process main thread busy for 30.0s`）、約 270 秒止まったままテストが落ちた（1 回） |

分かったこと: (1) 後ろにいても、自分の内容は読める（ダイアログなし）。(2) ほかのアプリの内容を読むと、後ろにいてもダイアログが出る。非同期の `loadItem` は答えを待つだけで main を止めない（箱の取り消しで終われる）。**同期の `read` は、答えが出るまで main を止める**（P4。同じく同期に中身を読む `readData` も同じ見込み。測っていない）。これは 1b の前からの今の口の振る舞い（OS の同期の API）で、C4 では変えていない。C4 では `read`・`readData` の DocC に「ダイアログの答えを main で待つ（後ろにいる間も）」を足した。C ABI は Clipboard で後ろにいるかを判定しない（第 1 部 5.13）ので、第 2 部の C の受け口が同期の読み出しを main のブロックの中で呼ぶと、後ろにいる間にほかのアプリの内容でダイアログが出たとき main が止まる（11 章の 5）。前面にいるときも同期の読み出しは答えを待つ見込みだが、C4 では測っていない

### 10.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1。`-parallel-testing-enabled NO`。18.3 の 2 つは 7.11 の注のとおり `-destination 'platform=iOS Simulator,id=<udid>,arch=arm64'`） | どれも 372/372（C3 の 351 + 21）。skip 0。消した・名前を替えたテストは無い |
| TSan | 10.5 の末尾 |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Clipboard`（ハッシュを固定した写し） | 34 件: 成功 33、skip 1（Navigation 2、IdentifierInventory 4、Clipboard 21 + skip 1、ClipboardPaste 5、ClipboardPasteDeny 1）。skip は基準と同じ意図した skip（`testU10b_namedPasteboardAfterProcessTermination`。M-08 がこの環境では決まらない）。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）との比べ合わせは `changed=0, added=2, removed=0`（足したのは CB5・CB6）。凍結した `ClipboardUITests` の 22 件と CB1〜CB4 は今の期待値のまま通った。I1d は Clipboard の 56 のボタンと節 12 で一致した。信頼する部分の警告なし |
| CB5・CB6 の壊して確かめる（写し。ライブラリを壊し、`xcodebuild test -only-testing` で 2 件だけ） | UM1（開始の前に閉じた箱でも読む。M52 と同じ壊し方）: CB5 は通り、**CB6 が落ちた**（完了は `CLIPBOARD_CANCELLED` のまま来たが、貼り付けのダイアログが出た: `an alert appeared: the load read the pasteboard`）。UM2（`cancelLoad` が箱を閉じない）: **CB5 が落ちた**（`✅ #3 [loadTextThenCancel] textLength=28, calls=1, closedAtCancel=false`）、CB6 も落ちた（読み込みが貼り付けのダイアログで止まり、結果の行が来ない）。戻した版は上の `--feature Clipboard` の回で通っている |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | 写し: 142/142。リポジトリ: 142 件のうち 4 件が落ちる（どれも `SampleApp.swift` のハッシュが固定と違うことによるもの: `SourceRules.test_the_real_tree_passes`、`Commands.test_preflight_refuses_the_device_when_the_trusted_part_changed`、`EndToEnd` の 2 件。C3 と同じ）。`scripts/tests` の全体はリポジトリで 350 件のうち同じ 4 件だけが落ちる（写しは Android・Windows のフォルダーを写していないので、その照合のテストが流れない） |
| 自己テストの fixture | 列挙（`enumeration.json`）は写しの `--feature Clipboard` の回の列挙（iPhone 17 / 26.2、Xcode 26.3、flat）をそのまま写した。前の fixture との差は CB5・CB6 の 2 つの項目だけ（UI テストは 112 件）。実機のバイナリ（`otool-ov-device.txt`・`otool-l-device.txt`）は写しを `generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組んだ UI テストのバンドルから取った（端末は使っていない。テストのメソッドの差は CB5・CB6 の 4 つの記号だけ）。どれにもローカルのパスは入っていない。数を照らす自己テストを 110 → 112 にした（サンプルのボタンの数 59 は Dialog・Notification・Share だけを数えるので変わらない） |
| ランナーの変異 | 流していない（ランナー `scripts/ios_ui_runner.py` は変えていない） |
| `scripts/test_ios.sh --dry-run --device-allow clipboard`（写し。`--udid` はどの端末でもない値、`--enumerate-udid` は iPhone 17 / 26.2。`--baseline` なし。`--devicectl-id` なし） | 先に `test_ios.sh` を読んで、`--dry-run` の `exit 0` より前に呼ぶのは `simctl list`、`xcodebuild -version`、列挙のシミュレーターへの `xcodebuild`、ランナー（`git` だけを呼ぶ）だけで、`devicectl` と実機の `xcodebuild` は呼ばないことを確かめた。消費済みの台帳も変わっていない（更新日時が前のまま）。112 件のうち 47 件を選び 65 件を除いた。**CB5・CB6（`[clipboard]`）は選ばれた**（CB3・CB4・I1d・`ClipboardUITests` の 21 件と同じ）。CB1・CB2 は `missing systemui`、S1 などは `missing sharesheet`、D17・D20〜D23・S18・S19 は `simulator only`。写しには未コミットの変更があるので、実機の回は断ると表示した |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1 は xcodebuild か `test_ios.sh` が起動し、終わった後に止めた（`test_ios.sh` は見つけたときの状態に戻す）。最後にどれも起動していないことを確かめた |

### 10.9 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| MS-08 の後に `read`・`readData` の DocC だけを直したので、`IosLibrary` の scheme を同じ組み方で両方の Xcode で組み直した | どちらもエラー 0、警告 0 |

### 10.10 信頼する部分の変更とハッシュ

`ios/IosLibraryExample/IosLibraryExampleUITests/Support/`。HEAD（`637b1078`）からの差分。別のモデルの再レビューに出す。

| ファイル | 操作 |
|---|---|
| `SampleApp.swift` | (1) `ClipboardButton` に `copyPlainText`（今のボタン。CB5 の準備）、`loadTextThenCancel`・`loadTextWithCancelledBox`（SA-15）の 3 つを足した。押す口は今の `tap(_ button: ClipboardButton, _ token: ClipboardToken)` だけで、`ClipboardToken` が要る（U-9）。(2) I1d の一覧（`SampleInventory.clipboardButtonNames`）に SA-15 の 2 つ、`expectedNonButtons(.clipboard)` に `clipboard.section.swiftAPI` を足した。**新しい操作・新しい要素の読み方は無い**（識別子を足しただけ） |
| ほかの 7 ファイル、凍結した `IosLibraryExampleUITests.swift` | 変えていない（CB5・CB6 は今の `RunnerPasteboard.write`・`requireUnchanged`、`observeQuietly`、`remainingAlertCount` を使う） |

識別子の文字列は信頼する部分の中だけにある（U-17。`ClipboardPasteUITests.swift` は `ClipboardButton` の case だけを使う）。

再レビューの後に固定するハッシュ（`python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests`。ほかの 7 ファイルと `FROZEN_CLIPBOARD_SHA256`（`4612943d…6cf3`）は変わらない）:

| ファイル | 今の固定 | 新しい値 |
|---|---|---|
| `Support/SampleApp.swift` | `9b1da32b…b9fc` | `9af74391d9751d5071cc4c5c7058eae57be057ceee6be2fc6440a738ebc3a12e` |

### 10.11 後のコミットへの申し送り（C5〜C7）

| 項目 | 内容 |
|---|---|
| 箱の使い方（C5・C6） | 通知の権限の要求と設定の画面は箱を外から受けない（11 章の S-6）。箱を受ける口を足すなら、Clipboard と同じく「付けてから `isClosed` を見て、閉じていれば何も始めない」「付けに失敗したら `invalidRequest` を後の回で」「結果は `box.close(.completed(…))` で閉じ、負けた結果の資源は片付ける」の 3 つ |
| 利用者の `@Sendable` でない完了（C5・C6） | 箱の閉じたときの処理（`@MainActor @Sendable`）から呼ぶときは、`@MainActor` の普通の Swift のクラスに持たせて捕まえる（`ClipboardBoxedLoad`）。`NSObject` の子にしない（0f の `isolated deinit` の罠） |
| 第 2 部（2a） | Clipboard の読み込みの C の受け口は、受け付けの時点で `RequestBox()` を作り、main のブロックの中で `loadItem(_:scope:requestBox:completion:)` を呼び、取り消しの関数は `cancelLoad(_:)` を呼ぶ（どのスレッドからでも、積まずに）。ただし `IosClipboardManager.shared` は main の actor でしか読めない（クラスが `@MainActor`）ので、取り消しの関数は main で受け取った Manager の参照を持っておくか、同じモジュールの中なので箱を直接 `close(.canceled)` する（`cancelLoad` がすることはそれだけ。12 章の B-1）。`.file` の結果の所有は受け口が引き継ぐ。取り消しに負けた `.file` はライブラリが消す。後ろにいるときの読み込みは 10.7 の MS-08 のとおり（判定しない） |
| `-only-testing`（C5〜C7） | 7.11 の注のとおり、iOS 18.3 のシミュレーターは `-destination 'platform=iOS Simulator,id=<udid>,arch=arm64'` で全件を流した（C4 は絞らずに全件） |
| C7 | MS-08 の結果を第 1 部 5.13 の Clipboard の行と README に写す（T-20） |

## 11. 利用者に決めてもらうこと（C4）

**決定（2026-11-01、利用者）: 5 つとも推奨のとおり。** 1 はサンプルに足さない。2 はこのまま。3 は 12 章の Codex のレビューの後に固定した。4 は設計書 8.6 に「取り消しに負けた `.file`」の行を足した。5 は第 2 部（2a）の C のヘッダーとマニュアル（段階 4）に書き、前面での待ちと実機での振る舞いは C7 か 2a の前に 1 回測る（実機は利用者の許可を得てから）

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | SA-05（3 秒後の要求）の Clipboard 版をサンプルに残すか。C4 は使い捨ての写しでだけ足して MS-08 を測った（10.4 の 7） | **残さない**。13.2 に Clipboard の後ろの UI テストが無く、13.3 は押さないボタンを足さない。C ABI も判定しないので記録だけで足りる。もう一度測るときは scratchpad の手順（`apply_ms08_probe.py`）を写しに当てる |
| 2 | CB5・CB6 を `ClipboardPasteUITests` に入れた（10.4 の 3）。名前は「貼り付け」だが、要求の箱の読み込みのテストも入る | **このままにする**。U-10 の「新しいクラス（`ClipboardPasteUITests` など）」に合い、クラスの下限と実行の表が既に効く。別のクラスにするとランナーの表と自己テストの変更（信頼の外だが守りの本体）が増える |
| 3 | 信頼する部分（`SampleApp.swift`）の変更（10.10。識別子の 3 つと I1d の 2 か所）と、CB5・CB6 を simulator only にしない判断（10.4 の 4）を、別のモデルのレビューに出してからハッシュを固定する | **C3 と同じく別のモデル（Codex）に `SampleApp.swift` の差分と `DeviceRequirements.json` の 2 行と CB5・CB6 の本体を見せ、通ったら 10.10 の値を固定して C4 のコミットに入れる**。新しい操作は無いので、観点は「識別子を足しただけか」「区分と実機での安全（CB5 は一般のクリップボードを書く、CB6 はランナーの内容の上で読まない）」の 2 つで足りる |
| 4 | 取り消しに負けた `.file` の結果をライブラリが消す（10.4 の 1。設計書 8.6 に無い） | **消す形のままにし、設計書 8.6 に 1 行足す**。消さないと一時フォルダに残り、利用者は URL を受け取らないので消せない |
| 5 | MS-08 の P4: 同期の `read` がほかのアプリの内容でダイアログを出すと、答えが出るまで main が止まる（後ろにいる間も）。C ABI の受け口は main のブロックの中で Manager を呼ぶ（P1-4）ので、C から同期の読み出しを呼ぶとゲームの main が止まりうる | **2.0.0 では口を変えず、第 2 部の C の読み出しの関数のヘッダーとマニュアルに「ほかのアプリの内容ではユーザーが答えるまで main が止まる。止めたくなければ非同期の読み込み（`loadItem`）を使う」と書く**。前面での同じ待ちの長さと実機での振る舞いは C7 か 2a の前に 1 回測る（実機は利用者の許可が要る） |

## 12. C4 のレビューと直したこと

コードのレビューを 2 者で並行に行った。Claude のサブエージェント（設計との一致と正しさ）は A 0・B 1・C 5。ハッシュを合わせた写しで `--feature Clipboard` 34 件（成功 33、skip 1 は意図した U10b。`changed=0, added=2, removed=0`）とランナーの自己テスト 142/142 を流し、凍結した `ClipboardUITests` のハッシュが `FROZEN_CLIPBOARD_SHA256` のままであることも確かめた。Codex（設定のモデル。並行・寿命と実機の安全。読むだけ）は指摘無し: 結果・別のスレッドからの `cancelLoad`・`cancelAllLoads`・呼ぶ前に閉じた箱・使い回しの箱のどれでも完了は main に 1 回、負けた `.file` を消す処理は渡したファイルを消さず渡さないファイルを残さない、`@unchecked Sendable`・`nonisolated(unsafe)`・Manager の `deinit` は増えていない、今の 2 つの形は変わらない、`SampleApp.swift` の差分は識別子だけ、CB5 はサンプル自身の文字列を書き CB6 は読まず、どちらも `clipboard` の区分に収まる（simulator only も `isDevice` の守りも要らない）、fixture にローカルのパスと端末の識別子は無い。

| 指摘 | 直したこと |
|---|---|
| B-1: 型と `cancelLoad(_:)` の DocC は「どのスレッドからでも」と書くが、`shared` はクラスの `@MainActor` を受け継ぐので、別のスレッドで `IosClipboardManager.shared.cancelLoad(box)` と書くと Swift 6 では組めない（レビューが `swiftc -typecheck -swift-version 6` で確かめた） | 型の Threading と `cancelLoad(_:)` の `- Note:` に「`shared` は main の actor で読む。別のスレッドから取り消すには、main で受け取った Manager（`Sendable`）を持っておき、それに対して呼ぶ」と書いた。付録 A の形（インスタンスの `nonisolated` のメソッド）は変えない。2a への申し送り（10.11）に、取り消しの関数が参照を持つか箱を直接閉じることを足した |
| C-1: DocC の表の「読み込みの間に Manager が無くなる」の行にテストが無い | UT-30 に `releasingTheManagerDuringABoxedLoadReportsCancelledOnce` を足した（箱の形で読み始め、Manager を手放すと loader の `cancelAll` が 1 回呼ばれ、後の回に `CLIPBOARD_CANCELLED` が 1 回、箱は閉じる） |
| C-2: テストの loader が `scope` を記録しない（`ClipboardBoxedLoad.start` が `.general` を渡す変異を、`.general` を読む本物の loader のテストでしか捕まえられない） | `PendingClipboardLoader` に `lastScope` を足し、`aFailedLoadReportsItsErrorCode` で `.named("ut30")` を確かめた |
| C-3: 先頭のログ（`ClipboardBoxedLoad.init(completion:)` にログが無い。`discardUndelivered` が `fileManager` を出さない） | `[init] completion: provided` を足し、`discardUndelivered` の先頭に `fileManager: default/custom` を足した |
| C-4: `aFileThatArrivesAfterTheCancellationIsDeleted` が実行のたびにセッションのフォルダを一時フォルダに残す | ほかの 2 つと同じく、セッションのフォルダを消す `defer` を足した |
| C-5: `checkForegroundChange` の「最初の確認は `false`」は `startObserving` の後には当たらない。`cancelLoad` はどの箱でも閉じる（Dialog の箱なら Dialog が終わる） | 「一度も確認も観察もしていない scope の最初の確認は `false`」に直し、`cancelLoad(_:)` に「Clipboard の読み込みの箱だけを渡す。ほかの要求の箱（Dialog など）を渡すとその要求が終わる」の `- Note:` を足した |

信頼する部分: Codex のレビューの後、`TRUSTED_FILES` の `Support/SampleApp.swift` を 10.10 の値（`9af74391d9751d5071cc4c5c7058eae57be057ceee6be2fc6440a738ebc3a12e`）に固定した。固定した後、リポジトリでランナーの自己テスト 142/142、直したファイルに関わる単体テスト（`IosClipboardManagerRequestBoxTests`・`IosClipboardManagerTests`・`LibraryLogPrivacyTests`・`RequestBoxTests`）48/48 を iPhone 17 / 26.2 で Xcode 26.6 の `-parallel-testing-enabled NO` で流した（警告は `appintentsmetadataprocessor` の決まったものだけ）。TSan（`IosClipboardManagerRequestBoxTests`・`IosClipboardManagerTests`・`RequestBoxTests`）は 41/41、報告 0 件。並列のクローンを切らずに流した 1 回は、各 suite が 2 回動き、2 回目の `privateValuesAreVisible`（canary の行がちょうど 1 つ）だけが落ちた。ライブラリの判定ではない記録のためのテストで、直したところとは関わらないので、全件の実行と同じく並列を切って流した結果を採った。直したのは DocC・ログ・テストなので、UI テストは流し直していない（レビューの写しの 34 件のまま）

## 13. C5 通知の delegate とイベント（T-13〜T-16）

- 状態: 前半（T-13・T-14。13.1〜13.10）: router、`CompletionOnce`、循環の防止、起動のきっかけ、proxy、`installDelegate()`・`isDelegateInstalled`、KVO、`didBecomeActive`、manager の delegate の準拠を外す、UT-19〜UT-22・UT-24、MS-05・MS-06・MS-12 は済んだ。後半（T-15・T-16。13.11〜13.21）: 印、値の木、イベントの口、`responses`・`settingsRequests`・`launchResponse()`、今の受け手と `setup()` の deprecated、UT-17・UT-18・UT-23・UT-25、サンプルの起動の処理と試験の形、UI テスト（N34b、N35〜N37、N41、N43〜N45。N40 は C6）、MS-07・MS-14 は済んだ。前半と後半は別の agent が同じ作業ツリーで作り、C5 は 1 つのコミットにする。**コミットはしていない**
- 2 回目の申し送りの結果（`results/2026-10-31-ios-c-abi-unity-handoff-2-results.md`）の H2-1（起動のきっかけは前面に出す応答だけ）、H2-3（差し替えは見張ってログに出し、自動では入れ直さない。入れ直せば戻る）、「1a-13 は足さない」を前提にした
- 測ったログ・下調べの写し（MS-05・MS-12）・変異の差分は scratchpad に置き、リポジトリには入れていない。シミュレーターだけで、実機には触れていない
- C1〜C4 のレビューで出た指摘（外の実装者が守れる DocC、先頭のログの全引数と伏せ方、DocC の表とコードの経路の一致、スレッドの約束を正確に、`NSObject` の子の `isolated deinit` の罠、P1-17 の一覧の外に `@unchecked Sendable`・`nonisolated(unsafe)` を足さない、壊して確かめる）を最初から当てた

### 13.1 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| Presentation（T-13） | `Notification/Presentation/Delegate/NotificationDelegateRouter.swift`（新、internal） | router と、router が受ける小さな値。`NotificationDelegateNotification`（identifier、date、push か、印があるか。`isLibraryNotification` は「push でなく印がある」）、`NotificationDelegateResponse`（通知、action、category、返信、userInfo、前面に出すか `Foreground`）、`NotificationDelegateUserInfo`（userInfo を main へ運ぶ二進の property list。13.4 の 4）、受け手の口 `NotificationDelegateEventSink`（`@MainActor` の `deliver(response:isLaunchResponse:)` と `deliver(settingsRequestFor:)`）。router は 3 つのメソッド（`willPresent` は表示の選択肢を汎用の `Options` で通すだけ）、循環の鍵の集合、起動のきっかけ（`launchResponse`・`isLaunchResponseSettled`・`noteFirstInstall`・`noteDidBecomeActive`）を持つ。状態は 1 つの `Mutex`。UserNotifications を import しない |
| Presentation（T-13） | `Notification/Presentation/Delegate/CompletionOnce.swift`（新、internal） | system の completion を 1 回だけ通す包み。2 回目からは捨ててログ（`.info`）。呼ばれた後は closure を手放す。`Sendable`（`@unchecked` なし。13.4 の 1） |
| Presentation（T-14） | `Notification/Presentation/Delegate/NotificationDelegateProxy.swift`（新、internal） | `UNUserNotificationCenterDelegate` を実装する proxy（`NSObject`、nonisolated、`Sendable`）。3 つのメソッドで `UNNotification` から router の値を作り、前の delegate がそのメソッドを持てば（呼ぶたびに `responds(to:)`）呼ぶ closure を渡す。前の delegate は `WeakNotificationDelegate`（同じファイル。`Mutex` の中の heap のオブジェクトが `weak` で持つ。13.4 の 2）。`@objc applicationDidBecomeActive(_:)`、KVO の `observeValue`（差し替えを `.error` で警告し、数を数える。入れ直さない）、`foreground(ofAction:)`（H2-1。13.4 の 3） |
| Presentation（T-14） | `Notification/Presentation/Delegate/NotificationDelegateInstaller.swift`（新、internal） | 入れる処理と入れた印（`Atomic<Bool>`。S-14）。`NotificationDelegateCenter`（`delegate` を持つ `NSObject`。`UNUserNotificationCenter` が準拠し、テストは偽物）。`static let shared`（proxy と印はプロセスで 1 つ、解放しない）。`@MainActor install(on:applicationIsActive:)`: 今の delegate が proxy なら何もしない、そうでなければ今の delegate を前の delegate にして proxy を入れる（差し替えの後なら `.info` のログ）、初めてなら `noteFirstInstall`・`didBecomeActive` の受け手・center の `delegate` の KVO を登録し印を立てる、`active` なら「起動の後かもしれない」の `.info`。**C5 のレビューの後**（16 章）: `shared` の組み立ては Manager の `IosNotificationManager.delegateInstaller` に移し、入れる順を「前の delegate と router の状態と観察 → `center.delegate` → 印」にし、center は closure で 2 回読む形にした |
| Domain | `Notification/Domain/Model/NotificationDelegateInstallResult.swift`（新、public） | `installed` / `notMainThread`（付録 A） |
| Domain | `Notification/Domain/Model/NotificationMarker.swift`（新、internal） | 印のキー `com.jonghyunkim.nativetoolkit`、値 `1`、`isPresent(in:)` だけ。付ける・外す・予約したキーの検査は後半（T-15。13.10） |
| Manager | `Notification/IosNotificationManager.swift` | `UNUserNotificationCenterDelegate` の extension（3 つの public のメソッド）を消した（S-P9）。`installDelegate()`（static、`@discardableResult`。`pthread_main_np()` で見て、main 以外は何もせず `.notMainThread`、main なら `MainActor.assumeIsolated` の中で installer を呼ぶ）と `isDelegateInstalled`（static、どのスレッドからでも）を足した。`setup()` は `installDelegate()` を呼ぶだけにした（main 以外は `.error` のログを出して何もしない。deprecated は後半）。router の受け手の口に internal で準拠し、`deliver(response:)` で今の受け手（返信があれば `onTextInputActionReceived`、無ければ `onActionReceived`）を main で呼ぶ。`deliver(settingsRequestFor:)` は**今の動作のまま `openNotificationSettings()`**（13.4 の 5）。`import UIKit` を足した。型の DocC（Overview・Threading・例）、`foregroundPresentationOptions`・2 つの受け手・受け手の typealias の DocC を直した |
| テスト | `IosLibraryTests/Notification/Presentation/Delegate/`（新、5 ファイル）、`Common/LibraryLogPrivacyTests.swift` | 13.6 |

`ios/IosLibrary/IosLibrary.xcodeproj` は変えていない（フォルダーと同期するターゲット）。サンプル・UI テスト・信頼する部分（`scripts/ios_ui_runner.py` の `TRUSTED_FILES`）・ブリッジは変えていない。

### 13.2 層と依存の向き

`common.md` の Clean Architecture（Domain → Application → Data → Presentation → Manager）のとおりに置いた。足したもの・直したものについて、ファイルごとの層と依存は次のとおり。

| ファイル | 層 | 依存するもの | 例外と理由 |
|---|---|---|---|
| `Domain/Model/NotificationDelegateInstallResult.swift` | Domain | Foundation だけ | - |
| `Domain/Model/NotificationMarker.swift` | Domain | Foundation だけ（`[AnyHashable: Any]` を読む） | - |
| `Presentation/Delegate/CompletionOnce.swift` | Presentation | `os`、`Synchronization` | - |
| `Presentation/Delegate/NotificationDelegateRouter.swift` | Presentation | Foundation、`os`、`Synchronization`、Domain の `NotificationMarker`（値だけ）、`CompletionOnce`、`LogRedaction` | UserNotifications も UIKit も import しない（S-P20、利用者の指示）。表示の選択肢は汎用の `Options`、前面かどうかは `@MainActor` の closure で受ける |
| `Presentation/Delegate/NotificationDelegateProxy.swift` | Presentation | UIKit（`Notification` の受け手）、UserNotifications、router、`NotificationMarker` | system の delegate を持つのはこの 1 つのクラスだけ（`common.md` の「Delegate の所有」。manager の準拠は外した） |
| `Presentation/Delegate/NotificationDelegateInstaller.swift` | Presentation | UIKit、UserNotifications、proxy、router | - （installer・router・proxy は受け手の口 `NotificationDelegateEventSink`（Presentation の protocol）だけを知り、Manager を参照しない。C5 のレビューの B-3 の前は `static let shared` が `IosNotificationManager.shared` を参照する例外があった。16 章） |
| `IosNotificationManager.swift` | Manager | Presentation の installer と受け手の口、Domain | ライブラリの installer の組み立て（`static let delegateInstaller`。受け手は `IosNotificationManager.shared`）はここに置く。`delegateInstaller` は初めて使うときに作られ、`shared` の初期化は installer を作らない（`NotificationDelegateStatus.library` は呼ぶたびに読む closure）ので、初期化の順に縛られない。`installDelegate()`・`isDelegateInstalled` は UseCase を置かない口（`ios.md` の「通知の delegate を入れる口」と「通知の delegate の状態の読み出し」）。受け手の口の実装も Data 層に届かないので UseCase を置かない |

Application（Port・UseCase）と Data には何も足していない。Domain と Application に platform の型を足していない（`NotificationDelegateInstallResult`・`NotificationMarker` は Foundation だけ）。

### 13.3 公開 API（付録 A の Notification の delegate の分との照合）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public enum NotificationDelegateInstallResult: Sendable { case installed, notMainThread }` | 同じ（`Domain/Model/`） | 一致 |
| `extension IosNotificationManager { // no longer a UNUserNotificationCenterDelegate` | 準拠を外した。`willPresent`・`didReceive`・`openSettingsFor` の 3 つの public のメソッドが消えた | 一致 |
| `@discardableResult public static func installDelegate() -> NotificationDelegateInstallResult` | 同じ | 一致 |
| `public static var isDelegateInstalled: Bool { get }` | 同じ | 一致 |
| `@available(*, deprecated, message: "Use installDelegate()") public static func setup()` | 形は今のまま、中を `installDelegate()` に替えた。**deprecated は後半**（T-16） | 後半で一致させる |
| `responses`・`settingsRequests`・`launchResponse()`・`NotificationEventHub`・`NotificationResponseEvent` など | 足していない（後半。T-15） | 後半 |

ほかの公開の変更は無い。`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` は足していない（P1-17 の一覧の外は 0 のまま。`CompletionOnce` も一覧に入っているが `@unchecked` は使わなかった。13.4 の 1）。足した型に `deinit` は無い（`NSObject` の子の proxy にも無い）。swiftinterface はまだ取っていない（後半が C5 全体で取る）。

### 13.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | P1-17 (3)・第 1 部 5.12.4: `CompletionOnce` は `@unchecked Sendable`（SDK の completion が `@Sendable` でない） | `@unchecked` なしの `Sendable`。closure は `@Sendable` で `Mutex` に入れる。proxy の 3 つのメソッドの completion の引数も `@Sendable` と書いた | Swift 6 は delegate のメソッドの completion handler を `@Sendable` として取り込む（`async` の形があるメソッドのため。前の delegate のメソッドに `@Sendable` でない closure を渡すと「`@Sendable` の closure を期待する関数」の警告が出ることを `-emit-sil` で確かめた）。Xcode 26.3 と 26.6 の両方で組めた。一覧で許されていても使わずに済むなら使わない。設計書 5.12.4 のコメントと P1-17 の一覧の (3) は C7 で直す（14 章の 2） |
| 2 | 8.3.2「proxy は nonisolated、`Sendable`、状態は `Mutex`」 | 前の delegate は、install のたびに作る `WeakNotificationDelegate`（`Sendable`。`Mutex` の中の heap の小さなクラスが `weak` で持つ）を、proxy の `Mutex` に入れ替える | Swift 6.2 の `Mutex` は、`Sendable` でない値を `withLock` の closure から入れられない（引数を `sending` にしても「`inout sending` は task-isolated にできない」で組めない。`-emit-sil` で 5 通り確かめた）。初期化（`sending`）だけが入れられるので、入れ替えるたびに新しい箱を作る。`weak` を `Mutex` の中に直に置くと、`Mutex` の初期化が値を動かし、Objective-C の弱い参照の登録とずれた（テストで `objc_storeWeak` の誤りのログが出てホストが落ちた）ので、heap のオブジェクトに持たせた。`@unchecked` は使っていない |
| 3 | 8.4.3「router が最初の `didReceive` を見て、最初の `didBecomeActive` より前でライブラリが扱ったなら起動のきっかけ」と H2-1「前面に出す応答だけ」 | 前面に出すかを `NotificationDelegateResponse.Foreground` で表す。本体のタップ（`UNNotificationDefaultActionIdentifier`）は前面、custom dismiss は前面でない、custom のアクションは **router が main に積んだブロックの中で `applicationState != .background` を読んで**決める。届いたときに「まだ active になっていない」かは `didReceive` の中（同期）で取る。プロセスで最初の**前面に出す**応答（転送したものを含む）が、届いたときにまだ active でなく、ライブラリが扱い、循環でなければ起動のきっかけ。背景のアクションは起動のきっかけにならず、「最初」の席も使わない | 応答は custom のアクションの選択肢（`.foreground`）を持たず、コールドスタートの `didReceive` の中では、前面に出す応答でも背景のアクションでも `applicationState` は `background`、scene は `unattached`、`targetScene` は `unattached`、`backgroundTimeRemaining` は最大で、見分けられない（MS-05。13.7）。積んだブロックの時点では、前面に出す応答なら scene が前面に入っていて、背景のアクションなら `background` のまま（26.2）。18.3 は積んだブロックが `didBecomeActive` の後に回るので、「active になる前に届いたか」はブロックの中でなく `didReceive` の中で決める。H2-1 は「最初」の数え方を決めていないので、背景のアクションは席を使わない形にした（14 章の 1） |
| 4 | S-P11・S-P25: イベントと今の受け手の userInfo は値の木から作る | 前半では値の木が無いので、userInfo を二進の property list（`Data`）にして main へ運び、今の受け手には `PropertyListSerialization` で作り直した辞書（`NSNumber`・`NSString`・`NSDate`・`NSData`・`NSArray`・`NSDictionary`）を渡す。property list にできない値があれば空の辞書（ログ） | `[AnyHashable: Any]` は `Sendable` でなく、proxy から main へ運べない（`@unchecked` の箱は足さない）。system は property list の値しか保存しないので、作り直した辞書は今と同じに読める（UT の `theValuesComeBackWithTheirFoundationTypes`）。値の木は後半（T-15）が入れ替える（13.10） |
| 5 | P1-10・8.3.2「`openSettingsFor` でライブラリが扱うときは `settingsRequests` のイベントを積む。設定の App は開かない」 | 前半では受け手の口の `deliver(settingsRequestFor:)` が**今の動作のまま** `openNotificationSettings()` を呼ぶ（main で、`openSettingsFor` から戻った後） | イベントの口は後半（T-15）。前半の作業ツリーで今の動作を保つため。後半で置き換える（13.10） |
| 6 | 6.1・8.3.2「proxy は `IosNotificationManager` の `static let` で強く持つ」 | `IosNotificationManager` の `static let delegateInstaller`（C5 のレビューの後。前は `NotificationDelegateInstaller.shared`）が installer を持ち、installer の `let proxy` が proxy を持つ（どちらも解放しない） | 入れる処理と入れた印と proxy を 1 つの型に置くと、テストが偽の center と自分の installer で、プロセスの印に触れずに全部を確かめられる。組み立ては Manager に置くので、Presentation から Manager への参照は無い（13.2） |
| 7 | 8.3.1「main 以外: すぐ `.notMainThread`。何も変えない。ログを出す」 | 同じ。`installDelegate()` の main 以外の経路は `.error` のログ。`setup()` も同じ経路で `.error` を足す | - |
| 8 | 8.3.2「KVO で差し替えをログに出す」 | `observeValue` が `.error` の警告（「差し替えた型、何回目か、`installDelegate()` を呼ぶまでライブラリの通知のコールバックは止まる、自動では入れ直さない」）を出し、`replacementCount` を数える。`nil` にしたのも差し替えとして数える。ライブラリ自身の設定は数えない | H2-3 の「ログに警告を出す」。数はテストが警告を確かめるのに使う（`Atomic`） |
| 9 | UT-19「前の delegate の振る舞い（無し、実装しない、…）」 | router のテストでは「無し」と「実装しない」は同じ（proxy が closure を渡さない）。「実装しない」の見分けは proxy の `previousDelegate(responding:)` のテストで確かめた | `UNNotification` はテストから作れないので、proxy の 3 つのメソッドは単体テストで呼べない（S-P20 のとおり、UI テストで確かめる。13.10） |
| 10 | 13.1 UT-21 の壊し方「closure を main actor の文脈で書く」 | 前の delegate に渡す closure は `@Sendable` の型なので、main actor の closure は型で渡せない（組めない）。変異は「渡す closure の中で `MainActor.assumeIsolated` を使う」にした（M64） | 型が守っているので、組める形で同じ前提（main で呼ばれる）を入れた |
| 11 | 8.3.2「router は純粋な値の型で、呼び出しごとに『ライブラリが扱う』か『前の delegate に渡す』の 2 つの結果のどちらかを返す」 | router は `Mutex` を持つ class（`Sendable`）で、決めるだけでなく、前の delegate への転送、main への積み込み、受け手の口の呼び出し、system の completion（`CompletionOnce`）まで行う（C5 のレビューの C-4 で記録した） | 循環の鍵の集合（5.12.5）と起動のきっかけ（P1-22）は呼び出しをまたぐ状態で、値の型では proxy が状態を持ち、決めた結果を proxy が実行することになる。そうすると UserNotifications を import しない router の単体テスト（S-P20）で、転送・main の順・completion の 1 回（1a-12、UT-19〜UT-22）を確かめられない。proxy には `UNNotification` から値を作ることと、前の delegate を呼ぶ closure を渡すことだけを残した |

### 13.5 今の利用者から見て変わる動作

前半の作業ツリーで、今の Swift の利用者とブリッジの利用者から見て変わるもの。どれも 3.3 の行に入る（入らないものは「3.3 の外」と書いた）。

| 口 | 前 | 後 | 3.3 |
|---|---|---|---|
| `IosNotificationManager` の型 | `UNUserNotificationCenterDelegate` に準拠し、3 つの public のメソッドを持つ | 準拠しない。3 つのメソッドが無い（`UNUserNotificationCenter.current().delegate = IosNotificationManager.shared` と書いた利用者のソースは組めなくなる） | 破壊的（S-P9） |
| `setup()` | どのスレッドからでも manager を delegate に入れる（前の delegate は捨てる） | main なら proxy を入れ、前の delegate に転送する。main 以外は何もせず `.error` のログ | 非推奨・動作（deprecated は後半） |
| ライブラリの通知でないもの | すべてライブラリが受ける | 前の delegate がそのメソッドを持てば前の delegate に渡り、ライブラリの受け手に届かない。持たなければ今と同じ | 動作。**前半ではライブラリの通知にまだ印が付かない**（T-15）ので、前の delegate がいるアプリでは、ライブラリが出した通知も前の delegate に渡る。後半で印が付くと設計書のとおりになる |
| `onActionReceived`・`onTextInputActionReceived` | system のスレッドで、`didReceive` の中で同期に | main で、`didReceive` から戻った後、system の completion の前 | 動作（1a-12） |
| 受け手に渡る userInfo | system の辞書そのもの | 同じ値を Foundation の型で作り直した別の辞書（13.4 の 4）。印はまだ外さない（後半） | 動作（S-P25 の形の先取り） |
| `openSettingsFor` | 同期に設定の App を開く | main で、戻った後に開く（後半でイベントに替わる） | 3.3 の外（前半だけの形） |
| 足す口 | - | `installDelegate()`、`isDelegateInstalled`、`NotificationDelegateInstallResult` | 追加 |
| ログ | `[willPresent]`・`[didReceive]`・`[openSettingsFor]`（manager） | proxy・router・installer・`CompletionOnce` の行。差し替えの警告（`.error`）、起動のきっかけ（`.info`）、2 回目の completion を捨てた（`.info`）、起動の後の入れ（`.info`）。返信と userInfo の値は出さない（長さと鍵の数だけ） | 動作（S-P21） |
| 入れたときに足すもの | - | 初めて入れたときに `UNUserNotificationCenter` の `delegate` の KVO と `UIApplication.didBecomeActiveNotification` の受け手（解放しない） | 追加（8.3.1） |

ブリッジ（`ios/UnityIosPlugin`）はソースを変えていない。`UnityIosNotificationManager.setup()` は `IosNotificationManager.setup()` を呼ぶので proxy が入り、受け手は main で呼ばれる（Unity の C# はもともと main）。

### 13.6 単体テストと壊して確かめたこと

| ID | ファイル（`IosLibraryTests/Notification/Presentation/Delegate/`） | 件数 | 中身 |
|---|---|---|---|
| UT-19 | `NotificationDelegateRouterTests.swift`（`NotificationDelegateRouterTableTests`） | 5（ケースは 35 + 35 + 10 + 2 + 1） | 1a delegate 3 章の表: 3 つのメソッド × 前の delegate の振る舞い（無し、同期、30 ms 後に main、30 ms 後に背景、2 回、捨てる、持ち続ける）× 通知の種類（ライブラリ、ホスト、1.x、印のある push、印の無い push）。どの組み合わせでも system の completion は 1 回以下で、捨てる・持ち続ける以外はちょうど 1 回。ライブラリの通知は前の delegate に渡らない。転送した `willPresent` は前の delegate の選択肢のまま、ライブラリが扱うものはライブラリの選択肢で呼び出しの中で完了。`didReceive` でライブラリが扱うものは呼び出しの中では完了せず、main でイベントを渡した後に completion（順を記録して確かめる）。`openSettingsFor` は転送か main のイベント、通知の無い要求はライブラリの通知でない（R-13）。8 スレッド × 25 回で同じ handler を呼んでも 1 回 |
| UT-20 | 同（`NotificationDelegateRouterCycleTests`） | 8 | 3 つのメソッドで、転送の中で同期に戻ってきた呼び出しを止め「誰も受けない」で扱う（`willPresent` はライブラリの選択肢、`didReceive` はイベント 1 つと completion 1 回で起動のきっかけにしない、`openSettingsFor` の `nil` はイベント 1 つ）。外側の転送の記録で席が使われなくても（状態を読むたびに変わる偽物）内側は起動のきっかけにならない（M74 の後に足した）。同じ identifier で date の違う配信、同じ配信の別の action は止めない。転送が戻った後は鍵が外れ、次の呼び出しはまた転送する。戻った後に非同期に戻ってくる形（契約の外）は止めないことも書いた |
| UT-21 | `CompletionOnceTests.swift` | 6 | 1 回目だけ通す、2 回目以降を捨てる（数は数える）、背景のキューから呼んでも止まらずそのスレッドで動く、8 スレッド × 25 回の競争で 1 回（20 回繰り返す）、呼んだ後は closure を手放す、呼ばれずに解放されたら何も呼ばず closure も手放す |
| UT-22 | 同（`NotificationDelegateRouterLaunchTests`） | 12 | P1-22 と H2-1: active になる前のライブラリの通知のタップは起動のきっかけ（`launchResponse`、`isLaunchResponseSettled`）、誰も受けない通知も同じ、`didBecomeActive` の後は無し、初めて入れたときに active なら無し・inactive なら残る、届いた後でブロックの前に active になっても起動のきっかけ（18.3 の順）、最初の応答を転送したら後のライブラリの応答も無し、2 つ目は無し、背景のアクションは無しで席も使わず次の前面の応答が起動のきっかけ、前面に出すアクションは起動のきっかけ、custom dismiss は無し、転送した背景のアクションも席を使わない |
| UT-24 | `NotificationDelegateInstallerTests.swift`（`NotificationDelegateInstallerTests`） | 10 | 偽の center で: 初めて入れると proxy・前の delegate・印、delegate が無いときは前の delegate も無し、2 回目は何も変えず前の delegate が proxy 自身にならない、差し替えを数えて自動では入れ直さず、入れ直すと差し替えた側の前に立つ（自分の設定は数えない）、観察は 1 回だけ登録（差し替え 2 回で 2）、`nil` にしたのも差し替え、前の delegate は弱い、初めて入れたときに active なら起動のきっかけは無い、`didBecomeActive` は初めて入れた後から受ける・その前は受けない |
| UT-24・MS-06・H2-3 | 同（`NotificationDelegateRealCenterTests`。`.serialized`） | 3 | 本物の `UNUserNotificationCenter`（テストのホストのアプリ）で: `Thread` と、そこから `DispatchQueue.global().sync` の中の `installDelegate()`・`setup()` は `.notMainThread` で delegate も印も変えない。MS-06（13.7）。H2-3: 入れた後に別の delegate（パッケージに似せた、転送しない delegate）で差し替えると、`.error` の警告が 1 つ出て（`OSLogStore` で読む）自動では入れ直さず、`installDelegate()` をもう一度呼ぶと proxy が戻り、前の delegate は差し替えた側になる |
| - | `NotificationDelegateProxyTests.swift`（`NotificationDelegateProxyTests`） | 5 | 前の delegate が 3 つを実装していれば使い、何も実装していなければ使わない（1a の noimpl）、`responds(to:)` は呼ぶたびに見る、`foreground(ofAction:)` の対応、push と印の判定 |
| - | 同（`NotificationDelegateUserInfoTests`） | 3 | 運んだ userInfo が Foundation の型で戻る（整数・実数・真偽値・文字列・日時・バイト列・配列・辞書・`UInt64.max`）、空は空、property list でない値は空で落ちない |
| - | 同（`IosNotificationManagerDelegateSinkTests`） | 4 | manager が受け手の口として: タップとアクションは `onActionReceived`、返信（空の返信も）は `onTextInputActionReceived` だけ、どちらも main。受け手が無くても落ちない。設定の要求は前半では今のとおり設定の画面を開く |
| UT-15 | `Common/LibraryLogPrivacyTests.swift` | +1 | router → manager（受け手の口）→ 今の受け手の経路で、番兵の返信と userInfo の値（入れ子も）がライブラリのログに無い（router と manager の行が読めることを `#require`）。転送の経路も通す |

`IosLibraryTests` は 430 件（C4 の 373 件 + 57）。今のテストは消していない・名前を替えていない（`IosNotificationManagerTests` の 15 件はそのまま通る）。

壊して確かめたこと（`mutate_c5a.py` で 1 つずつ当てて該当の suite を流し、落ちることを見てから戻した。差分とログは scratchpad）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M62 | UT-21 | `CompletionOnce` が呼ばれた後も closure を残す（2 回目以降も通す） | `laterCallsAreDropped`、`racingCallsPassOnce`、`theCompletionIsReleasedAfterTheCall` |
| M63 | UT-21 | 1 回だけ通すが、呼んだ後も closure を持ち続ける | `theCompletionIsReleasedAfterTheCall` |
| M64 | UT-21（R-4。13.4 の 10） | 前の delegate に渡す closure の中で `MainActor.assumeIsolated` を使う | 背景のキューから呼ぶケースでホストが止まった（`willPresent` の `asyncBackground` の途中で再起動） |
| M65 | UT-19（1a-7） | `didReceive` でライブラリの通知も前の delegate に渡す | `didReceive`（表） |
| M66 | UT-19（1a-12） | 印のある push をライブラリの通知とする | `willPresent`・`didReceive`・`openSettings`（表）、`theRouterSeesThePushAndTheMarker` |
| M67 | UT-19（1a-12） | ライブラリが扱う `didReceive` で、イベントを渡す前に completion を呼ぶ | `didReceive`（表） |
| M68 | UT-20（設計書 13.1「鍵に `date` を入れない」） | `willPresent` の鍵から date を外す | `theSameIdentifierWithAnotherDateIsForwarded` |
| M69 | UT-20 | 転送が戻った後に鍵を外さない | `theSameNotificationLaterIsForwardedAgain`、`comingBackAfterTheForwardingCallReturnedIsNotStopped` |
| M70 | UT-20 | `didReceive` の鍵から action を外す | `anotherActionOfTheSameDeliveryIsForwarded` |
| M71 | UT-22（設計書 13.1「転送したものを起動のきっかけにする」） | 転送した応答も起動のきっかけになりうる | `aForwardedFirstResponseLeavesNone` |
| M72 | UT-22 | 「active になる前に届いたか」を main のブロックの中で決める | `becomingActiveBeforeTheMainQueueBlockRunsKeepsIt` |
| M73 | UT-22（H2-1） | custom のアクションをいつも前面に出す応答とする | `aBackgroundActionIsNotTheLaunchResponse`、`aForwardedBackgroundActionLeavesTheFirstPlace` |
| M74 | UT-20・UT-22（R4-3） | 循環の内側も起動のきっかけになりうる | **最初は生き残った**（外側の転送の記録が先に席を使うので、ふつうは同じ結果になる）。状態が 2 回の記録の間で変わる形のテスト `theInnerCallOfACycleIsNeverTheLaunchResponse` を足して落ちることを確かめた |
| M75 | UT-24（設計書 13.1「2 回目に前の delegate を上書き」） | 今の delegate が proxy でも入れ直す | `aSecondInstallKeepsThePreviousDelegate` |
| M76 | UT-24 | 入れるたびに観察を登録する | `theCenterIsObservedOnlyOnce` |
| M77 | UT-24（H2-3） | 差し替えを見つけたら KVO の中で自分を入れ直す | `aReplacementIsWatchedAndInstallingAgainRestoresTheProxy` |
| M78 | UT-24（1a-9） | `installDelegate()` の main の確かめを外す | `offTheMainThreadNothingChanges` でホストが止まった（main 以外の `assumeIsolated`） |
| M79 | UT-24（P1-22） | 初めて入れたときの `applicationIsActive` を無視する | `aFirstInstallWhileActiveLeavesNoLaunchResponse` |
| M80 | proxy（第 1 部 5.12.1） | 前の delegate の `responds(to:)` を見ない | `aPreviousDelegateThatImplementsNothingIsNotUsed`、`respondsToIsCheckedOnEveryCall` |
| M81 | UT-15 | router の先頭のログに返信を生で入れる | `notificationResponsesThroughTheDelegateNeverReachTheLog` |
| M82 | 受け手の口 | 空の返信を `onActionReceived` に回す | `aReplyReachesOnTextInputActionReceived`（空の返信のケース） |
| M83 | H2-1 | 本体のタップを custom のアクションと同じ扱いにする | `theForegroundOfAnActionFollowsH21` |
| M84 | H2-3 | `nil` への差し替えを数えない | `clearingTheDelegateIsAReplacementToo` |

23 件とも落ち（M74 はテストを足した後）、戻した版で通ることを確かめた（13.8 の全件の実行）。

TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2）: `CompletionOnceTests`、router の 3 つの suite、installer の 2 つ、proxy、受け手の口、`IosNotificationManagerTests` の 68 件が成功。TSan の報告は 0 件。最初の回は `thePreviousDelegateIsHeldWeakly` が落ちた（TSan の版は autorelease された参照を長く持つので、弱い参照が `nil` にならない）。テストの中を `autoreleasepool` で包んで直した（ライブラリは変えていない）

### 13.7 シミュレーターで測ったこと（C5 前半に付いた MS-05・MS-06・MS-12）

**MS-05**（scene のアプリでの `didBecomeActive` の順。P1-22）。サンプル（SwiftUI、scene のアプリ）の使い捨ての写し（HEAD の `747897de`。今の受け手が `didReceive` の中で同期に呼ばれる形）に、app と scene の通知とそのときの状態、受け手の中の状態、`App.init` で積んだ `DispatchQueue.main.async` を記録する probe を足し、今の UI テスト（N30・N31・N32・N33・N25・N27・N28）をそのまま流した。2 回目は `didReceive` の中で `targetScene` と `backgroundTimeRemaining` も記録した（N30・N31・N33・N25・N27・N28）。どの回も UI テストは通った。

| 場面 | iPhone 17 / 26.2 | iPhone 16 / 18.3 |
|---|---|---|
| コールドスタート、本体のタップ（N30） | `didFinishLaunching`（app は background）→ `scene.willConnect` → **`didReceive`（app は background、scene は unattached）** → 同じ回に `scene.willEnterForeground` → `app.willEnterForeground`（inactive）→ 積んだブロック（inactive）→ `scene.didActivate` → `app.didBecomeActive` | 同じ順。ただし**積んだブロックは `app.didBecomeActive` の後**（active） |
| コールドスタート、Open（前面に出すアクション。N31） | N30 と同じ（`didReceive` の時点は background・unattached） | N30 と同じ |
| コールドスタート、Reply・Delete（背景のアクション。N32・N33） | `didReceive`（background・unattached）→ 積んだブロック（app も scene も background）→ テストが前に出したときに `willEnterForeground` | `didReceive`（background・unattached）→ テストが前に出す（4〜164 ms 後）→ 積んだブロック（inactive）。2 回目の N33 は、テストが先に前に出し、`didReceive` の時点で active だった |
| 背景からのタップ・Open（N25・N27） | `didReceive` の時点で app は inactive、scene は foregroundInactive | 同じ |
| 背景で Delete（N28） | `didReceive` の時点で app も scene も background | 同じ |
| `targetScene`（2 回目） | どの応答でも設定されている。コールドスタートでは前面の応答も背景のアクションも `unattached`。背景からのタップ・Open は foregroundInactive、Delete は background | 同じ（2 回目の N33 だけ foregroundActive。上の行） |
| `backgroundTimeRemaining`（2 回目） | どれも最大 | 同じ |

分かったこと: (1) scene のアプリでも、プロセスで最初の `UIApplication.didBecomeActiveNotification` はコールドスタートの応答の後に来る（P1-22 の前提は成り立つ。scene の通知を見る必要は無い）。(2) コールドスタートの `didReceive` の中では、前面に出す応答と背景のアクションを見分ける値が無い（`applicationState`、scene の状態、`targetScene`、`backgroundTimeRemaining`）。(3) `didReceive` から積んだ main のブロックの時点では、前面に出す応答なら scene が前面に入っている。背景のアクションなら 26.2 では background のまま。**18.3 では積んだブロックが遅れて回り、`didBecomeActive` の後になる**ことがあり、背景のアクションの直後にアプリが前に出されるとブロックの時点では inactive になる。そのため実装は、「active になる前に届いたか」を `didReceive` の中で取り、「前面に出すか」は本体のタップ・dismiss を action の識別子で、custom のアクションだけをブロックの時点の `applicationState` で決める（13.4 の 3）。18.3 で背景のアクションの直後（約 0.2 秒以内）に利用者がアプリを開くと、その背景のアクションを前面の応答と取りうる（14 章の 1）。scene の無いアプリはこの回では測っていない（1a の 2.4 で、scene の無いアプリの前面の起動は `didFinishLaunching` から inactive）

**MS-06**（main スレッドの上の `DispatchQueue(label:).sync` の中の `MainActor.assumeIsolated`。R-23）。`NotificationDelegateRealCenterTests.insideASyncBlockOnTheMainThreadTheInstallGoesThrough`: main スレッドから `DispatchQueue(label:).sync` の中で `pthread_main_np()` は真、`MainActor.assumeIsolated` は止まらず、`installDelegate()` は `.installed` を返して proxy が入った。iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1 の全件の実行（13.8）で通った。第 1 部 1.3 の判定の書き方（`pthread_main_np()`）は変えなくてよい

**MS-12**（`UIApplicationMain` の前の `installDelegate()`。G-9。1 回、iPhone 17 / 26.2）。`IosLibraryTestHost` の使い捨ての写しを `main.swift` で起動する形にし、`UIApplicationMain` の前に `installDelegate()` を呼んだ。結果: 落ちない。main スレッドで、`.installed` を返し、`isDelegateInstalled` は真。`UNUserNotificationCenter.current()` は使え、`didFinishLaunching` と最初の main のブロックでも delegate は proxy のまま、その後の 2 回目の呼び出しは何もしなかった。**ただし `UIApplication.shared` がまだ無いので `applicationState` は 0（`.active`）と読め**、「起動の後かもしれない」の `.info` が誤って出て、初めて入れたときに active とみなすので**起動のきっかけは決まらない**（コールドスタートのタップのイベント自体は届く見込み。測っていない）。DocC は「`UIApplicationMain` の前は対応しない」のまま（第 1 部 1.3.3 の「契約の外」）。マニュアルに「`UIApplicationMain` の前に呼ぶと起動のきっかけが取れない」と書く（段階 4。14 章の 3）

### 13.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1。`-parallel-testing-enabled NO`。18.3 の 2 つは `-destination 'platform=iOS Simulator,id=<udid>,arch=arm64'`） | どれも 430/430（C4 の 373 + 57）。skip 0。消した・名前を替えたテストは無い |
| TSan | 13.6 の末尾 |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Notification`（リポジトリのまま。信頼する部分のハッシュは固定のとおり） | 42 件すべて成功（権限の NP2・NP1、Navigation 2、IdentifierInventory 4、Notification 23、NotificationEvent 7、NotificationColdStart 4）。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）との比べ合わせは `changed=0, added=0, removed=0`。N25〜N33（今の受け手の経路、コールドスタートのタップ・Open・Reply・Delete）は proxy と main の受け手で期待値を変えずに通った。信頼する部分の警告なし。この回の後に足したのは 3 つの先頭のログ（`WeakNotificationDelegate.Reference.init`、router の `launchResponse`・`isLaunchResponseSettled`）だけで、その後に全件の単体テストと警告の確かめを流し直した（上の行と 13.9） |
| MS-05 の写しでの UI テスト | 13.7。HEAD の写しで N30〜N33・N25・N27・N28 を 2 つのシミュレーターで 2 回ずつ流し、どれも通った |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1 は xcodebuild・`simctl`・`test_ios.sh` が起動し、終わった後に止めた。MS-12 で写しの `IosLibraryTestHost` を入れた iPhone 17 からはそれを消した。iPhone 16 / 18.3.1 には MS-05 の写しのサンプル（probe のログ入り）が入ったまま（消すと通知の権限が戻るため。次の UI テストの回が入れ直す）。最後にどれも起動していないことを確かめた |

### 13.9 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme（`IosLibrary`、`IosLibraryExample`）を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |

`ios/UnityIosPlugin`（ワークスペースの外）は組んでいない（C1 と同じ）。

### 13.10 後半（T-15・T-16）への申し送り

| 項目 | 内容 |
|---|---|
| 受け手の口（seam） | `NotificationDelegateEventSink`（router の出口。`@MainActor`）。ライブラリの実体は `IosNotificationManager`（internal の extension、`IosNotificationManager.swift` の末尾）。`deliver(response:isLaunchResponse:)` は main のブロックの中で呼ばれ、戻った後に router が system の completion を呼ぶ（1a-12）。**ここで `responses` の hub に渡す（受け手か保ち）→ 今の受け手、の順にする**（8.3.2）。`deliver(settingsRequestFor:)` は今は `openNotificationSettings()`（今の動作）なので、`settingsRequests` の hub に替え、設定の App を開くのをやめる（P1-10、3.3） |
| イベントの値 | `NotificationDelegateResponse` に identifier、action、category、返信（`userText`。`nil` 以外はテキスト入力）、userInfo、`Foreground` がある。`NotificationResponseEvent` はこれと `isLaunchResponse` から作れる。userInfo は今 `NotificationDelegateUserInfo`（二進の property list の `Data`）で運ぶ。値の木（`NotificationUserInfoValue`）ができたら、proxy の `value(of: response)` で値の木を作り（印を外して）、`NotificationDelegateUserInfo` を置き換える。今の受け手の辞書は値の木から作る（S-P25）。router のテストの支え（`DelegateTestSupport.swift` の `TestNotificationKind.response`）と `NotificationDelegateUserInfoTests` も合わせて直す |
| 印 | `NotificationMarker`（`Domain/Model/`）に key・value・`isPresent(in:)` だけを置いた。付ける・外す・予約したキーの検査（8.3.3）はここに足す。**前半では表示・予約・更新が印を付けない**ので、前の delegate がいるとライブラリの通知も転送される（13.5）。印を付けるとそれが直る |
| `launchResponse()` | router の `launchResponse`（`NotificationDelegateResponse?`）と `isLaunchResponseSettled` を使う。どちらもどのスレッドからでも読める。`NotificationDelegateInstaller.shared.proxy.router` から届く。入れたかは `NotificationDelegateInstaller.shared.isInstalled`（= `isDelegateInstalled`）。起動のきっかけの印は main のブロックの中で決まるので、`didReceive` の直後はまだ `nil` で settled でもない（8.4.3 の「後で値に変わりうる」） |
| `delegateNotInstalled` のテスト | `NotificationDelegateRealCenterTests` が本物の center に proxy を入れるので、テストのプロセスでは**その後 `isDelegateInstalled` が真のまま**になる（suite の順は決まらない）。hub の「入れていないと `delegateNotInstalled`」のテストは、入れたかを読む口を hub に渡せる形（`NotificationDelegateInstaller` を作って渡すか、closure）にし、プロセスの印に頼らない |
| `setup()` の deprecated | 中は `installDelegate()` を呼ぶだけ。`@available(*, deprecated, message: "Use installDelegate()")` を付けると、`IosNotificationManagerTests` には呼ぶ所が無いが、`NotificationDelegateRealCenterTests.offTheMainThreadNothingChanges` が `setup()` を呼ぶので、そのテストに deprecated の警告が出る。テストの側で抑える形（`@available(*, deprecated)` を付けた helper から呼ぶ）にするか、呼ぶのをやめる |
| UI テスト | proxy の 3 つのメソッドは単体テストで呼べない（`UNNotification` を作れない）。サンプルの UI テスト（N25〜N33 は今の受け手の経路、後半の N34〜N45）が確かめる。前半では UI テストを変えていない。今の N25〜N33 は前半の作業ツリーで期待値を変えずに通った（13.8） |
| 前の delegate の影響（N41） | サンプルにホストの delegate を入れる形（SA-12）では、前半ではライブラリの通知も印が無いのでホストに渡る。N41 は印を付けた後（T-15）でないと通らない |
| H2-3 | 自動では入れ直さないことと、入れ直せば戻ることは `NotificationDelegateRealCenterTests` と `NotificationDelegateInstallerTests` で確かめた。マニュアル（段階 4）と 2c の包みに「パッケージの `AuthorizationRequest` の後に `installDelegate()` / `ntk_notification_install` をもう一度呼ぶ」と書く |
| C6 に残す今の不備（直していない） | (1) `IosNotificationManager` が `repository.openNotificationSettings()` と `repository.setBadgeCount` を UseCase なしで直に呼んでいる（`common.md` の Manager → UseCase → Repository に反する。T-17・T-18）。(2) port の `NotificationRepository` が `UNAuthorizationOptions` を使うが、`common.md` が求める例外の note が無い。(3) `Application/UseCase/NotificationDispatchUseCases.swift` が UN の型を使わないのに `import UserNotifications` している |

### 13.11 後半（T-15・T-16）で変えたもの（リポジトリ）

後半は 13.10 の申し送りの上に、前半と同じ作業ツリーで作った。**コミットはしていない**（C5 は前半と合わせて 1 つのコミットにする）。

| 区分 | ファイル | 中身 |
|---|---|---|
| Domain（T-15） | `Notification/Domain/Model/NotificationEvents.swift`（新） | public の `NotificationUserInfoValue`（値の木。S-P11）、`NotificationResponseEvent`（`description` は返信の長さと userInfo の鍵の数だけ）、`NotificationSettingsRequest`（付録 A）。internal の変換: `tree(of:)`（`[AnyHashable: Any]` → 値の木。`String` でない鍵と property list でない値は捨てて数え、ログは件数だけ）、`make(from: NSNumber)`（`CFBoolean` → 実数 → `Int64` → `UInt64` の順。S-P11）、`foundationValue`・`foundationDictionary`（`NSString`・`NSNumber`（真偽値は `CFBoolean`）・`NSDate`・`NSData`・`NSArray`・`NSDictionary` で作り直す。S-P25）。ログの形の internal の protocol `NotificationEventLogSummary` |
| Domain（T-15） | `Notification/Domain/Model/NotificationMarker.swift` | 付ける（`attaching(to:)`。値は `1`）、外す（`removing(from:)`）、予約したキーの検査（`isReserved(in:)`。値に関わらずキーだけで）を足した（8.3.3）。internal のまま |
| Domain（T-15） | `Notification/Domain/Model/NotificationError.swift` | `reservedUserInfoKey` と `delegateNotInstalled` の 2 つの case を足した。ほかの S-P7 の直し（`FailureDetail`、`Sendable`・`Equatable`・`LocalizedError`、使わない case を消す）は C6（T-17）のまま（13.15 の 2） |
| Presentation（T-15） | `Notification/Presentation/Event/NotificationEventHub.swift`（新、public） | `@MainActor` の `NotificationEventHub<Event: Sendable>` と `NotificationEventRegistration`（8.4.2、S-P10）。足す: 入れていなければ `delegateNotInstalled`、保ちがあれば先に外してから、その呼び出しの中で足した受け手に受けた順に渡す。渡す途中で受け手が自分を外したら、残りは並びに残る最も古い受け手へ、無ければ保ちの先頭へ戻す。配る: 並びの写しを取り、外された受け手は呼ばない。受け手が 0 なら 32 件まで保ち、超えたら古いものから捨てる（hub ごとに最初の 1 回だけ `.info`、以後 `.debug`）。外す: その場で、2 回目は何もしない。init は internal で `nonisolated`（「入れたか」を読む closure を受ける。13.10 の申し送り） |
| Presentation（T-15） | `Notification/Presentation/Delegate/NotificationDelegateRouter.swift` | `NotificationDelegateUserInfo`（二進の property list）を消し、`NotificationDelegateResponse.userInfo` を値の木（`[String: NotificationUserInfoValue]`）にした（13.10） |
| Presentation（T-15） | `Notification/Presentation/Delegate/NotificationDelegateProxy.swift` | `userInfoValues(of:)`: 届いた userInfo から印を外して値の木にする。`value(of: response)` がそれを使う |
| Presentation（T-15） | `Notification/Presentation/Delegate/NotificationDelegateInstaller.swift` | internal の `NotificationDelegateStatus`（「入れたか」と「起動のきっかけ」を読む 2 つの closure。`library` は `NotificationDelegateInstaller.shared` を呼ぶたびに読む。テストは自分の closure を渡す。13.10 の申し送り） |
| Data（T-15） | `Notification/Data/Repository/NotificationRepositoryImpl.swift` | `show`・`schedule`・`update` の**入口の最初**（`update` は今の予約を消す前）に予約したキーを `reservedUserInfoKey` で断る。足す要求の userInfo に印を付ける。`getScheduled`・`getDelivered` の userInfo から印を外す。要求の追加・削除・一覧を internal の `NotificationRequestCenter`（本番は `CurrentNotificationRequestCenter` が呼ぶたびに `UNUserNotificationCenter.current()` を読む）に通し、internal の `init(requestCenter:)` を足した（13.15 の 4） |
| Application（T-15） | `Notification/Application/Port/NotificationRepository.swift` | DocC だけ: 印を付ける・予約したキーを断る・一覧から外すのはライブラリの `NotificationRepositoryImpl` だけで、自分で実装した port が足した通知はライブラリの通知でない（前の delegate があればそちらへ渡る）と書いた |
| Manager（T-15・T-16） | `Notification/IosNotificationManager.swift` | `responses`・`settingsRequests`（どのスレッドからでも読める hub）と `@MainActor launchResponse() throws(NotificationError)` を足した。受け手の口の `deliver(response:)` は、hub に渡す（受け手か保ち）→ 今の受け手（値の木から Foundation の型で作り直した辞書）の順。`deliver(settingsRequestFor:)` は `settingsRequests` に渡すだけで、設定の App を開かない（P1-10）。`setup()`・`onActionReceived`・`onTextInputActionReceived` を deprecated にした（S-P8。受け手の getter / setter に先頭のログ）。テストの init に `delegateStatus` を足した（既定は `library`）。型と口の DocC（Overview・Threading・例、`installDelegate()` の SwiftUI の注意。13.15 の 7） |
| テスト | `IosLibraryTests/Notification/Presentation/Event/NotificationEventHubTests.swift`（新）、`Notification/Domain/NotificationUserInfoValueTests.swift`（新）、`Notification/Data/NotificationRepositoryMarkerTests.swift`（新）、`Notification/Presentation/IosNotificationManagerEventTests.swift`（新）、`Notification/Presentation/Delegate/Support/DeprecatedNotificationCalls.swift`（新）、前半のテストの直し（`DelegateTestSupport.swift`、`NotificationDelegateProxyTests.swift`、`NotificationDelegateInstallerTests.swift`、`IosNotificationManagerTests.swift`、`Common/LibraryLogPrivacyTests.swift`） | 13.16 |
| サンプル（T-16） | `IosLibraryExample/SampleLaunchConfiguration.swift`（新） | 試験の形（SA-18）: 起動の引数 `-ntkSampleTestMode <none/legacyReceivers/delayListener>` と旗 `-ntkSampleHostDelegate`（SA-12）を読み、Application Support の `ntk-sample-test-mode.txt` に書く。引数の無い起動はファイルを読む。どこから読んだか（`arguments` / `file` / `defaults`）も返す。`UserDefaults` は使わない |
| サンプル（T-16） | `IosLibraryExample/NotificationEventRouting.swift`（新） | 起動の処理（SA-06・SA-08・SA-11・SA-12・SA-18）: ホストの delegate（`SampleHostNotificationDelegate`。`willPresent` と `didReceive` を実装し、受けた数と最後の識別子を記録）を先に入れる形、`legacyReceivers` は今の受け手 → `setup()`（deprecated の呼び出しは protocol の witness を通して警告を出さない）、ほかは `installDelegate()` → 1 人目の受け手（`delayListener` は 3 秒後。C5 のレビューの UI C-1 で 5 秒後にした。16 章）。`settingsRequests` の受け手はどの形でも足す。1 人目の受け手は最後のイベントを記録し、`addListener` の呼び出しの中で受けたら `delivery=held`。2 人目の受け手の足し外し（SA-06）、`launchResponse()` の結果の行（SA-08）、ライブラリを通さないホストの通知（印なし。SA-12） |
| サンプル（T-16） | `IosLibraryExample/IosLibraryExampleApp.swift` | 起動の処理を `App.init` から `UIApplicationDelegateAdaptor` の `application(_:didFinishLaunchingWithOptions:)`（`SampleAppDelegate`）に移した（13.15 の 7、13.17 の 3） |
| サンプル（T-16） | `IosLibraryExample/NotificationEventLog.swift` | 最後のイベントに経路（`hub` / `legacy`）、`isLaunchResponse`、`live` / `held` を足した。状態（`install`、`isDelegateInstalled`、形と読んだ所、ホストの delegate、受け手ごとの数、設定の要求、ホストの受けたもの）を同じ鍵で持つ |
| サンプル（T-16） | `IosLibraryExample/NotificationSampleView.swift` | 節「Swift API (2.0.0)」（`notification.section.swiftAPI`）と、ボタン 4 つ（`addSecondListener`、`removeSecondListener`、`readLaunchResponse`、`showHostNotification`）、状態の行 4 つ（`notification.launchStatus`・`listenerCounts`・`lastSettingsRequest`・`hostEvent`）。最後のイベントの `notification.lastEvent.sequence` の `accessibilityValue` に `path=…,launch=…,delivery=…,mode=…,source=…`（見た目は変えない）。今の 25 のボタン・結果の行・最後のイベントの 5 行は変えていない。返信の全文はログに出さない（長さだけ。SA-07。前から） |
| UI テスト | `NotificationUITests.swift`（N34b）、`NotificationEventUITests.swift`（N35、N41、N43、N44。N25〜N29 に経路の確かめ）、`NotificationColdStartUITests.swift`（N36、N37、N45。N30〜N33 に経路の確かめ）、`Support/DeviceRequirements.json`（8 件） | 13.18 |
| UI テスト（信頼する部分） | `Support/SampleApp.swift`、`Support/SampleUITestCase.swift` | 13.20 |
| ランナーの自己テスト | `scripts/tests/test_ios_ui_runner.py`、`scripts/tests/fixtures/ios_ui_runner/enumeration.json`・`otool-ov-device.txt`・`otool-l-device.txt` | 数（112 → 120、サンプルのボタン 59 → 63）と冒頭の注、fixture の取り直し（13.18） |
| 文書 | `designs/2026-10-18-ios-c-abi-ui-test-design.md` | 3.3 に C5 のテストの表と試験の形、5.1 の一覧（Notification の節 1・ボタン 4・状態の行 4、数）、U-14 の例外に N35・N36・N41 |
| 文書 | `designs/2026-10-31-ios-c-abi-swift-api-design.md` | 13.2 の N34（`testN34b_…` と状態の行にしたこと）と N40（MS-07 の結果と、C6 で SA-13 と一緒に足すこと）に注を足した |
| 公開 API | `results/swiftinterface/IosLibrary-after-1b-c5.swiftinterface`、`2026-10-31-stage1b-c5.diff` | 13.13 |

`ios/IosLibrary/IosLibrary.xcodeproj` と `ios/IosLibraryExample/IosLibraryExample.xcodeproj` は変えていない（フォルダーと同期するターゲット）。ランナー（`scripts/ios_ui_runner.py`）の表も変えていない（新しいテストは今の 3 つのクラスに入れたので、クラスの下限 `systemui` がそのまま効く。`SIMULATOR_ONLY_TESTS` に足したものは無い: 13.18）。ブリッジ（`ios/UnityIosPlugin`）は変えていない（13.14 の末尾）。

### 13.12 層と依存の向き（後半）

| ファイル | 層 | 依存するもの | 例外と理由 |
|---|---|---|---|
| `Domain/Model/NotificationEvents.swift` | Domain | Foundation（`NSNumber`・`CFBoolean` を読む）、`os`、`LogRedaction`（`caseName`） | - |
| `Domain/Model/NotificationMarker.swift` | Domain | Foundation、`os` | - |
| `Domain/Model/NotificationError.swift` | Domain | Foundation | - |
| `Presentation/Event/NotificationEventHub.swift` | Presentation | Foundation、`os`、Domain の `NotificationError`・`NotificationEventLogSummary` | UseCase を置かない（`ios.md` の「受け手の登録・解除」。Data に届かない）。Manager から作り、Manager の口で公開する |
| `Presentation/Delegate/NotificationDelegateRouter.swift` | Presentation | 前半の依存 + Domain の `NotificationUserInfoValue`（値だけ） | 前半と同じく UserNotifications も UIKit も import しない |
| `Presentation/Delegate/NotificationDelegateProxy.swift` | Presentation | 前半の依存 + Domain の `NotificationUserInfoValue`・`NotificationMarker.removing` | - |
| `Presentation/Delegate/NotificationDelegateInstaller.swift` | Presentation | 前半の依存（`NotificationDelegateStatus` は 2 つの closure を持つだけの値） | -（C5 のレビューの B-3 で、`NotificationDelegateStatus.library` と installer の組み立てを `IosNotificationManager.swift` に移した。13.2） |
| `Data/Repository/NotificationRepositoryImpl.swift` | Data | 今の依存 + Domain の `NotificationMarker` | `NotificationRequestCenter` は Data の中の internal の抽象（`UNNotificationRequest` を持つので Domain・Application には置かない。テストの偽物のため） |
| `Application/Port/NotificationRepository.swift` | Application | 変えていない（DocC だけ） | - |
| `IosNotificationManager.swift` | Manager | Presentation の hub・installer・`NotificationDelegateStatus`、Domain の events・marker | `NotificationDelegateStatus.library`（`delegateInstaller` を呼ぶたびに読む）もここに置く（13.2）。`responses`・`settingsRequests`・`launchResponse()` は UseCase を置かない口（受け手の登録と、Data に届かない状態の読み取り。`ios.md` の「通知の delegate の状態の読み出し」は C5 のレビューの C-5 で一覧に足した）。`deliver(response:)` が値の木から今の受け手の辞書を作るのは Domain の変換を呼ぶだけ |

Domain と Application に platform の型を足していない（events・marker・error は Foundation だけ。値の木の変換は `NSNumber` を読むが、Foundation の型）。13.10 の C6 に残す 3 つ（Manager が `openNotificationSettings`・`setBadgeCount` を UseCase なしで呼ぶ、port の `UNAuthorizationOptions` の注、`NotificationDispatchUseCases.swift` の不要な import）は直していない。

### 13.13 公開 API（付録 A の Notification の delegate とイベントの分との照合。C5 全体）

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public indirect enum NotificationUserInfoValue: Sendable, Equatable { case string, integer(Int64), unsignedInteger(UInt64), double, bool, date, data, array, dictionary }` | 同じ | 一致 |
| `public struct NotificationResponseEvent: Sendable, Equatable, CustomStringConvertible`（6 つの `let`） | 同じ。public の init は無い（付録 A にも無い） | 一致 |
| `public struct NotificationSettingsRequest: Sendable, Equatable { public let notificationIdentifier: String? }` | 同じ | 一致 |
| `@MainActor public final class NotificationEventHub<Event: Sendable> { addListener(_:) throws(NotificationError) -> NotificationEventRegistration }` | 同じ形に **`@discardableResult`** を足した（13.15 の 1） | ほぼ一致 |
| `@MainActor public final class NotificationEventRegistration { public func remove() }` | 同じ | 一致 |
| `public var responses` / `settingsRequests: NotificationEventHub<…> { get }` | 同じ（計算プロパティ。中は private の `let`） | 一致 |
| `@MainActor public func launchResponse() throws(NotificationError) -> NotificationResponseEvent?` | 同じ | 一致 |
| `@available(*, deprecated, message: "Use installDelegate()") public static func setup()` | 同じ | 一致（前半の「後半で一致させる」） |
| `@available(*, deprecated, message: "Use responses") public var onActionReceived` / `onTextInputActionReceived` | 同じ | 一致 |
| `NotificationError` の `reservedUserInfoKey`・`delegateNotInstalled` | この 2 つだけ足した。付録 A の残り（`Sendable, Equatable, LocalizedError`、`FailureDetail` の case、`invalidUserInfo`・`notForeground`・`openSettingsFailed`、消す case）は C6 | C6 で一致させる |
| 前半の `NotificationDelegateInstallResult`・`installDelegate()`・`isDelegateInstalled`、準拠を外す | 13.3 のまま | 一致 |

swiftinterface（C4 と同じ組み方: Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3。`arm64-apple-ios.swiftinterface` を写した）: `IosLibrary-after-1b-c5.swiftinterface` と差分 `2026-10-31-stage1b-c5.diff`（`after-1b-c4` が基準。C5 の前半と後半の全体）。差分は、上の表の型と口、`NotificationError` の 2 つの case、`NotificationDelegateInstallResult`、3 つの deprecated、`UNUserNotificationCenterDelegate` の準拠の extension が消えたこと、`NotificationEventHub`・`NotificationEventRegistration` の `Sendable`（main actor の型が暗に持つもの）、それと **`NotificationRepositoryImpl` に `@_hasMissingDesignatedInitializers` が付いた**こと（internal の `init(requestCenter:)` を足したため。`final` のクラスなので継承の初期化子を受け継ぐ利用者はおらず、利用者のソースと ABI に影響は無い）。`addListener` の受け手の型は `@MainActor @Sendable` と出る（main actor の closure の型は Swift 6 で暗に `Sendable`）。`swift-frontend -typecheck-module-from-interface`（Xcode 26.3、Swift 6.2.4、`-F` に framework の置き場）で public と private の 2 つとも型検査が通った（出力 0 行）。

`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` はライブラリに足していない（P1-17 の一覧の外は 0 のまま）。テストの偽物 `FakeRequestCenter`（`UNNotificationRequest` が `Sendable` でないため `@unchecked Sendable`、鍵で守る）はテストのコードだけで、前半の `FakeNotificationCenter` と同じ扱い。足した型に `deinit` は無い（hub と登録は `@MainActor` の普通の Swift のクラスで、`NSObject` の子でない。`isolated deinit` も無い）。

### 13.14 今の利用者から見て変わる動作（後半。3.3）

前半の 13.5 に続けて、後半で変わったもの。どれも 3.3 の行に入る。

| 口 | 前 | 後 | 3.3 |
|---|---|---|---|
| `show`・`schedule`・`update` | userInfo をそのまま足す | 入口の最初にキー `com.jonghyunkim.nativetoolkit` があれば `reservedUserInfoKey` で失敗し、何も足さず消さない（`update` は今の予約を消す前に）。通れば印を付けて足す。callback 版の `errorMessage` は C6 で固定の文言になるまで OS の言語の汎用の文（`NotificationError` がまだ `LocalizedError` でない） | 動作（P1-9。3.3 の「予約したキーを拒む」） |
| `getScheduled`・`getDelivered` | userInfo をそのまま返す | 印を外して返す（型は今のまま。`Sendable` と値の木は C6） | 動作（8.3.3） |
| 前の delegate がいるアプリでのライブラリの通知 | 前半の作業ツリーでは印が無く前の delegate に渡った（13.5） | 印でライブラリの通知と分かり、前の delegate に渡らない（N41） | 動作（設計書のとおりになった） |
| `openSettingsFor` | 前は設定の App を開いた（前半の作業ツリーは main で、戻った後に開いた） | `settingsRequests` のイベントになる。ライブラリは何も開かない | 動作（P1-10。3.3 の `openSettingsFor`） |
| 今の受け手に渡る userInfo | 前半: Foundation の型で作り直した辞書、印は付いたまま | 値の木から Foundation の型で作り直した辞書で、印を外す | 動作（3.3 の「印が外れる」） |
| `setup()`・`onActionReceived`・`onTextInputActionReceived` | - | deprecated（呼ぶ所に警告が出る） | 非推奨（3.3） |
| `NotificationError` | 7 つの case | `reservedUserInfoKey`・`delegateNotInstalled` が増えた（網羅した `switch` は組めなくなる。ライブラリの外では `@unknown default` が要る形のまま） | 破壊的（3.3 の S-P7 の行。残りは C6） |
| 足す口 | - | `responses`、`settingsRequests`、`launchResponse()`、`NotificationEventHub`、`NotificationEventRegistration`、`NotificationResponseEvent`、`NotificationSettingsRequest`、`NotificationUserInfoValue` | 追加（3.3） |
| ログ | - | hub の行（受け手の数、保った数、捨てた数。イベントは識別子・返信の長さ・鍵の数だけ）、`NotificationResponseEvent`・`NotificationSettingsRequest` の init、印の付け外しと予約したキーの行（鍵の数と有無だけ） | 動作（S-P21） |

ブリッジ（`ios/UnityIosPlugin`。ソースは変えていない）: `UnityIosNotificationManager` は `setup()`・`onActionReceived`・`onTextInputActionReceived` を使うので、ブリッジを組むと deprecated の警告が出る（ワークスペースの外で、C1 から組んでいない）。動作は、受け手が main で呼ばれ userInfo から印が外れることのほか、**`openSettingsFor` で設定の App を開かなくなる**（ブリッジは `settingsRequests` を受けない）。ブリッジは段階 3 で消す（D-22）ので直さない。

### 13.15 設計書からの偏りと理由（後半）

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | 付録 A の `addListener(_:) throws(NotificationError) -> NotificationEventRegistration` | `@discardableResult` を付けた | C ABI の受け口（5.12.7）とサンプルの設定の要求の受け手のように、足したら外さない使い方では登録を使わない。付けなければ `_ =` が要る。戻り値の形は同じで、付けても互換は壊れない |
| 2 | S-P7（`NotificationError` の作り直し）は T-17（C6）、T-15 は印とイベントの口 | C5 では T-15 に要る `reservedUserInfoKey`・`delegateNotInstalled` だけを足した | 型つきの throws（`throws(NotificationError)`）と予約したキーの失敗に case が要る。ほかの case と `LocalizedError` は C6 の T-17 がまとめて作り直す（`errorMessage` の固定の文言も C6）。UI テスト N38 も C6 |
| 3 | 8.4.2「`isDelegateInstalled` が偽なら…」 | hub と `launchResponse()` は「入れたか」を読む closure（`NotificationDelegateStatus`）を通して読む。ライブラリの値は `isDelegateInstalled` と同じ installer の `isInstalled`（C5 のレビューの後は `IosNotificationManager.delegateInstaller`） | 13.10 の申し送り: `NotificationDelegateRealCenterTests` がプロセスの印を立てるので、テストはプロセスの印に頼れない |
| 4 | UT-17「Mock の repository と router」 | 本物の `NotificationRepositoryImpl` に、要求の追加・削除・一覧の偽物（internal の `NotificationRequestCenter`）を渡して確かめた | 印を付ける・外す・予約したキーの検査は repository の中にあるので、Mock の repository では確かめられない。テストのホストのアプリには通知の権限が無く、本物の center は要求を残さなかった（最初の版で `pendingNotificationRequests()` が空だった）。push の扱いは前半の router のテストのまま |
| 5 | 13.2 の N34「結果の行に `installDelegate: installed`」 | `testN34b_launchReportsTheInstalledDelegate` で、Swift API の節の `notification.launchStatus` を見る | 番号 N34 は UI テストの設計書のアイコンのバッジ（`testN34_homeIconBadge`）が使っている。結果の行の初めの値は M2 などの今の期待値（`Result will be displayed here`）で、13.3 は変えると書いていない |
| 6 | SA-06「受け手ごとの受けた回数」、SA-12「ホストの印の通知を受けたら結果の行に出す」、SA-11「`settingsRequests` の最後のイベントの表示」 | 結果の行でなく、Swift API の節の状態の行（`listenerCounts`、`hostEvent`、`lastSettingsRequest`）に出す | 結果の行はボタンの結果で、`updates=<n>` を数える（U-3）。ホストの delegate と hub の受け手はボタンと関わりなく呼ばれるので、別の行にした。識別子は 5.1 の一覧に足した |
| 7 | 12 章 SA-06「起動の処理を…`installDelegate()` → `responses.addListener` に替える」（場所は書いていない。今の処理は `App.init`） | 起動の処理を `UIApplicationDelegateAdaptor` の `application(_:didFinishLaunchingWithOptions:)` に移した。`installDelegate()` の DocC と型の Overview に「SwiftUI では `App.init` でなくここで呼ぶ」と書いた | SwiftUI の `App.init` の時点では `UIApplication.shared` がまだ無く（`nil`）、`applicationState` が `0`（`.active`）と読める。そのため初めて入れたときに active とみなされ、起動のきっかけが決まらず、誤った「起動の後かもしれない」のログが出た（13.17 の 3。MS-12 と同じ状況）。14 章の 3 の推奨（コードは変えない）に従ってライブラリは変えず、サンプルを直した。直すかは 15 章の 1。**15 章の 1 の決定で、`installDelegate()` が `sharedApplication` の `nil` を「まだ active でない」とみなす確かめを足し、DocC を「`App.init` でもよい」に戻した（16 章）。サンプルは `UIApplicationDelegateAdaptor` のまま（UIKit のアプリと同じ所）** |
| 8 | 12 章 SA-18「通知のテストは後片付け（`tearDown`）で `none` の形で 1 回起動し直してファイルを戻す」（SR3-5） | 基底の `tearDownWithError` が、そのテストが標準でない形で起動したときだけ、標準の形で起動し直す | 基底を通る起動は毎回形を引数で渡してファイルを書き直すので、標準の形だけで起動したテストの後はファイルがもう `none` になっている |
| 9 | 13.2 の N40・MS-07 は T-16 | MS-07 は使い捨ての写しで測った（13.17 の 1）。N40 は足していない | 呼ばせるには、アプリが `.providesAppNotificationSettings` を付けて権限を求めている必要がある（13.17 の 1）。そのボタンは SA-13 で C6（T-19）にある（SR-11 は「新しく入れたアプリで SA-13 のボタンから先に求める」）。C5 にだけ別のボタンを足すと C6 で入れ替わる。N40 は C6 で SA-13 と一緒に足す（13.21。15 章の 2） |
| 10 | 8.4.2「捨てたログはプロセスで最初の 1 回だけ `.info`」 | hub ごとに最初の 1 回 | hub はプロセスで 2 つ（`responses`・`settingsRequests`）だけで、どちらも解放しない。種類ごとに 1 回出すほうが、どちらが溢れたか分かる |
| 11 | 13.3「N25〜N33 は期待値を変えない」 | 期待値（最後のイベントの 5 行）は変えず、経路が `path=hub`・`mode=none` であることの確かめを足した | SA-18 の「どの経路でイベントを受けたかを結果に出し、テストで確かめる」。足しただけで、今の期待値の比べ方は同じ |
| 12 | S-P8「今の受け手は…呼ぶ」 | サンプルと単体テストは、deprecated の口を deprecated の印の付いた protocol の witness から呼ぶ（`LegacyNotificationEntries`、テストの `DeprecatedNotificationCalls`） | 今の受け手の経路（N43〜N45、UT-25）を流しながら、2 つの scheme を警告 0 で組むため。Swift には警告を抑える指示が無く、deprecated の文脈から呼べば警告が出ない |
| 13 | 13.2 の N31〜N33 は起動のきっかけの印を書いていない（C5 のレビューの UI B-1） | N31（Open）はどの OS でも `launch=true` を確かめる。N32・N33（Reply・Delete）は iOS 26 では `launch=false` を確かめ、iOS 18 では値を `XCTContext.runActivity` で残すだけにした（前例は `DialogUITests` の D7）。起動の後の応答（N25〜N29、N35、N41、N43、N44）は共通の確かめで `launch=false` を見る。UI テストの設計書の U-16 と 3.3 に書いた | H2-1 の「前面に出す応答だけ」を UI テストでも見る。背景のアクションは、18.3 では main に積んだブロックがテストが前に出した後に回り（MS-05。13.7）、`launch=true` になりうる。これは 14 章の 1 の決定で残す既知の窓なので、18.3 では落とさずに値を残す。U-16 は測りに基づく OS の分岐を許す |
| 14 | SA-08「受け手を足すのを 3 秒遅らせる」（N36） | `listenerDelay` を 5 秒にし、SA-08 を 5 秒に直した（C5 のレビューの UI C-1） | N36 はサンプルの決まった遅れと、システムが起動の中で呼ぶ `didReceive` の競争に頼る。`didReceive` は起動の最初の回、最初の `didBecomeActive` より前に来る（MS-05）ので 3 秒でも余裕はあるが、遅いマシンでの余裕を広げるほうが確かなので延ばした（U-14 の例外にする道もあったが、それは待ちの長さを変えないだけで競争は残る）。5 秒の後に届いても、UI テストのイベントの待ち（`waitForEventSequence` の 10 秒。前面に来てメニューから開いた後に始まる）に十分収まる |
| 15 | 13.2 の N37 は N36 と並べて書いている | N37 は N36 の後に続けて流す前提を持たない。普通の起動（標準の形）で `[launchResponse] nil` を読み、N30 と同じ標準の形の独立したコールドスタートで起動のきっかけを確かめる（C5 のレビューの UI C-7）。UI テストの設計書 3.3 の N37 の行に書いた | テストの順は決まらない（XCTest はクラスの中で名前の順に流すが、`--only-testing` で 1 件だけ流すこともある）。形は基底が起動のたびに明示し、標準でない形の後は後片付けで戻す（13.15 の 8） |

### 13.16 単体テストと壊して確かめたこと（後半）

| ID | ファイル（`IosLibraryTests/Notification/`） | 件数 | 中身 |
|---|---|---|---|
| UT-23 | `Presentation/Event/NotificationEventHubTests.swift`（新） | 14 | 受け手が 0 の間に保ち、1 人目に足す呼び出しの中で順に渡す、32 件を超えたら古いものから捨てる、重複も保つ、2 人目には保ちを渡さない、1 人目の中で足した受け手に保ちを 2 度渡さない（「足す前に保ちを外さない」）、渡す途中で自分を外すと残りは最も古い受け手（途中で足したもの）へ、受け手が残らなければ保ちの先頭へ戻す、途中で届いた新しいイベントは残りの後ろ（M88 の後に足した）、全員に 1 回ずつ配る、配る途中で外された受け手は呼ばない、配る途中で足した受け手は次から、`remove` 2 回、全員外すとまた保つ、入れていなければ `delegateNotInstalled` で何も足さず保ちも残す、「入れたか」は呼ぶたびに読む |
| UT-18（値の木） | `Domain/NotificationUserInfoValueTests.swift`（新、`NotificationUserInfoValueTests`） | 8 | どの種類も自分の case になる（`Int64.min`・`Int64.max`・`Int64.max + 1`・`UInt64.max`、整数の値の実数、真偽値、日時、バイト列、入れ子）、二進の property list を通しても同じ木（XML は日時が秒までなので比べない）、数の見分けの順（S-P11）、property list でない値と `String` でない鍵は捨てて数え（入れ子の中も）、落ちない、Foundation の型で今と同じに読める（`as? Int`・`Int64`・`Double`・`Bool`・`String`・`Date`・`Data`・`[Any]`・`[String: Any]`、`UInt64` は `NSNumber`）、真偽値は `CFBoolean`・ほかも Foundation の型、木 → Foundation → 木で同じ、8 タスク × 25 回の変換が同じ（TSan） |
| UT-17（印） | 同（`NotificationMarkerTests`） | 4 | キーは値に関わらず予約、付けると値 `1` で他を残す、外すと印だけ消える、`NSString` のキーでも見つかり外れる |
| UT-17（repository） | `Data/NotificationRepositoryMarkerTests.swift`（新） | 4 | 偽の center で: `schedule` は印を付けて足し `getScheduled` は外して返す、`show`・`update` も付ける（`update` は消してから足す）、`show`・`schedule` は予約したキーを断り center を呼ばない、`update` は予約したキーを今の予約を消す前に断る（center の呼び出しは前の `add` だけ） |
| UT-25 ほか | `Presentation/IosNotificationManagerEventTests.swift`（新） | 10 | 応答が印の無いイベントになる（起動のきっかけの印つき）、`description`・`String(describing:)`・`String(reflecting:)`・補間に返信と値が出ない、入れていなければ 2 つの hub と `launchResponse()` が `delegateNotInstalled`、**UT-25**: 今の受け手だけがいても hub は保ち、次の受け手が受ける（今の受け手は並びに入らない）、受け手 → 今の受け手の順で 1 回ずつ（テキスト入力も）、router から: 背景のキューの `didReceive` で、受け手が main でイベントを受けた後に system の completion、保った起動のきっかけは足したときに印つきで渡る、`launchResponse()` は router の応答を印つきのイベントにする・無ければ `nil`、`shared` は installer を読む |
| - | `Presentation/Delegate/NotificationDelegateProxyTests.swift`（`NotificationDelegateUserInfoTests` を値の木に書き直し、`IosNotificationManagerDelegateSinkTests` に 1 件） | 3 + 5 | 印を外して他を残す、空と印だけは空、property list でない値は捨てる。今の受け手は印の無い userInfo を受ける（足した 1 件）、設定の要求はイベントで、設定の画面を開かない（前半の「今のとおり開く」を P1-10 に替えた） |
| UT-15 | `Common/LibraryLogPrivacyTests.swift`（前半の 1 件を書き直し） | 1 | 番兵の返信と userInfo の値（入れ子と印も）で、受け手の無い hub に保つ → 受け手に渡す → 生で渡す → 転送する、`launchResponse()`、設定の要求、今の受け手を通し、ライブラリのログに番兵が無い（router・manager・hub の 2 行・イベントの init の行が読めることを `#require`） |

前半のテストの直し: `TestNotificationKind.response` の userInfo を値の木に（`DelegateTestSupport.swift`）、`offTheMainThreadNothingChanges` の `setup()` と `delegateSettingsCanBeChangedFromAnotherThread` の受け手を `DeprecatedNotificationCalls` から（13.15 の 12）。消した・名前を替えたテストは無い（前半の `NotificationDelegateUserInfoTests` の 3 件は名前を値の木に合わせて替えた。前半はコミットしていないので今の基準には無い）。

`IosLibraryTests` は 471 件（前半の 430 件 + 41）。

壊して確かめたこと（`mutate_c5b.py` で 1 つずつ当てて該当の suite を流し、落ちることを見てから戻した。差分とログは scratchpad。番号は前半の M84 に続ける）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M85 | UT-23（設計書 13.1「足す前に保ちを外さない」） | 保ちを外さずに渡す | `aListenerAddedInsideTheFirstDoesNotGetTheKeptEventsAgain` ほか 4 件 |
| M86 | UT-23 | 32 件を超えたら新しいほうを捨てる | `atMost32AreKeptAndTheOldestAreDropped` |
| M87 | UT-23 | 自分を外した後の残りを最も古い受け手に渡さない | `theRestGoToTheOldestRemainingListener` |
| M88 | UT-23 | 受け手が残らないとき、残りを保ちの後ろに足す | **最初は生き残った**（保ちは渡す前に空にするので、ふつうは前でも後ろでも同じ）。渡す途中で届いたイベントの後ろに回る形のテスト `anEventThatArrivesOnTheWayStaysBehindTheRest` を足して落ちることを確かめた |
| M89 | UT-23 | 配る前に受け手の closure の写しを取る（外された受け手も呼ぶ） | `aListenerRemovedDuringTheDeliveryIsNotCalled`。**最初の壊し方（`isRemoved` の確かめだけを外す）は生き残った**: 外すと closure の表からも消えるので、同じ守りが 2 つあり、1 つを外しても動作は変わらない（同じ意味の変異）。2 つとも外れる形に替えた |
| M90 | P1-6 | `addListener` で入れたかを見ない | `withoutTheDelegateAddingThrowsAndAddsNothing`、`theInstalledSourceIsReadOnEveryCall`、`withoutTheDelegateTheHubsAndTheLaunchResponseThrow` |
| M91 | UT-25（設計書 13.1「今の受け手を並びに入れる」） | 今の受け手がいれば hub に渡さない（今の受け手を受け手と数える） | `theDeprecatedReceiversAreNotListeners`、`theListenerComesBeforeTheDeprecatedReceiver` |
| M92 | 8.3.2 | 今の受け手を hub より先に呼ぶ | `theListenerComesBeforeTheDeprecatedReceiver` |
| M93 | UT-18（設計書 13.1「作り直しを Swift の `Int64`・`Bool` にする」） | 整数を Swift の `Int64` で作り直す | `theFoundationFormReadsAsBefore` |
| M94 | UT-18（S-P11） | 実数を整数と見分けない | `numbersAreToldApartInTheDesignedOrder` ほか 4 件 |
| M95 | UT-18（S-P11、RK-09） | 真偽値を数と見分けない | 同じ 5 件 |
| M96 | UT-18 | `Int64.max` を超える整数を `Int64` で読む | 同じ 5 件 |
| M97 | UT-17（設計書 13.1「消してから検査する」） | `update` が今の予約を消してから検査する | `updateWithTheReservedKeyLeavesThePendingRequest` |
| M98 | UT-17 | 印を付けない | `whatTheRepositoryAddsIsMarkedAndHandedBackWithoutTheMarker`、`showAndUpdateMarkWhatTheyAdd` |
| M99 | UT-17 | `getScheduled` が印を外さない | `whatTheRepositoryAddsIsMarkedAndHandedBackWithoutTheMarker` |
| M100 | 8.3.3 | 応答の userInfo から印を外さない | `theMarkerIsRemovedAndTheOtherValuesKept`、`aResponseBecomesAnEventWithoutTheMarker`、`theExistingReceiversGetTheUserInfoWithoutTheMarker` ほか 2 件 |
| M101 | P1-10 | 設定の要求で設定の App も開く | `aSettingsRequestIsAnEventAndOpensNothing` |
| M102 | P1-6 | `launchResponse()` で入れたかを見ない | `withoutTheDelegateTheHubsAndTheLaunchResponseThrow`、`theSharedManagerReadsTheLibraryInstaller` |
| M103 | S-P12 | `launchResponse()` のイベントに印を付けない | `theLaunchResponseIsTheRoutersResponseAsAnEvent` |
| M104 | UT-15 | イベントの `description` に返信を入れる | `theEventDescriptionHidesTheReplyAndTheValues`、`notificationResponsesThroughTheDelegateNeverReachTheLog` |
| M105 | 8.4.1 | イベントの userInfo を空にする | `aResponseBecomesAnEventWithoutTheMarker`、`theLaunchResponseIsTheRoutersResponseAsAnEvent` |
| M106 | UT-17 | `show` が予約したキーを断らない | `showAndScheduleRejectTheReservedKey` |

22 件とも落ち（M88 はテストを足した後、M89 は壊し方を替えた後）、戻した版で通ることを確かめた（13.18 の全件の実行）。

TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2）: hub、値の木と印、manager のイベント、repository の印、proxy、受け手の口、router の 3 つ、`CompletionOnce`、`IosNotificationManagerTests` の 13 suite・99 件が成功。TSan の報告は 0 件（値の木の変換の並行のテスト、背景のキューの `didReceive` から hub へ渡るテストを含む）。

### 13.17 シミュレーターで測ったこと（C5 後半に付いた MS-07・MS-14 と、SwiftUI の `App.init`）

1. **MS-07**（`openSettingsFor` をシステムから呼ばせられるか。iPhone 17 / 26.2、1 回）。使い捨ての写しのサンプルに `requestPermission(options: [.alert, .sound, .badge, .providesAppNotificationSettings])` を呼ぶ下調べのボタンと、設定の App を辿る下調べの UI テスト（`ProbeMS07UITests`）を足して測った（リポジトリには入れていない）。結果: 許可済みのアプリでもう一度求めるとダイアログは出ずに `granted=true` で戻り、設定の App の「Apps」→「IosLibraryExample」→「Notifications」の一番下に「IosLibraryExample Notification Settings」が出た。押すとサンプルが前に来て、`settingsRequests` にイベントが 1 つ届いた（`notificationId` は `nil`）。サンプルは通知の画面のまま。**呼ばせられる**ので HC10 は要らない。補足: 今のボタン OpenNotificationSettings（`UIApplication.openNotificationSettingsURLString`）では、この回は設定の App の一番上が開き、アプリの通知の画面へは辿らなかった（前から開いていた設定の App の状態による見込み。測っていない）。iOS 18.3 と、新しく入れたアプリで最初に求める形（SR-11）は測っていない
2. **MS-14**（バナーのタップで `terminate()` の後にシステムがサンプルを起こしたとき、`launchArguments` が渡るか。iPhone 17 / 26.2）。N45（`legacyReceivers`）と N36（`delayListener`）で、システムが起こしたプロセスは**引数を受けず、ファイルから形を読んだ**（`source=file`。N45 は結果の activity に、N36 は最後のイベントの経路に出る）。SA-18 のファイルで足りる
3. **SwiftUI の `App.init` での `installDelegate()`**（iPhone 17 / 26.2）。最初に `App.init` のまま流すと、N36・N37 の起動のきっかけが `launch=false` になった。統合ログを見ると、`App.init` の中の `installDelegate()` で `[install] the app is already active: this may be after launch …` が出ていた。下調べの版で Objective-C の経路（`UIApplication` の `sharedApplication`）を読むと、その時点で `UIApplication.shared` は `nil` だった。`nil` に送った `applicationState` は `0`（`.active`）と読めるので、初めて入れたときに active とみなし、起動のきっかけを「無し」と決める（MS-12 の `UIApplicationMain` の前と同じこと）。サンプルの起動の処理を `UIApplicationDelegateAdaptor` の `didFinishLaunching` に移すと `applicationIsActive: false` になり、N36・N37 が通った。ライブラリは 14 章の 3 の推奨のまま変えず、DocC に書いた（13.15 の 7、15 章の 1）。**15 章の 1 の決定で、`installDelegate()` は Objective-C の `sharedApplication` が `nil` なら active でないとみなすようにした（16 章）**

### 13.18 UI テストと基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1。`-parallel-testing-enabled NO`。18.3 の 2 つは 7.11 の注のとおり `arch=arm64`） | どれも 471/471（前半の 430 + 41）。skip 0。消した・名前を替えたテストは無い（13.16） |
| TSan | 13.16 の末尾 |
| 新しい UI テストの下調べ（リポジトリの作業ツリーを `xcodebuild test-without-building -only-testing` で直に。iPhone 17 / 26.2） | 1 回目: N34b・N35・N41・N43・N45 は通り、**N36・N37 が落ちた**（起動のきっかけが `launch=false`。13.17 の 3）。サンプルの起動の処理を `didFinishLaunching` に移した後、`NotificationColdStartUITests` の 7 件（N30〜N33・N36・N37・N45）が通った |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Notification`（ハッシュを固定した写し） | 50 件すべて成功（権限の NP2・NP1、Navigation 2、IdentifierInventory 4、Notification 24、NotificationEvent 11、NotificationColdStart 7）。閉じた形のソースの規則が通り、列挙の 120 件が宣言と一致した。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）との比べ合わせは `changed=0, added=8, removed=0`（足したのは N34b・N35・N36・N37・N41・N43・N44・N45）。N25〜N33 は期待値を変えずに `path=hub` で通った。I1b は Notification の 29 のボタンと節 8・状態の行 4 で一致した。信頼する部分の警告なし |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | 写し: 142/142。リポジトリ: 142 件のうち 5 件が落ちる（どれも `SampleApp.swift`・`SampleUITestCase.swift` のハッシュが固定と違うことによるもの: `SourceRules` の 2 件（`test_the_real_tree_passes`・`test_a_trusted_file_that_changes_is_reported`）、`Commands.test_preflight_refuses_the_device_when_the_trusted_part_changed`、`EndToEnd` の 2 件。信頼する部分が 2 ファイル変わった C2 と同じ）。`scripts/tests` の全体はリポジトリで 350 件のうち同じ 5 件だけが落ちる |
| 自己テストの fixture | 列挙（`enumeration.json`）は写しの `--feature Notification` の回の列挙（iPhone 17 / 26.2、Xcode 26.3、flat）をそのまま写した。前の fixture との差は足した 8 件の項目だけ（UI テストは 120 件）。実機のバイナリ（`otool-ov-device.txt`・`otool-l-device.txt`）は作業ツリーを `generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組んだ UI テストのバンドルから取った（端末は使っていない。テストのメソッドは 120）。どれにもローカルのパスは入っていない。数を照らす自己テストを 112 → 120、サンプルのボタンの数を 59 → 63 にした |
| ランナーの変異 | 流していない（ランナー `scripts/ios_ui_runner.py` は変えていない） |
| `scripts/test_ios.sh --dry-run --device-allow systemui`（写し。`--udid` はどの端末でもない値、`--enumerate-udid` は iPhone 17 / 26.2。`--baseline` なし。`--devicectl-id` なし） | 先に `test_ios.sh` を読み、`--dry-run` の `exit 0` より前に呼ぶのは `simctl list`、`xcodebuild -version`、列挙のシミュレーターへの `xcodebuild`、ランナー（`git` だけを呼ぶ）だけで、`devicectl` と実機の `xcodebuild` は 3 の後にしか無いことを確かめた。消費済みの台帳は変わっていない（更新日時が前のまま）。列挙の 120 件が宣言と一致し、60 件を選び 60 件を除いた。**足した 8 件はどれも選ばれた**（N34b は区分なし、ほかは `[systemui]`）。D17・D20〜D23・S18・S19 は今のまま `simulator only`。写しには未コミットの変更とランナーの差（固定したハッシュ）があるので、実機の回は断ると表示した |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1 は xcodebuild・`simctl`・`test_ios.sh` が起動し、終わった後に止めた。iPhone 17 / 26.2 には、写しの `--feature Notification` の回のサンプルが入っている。iPhone 16 / 18.3.1 の前半の MS-05 の写し（13.8）は入れ直していない（後半では iPhone 16 で UI テストを流していない）。最後にどれも起動していないことを確かめた |

### 13.19 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme（`IosLibrary`、`IosLibraryExample`）を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ）。deprecated の口を呼ぶサンプルとテストにも警告は出ない（13.15 の 12） |

`ios/UnityIosPlugin`（ワークスペースの外）は組んでいない（C1 と同じ。13.14 の末尾のとおり、組めば deprecated の警告が出る）。

### 13.20 信頼する部分の変更とハッシュ

`ios/IosLibraryExample/IosLibraryExampleUITests/Support/`。HEAD（`747897de`）からの差分。C2〜C4 と同じく作業ツリーに入れ、**ハッシュは固定していない**（別のモデルのレビューの後に固定する）。UI テストとランナーの自己テストは、ハッシュだけを直した使い捨ての写しで流した（13.18）。

| ファイル | 操作 |
|---|---|
| `SampleApp.swift` | (1) `NotificationButton` に `addSecondListener`・`removeSecondListener`・`readLaunchResponse`（印は要らない。サンプル自身の受け手の足し外しと状態の読み出しだけ）と `showHostNotification`（`systemui`。サンプル自身の通知を出す）を足した。(2) 状態の行の `NotificationStatusLine`（4 つの識別子）と、その label を読む `statusLine(_:)`・待つ `waitForStatusLine(_:_:timeout:)`（0.2 秒おきに読み直す。今の `waitForEventSequence` と同じ形）、最後のイベントの通し番号の行の `accessibilityValue` を読む `lastEventRoute()`。(3) 試験の形の `SampleLaunch`（`standard` / `legacyReceivers` / `delayListener` / `hostDelegate` と、その起動の引数）と、`launch(_:)` が `app.launchArguments` に形を入れてから起動する（既定は `standard`）。(4) I1b の一覧（`expectedNonButtons(.notification)`）に `notification.section.swiftAPI` と 4 つの状態の行。**読むのはサンプル自身の要素の label と value だけ**で、システムの UI の新しい操作・読み出しは無い |
| `SampleUITestCase.swift` | (1) `launchSample(_ launch: SampleLaunch = .standard)`: 形を渡して起動する。標準でない形で起動したら覚える。(2) `tearDownWithError`: 標準でない形で起動したテストなら、`tearDownAfterGate()` の後に標準の形で起動し直す（SR3-5）。実機で監視が答えないアラートで止めた後は、springboard の片付けと同じく行わない。そのときは形のファイルが標準でない形のまま残り、次に基底を通って起動するとき（どのテストも起動のたびに形を明示して書き直す）に直る。基底を通らない起動（人がホームから開くなど）はそれまで標準でない形を読む（C5 のレビューの UI C-4）。ゲートと印の発行は変えていない |
| ほかの 6 ファイル、凍結した `IosLibraryExampleUITests.swift` | 変えていない（バナーの操作は今の `Springboard` の口だけ。ホストの通知のバナーもサンプル自身の通知） |

識別子の文字列は信頼する部分の中だけにある（U-17。テストのクラスは `NotificationButton`・`NotificationStatusLine`・`SampleLaunch` の case だけを使う）。

再レビューの後に固定するハッシュ（`python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests`。ほかの 6 ファイルと `FROZEN_CLIPBOARD_SHA256`（`4612943d…6cf3`）は変わらない）:

| ファイル | 今の固定 | 新しい値 |
|---|---|---|
| `Support/SampleApp.swift` | `9af74391…a12e` | `1ac8667f119d835d39b9b36bb0e05ff00243b679fc817e8e62bbc1ea5801421e` |
| `Support/SampleUITestCase.swift` | `f9ac9bc5…1499` | `49bd2c07958fadedbf235c9ab155f0aedbcec4dbebd2260b7034f2e55adfe874` |

### 13.21 C6・C7 への申し送り

| 項目 | 内容 |
|---|---|
| `NotificationError`（C6、T-17） | C5 は `reservedUserInfoKey`・`delegateNotInstalled` だけを足した。S-P7 の作り直しで、この 2 つの `errorDescription` も固定の英語の文言にする（今は callback 版の `errorMessage` が OS の言語の汎用の文）。`Equatable` にしたら、テストの `if case`（`isReservedKeyError` など）を `==` に直してよい |
| userInfo の検査（C6、T-17） | 予約したキーの検査は `NotificationRepositoryImpl` の `rejectReservedKey(in:method:)` にあり、`update` は今の予約を消す前に呼ぶ。S-P15 の property list の検査（`invalidUserInfo`）は同じ所に並べる。テストは `NotificationRepositoryMarkerTests` の偽の center（`NotificationRequestCenter`）が使える |
| 一覧の型（C6、T-17。S-P25） | `getScheduled`・`getDelivered` は今の `[AnyHashable: Any]` のまま印を外している。値の木は `NotificationUserInfoValue.tree(of:)`（捨てた数も返す）と `foundationDictionary(_:)` をそのまま使える。`init` の捨てた件数のログも `tree(of:)` が出す |
| N40（C6、T-19） | MS-07 のとおり呼ばせられる（13.17 の 1）。SA-13 のボタンで `.providesAppNotificationSettings` を付けて求め、設定の App の「Apps」→ アプリ →「Notifications」→「<アプリ名> Notification Settings」を押し、`notification.lastSettingsRequest` が `settingsRequests=1, notificationId=-` になるのを待つ。設定の App を操作するので、信頼する部分（`Springboard`）に `session.isDevice` で throw する口を足し、`SIMULATOR_ONLY_TESTS` に入れる。ラベルは en と ja を `SystemLabels` に持つ（18.3 の ja のラベルは測っていない） |
| サンプル（C6） | 起動の処理は `SampleAppDelegate.application(_:didFinishLaunchingWithOptions:)` → `NotificationEventRouting.start()`。新しいボタンは Swift API の節（`notification.section.swiftAPI`）に足し、識別子は `NotificationSampleIdentifiers.ButtonName` と信頼する部分の `NotificationButton` に足す。結果の行の `updates=<n>` は変えていない |
| 試験の形（C6・C7） | 標準でない形を使う UI テストは `launchSample(.legacyReceivers)` などで起動し直す。後片付けは基底が行う |
| ブリッジ（段階 3 まで） | `openSettingsFor` で設定の App を開かなくなった（13.14）。Unity の利用者で困る人がいれば、段階 3 の C# の包みで `settingsRequests` の受け口を使う |
| C7 | MS-07・MS-14 の結果と、SwiftUI の `App.init` の扱い（15 章の 1 の決定）を README・第 1 部・マニュアルの元に写す（T-20）。N34b の番号の付け方を UI テストの設計書と設計書 13.2 の注のとおりに残す |
| 先頭のログ | 足した関数・init・helper には先頭のログがある（値の木の変換は型の名前と case の名前だけ、印は鍵の数と有無だけ）。C5 のレビュー（C-3）の前は、`NotificationMarker.isPresent(in:)`、router の `State.noteResponse`、proxy の `typeName`、hub の `summary(of:)` にログが無く、`NotificationEventRegistration.init` のログが状態を変えた後にあった（16 章で直した）。例外として残るもの: ログの補間の中だけで使う値（`logSummary` などの計算プロパティ）と、テストの支え。`NotificationRepositoryImpl` の今の private の helper（`makeUNContent` など）には前からログが無い（C5 では足していない） |

## 14. 利用者に決めてもらうこと（C5 前半）

**決定（2026-11-01、利用者）: 1・2 は推奨のとおり、3 は 15 章の 1 の決定に置き換わった。** 1 は H2-1 の見分け方をこのまま残し、18.3 の約 0.2 秒の窓を `launchResponse()` の DocC とマニュアルに書く（DocC は C5 で書いた）。2 は `CompletionOnce` を `@unchecked` なしのまま残し、第 1 部 5.12.4 のコメントと P1-17 の一覧の (3) を C7 で直す。3 は 15 章の 1 で `sharedApplication` の `nil` の確かめを足すことにしたので、「コードは変えない」は取り消した（16 章）

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | H2-1 の「前面に出す応答」の見分け方（13.4 の 3、13.7 の MS-05）。本体のタップ・dismiss は識別子で、custom のアクションは main に積んだブロックの時点の `applicationState` で決めた。18.3 では背景のアクションの直後（約 0.2 秒以内）に利用者がアプリを開くと、それを前面の応答と取りうる。あわせて、背景のアクションは「最初」の席を使わない（その後の最初の前面の応答が起動のきっかけになりうる）とした | **この形のままにし、DocC（後半の `launchResponse()`）とマニュアルに「custom のアクションはアプリの状態で見分ける」と書く**。確実にするには、custom のアクションのときに `getNotificationCategories` で `.foreground` を引いてから配る形があるが、イベントと completion を非同期の問い合わせで遅らせ、順も崩しうる。人の操作でその間に開くことはまれ |
| 2 | `CompletionOnce` を `@unchecked` なしにした（13.4 の 1）。P1-17 (3) と第 1 部 5.12.4 は `@unchecked Sendable` と書いている | **このままにし、C7（T-20）で第 1 部 5.12.4 のコメントと P1-17 の一覧の (3) を「使わずに済んだ（SDK が `@Sendable` で取り込む）」に直す**。一覧の (3) は消さずに「1b では使っていない」と残す（capi が同じ包みを要るかは 2b で見る） |
| 3 | MS-12: `UIApplicationMain` の前に入れると入るが、起動のきっかけが決まらず、誤った「起動の後かもしれない」のログが出る（13.7） | **コードは変えず、「`UIApplicationMain` の前は対応しない」のまま、マニュアル（段階 4）と C のヘッダー（2a）に「起動のきっかけが取れない」と書く**。直すなら `UIApplication.shared` がまだ無いかを Objective-C の経路で調べる形になり、契約の外のために手を足すことになる |

## 15. 利用者に決めてもらうこと（C5 後半）

**決定（2026-11-01、利用者）: 5 つとも推奨のとおり。** 1 は C5 のレビューの直しで `installDelegate()` に `sharedApplication` の `nil` の確かめを足した（16 章）。2 は N40 を C6（T-19）で SA-13 と一緒に足し、`session.isDevice` で止める口を付けて simulator only にする。3 は N34b のまま。4 は Codex のレビューの後にハッシュを固定した（16 章）。5 は `@discardableResult` を残し、C7 で付録 A に足す

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | SwiftUI の `App.init` で `installDelegate()` を呼ぶと、`UIApplication.shared` がまだ無いので active とみなされ、起動のきっかけが決まらず、誤った「起動の後かもしれない」のログが出る（13.17 の 3）。14 章の 3（MS-12）と同じ状況で、C5 はその推奨のとおりライブラリを変えず、DocC に書き、サンプルを `UIApplicationDelegateAdaptor` に移した。ただし `App.init` は SwiftUI のアプリでいちばん書かれやすい所で、イベント自体は届くので気づきにくい。逆の考え（14 章の 3）: この確かめは Objective-C の `nil` への送信（と `UIApplication.shared` が `nil` になる、契約の外の状態）に頼るもので、契約の外のために手を足すことになる | **14 章の 3 を決め直し、ライブラリに「`UIApplication` の `sharedApplication` が `nil` なら active でない（起動の途中）とみなす」確かめを足す**（`installDelegate()` の 1 か所、Objective-C の経路で読むだけ。下調べの版で `App.init` の時点が `nil` で、足すと `applicationIsActive: false` になることを確かめた）。足すなら C6 の最初か C5 のレビューの直しで入れ、DocC の「`App.init` では呼ばない」を「`App.init` でもよい」に戻し、UIKit の `main.swift` の場合（MS-12）も同じく直る。足さないなら今の DocC とサンプルのまま、マニュアル（段階 4）にも書く。逆の考えに対しては、読むのは optional の結果だけで（`nil` に送らない）、`App.init` は契約の外というより SwiftUI のふつうの書き方なので、1 か所の確かめで得るもののほうが大きい |
| 2 | N40（設定の App から `openSettingsFor`）を C5 に入れず、C6 で SA-13 と一緒に足す（13.15 の 9）。MS-07 で呼ばせられると分かった（13.17 の 1） | **C6（T-19）で足す**。設定の App を操作するので、信頼する部分に `session.isDevice` で止める口を足し、`SIMULATOR_ONLY_TESTS` に入れる。HC10 は足さない |
| 3 | 設計書 13.2 の N34 の番号が、UI テストの設計書の N34（アイコンのバッジ）と重なった。`testN34b_launchReportsTheInstalledDelegate` にし、結果の行でなく状態の行に出した（13.15 の 5） | **このままにする**（UI テストの設計書 3.3 と設計書 13.2 に注を書いた）。番号を空いている N46 に替えると、設計書の N34〜N45 の並びと合わなくなる |
| 4 | 信頼する部分（`SampleApp.swift`・`SampleUITestCase.swift`）の変更（13.20）と、足した 8 件の区分（N34b は無し、ほかは `systemui`）と、どれも simulator only にしない判断を、別のモデルのレビューに出してからハッシュを固定する | **C2〜C4 と同じく Codex に差分と 8 件の本体と `DeviceRequirements.json` の 8 行を見せ、通ったら 13.20 の値を固定して C5 のコミットに入れる**。観点は (a) 基底の後片付けの起動し直しがサンプルを起動するだけで、実機で監視が止めた後は行わないこと、(b) 新しい読み出しがサンプル自身の要素だけであること、(c) N41 のホストの通知もサンプル自身の通知で、N36・N37・N45 のコールドスタートは N30〜N33 と同じ操作であること（実機でも私物に触れない） |
| 5 | 付録 A に無い `@discardableResult` を `addListener` に付けた（13.15 の 1） | **このままにし、C7（T-20）で付録 A に足す** |
| 5 | `addListener(_:)` に付録 A に無い `@discardableResult` を付けた（13.15 の 1。決定のときに足した行） | **このまま残し、C7 で付録 A に足す**。戻り値の形は同じで、付けても互換は壊れない |

## 16. C5 のレビューと直したこと

コードのレビューを 3 者で並行に行った。Claude のサブエージェント（ライブラリ。設計との一致と正しさ）は A 0・B 4・C 10。Claude のサブエージェント（サンプル・UI テスト・文書）は A 0・B 1・C 7。Codex（設定のモデル。並行・寿命と実機の安全。読むだけ）は P2 が 1 つ（入れる順。下の表の C-7）で、信頼する部分（`Support/SampleApp.swift`・`Support/SampleUITestCase.swift`）の変更は固定してよいとした。その後 `TRUSTED_FILES` を 13.20 の値（`SampleApp.swift` は `1ac8667f…421e`、`SampleUITestCase.swift` は `49bd2c07…e874`）に固定した。15 章の決定（2026-11-01）を受けて、B-4 もこの直しで入れた。

| 指摘 | 直したこと |
|---|---|
| C-7（Codex の P2 と同じ）: `install` が `center.delegate = proxy` の後に `noteFirstInstall` と `setPreviousDelegate(current)` を呼ぶ。その間に別のスレッドで delegate のメソッドが呼ばれると、前の delegate が無い・古いまま、起動のきっかけの判定も違う | 順を「前の delegate を proxy に移す → 初めてなら `noteFirstInstall`・`didBecomeActive` の受け手・center の KVO → `center.delegate = proxy` → 印」にした。KVO は代入の前に付け、自分の代入は差し替えに数えない（`observeValue` の `newObject !== self` の確かめに `.debug` の行を足した）。領域の制約（前の delegate を `sending` で渡すと center も使えなくなる）は、`install(on:)` を center そのものでなく `@Sendable () -> any NotificationDelegateCenter` を受ける形にし、1 回目の値から前の delegate を読み、2 回目の値に代入・観察して解いた（呼ぶたびに別の領域の値になる。`@unchecked`・`nonisolated(unsafe)` は使っていない）。テストの偽の center に「delegate の setter の中で呼ばれる closure」を足し、`aCallDuringTheAssignmentSeesThePreparedState`（初めて入れるとき。代入の中の呼び出しが前の delegate に転送でき、active だったことを見て、起動のきっかけにならず、印はまだ立っていない）と `aCallDuringAReinstallSeesTheNewPreviousDelegate`（差し替えの後に入れ直すとき。代入の中で前の delegate はもう差し替えた側）を足した。`theFirstInstallSetsTheProxyAndTheFlag` に `replacementCount == 0` を足した |
| B-1: `settingsRequests` と `NotificationSettingsRequest` の DocC が「通知の無い要求はいつもライブラリ」と読める（コードは、ライブラリの通知の要求はいつも、通知の無い要求とほかの通知の要求は前の delegate が `openSettingsFor` を実装しないときだけ） | 2 つの DocC をコードのとおりに直した |
| B-2: 既定の `isApplicationInForeground` が名前もテストも無い closure | `NotificationDelegateProxy.bringsAppToForeground(_ state: UIApplication.State) -> Bool`（`.active`・`.inactive` は真、`.background` は偽）にし、installer の既定はこれを呼ぶ。`theForegroundOfAnActionFollowsH21` で `foreground(ofAction:)` と一緒に確かめる |
| B-3: Presentation の installer の `shared` が Manager の `IosNotificationManager.shared` を参照する（下の層から上の層） | 組み立て（`static let delegateInstaller`）と `NotificationDelegateStatus.library` を `IosNotificationManager.swift` に移した。installer・router・proxy は受け手の口だけを知る。13.2・13.4 の 6・13.12 の例外の行と理由を直した |
| B-4（15 章の 1。決定のとおり入れた） | `installDelegate()` は Objective-C のクラスメソッド `sharedApplication` を optional の結果として読み（`NotificationDelegateInstaller.sharedApplication()`。`UIApplication.shared` の非 optional の参照を `nil` のときに読まない）、`nil` なら active でないとみなす（`isActive(_:)`）。`App.init` と UIKit の `main.swift` の `UIApplicationMain` の前（MS-12）で、起動のきっかけが取れ、誤った「起動の後かもしれない」のログが出ない。`installDelegate()` の `- Important:`・`- Note:` と型の Overview を「起動の処理で呼ぶ。`App.init` でもよい（そのときは active でないとみなす）」に直した。サンプルは `UIApplicationDelegateAdaptor` のまま（UIKit のアプリと同じ所。コメントだけ直した）。テスト `withoutTheApplicationObjectTheAppIsNotActiveYet`（`nil` は active でない、テストのホストでは `UIApplication.shared` と同じものが読める、`nil` で入れると起動のきっかけが残る）。使い捨ての写しで `App.init` から呼ぶ形を測った（下の実行の表） |
| C-1: `LibraryLogPrivacyTests` の転送の呼び出しが印のある応答で、転送されていなかった | 印の無いホストの応答（番兵の返信と値つき）にし、「forwarded to the previous delegate」の行を `#require` した |
| C-2: `getDelivered` の印の外しにテストが無い。`removeAllPendingRequests` が `NotificationRequestCenter` を通らない | 内容 → 一覧の値の変換を internal の `NotificationRepositoryImpl.activeNotification(identifier:date:content:)` に出し、`UNMutableNotificationContent` で確かめた（`aDeliveredNotificationIsHandedBackWithoutTheMarker`）。`removeAllPendingNotificationRequests()` を seam に足し、`cancelAll`・`cancelAllScheduled` を通した（`cancelAllAndCancelAllScheduledRemoveThroughTheCenter`） |
| C-3: 先頭のログが無い（`NotificationMarker.isPresent(in:)`、`State.noteResponse`、`typeName`、`summary(of:)`）、`NotificationEventRegistration.init` のログが状態を変えた後。13.21 が「すべてある」と書く | 4 つに先頭のログを足し（`isPresent`・`typeName`・`summary` はほかのログの補間の中からも呼ばれるが、自分のログの中では自分を呼ばないので循環しない。`noteResponse` のログは鍵の中だが、ログはほかのコードを呼ばない）、`init` のログを番号を変える前に移した。13.21 を直した |
| C-4: router が class で、転送・main への積み込み・受け手の呼び出しまで行う（設計書 8.3.2 は 2 つの結果を返す純粋な値の型） | 13.4 に 11 の行を足した（呼び出しをまたぐ状態があり、転送と completion の順を UserNotifications 無しの単体テストで確かめるため） |
| C-5: `isDelegateInstalled`・`launchResponse()` が `ios.md` の「UseCase を置かない口」の一覧に無い | `ios.md` の一覧に「通知の delegate の状態の読み出し（`isDelegateInstalled`、`launchResponse()`。2026-11-01）」を足し、13.2・13.12 に書いた |
| C-6: DocC が、入れ直すと前の delegate が 1 つだけになることを書かない。`isDelegateInstalled` がまだ無い C の入口に触れる | `installDelegate()` の DocC と表に「前の delegate は 1 つだけ。入れ直すと差し替えた側が前の delegate になり、それより前のものはその側が転送するときだけ届く」を足した。`isDelegateInstalled` は「`installDelegate()`（と、それを呼ぶ deprecated の `setup()`）」にした。installer の型の DocC からも C の入口の言及を外した |
| C-8: proxy の型の DocC の「持つもの」に `presentationOptions` の closure が無い | `@Sendable` の closure を足した |
| C-9: hub の「最初の捨てだけ `.info`、後は `.debug`」（SR-23）と、install の「already active」の `.info` にテストが無い | `onlyTheFirstDropIsLoggedAtTheInfoLevel`（hub ごとに一意の名前で 3 回捨て、`OSLogStore` に `.info` の 1 行だけ）と `installingWhileActiveLogsThatItMayBeAfterLaunch`（main actor の上で途中に suspend しない 3 つの canary の行の間で、active でない install には行が無く、active の install には `.info` の 1 行）を足した |
| C-10: `theSharedManagerReadsTheLibraryInstaller` がテストの順で 2 つの枝のどちらかを確かめる。`withoutTheDelegateTheHubsAndTheLaunchResponseThrow` が型だけを見る | 前者は `.serialized` の `NotificationDelegateRealCenterTests` に移し、先に `installDelegate()` を呼んで 1 つの枝（投げない、`launchResponse()` は router の値で `nil`、2 つの hub に足せる）を確かめる形にした。後者は 3 つとも `.delegateNotInstalled` を確かめる |
| UI B-1: N31〜N33 が起動のきっかけの印を見ない | N31 はどの OS でも `launch=true`、N32・N33 は iOS 26 で `launch=false`、iOS 18 は値を `XCTContext.runActivity` に残す（前例 D7。U-16）。起動の後の応答（N25〜N29、N35、N41、N43、N44）は共通の確かめで `launch=false`。UI テストの設計書の U-16・3.3 と 13.15 の 13 に書いた |
| UI C-1: N36 はサンプルの 3 秒の `listenerDelay` とシステムの `didReceive` の競争に頼る | 遅れを 5 秒にした（U-14 の例外にしても競争は残るので、余裕を広げるほうを選んだ）。SA-08 と 13.15 の 14 に書いた |
| UI C-2: アイコンのバッジの注が N34b の上にずれた。冒頭の 5 行目が 150 文字 | 注を `testN34_homeIconBadge` の上に戻し、冒頭を折り返した |
| UI C-3: サンプルの新しい関数の先頭のログ | `DeprecatedNotificationEntries.setReceivers(action:textInput:)`・`setup()`、`SampleLaunchConfiguration.read(_:)`（`file` の名前）、`SampleHostNotificationDelegate.post(completion:)`（`completion: provided`）、`NotificationEventLog.status()`・`signal()` に足した |
| UI C-4: 実機で監視が止めた後は後片付けの起動し直しをしないので、形のファイルが次の基底の起動まで標準でない形のまま | 13.20 と SA-18 に 1 行足した |
| UI C-5: 設計書 13.2 の N40 の「MS-07 で呼ばせられると分かった」が言い過ぎ | 「26.2 の許可済みのアプリで求め直した形で呼ばせられた。新しく入れたアプリで先に求める形（SR-11）と 18.3 は測っていない」にした |
| UI C-6: 15 章の 1 に 14 章の 3 の反対の理由が無い | 「Objective-C の `nil` への送信と契約の外の状態に頼る、契約の外のために手を足す」を利点の横に置き、それへの答えも書いた |
| UI C-7: N37 は N36 の後ではなく、標準の形の独立したコールドスタート | 13.15 の 15 と UI テストの設計書 3.3 の N37 の行に書いた |

単体テストは 7 件増えた（`NotificationDelegateInstallerTests` に 4: 代入の中の呼び出し 2、`.info` のログ 1、`sharedApplication` 1。`NotificationEventHubTests` に 1。`NotificationRepositoryMarkerTests` に 2）。`theSharedManagerReadsTheLibraryInstaller` は `IosNotificationManagerEventTests` から `NotificationDelegateRealCenterTests` に移した（C5 はコミットしていないので基準には無い）。`IosLibraryTests` は 478 件。

壊して確かめたこと（`mutate_c5fix.py` で 1 つずつ使い捨ての写しに当てて該当の suite を流し、落ちることを見てから戻した。差分とログは scratchpad。番号は M106 に続ける）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M107 | C-7（Codex P2） | 前の delegate を代入の後に移す（直す前の順） | `aCallDuringTheAssignmentSeesThePreparedState`、`aCallDuringAReinstallSeesTheNewPreviousDelegate`（最初の版は代入の後に center から読み直す形で、ほかの 5 件も落ちた。直す前の順そのものに替えて流し直した） |
| M108 | C-7 | `noteFirstInstall` を代入の後にする | `aCallDuringTheAssignmentSeesThePreparedState` |
| M109 | C-7 | 印を準備の前に立てる | `aCallDuringTheAssignmentSeesThePreparedState` |
| M110 | C-7 | proxy 自身の代入も差し替えに数える | `theFirstInstallSetsTheProxyAndTheFlag`、代入の中の 2 件、`aReplacementIsWatchedAndInstallingAgainRestoresTheProxy` ほか |
| M111 | B-2 | `bringsAppToForeground` が `.active` だけを真にする | `theForegroundOfAnActionFollowsH21` |
| M112 | B-4 | application object が無いときを active とみなす | `withoutTheApplicationObjectTheAppIsNotActiveYet` |
| M113 | B-4 | `sharedApplication()` がいつも `nil` | `withoutTheApplicationObjectTheAppIsNotActiveYet` |
| M114 | C-1 | 転送の行に返信を生で入れる | `notificationResponsesThroughTheDelegateNeverReachTheLog` |
| M115 | C-2 | `getDelivered` の値が印を外さない | `aDeliveredNotificationIsHandedBackWithoutTheMarker` |
| M116 | C-2 | 全部消すのを `UNUserNotificationCenter` に直に送る | `cancelAllAndCancelAllScheduledRemoveThroughTheCenter` |
| M117 | C-9 | hub の捨てをいつも `.info` で出す | `onlyTheFirstDropIsLoggedAtTheInfoLevel` |
| M118 | C-9 | 最初の捨てを `.debug` で出す | `onlyTheFirstDropIsLoggedAtTheInfoLevel` |
| M119 | C-9 | 「already active」を `.debug` で出す | `installingWhileActiveLogsThatItMayBeAfterLaunch` |
| M120 | C-10 | `NotificationDelegateStatus.library` がライブラリの installer を読まない | `theSharedManagerReadsTheLibraryInstaller` |
| M121 | C-10 | 入れていない hub が別の case を投げる | `withoutTheDelegateTheHubsAndTheLaunchResponseThrow` |
| M122 | C-10 | 入れていない `launchResponse()` が別の case を投げる | `withoutTheDelegateTheHubsAndTheLaunchResponseThrow` |

16 件とも落ち、戻した版で通ることを確かめた（下の全件の実行）。UI テストの直し（UI B-1 の `launch` の確かめ）は壊して流していない（UI テストの変異はここまでも流していない。下の `--feature Notification` で通ったことだけを確かめた）。

| 実行 | 結果 |
|---|---|
| 直しの途中の Notification の suite と `LibraryLogPrivacyTests`（iPhone 17 / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`） | 16 suite・126 件が成功（B-4 の前）。B-4 の後に installer の 2 つの suite 18 件が成功 |
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3。`-parallel-testing-enabled NO`。18.3 の 2 つは `arch=arm64`。Xcode 26.6） | どれも 478/478（471 + 7）。消したテストは無い |
| TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2） | delegate の 9 suite（installer 2、proxy、userInfo、受け手の口、router 3、`CompletionOnce`）、hub、manager のイベント、repository の印、値の木と印、`IosNotificationManagerTests` の 15 suite・119 件が成功。報告 0 件 |
| B-4 の下調べ（使い捨ての写しのサンプルで、`NotificationEventRouting.start()` を `App.init` に移し `didFinishLaunching` から外した。`xcodebuild test-without-building -only-testing`。iPhone 17 / 26.2） | N31・N36・N37 が通った（`launch=true`、`[launchResponse] notificationId=sample-notification, …, isLaunchResponse=true`）。13.17 の 3 で `App.init` のまま落ちた N36・N37 が、`sharedApplication` の確かめで通るようになった。リポジトリのサンプルは `UIApplicationDelegateAdaptor` のまま |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Notification`（リポジトリのまま。信頼する部分は固定のハッシュのとおり） | 50 件すべて成功（NP2・NP1、Navigation 2、IdentifierInventory 4、Notification 24、NotificationEvent 11、NotificationColdStart 7）。基準との比べ合わせは `changed=0, added=8, removed=0`（13.18 と同じ 8 件）。N31 の `launch=true`、N32・N33 の `launch=false`（26.2）、N25〜N29 などの `launch=false`、5 秒の N36 が通った |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`。リポジトリ） | 142/142（固定の後なので、13.18 の 5 件の失敗は無くなった） |
| 2 つの scheme の `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`。Xcode 26.3 と 26.6） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| swiftinterface（13.13 と同じ組み方。Xcode 26.3） | `IosLibrary-after-1b-c5.swiftinterface` と同じ（差 0）。公開面は変わらないので取り直していない |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3 は xcodebuild と `test_ios.sh` が起動し、最後に `simctl shutdown all` で止め、どれも起動していないことを確かめた。iPhone 17 / 26.2 には `test_ios.sh` の回のサンプル（リポジトリの版）が入っている（下調べの写しは `test_ios.sh` の NP2 が消して入れ直した）。実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない） |

信頼する部分（`scripts/ios_ui_runner.py` の `TRUSTED_FILES`）は変えていない。直しのどれも信頼する部分の変更を要しなかった。
## 17. C6 通知の操作（T-17〜T-19、T-23）

- 状態: ライブラリ（T-17 のエラー・`async` 版・一覧の型・userInfo の検査、T-18 の権限の要求と設定の画面の gate と 2 つの UseCase、T-23 の category の列）、単体テスト（UT-16 の通知の分、UT-18 の検査と一覧の分、UT-26〜UT-29、UT-32）、壊して確かめる、サンプル（SA-09、SA-10、SA-13、SA-05 の権限の分）、UI テスト（N38、N39、N40、N42）、MS-04・MS-09 は済んだ。**コミットはしていない**
- 13.10 の「C6 に残す今の不備」の 3 つを直した: (1) Manager は `repository` を持たなくなり、`openNotificationSettings()` は `OpenNotificationSettingsUseCase`、`setBadgeCount` は新しい `SetBadgeCountUseCase` を通る。(2) port の `UNAuthorizationOptions` に理由の注を付けた（型の DocC の `- Note:` と import の行の注）。(3) `NotificationDispatchUseCases.swift` の `import UserNotifications` を外した
- C5 で足した 2 つの case（`reservedUserInfoKey`・`delegateNotInstalled`）は S-P7 の作り直しに入れ、英語の固定の `errorDescription` を持つ（13.21 の 1 行目）
- 信頼する部分（`Support/SampleApp.swift`・`Support/Springboard.swift`・`Support/SystemLabels.swift`）の変更はリポジトリの作業ツリーに入れ、**ハッシュは固定していない**。UI テストとランナーの自己テストは、ハッシュだけを直した使い捨ての写し（scratchpad）で流した（17.10）
- 測ったログ・下調べ（MS-04・MS-09）・変異の差分は scratchpad に置き、リポジトリには入れていない。シミュレーターだけで、実機には触れていない
- 13.21 の申し送りの 9 行（`NotificationError`、userInfo の検査、一覧の型、N40、サンプル、試験の形、ブリッジ、C7、先頭のログ）のうち C6 の行はすべて当てた。C7 の行と、ブリッジの行（段階 3 まで直さない）は 17.11 に引き継いだ

### 17.1 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| Domain（T-17） | `Notification/Domain/Model/NotificationError.swift` | S-P7 の作り直し: `Error, Sendable, Equatable, LocalizedError`。任意の `Error` を持つ case を `FailureDetail` を持つ case に直した（`attachmentLoadFailed(identifier:detail:)`、`addRequestFailed`、`setBadgeCountFailed`、`authorizationFailed`。前の `unknown(Error)` は `authorizationFailed`）。`permissionNotDetermined`・`attachmentInvalidURL`・`unknown` を消し、`invalidUserInfo`・`notForeground`・`openSettingsFailed` を足した。C5 の `reservedUserInfoKey`・`delegateNotInstalled` を含む 10 の case に英語の固定の `errorDescription`（入力の値・識別子・domain を含めない）。型の DocC に case と場面の表 |
| Domain（T-17） | `Notification/Domain/Model/ScheduledNotification.swift`、`ActiveNotification.swift` | S-P25: `Sendable`。userInfo を値の木 `userInfoValues` で持ち、`userInfo` は値の木から Foundation の型で作り直す計算プロパティ。public の `init` は今の引数のまま、中で `NotificationUserInfoValue.tree(of:)`（property list でない値と `String` でない鍵は捨て、件数だけをログ）。先頭のログ（題・副題・本文は長さだけ） |
| Domain（T-23） | `Notification/Domain/Model/NotificationCategoryChange.swift`（新、public） | `register(NotificationCategory)` / `remove(identifier:)`（付録 A）と、ログの形 `logSummary`（識別子だけ） |
| Application（T-17・T-18・T-23） | `Notification/Application/Port/NotificationRepository.swift` | `UNAuthorizationOptions` の理由の注（13.10 の 2）。`openNotificationSettings() async -> Bool`（8.5.5）。`enqueueCategoryChange(_:completion:)` と protocol extension の既定の実装（`Task` で今の `async` の口を呼んで `completion`。順は保たないと DocC に書いた。S-P28）。`registerCategory`・`removeCategory` の DocC に列のこと。印の DocC に `invalidUserInfo` |
| Application（T-18） | `Notification/Application/UseCase/NotificationPermissionUseCases.swift`（新） | `RequestNotificationPermissionUseCase`（`execute(options:) async throws(NotificationError) -> Bool`。拒否は `false`。port が `NotificationError` でないものを投げたら `authorizationFailed` に写す）、`OpenNotificationSettingsUseCase`（`execute() async -> Bool`）。前面は知らない（SR-17） |
| Application（13.10 の 1） | `Notification/Application/UseCase/NotificationBadgeUseCases.swift`（新） | `SetBadgeCountUseCase`（設計書 6.1・9 章に無い。17.4 の 1） |
| Application（T-23） | `Notification/Application/UseCase/NotificationCategoryUseCases.swift` | `enqueue(_:completion:)`・`enqueue(identifier:completion:)`（同期に port へ積む。S-P28）と先頭のログ |
| Application（13.10 の 3） | `Notification/Application/UseCase/NotificationDispatchUseCases.swift` | 使わない `import UserNotifications` を外した |
| Application（19 章の L-C1） | `Notification/Application/UseCase/NotificationQueryUseCases.swift`、`NotificationScheduleUseCases.swift` と、上の Dispatch・Category・Badge・Permission の UseCase | どの UseCase も `init` と `execute` の先頭にログ（型ごとの logger。識別子と `content.id` は `.public`、trigger は `.private`） |
| Data（T-23） | `Notification/Data/Repository/NotificationCategoryQueue.swift`（新、internal） | プロセスで 1 つの FIFO（`static let shared`）。internal の `NotificationCategoryCenter`（`categories() async`・`setCategories(_:)`）と本番の `CurrentNotificationCategoryCenter`。積む: 1 つの `Mutex` の区間で足す・印を見る・起こす権利を取り、区間の外で権利を取ったときだけ 1 つの `Task`。取り出す: 1 つの区間で空なら印を下ろして終わり、空でなければ先頭を外す。1 件の処理は読む → 変える → 書き戻す → 読み直す（足すときは書いた category と識別子・アクションの識別子の並び・options が同じものがあるか、外すときは識別子が無いかを `isReadBack` で確かめる。読めなければ `.error` のログ。19 章の L-C4）→ `completion`。`makeUNCategory(from:)` を repository から移した。テストのための `init(center:drainHook:)` と `drainStartCount` |
| Data（T-17・T-18・T-23） | `Notification/Data/Repository/NotificationRepositoryImpl.swift` | 入口の最初の `checkUserInfo(of:method:)`（予約したキー → property list。`update` は今の予約を消す前。8.3.3、8.5.3、SR-9）と internal の `isPropertyList(_:)`（`PropertyListSerialization.propertyList(_:isValidFor: .binary)`）。system のエラーを `FailureDetail` に（`add`・バッジ・権限・添付。domain と code を `.error` のログに）。`openNotificationSettings() async -> Bool`（main actor の `UIApplication.open`）。`registerCategory`・`removeCategory` は列に積んで反映を待つ。`enqueueCategoryChange` は列に同期に積む。`categoryQueue`（public の `init()` は `.shared`、テストの `init(requestCenter:categoryQueue:)`）。`update` は検査 → 内容（添付）と trigger → 今の予約を消す → `add` の順（C6 の前は消してから内容を作っていた。19 章の L-B1） |
| Presentation（T-18） | `Notification/Presentation/Permission/NotificationPresentationGate.swift`（新、internal） | 8.5.4・8.5.5 の表を持つ gate（`Sendable` の struct、2 つの口は `@MainActor`）。`.firstActiveScene` はそのまま UseCase。`.foreground`・`.viewController` は、権限なら先に状態を読み（決まっていれば要求せずに `grants(_:)` で答える）、未決なら `PresentationProcedure.requireForeground` で前面を確かめる。設定の画面は前面を確かめてから開き、開けなければ `openSettingsFailed` |
| Presentation（T-18） | `Notification/Presentation/Permission/NotificationPermissionHelper.swift` | `@available(*, deprecated, message: "Use IosNotificationManager.requestPermission(options:presenter:)")`（S-P27）。`openNotificationSettings()` は `Task` で port の `async` の口を呼び結果を捨てる。DocC の `.unknown` を `authorizationFailed` に直し、移り先を `- Important:` に書いた |
| Manager（T-17・T-18・T-23） | `Notification/IosNotificationManager.swift` | `repository` と `permissionHelper` を持たなくなった（13.10 の 1、SR3-4）。テストの `init(repository:delegateStatus:presentationGate:)`。`async throws` 版（`show`・`update`・`schedule`・`setBadgeCount`）と投げない `async` 版（`getScheduled`・`getDelivered`・`hasPermission`・`authorizationStatus`）。callback 版の `errorMessage` は `errorMessage(of:)`（`NotificationError` の固定の文言）。今の `requestPermission(options:completion:)` は UseCase を呼び、拒否は `(false, <permissionDenied の文言>)`。新しい `requestPermission(options:presenter:completion:)`（`Result<Bool, NotificationError>`）と `async throws -> Bool`（`@discardableResult`）、`openNotificationSettings(presenter:completion:)`（`Result<Void, NotificationError>`）と `async throws`。今の `openNotificationSettings()` は UseCase で開いて結果を捨てる。`registerCategory(_:completion:)`・`removeCategory(identifier:completion:)`（`completion` は既定 `nil`。UseCase の同期の `enqueue` に積み、完了を `DispatchQueue.main.async` で 1 回）と `nonisolated(nonsending)` の `async` 版（`withCheckedContinuation` の本体で積む）。S-P16 の DocC（`cancel` と `cancelScheduled` が同じ、`schedule` は `identifier` を使う。違えばログ）、全件の消去がホストの通知も消すこと（3.4）。型の Overview の「Unity の相互運用のために `(isSuccess, errorMessage)`」を直した（設計書 18.1 の 11） |
| 共通 | `Common/LogRedaction.swift` | DocC の例を `NotificationError.addRequestFailed(FailureDetail)` に直しただけ |
| テスト | 17.5 | |
| サンプル（T-19） | `IosLibraryExample/NotificationSampleView.swift` | Swift API の節にボタン 6: `showReservedKey`・`showInvalidUserInfo`（SA-09。`async` 版の `show`）、`registerCategoryWithCompletion`（SA-10。完了で結果の行）、`requestPermissionWithAppSettings`（SA-13。`.providesAppNotificationSettings` を足して `.foreground`、`async` 版）、`openNotificationSettingsForeground`（SA-13。`.foreground`、C ABI が使う callback 版）、`requestPermissionAfter3Seconds`（SA-05。`#if DEBUG`、3 秒後に `.foreground` で求める。結果の行に要求の時点の scene の状態）。結果の行は `[<印>] success <値>` / `failure <case>`。category の組み立てを `makeCategory()` に、`makeContent` に userInfo の足しを出した（今のボタンの userInfo は変わらない）。今の 29 のボタンと結果の行は変えていない |
| UI テスト | `NotificationUITests.swift`（N38）、`NotificationEventUITests.swift`（N39）、`NotificationPermissionUITests.swift`（N42・N40）、`Support/DeviceRequirements.json`（4 件） | 17.8 |
| UI テスト（信頼する部分） | `Support/SampleApp.swift`、`Support/Springboard.swift`、`Support/SystemLabels.swift` | 17.10 |
| ランナー | `scripts/ios_ui_runner.py` | `PERMISSION_ORDER` を NP2 → N42 → N40 → NP1 に、`SIMULATOR_ONLY_TESTS` に N40・N42（17.4 の 8） |
| ランナーの自己テスト | `scripts/tests/test_ios_ui_runner.py`、`scripts/tests/fixtures/ios_ui_runner/enumeration.json`・`otool-ov-device.txt`・`otool-l-device.txt` | 数（120 → 124、サンプルのボタン 63 → 69）、権限の順の 2 件と N40・N42 の simulator only の 1 件、fixture の取り直し（17.8） |
| 文書 | `designs/2026-10-18-ios-c-abi-ui-test-design.md` | U-14 の例外（N38・N40・N42）、3.3 に C6 のテストの表と置き場所、「テストに入れないもの」の `openSettingsFor` と文言の行、5.1 の一覧（ボタン 6、数 47 → 53） |
| 文書 | `designs/2026-10-31-ios-c-abi-swift-api-design.md` | 偏りの注だけ（3.3 の S-P26 の行に `openNotificationSettings()`、6.1 に `NotificationBadgeUseCases.swift`、8.5.4 に gate の形と決まった状態での新しい選択肢、8.5.6 に同じ識別子の置き換えと読み直し、付録 A の後の注） |
| 公開 API | `results/swiftinterface/IosLibrary-after-1b-c6.swiftinterface`、`2026-10-31-stage1b-c6.diff` | 17.6 |

`ios/IosLibrary/IosLibrary.xcodeproj` と `ios/IosLibraryExample/IosLibraryExample.xcodeproj` は変えていない（フォルダーと同期するターゲット）。ブリッジ（`ios/UnityIosPlugin`）は変えていない（`NotificationError` の case も `NotificationPermissionHelper` も使っていない。`registerCategory(category)` は同期の文脈で今の口に決まる）。`ios.md` は変えていない（UseCase を置かない口を足していない。設定の画面とバッジは UseCase を通した）。

### 17.2 層と依存の向き

| ファイル | 層 | 依存するもの | 例外と理由 |
|---|---|---|---|
| `Domain/Model/NotificationError.swift` | Domain | Foundation、`FailureDetail` | - |
| `Domain/Model/ScheduledNotification.swift`・`ActiveNotification.swift` | Domain | Foundation、`os`、`NotificationUserInfoValue`、`LogRedaction` | - |
| `Domain/Model/NotificationCategoryChange.swift` | Domain | Foundation、`NotificationCategory` | - |
| `Application/Port/NotificationRepository.swift` | Application | Foundation、`os`、UserNotifications（`UNAuthorizationOptions` だけ） | `common.md` の許容の例外（薄いビットマスク）。注を付けた（13.10 の 2） |
| `Application/UseCase/NotificationPermissionUseCases.swift` | Application | 同上（`UNAuthorizationOptions` を port へ渡すだけ） | 同じ例外。import の行に注 |
| `Application/UseCase/NotificationBadgeUseCases.swift`・`NotificationCategoryUseCases.swift`・`NotificationDispatchUseCases.swift` | Application | Foundation、`os` | - |
| `Data/Repository/NotificationCategoryQueue.swift` | Data | Foundation、`os`、`Synchronization`、UserNotifications、Domain | `NotificationCategoryCenter` は Data の中の internal の抽象（`UNNotificationCategory` を持つので Domain・Application に置かない） |
| `Data/Repository/NotificationRepositoryImpl.swift` | Data | 今の依存 + `NotificationCategoryQueue` | - |
| `Presentation/Permission/NotificationPresentationGate.swift` | Presentation | `os`、UserNotifications（`UNAuthorizationOptions`）、`PresentationProcedure`（Common の Presentation）、Application の 3 つの UseCase | UseCase を呼ぶのは Manager から委ねられた判定のため（設計書 8.5.4 の「判定する所」。SR-17） |
| `Presentation/Permission/NotificationPermissionHelper.swift` | Presentation | 今のまま（port を直に呼ぶ） | deprecated の今の型で、動作を今のまま残す（S-P27）。新しいコードからは使わない |
| `IosNotificationManager.swift` | Manager | Application の UseCase、Presentation の gate | Data 層（`NotificationRepositoryImpl`）は `shared` の組み立てにだけ使い、操作は UseCase を通す（13.10 の 1 を直した） |

Domain と Application に platform の型を足していない（`UNAuthorizationOptions` の例外は今のもの）。Manager → UseCase → Repository の経路の外は、13.2・13.12 の UseCase を置かない口（delegate・hub・`launchResponse()`）だけ。

### 17.3 公開 API（付録 A の Notification の操作の分との照合）と、今の利用者から見て変わる動作

| 付録 A | 実装 | 一致 |
|---|---|---|
| `public enum NotificationError: Error, Sendable, Equatable, LocalizedError { permissionDenied, attachmentLoadFailed(identifier:detail:), addRequestFailed(FailureDetail), setBadgeCountFailed(FailureDetail), authorizationFailed(FailureDetail), reservedUserInfoKey, invalidUserInfo, notForeground, openSettingsFailed, delegateNotInstalled }` | 同じ（C5 の「C6 で一致させる」） | 一致 |
| `ScheduledNotification: Sendable`（`userInfoValues`、計算の `userInfo`、今の引数の `init`）と `ActiveNotification` の同じ直し | 同じ | 一致 |
| `public enum NotificationCategoryChange: Sendable { register(NotificationCategory), remove(identifier: String) }` | 同じ | 一致 |
| port: `openNotificationSettings() async -> Bool`、`enqueueCategoryChange(_:completion:)` と既定の実装 | 同じ | 一致 |
| `RegisterNotificationCategoryUseCase.enqueue(_:completion:)`、`RemoveNotificationCategoryUseCase.enqueue(identifier:completion:)` | 同じ | 一致 |
| `@available(*, deprecated, message: "Use IosNotificationManager.requestPermission(options:presenter:)") NotificationPermissionHelper` | 同じ（中の口は今のまま） | 一致 |
| `show`・`update`・`schedule`（`content: sending`、`trigger` に既定なし）・`setBadgeCount` の `async throws` | 同じ | 一致 |
| `getScheduled`・`getDelivered`・`hasPermission`・`authorizationStatus` の `async` | 同じ | 一致 |
| `requestPermission(options:presenter:completion:)`、`requestPermission(options:presenter:) async throws -> Bool` | 同じ。`async` 版に `@discardableResult` を付けた（17.4 の 5） | ほぼ一致 |
| `openNotificationSettings(presenter:completion:)`、`openNotificationSettings(presenter:) async throws` | 同じ | 一致 |
| `registerCategory(_:completion:)`・`removeCategory(identifier:completion:)`（既定 `nil`）、`nonisolated(nonsending)` の `async` 版 2 つ | 同じ | 一致 |
| （付録 A に無い）`RequestNotificationPermissionUseCase`・`OpenNotificationSettingsUseCase`・`SetBadgeCountUseCase` | public（6.1 の「public」。`SetBadgeCountUseCase` は 17.4 の 1） | 6.1 と一致 |

`@unchecked Sendable`・`nonisolated(unsafe)`・`@preconcurrency` はライブラリに足していない（P1-17 の一覧の外は 0 のまま）。テストの偽物 `FakeRequestCenter`・`FakeCategoryCenter`（`UNNotificationRequest`・`UNNotificationCategory` が `Sendable` でないため `@unchecked Sendable`、鍵で守る）はテストのコードだけ。足した型に `deinit` は無い。

| 口 | 前 | 後 | 3.3 |
|---|---|---|---|
| `NotificationError` | 9 の case（C5 の 2 つを含む）。任意の `Error` を持つ。`LocalizedError` でない | 10 の case（17.1）。`Sendable`・`Equatable`・`LocalizedError`。網羅した `switch` は組めなくなる | 破壊的（S-P7） |
| callback 版の `errorMessage`（`show`・`update`・`schedule`・`setBadgeCount`・`requestPermission`） | OS の言語の汎用の文 | `NotificationError` の英語の固定の文言（例 `Failed to add the notification request.`）。自分で実装した port の他のエラーはそのエラーの説明 | 動作（S-P7） |
| `requestPermission(options:completion:)` の拒否 | helper が `permissionDenied` を投げ、`(false, <汎用の文>)` | `(false, "Notification permission was denied.")`（値の組は同じ、文言が固定）。要求の失敗は `authorizationFailed` の文言 | 動作（S-P27） |
| `show`・`schedule`・`update` の userInfo | property list でない値は `add` の中で例外か黙った欠落になりえた。**`NSNull` は通った**（19 章の測り。HEAD `b80399eb` の版で `["k": NSNull(), "a": [1, NSNull()]]` を `schedule` すると `add` は成功し、`getScheduled` は 2 つの `NSNull` をそのまま返した。iPhone 17 / 26.2） | 入口の最初に `invalidUserInfo` で失敗し、何も足さず消さない（`update` は今の予約を消す前）。`NSNull` と `NSURL` も断る（`NSSecureCoding` だが property list の値でない。S-P15） | 動作（S-P15）。`NSNull` は今の利用者に破壊的（JSON の `null` を `NSNull` にするブリッジの利用者を含む。18 章の 6） |
| `update` で添付を作れないとき | 今の予約を消してから内容を作るので、`attachmentLoadFailed` で予約が消えたままになった（C6 の前からの順） | 内容と trigger を作ってから消すので、予約は残る（`add` 自体の失敗は、消した後なので残らない。Manager の DocC に書いた） | 動作（直し。19 章の L-B1） |
| `registerCategory`・`removeCategory` | 別々の `Task` で、片方の変更が失われえた。完了なし | 呼んだ時点で列に積み、呼んだ順に 1 件ずつ反映。完了つきの口。同じ識別子の登録は置き換え（17.4 の 3） | 動作（直し）・追加（S-P14） |
| `ScheduledNotification`・`ActiveNotification` | `userInfo` は格納の辞書（Swift の値も入った） | `Sendable`。`userInfo` は値の木から Foundation の型で作り直す（`as? Int` などは今と同じ）。`init` に渡した property list でない値と `String` でない鍵は捨てる | 動作・追加（S-P25） |
| `NotificationRepository`（public の port） | `openNotificationSettings()` | `openNotificationSettings() async -> Bool` と `enqueueCategoryChange(_:completion:)`（既定の実装あり） | 破壊的・追加 |
| `NotificationPermissionHelper` | - | deprecated（呼ぶ所に警告）。動作は今のまま | 非推奨（S-P27） |
| `async` の文脈で `completion` を書かずに今の口を呼ぶ所 | 組めた | `await`（と `try`）が要る。3.3 の一覧に無かった `openNotificationSettings()`（引数なし）も同じ（17.4 の 2） | 破壊的（ソース。S-P26） |
| 足す口 | - | 17.1 の Manager の行 | 追加 |
| ログ | - | 先頭のログに `completion` の有無と trigger（`.private`）。検査・`add`・バッジ・権限・添付の失敗は domain と code を `.error` で。列の積み・取り出し・反映（識別子だけ）。userInfo は鍵の数だけ | 動作（S-P21） |

### 17.4 設計書からの偏りと理由

| # | 設計書 | 実装 | 理由 |
|---|---|---|---|
| 1 | 6.1・9 章に Badge の UseCase が無い（9 章は `setBadgeCount` を「今の口と `async throws` 版」とだけ書く） | `SetBadgeCountUseCase`（`Application/UseCase/NotificationBadgeUseCases.swift`、public）を足し、Manager の callback 版・`async` 版はそれを通る | 13.10 の不備の 1（Manager が `repository.setBadgeCount` を直に呼ぶ）を直すため（`common.md` の Manager → UseCase → Repository）。設計書 6.1 に注を足した |
| 2 | 3.3・S-P26 の「組めなくなる今の呼び出し」の一覧 | 引数の無い `openNotificationSettings()` も、`async` の文脈では `async throws` 版（`presenter` の既定 `.firstActiveScene`）に決まって組めなくなる | 一覧に無かった（C6 のテストのソースで組めなくなって分かった。`IosNotificationManagerTests` は同期の closure から呼ぶ形に直した）。設計書 3.3 に注を足した。UT-31 の一覧（C7、T-21）に入れる（17.11） |
| 3 | 8.5.6「足すか外す」 | 登録は同じ識別子の category を外してから足す | 今の `registerCategory` は `Set<UNNotificationCategory>.insert` だけで、集合は category 全体（`isEqual`）で比べるので、中身の違う同じ識別子の category が 2 つ残った（どちらが効くかは決まっていない）。UT-28 の `registeringAgainReplacesTheCategory` と M150。設計書 8.5.6 に注。動作の直しなので 18 章の 1 に挙げた |
| 4 | 6.1「`NotificationPresentationGate`（internal、`@MainActor`）」 | `Sendable` の struct で、2 つの口が `@MainActor`。前面の確かめは作るときに受けた環境（本番は `UIKitPresentationEnvironment`、テストは `FakePresentationEnvironment`）で `PresentationProcedure.requireForeground` を呼ぶ closure | Manager（`Sendable`、`@MainActor` でない）が `let` で持ち、テストの init で差し替えられる形にするため。判定は main actor で行う（設計の意図のまま）。設計書 8.5.4 に注 |
| 5 | 付録 A の `requestPermission(options:presenter:) async throws -> Bool` | `@discardableResult` を付けた | `ios.md` の「ネイティブ版は `@discardableResult` を付け」。付録 A の後に注（C5 の `addListener` と同じく C7 で付録 A に足す） |
| 6 | 9 章の `RequestNotificationPermissionUseCase`（形は書いていない） | `execute(options:) async throws(NotificationError) -> Bool`。port が `NotificationError` でないものを投げたら `authorizationFailed(FailureDetail)` に写す | gate と Manager の `Result<Bool, NotificationError>` を型で保つため。自分で実装した port の任意のエラーも 1 つの case になる（10.2 の「1 つの case に 1 つの値」）。deprecated の helper は今のまま投げ直す（S-P27）ので、この違いが「Manager が helper を使わない」ことの単体テストの手がかりになった（17.5 の M141） |
| 7 | 8.5.6「確認」・RK-10「読み直しで確かめられなければ『書き戻した後』を完了にする」 | 読み直して読めなければ `.error` のログを出すだけで、待ち直さない。完了は書き戻しと読み直しの後。読み直しは、足すときは書いた category と識別子・アクションの識別子の並び・options で比べ、外すときは識別子が無いことを見る（19 章の L-C4。識別子だけでは、置き換えが効かず古い category が残っても通った） | MS-09（17.7）で読み直しはいつも 1 回目で反映を読んだので、待ち直しの手順を足さなかった。比べ方は、本物の center で書いて読み直した category がこの比べ方で 20/20 一致し、`isEqual` でも 20/20 一致した（使い捨ての写しの下調べ。iPhone 17 / 26.2 と iPhone 16 / 18.3。アクションの icon・options、テキスト入力のアクション、category の 3 つの options を含む）。`isEqual` は OS が持つ値（題・icon など）まで比べ、将来の OS で写しの値が変わると誤った `.error` を出しうるので、確かめに要る 3 つだけを比べた |
| 8 | 13.2 の N40・N42 の環境（シミュレーター、`reinstall`）と置き場所（書いていない） | 2 つとも `NotificationPermissionUITests` に入れ、ランナーの `PERMISSION_ORDER` を NP2 → N42 → N40 → NP1 にした（どれも消してから 1 件ずつ）。`SIMULATOR_ONLY_TESTS` に足した。N40 の設定の App の操作は信頼する部分の `Springboard.openSampleNotificationSettingsLink()` で、`session.isDevice` なら何もせずに投げる | 権限が未決の新しいインストールが要る（N42 は未決のときだけ前面を見る、N40 は SR-11 の「新しく入れたアプリで先に求める」）。権限のクラスはランナーが 1 件ずつ消して流す唯一の所。最後を NP1 にして許可済みで終わる（U-7）。実機では NP1・NP2 だけが今の順で流れる（自己テスト `test_systemui_and_reinstall_leave_n40_and_n42_out`）。HC10 は足さない（15 章の 2 の決定） |
| 9 | 13.2 の N39「SA-10 → 完了の後すぐ ShowImmediate → 長押し」 | 先に今の RemoveCategory を押してから SA-10。長押しは前面のバナー | category は OS に残るので、消さずに登録すると前から残る category で通ってしまう（N23・N24 と同じ考え）。今の RemoveCategory も同じ列に積むので、登録より後に反映されることは無い。前面のバナーを長押しすると、ホームに移る間のバナーの消え方に頼らない |
| 10 | 13.2 の N38「通知は出ない」 | 2 つのバナーが 3 秒と 1 秒出ないこと（固定の待ち。U-14 の例外に足した）と、表示済み・予約が 0 件 | 「出ない」ことの確かめなので U-14 の例外の形。0 件の確かめは待ちの後に行う（足されていれば 3 秒の間に表示済みに入る） |
| 11 | 13.2 の N42「`failure notForeground`。ダイアログは出ない」 | 加えて、AuthorizationStatus が `notDetermined` のまま（何も要求していない）こと | 要求したのに OS がダイアログを出さなかった、と区別するため |
| 12 | 12 章 SA-13・SA-05 の口の形（書いていない） | `requestPermissionWithAppSettings` は `async` 版、`openNotificationSettingsForeground` と `requestPermissionAfter3Seconds` は C ABI が使う `Result` の callback 版 | `ios.md` の「新しく足すボタンは `async` 版」と、C3 の Share のサンプル（`shareThenDismissFromOutside`・`shareAfter3Seconds` は callback 版）の前例に合わせ、両方の形を UI テストが通るようにした |
| 13 | UT-28「取り出しが空を見る直前と直後に積む形を、偽物の中の待ち合わせで作る」 | 列に internal の `drainHook`（取り出しの直前と、印を下ろした直後に呼ぶ）を付け、そこで積むテスト（`aChangeEnqueuedAtTheEndOfADrainIsNeverLeft`）。加えて、別のスレッドから 1 件ずつ、取り出しの点で放して積み、取り出しを 0〜3 µs 遅らせる競争（5000 回。`aChangeRacingTheEndOfADrainIsNeverLeft`。取り残しがあれば次が積まれないので止まる） | 偽物の center は取り出しの区間に入れないので、列の側に点を作った。点は区間の外で、本番では `nil`。「空を見るのと印を下ろすのを別の区間にする」変異（M142）を 2 つ目のテストが落とした（最初の 2 つの版は落とせなかった。17.5 の M142） |
| 14 | 13.1 UT-32 の壊し方「一覧の型の `Sendable` を外す」 | 外すとテストのターゲットが組めない（M152。ライブラリ自体は組める） | 組めないことが守り（Swift 6 の complete）。テストは `Task.detached` と main actor の `Task` で境界を越えさせる |
| 15 | S-P27・SR3-4「テストは `init(repository:)` で Mock の repository を渡す形に直す」 | テストの init は `init(repository:delegateStatus:presentationGate:)`（後ろの 2 つは既定あり）。`init(repository:)` で書ける | gate の偽物の環境をテストから渡すため |
| 16 | 8.5.4「`.foreground`・`.viewController`: 先に状態を読む。`notDetermined` でなければ要求せずに今の状態で完了」 | そのとおりにし、そのため許可済みのアプリが `.foreground` で `.providesAppNotificationSettings` を足して求めても求め直さないことを DocC の `- Important:` に書いた（`.firstActiveScene` なら求め直す） | 設計どおりだが、MS-07（13.17 の 1）は許可済みのアプリで求め直してリンクを出した。C ABI の受け口は `.foreground` を渡すので、ゲームが後から選択肢を足せない。18 章の 2 に挙げた |
| 17 | 13.1 UT-18「添付を作れない」の確かめ方（書いていない） | 単体テストは system が受けない種類のファイル（`.ut18unknown`）で `attachmentLoadFailed`（domain は `UNErrorDomain`）を確かめた | テストのホスト（iOS 26.2）では、無いファイルの URL でも `UNNotificationAttachment(identifier:url:options:)` が投げず、`add` まで進んだ（最初の版のテストで分かった）。今の動作で、C6 では変えていない（17.11） |
| 18 | 8.3.3・8.5.3・SR-9「消す前に検査する」 | `update` は userInfo の検査に加えて、内容（添付）と trigger も今の予約を消す前に作る | C6 の前からの順の不備の直し（前は消してから `makeUNContent` を呼び、添付を作れないと `attachmentLoadFailed` で予約が消えたままだった）。C6 のレビューの L-B1（19 章）。`updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest` と M155 |

### 17.5 単体テストと壊して確かめたこと

| ID | ファイル（`IosLibraryTests/Notification/`） | 件数 | 中身 |
|---|---|---|---|
| UT-16（通知の分） | `Domain/NotificationErrorTests.swift`（新） | 6 | 10 の case がちょうど 1 回ずつ（網羅の `switch` の番号）、どれも空でない固定の文言で `localizedDescription` も同じ、文言は互いに違う。別の値でも同じ文言で、識別子や domain を含まない。C5 の 2 つの case と `invalidUserInfo` の文言。`Equatable` が値で比べる。ログの形（`LogRedaction.describe`）が case と `FailureDetail` の domain・code だけ。callback 版の `errorMessage` が固定の文言（自分の port の別のエラーはその説明） |
| UT-18（一覧の分） | `Domain/NotificationListTypesTests.swift`（新） | 5 | system が返す Foundation の型の userInfo（整数・`Int64.min`・`UInt64.max`・実数・真偽値・文字列・日時・バイト列・配列・辞書）で、`ScheduledNotification`・`ActiveNotification` の `userInfo` が `as? Int`・`Int64`・`UInt64`・`Double`・`Bool`・`String`・`Date`・`Data`・`[Any]`・`[String: Any]` で今と同じに読め、真偽値が `CFBoolean` のまま。`userInfoValues` の case。Swift の値で作っても同じ。property list でない値と `String` でない鍵は捨て、入れ子の中も、落ちない。`Task.detached` から main actor へ渡る（`Sendable`） |
| UT-18（検査の分） | `Data/NotificationRepositoryUserInfoCheckTests.swift`（新） | 7 → 8（19 章） | `isPropertyList` がすべての property list の型を通し、`NSObject`・`NSNull`・`URL`・入れ子の中の値・配列の中の `NSNull`・整数の鍵の辞書を断る。`show`・`schedule` は断って center を呼ばない。**`update` は断ったとき今の予約を消さない**（center の呼び出しは前の `add` だけ。SR-9）。予約したキーが先（両方あれば `reservedUserInfoKey`）。property list は印を付けて通る。`add` の失敗が `addRequestFailed` で domain と code を保つ（3 つの口）。受けない種類の添付は `attachmentLoadFailed` で識別子と `UNErrorDomain`、何も足さない（`anAttachmentOfAFileTypeTheSystemRejectsKeepsItsIdentifierAndTheDetail`。19 章で名前を直した）。**`update` で受けない種類の添付は今の予約を消さない**（center の呼び出しは前の `add` だけ。19 章の L-B1） |
| UT-28 | `Data/NotificationCategoryQueueTests.swift`（新、`.serialized`） | 14 → 15（19 章） | 1 件: 読む → 書き戻す → 読み直す → 完了。1 つのスレッドから呼んだ順（`+a +b -a +c`）。8 スレッド × 25 回の登録と 13 回の削除で変更が失われず、どの変更も読む・書く・読むが割り込まれない。**処理の途中**（偽物の読み取りを止めている間）に 2 件積んでも取り出しは 1 つのまま、順に反映。**終わり際**: 取り出しの直前に積んだものは同じ取り出しが拾い、印を下ろした直後に積んだものは新しい取り出しを起こす（`drainStartCount` が 2）。別のスレッドから 1 件ずつ取り出しの点に合わせて積む 5000 回（取り出しを 0〜3 µs 遅らせる）で取り残しが無い。同じ識別子は置き換え。`NotificationRepositoryImpl()` を 2 つ作っても `.shared`。repository の `async` の口と `enqueueCategoryChange` が同じ列に順に積む。自分の port は既定の実装（`async` の口を呼んで完了）。Manager: callback 版は呼び出しの中で積み、完了は main で 1 回、反映の後、呼び出しの中では来ない。`async` 版は反映の後に戻る。C ABI の形（main のブロックの中で callback 版を 16 回）は呼んだ順。**main の `Task` を 8 つ続けて起こして `async` 版の登録、次の 8 つで削除、を 300 回繰り返して、ずれが 0 回**。読み直しの比べ方（`isReadBack`）: 書いた category と作り直した写しは通り、古い category・アクションの順の違い・options の違い・別の識別子・空は通らない。外すときは識別子が無いときだけ通る（19 章の L-C4） |
| UT-28（UseCase） | `Application/NotificationCategoryUseCasesTests.swift` | +1 | 2 つの UseCase の `enqueue` が port に同期に積み、反映の後に完了 |
| UT-26・UT-27 | `Presentation/Permission/NotificationPresentationGateTests.swift`（新。`NotificationPresentationGateTests` 10 → 11 と `IosNotificationManagerPermissionTests` 5） | 15 → 16（19 章） | gate: `.firstActiveScene` は状態も前面も見ずに要求（許可・拒否）。`.foreground` と `.viewController`（window の外と中）で決まった状態（`authorized`・`provisional`・`ephemeral` は `true`、`denied`・`unknown` は `false`）は要求せず前面も見ない（引数 5 つ × presenter 3 つ。19 章の L-C5 で presenter を足した）。未決で前面でなければ `notForeground` で要求しない。未決で前面なら、落ち着いていなくても要求し、選択肢がそのまま渡る。`.viewController` は window の中のときだけ。失敗は `authorizationFailed`（ライブラリの case はそのまま、ほかは domain と code）。`grants`。設定の画面: `.firstActiveScene` は前面を見ずに開く、前面でなければ（`.foreground`・`.viewController`）開かずに `notForeground`、window の中の `.viewController` は開く（19 章の L-C5）、開けなければ `openSettingsFailed`。Manager: `Result` の 2 つの口の完了は main で 1 回、呼び出しの中では来ない。4 スレッドから重ねた要求はそれぞれ完了。今の `requestPermission(options:completion:)` の拒否は `(false, <permissionDenied の文言>)`。**今の口は helper でなく UseCase を通る**（port が `NotificationError` でないものを投げると `authorizationFailed` の文言。helper ならそのエラーの説明。選択肢がそのまま渡る）。`async` 版: 拒否は `false`、`notForeground`、`openSettingsFailed` |
| UT-29・UT-32 | `Presentation/IosNotificationManagerAsyncTests.swift`（新） | 6 | `show`・`update`・`schedule`・`setBadgeCount` の `async throws` 版が UseCase を通って成功し、UseCase が投げた値をそのまま投げる。ライブラリの repository の検査（`invalidUserInfo`・`reservedUserInfoKey`）が `async` 版に届き center を呼ばない。4 つの問い合わせの `async` 版の値。callback 版の文言が固定。**UT-32**: main actor の `Task` の中で `getScheduled()`・`getDelivered()`・`requestPermission(options:presenter:)`・`authorizationStatus()` を待ち、結果を持ち出せる（Swift 6 の complete で組める） |
| - | `Application/NotificationPermissionUseCasesTests.swift`（新） | 4 | 権限の要求の UseCase（許可・拒否・選択肢・状態を読まない、`NotificationError` はそのまま・ほかは `authorizationFailed`）、設定の画面の UseCase（開けたか）、`SetBadgeCountUseCase` |
| S-P27 | `Presentation/NotificationPermissionHelperTests.swift` | 4 → 5 | deprecated の helper を deprecated の witness（`DeprecatedNotificationCalls`）から呼ぶ形に直した（警告 0）。拒否は今のまま `permissionDenied` を投げる、port のエラーはそのまま、状態、設定の画面は `Task` で port の `async` の口を 1 回呼ぶ |
| UT-15（19 章の L-B3） | `Common/LibraryLogPrivacyTests.swift` | 0（今のテストに足した） | `secretValuesNeverReachTheLog` に、番兵の題・副題・本文・userInfo の値（入れ子と、捨てられる `URL` を含む）で `ScheduledNotification`・`ActiveNotification` の `init`、`NotificationRepositoryImpl.activeNotification(identifier:date:content:)`、番兵の要求を持つ `FakeRequestCenter` からの `getScheduled` を足した。4 つの先頭のログが読めることを `#require` する |
| - | 今のテストの直し | - | `MockNotificationRepository`（`FailureDetail` の case、`stubbedGranted`・`requestPermissionError`・`lastRequestedOptions`・`stubbedSettingsOpened`・呼び出しの数、`openNotificationSettings() async -> Bool`）、`IosNotificationManagerTests`（`init(repository:)`、今の `openNotificationSettings()` は同期の closure から呼んで `Task` を待つ）、`NotificationRepositoryMarkerTests`（偽の center を `Data/Support/FakeNotificationCenters.swift` に移し、`if case` を `==` に。13.21 の 1 行目）、`IosNotificationManagerEventTests`・`NotificationDelegateProxyTests`・`LibraryLogPrivacyTests`（helper の引数を外した。`describe` の内側のエラーの確かめはテストの中の enum で） |

`IosLibraryTests` は 537 件（C5 の 478 件 + 59）。19 章の直しで 540 件（+3）。消したテストは無い。名前を替えたのは 1 件: `NotificationPermissionHelperTests.requestPermissionThrowsPermissionDeniedWhenFailed` を `…WhenDenied` にした（Mock の `shouldFail` が拒否でなく port のエラーを投げる形になったので、拒否の件と port のエラーの件 `requestPermissionThrowsWhatTheRepositoryThrew` に分けた）。

壊して確かめたこと（`mutate_c6.py` で 1 つずつ使い捨ての写しに当てて該当の suite を流し、落ちることを見てから戻した。iPhone 16 / 26.2、Xcode 26.6。差分とログは scratchpad。番号は M122 に続ける）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M123 | S-P7（エラーの写し） | `add` の失敗を `setBadgeCountFailed` で投げる | `aFailedAddKeepsTheDomainAndTheCode` |
| M124 | S-P7 | `add` の失敗の `FailureDetail` の code を 0 にする | `aFailedAddKeepsTheDomainAndTheCode` |
| M125 | S-P7・T-18 | 権限の UseCase が `NotificationError` でないエラーを `permissionDenied` に写す | `aFailedRequestIsAuthorizationFailed`、`requestThrowsANotificationErrorAsItIsAndAnotherAsAuthorizationFailed`、`theExistingRequestGoesThroughTheUseCase` |
| M126 | UT-16（設計書 13.1「文言を変える」） | `attachmentLoadFailed` の文言に識別子を入れる | `theDescriptionsHoldNoValues` |
| M127 | S-P7 | callback 版の `errorMessage` を `String(describing:)` にする | `theCallbackMessageIsTheFixedText`、`theCallbackFormsReportTheFixedText` |
| M128 | 8.5.3（検査の順） | property list の検査を予約したキーより先にする | `theReservedKeyIsCheckedBeforeThePropertyList` |
| M129 | SR-9（設計書 13.1「消してから検査する」） | `update` が今の予約を消してから検査する | `updateWithAUserInfoThatIsNotAPropertyListLeavesThePendingRequest`、`updateWithTheReservedKeyLeavesThePendingRequest` |
| M130 | S-P15 | `schedule` が予約したキーだけを見る | `showAndScheduleRejectAUserInfoThatIsNotAPropertyList` |
| M131 | S-P25（設計書 13.1「作り直しを Swift の値にする」） | 一覧の `userInfo` を値の木の case のまま返す | `aScheduledNotificationReadsAsBefore`、`swiftValuesPassedToInitReadAsBefore`、`theListsCrossToTheMainActor` |
| M132 | S-P25 | `init` が文字列の値だけを残す | `aScheduledNotificationReadsAsBefore`、`initLeavesOutWhatIsNotAPropertyList` ほか 2 件 |
| M133 | UT-26（設計書 13.1「未決でなくても前面を求める」の向きの逆） | 決まった状態でも要求する | `aDecidedStatusAnswersWithoutARequest` |
| M134 | UT-26・S-13 | 未決のとき前面を求めない | `notDeterminedOutsideTheForegroundIsNotForeground`、`theProvidedViewControllerMustBeInAWindow` |
| M135 | 8.5.4（`.firstActiveScene` は今のまま） | `.firstActiveScene` も前面を確かめる | `theFirstActiveSceneRequestsAtOnce` |
| M136 | 8.5.4 | `provisional` を許可でないとする | `aDecidedStatusAnswersWithoutARequest`、`theStatusesThatGrant` |
| M137 | UT-27（設定の画面の gate） | 前面でなくても開く | `outsideTheForegroundTheSettingsPageIsNotOpened` |
| M138 | UT-27（設計書 13.1「結果を捨てる」） | 開けなくても成功にする | `inTheForegroundTheSettingsPageOpensOrFails` |
| M139 | 6.2（完了は main） | `Result` の口の完了を背景のキューから呼ぶ（`MainActor.assumeIsolated` の中） | `theResultFormsCompleteOnMainOnceAndNeverInsideTheCall` と `overlappingRequestsEachComplete` でテストのホストが止まった（main 以外の `assumeIsolated`。M78 と同じ落ち方。ほかの 3 件は再起動の後に通った） |
| M140 | S-P27（今の口の値） | 今の `requestPermission(options:completion:)` の拒否の `errorMessage` を `nil` にする | `theExistingRequestReportsADenialAsAFailure` |
| M141 | S-P27・SR2-9（helper を中で使わない） | 今の `requestPermission(options:completion:)` を deprecated の helper で行う | `theExistingRequestGoesThroughTheUseCase`（helper は port のエラーをそのまま投げ直すので文言が違う）。組むと `'NotificationPermissionHelper' is deprecated` の警告が出た（17.9 の警告 0 の確かめも落とす） |
| M142 | UT-28（設計書 13.1「空を見るのと印を下ろすのを別の `Mutex` の区間にする」） | 取り出しが空を見る区間と印を下ろす区間を分ける | **最初は生き残った**（最初の版の `aChangeRacingTheEndOfADrainIsNeverLeft` は別のスレッドの積みが区間の隙間に当たらなかった。セマフォで起こす版も 2 回のうち 1 回は生き残った）。取り出しの点の手前で回して待っているスレッドを放し、取り出しを 0〜3 µs 遅らせて 5000 回当てる形に直し、**3 回とも落ちる**ことを確かめた（取り残しで次の積みが来ず、2 秒で止まる）。直した版は壊さないコードで 5 回繰り返し・TSan・18.3 の 2 台で通った |
| M143 | 8.5.6（積む） | 積むたびに取り出しを起こす | `aChangeEnqueuedDuringAnotherWaitsAndStartsNoSecondDrain`、`concurrentChangesFromEightThreadsAreAllKept`、`changesFromOneThreadKeepTheirOrder`、`mainActorTasksStartedInARowKeepTheirOrder` ほか 3 件 |
| M144 | 8.5.6（始めと終わりの順） | 完了を反映の前に呼ぶ | `aChangeCompletesAfterItIsAppliedAndReadBack`、`theCallbackFormsCompleteOnMainAfterTheChange`、`theAsyncFormsReturnAfterTheChange`、`enqueueQueuesOnThePortInsideTheCall` ほか 3 件 |
| M145 | SR3-1（設計書 13.1「`nonisolated(nonsending)` を外す」） | 2 つの `async` 版の `nonisolated(nonsending)` を外す | `mainActorTasksStartedInARowKeepTheirOrder` |
| M146 | S-P28 | callback 版の登録を `Task` の中で UseCase の `async` の口で行う（v2 の形） | `callsInsideAMainQueueBlockKeepTheirOrder`、`theCallbackFormsCompleteOnMainAfterTheChange` |
| M147 | S-P28 | repository が `enqueueCategoryChange` を持たず、port の既定の実装（変更ごとの `Task`）になる | `callsInsideAMainQueueBlockKeepTheirOrder`、`mainActorTasksStartedInARowKeepTheirOrder`、`theRepositoryQueuesItsChanges` |
| M148 | SR3-6（完了は main） | category の利用者の完了を背景のキューから呼ぶ | `theCallbackFormsCompleteOnMainAfterTheChange` でテストのホストが止まった（main 以外の `assumeIsolated`） |
| M149 | SR-18 | public の `init()` が repository ごとに列を作る | `everyRepositoryUsesTheQueueOfTheProcess` |
| M150 | 17.4 の 3 | 登録で同じ識別子の category を外さない（今の `insert` だけ） | `registeringAgainReplacesTheCategory` |
| M151 | UT-29（設計書 13.1「エラーを写し違える」） | `async` 版の `show` がどのエラーも `addRequestFailed` に包む | `theThrowingFormsThrowWhatTheirUseCasesThrow`、`theUserInfoChecksReachTheAsyncForms` |
| M152 | UT-32（設計書 13.1「一覧の型の `Sendable` を外す」） | `ScheduledNotification` の `Sendable` を外す | テストのターゲットが組めない（`NotificationListTypesTests` と `IosNotificationManagerAsyncTests` で「`Sendable` に準拠しない」）。ライブラリは組める |
| M153 | UT-15（設計書 13.1「1 か所で値を `.public` で補間する」） | userInfo の検査の先頭のログに userInfo を `.public` で入れる | `notificationContentsThroughTheRealCenterNeverReachTheLog` |
| M154 | T-18 | 今の `requestPermission(options:completion:)` が選択肢を捨てて既定で求める | `theExistingRequestGoesThroughTheUseCase` |
| M155 | 19 章の L-B1（C6 の前の順） | `update` が今の予約を消してから内容を作る | `updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest` |
| M156 | 19 章の L-C4（直す前の確かめ） | 読み直しが識別子だけを見る | `theReadBackComparesTheWrittenCategory`（3 件の確かめ） |
| M157 | 19 章の L-C4 | 読み直しが options を見ない | `theReadBackComparesTheWrittenCategory`（1 件の確かめ） |

32 件とも落ちた（M142 はテストを直した後。M152 は組めない形で落ちる）。19 章の直しの M155〜M157 も 3 件とも落ちた（`mutate_c6fix.py`。iPhone 16 / 26.2、Xcode 26.6）。戻した版で通ることは 17.8 の全件の実行で確かめた（M142 の後に直した `NotificationCategoryQueueTests` は、その suite を 3 台と TSan で流し直した）。UI テストの変異は流していない（C5 と同じ）。

### 17.6 公開 API（swiftinterface）

- 組み方: C4・C5 と同じ（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3）。`arm64-apple-ios.swiftinterface` を写した
- 足したファイル: `IosLibrary-after-1b-c6.swiftinterface`、差分 `2026-10-31-stage1b-c6.diff`（`after-1b-c5` が基準）
- 差分の中身: 17.3 の表のとおり。port の `openNotificationSettings() async -> Swift.Bool` と `enqueueCategoryChange` の要件と既定の実装、3 つの UseCase と 2 つの `enqueue`、`NotificationError` の case と `Sendable, Equatable, LocalizedError`・`errorDescription`・`==`、2 つの一覧の型の `Sendable`・`userInfoValues`・計算の `userInfo`、`NotificationCategoryChange`、`NotificationPermissionHelper` の `@available(*, deprecated, …)`、Manager の `async` 版 10（4 つの操作、4 つの問い合わせ、権限の要求、設定の画面）・`Result` の 2 つの口・`registerCategory`・`removeCategory` の `completion` と `nonisolated(nonsending)` の `async` 版（`#if compiler(>=5.3) && $AsyncExecutionBehaviorAttributes` の中）。今の `registerCategory(_:)`・`removeCategory(identifier:)` の宣言は既定 `nil` の `completion` を足した形に替わった（ソースは組める。ABI の記号は替わる。2.0.0 は破壊的変更の版）
- `swift-frontend -typecheck-module-from-interface`（Xcode 26.3、Swift 6.2.4、`-F` に framework の置き場）で public と private の 2 つとも型検査が通った（出力 0 行）。`nonisolated(nonsending)` と型つきの throws（`RequestNotificationPermissionUseCase.execute(options:)` の `throws(IosLibrary.NotificationError)`）を含む

### 17.7 シミュレーターで測ったこと（C6 に付いた MS-04・MS-09 と、MS-07 の残り）

1. **MS-09**（`setNotificationCategories` の後の `notificationCategories()` に反映が読めるまで。設計書 8.5.6 の「確認」、RK-10）。使い捨ての写しのテストのホストに下調べのテスト（`ProbeMS09Tests`。リポジトリには入れていない）を足し、本物の `UNUserNotificationCenter` で、(a) 直に: 読む → 1 つ足す（または外す）→ 書き戻す → 反映が読めるまで読み直す、を 30 回 × 足す・外す、(b) ライブラリの列（`NotificationCategoryQueue.shared`）で積んでから完了までの時間と、完了の後に読んだ値、を測った

| 測り | iPhone 17 / 26.2 | iPhone 16 / 18.3 |
|---|---|---|
| (a) 1 回目の読み直しで反映が読めた回数 | 60/60 | 60/60 |
| (a) 書き戻しから反映が読めるまで | 1.1〜3.3 ms（中央 1.3 ms） | 1.2〜4.0 ms（中央 1.5 ms） |
| (b) 積んでから完了まで（読む・書く・読み直す） | 1.4〜2.9 ms（中央 1.6 ms） | 1.7〜3.4 ms（中央 2.2 ms） |
| (b) 完了の後に読んだ値が変更どおり | 60/60 | 60/60 |

分かったこと: 書き戻しの後の最初の読み直しで、いつも反映が読めた（両方の OS）。そのため「読み直して確かめてから完了」の形のまま、読めなかったときの待ち直しは足さず、`.error` のログだけにした（17.4 の 7）。完了の後に出した通知でアクションが出ることは N39 で確かめた（26.2）。テストのホストは通知の権限を持たないが、category の読み書きは権限に関わらず動いた

2. **MS-04**（後ろから `UIApplication.open` を呼んだとき、権限が未決で後ろにいるときの `requestAuthorization`。iPhone 17 / 26.2、各 1 回）。使い捨ての写しのサンプルに、3 秒後に `.firstActiveScene`（前面を見ない）で呼ぶ下調べのボタン 2 つと、押してホームに移り 9 秒見てから前に戻す下調べの UI テスト（`ProbeMS04UITests`）を足して測った（リポジトリには入れていない）

| # | 呼び方 | 結果 |
|---|---|---|
| P1 | 新しく入れたアプリ（未決）で、後ろから `requestPermission(presenter: .firstActiveScene)`（`requestAuthorization`） | **後ろにいる間に権限のダイアログがホーム画面の上に出た**（ホームに移ってから約 2.7 秒。要求の時点）。完了はダイアログの答えまで来ない（前に戻してから「Don’t Allow」を押して `success granted=false`、要求から約 7.9 秒。完了の時点は `foregroundInactive`） |
| P2 | 後ろから `openNotificationSettings(presenter: .firstActiveScene)`（`UIApplication.open(openNotificationSettingsURLString)`） | **`UIApplication.open` が約 15 ms で `false` を返し、設定の App は開かなかった**（`failure openSettingsFailed`、完了の時点も `background`） |

分かったこと: (1) 未決のまま後ろで要求すると、OS はアプリが見えていないのにダイアログを出し、答えが出るまで完了しない。8.5.4 の「未決なら前面を確かめる」（`.foreground` で `notForeground`）が要る根拠になる（N42 は `.foreground` で出ないことを確かめた）。(2) 後ろからの `open` は OS が断る（`false`）。`.firstActiveScene` でも `openSettingsFailed` で 1 回完了し、止まらない。`.foreground` は先に `notForeground` で断る（8.5.5 のとおり）。判定（8.5.4・8.5.5）は変えなくてよい。C7（T-20）で第 1 部 G-7 の記録に写す

3. **MS-07 の残り**（13.17 の 1 で測っていなかった「新しく入れたアプリで SA-13 のボタンから先に求める形」。SR-11）: N40 のとおり、iPhone 17 / 26.2 で新しく入れたアプリが `.providesAppNotificationSettings` を足して求めて許可すると、設定の App の通知の画面にリンクが出て、押すと `settingsRequests` にイベントが 1 つ（`notificationId=nil`）届いた。通知の行は label が設定の要約（`Notifications, Banners, Sounds, Badges`）を含むので、識別子 `NOTIFICATIONS` で探す（最初の版の N40 は label で探して見つけられなかった）。iOS 18.3 は測っていない（UI テストは iPhone 17 / 26.2 だけで流した）

### 17.8 テストの実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3。`-parallel-testing-enabled NO`。18.3 の 2 つは `arch=arm64`。Xcode 26.6） | どれも 537/537（C5 の 478 + 59）。skip 0。消したテストは無い（名前を替えたのは 17.5 の 1 件）。この回の後に M142 のために `aChangeRacingTheEndOfADrainIsNeverLeft` を直したので、`NotificationCategoryQueueTests` だけを 3 台で流し直した（iPhone 17 / 26.2 は 5 回繰り返して 70/70、18.3 の 2 台は 14/14） |
| TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2、Xcode 26.6） | 列・UseCase・gate・Manager の権限・`async` 版・エラー・一覧の型・userInfo の検査・印・権限の UseCase・helper・`IosNotificationManagerTests`・値の木の 13 suite・94 件が成功。TSan の報告は 0 件（8 スレッドの並行の積み、別のスレッドからの競争、main の `Task` の 300 回を含む）。M142 の後に直した競争のテストを含む `NotificationCategoryQueueTests` は TSan で流し直し、14 件成功・報告 0 件 |
| 新しい UI テストの下調べ（写しを `xcodebuild test-without-building -only-testing` で直に。iPhone 17 / 26.2） | N38・N39・N42 は 1 回目で通った。**N40 は 1 回目に落ちた**（通知の行を label の `Notifications` で探したが、label は `Notifications, Banners, Sounds, Badges`。写しにだけ hierarchy を書き出す行を足して確かめた）。識別子 `NOTIFICATIONS` で探す形に直して通った（17.7 の 3） |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Notification`（ハッシュを固定した写し。Xcode 26.3、`xcode-select` のまま） | 54 件すべて成功（権限の NP2・N42・N40・NP1、Navigation 2、IdentifierInventory 4、Notification 25、NotificationEvent 12、NotificationColdStart 7）。閉じた形のソースの規則が通り、列挙の 124 件が宣言と一致した。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`。0g の後に取ったもの）との比べ合わせは `changed=0, added=12, removed=0`。**足した 12 件のうち C6 の分は 4 件**（N38・N39・N40・N42）で、残りの 8 件は C5 の分（N34b・N35・N36・N37・N41・N43・N44・N45。基準はまだ取り直していないので C5 の 13.18 と同じく足したものに出る）。今の N1〜N33 と NP1・NP2 は期待値を変えずに通った。I1b は Notification の 35 のボタンと節 8・状態の行 4 で一致した。信頼する部分の警告なし |
| N40 の流し直し（同じ写し、`-only-testing`、消してから） | この回の後にサンプルの `requestPermissionWithAppSettings` を `async` 版に替えた（17.4 の 12）ので、写しに入れ直して N40 を 1 件だけ流し直し、通った（43.9 秒）。ほかのボタンと UI テストは変えていない |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | 写し: 144/144。リポジトリ: 144 件のうち 5 件が落ちる（どれも信頼する部分の 3 ファイルのハッシュが固定と違うことによるもの: `SourceRules` の 2 件、`Commands.test_preflight_refuses_the_device_when_the_trusted_part_changed`、`EndToEnd` の 2 件。C5 の 13.18 と同じ 5 件）。`scripts/tests` の全体はリポジトリで 352 件のうち同じ 5 件だけが落ちる |
| 自己テストの fixture | 列挙（`enumeration.json`）は写しの `--feature Notification` の回の列挙（iPhone 17 / 26.2、Xcode 26.3、flat）をそのまま写した。前の fixture との差は足した 4 件の項目だけ（UI テストは 124 件）。実機のバイナリ（`otool-ov-device.txt`・`otool-l-device.txt`）は写しを `generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組んだ UI テストのバンドルから取った（端末は使っていない。テストのメソッドの差は N38〜N40・N42 の 8 つの記号だけ）。どれにもローカルのパスと端末の識別子は入っていない。数を照らす自己テストを 120 → 124、サンプルのボタンの数を 63 → 69 にし、権限の順の自己テスト 2 件（シミュレーターは `PERMISSION_ORDER` のとおり 4 件を消してから、実機は NP2・NP1 だけをその順で）を足した |
| ランナーの変異 | 流していない（表の値を足しただけで、判定の関数は変えていない。足した自己テストは、N40・N42 を `SIMULATOR_ONLY_TESTS` から外す・順を入れ替えると落ちる形） |
| `scripts/test_ios.sh --dry-run` | 流していない（ランナーの判定の関数は変えていない。実機の選び方は自己テスト `test_systemui_and_reinstall_leave_n40_and_n42_out` が本物の宣言で確かめる） |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2（UI テスト・下調べ）、iPhone 16 / 26.2（変異）、iPhone 16 / 18.3・iPad Pro 11-inch (M4) / 18.3（全件と MS-09）は xcodebuild・`simctl`・`test_ios.sh` が起動し、終わった後に止めた。最後に `simctl shutdown all` で止め、どれも起動していないことを確かめた。iPhone 17 / 26.2 には写しのサンプル（MS-04 の下調べの後に入れ直した版）が入っている。実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない） |

### 17.9 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme（`IosLibrary`、`IosLibraryExample`）を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |

`ios/UnityIosPlugin`（ワークスペースの外）は組んでいない（C1 と同じ）。deprecated の helper はライブラリの中で使っていない（使えば警告で分かる。M141 の版では警告が出た）。テストは deprecated の口を deprecated の witness から呼ぶ（13.15 の 12）。

### 17.10 信頼する部分の変更とハッシュ

`ios/IosLibraryExample/IosLibraryExampleUITests/Support/`。HEAD（`b80399eb`）からの差分。C2〜C5 と同じく作業ツリーに入れ、別のモデルのレビューの後に固定する形にした（18 章の 3）。**19 章の Codex の 2 回のレビューの後、下の新しい値で固定した**。UI テストとランナーの自己テストは、ハッシュだけを直した使い捨ての写しで流した（17.8）。差分は patch にして scratchpad に置いた（レビューに渡す）。

| ファイル | 操作 |
|---|---|
| `SampleApp.swift` | `NotificationButton` に 6 つ（`showReservedKey`・`showInvalidUserInfo`・`requestPermissionWithAppSettings`・`openNotificationSettingsForeground`・`requestPermissionAfter3Seconds` は `systemui`、`registerCategoryWithCompletion` は区分なし）を足した。`requestPermissionAfter3Seconds` に Debug のビルドだけの注。押す口は今の `tap(_:)`・`tap(_:_:)`・`press` だけ。**新しい操作・新しい要素の読み方は無い**（識別子と区分を足しただけ。I1b は `NotificationButton.allCases` から数えるので一覧の直しは要らない） |
| `Springboard.swift` | `openSampleNotificationSettingsLink()`（N40）: **実機では何もせずに投げる**（`session.isDevice` の確かめが最初の行。D22 の Control Center の口と同じ守り）。シミュレーターでは設定の App を終わらせて起動し直し（決まった最初の画面から始める）、「Apps」→ サンプルの行 → 通知（識別子 `NOTIFICATIONS`）→「IosLibraryExample Notification Settings」を押す。各行は label か識別子が完全に一致する button か cell がちょうど 1 つで押せるときだけ押し（2 つ以上なら押さずに投げる）、12 回まで上へ送る。押すたびに `checkInterruption()`。ファイルの冒頭の注に N40 を足した。19 章の U-C2 で、行ごとに最初の送りの前に約 2 秒その行を待ち、12 回送っても無ければ 1 回下へ戻してから諦めるようにした（ちょうど 1 つでなければ押さないのは同じ） |
| `SystemLabels.swift` | 設定の App の `settingsApps`（`Apps`）、`settingsNotificationsIdentifier`（`NOTIFICATIONS`）、`sampleNotificationSettingsLink`（`IosLibraryExample Notification Settings`）。シミュレーター（en、iOS 26.2）だけのものとして注を付けた（実機は N40 を流さないので ja は持たない。13.21 は「en と ja」と書いたが、ja は測れず使う所も無い） |
| ほかの 5 ファイル、凍結した `IosLibraryExampleUITests.swift` | 変えていない（N38・N39 は今の `waitForBanner`・`expandBanner`・`waitForActions`、N42 は今の `goHome`・`waitForAlert`、N40 は今の `waitForAlert`・`tapAlertButton`・`waitForSettingsForeground` と上の新しい口） |

識別子の文字列は信頼する部分の中だけにある（U-17。テストのクラスは `NotificationButton`・`NotificationStatusLine` の case だけを使う）。`DANGEROUS_NAMES` の新しい出現は無い（設定の App は今の `settings` の `XCUIApplication` を使う）。

再レビューの後に固定するハッシュ（`python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests`。ほかの 5 ファイルと `FROZEN_CLIPBOARD_SHA256`（`4612943d…6cf3`）は変わらない）:

| ファイル | 今の固定 | 新しい値 |
|---|---|---|
| `Support/SampleApp.swift` | `1ac8667f…421e` | `86734d0cdaae20dc51abddcbe0be36ede0e78358757a128c55eed822dcd78690` |
| `Support/Springboard.swift` | `7c642008…daba` | `b08dc1ef7a22bccd9c2029a4fc7fff8d09dfd75ff6af92101307885af7f6ce65`（19 章の U-C2 の後。Codex が見た版は `6a0abc87…55a4`） |
| `Support/SystemLabels.swift` | `f8d3e580…c0e7` | `571cb63fea2f83fd65012588d8fc9a2982e2bb65601768f5d75f1916a0003616` |

### 17.11 C7 への申し送り

| 項目 | 内容 |
|---|---|
| UT-31（T-21） | 組めなくなる今の呼び出しの一覧に、引数の無い `openNotificationSettings()` を足す（17.4 の 2）。C6 のテストのソースでは `IosNotificationManagerTests.openNotificationSettingsCallsRepository` が同期の closure から呼んでいる（その形は組める） |
| 付録 A（T-20） | `requestPermission(options:presenter:) async throws -> Bool` の `@discardableResult`（17.4 の 5）を、C5 の `addListener` と一緒に足す。gate の形（17.4 の 4）と、`SetBadgeCountUseCase`（17.4 の 1）は設計書に注を付けた |
| README 4.1・移行の手引き（T-20） | 17.3 の後ろの表（`errorMessage` の固定の文言、`requestPermission(options:completion:)` の拒否の文言、`invalidUserInfo`、category の順・完了・置き換え、一覧の型、port の 2 つの変更、helper の deprecated、`openNotificationSettings()` のソースの破壊的変更）。`NSNull` を含む userInfo が `invalidUserInfo` になること（C6 の前は通り、`getScheduled` も `NSNull` を返した。19 章の測り。18 章の 6）。18 章の決定で変わるもの |
| 第 2 部（2a） | 権限の要求と設定の画面は `Result` の callback 版に `.foreground` を渡す（8.9）。`.foreground` で権限が決まっていると求め直さない（17.4 の 16、18 章の 2）。category は callback 版を main のブロックの中で呼ぶ（UT-28 の `callsInsideAMainQueueBlockKeepTheirOrder` が守る）。`NotificationError` の 10 の case と C の値（10 章）。`attachmentLoadFailed` の識別子は C に渡さない（D-13） |
| 測り（T-20） | MS-04・MS-09 の結果（17.7）を第 1 部 G-7 と README に写す。MS-07 の新しく入れたアプリで先に求める形（SR-11）は N40 で iOS 26.2 で通った（18.3 は測っていない） |
| 全体の実行（T-21） | 基準の取り直しでは、権限のクラスが 4 件（NP2・N42・N40・NP1）になり、シミュレーターの全件は 124 件になる |
| 添付 | 18 章の 5（無いファイルの添付の振る舞いを 1 回測る） |
| ブリッジ（段階 3 まで） | 変えていない。`UnityIosNotificationManager` は `registerCategory(category)` を同期の文脈で呼ぶので今の口（完了なし）に決まり、組める。13.21 のブリッジの行（`openSettingsFor`）のまま。`UnityIosNotificationJsonParser`（`userInfo` を `JSONSerialization` の結果のまま渡す）は JSON の `null` を `NSNull` にするので、`null` を含む userInfo は C6 から `invalidUserInfo` で失敗する（C6 の前は通った。19 章の測り）。ブリッジはこのトピックで消すので直さない。C ABI で `null` を落とすか断るかは第 2 部（2a）で決める（18 章の 6） |

## 18. 利用者に決めてもらうこと（C6）

**決定（2026-11-01、利用者）: 1・2・4・5・6 は推奨のとおり。** 1 は置き換えのままにし、C7 で README 4.1 に「同じ識別子は置き換える」を足す。2 は設計のままにし、2a の C のヘッダーとマニュアル（段階 4）に書く。3 は 19 章のとおり済み。4 は組めなくなるままにし、C7（T-21）の UT-31 と README 4.1・移行の手引きの元に足す。5 は C7 で実際に通知を出す形で確かめる。6 は拒むままにし（S-P15）、C6 より前は通っていたことを移行の手引きの元に書き、C ABI での null の扱いは 2a で決める

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | category の登録が、同じ識別子の category を置き換えるようになった（17.4 の 3）。前は `Set.insert` だけで、中身の違う同じ識別子の category が 2 つ残りえた（どちらが効くかは決まっていない）。設計書 8.5.6 は「足すか外す」とだけ書き、1b の「今の動作を変えない」の外の直しになる | **置き換えのままにし、C7 で README 4.1 の「`registerCategory`・`removeCategory` が呼んだ順に反映される」の行に「同じ識別子は置き換える」を足す**。逆の考え: 今の利用者が同じ識別子で中身を変えて登録し直していた場合、前は古い方が効く見込みもあり、動作が変わる。ただし 2 つ残る状態は OS が定めていない状態で、置き換えがブリッジ（Unity の C#）の利用者の期待とも合う。戻すなら `queue.apply` の 1 行と UT-28 の 1 件（M150 の形）だけ |
| 2 | `.foreground`・`.viewController` で権限が決まっていると要求しない（8.5.4 のとおり。17.4 の 16）。そのため、許可済みのアプリが後から `.providesAppNotificationSettings` などの選択肢を足しても、C ABI（`.foreground` を渡す）からは求め直せない。MS-07 は許可済みのアプリで求め直してリンクを出せた | **設計のままにし、DocC（済み）と、第 2 部（2a）の C のヘッダー・マニュアル（段階 4）に「選択肢を足すときは最初の要求に入れる。決まった後は求め直さない」と書く**。逆の考え: 決まっているときは `requestAuthorization` を前面の確かめなしで呼んでもダイアログは出ない見込みで、選択肢を足せる。ただし `provisional` のアプリが `.alert` を求めるとダイアログが出うるので、後ろにいるときに出さない（S-13）を守るには、状態ごとに見分ける手順が要り、測りも要る。足すなら 2.0.0 の後に、選択肢の差だけを求める口として |
| 3 | **済み（2026-11-01）**: Codex が信頼する部分の patch を file:line の根拠つきでレビューし、固定してよいとした（19 章）。19 章の U-C2 で足した `Springboard.swift` の差分（行を待つことと 1 回下へ戻すこと）も Codex が file:line の根拠つきでレビューし、固定してよいとしたので、17.10 の値で固定した（19 章）。以下はもとの事柄: 信頼する部分の変更（17.10。`SampleApp.swift` のボタン 6、`Springboard.swift` の設定の App を操作する口、`SystemLabels.swift` のラベル 3 つ）と、N40・N42 を simulator only にし、権限のクラスの順を NP2 → N42 → N40 → NP1 にしたこと（ランナー） | **C2〜C5 と同じく別のモデル（Codex）に、信頼する部分の patch（scratchpad に置いた）と N38〜N40・N42 の本体、`DeviceRequirements.json` の 4 行、ランナーの 2 つの表の差分を見せ、通ったら 17.10 の値を固定して C6 のコミットに入れる**。観点は (a) `openSampleNotificationSettingsLink()` が実機では何もせずに投げ、どの押す操作よりも前に止まること、(b) 新しいボタンの区分（拒みの 2 つ・権限・設定の画面・3 秒後は `systemui`、完了つきの登録は無し）、(c) 実機で NP1・NP2 の順と消し方が変わらないこと |
| 4 | 引数の無い `openNotificationSettings()` が、`async` の文脈で組めなくなる（17.4 の 2）。設計書 3.3 の S-P26 の一覧に無かった | **組めなくなるままにし（S-P26 の決定と同じ扱い）、C7（T-21）の UT-31 の一覧と README 4.1・移行の手引きの元に足す**。名前を分けると S-P26 の B を 1 つだけ採ることになり、ほかの口とそろわない |
| 5 | テストのホスト（iOS 26.2 のシミュレーター）で、無いファイルの URL の添付は `UNNotificationAttachment` が投げず、`add` まで進んだ（17.4 の 17）。`attachmentLoadFailed` になるのは system が受けない種類のファイルなど | **C6 ではライブラリを変えず、C7 で実際に通知を出す形（サンプルの添付を消した写し）で 1 回確かめて記録する**。無い添付で通知がどうなるか（添付なしで出るか、出ないか）が分かってから、入口でファイルの有無を確かめるかを決める。今の動作で、1b の範囲を超える。逆の考え: 今の入口（`makeUNAttachment` の前）でファイルの有無を確かめれば、無いファイルを今すぐ `attachmentLoadFailed` で断れ、C ABI の利用者にも決まった失敗を返せる。ただし、今は無い添付でも `add` まで進むので、今の利用者で（添付なしで）出ていた通知が出なくなりうる（動作の変更）うえ、測らずに決めると OS がどう扱うかを先取りすることになる |
| 6 | `NSNull`（と `NSURL`）は `NSSecureCoding` だが property list の値でなく、C6 は userInfo の中の `NSNull` を `invalidUserInfo` で断る（S-P15）。C6 の前は通った: HEAD `b80399eb` の版で `["k": NSNull(), "a": [1, NSNull()]]` を `schedule` すると `add` は成功し、`getScheduled` は 2 つの `NSNull` をそのまま返した（iPhone 17 / 26.2、19 章）。今のブリッジ（`UnityIosNotificationJsonParser.swift` の `userInfo`）は JSON の `null` を `NSNull` にするので、`null` を含む userInfo を渡す今の利用者は C6 から失敗する | **S-P15 のとおり断るままにし、README 4.1・移行の手引き（C7）に書く。C ABI で `null` を落とすか断るかは第 2 部（2a）で決める**。逆の考え: `NSNull` を通すか黙って落とせば、今の呼び出しはそのまま動く。ただし値の木（`NotificationUserInfoValue`）に null が無いので、通しても一覧の型で読み戻すときに失われ（`init` が捨てる）、書いた値と読み戻した値が合わない。黙って落とすのは利用者の値を知らせずに捨てることになる。ブリッジ（`ios/UnityIosPlugin`）はこのトピックで消すので、ブリッジのために残す理由も無い |

## 19. C6 のレビューと直したこと

コードのレビューを 3 者で行った。Claude のサブエージェント（ライブラリ。設計との一致と正しさ）は A 0・B 3・C 9。Claude のサブエージェント（サンプル・UI テスト・文書）は A 0・B 1・C 4。Codex（設定のモデル。信頼する部分の patch と N38〜N40・N42 の本体、`DeviceRequirements.json`、ランナーの 2 つの表。読むだけ）は指摘なし。1 回目は理由を書かずに「指摘なし」だけを返したので、file:line の根拠を付けて流し直してもらい、信頼する部分の変更は固定してよいとした（18 章の 3）。直しのうち信頼する部分に触れるのは U-C2（`Support/Springboard.swift`）だけで、その差分も Codex（設定のモデル。読むだけ）が file:line の根拠つきでレビューし、指摘なしで固定してよいとした（送りは押す操作ではないが「何も変えない」とまでは言えない、という注だけ。どれも実機の確かめの後ろにある）。その後に `TRUSTED_FILES` の 3 つのハッシュを 17.10 の値でリポジトリに固定した（UI テストは、同じ値に固定した使い捨ての写しで流した。写しと作業ツリーは同じ）。18 章の 1・2・4・5 と新しい 6 は利用者の決定待ちで、推奨はどれもコードの変更を要しないので、動作は変えていない。

| 指摘 | 直したこと |
|---|---|
| L-B1: `NotificationRepositoryImpl.update` が今の予約を消してから `makeUNContent` を呼ぶ。添付を作れない（`attachmentLoadFailed`）と予約が消えたまま | 検査 → 内容（添付）と trigger → 今の予約を消す → `add` の順にした（C6 の前からの順の不備。17.3 と 17.4 の 18）。`updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest`（`.ut18unknown` の添付で `attachmentLoadFailed`、予約は残り、center の呼び出しは `["add u"]` だけ）と M155。Manager の `update` の DocC と repository の型の DocC を「検査と添付の失敗では予約は残る。`add` 自体の失敗は消した後」に直した |
| L-B2: `NSNull`・`NSURL` は `NSSecureCoding` だが property list の値でなく、C6 は `invalidUserInfo` で断る。今のブリッジは JSON の `null` を `NSNull` にする | 断るままにした（S-P15）。C6 の前の動作をシミュレーターで 1 回測った（下の表）: HEAD `b80399eb` の版では `add` は成功し、`getScheduled` は `NSNull` をそのまま返した。17.3、17.11 の README・移行の手引きとブリッジの行に書き、18 章の 6 に挙げた |
| L-B3: UT-15 に、一覧の型（`ScheduledNotification`・`ActiveNotification`）と `activeNotification(identifier:date:content:)` を番兵で作るものが無い | `secretValuesNeverReachTheLog` に、番兵の題・副題・本文・userInfo の値（入れ子と、捨てられる `URL`）で 2 つの `init`、`activeNotification`、番兵の要求を持つ `FakeRequestCenter` からの `getScheduled` を足し、4 つの先頭のログが読めることを `#require` した（17.5） |
| L-C1: 新しい UseCase（`SetBadgeCountUseCase`、権限の 2 つ）の `init` に先頭のログが無い。Dispatch・Query・Schedule・Category の今の UseCase の `init`・`execute` にも無い | すべての通知の UseCase の `init`（`repository` の型名）と `execute`（識別子・`content.id` は `.public`、trigger は `.private`）に足した。1 つのファイルに型が複数あるので型ごとの logger（`ios.md`）。例外として残したものは無い（17.1） |
| L-C2: Manager の Overview が「`async` 版は型つきの `NotificationError` を投げる」と読める（`async throws` は型なし） | 「`async` 版は型を書かない `async throws`。ライブラリの repository は `NotificationError` を投げ、自分で実装した repository は自分のエラーを投げうる」にした |
| L-C3: `RequestNotificationPermissionUseCase` の DocC が前面を決めるのを `IosNotificationManager` とする | `NotificationPresentationGate`（Manager の gate）にした |
| L-C4: category の列の読み直しが識別子があるかだけを見るので、置き換えが効かず古い category が残っても通る | `NotificationCategoryQueue.isReadBack(_:identifier:in:)` を足し、足すときは書いた category と識別子・アクションの識別子の並び・options が同じものがあるか、外すときは識別子が無いかで確かめる（17.4 の 7）。`theReadBackComparesTheWrittenCategory` と M156・M157。本物の center で比べ方が誤らないことを下調べで確かめた（下の表） |
| L-C5: gate のテストの決まった状態の確かめが `.foreground` だけ。window の中の `.viewController` で設定の画面が開くテストが無い | `aDecidedStatusAnswersWithoutARequest` を状態 5 × presenter 3（`.foreground`、window の外と中の `.viewController`）にし、`theSettingsPageOpensForAProvidedViewControllerInAWindow` を足した |
| L-C6: `aMissingAttachmentKeepsItsIdentifierAndTheDetail` は無いファイルでなく system が受けない種類のファイルを確かめる | `anAttachmentOfAFileTypeTheSystemRejectsKeepsItsIdentifierAndTheDetail` にした（ファイルを作る所を L-B1 のテストと共通の関数にした） |
| L-C7: 18 章の 5 に逆の考えが無い。3 が済んだと書いていない。設計書 8.5.6 の置き換えの注が決定待ちと分からない | 5 に「今の入口でファイルの有無を確かめる」側の利点と、取らない理由を足した。3 を「済み（U-C2 の差分はまだ）」にした。設計書 8.5.6 の注に「18 章の 1 の決定待ち」と、読み直しの比べ方（L-C4）を足した |
| L-C8: 設計書 6.1 の `NotificationPresentationGate` の行が `@MainActor` の型のまま | 「`Sendable` の struct で、2 つの口が `@MainActor`」の 1b C6 の注を足した |
| L-C9: `NotificationError` の表の `permissionDenied` の行が、今の `requestPermission(options:completion:)` もこの値を報告すると読める（報告するのは文言だけ） | 「deprecated の helper が投げる。今の `requestPermission(options:completion:)` は文言だけを `false` と一緒に `errorMessage` で報告する」にした |
| UI B-1: UI テストの設計書が C6 の simulator only・N40 の操作・権限の順を書いていない | 6.3 の 3 を N40・N42 を含む 9 件にし、二重の守りに設定の App のリンクの口を足した。6.1 の `Springboard` の行に N40 の操作（シミュレーターだけ、実機では throw）を足した。2.1 の例外の表に N40 の行（設定の App の中の行を押す。シミュレーターだけ。利用者の決定 2026-11-01、15 章の 2）を足した。U-7 にシミュレーターの NP2 → N42 → N40 → NP1、実機は今の NP2 → NP1 を書いた |
| UI C-1: N39 は早すぎる完了を捕まえられない（反映は数 ms で、バナーよりずっと前） | テストのコメントと UI テストの設計書 3.3 の N39 の行を直し、「完了は反映の後」を UT-28（`aChangeCompletesAfterItIsAppliedAndReadBack`、M144）の確かめとした |
| UI C-2（信頼する部分）: `pressSettingsRow` が押した直後に探して上へ送るだけ | 行ごとに、最初の送りの前にその行を約 2 秒待ち（`waitForExistence(timeout: 2)`）、12 回上へ送っても無ければ 1 回下へ戻して見てから諦めるようにした。ちょうど 1 つでなければ押さない（2 つ以上は押さずに投げる）のは同じで、実機で投げる確かめも変えていない。差分は scratchpad の `springboard-delta.patch`（今の作業ツリーからの差分。Codex のレビューに渡す）。新しいハッシュは 17.10 |
| UI C-3: Swift の API の設計書の T-16・T-19 の行と 13.2 の N40 の行が C6 の後の状態でない | T-19 に SA-05 と N40 を足し、T-16 から N40 を外した（C6 に移した）。13.2 の N40 の「C6 で測る」を 17.7 の 3 の 26.2 の結果にした |
| UI C-4: サンプルの `requestPermissionWithAppSettings` を `async` 版に替えた後の全体の実行が無い（N40 だけを流し直した） | 直しの後に、ハッシュを固定した使い捨ての写しで `--feature Notification` を 1 回流した（下の表） |

単体テストは 3 件増えた（`NotificationRepositoryUserInfoCheckTests` に 1、`NotificationCategoryQueueTests` に 1、`NotificationPresentationGateTests` に 1。`aDecidedStatusAnswersWithoutARequest` は引数が 5 から 15 になった）。名前を替えたのは 1 件（L-C6）。消したテストは無い。

壊して確かめたこと（`mutate_c6fix.py` で 1 つずつ使い捨ての写しに当てて該当の suite を流し、落ちることを見てから戻した。iPhone 16 / 26.2、Xcode 26.6。差分とログは scratchpad。番号は M154 に続ける。17.5 の表にも足した）:

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M155 | L-B1 | `update` が今の予約を消してから内容を作る（直す前の順） | `updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest` |
| M156 | L-C4 | 読み直しが識別子だけを見る（直す前の確かめ） | `theReadBackComparesTheWrittenCategory`（古い category・順の違い・options の違いの 3 件の確かめ） |
| M157 | L-C4 | 読み直しが options を見ない | `theReadBackComparesTheWrittenCategory`（options の違いの 1 件） |

3 件とも落ち、戻した版で通ることを確かめた（下の全件の実行）。UI テストの直し（U-C2）は壊して流していない（UI テストの変異はここまでも流していない）。

シミュレーターで測ったこと（使い捨ての写し。リポジトリには入れていない）:

| 測り | 結果 |
|---|---|
| L-B2: C6 の前の `NSNull`（HEAD `b80399eb` を写した版のサンプルに下調べのボタンを 1 つ足し、下調べの UI テストで流した。サンプルを消して入れ直し、権限のダイアログで Allow を押してから（通知の権限はこのシミュレーターのサンプルにだけ与えた）、`IosNotificationManager.shared.schedule` で `["k": NSNull(), "a": [1, NSNull()], "s": "plain"]` を 1 時間後に予約し、`getScheduled` で読み戻して消した。iPhone 17 / 26.2、Xcode 26.6） | `add` は成功（`isSuccess=true`、`errorMessage=nil`）。`getScheduled` は 1 件で、userInfo は `k` が `NSNull`、`a` が `[1, NSNull]`（`__NSCFNumber` と `NSNull`）、`s` が文字列。`NSNull` は保存されて、そのまま返った |
| L-C4: 本物の center での読み直しの比べ方（写しのテストのホストに下調べのテストを足し、`NotificationCategoryQueue.shared` で 2 つの category（アクション無し、および icon・options つきのアクション 2 つとテキスト入力のアクション 1 つ、category の options 3 つ）を毎回アクションを 1 つ替えて 10 回ずつ登録し、本物の center から読んで `isReadBack` と `isEqual` を見た。iPhone 17 / 26.2 と iPhone 16 / 18.3） | どちらの OS も `isReadBack` は 20/20 で真、`isEqual` も 20/20 で真。比べ方が本物の写しで誤った `.error` を出さない |

| 実行 | 結果 |
|---|---|
| 直しの途中の suite（userInfo の検査、category の列、gate、Manager の権限、`LibraryLogPrivacyTests`、2 つの UseCase、`async` 版、`IosNotificationManagerTests`。iPhone 17 / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`） | 9 suite・75 件が成功 |
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3。`-parallel-testing-enabled NO`。18.3 の 2 つは `arch=arm64`。Xcode 26.6） | どれも 540/540（537 + 3）。消したテストは無い |
| TSan（`-enableThreadSanitizer YES`、iPhone 17 / 26.2、Xcode 26.6） | userInfo の検査、列、gate、Manager の権限、`LibraryLogPrivacyTests`、category と権限の UseCase、`async` 版、`IosNotificationManagerTests`、一覧の型、エラー、印の 12 suite・92 件が成功。TSan の報告は 0 件 |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --feature Notification`（ハッシュを 17.10 の値に固定した使い捨ての写し。Xcode 26.6。写しは、ランナーの `TRUSTED_FILES` の 3 つのハッシュの行のほかは、作業ツリーの `ios/` と `scripts/` と同じことを流した前と後に確かめた） | 54 件すべて成功（権限の NP2・N42・N40・NP1、Navigation 2、IdentifierInventory 4、Notification 25、NotificationEvent 12、NotificationColdStart 7）。列挙の 124 件が宣言と一致した。基準との比べ合わせは `changed=0, added=12, removed=0`（17.8 と同じ 12 件）。`async` 版の `requestPermissionWithAppSettings` と U-C2 の `pressSettingsRow` で N40 が通った |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`） | 写し: 144/144。リポジトリ（固定の前）: 144 件のうち 5 件が落ちる（信頼する部分の 3 ファイルのハッシュが固定と違うことによる、17.8 と同じ 5 件）。リポジトリ（固定の後）: 144/144、`scripts/tests` の全体（`python3 -m unittest discover -s scripts/tests`）も 352/352 |
| 2 つの scheme の `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`。Xcode 26.3 と 26.6） | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| swiftinterface（17.6 と同じ組み方。Xcode 26.3） | `IosLibrary-after-1b-c6.swiftinterface` と同じ（差 0。足したのはログと internal の `isReadBack` だけ）。取り直していない |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2（`NSNull` の測り、読み直しの下調べ、UI テスト、TSan、全件）、iPhone 16 / 26.2（変異）、iPhone 16 / 18.3（読み直しの下調べ、全件）、iPad Pro 11-inch (M4) / 18.3（全件）は xcodebuild・`test_ios.sh` が起動し、最後に `simctl shutdown all` で止め、どれも起動していないことを確かめた。通知の権限は iPhone 17 / 26.2 の HEAD の版のサンプルにだけ（下調べの UI テストで Allow を押して）与え、そのサンプルは `test_ios.sh` の NP2 が消して入れ直した。実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない） |

信頼する部分は `Support/Springboard.swift` の U-C2 の差分だけを変えた。3 つのファイルの新しい値は 17.10（`SampleApp.swift` と `SystemLabels.swift` は変わらない）。この差分の Codex のレビューの後に、3 つのハッシュをリポジトリで固定した（ランナーの `TRUSTED_FILES` は、UI テストを流した写しと同じになった）。

## 20. C7 測りの記録と全体（T-20・T-21）

- 状態: 14 章の測りの記録（MS-11・MS-13 の残りと、18 章の 5 の無い添付を C7 で測った）、README・第 1 部・付録 A への反映（UI テストの設計書は C5 で書いたまま変えていない）、全体の実行と基準との比べ合わせ、棚卸しの `grep` の流し直し、ブリッジのテストとの対応の記録、UT-31 の組めない形の一覧、Xcode 26.3 での swiftinterface の型検査（3 つのスライス）、1b の結果のファイル（`results/2026-10-31-ios-c-abi-stage1b-result.md`）は済んだ。**コミットはしていない**
- 残るのは、利用者が Xcode の Organizer で作る MS-10 のプライバシーのレポート（20.9）と、実機が要るもの（20.10。どれも利用者の許可が要り、行っていない）
- ライブラリのコードは変えていない（swiftinterface は `after-1b-c6` と同じ。20.7）。変えたのはテストと文書だけ
- 測ったログ・下調べの写し・変異の差分は scratchpad に置き、リポジトリには入れていない。シミュレーターだけで、実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない）
- 環境: Xcode 26.6（17F113、Swift 6.3.3。`DEVELOPER_DIR` でコマンドごとに選んだ）と Xcode 26.3（17C529、Swift 6.2.4。`xcode-select` のまま）。シミュレーターは iPhone 17 / 26.2、iPhone 17 Pro / 26.2（MS-11・無い添付・変異）、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3

### 20.1 申し送りの当て方（C1〜C6 から C7 へ）

| 申し送り（出どころ） | C7 で行ったこと |
|---|---|
| MS-10 のプライバシーのレポート（2 章の 1、1.9） | コマンドラインでは作れないので、利用者が Organizer で作る手順を 20.9 に書いた。結果の行は空のまま |
| `.private` が伏せて見えること（2 章の 2、MS-13） | 実機が要る。2.0.0 の前の実機の区切りにまとめる決定のまま（20.10）。シミュレーターでは C7 でも平文で見えた（20.4） |
| G-6 の iPad の複数の window（5 章の 2） | 第 1 部 4.4 の G-6 と 5.13 の前面の定義、README 3.1 に書いた（複数の window の iPad は `.viewController(_:)` で表示元を渡す。マニュアルと C のヘッダーにも書く） |
| C1・C2 の TSan の skip（7.11、8 章の 4） | 外して全体の TSan の回で流した（20.5）。設計書 6.3.4・RK-11 を直した |
| MS-02 の Share の分（8 章の 5） | 第 1 部 G-6 に Share の分として書いた |
| MS-08（10.11、11 章の 5） | 第 1 部 5.13 の Clipboard の行と README 3.1 に書いた。前面での待ちの長さと実機での振る舞いは実機が要る（20.10） |
| MS-07・MS-14・SwiftUI の `App.init`（13.21 の C7 の行、15 章の 1） | README 4.1（`openSettingsFor` の行、`installDelegate()` の行）、第 1 部 1.3.3（SwiftUI の `App.init` の行を足した）・G-9・10 章、マニュアルの元（1b の結果の 6 章）に書いた。MS-14 はサンプルの試験の形の話なので、UI テストの設計書 3.3（C5 で書いた）のまま（1b の結果は 5 章で 20.3 の表を指すだけで、MS-14 の行は持たない） |
| N34b の番号（13.21 の C7 の行、15 章の 3） | UI テストの設計書 3.3 と設計書 13.2 の注（C5 で書いた）のまま残した。変えていない |
| `CompletionOnce`（14 章の 2） | 第 1 部 5.12.4 のコメントと表の行、P1-17 の (3) を「`@unchecked` は 1b では使っていない（`CompletionOnce` 自体は使い、`@unchecked` なしの `Sendable`。SDK が completion を `@Sendable` で取り込む）」に直した。同じく (4) も「`@unchecked` は 1b では使っていない（`RequestBox` と解放の見張り自体は使い、`@unchecked` なしの `Sendable`）」と書いた（1.4 の 1） |
| H2-1 の 18.3 の約 0.2 秒の窓（14 章の 1）、MS-12（14 章の 3） | マニュアルの元（1b の結果の 6 章）と第 1 部 G-9 |
| 付録 A の `@discardableResult`（15 章の 5、17.4 の 5、17.11） | `addListener(_:)` と `requestPermission(options:presenter:) async throws -> Bool` の宣言に足した |
| UT-31（17.11、18 章の 4） | 20.6。`openNotificationSettings()` を一覧に入れ、設計書 3.3 と README 4.1 に写した。UT-31 のテストのソース（組める形）が無かったので足した |
| README 4.1・移行の手引き（17.11、18 章の 1・6） | README 4.1 と設計書 3.3 に、同じ識別子の category の置き換え、`NSNull`・`NSURL` を拒むこと（C6 の前は通り、`getScheduled` も `NSNull` を返した）、`requestPermission(options:completion:)` の拒否の文言、`update` で添付を作れない（`attachmentLoadFailed`）ときに予約を消さないこと、UT-31 の形を足した（`update` の分は README 4.1 にだけ足し、設計書 3.3 には足していなかった。無いファイルの添付では `add` が失敗して予約が消えることと合わせて、22 章の直しで両方に書いた）。ほかの 17.3 の行（`errorMessage` の固定の文言、一覧の型、port の 2 つの変更、helper の deprecated）は README 4.1 に前からあった |
| 測り MS-04・MS-09（17.11） | 第 1 部 G-7 と 5.13 の設定の画面の行、README 3.1（MS-04）・4.1（MS-09） |
| 全体の実行（17.11） | 20.7 |
| 無い添付（17.11、18 章の 5） | 20.4 で測り、21 章の 1 に挙げた |
| 第 2 部（2a）への申し送り（7.11、10.11、17.11、18 章の 2） | 1b の結果の 7 章にまとめた |
| ブリッジ（13.21、17.11） | 変えていない（段階 3 で消す） |
| ブリッジのテストとの対応（設計書 13.1 の注） | 20.8。`parseContentNoSoundDefaultsToDefault` に当たる確かめが無かったので `NotificationContentTests` に足した |
| 棚卸しの `grep`（設計書 8.8.2、T-21） | 20.8 |
| D23 の simulator only（6 章の「残ること」） | 決まっていなかったので 21 章の 4 に挙げた |
| `sourceRect` の DocC の 1 文（5 章の 5） | 「C3 の Share と合わせて決める」のまま決まっていなかったので 21 章の 5 に挙げた |

### 20.2 変えたもの（リポジトリ）

| 区分 | ファイル | 中身 |
|---|---|---|
| テスト（TSan の skip） | `IosLibraryTests/Common/ReleaseWatchTests.swift`、`Dialog/AlertDialogPresenterTests.swift`、`Dialog/IosDialogManagerShownTests.swift`、`Common/Support/CommonTestSupport.swift` | `aRealViewControllerClosesTheBoxWhenFreed`・`theAlertAndItsObserversAreFreedAfterItCloses`（UT-14）・`aDialogDismissedFromOutsideCallsNothingButTheNewAPIIsTold` の `.disabled(if: isThreadSanitizerEnabled, …)` を外し、使う所の無くなった `isThreadSanitizerEnabled` を消した（20.5） |
| テスト（ブリッジのテストとの対応） | `IosLibraryTests/Notification/Domain/NotificationContentTests.swift` | `theSoundDefaultsToTheDefaultSound`（音を渡さない内容は `.default`。ブリッジの `parseContentNoSoundDefaultsToDefault` に当たる。M158） |
| テスト（UT-31） | `IosLibraryTests/Notification/Presentation/IosNotificationManagerCallFormTests.swift`（新） | `async` の関数の中で `completion` を書いた今の 7 つの口と `trigger` を書かない `show(content:)` が callback 版に決まり、完了が main で 1 回ずつ来る。同期の closure の中で `completion` を書かない今の 9 つの形が組めて callback 版に届く（M159・M160） |
| 文書 | `designs/2026-10-31-ios-c-abi-swift-api-design.md` | 3.3（UT-31 の 9 つの形、category の置き換え、`NSNull`）、6.3.4・RK-11（TSan）、13.1 の UT-31、付録 A の `@discardableResult` 2 つと注 |
| 文書 | `designs/2026-10-31-ios-c-abi-c-abi-design.md` | 改訂の行、1.3.3（SwiftUI の `App.init` の行）、4.4 の G-4・G-6〜G-9、P1-17 の (3)・(4)、5.11、5.12.4、5.13（前面の定義、設定の画面と Clipboard の行）、5.13.1、10 章 |
| 文書 | `README.md` | 状態の行、3.1（前面と iPad、Clipboard の同期の読み出し）、4.1（`openSettingsFor`、UT-31、category・userInfo・文言、`installDelegate()`）、5 章の 1b の行、8.6 のプライバシーの行、9 章 |
| 文書 | `results/2026-10-31-ios-c-abi-stage1b-result.md`（新） | 1b の結果 |
| 文書 | この記録 | 冒頭の行、20〜22 章 |
| 文書 | `artifact/README.md` | トピックの一覧の ios-c-abi の行（22 章の直し） |

信頼する部分（`scripts/ios_ui_runner.py` の `TRUSTED_FILES` と固定したハッシュ）、ランナー、サンプル、UI テスト、ライブラリのコードは変えていない。

### 20.3 14 章の測り（MS-01〜MS-14）の記録

| ID | 測った所 | 結果（要点） | 反映した所 |
|---|---|---|---|
| MS-01（G-4） | C2（4.7）、C3（7.7） | `UIAlertController` は `present` の中で `presentingViewController` が設定され（補いを残す）、coordinator があり、completion の中ではまだ落ち着いていない。同じ回の 2 つは 2 つとも出て 2 つ目が上。表示の途中の `dismiss` は無視されない。`UIActivityViewController` は戻った後にしか設定されない（Share は補いを外した） | 第 1 部 G-4（C7）。設計書 6.3.3 は C2・C3 で直した |
| MS-02（G-6） | C2（4.7）、C3（7.7） | inactive の間も Dialog と Share は出る。iPad の 2 つの scene で key window が 2 つ | 第 1 部 G-6・5.13、README 3.1（C7） |
| MS-03（G-7） | C2（4.7）、C3（7.7）、C7（20.5） | 外から閉じた Dialog 約 0.4 秒・Share 約 0.55 秒で解放、Share の handler は呼ばれない、UIKit が断ったシートは約 0.03 秒、handler は main、scene を切っても window が残れば解放されない。**TSan の版でも同じ**（C7 で全体の TSan の回を通した） | 第 1 部 G-7・5.13.1、設計書 6.3.4・RK-11（C7） |
| MS-04（G-7） | C6（17.7） | 後ろの `open` は `false`、後ろで未決の権限を求めると見えないままダイアログが出る | 第 1 部 G-7・5.13、README 3.1（C7） |
| MS-05（G-7・P1-22） | C5（13.7） | scene のアプリでも最初の `didBecomeActive` はコールドスタートの応答の後。18.3 は積んだブロックが遅れる | 第 1 部 G-7（C7）。実装は C5 |
| MS-06（R-23） | C5（13.7） | main の上の `DispatchQueue(label:).sync` の中で `assumeIsolated` は止まらない | 変わらない（第 1 部 1.3 のまま） |
| MS-07 | C5（13.17 の 1）、C6（17.7 の 3） | 26.2 で、求め直した形と新しく入れたアプリの形の両方で設定の App のリンクから `settingsRequests` が届く。18.3 は測っていない | README 4.1、第 1 部 10 章（C7） |
| MS-08 | C4（10.7） | 後ろでも自分の内容は読める。ほかのアプリの内容は後ろでもダイアログ。同期の読み出しは main を止める | 第 1 部 5.13、README 3.1（C7） |
| MS-09 | C6（17.7 の 1。RK-10 の測り） | 書き戻しの後の最初の読み直しで 60/60 反映（1〜4 ms） | README 4.1（C7）。実装は C6 |
| MS-10 | C1（1.9） | 署名なしのアーカイブは作れ、中のマニフェストは 8.8.2 のとおり。**レポートは未**（20.9） | - |
| MS-11（G-8） | C7（20.4） | 利用者の完了の中の `NSException` は巻き戻しを始めずに `abort` | 第 1 部 G-8・5.11（C7） |
| MS-12（G-9） | C5（13.7、16 章の B-4） | 入るが、測った版では起動のきっかけが決まらなかった。B-4 で `sharedApplication` の `nil` を active でないとみなす | 第 1 部 G-9・1.3.3（C7）、マニュアルの元 |
| MS-13 | C1（1.7）、C7（20.4） | `OSLogStore` は `.debug` を返さず `.private` を平文で返す。Release の `.debug` は保存されない。`log stream` に `.public` の行が出る。シミュレーターでは `.private` が平文。Xcode の GUI のコンソールは測っていない | 設計書 8.7.1 は C1 のまま（`libraryDebug`。2 章の 3） |
| MS-14 | C5（13.17 の 2） | システムが起こしたプロセスに `launchArguments` は渡らない。SA-18 のファイルで足りる | UI テストの設計書 3.3（C5） |

### 20.4 C7 で測ったこと

1. **MS-11**（G-8。利用者のコールバックの Objective-C の例外が Swift のフレームを越えるとき。iPhone 17 Pro / 26.2、Xcode 26.6、1 回）。使い捨ての写しのテスト（`ProbeMS11Tests`。リポジトリには入れていない）で、開始の前に取り消した要求の箱で `IosClipboardManager.shared.loadItem(.text, requestBox:completion:)` を呼び、ライブラリが main で呼ぶ完了（`CLIPBOARD_CANCELLED`）の中で `NSException(...).raise()` した。結果: 完了は main で呼ばれ、`raise` の直後に `*** Terminating app due to uncaught exception 'NtkProbeMS11'` と `libc++abi: terminating due to uncaught exception of type NSException` が出て、テストのホストは `EXC_CRASH`（`SIGABRT`、`Abort trap: 6`）で終わった。crash report の落ちたスレッドは `objc_exception_throw` → `__cxa_throw` → `failed_throw` → `std::__terminate` → `_XCTTerminateHandler` → `_objc_terminate` → `abort` で、**その下に利用者の closure とライブラリの `ClipboardBoxedLoad.report(_:)`・`finish` が残っていた**（巻き戻しを始めない。捕まえる所が無いので最初の探索で terminate に入る）。最初に投げた所のスタック（`First throw call stack`）には、ライブラリの `RequestBox.attach` の閉じたときの処理と `MainActor.assumeIsolated`、`_dispatch_main_queue_drain` が並んだ。XCTest の外のアプリでは `_XCTTerminateHandler` が無いだけで同じ経路の見込み。crash report は scratchpad に写し、Mac の `DiagnosticReports` から消した。C++ の例外は試していない（P1-16 の「振る舞いは定めない」は変えない）
2. **MS-13 の残り**（iPhone 17 Pro / 26.2、サンプルの Debug）。`log stream --level debug`（subsystem `com.jonghyunkim.nativetoolkit.IosLibrary`）を流しながらサンプルを起動すると、`.public` の値を補間した行（`[installDelegate] isMainThread: true` など）が出た（68 行）。Xcode のコンソールの代わりに `OS_ACTIVITY_DT_MODE=YES` を渡して `simctl launch --console-pty` で起動したが、ライブラリの行は標準出力にも標準エラーにも出なかった（Xcode 15 からの GUI のコンソールはデバッガーの経路で統合ログを読むので、コマンドラインでは同じものを作れない）。**Xcode の GUI のコンソールでの見え方は測っていない**（20.9 の手順の任意の 6 で頼む）。C1 の 1.7 で、`xcodebuild` から動かしたテストのプロセスでは `.error` が出力に出たことは確かめている
3. **無い添付で通知を出す**（18 章の 5。iPhone 17 Pro / 26.2 と iPhone 16 / 18.3、Xcode 26.3）。使い捨ての写しのサンプルから `app-icon-attachment.png` を消し、`ShowImmediateWithAttachment(AppIcon)` が消したファイルのあった所の URL（`Bundle.main.bundleURL` の下）を `NotificationAttachment` に渡すようにした。新しく入れて NP1 で権限を許し、N5 の代わりの下調べの UI テストで押した。結果（両方の OS で同じ）:

| 見たもの | 結果 |
|---|---|
| `UNNotificationAttachment(identifier:url:options:)` | 投げない（17.4 の 17 と同じ） |
| `UNUserNotificationCenter.add` | **失敗する**（`UNErrorDomain`、code `100`。`UNErrorCodeAttachmentInvalidURL`）。ライブラリの `.error` のログは `[show] identifier: sample-notification: the system did not add the request: domain=UNErrorDomain, code=100`（このログの行は scratchpad に残していない。残したのは下のサンプルの結果の行だけ） |
| ライブラリの結果 | `addRequestFailed(FailureDetail(domain: "UNErrorDomain", code: 100))`。サンプルの結果の行は `❌ [showImmediateWithAttachment] error: Failed to add the notification request.` |
| 通知 | **出ない**（10 秒待ってもバナーが無い）。`getDelivered` は 0 件 |

分かったこと: 無いファイルの添付は「添付なしで出る」のではなく、OS が要求ごと断り、通知は出ない。ライブラリは `attachmentLoadFailed` ではなく `addRequestFailed` で返す（どちらも 1b の前から同じ経路で、C6 で変わったのは文言が固定になったことだけ）。`update` では、今の予約を消した後の `add` で失敗するので、**今の予約が消えたまま新しい要求も足されない**（17.3 の「`add` 自体の失敗は消した後なので残らない」の場合に当たる）。**`update` のこの結論はコードから導いたもので、測ったのは `show` だけ**（`NotificationRepositoryImpl.update` は検査・内容と trigger を作った後に今の予約を消し、その後に `add` を呼ぶ。無いファイルは内容を作る所では失敗しないので、消した後の `add` で失敗する）。入口でファイルの有無を確かめるかは 21 章の 1（2026-11-01 に確かめると決まり、23.2 で直した）。写しは scratchpad に置いた

### 20.5 TSan の skip を外す（7.11、8 章の 4）

C1・C2 で見張りに頼るテストを TSan の回で skip していた 3 件（`ReleaseWatchTests.aRealViewControllerClosesTheBoxWhenFreed`、UT-14 の `AlertDialogPresenterTests.theAlertAndItsObserversAreFreedAfterItCloses`、`IosDialogManagerShownTests.aDialogDismissedFromOutsideCallsNothingButTheNewAPIIsTold`）の `.disabled` を外し、`IosLibraryTests` の全件を TSan で流した。UI テストの D20 と S19 は、サンプルを TSan で組んで `-only-testing` で流した（設計書 13.2 の D20 の「TSan の回では流さない」の確かめ）。

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件を TSan で（`-enableThreadSanitizer YES`、iPhone 17 / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`） | **543/543 成功、skip 0、TSan の報告 0 件**（約 128 秒）。外した 3 件も通った（`aRealViewControllerClosesTheBoxWhenFreed` 0.001 秒、`theAlertAndItsObserversAreFreedAfterItCloses` 1.6 秒、`aDialogDismissedFromOutsideCallsNothingButTheNewAPIIsTold` 1.3 秒） |
| D20・S19 を TSan で（サンプルの scheme を `-enableThreadSanitizer YES` で組み、`-only-testing` で 2 件。アプリに `libclang_rt.tsan_iossim_dynamic.dylib` が入ったことを確かめた） | 2/2 成功（D20 22 秒、S19 18 秒）。TSan の報告 0 件 |

外せたので、テストから `.disabled(if: isThreadSanitizerEnabled, …)` と `isThreadSanitizerEnabled` を消し、設計書 6.3.4（1b の結果の項）・UT-05・D20・RK-11 を直した。D20 の「TSan の回では流さない」は、`test_ios.sh` が TSan の回を持たないので、設計書の注だけを直した（UI テストのソースに TSan の分岐は無い）。申し送り 1 の雛形で TSan の版が解放しなかった理由は調べていない（`IosLibrary` の手順では起きない）。

### 20.6 UT-31（組めなくなる今の呼び出しの一覧。S-P26、17.4 の 2、18 章の 4）

`swiftc -typecheck` に、`async` の関数の中から今の口を `completion` を書かずに呼ぶ小さなファイル（scratchpad の `forms.swift`）を渡した。`IosLibrary` は C7 の作業ツリーを Xcode 26.6 と 26.3 で組んだもの（シミュレーター、Debug）。Swift 6 と Swift 5 の言語モードで同じ結果だった。

| # | 形（`async` の関数の中） | 結果 | エラー |
|---|---|---|---|
| 1 | `manager.setBadgeCount(1)` | 組めない | `call can throw, but it is not marked with 'try'`（`try await` が要る） |
| 2 | `manager.registerCategory(category)` | 組めない | `expression is 'async' but is not marked with 'await'` |
| 3 | `manager.removeCategory(identifier:)` | 組めない | 同上 |
| 4 | `manager.show(content:trigger:)`（`trigger` を書く） | 組めない | `try` が要る |
| 5 | `manager.update(identifier:content:trigger:)` | 組めない | 同上 |
| 6 | `manager.schedule(content:trigger:identifier:)` | 組めない | 同上 |
| 7 | `manager.requestPermission()`（引数なし） | 組めない | 同上（`presenter` の既定で `async throws` 版に決まる） |
| 8 | `manager.requestPermission(options:)` | 組めない | 同上 |
| 9 | `manager.openNotificationSettings()`（引数なし） | 組めない | 同上（17.4 の 2） |
| 10 | `Task { await …; manager.setBadgeCount(1) }`（`await` を含む closure） | 組めない | 1 と同じ |
| 11 | `Task { manager.setBadgeCount(1) }`（`await` を含まない closure） | 組める | -（closure が `async` にならず、callback 版に決まる） |
| 12 | `manager.show(content:)`（`trigger` を書かない） | 組める | -（`async` 版に `trigger` の既定が無い） |
| 13 | `completion` を書いた形（`setBadgeCount`・`registerCategory`・`requestPermission(options:completion:)`・`show`） | 組める | - |
| 14 | 同期の関数の中の `openNotificationSettings()`・`registerCategory(_:)` | 組める | - |
| 15 | `getScheduled { … }`（前から `completion` が要る口） | 組める | - |

黙って意味が変わる形は無い（組めるものは今の callback 版に決まる）。この一覧を設計書 3.3 と README 4.1 に写した。Share・Dialog・Clipboard の今の口は、同じ名前の `async` 版を 1b で足していない（Share の `async` 版は前からあり、`presenter` を既定つきで足しただけ）ので、この形の破壊は無い。

UT-31 のテストのソース（設計書 13.1「組める形を置く」）は無かったので `IosNotificationManagerCallFormTests` を足した（20.2）。

### 20.7 全体の実行と基準との比べ合わせ

| 実行 | 結果 |
|---|---|
| `IosLibraryTests` の全件（iPhone 17 / 26.2、iPhone 16 / 18.3.1、iPad Pro 11-inch (M4) / 18.3.1。Xcode 26.6、`-parallel-testing-enabled NO`。18.3 の 2 台は `-destination 'platform=iOS Simulator,id=<udid>,arch=arm64'`） | どれも **543/543 成功**、skip 0（C6 の 540 + C7 の 3）。消した・名前を替えたテストは無い |
| TSan | 20.5（543/543、報告 0 件。D20・S19 も通った） |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2>`（全体。リポジトリのまま、Xcode 26.3、`--baseline` なし。信頼する部分のハッシュは固定のとおりで、閉じた形のソースの規則も通った） | **678 件: 成功 677、skip 1**（skip は基準と同じ意図した `ClipboardUITests/testU10b_namedPasteboardAfterProcessTermination`。M-08 がこの環境では決まらない）。内訳（`results.jsonl` の 678 行）: `IosLibraryTests` 543/543、`IosLibraryExampleTests` 10/10、UI テスト 124 件（列挙が `DeviceRequirements.json` とちょうど一致し、simulator only を含めて 0 件を除いた。権限 4（NP2 → N42 → N40 → NP1）、Navigation 2、IdentifierInventory 4、Dialog 23、Notification 25、NotificationEvent 12、NotificationColdStart 7、Share 19、Clipboard 21 + skip 1、ClipboardPaste 5、ClipboardPasteDeny 1）、ボタンの網羅の 1 行（`IosLibraryExampleUITests#buttonCoverage`。69 ボタン、102 テスト。成功）で、543 + 10 + 124 + 1 = 678。成功の 677 はボタンの網羅の 1 行を含む（UI テストは 123 件が成功、1 件が skip）。約 1 時間 55 分 |
| 基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`。0g の後の 320 件）との比べ合わせ | **`changed=0, added=361, removed=4`**。終了の値は 1 で、理由は removed の 4 件（基準で通ったテストが流れなかった）だけ。4 件はどれも 1b で名前を替えた・消したと記録したもの: `IosDialogManagerTests/showLoginDialogFailsThroughOnLoginOnTheMainThreadExactlyOnce`（C2 で `…ThroughCompletion…` に替えた。4.5）、`ShareErrorTests/presentationFailedDescriptionContainsUnderlyingMessage`・`unknownDescriptionContainsUnderlyingMessage`（C3 で消した case の確かめ。7.5）、`NotificationPermissionHelperTests/requestPermissionThrowsPermissionDeniedWhenFailed`（C6 で `…WhenDenied` と port のエラーの件に分けた。17.5）。changed は 0（基準で通ったテストで、結果が変わったものは無い） |
| 機能ごとの差（UI テスト） | Dialog: 足した 8（D16〜D23）、変えた 0、消した 0（D12 は C2 で期待値を変え、基準の名前のまま通った）。Notification: 足した 12（N34b・N38 は `NotificationUITests`、N35・N39・N41・N43・N44 は `NotificationEventUITests`、N36・N37・N45 は `NotificationColdStartUITests`、N40・N42 は `NotificationPermissionUITests`）、変えた 0、消した 0。Share: 足した 3（S17〜S19）、変えた 0、消した 0。Clipboard: 足した 2（CB5・CB6）、変えた 0、消した 0。共通（Navigation・IdentifierInventory）: 差なし。UI テストの合計は 99 → 124 |
| 機能ごとの差（単体テスト） | 足した 336（C1〜C7 の単体テスト。`IosLibraryTests` は 211 → 543）、消した 4（上の表）、変えた 0。`IosLibraryExampleTests` は 10 で差なし |
| ランナーの自己テスト（`python3 -m unittest discover -s scripts/tests -p 'test_ios_ui_runner.py'`。リポジトリ） | 144/144 |
| `scripts/tests` の全体（`python3 -m unittest discover -s scripts/tests`。リポジトリ） | 352/352（OK） |
| 2 つの scheme の clean・whole-module のビルド | 20.13（警告 0） |
| swiftinterface | Xcode 26.3 で C7 の作業ツリーを C1〜C6 と同じ組み方（Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`）で組んだ `arm64-apple-ios.swiftinterface` は `IosLibrary-after-1b-c6.swiftinterface` と 1 文字も違わない（公開面は変わらないので取り直していない）。Xcode 26.6 で組んだ 3 つのスライス（`arm64-apple-ios`、`arm64-apple-ios-simulator`、`x86_64-apple-ios-simulator`）の public と private の 6 つを、Xcode 26.3（Swift 6.2.4）の `swift-frontend -typecheck-module-from-interface`（`-sdk` に各 SDK、`-F` に組んだ framework の置き場）で型検査し、6 つとも終了 0、出力 0 行（型つきの throws の `throws(IosLibrary.NotificationError)` 3 か所と `nonisolated(nonsending)` を含む。SR-15）。型を壊した写し（`NotificationError` を無い型に）では 8 件のエラーで落ちることも確かめた |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2（全件・TSan・UI）、iPhone 17 Pro / 26.2（MS-11・MS-13・無い添付・変異）、iPhone 16 / 18.3.1（単体テスト・無い添付）、iPad Pro 11-inch (M4) / 18.3.1（単体テスト）は xcodebuild・`simctl`・`test_ios.sh` が起動し、最後に `simctl shutdown all` で止め、どれも起動していないことを確かめた。iPhone 17 Pro / 26.2 と iPhone 16 / 18.3.1 には、無い添付の下調べの写しのサンプル（添付のファイルを消した版。通知の権限を許した）が入ったまま（次の UI テストの回が入れ直す）。実機には触れていない |

### 20.8 棚卸しとブリッジのテストとの対応

**理由の申告が要る API の棚卸し**（設計書 8.8.1 の `grep` を C7 の作業ツリーで流し直した。T-21）: ファイルの時刻は `Clipboard/Data/File/ClipboardTemporaryFileStore.swift` の `.contentModificationDateKey` の 2 か所だけで、増えていない（行は C4 の `discardUndelivered` の追加で 116・120 にずれた）。システムの起動からの時間・ディスクの空き・有効なキーボード・`UserDefaults` は 0 件。`PrivacyInfo.xcprivacy` は `plutil -lint` で OK。

**ログの秘密の値の `grep`**（T-02 の照合を流し直した）: 秘密の値の名前を含む補間で `LogRedaction`・長さ・件数を通さないものは、Dialog の題と本文（`.private`。設計書 8.7.2 で出してよい値）と、`NotificationRepositoryImpl.open(_:)` の設定の画面の URL（system の定数の `openNotificationSettingsURLString`。`.public`）だけ。ライブラリに `Log.d` などの呼び出しは 0 件。`print(` は `ios/IosLibrary/IosLibrary` の下に 19 行（`grep -rn 'print('`）: Swift のソースの DocC の例 9 行（`IosNotificationManager.swift` 2、`IosDialogManager.swift` 5、`IosShareManager.swift` 2）、deprecated の `Log` の中身 4 行（`Common/Log.swift:48,56,64,72`。S-P21 で中身は `print` のまま）、`IosLibrary.docc/IosLibrary.md` の例 6 行。ライブラリが自分で出すログに `print` は無い。

**ブリッジのテスト（`results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md` の 83 件）との対応**（設計書 13.1 の注）:

| ブリッジのテスト | 件数 | `IosLibrary` での扱い |
|---|---|---|
| `UnityIosClipboardJsonParserTests` | 25 | 書き直さない。JSON の解析と組み立てで、移すロジックが無い（README 1.2。JSON は捨てる） |
| `UnityIosNotificationJsonParserTests` | 40 | 39 件は書き直さない（同上）。省いた JSON の鍵の既定（`repeats`・`notifyOnEntry`・`notifyOnExit`・`interruptionLevel` など）はブリッジの解析の決まりで、C ABI では 0 で埋めた構造体の意味として第 2 部で決める（設計書 8.9 の「既定の値」）。**`parseContentNoSoundDefaultsToDefault` だけはライブラリの既定（`NotificationContent` の `sound` の既定 `.default`）に当たり、`NotificationContentTests` に確かめが無かった**ので `theSoundDefaultsToTheDefaultSound` を足した（M158） |
| `UnityIosShareJsonParserTests` | 7 | 書き直さない（JSON） |
| `UnityIosShareManagerTests` | 1 | 書き直さない。不正な JSON で handler が main で 1 回、はブリッジの入口の約束で、C ABI のテスト（2b）が受け持つ。`IosShareManager` の完了が main で 1 回は UT-13 が守る |
| `UnityIosClipboardManagerCallbackContractTests` | 9 | C ABI のテスト（2b）で置き換える（main で 1 回、不正な要求も 1 回）。`IosClipboardManager` の完了の約束は今の `IosClipboardManagerTests` と UT-30 が守る |
| `UnityIosPluginTests.example` | 1 | 空のテンプレート。対応なし |

設計書 13.1 の件数（Clipboard 26、Notification 41、Share 7）は、記録の数（25・40・7 と、Share のマネージャー 1）と少し違う。記録の表のほうに合わせた。

### 20.9 MS-10: 利用者に頼む手順（プライバシーのレポート）

レポートは Xcode の Organizer の「Generate Privacy Report」でしか作れない（1.9）。2 章の 1 の決定のとおり、利用者に 1 回作ってもらう。Mac の上だけの作業で、実機は使わない。

1. ターミナルでリポジトリの直下に移り、署名なしのアーカイブを作る（C1 の 1.9 で警告 0 件で通った形）:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer xcodebuild archive \
     -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryExample \
     -destination 'generic/platform=iOS' \
     -archivePath ~/Library/Developer/Xcode/Archives/ntk-1b-privacy/IosLibraryExample.xcarchive \
     CODE_SIGNING_ALLOWED=NO
   ```

2. 最後に `** ARCHIVE SUCCEEDED **` が出たことを確かめる
3. Xcode 26.6 を開き、メニューの「Window」→「Organizer」を選び、左の「Archives」で `IosLibraryExample` の今日のアーカイブを選ぶ（一覧に無ければ、Finder で `~/Library/Developer/Xcode/Archives/ntk-1b-privacy/IosLibraryExample.xcarchive` をダブルクリックすると Organizer に足される）
4. アーカイブの行を Control キーを押しながらクリック（右クリック）し、「Generate Privacy Report」を選ぶ。保存先を聞かれたら、リポジトリの外（デスクトップなど）を選ぶ。PDF ができる
5. PDF を開き、次を見る: (a) `IosLibrary.framework` の節があるか、(b) その中に「File Timestamp」（ファイルの時刻）と理由「C617.1」があるか、(c) トラッキングと集めるデータが無いか、(d) ほかに出た節（サンプル自身など）とその中身
6. （任意。MS-13 の残り）同じ Xcode でサンプルの scheme `IosLibraryExample` を iPhone 17（iOS 26.2）のシミュレーターで実行（Run）し、下のデバッグのコンソールに `IosLibrary` の行（例 `[installDelegate] isMainThread: true`）が出るかを見る。Dialog の画面で何かの Dialog を出したときに、その題が平文で見えるか（シミュレーターでは `.private` も平文で見える見込み）も見る
7. 後片付け: Organizer でそのアーカイブを選んで削除する（または Finder で `ntk-1b-privacy` のフォルダーを消す）。PDF はリポジトリに入れない

知らせてほしいこと: 1 の成否、5 の (a)〜(d)（できれば PDF の `IosLibrary` の部分の文面）、6 を行ったならその結果。結果はこの表に書く。

| 項目 | 結果 |
|---|---|
| アーカイブ（手順 1・2） | |
| レポートを作れたか（手順 4） | |
| `IosLibrary.framework` の節と FileTimestamp・C617.1（手順 5 の (a)(b)） | |
| トラッキング・集めるデータ（手順 5 の (c)） | |
| ほかに出た節（手順 5 の (d)） | |
| Xcode のコンソール（手順 6、任意） | |

作れなければ、設計書 3.5 の代わりの道（`unity-native-plugin` の agent の Release のアーカイブで確かめる。1a-4）に移る。

### 20.10 実機が要るもの（利用者の許可が要る。C7 では行っていない）

| 項目 | 行うこと | 出どころ |
|---|---|---|
| `.private` の見え方（MS-13） | 実機（iPhone XS / 18.7.2）でサンプルを動かし、Mac の Console.app で subsystem `com.jonghyunkim.nativetoolkit.IosLibrary` を見て、Dialog の題などの `.private` の値が `<private>` と伏せて見えることを確かめる | 2 章の 2（2.0.0 の前の実機の区切りにまとめる決定） |
| MS-08 の前面での待ちと実機での振る舞い | 実機で、前面と後ろで Clipboard の同期の読み出しと非同期の読み込みをほかのアプリの内容で呼び、貼り付けのダイアログと main の止まり方を見る（クリップボードを読む操作なので、毎回の許可が要る） | 11 章の 5（C7 か第 2 部の設計の前に 1 回。11 章の「2a」は第 2 部の設計を指す） |
| 1b で足した UI テストの実機の回と、実機の基準の取り直し | `scripts/test_ios.sh --dry-run --device-allow …` で選ばれるもの（1b で足した区分の無いもの・`systemui`・`sharesheet`・`clipboard` のテスト。simulator only の 9 件は選ばれない）を流し、0g の実機の基準（60 件）と比べる | 設計書 13.4、`agent-rules/device-testing.md` |
| 0c からの実機の残り | `clipboard`・`files`・`reinstall`・`credentials` の 39 件と、人の確認の手順書（HC1・HC4・HC7・HC8） | README の状態の行 |
| 配布用の署名 | Distribution のアーカイブと Organizer の Validate App で、2 つの framework がアプリの証明書で署名し直されることを確かめる（2b の後の dist で） | README 9 章の 1 行目（D-18） |

### 20.11 1b の DoD（設計書 17 章）

| DoD | 状態 |
|---|---|
| 6.1 のファイルと可視性、付録 A の宣言があり、8 章の振る舞い、6.2 のスレッド、取り消しの契約と一致している | 済み（C1〜C6 の各章の付録 A との照合。C7 で付録 A に `@discardableResult` を 2 つ足して実装と一致させた） |
| `PLANNED_SYMBOLS_EXEMPT` の名前を実装と照合した | 済み（各章の公開 API の照合） |
| 5.1 のロジックがすべて `IosLibrary` にあるか、C ABI / 包みの受け持ちと決めている（7 章） | 済み（C2〜C6。20.8 のブリッジのテストの対応） |
| 5.2 の README 1.4 の不備が直っているか、3.4 に理由つきで残している | 済み |
| `ios.md` に 4.2 の 4 つの書き足しがあり、UT-15 が通る | 済み（C1、UT-15 は全件の実行で通る） |
| `PrivacyInfo.xcprivacy` があり、棚卸しと一致し、アーカイブのプライバシーのレポートで確かめた（MS-10） | **一部**: マニフェストと棚卸しは済み（20.8）。**レポートは利用者の手順待ち（20.9）** |
| 13 章のテストがシミュレーターで通り、全件が 0g の後の基準と同じ（足したテストと変えた期待値は理由を記録）。足したテストは壊すと落ちることを確かめた | 済み（20.7。単体テストは 3 台と TSan で 543/543、全体の実行は 678 件（`IosLibraryTests` 543、`IosLibraryExampleTests` 10、UI テスト 124、ボタンの網羅の 1 行）のうち 677 成功・意図した skip 1。基準との差は足した 361 と、名前を替えた・消したと記録した 4 件だけで、変わった結果は 0。足したテストは C1〜C7 の各章で壊して確かめた（M1〜M160）） |
| 14 章の MS-01〜MS-14 を記録し、決まりが変わるものを README と第 1 部に反映した | **一部**: MS-10 のレポートの結果だけが空（20.3・20.9） |
| 第 1 部 9.1 の S-1〜S-16 を 11 章の表で確かめた | 済み（設計書 11 章。各コミットの照合） |
| Xcode 26.6 で組んだ `IosLibrary` の swiftinterface を、利用者の下限の Xcode 26.3 で 3 つのスライスとも読めた（型つきの throws を含む） | 済み（20.7） |
| UT-31 の組めなくなる呼び出しの一覧を 3.3 と移行の手引きの元に写した | 済み（20.6） |
| README の 4 章・4.1・5 章の 1b の行・8.6・9 章を直した（18.2） | 済み（18.2 は設計の決定のとき、C7 で 1b の結果を足した） |

1b の DoD の外で残るもの: 20.10 の実機の項目、21 章の決定。

### 20.12 壊して確かめたこと（番号は M157 に続ける）

使い捨ての写し（scratchpad）に当てて該当の suite を流し、落ちることを見てから戻した。iPhone 17 Pro / 26.2、Xcode 26.6。

| # | 対象 | 壊し方 | 落ちたテスト |
|---|---|---|---|
| M158 | ブリッジのテストとの対応（`NotificationContent` の既定） | `sound` の既定を `nil` にする | `theSoundDefaultsToTheDefaultSound`（`Expected .default sound when omitted, got nil`） |
| M159 | UT-31（設計書 13.1「`completion` の既定の `nil` を外す」） | `setBadgeCount(_:completion:)` の `= nil` を外す | テストのターゲットが組めない（`IosNotificationManagerCallFormTests` の同期の closure の `setBadgeCount(2)` が `async` 版に決まり、`'async' call in a function that does not support concurrency`）。ほかのテストのソースでは捕まらなかった |
| M160 | UT-31 | `registerCategory(_:completion:)` の `= nil` を外す | 同じく組めない（`registerCategory(self.category)`）。22 章の流し直しでは、C6 の `NotificationCategoryQueueTests` の同期の closure の `registerCategory(category("b"))`（329 行）が先に捕まえた。その呼び出しに `completion: nil` を書いた写しでも `IosNotificationManagerCallFormTests` が捕まえた |

TSan の skip を外した 3 件は、テストそのものは C1・C2 で壊して確かめている（M5・M16〜M18 など）。UI テストの変異は流していない（C5・C6 と同じ）。

### 20.13 警告

| 測り方 | 結果 |
|---|---|
| 2 つの scheme（`IosLibrary`、`IosLibraryExample`）を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`）。Xcode 26.3 と 26.6（`DEVELOPER_DIR`）。C7 のテストを足した後の作業ツリー | 4 つともエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| `IosLibrary` の Release（Xcode 26.6 の `generic/platform=iOS` と `generic/platform=iOS Simulator`、Xcode 26.3 の `generic/platform=iOS`。`CODE_SIGNING_ALLOWED=NO`） | エラー 0、警告 0 |

`ios/UnityIosPlugin`（ワークスペースの外）は組んでいない（C1 と同じ）。

## 21. 利用者に決めてもらうこと（C7）

**決定（2026-11-01、利用者）: 1〜6 は推奨のとおり。** 1 は入口でファイルの有無を確かめる形にし、無ければ `attachmentLoadFailed(identifier:detail:)` で何も足さず消さない。`detail` は `NSCocoaErrorDomain` の `NSFileReadNoSuchFileError`（260）にする（推奨の文の `NSFileNoSuchFileError` でも、OS と同じ `UNErrorDomain` の 100 でもない。23 章）。2 は C7 のコミット `75881825` の後に、シミュレーターの基準を取り直す。1 回目（2026-11-01 21:03〜23:10、`75881825`）は、同じ時間に別のシミュレーターでテストが動いていてホストの負荷が高く（15 分の平均で 47）、UI テストの N9・N32・N33 が失敗したので、ランナーは基準を保存しなかった。ほかに何も動かさずに Notification だけを流し直す（23:11〜23:59、`--feature Notification`）と、N9・N33 は通り、N32 はまた同じ所（`NotificationColdStartUITests.swift:149`、launch が `true`）で失敗した。原因と直しは 23.3（N32・N33 の待ちを足した）。2 回目（2026-11-02 22:26〜11-03 00:22、`4ea74702`、ほかは何も動かしていない）は全件が通り、基準を保存した（23.3）。3・4・6 は推奨のとおり。5 は DocC に足し（コメントだけ。23 章）、マニュアル（段階 4）にも書く

| # | 事柄 | 推奨 |
|---|---|---|
| 1 | 無いファイルの添付（20.4 の 3）。`UNNotificationAttachment` は投げず、`add` が `UNErrorDomain` の 100 で断り、通知は出ない。ライブラリは `addRequestFailed` で返す。`update` では今の予約を消した後に `add` が失敗するので、予約が消えたまま新しい要求も足されない。入口（`makeUNAttachment` の前）でファイルの有無を確かめるか | **確かめる形にする（第 2 部の設計の前の小さなコミットで。入口で `FileManager.fileExists` が偽なら `attachmentLoadFailed(identifier:detail:)` で何も足さず消さない）**。理由: 18 章の 5 で入口の確かめを取らなかった理由（今の利用者で添付なしで出ていた通知が出なくなりうる）は当たらない（今も出ない）。添付の失敗が決まった case になり、`update` が予約を消さない（L-B1 と同じ向き）。C ABI の利用者にも決まった失敗を返せる。逆の考え: 確かめから `add` までの間にファイルが消えれば今と同じ `addRequestFailed` になる（確かめは近道で、守りの全部ではない）。`detail` に入れる domain と code（`NSCocoaErrorDomain` の `NSFileNoSuchFileError` か、OS と同じ `UNErrorDomain` の 100 か）を決める必要があり、1b の「今の動作を変えない」の外の変更になる。変えないなら、今の形（`addRequestFailed`、`update` で予約が消える）を DocC・マニュアルに書く |
| 2 | 基準の取り直し。シミュレーターの基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）は 0g の後のもの（320 件）で、1b で足したテストがすべて「足した」に出る。1b で名前を替えた・消した 4 件が「基準で通ったのに流れなかった」になり、全体の実行の `test_ios.sh` は終了の値 1 で終わる（20.7） | **C7 のコミットの後に、そのコミットの作業ツリーで `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --baseline` を 1 回流して取り直す**（シミュレーターだけで、許可は要らない）。2a 以降の差を 1b の後から見られる。逆の考え: 実機の基準（60 件）は取り直せないので、2 つの環境の基準の時点がずれる。実機は 20.10 の実機の回で取り直す |
| 3 | 20.10 の実機の項目をいつ行うか | **MS-08 の前面と実機の振る舞い、1b の UI テストの実機の回と実機の基準の取り直しを、第 2 部の設計の前に 1 回の実機の回にまとめる**。MS-08 の結果は第 2 部の C のヘッダーの文言に効くため。**`.private` の見え方は、2 章の 2 の決定のとおり 2.0.0 の前の実機の区切り（DoD）の 1 回で見る**（この回に移さない。移すなら 2 章の 2 の決め直しで、利用者が決める）。配布用の署名と 0c の残りの 39 件も、決まっているとおり 2b の後（2.0.0 の前）。どれも始める前に利用者の許可を得る。逆の考え: 実機の回を 2b の後（2.0.0 の前）の 1 回にまとめれば、私物の実機を使う回が 1 回減り、capi のログ（P1-18。2b で初めて出る）の `.private` も同じ回で見られる。ただし MS-08 の結果を第 2 部のヘッダーに入れられず、2b の後に文言を直すことになる |
| 4 | D23（iPad のアクションシート）が `SIMULATOR_ONLY_TESTS` にある（6 章の「残ること」）。D23 はアクションシートを出して選ぶだけで、実機でも私物に触れない | **このまま（simulator only）にする**。設計書 13.2 の環境が「iPad のシミュレーター」で、実機（iPhone XS / 18.7.2）ではアクションシートが popover にならず確かめの意味が薄い。外すなら設計書 13.2 と UI テストの設計書 6.3 の 3、ランナーの表と自己テストを直す。逆の考え: D23 は私物に触れないので外しても危険は小さく、外せば実機の回でも Dialog のアクションシートを選ぶ確かめが 1 件増える。ただし実機では popover にならないので、確かめるのは iPad の基点でなく選択だけになり、D6（アクションシートの選択。設計書 13.2 の D23 は D6 と SA-01 を iPad で流すもの）と重なる |
| 5 | Dialog の今の口の `sourceRect` の DocC（5 章の 5）。iPad で `sourceRect` を渡さないと `sourceView` 全体を基点にし、大きな view では選択肢の無い popover になる（1b の前から）。DocC に書くかは「C3 の Share と合わせて決める」のまま決まっていない | **DocC の `sourceRect` の説明に「`nil` は `sourceView` の bounds 全体。iPad で画面全体の view を渡すと置き場が無いので、点に近い矩形を渡す」を足す（第 2 部の設計の前の小さなコミットで。コメントだけ）。マニュアル（段階 4）にも書く**。Share は基点をライブラリが view の中央に付けるので同じ問題は無い（7.4 の 9）。逆の考え: 今の口の動作は変えないので、DocC だけ直しても既存の利用者は気づかない。サンプルは C2 で中央の点に直した |
| 6 | C ABI から表示元を渡す口（22 章で足した。README 3.1・8.6、第 1 部 G-6、1b の結果 7 章の「iPad の表示元」）。第 1 部の P1-11 の C で「C ABI の受け口は新しい定義の前面を選んで渡すだけ」と決めた。1b の G-6 で、複数の window の iPad では key window が 2 つになり、前面の探し方がどちらの window を選ぶかは決まらないと分かった（5 章の 2）。Swift の利用者は `.viewController(_:)` で表示元を渡せるが、C ABI の利用者には選ぶ手段が無い | **2.0.0 の C ABI には足さない（P1-11 の C のまま）。第 2 部のヘッダーとマニュアル（段階 4）に「複数の window を開ける iPad では、どちらの window に出すかは決まらない」と書く**。理由: C ABI の主な利用者の Unity の iOS のアプリは 1 つの window で動く見込みで（確かめていない）、複数の window を開ける構成は少ない。足すなら `UIViewController` か `UIWindowScene` のポインタを C で受けることになり、寿命（いつまで有効か）と、受けたものがまだ window にあるかの確かめを第 2 部で新しく決める必要がある。要求の構造体は `struct_size` の規則で後から項目を足せる（P1-13 と同じ考え）。逆の考え: 足せば、複数の window の iPad で C ABI の利用者も出す window を選べ、Swift の利用者と同じ道ができる。後から足すと、ヘッダーの「決まらない」の文言と利用者のコードの両方を直すことになる。**足すなら P1-11 の決め直しになり、それは利用者が決める**（口の形は第 2 部の設計で決める） |

## 22. C7 のレビューと直したこと

C7 の未コミットの変更（文書とテスト）のレビュー（文書の観点と、テストのコードの観点。scratchpad の `c7review-docs`・`c7review-tests`）の指摘を直した。指摘はどれも文書の書き方とテストの確かめの細かさで、ライブラリのコード、信頼する部分（`scripts/ios_ui_runner.py` の `TRUSTED_FILES` とハッシュ）、ランナー、サンプル、UI テストは変えていない。21 章の 3 は 2 章の 2 の決定に戻し、C ABI から表示元を渡す口を新しい決定待ち（21 章の 6）に挙げた。

| 指摘 | 直したこと |
|---|---|
| 1: 1b の結果 7 章の「例外」の行が、利用者のコールバックの例外は一般に巻き戻さずに `abort` すると読める。測ったのは `NSException` だけ（20.4 の 1。C++ の例外は試していない） | 1b の結果 7 章の行と 5 章の「例外」を、「`NSException` は巻き戻しを始めずにその場で `abort` した（MS-11、1 回。C++ の例外は試していない）」に絞った |
| 2: README 4.1 と 1b の結果 6 章が、`update` は添付の失敗で予約を残すと読める。無いファイルは `UNNotificationAttachment` でなく `add` で失敗し（`UNErrorDomain` の 100 → `addRequestFailed`）、そのときは今の予約を消した後（`NotificationRepositoryImpl.update`）。設計書 3.3 には `update` の行が無い（20.1 は足したと書いていた） | README 4.1、1b の結果 6 章、設計書 3.3（行を足した）に「添付を作れない（`attachmentLoadFailed`）ときは残る。無いファイルは `add` が断り（`addRequestFailed`）、予約は残らない（21 章の 1）」を書いた。20.1 の行に、設計書 3.3 には足していなかったことを書いた。20.4 の 3 に「`update` の結論はコードから導いた。測ったのは `show` だけ」を足した |
| 3: 「678 件: 成功 677、skip 1」の内訳が無い | 20.7、20.11、1b の結果 1 章・4 章、README 5 章の 1b の行に、678 = `IosLibraryTests` 543 + `IosLibraryExampleTests` 10 + UI テスト 124 + ボタンの網羅の 1 行（`results.jsonl` の `IosLibraryExampleUITests#buttonCoverage`）で、成功の 677 はこの 1 行を含むことを書いた（数は変えていない） |
| 4: 1b の結果 6 章（マニュアルに書くと決めたもの）に、決まっていない `sourceRect` の行がある | その行と、無い添付・iPad の表示元の行に**決定待ち**を書き、表の前の文に「決定待ちの行は 21 章の決定で決まる」を足した |
| 5: README 3.1 と第 1 部 5.13 が「C ABI の利用者も表示元を渡す」と読める。P1-11 の C では C ABI は前面を探すだけで、C の表示元の口は未決（第 1 部 G-6、1b の結果 7 章） | README 3.1 を「C ABI は前面を探すだけ（P1-11 の C）で、複数の window の iPad ではどちらの window に出すかは決まらない。Swift の利用者は `.viewController(_:)` で渡せる。C の口を足すかは第 2 部で決める」にした。第 1 部 5.13 の前面の定義と G-6、1b の結果 5 章・6 章・7 章も同じ向きに直した。21 章の 6（推奨と逆の考え、P1-11 の決め直しは利用者が決めること）と README 8.6 の行を足した |
| 6: 21 章の 3 が、`.private` の確かめを第 2 部の設計の前の実機の回に移し、2 章の 2 の決定（2.0.0 の前の実機の区切りで 1 回）を黙って変えていた | `.private` は 2 章の 2 のとおり 2.0.0 の前に戻し、移すなら決め直しだと書いた。逆の考え（2b の後の 1 回にまとめれば実機の回が減り、capi のログ（P1-18。2b で初めて出る）も見られる）を足した |
| 7: 第 1 部 P1-17 の (3)・(4) と 20.1 の「1b では使っていない」が、`CompletionOnce`（`NotificationDelegateRouter.swift` で使う）や要求の箱・解放の見張りを使っていないと読める | 「`@unchecked` は 1b では使っていない（`CompletionOnce` 自体は使い、`@unchecked` なしの `Sendable`）」と、`RequestBox` と解放の見張りの同じ形にした。第 1 部 5.12.4 の表の行も同じ |
| 8: 20 章の状態の行が、行っていない UI テストの設計書の反映を挙げる | 「UI テストの設計書は C5 で書いたまま変えていない」にした |
| 9: `artifact/README.md` のトピックの一覧の ios-c-abi の行が 2026-10-31 のまま（次は 2 回目の申し送りと 1b） | 前の段階の終わりと同じく、行の終わりに 1b の完了（シミュレーター）、残り（MS-10 と実機の項目）、次（第 2 部）を足し、日付を 2026-11-01 にした |
| C1: 20.3 の MS-09 の行の 1 列目に RK の番号を書いたので、`scripts/check_design_consistency.py` がその行を RK の表の行と読み、記録の中の RK の参照を「表に無い」と落とす | RK の番号を 2 列目に移した（「C6（17.7 の 1。RK-10 の測り）」）。下の表のとおり FAIL は 0 |
| C3: README 5 章と 1b の結果 1 章が、iPad も 26.2 で流したと読める（iPad は 18.3 だけ） | 3 台を「iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3」と書いた |
| C4: README 5 章の 1b の行の「TSan）。 公開 API」の余分な空白 | 消した |
| C5: 第 1 部 5.12.4 の例の `CompletionOnce<Value>: Sendable` がコードと違う | コードのとおり `CompletionOnce<Value: Sendable>: Sendable` にした |
| C6: 21 章の 1 が、18 章の 5 で逆の考えへの反論だった文を「逆の考え」と呼ぶ | 「18 章の 5 で入口の確かめを取らなかった理由」にした |
| C7: 21 章の 4 に逆の考えが無い | 外す側の利点（私物に触れない、実機でも 1 件増える）と、取らない理由（実機では popover にならず、D6 と重なる）を足した |
| C9: 20.8 の「`print(` は DocC の例の 9 か所だけ」が、deprecated の `Log` と `IosLibrary.docc` を数えていない | `grep -rn 'print(' ios/IosLibrary/IosLibrary` で数え直し、19 行（Swift の DocC の例 9、`Common/Log.swift:48,56,64,72` の 4、`IosLibrary.docc/IosLibrary.md` の 6）と書いた |
| C10: 設計書 13.1 のブリッジのテストの件数（26・41・7）が 20.8 の数と違う | 設計書 13.1 の注に、20.8 は記録の表（25・40・7 と Share のマネージャー 1）に合わせたことを足した |
| C11: 新しい文の「2a の前」が、README 5 章の 2a（照合のスクリプト）と第 2 部の設計（1b の後、2b の前）のどちらか分からない | 第 2 部の設計を指す所（21 章の 1・3・5、20.10 の MS-08 の行）を「第 2 部の設計の前」にした |
| C12: C ABI の userInfo の `null` の扱い（第 2 部に回した。18 章の 6）が README 8.6 に無い | README 8.6 に行を足した |
| C13: 20.1 の MS-14 の行が「1b の結果のまま」と書くが、1b の結果は 20.3 を指すだけ。20.4 の 3 の `UNErrorDomain` の 100 のログの行は scratchpad に残していない | 20.1 を「UI テストの設計書 3.3 のまま（1b の結果は 20.3 の表を指すだけ）」にした。20.4 の 3 の表に、ログの行は残しておらず、残したのはサンプルの結果の行だけと書いた |
| T-11: `CommonTestSupport.swift` の `import Darwin` が使われていない（C7 で `isThreadSanitizerEnabled` を消した後） | 消した。下の実行と whole-module のビルドで組めた |
| T-12: `ReleaseWatchTests.aRealViewControllerClosesTheBoxWhenFreed` のコメントが「ライブラリが出したアラートとシートは TSan の版でも解放された」と言うが、このテストは表示しない ViewController を手放すだけ。待ちが 1 秒の自前の繰り返し | コメントを「TSan でも流す。手放した ViewController はそこでもすぐ解放される（1b C7、設計書 6.3.4、RK-11）」にした。待ちをほかの 2 つと同じ `waitUntil(timeout: 5) { box.isClosed }` にした（`try` が要らなくなったので `throws` を外した。名前は同じ） |
| T-13: `IosNotificationManagerCallFormTests` の 2 つ目のテストが回数をまとめた 1 つの `#expect` だけで、落ちたときにどれか分からない。1 つ目の doc comment が `trigger` を書かない `show(content:)` の意味を書いていない | まとめた待ちの後に、1 つ目と同じく回数ごとの `#expect` を 8 つ足した。1 つ目の doc comment に「`trigger` を書かない `show(content:)` も置き、`async` 版の `trigger` に既定が無いこと（SR2-7）を守る。既定があれば `async` 版に決まり組めなくなる」を足した（名前は同じ） |

単体テストの数は変わらない（543。足した・消した・名前を替えたテストは無い）。

| 実行 | 結果 |
|---|---|
| 直したテストと C7 で触れたテスト（`IosNotificationManagerCallFormTests` 2、`NotificationContentTests` 5、TSan の skip を外した 3 件。iPhone 17 / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`、`-only-testing`、DerivedData は scratchpad） | 10/10 成功（5 suite） |
| 同じ 10 件を TSan で（`-enableThreadSanitizer YES`。テストのホストに `libclang_rt.tsan` が入った） | 10/10 成功、TSan の報告 0 件。外した 3 件は 0.002 秒・2.7 秒・1.3 秒 |
| `IosLibrary` の scheme の `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`、Xcode 26.6） | エラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| M159・M160 の流し直し（`ios/IosLibrary` を scratchpad に写し、`completion` の `= nil` を外して `build-for-testing`。リポジトリは変えていない） | M159: テストのターゲットが組めない（`IosNotificationManagerCallFormTests.swift:67` の `setBadgeCount(2)`。ほかのテストのソースでは捕まらない）。M160: 組めない（先に `NotificationCategoryQueueTests.swift:329`、その呼び出しに `completion: nil` を書いた写しでは `IosNotificationManagerCallFormTests.swift:74` の `registerCategory(self.category)`）。20.12 の M160 の行に書き足した |
| `scripts/check_design_consistency.py`（第 1 部、設計書、README、この記録、1b の結果） | 5 つとも FAIL 0（終了の値 0） |
| シミュレーター | 始める前に起動しているものは無かった。iPhone 17 / 26.2 は xcodebuild が起動し、最後に起動しているものが無いことを確かめた。実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない） |

全体の実行（`scripts/test_ios.sh`）は流し直していない（直したのはテストの確かめの細かさとコメントで、関係するテストを両方の版で流したため）。

## 23. 1b の後の小さな直し（21 章の 1・5）

21 章の決定の 1 と 5 を、第 2 部の設計の前の小さな変更にした。5（コメントだけ）と 1（添付の入口の確かめ）は別の変更に分けた。21 章の決定の行は 5 の変更に入れた。実機には触れていない（`devicectl` も実機の `xcodebuild` も使っていない）

### 23.1 `sourceRect` の DocC（21 章の 5）

| 変えたもの | 中身 |
|---|---|
| `ios/IosLibrary/IosLibrary/Dialog/IosDialogManager.swift` の `showDialog(title:message:preferredStyle:actions:textFields:sourceView:sourceRect:barButtonItem:permittedArrowDirections:animated:completion:)` と `showActionSheet(title:message:options:cancelTitle:sourceView:sourceRect:animated:onAction:completion:)` の `sourceRect` の DocC | 「`nil` uses the whole bounds of `sourceView`. On iPad, a large view (for example, one that fills the screen) leaves no room for the popover, which then shows without its options; pass a small rect, close to a point, where the popover should point.」を足した。`showDialog` には「it matters only for `.actionSheet`」も足した（レビューの C5）。コードは変えていない（基点は `AlertDialogPresenter` の `anchor.sourceRect ?? sourceView.bounds` のまま。S-P5）。`sourceRect` を取る今の口はこの 2 つだけで、新しい口の `show(_:presenter:requestBox:completion:)` は基点を view の中央に付ける |
| 1b の結果 6 章 | `sourceRect` の行の**決定待ち**を外し、DocC に書いたこととマニュアル（段階 4）に書くことにした |
| 21 章の 6 の決定の反映（C ABI から表示元を渡す口は 2.0.0 では設けない） | README 3.1・8.6、第 1 部の G-6 と 5.13 の前面の定義、1b の結果 5 章・6 章・7 章の iPad の行の「決定待ち」「未決」「第 2 部で決める」を、決まったこと（設けない。C のヘッダーとマニュアルに「複数の window を開ける iPad では、どちらの window に出すかは決まらない」と書く）にした |
| 1b の結果の冒頭とコミットの表 | C7 を未コミットから `75881825` に直した |

確かめ（23.1 の変更だけを当てた作業ツリー）:

| 実行 | 結果 |
|---|---|
| `IosLibrary` の scheme の `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`。Xcode 26.6 と 26.3、`DEVELOPER_DIR`。`ios/IosLibrary` を scratchpad に写して組んだ） | どちらもエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| 公開 API（1.6 と同じ組み方: Release、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`、Xcode 26.3。`arm64-apple-ios.swiftinterface`） | `results/swiftinterface/IosLibrary-after-1b-c6.swiftinterface` と 1 文字も違わない（DocC は swiftinterface に入らない）。取り直していない |
| Dialog の基点と表示のテスト（`IosDialogManagerShownTests`・`AlertDialogPresenterTests`。iPhone 17 Pro / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`、`-only-testing`。iPhone 17 / 26.2 は 21 章の 2 の取り直しで別の作業が使うので触れていない） | 32/32 成功（2 suite）。TSan（`-enableThreadSanitizer YES`）でも 32/32 成功、報告 0 件 |
| `scripts/check_design_consistency.py`（README、第 1 部、この記録、1b の結果） | 4 つとも FAIL 0（終了の値 0） |

後の項目（この直しの外）: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md:96` の ``IosDialogManager/showActionSheet(title:message:actions:sourceView:sourceRect:animated:completion:)`` は今のコードに無い記号（今の口は `showActionSheet(title:message:options:cancelTitle:sourceView:sourceRect:animated:onAction:completion:)`）。DocC の目次の直しとして後で行う（レビューの C6）

### 23.2 無いファイルの添付を入口で断る（21 章の 1）

| 変えたもの | 中身 |
|---|---|
| `ios/IosLibrary/IosLibrary/Notification/Data/Repository/NotificationRepositoryImpl.swift` | `checkAttachmentFilesExist(_:)`（private）を足し、`makeUNContent(from:)` の中で、添付を作る（`makeUNAttachment(from:)` の `map`）直前に呼ぶ。添付ごとに `FileManager.default.fileExists(atPath: fileURL.path)` を見て、無ければ `attachmentLoadFailed(identifier:detail:)`（`detail` は `FailureDetail(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)`、260）を投げる。全部の添付を見てから 1 つ目を作る。`show`・`update`・`schedule` はどれも `makeUNContent` を通るので、3 つとも同じ所で確かめる。`update` は今までどおり「検査 → 内容と trigger を作る（ここで確かめる）→ 今の予約を消す → `add`」の順で、無いファイルでは消さない。`.error` のログは識別子と domain・code だけで、パスは出さない（`ios.md` のエラーの値が URL やパスを持つときの規則）。型の DocC と `update` の行コメントを直した |
| `IosNotificationManager.swift` の `show(content:trigger:completion:)`・`update(identifier:content:trigger:completion:)`・`schedule(content:trigger:identifier:completion:)` の DocC | `show` に「添付のファイルが無ければ `attachmentLoadFailed`（`NSCocoaErrorDomain`・`NSFileReadNoSuchFileError`）で何も足さない。確かめの後に消えたファイルは `addRequestFailed`」、`update` に「無いファイルも予約を残す。確かめの後に消えたファイルで `add` が断れば予約は消えた後」、`schedule` に「添付のファイルも `show` と同じく先に確かめる」を足した |
| `NotificationError.swift` の DocC | 表の `attachmentLoadFailed` の行と case の説明に「ファイルが無い（またはプロセスから見えない）」ときと、そのときの `detail`、確かめるのは file URL だけであることを足した |
| `NotificationAttachment.swift` の DocC | `fileURL` を「The file URL of the attachment file」にした（レビューの B1） |
| 単体テスト `IosLibraryTests/Notification/Data/NotificationRepositoryAttachmentCheckTests.swift`（足した。UT-18 の添付の分） | 5 件: `everyAttachmentIsCheckedBeforeTheFirstIsMade`（OS が作らない型のある file（`.ut18unknown`。作れば `UNErrorDomain` の 101）を先に、無いファイルを後に置き、無いファイルの識別子と 260 で落ちる。全部を確かめてから 1 つ目を作ることを守る）、`aURLThatIsNotAFileURLIsLeftToTheSystem`（`https://example.com/a.png` は 260 で断らず、テストのホストでは `center.calls == ["add n"]` まで進む。下の偏りを守る）、`showAndScheduleWithAMissingFileFailAndAddNothing`（無いファイルの添付 1 つと、あるファイルの後の無いファイルで、`show`・`schedule` が `attachmentLoadFailed(identifier: "missing", detail: NSCocoaErrorDomain / 260)` で落ち、`FakeRequestCenter` に何も呼ばない）、`updateWithAMissingFileKeepsThePendingRequest`（予約が残り、呼ばれたのは前の `add u` だけ）、`anExistingFileStillGoesThrough`（4×4 の PNG 2 つで `show`・`schedule`・`update` が通り、要求に添付が 2 つ付く。2 つ目の名前は空白・`%20`・日本語を含む「`ut18 画像 %20-<UUID>.png`」で、作って `defer` で消す。`path(percentEncoded: true)` で見ると捕まる） |
| `NotificationRepositoryUserInfoCheckTests.swift` | 添付のテストの doc comment に、無いファイルはライブラリが先に確かめること（新しいテストのファイル）を足した。テストは変えていない |
| README 4.1 の 1b の行、設計書 3.3 の `update` の行、1b の結果 5 章・6 章・7 章（エラー）・8 章（利用者の決定） | 無いファイルは入口で `attachmentLoadFailed`、`update` は予約を残す。確かめから `add` までの間に消えたファイルは今までどおり `addRequestFailed`（`update` では予約が消えた後） |

設計からの偏り: 確かめるのは file URL（`isFileURL`）だけにした。file URL でない URL（`https:` など）は今までどおり `UNNotificationAttachment` と `add` に任せる（`fileURL.path` で見ると、ファイルでないものも 260 になり、無いファイルと見分けられなくなるため）。そのため file URL でない添付で `add` が断れば、`update` は今までどおり今の予約を消した後になる（DocC にも書いた）。ディレクトリと通常のファイルでないもの（`fileExists` は真を返す）も今までどおり OS に任せる（コードは変えていない）。プロセスから見えないファイル（security-scoped の URL で `startAccessingSecurityScopedResource` の前、読めない親のディレクトリの下など）も `fileExists` が偽になり 260 になる。これは DocC に「does not exist (or cannot be seen by the process)」の形で書いた（レビューの C4。記録ではなく DocC を選んだのは、利用者が見る所だから）。テストのための差し込み口（`NotificationRequestCenter` のような seam）は足していない。テストは一時ディレクトリの実のファイル（あるもの）と、作っていないパス（無いもの）で足りた（今の UT-18 の添付のテストと同じ形）。

層: 確かめは Data 層（`NotificationRepositoryImpl`）だけで、Domain（`NotificationError` の case は今のまま）・Application（Port と UseCase）・Manager のコードは変えていない。公開 API は変えていない（下の swiftinterface）。

#### 23.2.1 壊して確かめたこと（M161〜M166。番号は 20.12 の M160 に続ける）

`ios/IosLibrary` を scratchpad に写して壊し、下の 4 つの suite を流して、落ちることを見た（作業ツリーは変えていない）。iPhone 17 Pro / 26.2、Xcode 26.6。M161〜M163 はレビューの直し（テスト 2 件を足した）の後に流し直した。

| # | 壊し方 | 落ちたテスト |
|---|---|---|
| M161 | 確かめを外す（`makeUNContent` の `checkAttachmentFilesExist` の呼び出しを消す） | `showAndScheduleWithAMissingFileFailAndAddNothing`（`an error was expected but none was thrown`、`center.calls` が `["add n", "add n"]`）、`updateWithAMissingFileKeepsThePendingRequest`（呼び出しが `["add u", "remove u", "add u"]`、残った要求の `before` が `nil`）、`everyAttachmentIsCheckedBeforeTheFirstIsMade`（`unusable` の `UNErrorDomain` の 101 が出た）。テストのホストでは `UNNotificationAttachment` が無いファイルを受け、偽の center の `add` は通るので、投げずに足した |
| M162 | `show` だけで確かめる（`makeUNContent` から外し、`show` の userInfo の検査の後に置く） | 同じ 2 件（`schedule` が投げずに `add n` を呼んだ。`update` は予約を消して足した） |
| M163 | `update` で今の予約を確かめの前に消す（`removePendingNotificationRequests` を userInfo の検査の直後、内容を作る前に移す） | `updateWithAMissingFileKeepsThePendingRequest`（`center.request("u")` が `nil`）。今の `updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest` も落ちた |
| M164 | パーセントで符号化したパスで見る（`fileURL.path(percentEncoded: true)`） | `anExistingFileStillGoesThrough`（空白・`%20`・日本語の名前のファイルが `attachmentLoadFailed(identifier: "named", detail: NSCocoaErrorDomain / 260)` になった） |
| M165 | `isFileURL` の絞りを外す（すべての URL を `fileURL.path` で見る） | `aURLThatIsNotAFileURLIsLeftToTheSystem`（`https://example.com/a.png` が 260 で断られ、`center.calls` が `[]`） |
| M166 | 確かめを `map` の中に移す（`makeUNContent` から外し、`makeUNAttachment(from:)` の先頭で添付 1 つずつ確かめる） | `everyAttachmentIsCheckedBeforeTheFirstIsMade`（先の `unusable` を作って `attachmentLoadFailed(identifier: "unusable", detail: UNErrorDomain / 101)` になり、後の無いファイルまで届かない） |

#### 23.2.2 確かめ（23.1 と 23.2 の変更を当てた作業ツリー）

| 実行 | 結果 |
|---|---|
| 通知のリポジトリの 4 つの suite（`NotificationRepositoryAttachmentCheckTests` 5、`NotificationRepositoryUserInfoCheckTests`、`NotificationRepositoryMarkerTests`、`NotificationCategoryQueueTests`）と Dialog の 2 つの suite（`IosDialogManagerShownTests`、`AlertDialogPresenterTests`。23.1 の DocC の口）。iPhone 17 Pro / 26.2、Xcode 26.6、`-parallel-testing-enabled NO`、`-only-testing`、DerivedData は scratchpad | 66/66 成功（6 suite。リポジトリ 34、Dialog 32） |
| 同じ 66 件を TSan で（`-enableThreadSanitizer YES`。テストのホストに `libclang_rt.tsan_iossim_dynamic.dylib` が入った） | 66/66 成功、TSan の報告 0 件 |
| `IosLibrary` の scheme の `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`（`generic/platform=iOS Simulator`。Xcode 26.6 と 26.3、`DEVELOPER_DIR`） | どちらもエラー 0、警告 0（`appintentsmetadataprocessor` の「Metadata extraction skipped」だけ） |
| 公開 API（23.1 と同じ組み方） | `IosLibrary-after-1b-c6.swiftinterface` と 1 文字も違わない（足したのは private の関数と DocC だけ）。取り直していない |
| `scripts/check_design_consistency.py`（README、設計書、この記録、1b の結果） | 4 つとも FAIL 0（終了の値 0） |
| シミュレーター | iPhone 17 Pro / 26.2 だけを使った（xcodebuild が起動し、終わった後は起動していなかった）。iPhone 17 / 26.2（21 章の 2 の基準の取り直しで別の作業が使う）には触れていない。実機には触れていない |

単体テストは 5 件増える（`IosLibraryTests` の `@Test` は 543 から 548）。全体の実行（`scripts/test_ios.sh`）と基準の取り直しは流していない（21 章の 2 は別の作業）。UI テストは変えていない（信頼する部分と `TRUSTED_FILES` のハッシュも変えていない）。

23.1・23.2 は、この直しのレビュー（文書とコードの観点、Codex）の指摘を直した後の版。23.2 で直したのは、確かめるのが file URL だけであることとプロセスから見えないファイルの DocC（B1・C-1・C4）、テストの 2 件の追加と名前の符号化の確かめ（B2・C-2）、ディレクトリなどの扱い（C1）、拡張子の型の `detail` の変わり方（C2）、ブリッジの `errorMessage`（C3）、設計書 13.1 の UT-18 の行（C7）。DocC の目次の記号（C6）は 23.1 の後の項目に回した

### 23.3 N32・N33 の `launch=true`（21 章の 2 の基準の取り直しで見つかった）

**起きたこと**: `75881825` で全件を流した回（11-01 21:03）で N9・N32・N33 が、Notification だけの回（23:11、ほかは動かしていない）で N32 が失敗した。N32・N33 は `NotificationColdStartUITests.swift` の launch の確かめで、`false` を期待して `true` だった。N9 はバナーが 10 秒で出なかった失敗で、1 回目の高い負荷（15 分の平均で 47）のせいと見ており、確かめてはいない。

**前の記録の誤り**: この章の決定の行を 11-01 に書いたとき「N32 は 10-24 にも 1 回失敗した」としたが、10-24 の失敗は「返信の欄が出ない」という別のもの（0d の作業の記録 11.3）で、`launch=true` の失敗はこの 2 回が初めて。決定の行を直した。

**測ったこと**（iPhone 17 / 26.2、落ちた回と同じビルド。11-02、再起動の後）:

| 回 | 結果 |
|---|---|
| N32 を 1 件ずつ 10 回（ほかは動かしていない） | 10/10 成功 |
| コールドスタートのクラス全体を 3 回 | N32・N33 を含む 21/21 成功 |
| N32・N33 を 5 回（CPU に負荷をかける） | 10/10 成功。ただし負荷のプロセスの時間切れが早く、負荷の中で流れたのは 1 回目の始めだけ。**負荷の確かめにはなっていない** |

ライブラリのログでは、Reply・Delete の状態はどの回も `2`（background）で、`didBecomeActive` のおよそ 0.5 秒前に読まれていた。**失敗は再現せず、順番の入れ替わりを iOS 26 で見てはいない。**

**原因の見込み**: Reply・Delete は応答からは前面に出るかが分からないので、ライブラリはメインキューのブロックの中で `applicationState` を読む（`NotificationDelegateRouter.noteOnMain`）。`launch=true` になる道はコード上、このブロックが動くときに状態が `background` でない場合だけで、テストの中で前面に出すのは `sample.activate()` だけ。テストは送った直後に前面に出すので、余裕は 0.5 秒ほどしかない。iOS 18 では同じ入れ替わりを MS-05 で測っている（13.7）。

**直し**: N32・N33 が前面に出す前に 3 秒待つ（`backgroundActionSettle`）。テストだけの変更で、ライブラリは変えていない。余裕を広げる直しで、順番を決まったものにする直しではない。

**直しの確かめ**（iPhone 17 / 26.2）: N32・N33 を 3 回ずつ流し、6/6 成功。状態を読んでから `didBecomeActive` までは 3.8〜3.9 秒になった（直す前は 0.5 秒ほど）。もとの失敗が再現しないので、この直しで失敗が無くなることまでは確かめられていない。

**基準の取り直し**（iPhone 17 / 26.2、`4ea74702`、2026-11-02 22:26〜11-03 00:22、1 時間 56 分。ほかのシミュレーターの作業は動かしていない）: 683 件（`IosLibraryTests` 548、`IosLibraryExampleTests` 10、UI テスト 124、ボタンの網羅の 1 行）のうち 682 件が成功し、skip は意図した U10b の 1 件で、N9・N32・N33 も通った。前の基準との比べ合わせは `changed=0, added=366, removed=4` で、足した 366 件は 1b の 361 件（20.7）と 23.2 の 5 件、removed の 4 件は 20.7 で記録した名前を替えた・消したテスト。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）は 682 件になった（ボタンの網羅の行は入らない）。ただし、待ちを足す前の C7 の全件の回も N32・N33 は通っていたので、1 回通ったことは直しの効き目の証拠にはならない。また落ちたら、原因の見込みから調べ直す。

**ライブラリの限り**: 背景のアクションの直後に利用者がアプリを前面に出すと、その応答が起動のきっかけ（`isLaunchResponse`）と扱われることがある。iOS 18 だけのことと見ていたが、iOS 26 でも起こりうる。動作は変えない。マニュアル（段階 4）に書く候補として残す。

## 24. 実機の回（21 章の 3）

### 24.1 UI テストの回（`clipboard` を含む 106 件）

利用者に 4 項目を示して許可を得て、`ff2384be` で流した（2026-11-03 04:00〜06:20、2 時間 19 分。iPhone XS / 18.7.2、Xcode 26.3）。`--device-allow systemui,sharesheet,clipboard`、`--baseline`。実機の UDID と devicectl の識別子はどこにも書いていない。実機の `.xcresult` はランナーが消した。`clipboard` を含めると、1b の CB5・CB6 だけでなく 0c の残りのテストも流れる（ランナーは区分で選ぶ）ことを示し、利用者が含めると決めた。

| 区分 | 件数 | 結果 |
|---|---|---|
| `clipboard` を含まない（`systemui`・`sharesheet`・区分なし） | 72 | すべて成功（N32・N33 を含む） |
| `clipboard` を含む | 34 | 成功 30、skip 1（U10b。シミュレーターと同じ、M-08 がこの環境では決まらない）、失敗 3 |

前の実機の基準（60 件）との比べ合わせは `changed=0, added=46, removed=0`。失敗があったので、基準は保存されていない（60 件のまま）。

| 失敗 | 文 |
|---|---|
| CB1 | `ClipboardPasteUITests.swift:46`: `the paste alert did not appear`（10 秒） |
| CB3・CB4 | `SampleApp.swift:735`: `the paste summary did not become Paste result: items=1, failures=0 in 10.0s: Paste result: -` |

### 24.2 切り分け

- 同じ 3 件を iPhone 16 / 18.3 のシミュレーターで流すと、3/3 成功。iOS の版ではなく、実機でだけ起きる
- CB1・CB3・CB4 を実機で流したのは今回が初めて。0a で合成のタップが受け付けられると確かめたのはシミュレーターだけ（0a の結果）
- 利用者が実機で手で確かめた（サンプルの Clipboard の画面で、メモなどからコピーした文字列）。Load Text で貼り付けの許可のダイアログが出た。Mount Paste Control の後に貼り付けのコントロールを指で押すと、`Paste result: items=1, failures=0` になった。画像だけの内容（CB4）は手で確かめていない

**見込み（確かめてはいない）**: CB3・CB4 は、実機が貼り付けのコントロールで XCUITest の合成のタップを受け付けない。テストの限りで、ライブラリの不具合ではない。CB1 の原因は分からない。同じ手順の CB2 は同じ回でダイアログが出て通り、手でも出たので、ダイアログが出ないのが実機の常の振る舞いではない。実機の画面の階層は読まない決まり（`agent-rules/device-testing.md`）なので、ログからはこれ以上分からない。

**残すこと**: `clipboard` を許す次の実機の回（2.0.0 の前の区切り）の前に、CB3・CB4 を `SIMULATOR_ONLY_TESTS` に移して人の確認に回すかを決める。CB1 はその回でもう一度見る。

**手順の誤り**: 1 回目の起動は `--skip-unit` と `--baseline` を一緒に渡して、引数の確かめで止まった（実機に触れていない。許可の ID も使っていない）。実機では単体テストは流れないので、`--skip-unit` は要らない。

### 24.3 実機の基準の取り直し（`clipboard` を含まない 72 件）

基準は失敗が無い回でしか保存されず、CB3・CB4 は実機で通らない見込みなので、`clipboard` を外して流した（利用者に 4 項目を示して、改めて許可を得た）。`ff2384be`、2026-11-03 08:48〜09:54、1 時間 6 分。`--device-allow systemui,sharesheet`、`--baseline`。

72 件すべて成功（Navigation 2、IdentifierInventory 3、Dialog 13、Notification 25、NotificationEvent 12、NotificationColdStart 7、Share 10）。前の基準との比べ合わせは `changed=0, added=12, removed=0`。実機の基準（`scripts/test_ios.baseline.iPhone_XS-18.7.2.json`）は 60 件から 72 件になった。許した区分は `systemui`・`sharesheet` で、`clipboard`・`files`・`reinstall`・`credentials` は基準に入らない。2.0.0 の前の区切りで `clipboard` を許すときに広げる。

N32・N33 はどちらの回も実機で通った。ただし iOS 18.7.2 の結果で、23.3 の iOS 26 の見込みの証拠にはならない。

### 24.4 MS-08 の前面と実機の振る舞い

利用者に 4 項目を示して許可を得て、2026-11-03 10:27〜10:44 に測った（iPhone XS / 18.7.2、`bf22985d`。デバッガーなしで利用者が起動）。使い捨ての写しに、すぐ読むボタンと 5 秒後に読むボタン（`loadItem(.text)` と同期の `read`）を足して上書きで入れ、利用者が手で操作した。結果の行にクリップボードの中身は出ない。測った後に元のサンプルを上書きで戻した。写しはリポジトリに入れていない（10.7 の `apply_ms08_probe.py` は残っていなかったので作り直した）。

`gap` は main の run loop の間の最も長い空き。`req`・`end` は要求と完了の時点の `applicationState`。

| # | 状況と内容 | 読み方 | 結果 | req → end | ms | gap | ダイアログ |
|---|---|---|---|---|---|---|---|
| A | 前面、メモの文字列、約 10 秒待って許可 | `loadItem` | 成功 | active → inactive | 14990 | 51 | 出た |
| B | 前面、同上。待つ間に画面は動かなかった | `read` | 成功 | active → active | 23909 | 23910 | 出た |
| C | 前面、同上、約 30 秒待って許可 | `read` | 成功 | active → active | 44469 | 44470 | 出た |
| D | ホームへ移った後、メモの文字列 | `loadItem` | `CLIPBOARD_TIMED_OUT` | background → inactive | 16028 | 51 | 後ろでは見えず、戻ると出ていた |
| E | 同上 | `read` | 成功 | background → background | 6319 | 6319 | 後ろでは見えず、戻ると出ていた |
| F | ホームへ移った後、サンプルが書いた文字列 | `loadItem` | 成功 | background → inactive | 42 | 42 | 出ない |
| G | 同上 | `read` | 成功 | background → background | 46 | 46 | 出ない |

分かったこと:

1. **同期の `read` は、前面でも答えが出るまで main を止める。** 44 秒止まっても、アプリは OS に終了させられなかった（デバッガーなし。7 行すべてが同じプロセスのメモリーに残っていた）。
2. **非同期の `loadItem` は main を止めない**（`gap` 51 ms）。
3. **`loadItem` の時間切れ（既定の `providerLoad` 15 秒）には、利用者が答える時間も入る。** D はこれで `CLIPBOARD_TIMED_OUT` になった。A は 14.99 秒で、時間切れの 10 ms 前に間に合っただけ。Swift の DocC にも設計書にも書いていない。時間切れの後にダイアログがどうなるか、許可を押すとどうなるかは測っていない。
4. **自分が書いた内容は、ダイアログなしで読める**（42〜46 ms）。シミュレーターと同じ。

**見込み（確かめてはいない）**: D〜G は、ホームに移った後に iOS がサンプルを止めて、5 秒後の要求が戻ったときに初めて動いた見込み。手がかりは、F が要求から 42 ms で `inactive` になっていること（戻る瞬間に要求が動いた）と、D・E のダイアログが戻って初めて見えたこと。そうなら、この表は「後ろで動いているアプリが読んだとき」を測っていない。シミュレーター（iOS 26.2、10.7）で後ろの間にダイアログが出たのとの違いが、実機によるのか iOS の版によるのかも分からない。E の `end=background` は、main が止まっていて状態が更新されなかったものかもしれない。

**決定（2026-11-03、利用者）: 時間切れの既定は変えず、文書に書く。** 15 秒の既定を延ばす案は OS が答えないときの待ちも延び、ダイアログの間だけ時計を止める案は OS がダイアログの有無を教えないので作れない見込み。`ClipboardTimeouts` で利用者が時間を変えられる。`loadItem(_:scope:completion:)` と `ClipboardTimeouts.providerLoad` の DocC に足した（コメントだけ）。第 2 部の C の非同期の読み込みの関数のヘッダーとマニュアル（段階 4）にも書く。時間切れの後に遅れて答えても結果が来ないのはコード（`ClipboardProviderLoadHandle.finish` は 1 回だけ）から読んだことで、実機では測っていない。
