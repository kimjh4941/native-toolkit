# レビュー結果

- 日付: 2026-09-02
- 対象ファイル: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v2.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- 参照設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 参照実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v14.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-sample-app-design-review.md`（v1 対象。高 1 / 中 9 / 低 3）

---

## 0. v1 指摘 13 件の反映状況（§0 対応表の検証）

対応表そのものを実装と突き合わせた結果を示す。表の記載は概ね正しいが、2 件は「反映したが実態は一部」である。

| v1 指摘 | §0 の主張 | 検証結果 |
|---|---|---|
| 高優先度 1（drag harness） | 消滅 | **正しい**。機能設計 v9 §2.1 で F-01〜F-10 が対象外、§13 の T-18 完了条件からも drag harness が消えている |
| M-1（OP-18 overload） | 消滅 | **正しい** |
| M-4（File Promise fixture） | 消滅 | **正しい** |
| L-2（受領ディレクトリ） | 消滅 | **正しい** |
| M-2（Observe lifecycle） | §6.4 に新設 | **解消**。`onDisappear` → `stopObserving()` が明記された |
| M-3（expect error の成功条件） | §6.3 に runner | **解消**（ただし §7.1 ST-03 が書けない問題は残る。中 4） |
| M-5（Detection 非決定性） | §6.2 / §6.1 | **解消**。arrange → act と固定 fixture が定義された |
| M-6（Active scope と OP-19） | §3.2 に明記 | **部分的**。OP-19 の除外は正しいが、OP-02 / OP-12 / OP-13 の分類が API と不一致（中 2） |
| M-7（throwing factory） | §5.4 に契約 | **部分的**。`Result` 保持の方針は正しいが生成タイミングが未定義（中 9） |
| M-8（自動テスト・a11y・再現コマンド） | §7 に新設 | **部分的**。テストが書けない（中 4）、再現コマンドが動かない（中 5） |
| M-9（秘匿方針） | §3.4 を実測で書き直し | **部分的**。`ClipboardLog` 実挙動の記述は正確だが、要件自体が達成不能（高 1） |
| L-1（`project.pbxproj` 不要） | §4.2 から削除 | **正しい**。`PBXFileSystemSynchronizedRootGroup` を 3 グループとも使用、テストターゲットも実在することを確認 |
| L-3（T-18 の参照節） | §13 に訂正 | **正しい**。v9 §13 に T-18 がある |

---

## 強み

- 公開 OP 16 件（OP-01〜OP-15 / OP-19）が `MacClipboardManager` に **実在することを確認済み**。`public func` の実カウントと §1.1 の表が完全に一致し、Unity ブリッジ側（`UnityMacClipboardManager`）は 15 操作で `makePasteButton` を持たないため、「Unity プラグイン経由でしか呼べない API はない」という §5.3 の判定も正しい。common.md「サンプルアプリの依存方向」に適合している。
- §1.3 のエラーコード範囲（1501〜1515 / 1521〜1524 / 1599、1516〜1520 欠番）が `ClipboardError.errorCode` の実装と完全に一致している。
- §3.4 の `ClipboardLog` 実挙動表（path は最終成分、file URL は basename、非 file URL は scheme+host、named/unique は短縮ハッシュ、text/data/json は長さのみ）は 4 行とも実装どおりで、v1 の推測混じりの記述から明確に改善している。
- §2.2 の既存規約抽出（`ShareSampleView.swift` 404 行、`TAG` / `resultText` / `sectionView` / `updateResult` / `FullWidthPressableButtonStyle` / `runXxx(label:) async`）が実ファイルと逐一一致しており、引き写しではなく実読に基づいている。
- §6.1 の期待エラーのうち、実装で検証できたものはすべて正しい。1501（`items: []` → `ClipboardContentValidator`）、1503（空 pattern → `DetectPatternsUseCase`）、1504（`UTType` 解決不能 → `PasteButtonFactory` の R11-H2 変更）、1508（`PasteboardResolver.isStandard`）、1511（ownership 照合）、1512（`matchingTypes: []` → `emptyTypeFilter`）、1523（`interval: 0` → `ClipboardChangeMonitor.start`）。
- §6.3 の 3 分岐（一致 / 成功してしまった / 別コード）を「成功してしまった場合も失敗」と定義したことで、v1 で衝突していた MS-01 と MS-02 の判定基準が分離された。
- §6.4 の `PasteButtonHost` の loader 行「View の deinit で cancelPaste（ライブラリ側の責務）」は `ClipboardPasteContainerView.deinit` → `coordinator.cancelPaste` の実装と一致している。
- 「named / unique は画面破棄時に解放しない（pasteboard server に残るのが正しい挙動）」という判断は `PasteboardScope` の DocC と一致し、意図的な非対応として明記されている。
- §10 で `detectMetadata` の 1515 期待を要検証として残し、要検証 2 を実測で解決済みに書き換えている点は、workflow の「直さない残件を理由つきで明記する」に沿っている。

## 改善点

### 高優先度

#### 高 1. §3.4 / MS-07 の秘匿要件が、ライブラリの実挙動と §3.3 の表示規約の両方と矛盾しており、達成できない

- 対象: §3.3、§3.4、§4.3、§6.1（セクション 1）、MS-07
- §3.4 は要件を「画面とログのどちらにも、クリップボードの値そのもの・完全パス・URL の query・**pasteboard 名**を出さない」と定義し、MS-07 がその手動確認になっている。しかし次の 3 経路で pasteboard 名が必ず出る。
  1. **ライブラリのログ**: `MacClipboardManager.createPasteboard(_:)` は `Log.d(TAG, "[createPasteboard] request: \(request)")`、`PasteboardResolver.create(_:)` は `Log.d(TAG, "[create] request: \(request)")` を出す。`PasteboardCreationRequest` は `Sendable, Equatable` な enum で `CustomStringConvertible` を持たないため、既定の文字列補間で `named("nt-sample")` がそのまま出力される。`Log` は `privacy: .public` で書くため秘匿されない。機能設計 §4.2「ペーストボード名は `general` はそのまま、名前付きは短縮ハッシュ」にも反している（本来 `ClipboardLog.scope` 相当を通すべき箇所）。
  2. **画面表示**: §3.3 が `errorCode=<Int>, errorMessage=<String>` を画面へ出す規約なのに、`cannotReleaseStandardPasteboard(name:)`（1508）の errorMessage は `Standard pasteboard cannot be released: <name>.` である。§6.1 の `RemoveGeneral` ボタンはこの 1508 を期待する設計であり、**押した瞬間に MS-07 が破れる**。同様に `invalidPasteboardName(_:)`（1505）、`pasteboardUnavailable(name:)`（1507）も名前を含む。
  3. §4.3 が「`MacLibrary` の一切」を非変更と宣言しているため、サンプル側の実装だけでは 1 を回避できない。
- 何が起きるか: T-18 実装後に MS-07 を実施すると必ず不合格になる。実装者は「ライブラリを直すか、要件を書き換えるか」の判断を T-18 の途中で迫られ、§4.3 の非変更宣言と衝突する。
- 提案: 次のいずれかを計画に確定させる。
  - MS-07 の対象を「**サンプルが出力する画面文字列とサンプル自身のログ**」に限定し、(a) `createPasteboard` の 2 箇所のライブラリログ、(b) 1505 / 1507 / 1508 の errorMessage を、既知の例外として §3.4 に列挙する。加えてサンプルの pasteboard 名を機密性のない固定値（`nt-sample`）に限る旨を書く。
  - または `MacClipboardManager.createPasteboard` / `PasteboardResolver.create` のログを `ClipboardLog` 経由に直す小修正を T-18 の前提タスクとして §9 に追加し、§4.3 の非変更宣言をその分だけ緩める（機能設計 §4.2 との整合という観点では、こちらが本筋）。

#### 高 2. ST-05 は「T-18 完了条件の機械的な検査」になっていない

- 対象: §7.1（ST-05）、§3.1、§9（手順 7）
- §7.1 は ST-05 を「セクション定義が公開 OP 16 件をすべて含む（§3.1 の対応表を機械照合）」と定義し、「**ST-05 が T-18 完了条件の機械的な検査である**」と断言している。
- しかし T-18 の完了条件は「全公開 OP が `MacLibraryExample` から **Unity 非依存で実行できること**」である。ST-05 が照合するのは「サンプルが手書きで宣言したセクション → OP の注釈表」と「テストが手書きで持つ 16 件のリスト」であり、**その注釈表と、ボタンが実際に呼ぶ API との対応は誰も検査しない**。注釈だけ書いてボタンを実装し忘れる、あるいはボタンが別の OP を呼ぶ、という最も起きやすい欠落が素通りする。Swift には公開 API の実行時列挙がないため、`MacClipboardManager` 側と自動照合することもできない。
- 何が起きるか: ST-05 が緑のまま T-18 が完了扱いになり、実際には呼ばれていない OP が残る。過去に本リポジトリで繰り返された「反映したと書いてあるが実態は一部」と同じ構造の失敗である。
- 提案: 注釈と呼び出しが分離できない形にする。たとえば
  - `enum SampleOperation: String, CaseIterable`（`case copy = "OP-01"` …）を定義し、各 case が「セクション」「ボタンラベル」「accessibility identifier」「**実際の呼び出しクロージャ**」を持つ 1 個の値を返す。
  - 画面はその値から生成する（ボタンを手書きしない）。
  - ST-05 は `SampleOperation.allCases` の OP id 集合が 16 件と一致することを検査する。これなら注釈だけ足してボタンを忘れる経路が消える。
  - あわせて `UnityMacPlugin` import 0 件（§7.4）も文言検査ではなく `grep -r "import UnityMacPlugin" mac/MacLibraryExample` を §7.3 の再現コマンドに入れる。現状 §7.4 の合格条件のうち、これだけ検査手段が定義されていない。

### 中優先度

#### 中 1. §1.2 の同期分類が `throws` を落としており、同期 throws 用の実行経路が §6 にない

- 対象: §1.2、§6.1（セクション 5 / 7 / 8）
- §1.2 は「OP-12〜OP-15 / OP-19 は同期」とだけ書き、throw するのは OP-19 のみという書き方になっている。実装は次のとおり。
  - OP-12 `accessBehavior(scope:) throws -> ClipboardAccessBehavior`
  - OP-13 `startObserving(scope:interval:onEvent:) throws`
  - OP-14 `stopObserving()`（**非 throwing はこれだけ**）
  - OP-15 `checkForegroundChange(scope:) throws -> Bool`
  - OP-19 `makePasteButton(...) throws -> NSView`
- 機能設計 §8.1 の署名列にも `throws` があり、v2 はその情報だけを落としている。
- §6.1 が定義する実行ラッパーは `run(label:)`（`Task` で包む async）と `runExpectingError(label:expected:_ body: () async throws -> Void)` の 2 つだけで、`AccessBehavior` / `CheckForegroundChange` 行には「同期」としか書かれておらず、失敗時に何を表示するかの規約がない。
- 何が起きるか: 実装者が同期 API を `do/catch` なしで書けばコンパイルエラー、`try?` で握り潰せば MS-01「Result が必ず更新される」が破れる。実行経路が 2 種類のまま第 3 の書き方が現場判断で増える。
- 提案: §1.2 の一覧に throws を明記し、同期 throws を `run` と同じ表示規約へ落とす経路（`runSync(label:) -> Void` か、`run` に非 async クロージャを渡す規約）を §6 に 1 つだけ定義する。

#### 中 2. §3.2 の Active scope 分類が実 API と一致しておらず、MS-03 の判定基準が定まらない

- 対象: §3.2、§6.1（セクション 4 / 5 / 7）、MS-03
- §3.2 は「効く: OP-01〜OP-11、OP-15」「効かない: OP-19。OP-12 / OP-13 / OP-14 は §6 のとおり個別に扱う」としているが、
  - **OP-02 `append(_:ownership:)` は `scope` 引数を持たない**。対象は `PasteboardOwnership.scope` で決まるため、Active scope は直接は効かない（直前の copy 経由で間接的に決まる）。「効く」列にあるのは誤り。
  - **OP-12 `accessBehavior(scope:)` と OP-13 `startObserving(scope:...)` は `scope` 引数を持つ**。§3.2 自身の基準「`scope` 引数を持つ操作だけ効く」に照らせば「効く」側であり、「個別に扱う」に落とすなら理由が要る。
  - しかも「§6 のとおり個別に扱う」の **§6 に該当する記述がない**（§6.1 の AccessBehavior / Observe 行はどの scope を使うか書いていない）。未解決の前方参照になっている。
- 何が起きるか: 実装者は OP-02 で Active scope を渡そうとしてコンパイルエラーに気づくが、OP-12 / OP-13 は黙って general 固定になる可能性がある。その状態で MS-03「Active scope の切り替えが `scope` 引数を持つ操作に反映される」を実施すると、判定が人によって割れる。v1 の M-6 と同種の指摘が 2 回目である。
- 提案: 表を実 API の引数で機械的に引き直す。効く = OP-01、OP-03〜OP-13、OP-15（scope 引数あり。OP-13 は開始時の scope を決める）。効かない = OP-02（ownership 由来）、OP-14（引数なし）、OP-19（general 固定）。§6.1 の Observe 行に「Active scope で開始する」と明記する。

#### 中 3. `MacClipboardManager` のインスタンス方針が未定義

- 対象: §5.1、§6.1 全体、§6.4、MS-05
- 計画は一度も「どのインスタンスを使うか」を書いていない。実装には `MacClipboardManager.shared` があり、同時に `public convenience init(limits:)` も公開されている。
- 重要なのは、次がすべて**インスタンス状態**であること。
  - `monitor`（OP-13 / OP-14 の監視。`stopObserving()` は同じインスタンスに対してしか効かない）
  - `useCases.changeTracker`（OP-15 と監視が共有する既読 changeCount）
  - `coordinator.pasteLoaders`（OP-19 の loader 登録）
- 何が起きるか: SwiftUI の `body` 中や各操作関数の中で `MacClipboardManager()` を作る実装になると、`onDisappear` の `stopObserving()` が別インスタンスに向かい MS-05 が落ちる。`let manager = MacClipboardManager()` をプロパティ初期値に書いた場合も、View struct が再生成されるたびに新しいグラフができうる。
- 提案: 「画面全体で単一の `MacClipboardManager`（`shared` または `@State private var manager = MacClipboardManager()` のいずれか）を使う」と §5.1 に明記する。加えて、OP-15 と OP-13 が tracker を共有するため、監視中は `CheckForegroundChange` が `false` を返しやすいことを §6.1 の注記に入れておくと手動確認の誤判定を防げる。

#### 中 4. §7.1 の ST-03 / ST-04 は、現在の §6.3 / §4.1 の契約のままでは書けない

- 対象: §7.1（ST-03 / ST-04）、§6.3、§4.1
- ST-03 は「`runExpectingError` が 3 分岐を正しく判定する」だが、§6.3 の署名は `func runExpectingError(label:expected:_ body:) async` で戻り値がなく、結果は `updateResult` 経由で `@State` に書かれる。テストから 3 分岐を観測する手段がない。
- ST-04 は「結果 formatter が値・完全パス・query・pasteboard 名を含まない」だが、§4.1 は `updateResult` を support ファイルに置くとしつつ、§2.2 / §5.1 では既存 `ShareSampleView` と同じ「View の private メソッドで `@State` を書き換える」パターンだとしている。純粋関数としての formatter が定義されていない。
- さらに、既存サンプルの慣習は `private`（`FullWidthPressableButtonStyle` も private）である。テストターゲットは Swift Testing + `@testable import MacLibraryExample` だが、`private` のままでは `@testable` でも見えない。計画にはテストフレームワークの指定も可視性の指定もない。
- 何が起きるか: 実装終盤で ST-03 / ST-04 が書けないことに気づき、テストを削るか、テストのために設計を作り直すかになる。
- 提案: (a) 判定を `enum ExpectedErrorOutcome { case matched, unexpectedSuccess, otherCode(Int) }` として純粋関数に切り出し、`runExpectingError` はそれを呼んで表示するだけにする。(b) 表示文字列を作る部分を `ClipboardSampleFormatter`（純粋関数）として分離し、`updateResult` は formatter の結果を `@State` に入れるだけにする。(c) fixtures / formatter / outcome は `internal` とし、§7.1 に「Swift Testing、`@testable import MacLibraryExample`」を明記する。

#### 中 5. §7.3 の再現コマンドは、この環境以外では動かない

- 対象: §7.3、§4.1、§4.2
- `xcodebuild ... -scheme MacLibraryExample` を前提にしているが、`MacLibraryExample.xcodeproj` に **共有 scheme が存在しない**。git が追跡しているのは `xcuserdata/jonghyunkim.xcuserdatad/xcschemes/xcschememanagement.plist` だけで、`xcshareddata/xcschemes/` 配下に `MacLibraryExample.xcscheme` はない。共有 scheme があるのは `MacLibrary` / `UnityMacPlugin`（および iOS 側の `IosLibraryExample`）である。
- 実装結果 v14 の再現コマンドが `-scheme MacLibrary` / `-scheme UnityMacPlugin` しか使っていないのは、この差のためと考えられる。
- 何が起きるか: 別マシンや CI で `Scheme MacLibraryExample is not currently configured for the test action` あるいは scheme not found になり、§7.4 の合格条件を再現できない。
- 提案: `MacLibraryExample` scheme を共有化し（Test action に `MacLibraryExampleTests` を含める）、生成される `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/xcschemes/MacLibraryExample.xcscheme` を §4.1 の新規作成ファイルに追加する。§7.3 の `xcresulttool` も `-resultBundlePath` を指定した形に直す（現状 `<*.xcresult>` がどこに出るか書かれていない）。

#### 中 6. サンプルで到達させるエラーコードの網羅方針がない

- 対象: §3.1（セクション 10）、§6.1、§1.3
- §3.1 のセクション 10 は「到達済みエラーコードの一覧」を表示するとあるだけで、**20 ケースあるエラー契約のうちどれをサンプルで到達させるか**の対応表がない。§6.1 の `(expect error)` は 1501 / 1503 / 1504 / 1508 / 1511 / 1512 / 1515 / 1523 の 8 件である。
- 簡単に到達できるのに操作がないもの: 1502 `emptyRepresentations(itemIndex:)`（`representations: [:]` の item を含む copy）、1505 `invalidPasteboardName`（`createPasteboard(.named(""))`）、1506 `contentTooLarge`（`ClipboardLimits.default` は 100 MiB / 200 MiB のため実用的でないなら「到達不可」と書けばよい）。
- 到達させないもの: 1507 / 1509 / 1510 / 1513（OS 依存）/ 1514（ユーザー操作依存）/ 1521 / 1522 / 1524 / 1599。
- 何が起きるか: 「エラー契約が公開 API 仕様どおりか」をサンプルで確認できる範囲が実装者の裁量になり、レビューでも網羅性を判定できない。
- 提案: §1.3 の直後か §3.1 セクション 10 に「20 ケース × 到達手段 / 到達不可の理由」の表を置き、到達可能なものは §6.1 にボタンを足す。

#### 中 7. 機能設計からの申し送り U-05〜U-07 が計画に現れない

- 対象: §1.1、§3.1、機能設計 v9 §2.1
- 機能設計 §2.1 は `U-05`〜`U-07`（`copyable` / `cuttable` / `pasteDestination`）を「**対象外。SwiftUI View modifier でありライブラリが提供する形にならない。サンプルアプリ側で直接使うべき API として `design-sample-app` へ申し送る**」と明記している。
- v2 はこの申し送りに一言も触れていない。
- 何が起きるか: 機能設計側で「サンプルへ渡した」と記録された項目が、どちらの文書にも残らないまま消える。過去に本リポジトリで繰り返された「反映したと書いてあるが実態は一部」と同じ抜け方である。
- 提案: 採用するなら Paste Control セクションに `copyable` / `pasteDestination` のデモを 1 つ足す。採用しないなら §1.4 か §10 に「ライブラリ検証が目的の本サンプルでは扱わない」と理由つきで記録する。どちらでもよいが、無言は不可。

#### 中 8. MT-06（部分失敗表示）を再現する手順がない

- 対象: §8.1（MT-06）、§6.1（セクション 8）、§6.2
- §8.1 は MT-06 を「Paste Control から貼り付け。部分失敗表示」「実施可」としているが、`ClipboardPasteResult.isPartial` は `!items.isEmpty && !failures.isEmpty` であり、**成功する provider と失敗する provider が同時に必要**である。File Promise が範囲外になった今、失敗する provider を外部アプリ由来で用意するのは現実的でない。
- 実装を読む限り、サンプル内で作れる。`ClipboardPasteLoader` は accepted type をどれも供給できない provider に `pasteLoadFailed("no accepted type available")` を付けるので、item 1 に `public.utf8-plain-text`、item 2 に `com.mycompany.myformat` だけを持たせた複数 item をコピーしてから貼り付ければ partial になる（`com.mycompany.myformat` は `ClipboardTypeIdentifierValidator` を通るが `UTType` を持たないため accepted types には入れられない、という性質をそのまま使える）。
- 何が起きるか: 手動確認の段階で「部分失敗を作れない」と分かり、MT-06 が未実施のまま残る。
- 提案: §6.2 に `partialPasteFixture`（上記の 2 item）を追加し、§6.1 セクション 8 に「`CopyPartialPasteFixture` → Paste Control で貼り付け」の導線を書く。

#### 中 9. `PasteButtonHost` 用 `NSView` の生成タイミングが未定義で、loader 登録が漏れ増えする

- 対象: §5.4、§6.4、MS-06
- §5.4 は「生成は `ClipboardSampleView` 側で行い、`Result<NSView, Error>` として保持する」とあるが、**いつ生成するか**がない。`makePasteButton` は純粋な factory ではなく、`coordinator.registerPasteLoader(loader)` という副作用を持ち、登録の解除は返された `NSView` の `deinit` でしか起きない。
- 何が起きるか: `@State private var host: Result<NSView, Error> = ...` のように初期値式で生成すると、SwiftUI が View struct を再生成するたびに `makePasteButton` が走り、採用されなかった `NSView` が解放されるまで `pasteLoaders` に登録が残る。また `Result` が唯一の強参照でないと、`PasteButtonHost` を画面から外しても loader が生き続け、MS-06「View 破棄で進行中の load がキャンセルされる」が観測できない。
- 提案: §5.4 に次を追加する。(a) 生成は `.task` か `.onAppear` の 1 回に限る（`@State` の初期値式では作らない）。(b) 保持した `Result` の `.success` 値が唯一の強参照であり、それを `nil` にすることが破棄の手段である。(c) MS-06 の手順を「Paste Control を押して load 中に画面を離れる（= `Result` が解放される）」と具体化する。

### 低優先度

#### 低 1. 「macOS 15.4 未満では全操作が 1513」は `DetectEmptyPatterns` に当てはまらない

- 対象: §6.1（セクション 6 の末尾）、§8.1（MT-07）
- `DetectPatternsUseCase` / `DetectValuesUseCase` は空集合チェック（1503）を先に行い、可用性チェック（1513）は `ClipboardRepositoryImpl` 側にある。したがって macOS 15.2 でも `DetectEmptyPatterns` は **1503** を返す。
- MT-07 は 15.2 環境で「Detect 各種」を確認する項目なので、期待値表がずれる。「空集合チェックは可用性より先。よって `DetectEmptyPatterns` は 15.4 未満でも 1503」と 1 行足せばよい。

#### 低 2. §3.4 の `ClipboardLog` 表が不完全

- 対象: §3.4
- 実装の `ClipboardLog` は 8 メンバー（`text` / `data` / `url` / `path` / `scope` / `content` / `types` / `scopeJson`）。表にあるのは 4 行分で、`content`（件数とバイト数）、`types`（**UTI は verbatim**）、`scopeJson` が漏れている。
- また File Promise 除外によりサンプルはファイルパスを扱わなくなったため、`path` / `url` 行は実質使わない。使う予定があるなら（`url` フィクスチャの表示など）どこで使うかを書き、ないなら表から落とすほうが正確である。

#### 低 3. 機械照合の扱いが書かれていない

- 対象: §7
- 参考として `python3 scripts/check_design_consistency.py <本計画>` を実行したところ、OK 4 / FAIL 2 / 残り SKIP だった。FAIL 2 件はいずれも**誤検知**である。
  - `named symbols exist in the implementation`: `ClipboardSampleView` / `PasteButtonHost` / `ClipboardSampleFixtures` は**これから作るファイル**なので実装にないのが正しい。`PBXFileSystemSynchronizedRootGroup` は `.pbxproj` にあるが走査対象外。
  - `referenced IDs exist in their tables`: §1.1 の OP 表が 1 行に 2 OP（`OP-01 copy / OP-02 append`）を書いているためパーサが拾えない。
- 現状この文書には機械照合の位置づけがない。「サンプルアプリ計画書は本スクリプトの対象外」と §7 に明記するか、§1.1 を 1 行 1 OP に直して ID 検査だけ通すか、どちらかを決めるとよい。実装結果 v14 の再現コマンドには機械照合が入っているので、入れないなら理由を書くほうが揃う。

#### 低 4. `PasteButtonHost` の寸法規約がない（要検証）

- 対象: §5.4、§6.1（セクション 8）
- `makePasteButton` が返すのは `ClipboardPasteContainerView(frame: .zero)` で、内部の `NSHostingView` を四辺 anchor で固定している。自前の `intrinsicContentSize` は実装していない。
- `NSViewRepresentable` を SwiftUI の `VStack` に置いたとき、この構造で期待どおりの高さになるかは未検証である。潰れる場合は `.frame(height:)` か `sizeThatFits` の実装が要る。§10 の要検証に 1 行足しておくのが安全である。

#### 低 5. 既存 UI テストの扱いが §7.4 にない

- 対象: §7.2、§7.4
- `mac/MacLibraryExample/MacLibraryExampleUITests/` には `ShareSampleViewUITests.swift`（235 行）と launch テストが既にある。§7.3 の `xcodebuild clean test` を scheme に対して流せばこれらも動く。
- §7.4 の合格条件は「ST-01〜ST-05 全通過」しか書いていない。既存 UI テストも通ることを合格条件に含めるか、テストプランで分けるかを明記する。「Clipboard の UI テストは書かない」判断自体は理由つきで書かれており妥当である。

#### 低 6. §1.2「`.general` と標準名 5 種」は二重に数えている

- 対象: §1.2
- 実装の `PasteboardResolver.standardNames` は general / font / ruler / find / drag の **5 件で、general を含む**。`isStandard` は `.general` case も無条件に true にする。「`.general` と標準名 5 種」だと 6 種に読める。「標準名 5 種（`general` を含む）」が正しい。

#### 低 7. named / unique ペーストボードに対する Detect の可否が要検証に入っていない

- 対象: §3.2、§10
- §3.2 は OP-09〜OP-11 に Active scope が効くとしており、Picker で named / unique を選んだまま Detect を押せる。実装は `PasteboardResolver.resolve` した `NSPasteboard` に対して検出 API を呼ぶが、system の data detection が general 以外のペーストボードで機能するかは実装にも設計にも記録がない。
- §10 に要検証として 1 行足し、機能しない場合の期待（1515 か空結果か）を実測で埋めるとよい。

#### 低 8. `StartObservingInvalidInterval` 失敗時の状態遷移が未定義

- 対象: §6.1（セクション 7）、§6.4
- `ClipboardChangeMonitor.start` は interval ガードを最初に評価するため、`interval: 0` で throw しても**既存の監視は動き続ける**（manager の DocC も「解決できない scope の場合は既存の観測を残したまま throw する」と述べている）。
- §6.4 の lifecycle 表は `observationActive` の開始条件を「`StartObserving` 成功」としか書いていない。「`StartObservingInvalidInterval` が失敗しても `observationActive` は変えない」と明記しておくと、MS-05 の判定がぶれない。

## 不足項目

- MS-07 が許容する既知の例外（ライブラリ側 `createPasteboard` のログ、1505 / 1507 / 1508 の errorMessage）の列挙、またはライブラリ側ログ修正の前提タスク化
- OP 注釈とボタンの実呼び出しが分離しない構造（`SampleOperation` 相当）と、それを前提にした ST-05 の再定義
- `UnityMacPlugin` import 0 件（§7.4）の検査コマンド
- 同期 `throws`（OP-12 / OP-13 / OP-15）用の実行・表示経路
- `MacClipboardManager` のインスタンス方針（`shared` か画面所有か）
- `runExpectingError` の判定結果を表す純粋な型と、表示文字列を作る純粋な formatter、およびそれらの可視性（`internal`）とテストフレームワーク（Swift Testing / `@testable`）の明記
- `MacLibraryExample` の共有 scheme と、それを §4.1 の新規作成ファイルへ追加すること
- エラーコード 20 ケース × 到達手段 / 到達不可理由の対応表
- 機能設計 §2.1 の申し送り U-05〜U-07 の採否
- MT-06 の部分失敗を作る fixture（accepted types に無い型だけを持つ item を含む複数 item）
- `PasteButtonHost` の生成タイミングと、`Result` が唯一の強参照である旨
- named / unique ペーストボードに対する Detect の可否（要検証）
- 本計画に対する機械照合の適用可否

## 総合評価

v1 の 13 件は、File Promise 除外で消滅した 4 件を除く 9 件すべてに手が入っており、`ClipboardLog` の実挙動調査（§3.4）、期待エラー専用 runner（§6.3）、決定的 fixture（§6.2）、lifecycle 表（§6.4）は、実装を読んで書かれたことが確認できる水準である。§1.1 の公開 OP 16 件、§1.3 のエラーコード範囲、§2.2 の既存サンプル規約、§5.3 の依存方向判定（common.md 準拠）は、いずれも実コードと突き合わせて一致した。**v1 のような「そもそも実装できない」構造的欠陥はもう残っていない。**

一方で、workflow の止める基準でいう **A 区分（この記述のまま実装すると成果物が変わる）が 2 件残っている**。1 つは秘匿要件（高 1）で、MS-07 は現在の §3.3 / §4.3 と組み合わせると必ず不合格になる。もう 1 つは ST-05（高 2）で、T-18 の完了条件を機械的に検査していると謳いながら、実際には手書き注釈どうしの照合にしかなっていない。中優先度のうち中 1 / 中 2 / 中 3 / 中 9 も、実装者が現場判断で埋めることになる契約の穴である。

指摘の傾向として、v1 の M-6（Active scope の分類ミス）と同型の誤りが中 2 で再発し、v1 の M-9（秘匿方針と実挙動の不一致）も高 1 として形を変えて残っている。個別に直すだけでは同じ場所がまた壊れる可能性が高いため、**§1.2 の同期／throws 分類と §3.2 の scope 分類は、文章ではなく `MacClipboardManager` の実シグネチャから引き写した 1 行 1 OP の表**に置き換えることを勧める（それは低 3 の機械照合を通す前提にもなる）。

高 2 件と中 1 / 中 2 / 中 3 / 中 9 を反映すれば、T-18 は着手可能である。中 5 / 中 6 / 中 7 / 中 8 と低優先度は、記録として残せば実装と並行して埋めてよい。
