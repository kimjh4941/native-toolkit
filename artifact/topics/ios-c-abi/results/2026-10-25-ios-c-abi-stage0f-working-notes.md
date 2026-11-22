# 段階 0f の作業の記録（Swift 6 の言語モード）

- 記録日: 2026-10-25
- 段階: 0f（`README.md` の 5 章の 0f の行、D-14、D-16、8.3）
- ブランチ: `feature/NTKIT-18`（HEAD `c508f524` の上の未コミットの変更）
- 環境: Xcode 26.3（17C529）、Swift 6.2.4、シミュレーター iPhone 17（iOS 26.2）と iPhone 16（iOS 18.3）だけ。**実機には触れていない**
- 状態: 4 つのターゲットを Swift 6 の言語モードにし、エラー・警告は 0 件。Swift 6 の実行時の隔離の検査で止まりうる所が 1 つ見つかり（`IosClipboardManager` を main 以外で手放す。4.3）、直してテストを足した。シミュレーターでの確かめ（単体テスト全件、`IosLibraryExampleTests`、UI テスト全件、iOS 18.3 の Notification・Share）は済んだ。コミットはしていない

## 1. 測り方

0e の作業の記録の 1 章と同じ。測ったログと抜き出した一覧は scratchpad に置き、リポジトリには入れていない。

| 項目 | 方法 |
|---|---|
| 警告の数 | 2 つの scheme（`IosLibrary`、`IosLibraryExample`）を `SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing` で組み、5 つのターゲットの診断を `migration` の 4.3 の正規化で数えた（0e と同じ） |
| build setting の差分 | `-showBuildSettings` を 5 ターゲット × 2 構成で前と後に取り、`diff` した |
| `swiftc` の引数 | 上のビルドのログから、意味に効く引数をモジュールごとに抜き出した（0e の 1 章の一覧） |
| 公開 API | `IosLibrary` を Release・`generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組み、`arm64-apple-ios.swiftinterface` を写した。`swift-frontend -typecheck-module-from-interface` で型検査した |
| 実行時の隔離の検査（4 章） | `IosLibrary` とサンプルの全ソースを `swiftc -emit-sil -wmo -Onone` で Swift 5（+ `StrictConcurrency`）と Swift 6 の 2 通りに下ろし、`_checkExpectedExecutor` / `swift_task_isCurrentExecutor` / `MainActor.assumeIsolated` を呼ぶ関数を挙げて比べた。trap するかは、プローブ（使い捨てのテストと macOS の小さなプログラム。リポジトリには残していない）で確かめた |

## 2. 設定

### 2.1 変えたもの

`SWIFT_VERSION` を、4 つのターゲットのターゲットの階層（Debug / Release）で `5.0` → `6.0` にした。プロジェクトの階層には `SWIFT_VERSION` が無い（前から）。

| ターゲット | 前 | 後 |
|---|---|---|
| `IosLibrary` | 5.0 | **6.0** |
| `IosLibraryTests` | 5.0 | **6.0** |
| `IosLibraryExample`（アプリ） | 5.0 | **6.0** |
| `IosLibraryExampleTests` | 5.0 | **6.0** |
| `IosLibraryExampleUITests` | 5.0 | 5.0（D-14 の例外。`SWIFT_STRICT_CONCURRENCY = minimal` も変えていない） |

`ios/UnityIosPlugin` は触れていない（ワークスペースの外。D-22）。

### 2.2 `-showBuildSettings` の差分（全部）

10 個の一覧（5 ターゲット × Debug / Release）のうち、変わったのは 4 ターゲット × 2 構成の `SWIFT_VERSION = 5.0` → `6.0` の 8 行だけ。`IosLibraryExampleUITests` の 2 つの一覧は 1 行も変わっていない。

### 2.3 `swiftc` の引数の差分

| モジュール | 前 | 後 |
|---|---|---|
| `IosLibrary`、`IosLibraryTests`、`IosLibraryExample`、`IosLibraryExampleTests` | `-swift-version 5`、`-enable-upcoming-feature StrictConcurrency`、`-enable-bare-slash-regex`、`-enable-experimental-feature DebugDescriptionMacro`、`-target arm64-apple-ios18.0-simulator` | `-swift-version 6`、`-enable-experimental-feature DebugDescriptionMacro`、`-target arm64-apple-ios18.0-simulator` |
| `IosLibraryExampleUITests` | `-swift-version 5`、`-enable-bare-slash-regex`、`-enable-experimental-feature DebugDescriptionMacro`、`-target ...` | 同じ |

消えた 2 つは Swift 6 で必ず入るもの（`Swift.xcspec` が `EFFECTIVE_SWIFT_VERSION` が 4 / 4.2 / 5 のときだけ渡す）。`-default-isolation`、`-strict-concurrency=`、ほかの `-enable-upcoming-feature` は前も後も渡っていない。

### 2.4 0e で固定した設定の見直し

0e の 2.4 でプロジェクトの階層に固定した設定を、Swift 6 で効くかどうかで分けた。`Swift.xcspec`（Xcode 26.3）の条件を読み、さらに、効かないはずの設定をコマンドラインで反対の値（`YES` / `minimal`）にして `IosLibrary` を組み、`swiftc` の引数が変わらないことを確かめた（下の「確かめ」）。

| 設定 | Swift 6 の 4 つのターゲット | Swift 5 の UI テストのターゲット | 扱い |
|---|---|---|---|
| `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` | 効く（`MainActor` にすると `-default-isolation=MainActor` が渡る） | 効く | 残す |
| `SWIFT_UPCOMING_FEATURE_` の条件の無い 5 つ（`EXISTENTIAL_ANY`、`INFER_ISOLATED_CONFORMANCES`、`INTERNAL_IMPORTS_BY_DEFAULT`、`MEMBER_IMPORT_VISIBILITY`、`NONISOLATED_NONSENDING_BY_DEFAULT`） | 効く（Swift 6 でも既定は無効。`YES` にすると引数が渡る） | 効く | 残す |
| `SWIFT_APPROACHABLE_CONCURRENCY = NO` | 効くが、影響する 5 つのうち Swift 6 で意味が残る 2 つ（`INFER_ISOLATED_CONFORMANCES`、`NONISOLATED_NONSENDING_BY_DEFAULT`）は個別にも `NO` を固定しているので、重なっている | 効く | 残す（Xcode の推奨設定で `YES` にされたときに、個別の固定と食い違わないように） |
| `SWIFT_UPCOMING_FEATURE_` の条件付きの 13 個（`CONCISE_MAGIC_FILE`、`DEPRECATE_APPLICATION_MAIN`、`DISABLE_OUTWARD_ACTOR_ISOLATION`、`DYNAMIC_ACTOR_ISOLATION`、`FORWARD_TRAILING_CLOSURES`、`GLOBAL_ACTOR_ISOLATED_TYPES_USABILITY`、`GLOBAL_CONCURRENCY`、`IMPLICIT_OPEN_EXISTENTIALS`、`IMPORT_OBJC_FORWARD_DECLS`、`INFER_SENDABLE_FROM_CAPTURES`、`ISOLATED_DEFAULT_VALUES`、`NONFROZEN_ENUM_EXHAUSTIVITY`、`REGION_BASED_ISOLATION`） | **効かない**（Swift 6 では言語モードが必ず入れる。`NO` は何もしない） | 効く（`NO` のまま。Swift 5 の既定と同じ） | 残す（UI テストのターゲットが継ぐ） |
| `SWIFT_STRICT_CONCURRENCY = complete`（プロジェクトの階層） | **効かない**（Swift 6 は必ず complete。条件付き） | 効かない（ターゲットの階層の `minimal` が上書きする） | 残す（UI テストのターゲットの `minimal` を外したときに complete に戻る形を保つ。0e の記録と同じ意味のまま） |

エラーになる固定は無い（Xcode は条件の外の設定を黙って無視する）。**どの固定も外していない**。Swift 6 の 4 つのターゲットでは 14 個（upcoming feature 13 個と `SWIFT_STRICT_CONCURRENCY`）が意味を失うが、同じプロジェクトの階層を Swift 5 の UI テストのターゲットが継ぐので、そのターゲットのために意味が残る。0e の作業の記録 2.4 の「注意（0f）」の 13 個は、この表のとおりだった。

確かめ: `SWIFT_STRICT_CONCURRENCY=minimal`、`SWIFT_ENABLE_BARE_SLASH_REGEX=YES`、条件付きの 13 個をすべて `YES`、`SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY=YES` をコマンドラインで渡して `IosLibrary` を組むと、`swiftc` の意味に効く引数は `-enable-upcoming-feature ExistentialAny` が増えただけだった（条件の無い設定は効き、条件付きの 15 個は効かない）。

## 3. 警告とエラー

| 所 | 0f の前（Swift 5 + complete） | 0f の後（Swift 6） |
|---|---|---|
| `IosLibrary` | 0 | 0 |
| `IosLibraryTests` | 0 | 0 |
| サンプル | 0 | 0 |
| `IosLibraryExampleTests` | 0 | 0 |
| `IosLibraryExampleUITests`（Swift 5 + minimal） | 0 | 0 |
| 計（2 つの scheme の和集合。エラー / 警告） | 0 / 0 | 0 / 0 |

`SWIFT_VERSION` を変えただけの状態で、エラーも警告も 0 件だった（0e で complete の警告を 0 にしてあったので、Swift 6 でエラーに上がるものが無かった）。4 章の直しと足したテストの後も 0 件。Swift 以外の警告は、前も後も `appintentsmetadataprocessor` の「Metadata extraction skipped」だけ（ビルドの道具の知らせで、ソースの診断ではない）。

## 4. 実行時の隔離の検査（dynamic actor isolation）

### 4.1 Swift 6 で増えた検査

Swift 6 の言語モードは、main actor に隔離された同期の関数・closure が、隔離を知らない呼び出し元（Objective-C、`@preconcurrency` の API、隔離の無い関数型への変換）から呼ばれうる所に、実行時の検査を入れる（SE-0423）。main 以外で呼ばれると、`_checkExpectedExecutor` → `dispatch_assert_queue` で止まる（`EXC_BREAKPOINT`）。

SIL で数えた、検査を呼ぶ関数（標準ライブラリの 2 つを除く）:

| モジュール | Swift 5 | Swift 6（直す前） | Swift 6（4.3 の直しの後） |
|---|---|---|---|
| `IosLibrary` | 7（`MainActor.assumeIsolated` 5、`isolated deinit` の移り先の判定 2） | 64 | 64 |
| サンプル | 1（`assumeIsolated`） | 109 | 109（変えていない） |

### 4.2 1 つずつの判定（`IosLibrary`。直しの後の 64 個）

| 所 | 数 | 呼ぶもの・スレッド | 判定 |
|---|---|---|---|
| UIKit の `UIView` の部分クラスの `@objc` の入口（`ClipboardPasteControlContainerView` の `init(frame:)`・`init(coder:)`・`intrinsicContentSize`・`dealloc`、`ClipboardPasteReceiverView` の `init(frame:)`・`init(coder:)`・`canPaste(_:)`・`paste(itemProviders:)`） | 8 | UIKit。main で呼ぶ。`dealloc` は 4.3 | 止まらない |
| `IosClipboardManager` の `@objc init()` | 1 | Objective-C から `alloc`/`init` されたときだけ（ブリッジは外した。D-22）。Swift からの `init` は `private` | 止まらない（Objective-C の利用者は無い） |
| Dialog の `DispatchQueue.main.async` の block、`UIAlertAction` の handler、`addTextField` の configuration、`queue: .main` の observer と、その中の `assumeIsolated` | 30 | main queue と UIKit | 止まらない |
| `getRootViewController()`（Dialog・Share）の `first(where:)` の closure | 4 | その場で同期に呼ぶ（呼び出し元は `@MainActor`） | 止まらない |
| `ShareSheetPresenter.present` の `withCheckedThrowingContinuation` の本体 | 1 | その場で同期に呼ぶ | 止まらない。`completionWithItemsHandler` の closure には検査が入らない（`Task { @MainActor in }` で main に移る形のまま） |
| Clipboard の `startObserving` の observer（`queue: .main`）と `assumeIsolated`、`loadItem` の継続の closure、`canPaste`・`firstMatchingProvider`・`requestKind` の `contains` / `first` の closure | 17 | main queue、その場で同期、main actor の loader の完了 | 止まらない |
| `isolated deinit` の移り先の判定（`ClipboardItemLoaderImpl`、`PasteItemProviderLoader`、4.3 の `ClipboardManagerCleanup`） | 3 | Swift の `isolated deinit` が main にいるかを見て、いなければ main に積む（止めない） | 止まらない |

直す前の 64 個は、上の 3 つの `isolated deinit` の代わりに 2 つ（`ClipboardManagerCleanup` が無い）と、**`IosClipboardManager` の `@objc dealloc`**（最後の参照を手放したスレッドで呼ばれる。4.3。止まりうる）を含んでいた。

Notification（`IosNotificationManager` と delegate の 3 つのメソッド、`NotificationRepositoryImpl`）には検査が 1 つも入らない。manager は nonisolated の `Sendable` で、delegate のメソッドは隔離されておらず、`UNUserNotificationCenter` は `async` の API で呼び、完了は `Task { @MainActor in }` で main に移すため。`UNUserNotificationCenter` の完了の handler を main actor の closure で受ける形（Swift 6 で止まる典型）は、ライブラリにもサンプルにも無い。

### 4.3 止まりうる所: `IosClipboardManager` を main 以外で手放す

`IosClipboardManager` は `@MainActor` の `NSObject` の部分クラスで、後始末（observer を外す、読み込みを取り消す）を `isolated deinit` で行っていた（Clipboard の設計 v4 の D-16）。Swift 6 では、**`isolated deinit` を持つ `NSObject` の部分クラスの Objective-C の `dealloc` の入口に main actor の検査が入り、最後の参照を main 以外で手放すと、`isolated deinit` が main に移る前にプロセスが止まる**。Swift 5 では同じコードが main に移って後始末をしていた。

- `IosClipboardManager` は `Sendable`（`@unchecked`。前から）で、公開の `init(timeouts:limits:)` があるので、利用者は別のスレッドに渡して手放せる（`shared` は手放されないので当たらない）
- 確かめ: iOS 26.2 のシミュレーターで、`IosClipboardManager(timeouts:limits:)` を作り、`Thread` の中で最後の参照を消す使い捨てのテストを流すと、`_dispatch_assert_queue_fail` ← `_checkExpectedExecutor` ← `@objc IosClipboardManager.__deallocating_deinit` で止まった。macOS の小さなプログラム（`@MainActor` の `NSObject` の部分クラス + `isolated deinit`）でも、Swift 6 では止まり、Swift 5 では main で deinit が走った。`isolated deinit` の無い `NSObject` の部分クラスは Swift 6 でも止まらない
- `ClipboardPasteControlContainerView`（`UIView` の部分クラス + `isolated deinit`）にも同じ検査が入るが、同じ形のテスト（main 以外で最後の参照を消す）では止まらず、deinit は main で走った。`UIView` の解放は UIKit が main で行うため（測った結果からの見立て）。さらに、この型は `Sendable` を宣言していないので、別のモジュール（利用者、`@testable import` のテスト）からは `Sendable` に見えず、Swift 6 の利用者のコードは main 以外へ渡せない（`need(ClipboardPasteControlContainerView.self)` が「does not conform to the 'Sendable' protocol」になること、テストを書こうとして `'inout sending' parameter ... cannot be main actor-isolated` で組めないことを確かめた。モジュールの中では `@MainActor` のクラスとして暗黙に `Sendable`）。直していない

**直し**: 後始末を、`NSObject` でない Swift のクラス `ClipboardManagerCleanup`（`private`、`@MainActor`、`isolated deinit`）に移し、manager から `isolated deinit` を消した。manager は observer の token をこの中に持つ。manager が解放されると、この holder が解放され、その `isolated deinit` が main に移って（main にいればその場で）observer を外し、読み込みを取り消す。Swift の `isolated deinit` は検査で止めずに main に積むので、どのスレッドで手放しても止まらない。`@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` は足していない。

| 振る舞い | 前（Swift 5 の `isolated deinit`） | 後 |
|---|---|---|
| main で手放す | 戻る前に後始末が走る | 同じ（holder の `isolated deinit` がその場で走る。テストで確かめた） |
| main 以外で手放す（Swift 5 で組んだ場合） | manager の解放ごと main に移り、そこで後始末 | manager のメモリはそのスレッドで解放され、後始末だけが main に移る |
| main 以外で手放す（Swift 6 で組んだ場合） | **止まる** | 止まらない。後始末は main で 1 回 |

Clipboard の設計 v4 の D-16（「Manager / Loader / Container は `isolated deinit` を使う」）からは、manager の分だけ形が変わる（後始末を `isolated deinit` で行うことは同じ）。設計書の直しは 1b の Swift の API の設計でまとめて扱う提案にする（8 章）。

### 4.4 サンプル（判定だけ。直したものは無い）

サンプルの 109 個は、SwiftUI の `body` の中の closure（`Button` の action、`@MainActor @Sendable` の完了、`.onAppear`）、`DispatchQueue.main.async`、`Task { @MainActor in }`、`NotificationEventViewModel` の Combine の `sink`（`.receive(on: DispatchQueue.main)` の後）、Clipboard の `startObserving` の受け手（manager が main の observer から呼ぶ）、Preview の closure。どれも main で呼ばれる。

`IosLibraryExampleApp.init` で入れる `onActionReceived` / `onTextInputActionReceived` の closure は、型が `@Sendable`（隔離の無い関数）なので、`App` の main actor を継がず、検査が入らない。delegate の `didReceive` がどのスレッドで呼んでも止まらない（closure の中身はロックと `DispatchQueue.main.async` だけ）。

## 5. 公開 API（swiftinterface）

- `results/swiftinterface/IosLibrary-after-0f.swiftinterface`（0e の 2.6 と同じ組み方）
- `results/swiftinterface/2026-10-25-stage0f.diff`（`IosLibrary-after-0e-dialog.swiftinterface` → `IosLibrary-after-0f.swiftinterface`）

差分は先頭の 2 行だけで、宣言は 1 つも変わっていない。

| 行 | 前 | 後 | 種類 |
|---|---|---|---|
| `swift-compiler-version` | `Apple Swift version 6.2.4 effective-5.10 (...)` | `Apple Swift version 6.2.4 (...)` | 情報 |
| `swift-module-flags` | `-swift-version 5`、`-enable-upcoming-feature StrictConcurrency`、`-enable-bare-slash-regex` がある | `-swift-version 6`。後の 2 つは消えた（Swift 6 で必ず入る） | 追加（interface から組み直す利用者のコンパイラにも Swift 6 の言語モードが渡る。宣言の意味は変わらない） |

4.3 の直しは `private` の型と `private` のプロパティの入れ替えだけなので、interface に出ない。`IosClipboardManager` から `isolated deinit` が消えたことも interface には出ない（deinit は interface に出ない）。

**`shared` の `@MainActor`**（README の 0f の行の「`shared` の `@MainActor` など」）: **付けていない**。理由:

- Swift 6 で `shared` に要るのは、`static let` の型が `Sendable` であることだけ。0e で `IosNotificationManager`・`IosShareManager`・`IosDialogManager`・`NotificationPermissionHelper` を検査付きの `Sendable` にしたので、Swift 6 でもエラーにならない（3 章の 0 件）。`IosClipboardManager` はクラスごと `@MainActor` で、`shared` も前から main actor に隔離されている
- 付けると、nonisolated の文脈（バックグラウンドの `Task`、C ABI の受け口）から `shared` を読むのに `await` が要り、同期の API（`cancel(identifier:)`、`foregroundPresentationOptions` の読み書きなど）が main 以外から呼べなくなる。今の DocC の「どのスレッドから呼んでもよく、完了は main で返る」と、C ABI の受け口（AC-4〜AC-6。main へ移す役を受け口が持つ）の形に合わない
- 付けないことの代わりの損: Clipboard（`@MainActor` のクラス）とほかの 3 機能（nonisolated の `Sendable`、完了だけ main）で隔離の形がそろわない。ほかの 3 機能の manager は、変えられる状態を `Mutex` で守るか（Notification）、持たない（Share・Dialog）ので、main actor に閉じ込める必要は無い
- 後から `@MainActor` を付けるのは破壊的変更なので、付けるなら 2.0.0 の中（1b の Swift の API の設計）で決める

**README 4.1 に足す行の案**:

| 段階 | 変更 | 種類 |
|---|---|---|
| 0f | `IosLibrary` を Swift 6 の言語モードで組む。swiftinterface の `swift-module-flags` が `-swift-version 6` になり、`-enable-upcoming-feature StrictConcurrency` と `-enable-bare-slash-regex` が消える。宣言の差分は無い | 追加 |
| 0f | `shared` に `@MainActor` は付けない（`IosClipboardManager` は前からクラスごと `@MainActor`）。ほかの manager は nonisolated の `Sendable` のまま、どのスレッドからも呼べる | 変更なし（記録） |
| 0f | `IosClipboardManager(timeouts:limits:)` で作った manager を main 以外で手放してもよい（Swift 6 で組むと、`isolated deinit` のままでは止まった。後始末は前と同じく main で 1 回） | 動作 |

Xcode 26.0（D-16 の利用者の下限）で読めるか: **ここでは確かめられない**（手元の Xcode は 26.3 の 1 本だけ）。確かめられたのは、出した 2 つの interface（public と private）を Xcode 26.3 の `swift-frontend -typecheck-module-from-interface` で型検査して通ること（`-F` に組んだ framework の場所を渡す。umbrella の Objective-C のモジュールを読むため）。0f の差分は `swift-module-flags` の `-swift-version 6` だけで、Swift 6.0 以降のどのコンパイラも受け付ける引数である。interface の中で版に頼る所（`$NonescapableTypes`、`$SendingArgsAndResults`、`$IsolatedDeinit` の `#if compiler(>=5.3) && $...` の分岐。`$IsolatedDeinit` は Swift 6.2 で入った機能で、Xcode 26.0 の Swift 6.2 にある）は 0e の interface から変わっていない。したがって、0f は 26.0 で読めるかどうかについて新しい要求を足していない見込みだが、26.0 で実際に `import IosLibrary` を通す確かめは、README の 8.2（1a）のとおり Xcode 26.0 を入れてから行う。

## 6. テスト

### 6.1 足したテスト

| ファイル | 変更 |
|---|---|
| `IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift` | 2 件を足した。`releasingOnMainCancelsLoadsSynchronously`（main で手放すと、戻る前に後始末が main で 1 回走る。前の `isolated deinit` と同じ）、`releasingOffMainDoesNotTrapAndCancelsLoadsOnMain`（`Thread` で最後の参照を消しても止まらず、manager は解放され、後始末は main で 1 回）。参照を運ぶ箱は `Mutex<IosClipboardManager?>` を持つ `Sendable` のクラス |
| `IosLibraryTests/Clipboard/Application/Mock/MockClipboardItemLoader.swift` | `cancelAll()` を呼んだスレッドを記録する `cancelAllOnMainThread` を足した |

**壊して確かめた**: `IosClipboardManager.swift` だけを HEAD に戻して 2 件を流すと、`releasingOffMainDoesNotTrapAndCancelsLoadsOnMain` がテストのプロセスごと止まり（xcresult の失敗は「Crash: xctest at closure #1 in closure #1 in closure #3 in ...releasingOffMainDoesNotTrapAndCancelsLoadsOnMain()」）、`releasingOnMainCancelsLoadsSynchronously` は通った（main で手放す振る舞いは変えていないので、通るのが正しい）。

### 6.2 確かめたこと（シミュレーターだけ）

| 確かめ | 結果 |
|---|---|
| `IosLibraryTests` 全件（`xcodebuild test -scheme IosLibrary -parallel-testing-enabled NO`、iPhone 17 / iOS 26.2） | 211 件すべて成功（0e の後の 209 件 + 6.1 の 2 件） |
| `IosLibraryExampleTests`（`-only-testing`） | 10 件すべて成功 |
| `scripts/test_ios.sh --udid <iPhone 17 / 26.2> --skip-unit`（UI テストの全件） | 列挙 99 件が `Support/DeviceRequirements.json` と完全に一致。99 件を選び（区分で除いたものは 0）、98 件が成功、1 件が skip（`ClipboardUITests` の U10b。0d の基準でも意図した skip）。押したボタンの照合（45 個のボタン、77 件）も通った。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）と比べて changed=0、added=0、removed=0（この実行の外の 196 件は単体テストなどで、比べていない）。結果のフォルダーは `ios/IosLibraryExample/build/test_ios/20261025-132402-iPhone_17-26.2/`（git の外） |
| `scripts/test_ios.sh --udid <iPhone 16 / 18.3> --feature Notification --skip-unit` | 列挙 99 件が一致。42 件を選んで 42 件すべて成功。この環境の基準は無い（D-21 の 2 つの環境ではない） |
| `scripts/test_ios.sh --udid <iPhone 16 / 18.3> --feature Share --skip-unit` | 列挙 99 件が一致。22 件を選んで 22 件すべて成功（0e の 10.4 で直した S5 を含む）。基準は無い |
| 閉じた形のソースの規則（`ios_ui_runner.py check-sources`） | 通った |
| 信頼する部分のハッシュ（`ios_ui_runner.py hashes`） | `TRUSTED_FILES` の 8 個と `FROZEN_CLIPBOARD_SHA256` が `scripts/ios_ui_runner.py` のピンの値と全部同じ。UI テストのフォルダーと `scripts/` は HEAD から変えていない |
| ランナーの自己テスト（`python3 -m unittest scripts/tests/test_ios_ui_runner.py`） | 132 件すべて成功 |
| swiftinterface の型検査 | public と private の 2 つとも通った（5 章） |
| `UnityIosPlugin` がまだ組めるか（0e の 2.1 と同じ組み方。報告だけ） | 0e の第 4 部の後と同じく組めない。エラーは同じ 1 件（`UnityIosDialogManager.swift:177` の `getRootViewController()` の main actor）、警告は同じ 9 件。`UnityIosPlugin` は Swift 5 のまま（触れていない）なので、`IosLibrary` を Swift 6 にしたことで増えた診断は無い（D-22） |

実行の後、2 つのシミュレーターは Shutdown に戻り、`xcodebuild`・Simulator・テストのプロセスは残っていない。

使い捨てのプローブのテスト（4.3 と 6.1 の「壊して確かめた」）がテストのプロセスを止めたので、macOS の `~/Library/Logs/DiagnosticReports/` に `xctest-2026-10-25-*.ips` が 2 つ残っている（シミュレーターのテストのプロセスのクラッシュの記録。消していない）。

## 7. コミットの分け方

`android/.idea/` の 3 つ（作業の前からの変更）は含めない。

| 順 | まとまり | ファイル | 1 行目の案 |
|---|---|---|---|
| 1 | 設定 | `ios/IosLibrary/IosLibrary.xcodeproj/project.pbxproj`、`ios/IosLibraryExample/IosLibraryExample.xcodeproj/project.pbxproj` | `build(ios): switch the library, the sample and their tests to Swift 6` |
| 2 | Clipboard（4.3） | `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift`、`ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift`、`ios/IosLibrary/IosLibraryTests/Clipboard/Application/Mock/MockClipboardItemLoader.swift` | `fix(ios): let IosClipboardManager be released off the main thread under Swift 6` |
| 3 | 記録 | `artifact/topics/ios-c-abi/results/2026-10-25-ios-c-abi-stage0f-working-notes.md`、`artifact/topics/ios-c-abi/results/swiftinterface/IosLibrary-after-0f.swiftinterface`、`artifact/topics/ios-c-abi/results/swiftinterface/2026-10-25-stage0f.diff`（8 章の README の更新を当てるなら `artifact/topics/ios-c-abi/README.md` も） | `docs(artifact): record stage 0f of ios-c-abi` |

1 だけを当てた状態でも組めて、テストも通る（4.3 の不具合は、テストに無い「main 以外で手放す」経路でだけ出る）。2 は 1 の上でだけ意味がある（Swift 5 では前の形でも止まらない）ので、1 → 2 の順にする。Notification・Share・Dialog は直すものが無かった。

## 8. 段階 0f の終わりの README の更新の案（2026-10-25 に反映した）

**状態の行（冒頭）**: 「段階 0e（…）もシミュレーターで完了した（2026-10-25）。実機での確かめと `LastUpgradeCheck` の反映は残る。次は段階 0f」の後半を、次に替える。

> 段階 0f（Swift 6 の言語モード。`IosLibrary`・サンプル・2 つのテストのターゲット）もシミュレーターで完了した（2026-10-25）。次は段階 0g

**5 章の 0f の行**の「内容」の末尾に足す。

> **完了（シミュレーター、2026-10-25）**（`results/2026-10-25-ios-c-abi-stage0f-working-notes.md`）。4 つのターゲットの `SWIFT_VERSION` を 6.0 にした（UI テストのターゲットは D-14 の例外で Swift 5 + minimal のまま）。エラー・警告は 0 件。0e で固定した設定は、Swift 6 の 4 つのターゲットでは 14 個（upcoming feature 13 個と `SWIFT_STRICT_CONCURRENCY`）が効かなくなるが、Swift 5 の UI テストのターゲットが継ぐので外していない。公開 API の宣言の差分は無く（`swift-module-flags` だけ）、`shared` に `@MainActor` は付けない（作業の記録 5 章）。Swift 6 の実行時の隔離の検査で、`IosClipboardManager` を main 以外で手放すと止まることが分かり、後始末を Swift のクラスの `isolated deinit` に移して直した（作業の記録 4.3）

「動作の変更」の列を次に替える。

> Swift の利用者から見た並行性の注釈は変わらない（宣言の差分は無い）。`IosClipboardManager` を main 以外で手放しても止まらない（直さないと、Swift 6 で組んだ `IosLibrary` では止まった）

**4.1 の表**: 5 章の「README 4.1 に足す行の案」の 3 行を足す。

**8.3 の「上げる版」の表**:

- `Swift の言語モード` の行の「理由・注意」に「**済み（0f）**。`IosLibrary`、`IosLibraryTests`、サンプル、`IosLibraryExampleTests`。`IosLibraryExampleUITests` は Swift 5（D-14 の例外）」を足す
- `SWIFT_DEFAULT_ACTOR_ISOLATION`、upcoming feature の行の「Swift 6 では 13 個の固定が効かなくなるので、0f で見直す」を「0f で見直した。Swift 6 の 4 つのターゲットでは 13 個と `SWIFT_STRICT_CONCURRENCY` が効かないが、Swift 5 の UI テストのターゲットのために残した（作業の記録 2.4）」に替える

**1.4 の「Swift の並行性」**の箇条: 末尾に「0e で complete の警告を 0 にし、0f で Swift 6 の言語モードにした（UI テストのターゲットは D-14 の例外）」を足す。

**9 章の DoD**: 「`IosLibrary` とサンプルが Swift 6 の言語モードと strict concurrency complete で、警告が 0（段階 0e・0f）。公開 API の差分を記録している」を `[x]` にし、「（`results/2026-10-25-ios-c-abi-stage0f-working-notes.md`。UI テストのターゲットは D-14 の例外で Swift 5 + minimal）」を足す。

**5.2 の表**の `IosLibrary` の公開 API の行: 「0f（`@MainActor` など）」を「0f（宣言の変更は無かった。`swift-module-flags` だけ）」に替える。

## 9. 残っていること・決めること

**決定（2026-10-25、利用者。どれも推奨のとおり）**: 4.3 の直しを採る。`shared` に `@MainActor` は付けない。8 章の README の更新を当てる。実機での確かめは、0g の後の全件の実行でまとめて行い、0e の 10 章の 3 件（N34・N5・S5）も含める。止まる様子を確かめたときのクラッシュの記録（Mac の `DiagnosticReports` の 2 つ）は消した。

| 項目 | 内容 | 推奨 |
|---|---|---|
| 決めること: 4.3 の直しを採るか | 採ると、Clipboard の設計 v4 の D-16（manager は `isolated deinit`）から形が変わる（後始末を `isolated deinit` で行うことは同じ）。採らない場合は、DocC に「Swift 6 で組んだ版では、main 以外で手放すと止まる」と書くことになる | **採る**。利用者のコードは `Sendable` の型を main 以外へ渡せるので、型が許す使い方で止まる形を残さない |
| 決めること: `shared` の `@MainActor` | 付けない（5 章）。Clipboard とほかの 3 機能の形はそろわないまま | **付けない**。付けるかは 1b の Swift の API の設計で、C ABI の受け口の形と一緒に決める |
| 設計書の追記 | Clipboard の設計 v4 の D-16 に、manager の後始末が `ClipboardManagerCleanup` に移ったことを書く | 1b の Swift の API の設計書で扱う（Clipboard の設計書は出荷済みの版の記録なので、直接は直さない） |
| 前からある unchecked な抜け道（0f では増やしていない。直していない） | `IosClipboardManager: @unchecked Sendable`（利用者から `Sendable` に見せるには明示が要る。暗黙の `Sendable` はモジュールの外に出ない。`@MainActor` のクラスなので、検査付きの `: Sendable` に替えられる見込み。確かめていない）、`ClipboardTemporaryFileStore`・`ClipboardImageCoder`・`ClipboardAsyncRaceCoordinator`・`ClipboardCancellationBox` の `@unchecked Sendable`、`ClipboardTemporaryFileStore.didRunStartupCleanup` の `nonisolated(unsafe)`（`NSLock` で守る）、テストの `MockClipboardTypeIdentifierValidating`、サンプルの `NotificationEventLog`（`NSLock`）。どれも Clipboard の段（NTKIT-14）か 0b からのもの | 1b で、`Mutex` などの検査付きの形に替えられるかを見る |
| Xcode 26.0 で読めるか | 5 章。ここでは確かめられない | 1a で Xcode 26.0 を入れて確かめる（README 8.2） |
| 実機 | 0f では流していない（許可を得ていない）。0f で動作が変わったのは Clipboard の manager を手放す経路だけで、UI テストは通らない経路 | 0g の後の全件の実行（README 7 章の区切り）で、実機の区分の無い 19 件を流す |
| `IosLibraryTests` の件数 | 211 件（0d の基準は 186 件） | 0g の後の全件の実行で基準を取り直す（0e の 7 章と同じ） |
| `LastUpgradeCheck` | 0e の 2.3 のまま | 利用者が Xcode の推奨設定の一覧を見て決める |
