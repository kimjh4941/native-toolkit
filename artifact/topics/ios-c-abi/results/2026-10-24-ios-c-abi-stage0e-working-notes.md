# 段階 0e の作業の記録（共通の設定、Share、Notification、Dialog）

- 記録日: 2026-10-24（第 3 部・第 4 部は 2026-10-25）
- 段階: 0e（`README.md` の 5 章の 0e の行、D-14、D-22、8.3）。共通の設定（第 1 部）、Share（第 2 部）、Notification（第 3 部、8 章）、Dialog（第 4 部、9 章）
- ブランチ: `feature/NTKIT-18`（第 1 部・第 2 部は HEAD `ae1f2a25` の上で作り、`6e804fd6`・`8a557bcc` でコミットした。第 3 部は `9c27e6e6` でコミットした。第 4 部は `9c27e6e6` の上の未コミットの変更）
- 環境: Xcode 26.3（17C529）、Swift 6.2.4、シミュレーター iPhone 17（iOS 26.2、`73A3F720-16B5-45F6-A743-E9D853C92424`）だけ。**第 1 部〜第 4 部では実機に触れていない**（実機は 10 章）
- 状態: 第 1 部〜第 4 部の実装とシミュレーターでの確かめが済み、`IosLibrary`・サンプル・テストの警告は 0 件になった（9.6）。実機では、区分 systemui・sharesheet と区分の無いテストの 60 件のうち 57 件が成功した（10 章。失敗の 3 件は OS の画面の読み方と端末の状態によるもの）。`LastUpgradeCheck`（2.3）は残っている

## 1. 測り方

| 項目 | 方法 |
|---|---|
| 警告の数 | `xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme <IosLibraryExample と IosLibrary> -destination 'platform=iOS Simulator,id=<上の UDID>' -derivedDataPath <scratchpad> SWIFT_COMPILATION_MODE=wholemodule clean build-for-testing`。2 つの scheme で、`IosLibrary`・`IosLibraryTests`・サンプル・`IosLibraryExampleTests`・`IosLibraryExampleUITests` の 5 つのターゲットをすべて組む。数え方は `migration` の 4.3 の正規化（位置と診断文の unique 行）を 2 つのログの和集合にかけたもの。変更の前は `SWIFT_STRICT_CONCURRENCY=complete` をコマンドラインで渡し、後はプロジェクトの設定のまま（上書きしない） |
| build setting の差分 | `xcodebuild -project <p> -target <t> -configuration <Debug/Release> -showBuildSettings` を 5 ターゲット × 2 構成で前と後に取り、`diff` した |
| 意味が変わらないことの確かめ | 上のビルドのログの `swiftc` の呼び出しから、意味に効く引数（`-swift-version`、`-enable-upcoming-feature`、`-enable-experimental-feature`、`-default-isolation`、`-strict-concurrency`、`-enable-bare-slash-regex`、`-target`）をモジュールごとに抜き出して比べた |
| 公開 API | `IosLibrary` を Release・`generic/platform=iOS`・`CODE_SIGNING_ALLOWED=NO` で組み、`arm64-apple-ios.swiftinterface` を写した（2.5） |

測ったログと抜き出した一覧は scratchpad に置き、リポジトリには入れていない。

## 2. 第 1 部: 共通の設定

### 2.1 `UnityIosPlugin` をワークスペースから外した（D-22）

- `ios/IosWorkspace.xcworkspace/contents.xcworkspacedata` から `UnityIosPlugin.xcodeproj` の `FileRef` を消した。`xcodebuild -list` の scheme は `IosLibrary` と `IosLibraryExample` の 2 つになった。ソース（`ios/UnityIosPlugin/`）は残した（段階 3 で消す）
- `scripts/test_ios.sh` と `scripts/ios_ui_runner.py` は、もともと `UnityIosPlugin` を参照していない（`IosLibraryExample` と `IosLibrary` の scheme だけを使い、0d の実行の DerivedData にも `UnityIosPlugin.framework` は無い）。変える所は無かった
- `scripts/build_ios_library_xcframework.sh` と `ios/generate_docc.sh` は、ワークスペースではなく `-project` で組む（`UnityIosPlugin` には `FRAMEWORK_SEARCH_PATHS` で `IosLibrary` の archive を渡す）。ワークスペースから外しても影響しない。スクリプトは変えていない（リリースの動作を黙って変えない）
- 第 2 部の後に、スクリプトの `UnityIosPlugin` の組み方（Release・`generic/platform=iOS Simulator`・`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`・`FRAMEWORK_SEARCH_PATHS` に `IosLibrary` の archive）を scratchpad で同じように流し、**`UnityIosPlugin` はまだ組める**ことを確かめた。警告が 1 件増えた（`UnityIosShareManager.swift:56` の「`@Sendable` を期待する所に non-Sendable の `handler` を渡す」）。`.m` の block は C の関数ポインタしか持たないので（`migration` の案 C の監査）、動作は変わらない。ブリッジには手を入れない（README 4 章）。0f で `IosLibrary` の公開 API がさらに変わると、`-m UnityIosPlugin` の組み立ては失敗しうる。1.x の直しはタグ `1.13.0` から行う（D-22）
- 残るもの: `scripts/README.md`、`ios/generate_docc.sh`、`scripts/publish_docs.sh`、ビルドスクリプトの `UnityIosPlugin` の記述は段階 3 で消す（README 5 章）

### 2.2 テストのターゲットの最小 iOS を 18.0 にした

`IosLibraryTests` と `IosLibraryExampleUITests` は、プロジェクトの階層の 18.2 を継いでいた。`IosLibraryExampleTests` はターゲットに 18.2 を持っていた。2 つの pbxproj の 18.2（プロジェクトの Debug / Release と `IosLibraryExampleTests` の Debug / Release）をすべて 18.0 にした。framework とアプリは前から 18.0 なので変わらない。

### 2.3 Xcode 26 の推奨設定（`LastUpgradeCheck`）は反映していない

`LastUpgradeCheck` / `LastSwiftUpdateCheck` は 1620（Xcode 16.2）のまま、scheme の `LastUpgradeVersion` も 1620 のまま。

理由: 「Update to recommended settings」は Xcode の IDE の機能で、コマンドラインから実行することも、変える項目の一覧を出すこともできない（`xcodebuild` のログにも出ない。調べた範囲で Apple の一覧の文書も無い）。数字だけを上げると、Xcode が何を推奨したかを見ないまま、確かめた印だけを付けることになる。既知の候補の `STRING_CATALOG_GENERATE_SYMBOLS`（Xcode 26 の新しい設定。今は `NO`）は、`IosLibrary` にもサンプルにも `.xcstrings` が無いので、効果が無い。

代わりに、推奨設定で意味が変わりうる設定をプロジェクトの階層で明示的に固定した（2.4）。Xcode で推奨設定を当てても、固定した値は残る。**推奨: 利用者が Xcode でプロジェクトを開いて推奨設定の一覧を見て（変える項目の一覧が出る）、当てた後に 1 章の 3 つ（build setting の差分、`swiftc` の引数、警告の数）を取り直す**。この作業の scratchpad のスクリプトで同じものを取れる。

### 2.4 Swift の設定を固定した

2 つの pbxproj のプロジェクトの階層（Debug / Release）に足した。ターゲットはこれを継ぐ。

| 設定 | 値 | 理由 |
|---|---|---|
| `SWIFT_STRICT_CONCURRENCY` | `complete` | 0e の目標（8.3）。5 つのターゲットすべて |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `nonisolated` | Xcode 26 の既定と同じ値。新しい雛形と推奨設定で `MainActor` になると、注釈の無い宣言の隔離が変わる |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `NO` | 有効にすると 5 つの upcoming feature（下の表の※）がまとめて入る |
| `SWIFT_UPCOMING_FEATURE_*`（Xcode 26.3 の `Swift.xcspec` にある 18 個すべて） | `NO` | 今の値（Swift 5 では既定が `NO`）を明示した。※は Approachable Concurrency の 5 つ。`NONISOLATED_NONSENDING_BY_DEFAULT` は nonisolated の `async` 関数の実行場所を変える |

固定した upcoming feature: `CONCISE_MAGIC_FILE`、`DEPRECATE_APPLICATION_MAIN`、`DISABLE_OUTWARD_ACTOR_ISOLATION`※、`DYNAMIC_ACTOR_ISOLATION`、`EXISTENTIAL_ANY`、`FORWARD_TRAILING_CLOSURES`、`GLOBAL_ACTOR_ISOLATED_TYPES_USABILITY`※、`GLOBAL_CONCURRENCY`、`IMPLICIT_OPEN_EXISTENTIALS`、`IMPORT_OBJC_FORWARD_DECLS`、`INFER_ISOLATED_CONFORMANCES`※、`INFER_SENDABLE_FROM_CAPTURES`※、`INTERNAL_IMPORTS_BY_DEFAULT`、`ISOLATED_DEFAULT_VALUES`、`MEMBER_IMPORT_VISIBILITY`、`NONFROZEN_ENUM_EXHAUSTIVITY`、`NONISOLATED_NONSENDING_BY_DEFAULT`※、`REGION_BASED_ISOLATION`。

注意（0f）: Swift 6 の言語モードでは、`Swift.xcspec` の条件（`EFFECTIVE_SWIFT_VERSION` が 4 / 4.2 / 5 のときだけ）により、Swift 6 で必ず入る 13 個の固定は効かなくなる（入る）。条件の無い 5 つ（`EXISTENTIAL_ANY`、`INFER_ISOLATED_CONFORMANCES`、`INTERNAL_IMPORTS_BY_DEFAULT`、`MEMBER_IMPORT_VISIBILITY`、`NONISOLATED_NONSENDING_BY_DEFAULT`）と `SWIFT_DEFAULT_ACTOR_ISOLATION` の固定は Swift 6 でも効く。`SWIFT_STRICT_CONCURRENCY=complete` は `swiftc` に `-enable-upcoming-feature StrictConcurrency` を渡す（RegionBasedIsolation の診断もこれで出る。`SWIFT_UPCOMING_FEATURE_REGION_BASED_ISOLATION=NO` は引数を足さないだけ）。

### 2.5 変わった build setting（`-showBuildSettings` の差分の全部）

| ターゲット（Debug / Release とも同じ） | 前 → 後 |
|---|---|
| 5 つすべて | `SWIFT_APPROACHABLE_CONCURRENCY`（無し → `NO`）、`SWIFT_DEFAULT_ACTOR_ISOLATION`（無し → `nonisolated`）、`SWIFT_STRICT_CONCURRENCY`（無し → `complete`）、`SWIFT_UPCOMING_FEATURE_*` 18 個（無し → `NO`） |
| `IosLibraryTests`、`IosLibraryExampleTests`、`IosLibraryExampleUITests` | `IPHONEOS_DEPLOYMENT_TARGET` 18.2 → 18.0、`LLVM_TARGET_TRIPLE_OS_VERSION` ios18.2 → ios18.0 |

「無し」は、設定していないので `-showBuildSettings` に出ていなかったもの（Swift のコンパイラの設定は、値を持つまで一覧に出ない）。ほかの build setting は 10 個の一覧のどれでも変わっていない。

`swiftc` の意味に効く引数の差は、全モジュールで `-enable-upcoming-feature StrictConcurrency` が増えたことと、3 つのテストのターゲットの `-target` が `arm64-apple-ios18.2-simulator` → `arm64-apple-ios18.0-simulator` になったことだけ。固定した設定は引数を 1 つも足していない（今の意味のまま）。`swiftinterface` の `swift-module-flags` にも `-enable-upcoming-feature StrictConcurrency` が入る（2.6 の差分の 1 行目）。

第 1 部だけを当てた状態の警告の集合は、変更の前に `complete` を渡したときの集合（423 件）と 1 行も違わなかった。

### 2.6 公開 API の基準（swiftinterface）

置き場所の提案: `artifact/topics/ios-c-abi/results/swiftinterface/`（README 0e の行の「公開 API の差分（swiftinterface）を保存する」を、段階の結果と同じ所に置く。0f・0g・1b の差分も同じフォルダーに足す）。

| ファイル | 中身 |
|---|---|
| `IosLibrary-before-0e-ae1f2a25.swiftinterface` | 0e の前（コミット `ae1f2a25`）の `arm64-apple-ios.swiftinterface`。1.3.0 の公開面の基準 |
| `IosLibrary-after-0e-share.swiftinterface` | 第 1 部と第 2 部を当てた後 |
| `2026-10-24-stage0e-share.diff` | 上の 2 つの `diff -u` |

0e が終わったら（Notification・Dialog の後）、`after` を最終の版に差し替え、差分も取り直す。

## 3. 第 2 部: Share

### 3.1 直したもの

`migration` の案 C（completion を main で返し、handler を `@Sendable` にする。unchecked な抜け道を使わない）に沿った。`@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` は使っていない。

| ファイル | 変更 | 理由（前の警告） |
|---|---|---|
| `Share/Domain/Model/ShareContent.swift`、`ShareItem.swift`、`ShareResult.swift` | `Sendable` を付けた | 値型で、中身もすべて `Sendable`。公開の struct / enum は暗黙に `Sendable` にならない。`sending 'content'`、`sending 'result'`、`non-Sendable type 'ShareResult' cannot be returned` |
| `Share/Application/Port/ShareRepository.swift` | `ShareRepository: Sendable` | `Sendable` の `IosShareManager` が持つ |
| `Share/Application/UseCase/ShareUseCases.swift` | `ShareContentUseCase: Sendable` | 同上 |
| `Share/IosShareManager.swift` | `IosShareManager: NSObject, Sendable`。callback 版の `completion` を `(@Sendable (Bool, Bool, String?, String?) -> Void)?` に。DocC にスレッドの節と `@Sendable` の意味を足した | `static let shared` が concurrency-safe でない、`sending 'self'`、`sending 'completion'`。保持するのは `let` の `Sendable` な値だけなので、検査付きの `Sendable` にできる。`shared` に `@MainActor` は付けない（0f の範囲。README 0f の行） |
| `Share/Presentation/ShareSheetPresenter.swift` | `ShareSheetPresenting: Sendable` にし、要求の `present(items:excluded:)` を `@MainActor` に。`getRootViewController()` を `@MainActor` に | `migration` の 6 章「Share の Presenter は Port 設計の見直しが要る」。要求が nonisolated で実装が `@MainActor` だったので、`[Any]` を渡す所と `ShareResult` を返す所で境界を越えていた。要求を `@MainActor` にし、`ShareRepositoryImpl` が作ったばかりの `[Any]` を渡す形にして、渡してよいことをコンパイラ（region-based isolation）が確かめる。`UIApplication.shared` などの main actor のプロパティの 6 件は、`getRootViewController()` を `@MainActor` にして消えた（呼ぶのは `@MainActor` の `present` だけ） |
| `Share/Data/Repository/ShareRepositoryImpl.swift` | 保持していた `FileManager` を消し、`FileManager.default` をその場で使う。`init(presenter:fileManager:)` → `init(presenter:)`（internal） | `ShareRepositoryImpl` が `Sendable` になり、`FileManager` は `Sendable` でない（`stored property 'fileManager' ... has non-Sendable type`）。`fileManager` を渡す呼び出し元はテストを含めて無かった。`FileManager.default` はスレッドから安全に使える（Apple の文書） |

継続（`withCheckedThrowingContinuation`）を 1 回だけ再開する仕組みと、`completionWithItemsHandler` から `Task { @MainActor in }` で戻す形は変えていない。

### 3.2 公開 API の変更（2.0.0 の破壊的変更として記録する）

`swiftinterface` の差分（`results/swiftinterface/2026-10-24-stage0e-share.diff`）:

| 宣言 | 前 | 後 | 利用者への影響 |
|---|---|---|---|
| `ShareContent`、`ShareItem`、`ShareResult`、`ShareContentUseCase` | 適合無し | `: Sendable` | 足しただけ。ソースは壊れない |
| `protocol ShareRepository` | 適合無し | `: Sendable` | **破壊的**。利用者が自分で適合させた型は `Sendable` が要る（Swift 5 では警告、Swift 6 ではエラー） |
| `IosShareManager` | `NSObject` | `NSObject, Sendable` | 足しただけ |
| `IosShareManager.share(content:completion:)` | `((Bool, Bool, String?, String?) -> Void)?` | `(@Sendable (Bool, Bool, String?, String?) -> Void)?` | **破壊的**（型が変わる）。Swift 5 の minimal では警告も出ない。complete / Swift 6 では、`Sendable` でない値を捕まえた closure が警告 / エラーになる。Objective-C の block の表現は変わらない |
| `swift-module-flags` | - | `-enable-upcoming-feature StrictConcurrency` が増えた | 第 1 部による。interface から組み直す利用者のコンパイラにも同じ引数が渡る |

動作の変更: 無し。`completion` は前から main で返していた（`Task { @MainActor in }`）。早期に失敗する経路（`items` が空）も同じ `Task` を通るので、どのスレッドから呼んでも main で 1 回だけ返る。テストで確かめた（3.3）。

### 3.3 テスト

| ファイル | 変更 |
|---|---|
| `IosLibraryTests/Share/Application/Mock/MockShareRepository.swift`、`Data/Mock/MockShareSheetPresenter.swift` | `@MainActor` を付けた（変えられる状態を持つモックを `Sendable` にするため。`ShareSheetPresenting` の要求と同じ隔離） |
| `ShareContentUseCaseTests`、`IosShareManagerTests` | スイートに `@MainActor`（モックを同じ actor で扱う） |
| `ShareRepositoryImplTests` | モックの presenter を使う 1 件に `@MainActor` |
| `IosShareManagerTests` | 3 件を足した: background のスレッドから呼んで main で返る（成功）、background から空の `items` で呼んで main で失敗が返る（早期の失敗の経路。リポジトリは呼ばれない）、`completion: nil` で trap しない。checked continuation は 2 回目の再開で止まるので、exactly-once も確かめている |

## 4. 警告の数（clean・whole-module・Swift 5 + complete）

| 所 | 0e の前 | 第 1 部の後 | 第 2 部の後 |
|---|---|---|---|
| `IosLibrary` / Dialog | 63 | 63 | 63 |
| `IosLibrary` / Notification | 27 | 27 | 27 |
| `IosLibrary` / Share | 14 | 14 | **0** |
| `IosLibrary` / Clipboard | 0 | 0 | 0 |
| `IosLibraryTests` / Notification | 1 | 1 | 1 |
| `IosLibraryTests` / Share・Clipboard | 0 | 0 | 0 |
| サンプル / Notification（`NotificationSampleView.swift:611` の `@unknown default`） | 1 | 1 | 1 |
| サンプル / Share（`ShareSampleView.swift:280` の `sending 'content'`） | 1 | 1 | **0** |
| `IosLibraryExampleTests` | 0 | 0 | 0 |
| `IosLibraryExampleUITests` | 316 | 316 | 316 |
| 計 | 423 | 423 | 408 |

`IosLibrary` の 104 件（0e の前）は README 0 章の数と一致する。サンプルの Share の 1 件は、`ShareContent` を `Sendable` にして消えた（サンプルのソースは変えていない）。第 2 部で、Share のほかの行は 1 行も増減していない。

**UI テストのターゲットの 316 件**（README の 0 章にも `migration` の 4.2 にも無かった。0e で初めて数えた）: `Support/SampleApp.swift` 146、`Support/Springboard.swift` 89、`Support/ShareSheet.swift` 64、`Support/UnexpectedAlertGuard.swift` 11、`Support/SampleUITestCase.swift` 4、`IosLibraryExampleUITests.swift`（`ClipboardUITests`、凍結）2。ほぼすべてが、iOS 26 の SDK で `@MainActor` の XCUITest の API を nonisolated のテストのコードから呼ぶもの（「main actor-isolated property ... from a nonisolated context」159、「call to main actor-isolated instance method ... in a synchronous nonisolated context」135 など）。**どのファイルも、ランナーが信頼する部分（`TRUSTED_FILES` と `FROZEN_CLIPBOARD_SHA256`）なので、0e では直していない**。直すとハッシュが変わり、0d の設計どおり別のモデルのレビューを通してからハッシュを更新することになる。0f（Swift 6）ではエラーになるので、0f の前に扱いを決める必要がある。

**決定（2026-10-24、利用者）: UI テストのターゲットは例外にする**。`IosLibraryExampleUITests` だけ、ターゲットの階層で `SWIFT_STRICT_CONCURRENCY = minimal` にし、0f でも Swift 5 の言語モードのまま残す。プロジェクトの階層の complete と固定した設定（2.4）は継ぐ。理由: UI テストは配る物に入らない。また、直すと信頼する部分と凍結した `ClipboardUITests` のハッシュが変わり、別のモデルのレビューのやり直し（0d では 3 回）が要る。もう 1 つの案（0f の前に信頼する部分を直し、レビューを通してハッシュを更新する）は採らなかった。直した後の警告は、サンプルの scheme（UI テストまで含む）を clean・whole-module で組んで、UI テストのターゲットが 0 件、`IosLibrary` が 90 件（Dialog 63、Notification 27）、サンプルが 1 件だった。ソースもハッシュも変わらない。

`current-warnings`（0e の前の設定のまま、minimal）は `IosLibrary` 1 件（`allowAnnouncement` の deprecated）とサンプル 1 件（`@unknown default`）。

## 5. 確かめたこと（シミュレーターだけ）

| 確かめ | 結果 |
|---|---|
| `IosLibraryTests` 全件（`xcodebuild test -scheme IosLibrary`、`-parallel-testing-enabled NO`） | 189 件すべて成功（0d の基準 186 件 + 3.3 で足した 3 件）。Share は 27 件 |
| `scripts/test_ios.sh --udid <上の UDID> --feature Share --skip-unit` | 22 件すべて成功（6 章） |
| `IosLibraryExampleTests`（`-only-testing`。最小 iOS を変えたので） | 10 件すべて成功（0d の基準と同じ件数） |
| 閉じた形のソースの規則（`ios_ui_runner.py check-sources`） | 通った |
| 信頼する部分のハッシュ（`ios_ui_runner.py hashes`） | 0d の結果の 2.3 の表と全部同じ。UI テストのフォルダーは変えていない |
| ランナーの自己テスト（`python3 -m unittest scripts/tests/test_ios_ui_runner.py`） | 132 件すべて成功 |
| `UnityIosPlugin` がまだ組めるか（2.1） | 組めた |

## 6. `test_ios.sh --feature Share`

結果のフォルダー: `ios/IosLibraryExample/build/test_ios/20261024-230600-iPhone_17-26.2/`（git の外）。

| 項目 | 結果 |
|---|---|
| 列挙 | 99 件が `Support/DeviceRequirements.json` と完全に一致 |
| 選んだテスト | 22 件（`NavigationUITests` 2、`IdentifierInventoryUITests` 4、`ShareUITests` 16）。区分で除いたものは 0 |
| 結果 | 22 件すべて成功 |
| 基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）との比べ | changed=0、added=0、removed=0（この実行の外の 273 件は比べていない） |

UI テストのビルドは、プロジェクトの設定（complete）のまま組まれた。実行の後、シミュレーターは Shutdown に戻り、`xcodebuild`・Simulator・テストのプロセスは残っていない。

## 7. 残っていること

- Notification と Dialog（0e の後半）。完了を main で返し、handler を `@Sendable` にする（済み。8 章・9 章）
- `LastUpgradeCheck`（2.3）。利用者が Xcode の推奨設定の一覧を見て決める
- 実機（iPhone XS / iOS 18.7.2）で、直した所に関係するテストを流す（README 0e の「両方の環境で流す」）。利用者の許可が要る
- `IosLibraryTests` の件数が基準の 186 から 189 になったので、`test_ios.sh` の単体テストを含む全件の実行では基準と件数が合わない。0g の後の全件の実行で基準を取り直す（README 0g）
- README の表（5 章の 0e の行、8.3 の表の `SWIFT_STRICT_CONCURRENCY`・`SWIFT_DEFAULT_ACTOR_ISOLATION`・最小 iOS の行）の更新は、0e を終えたときにまとめて行う

## 8. 第 3 部: Notification

`migration` の案 C に沿った（操作の完了を全経路で main に 1 回だけ返し、handler を `@Sendable` にする）。`@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` は使っていない。`shared` に `@MainActor` は付けていない（0f）。1.4 の不備（`registerCategory` の完了、category の読んで書き戻す競合、static の権限の受け手など）は直していない（1b）。

### 8.1 直したもの

| ファイル | 変更 | 理由（前の警告） |
|---|---|---|
| `Notification/Domain/Model/` の `NotificationAction`（と `NotificationActionOptions`）、`NotificationAttachment`、`NotificationCategory`、`NotificationCategoryOptions`、`NotificationInterruptionLevel`、`NotificationSound`、`NotificationTrigger`、`TextInputNotificationAction` | `Sendable` を付けた | 値型で、中身もすべて `Sendable`。2 つの `OptionSet` の static の値 7 件（`static property ... is not concurrency-safe`）。`NotificationCategory` と `NotificationTrigger` は操作の `Task` に渡す |
| 同 `NotificationContent`、`ScheduledNotification`、`ActiveNotification` | 変えていない（`Sendable` にしない） | `userInfo` が `[String: Any]` / `[AnyHashable: Any]` で、`Sendable` にできない。8.2 |
| `Application/Port/NotificationRepository.swift` | `NotificationRepository: Sendable` | `Sendable` の manager と use case が持つ |
| `Application/UseCase/` の 15 個の use case | `: Sendable` | 同上。公開の struct は暗黙に `Sendable` にならない |
| `Data/Repository/NotificationRepositoryImpl.swift` | 保持していた `center` を消し、操作のたびに `UNUserNotificationCenter.current()` を読む（private の computed property）。`init(center:)` → `init()`。DocC にスレッドの節 | `UNUserNotificationCenter` は今の SDK で `Sendable` でない（ヘッダーにも apinotes にも注釈が無い）。`init` は `NS_UNAVAILABLE` で、アプリが得られる実体は `current()` だけなので、引数で別の center を渡すことはもともとできなかった（テストにも呼び出し元にも使う所が無い）。`init` のログは `[init] center: ...` → `[init]` |
| `Presentation/Permission/NotificationPermissionHelper.swift` | `: Sendable` | `static let shared`（1 件）。`let` の `Sendable` な repository だけを持つ |
| `IosNotificationManager.swift` | `NSObject, Sendable`。操作の完了 9 個（`show`、`update`、`schedule`、`requestPermission`、`setBadgeCount`、`getScheduled`、`getDelivered`、`hasPermission`、`authorizationStatus`）を `@MainActor @Sendable` にし、全経路（成功と失敗）で `Task { @MainActor in completion(...) }` を通す。`show`・`update`・`schedule` の `content` を `sending` に。`NotificationActionHandler` と `NotificationTextInputActionHandler` を `@Sendable` に。`foregroundPresentationOptions`・`onActionReceived`・`onTextInputActionReceived` を `Mutex`（`Synchronization`。iOS 18 から）で守る computed property に。DocC にスレッドの節 | `static let shared`（1 件）、`passing closure as a 'sending' parameter`（17 件。分離していないクラスの `self` と、`Sendable` でない完了・`content` を `Task` に渡していた）。変えられる 3 つのプロパティは、アプリが書き、delegate のコールバックが（文書に書かれていないスレッドで）読むので、`Sendable` にするには守りが要る |

delegate のメソッド（`willPresent`・`didReceive`・`openSettingsFor`）の振る舞いは変えていない。`onActionReceived` / `onTextInputActionReceived` は、今までどおり `didReceive` の中で同期的に、system の `completionHandler` の前に呼ぶ（README 0e の行にアクションのスレッドの変更は無いので、main へは移していない）。

### 8.2 型の選び方

- **完了は `@MainActor @Sendable`**（Share は `@Sendable` だけ）。初めに Share と同じ `@Sendable` だけで組むと、サンプルに 30 件の警告が出た。サンプルの完了は SwiftUI の view の中で書かれ、main actor の `updateResult` を呼ぶ（26 件）。`@Sendable` だけの closure は nonisolated になるので、main で呼ばれると分かっていても、利用者が `MainActor.assumeIsolated` などで包み直す必要がある。`@MainActor` を型に付けると、main で返すという約束を型で示し、main actor の側で書いた closure がそのまま main actor の状態を使える。サンプルの完了のコードは 1 行も変えずに 26 件と、`requirePermission` の `action` を捕まえる 1 件が消えた。ライブラリは `Task { @MainActor in }` から呼ぶので、型の約束をコンパイラが確かめる。`@Sendable` の非 isolated な関数値は暗黙に `@MainActor @Sendable` へ変換できるので、渡す側は書き換えなくてよい。**Share との不揃いは残る**（8.9 の提案）
- **`content` は `sending`**。`NotificationContent` の `userInfo: [String: Any]` を `Sendable` な型（`[String: any Sendable]`）に変えると、Swift 5 の利用者も含めて `[String: Any]` の値を渡すコードが壊れ、JSON から作る値（入れ子の `NSArray`）も入らなくなる。`@unchecked Sendable` は、利用者が `NSMutableArray` などを入れられるので事実に反する。`sending` は Swift 5 の minimal では何も診断せず、complete / Swift 6 では「渡した後に使わない値」であることをコンパイラが確かめる。代わりに、main actor の関数が返した値はそのままでは渡せない（main actor の領域に属する）。サンプルの 9 件はこれで、作る関数の戻り値を `sending` にした（8.5）
- **結果の配列は `Sendable` にせずに main へ運ぶ**。`getScheduled` / `getDelivered` は nonisolated の `Task` で use case を呼び、その戻り値（引数がすべて `Sendable` なので、どこにも繋がっていない値）を `Task { @MainActor in completion(result) }` に渡す（`Task` の closure は `sending`）。`sending` の `@MainActor` closure を受ける共通の helper を一度作ったが、Swift 6.2.4 の region の検査が「pattern that the region based isolation checker does not understand」を 12 件、結果を運ぶ 2 か所で `passing closure as a 'sending' parameter` を 2 件出したので、各所に `Task { @MainActor in }` を書く形にした
- **`Mutex`**: 標準ライブラリの `Synchronization` の `Mutex` を使う（iOS 18.0 から。`IosLibrary` の最小 iOS は 18.0）。`swiftinterface` に `import Synchronization` が増える。最小 iOS を 18 より下げる場合は `OSAllocatedUnfairLock`（iOS 16 から）などに替える必要がある

### 8.3 公開 API の変更（2.0.0 の破壊的変更として記録する）

`swiftinterface` の差分: `results/swiftinterface/2026-10-24-stage0e-notification.diff`（`IosLibrary-after-0e-share.swiftinterface` → `IosLibrary-after-0e-notification.swiftinterface`）。出した interface は `swift-frontend -typecheck-module-from-interface` で型検査が通った（ビルドの設定は `-no-verify-emitted-module-interface`）。

| 宣言 | 前 | 後 | 利用者への影響 |
|---|---|---|---|
| 8.1 の値型 9 個、use case 15 個、`NotificationPermissionHelper`、`IosNotificationManager` | 適合無し / `NSObject` | `: Sendable` を足した | 足しただけ |
| `protocol NotificationRepository` | 適合無し | `: Sendable` | **破壊的**。利用者が自分で適合させた型は `Sendable` が要る（Swift 5 + complete では警告、Swift 6 ではエラー） |
| `NotificationRepositoryImpl.init(center:)` | `init(center: UNUserNotificationCenter = .current())` | `init()` | **破壊的**（ソース）。`NotificationRepositoryImpl()` と書く呼び出しは壊れない。`center:` を書いた呼び出しは消す（渡せる値は `.current()` だけだった） |
| 操作の完了 9 個 | `((Bool, String?) -> Void)?` など | `(@MainActor @Sendable (Bool, String?) -> Void)?` など | **破壊的**（型が変わる）。Swift 5 の minimal では警告も出ない。complete / Swift 6 では、`Sendable` でない値を捕まえた closure が警告 / エラーになる。closure の本体は main actor に隔離される |
| `show` / `update` / `schedule` の `content` | `NotificationContent` | `sending NotificationContent` | **破壊的**（complete / Swift 6 のみ）。渡した後に使う値、main actor などに属する値を渡すと警告 / エラー。minimal では変わらない。古いコンパイラ向けの分岐（`__owned`）が interface に出る |
| `NotificationActionHandler`、`NotificationTextInputActionHandler` | `(...) -> Void` | `@Sendable (...) -> Void` | **破壊的**（型が変わる）。影響は完了と同じ |
| `foregroundPresentationOptions`、`onActionReceived`、`onTextInputActionReceived` | 保存プロパティ | `{ get set }` の computed property | ソースは変わらない（interface の表現だけ）。どのスレッドから読み書きしてもよくなった |
| `import Synchronization` | - | 増えた | iOS 18 の SDK で組む利用者には影響しない |

### 8.4 動作の変更

| 変更 | 前 | 後 |
|---|---|---|
| 操作の完了のスレッド（README 0e の行、1.3） | 分離していないクラスの `Task {}` から返り、main の保証が無かった（シミュレーターのテストでは 9 個とも main 以外で返った。8.6） | どのスレッドから呼んでも main で 1 回だけ、いつも非同期に返る |
| `NotificationRepositoryImpl.init` のログ | `[init] center: <UNUserNotificationCenter: 0x...>` | `[init]` |

ほかの動作は変えていない。完了はもともと 1 回だけ、非同期に返っていた（早期に返る経路は `IosLibrary` の Notification には無い。1.3 の「JSON の解析の失敗と `registerCategory` は呼び出し元のスレッドで同期的に返る」はブリッジの話で、ブリッジは変えていない）。`cancel` などの完了の無い操作と、delegate の 3 つのメソッドは前のまま。

### 8.5 サンプル

`NotificationSampleView.swift` だけを変えた。動作は変わらない。

- `makeContent(id:title:body:)` と `makeContentWithAppIconAttachment(id:title:body:)` の戻り値を `sending NotificationContent` にした（9 件の `sending 'content'`）。中で新しく作った値を返しているだけなので、コンパイラが確かめて通る
- **0e の前からの 1 件（611 行の `@unknown default`）**: `NotificationAuthorizationStatus` は `IosLibrary`（library evolution で組む）の `@frozen` でない公開の enum なので、別のモジュールの `switch` は、後の版で case が増える場合に備えて `@unknown default` が要る（Swift 6 ではエラー）。今の 6 個の case はすべて書かれているので、足した節には今の `IosLibrary` では決して来ない。`@unknown default: return "unknown"`（注釈付き）を足した。**動作に影響しない自明な直しなので直した**。enum を `@frozen` にする直し方は公開 API を変えるので採らなかった
- 完了の型を `@MainActor @Sendable` にしたことで、完了のコードは変えずに済んだ（8.2）

UI テストのフォルダー、`Support`、`ClipboardUITests` には触れていない。閉じた形のソースの規則は、サンプルのボタンの識別子を読むが、識別子は変えていない。

### 8.6 テスト

| ファイル | 変更 |
|---|---|
| `IosLibraryTests/Notification/Application/Mock/MockNotificationRepository.swift` | `NotificationRepository` が `Sendable` になったので、変えられる状態を `Mutex` の中に移した（Share のモックのような `@MainActor` は、同期の要求 `openNotificationSettings()` と、`Sendable` でない戻り値の要求を満たせない）。`ScheduledNotification` / `ActiveNotification` は `Sendable` でないので、スタブは `@Sendable` の factory（`makeScheduled` / `makeDelivered`）にして、呼ぶたびに新しい値を作る |
| `NotificationQueryUseCasesTests.swift` | スタブを factory に合わせた |
| `IosNotificationManagerTests.swift` | 0e の前からの 1 件（63 行の `sending 'scheduled'`。`Sendable` でない配列を継続へ渡していた）は、確かめる欄だけを取り出して渡す形にした。11 個を足した: background のスレッドから呼んで、完了が main で 1 回だけ返る（`show`・`update`・`schedule`・`setBadgeCount`・`requestPermission` は成功と失敗の 2 通り、`getScheduled`・`getDelivered`・`hasPermission`・`authorizationStatus`。計 13 ケース）、`completion: nil` で trap しない、delegate の設定を別のスレッドから変えられる |

1 回だけを確かめるため、完了の呼び出しをすべて記録し、最初の呼び出しの後さらに 200 ms 待ってから件数が 1 であることを見る。**足した 9 個のテスト（13 ケース）は、HEAD の `IosNotificationManager.swift` に戻して流すと、13 ケースすべてが main のスレッドの確かめで失敗した**（今の版ではすべて成功）。

### 8.7 警告の数（clean・whole-module・Swift 5 + complete。1 章と同じ測り方）

| 所 | 第 2 部の後（UI テストを minimal にした後） | 第 3 部の後 |
|---|---|---|
| `IosLibrary` / Dialog | 63 | 63（行も診断文も同じ） |
| `IosLibrary` / Notification | 27 | **1**（`allowAnnouncement` の deprecated。8.9） |
| `IosLibrary` / Share・Clipboard | 0 | 0 |
| `IosLibraryTests` / Notification | 1 | **0** |
| サンプル / Notification | 1 | **0** |
| `IosLibraryExampleTests`、`IosLibraryExampleUITests` | 0 | 0 |
| 計 | 92 | 64 |

`swiftc` の意味に効く引数は、2 つの scheme とも第 2 部の後と同じだった。

### 8.8 確かめたこと（シミュレーターだけ）

| 確かめ | 結果 |
|---|---|
| `IosLibraryTests` 全件（`-parallel-testing-enabled NO`） | 200 件すべて成功（第 2 部の後の 189 件 + 8.6 で足した 11 件。引数付きのテストは 1 件と数える） |
| `IosLibraryExampleTests`（`-only-testing`） | 10 件すべて成功 |
| `scripts/test_ios.sh --udid <シミュレーター> --feature Notification --skip-unit` | 列挙 99 件が `Support/DeviceRequirements.json` と完全に一致。42 件を選び（`NotificationPermissionUITests` 2、`NavigationUITests` 2、`IdentifierInventoryUITests` 4、`NotificationUITests` 23、`NotificationEventUITests` 7、`NotificationColdStartUITests` 4。区分で除いたものは 0）、42 件すべて成功。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）と比べて changed=0、added=0、removed=0（この実行の外の 253 件は比べていない）。結果のフォルダーは `ios/IosLibraryExample/build/test_ios/20261024-235044-iPhone_17-26.2/`（git の外） |
| 閉じた形のソースの規則（`ios_ui_runner.py check-sources`） | 通った |
| 信頼する部分のハッシュ（`ios_ui_runner.py hashes`） | `TRUSTED_FILES` の 8 個と `FROZEN_CLIPBOARD_SHA256` がピンの値と全部同じ。UI テストのフォルダーと `scripts/` は HEAD から変えていない |
| `UnityIosPlugin` がまだ組めるか（2.1 と同じ組み方） | 組めた。警告が 6 件増えた（`UnityIosNotificationManager.swift` の「`@Sendable` を期待する所に non-Sendable の `completion` を渡す」。Share の 1 件と同じ種類）。ブリッジには手を入れない（D-22） |

実行の後、シミュレーターは Shutdown に戻り、`xcodebuild`・Simulator・テストのプロセスは残っていない。

### 8.9 残っていること

- 既存のログは全パラメータを出していない（例: `[show] content.id` だけ）。今回は変えていない（1.4・1b のログの規則の直しでまとめて扱う）
- 実機での確かめ（D-21）。利用者の許可が要る
- `IosLibraryTests` の件数は 200 件になった（基準は 186 件。7 章と同じく 0g の後に取り直す）
- swiftinterface の置き方（8.10 で決めた）: 段ごとの版（`IosLibrary-after-0e-share`、`IosLibrary-after-0e-notification`、Dialog の後に `IosLibrary-after-0e-dialog`）と、その前の版との差分を残し、0e の終わりに `IosLibrary-before-0e-ae1f2a25` → 最後の版の通しの差分（`2026-10-24-stage0e.diff`）を足す。2.6 の「`after` を最終の版に差し替える」より、段ごとの差分が後から読める

### 8.10 決めたことと、その反映（2026-10-25、利用者。どれも推奨のとおり）

| 決めたこと | 反映 |
|---|---|
| `allowAnnouncement` は案 A | `NotificationRepositoryImpl.makeUNCategory` で `UNNotificationCategoryOptions` に写すのをやめた（注釈を 1 行残した）。公開の `NotificationCategoryOptions.allowAnnouncement` に `@available(*, deprecated, message:)` を付け、DocC に「iOS 15 から OS が無視する。効果は無い」と書いた。値（`1 << 3`）は残すので、使っているコードは警告が出るだけで組める。**2.0.0 の変更として記録する**（登録した category の `options` から bit が消える。OS の振る舞いは変わらない）。これを使っていたテスト（`NotificationContentTests` の `OptionSet` のテスト）は `hiddenPreviewsShowTitle` に、サンプルの `registerCategory` のボタンは `[.customDismissAction]` に替えた（どちらも動作は変わらない。サンプルの UI テストは 8.10 の下の表） |
| Share の完了も `@MainActor @Sendable` にそろえる | `IosShareManager.share(content:completion:)` の completion を `(@MainActor @Sendable (Bool, Bool, String?, String?) -> Void)?` にした。もとから `Task { @MainActor in }` の中で呼んでいるので、本体は変えていない。Dialog も同じ形にする |
| swiftinterface の置き方 | 段ごとの版と、その前の版との差分を残す。0e の終わりに通しの差分を足す。この 2 つの反映は、Notification の段の版（`IosLibrary-after-0e-notification.swiftinterface`）と差分を取り直して含めた |

反映の後の確かめ（シミュレーターだけ）:

| 確かめ | 結果 |
|---|---|
| 警告の数（2 つの scheme を clean・whole-module で） | `IosLibrary` の Dialog の 63 件だけ。Notification・Share・Clipboard、テスト、サンプル、UI テストは 0 件 |
| `IosLibraryTests` 全件 | 200 件すべて成功 |
| `IosLibraryExampleTests` | 10 件すべて成功 |
| `scripts/test_ios.sh --feature Notification --skip-unit` | 列挙 99 件が一致。42 件を選んで 42 件すべて成功。基準と比べて changed=0、added=0、removed=0（この実行の外の 253 件は比べていない）。`registerCategory` のボタンを含む |
| swiftinterface | `IosLibrary-after-0e-notification.swiftinterface` を同じ組み方（2.6）で作り直し、`2026-10-24-stage0e-notification.diff` を取り直した。`allowAnnouncement` の `@available(*, deprecated, ...)` と、Share の completion の `@_Concurrency.MainActor @Sendable` が入る |

実行の後、シミュレーターは Shutdown に戻り、`xcodebuild`・テストのプロセスは残っていない。

## 9. 第 4 部: Dialog

`migration` の案 C と 8.10 の決定（Dialog の完了も `@MainActor @Sendable`）に沿った。`@unchecked Sendable`、`nonisolated(unsafe)`、`@preconcurrency` は使っていない。`shared` に `@MainActor` は付けていない（0f）。1b の作業（ブリッジの結果のまとめを `IosLibrary` へ移す、Dialog を層に分ける、1.4 の不備、ログの規則）には手を付けていない（9.8 に見つけたものを書いた）。直したのは `Dialog/IosDialogManager.swift` の 1 ファイルだけで、サンプルは変えていない。

### 9.1 0e の前の警告（63 件）

| 種類 | 件数 | 所 |
|---|---|---|
| `UIAlertAction.init` を呼び出し元のスレッドで呼ぶ（main actor の初期化子と、`handler` の closure を渡す `sending`） | 14 | 便利なメソッド 4 つ（`showAlert`・`showConfirmDialog`・`showDestructiveDialog`・`showActionSheet`）が、`UIAlertAction` を main に移る前に作っていた |
| `getRootViewController()` が UIKit の main actor のプロパティを読む | 7 | `UIApplication.shared`、`connectedScenes`、`activationState`、`windows`、`isKeyWindow`、`rootViewController`、`presentedViewController` |
| `Sendable` でない完了・ボタンの callback・`textFields` を `DispatchQueue.main.async` と `UIAlertAction` の handler に渡す（capture と `sending`） | 23 | 6 つの `show...` |
| `Sendable` でない `self` を `DispatchQueue.main.async` に渡す、`static let shared` | 7 | クラスが `Sendable` でない |
| observer の block（`@Sendable`）から `isEnabled`・`text`・`textFields` を使う | 12 | テキスト入力とログインの、空のときにボタンを止める observer |

### 9.2 直したもの

| 変更 | 理由 |
|---|---|
| `IosDialogManager` を `public final class IosDialogManager: NSObject, Sendable` に | 保持するのは `let TAG`（`String`）だけなので、検査付きの `Sendable` にできる。`Sendable` のクラスは `final` が要る。`init` は `private` で、もとから外のモジュールは継承できない（`open` でない）ので、`final` は利用者に影響しない |
| 完了 7 個とボタンの callback 10 個（`onButton`、`onConfirm` 2、`onCancel` 4、`onDestructive`、`onAction`、`onLogin`）を `(@MainActor @Sendable (...) -> Void)?` に | 8.10 の決定。どれも main で呼ばれる（完了は main の block の中か `present` の完了、ボタンは `UIAlertAction` の handler）。`@Sendable` は呼び出し元のスレッドから main へ運ぶため、`@MainActor` は呼ばれる所を型で示すため |
| `showDialog` の `textFields` を `[@MainActor @Sendable (UITextField) -> Void]?` に | main へ運び、`addTextField(configurationHandler:)` が main で呼ぶ |
| `getRootViewController()` を `@MainActor` に | UIKit の状態を読むので main actor でしか正しく動かない。7 件の警告がこれで消えた。**公開 API の変更で、`UnityIosPlugin` の組み立てを壊す**（9.7） |
| `showDialog` の main の block の中身を `@MainActor private func presentDialog(...)` に移し、便利なメソッド 4 つは、`UIAlertAction` を作る所から main の block（`DispatchQueue.main.async`）の中で行って `presentDialog` を呼ぶ形に | `UIAlertAction` は main actor のクラスで、前は呼び出し元のスレッドで作っていた（14 件）。main へ移るのは前と同じ 1 回だけで、時機は変わらない |
| observer の block の中を `MainActor.assumeIsolated { }` で包んだ（3 か所） | observer は `queue: .main` で登録しているので、block は main で動く。`assumeIsolated` はそれを実行時に確かめる（main 以外なら止まる）。`Task { @MainActor in }` にすると、ボタンの有効・無効の切り替えが 1 回遅れ、UI テスト（D8・D11）の見る振る舞いが変わりうるので採らなかった。observer を外さない不備（1.4）は直していない |
| DocC の「Thread Safety」を「Threading」に書き直した | どのスレッドから呼べるか、何が main で返るか、型の意味、`getRootViewController()` は main actor で呼ぶこと、完了が呼ばれない既知の 2 つの経路（9.4）を書いた |

`DispatchQueue.main.async` は `Task { @MainActor in }`（Notification）に替えていない。Swift 6.2.4 は `DispatchQueue.main.async` に渡す closure を main actor に隔離されたものとして扱う（前の警告にも「in an isolated closure」と出ていた）ので、警告は出ない。替えると、main で呼んだときの順序（main の queue に積む順）が変わりうる。サンプルの UI テスト（D14・D15 の 1 回だけの確かめ）は今の順序の上で通っている。

`@MainActor` を型の一部（`shared` 以外のメソッド）に付けるかは次のように決めた。`show...` の 7 つは、今の DocC の「どのスレッドから呼んでもよい」を保ち、C ABI（AC-4〜AC-6）の受け口としても main へ移す役を持つので、nonisolated のままにした。`UIAlertAction`・`UIView`・`UIBarButtonItem` を引数に取るが、どれも main actor のクラスで `Sendable` なので、運ぶことに問題は無い（作るのは呼び出し元の main actor）。UIKit の状態を同期的に返す `getRootViewController()` だけを `@MainActor` にした。

### 9.3 公開 API の変更（2.0.0 の破壊的変更として記録する）

`swiftinterface` の差分: `results/swiftinterface/2026-10-24-stage0e-dialog.diff`（`IosLibrary-after-0e-notification.swiftinterface` → `IosLibrary-after-0e-dialog.swiftinterface`）。2.6 と同じ組み方で作り、`swift-frontend -typecheck-module-from-interface` で型検査が通った。0e の通しの差分は `results/swiftinterface/2026-10-24-stage0e.diff`（`IosLibrary-before-0e-ae1f2a25.swiftinterface` → `IosLibrary-after-0e-dialog.swiftinterface`）。

| 宣言 | 前 | 後 | 利用者への影響 |
|---|---|---|---|
| `IosDialogManager` | `public class ...: NSObject` | `final public class ...: NSObject, Sendable` | 足しただけ（`final` は、もとから外のモジュールで継承できないので影響しない）。interface では各メソッドに `final` が付く |
| `show...` の 7 つの完了 | `((Bool, String?) -> Void)?` | `(@MainActor @Sendable (Bool, String?) -> Void)?` | **破壊的**（型が変わる）。Swift 5 の minimal では警告も出ない。complete / Swift 6 では、`Sendable` でない値を捕まえた closure が警告 / エラーになる。closure の本体は main actor に隔離される |
| ボタンの callback 10 個 | `((String?, Bool, String?) -> Void)?` など | `(@MainActor @Sendable (String?, Bool, String?) -> Void)?` など | **破壊的**。影響は完了と同じ |
| `showDialog` の `textFields` | `[(UITextField) -> Void]?` | `[@MainActor @Sendable (UITextField) -> Void]?` | **破壊的**。影響は完了と同じ |
| `getRootViewController()` | nonisolated | `@MainActor` | **破壊的**（Swift 5 の minimal でも）。main actor でない同期の文脈から呼ぶとエラーになる。`UnityIosPlugin` の 1 か所がこれに当たる（9.7）。SwiftUI の `Button` の action（main actor）から呼ぶサンプルは変わらない |

### 9.4 動作の変更

| 変更 | 前 | 後 |
|---|---|---|
| 便利なメソッド 4 つ（`showAlert`・`showConfirmDialog`・`showDestructiveDialog`・`showActionSheet`）の `UIAlertAction` を作るスレッド | 呼び出し元のスレッド（main 以外から呼ぶと、UIKit のオブジェクトを main 以外で作っていた） | main（main へ移る `DispatchQueue.main.async` の中）。main から呼ぶ場合は、見える違いは無い |
| 同じ 4 つのログ | 自分のログの後に、中で呼ぶ `showDialog` の `showDialog called with ...` が出ていた | `showDialog` を通らないので、その行が出ない。自分の行（`showAlert called with ...` など）と、失敗の `Failed to get root view controller` は前と同じ |

ほかの動作は変えていない。完了とボタンの callback は前から main で、非同期に返っていた（README 1.3 の Dialog の行の「`showActionSheet` は呼び出し元のスレッドで探す」はブリッジの `UnityIosDialogManager` の話で、`IosLibrary` の `showActionSheet` は前から main で探していた）。完了は、呼ばれる経路では前から 1 回だけだった。

**完了が 1 回も呼ばれない経路が 2 つある（前から。直していない）**:

1. `showLoginDialog` で前面の ViewController が見つからないとき、失敗は `onLogin`（`(nil, nil, nil, false, message)`）で返り、`completion` は呼ばれない。1.4 の「失敗の返し方が揃っていない」で、1b で Dialog の結果の型にまとめるときに直す。今の振る舞いをテストで固定した（9.5）
2. UIKit が表示を断ったとき（見つけた ViewController が window に無い、など）、`present(_:animated:completion:)` の完了が呼ばれないので、`completion` も呼ばれない。シミュレーターで、window に無い ViewController から `present` して確かめた（UIKit が「whose view is not in the window hierarchy」を出し、完了は 1 秒待っても呼ばれなかった。確かめのテストはリポジトリに残していない）。**1.4 に無い不備**。1b のエラーの型を作るときに、表示の後に `presentingViewController` を見るなどで失敗を返す形を決める

どちらも DocC の「Threading」に既知の欠けとして書いた。

### 9.5 テスト

Dialog のテストはどのターゲットにも無かった（README 1.4）。`IosLibraryTests/Dialog/IosDialogManagerTests.swift` を足した（9 件。フォルダーは pbxproj と同期するので、pbxproj は変えていない）。

`IosLibraryTests` はホストのアプリを持たない（`TEST_HOST` が無い）ので、テストのプロセスには前面の `UIWindowScene` が無く、`show...` はどれも「前面の ViewController が見つからない」経路を通る。本物の UI を出さずに確かめられるのはこの経路で、表示した後の経路はサンプルの UI テスト（D1〜D15）が見る。各テストは初めに `getRootViewController()` が `nil` であることを `#require` で確かめ、ホストが付いて本物の UI を出してしまう形では先へ進まない。

| テスト | 確かめること |
|---|---|
| `showDialog`・`showAlert`・`showConfirmDialog`・`showDestructiveDialog`・`showActionSheet`・`showTextInputDialog` の 6 件 | background のスレッドから呼んで、`completion` が main で 1 回だけ `(false, "Failed to get root view controller")` で返る。ボタンの callback は呼ばれない |
| `showLoginDialog` | background から呼んで、`onLogin` が main で 1 回だけ `(nil, nil, nil, false, message)` で返り、`completion` と `onCancel` は呼ばれない（9.4 の 1。今の振る舞いを固定する） |
| main から呼んだとき | 呼び出しが戻る前には `completion` が呼ばれず、後で main で 1 回だけ返る（いつも非同期） |
| callback がすべて `nil` | 7 つを background から呼んで trap しない |

1 回だけを確かめるため、呼び出しをすべて記録し、最初の呼び出しの後さらに 200 ms 待つ（8.6 と同じ）。最初の呼び出しを待つ上限は 30 秒にした。シミュレーターを起動した直後の最初の実行で、プロセスで最初の `UIAlertAction` を作るのに main で 5 秒余りかかり、5 秒の上限では `showAlert` の 1 件が落ちたため（2 回目からは 0.2 秒ほど）。

**HEAD（`9c27e6e6`）の `IosDialogManager.swift` に戻して流すと、9 件すべてが通った**（今の版でもすべて通る）。Notification（8.6）と違い、確かめられる経路は HEAD でも main で 1 回だけ返っていたので、このテストは HEAD の不備を捕まえるものではなく、契約を守るための回帰のテストである。0e で変えた振る舞いのうち、`UIAlertAction` を作るスレッド（9.4）は UI を出さないと見えず、型の変更（`@MainActor @Sendable`、`getRootViewController()` の `@MainActor`）はコンパイラが確かめる。

### 9.6 警告の数（clean・whole-module・Swift 5 + complete。1 章と同じ測り方）

| 所 | 第 3 部の後（`9c27e6e6`） | 第 4 部の後 |
|---|---|---|
| `IosLibrary` / Dialog | 63 | **0** |
| `IosLibrary` / Notification・Share・Clipboard | 0 | 0 |
| `IosLibraryTests`（足した Dialog のテストを含む） | 0 | 0 |
| サンプル（`IosLibraryExample`） | 0 | 0 |
| `IosLibraryExampleTests`、`IosLibraryExampleUITests` | 0 | 0 |
| 計（2 つの scheme の和集合） | 63 | **0** |

`swiftc` の意味に効く引数は、2 つの scheme とも第 3 部の後と同じだった。サンプルは 1 行も変えずに 0 件のまま（完了とボタンの callback は SwiftUI の view の中で書かれ、`@MainActor` の型なので main actor の `updateResult` をそのまま呼べる）。

0e を通した数: 0e の前に `complete` を渡したときは 423 件（`IosLibrary` 104、テスト 1、サンプル 2、UI テスト 316）。0e の後は 0 件（UI テストのターゲットは D-14 の例外で minimal）。

### 9.7 確かめたこと（シミュレーターだけ）

| 確かめ | 結果 |
|---|---|
| `IosLibraryTests` 全件（`-parallel-testing-enabled NO`） | 209 件すべて成功（第 3 部の後の 200 件 + 9.5 の 9 件） |
| `IosLibraryExampleTests`（`-only-testing`） | 10 件すべて成功 |
| `scripts/test_ios.sh --udid <シミュレーター> --feature Dialog --skip-unit` | 列挙 99 件が `Support/DeviceRequirements.json` と完全に一致。21 件を選び（`NavigationUITests` 2、`IdentifierInventoryUITests` 4、`DialogUITests` 15。区分で除いたものは 0）、21 件すべて成功。基準（`scripts/test_ios.baseline.iPhone_17-26.2.json`）と比べて changed=0、added=0、removed=0（この実行の外の 274 件は比べていない）。結果のフォルダーは `ios/IosLibraryExample/build/test_ios/20261025-090535-iPhone_17-26.2/`（git の外） |
| 閉じた形のソースの規則（`ios_ui_runner.py check-sources`） | 通った |
| 信頼する部分のハッシュ（`ios_ui_runner.py hashes`） | `TRUSTED_FILES` の 8 個と `FROZEN_CLIPBOARD_SHA256` がピンの値と全部同じ。UI テストのフォルダー、`scripts/`、サンプルは HEAD から変えていない |
| swiftinterface | 9.3 のとおり。型検査が通った |
| `UnityIosPlugin` がまだ組めるか（2.1 と同じ組み方。シミュレーターのスライス） | **組めなくなった**。エラー 1 件: `UnityIosDialogManager.swift:177`（`showActionSheet` の中）の「call to main actor-isolated instance method 'getRootViewController()' in a synchronous nonisolated context」。警告は第 3 部の後と同じ 9 件（Notification 6、Share 1、`allowAnnouncement` の deprecated 1、`@unknown default` 1）。ブリッジには手を入れていない（D-22） |

実行の後、シミュレーターは Shutdown に戻り、`xcodebuild`・Simulator・テストのプロセスは残っていない。

`UnityIosPlugin` が組めないことの影響: `scripts/build_ios_library_xcframework.sh`（`IosLibrary` の後に `UnityIosPlugin` を組む）と `ios/generate_docc.sh` は、このブランチでは `UnityIosPlugin` の所で失敗する。ワークスペースのビルドと `test_ios.sh` は `UnityIosPlugin` を使わないので影響しない（2.1）。2.1 で見込んでいた「0f で組めなくなりうる」が 0e で起きた形で、D-22 の A（1.x の直しはタグ `1.13.0` から。ブリッジは段階 3 で消す）の範囲にある。

もう 1 つの案として、`getRootViewController()` を nonisolated のままにし、中を `MainActor.assumeIsolated { }` で包む形を試した。`UnityIosPlugin` は第 3 部の後と同じ 9 件の警告で組めた。代わりに、main 以外から呼ぶと実行時に止まる（前は UIKit を main 以外で読んでいた）。型で約束を示せず、0f で `shared` などを `@MainActor` にするときにはブリッジがやはり組めなくなるので、採らなかった（利用者の決定待ち。9.9）。

### 9.8 見つけたもの（直していない。1b などで扱う）

- 9.4 の 2 つの経路（`showLoginDialog` の失敗が `completion` に来ない、UIKit が表示を断ると `completion` が来ない）。後者は 1.4 に無い
- `showTextInputDialog` と `showLoginDialog` の確定ボタンの handler が `alert` を強く捕まえ、`alert` が action を持つので、循環参照になる。observer（1.4 の「外していない」）も `alert` と action を強く捕まえる。DocC の「Memory」の「Callbacks are not retained after dialog dismissal」は、この 2 つでは正しくない見込み（測っていない）
- `showDestructiveDialog` のログに `completion` が無い（ログの規則。1.4）
- `showDialog` の DocC の `actions` は「`UIAlertAction` を渡す」形で、作るのは呼び出し元の main actor になる。C ABI と Swift の API の設計（1b）で、ボタンを値で渡す形にするかを決める

### 9.9 残っていること

- **決めること**: `getRootViewController()` の `@MainActor`（推奨: 今のまま。理由は 9.7）。採ると、段階 3 までこのブランチではリリースのスクリプトと DocC のスクリプトが `UnityIosPlugin` の所で失敗する
- 実機での確かめ（D-21）。利用者の許可が要る
- `LastUpgradeCheck`（2.3）
- README の 0e の行、8.3 の表の更新（7 章）

## 10. 実機での確かめ（2026-10-25、iPhone XS / iOS 18.7.2）

利用者に流すテストの一覧・端末に起きること・事前の準備（ロックの解除、自動ロック「なし」、給電、IosLibraryExample だけを許す集中モード）・時間を示し、許可を得て流した。`--device-allow systemui,sharesheet`、`--skip-unit`。HEAD は `36238cca`。実機の UDID と devicectl の識別子はどこにも書いていない。実機の `.xcresult` はランナーが一時フォルダーごと消した（結果のフォルダーに残るのはシミュレーターの列挙の分だけ）。

| 回 | 許可の ID | 結果 |
|---|---|---|
| 1 | `2ad2d50ac050c94b3f179c8b0d0010f4` | 最初の呼び出し（`NavigationUITests`）で、テストのランナーが「encountered an error」で終わり、結果が 0 件だった。ランナーは「名指したテストと結果が合わない」で残りを流さずに止めた。開始のときに開発用の接続が切れていた見込み（devicectl で tunnel が disconnected、Developer Disk Image のサービスが使えない、端末の言語が読めない）。`devicectl device info details` で接続を張り直してから 2 回目を作った |
| 2 | `cf53b6acd9b50db21da3cc9b15041ceb` | 60 件のうち 57 件が成功、3 件が失敗。前からの実機の基準 19 件は changed=0。残りの 41 件は実機で初めて流したもの（基準に無いので added） |

呼び出しごと: Navigation 2/2、識別子 3/3、Dialog 11/11、Notification 21/23、Notification のイベント 7/7、コールドスタート 4/4、Share 9/10。

### 10.1 失敗した 3 件

どれもサンプルの操作の結果の行は成功していて、止まったのは OS の画面を読む所。0e で変えた型と完了のスレッドを同じ形で通る N4・ほかの Share のテストは通っている。

| テスト | 止まった所 | 調べたこと | 見立て |
|---|---|---|---|
| N34（ホームのアイコンのバッジ） | `expected exactly one sample icon, found 2`。2 つのどちらにも触れずに止めた（U-2） | 利用者によると、端末に同じ名前の古いアプリがあった（実行の後に利用者が消した）。iOS 18.3 のシミュレーターでは通る | 端末の状態による。流し直して確かめる |
| N5（画像付きの通知を 2 回） | 1 回目の画像付きのバナーが 10 秒以内に見つからなかった（`NotificationUITests.swift:92`） | 利用者がサンプルを手で動かすと、バナーに題名・本文・アプリのアイコンの画像が正しく出る。iOS 18.3 のシミュレーターでは通る | 実機だけで起きる。画像の付いたバナーが出るまで 10 秒を超えたか、実機ではバナーの読み上げの文が違うか。端末の画面の階層は私物の画面を含むので読まない（U-9）。流し直して、起きるかを確かめる |
| S5（共有のシートのプレビューの題名） | 見出しの題名が空（`header titles seen after the sheet opened: [""]`） | 利用者によると、シートの上に `Apple` と `apple.com` が出る。**iOS 18.3 のシミュレーターでも同じく失敗する**。シミュレーターで画面の階層を出すと（使い捨ての worktree で、S5 に階層を出す 1 行を足して流した。リポジトリは変えていない）、iOS 18 には `LP.CaptionBar.TopCaption` の識別子が無く、題名は見出しの `NavigationBar` の識別子（`Apple`）と、その下の要素の label（`Apple`、`apple.com`）にある | テストの読み方が iOS 26 の作りにしか合っていない。`Support/ShareSheet.swift` の `observeHeaderTitle` を iOS 18 でも読めるように直す必要がある（信頼する部分なので、0d の手順どおり別のモデルのレビューとハッシュの更新が要る） |

0c・0d の実機の実行は区分の無い 19 件だけで、S5 の iOS 18 での読み方はこれまで確かめていなかった（シミュレーターの基準は iOS 26.2 だけ）。

### 10.2 iOS 18.3 のシミュレーター（iPhone 16）

`scripts/test_ios.sh --feature Share --skip-unit` は 22 件のうち 21 件が成功（S5 だけが失敗。上の表）、`--feature Notification --skip-unit` は 42 件すべて成功（N5・N34 を含む）。この環境の基準は無い（D-21 の 2 つの環境ではない）。

### 10.3 端末に残ったもの

ランナーの表示のとおり、通知の category（`sample-category`）が残る。files と clipboard は許可していないので、「ファイル」への写しとクリップボードの文字は残らない。端末の設定は変えていない。

### 10.4 S5 の直し（`Support/ShareSheet.swift`）

iOS 18.3 のシミュレーターで出した見出しの階層（10.1）は次の並びだった。

| 子 | 種類 | 中身 |
|---|---|---|
| 見出しの `NavigationBar` | - | identifier が題名（`Apple`） |
| 1 つ目 | `Other` | label が題名（`Apple`） |
| 2 つ目 | `Button` | `閉じる`（`SystemLabels.close`） |
| 3 つ目 | `Other` | label が副題（`apple.com`） |

`observeHeaderTitle` を、iOS 26 では今までどおり `LP.CaptionBar.TopCaption` がちょうど 1 つのときに読み、iOS 18 では `Close` のボタンを持つナビゲーションバーがちょうど 1 つで、その直下の `Other` の子がちょうど 2 つのときだけ 1 つ目の label を読む形にした。ほかの形は ""（U-2）。押す操作もログも足していない。

レビュー（ハッシュを固定する前。観点は「正しく読めるか・誤って通らないか」と「iOS 26 と安全の規則を壊さないか」の 2 つなので、Claude のサブエージェント 1 本と Codex 1 回にした）:

| 指摘 | 区分 | 扱い |
|---|---|---|
| iOS 18 の経路が `Other` の子の数を確かめず、先頭を題名とみなす（U-2 の当て推量。サブエージェントの B-1、Codex の C） | B | 直した（子がちょうど 2 つのときだけ読む） |
| 子の並びに頼る。確かめたのは 18.3 のシミュレーターだけ（C-1） | C | 並びを上の表に残した。実機（18.7.2）は 0f の実機の確かめで S5 を流して確かめる。作りが違えば "" になり、失敗する側に倒れる |
| `count`・`label` が別々の snapshot（C-2） | C | 直していない（押す操作が無いので安全側。iOS 26 の経路と同じ形） |
| iPad では Close が無い見込み（C-3） | C | 対象外（テストの環境は iPhone だけ。U-16） |
| 述語の書式 `%d` と `%lu` の不揃い（C-4） | C | `%lu` に揃えた |
| 記録（C-6） | C | この節と、設計の 8.8 に書いた |

区分 A は 0。Codex は設定のモデルのまま動いた。

確かめ（シミュレーターだけ）: 直した後の S5 は、iOS 18.3（iPhone 16）と iOS 26.2（iPhone 17）の両方で通った（最初の形では S2・S3 も両方で通した。S2・S3 はこの関数を通らない）。新しいハッシュ `b32c3595080dfca93d415e6e70010373edd8cf9471fa41f4e024ef8893f69329` を `scripts/ios_ui_runner.py` の `TRUSTED_FILES` と 0d の結果の 2.3 の表に入れた。ランナーの自己テスト 132 件、閉じた形のソースの規則は通った。

## 11. 0g の後の実機の実行と、N34・N5 の調べ（2026-10-25）

### 11.1 実機の実行（許可の ID `c801732092a309fdfee562d06df4c85b`）

0g の後（HEAD `7919721a`）に、10 章と同じ 60 件を `--baseline` を付けて流した（`--dry-run` は `--baseline` と一緒に使えないので付けずに作り、許可の照合は通った。0d と同じ）。58 件が成功し、N34 と N5 が失敗した。失敗があったので実機の基準は保存されていない（19 件のまま）。S5 は実機でも通った（10.4 の直しを実機で確かめた）。前からの基準 19 件は changed=0。実機の `.xcresult` はランナーが消した。

### 11.2 N34

`expected exactly one sample icon, found 2` が続いた。端末に入っているアプリのうちサンプルに関係するものだけを `devicectl device info apps` で読むと、表示名が `IosLibraryExample` のアプリが 2 つあった: 今のサンプル（`com.jonghyunkim.ios.nativetoolkit.example`）と、古いサンプル（`ios.library.example.IosLibraryExample`。`37615913` で bundle id を変える前のもの）。ランナーが組むアプリの bundle id は今のものだけで、古いものは前から残っていた。利用者が古いものを消し、一覧で消えたことを確かめた。次の実機の実行で N34 を確かめる。

### 11.3 N5

1 回目の画像付きのバナーが 10 秒以内に見つからないことが 2 回続いた。利用者がサンプルで Show Immediate → Show Immediate with Attachment と押すと、2 つ目のバナーはすぐに出た（待つ時間の不足ではない）。iOS 18.3 と 26.2 のシミュレーターでは通る。実機の画面の階層は読まない（U-9）ので、何が違うかは分からない。

### 11.4 N5 の手がかり（`Springboard.waitForBannerNotingSampleNotifications`）

N5 の 2 回のバナーの待ちだけを、待つ間に springboard で label が `IosLibraryExample, `（大文字小文字を問わない）で始まる要素を書き留める形にした。見つかったときの動きは `waitForBanner` と同じ（割り込みの確かめ、`exactlyOne`）。書き留めるときは:

- label を `, ` で区切り、サンプル名・期待した題・本文と一致する部分だけを `<app>` / `<title>` / `<body>` と書き、ほかの部分は文字数（`<12>` など）にする。識別子は知っているもの（`NotificationShortLookView` など 3 つ）だけをそのまま書き、ほかは文字数にする。中身の文は書かない
- 要素は `snapshot()` で 1 回だけ読み、読めなければ飛ばす（消えた要素を読んでテストが落ちないように）
- 4 件まで（ランナーが失敗の文を 300 文字で切る）
- 「確かめる → 期限なら抜ける → 書き留める → 残りの時間だけ待つ」の順（期限の直前に出たバナーも確かめる）

「実機では失敗の文に springboard のラベルを書かない」（設計 U-8 (3)、6.1）の唯一の例外で、利用者が承認した（2026-10-25）。設計の U-8 (3)、6.1、8.8 にも書いた。

レビュー（ハッシュを固定する前。観点は「私物が文に入りえないか」と「見つかったときに `waitForBanner` と同じか」の 2 つなので、Claude のサブエージェント 1 本と Codex 1 回）:

| 指摘 | 出どころ | 区分 | 扱い |
|---|---|---|---|
| 名前の前方一致だけでは、サンプルの通知だと言い切れない（同じ名前の別のアプリ、まとめられた通知）。label の全体を書く | Codex | A | 直した: 一致した既知の文字だけを書き、ほかは文字数にする。言い切りを仕組みで成り立たせた |
| 前方一致の言い切りは実機で確かめていない | サブエージェント B-4 | B | 同上 |
| 消えた要素を読むと「No matches found」でテストが落ち、手がかりが失われる | サブエージェント B-1、Codex C | B | `snapshot()` で読む |
| ランナーが失敗の文を 300 文字で切る | サブエージェント B-2 | B | 短い印と 4 件までにした |
| 例外が記録と設計に無い | サブエージェント B-3 | B | この節と設計の 3 か所に書いた |
| 期限の直前に出たバナーを確かめずに false を返しうる | Codex B、サブエージェント C-1 | B | 順を直し、待つ時間を残りの時間で抑えた |
| 名前とコメント（`seen` → `note`、「通知」→「サンプル名で始まる要素」） | サブエージェント C-5 | C | 直した |

確かめ（シミュレーターだけ）: iOS 18.3 と 26.2 で、本物の N5 は通った。使い捨ての worktree で期待する本文をわざと違えると、失敗の文は `sample-named elements seen: NotificationShortLookView: <app>, <3>, <title>, <34>` になった（題は合い、本文は 34 文字の別の文）。閉じた形のソースの規則は通った。

直した後に、Codex に区分 A の指摘だけを確かめ直してもらった（設定のモデルのまま）。A・B・C はどれも解消した（失敗の文に入りうるのは、固定の文字、`<app>` / `<title>` / `<body>`、数字、知っている識別子だけ）。新しく C が 1 つ: 1 件の中の区切りの数に上限が無いので「4 件なら 300 文字に収まる」とは言い切れない。1 件あたり 6 つまで（それより多ければ `…`）にし、コメントを「実際には収まる」に直した。直した後の N4・N5 は iOS 18.3 と 26.2 のシミュレーターで通った。新しいハッシュ `d87dee42f805a7d7daaf20cc46bf242fc0c6fab4538e32e97bac3585bc39d785` を `scripts/ios_ui_runner.py` の `TRUSTED_FILES` と 0d の結果の 2.3 の表に入れた。

### 11.5 Notification の実機の実行（許可の ID `c2f840f441552cfb7eb8c28acd48caee`）と、N34・N5 の直し

`e6a098b6` で、`--feature Notification --skip-unit --device-allow systemui` の 39 件を流した（3 件は区分で除いた: I1d、NP1、NP2）。37 件が成功し、N34 と N5 が失敗した。前からの基準 19 件の範囲は changed=0。

| テスト | 失敗の文 | 分かったこと | 扱い |
|---|---|---|---|
| N34 | `icon value did not become a value with the digit 1: ""` | アイコンはちょうど 1 つになった（11.2 で古いアプリを消した）。値が空のままなのは、利用者の集中モードの「ホーム画面 > 通知バッジを非表示」がオンだったため（利用者が確かめてオフにした） | テストのコードは正しい。実機の準備に「通知バッジを非表示をオフ」を足した（D-21 の準備。利用者が設定する） |
| N5 | `sample-named elements seen: NotificationShortLookView: <app>, <1>, <title>, <body>, <6>` | 実機では、画像を添付したバナーのラベルが本文で終わらず、後ろに 6 文字の部分が 1 つ付く（日本語の「添付ファイル」の見込みだが、中身は書かない形なので分からない）。サンプル名・時刻・題・本文は合っている。シミュレーター（18.3、26.2）には付かない | `bannerQuery` に `hasAttachment` を足し、N5（画像を添付）の 2 回の待ちと消えるのを待つ所だけ、`", <本文>"` で終わるか `", <本文>, "` を含むものを受けるようにした。ほかのバナーは本文で終わることを求めたまま。設計 3.0・8.1・8.8 を直した |

直す前の N5 は、消えるのを待つ所（`waitForBannerToVanish`）が実機では何にも当たらないので、確かめずに通っていた。`hasAttachment` を渡したので、直した後は本当にバナーが消えるのを待つ。

最初の形は、すべてのバナーで「本文の後ろに続く」を受けていた。レビュー（観点は「別のバナーに当たらないか」と「もっと狭い形があるか」の 2 つなので、Claude のサブエージェント 1 本と Codex 1 回）:

| 指摘 | 出どころ | 区分 | 扱い |
|---|---|---|---|
| 設計 3.0 が「本文で終わる」のままで実装と食い違う。8.1 の未確認の項目と 8.8 にも書く | サブエージェント | A（記録） | 直した |
| コメントが指す作業の記録 11.5 がまだ無い | サブエージェント | A（記録） | この節を書いた |
| 条件が観測より広い。画像を添付したバナーだけに絞るのがよい（理屈では、本文が `X` と `X, …` の別のバナーに当たりうる。今のテストの文字列にはぶつかる組は無い） | 2 者 | B / C | 絞った（`hasAttachment`） |
| 後ろの部分の長さ 6 で縛るのは言語に頼るので勧めない | 2 者 | - | 縛っていない |
| 述語の書式（`%@` の数、`OR` の括り） | Codex | 問題なし | 絞った形では、条件を `NSCompoundPredicate` に分けた |

絞った形を Codex に確かめ直してもらった（設定のモデルのまま）: 勧めのとおりで、N5 だけが `hasAttachment: true` を渡し、ほかの呼び出しは前と同じ「本文で終わる」のまま。`hasAttachment` が false のときの複合の述語は、前の 1 つの述語と同じ意味。区分 A・B・C は 0。

確かめ（シミュレーターだけ）: 最初の形で、Notification の 3 クラスの 34 件を iOS 18.3 と 26.2 で流し、どちらもすべて成功した。絞った形で、N4・N5・N10 を両方で流し、すべて成功した。閉じた形のソースの規則とランナーの自己テスト 132 件は通った。新しいハッシュ `725c9cea8fbf0fd33c6eb971057f3aa374fd307993a71bd6d847fc5ff55d6d15` を `TRUSTED_FILES` と 0d の結果の 2.3 の表に入れた。実機での確かめは、次の Notification の実行で行う。

### 11.6 直した後の Notification の実機の実行（許可の ID `b6a5af34248f4b691650a7c5f79e0ae2`）

`2f8d215f` で、11.5 と同じ 39 件を流した。27 件が成功し、12 件が失敗した。前からの基準 19 件の範囲は changed=0。

- **N5 と N34 は実機で通った**（11.5 の直しと、集中モードの「通知バッジを非表示」をオフにしたことを、実機で確かめた）。`NotificationUITests` は 23 件のうち 22 件が成功
- 失敗したのは、`NotificationUITests` の最後に流れる N9 と、その後の `NotificationEventUITests` の 7 件と `NotificationColdStartUITests` の 4 件。どれもサンプルのバナーが待つ時間の中で見つからなかった（11.1 の実機の実行では、この 12 件はすべて通っていた）
- 原因は、22 時ごろに予定で始まる利用者の「睡眠」の集中モードだった（利用者が確かめてオフにした）。サンプルだけを許す集中モードから入れ替わり、サンプルの通知も出なくなった。テストのコードの問題ではない。同じ探し方の N4・N10 などは、同じ実行の前半で通っている
- 実機の準備（D-21）に「流す時間に、予定で始まる別の集中モードが重ならないこと」を足した

次の実機の実行で、10 章と同じ 60 件を `--baseline` を付けて流し、実機の基準を取り直す。

### 11.7 実機の基準の取り直し（1 回目。許可の ID `c39b5b97e872466d875ac8bc5846d7ee`）

`ffbebf73` で、10 章と同じ 60 件を `--baseline` を付けて流した（睡眠の集中モードはオフ）。59 件が成功し、N4 が 1 件失敗した。失敗があったので実機の基準は保存されていない（19 件のまま）。前からの基準 19 件の範囲は changed=0。N5・N34 を含むほかの 59 件はすべて通った。

N4 は、テストがサンプルを起動する所（`SampleApp.swift:285`）で、XCTest の `Failed to get launch progress … Failed to create direct …` で止まった。通知やバナーに入る前の、Xcode と端末のやりとりの失敗で、N4 はこれまでの実機の 4 回の実行ではすべて通っている。0e〜0g の変更によるものではなく、たまたま起きたものと見ている。次の機会に、同じ 60 件を `--baseline` を付けて流し直す（新しい `--dry-run` と許可が要る）。
