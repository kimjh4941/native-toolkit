# macOS クリップボード機能 実装レビュー v12

- 日付: 2026-09-02
- 対象ブランチ: `feature/NTKIT-15`
- 対象差分: `git diff develop`（**未コミットの working tree を含む**）
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v13.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v11.md`（high 4 / medium 7 / low 7）
- 対象OS: macOS 15 以降
- 適用ルール: `agent-rules/coding-rules/common.md`、`agent-rules/coding-rules/mac.md`
- 対象外: 設計書 §7.12 のスコープ変更判断そのもの / T-18 / MT-01〜MT-09 / 旧サンプル計画 v1

---

## レビュー概要

v11 の指摘 18 件を一度に反映した状態を、working tree を含めて検証した。

### 数値検証（すべて再現できた）

| 項目 | 報告値 | 再現値 | 判定 |
|---|---|---|---|
| MacLibrary（宣言 / 実行 / 失敗） | 304 / 348 / 0 | **304 / 348 / 0** | 一致 |
| UnityMacPlugin（宣言 / 実行 / 失敗） | 72 / 73 / 0 | **72 / 73 / 0** | 一致 |
| 通常 `clean test` の Clipboard 警告 | 0 件 | **0 件**（残るのは `appintentsmetadataprocessor` と既存 `UnityMacNotificationJsonParser.swift:198` のみ） | 一致 |
| strict build | BUILD SUCCEEDED / 173 / Clipboard 0 | **BUILD SUCCEEDED / 一意 173 件 / Clipboard 由来 0 件** | 一致 |
| 機械照合 | 28 / 28（SKIP 0） | **28 / 28、SKIP 0、exit 0** | 一致 |
| `git diff develop --check` | 0 件 | **0 件** | 一致 |

件数は `xcrun xcresulttool get test-results summary` から読んでいる。

### v11 指摘 18 件の反映状況

| ID | 判定 | 備考 |
|---|---|---|
| H-1 corpus 汚染 | **一部** | v11 が実演した経路は塞がった。**同型の穴が 3 つ残る**（本版 H-4） |
| H-2 独自 UTI の無言破棄 | **一部** | コードは throw に修正。**設計・公開 DocC が追随していない**（本版 H-3） |
| H-3 必須引数 NULL が 1301 | **一部** | 1302 分類と BT-26 は入った。**BT-01/05/08/10/12/22/23 は依然として未実装で DoD は [x]**（本版 H-1） |
| H-4 ヘッダの wire format | **一部** | `ScopeResultJson` は修正。**`_Nullable` 3 箇所と BT-10 は未対応**（本版 H-2） |
| M-1 設計現行章の取り残し 7 件 | **一部** | 4 件修正、**3 件残存**。同型の 4 件目を新規検出（本版 M-1） |
| M-2 ファイル構成の乖離 | **一部** | §6.1 は実ツリーから再生成され完全一致。**§4.1 / §6.5.1 は未修正**（本版 M-2） |
| M-3 Port の "stale detection" | 反映 | - |
| M-4 Unity facade の DocC | 反映 | 走査範囲も両ツリーへ拡大 |
| M-5 Manager → Data 直接生成 | 反映 | ただし該当経路のテストは無い（本版 M-7） |
| M-6 恒真の band 検査 | **一部** | band 検査は落ちるようになった（実証済み）。**「設計 → 実装」の未検査は放置**（本版 H-4c） |
| M-7 observer の解放漏れ | 反映 | `ObserverTokens` は競合・解放漏れとも問題なし |
| L-1 IT 表の分断 | 反映 | - |
| L-2 設計の `Timer` 記述 | **未対応** | 1 箇所も直っていない（本版 M-3） |
| L-3 `attachCoordinator` | 反映 | - |
| L-4 `Log.d` 漏れ 5 件 | 反映 | - |
| L-5 空回りする捕捉監査 | 反映 | ブロック単位の解析に書き直され、実際に落ちうる形になっている |
| L-6 encode 失敗が成功扱い | **一部** | `run(...)` のみ。**名指しされた `readData` が直っていない**（本版 M-4） |
| L-7 削除跡の空行 | **未対応** | 全箇所残存、さらに 2 箇所増えた（本版 L-1） |

反映 9 / 一部 7 / 未対応 2。

### 総合

**要修正（重大）**。high 4 件 / medium 7 件 / low 6 件。

コード側の実害のある欠陥（H-2 無言破棄、H-3 の 1301/1302、M-5 の層違反、M-7 の observer 蓄積、
L-5 の空回り監査）は解消している。残っているのは **「直したと報告されているが直っていない／半分しか
直っていない」もの**が中心である。結果レポート v13 の §4 / §5 の表は M-1・M-2・L-2・L-6・L-7 について
実態より進んだ状態を記載している。

---

## 重大な問題（high）

### H-1. §15 実装完了条件が、存在しない Bridge テストを [x] としている（v11 H-3 の未解消部分）

- 該当（宣言）: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1781`

```
- [x] 12.4 の Bridge テスト BT-01〜BT-03 / BT-05〜BT-08 / BT-10〜BT-12 / BT-17 / BT-20〜BT-25 が全通過する
```

- 該当（実装）: `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift`

実在するのは BT-06 / BT-07 / BT-11 / BT-17 / BT-20 / BT-21 / BT-24 / BT-25 と、設計に行の無い BT-26。

| ID | 設計での要求 | 実装 |
|---|---|---|
| BT-01 | 全 15 endpoint が正常系で operation callback を 1 回呼ぶ | **なし**（facade メソッド数 15 を数えるのみ・`:54-60`） |
| BT-03 | 必須引数 NULL で 1302 を 1 回 | 実質 BT-26（`:72-95`）が担うが、**設計 §12.4 に既にある BT-03 を名乗っていない** |
| BT-05 | 非メインスレッド呼び出しでも callback がメインスレッド | **なし** |
| BT-08 | 監視 endpoint が購読中 N 件配信し stop で止まる | **なし** |
| BT-10 | 全 15 endpoint の C prototype が §8.4.3 と一致（ヘッダ検査） | **なし**（数と `const char*` 規約のみ） |
| BT-12 | event N 回 / operation 1 回 | **なし** |
| BT-22 | background thread からの早期リターン経路も main で exactly-once | **なし** |
| BT-23 | nil callback で trap しない / start・stop 境界で handler が交差しない | **なし** |

`§15:1782` の `- [x] 12.5 の並行性テスト CT-01〜CT-02 / CT-04〜CT-05 / CT-07 が全通過する` も同様で、
テスト側に CT-02（非 Sendable 捕捉警告なし）と CT-05（同期 UseCase のシグネチャ検査）に対応する
アサーションが見当たらない（CT-04 / CT-07 は実在）。

**何が壊れるか**: BT-05 / BT-22 は「任意スレッドから呼んで main で exactly-once」という H-7 と案 C の
中心契約であり、この機能の Bridge 設計そのものである。それが 1 件も実行されていないまま DoD が [x] に
なっているため、次工程（T-18 サンプル、write-manual、リリース判断）はこの契約を検証済みとして扱う。
v11 が同じ表を挙げたのに、今回追加されたのは BT-26 1 件だけである。

対処案: (a) 未実装の BT を実装する、または (b) DoD のチェックを外して未実装であることを明示する。
いずれかを選ぶまで、この行は「テストがあると読める嘘」である。

---

### H-2. Bridge ヘッダと §8.4.3 の prototype が今も一致していない（`_Nullable` 3 種）。BT-10 も未実装のまま

- 設計 `:1171` / `:1176` / `:1178`（§8.4.2 typedef）、`:1205`（§8.4.3）

```c
typedef void (*ClipboardCallback)(BOOL isSuccess,
                                  NSInteger errorCode,
                                  const char* _Nullable errorMessage);
typedef void (*ClipboardJsonCallback)(BOOL isSuccess,
                                      const char* _Nullable json, ...);
void clipboardSnapshot(const char* _Nullable matchingTypesJson, ...);
```

- 実装 `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.h:45-55` / `:96`
  — いずれも `_Nullable` が無い。ファイルに `NS_ASSUME_NONNULL_BEGIN` も無いので nullability は
  unspecified 扱いになる。

v11 H-4 が「なお `.h:96` の `matchingTypesJson` に §8.4.3 が付けている `_Nullable` も落ちている」と
書いた部分がそのまま残っている。ヘッダ検査 BT-10 も未実装なので、この差は誰も検出しない。

**何が壊れるか**: `matchingTypesJson` は「NULL を渡すのが正しい使い方」の唯一の引数で（`.h:95` の
散文だけがそれを述べている）、`json` / `errorMessage` は失敗時に NULL になる。これらの nullability は
ヘッダの型に現れない。C# の P/Invoke 実装者と Swift への import の双方が、ヘッダを一次資料として
読むにもかかわらず、設計が定めた nullability 契約を受け取れない。

対処案: `.h` に `_Nullable` を 3 箇所付ける。あわせて BT-10 を「§8.4.3 のコードブロックを設計書から
読み出し、`.h` の prototype と引数名・型・nullability 単位で突き合わせる」形で実装する
（BT-25 が signature から監査対象を導出しているのと同じ作り方ができる）。

---

### H-3. `makePasteButton` の新しい失敗契約が、設計にも公開 DocC にも無い。§8.2 の明文と矛盾する

- 実装: `mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:88-95`

```swift
for identifier in acceptedTypes {
    guard let type = UTType(identifier) else {
        Log.e(TAG, "[makePasteButton] no UTType declaration for an accepted type")
        throw ClipboardError.invalidTypeIdentifier(identifier)
    }
    contentTypes.append(type)
}
```

無言で捨てる挙動は解消しており、登録より前に throw する点も正しい。問題は契約の記述側にある。

1. **設計 §8.2（`:1108-1111`）は「判定基準は `UTType(identifier) != nil` ではない」「`UTType` で検証すると
   アプリ独自フォーマットを不当に拒否する」と実測に基づいて明記している。** OP-19 だけがこの基準を
   採ったこと、およびその理由が、設計書のどこにも書かれていない。
2. **設計 §7.11（`:875`、`ClipboardPasteLoader` の契約）は今も**
   「`acceptedTypes` は UTI として検証済み。空なら `invalidTypeIdentifier`」**のままである。**
   新しい失敗条件が追加されていない。
3. **公開 API `MacClipboardManager.makePasteButton`（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:527-545`）の DocC に `- Throws:` が無い。**
   throw 条件は internal な `PasteButtonFactory` の DocC（`:70-78`）にしか書かれておらず、
   ライブラリ利用者が読む生成 DocC には出ない。§9 OP-19 行（`:1456`）の「エラー」欄も更新されていない。

**何が壊れるか**: `copy(["com.mycompany.myformat"])` は成功し、
`makePasteButton(acceptedTypes: ["com.mycompany.myformat"])` は throw する、という非対称が公開契約に
現れない。呼び出し側から見ると「ライブラリが受理すると明記した識別子を渡したのに throw された」ことになり、
`ClipboardTypeIdentifierValidator` の DocC（「`UTType` で検証してはならない」）を読んだ人ほど混乱する。
v11 H-2 の対処案は「throw する **または** 設計と DocC に明記する」だったが、throw を選んだ以上、
その条件を書くことは選択肢ではなく必須である。

---

### H-4. 検査 12 / 11 に、H-1 修正後も同型の穴が 3 つ残る（すべて実証済み）

`scripts/check_design_consistency.py`。以下はいずれも設計書のコピーに一行足して
`28 / 28 OK, EXIT=0` を確認した。

**(a) 部分文字列一致が残っている** — `:381` `if FOREIGN_SYMBOL.match(ident) or ident in corpus`

```
`ScopeResult` は受領を運ぶ。`PasteboardPromise` も同様。   → 28/28 OK
```

`ScopeResult` / `PasteboardPromise` はどこにも宣言が無く、`ScopeResultJson` /
`PasteboardPromiseHandle` の**前方一致**で通っている。v11 H-1 は
「corpus からテストを除く」「宣言位置で照合する」の 2 案を出したが、採られたのは前者だけで、
**名前の切り詰め・改名・誤記は今も素通しする**。

**(b) コメントは corpus から落ちていない** — `:367-370` はテストソースの**文字列リテラル**だけを消す

```
`isolation` は `domains` ごとに `assumeIsolated` で確定する。   → 28/28 OK
```

`domains` は `UnityMacClipboardManagerBridge.m:48` ほかのコメント
「`// isolation domains (MIGRATION.md section 6, plan C).`」にしか存在しない。
削除済みの型名がコメントに 1 行残っていれば、設計書側の取り残しはそれを根拠に「実在する」と判定される。

**(c) 「設計 → 実装」の向きが今も未検査** — `check_error_mapping:204`

```python
documented = {k: v for k, v in declared.items() if k in actual}
```

v11 M-6 の後半（実装に無いケースの行を暗黙に除外している）は放置されている。実証:

```
| 1598 | `detectionDenie` | `Ghost error.` |     ← §11 の表に追加   → 28/28 OK
```

実装に存在しないエラーコードとケース名が、検査 11（交差集合しか見ない）と検査 12（(a) の部分一致で
`detectionDenied` に吸収される）の両方をすり抜ける。過去 3 ラウンドの取り残しはすべて
「設計に残った」方向であり、未検査の向きが逆であるという v11 の指摘がそのまま成立している。

**何が壊れるか**: 「削除の取り残しは機械照合が捕まえる」という DoD の前提。実際に捕まえられるのは
v11 が実演した 1 パターン（テストの文字列リテラル経由の汚染）だけで、同じ構造の穴が 3 つ残っている。
`corpus` を全文連結して部分一致する限り、この形の false green は種類を変えて出続ける。

対処案: 判定を宣言位置に変える
（`(struct|class|enum|protocol|typealias|func|let|var|case)\s+<ident>\b` で照合する）。
これ 1 つで (a) と (b) の両方が閉じる。(c) は `check_error_mapping` に
`set(declared) - set(actual)` の検査を 1 本足す。

---

## 改善提案（medium）

### M-1. v11 M-1 の 7 件のうち 3 件が §15 に残り、同型の 4 件目を新たに検出した

いずれも `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md` の §15 設計完了条件。

| 行 | 内容 | 実態 |
|---|---|---|
| `:1729` | 「機械照合を導入し、全検査が通ることを確認した（**§16.2** / R6-L13 / R6-L14）」 | **§16.2 は存在しない**（§16 の子は §16.1 のみ）。v11 M-1 #5 で指摘された 2 点のうち「全 22 検査」だけが直り、参照先は残った |
|  `:1734` | 「**T-11 を 3 分割し、さらに T-06 / T-12 を 2 分割して**、全タスクを 0.5〜1.5 日粒度に収めた」 | §13 のタスク表に T-11 / T-12 は無い（T-11a/b/c と T-12a/b は §0 の削除表で消えている）。v11 M-1 #3 が未対応 |
|  `:1736` | 「**callback 必須 endpoint を 3 件に確定した**（R4-M6）」 | 冒頭「用語」・§8.4.1・BT-17 はいずれも **1 件**。2 件は `clipboardProvideFilePromise` / `clipboardReceiveFilePromises` だった。v11 M-1 #2 が未対応 |
|  `:1741` | 「**handle を返す 2 endpoint** の NULL callback 契約を分離した（R3-M4）」 | **新規検出**。handle を返すのは `clipboardCreatePasteboard` の 1 件のみ。2 件目は `provideFilePromise`。同じ形の取り残し |

4 件とも backtick 識別子を含まず、`全 N endpoint` / `実体 N 型` の言い回しにも当たらないので、
28 検査の対象外である（H-4 / M-6 と同じ理由）。

### M-2. §4.1 と §6.5.1 のパスが実装と一致していない（v11 M-2 の未修正部分）

§6.1 は実ツリーから再生成され、**41 + 20 + 4 + 2 ファイルすべてが完全一致**していることを確認した。
一方、同じ乖離を指摘された他の 2 箇所は直っていない。

| 行 | 設計の記述 | 実際 |
|---|---|---|
| `:340`（§4.1） | `ClipboardSystemCoordinator` … `mac/MacLibrary/.../Clipboard/Coordinator/` | `Clipboard/Manager/ClipboardSystemCoordinator.swift` |
| `:541`（§6.5.1） | `ClipboardPasteHandle` は `Clipboard/Domain/Model/ClipboardPasteHandle.swift` | `Clipboard/Domain/Model/ClipboardHandles.swift` |

検査 12 は backtick の中身が `\w{6,}` に完全一致するときだけ見るため、`/` と `.` を含むパスは対象外。

あわせて、§6.1 の冒頭に「**この一覧は実ツリーから生成する**」と書かれたが、**それを検証する検査は
追加されていない**（機械照合は 15 → 15 項目のまま、16 項目目は無い）。今回は手で正しく生成されているが、
次にファイルが 1 本増減した時点で再び黙ってずれる。生成物であることを主張するなら、`§6.1` のツリーと
`find` の結果を突き合わせる検査を足すのが筋である。

### M-3. L-2「実装が正なので設計を追随済み」は行われていない

結果レポート v13 §5 の表は L-2 を「実装が正。設計を追随済み」としているが、設計書は 1 箇所も
変わっていない。

| 行 | 記述 |
|---|---|
| `:251` | 「`Timer` を使う監視は `@MainActor` 隔離が必要」 |
| `:341`（§4.1） | `ClipboardChangeMonitor` \| **Timer（coordinator が所有）** |
| `:495`（§6.2） | 「`Timer` は Swift 6 で `@MainActor` が必要（RK-10）」 |
| `:722`（§7.9 手順 4） | 「**`Timer.scheduledTimer` を作る**。本体は `MainActor.assumeIsolated { }` で包む」 |
| `:1453` / `:1454`（§9） | OP-13 の System API 欄「M-01 + **Timer**」、OP-14 のキャンセル欄「**Timer** invalidate」 |

実装は `mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardChangeMonitor.swift:106-114` の
`Task { while !Task.isCancelled { try? await Task.sleep(...) } }` である。

さらに `:341` の「coordinator が所有」も誤りで、monitor を所有するのは
`MacClipboardManager`（`MacClipboardManager.swift:119`）であり、`ClipboardSystemCoordinator` には
monitor への参照が 1 件も無い（`grep -n monitor ClipboardSystemCoordinator.swift` が空）。

**何が壊れるか**: §7.9 は変更監視の実装手順書であり、§9 は「実行方式が設計と一致していること」を
DoD が要求している表である（`:1777`）。その表が実装と違う機構を指している。

### M-4. L-6 の修正が `run(...)` にしか入っておらず、指摘で名指しされた `readData` が直っていない

- 修正済み: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:62-71`
  （`encode` が nil を返したら 1599 を返す。R11-L6 のコメント付き）
- 未修正:

| 行 | コード | 挙動 |
|---|---|---|
|  `:193` | `handler?(true, parser.encodeData(data), 0, nil)` | encode 失敗で **isSuccess=YES / json=NULL / code=0** |
| `:427` | `handler?(true, parser.encodeBool(changed), 0, nil)` | 同上 |
|  `:384` | `guard let json = parser.encodeChangeEvent(event) else { return }` | **event を無言で破棄**（`Log.e` も無い） |

v11 L-6 は「`readData` の『該当型なし』は `{"data":null}` を返す設計なので、本当の encode 失敗と
区別する手段が無い」と、まさに `readData` を根拠に挙げていた。`readData` は値を返す endpoint の中で
唯一 `run(...)` を通らない経路（`:184-197` で手書き）であり、そこだけが残った。

発生確率は低い（Base64 文字列と Bool の encode が失敗する状況は考えにくい）が、`run` に付けた
「`isSuccess=YES` + NULL は `readData` の正常系と区別できない」というコメントが、
`readData` 自身には適用されていない状態になっている。

### M-5. 28 検査が SKIP に化けても exit 0 のまま。「28/28」を機械が保証していない

- 該当: `scripts/check_design_consistency.py:109-113`（`dump` は `not self.failures` を返すだけ）

検査本数のアサーションが無く、SKIP は exit code に影響しない。実証:

```
§8.4.3 の見出しを「完全な C prototype（15 endpoint）」→「C prototype 一覧（15 endpoint）」に変更
→ 「Bridge endpoint count」が SKIP、出力は 27 行、FAIL 以外は全部 OK
```

SKIP に落ちやすい箇所は他にもある。

| 検査 | SKIP 条件 |
|---|---|
| 1 / 2（OP） | `^### 8.1 ` `^## 9. ` の見出し、`**公開 OP**: OP-01〜OP-NN の **N 件**` の言い回し |
| 3（Bridge endpoint） | `^#### N.N.N 完全な C prototype` の見出し |
| 4 / 5（Port） | `**Port N 種**（...）` の言い回し |
| 9 / 11 / 12（旧表現・エラー対応・識別子） | **文書パスに `clipboard` が含まれること**（`:191` / `:304` / `:353`）。設計書をリネーム／別機能へ流用した時点で 3 検査が黙って SKIP |
| 15（schema サンプル） | JSON 在庫表の第 1 列が `入力専用` / `入出力共用` / `出力専用` / `イベント` のいずれかであること（`:435` に人が列挙） |

結果レポート v13 §2.3 は、この罠に自分で落ちたこと（一時ファイル名に `clipboard` が無く SKIP に
なっていた）を記録している。しかし対処は「人が SKIP も見る」という手順の追加だけで、
**スクリプト側は何も変えていない**。冒頭の docstring が「a silent vacuous pass hands out false
confidence」と書いているのに、その silent vacuous pass を exit code で表現する手段が無い。

対処案: `--expect 28` のような本数指定、または `--strict`（SKIP を FAIL 扱い）を足し、DoD のコマンドを
そちらに差し替える。

### M-6. 検査 13「件数の一致」は 2 通りの言い回ししか知らない

- 該当: `scripts/check_design_consistency.py:476` / `:480`

```python
for n in re.findall(r"全 \*{0,2}(\d+) endpoint", line): ...
for n in re.findall(r"実体 \*{0,2}(\d+) (?:JSON )?型", line): ...
```

実証: 現行章（§7.11 冒頭）に

```
Bridge endpoint は 19 件、公開 OP は 20 件である。UseCase は 18 本。
```

を足しても **28 / 28 OK、exit 0**。

v11 M-1 #4（§15 の「公開 OP 20 / Bridge endpoint 19」）は該当行を書き換えて閉じたが、
検査は同じ形のドリフトを今も見ない。冒頭「用語」が固定している 5 つの数（公開 OP 16 /
Bridge endpoint 15 / UseCase 14 / callback 必須 1 / JSON 実体 17）のうち、
検査対象は endpoint と JSON 型の 2 つ、しかも決まった言い回しのときだけである。

### M-7. `MacClipboardManager.makePasteButton` を通るテストが依然として 0 件

- PT-16（`mac/MacLibrary/MacLibraryTests/Clipboard/Presentation/ClipboardPasteLoaderTests.swift:520` / `:540`）は
  `PasteButtonFactory.makePasteButton` を直接呼び、`MockClipboardTypeIdentifierValidating` を渡している
- `MacClipboardManagerTests` に `makePasteButton` を呼ぶテストは無い（`@Test` 15 本を確認）

M-5 の修正（validator を注入可能にした）の目的は「Manager 経路も mock で固定できるようにする」ことだった。
注入口はできたが、その経路を通るテストは追加されていない。`MacClipboardManager.swift:551` の
`validator: typeValidator` という配線が正しいことは、現状どのテストも保証していない。

---

## 軽微な指摘（low）

### L-1. L-7（削除跡の空行）が 1 箇所も直っておらず、2 箇所増えた

v11 が挙げた 4 ファイルすべてで残存。

| ファイル | 行 |
|---|---|
| `mac/MacLibrary/MacLibraryTests/Clipboard/Mock/MockClipboardTypeIdentifierValidating.swift` | `:19-20`（連続空行）、`:26`（閉じ括弧前） |
| `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift` | `:55-56`、`:352-354`、`:425-426` |
| `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift` | `:197-199` |

今回の L-5 修正で新たに増えたもの。

| ファイル | 行 |
|---|---|
| `mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift` | `:394-397`（**中身が空の `// MARK: - Privacy`** と 3 連続空行）、`:443-444` |

`git diff develop --check` は空白の種類しか見ないので 0 件のまま通る。

### L-2. BT-26 / PT-16 が設計に存在しない ID

- `UnityMacClipboardBridgeTests.swift:72` の `BT-26` は §12.4 に行が無い。同じ内容の **BT-03 が §12.4 に既にある**
- `ClipboardPasteLoaderTests.swift:520` / `:540` の `PT-16` は §12.3 に行が無い（§12.3 は PT-15 まで）

設計の ID 体系とテストの ID が二重管理になっている。検査 14（ID 参照の実在）は設計書内の参照しか
見ないので、「テストにあって設計に無い ID」は原理的に検出できない。設計に行を足すか、既存 ID
（BT-03）を使うかのどちらかに寄せること。

### L-3. `argumentError(_:)` は空文字列も 1302 にする

- 該当: `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:83-88`

```swift
guard let raw, !raw.isEmpty else {
    return .contractViolation(reason: "A required argument was missing.")
}
```

設計 §8.4.1（`:1156-1157`）は「**必須引数が NULL** → 1302」「**JSON パース失敗** → 1301」であり、
空文字列には触れていない。`""` は「送られてきたが JSON ではない」ので 1301 のほうが素直である。
BT-26（`:90`）が `read(scopeJson: "")` を 1302 として固定しているため、この解釈がテストで確定している。
設計側に「NULL または空文字列」と 1 行足すか、実装を `raw == nil` のみに絞るか、どちらかに合わせること。

### L-4. `ClipboardTypeIdentifierValidator` が 2 インスタンス生成される

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:96` と `:99`

`ClipboardRepositoryImpl` と `ClipboardUseCases` / `MacClipboardManager` が別インスタンスを持つ。
stateless なので実害は無いが、理由も無い。v11 M-5 の付記が未対応。

### L-5. `.h` の HeaderDoc は DocC テストの対象外

- 該当: `mac/MacLibrary/MacLibraryTests/Clipboard/ClipboardDocumentationTests.swift:37`
  （`where url.pathExtension == "swift"`）

M-4 の修正で走査範囲は両ツリーへ広がったが、`.h` は依然として対象外である。
`mac.md`「コメント（DocC / HeaderDoc）」は `.h` の公開関数宣言・callback typedef にも HeaderDoc を
必須としている。現状は全て書かれているので違反は無いが、H-2 のような**ヘッダ側の欠落**を
検出する仕組みは存在しない。DoD `:1783` の「`public` シンボルすべてに英語の DocC が付いている」を
支える検査が、C 境界を見ていない。

### L-6. `ClipboardChangeMonitor.deinit` が main actor 隔離の `pollTask` を nonisolated から触る（要確認）

- 該当: `mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardChangeMonitor.swift:48-53`

```swift
deinit {
    pollTask?.cancel()
    activeObservers.removeAll()
}
```

`activeObservers` は「nonisolated deinit から安全に触れる箱」に逃がしたのに、同じ deinit で
`@MainActor` 隔離の stored `var pollTask` を直接読んでいる。`Task` は `Sendable` なので現行の
Swift 5 言語モードでは診断は出ず、strict build も 0 件だった。monitor は `MacClipboardManager` からしか
到達できず main actor 上で解放されるため実害は無い。ただし Swift 6 言語モードへ移行した時点で
扱いが問題になる可能性がある。`ObserverTokens` と同じ理由付けが `pollTask` にも要るのか、
不要なら deinit のコメントにその根拠を書いておくのが望ましい。

なお `ObserverTokens`（`:173-193`）自体はレビューした範囲で問題ない。`removeAll` はロック内で
トークンを取り出してからロック外で `removeObserver` を呼ぶので再入デッドロックは起きず、
`stop()` / `deinit` / restart（`start` が先頭で `stop()` を呼ぶ）のいずれの経路でも解放漏れと
二重解放の双方が防がれている。

---

## 設計書整合性チェック

| 項目 | 判定 | 根拠 |
|---|---|---|
| 企画書との整合性 | ○ | §2.1 の API ID 対応表と実装の公開範囲が一致 |
| Clean Architecture 準拠 | ○ | 層構成・依存方向・Port の Domain 値型限定・delegate の単一所有はすべて適合。v11 M-5（Manager → Data の具象生成）は注入化で解消 |
| 既存実装との差分分析の正確性 | △ | §6.1 は実ツリーから再生成され完全一致。ただし §4.1（`Coordinator/`）・§6.5.1（`ClipboardPasteHandle.swift`）・§7.9 / §9（`Timer`）が実装と乖離（M-2 / M-3） |
| テスト設計の網羅性 | × | BT-01 / 05 / 08 / 10 / 12 / 22 / 23 と CT-02 / CT-05 が未実装のまま DoD [x]（H-1）。`MacClipboardManager.makePasteButton` を通る経路が 0 件（M-7） |
| ドメインエラー全ケース実装 | ○ | 20 ケースすべて実装され、`ClipboardErrorTests` / `ClipboardDocumentationTests` が全件を固定 |
| エラーコード / メッセージ対応表との整合 | ○ | 1501〜1515 / 1521〜1524 / 1599 が §11 と 1 件ずつ一致（検査 11 で確認）。1516〜1520 は欠番のまま。ただし逆向き（設計にあって実装に無い行）は未検査（H-4c） |

## プロジェクトルール適合チェック

| 項目 | 判定 | 根拠 |
|---|---|---|
| common.md 準拠 | ○ | 層・依存方向・Port の型制約・delegate 所有・同期非同期設計・Manager の callback + native 併設すべて適合 |
| mac.md 準拠 | ○ | `Log.d` 先頭 1 行は今回の 5 件修正で解消（`ClipboardDetectionMapper` / `ItemProviderSource` を確認）。`public` DocC は両ツリーで検査。`BOOL` / `NSInteger` / `const char*` 規約も適合。`.h` の nullability（H-2）は mac.md の型表そのものには抵触しない |
| エラー契約反映 | ○ | 1301 / 1302 の切り分けが実装され BT-26 で固定。`ClipboardError` → 数値変換は Manager callback 1 箇所に閉じている。ただし encode 失敗の扱いが 3 経路で非対称（M-4） |
| 既存 API 互換性 | ○ | 破壊的変更なし。`BridgeError` は DocC のみ変更。`MacClipboardManager` の injecting init は internal、`ClipboardTypeIdentifierValidating.isValidFileType` の削除は未公開 API 内の整理 |

## テストカバレッジ

**カバーできている観点**

- UseCase 全 14 本 + Validator / Tracker の正常系・異常系・境界値
- 実 `NSPasteboard` 統合 IT-01〜IT-11 / IT-20 / IT-50
- Presentation PT-01〜PT-16（PT-16 で `PasteButtonFactory` の失敗経路・成功経路が入った）
- JSON 17 型の round-trip を `ClipboardJson` の宣言そのものから導出（BT-11）
- BT-26（必須引数 NULL = 1302 / 不正 JSON = 1301）を実際の callback で確認
- BT-21 のブロック捕捉監査がブロック本文単位の解析に書き直され、`audited >= 15` で空回りも塞がれた
- BT-25 のログ秘匿監査は signature から対象を導出しており、`auditCoversEveryEndpoint` で監査自身の網羅も固定
- CT-01 strict build 差分 0 件、CT-04 / CT-07

**不足している観点**

- **Bridge の実挙動テストが依然としてほぼ無い**: BT-01 / BT-05 / BT-08 / BT-10 / BT-12 / BT-22 / BT-23。
  「任意スレッドから呼んで main で exactly-once」を実行するテストが 1 件も無い（H-1）
- CT-02 / CT-05 に対応するアサーションが見当たらない（H-1）
- `MacClipboardManager.makePasteButton` を通る経路が 0 件（M-7）
- `.h` の HeaderDoc / nullability を検査する仕組みが無い（H-2 / L-5）
- 機械照合の自己検査: 検査本数と SKIP を exit code に反映する手段が無い（M-5）

---

## 総合評価

**要修正（重大）**

- high 4 件 / medium 7 件 / low 6 件
- 数値検証（テスト件数・警告 0・strict build・機械照合 28/28 SKIP 0・`--check` 0）はすべて再現できた
- v11 の 18 件は **反映 9 / 一部 7 / 未対応 2**。コード側の実害ある欠陥（無言破棄・1301/1302・層違反・
  observer 蓄積・空回り監査）はすべて解消しており、この 5 件の修正内容は妥当である
- 一方、**結果レポート v13 の反映表は M-1 / M-2 / L-2 / L-6 / L-7 について実態より進んだ状態を記載している**。
  特に L-2（設計の `Timer`）と L-7（削除跡の空行）は「対応した」とされているが 1 箇所も変わっていない
- **28 検査には実証済みの false green が 3 パターン残る**（H-4）。v11 H-1 の対処案 2 つのうち
  「宣言位置での照合」を採っていれば (a) と (b) の両方が閉じていた
- **DoD が [x] としている Bridge / 並行性テストのうち 9 件に実体が無い**（H-1）。v11 H-3 で同じ表を
  指摘されており、2 ラウンド連続で未対応である

### 優先順位

1. **H-1**（DoD が主張するテストを実装するか、チェックを外す）
   — 「検証済み」と書かれた契約が検証されていない状態が 2 ラウンド続いている
2. **H-4**（検査 12 を宣言位置照合に変え、検査 11 に逆向きを足す）
   — これを直さない限り、次ラウンドでも別の語で同じ形の取り残しが出る
3. **H-2 / H-3**（公開契約の記述。ヘッダの nullability と OP-19 の失敗条件）
4. **M-5 / M-6**（機械照合の自己検査。SKIP と件数を exit code に反映する）
5. **M-1 / M-2 / M-3**（設計書の現行章と実装の一致。§15 の 4 行、§4.1、§6.5.1、`Timer` 5 箇所）
6. **M-4 / M-7**、その後 low

### 手順への注記

結果レポート v13 §7.1 は「レビュアーを固定しない」「検査を書いたら必ず落ちることを確認する」を
教訓としているが、今回の 18 件一括修正では **修正したと報告した項目の再確認**が抜けている。
L-2 と L-7 は設計書とソースを grep するだけで未対応と分かる。反映表を書く前に、
指摘 1 件ごとに「該当行が実際に変わったか」を diff で確認する手順を足すこと。
