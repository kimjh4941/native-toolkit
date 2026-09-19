# macOS クリップボード機能 実装設計書

- 作成日: 2026-08-29
- 対象企画書: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research-v3.md`
- 対象OS: macOS 15 以降（`MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1）
- 使用言語: Swift 6（strict concurrency）、Objective-C（Bridge）
- 対象モジュール: `mac/MacLibrary`（Domain 〜 Manager）、`mac/UnityMacPlugin`（Unity Bridge）
- 適用ルール: `agent-rules/coding-rules/common.md`、`agent-rules/coding-rules/mac.md`

---

## 1. 設計目的

企画書 v3 で確定した macOS の `NSPasteboard` API 群を、native-toolkit の Clean Architecture に沿って `mac/MacLibrary` へ実装するための設計を確定する。

あわせて、企画書で実測により確定した 3 つの制約を設計に織り込む。

- **RK-21**: `NSFilePromiseProvider.delegate` は `weak` で、完了通知も存在しない。provider / delegate を強参照するセッションが必須
- **RK-23**: `writeObjects` による追記は自分が所有権を持つ間のみ成立する。他アプリ所有時は `false` を返して何も起きない
- **RK-08 / RK-10**: `NSPasteboard` / `NSPasteboardItem` は非 Sendable。`Timer` を使う監視は `@MainActor` 隔離が必要

---

## 2. スコープ（in / out）

### in（設計対象）

企画書のサブ機能記号に対応させる。

| 企画書サブ機能 | 設計対象 |
|---|---|
| P. ペーストボード取得・寿命管理 | createPasteboard / removePasteboard / scope 解決 |
| C. コピー（書き込み） | copy / append |
| L. 遅延データ提供 | `NSPasteboardItemDataProvider` による遅延提供（内部利用） |
| H. デバイス間同期制御 | `ClipboardCopyOptions.localOnly` → `.currentHostOnly` |
| R. ペースト（読み取り） | read / readData / snapshot |
| Q. 内容確認・型判定 | snapshot の型一覧、内部の事前判定 |
| X. クリア | clear |
| M. 変更監視 | startObserving / stopObserving / checkForegroundChange |
| D. 検出・プライバシー | detectPatterns / detectValues / detectMetadata / accessBehavior |
| U. ユーザー起点の貼り付け UI | makePasteButton（ネイティブ専用。Bridge 非公開） |
| F. ファイル約束 | provideFilePromise / releaseFilePromise |

### out（設計対象外）

| 対象 | 理由 |
|---|---|
| G. レガシー / Filter Services | 企画書 G-01〜G-09。新規採用しない方針が企画書で確定済み |
| 廃止済み定数（macOS 10.13 / 10.14 廃止） | 企画書 RK-19。使用禁止 |
| `NSPasteboard.Name.font` / `.ruler` / `.find` | 企画書 out スコープ（`NSTextView` 固有） |
| ドラッグ&ドロップ UI | 企画書 out スコープ。File Promise の provider / receiver のみ扱う |
| Services メニュー提供側 | 企画書 out スコープ |
| サンプルアプリ実装 | `design-sample-app` の担当。本書ではタスクの完了条件のみ定義 |
| `docs/` 配下 | 出力ルールにより固定で対象外 |

---

## 3. 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data / Presentation → Manager → Unity Bridge。Domain は `Foundation` の値型のみ |
| Domain に platform 型を持ち込まない | 適合 | `NSPasteboard` / `NSPasteboardItem` / `NSImage` / `UTType` は Domain に出さない。UTI は `String`、画像は `Data` として保持 |
| Port はドメイン型のみ | 適合 | `ClipboardRepository` の引数・戻り値は全てドメイン型。例外扱いの platform ビットマスク型なし |
| Manager は UseCase 経由 | 適合 | Manager から `ClipboardRepository` を直接呼ばない |
| **層とモジュールの対応** | **適合（要注意）** | **`ClipboardChangeMonitor`（Timer 所有）と `FilePromiseSession`（system delegate 所有）は `mac/MacLibrary` の Presentation 層に置く。Unity プラグインには置かない**。§4.1 参照 |
| Delegate / Listener の所有権 | 適合 | `NSPasteboardItemDataProvider` / `NSFilePromiseProviderDelegate` の実装は MacLibrary 内に置き、Unity Bridge は委譲のみ |
| Manager の公開 API 方式 | 適合 | 待機を伴う操作は callback 版 + `async throws` 版を併設。即時完了する control / factory 操作は同期形式のみ（common.md の例外規定） |
| **システム API に合わせた同期・非同期設計** | **適合（重要）** | **`NSPasteboard` の API はほぼ全て同期。したがって Repository / UseCase も同期関数とする。`async` にするのは検出 API（`detectedPatterns` 系）のみ**。§8 の対応表で全操作を追跡 |
| TDD | 適合 | UseCase 単位で Swift Testing。Mock は Port を実装し `shouldFail` / call counter / stubbed 戻り値の 3 点セット |
| エラー変換 | 適合 | システムエラー → RepositoryImpl → `ClipboardError` → Manager → `(Bool, Int, String?)` → Bridge |
| Unity Bridge を薄く保つ | 適合 | Bridge は JSON パースと Manager 呼び出しのみ |
| サンプルアプリの依存方向 | 適合 | `MacLibraryExample` は `MacLibrary` のみに依存。監視・File Promise も MacLibrary 側にあるため Unity 依存は発生しない |
| Minimum OS | 適合 | macOS 15 以降。15.4 未満での検出 API は `@available` で分岐（§7.9） |

---

## 4. 個別実装方針の適用チェック（mac.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| 全メソッド先頭に全パラメータの `Log.d` | 適合 | `public` / `internal` / `@objc` / `override` の全関数。クリップボード内容は §4.2 の秘匿方針でマスクする |
| ObjC / Swift ブリッジの型 | 適合 | ObjC ブロックは `BOOL` / `NSInteger` / `NSString * _Nullable` を使う。`bool` は使わない |
| Manager は callback 版 + `async throws` 版 | 適合 | 新規 Manager のため最初から両方式を用意する |
| private helper を一律 `async` にしない | 適合 | `NSPasteboard` 呼び出しは同期なので helper も同期 |
| UI 状態更新はメインスレッドへ戻す | 適合 | Manager の callback は必ず MainActor で呼ぶ |
| DocC コメント | 適合 | `public` シンボルに DocC。本文は英語 |
| コメント・ユーザー向け文言は英語 | 適合 | `ClipboardError.errorMessage` も英語 |

### 4.1 モジュール配置の判定（common.md の再発防止項目）

common.md には、Android の Clipboard 変更監視で system listener 所有クラスを Unity プラグインへ置いた違反例が記録されている。本設計は同じ判定を明示的に通す。

| クラス | system callback を持つか | Unity なしの呼び出し元が必要か | 配置 |
|---|---|---|---|
| `ClipboardChangeMonitor` | 持つ（`Timer` による周期実行） | **必要**（`MacLibraryExample` の監視デモ） | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `FilePromiseSession` | 持つ（`NSFilePromiseProviderDelegate`） | **必要**（サンプルアプリのファイル約束デモ） | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `LazyDataProvider` | 持つ（`NSPasteboardItemDataProvider`） | **必要** | `mac/MacLibrary/.../Clipboard/Data/Repository/` |
| `PasteButtonFactory` | 持たない（View 生成のみ） | **必要** | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `UnityMacClipboardManager` | 持たない（委譲のみ） | 不要 | `mac/UnityMacPlugin/.../Clipboard/` |

**Unity プラグインに置くのは `UnityMacClipboardManager` と JSON パーサ、Bridge の `.h` / `.m` のみ。**

### 4.2 ログの秘匿方針

クリップボードの内容は機密（パスワード等）を含みうるため、`Log.d` にそのまま出さない。iOS の `ClipboardRedaction` に相当する `ClipboardLog` を新設し、次の方針で出力する。

- 文字列: 長さのみ（`text(len:42)`）
- Data: バイト数のみ（`data(bytes:1024)`）
- URL: スキームとホストのみ（`url(https://example.com)`）。パス・クエリは出さない
- UTI / 型識別子: そのまま出す（機密ではない）
- ペーストボード名: `general` はそのまま、名前付きはハッシュ化した短縮値

---

## 5. 既存実装差分サマリー

### 5.1 新規追加

| モジュール | 追加内容 |
|---|---|
| `mac/MacLibrary` | `Clipboard/` 配下一式（Domain / Application / Data / Presentation / Manager）。§6 のファイル一覧 |
| `mac/MacLibrary/MacLibraryTests` | `Clipboard/` 配下のテスト一式 |
| `mac/UnityMacPlugin` | `Clipboard/` 配下（Unity Bridge 4 ファイル） |

### 5.2 既存への変更

| 対象 | 変更 | 破壊的変更 |
|---|---|---|
| `mac/MacLibrary/MacLibrary.xcodeproj` | 新規ファイルのターゲット追加 | なし |
| `mac/UnityMacPlugin/UnityMacPlugin.xcodeproj` | 同上 | なし |
| `mac/MacLibrary/MacLibrary/Common/Log.swift` | 変更なし（既存をそのまま利用） | なし |
| `mac/MacLibraryExample` | `design-sample-app` の担当。本書では変更しない | なし |

**破壊的変更なし。** 既存の Notification / Share / Dialog の公開 API には一切触れない。

### 5.3 既存規約との整合

| 規約 | 既存例 | 本設計 |
|---|---|---|
| 機能ディレクトリ | `Share/`, `Notification/` | `Clipboard/` |
| Manager 命名 | `MacShareManager`, `MacNotificationManager` | `MacClipboardManager` |
| Bridge 命名 | `UnityMacShareManager(Bridge).h/.m` | `UnityMacClipboardManager(Bridge).h/.m` |
| エラー型 | `ShareError`（1401〜1499）、`NotificationDomainError`（1101〜1205） | `ClipboardError`（**1501〜1599**。既存と衝突しない未使用帯） |
| テスト FW | Swift Testing（`import Testing`） | 同じ |
| Port 命名 | `ShareRepository` | `ClipboardRepository` |

---

## 6. 実装アーキテクチャ

### 6.1 ファイル構成

```
mac/MacLibrary/MacLibrary/Clipboard/
├── MacClipboardManager.swift                          Manager
├── Common/
│   └── ClipboardLog.swift                             ログ秘匿ヘルパ
├── Domain/
│   ├── Error/
│   │   └── ClipboardError.swift
│   └── Model/
│       ├── PasteboardScope.swift                      general / named / unique
│       ├── PasteboardCreationRequest.swift
│       ├── PasteboardOwnership.swift                  所有権トークン（RK-23）
│       ├── ClipboardItemData.swift                    1 アイテム = [UTI: Data]
│       ├── ClipboardContent.swift                     複数アイテム
│       ├── ClipboardCopyOptions.swift                 localOnly
│       ├── ClipboardReadResult.swift
│       ├── ClipboardSnapshot.swift
│       ├── ClipboardChangeEvent.swift
│       ├── ClipboardDetectionPattern.swift
│       ├── ClipboardDetectedValues.swift
│       ├── ClipboardDetectedMetadata.swift
│       ├── ClipboardAccessBehavior.swift
│       └── FilePromiseRequest.swift
├── Application/
│   ├── Port/
│   │   ├── ClipboardRepository.swift
│   │   └── ClipboardTypeIdentifierValidating.swift
│   └── UseCase/
│       ├── ClipboardContentValidator.swift
│       ├── ClipboardChangeTracker.swift
│       ├── CopyContentUseCase.swift
│       ├── AppendContentUseCase.swift
│       ├── ReadContentUseCase.swift
│       ├── ReadDataUseCase.swift
│       ├── GetSnapshotUseCase.swift
│       ├── ClearClipboardUseCase.swift
│       ├── CreatePasteboardUseCase.swift
│       ├── RemovePasteboardUseCase.swift
│       ├── DetectPatternsUseCase.swift
│       ├── DetectValuesUseCase.swift
│       ├── DetectMetadataUseCase.swift
│       ├── GetAccessBehaviorUseCase.swift
│       ├── CheckForegroundChangeUseCase.swift
│       ├── ProvideFilePromiseUseCase.swift
│       └── ClipboardUseCases.swift                    集約
├── Data/
│   ├── Repository/
│   │   ├── ClipboardRepositoryImpl.swift
│   │   ├── PasteboardResolver.swift                   scope → NSPasteboard
│   │   ├── ClipboardMappers.swift                     Domain ↔ NSPasteboardItem
│   │   ├── ClipboardDetectionMapper.swift             DetectedValues 変換
│   │   ├── ClipboardTypeIdentifierValidator.swift     UTI 検証（RK-18）
│   │   └── LazyDataProvider.swift                     NSPasteboardItemDataProvider
│   └── Image/
│       └── ClipboardImageCoder.swift                  NSImage ↔ Data（PNG/TIFF）
└── Presentation/
    ├── ClipboardChangeMonitor.swift                   changeCount ポーリング（MainActor）
    ├── FilePromiseSession.swift                       provider/delegate 保持（RK-21）
    ├── FilePromiseDelegate.swift                      nonisolated 要件の実装
    └── PasteButtonFactory.swift                       SwiftUI PasteButton → NSView

mac/MacLibrary/MacLibraryTests/Clipboard/
├── Mock/
│   ├── MockClipboardRepository.swift
│   ├── MockClipboardTypeIdentifierValidating.swift
│   └── MockClock.swift
├── Domain/ClipboardErrorTests.swift
├── Application/
│   ├── CopyContentUseCaseTests.swift
│   ├── AppendContentUseCaseTests.swift
│   ├── ReadContentUseCaseTests.swift
│   ├── ReadDataUseCaseTests.swift
│   ├── GetSnapshotUseCaseTests.swift
│   ├── ClearClipboardUseCaseTests.swift
│   ├── CreatePasteboardUseCaseTests.swift
│   ├── RemovePasteboardUseCaseTests.swift
│   ├── DetectUseCasesTests.swift
│   ├── CheckForegroundChangeUseCaseTests.swift
│   ├── ClipboardChangeTrackerTests.swift
│   ├── ClipboardContentValidatorTests.swift
│   └── ProvideFilePromiseUseCaseTests.swift
├── Data/
│   ├── ClipboardTypeIdentifierValidatorTests.swift
│   ├── ClipboardMappersTests.swift
│   └── PasteboardResolverTests.swift
└── Presentation/
    ├── ClipboardChangeMonitorTests.swift
    └── FilePromiseSessionTests.swift

mac/UnityMacPlugin/UnityMacPlugin/Clipboard/
├── UnityMacClipboardManager.swift
├── UnityMacClipboardJsonParser.swift
├── UnityMacClipboardManagerBridge.h
└── UnityMacClipboardManagerBridge.m
```

### 6.2 actor isolation の方針（新規設計判断）

企画書 RK-08 / RK-10 の引き継ぎ条件「`@MainActor` 固定か専用実行文脈か」を、**`@MainActor` 固定**で確定する。

**根拠**

- `NSPasteboard` / `NSPasteboardItem` は非 Sendable（企画書で実測確認済み）。アクター境界を越えられないため、取得と使用を同一隔離ドメインに閉じる必要がある
- 変更監視は `Timer` を使い、Swift 6 では `@MainActor` + `MainActor.assumeIsolated` が必要（RK-10）
- `PasteButton`（SwiftUI）と `NSView` 生成は MainActor 必須
- `NSPasteboard` の同期 API はペーストボードサーバへの IPC だが、通常のテキスト・URL・小さな画像では数ミリ秒（企画書の実測では `readObjects` が 9〜12 ミリ秒）

**適用範囲**

`ClipboardRepositoryImpl` / 全 UseCase / `MacClipboardManager` / `ClipboardChangeMonitor` / `FilePromiseSession` / `PasteButtonFactory` を `@MainActor` とする。

**例外**

`FilePromiseDelegate` は `NSFilePromiseProviderDelegate` の `filePromiseProvider(_:writePromiseTo:completionHandler:)` が `NS_SWIFT_NONISOLATED` のため、**`@MainActor` にしない**（企画書 RK-09 と同種の適合隔離エラーになる）。この 1 クラスのみ nonisolated とし、状態共有は `NSLock` で保護する。

**受容するリスク（RK-20）**

大容量データ（大きな画像、ファイル本体）の同期読み書きはメインスレッドをブロックする。緩和策は企画書 RK-20 の方針に従い、大容量は遅延提供（`LazyDataProvider`）または File Promise 経路へ寄せる。`ClipboardLimits` で警告閾値（既定 10MB）を設け、超過時に `Log.e` を出す。**閾値の妥当性は要検証。**

### 6.3 所有権モデル（新規設計判断 / RK-23 対応）

企画書 RK-23 で「追記は自所有時のみ成立し、他アプリ所有時は `false` で無変化」が確定した。`writeObjects` の戻り値を見なければ失敗に気づけないため、所有権を明示的に追跡する。

```
copy(...) -> PasteboardOwnership          // changeCount を保持したトークンを返す
append(_:ownership:)                      // トークンが現在の changeCount と一致する時のみ実行
```

- `copy` は `prepareForNewContents(with:)`（C-02）の戻り値 `changeCount` を `PasteboardOwnership` として返す
- `append` は実行前に現在の `changeCount` と照合し、不一致なら **`writeObjects` を呼ばずに** `ClipboardError.ownershipLost` を投げる
- 照合が一致していても `writeObjects` が `false` を返した場合は `ClipboardError.appendRejected` を投げる（二重の防御）

これにより「黙って何も起きない」失敗が公開 API から消える。

### 6.4 Universal Clipboard 制御（RK-05 対応）

企画書 RK-05 で「`clearContents()` は `currentHostOnly` を解除する」が確定している。設計として**所有権取得を 1 経路に集約する**。

- `ClipboardRepositoryImpl` の内部 helper `takeOwnership(scope:localOnly:) -> Int` のみが所有権を取得する
- 実装は常に `prepareForNewContents(with:)` を使う。`localOnly == true` なら `.currentHostOnly`、`false` なら `[]`
- `clearContents()` は **`clear` 操作（OP-06）でのみ**使用する
- `copy` 経路から `clearContents()` を呼ぶことを禁止する（レビュー観点に含める）

---

## 7. サブ機能別詳細設計

### 7.1 P. ペーストボード取得・寿命管理

**データ構造**

```swift
public enum PasteboardScope: Sendable, Equatable {
    case general
    case named(String)
    case unique(String)   // withUniqueName() の結果名を保持
}

public struct PasteboardCreationRequest: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case named(String); case unique }
    public let kind: Kind
}
```

**制御フロー**

- `PasteboardResolver.resolve(_ scope:) throws -> NSPasteboard`
  - `.general` → `NSPasteboard.general`
  - `.named(n)` / `.unique(n)` → `NSPasteboard(name: .init(n))`
  - 名前が空文字なら `ClipboardError.invalidPasteboardName`
- `createPasteboard`
  - `.named(n)` → `NSPasteboard(name:)`、`.unique` → `NSPasteboard.withUniqueName()` し、`pasteboard.name.rawValue` を `PasteboardScope.unique` に包んで返す
- `removePasteboard`
  - **`.general` および標準名（`general` / `font` / `ruler` / `find` / `drag`）に対しては `releaseGlobally()` を呼ばず `ClipboardError.cannotReleaseStandardPasteboard` を投げる**（RK-07）
  - それ以外は `releaseGlobally()`

**企画書リスク対応**: RK-06（終了後も残存する）は DocC の契約文に明記する。RK-07 は上記のガードで構造的に防ぐ。

### 7.2 C. コピー / 追記

**データ構造**

```swift
public struct ClipboardItemData: Sendable, Equatable {
    /// UTI -> raw bytes. 1 アイテムが複数表現を持てる。
    public let representations: [String: Data]
}

public struct ClipboardContent: Sendable, Equatable {
    public let items: [ClipboardItemData]
}

public struct ClipboardCopyOptions: Sendable, Equatable {
    /// true で Universal Clipboard へ渡さない（.currentHostOnly）。既定 true。
    public let localOnly: Bool
    public static let `default` = ClipboardCopyOptions(localOnly: true)
}

public struct PasteboardOwnership: Sendable, Equatable {
    public let scope: PasteboardScope
    public let changeCount: Int
}
```

**制御フロー（copy）**

1. `ClipboardContentValidator` が `items` 非空・各 UTI の妥当性を検証（`ClipboardTypeIdentifierValidating`）
2. `PasteboardResolver` で `NSPasteboard` を取得
3. `takeOwnership(scope:localOnly:)` → `prepareForNewContents(with:)`
4. 各 `ClipboardItemData` から **毎回新しい `NSPasteboardItem` を生成**（RK-14: 再利用禁止）
5. `writeObjects(items)`。`false` なら `ClipboardError.writeRejected`
6. `PasteboardOwnership(scope:changeCount:)` を返す

**制御フロー（append）**

1. `validator` で検証
2. 現在の `changeCount` と `ownership.changeCount` を照合。不一致なら `ClipboardError.ownershipLost`（§6.3）
3. **`clearContents` / `prepareForNewContents` を呼ばずに** `writeObjects` のみ実行
4. `false` なら `ClipboardError.appendRejected`
5. 成功時は同じ `ownership` を返す（`changeCount` は変化しない。企画書 V-13b 実測）

**iOS との契約差**: iOS の `append` は所有者を問わないが、macOS は自所有時のみ。DocC に明記し、Unity Bridge のヘッダにも書く（RK-23）。

### 7.3 L. 遅延データ提供

`ClipboardItemData` に「即時バイト列」と「遅延クロージャ」の両方を持たせると Domain が非 Sendable な閉包を抱えるため、**Domain には持ち込まない**。

代わりに Repository の内部 API とする。

```swift
// Data 層内部（Port には出さない）
func writePromised(scope: PasteboardScope,
                   types: [String],
                   localOnly: Bool,
                   provider: @escaping @Sendable (String) -> Data?) throws -> PasteboardOwnership
```

- `LazyDataProvider: NSObject, NSPasteboardItemDataProvider` が `provider` を保持
- `ClipboardRepositoryImpl` が `LazyDataProvider` を**強参照で保持**する（RK-17）
- `pasteboardFinishedWithDataProvider(_:)`（L-03）到達時に参照を外す
- 公開 API としては v1 では出さない（内部最適化として大容量 copy に使う）

**要検証**: システム側が provider を保持するかは企画書 V-3 が未消化。強参照保持で安全側に倒す。

### 7.4 H. デバイス間同期制御

`ClipboardCopyOptions.localOnly` を `NSPasteboard.ContentsOptions.currentHostOnly` に写像する。§6.4 の単一経路に集約。

**既定値は `localOnly: true`**（iOS 版 `ClipboardCopyOptions.default` と同じ安全側の既定）。

**要検証**: 実効性は企画書 V-8 / V-9 が未消化（実機 Mac + iPhone が必要）。DocC には「Universal Clipboard への転送を抑止する意図の設定であり、実効性は未検証」と明記する。

### 7.5 R. ペースト / 読み取り

```swift
public struct ClipboardReadResult: Sendable, Equatable {
    public let items: [ClipboardItemData]
    public let changeCount: Int
}
```

- `read(scope:)` → `pasteboardItems`（R-07）を走査し、各 item の `types` ごとに `data(forType:)` を集めて `ClipboardItemData` を構成
- `readData(utType:scope:)` → `data(forType:)`（R-05）。該当なしは `nil` を返す（エラーにしない）
- `pasteboardItems` が `nil` の場合は `ClipboardError.pasteboardUnavailable`

**RK-15 対応**: `string(forType:)` は複数アイテムを改行連結してしまうため、**公開 API では使わない**。件数が意味を持つ `pasteboardItems` 経路に統一する。

### 7.6 Q. 内容確認 / 型判定

```swift
public struct ClipboardSnapshot: Sendable, Equatable {
    public let changeCount: Int
    public let itemTypes: [[String]]   // アイテムごとの UTI 一覧
    public let hasItems: Bool
}
```

- `snapshot(matchingTypes:scope:)` は `pasteboardItems` の `types` のみを読み、**データ本体は読まない**
- `matchingTypes` 指定時は `availableType(from:)` で絞り込む

**重要（RK-01 / RK-02 / RK-22）**: `snapshot` は「通知が出ない」ことを**保証しない**。DocC に「This does not guarantee that the system will not notify the user」と明記する。企画書で V-1 が判定保留のため、通知回避を契約にしない。

### 7.7 X. クリア

`clearContents()`（C-01）を呼び、新しい `changeCount` を返す。§6.4 のとおり、この操作だけが `clearContents()` を使う。

### 7.8 M. 変更監視

`ClipboardChangeMonitor`（`mac/MacLibrary/.../Presentation/`、`@MainActor`）。

```swift
public struct ClipboardChangeEvent: Sendable, Equatable {
    public let scope: PasteboardScope
    public let changeCount: Int
}
```

**制御フロー**

- `start(scope:interval:onEvent:)`: 既存監視があれば停止 → `changeCount` を初期値として記録 → `Timer.scheduledTimer` を作る
- タイマ本体は `MainActor.assumeIsolated { }` で包む（RK-10）
- `onEvent` は `@escaping @MainActor (ClipboardChangeEvent) -> Void`
- `stop()`: `timer?.invalidate()`
- 既定間隔 0.5 秒。`interval` は引数で変更可能
- 二重購読を防ぐため、`start` は世代カウンタを持ち、古いタイマのコールバックを無視する（iOS 版 `observingGeneration` と同じ方式）

**アプリ非アクティブ時（RK-11）**

`NSApplication.didResignActiveNotification` / `didBecomeActiveNotification` を購読し、非アクティブ中はタイマを止め、復帰時に `checkForegroundChange` 相当の 1 回照合を行う。

**イベント種別の制約**: macOS には `changedNotification` / `removedNotification` の区別がないため、`ClipboardChangeEvent` に種別を持たせない。iOS との差分として DocC に明記。

### 7.9 D. 検出・プライバシー（macOS 15.4+）

**バージョン分岐（RK-01）**

`MACOSX_DEPLOYMENT_TARGET` が 15.0 / 15.1 のため、検出 API は `if #available(macOS 15.4, *)` で分岐する。

- 15.4 未満 → `ClipboardError.detectionUnavailable(minimumOS: "15.4")` を投げる
- **`canReadItem` / `canReadObject` によるフォールバックは実装しない**。企画書 RK-01 が「V-1 の結果が出るまで Q 群フォールバックを正式採用しない」と定めており、V-1 は判定保留のまま。フォールバックを入れると「通知なしで判定できる」という誤った契約を公開することになる

**データ構造**

```swift
public enum ClipboardDetectionPattern: String, Sendable, CaseIterable {
    case probableWebURL, probableWebSearch, number, links, phoneNumbers,
         emailAddresses, postalAddresses, calendarEvents,
         shipmentTrackingNumbers, flightNumbers, moneyAmounts
}

public struct ClipboardDetectedValues: Sendable, Equatable {
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [String]
    public let phoneNumbers: [String]
    public let emailAddresses: [String]
    public let postalAddresses: [String]
    public let calendarEvents: [String]
    public let shipmentTrackingNumbers: [String]
    public let flightNumbers: [String]
    public let moneyAmounts: [String]
}

public struct ClipboardDetectedMetadata: Sendable, Equatable {
    public let contentTypeIdentifier: String?   // UTType.identifier
}

public enum ClipboardAccessBehavior: String, Sendable {
    case `default`, ask, alwaysAllow, alwaysDeny, unavailable
}
```

`DDMatch*` は Domain に持ち込まず、`ClipboardDetectionMapper`（Data 層）で `String` へ正規化する（common.md の Domain 制約）。

**実行方式**

検出 API のみ `async throws`。Swift の refined API は `PartialKeyPath<NSPasteboard.DetectedValues>` を取るため、`ClipboardDetectionMapper` が `ClipboardDetectionPattern` → KeyPath の変換表を持つ。

**通知の扱い（RK-03）**

- `detectPatterns` / `detectMetadata`: ヘッダ上「通知しない」と明記されている。ただし §7.6 と同様、契約としては保証しない
- `detectValues`: 一致時に通知が発生し、拒否時に throw する。DocC に明記し、**ユーザー操作起点でのみ呼ぶこと**を要求する

**キャンセル（要検証 V-5）**: Swift の Task キャンセルを尊重するかは未確認。`ClipboardError.cancelled` を用意し、`CancellationError` を受けたら変換する。実際に届くかは要検証。

### 7.10 U. 貼り付け UI（ネイティブ専用）

`PasteButtonFactory`（`@MainActor`、Presentation 層）。

```swift
public func makePasteButton(
    acceptedTypes: [String],
    onPaste: @escaping @MainActor ([ClipboardItemData]) -> Void
) throws -> NSView
```

- SwiftUI `PasteButton(supportedContentTypes:payloadAction:)`（U-02、macOS 11.0）を `NSHostingView` で包んで `NSView` として返す
- `payloadType:onPaste:` 版（U-01）は macOS 13.0 のため、最小 15.0 の本プロジェクトでは両方使えるが、`[NSItemProvider]` 版の方が UTI 指定と相性が良いため U-02 を採用する
- `acceptedTypes` が空、または不正 UTI を含む場合は `ClipboardError.invalidTypeIdentifier`

**Bridge 非公開**: `NSView` を返す factory は C ABI に載らないため、Unity Bridge には出さない。iOS の `makePasteControl` も「not exposed to the Unity Bridge」と同じ扱い。

**制約（RK-16）**: macOS の `PasteButton` はペーストボード変更に応じた自動 validate / invalidate を行わない。DocC に明記する。

### 7.11 F. ファイル約束

**RK-21 が本機能の中核。** provider だけがシステムに保持され delegate が落ちると、他アプリからは有効な約束に見えたまま永久に履行されない。

```swift
public struct FilePromiseRequest: Sendable {
    public let fileTypeIdentifier: String      // UTI（data / directory 適合が必要）
    public let fileName: String
    /// 書き出し本体。nonisolated な OperationQueue 上で呼ばれる。
    public let write: @Sendable (URL) throws -> Void
}
```

**クラス構成**

- `FilePromiseDelegate`（**nonisolated**、`NSFilePromiseProviderDelegate`）
  - `filePromiseProvider(_:fileNameForType:)` → `request.fileName`
  - `filePromiseProvider(_:writePromiseTo:completionHandler:)` → `request.write(url)` を実行し、**成否に関わらず completionHandler をちょうど 1 回**呼ぶ。**書き出し要求は複数回来うるため、provider 全体で 1 回に絞るガードは置かない**（企画書 RK-21 / v2 第 2 回レビュー反映）
  - `operationQueue(for:)` → 専用の `OperationQueue`
- `FilePromiseSession`（`@MainActor`、Presentation 層）
  - `provider` と `delegate` を**両方とも強参照**で保持する
  - `ownership: PasteboardOwnership` を保持し、`isStale` を `changeCount` の不一致で判定
  - `release()` で参照を解放

**公開 API**

```swift
public func provideFilePromise(_ request: FilePromiseRequest,
                               scope: PasteboardScope) throws -> FilePromiseSession
public func releaseFilePromise(_ session: FilePromiseSession)
```

**セッションの寿命管理**

`NSFilePromiseProviderDelegate` に完了通知が存在しないため、解放は次のいずれかで行う。

1. 呼び出し側が明示的に `releaseFilePromise` を呼ぶ
2. `MacClipboardManager` が保持するセッション一覧を、変更監視（§7.8）の各 tick で走査し、`isStale == true` のものを自動解放する

2 を既定動作とし、監視を使っていない場合は 1 が必要であることを DocC に明記する。

**受領側（F-10）**

```swift
public func receiveFilePromises(destinationDirectory: URL,
                                scope: PasteboardScope,
                                completion: @escaping @MainActor ([URL], [ClipboardError]) -> Void)
```

`NSFilePromiseReceiver.receivePromisedFiles` は reader block が**複数回**呼ばれるため、内部でカウンタを持ち、`fileTypes.count` 分の到達を待って 1 回だけ completion を呼ぶ。async 版は存在しない（企画書 F-10 でコンパイル確認済み）ため、callback のまま扱う。

---

## 8. API 設計

### 8.1 公開 API（`MacClipboardManager`）

mac.md に従い、待機を伴う操作は **callback 版 + `async throws` 版**を併設する。即時完了する control / factory 操作は同期形式のみ（common.md の例外規定）。

| ID | 操作 | callback 版 | ネイティブ版 |
|---|---|---|---|
| OP-01 | copy | `copy(_:options:scope:completion:)` | `copy(_:options:scope:) async throws -> PasteboardOwnership` |
| OP-02 | append | `append(_:ownership:completion:)` | `append(_:ownership:) async throws -> PasteboardOwnership` |
| OP-03 | read | `read(scope:completion:)` | `read(scope:) async throws -> ClipboardReadResult` |
| OP-04 | readData | `readData(utType:scope:completion:)` | `readData(utType:scope:) async throws -> Data?` |
| OP-05 | snapshot | `snapshot(matchingTypes:scope:completion:)` | `snapshot(matchingTypes:scope:) async throws -> ClipboardSnapshot` |
| OP-06 | clear | `clear(scope:completion:)` | `clear(scope:) async throws -> Int` |
| OP-07 | createPasteboard | `createPasteboard(_:completion:)` | `createPasteboard(_:) async throws -> PasteboardScope` |
| OP-08 | removePasteboard | `removePasteboard(_:completion:)` | `removePasteboard(_:) async throws` |
| OP-09 | detectPatterns | `detectPatterns(_:scope:completion:)` | `detectPatterns(_:scope:) async throws -> Set<ClipboardDetectionPattern>` |
| OP-10 | detectValues | `detectValues(_:scope:completion:)` | `detectValues(_:scope:) async throws -> ClipboardDetectedValues` |
| OP-11 | detectMetadata | `detectMetadata(scope:completion:)` | `detectMetadata(scope:) async throws -> ClipboardDetectedMetadata` |
| OP-12 | accessBehavior | なし（同期 control） | `accessBehavior() -> ClipboardAccessBehavior` |
| OP-13 | startObserving | なし（同期 control） | `startObserving(scope:interval:onEvent:) throws` |
| OP-14 | stopObserving | なし（同期 control） | `stopObserving()` |
| OP-15 | checkForegroundChange | なし（同期 control） | `checkForegroundChange(scope:) -> Bool` |
| OP-16 | provideFilePromise | なし（同期 factory） | `provideFilePromise(_:scope:) throws -> FilePromiseSession` |
| OP-17 | releaseFilePromise | なし（同期 control） | `releaseFilePromise(_:)` |
| OP-18 | receiveFilePromises | `receiveFilePromises(destinationDirectory:scope:completion:)` | なし（システム API に async 版が存在しない） |
| OP-19 | makePasteButton | なし（同期 factory） | `makePasteButton(acceptedTypes:onPaste:) throws -> NSView` |

callback 版のシグネチャは既存 macOS 実装に合わせ、`(Bool isSuccess, <値>?, Int errorCode, String? errorMessage)` 形式とする。

### 8.2 内部 API（Port）

```swift
@MainActor
public protocol ClipboardRepository {
    // P
    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope
    func removePasteboard(_ scope: PasteboardScope) throws
    // C
    func write(_ content: ClipboardContent, options: ClipboardCopyOptions,
               scope: PasteboardScope) throws -> PasteboardOwnership
    func append(_ content: ClipboardContent,
                ownership: PasteboardOwnership) throws -> PasteboardOwnership
    // R / Q
    func read(scope: PasteboardScope) throws -> ClipboardReadResult
    func readData(utType: String, scope: PasteboardScope) throws -> Data?
    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot
    // X / M
    func clear(scope: PasteboardScope) throws -> Int
    func changeCount(scope: PasteboardScope) throws -> Int
    // D
    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                        scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern>
    func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                      scope: PasteboardScope) async throws -> ClipboardDetectedValues
    func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata
    func accessBehavior() -> ClipboardAccessBehavior
    // F
    func writeFilePromise(_ request: FilePromiseRequest,
                          scope: PasteboardScope) throws -> FilePromiseSession
    func receiveFilePromises(destinationDirectory: URL, scope: PasteboardScope,
                             completion: @escaping @MainActor ([URL], [ClipboardError]) -> Void) throws
}
```

Port にプラットフォーム型は現れない（`URL` / `Data` は common.md が Domain で許容する `Foundation` 値型）。

---

## 9. 同期・非同期レイヤー対応表（全公開操作）

| ID | 操作 | System API と実行方式 | Repository | UseCase | Manager callback | Manager native | Bridge | actor / thread | キャンセル・リソース所有権 | 変換理由 |
|---|---|---|---|---|---|---|---|---|---|---|
| OP-01 | copy | C-02 `prepareForNewContents` + C-03 `writeObjects`（**同期**） | 同期 `throws` | 同期 `throws` | `Task { @MainActor }` で callback | `async throws`（薄いラッパー） | C 関数 + callback | MainActor | キャンセル手段なし。`PasteboardOwnership` を返す | Manager の公開規約（mac.md）により async を併設。下位層は同期のまま |
| OP-02 | append | C-03 `writeObjects`（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | 同上。所有権不一致で `ownershipLost` | 同上 |
| OP-03 | read | R-07 `pasteboardItems` + R-09（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | なし。返却は値型 | 同上 |
| OP-04 | readData | R-05 `data(forType:)`（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | なし | 同上 |
| OP-05 | snapshot | Q-01 `types` / Q-05（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | なし | 同上 |
| OP-06 | clear | C-01 `clearContents`（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | なし | 同上 |
| OP-07 | createPasteboard | P-02 / P-03（**同期**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | 一意名は `releaseGlobally` 必須 | 同上 |
| OP-08 | removePasteboard | P-04 `releaseGlobally`（**同期・oneway**） | 同期 `throws` | 同期 `throws` | 同上 | `async throws` | 同上 | MainActor | 標準ペーストボードは拒否 | 同上 |
| OP-09 | detectPatterns | D-01（**async throws**） | `async throws` | `async throws` | `Task { @MainActor }` | `async throws` | 同上 | 呼び出し元アクター（Manager から呼ぶため MainActor） | Task キャンセル対応は要検証（V-5） | システム API が async のためそのまま |
| OP-10 | detectValues | D-02（**async throws**） | `async throws` | `async throws` | 同上 | `async throws` | 同上 | MainActor | 同上。ユーザー拒否で throw | 同上 |
| OP-11 | detectMetadata | D-03（**async throws**） | `async throws` | `async throws` | 同上 | `async throws` | 同上 | MainActor | 同上 | 同上 |
| OP-12 | accessBehavior | D-07（**同期プロパティ**） | 同期（非 throws） | 同期 | なし | 同期 | 同期 C 関数 | MainActor | なし | 即時完了する control のため callback / async を設けない（common.md 例外） |
| OP-13 | startObserving | M-01 `changeCount` ポーリング（**同期 + Timer**） | 同期（`changeCount`） | 同期（`ClipboardChangeTracker`） | なし | 同期 `throws` | 同期 C 関数 + event callback | MainActor（`MainActor.assumeIsolated`） | `stopObserving` で停止。二重購読は世代カウンタで排除 | 開始・停止は同期 control、イベント配信のみ非同期（common.md の listener 規定） |
| OP-14 | stopObserving | 同上 | - | - | なし | 同期 | 同期 C 関数 | MainActor | タイマ `invalidate` | 同上 |
| OP-15 | checkForegroundChange | M-01（**同期**） | 同期 | 同期 | なし | 同期 | 同期 C 関数 | MainActor | なし | 即時完了する判定のため（common.md 例外） |
| OP-16 | provideFilePromise | F-01 + C-03（**同期**） | 同期 `throws` | 同期 `throws` | なし | 同期 `throws` | 非公開 | MainActor（生成）/ nonisolated（書き出し） | **セッションが provider + delegate を強参照（RK-21）。解放は明示 or stale 検出** | factory 操作のため同期（common.md 例外）。約束の履行はシステム都合で後から起きる |
| OP-17 | releaseFilePromise | - | - | - | なし | 同期 | 非公開 | MainActor | 参照解放 | 即時完了する control |
| OP-18 | receiveFilePromises | F-10 `receivePromisedFiles`（**callback、複数回**） | callback | callback | callback | **なし** | 非公開 | 引数の `OperationQueue` → MainActor へ集約 | キャンセル手段なし。失敗も reader に届く | **システム API に async 版が存在しない**（企画書 F-10 でコンパイル確認済み）ため async 版を作らない |
| OP-19 | makePasteButton | U-02 `PasteButton`（**callback**） | - | - | なし | 同期 `throws` | 非公開 | MainActor | View の破棄で終了 | factory 操作のため同期（common.md 例外） |

### 9.1 企画書の分類表との差分（新規設計判断）

| 差分 | 内容 | 理由 |
|---|---|---|
| L 群（遅延提供）を公開 API に出さない | 企画書 L-01〜L-07 は Repository 内部に閉じる | Domain に非 Sendable な閉包を持ち込まないため。大容量 copy の内部最適化としてのみ使用 |
| Q 群を独立操作にせず `snapshot` に統合 | 企画書 Q-01〜Q-07 を OP-05 に集約 | 公開 API の粒度を iOS 版 `snapshot` に合わせるため |
| `string(forType:)`（R-04）を使わない | OP-03 は `pasteboardItems` 経路のみ | RK-15（複数アイテムが改行連結される）を回避するため |
| Q 群を 15.0–15.3 の検出フォールバックにしない | OP-09〜OP-11 は 15.4 未満で throw | 企画書 RK-01 が V-1 の結果が出るまで正式採用を禁じており、V-1 は判定保留のため |

---

## 10. ドメインエラー一覧（全ケース）

```swift
public enum ClipboardError: Error, Equatable { ... }
```

| # | ケース | 発生条件 | 発生層 |
|---|---|---|---|
| 1 | `emptyContent` | `ClipboardContent.items` が空 | Application（Validator） |
| 2 | `emptyRepresentations(itemIndex: Int)` | アイテムの `representations` が空 | Application |
| 3 | `emptyDetectionPatterns` | `detectPatterns` / `detectValues` に空集合 | Application |
| 4 | `invalidTypeIdentifier(String)` | UTI として不正な型識別子 | Application / Data |
| 5 | `invalidPasteboardName(String)` | 空文字などの不正なペーストボード名 | Data |
| 6 | `contentTooLarge(bytes: Int, limit: Int)` | 単一表現が上限超過 | Application |
| 7 | `pasteboardUnavailable(name: String)` | `pasteboardItems` が `nil` 等 | Data |
| 8 | `cannotReleaseStandardPasteboard(name: String)` | `general` / 標準名に `releaseGlobally` | Data |
| 9 | `writeRejected` | `writeObjects` が `false`（copy 経路） | Data |
| 10 | `appendRejected` | `writeObjects` が `false`（append 経路） | Data |
| 11 | `ownershipLost(expected: Int, actual: Int)` | append 時に `changeCount` 不一致 | Data |
| 12 | `noMatchingItem(utType: String)` | 指定 UTI のアイテムが存在しない | Data |
| 13 | `imageDecodeFailed` | 画像 `Data` を `NSImage` にできない | Data |
| 14 | `imageEncodeFailed` | `NSImage` を PNG / TIFF にできない | Data |
| 15 | `detectionUnavailable(minimumOS: String)` | macOS 15.4 未満で検出 API 呼び出し | Data |
| 16 | `detectionDenied` | `detectValues` でユーザーが拒否 | Data |
| 17 | `detectionFailed(String)` | 検出 API がその他のエラーを返した | Data |
| 18 | `filePromiseTypeInvalid(String)` | `fileType` が data / directory に非適合 | Data |
| 19 | `filePromiseWriteFailed(String)` | 書き出しクロージャが throw | Presentation |
| 20 | `filePromiseReceiveFailed(String)` | 受領時に reader が error を返した | Data |
| 21 | `observationAlreadyActive` | 監視中に不正な再入 | Presentation |
| 22 | `cancelled` | Task キャンセル（要検証 V-5） | Data |
| 23 | `unknown(String)` | 上記以外 | 全層 |

---

## 11. エラーコード / メッセージ対応表

Bridge 返却形式は `(isSuccess: Bool, errorCode: Int, errorMessage: String?)`。成功時は `errorCode == 0`、`errorMessage == nil`（`NotificationDomainError` の規約に合わせる）。

コード帯は既存と衝突しない **1501〜1599** を使う（既存: 1001-1003 / 1101-1104 / 1201-1205 / 1301-1302 / 1401-1408 / 1499 / 1999）。

| コード | ケース | errorMessage（英語） |
|---|---|---|
| 1501 | `emptyContent` | `No clipboard content was provided.` |
| 1502 | `emptyRepresentations` | `Clipboard item at index {i} has no representations.` |
| 1503 | `emptyDetectionPatterns` | `No detection patterns were specified.` |
| 1504 | `invalidTypeIdentifier` | `Invalid uniform type identifier: {value}.` |
| 1505 | `invalidPasteboardName` | `Invalid pasteboard name: {value}.` |
| 1506 | `contentTooLarge` | `Clipboard content is too large: {bytes} bytes (limit {limit}).` |
| 1507 | `pasteboardUnavailable` | `Pasteboard is unavailable: {name}.` |
| 1508 | `cannotReleaseStandardPasteboard` | `Standard pasteboard cannot be released: {name}.` |
| 1509 | `writeRejected` | `The pasteboard rejected the write operation.` |
| 1510 | `appendRejected` | `The pasteboard rejected the append operation.` |
| 1511 | `ownershipLost` | `Pasteboard ownership was lost (expected change count {expected}, found {actual}). Append is only possible while this app owns the pasteboard.` |
| 1512 | `noMatchingItem` | `No pasteboard item matches type: {utType}.` |
| 1513 | `imageDecodeFailed` | `Failed to decode image data.` |
| 1514 | `imageEncodeFailed` | `Failed to encode image data.` |
| 1515 | `detectionUnavailable` | `Pasteboard detection requires macOS {minimumOS} or later.` |
| 1516 | `detectionDenied` | `The user denied access to the pasteboard contents.` |
| 1517 | `detectionFailed` | `Pasteboard detection failed: {reason}.` |
| 1518 | `filePromiseTypeInvalid` | `File promise type must conform to data or directory: {value}.` |
| 1519 | `filePromiseWriteFailed` | `Failed to write the promised file: {reason}.` |
| 1520 | `filePromiseReceiveFailed` | `Failed to receive the promised file: {reason}.` |
| 1521 | `observationAlreadyActive` | `Clipboard observation is already active.` |
| 1522 | `cancelled` | `The clipboard operation was cancelled.` |
| 1599 | `unknown` | `An unknown clipboard error occurred: {reason}.` |

---

## 12. テスト設計

### 12.1 単体テスト（Swift Testing、`MacLibraryTests/Clipboard/`）

Mock は `ClipboardRepository` を実装し、`shouldFail: Bool` / `xxxCallCount` / `stubbedXxx` の 3 点セットを持つ（common.md の Mock 設計パターン）。

| 対象 | 正常系 | 異常系 | 境界値 |
|---|---|---|---|
| `ClipboardContentValidator` | 有効な items を通す | `emptyContent` / `emptyRepresentations` / `invalidTypeIdentifier` | 1 アイテム、上限ちょうどのサイズ、上限 +1 |
| `CopyContentUseCase` | Repository に 1 回委譲し `PasteboardOwnership` を返す | Repository の throw を素通し | items が 1 件と多数 |
| `AppendContentUseCase` | 所有権一致で成功 | `ownershipLost` / `appendRejected` | `changeCount` が一致 / +1 |
| `ReadContentUseCase` | items を返す | `pasteboardUnavailable` | 0 件、複数件 |
| `ReadDataUseCase` | Data を返す | `noMatchingItem` | `nil` 返却（エラーにしない）ことの確認 |
| `GetSnapshotUseCase` | 型一覧を返す | - | `matchingTypes` 指定あり / なし |
| `ClearClipboardUseCase` | 新 `changeCount` を返す | - | - |
| `CreatePasteboardUseCase` | named / unique を返す | `invalidPasteboardName` | 空文字 |
| `RemovePasteboardUseCase` | 一意名を解放 | **`cannotReleaseStandardPasteboard`（`.general` と標準名 5 種すべて）** | - |
| `DetectPatternsUseCase` 他 | パターン集合を返す | `emptyDetectionPatterns` / `detectionUnavailable` / `detectionDenied` | 空集合、全パターン |
| `ClipboardChangeTracker` | `changeCount` 変化を検出 | - | 同値、+1、桁上がり |
| `CheckForegroundChangeUseCase` | 変化ありで `true` | - | 初回呼び出し |
| `ProvideFilePromiseUseCase` | セッションを返す | `filePromiseTypeInvalid` | - |
| `ClipboardError` | 全 23 ケースの `errorCode` / `errorMessage` | - | コードの重複がないこと |

### 12.2 統合テスト（実 `NSPasteboard` を使用）

`.unique` スコープを使い、`general` を汚さない。各テストは `defer` で `releaseGlobally()` する。

| ID | 検証内容 | 企画書リスク対応 |
|---|---|---|
| IT-01 | copy → read の往復で内容が一致する | - |
| IT-02 | copy 後の append で items が増え、`changeCount` が変わらない | **RK-23 / V-13b** |
| IT-03 | 別途 `clearContents` した後の append が `ownershipLost` になる | **RK-23 / V-13a** |
| IT-04 | `copy(localOnly: true)` が `clearContents` を経由しない（`currentHostOnly` が解除されない） | **RK-05** |
| IT-05 | `NSPasteboardItem` を再利用しない（同一内容の連続 copy が例外を投げない） | **RK-14** |
| IT-06 | `removePasteboard(.general)` が `cannotReleaseStandardPasteboard` を投げる | **RK-07** |
| IT-07 | 複数アイテム read で件数が保たれる（改行連結されない） | **RK-15** |
| IT-08 | 監視開始 → 別プロセス相当の書き込み → イベント 1 回 → 停止でイベントが止まる | RK-11 |
| IT-09 | File Promise セッションが provider / delegate を保持し、スコープ離脱後も `deinit` しない | **RK-21 / V-11** |
| IT-10 | `releaseFilePromise` 後に参照が解放される | RK-21 |
| IT-11 | 15.4 未満相当の分岐で `detectionUnavailable` を返す（`@available` 分岐のテスト用注入） | **RK-01** |

### 12.3 並行性テスト

| ID | 検証内容 | 対応リスク |
|---|---|---|
| CT-01 | Swift 6 strict concurrency でビルドが警告ゼロ | RK-08 |
| CT-02 | `ClipboardChangeMonitor` が `@MainActor` で Timer を扱い、非 Sendable 捕捉の警告が出ない | **RK-10** |
| CT-03 | `FilePromiseDelegate` が nonisolated 要件を満たし、適合隔離エラーが出ない | **RK-09 と同種** |
| CT-04 | Manager の callback が常に MainActor で呼ばれる | mac.md |
| CT-05 | 同期 UseCase が `async` になっていない（シグネチャ検査） | common.md |

### 12.4 手動確認項目

| ID | 内容 | 実施環境 |
|---|---|---|
| MT-01 | 他アプリ（TextEdit）でコピー → サンプルアプリで read できる | macOS 15.x 実機 |
| MT-02 | サンプルアプリで copy → 他アプリで貼り付けできる | 同上 |
| MT-03 | append が自所有時のみ成功し、他アプリ所有時は明示エラーになる | 同上 |
| MT-04 | 監視が別アプリのコピーを検出する。非アクティブ時に停止し復帰時に照合する | 同上 |
| MT-05 | File Promise を Finder へドロップしてファイルが生成される | 同上 |
| MT-06 | `PasteButton` から貼り付けできる | 同上 |
| MT-07 | 検出 API が 15.4 以降で動作し、15.0–15.3 で `detectionUnavailable` になる | **15.4.1 と 15.2 の両方が必要** |
| MT-08 | `localOnly` の Universal Clipboard 抑止 | **実機 Mac + iPhone（企画書 V-8 / V-9。VM 不可）** |
| MT-09 | プライバシーアラートの挙動 | **企画書 RK-22 により検証手段が未確立。判定保留** |

---

## 13. 実装タスク分解

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | Domain モデル + `ClipboardError`（23 ケース・コード 1501〜1599） | 0.5日 | なし | 型がビルドでき、`ClipboardErrorTests` が全ケース通過 | Domain に platform 型が無いこと。コード重複が無いこと |
| T-02 | Port（`ClipboardRepository` / `ClipboardTypeIdentifierValidating`）定義 | 0.5日 | T-01 | protocol がビルドでき、Mock が実装できる | Port にドメイン型のみが現れること。同期・async の割り当てが §9 と一致 |
| T-03 | `PasteboardResolver` / `ClipboardMappers` / `ClipboardTypeIdentifierValidator` / `ClipboardImageCoder` | 1.0日 | T-02 | Data 層の単体テストが通過 | RK-14（アイテム再利用禁止）、RK-18（UTI 検証） |
| T-04 | `ClipboardRepositoryImpl` の C / R / Q / X 実装（copy / append / read / readData / snapshot / clear） | 1.5日 | T-03 | IT-01〜IT-05、IT-07 が通過 | **§6.4 の所有権取得単一経路（RK-05）**、**§6.3 の所有権トークン（RK-23）**、RK-15 |
| T-05 | `ClipboardRepositoryImpl` の P 実装（create / remove）と標準ペーストボード保護 | 0.5日 | T-03 | IT-06 が通過 | **RK-07 のガードが構造的に効いていること** |
| T-06 | UseCase 群（C / R / Q / X / P）+ `ClipboardContentValidator` + 単体テスト | 1.5日 | T-04, T-05 | 12.1 の該当行が全通過 | UseCase が同期のままであること（不要な `async` が無い） |
| T-07 | `MacClipboardManager` の骨格（DI、callback 版 + async 版、`Log.d`） | 1.0日 | T-06 | 全 OP が呼び出せ、callback が MainActor で返る | mac.md の callback / async 併設。CT-04 |
| T-08 | 検出 API（D 群）実装 + `ClipboardDetectionMapper` + バージョン分岐 | 1.0日 | T-07 | IT-11 と該当単体テストが通過 | **15.4 未満で Q 群フォールバックを実装していないこと（RK-01）** |
| T-09 | `ClipboardChangeMonitor` + `ClipboardChangeTracker` + アクティブ状態連動 | 1.0日 | T-07 | IT-08、CT-02 が通過 | **配置が MacLibrary/Presentation であること（common.md 再発防止）**、RK-10 |
| T-10 | File Promise（`FilePromiseDelegate` / `FilePromiseSession` / provide / release / receive） | 1.5日 | T-07 | IT-09、IT-10、CT-03 が通過 | **RK-21: provider と delegate の双方を強参照。completion は要求ごとに 1 回。全体で 1 回に絞るガードを置かない** |
| T-11 | `PasteButtonFactory` | 0.5日 | T-07 | ビルドが通り、サンプルから配置できる | RK-16 を DocC に明記 |
| T-12 | `LazyDataProvider`（遅延提供の内部利用） | 0.5日 | T-04 | 大容量 copy が遅延提供経路を通る | RK-17（provider の強参照保持） |
| T-13 | Unity Bridge（Swift facade / JSON パーサ / `.h` / `.m`） | 1.5日 | T-07〜T-10 | Unity から全 Bridge 公開 OP が呼べる | **Bridge に Delegate を実装していないこと**。mac.md の ObjC 型規約（`BOOL` / `NSInteger`） |
| T-14 | DocC 整備と契約文の明記 | 0.5日 | T-13 | `public` シンボルに DocC が付く | **「通知なし」を保証しない旨（RK-01/02/22）**、append の契約差（RK-23）、名前付きペーストボードの残存（RK-06）、`localOnly` 未検証（V-8） |
| T-15 | サンプルアプリ対応 | - | T-14 | **`design-sample-app` で設計する。本書ではファイルパスを定義しない。完了条件は「全公開 OP が `MacLibraryExample` から Unity 非依存で実行できること」** | common.md のサンプル依存方向 |

**先行（基盤）**: T-01 〜 T-07
**後続（拡張）**: T-08 〜 T-15

合計見積: 約 13.5 日（T-15 を除く）

---

## 14. リスクと緩和策

| 企画書リスク | 本設計での対応 | 残存リスク |
|---|---|---|
| RK-01 / RK-02（15.0–15.3 の検出手段なし） | 15.4 未満は `detectionUnavailable` を投げる。Q 群フォールバックを実装しない | 15.0–15.3 で検出機能が使えない。仕様として受容 |
| RK-03（`detectValues` は通知あり） | DocC に明記し、ユーザー操作起点での呼び出しを要求 | 呼び出し側の規律に依存 |
| RK-04（`expirationDate` なし） | 公開 API に持たない。DocC に iOS との差分を明記 | なし |
| RK-05（`clearContents` が `currentHostOnly` を解除） | §6.4 の単一経路。`copy` から `clearContents` を呼ばない | レビューでの確認が必要（T-04 の観点に記載） |
| RK-06（名前付きは終了後も残存） | DocC に明記。機密データを置かないことを要求 | 仕様として受容 |
| RK-07（標準ペーストボードの誤解放） | `removePasteboard` で構造的にガード（T-05） | なし |
| RK-08（非 Sendable） | 全層 `@MainActor` 固定（§6.2） | 大容量時のメインスレッドブロック → RK-20 |
| RK-09（`NSServicesMenuRequestor`） | 本設計では未使用 | なし |
| RK-10（Timer と Swift 6） | `@MainActor` + `MainActor.assumeIsolated`（T-09） | なし |
| RK-11（通知 API なし） | ポーリング + アクティブ状態連動。既定 0.5 秒 | 取りこぼしと電力コスト。間隔は設定可能にして緩和 |
| RK-12（サンドボックス下の fileURL） | 読み込み失敗を握り潰さず明示エラー | **企画書 V-6 が未消化** |
| RK-13 / RK-14（`writeObjects` 追加・アイテム再利用） | 所有権取得 → `writeObjects` に固定。アイテムは毎回生成 | なし |
| RK-15（最良表現の改行連結） | `pasteboardItems` 経路に統一 | なし |
| RK-16（`PasteButton` の自動 validate なし） | DocC に明記 | 呼び出し側で制御が必要 |
| RK-17（provider の保持） | Repository が強参照。L-03 で解放 | **企画書 V-3 が未消化** |
| RK-18（UTI 検証） | `ClipboardTypeIdentifierValidator` を Data 層に配置 | なし |
| RK-19（廃止定数） | `NSPasteboardType*` / `NSPasteboard.Name.*` のみ使用。レビュー観点に記載 | なし |
| RK-20（同期 IPC のブロック） | 大容量は遅延提供 / File Promise へ。閾値 10MB で警告 | **閾値の妥当性は要検証** |
| RK-21（File Promise の weak delegate） | `FilePromiseSession` が双方を強参照。stale 検出で自動解放（T-10） | 解放漏れの可能性。監視未使用時は明示解放が必要 |
| RK-22（アラート検証手段が未確立） | どの読み取り経路も「通知なし」を保証しない | **MT-09 は判定保留のまま** |
| RK-23（append の契約差） | 所有権トークンで明示エラー化（§6.3） | iOS と API 名は同じで契約が異なる。DocC で明示 |

### 14.1 要検証事項（本設計で新たに生じたもの）

| ID | 内容 | 検証方法 |
|---|---|---|
| DV-01 | `@MainActor` 固定で大容量データ（10MB 超の画像）の copy / read が UI をブロックする程度 | 実機で 1MB / 10MB / 50MB を計測し、閾値の妥当性を判断する |
| DV-02 | `ClipboardLimits` の警告閾値 10MB が妥当か | 同上 |
| DV-03 | 監視のポーリング間隔 0.5 秒が電力・CPU に与える影響 | 実機で 0.5 / 1.0 / 2.0 秒を比較 |
| DV-04 | `FilePromiseSession` の stale 自動解放が、約束の履行中に誤って解放しないか | 履行に時間がかかる書き出しで検証 |
| DV-05 | `receiveFilePromises` の reader が `fileTypes.count` と同数呼ばれる保証があるか（企画書のヘッダ注記では保証されない） | 複数ファイルの約束を受領して回数を計測 |

---

## 15. Definition of Done

### 設計完了条件

- [x] 企画書 v3 の全サブ機能（P / C / L / H / R / Q / X / M / D / U / F）を設計対象に含めた。out はすべて理由付きで明記した
- [x] common.md の各項目に対する適合可否を §3 に記載した
- [x] mac.md の各項目に対する適合可否を §4 に記載した
- [x] **層とモジュールの対応を §4.1 で判定し、system callback を持つクラスがすべて `mac/MacLibrary` 側に配置されることを確認した**
- [x] **全公開操作（OP-01〜OP-19）を §9 の同期・非同期レイヤー対応表に収録し、System API / Repository / UseCase / Manager callback / Manager native / Bridge / actor / キャンセル・所有権 / 変換理由の全列を記載した**
- [x] 企画書の分類表と設計表の差分を §9.1 に「新規設計判断」として理由付きで記載した
- [x] ドメインエラーの全 23 ケースを §10 に列挙した
- [x] エラーコード / メッセージ対応表を §11 に記載し、既存の使用済みコード帯と衝突しないことを確認した
- [x] 単体 / 統合 / 並行性 / 手動確認をテスト設計で分離し、企画書の全リスク項目に対応する検証ケースを含めた
- [x] 実装タスクを 0.5〜1.5 日粒度に分解し、依存関係・完了条件・レビュー観点を付けた
- [x] 変更対象ファイルを具体的なパスで示した。`docs/` を対象に含めていない
- [x] 不確実な事項を DV-01〜DV-05 として要検証に分離した

### 実装完了条件（次工程で満たす）

- [ ] `mac/MacLibrary` の Clipboard ターゲットが Swift 6 strict concurrency で警告ゼロでビルドできる
- [ ] **実装のシグネチャ・actor isolation・キャンセル契約が §9 の対応表と一致している**
- [ ] 12.1 の単体テストが全通過する
- [ ] 12.2 の統合テスト IT-01〜IT-11 が全通過する
- [ ] 12.3 の並行性テスト CT-01〜CT-05 が全通過する
- [ ] `public` シンボルすべてに英語の DocC が付いている
- [ ] 全メソッド先頭に `Log.d` があり、クリップボード内容が §4.2 の方針で秘匿されている
- [ ] Unity Bridge に Delegate 実装が存在しない
- [ ] `MacLibraryExample` が `MacLibrary` のみに依存して全公開 OP を実行できる
- [ ] MT-01〜MT-07 を macOS 15.x で実施した（MT-08 は実機 Mac + iPhone、MT-09 は判定保留）
