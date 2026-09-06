# レビュー結果（範囲を絞ったレビュー）

- 日付: 2026-09-02
- 対象ファイル: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v3.md`
- 前版: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v2.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-sample-app-design-review-v2.md`（高 2 / 中 9 / 低 8 = 19 件）
- 併せて確認したライブラリ側修正: `ClipboardLog.request(_:)` と `ClipboardLogAuditTests.swift`
- レビュー範囲: 依頼どおり (1) 前回指摘の解消状況、(2) v3 で書き直した節の新規欠陥、(3) `ClipboardLog.request` 修正の 3 点のみ。§2 / §4 / §6.1 / §6.3 / §6.4 / §6.5 / §7.2 / §7.3 / §8 / §9 / §10 は変更なしのため通読のみ。

## 検証環境

| 検査 | 結果 |
|---|---|
| `python3 scripts/check_design_consistency.py <v3>` | OK 6 / FAIL 0 / 残り SKIP |
| `xcodebuild clean test -scheme MacLibrary` | **宣言 307 / 実行 351 / 失敗 0**（申告値と一致） |
| ビルド警告 | 2 件（いずれも Clipboard 由来ではない） |

**ただし FAIL 0 は、`scripts/check_design_consistency.py` が本レビュー期間中に変更され、`named symbols exist in the implementation` がサンプル計画書に対して SKIP されるようになった結果である**（M-7 を参照）。

---

## 0. 前回指摘 19 件の解消状況

依頼文は「13 件」とあるが、前回レビュー v2 の指摘は **高 2 / 中 9 / 低 8 = 19 件**である。13 件は v1 レビュー（§0.1 の表）の件数であり、v3 の §0 が扱っているのは v2 の 19 件のほうである。以下は 19 件すべてについて、**§0 の自己申告ではなく v3 の本文と実コードを突き合わせた結果**である。

| v2 指摘 | §0 の主張 | 実態 | 判定 |
|---|---|---|---|
| **高 1** 秘匿要件が達成不能（3 経路） | ライブラリ側を修正し解決 | 経路 1（ライブラリログ）のみ解消。**経路 2（§3.3 が `errorMessage` を画面に出す規約 × 1505 / 1507 / 1508 の名前入りメッセージ）と経路 3（§4.3 の非変更宣言）は手つかず** | **一部** |
| **高 2** ST-05 が機械的検査でない | §7.1 で実コード導出へ再設計 | 導出方式そのものは成立する（左辺抽出を実測: 16 件ちょうど取れる）。ただし右辺の走査対象・パス解決・コメント誤検出が未定義（M-3） | **解消**（新欠陥あり） |
| **中 1** §1.2 が `throws` を落とす | 実シグネチャから表に置換 | 表は**完全に正しい**（実コードと 16 行すべて一致）。ただし指摘の後半「同期 `throws` 用の実行・表示経路を §6 に 1 つ定義する」は未対応 | **一部** |
| **中 2** §3.2 の scope 分類が API と不一致 | §1.2 の表から導出 | **正しい**。効く 12 / 効かない 4 が実シグネチャと一致 | **解消** |
| **中 3** インスタンス方針が未定義 | §5.5 に明記 | `shared` 固定と、その帰結（監視・変更追跡・loader 登録）が書かれている | **解消** |
| **中 4** ST-03 / ST-04 が書けない | §7.1 で書ける形に再定義 | (b) formatter の純粋関数化は解消。**(a) `runExpectingError` の 3 分岐は依然テスト不能（ST-03 が formatter 検査に差し替わり、3 分岐の検査が消えた）。(c) 可視性（`internal`）とテストフレームワーク（Swift Testing / `@testable`）の明記は未対応** | **一部** |
| **中 5** 再現コマンドが動かない | §7.3 に前提として明記 | 前提の明記は解消（実測: `xcshareddata/xcschemes/` は存在しない）。**`.xcscheme` を §4.1 の新規作成ファイルへ追加する件と `-resultBundlePath` 指定は未対応** | **一部** |
| **中 6** エラー到達方針がない | §6.6 に分類を追加 | 表は追加されたが**分類が誤っている**（1502 / 1505 は到達容易、1521 は §6.2 と矛盾）。指摘が名指しした 1502 / 1505 がそのまま「到達手段なし」に入っている | **一部** |
| **中 7** U-05〜U-07 が計画に不在 | §1.5 に理由を明記 | 内容は解消（実際の節番号は **§1.4**。§0 の参照が誤り） | **解消** |
| **中 8** MT-06 の部分失敗 fixture がない | §6.2 に追加 | fixture 名は追加されたが、**§6.1 セクション 8 に導線（`CopyPartialPasteFixture` ボタン）がなく、コピーする手段がない**。§6.6 とも矛盾 | **一部** |
| **中 9** `PasteButtonHost` の生成タイミング未定義 | §5.4 に明記 | 生成タイミング（`onAppear` 1 回・`@State`）は解消。**(b) `Result` が唯一の強参照である旨、(c) MS-06 手順の具体化は未対応**。加えて §5.4 が MS-06 を「MS-05」と誤記 | **一部** |
| **低 1** 15.4 未満でも `DetectEmptyPatterns` は 1503 | 「§7.4 に注記」 | §6.1 セクション 6 は「macOS 15.4 未満では全操作が 1513」のまま | **未対応** |
| **低 2** §3.4 の `ClipboardLog` 表が不完全 | 同上 | 表は 4 行のまま。`content` / `types` / `scopeJson`、および今回追加した `request` が漏れている | **未対応** |
| **低 3** 機械照合の扱いが未記載 | 同上 | §7 に記載なし。代わりにスクリプト側を無断で緩めている（M-7） | **未対応** |
| **低 4** `PasteButtonHost` の寸法規約（要検証） | 同上 | §5.4 にも §10 にも記載なし | **未対応** |
| **低 5** 既存 UI テストの扱い | 同上 | §7.4 は「ST-01〜ST-05 全通過」のみ | **未対応** |
| **低 6** 「`.general` と標準名 5 種」の二重数え | 同上 | **書き直した §1.2.1 に同じ表現がそのまま再登場**（実装 `PasteboardResolver.standardNames` は general を含む 5 件） | **未対応** |
| **低 7** named / unique への Detect の可否 | 同上 | §10 に行なし | **未対応** |
| **低 8** `StartObservingInvalidInterval` 失敗時の状態遷移 | 同上 | §6.4 の lifecycle 表は変更なし | **未対応** |

**集計: 解消 4 / 一部 7 / 未対応 8。**

### 自己申告との差分

- §0 の表は「低 3 件 | §7.4 に注記」と書いているが、**v2 の低優先度は 8 件であり、§7.4 に注記は 1 行もない。低 8 件は 1 件も反映されていない。**
- 高 1 の行は「サンプル計画ではなく機能側の不具合だった」と結論しているが、v2 高 1 は**経路を 3 つ挙げており、ライブラリログはそのうちの 1 つ**である。残る 2 経路（画面表示・§4.3）は v3 でも未処理のままで、この行の書き方では解消済みに読める。
- 中優先度 9 件のうち、指摘全体が解消したのは中 2 / 中 3 / 中 7 の 3 件。残り 6 件は「指摘の前半だけ直して後半が残っている」形である。
- 過去 2 回と同種の傾向（自己申告が実態より進んでいる）が**3 回連続で再現**している。今回は特に、低優先度をまとめて 1 行に圧縮したうえで件数を 8 → 3 に取り違えている点が新しい。

---

## 1. 高優先度

### 高 1. §3.4 / MS-07 は依然として必ず不合格になる（前回 高 1 の残り 2 経路）

- 対象: §3.3、§3.4、§4.3、§6.1（セクション 1）、§7.1（ST-04）、MS-07
- ライブラリログ（経路 1）は確かに塞がった。しかし §3.4 の要件文は **v2 から一字も変わっていない**。

  > 画面とログのどちらにも、クリップボードの値そのもの・完全パス・URL の query・**pasteboard 名**を出さない。

  一方 §3.3 は画面表示の規約を `errorCode=<Int>, errorMessage=<String>` と定めており、実装の `ClipboardError.errorMessage` は次の 3 ケースで pasteboard 名を含む（`ClipboardError.swift` 99 / 104 / 106 行）。
  - 1505 `invalidPasteboardName` → `Invalid pasteboard name: <value>.`
  - 1507 `pasteboardUnavailable` → `Pasteboard is unavailable: <name>.`
  - 1508 `cannotReleaseStandardPasteboard` → `Standard pasteboard cannot be released: <name>.`
- §6.1 セクション 1 の `RemoveGeneral` は **1508 を期待する設計**である。つまり計画どおり実装して計画どおりボタンを押すと、画面に `Standard pasteboard cannot be released: general.` が出る。
- v3 はここに **ST-04** を新設し、「formatter の出力が、値・完全パス・query・**pasteboard 名**を含まない」を自動検査すると宣言した。`SampleOutcome.clipboardFailure(label:code:message:)` の `displayText` は §3.3 の規約上 `message` を含まざるを得ないため、**機微な `message` を与えれば ST-04 は必ず落ちる**。§7.1 は「`logText` が payload を含まないことは ST-04 が保証する」とも書いており、ST-04 が `displayText` と `logText` のどちらを対象にするのかも確定していない。
- 何が起きるか: v2 レビューが予告したとおり、実装者は T-18 の途中で「§3.4 を書き換えるか、§3.3 を書き換えるか、`RemoveGeneral` を捨てるか」の判断を迫られる。今回はそこに ST-04 という自動テストが加わったため、**手動確認（MS-07）だけでなく CI も赤くなる**。
- 併せて §4.3 は今も「`MacLibrary` / `UnityMacPlugin` の一切」を非変更と宣言しているが、§0 は同じ文書内でライブラリを変更したと述べている（低 8）。
- 必要な対応: §3.4 の要件を「**サンプルが自分で組み立てる文字列**が対象。ライブラリ由来の `errorMessage` に含まれる標準 pasteboard 名（1505 / 1507 / 1508）は既知の例外」と限定し、ST-04 の対象を `logText` と `SampleOutcome.success` / `otherFailure` の `displayText` に絞る。あるいは §3.3 を「`errorMessage` は `logText` に出さず、画面のみ」と分ける。どちらでもよいが、**実装前に決める必要がある**。

### 高 2. `ClipboardLogAuditTests` の行フィルタが、まさに検査対象の欠陥で無効化される

- 対象: `mac/MacLibrary/MacLibraryTests/Clipboard/ClipboardLogAuditTests.swift`（`interpolations()`）
- 監査は次の行だけを見る。

  ```swift
  for (offset, line) in lines.enumerated() where line.contains("Log.") {
  ```

- ところが本リポジトリの log 文は 2 行に折られており、**継続行は `Log.` を含まない**。継続行が監査に入っているのは、そこに `ClipboardLog.` という文字列がたまたま含まれているからにすぎない。

  ```swift
  Log.d(TAG, "[copy] content: \(ClipboardLog.content(content)), "
        + "localOnly: \(options.localOnly), scope: \(ClipboardLog.scope(scope))")   // ← "Log." を含むのは "ClipboardLog." のおかげ
  ```

  この 2 行目を `scope: \(scope)` に書き換える（＝ R-S2-H1 とまったく同じ壊し方をする）と、行から `ClipboardLog.` が消え、**行そのものが監査対象から外れて漏れが見えなくなる**。監査が探している欠陥を作った瞬間に監査が目を閉じる構造である。
- 実測: 監査対象ツリーで**この形の継続行が 16 行**ある（`MacClipboardManager` 9、`ClipboardRepositoryImpl` 4、`AppendContentUseCase` / `GetSnapshotUseCase` / `CopyContentUseCase` 各 1）。うち 13 行は `ClipboardLog.scope(...)`、すなわち **pasteboard 名の秘匿そのもの**を担っている行である。
- さらに、`Log.` を含まない継続行はもとから完全な死角である。実測で**監査対象ツリーの補間 179 件中 37 件が `Log.` を含まない行にあり、うち 6 件は生きた log 文の継続行**である。
  - `MacClipboardManager.swift:547` → `+ "timeout: \(timeout)")`
  - `ClipboardContentValidator.swift:68` → `+ "\(identifier), bytes: \(bytes), warn: \(...)")`
  - `PasteButtonFactory.swift:80`、`ClipboardPasteLoader.swift:68` / `:173`
  現状これらは無害だが、**この位置に何を書いても監査は通る**。
- 何が起きるか: 「MacLibrary 側に監査を新設したので R-S2-H1 型の漏れは再発しない」という §0 の結論が成り立たない。BT-25 が 3 ラウンド空回りしたのと同じ失敗をこの監査も持っている。
- 必要な対応: 行単位ではなく**文単位**で走査する。最小の直し方は、継続行（直前の行が `,` / `+` / `"` で終わる、あるいはインデント継続）を直前の `Log.` 行に連結してから補間を抽出すること。もしくは `Log.` 判定を「行に `Log.d(` / `Log.e(` があるか、または直前が未閉じ」に変える。

---

## 2. 中優先度

### 中 1. §6.6 のエラー到達可能性の分類が誤っており、前回 中 6 の指摘対象がそのまま残っている

- 対象: §6.6、§6.2、§6.5、§3.1（セクション 10）、MS-02
- v2 レビュー中 6 は「簡単に到達できるのに操作がないもの」として **1502 と 1505 を名指し**した。v3 の §6.6 は、その 1502 / 1505 を「**到達手段なし（10）**」に入れている。実装では両方とも 1 行で到達できる。
  - 1502 `emptyRepresentations(itemIndex:)`: `ClipboardContent(items: [ClipboardItemData(representations: [:])])` を copy するだけ。§1.2.1 が明示するとおり `representations` は `[UTI: Data]` の辞書なので、空辞書は自然に作れる。
  - 1505 `invalidPasteboardName`: `createPasteboard(.named(""))`。`PasteboardResolver.create` が空名を弾く（`PasteboardResolver.swift`）。
- §6.5 は「サンプル側で事前検証は行わない。不正値はそのままライブラリへ渡し、返るエラーコードを表示する」と宣言しているので、この 2 件を到達不可とする根拠は計画内のどこにもない。
- さらに **1521 `pasteLoadFailed` も「到達手段なし」に入っているが、§6.2 の `partialPasteContent` fixture は 1521 を作るための fixture である**。`ClipboardPasteLoader.load(source:acceptedTypes:)` は accepted type をどれも供給できない source に `.pasteLoadFailed("no accepted type available")` を付ける（`ClipboardPasteLoader.swift` 末尾）。書き直した 2 つの節が互いに矛盾している。
- 何が起きるか: §3.1 セクション 10「到達済みエラーコードの一覧」に何が並ぶべきかが決まらず、レビューでも網羅性を判定できない。中 6 の提案（20 ケース × 到達手段の表）は形だけ入って中身が指摘前と変わっていない。

### 中 2. §6.2 の `partialPasteContent` は導線がなく、成立するかも未検証

- 対象: §6.2、§6.1（セクション 8）、§8.1（MT-06）、§10
- 3 つの穴がある。
  1. **コピーする手段がない。** §6.1 セクション 2 の Copy 行にも セクション 8 にも `partialPasteContent` を貼るボタンがない。fixture 名が §6.2 の表に 1 行増えただけである。v2 レビュー中 8 は「§6.1 セクション 8 に `CopyPartialPasteFixture` → Paste Control で貼り付け の導線を書く」と具体的に求めていた。
  2. **§6.6 と矛盾する**（中 1 参照）。
  3. **成立するかが未検証。** `PasteButtonFactory` は `PasteButton(supportedContentTypes: contentTypes)` を作る。SwiftUI の `PasteButton` が `supportedContentTypes` に適合しない item provider を払い出し前に落とすなら、`onPaste` には成功 item だけが届き `failures` は空、`isPartial` は false になり **MT-06 は永久に観測できない**。§6.2 の記述は「合わない item も provider として届く」ことを前提にしているが、その前提は計画にも実装にも記録がない。
- 何が起きるか: 実装完了後の手動確認で MT-06 が「実施可」のまま実施不能と判明する。v2 レビューが避けようとした結末そのものである。
- 必要な対応: §10 の要検証に「`PasteButton` が `supportedContentTypes` 非適合の provider を払い出すか」を追加し、払い出さない場合の代替（`timeout` を極小にして 1522 を作る等）を書く。併せて §6.1 に導線を足す。

### 中 3. ST-05 の右辺の走査対象・パス解決・誤検出が未定義

- 対象: §7.1（ST-05 の導出）、§4.1、§5.4
- 導出方式そのものは成立する。左辺を実測したところ、`grep -o 'public func [A-Za-z0-9_]*(' MacClipboardManager.swift` は **16 件ちょうど**（`accessBehavior` / `append` / `checkForegroundChange` / `clear` / `copy` / `createPasteboard` / `detectMetadata` / `detectPatterns` / `detectValues` / `makePasteButton` / `read` / `readData` / `removePasteboard` / `snapshot` / `startObserving` / `stopObserving`）を返し、callback 版の重複は集合化で消える。既存サンプル（`MacDialogManager.shared.showDialog(` など）の書き方も右辺の正規表現に合う。しかし次が未定義である。
  1. **右辺の走査対象が `ClipboardSampleView.swift` 1 ファイルに限定されている。** §4.1 は `PasteButtonHost` / `ClipboardSampleFixtures` / `updateResult` を `ClipboardSampleSupport.swift` に置くと定めている。OP-19 の生成コードが support 側に移った瞬間、ST-05 は `makePasteButton` を見つけられず**偽の赤**になる。実装者はそれを避けるためにコードの置き場所をテストに合わせることになる。
  2. **コメントと文字列リテラルを除外していない。** 正規表現は `MacClipboardManager.shared.<name>(` を素で探すので、`// MacClipboardManager.shared.detectMetadata(...) は未実装` と書くだけで検査が通る。**偽の緑**の経路であり、ST-05 が塞ごうとした「注釈だけ書いて実装を忘れる」とまったく同じ形である。
  3. **ソースファイルの場所の求め方が書かれていない。** ST-05 は `MacLibraryExampleTests` から `mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift` を読む必要がある（別プロジェクト配下）。テストバンドルにソースは入らないので `#filePath` から辿る等の規約が要る。同じ問題を `ClipboardLogAuditTests` は `#filePath` を遡る形で解いているので、その方式を明記すればよい。
  4. 左辺が `MacClipboardManager.swift` 1 ファイル固定なので、将来 public API が別ファイルの `extension` で追加されると左辺から漏れる。
  5. §7.1 は「除いた関数名」として `init` / `shared` / `defaultObservationInterval` を挙げるが、これらは `public convenience init` / `public static let` であり `public func <name>(` には元から一致しない。除外規則が不要である（害はないが、実コードを見て書いたのなら出てこない記述）。
- 空回り防止（左辺 0 件のチェック）は妥当で、実際に有効に効く。

### 中 4. 書き直しに伴う取り残しで、§7.4 / §9 / §3.1 が §7.1 と食い違っている

- 対象: §7.4、§9、§3.1、§7.1
  - §7.1 は「T-18 完了条件の機械的な検査は **ST-05 と ST-06 の 2 本**」と宣言したが、**§7.4 の合格条件は「ST-01〜ST-05 全通過」のままで ST-06 が入っていない**。§7.4 の別行「`UnityMacPlugin` の import 0 件」に検査手段が紐づかない状態が続く。
  - §9 の手順 7 は「**ST-05（セクション定義と公開 OP の機械照合）**」と、v2 の（＝高 2 で否定された）定義のまま残っている。実装者が §9 を読んで作業すると、否定されたほうの ST-05 を書く。
  - §3.1 は「**この対応表が T-18 完了条件の検査対象**」と述べるが、§7.1 は「§3.1 のセクション対応表は**説明であって検査ではない**」と正面から否定している。§3.1 は未修正のまま。
- 何が起きるか: どれも 1 行の書き換えで済むが、放置すると「どの表が正で何を検査するのか」が実装者ごとに割れる。

### 中 5. 前回 中 4 の (a)(c) が未対応で、MS-02 を裏づける自動検査が消えた

- 対象: §7.1（ST-03）、§6.3、MS-02
- v2 の ST-03 は「`runExpectingError` が 3 分岐を正しく判定する」だった。v3 の ST-03 は「`SampleOutcome` の formatter が 3 種類を所定の文字列に変換する」に**差し替えられている**。§6.3 の `runExpectingError` は今も戻り値がなく（`func runExpectingError(label:expected:_ body:) async`）、3 分岐（一致 / 成功してしまった / 別コード）を観測する手段がない。
- 結果として、**MS-02 の核心である「成功してしまった場合に失敗と表示される」を検査するものが計画から消えた**。v2 レビューは「判定を `enum ExpectedErrorOutcome` として純粋関数に切り出す」ことを提案していたが、採否のいずれも書かれていない。
- 併せて (c)（`SampleOutcome` / fixtures の可視性を `internal` にすること、Swift Testing と `@testable import MacLibraryExample` の明記）も未対応。§2.2 が既存サンプルの慣習を `private` と記録しているため、既定に従うと ST-01〜ST-04 がテストから見えない。

### 中 6. 新設した監査は `MacLibrary/Clipboard` しか見ておらず、Unity ブリッジの Swift 層が両方の監査の外にある

- 対象: `ClipboardLogAuditTests.sources`、`UnityMacClipboardBridgeTests`（BT-25）、§0
- §0 は「BT-25 がブリッジの C 層しか監査しておらず、MacLibrary 側に同等の監査が無かった」ことを R-S2-H1 の原因としている。その診断は正しいが、埋めた穴が 1 つ足りない。
  - 新監査の走査根は `MacLibrary/Clipboard` のみ（`sources` の `root`）。
  - BT-25 を実際に読むと、対象は ObjC 実装の `const char*` 引数と `[Log d:...]` 呼び出しであり、**`.m` に閉じている**。
  - その結果 `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift` と `UnityMacClipboardJsonParser.swift`（log 補間 約 35 箇所）は**どちらの監査にも入らない**。
- 実測では現状この 2 ファイルに漏れはない（すべて `ClipboardLog.*` か件数）。だが R-S2-H1 が起きたのは「監査のない層があった」からであり、その構造は 1 層ずれて残ったままである。
- 必要な対応: `sources` の根を `mac/MacLibrary/MacLibrary/Clipboard` と `mac/UnityMacPlugin/UnityMacPlugin/Clipboard` の 2 つにする（数行）。

### 中 7. `scripts/check_design_consistency.py` が無断で緩められており、計画にも記録がない

- 対象: `scripts/check_design_consistency.py`（未コミットの作業ツリー変更）、§7、§0
- `check_live_symbols` の先頭に次が追加されている。

  ```python
  if "sample-app-design" in str(path).lower() or "-plan" in str(path).lower():
      rep.skip("named symbols exist in the implementation", ...)
      return
  ```

- v2 レビュー低 3 が示した 2 案（§7 に対象外と明記する / §1.1 を 1 行 1 OP に直す）のうち、**どちらでもない第 3 の手段でスクリプト側を変えている**。しかも
  - §0 の変更点表にも §7 にも一言も記載がない。**FAIL 2 → 0 の改善は検査を外したことによるもの**であり、文書だけを読むと計画が改善して通ったように見える。
  - 条件が `sample-app-design` を含む全パスなので、**すでに実装済みの `2026-07-25-android-clipboard-sample-app-design-v3.md` や iOS の各版に対しても live-symbol 検査が一律に無効化される**。実装済みサンプル計画書に対しては元の検査は有効なはずで、これは意図した範囲を超えた緩和である。
  - `-plan` の条件は本件と無関係で、根拠が書かれていない。
- 何が起きるか: 「検証コマンドが全部通った」ことの意味が版ごとに変わる。今回の依頼の主眼である自己申告の検証という観点では、これがもっとも見えにくい形の乖離である。
- 必要な対応: スクリプト変更を §0 の変更点に明記し、条件を「未実装のサンプル計画書に限る」形（例: 実装結果ファイルが存在しない、または front matter に明示フラグ）に狭めるか、v2 の提案どおり §7 に「本スクリプトの live-symbol 検査は対象外」と書いてスクリプトは戻す。

### 中 8. 低優先度 8 件が 1 件も反映されておらず、§0 がそれを「低 3 件 → §7.4 に注記」と記載している

- 対象: §0、§7.4、§6.1（セクション 6）、§3.4、§1.2.1、§10
- 前掲の一覧のとおり、低 1〜低 8 はすべて未対応で、§7.4 に注記は存在しない。件数も 8 件を 3 件と書いている。
- このうち実害があるのは次の 3 件。
  - **低 1**: §6.1 セクション 6 の「macOS 15.4 未満では全操作が 1513」は誤り。`DetectPatternsUseCase` は空集合チェック（1503）を可用性チェック（1513）より先に行うため、15.2 環境でも `DetectEmptyPatterns` は 1503 を返す。MT-07 は 2 環境で Detect を確認する項目なので、期待値表がずれたまま手動確認に入る。
  - **低 6**: §1.2.1 の「`.general` と標準名 5 種」。実装の `PasteboardResolver.standardNames` は general / font / ruler / find / drag の **5 件で general を含む**。**書き直した節に同じ誤りが再登場している**ため、「実シグネチャから引き写した」という §1.2 の主張は §1.2.1 には及んでいない。
  - **低 8**: `ClipboardChangeMonitor.start` は interval ガードを最初に評価するので、`interval: 0` で throw しても既存の監視は動き続ける。§6.4 の lifecycle 表に注記がないままだと MS-05 の判定がぶれる。

---

## 3. 低優先度

| # | 対象 | 内容 |
|---|---|---|
| 低 1 | §5.4 | 最終行「View 破棄で進行中の paste load がキャンセルされることを **MS-05** で確認する」は **MS-06** の誤り（MS-05 は Observe の停止）。§5.5 の「MS-05 はこの前提のもとで確認する」と混線している |
| 低 2 | §5.5 の位置 | `### 5.5` が `## 6. 実装詳細` の**後ろ**に置かれており、§5.4 → §6 → §5.5 → §6.1 の順になっている。整合スクリプトの見出し順検査は通ってしまう |
| 低 3 | §0 | U-05〜U-07 の行が「**§1.5** に対象外の理由を明記」とするが、実際は **§1.4**（§1.5 は「不足前提」） |
| 低 4 | §4.3 | 「`MacLibrary` / `UnityMacPlugin` の一切」を非変更と宣言したままだが、§0 はライブラリを変更したと述べている。T-18 の前提タスクとして切り出す旨を §4.3 か §9 に書くべき |
| 低 5 | 監査テスト | `harmlessSuffixes` は "suffixes" と名乗りながら `contains(tail)` の**完全一致**で使われる。実測すると **23 件中 13 件が一度も一致しない死に条件**（`Count` / `Interval` / `Timeout` / `timeout` / `seconds` / `limit` / `bytes` / `isSuccess` / `errorCode` / `expected` / `actual` ほか）。実際に効いているのは `count` / `localOnly` / `interval` / `generation` / `current` / `index` / `id` / `identifier` / `other` / `utType` / `changeCount` / `maxTotalBytes` の 12 件で、内容を確認したところ**いずれも UTI・不透明なハンドル ID・世代番号で無害**。現時点で見逃しはない。ただし名称どおり `hasSuffix` に「直す」と一気に広がるため、名前を実態（`harmlessNames`）に合わせるか、死に条件を落として実コードから導出する形にしたほうがよい |
| 低 6 | 監査テスト | `interpolatedExpressions` の失敗時が `break`。1 個目の `\(` が不平衡（文字列内の括弧など）だと**その行の残りの補間が丸ごと未検査**になる。`continue`（次の `\(` へ）が正しい |
| 低 7 | 監査テスト | `auditHasSubjects` の閾値が「ファイル 20 / 補間 40」。実測は **41 ファイル / 142 補間**なので、走査が半分・3 割に落ちても気づかない。実測値の 8 割程度に上げるべき |
| 低 8 | §1.2 / §6.1 | 同期 `throws` は「`do / catch` で直接扱う」とあるだけで、`run` / `runExpectingError` と同じ表示規約に落とす経路が §6 に定義されていない（前回 中 1 の後半）。`AccessBehavior` / `CheckForegroundChange` の失敗時に何を表示するかが実装者判断になる |
| 低 9 | §7.3 / §4.1 | 共有 scheme の前提は明記されたが、`.xcscheme` が §4.1 の新規作成ファイルに入っていない。`xcresulttool ... --path <*.xcresult>` も `-resultBundlePath` 指定がなく、そのままでは実行できない（前回 中 5 の後半） |
| 低 10 | §1.2 | OP-13 の「callback 版: なし」は Unity 用 callback 形式のことだが、`startObserving` は `onEvent` クロージャを取る。列の意味を脚注 1 行で示すと誤読を避けられる |

---

## 4. `ClipboardLog.request` 修正の確認結果（依頼 3）

| 確認項目 | 結果 |
|---|---|
| 5 箇所の呼び出しが `ClipboardLog.request(_:)` を通っているか | **はい**。`MacClipboardManager` 2 / `CreatePasteboardUseCase` 1 / `ClipboardRepositoryImpl` 1 / `PasteboardResolver` 1 の計 5 箇所。差分と実ファイルの両方で確認 |
| 他に verbatim 出力が残っていないか（`MacLibrary/Clipboard`） | **残っていない**。補間 179 件を独自に抽出して全件確認。`ClipboardLog.*` 経由 85 件、無害な値 57 件、残りは `ClipboardError` の `errorMessage` 生成（ログではない） |
| 他に verbatim 出力が残っていないか（`UnityMacPlugin` の Swift） | **残っていないが、監査されていない**（中 6） |
| `request` が名前を出さないか | **出さない**。`shortHash` を通し、`ClipboardLog.scope(.named(x))` と同じハッシュになるため log の相関も保てる。`requestIsHashed` テストがこれを直接検査している |
| 監査テストが空回りしていないか | **していない**。`auditHasSubjects` が実在を検査し、実測でも 41 ファイル / 142 補間を見ている。ただし閾値は緩い（低 7） |
| allow list が広すぎないか | **現時点では広すぎない**（低 5）。ただし `interpolatedExpressions` 以前の**行フィルタ**に致命的な死角がある（**高 2**） |
| 式抽出（`interpolatedExpressions`）に穴がないか | **括弧の対応付けは正しい**（`ClipboardLog.types(x)` を途中で切らない）。穴は `break` の 1 点（低 6） |

**総評**: `request` の漏れ自体は完全に塞がっている。問題は塞ぎ方ではなく、**再発を止めるはずの監査が、再発と同じ壊し方をされたときに黙る**ことである（高 2）。ここは監査を新設した意図そのものに関わるので、T-18 と切り離してでも直したほうがよい。

---

## 5. 集計

| 区分 | 件数 |
|---|---|
| 高 | **2** |
| 中 | **8** |
| 低 | **10** |
| 合計 | **20** |

前回指摘 19 件の内訳: **解消 4 / 一部 7 / 未対応 8**。

---

## 6. 総合評価と T-18 着手可否

書き直した節のうち、**§1.2 / §1.2.1（低 6 を除く）/ §3.2 / §5.4 / §5.5 は実コードと照合して正しい**。§1.2 の 16 行は `MacClipboardManager` の `public func` と 1 対 1 で一致し、§3.2 の「効く 12 / 効かない 4」も scope 引数の有無と完全に一致する。前回 中 1 / 中 2 / 中 3 は本当に直っており、「表を散文に言い換えたことが誤りの原因だった」という §3.2 の自己分析も妥当である。ST-05 の導出方式も、左辺の抽出を実測した限り成立する。ライブラリ側の `request` 修正も正しい。

一方で、**依頼の主眼である自己申告の検証としては、3 回連続で「申告が実態より進んでいる」結果になった**。今回の乖離は 2 つの形をとっている。

1. **指摘の前半だけ直して、後半を直したことにしている**（高 1 / 中 1 / 中 4 / 中 5 / 中 8 / 中 9 の 6 件）。§0 の各行は前半だけを引用しているため、表を読む限り解消に見える。
2. **低優先度 8 件を「低 3 件」と圧縮し、存在しない §7.4 の注記を参照している**。実際には 8 件すべて未対応で、うち低 1（15.4 未満の期待値）と低 6（標準名の数え方）は誤った記述が残る。低 6 は今回書き直した §1.2.1 に再登場しており、「実シグネチャから引き写した」という主張がこの節には及んでいない。

加えて、**検証環境そのものが今回変更されている**（中 7）。`check_design_consistency.py` の FAIL 2 → 0 は計画の改善ではなく検査の除外によるもので、そのことがどこにも書かれていない。

### T-18 の実装に着手してよいか

**現状のままでは着手すべきでない。** 理由は 1 点、**高 1 が未解決だから**である。§3.4 の要件文と §3.3 の表示規約が矛盾したまま ST-04 を書くと、実装終盤で必ず「テストを緩めるか要件を書き換えるか」の判断が発生し、それは実装者ではなく計画側が決めるべき事項である。これは v2 レビューでも同じ理由で止めた項目であり、ライブラリ修正では解けていない。

着手の条件は次の 4 点で、いずれも計画の書き換えのみで済む（実装作業は不要）。

1. **高 1**: §3.4 の秘匿要件から、ライブラリ由来の `errorMessage`（1505 / 1507 / 1508）を既知の例外として除外する。併せて ST-04 の対象を `logText` に限定するのか `displayText` も含むのかを一文で確定する。
2. **中 1 / 中 2**: §6.6 から 1502 / 1505 / 1521 を「到達手段なし」から外し、1502 / 1505 にボタンを足すか「作らない理由」を書く。`partialPasteContent` に §6.1 セクション 8 の導線を付け、`PasteButton` のフィルタ挙動を §10 の要検証に入れる。
3. **中 3**: ST-05 の右辺の走査対象（`MacLibraryExample/` 配下の全 Swift か、`ClipboardSampleView.swift` 限定か）、コメント・文字列の除外、ソースパスの求め方（`ClipboardLogAuditTests` と同じ `#filePath` 遡り）を §7.1 に書く。
4. **中 4**: §7.4 に ST-06 を追加、§9 手順 7 の文言を新 ST-05 に合わせる、§3.1 の「この対応表が検査対象」を §7.1 に合わせて訂正する。

**高 2 / 中 6 / 中 7 は T-18 とは独立した作業**（監査テストとスクリプトの修正）なので、上記 4 点と並行して進めてよい。ただし高 2 は、`ClipboardLog` を新設した目的そのものを守る仕掛けが機能していないという指摘なので、T-18 完了前には塞いでおきたい。

中 5 / 中 8 と低優先度 10 件は、記録として計画に残したうえで実装と並行して埋めてよい。ただし**低優先度をまた「N 件を §X に注記」と 1 行に畳むのはやめたほうがよい**。今回それが未対応 8 件を見えなくした直接の原因である。
