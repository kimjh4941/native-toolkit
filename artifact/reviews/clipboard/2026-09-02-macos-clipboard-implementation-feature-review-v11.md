# macOS クリップボード機能 実装レビュー v11

- 日付: 2026-09-02
- 対象ブランチ: `feature/NTKIT-15`
- 対象差分: `git diff develop`（**未コミットの working tree を含む**）
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v12.md`
- 対象OS: macOS 15 以降
- 適用ルール: `agent-rules/coding-rules/common.md`、`agent-rules/coding-rules/mac.md`
- 対象外: 設計書 §7.12 のスコープ変更判断そのもの / T-18 / MT-01〜MT-09 / 旧サンプル計画 v1

---

## レビュー概要

v10 指摘 3 件（H-4 / M-6 / L-4）の反映後の状態を、working tree を含めて検証した。

### 検証結果（再現できた）

| 項目 | 報告値 | 再現値 | 判定 |
|---|---|---|---|
| MacLibrary（宣言 / 実行 / 失敗） | 302 / 346 / 0 | **302 / 346 / 0** | 一致 |
| UnityMacPlugin（宣言 / 実行 / 失敗） | 71 / 72 / 0 | **71 / 72 / 0** | 一致 |
| 通常 `clean test` の Clipboard 警告 | 0 件 | **0 件**（残る警告は `appintentsmetadataprocessor` 2 件と既存 `UnityMacNotificationJsonParser.swift:198` のみ） | 一致 |
| strict build | BUILD SUCCEEDED / 173 / Clipboard 0 | **BUILD SUCCEEDED / 一意 173 件 / Clipboard 由来 0 件** | 一致 |
| 機械照合 | 28 / 28 | **28 / 28（exit 0）** | 一致 |
| `git diff develop --check` | 0 件 | **0 件** | 一致 |

数値はすべて再現できた。件数は `xcresulttool get test-results summary` から読んでいる。

### v10 指摘の反映

- **H-4**: `HandleJson` サンプル / File Promise 由来 CT / 実在しない ID 範囲 / OP-16 の DoD はすべて消えている。検査 14・15 を追加し 28 検査になっている。**反映されている。**
- **M-6**: `MacClipboardManager` の型 DocC は同期 API を名指しする形に修正され、OP-12〜15 / OP-19 の記述と一致した。**反映されている。**
- **L-4**: §16.1 の表は 15 行、冒頭は「28 項目」に更新されている。**反映されている**（ただし §15 の DoD 行は追随していない。M-1 参照）。

### 総合

**要修正（重大）**。high 4 件 / medium 7 件 / low 7 件。

3 ラウンド続いた「削除の取り残し」は production code / テストからはほぼ消えたが、
**設計書の現行章にまだ 7 箇所残っており**（M-1）、
**それを止めるはずの機械照合 28 検査には実証済みの false green が 2 件ある**（H-1 / M-6）。
加えて、File Promise とは無関係な既存欠陥を 4 件（H-2 / H-3 / H-4 / M-5）検出した。

---

## 重大な問題（high）

### H-1. 機械照合の「識別子の実在」検査が、削除済み JSON 型を通してしまう（実証済み）

- 該当: `scripts/check_design_consistency.py:329-364`（`check_live_symbols`）、特に corpus 構築 `:344-351` と判定 `:361`
- 共犯: `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift:41`

検査 12 は「現行章が backtick で名指す識別子が `mac/` のソースに実在するか」を見る。
しかし corpus は **`*.swift` / `*.h` / `*.m` を全文連結した 1 本の文字列**であり、判定は
`ident in corpus`（単なる部分文字列一致）である。corpus には **テストコードも含まれる**。

その結果、v9 で削除した JSON 型名は、**それらが消えたことを主張しているテスト自身の
文字列リテラルによって「実在する」ことになっている。**

```swift
// UnityMacClipboardJsonParserTests.swift:41
for gone in ["FilePromiseRequestJson", "PolicyJson", "ReceiptEventJson", "HandleJson"] {
    #expect(!all.contains(gone), "\(gone) is still declared")
}
```

再現（設計書に §13.5 を追加し、削除済み 3 型を現行章で名指した）:

```
`ReceiptEventJson` と `HandleJson` は受領 session の終端を運ぶ。`PolicyJson` で挙動を指定する。
→ 28 / 28 OK, EXIT=0
```

**何が壊れるか**: v10 H-4 で見つかった `HandleJson` の取り残しは、コードブロック検査（15）が
無ければ**今も通る**。同じ 4 語が現行章の散文に戻ってきた場合、28 検査は全部緑を返す。
「毎ラウンド、前ラウンドで作った検査の穴が次の指摘になっている」（結果 v12 §6）という
構図が、11 ラウンド目でもそのまま成立している。

比較として `overallTimeout` / `inFlightCount` は corpus に無いので現状は捕まる。
つまり穴は語ではなく **「テストの負のアサーションが corpus を汚染する」構造**にある。

対処案（いずれか）:
- corpus からテストターゲット（`*Tests/`）を除外する
- 部分文字列一致をやめ、宣言位置（`(struct|class|enum|protocol|typealias|func|let|var)\s+<ident>`）で照合する

---

### H-2. `makePasteButton` がアプリ独自 UTI を無言で捨てる

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:79`

```swift
let contentTypes = acceptedTypes.compactMap { UTType($0) }
let button = PasteButton(supportedContentTypes: contentTypes) { ... }
```

設計書 §8.2 と `ClipboardTypeIdentifierValidator` の DocC は、**「`UTType(identifier) != nil`
を判定基準にしてはならない。`com.mycompany.myformat` は `UTType` が `nil` を返すが
pasteboard は受理する。`UTType` で検証すると**アプリ独自フォーマットを不当に拒否する**」と
明記しており、実装もその方針で検証している（`ClipboardPasteLoader.swift:72`）。

ところが同じ識別子が、その 7 行あとで `compactMap { UTType($0) }` によって**黙って捨てられる**。

**何が壊れるか**:
- `makePasteButton(acceptedTypes: ["com.mycompany.myformat"])` は **throw せず成功する**。
  返るのは `PasteButton(supportedContentTypes: [])`、すなわち何も受け付けないボタンである。
- 呼び出し側には `onPaste` が来ないだけで、エラーも `Log.e` も出ない。原因を追う手掛かりがない。
- 混在時（`["com.mycompany.myformat", "public.utf8-plain-text"]`）は独自型だけが静かに落ち、
  独自型を持つ item が貼れないという再現性の低い挙動になる。

設計 §7.11 は `acceptedTypes` の扱いを「UTI として検証済み。空なら `invalidTypeIdentifier`」
としか書いておらず、この縮退は設計にも DocC にも無い。

**テストが 1 件も無い**: `PasteButtonFactory.makePasteButton` を通る自動テストは存在しない
（`ClipboardPasteLoaderTests.swift` は `ClipboardPasteLoader` と `ClipboardPasteContainerView`
を直接組み立てている）。PT-14 が「本番境界を通らない fake 注入」を戒めているのと同じ穴が、
factory 側に残っている。

対処案: `UTType` に解決できない識別子は `invalidTypeIdentifier(_:)` を投げる、または
DocC と設計に「`UTType` に解決できる型のみ `PasteButton` に渡る」と明記したうえで
`Log.e` を残す。いずれにせよ **無言で落とすのは不可**。

---

### H-3. 必須引数 NULL が 1302 ではなく 1301 を返す。BT-03 は実装されていない

- 該当（契約）: 設計 §8.4.1「必須引数が NULL → `BridgeError.contractViolation`（1302）」／
  §12.4 BT-03「必須引数 NULL で `errorCode == 1302` を 1 回返す」／§15 実装完了条件は
  BT-03 を **[x]** としている
- 該当（実装）: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:130`
  （`read`）ほか、`scopeJson` を取る 12 endpoint と `contentJson` / `ownershipJson` /
  `patternsJson` / `requestJson` のすべて

```swift
guard let scope = parser.parseScope(scopeJson) else {
    return fail(handler, .parseFailed(reason: "Invalid clipboard JSON argument."))   // 1301
}
```

`parseScope(nil)` は `decode` の `guard let json` で `nil` を返すため、**引数そのものが NULL でも
「JSON パース失敗（1301）」になる**。1302 を返しているのは `readData` の `utType`
（`:143`）と `startObserving` の `onChange`（`:301`）だけである。

`.h` にも `_Nullable` は付いておらず（`UnityMacClipboardManagerBridge.h:85` 等）、
`matchingTypesJson` 以外は必須引数として文書化されている。

**何が壊れるか**: Unity 側は「引数を渡し忘れた（自分のバグ）」と「JSON が壊れている
（データの問題）」を区別できない。この 2 つを分けるために `BridgeError` が 2 コードに
分かれており、その分割が Bridge の公開契約になっている。

さらに **BT-03 を検証するテストが存在しない**。`UnityMacClipboardBridgeTests.swift` は
ソーステキスト検査と BT-24 のみで、以下の BT が DoD で [x] とされながら 1 件も実装されていない。

| ID | 設計での要求 | 実装 |
|---|---|---|
| BT-01 | 全 15 endpoint が正常系で operation callback を 1 回呼ぶ | なし（facade メソッド数 15 を数えるのみ・`:54-60`） |
| BT-03 | 必須引数 NULL で 1302 を 1 回 | **なし。かつ実装は 1301** |
| BT-05 | 非メインスレッド呼び出しでも callback がメインスレッド | なし |
| BT-08 | 監視 endpoint が購読中 N 件配信し stop で止まる | なし |
| BT-12 | event N 回 / operation 1 回 | なし |
| BT-22 | background thread からの早期リターン経路も main で exactly-once | なし |
| BT-23 | nil callback で trap しない / start・stop 境界で handler が交差しない | なし |

BT-02 は BT-24 の `copy` 1 経路のみが実質的にカバーしている。

---

### H-4. Bridge ヘッダが `clipboardCreatePasteboard` の戻り値を誤って `ScopeJson` と書いている

- 該当: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.h:105`
- 実装: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift:377-380`

```objc
/// Creates or fetches a pasteboard. Returns ScopeJson.
void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback);
```

```swift
func encodeScope(_ scope: PasteboardScope) -> String? {
    return encode(ClipboardJson.ScopeResultJson(scope: scopeShape(scope)))   // {"scope": {...}}
}
```

設計 §8.4.3 は `// -> ScopeResultJson`、§8.4.4 は
「**`ScopeResultJson` は `createPasteboard` の戻り値**であり、`ScopeJson` を直接返すのではなく
`{"scope": ...}` で包む。**この形が Unity 側と交わす wire format の正である**」と明記している
（R8-H2 で確定した事項）。

**何が壊れるか**: ヘッダは Unity C# 実装者が唯一読む一次資料である。ここに従って
`{"kind":"unique","name":"..."}` をパースすると、実際に来るのは `{"scope":{...}}` なので
**unique ペーストボードの名前が取れず、`clipboardRemovePasteboard` で解放できなくなる**。
callback を必須にしてまで守っている資源回収の契約が、ヘッダ 1 行で無効化される。

BT-10「全 15 endpoint の C prototype が §8.4.3 と一致する（ヘッダ検査）」は DoD で [x] だが、
実装されていない（`UnityMacClipboardBridgeTests` はプロトタイプ**数**しか数えていない）。
なお `.h:96` の `matchingTypesJson` に §8.4.3 が付けている `_Nullable` も落ちている。

---

## 改善提案（medium）

### M-1. 設計書の現行章に File Promise 削除の取り残しが 7 箇所ある

**§7.12・§2.1 / §2.2・変更履歴 `## 0.x` を除いた現行章**での検出。

| # | 行 | 内容 | なぜ問題か |
|---|---|---|---|
| 1 | `design-v9.md:500`（§6.2） | 「大容量は遅延提供（§7.4）または **File Promise へ誘導する**」 | RK-20 の緩和策として、v1 に存在しない機構を提示している。§14 の RK-20 行は「遅延提供誘導」に修正済みで、§6.2 だけ取り残されている |
| 2 | `:1734`（§15 設計完了条件） | 「**callback 必須 endpoint を 3 件に確定した**（R4-M6）」 | 現行は 1 件（冒頭「用語」・§8.4.1・BT-17）。3 件のうち 2 件は `clipboardProvideFilePromise` / `clipboardReceiveFilePromises` で v9 に無い。**直接の削除取り残し** |
| 3 | `:1732`（§15） | 「**T-11 を 3 分割し、さらに T-06 / T-12 を 2 分割して**…」 | T-11 / T-12 は v9 で削除済み（§0 の削除表）。§13 のタスク表に存在しない ID を DoD が参照している |
| 4 | `:1741`（§15） | 「件数の基準（**公開 OP 20 / Bridge endpoint 19**）を冒頭に固定し」 | 現行は 16 / 15。冒頭「用語」と矛盾する |
| 5 | `:1727`（§15） | 「機械照合を導入し、**全 22 検査**が通ることを確認した（**§16.2**…）」 | 現行は 28 検査。しかも **§16.2 は存在しない**（§16 の子は §16.1 のみ）。v10 L-4 の修正が §16.1 に留まり DoD 行に及んでいない |
| 6 | `:471`（§6.1 テスト構成） | `Application/ (UseCase ごとに 1 ファイル、20 本)` | UseCase 18 本時代の数。冒頭「用語」の 14 本 + 3（ファイル 17 本）とも、実ファイル 4 本とも合わない |
| 7 | `:928`（§7.12） | 「4 公開 OP、**2 Bridge endpoint** を占めていた」 | §0 は「Bridge endpoint 4 件。19 → 15 件」。v8 の実数（19）と現行（15）の差も 4。**§7.12 内の数値矛盾**（スコープ変更判断そのものではないので対象内） |

いずれも検査 12〜15 では捕まらない。#1 / #2 / #3 / #5 は backtick 識別子を含まず、#4 は
`check_live_counts` の 2 パターン（`全 N endpoint` / `実体 N 型`）に当たらない（実証済み:
「Bridge endpoint は 19 件ある」を追加しても 28/28 通過）。

### M-2. §6.1 / §4.1 / §6.5.1 のファイル構成が実装と一致していない

現行章の記述と実ツリーの差。

| 設計の記述 | 実際 |
|---|---|
| §4.1・§6.1: `Clipboard/Coordinator/ClipboardSystemCoordinator.swift` | `Clipboard/Manager/ClipboardSystemCoordinator.swift` |
| §6.1: `Clipboard/MacClipboardManager.swift`（Clipboard 直下） | `Clipboard/Manager/MacClipboardManager.swift` |
| §6.1: Domain/Model 18 ファイル（`PasteboardCreationRequest.swift` / `PasteboardOwnership.swift` / `PasteboardPromiseHandle.swift` / `ClipboardItemData.swift` / `ClipboardCopyOptions.swift` / `ClipboardReadResult.swift` / `ClipboardSnapshot.swift` / `ClipboardChangeEvent.swift` / `ClipboardDetectionPattern.swift` / `ClipboardDetectedValues.swift` / `ClipboardDetectedEntities.swift` / `ClipboardDetectedMetadata.swift` / `ClipboardAccessBehavior.swift` / `ClipboardPasteHandle.swift` の 14 本が存在しない） | 6 ファイル（`ClipboardContent.swift` / `ClipboardDetection.swift` / `ClipboardHandles.swift` / `ClipboardLimits.swift` / `ClipboardPasteResult.swift` / `PasteboardScope.swift`） |
| §6.5.1: `ClipboardPasteHandle` は `Clipboard/Domain/Model/ClipboardPasteHandle.swift` | `Clipboard/Domain/Model/ClipboardHandles.swift` |
| §6.1: `MacLibraryTests/Clipboard/Mock/MockClock.swift` | 存在しない |
| §6.1: テストの `Data/` に `LazyDataProviderTests.swift` なし、`Manager/` ディレクトリなし、`Domain/ClipboardConfigurationTests.swift` なし、`ClipboardDocumentationTests.swift` なし | いずれも存在する |

**何が壊れるか**: §6.1 は T-01〜T-16 の作業単位を定義する章であり、レビュー・後続タスク
（T-18 サンプル、write-manual）はここを地図として読む。実在しないパスを 14 件抱えた地図は、
File Promise 取り残しと同じ「設計書だけが古い」状態である。検査 12 は backtick 内の
`\w{6,}` しか見ないので、コードフェンス内のパス（`.` を含む）は対象外になっている。

### M-3. Port の公開 DocC に「stale detection」が残っている

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Application/Port/ClipboardRepository.swift:70`

```swift
/// Current change count, used for observation and stale detection.
func changeCount(scope: PasteboardScope) throws -> Int
```

stale 判定は File Promise 専用の機構で、設計 §6.5.1 は
「stale 判定は File Promise 専用の機構だったため、**v9 の削除に伴い構造ごと不要になった**」
と明記している。v12 で `GetChangeCountUseCase.swift` の同趣旨の記述は削除されたが、
**その 1 階層上の Port の DocC は残っている**。

**何が壊れるか**: `ClipboardRepository` は `public protocol` であり、この 1 行は生成 DocC に
そのまま出る。「stale detection」に対応する呼び出し元も概念もライブラリに無いため、
読んだ人は存在しない機能を探すことになる。検査 12 は設計→コードの一方向しか見ないので、
コード側に残った削除済み概念は原理的に検出できない。

### M-4. Unity facade の public 関数 14 本に DocC が無い（mac.md 違反）

- 該当: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift`
  の `:87` `copy` / `:111` `append` / `:127` `read` / `:139` `readData` / `:161` `snapshot` /
  `:178` `clear` / `:190` `createPasteboard` / `:210` `removePasteboard` / `:223` `detectPatterns` /
  `:239` `detectValues` / `:255` `detectMetadata` / `:267` `accessBehavior` /
  `:328` `stopObserving` / `:338` `checkForegroundChange`

`mac.md`「コメント（DocC / HeaderDoc）」は適用対象を
「Swift 実装（`mac/MacLibrary/`, **`mac/UnityMacPlugin/`** 配下）」と定め、`public func` を必須と
している。既存の `UnityMacShareManager.swift:47-50 / :69-72` は各引数の意味を DocC で書いており、
これが確立した慣例である。

DoD（§15 実装完了条件）は「`public` シンボルすべてに英語の DocC が付いている」を **[x]** に
しているが、これを検証する `ClipboardDocumentationTests` は
`MacLibrary/MacLibrary/Clipboard` 配下しか走査していない（`:19-25`）。
**検査範囲外を「合格」と数えている**点は、H-1 と同じ形の false green である。

### M-5. Manager が Data 層の具象 `ClipboardTypeIdentifierValidator` を直接生成している

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:545`

```swift
public func makePasteButton(...) throws -> NSView {
    return try PasteButtonFactory.makePasteButton(
        acceptedTypes: acceptedTypes,
        timeout: timeout,
        validator: ClipboardTypeIdentifierValidator(),   // ← Data 層の具象を操作内で new
        ...)
}
```

`common.md`「Manager は UseCase 経由で Data 層にアクセスし、直接 Repository を呼ばない」および
その理由（「入力検証・エラー変換・ビジネスロジックがテスト不能なまま Manager 内に混在する」）に
反する。`ClipboardTypeIdentifierValidator` は `Clipboard/Data/Repository/` の internal クラスであり、
`ClipboardTypeIdentifierValidating` Port の実装である。

**何が壊れるか**: 注入用 initializer `init(coordinator:useCases:)`（`:104`）を使うテストからも、
この検証器だけは差し替えられない。実際 `MacClipboardManagerTests` は mock を注入しているのに
`makePasteButton` だけ本物の検証器を通る。UTI 検証規則を変えたときに Manager 経路だけ
mock で固定できないため、H-2 のような取りこぼしがテストで表面化しない。

なお `:93` と `:98` でも同じクラスを 2 回生成している（composition root なので層の違反ではないが、
`ClipboardUseCases` と `ClipboardRepositoryImpl` が別インスタンスを持つ理由は無い）。

対処案: 検証器を `MacClipboardManager` のストアドプロパティにし、注入用 init から渡す。

### M-6. 28 検査のうち「error code bands disjoint」は構造上決して失敗しない

- 該当: `scripts/check_design_consistency.py:215-219`

```python
bands = {}
for code in codes:
    bands.setdefault(code[:2], set()).add(code)
rep.check(len(bands) == len({frozenset(v) for v in bands.values()}), "error code bands disjoint", ...)
```

`bands` のキーは各要素の先頭 2 桁そのものなので、**異なるキーが同じ集合を持つことはあり得ない**。
したがって `len(bands) == len({frozenset...})` は恒真である。ランダムなコード集合 20,000 通りで
一度も失敗しないことを確認した。

**何が壊れるか**: 28 検査のうち 1 つが「永久に緑」であり、
`ClipboardError`（1501〜1599）と `BridgeError`（1301 / 1302）の帯が衝突しても検出できない。
28 という数字が実際の検査力より 1 件多く見積もられている。

あわせて `check_error_mapping`（`:194-204`）は
`documented = {k: v for k, v in declared.items() if k in actual}` で
**実装に存在しないケースの行を暗黙に除外**している。すなわち
「実装 → 設計」は検査するが「設計 → 実装」は検査していない。削除済みエラーの行が §11 に
残っても、その case 名が corpus のどこか（テストの文字列を含む）にあれば検査 12 も通る。
過去 3 ラウンドの取り残しはすべて「設計に残った」方向だったので、未検査の向きが逆である。

### M-7. `ClipboardChangeMonitor` が `NotificationCenter` の observer を `deinit` で解除しない

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardChangeMonitor.swift:42-46`、
  登録は `:135-148`

```swift
deinit {
    // ... the notification observers are removed by the center when it is torn down with the
    // process.
    pollTask?.cancel()
}
```

コメントの主張が事実と異なる。`NotificationCenter.addObserver(forName:object:queue:using:)` が
返す observer トークンは **center が強参照で保持し、`removeObserver` を呼ぶまで解放されない**。
解除は `stop()`（`:89-92`）にしか無い。

**何が壊れるか**: `MacClipboardManager(limits:)` は `public` で、`shared` 以外にも生成できる。
`startObserving` したまま manager（→ monitor）を解放すると、
`didResignActive` / `didBecomeActive` の observer 2 件がプロセス終了まで center に残り続ける。
ブロックは `[weak self]` なので誤配信は起きないが、生成のたびに単調増加する。
テストでも manager を毎回作っているため、蓄積は実際に起きている。

対処案: `deinit` で `activeObservers` を `removeObserver` する（`stop()` と同じ処理を
`MainActor.assumeIsolated` 無しで書ける。stored property は deinit から読める）。

---

## 軽微な指摘（low）

### L-1. §12.2 の IT-20 / IT-50 が表として壊れている

- 該当: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1581-1583`

IT-11 の後に空行が入り、IT-20 / IT-50 の 2 行がヘッダ行の無い「表」になっている
（IT-12〜IT-19 削除の副作用）。Markdown としては表にならず、`| IT-20 | ... |` が
そのまま本文に出る。`check_tables` は列数しか見ないため検出できない（両行とも 4 列で一致）。

### L-2. 変更監視の実装が設計の `Timer` ではなく `Task` + `Task.sleep`

- 設計: §7.9 手順 4「`Timer.scheduledTimer` を作る。本体は `MainActor.assumeIsolated { }` で
  包む（RK-10）」、§9 OP-13 の System API 欄「M-01 + Timer」、§14 RK-10「`@MainActor` +
  `assumeIsolated`（T-10）」
- 実装: `ClipboardChangeMonitor.swift:99-110` は `Task { while !Task.isCancelled { try? await Task.sleep(...) } }`

機能的には等価で、`assumeIsolated` はアクティブ通知側（`:141` / `:146`）で使われている。
実装のほうが Swift 6 に対して素直だが、**設計書が更新されていない**。
どちらが正かを設計側で確定すること（要確認）。

### L-3. `ClipboardRepositoryImpl.attachCoordinator` は誰も呼んでいない

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Data/Repository/ClipboardRepositoryImpl.swift:29-33`

`lookup` は init で注入されており（`MacClipboardManager.swift:93`）、
本番・テストとも `attachCoordinator` の呼び出しは 0 件。設計 §6.5.1 の DI 順序にも無い。
Data 層のクラスが Manager 層の具象型 `ClipboardSystemCoordinator` を引数に取っており、
残しておくと依存方向を誤らせる。

### L-4. `Log.d` 先頭 1 行ルールの漏れ（mac.md）

- `mac/MacLibrary/MacLibrary/Clipboard/Data/Repository/ClipboardDetectionMapper.swift:144 / :153 / :162`
  （`detectPatterns` / `detectValues` / `detectMetadata`。いずれも引数を取る internal static 関数）
- `mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:28 / :32`
  （`ItemProviderSource.conforms(to:)` / `loadData(for:)`）

`mac.md` の除外（data model / enum / protocol 宣言、private utility extension、純粋 UI
ユーティリティ）に当たらない。検出 API は失敗条件が不明（RK-25）な経路なので、
ログが無いと切り分けができない。

### L-5. Bridge テストに空回りするアサーションがある

- 該当: `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:115-130`

```swift
for line in implementation.split(separator: "\n") where line.contains("^(") {
    #expect(callbackNames.contains { implementation.contains("\($0)(") })
    _ = line
}
```

`#expect` の中身が `line` を一切参照しておらず、ファイル全体に `callback(` があれば
すべてのループ回で真になる。`_ = line` は未使用警告の抑止であり、
**ブロックごとの捕捉監査は実際には行われていない**。BT-21 は
「コンパイラ検証が及ばない ObjC 側の担保」（設計 §8.4.5）として位置づけられている。

### L-6. encode 失敗が「成功 + json = NULL」として通知される

- 該当: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:57-65`

```swift
handler?(true, encode(value), 0, nil)
```

`encode` が `nil` を返した場合（`JSONEncoder` の失敗）、`isSuccess = YES` / `json = NULL` /
`errorCode = 0` が渡る。`.h:51` の「json: Non-NULL only when isSuccess is YES」は
これを禁じてはいないが、Unity 側は成功として NULL を触る。
`readData` の「該当型なし」は `{"data":null}` を返す設計なので、
本当の encode 失敗と区別する手段が無い。1599（`unknown`）にするのが素直。

### L-7. 削除跡の空行が残っている

- `mac/MacLibrary/MacLibraryTests/Clipboard/Mock/MockClipboardTypeIdentifierValidating.swift:19-20`（連続空行）と `:27`（閉じ括弧前の空行）
- `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift:56 / :353 / :426`（削除された宣言の跡）
- `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift:198-200`

`git diff develop --check` は 0 件だが、いずれも v10 → v12 の削除でできた跡。

---

## 設計書整合性チェック

| 項目 | 判定 | 根拠 |
|---|---|---|
| 企画書との整合性 | ○ | §2.1 の API ID 対応表と実装の公開範囲が一致。F-01〜F-10 は §7.12 の実測に基づく対象外 |
| Clean Architecture 準拠 | △ | 層構成・Port の Domain 型限定・delegate の単一所有は守られている。ただし Manager が Data 層の具象を直接生成（M-5） |
| 既存実装との差分分析の正確性 | × | §6.1 / §4.1 / §6.5.1 のファイル構成が実装と大きく乖離（M-2）。§5.2 の `BridgeError.swift` DocC のみ変更は正確 |
| テスト設計の網羅性 | × | BT-01 / 03 / 05 / 08 / 10 / 12 / 22 / 23 に対応するテストが無いまま DoD が [x]（H-3 / H-4）。`makePasteButton` を通る経路がゼロ（H-2） |
| ドメインエラー全ケース実装 | ○ | 20 ケースすべて実装され、`ClipboardErrorTests` / `ClipboardDocumentationTests` が全件を固定 |
| エラーコード / メッセージ対応表との整合 | ○ | 1501〜1515 / 1521〜1524 / 1599 が §11 と 1 件ずつ一致（機械照合 11 で検証）。1516〜1520 は欠番のまま |

## プロジェクトルール適合チェック

| 項目 | 判定 | 根拠 |
|---|---|---|
| common.md 準拠 | △ | 層・依存方向・Port の型制約・delegate 所有・同期非同期設計は適合。Manager → Data 直接生成のみ違反（M-5） |
| mac.md 準拠 | × | Unity facade の public 関数 14 本に DocC が無い（M-4）。`Log.d` 先頭ルールの漏れ 5 件（L-4）。`BOOL` / `NSInteger` / `const char*` 規約は適合 |
| エラー契約反映 | △ | `ClipboardError` → 数値変換は Manager callback 1 箇所に閉じており設計どおり。Bridge 境界の 1301 / 1302 の切り分けが未実装（H-3） |
| 既存 API 互換性 | ○ | 破壊的変更なし。`BridgeError` は DocC のみ変更で enum ケース・code・message は不変 |

## テストカバレッジ

**カバーできている観点**

- UseCase 全 14 本 + Validator / Tracker の正常系・異常系・境界値（§12.1 の全行に対応するテストを確認）
- 実 `NSPasteboard` 統合 IT-01〜IT-11 / IT-50（`ClipboardRepositoryImplTests`）
- Presentation PT-01〜PT-15 相当（`ClipboardPasteLoaderTests`。PT-09〜11 は `H-4:`、
  PT-14 は「the adapter loads through a real NSItemProvider」、PT-15 は `M-4:` として実在）
- JSON 17 型の round-trip を `ClipboardJson` の宣言そのものから導出（BT-11）
- C 層のログ秘匿監査を signature から導出（BT-25。監査自身の網羅も `auditCoversEveryEndpoint` で固定）
- CT-01 strict build 差分 0 件、CT-04 / CT-07

**不足している観点**

- **Bridge の実挙動テストがほぼ無い**: BT-01 / BT-03 / BT-05 / BT-08 / BT-12 / BT-22 / BT-23。
  現状の `UnityMacClipboardBridgeTests` はソーステキスト検査が中心で、
  「任意スレッドから呼んで main で exactly-once」という H-7 の中心契約を 1 件も実行していない
- **`PasteButtonFactory.makePasteButton` を通るテストが 0 件**（H-2 の直接原因）
- BT-10（ヘッダと §8.4.3 のプロトタイプ一致）が数のみ。引数名・`_Nullable`・戻り値型コメントは未検査（H-4 の直接原因）
- `UnityMacPlugin` 側の public シンボル DocC がテスト対象外（M-4）
- IT-20（15.4 未満分岐）は mock 経由のみ。実 OS 分岐は MT-07 待ち（設計どおりで、指摘ではない）

---

## 総合評価

**要修正（重大）**

- high 4 件 / medium 7 件 / low 7 件
- 数値検証（テスト件数・警告 0・strict build・機械照合 28/28・`--check` 0）はすべて再現できた
- v10 の指摘 3 件はいずれも正しく反映されている
- ただし **28 検査には実証済みの false green が 2 件あり**（H-1: 削除済み JSON 型を通す /
  M-6: 恒真の検査）、**設計書の現行章には削除の取り残しが 7 箇所残っている**（M-1）
- あわせて、File Promise とは無関係な既存欠陥を 4 件検出した
  （H-2 独自 UTI の無言破棄 / H-3 1302 契約の未実装 / H-4 ヘッダの wire format 誤記 /
  M-5 Manager → Data の直接生成）。いずれも該当箇所を通る自動テストが存在しない

### 優先順位

1. **H-1**（検査 corpus からテストを除外、または宣言位置での照合へ）
   — これを直さないと以降のラウンドで同じ形の取り残しが再発する
2. **H-2 / H-4**（公開契約の誤り。利用者側のコードが壊れる）
3. **H-3 / M-4 / M-6**（DoD が [x] としている項目に検証が無い、または検証が空回りしている）
4. **M-1 / M-2**（設計書の現行章と実装の一致）
5. **M-3 / M-5 / M-7**、その後 low
