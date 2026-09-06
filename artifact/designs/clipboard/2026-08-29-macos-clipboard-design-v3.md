# macOS クリップボード機能 実装設計書 v3

- 作成日: 2026-08-29
- 改訂日: 2026-08-29（v3: 第 2 回レビュー指摘 14 件を全件反映）
- 前版: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v2.md`
- 初版: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design.md`
- レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review-v2.md`（第 2 回）、`.../2026-08-29-macos-clipboard-design-review.md`（第 1 回）
- 対象企画書: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research-v3.md`
- 対象OS: macOS 15 以降（`MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1）
- 使用言語: Swift 6（strict concurrency）、Objective-C（Bridge）
- 対象モジュール: `mac/MacLibrary`（Domain 〜 Manager）、`mac/UnityMacPlugin`（Unity Bridge）
- 適用ルール: `agent-rules/coding-rules/common.md`、`agent-rules/coding-rules/mac.md`

---

## 0. v3 での変更点（第 2 回レビュー反映サマリ）

### 高優先度（4 件）

| # | 指摘 | 反映 |
|---|---|---|
| R2-H1 | OP-01〜OP-08 の native API が同期 `throws` へ退行し `mac.md` と不整合 | **OP-01〜OP-11 の native 版を `async throws` + `@discardableResult` に戻した**。Repository / UseCase は同期のまま。OP-12〜OP-17 / OP-19 の即時 control / factory のみ同期を維持（§8.1、§9）。§4 の適合判定も訂正 |
| R2-H2 | OP-18 のキャンセル経路が公開面にない | **OP-20 `cancelReceiveFilePromises(_:)` を新設**。Bridge に `clipboardCancelReceiveFilePromises` を追加し、開始 ack で receipt handle を返す契約に変更。`AsyncThrowingStream` の `onTermination` と Task キャンセルを同じ control に接続（§7.12、§8.1、§8.4） |
| R2-H3 | Bridge 契約が「全 endpoint 定義済み」を満たさない | **§8.4 を全面書き直し**。全 20 endpoint の完全な C prototype、operation callback と event callback の区別、全 request / result / event の JSON schema、required / optional / null、開始失敗、terminal event を定義。exactly-once を operation / terminal callback に限定し、event callback は購読中 N 回と明記 |
| R2-H4 | File Promise 提供側が複数同時履行と race を扱えない | **`inFlightCount` を持つ状態機械へ変更**（§7.12）。専用 `OperationQueue` を **serial** と定義。開始をクロージャ実行前に原子的に記録し、全要求完了後のみ解放。同時開始・完了・release・stale の race テストを追加 |

### 中優先度（9 件）

| # | 指摘 | 反映 |
|---|---|---|
| R2-M5 | `releaseFilePromise` の冪等性と error が矛盾 | **ハンドル基準の control（release / cancel）を完全冪等・非 throwing に統一**。unknown / released はいずれも成功扱い。`promiseHandleNotFound` を**削除**（§7.12、§10） |
| R2-M6 | OP-18 の terminal result と error の対応が不明 | **§7.12.3 に truth table を新設**。開始失敗 / per-file failure / quiescence / overallTimeout / explicit cancel / Task cancel の 6 経路について stream / aggregate async / callback / Bridge の結果を固定。partial receipt は throw せず `finished` で返す |
| R2-M7 | `PromiseObjectLookup` / `PasteHandle` が未定義 | **§6.5.1 に両型の配置・protocol・可視性・寿命を定義**。`PromiseObjectLookup` は Data 層の非保持 lookup。`PasteHandle` は `ClipboardPasteHandle` として定義し、View container の `deinit` から解放する所有グラフを §7.11 に追加 |
| R2-M8 | `matchedString` が全 8 種から欠落 | **全 Domain entity に `matchedString` を追加**（§7.10）。`DDMatch` 基底クラスの必須プロパティ |
| R2-M9 | timeout / interval / limits の入力制約がない | **§6.8 に検証規則を新設**。正数性・大小関係を initializer で検証し、公開入力は `invalidConfiguration` を返す |
| R2-M10 | PasteButton の順序・全失敗・View 寿命 | **結果を入力順に正規化**し `providerIndex` を保持。`isPartial` は成功と失敗が**両方ある**場合のみ true。全失敗は `items` が空で判別。View container の `deinit` で cancel（§7.11） |
| R2-M11 | Bridge OP-16 の `sourcePath` 寿命・Sandbox | **登録時に app-owned staging へスナップショットする方式に確定**（§8.4.5）。copy policy、失敗通知、release 時 cleanup、機密パスのログ禁止を定義 |
| R2-M12 | register 後の write 失敗で登録が残留 | **UseCase に register → write → commit / catch で release の transaction を定義**（§7.4、§7.12）。leak テストを追加 |
| R2-M13 | テスト表が残存契約を固定していない | §12 に 18 ケース追加（§12.1 / 12.2 / 12.3 / 12.4 / 12.5） |

### 低優先度（1 件）

| # | 指摘 | 反映 |
|---|---|---|
| R2-M14 | `BridgeError` の DocC と NULL callback 契約が食い違う | **NULL callback を許容する方針を維持**し、既存 `BridgeError.swift` の DocC 修正を §5.2 の変更対象に追加 |

---

## 0.1 v2 での変更点（第 1 回レビュー反映サマリ）

### 高優先度（8 件）

| # | 指摘 | 反映 |
|---|---|---|
| H-1 | Port が Presentation 型 `FilePromiseSession` を返す | Domain の不透明ハンドル `FilePromiseHandle` / `PasteboardPromiseHandle` を導入。Port はハンドルのみを返す（§8.2） |
| H-2 | Unity Bridge の契約が未定義 | §8.4 に全 endpoint の callback 型・JSON schema・C 文字列寿命・スレッド・NULL・exactly-once を定義。境界失敗は既存 `BridgeError`（1301 / 1302）、Manager 以降は `ClipboardError` と責務分離 |
| H-3 | `receiveFilePromises` が保証されない `fileTypes.count` に依存 | 総数による集約を**廃止**。ファイル単位イベント + 静穏タイムアウト + 全体タイムアウトによる終了モデルへ再設計（§7.12） |
| H-4 | OP-18 に native async 版がない | Manager に `AsyncThrowingStream` 版と、終端まで待つ `async throws` 版を追加（§8.1） |
| H-5 | system delegate の所有が Repository / Presentation に分散 | **Manager 層の `ClipboardSystemCoordinator` 1 クラスに一元化**（§6.5） |
| H-6 | `ReceiveFilePromisesUseCase` が欠落 | UseCase 3 種（provide / release / receive）と Mock・テストを追加（§6.1、§12.1） |
| H-7 | 全層 `@MainActor` と同期 C Bridge が両立しない | **Bridge は control 操作も含めて全て callback 形式**にし、facade を nonisolated + 内部 hop とする。既存 `UnityMacShareManager` の「任意スレッド可」契約を維持（§6.6） |
| H-8 | `PasteButton` の `[NSItemProvider]` → `[ClipboardItemData]` 変換が未設計 | `ClipboardPasteLoader` を新設し、非同期ロード・部分失敗・キャンセル・一時ファイル寿命を定義（§7.11） |

### 中優先度（11 件）

| # | 指摘 | 反映 |
|---|---|---|
| M-1 | `readData` の `Data?` と `noMatchingItem` が矛盾 | `Data?` を維持し **`noMatchingItem` を削除**。エラー表・コード表・テストを同期 |
| M-2 | `accessBehavior` が無引数 | `accessBehavior(scope:)` に変更。15.4 未満は `.unavailable`、解決不能 scope は throw（§7.10） |
| M-3 | 10MB 警告と `contentTooLarge` 拒否が矛盾 | `ClipboardLimits`（Domain）で **warn 10MB / hard 100MB** を分離。Validator に注入（§6.7） |
| M-4 | File Promise session の解放が監視 tick 依存 | 監視から独立した `ClipboardSystemCoordinator` の lifecycle 管理へ。状態遷移を定義（§7.12） |
| M-5 | `observationAlreadyActive` の到達条件がない | **restart 方式に統一し当該エラーを削除**。scope 解決を停止より先に行う順序も定義（§7.9） |
| M-6 | 非同期契約（timeout / cancel / late result / exactly-once）が不足 | §9 の対応表に 4 列を追加し全 OP を埋める |
| M-7 | 検出値の Domain mapping が非可逆 | `DDMatch*` の全フィールドを保つ Domain struct を定義。`patterns` / `metadataTypes` も追加（§7.10） |
| M-8 | `snapshot(matchingTypes:)` の意味が不明 | 返却型に `matchingItemIndexes` を追加。UTI conformance 判定、nil / 空配列の扱いを定義（§7.7） |
| M-9 | File Promise の URL 契約と入力検証がない | `write` の引数は**完成ファイルの URL**と定義。fileName 検証と destination policy を追加（§7.12） |
| M-10 | テスト網羅性 | 全 OP を ID で追跡。exactly-once / NULL / parse failure / partial failure / late callback / release race を追加（§12） |
| M-11 | scope 表が API ID 単位でない | §2.1 に企画書 API ID 単位の採用・内部限定・対象外の完全対応表を追加 |

### 低優先度（1 件）

| # | 指摘 | 反映 |
|---|---|---|
| L-1 | `ClipboardImageCoder` の到達経路が不明 | **v1 から削除**。`imageDecodeFailed` / `imageEncodeFailed` も削除。画像は UTI → raw `Data` で扱う |

---

## 1. 設計目的

企画書 v3 で確定した macOS の `NSPasteboard` API 群を、native-toolkit の Clean Architecture に沿って `mac/MacLibrary` へ実装するための設計を確定する。

企画書で実測により確定した制約を設計に織り込む。

- **RK-21**: `NSFilePromiseProvider.delegate` は `weak`。provider / delegate を強参照するオーナーが必須
- **RK-23**: 追記は自分が所有権を持つ間のみ成立。他アプリ所有時は `false` を返して何も起きない
- **RK-08 / RK-10**: `NSPasteboard` は非 Sendable。`Timer` を使う監視は `@MainActor` 隔離が必要
- **RK-22**: アラート挙動の検証手段が未確立。どの経路も「通知なし」を保証しない

---

## 2. スコープ（in / out）

### 2.1 企画書 API ID 単位の対応表（M-11）

| 企画書 ID | API | v1 での扱い | 理由 |
|---|---|---|---|
| P-01〜P-05 | general / init(name:) / withUniqueName / releaseGlobally / name | **公開**（OP-07 / OP-08 / scope 解決） | - |
| P-06 | `NSPasteboard.Name` | 内部限定 | `PasteboardScope` に包む |
| C-01 | `clearContents` | **公開**（OP-06）+ 内部 | §6.4 の単一経路 |
| C-02 | `prepareForNewContents(with:)` | 内部限定 | 所有権取得の唯一の経路 |
| C-03 | `writeObjects` | **公開**（OP-01 / OP-02） | - |
| C-04〜C-06 | `setString` / `setData` / `setPropertyList` | **対象外** | 先頭アイテムのみに作用し複数アイテム設計と噛み合わない。C-07〜C-10 で代替 |
| C-07〜C-10 | `NSPasteboardItem` 生成と設定 | 内部限定 | Mapper が使用 |
| C-11 | `PasteboardType` | 内部限定 | 公開は UTI 文字列 |
| C-12〜C-15 | `NSPasteboardWriting` / `WritingOptions` | 内部限定 | 遅延提供で使用 |
| L-01〜L-03 | `setDataProvider` / DataProvider | 内部限定 | 大容量 copy の内部最適化（§7.4） |
| L-04〜L-07 | `declareTypes` / `NSPasteboardTypeOwner` | **対象外** | 企画書 RK-13 でレガシー扱い |
| H-01 | `.currentHostOnly` | **公開**（`ClipboardCopyOptions.localOnly`） | - |
| R-01 | `readObjects` | 内部限定 | OP-03 の実装に使用 |
| R-02 / R-03 | ReadingOptionKey | **対象外** | URL 特化オプション。v1 では不要 |
| R-04 | `string(forType:)` | **対象外** | RK-15（改行連結）のため使わない |
| R-05 | `data(forType:)` | **公開**（OP-04） | - |
| R-06 | `propertyList(forType:)` | **対象外** | plist 型は v1 のスコープ外 |
| R-07 / R-08 / R-09 | `pasteboardItems` / `index(of:)` / item アクセサ | 内部限定 | OP-03 / OP-05 の実装 |
| R-10〜R-13 | `NSPasteboardReading` | **対象外** | カスタム型読み取りは v1 で提供しない |
| Q-01〜Q-06 | types / availableType / canRead* | 内部限定 | OP-05 に集約。**単独公開しない**（RK-01） |
| Q-07 | `types(filterableTo:)` | **対象外** | Filter Services はレガシー |
| M-01 | `changeCount` | **公開**（OP-13〜OP-15） | - |
| D-01〜D-07 | 検出 API / accessBehavior | **公開**（OP-09〜OP-12） | 15.4+ |
| D-08〜D-11 | 定数・値型・ObjC 版 | 内部限定 | Domain 型に写像 |
| U-01 | `PasteButton(payloadType:)` | **対象外** | U-02 を採用（UTI 指定と相性が良い） |
| U-02 | `PasteButton(supportedContentTypes:)` | **公開**（OP-19、ネイティブ専用） | - |
| U-03 / U-04 | 非推奨 initializer | **対象外** | 非推奨 |
| U-05〜U-07 | `copyable` / `cuttable` / `pasteDestination` | **対象外** | SwiftUI View modifier であり、ライブラリが提供する形にならない。**サンプルアプリ側で直接使うべき API**として `design-sample-app` へ申し送る |
| U-08〜U-10 | responder chain / Services | **対象外** | 呼び出し側アプリの responder 実装に属する |
| F-01〜F-07 | File Promise 提供側 | **公開**（OP-16 / OP-17） | - |
| F-08〜F-10 | File Promise 受領側 | **公開**（OP-18） | v1 の in スコープ（レビュー M-11 で明示化） |
| G-01〜G-09 | レガシー / 廃止 | **対象外** | 企画書で採用禁止 |

### 2.2 out（その他）

| 対象 | 理由 |
|---|---|
| サンプルアプリ実装 | `design-sample-app` の担当。本書ではタスクの完了条件のみ定義 |
| `docs/` 配下 | 出力ルールにより固定で対象外 |

---

## 3. 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data / Presentation → Manager → Unity Bridge |
| Domain に platform 型を持ち込まない | 適合 | `NSPasteboard` / `NSPasteboardItem` / `NSItemProvider` / `UTType` / `DDMatch*` は Domain に出さない |
| **Port はドメイン型のみ** | **適合（v2 で修正）** | **`FilePromiseHandle` / `PasteboardPromiseHandle` はいずれも Domain の値型。Presentation 型は Port に現れない（H-1）** |
| Manager は UseCase 経由 | 適合 | `ReceiveFilePromisesUseCase` 等を追加し、Manager から Repository を直接呼ぶ経路をなくした（H-6） |
| 層とモジュールの対応 | 適合 | system callback を持つクラスは全て `mac/MacLibrary` 側。§4.1 |
| **Delegate / Listener の所有権** | **適合（v2 で修正）** | **`ClipboardSystemCoordinator`（Manager 層）1 クラスが全ての system delegate を所有する（H-5）。§6.5** |
| Manager の公開 API 方式 | 適合 | 待機を伴う操作は callback 版 + native async 版を併設。OP-18 も native async を追加（H-4） |
| システム API に合わせた同期・非同期設計 | 適合 | `NSPasteboard` は同期のため Repository / UseCase も同期。async は検出 API と File Promise 受領のみ |
| TDD | 適合 | UseCase 単位で Swift Testing。Mock は `shouldFail` / call counter / stubbed |
| エラー変換 | 適合 | **Bridge 境界は `BridgeError`、Manager 以降は `ClipboardError`（H-2）** |
| Unity Bridge を薄く保つ | 適合 | §8.4 の契約に従い、JSON パースと Manager 呼び出しのみ |
| サンプルアプリの依存方向 | 適合 | `MacLibraryExample` は `MacLibrary` のみに依存 |
| Minimum OS | 適合 | macOS 15 以降。検出 API は `@available(macOS 15.4, *)` |

---

## 4. 個別実装方針の適用チェック（mac.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| 全メソッド先頭に全パラメータの `Log.d` | 適合 | クリップボード内容は §4.2 の秘匿方針でマスク |
| ObjC / Swift ブリッジの型 | 適合 | `BOOL` / `NSInteger` / `NSString * _Nullable`。§8.4 に型表 |
| **Manager は callback 版 + `async throws` 版** | **適合（v3 で訂正）** | **mac.md は native 版を「必ず `async throws`」と定める。v2 は OP-01〜OP-08 を同期 `throws` にしており不適合だった。v3 で OP-01〜OP-11 を `async throws` + `@discardableResult` に戻した（R2-H1）。同期のままなのは common.md が例外として認める即時 control（OP-12〜OP-15、OP-17、OP-20）と factory（OP-16、OP-19）のみ** |
| private helper を一律 `async` にしない | 適合 | `NSPasteboard` 呼び出しは同期 helper |
| UI 状態更新はメインスレッドへ | 適合 | Manager callback は必ず MainActor |
| DocC コメント | 適合 | `public` シンボルに英語 DocC |
| コメント・文言は英語 | 適合 | `ClipboardError.errorMessage` も英語 |

### 4.1 モジュール配置の判定

| クラス | system callback | 配置 |
|---|---|---|
| `ClipboardSystemCoordinator` | **所有（唯一）** | `mac/MacLibrary/.../Clipboard/Coordinator/`（Manager 層） |
| `ClipboardChangeMonitor` | Timer（coordinator が所有） | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `FilePromiseDelegate` | `NSFilePromiseProviderDelegate`（coordinator が所有） | `mac/MacLibrary/.../Clipboard/Data/Promise/` |
| `LazyDataProvider` | `NSPasteboardItemDataProvider`（coordinator が所有） | `mac/MacLibrary/.../Clipboard/Data/Promise/` |
| `FilePromiseReceiptSession` | reader block（coordinator が所有） | `mac/MacLibrary/.../Clipboard/Data/Promise/` |
| `ClipboardPasteLoader` | `NSItemProvider` load（coordinator が所有） | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `PasteButtonFactory` | なし | `mac/MacLibrary/.../Clipboard/Presentation/` |
| `UnityMacClipboardManager` | なし（委譲のみ） | `mac/UnityMacPlugin/.../Clipboard/` |

**Unity プラグインに置くのは委譲のみの 4 ファイル。**

### 4.2 ログの秘匿方針

`ClipboardLog` を新設し、内容そのものを出さない。

- 文字列: 長さのみ（`text(len:42)`）
- Data: バイト数のみ（`data(bytes:1024)`）
- URL: スキームとホストのみ。パス・クエリは出さない
- UTI: そのまま
- ペーストボード名: `general` はそのまま、名前付きは短縮ハッシュ

---

## 5. 既存実装差分サマリー

### 5.1 新規追加

| モジュール | 追加内容 |
|---|---|
| `mac/MacLibrary` | `Clipboard/` 配下一式（§6.1） |
| `mac/MacLibrary/MacLibraryTests` | `Clipboard/` 配下のテスト一式 |
| `mac/UnityMacPlugin` | `Clipboard/` 配下 4 ファイル |

### 5.2 既存への変更

| 対象 | 変更 | 破壊的変更 |
|---|---|---|
| `mac/MacLibrary/MacLibrary.xcodeproj` | ファイル追加 | なし |
| `mac/UnityMacPlugin/UnityMacPlugin.xcodeproj` | ファイル追加 | なし |
| `.../Notification/Domain/Error/BridgeError.swift` | **DocC のみ修正**（R2-M14）。既存 DocC は `contractViolation` の例に「nil callback」を挙げているが、Clipboard Bridge は **callback NULL を許容**する。例を「unexpected nil argument」に限定し、nil callback を例から外す。**enum ケース・errorCode・errorMessage は変更しない** | なし（DocC のみ） |

**破壊的変更なし。**

### 5.3 既存規約との整合

| 規約 | 既存例 | 本設計 |
|---|---|---|
| 機能ディレクトリ | `Share/`, `Notification/` | `Clipboard/` |
| Manager 命名 | `MacShareManager` | `MacClipboardManager` |
| Bridge 命名 | `UnityMacShareManager(Bridge).h/.m` | `UnityMacClipboardManager(Bridge).h/.m` |
| エラーコード | Share 1401〜1499 / Notification 1101〜1205 / Bridge 1301〜1302 | `ClipboardError` **1501〜1599**（未使用帯） |
| テスト FW | Swift Testing | 同じ |

---

## 6. 実装アーキテクチャ

### 6.1 ファイル構成

```
mac/MacLibrary/MacLibrary/Clipboard/
├── MacClipboardManager.swift                      Manager
├── Coordinator/
│   └── ClipboardSystemCoordinator.swift           全 system delegate の唯一の所有者（H-5）
├── Common/
│   └── ClipboardLog.swift
├── Domain/
│   ├── Error/ClipboardError.swift
│   └── Model/
│       ├── PasteboardScope.swift
│       ├── PasteboardCreationRequest.swift
│       ├── PasteboardOwnership.swift
│       ├── PasteboardPromiseHandle.swift           遅延提供のハンドル（H-1）
│       ├── FilePromiseHandle.swift                 File Promise のハンドル（H-1）
│       ├── FilePromiseReceiptHandle.swift          受領セッションのハンドル（H-1）
│       ├── ClipboardItemData.swift
│       ├── ClipboardContent.swift
│       ├── ClipboardCopyOptions.swift
│       ├── ClipboardLimits.swift                   warn / hard の 2 段（M-3）
│       ├── ClipboardReadResult.swift
│       ├── ClipboardSnapshot.swift                 matchingItemIndexes を含む（M-8）
│       ├── ClipboardChangeEvent.swift
│       ├── ClipboardDetectionPattern.swift
│       ├── ClipboardDetectedValues.swift           DDMatch* の全フィールド（M-7）
│       ├── ClipboardDetectedEntities.swift         Link/Phone/Email/Postal/Event/Shipment/Flight/Money
│       ├── ClipboardDetectedMetadata.swift
│       ├── ClipboardAccessBehavior.swift
│       ├── ClipboardPasteResult.swift              入力順・部分失敗（H-8 / R2-M10）
│       ├── ClipboardPasteHandle.swift               loader 識別（R2-M7）
│       ├── FilePromiseRequest.swift
│       ├── FilePromiseReceiptEvent.swift           ファイル単位イベント（H-3）
│       └── FilePromiseReceiptPolicy.swift          timeout 設定（H-3）
├── Application/
│   ├── Port/
│   │   ├── ClipboardRepository.swift
│   │   ├── ClipboardPromiseRegistry.swift          coordinator が実装する Port（H-5）
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
│       ├── ReleaseFilePromiseUseCase.swift          （H-6）
│       ├── ReceiveFilePromisesUseCase.swift         （H-6）
│       └── ClipboardUseCases.swift
├── Data/
│   ├── Repository/
│   │   ├── ClipboardRepositoryImpl.swift            Domain ↔ NSPasteboard 変換に限定（H-5）
│   │   ├── PasteboardResolver.swift
│   │   ├── ClipboardMappers.swift
│   │   ├── ClipboardDetectionMapper.swift
│   │   └── ClipboardTypeIdentifierValidator.swift
│   └── Promise/
│       ├── PromiseObjectLookup.swift                ハンドル → AppKit の非保持 lookup（R2-M7）
│       ├── LazyDataProvider.swift
│       ├── FilePromiseDelegate.swift                nonisolated
│       └── FilePromiseReceiptSession.swift          ファイル単位イベント + timeout（H-3）
└── Presentation/
    ├── ClipboardChangeMonitor.swift
    ├── ClipboardPasteLoader.swift                   NSItemProvider → Domain（H-8）
    ├── ClipboardPasteContainerView.swift            deinit で cancelPaste（R2-M10）
    └── PasteButtonFactory.swift

mac/MacLibrary/MacLibraryTests/Clipboard/
├── Mock/
│   ├── MockClipboardRepository.swift
│   ├── MockClipboardPromiseRegistry.swift
│   ├── MockClipboardTypeIdentifierValidating.swift
│   └── MockClock.swift
├── Domain/ClipboardErrorTests.swift
├── Application/ (UseCase ごとに 1 ファイル、19 本)
├── Data/
│   ├── ClipboardTypeIdentifierValidatorTests.swift
│   ├── ClipboardMappersTests.swift
│   ├── ClipboardDetectionMapperTests.swift
│   ├── PasteboardResolverTests.swift
│   └── FilePromiseReceiptSessionTests.swift
└── Presentation/
    ├── ClipboardChangeMonitorTests.swift
    └── ClipboardPasteLoaderTests.swift

mac/UnityMacPlugin/UnityMacPlugin/Clipboard/
├── UnityMacClipboardManager.swift                   nonisolated facade（H-7）
├── UnityMacClipboardJsonParser.swift
├── UnityMacClipboardManagerBridge.h
└── UnityMacClipboardManagerBridge.m
```

### 6.2 actor isolation の方針

`ClipboardRepositoryImpl` / 全 UseCase / `MacClipboardManager` / `ClipboardSystemCoordinator` / `ClipboardChangeMonitor` / `ClipboardPasteLoader` / `PasteButtonFactory` を `@MainActor` とする。

**根拠**: `NSPasteboard` / `NSPasteboardItem` は非 Sendable（企画書で実測確認済み）。`Timer` は Swift 6 で `@MainActor` が必要（RK-10）。SwiftUI / `NSView` 生成は MainActor 必須。

**nonisolated にする例外**

| クラス | 理由 |
|---|---|
| `FilePromiseDelegate` | `filePromiseProvider(_:writePromiseTo:completionHandler:)` が `NS_SWIFT_NONISOLATED`。`@MainActor` にすると適合隔離エラー（企画書 RK-09 と同種） |
| `FilePromiseReceiptSession` | reader block が任意の `OperationQueue` で呼ばれる。内部状態は `NSLock` で保護し、イベントは MainActor へ転送 |
| `UnityMacClipboardManager` | 任意スレッドから呼ばれる Bridge facade（§6.6） |

**受容するリスク（RK-20）**: 大容量データの同期読み書きはメインスレッドをブロックする。§6.7 の `ClipboardLimits` で warn / hard の 2 段に分け、大容量は遅延提供（§7.4）または File Promise へ誘導する。

### 6.3 所有権モデル（RK-23）

`copy` は `PasteboardOwnership`（`scope` + `changeCount`）を返す。`append` は実行前に現在の `changeCount` と照合し、不一致なら **`writeObjects` を呼ばずに** `ownershipLost` を投げる。一致していても `writeObjects` が `false` なら `appendRejected` を投げる。

### 6.4 Universal Clipboard 制御（RK-05）

所有権取得は `ClipboardRepositoryImpl` の内部 helper `takeOwnership(scope:localOnly:) -> Int` のみが行い、常に `prepareForNewContents(with:)` を使う。`clearContents()` は OP-06 でのみ使用する。`copy` 経路からの `clearContents()` 呼び出しは禁止（レビュー観点）。

### 6.5 system delegate の所有モデル（H-5 / 新規設計判断）

common.md は「system Delegate / Listener は **Manager 層の 1 クラスのみが所有する**」と定める。v1 は `LazyDataProvider` を Repository が、File Promise の delegate を Presentation が所有しており違反していた。

**v2 の構造**

```
MacClipboardManager (Manager)
  └─ owns ─> ClipboardSystemCoordinator (Manager 層, @MainActor)
                ├─ owns ─> [PasteboardPromiseHandle : LazyDataProvider]
                ├─ owns ─> [FilePromiseHandle       : (NSFilePromiseProvider, FilePromiseDelegate)]
                ├─ owns ─> [FilePromiseReceiptHandle: FilePromiseReceiptSession]
                ├─ owns ─> ClipboardChangeMonitor
                └─ owns ─> [PasteHandle             : ClipboardPasteLoader]
```

- **`ClipboardSystemCoordinator` が全ての system delegate / listener の唯一の強参照保持者**
- Repository は Domain ↔ `NSPasteboard` の変換に限定し、delegate を保持しない
- Repository が遅延提供を書き込む必要がある場合、**delegate オブジェクトそのものは受け取らず**、`ClipboardPromiseRegistry`（Application Port、実装は coordinator）から `PasteboardPromiseHandle` を受け取り、Data 層の `PromiseObjectLookup`（coordinator が注入する読み取り専用ビュー）でハンドルから provider を解決する
- 登録・保持・解放は coordinator のみが行う。Repository と Data 層はハンドルからの解決しかできない

**依存方向**: `ClipboardPromiseRegistry` は Application 層の Port。coordinator（Manager 層）が実装する。Manager → Application は正方向であり、逆流しない。

### 6.5.1 Coordinator 境界の内部型（R2-M7）

v2 では図と本文にだけ現れていた 2 型を、配置・可視性・寿命まで確定する。

| 型 | 配置 | 可視性 | 契約 |
|---|---|---|---|
| `PromiseObjectLookup` | `Clipboard/Data/Promise/PromiseObjectLookup.swift` | `internal protocol`（`@MainActor`） | ハンドル → AppKit オブジェクトの**非保持 lookup**。`func lazyProvider(for: PasteboardPromiseHandle) -> NSPasteboardItemDataProvider?` / `func filePromiseProvider(for: FilePromiseHandle) -> NSFilePromiseProvider?`。**戻り値を保持してはならない**（`setDataProvider` / `writeObjects` の呼び出し中のみ使用）。強参照は coordinator のみが持つ |
| `ClipboardPasteHandle` | `Clipboard/Domain/Model/ClipboardPasteHandle.swift` | `public struct`（`id: UUID`） | PasteButton の loader 登録を識別する。View container の `deinit` から `coordinator.cancelPaste(_:)` を呼ぶために使う |

**DI 順序**: `MacClipboardManager.init` → `ClipboardSystemCoordinator` 生成 → coordinator を `PromiseObjectLookup` として `ClipboardRepositoryImpl` に注入 → Repository を UseCase に注入。coordinator は Repository を保持しない（循環回避）。

### 6.8 設定値の検証（R2-M9）

公開入力として受け取る時間・サイズは initializer で検証し、違反は `ClipboardError.invalidConfiguration(String)` を投げる。

| 対象 | 制約 |
|---|---|
| `ClipboardLimits.warnBytesPerRepresentation` | `> 0` かつ `<= maxBytesPerRepresentation` |
| `ClipboardLimits.maxBytesPerRepresentation` | `> 0` かつ `<= maxTotalBytes` |
| `ClipboardLimits.maxTotalBytes` | `> 0` |
| 監視 `interval` | `> 0` かつ `<= 60` 秒 |
| PasteButton `timeout` | `> 0` かつ `<= 300` 秒 |
| `FilePromiseReceiptPolicy.quietInterval` | `> 0` かつ `< overallTimeout` |
| `FilePromiseReceiptPolicy.overallTimeout` | `> 0` かつ `<= 3600` 秒 |

`ClipboardLimits.default` / `FilePromiseReceiptPolicy.default` は制約を満たす。境界値はテストで固定する（§12.1）。

### 6.6 Unity Bridge のスレッド境界（H-7 / 新規設計判断）

v1 は Manager を `@MainActor` にしながら control 操作の Bridge を同期 C 関数としていた。任意スレッドから呼ばれる同期関数は、値を返しながら MainActor へホップできない。

**v2 の決定**

- `UnityMacClipboardManager`（Bridge facade）を **nonisolated** とし、既存 `UnityMacShareManager` と同じ「任意スレッドから呼び出し可」の契約を維持する
- **Bridge の全 endpoint を callback 形式にする**。`accessBehavior` / `checkForegroundChange` / `stopObserving` / `releaseFilePromise` のような同期 control 操作も、Bridge では callback で結果を返す
- facade 内部で `Task { @MainActor in ... }` により Manager を呼ぶ
- **ネイティブ Swift API は同期のまま**（common.md の control / factory 例外）。`@MainActor` 隔離のため、他アクターからの呼び出し側は `await` する

これにより「ネイティブは同期・Bridge は callback」という差分が生じるが、これは actor 隔離と C ABI の制約による必然であり、§9 の変換理由列に明記する。

### 6.7 サイズ制御（M-3）

```swift
public struct ClipboardLimits: Sendable, Equatable {
    /// 超過で Log.e を出すが処理は継続する。既定 10 MiB。
    public let warnBytesPerRepresentation: Int
    /// 超過で contentTooLarge を投げる。既定 100 MiB。
    public let maxBytesPerRepresentation: Int
    /// 全アイテム・全表現の合計に対する上限。既定 200 MiB。
    public let maxTotalBytes: Int
    public static let `default` = ClipboardLimits(
        warnBytesPerRepresentation: 10 * 1024 * 1024,
        maxBytesPerRepresentation: 100 * 1024 * 1024,
        maxTotalBytes: 200 * 1024 * 1024)
}
```

`ClipboardContentValidator` に `limits` を注入する。`MacClipboardManager` の internal init で差し替え可能にし、テストで小さい値を使う。既定値の妥当性は要検証（DV-02）。

---

## 7. サブ機能別詳細設計

### 7.1 P. ペーストボード取得・寿命管理

```swift
public enum PasteboardScope: Sendable, Equatable, Hashable {
    case general
    case named(String)
    case unique(String)
}
```

- `PasteboardResolver.resolve(_:) throws -> NSPasteboard`。空名は `invalidPasteboardName`
- `createPasteboard`: `.named(n)` / `.unique` に応じて生成し、`pasteboard.name.rawValue` を包んだ scope を返す
- `removePasteboard`: `.general` および標準名 5 種（`general` / `font` / `ruler` / `find` / `drag`）は `cannotReleaseStandardPasteboard` を投げる（RK-07）。それ以外は `releaseGlobally()`

### 7.2 C. コピー / 追記

```swift
public struct ClipboardItemData: Sendable, Equatable {
    public let representations: [String: Data]   // UTI -> bytes
}
public struct ClipboardContent: Sendable, Equatable {
    public let items: [ClipboardItemData]
}
public struct ClipboardCopyOptions: Sendable, Equatable {
    public let localOnly: Bool                    // 既定 true
}
public struct PasteboardOwnership: Sendable, Equatable {
    public let scope: PasteboardScope
    public let changeCount: Int
}
```

**copy**: 検証 → resolve → `takeOwnership` → **毎回新しい `NSPasteboardItem` を生成**（RK-14）→ `writeObjects`（`false` なら `writeRejected`）→ `PasteboardOwnership` を返す。

**append**: 検証 → `changeCount` 照合（不一致で `ownershipLost`）→ `clearContents` / `prepareForNewContents` を呼ばずに `writeObjects`（`false` なら `appendRejected`）→ 同じ `ownership` を返す。

### 7.3 サイズ検証

`ClipboardContentValidator` が `ClipboardLimits` に基づき、表現ごと・合計の両方を検証する。warn 超過は `Log.e` のみ、hard 超過は `contentTooLarge(bytes:limit:)`。

### 7.4 L. 遅延データ提供（内部限定）

```swift
// Application Port（coordinator が実装）
@MainActor
public protocol ClipboardPromiseRegistry {
    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle
    func releaseLazyProvider(_ handle: PasteboardPromiseHandle)
}
```

- coordinator が `LazyDataProvider` を生成・保持し、ハンドルを返す
- Repository は `writePromised(handle:types:options:scope:)` を呼び、Data 層の `PromiseObjectLookup` でハンドル → provider を解決して `setDataProvider` する
- `pasteboardFinishedWithDataProvider(_:)`（L-03）到達時に coordinator が解放する
- 公開 API には出さない。`copy` が hard limit 未満かつ warn 超過のときに内部で選択する
- **登録 → 書き込み → commit / catch で release の transaction とする**（R2-M12）。`writePromised` が throw または `false` を返した場合、`releaseLazyProvider(handle)` で登録を巻き戻す

**要検証**: システム側が provider を保持するかは企画書 V-3 が未消化。coordinator の強参照で安全側に倒す。

### 7.5 H. デバイス間同期制御

`localOnly` → `.currentHostOnly`。§6.4 の単一経路。既定 `true`。実効性は企画書 V-8 / V-9 が未消化のため、DocC に「実効性は未検証」と明記する。

### 7.6 R. 読み取り

```swift
public struct ClipboardReadResult: Sendable, Equatable {
    public let items: [ClipboardItemData]
    public let changeCount: Int
}
```

- `read`: `pasteboardItems` を走査し、各 item の `types` ごとに `data(forType:)` を集める。`nil` なら `pasteboardUnavailable`
- `readData(utType:)`: `data(forType:)` の結果をそのまま返す。**該当なしは `nil`（エラーにしない）**（M-1）
- `string(forType:)` は使わない（RK-15）

### 7.7 Q. スナップショット（M-8）

```swift
public struct ClipboardSnapshot: Sendable, Equatable {
    public let changeCount: Int
    /// 全アイテムの全 UTI（フィルタの有無に関わらず全件）
    public let itemTypes: [[String]]
    /// matchingTypes に適合したアイテムの index。フィルタ未指定なら全 index
    public let matchingItemIndexes: [Int]
}
```

- `matchingTypes == nil`: フィルタなし。`matchingItemIndexes` は全 index
- `matchingTypes == []`: `emptyTypeFilter` を投げる
- 判定は **UTI conformance**（`UTType.conforms(to:)`）で行い、完全一致に限定しない
- **データ本体は読まない**。ただし「通知が出ない」ことは保証しない（RK-01 / RK-22）。DocC に明記

### 7.8 X. クリア

`clearContents()` を呼び、新しい `changeCount` を返す。§6.4 のとおりこの操作だけが `clearContents()` を使う。

### 7.9 M. 変更監視（M-5）

```swift
public struct ClipboardChangeEvent: Sendable, Equatable {
    public let scope: PasteboardScope
    public let changeCount: Int
}
```

**start の順序（M-5）**

1. **先に scope を解決する**。失敗すれば throw し、**既存の監視は停止しない**
2. 解決に成功したら既存監視を停止する
3. 世代カウンタを進め、`changeCount` を初期値として記録
4. `Timer.scheduledTimer` を作る。本体は `MainActor.assumeIsolated { }` で包む（RK-10）
5. 古い世代のコールバックは無視する

**restart 方式に統一**し、`observationAlreadyActive` は定義しない（M-5）。

- 既定間隔 0.5 秒（`interval` で変更可能）
- `NSApplication.didResignActiveNotification` で停止、`didBecomeActiveNotification` で 1 回照合してから再開（RK-11）
- `onEvent: @escaping @MainActor (ClipboardChangeEvent) -> Void`
- イベント種別（changed / removed）は macOS に存在しないため持たない

### 7.10 D. 検出・プライバシー（M-2 / M-7）

**バージョン分岐（RK-01）**

- 15.4 未満 → `detectionUnavailable(minimumOS: "15.4")`
- **`canReadItem` / `canReadObject` によるフォールバックは実装しない**（企画書 RK-01 が V-1 の結果まで正式採用を禁じており、V-1 は判定保留）

**accessBehavior（M-2）**

```swift
public func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior
```

- 15.4 未満 → `.unavailable`（throw しない）
- scope 解決不能 → `invalidPasteboardName` を throw
- `NSPasteboard.accessBehavior` はインスタンスプロパティなので、必ず解決した scope のインスタンスから読む

**検出値の Domain 写像（M-7）**

`DDMatch*` の全フィールドを保持する。`String` への一律変換は行わない。

```swift
// DDMatch 基底クラスの `matchedString` は全 subclass が持つ（R2-M8）。
// DDMatch.h: "Each object contains the matched string."
public struct ClipboardDetectedLink: Sendable, Equatable {
    public let matchedString: String
    public let url: String
}
public struct ClipboardDetectedPhoneNumber: Sendable, Equatable {
    public let matchedString: String
    public let phoneNumber: String; public let label: String?
}
public struct ClipboardDetectedEmailAddress: Sendable, Equatable {
    public let matchedString: String
    public let emailAddress: String; public let label: String?
}
public struct ClipboardDetectedPostalAddress: Sendable, Equatable {
    public let matchedString: String
    public let street: String?; public let city: String?; public let state: String?
    public let postalCode: String?; public let country: String?
}
public struct ClipboardDetectedCalendarEvent: Sendable, Equatable {
    public let matchedString: String
    public let isAllDay: Bool
    public let startDate: Date?; public let startTimeZoneIdentifier: String?
    public let endDate: Date?;   public let endTimeZoneIdentifier: String?
}
public struct ClipboardDetectedShipmentTracking: Sendable, Equatable {
    public let matchedString: String
    public let carrier: String; public let trackingNumber: String
}
public struct ClipboardDetectedFlightNumber: Sendable, Equatable {
    public let matchedString: String
    public let airline: String; public let flightNumber: String
}
public struct ClipboardDetectedMoneyAmount: Sendable, Equatable {
    public let matchedString: String
    public let currencyCode: String; public let amount: Double
}

public struct ClipboardDetectedValues: Sendable, Equatable {
    public let patterns: Set<ClipboardDetectionPattern>      // M-7: 追加
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [ClipboardDetectedLink]
    public let phoneNumbers: [ClipboardDetectedPhoneNumber]
    public let emailAddresses: [ClipboardDetectedEmailAddress]
    public let postalAddresses: [ClipboardDetectedPostalAddress]
    public let calendarEvents: [ClipboardDetectedCalendarEvent]
    public let shipmentTrackingNumbers: [ClipboardDetectedShipmentTracking]
    public let flightNumbers: [ClipboardDetectedFlightNumber]
    public let moneyAmounts: [ClipboardDetectedMoneyAmount]
}

public struct ClipboardDetectedMetadata: Sendable, Equatable {
    public let metadataTypes: Set<ClipboardMetadataType>      // M-7: 追加
    public let contentTypeIdentifier: String?
}
```

**正規化規則（locale 非依存）**

| 元 | 変換 |
|---|---|
| `NSURL` | `absoluteString` |
| `NSDate` | `Date` をそのまま保持（フォーマットしない） |
| `NSTimeZone` | `identifier`（`"Asia/Tokyo"` 等。localizedName は使わない） |
| `double amount` | `Double` をそのまま保持（通貨記号を付けない） |
| `currency` | ISO コード文字列をそのまま |
| `label` | 原文をそのまま（`nil` 可） |
| `matchedString` | **原文をそのまま。全 entity で必須**（R2-M8） |

`DDMatch*` は Data 層の `ClipboardDetectionMapper` でのみ扱い、Domain には出さない。

**通知の扱い（RK-03）**: `detectValues` は一致時に通知が発生し拒否時に throw する。DocC に明記し、ユーザー操作起点での呼び出しを要求する。`detectPatterns` / `detectMetadata` は「通知しない」とヘッダにあるが、契約としては保証しない。

**キャンセル**: `CancellationError` を `ClipboardError.cancelled` に変換する。実際に届くかは企画書 V-5 が未消化。

### 7.11 U. 貼り付け UI と非同期ロード（H-8）

`PasteButton(supportedContentTypes:payloadAction:)`（U-02）の payload は `[NSItemProvider]` であり、`[ClipboardItemData]` へは**非同期ロード**が必要。

```swift
public struct ClipboardPasteItem: Sendable, Equatable {
    public let providerIndex: Int              // 入力 provider の index（R2-M10）
    public let data: ClipboardItemData
}
public struct ClipboardPasteFailure: Sendable, Equatable {
    public let providerIndex: Int
    public let error: ClipboardError
}
public struct ClipboardPasteResult: Sendable, Equatable {
    /// providerIndex の昇順（= 入力順）に正規化済み。完了順ではない。
    public let items: [ClipboardPasteItem]
    /// 同じく providerIndex の昇順。
    public let failures: [ClipboardPasteFailure]
    /// 成功と失敗が **両方** ある場合のみ true（R2-M10）。
    public var isPartial: Bool { !items.isEmpty && !failures.isEmpty }
    /// 1 件も成功しなかった。
    public var isCompleteFailure: Bool { items.isEmpty && !failures.isEmpty }
    /// provider が 0 件だった（貼り付け内容なし）。
    public var isEmpty: Bool { items.isEmpty && failures.isEmpty }
}

@MainActor
public func makePasteButton(
    acceptedTypes: [String],
    timeout: TimeInterval = 15,
    onPaste: @escaping @MainActor (ClipboardPasteResult) -> Void
) throws -> NSView
```

**`ClipboardPasteLoader` の契約**

- `acceptedTypes` は UTI として検証済み。空なら `invalidTypeIdentifier`
- 各 `NSItemProvider` について、`acceptedTypes` のうち `hasItemConformingToTypeIdentifier` を満たす**最初の型**を選ぶ。複数表現がある場合は `acceptedTypes` の**指定順**を優先度とする（決定的）
- `loadDataRepresentation(forTypeIdentifier:)` で `Data` を取得
- 個々の失敗は `pasteLoadFailed` として `failures` に積み、**他の provider の処理は継続する**（部分成功）
- 全体 `timeout`（既定 15 秒）超過で未完了分を `pasteLoadTimedOut` として積み、その時点の結果で `onPaste` を呼ぶ
- `onPaste` は **exactly-once**。timeout と全完了の競合は世代トークンで排除する
- **結果は `providerIndex` の昇順に正規化して返す**（並行ロードの完了順ではない。R2-M10）
- **一時ファイルは使わない**（`loadFileRepresentation` を使わず `loadDataRepresentation` のみ）。これにより一時 URL の寿命問題を回避する

**View の寿命と登録解除（R2-M10）**

```
PasteButtonFactory.makePasteButton()
  ├─ coordinator.registerPasteLoader(...) -> ClipboardPasteHandle
  └─ returns ClipboardPasteContainerView (NSView subclass)
        ├─ holds: handle
        ├─ hosts:  NSHostingView(PasteButton(...))
        └─ deinit: coordinator.cancelPaste(handle)
```

- 返却する `NSView` は `ClipboardPasteContainerView`（`Clipboard/Presentation/`）で、`ClipboardPasteHandle` を保持する
- **`deinit` で `coordinator.cancelPaste(handle)` を呼ぶ**。coordinator は進行中の `Progress` を `cancel()` し、loader の登録を外す
- キャンセル後は `onPaste` を呼ばない
- `cancelPaste` は**冪等**。二重解放でクラッシュしない

**制約（RK-16）**: macOS の `PasteButton` は自動 validate / invalidate を行わない。DocC に明記。

**Bridge 非公開**: `NSView` を返すため C ABI に載らない。

### 7.12 F. ファイル約束（H-1 / H-3 / M-4 / M-9）

#### 提供側

```swift
public struct FilePromiseRequest: Sendable {
    public let fileTypeIdentifier: String
    public let fileName: String
    /// 引数は「書き出し先の完成ファイル URL」。ディレクトリではない（M-9）。
    public let write: @Sendable (URL) throws -> Void
}
public struct FilePromiseHandle: Sendable, Equatable, Hashable {
    public let id: UUID
}
```

**fileName の検証（M-9）**

- 空文字 → `invalidFileName`
- `/` を含む → `invalidFileName`
- `.` / `..` → `invalidFileName`
- 255 バイト超 → `invalidFileName`

**fileTypeIdentifier の検証**: `UTType` に解決でき、`public.data` または `public.directory` に conform すること。満たさなければ `filePromiseTypeInvalid`。

**ライフサイクル（M-4 / R2-H4 / R2-M5）**

`ClipboardSystemCoordinator` が状態機械を持つ。**変更監視には依存しない**（独立した 5 秒間隔の内部 tick、または明示 release で駆動）。

企画書 RK-21 のとおり **1 つの provider に書き出し要求が複数回来うる**。したがって状態は真偽値ではなく **in-flight 件数**で持つ（R2-H4）。

```swift
// coordinator 内部。NSLock で保護し、nonisolated delegate からも更新できる。
struct FilePromiseState {
    var inFlightCount: Int = 0        // 進行中の writePromiseTo 件数
    var releaseRequested: Bool = false // 明示 release または stale 検出
    var isReleased: Bool = false
    var canRelease: Bool { releaseRequested && inFlightCount == 0 && !isReleased }
}
```

**遷移規則**

| 事象 | 更新 | 解放判定 |
|---|---|---|
| `writePromiseTo` 開始 | `inFlightCount += 1`（**クロージャ実行前に原子的に**） | しない |
| `completionHandler` 呼び出し | `inFlightCount -= 1` | `canRelease` なら解放 |
| `releaseFilePromise(handle:)` | `releaseRequested = true` | `canRelease` なら解放 |
| stale 検出（`changeCount` 不一致） | `releaseRequested = true` | `canRelease` なら解放 |

- 「1 件目の完了で解放され 2 件目が失敗する」ことが構造的に起きない
- **`operationQueue(for:)` が返すキューは `maxConcurrentOperationCount = 1` の serial キュー**とする。同一 provider の書き出しを直列化し、`request.write` の再入を防ぐ
- 状態更新は `NSLock`。nonisolated な delegate から更新し、解放の実行（coordinator の辞書からの除去）は `Task { @MainActor in ... }` で MainActor へ渡す
- `releaseFilePromise(handle:)` は **完全冪等・非 throwing**（R2-M5）。**未知ハンドルも解放済みハンドルも no-op 成功**として扱う。`promiseHandleNotFound` は定義しない（解放済み ID の保持期間という問題自体をなくす）

**登録と書き込みの transaction（R2-M12）**

`ProvideFilePromiseUseCase` は次の順序で行い、失敗時に登録を必ず巻き戻す。

```
1. registry.registerFilePromise(request) -> handle
2. do { try repository.writeFilePromise(handle:scope:) }
   catch { registry.releaseFilePromise(handle); throw }   // rollback
3. return handle
```

遅延提供（§7.4）も同じ形（`registerLazyProvider` → `writePromised` → catch で `releaseLazyProvider`）。`writeObjects` が `false` を返した場合も throw 経路に入るため巻き戻る。leak テストを §12.1 に置く。

**`FilePromiseDelegate`（nonisolated）**

- `fileNameForType` → 検証済み `fileName`
- `writePromiseTo` → `request.write(url)` を実行し、**書き出し要求ごとにちょうど 1 回** `completionHandler` を呼ぶ。**provider 全体で 1 回に絞るガードは置かない**（企画書 RK-21）
- 失敗は `filePromiseWriteFailed` に変換して completion に渡す
- `operationQueue(for:)` → coordinator が持つ専用キュー

#### 受領側（H-3 / 新規設計判断）

**v1 の誤り**: `fileTypes.count` 回の reader 到達を待つ設計だったが、`NSFilePromiseReceiver.h` は次のとおり明記している。

> Note: The count of fileTypes should tell you the number of promised files, **however, that is not guaranteed**. Historically, some legacy file promisers only list each unique fileType once and write one or more files per type.

**v2 の終了モデル**: 総数による集約を廃止し、**ファイル単位イベント + 二重タイムアウト**で終端を決める。

```swift
public enum FilePromiseReceiptEvent: Sendable {
    case received(URL)
    case failed(ClipboardError)
    case finished(FilePromiseReceipt)      // 終端。ちょうど 1 回
}
public struct FilePromiseReceipt: Sendable, Equatable {
    public let urls: [URL]
    public let failures: [ClipboardError]
    public let terminatedBy: Termination
    public enum Termination: Sendable, Equatable {
        case quiescence      // 最後の到達から quietInterval 経過
        case overallTimeout  // 全体 timeout に到達
        case cancelled       // 呼び出し側が cancel
    }
}
public struct FilePromiseReceiptPolicy: Sendable, Equatable {
    /// 最後の reader 到達からこの時間だけ新着がなければ終端とみなす。既定 2 秒。
    public let quietInterval: TimeInterval
    /// 1 件も来なくてもこの時間で必ず終端する。既定 60 秒。
    public let overallTimeout: TimeInterval
    public static let `default` = FilePromiseReceiptPolicy(quietInterval: 2, overallTimeout: 60)
}
```

- reader が呼ばれるたび `received` / `failed` を発行し、静穏タイマを再起動する
- `quietInterval` 経過、または `overallTimeout` 到達、または `cancel()` で `finished` を **exactly-once** で発行する
- 終端後に遅れて到達した reader コールバックは**破棄**する（late callback 抑止。世代トークンで判定）
- `fileTypes.count` は**参考値としてログにのみ出す**。終了判定には使わない

**この終了モデルはヒューリスティックである。** SDK が総数を保証しない以上、保証可能な終端は存在しない。DocC に「`finished` の到達は静穏タイムアウトに基づく推定であり、極端に遅い provider では `overallTimeout` まで待つ」と明記する。既定値の妥当性は要検証（DV-05）。

#### 7.12.3 OP-18 の終端 truth table（R2-M6）

`overallTimeout` と cancel は**正常終端**であり throw しない。partial receipt を失わないため、**集約 async 版も throw ではなく `FilePromiseReceipt` を返す**。throw するのは開始前の失敗のみ。

| 経路 | callback 版 (`onEvent`) | stream 版 | 集約 async 版 | Bridge |
|---|---|---|---|---|
| 開始失敗（destination 不正、scope 解決失敗） | **`onEvent` は呼ばれない**。開始 API が throw | 開始 API が throw（stream を作らない） | throw | 開始 ack callback で `isSuccess=NO` + errorCode |
| per-file 失敗 | `.failed(error)` | `.failed(error)` を yield | `receipt.failures` に積む | event callback で `isFinished=NO`、`eventJson.kind = "failed"` |
| ファイル受領 | `.received(url)` | `.received(url)` を yield | `receipt.urls` に積む | 同上 `kind = "received"` |
| quiescence 終端 | `.finished(receipt)`、`terminatedBy = .quiescence` | `.finished` を yield 後 `finish()` | `receipt` を返す | `isFinished=YES`、`errorCode=0` |
| `overallTimeout` 終端 | `.finished(receipt)`、`terminatedBy = .overallTimeout` | 同上（**throw しない**） | `receipt` を返す（**throw しない**） | `isFinished=YES`、`errorCode=0`、`eventJson.terminatedBy="overallTimeout"` |
| 明示 cancel（OP-20） | `.finished(receipt)`、`terminatedBy = .cancelled` | 同上 | `receipt` を返す | 同上 `terminatedBy="cancelled"` |
| Task キャンセル（stream / 集約 async） | 該当なし | `onTermination` から OP-20 を呼び、`.finished` を yield 後 `finish()` | 同上を待って `receipt` を返す | 該当なし |

- `filePromiseTimedOut` / `cancelled` は **OP-18 の終端では使わない**。`filePromiseTimedOut` は削除し、`cancelled` は検出 API（OP-09〜OP-11）専用とする
- `finished` は経路によらず **exactly-once**。終端後の reader コールバックは世代トークンで破棄する

#### 7.12.4 キャンセル（OP-20 / R2-H2）

```swift
public func cancelReceiveFilePromises(_ handle: FilePromiseReceiptHandle)
```

- 同期・**完全冪等**・非 throwing。未知 / 終端済みハンドルは no-op
- 内部で `registry.cancelReceipt(handle)` を呼ぶ
- `AsyncThrowingStream` は `onTermination` で必ずこれを呼ぶ。Task キャンセルもここに合流する
- Bridge は `clipboardCancelReceiveFilePromises(handleJson, callback)` として公開する（§8.4）

**destination policy（M-9）**

- `destinationDirectory` は呼び出し側が指定する。存在しない、またはディレクトリでない、または書き込み不可なら `destinationNotWritable`
- 同名衝突はシステムに委ねる（`receivePromisedFiles` の仕様）。結果 URL をそのまま返す

---

## 8. API 設計

### 8.1 公開 API（`MacClipboardManager`、`@MainActor`）

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
| OP-12 | accessBehavior | なし | `accessBehavior(scope:) throws -> ClipboardAccessBehavior` |
| OP-13 | startObserving | なし | `startObserving(scope:interval:onEvent:) throws` |
| OP-14 | stopObserving | なし | `stopObserving()` |
| OP-15 | checkForegroundChange | なし | `checkForegroundChange(scope:) throws -> Bool` |
| OP-16 | provideFilePromise | なし | `provideFilePromise(_:scope:) throws -> FilePromiseHandle` |
| OP-17 | releaseFilePromise | なし | `releaseFilePromise(_:) ` （冪等） |
| OP-18 | receiveFilePromises | `receiveFilePromises(destinationDirectory:scope:policy:onEvent:) throws -> FilePromiseReceiptHandle` | **`receiveFilePromiseEvents(...) -> AsyncThrowingStream<FilePromiseReceiptEvent, Error>`** と **`receiveFilePromises(...) async throws -> FilePromiseReceipt`**（H-4） |
| OP-19 | makePasteButton | なし | `makePasteButton(acceptedTypes:timeout:onPaste:) throws -> NSView` |
| **OP-20** | **cancelReceiveFilePromises** | なし | **`cancelReceiveFilePromises(_:)`（同期・冪等・非 throwing）** |

**native 版の実行方式（R2-H1）**

- **OP-01〜OP-11 は `async throws` + `@discardableResult`**。mac.md「Manager の公開 API（ネイティブ版）は上記のとおり必ず `async throws` にする」に従う。**Repository / UseCase は同期のまま**で、Manager だけが薄い `async` ラッパーになる（common.md「Manager の公開規約を理由に、下位層まで不必要に非同期化してはならない」）
- **OP-12〜OP-15 / OP-17 / OP-20 は同期**。真偽値の即時判定・監視の開始停止・ハンドル解放・キャンセルであり、common.md の「即時完了する control 操作」例外に該当する
- **OP-16 / OP-19 は同期**。同 例外の「factory 操作」に該当する
- OP-18 は開始が factory 的だが結果が後着するため、callback 版・stream 版・集約 async 版の 3 形態を持つ

**callback 版の完了アクター**: すべて MainActor。

**OP-20（新設・R2-H2）**: `cancelReceiveFilePromises(_ handle: FilePromiseReceiptHandle)`。同期・**完全冪等**・非 throwing。未知ハンドルと解放済みハンドルはいずれも no-op 成功。

### 8.2 内部 API（Port）— Domain 型のみ（H-1）

```swift
@MainActor
public protocol ClipboardRepository {
    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope
    func removePasteboard(_ scope: PasteboardScope) throws
    func write(_ content: ClipboardContent, options: ClipboardCopyOptions,
               scope: PasteboardScope) throws -> PasteboardOwnership
    func writePromised(handle: PasteboardPromiseHandle, types: [String],
                       options: ClipboardCopyOptions,
                       scope: PasteboardScope) throws -> PasteboardOwnership
    func append(_ content: ClipboardContent,
                ownership: PasteboardOwnership) throws -> PasteboardOwnership
    func read(scope: PasteboardScope) throws -> ClipboardReadResult
    func readData(utType: String, scope: PasteboardScope) throws -> Data?
    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot
    func clear(scope: PasteboardScope) throws -> Int
    func changeCount(scope: PasteboardScope) throws -> Int
    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                        scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern>
    func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                      scope: PasteboardScope) async throws -> ClipboardDetectedValues
    func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata
    func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior
    func writeFilePromise(handle: FilePromiseHandle,
                          scope: PasteboardScope) throws -> PasteboardOwnership
    func startReceivingFilePromises(handle: FilePromiseReceiptHandle,
                                    destinationDirectory: URL,
                                    scope: PasteboardScope) throws
}
```

**Port の戻り値・引数はすべて Domain 値型**（`UUID` ベースのハンドル、`URL` / `Data` / `Date` は common.md が許容する `Foundation` 値型）。Presentation 型・AppKit 型は現れない。

### 8.3 Application Port（coordinator が実装、H-5）

```swift
@MainActor
public protocol ClipboardPromiseRegistry {
    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle
    func releaseLazyProvider(_ handle: PasteboardPromiseHandle)
    func registerFilePromise(_ request: FilePromiseRequest) throws -> FilePromiseHandle
    func releaseFilePromise(_ handle: FilePromiseHandle)
    func registerReceipt(policy: FilePromiseReceiptPolicy,
                         onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void) -> FilePromiseReceiptHandle
    func cancelReceipt(_ handle: FilePromiseReceiptHandle)
}
```

### 8.4 Unity Bridge 契約（H-2 / R2-H3）

#### 8.4.1 共通規約

| 項目 | 契約 |
|---|---|
| 呼び出しスレッド | **任意スレッドから呼び出し可**（既存 `UnityMacShareManager` と同じ） |
| callback スレッド | **常にメインスレッド** |
| **operation callback の回数** | **各呼び出しにつき exactly-once**。JSON パース失敗など早期リターン経路でも必ず 1 回呼ぶ |
| **event callback の回数** | **購読中に 0 回以上（N 回）**。`clipboardStartObserving` の変更通知と `clipboardReceiveFilePromises` の受領通知が該当する。exactly-once 規約は適用しない（R2-H3） |
| **terminal event の回数** | 受領通知の `isFinished == YES` は **exactly-once** |
| callback が NULL | 呼び出しは実行するが結果を通知しない。**エラーにしない**（R2-M14。既存 `BridgeError.contractViolation` の DocC はこの方針に合わせて修正する。§5.2） |
| 必須引数が NULL | `BridgeError.contractViolation`（1302）を operation callback で返す |
| JSON パース失敗 | `BridgeError.parseFailed`（1301）を operation callback で返す |
| C 文字列の寿命 | **callback の実行中のみ有効**。呼び出し側は即座にマネージド文字列へコピーすること。callback から戻った後にポインタを保持してはならない |
| 文字列エンコード | UTF-8 |
| 成功時 | `isSuccess = YES`、`errorCode = 0`、`errorMessage = NULL` |
| 失敗時 | `isSuccess = NO`、`errorCode` は `BridgeError` または `ClipboardError` の値、`errorMessage` は英語メッセージ |
| 数値 | `changeCount` は 64bit 整数（JSON number）。バイト列は **Base64 文字列** |

#### 8.4.2 callback typedef

```c
/// Operation callback. 値を返さない操作。呼び出しにつき exactly-once。
typedef void (*ClipboardCallback)(BOOL isSuccess,
                                  NSInteger errorCode,
                                  const char* _Nullable errorMessage);

/// Operation callback. JSON を返す操作。呼び出しにつき exactly-once。
/// json は isSuccess=YES のときのみ非 NULL。
typedef void (*ClipboardJsonCallback)(BOOL isSuccess,
                                      const char* _Nullable json,
                                      NSInteger errorCode,
                                      const char* _Nullable errorMessage);

/// Event callback. 変更監視。購読中に N 回呼ばれる。terminal はない。
typedef void (*ClipboardChangeCallback)(const char* eventJson);

/// Event callback. File Promise 受領。
/// isFinished=NO の中間イベントが N 回、isFinished=YES の terminal が exactly-once。
typedef void (*ClipboardReceiptCallback)(BOOL isFinished,
                                         const char* eventJson);
```

#### 8.4.3 完全な C prototype（19 endpoint）

```c
// --- C: copy / append ---------------------------------------------------
void clipboardCopy(const char* contentJson,
                   const char* optionsJson,
                   const char* scopeJson,
                   ClipboardJsonCallback callback);           // -> OwnershipJson

void clipboardAppend(const char* contentJson,
                     const char* ownershipJson,
                     ClipboardJsonCallback callback);         // -> OwnershipJson

// --- R / Q --------------------------------------------------------------
void clipboardRead(const char* scopeJson,
                   ClipboardJsonCallback callback);           // -> ReadResultJson

void clipboardReadData(const char* utType,
                       const char* scopeJson,
                       ClipboardJsonCallback callback);       // -> ReadDataJson

void clipboardSnapshot(const char* _Nullable matchingTypesJson,
                       const char* scopeJson,
                       ClipboardJsonCallback callback);       // -> SnapshotJson

// --- X / P --------------------------------------------------------------
void clipboardClear(const char* scopeJson,
                    ClipboardJsonCallback callback);          // -> ChangeCountJson

void clipboardCreatePasteboard(const char* requestJson,
                               ClipboardJsonCallback callback); // -> ScopeJson

void clipboardRemovePasteboard(const char* scopeJson,
                               ClipboardCallback callback);

// --- D ------------------------------------------------------------------
void clipboardDetectPatterns(const char* patternsJson,
                             const char* scopeJson,
                             ClipboardJsonCallback callback);  // -> PatternsJson

void clipboardDetectValues(const char* patternsJson,
                           const char* scopeJson,
                           ClipboardJsonCallback callback);    // -> DetectedValuesJson

void clipboardDetectMetadata(const char* scopeJson,
                             ClipboardJsonCallback callback);  // -> DetectedMetadataJson

void clipboardAccessBehavior(const char* scopeJson,
                             ClipboardJsonCallback callback);  // -> AccessBehaviorJson

// --- M ------------------------------------------------------------------
/// callback は購読開始の ack（exactly-once）。onChange は購読中 N 回。
void clipboardStartObserving(const char* scopeJson,
                             double intervalSeconds,
                             ClipboardCallback callback,
                             ClipboardChangeCallback onChange);

void clipboardStopObserving(ClipboardCallback callback);

void clipboardCheckForegroundChange(const char* scopeJson,
                                    ClipboardJsonCallback callback); // -> BoolJson

// --- F ------------------------------------------------------------------
void clipboardProvideFilePromise(const char* requestJson,
                                 ClipboardJsonCallback callback);  // -> HandleJson

/// 完全冪等。未知 / 解放済みハンドルでも isSuccess=YES。
void clipboardReleaseFilePromise(const char* handleJson,
                                 ClipboardCallback callback);

/// callback は開始 ack（exactly-once）で receipt handle を返す。
/// onEvent は中間 N 回 + terminal 1 回。
void clipboardReceiveFilePromises(const char* destinationPath,
                                  const char* scopeJson,
                                  const char* _Nullable policyJson,
                                  ClipboardJsonCallback callback,   // -> HandleJson
                                  ClipboardReceiptCallback onEvent);

/// 完全冪等。未知 / 終端済みハンドルでも isSuccess=YES。
void clipboardCancelReceiveFilePromises(const char* handleJson,
                                        ClipboardCallback callback);
```

**OP-19（makePasteButton）は `NSView` を返すため Bridge に公開しない。**

#### 8.4.4 JSON schema（全型）

`required` を明示し、それ以外は optional。`null` を許すフィールドは型に `|null` を付ける。

```jsonc
// ---- 入力 ----

// ScopeJson  (required: kind)  kind = "general" | "named" | "unique"
// name は kind が named / unique のとき required
{ "kind": "general" }
{ "kind": "named",  "name": "com.example.private" }

// ContentJson  (required: items)
// representations: UTI -> Base64 文字列。1 件以上必須
{ "items": [ { "representations": { "public.utf8-plain-text": "aGVsbG8=" } } ] }

// OptionsJson  (すべて optional。省略時は既定値)
{ "localOnly": true }

// OwnershipJson  (required: scope, changeCount)
{ "scope": { "kind": "general" }, "changeCount": 12 }

// CreateRequestJson  (required: kind)  kind = "named" | "unique"
{ "kind": "named", "name": "com.example.private" }
{ "kind": "unique" }

// MatchingTypesJson  (null 可 = フィルタなし。空配列は 1512 エラー)
["public.utf8-plain-text", "public.png"]

// PatternsJson  (required。空配列は 1503 エラー)
["probableWebURL", "emailAddresses"]

// FilePromiseRequestJson  (required: fileTypeIdentifier, fileName, sourcePath)
// sourcePath の扱いは §8.4.5
{ "fileTypeIdentifier": "public.plain-text",
  "fileName": "export.txt",
  "sourcePath": "/Users/me/Documents/export.txt" }

// PolicyJson  (すべて optional)
{ "quietIntervalSeconds": 2.0, "overallTimeoutSeconds": 60.0 }

// HandleJson  (required: id)
{ "id": "9F1E4C0A-....-....-....-............" }

// ---- 出力 ----

// ReadResultJson
{ "changeCount": 12,
  "items": [ { "representations": { "public.utf8-plain-text": "aGVsbG8=" } } ] }

// ReadDataJson  (data は null 可 = 該当型なし。エラーではない)
{ "data": "aGVsbG8=" }
{ "data": null }

// SnapshotJson
{ "changeCount": 12,
  "itemTypes": [ ["public.utf8-plain-text", "NSStringPboardType"] ],
  "matchingItemIndexes": [0] }

// ChangeCountJson
{ "changeCount": 13 }

// BoolJson
{ "value": true }

// PatternsJson（出力も同じ形）
["probableWebURL"]

// DetectedValuesJson  (欠落フィールドは null または空配列)
{ "patterns": ["probableWebURL", "emailAddresses"],
  "probableWebURL": "https://example.com",
  "probableWebSearch": null,
  "number": null,
  "links": [ { "matchedString": "https://example.com", "url": "https://example.com" } ],
  "phoneNumbers": [ { "matchedString": "+81 3-1234-5678",
                      "phoneNumber": "+81312345678", "label": null } ],
  "emailAddresses": [ { "matchedString": "a@example.com",
                        "emailAddress": "a@example.com", "label": "Work" } ],
  "postalAddresses": [ { "matchedString": "...", "street": null, "city": "Tokyo",
                         "state": null, "postalCode": null, "country": "JP" } ],
  "calendarEvents": [ { "matchedString": "...", "isAllDay": false,
                        "startDate": "2026-08-29T10:00:00Z", "startTimeZoneIdentifier": "Asia/Tokyo",
                        "endDate": null, "endTimeZoneIdentifier": null } ],
  "shipmentTrackingNumbers": [ { "matchedString": "...", "carrier": "UPS",
                                 "trackingNumber": "1Z..." } ],
  "flightNumbers": [ { "matchedString": "NH106", "airline": "NH", "flightNumber": "106" } ],
  "moneyAmounts": [ { "matchedString": "$12.34", "currencyCode": "USD", "amount": 12.34 } ] }

// DetectedMetadataJson
{ "metadataTypes": ["contentType"], "contentTypeIdentifier": "public.png" }

// AccessBehaviorJson
// value = "default" | "ask" | "alwaysAllow" | "alwaysDeny" | "unavailable"
{ "value": "alwaysAllow" }

// ---- イベント ----

// ChangeEventJson（clipboardStartObserving の onChange）
{ "scope": { "kind": "general" }, "changeCount": 14 }

// ReceiptEventJson（clipboardReceiveFilePromises の onEvent）
// kind = "received" | "failed" | "finished"
{ "kind": "received", "url": "file:///Users/me/Downloads/a.txt" }
{ "kind": "failed",   "errorCode": 1519, "errorMessage": "Failed to receive a promised file: ..." }
// terminal（isFinished = YES）。terminatedBy = "quiescence" | "overallTimeout" | "cancelled"
{ "kind": "finished",
  "terminatedBy": "quiescence",
  "urls": ["file:///Users/me/Downloads/a.txt"],
  "failures": [ { "errorCode": 1519, "errorMessage": "..." } ] }
```

**日付フォーマット**: ISO 8601（UTC、`yyyy-MM-dd'T'HH:mm:ss'Z'`）。locale 非依存。

#### 8.4.5 OP-16 の `sourcePath` 契約（R2-M11）

Bridge は C ABI にクロージャを載せられないため、`FilePromiseRequestJson.sourcePath` から `write` クロージャを合成する。ただし**履行は登録より後**に起きるため、登録時点でのソースの状態を保証する必要がある。

**方針: 登録時に app-owned staging へスナップショットする。**

1. `clipboardProvideFilePromise` の受理時、`sourcePath` を **アプリ専用の staging ディレクトリへコピー**する（`FileManager.default.temporaryDirectory/ClipboardPromise/<handleId>/`）
2. 合成される `write` クロージャは staging 上のコピーを書き出す。**登録後に元ファイルが削除・変更されても履行は成功する**
3. `fileTypeIdentifier` が `public.directory` に conform する場合はディレクトリごと再帰コピーする
4. コピー失敗（存在しない、権限なし、容量不足）は**登録を失敗させる**（`filePromiseWriteFailed` を開始 callback で返す）。登録は行わない
5. **staging は handle 解放時に削除する**。`releaseFilePromise` / stale 解放 / アプリ終了時のクリーンアップ（起動時に `ClipboardPromise/` の残骸を削除）
6. **App Sandbox（RK-12）**: `sourcePath` がサンドボックス外の場合、コピー自体が失敗する。ユーザーが選択したファイルは security-scoped bookmark が必要になるが、**v1 では対応しない**。DocC と Bridge ヘッダに「`sourcePath` はアプリがアクセス権を持つパスであること」と明記する
7. **ログ禁止**: `sourcePath` の完全パスは `Log.d` に出さない（§4.2 の秘匿方針。ファイル名のみ、または長さのみ）

ネイティブ版（`FilePromiseRequest.write` クロージャ）はスナップショットを行わない。呼び出し側がクロージャ内で自由に生成できるため。**この差分を DocC に明記する。**

## 9. 同期・非同期レイヤー対応表（全公開操作）

列: 操作 / System API と実行方式 / Repository / UseCase / Manager callback / Manager native / Bridge / actor・thread / キャンセル・所有権 / **timeout** / **exactly-once** / **late result** / 変換理由

| ID | System API | Repository | UseCase | Mgr callback | Mgr native | Bridge | actor | キャンセル・所有権 | timeout | exactly-once | late result | 変換理由 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OP-01 | C-02 + C-03（同期） | 同期 throws | 同期 throws | `Task{@MainActor}` | **async throws** | callback | MainActor | なし / `PasteboardOwnership` を返す | なし | callback 1 回 | 該当なし | Bridge は C ABI と actor 隔離のため callback（§6.6） |
| OP-02 | C-03（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | なし / 所有権照合 | なし | callback 1 回 | 該当なし | 同上 |
| OP-03 | R-07 + R-09（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | なし / 値型返却 | なし | callback 1 回 | 該当なし | 同上 |
| OP-04 | R-05（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | なし | なし | callback 1 回 | 該当なし | 同上 |
| OP-05 | Q-01 / Q-05（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | なし | なし | callback 1 回 | 該当なし | 同上 |
| OP-06 | C-01（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | なし | なし | callback 1 回 | 該当なし | 同上 |
| OP-07 | P-02 / P-03（同期） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | 一意名は release 必須 | なし | callback 1 回 | 該当なし | 同上 |
| OP-08 | P-04（同期 oneway） | 同期 throws | 同期 throws | 同上 | **async throws** | callback | MainActor | 標準名は拒否 | なし | callback 1 回 | 該当なし | 同上 |
| OP-09 | D-01（async throws） | async throws | async throws | `Task{@MainActor}` | async throws | callback | MainActor | Task キャンセル → `cancelled`（要検証 V-5） | なし（システム依存） | callback 1 回 | Task 破棄で無視 | システム API が async |
| OP-10 | D-02（async throws） | async throws | async throws | 同上 | async throws | callback | MainActor | 同上 / ユーザー拒否で throw | 同上 | callback 1 回 | 同上 | 同上 |
| OP-11 | D-03（async throws） | async throws | async throws | 同上 | async throws | callback | MainActor | 同上 | 同上 | callback 1 回 | 同上 | 同上 |
| OP-12 | D-07（同期プロパティ） | 同期 throws | 同期 throws | なし | 同期 throws | callback | MainActor | なし | なし | callback 1 回 | 該当なし | ネイティブは即時 control（common.md 例外）。Bridge のみ callback（§6.6） |
| OP-13 | M-01 + Timer | 同期 | 同期 | なし | 同期 throws | callback + event callback | MainActor | `stopObserving` / 世代トークン | なし | **開始 callback 1 回。event は購読中 N 回** | 旧世代の tick は破棄 | 開始・停止は同期 control、配信のみ非同期（common.md） |
| OP-14 | 同上 | - | - | なし | 同期 | callback | MainActor | Timer invalidate | なし | callback 1 回 | 旧世代破棄 | 同上 |
| OP-15 | M-01（同期） | 同期 throws | 同期 throws | なし | 同期 throws | callback | MainActor | なし | なし | callback 1 回 | 該当なし | 即時判定（common.md 例外） |
| OP-16 | F-01 + C-03（同期） | 同期 throws | 同期 throws | なし | 同期 throws | callback | MainActor（登録）/ nonisolated（書き出し） | **coordinator が provider+delegate を強参照。stale / 明示 release で解放** | なし | 登録 callback 1 回。**writePromiseTo は要求ごとに completion 1 回** | 該当なし | factory 操作（common.md 例外） |
| OP-17 | - | - | 同期 | なし | 同期（冪等） | callback | MainActor | ハンドル解放。`fulfilling` 中は `pendingRelease` | なし | callback 1 回 | 該当なし | 即時 control |
| OP-18 | F-10（callback、回数不定） | callback | callback | `onEvent`（複数回） | **`AsyncThrowingStream` / `async throws`（H-4）** | `ClipboardReceiptCallback` | reader は任意 queue → MainActor へ転送 | `cancelReceipt` / Task キャンセル。**総数を使わない終了モデル（§7.12）** | **quietInterval 2s + overallTimeout 60s** | **`finished` は exactly-once** | **終端後の reader は破棄（世代トークン）** | システム API に async 版がないため下位は callback。Manager で continuation / stream 化（common.md の併設要求） |
| OP-19 | U-02（callback）+ `NSItemProvider` load（async） | - | - | なし | 同期 throws（factory）。`onPaste` は非同期後に 1 回 | 非公開 | MainActor | **container View の `deinit` → `cancelPaste`（冪等）** | **既定 15 秒** | **`onPaste` は exactly-once** | timeout 後の完了は破棄 | factory は同期。payload 変換のみ非同期（§7.11） |
| **OP-20** | **なし（内部 control）** | - | 同期 | なし | **同期・冪等・非 throwing** | callback | MainActor | **未知 / 終端済みは no-op** | なし | callback 1 回 | 該当なし | 即時 control（common.md 例外）。stream の `onTermination` と Task キャンセルもここへ合流（R2-H2） |

### 9.1 企画書の分類表との差分（新規設計判断）

| 差分 | 内容 | 理由 |
|---|---|---|
| L 群を公開しない | 内部の大容量最適化に限定 | Domain に非 Sendable な閉包を持ち込まないため |
| Q 群を `snapshot` に集約 | 単独公開しない | 公開粒度を iOS 版に合わせる。かつ RK-01 により「通知なし判定」として売らない |
| R-04 を使わない | `pasteboardItems` 経路のみ | RK-15（改行連結）回避 |
| 15.0–15.3 に Q 群フォールバックを置かない | 15.4 未満は throw | RK-01。V-1 判定保留のため |
| **OP-18 の終了判定を総数から静穏タイムアウトへ変更** | `fileTypes.count` を終了条件に使わない | **SDK が総数を保証しないため（H-3）** |
| **OP-18 の overallTimeout / cancel を正常終端にする** | throw せず partial receipt を返す | 受領済みファイルを失わないため（R2-M6） |
| **OP-01〜OP-11 の native を `async throws` に統一** | 下位層は同期のまま | **mac.md「必ず `async throws` にする」（R2-H1）** |
| **OP-18 に native async を追加** | 下位は callback、Manager で stream / continuation | common.md の callback + native async 併設要求（H-4） |
| **Bridge の control 操作を callback 化** | ネイティブは同期、Bridge は callback | `@MainActor` と任意スレッド同期 C 関数が両立しないため（H-7） |

---

## 10. ドメインエラー一覧（全ケース）

Bridge 境界の失敗（JSON パース、必須引数 NULL）は **`BridgeError`（1301 / 1302）** を使い、`ClipboardError` には含めない（H-2）。

**v2 から削除**: `promiseHandleNotFound`（ハンドル基準の control を完全冪等にしたため。R2-M5）、`filePromiseTimedOut`（`overallTimeout` を正常終端としたため。R2-M6）。
**v3 で追加**: `invalidConfiguration`（R2-M9）。

| # | ケース | 発生条件 | 発生層 |
|---|---|---|---|
| 1 | `emptyContent` | `items` が空 | Application |
| 2 | `emptyRepresentations(itemIndex: Int)` | アイテムの表現が空 | Application |
| 3 | `emptyDetectionPatterns` | 検出パターンが空集合 | Application |
| 4 | `invalidTypeIdentifier(String)` | UTI として不正 | Application / Data |
| 5 | `invalidPasteboardName(String)` | 空文字などの不正名 | Data |
| 6 | `contentTooLarge(bytes: Int, limit: Int)` | hard limit 超過（§6.7） | Application |
| 7 | `pasteboardUnavailable(name: String)` | `pasteboardItems` が nil 等 | Data |
| 8 | `cannotReleaseStandardPasteboard(name: String)` | 標準名に release | Data |
| 9 | `writeRejected` | copy 経路で `writeObjects` が false | Data |
| 10 | `appendRejected` | append 経路で `writeObjects` が false | Data |
| 11 | `ownershipLost(expected: Int, actual: Int)` | append 時に changeCount 不一致 | Data |
| 12 | `emptyTypeFilter` | `snapshot(matchingTypes: [])` | Application |
| 13 | `detectionUnavailable(minimumOS: String)` | 15.4 未満で検出 API | Data |
| 14 | `detectionDenied` | `detectValues` でユーザー拒否 | Data |
| 15 | `detectionFailed(String)` | 検出 API のその他失敗 | Data |
| 16 | `filePromiseTypeInvalid(String)` | data / directory に非適合 | Application |
| 17 | `invalidFileName(String)` | 空 / `/` / `.` / `..` / 255 バイト超 | Application |
| 18 | `filePromiseWriteFailed(String)` | 書き出しクロージャが throw、または staging コピー失敗（§8.4.5） | Data / Manager |
| 19 | `filePromiseReceiveFailed(String)` | reader が error を返した（per-file） | Data |
| 20 | `destinationNotWritable(String)` | 受領先が存在しない / ディレクトリでない / 書き込み不可 | Application |
| 21 | `pasteLoadFailed(String)` | `NSItemProvider` のロード失敗（per-provider） | Presentation |
| 22 | `pasteLoadTimedOut(seconds: Int)` | PasteButton のロード timeout | Presentation |
| 23 | `invalidConfiguration(String)` | interval / timeout / limits が §6.8 の制約に違反 | Application |
| 24 | `cancelled` | 検出 API（OP-09〜OP-11）の Task キャンセル | Data |
| 25 | `unknown(String)` | 上記以外 | 全層 |

**OP-18 の終端理由（`overallTimeout` / `cancelled`）はエラーではない。** `FilePromiseReceipt.terminatedBy` で表す（§7.12.3）。

---

## 11. エラーコード / メッセージ対応表

Bridge 返却形式は `(isSuccess: BOOL, errorCode: NSInteger, errorMessage: NSString*)`。成功時は `errorCode == 0`、`errorMessage == NULL`。

| コード | ケース | errorMessage（英語） |
|---|---|---|
| 1301 | `BridgeError.parseFailed` | `Failed to parse JSON: {reason}` |
| 1302 | `BridgeError.contractViolation` | `Bridge contract violation: {reason}` |
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
| 1512 | `emptyTypeFilter` | `The type filter must not be empty. Pass null to disable filtering.` |
| 1513 | `detectionUnavailable` | `Pasteboard detection requires macOS {minimumOS} or later.` |
| 1514 | `detectionDenied` | `The user denied access to the pasteboard contents.` |
| 1515 | `detectionFailed` | `Pasteboard detection failed: {reason}.` |
| 1516 | `filePromiseTypeInvalid` | `File promise type must conform to public.data or public.directory: {value}.` |
| 1517 | `invalidFileName` | `Invalid promised file name: {value}.` |
| 1518 | `filePromiseWriteFailed` | `Failed to write the promised file: {reason}.` |
| 1519 | `filePromiseReceiveFailed` | `Failed to receive a promised file: {reason}.` |
| 1520 | `destinationNotWritable` | `The destination directory is not writable: {path}.` |
| 1521 | `pasteLoadFailed` | `Failed to load pasted item: {reason}.` |
| 1522 | `pasteLoadTimedOut` | `Loading pasted items timed out after {seconds} seconds.` |
| 1523 | `invalidConfiguration` | `Invalid configuration: {reason}.` |
| 1524 | `cancelled` | `The clipboard operation was cancelled.` |
| 1599 | `unknown` | `An unknown clipboard error occurred: {reason}.` |

---

## 12. テスト設計

### 12.1 単体テスト（Swift Testing）

Mock は `shouldFail` / `xxxCallCount` / `stubbedXxx` の 3 点セット。

| 対象 | 正常系 | 異常系 | 境界値 |
|---|---|---|---|
| `ClipboardContentValidator` | 有効 content を通す | `emptyContent` / `emptyRepresentations` / `invalidTypeIdentifier` / `contentTooLarge` | warn ちょうど / hard ちょうど / hard+1 / 合計上限 |
| `CopyContentUseCase` | ownership を返す | Repository の throw を素通し | 1 件 / 多数 |
| `AppendContentUseCase` | 所有権一致で成功 | `ownershipLost` / `appendRejected` | changeCount 一致 / +1 |
| `ReadContentUseCase` | items を返す | `pasteboardUnavailable` | 0 件 / 複数件 |
| `ReadDataUseCase` | Data を返す | - | **該当なしで `nil`（エラーにしない）**（M-1） |
| `GetSnapshotUseCase` | 型一覧と matchingItemIndexes | `emptyTypeFilter` | nil フィルタ / conformance 一致 / 不一致 |
| `ClearClipboardUseCase` | changeCount を返す | - | - |
| `CreatePasteboardUseCase` | named / unique | `invalidPasteboardName` | 空文字 |
| `RemovePasteboardUseCase` | 一意名を解放 | **標準名 5 種すべてで `cannotReleaseStandardPasteboard`** | - |
| `DetectPatternsUseCase` 他 3 種 | 値を返す | `emptyDetectionPatterns` / `detectionUnavailable` / `detectionDenied` / `cancelled` | 空集合 / 全パターン |
| `GetAccessBehaviorUseCase` | 4 値を返す | 解決不能 scope で throw | **15.4 未満で `.unavailable`**（M-2） |
| `ClipboardChangeTracker` | 変化を検出 | - | 同値 / +1 |
| `CheckForegroundChangeUseCase` | 変化ありで true | - | 初回呼び出し |
| `ProvideFilePromiseUseCase` | handle を返す | `filePromiseTypeInvalid` / `invalidFileName` | 空 / `/` 含み / `..` / 255 バイト / 256 バイト |
| `ReleaseFilePromiseUseCase` | 解放 | **異常系なし（完全冪等・非 throwing）** | **二重 release / 未知ハンドル / 解放済みハンドルがいずれも no-op 成功**（R2-M5） |
| `ReceiveFilePromisesUseCase` | イベントを転送 | `destinationNotWritable` | - |
| `ClipboardDetectionMapper` | **DDMatch* の全フィールドが保たれる**（M-7） | - | 全 nullable フィールドが nil の場合 |
| `ClipboardError` | 全 25 ケースの code / message | - | コード重複なし。`BridgeError` と衝突なし |
| **`ClipboardLimits` / `FilePromiseReceiptPolicy` の init** | 既定値が制約を満たす | **`invalidConfiguration`**（R2-M9） | **0 / 負数 / `warn > hard` / `hard > total` / `quiet >= overall` / interval 61 秒 / timeout 301 秒** |
| **`ProvideFilePromiseUseCase` の rollback** | 成功時は handle を返す | **`writeFilePromise` が throw したとき `releaseFilePromise` が呼ばれる**（R2-M12） | `writeObjects == false` 経路 |
| **遅延提供の rollback** | 同上 | `writePromised` 失敗で `releaseLazyProvider` が呼ばれる | 同上 |
| **`ClipboardDetectionMapper` の `matchedString`** | **全 8 entity で `matchedString` が保たれる**（R2-M8） | - | 全 nullable フィールドが nil |
| **Manager の native シグネチャ検査** | **OP-01〜OP-11 が `async throws` + `@discardableResult`**（R2-H1） | - | OP-12〜OP-17 / OP-20 が同期であること |

### 12.2 統合テスト（実 `NSPasteboard`）

`.unique` scope を使い `general` を汚さない。各テストは `defer` で `releaseGlobally()`。

| ID | 検証内容 | 対応 |
|---|---|---|
| IT-01 | copy → read の往復一致 | OP-01 / OP-03 |
| IT-02 | copy 後の append で items 増加、changeCount 不変 | **RK-23 / V-13b** |
| IT-03 | 他者所有後の append が `ownershipLost` | **RK-23 / V-13a** |
| IT-04 | copy が `clearContents` を経由しない | **RK-05** |
| IT-05 | 同一内容の連続 copy が例外を投げない | **RK-14** |
| IT-06 | `removePasteboard(.general)` が拒否される | **RK-07** |
| IT-07 | 複数アイテム read で件数が保たれる | **RK-15** |
| IT-08 | snapshot の conformance 判定 | M-8 |
| IT-09 | 監視の restart 時、scope 解決失敗で既存監視が止まらない | **M-5** |
| IT-10 | 監視の start → 変更 → イベント 1 回 → stop | RK-11 |
| IT-11 | 旧世代 tick が新購読へ届かない | M-5 |
| IT-12 | File Promise の provider / delegate がスコープ離脱後も生存 | **RK-21 / V-11** |
| IT-13 | `releaseFilePromise` が冪等。二重呼び出しで例外を出さない | M-4 |
| IT-14 | `fulfilling` 中の release が `pendingRelease` になり、履行完了後に解放される | M-4 |
| IT-15 | `receiveFilePromises` が静穏タイムアウトで `finished` を 1 回だけ発行 | **H-3** |
| IT-16 | reader が `fileTypes.count` と異なる回数呼ばれても終端する | **H-3** |
| IT-17 | 終端後の遅延 reader コールバックが破棄される | **H-3 / late result** |
| IT-18 | `overallTimeout` で `finished(terminatedBy: .overallTimeout)` | H-3 |
| IT-19 | `cancelReceipt` で `finished(terminatedBy: .cancelled)` | H-3 |
| IT-20 | 検出 API が 15.4 未満分岐で `detectionUnavailable` | RK-01 |
| **IT-21** | **同一 provider に 2 件の書き出し要求が重なっても、1 件目の完了で解放されない**（`inFlightCount`） | **R2-H4** |
| **IT-22** | **全要求完了後にのみ解放される。`releaseRequested` 中の履行が完走する** | R2-H4 |
| **IT-23** | **`operationQueue(for:)` が serial（`maxConcurrentOperationCount == 1`）である** | R2-H4 |
| **IT-24** | **未知ハンドルの `releaseFilePromise` / `cancelReceiveFilePromises` が成功扱いで no-op** | **R2-M5** |
| **IT-25** | **`cancelReceiveFilePromises` で `finished(terminatedBy: .cancelled)` が 1 回だけ出る** | **R2-H2** |
| **IT-26** | **`overallTimeout` 終端が throw せず partial receipt を返す** | **R2-M6** |
| **IT-27** | **stream の Task キャンセルで `onTermination` から cancel され、`finished` が出る** | R2-H2 / R2-M6 |
| **IT-28** | **`sourcePath` を登録後に削除しても履行が成功する**（staging スナップショット） | **R2-M11** |
| **IT-29** | **handle 解放時に staging ディレクトリが削除される** | R2-M11 |

### 12.3 Presentation テスト

| ID | 検証内容 | 対応 |
|---|---|---|
| PT-01 | `ClipboardPasteLoader` が複数 provider を並行ロードし全件返す | H-8 |
| PT-02 | 1 件失敗しても他が返り `isPartial == true` | **H-8 部分失敗** |
| PT-03 | timeout で未完了分が `pasteLoadTimedOut` になり `onPaste` は 1 回 | **H-8 exactly-once** |
| PT-04 | 型の優先度が `acceptedTypes` の指定順で決定的 | H-8 |
| PT-05 | View 破棄で `Progress.cancel()` が呼ばれ `onPaste` が呼ばれない | H-8 |
| **PT-06** | **結果が `providerIndex` の昇順（入力順）に正規化される** | **R2-M10** |
| **PT-07** | **全件失敗で `isCompleteFailure == true`、`isPartial == false`** | R2-M10 |
| **PT-08** | **`ClipboardPasteContainerView.deinit` から `cancelPaste` が呼ばれる。二重呼び出しでクラッシュしない** | R2-M10 |

### 12.4 Bridge テスト

| ID | 検証内容 | 対応 |
|---|---|---|
| BT-01 | 全 18 endpoint が正常系で callback を 1 回呼ぶ | **H-2 exactly-once** |
| BT-02 | JSON パース失敗で `errorCode == 1301` を 1 回返す | H-2 |
| BT-03 | 必須引数 NULL で `errorCode == 1302` を 1 回返す | H-2 |
| BT-04 | callback が NULL でも操作は実行され、クラッシュしない | H-2 |
| BT-05 | 非メインスレッドから呼んでも callback がメインスレッドで来る | **H-7** |
| BT-06 | 全 endpoint の JSON schema が §8.4 と一致（round-trip） | H-2 |
| BT-07 | `Data` が Base64 で往復する | H-2 |
| BT-08 | 監視 endpoint が購読中に複数イベントを配信し、stop 後に止まる | H-2 |
| BT-09 | 受領 endpoint が `isFinished == YES` を 1 回だけ返す | H-3 |
| **BT-10** | **全 19 endpoint の C prototype が §8.4.3 と一致する（ヘッダ検査）** | **R2-H3** |
| **BT-11** | **§8.4.4 の全 JSON 型が round-trip する（入力 9 種・出力 10 種・イベント 2 種）** | **R2-H3** |
| **BT-12** | **event callback が購読中 N 回呼ばれ、operation callback は 1 回のみ** | **R2-H3（exactly-once の適用範囲）** |
| **BT-13** | **`clipboardReceiveFilePromises` の開始 ack が receipt handle を返す** | R2-H2 |
| **BT-14** | **`clipboardCancelReceiveFilePromises` が冪等で、terminal event を 1 回だけ出す** | R2-H2 |
| **BT-15** | **`sourcePath` が存在しない場合、登録自体が失敗し handle を返さない** | R2-M11 |
| **BT-16** | **`Log` に `sourcePath` の完全パスが出ない** | R2-M11 / §4.2 |

### 12.5 並行性テスト

| ID | 検証内容 |
|---|---|
| CT-01 | Swift 6 strict concurrency で警告ゼロ |
| CT-02 | `ClipboardChangeMonitor` が非 Sendable 捕捉の警告を出さない（RK-10） |
| CT-03 | `FilePromiseDelegate` が nonisolated 要件を満たす |
| CT-04 | Manager の callback が常に MainActor |
| CT-05 | 同期 UseCase が `async` になっていない（シグネチャ検査） |
| CT-06 | **`releaseFilePromise` と履行完了の競合で二重解放が起きない**（M-4 race） |
| CT-07 | **監視の再入（start 連続呼び出し）でイベントが重複配信されない**（M-5 race） |
| **CT-08** | **同時開始・同時完了・release・stale の 4 者競合で二重解放も早期解放も起きない**（R2-H4 race） |
| **CT-09** | **nonisolated delegate からの状態更新と MainActor coordinator の解放が原子的に接続される**（R2-H4） |

### 12.6 手動確認項目

| ID | 内容 | 環境 |
|---|---|---|
| MT-01 | 他アプリでコピー → read できる | macOS 15.x 実機 |
| MT-02 | copy → 他アプリで貼り付け | 同上 |
| MT-03 | append が自所有時のみ成功し、他者所有時は明示エラー | 同上 |
| MT-04 | 監視が別アプリのコピーを検出。非アクティブで停止し復帰で照合 | 同上 |
| MT-05 | **File Promise を Finder へドラッグしてファイル生成**。D&D UI は out スコープだが、検証には最小 drag harness をサンプルアプリ側に用意する（`design-sample-app` へ申し送り） | 同上 |
| MT-06 | `PasteButton` から貼り付け。部分失敗時の表示 | 同上 |
| MT-07 | 検出 API が 15.4+ で動作、15.0–15.3 で `detectionUnavailable` | **15.4.1 と 15.2 の両方** |
| MT-08 | `localOnly` の Universal Clipboard 抑止 | **実機 Mac + iPhone（VM 不可）** |
| MT-09 | プライバシーアラートの挙動 | **RK-22 により判定保留** |

---

## 13. 実装タスク分解

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | Domain モデル + `ClipboardLimits` + `FilePromiseReceiptPolicy` + `ClipboardError`（25 ケース / 1501〜1599） | 1.0日 | なし | `ClipboardErrorTests` と設定値検証テスト全通過 | Domain に platform 型なし。コード重複なし。`BridgeError` と衝突なし。**§6.8 の入力検証（R2-M9）** |
| T-02 | Port 3 種（`ClipboardRepository` / `ClipboardPromiseRegistry` / `ClipboardTypeIdentifierValidating`） | 0.5日 | T-01 | Mock が実装できる | **Port に Presentation / AppKit 型が現れないこと（H-1）**。同期・async の割り当てが §9 と一致 |
| T-03 | `PasteboardResolver` / `ClipboardMappers` / `ClipboardTypeIdentifierValidator` | 1.0日 | T-02 | Data 層単体テスト通過 | RK-14 / RK-18 |
| T-04 | `ClipboardRepositoryImpl` の C / R / Q / X | 1.5日 | T-03 | IT-01〜IT-05、IT-07、IT-08 通過 | **§6.4 の所有権単一経路（RK-05）**、§6.3（RK-23）、RK-15 |
| T-05 | `ClipboardRepositoryImpl` の P + 標準ペーストボード保護 | 0.5日 | T-03 | IT-06 通過 | **RK-07 のガードが構造的** |
| T-06 | UseCase 19 本 + Validator + 単体テスト | 2.0日 | T-04, T-05 | 12.1 全通過 | 不要な `async` がないこと |
| T-07 | **`ClipboardSystemCoordinator`（全 delegate の唯一の所有者）** | 1.0日 | T-06 | 登録・解放・冪等性のテスト通過 | **H-5: Repository / Presentation が delegate を所有していないこと** |
| T-08 | `MacClipboardManager` 骨格（DI、callback + native、`Log.d`） | 1.0日 | T-07 | 全 OP が呼べ、callback が MainActor | **OP-01〜OP-11 が `async throws` + `@discardableResult`、OP-12〜OP-17 / OP-20 が同期であること（R2-H1）**。CT-04 |
| T-09 | 検出 API + `ClipboardDetectionMapper`（**DDMatch\* 全フィールド + `matchedString`**）+ バージョン分岐 | 1.5日 | T-08 | IT-20、Mapper テスト通過 | **M-7 の非可逆変換がないこと。`matchedString` が全 8 entity にあること（R2-M8）**。**15.4 未満に Q 群フォールバックを置かないこと（RK-01）** |
| T-10 | `ClipboardChangeMonitor` + Tracker + アクティブ連動 | 1.0日 | T-08 | IT-09〜IT-11、CT-02、CT-07 通過 | **M-5 の start 順序**。配置が MacLibrary/Presentation |
| T-11 | File Promise 提供側（delegate / registry / **`inFlightCount` 状態機械** / serial queue / transaction） | 2.0日 | T-07, T-08 | IT-12〜IT-14、**IT-21〜IT-24**、CT-03、CT-06、**CT-08、CT-09** 通過 | **RK-21: coordinator が provider+delegate を強参照。completion は要求ごとに 1 回。全体で 1 回に絞るガードを置かない**。**R2-H4: `inFlightCount` で複数同時履行を扱う。R2-M5: release は完全冪等・非 throwing。R2-M12: register→write→rollback** |
| T-12 | **File Promise 受領側（静穏 + 全体タイムアウト + OP-20 cancel）** | 1.5日 | T-11 | IT-15〜IT-19、**IT-25〜IT-27** 通過 | **H-3: `fileTypes.count` を終了判定に使っていないこと。`finished` が exactly-once。終端後の late callback 破棄**。**R2-H2: 公開 cancel。R2-M6: §7.12.3 の truth table どおり throw しないこと** |
| T-13 | OP-18 の native async（`AsyncThrowingStream` + 集約 async） | 0.5日 | T-12 | ストリームが終端し、Task キャンセルが OP-20 へ合流する | **H-4: common.md の併設要求**。**R2-M6: 集約版は throw せず partial receipt を返す**。`onTermination` の接続 |
| T-14 | `ClipboardPasteLoader` + `PasteButtonFactory` + `ClipboardPasteContainerView` | 1.5日 | T-08 | PT-01〜**PT-08** 通過 | **H-8: 部分失敗・timeout・exactly-once・cancel**。**R2-M10: 入力順正規化、`isPartial` の定義、container の `deinit` から cancel** |
| T-15 | `LazyDataProvider`（内部限定） | 0.5日 | T-07 | 大容量 copy が遅延提供を通る | RK-17。所有は coordinator |
| T-16 | Unity Bridge（facade / parser / `.h` / `.m`）+ §8.4 の契約実装（**19 endpoint、全 JSON 型、staging スナップショット**） | 2.5日 | T-08〜T-14 | BT-01〜**BT-16** 通過 | **H-2 / R2-H3: 全 19 endpoint の C prototype と JSON schema が §8.4 と一致。operation は exactly-once、event は N 回**。**H-7: nonisolated facade + 任意スレッド可**。**R2-M11: staging スナップショットと cleanup、sourcePath をログに出さない**。ObjC 型規約 |
| **T-16b** | **既存 `BridgeError.swift` の DocC 修正（R2-M14）** | 0.25日 | T-16 | DocC が NULL callback 許容と矛盾しない | **enum ケース・code・message を変更しないこと** |
| T-17 | DocC 整備 | 0.5日 | T-16 | `public` に英語 DocC | 「通知なし」を保証しない（RK-01/02/22）、append の契約差（RK-23）、名前付きの残存（RK-06）、`localOnly` 未検証（V-8）、`finished` が推定であること（H-3）、`PasteButton` の非自動 validate（RK-16） |
| T-18 | サンプルアプリ対応 | - | T-17 | **`design-sample-app` で設計。完了条件は「全公開 OP が `MacLibraryExample` から Unity 非依存で実行できること」および「MT-05 用の最小 drag harness を含むこと」** | common.md のサンプル依存方向 |

**先行（基盤）**: T-01 〜 T-08
**後続（拡張）**: T-09 〜 T-18

合計見積: 約 21.25 日（T-18 を除く）

---

## 14. リスクと緩和策

| 企画書リスク | 本設計での対応 | 残存リスク |
|---|---|---|
| RK-01 / RK-02 | 15.4 未満は throw。Q 群フォールバックなし | 15.0–15.3 で検出不可。仕様として受容 |
| RK-03 | `detectValues` の通知を DocC 明記 | 呼び出し側の規律に依存 |
| RK-04 | `expirationDate` を持たない | なし |
| RK-05 | §6.4 の単一経路 | レビュー確認が必要（T-04） |
| RK-06 | DocC に残存を明記 | 仕様として受容 |
| RK-07 | 構造的ガード（T-05） | なし |
| RK-08 | 全層 `@MainActor`（§6.2） | 大容量時のブロック → RK-20 |
| RK-09 | `FilePromiseDelegate` を nonisolated に | なし |
| RK-10 | `@MainActor` + `assumeIsolated`（T-10） | なし |
| RK-11 | ポーリング + アクティブ連動 | 取りこぼしと電力。間隔設定可 |
| RK-12 | 読み込み失敗を明示エラー化 | **企画書 V-6 未消化** |
| RK-13 / RK-14 | 所有権取得 → `writeObjects` 固定。アイテム毎回生成 | なし |
| RK-15 | `pasteboardItems` 経路に統一 | なし |
| RK-16 | DocC 明記 | 呼び出し側で制御 |
| RK-17 | coordinator が強参照。L-03 で解放 | **企画書 V-3 未消化** |
| RK-18 | Validator を Data 層に配置 | なし |
| RK-19 | `NSPasteboardType*` / `Name.*` のみ | なし |
| RK-20 | warn / hard の 2 段（§6.7）+ 遅延提供誘導 | **閾値の妥当性は DV-02** |
| RK-21 | coordinator が provider+delegate を強参照。状態機械で解放（T-11） | 解放漏れは冪等 release と stale 検出で緩和 |
| RK-22 | どの経路も「通知なし」を保証しない | **MT-09 は判定保留** |
| RK-23 | 所有権トークンで明示エラー化（§6.3） | iOS と同名で契約が異なる。DocC で明示 |

### 14.1 要検証事項

| ID | 内容 | 検証方法 |
|---|---|---|
| DV-01 | `@MainActor` 固定で大容量 copy / read が UI をブロックする程度 | 実機で 1 / 10 / 50 MB を計測 |
| DV-02 | `ClipboardLimits` の warn 10MiB / hard 100MiB / 合計 200MiB が妥当か | 同上 |
| DV-03 | 監視間隔 0.5 秒の電力・CPU 影響 | 0.5 / 1.0 / 2.0 秒を比較 |
| DV-04 | File Promise の `pendingRelease` 遷移が履行を阻害しないか | 長時間書き出しで検証 |
| DV-05 | **`quietInterval` 2 秒 / `overallTimeout` 60 秒が妥当か。遅い provider で早期終端しないか** | 複数ファイル・低速 provider で計測（H-3） |
| DV-06 | `ClipboardPasteLoader` の timeout 15 秒が妥当か | 大きな画像の貼り付けで計測 |

---

## 15. Definition of Done

### 設計完了条件

- [x] **第 2 回レビュー指摘 14 件（高 4 / 中 9 / 低 1）をすべて反映した。反映先は §0 の対応表**
- [x] **OP-01〜OP-11 の Manager native API を `async throws` + `@discardableResult` に戻し、mac.md の必須契約を満たした（R2-H1）**
- [x] **OP-20 `cancelReceiveFilePromises` を公開 API・Bridge の双方に追加した（R2-H2）**
- [x] **Bridge の全 19 endpoint について完全な C prototype と JSON schema を定義し、operation callback と event callback の回数契約を分離した（R2-H3）**
- [x] **File Promise 提供側を `inFlightCount` ベースの状態機械にし、serial queue と原子的な開始記録で複数同時履行の race を排除した（R2-H4）**
- [x] **OP-18 の終端 truth table を 6 経路 × 4 形態で固定した（R2-M6）**
- [x] **`PromiseObjectLookup` / `ClipboardPasteHandle` の配置・可視性・寿命を定義した（R2-M7）**
- [x] **全 8 種の detection entity に `matchedString` を追加した（R2-M8）**
- [x] **interval / timeout / limits の入力検証規則を §6.8 に定義した（R2-M9）**
- [x] **PasteButton の結果順序・全失敗の判別・View 破棄時の解放経路を定義した（R2-M10）**
- [x] **Bridge の `sourcePath` を登録時 staging スナップショット方式に確定し、Sandbox 制約と cleanup を定義した（R2-M11）**
- [x] **register → write → rollback の transaction を UseCase に定義した（R2-M12）**
- [x] 第 1 回レビュー指摘 20 件（高 8 / 中 11 / 低 1）を反映済み。反映先は §0.1 の対応表
- [x] 企画書 API ID 単位の採用・内部限定・対象外の完全対応表を §2.1 に作成した（M-11）
- [x] common.md / mac.md の各項目に対する適合可否を §3 / §4 に記載した
- [x] **Port の引数・戻り値が Domain 値型のみであることを確認した（H-1）**
- [x] **system delegate の所有を Manager 層 1 クラスに一元化した（H-5）**
- [x] **`receiveFilePromises` の終了判定から保証されない `fileTypes.count` を排除した（H-3）**
- [x] **OP-18 に native async 版を追加した（H-4）**
- [x] **`ReceiveFilePromisesUseCase` / `ReleaseFilePromiseUseCase` を追加した（H-6）**
- [x] **Unity Bridge の全 endpoint 契約（callback 型・JSON schema・C 文字列寿命・スレッド・NULL・exactly-once）を §8.4 に定義した（H-2）**
- [x] **`@MainActor` と任意スレッド C Bridge の両立方針を §6.6 で確定した（H-7）**
- [x] **`PasteButton` の payload 変換（非同期ロード・部分失敗・timeout・cancel）を §7.11 で定義した（H-8）**
- [x] 全公開操作（OP-01〜OP-19）を §9 に収録し、timeout / exactly-once / late result の列を追加した（M-6）
- [x] 企画書の分類表との差分を §9.1 に理由付きで記載した
- [x] ドメインエラー 25 ケースを §10 に列挙し、`BridgeError` と責務分離した。`promiseHandleNotFound` と `filePromiseTimedOut` は契約変更に伴い削除した
- [x] エラーコード表が既存の使用済みコードと衝突しないことを確認した
- [x] 単体 / 統合 / Presentation / Bridge / 並行性 / 手動確認をテスト設計で分離し、全 OP を ID で追跡した（M-10）
- [x] 実装タスクを 0.5〜2.0 日粒度に分解し、依存関係・完了条件・レビュー観点を付けた
- [x] 変更対象ファイルを具体的なパスで示した。`docs/` を含めていない
- [x] 不確実な事項を DV-01〜DV-06 として要検証に分離した

### 実装完了条件（次工程で満たす）

- [ ] Swift 6 strict concurrency で警告ゼロでビルドできる
- [ ] **実装のシグネチャ・actor isolation・キャンセル・timeout・exactly-once 契約が §9 の対応表と一致している**
- [ ] 12.1 の単体テストが全通過する
- [ ] 12.2 の統合テスト IT-01〜IT-20 が全通過する
- [ ] 12.3 の Presentation テスト PT-01〜PT-08 が全通過する
- [ ] 12.2 の統合テスト IT-21〜IT-29 が全通過する
- [ ] 12.4 の Bridge テスト BT-01〜BT-16 が全通過する
- [ ] 12.5 の並行性テスト CT-01〜CT-09 が全通過する
- [ ] `public` シンボルすべてに英語の DocC が付いている
- [ ] 全メソッド先頭に `Log.d` があり、内容が §4.2 の方針で秘匿されている
- [ ] **Unity Bridge に Delegate 実装が存在せず、system delegate の強参照が `ClipboardSystemCoordinator` のみである**
- [ ] `MacLibraryExample` が `MacLibrary` のみに依存して全公開 OP を実行できる
- [ ] MT-01〜MT-07 を macOS 15.x で実施した（MT-08 は実機 Mac + iPhone、MT-09 は判定保留）
