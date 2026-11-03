# 段階 2 の作業の記録（C ABI の実装）

- 記録日: 2026-11-03
- 段階: 2（`README.md` の 5 章。設計書は `designs/2026-11-03-ios-c-abi-c-abi-design-part2.md`。以下「第 2 部」）
- ブランチ: `feature/NTKIT-18`
- 環境: Xcode 26.3（`xcode-select` のまま）。単体テストは Xcode 26.6

## 1. TB-0（第 2 部 7 章）

### 1.1 `IosLibrary` に足したもの

| 決定 | 変更 | Swift の利用者から見ると |
|---|---|---|
| P2-6 | `removeDelivered`、`removeAllDelivered`、`cancelScheduled`、`cancelAllScheduled` に `completion: (@MainActor @Sendable () -> Void)? = nil` | 普通の呼び出しは同じ。関数の参照は組めなくなる（Swift の設計書 3.3） |
| P2-12 | `nonisolated public static func cancelLoad(_ box: RequestBox)`。インスタンスの形はこれを呼ぶ | 足しただけ |
| P2-26 | `NotificationTrigger.isValid`、`NotificationError.invalidTrigger`。Repository の `checkTrigger`（userInfo の後、添付の前） | **落ちていた `timeInterval` だけが失敗になる**。`NotificationError` の `switch` に case が要る |
| 7 章 | `show`、`update`、`schedule` の DocC に、権限が無いと成功を返して残らないこと（M2）。`PresenterSelection` の古い Note を消した | 文書だけ |

- `cancelLoad(_:)` の DocC のリンクは、インスタンスと `static` で曖昧になるので文字にした（`cancelLoad(_:)`）。docbuild の関係する警告は 0 件
- `invalidTrigger` は Domain（`NotificationError`）、`isValid` は Domain（`NotificationTrigger`）に置いた。`Foundation` のほかを import しない

### 1.2 公開 API の差

`results/swiftinterface/IosLibrary-after-tb0.swiftinterface`、差分は `2026-11-03-stage2-tb0.diff`（`after-1b-c6` から）。足した `static cancelLoad`、`invalidTrigger`、`isValid` と、4 つの関数の `completion`（前の宣言が 4 行消える）だけ。

### 1.3 テスト

| 実行 | 結果 |
|---|---|
| `IosLibraryTests`（iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3。Xcode 26.6、`-parallel-testing-enabled NO`） | どれも 563/563（548 + 15）。警告 0 |
| TSan（`NotificationRepositoryTriggerCheckTests`、`IosNotificationManagerCallFormTests`、`IosClipboardManagerRequestBoxTests`。iPhone 17 Pro / 26.2） | 通った。報告 0 件 |
| サンプルと UI テストの `build-for-testing`（Xcode 26.3） | 組めた。UI テストは変えていないので流していない（全件の基準の取り直しは段階 2 の区切りで）。サンプルは `switch` の 1 行だけ |

### 1.4 壊して確かめたこと（使い捨ての写し）

| # | 壊し方 | 落ちたテスト |
|---|---|---|
| M167 | `isValid` が 0 を通す | `isValidIsFalseOnly…` |
| M168 | 繰り返しの下限を 59 に | 同上 |
| M169〜M171 | `show`、`update`、`schedule` の確かめを外す | プロセスが落ちる（`NSInternalInconsistencyException`） |
| M172 | 完了を Repository の前に呼ぶ | 1 回目は生き残った。Repository を止めるテストを足し、`theRemovalFormsCompleteOnlyAfterTheRepositoryReturned` で落ちる |
| M173、M174 | 完了を呼ばない、2 回呼ぶ | `theRemovalFormsComplete…` |
| M175 | `static` が箱を閉じない | `aBoxCancelledBefore…` ほか |
| M176 | `invalidTrigger` の文言を変える | `everyCaseHasItsOwnFixedDescription`、`theTriggerCaseHasItsText` |
| M177 | `schedule` の確かめを添付の後へ | `theTriggerIsCheckedBeforeTheAttachments` |

**`.private` はテストで守れない**: レビューの提案で UT-15 に位置の trigger の番兵を足すと、`.private` の行でも落ちた。プロセスの中から `OSLogStore` で読むと `.private` の値も見えるので、`.private` と `.public` を区別できない（足した行は外した）。`checkTrigger` の `.private` はレビューと目で確かめた。**見え方は 2.0.0 の前の実機の区切り（MS-13）で確かめる**。UT-15 が守るのは、値をログに出さない行だけ。

### 1.5 レビューと直したこと

レビューは 2 本（Claude: コードと文書、Codex: 並行と隔離）。Codex は A も B も無し。Claude は A 1、B 9、C 8 で、コードの動きの誤りは無かった。

| 指摘 | 対応 |
|---|---|
| A: `checkTrigger` のログが trigger を `.public` で出し、位置の緯度と経度が平文になる | `.private` にした（テストでは守れない。1.4） |
| B: 第 2 部 7 章の行の未対応（第 1 部 8 章と 5.7、1b の記録の B-1、Swift の設計書 10.1） | 直した |
| B: `update`、`schedule` の DocC | 足した |
| B: `checkTrigger` が添付より前であることを守るテストが無い | `theTriggerIsCheckedBeforeTheAttachments` |
| B: インスタンスの `cancelLoad` に先頭のログが無い | 足した |
| B: 関数の参照の破壊が書かれていない | Swift の設計書 3.3 |
| C | 文面、`completion` のログの語、Manager を通した `invalidTrigger` のテスト、`update(trigger: nil)`、文言のテスト |

途中で次の失敗があった: 1 回目に足した順序のテストは 1 つの `AsyncStream` を 4 つのタスクで待ち、iOS 18.3 で完了が来ずに落ちた。`Mutex` の印を待つ形に直した。

## 2. TA-1 と TA-2

### 2.1 足したもの

| タスク | ファイル | 中身 |
|---|---|---|
| TA-1 | `scripts/check_c_abi_contract_ios.py` | 12.3 の照合。`--design-only` は付録 A を読み、`ios/IosLibraryCApi` の下に `.h` が 1 つでもあれば落ちる。`--library` は `nm -arch all -gU` の結果を `_ntk_*`（8.2）とアーキテクチャごとに比べ、`_ntk_` で始まらないものも落とす（第 1 部 5.5）。`--architectures` で持つべきスライスを指定する。実行権限あり |
| TA-1 | `scripts/c_abi_error_numbers.json` | 機能ごとの名前 → 番号。Dialog 11、Notification 21、Clipboard 30、Share 22 の計 84 名（0〜5 を含む。11.5）。11.1〜11.4 と Android のヘッダーから作った。同じ名前で番号が違うものも、1 つの番号に 2 つの名前が付くものも無かった |
| TA-1 | `scripts/c_abi_contract_common.py` | `common_header_problems` を N 個の OS に（`{OS: 本文}` と OS ごとに許す定数の表）。番号の表の読み取りと `check_error_numbers`。`check_functions`、`takes_callback`、`is_listener`、`check_ascii` を Android の照合から移した。`declarations` が読めないものを `unread` に入れ、`check_signatures` で落とす。`directive_problems` の `include_blocks`。`op_range` は区切りごとに読む |
| TA-1 | `scripts/check_c_abi_contract_android.py` | 結果は `numbers` の行が増えただけ（2.3）。同じオプションの 2 回目は使い方の誤り |
| TA-1 | `scripts/tests/test_check_c_abi_contract_ios.py` | 215 件（新規）。Android は 76 → 87 件、Windows は 20 → 22 件 |
| TA-2 | `scripts/check_manual_c_examples_ios.py` と `scripts/tests/test_check_manual_c_examples_ios.py` | Android と同じ形。Xcode の clang（`xcrun --find clang`）と iOS の SDK で `arm64-apple-ios18.0` に `-fsyntax-only`。テスト 33 件（Android は 21 → 22 件）。coverage は `NativeToolkitC/*.h` を全部読む（Android も） |
| TA-2 | `scripts/manual_c_examples_common.py` | 章の見出しを行全体で読む、近い見出しを落とす、節は次の `###` で終わる、コメントの中の名前を宣言と数えない |
| 両方 | `scripts/README.md` | 2 つの照合、番号の表、`Common.h` の流し方。件数を 614 に（前の 337 は既に古かった。今回の追加の前で 352） |

- **番号の照合の規則**: 各 OS のヘッダーの `NTK_<機能>_ERROR_*` は表に同じ番号である。表に無い機能は落とす。ある OS に無い名前はその OS の欠番。iOS の照合だけが両方の OS を読むので、**どちらの OS も宣言しない名前**も落とす（Android の照合は自分のヘッダーだけを見る。P1-7 のとおり両方を流す）。`Android.h` の `NTK_ANDROID_ERROR_*` は表の外。Windows は対象外
- **`Common.h`**: iOS の照合が 3 つの OS を比べ、Android の照合は今までどおり Android と Windows を比べる

### 2.2 照合が見つけたこと、設計書への変更

| # | 見つけたこと | 対応 |
|---|---|---|
| 1 | 付録 A の機能のヘッダーが `#include "Common.h"` で、第 1 部 5.2 の `__has_include` の形と違った | **設計書の持ち主が付録 A を 5.2 の形に直した**（2a の後の版）。照合は付録 A とヘッダーの両方にこの形を求める |
| 2 | 11.5 の JSON の例が Dialog を 6 から書いていた | **持ち主が 0〜5 も表に入れると 11.5 に書いた** |
| 3 | `declarations` が `1u << N` を読み違えていた（どのビットも値 1）。Android と Windows のヘッダーに `<<` の定数は無く、iOS で初めて踏む | 共通の読み取りを直した。後に形を厳しくした（2.5 の A1） |
| 4 | 11.1 だけ `DialogError.invalidRequest` と型名つきで書いている | 書き方の違いとして読み分けた。別の型の名前は数えない |
| 5 | PR-02 は `イベント` の行に `OP-44`（解除）を持つ | 表のとおりに読む。受け手を足さない行は落とす |
| 6 | **帳簿の行を書けば Swift の口の照合を抜けられた**（2.5 の B-1）。行の形だけでは OP-16 と OP-42 を区別できない | **8.1 の前文に 1 文足した**: 「（受け口の帳簿）」の行は OP-16、OP-17、OP-44 だけで、Swift の口を呼ばない（2a が読む）。これが今回こちらで変えた設計書の唯一の箇所 |

### 2.3 コマンドと結果（2 回のレビューの直しの後）

```
python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_*.py'    # Ran 324 tests  OK（iOS 215、Android 87、Windows 22）
python3 -m unittest discover -s scripts/tests -p 'test_check_manual_c_examples_*.py'  # Ran 67 tests  OK（iOS 33、Android 22、Windows 12）。skip なし
```

| コマンド | 結果 |
|---|---|
| `python3 scripts/check_c_abi_contract_ios.py --design-only` | exit 0。FAIL 0。関数 134、操作 46、Swift の口 43（46 から受け口の帳簿の 3 つを除く）、BH 37・EV 3・RG 6・PR 3（同期の結果 3、受け付けた後の完了 40、イベント 4、登録と解除 2）、case 49、番号 84 名。SKIP は `signatures` と `symbols` |
| `python3 scripts/check_c_abi_contract_android.py` | exit 0。FAIL 0。SKIP は `symbols` |
| `python3 scripts/check_c_abi_contract_windows.py` | exit 0。FAIL 0 |
| `python3 scripts/check_manual_c_examples_ios.py` | exit 0。`SKIP the manual has C examples: no page under manual/1.13.0 has an iOS C ABI section` |

**`git show HEAD:` の版との比較**（HEAD の 6 つのスクリプトを写して `--root` で同じ木に向けた）:

| 比べたもの | HEAD | 今 | 出力の差 |
|---|---|---|---|
| Android の照合 | exit 0 | exit 0 | `numbers` の 1 行だけ |
| Android の照合 `--design-only` | exit 1 | exit 1 | `numbers` の 1 行だけ（`design only` の FAIL は前から。Android のヘッダーが既にあるため） |
| Windows の照合 | exit 0 | exit 0 | 無し |
| マニュアルの Android、Windows（1.13.0、1.12.0、1.11.0） | exit 0 | exit 0 | 無し |

全件（614 件）は流していない。数えただけ（`TestLoader` で `countTestCases`）。

### 2.4 1 回目の変異（使い捨ての写し）

- **最初の結果 50/50 は誤りだった**: 落ちた名前が空だったので変異を入れない回を足すと、それも「落ちた」。写しの場所を相対で渡していて、テストが 1 件も流れていなかった。直して変異なしの回が通ることを確かめてから流し直した
- 流し直しの結果は 43/50。残った 7 つはテストを足すか、余分な判定を消して塞いだ（`同上` の行、`nm` の並び、0〜5 の全機能、`true`、`_MSC_VER`、表の列、行の形の判定）

### 2.5 レビュー（2 本）と直したこと

Claude と Codex のレビューを受けた。それぞれ実物で確かめてから直した。**A と B に退けたものは無い。**

| 指摘 | 確かめたこと | 直し |
|---|---|---|
| Codex A1、Claude A-4: 初期値を一部だけ読む（`1u << 1 \| 1` は C では 3、読むと 2。`21 + 1`、初期値なしは読まれない） | Android の照合が exit 0 で通った | 項目ごとに `fullmatch`。文法の外は `unread` で、`signatures` が落とす。Android の実行、Windows の実行にもテストを足した |
| Claude A-3: どの形にも合わない文を黙って捨てる（`NTK_CALL` なしの関数、`extern`、素の `struct`、`static inline`） | 5 つとも `rc=0`。実物のヘッダーに `unread` は 0 件（テストで固定した） | `unread` に集めて落とす |
| Codex A2、Claude A-5: include の形の中に宣言を隠せる。`extern "C"` の内側に移せる | 5 行の `#` の並びしか見ていなかった。前の私のテストは新しい関数を足していたので、名前のとおりのことを確かめていなかった | 形の範囲の本文に `#` 行のほかが無いこと、最初の `#ifdef __cplusplus` より前にあることを見る。付録 A にある宣言を枝に移す形でテストする |
| Codex A3、Claude A-1: `nm -gU` は fat の host のスライスだけ。空のスライスに節ができない | **macOS の fat の dylib で本物の `nm` を流して確かめた**（`-gU` は見出しなしで arm64 だけ。`-arch all` は空のスライスも見出しを出す） | `-arch all`、見出しで空の節を作る。偽の `nm` を本物と同じ振る舞いに（`-arch all` でなければ host の分だけ）。**本物の `nm` と `lipo` を使うテストを 3 件足した** |
| Codex B4、Claude A-2: 雛形が付録 A を二重に包み、テストが赤い。`signatures` のテストがどの木でも通る | 153 件中 5 件が落ちていた | 付録 A をそのまま書く。**`setUpClass` で壊さない木に FAIL が無いことを確かめる**（Android にも）。`reports` で照合の名前を行の先頭で比べる |
| B-1: 帳簿の行で抜けられる | `rc=0` だった | 帳簿の行は受け手か解除の関数だけ。8.1 の前文の一覧と比べる（2.2 の 6） |
| B-2: `cases` が基準の写しだけを読む | ソースに足しても通った | 4 つのソース（`ios/IosLibrary/...`。読むだけ）と基準が同じ集合であることを見る |
| B-3: 表の古い case を見ない | `rc=0` だった | 表にあって case に無いものを落とす（除くのは `.success`、`.firstActiveScene`） |
| B-4、B-5、B-6: 付録 A の形を見ない、`#include` が何でも通る、版の値を比べない | `rc=0` だった | `shape` の行を足し、付録 A に同じ規則と `unread` を当てる。ヘッダーの `#` 行は付録 A と同じ（`#define` の値も含むので B-6 も塞がる） |
| B-7: `--library` の重ね、スライスの欠け | `rc=0` だった | 2 回目は使い方の誤り（iOS と Android の 4 本）。`--architectures` を足した（薄いバイナリは Mach-O の見出しで読む） |
| B-8、B-9: `### iOS` を章と読む、coverage が手書きの一覧 | `SKIP`、`rc=0` だった | 行全体で読む。近い見出しを落とす。`*.h` を全部読む |
| B-10: 落とせないテスト | 確かめた | `cannot be compared` を見る、`Common.h` の struct と値、`typeof`（`-std=c99`）、`__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__`（`--target`）、11.5 を読んで比べる |

**C の扱い**:

| C の指摘 | 扱い |
|---|---|
| `op_range` の過剰な読み、`_` のある機能の接頭辞、同じ行の `@available`、`/* */`、`rglob("*.h")`、`--nm` だけ、`declared_names` のコメント、次の `###`、実行権限、`ERROR_TABLES` の重複 | 直した |
| README の 43 | 8.3 の行数と比べ、10 章の B の列と 8.3 の ID が同じことも見る |
| docstring に範囲外を書く | 書いた |
| **README の 6 と RG の数を比べる** | **退けた**。数が合うのは偶然（RG-01 はブリッジの 2 つをまとめ、RG-02 は新しい行。README の 6 と行が対応しない） |
| **`static` を両方向に見る** | **退けた**。OP-25 の `installDelegate()` は swiftinterface で `static` だが、8.1 の行に書いていない。行が言うときだけ見るのが今の表の書き方 |
| 2 つの BH の行の OP の入れ替え、8.1 の C 関数の引数の文 | 直さない。同じ形の OP のどちらが正しいかは機械で分からない。docstring に書いた |
| `NTK_SHARE_FAILURE_X`（`_ERROR_` を含まない名前）の iOS の実行 | 直さない。名前では分からず、Android の実行が付録 A との比較で落とす |

### 2.6 最後の変異

レビューの 64 個（`mt.py`）と 1 回目の残りと今回の直しの分を合わせて、重ねを除いた **125 個**を使い捨ての写しで流した。変異なしの回が通ることも毎回確かめた。

- **123 個が落ちた**（全部の回で 120 個。アンカーが古かった 2 個と、テストを直した 1 個は、その 3 個だけ流し直した）
- **残った 2 個はどちらも同じ動きの変異**:
  - `-x c` を外す: 書き出すファイルが `.c` なので同じ。Android と同じ形に保つため旗は残した
  - `check_signatures` の `elif got is None` を外す: 次の `elif want != got` が同じ入力で落とす（文言だけ違う）
- 全部の回の途中で残ったものは、消した判定 1 つ（`macros` の比較。`#` 行の比較と同じだった）とテストの追加で塞いだ（`found` の枝、`Common.h` の形、`ascii` の空、帳簿の形、Android のマニュアルの 2 回目、`*.h` の探し方）

レビューの壊し方（入力を壊す `m1`、`m2`、`m4`、`m8`。ソースを写すように直して流した）を流し直すと、通るのは次のものだけで、どれも説明がつく。

| 通るもの | 理由 |
|---|---|
| OP-26 の行が `async throws` を書かない、OP-24 が `static` だけになる | 行が言うときだけ見る（2.5） |
| swiftinterface の `internal` の関数 | swiftinterface に public でない宣言は出ない |
| 同じ名前の型の中の入れ子の case | `ShareError` の case ではない。正しく通る |
| BH の行の入れ替え、`OP-01〜OP-02、OP-10`（どれも完了の形）、8.1 の引数の文 | 2.5 の範囲外 |
| README の 6 | 2.5 で退けた |
| 番号を表、ヘッダー、付録 A、11 章ですべて揃えて入れ替える | **残っている**（下） |
| Windows の `Common.h` のコメント | 変えていないのと同じ。正しく通る |
| `NTK_SHARE_FAILURE_X`（iOS の実行） | Android の実行が落とす |
| スライスを丸ごと失う（`--architectures` なし） | `--architectures` で見る。TB-11 で渡す |
| `### iOS` が前にあるページ（今は節を読んで通る）、`### Plain C`、`### Other`、コメントだけの差 | 正しく通るか、`--require-examples`（2.0.0 から）で落ちる |

### 2.7 動かせなかった照合、残っているもの

- **`signatures` と `--design-only` なしの全行は、本物のヘッダーで流せていない**（TB-1 の前）。付録 A から作った木でだけ通る
- **`symbols` は本物の xcframework で流せていない**（TB-11 の前）。本物の `nm` は macOS の dylib で確かめた（iOS は組まない約束）。実機のスライスは thin、シミュレーターのスライスは fat と考えて `--architectures` を作った
- **TA-2 の `compile` は本物の例で流せていない**（段階 4 の前）。`-I include` では `__has_include` が偽になり `"Common.h"` の枝を通るので、framework の枝は TB-1 のコンパイルまで試されない
- **「出した番号は変えない」（第 1 部 5.10）を止めるものは無い**: 表とヘッダーと設計書をすべて揃えて変えると通る。2.0.0 の前は問題にならないが、リリースの後は穴になる。出した版の表を固定するかを決める必要がある
- **依頼の範囲の外なので足していないもの**: 第 1 部 5.5 の H = E、E = P、capi の C のソース、module map の並び、`Headers/` と `Modules/`。12.3 のヘッダーだけのコンパイル。12.1 の「8.2 の名前がテストのソースに現れる」（13 章で TB-1、TB-11 に割り振られている分を含む）
- `check_ios_dist.py` と `test_ios.sh` はまだこの照合を呼ばない（TB-11、TB-12）
- 指定の外で流したもの: マニュアルの照合の Android と Windows（共通のモジュールを変えたので HEAD と比べるため。読むだけ）。macOS の dylib を clang と `lipo` で組む自己テスト（写しの中で。iOS のプロジェクトは組んでいない）

## 3. TB-1

### 3.1 足したもの

| 区分 | ファイル | 中身 |
|---|---|---|
| ヘッダー | `ios/IosLibraryCApi/include/NativeToolkitC/` の 5 つ | 付録 A のコードブロックをそのまま書き、先頭に `@file` のコメントだけ足した。**コメントを除いた本文が付録 A とバイト単位で同じ**ことを一度比べた（5 つとも一致）。第 1 部 5.2 のとおり、先頭のコメントに `ntk_notification_install` の例外を書いた |
| 公開の一覧など | `IosLibraryCApi/module.modulemap`、`IosLibraryCApi/IosLibraryCApi.exp` | 第 1 部 5.1 の形（`_ntk_*` の 1 行） |
| Common | `CommonEntry.swift`、`Handle.swift`、`CApiString.swift`、`CApiLog.swift` | 11 関数。ハンドルは型ごとに別のクラス（違う型の読み取りは `NULL` か 0。R-30）。出力の文字列だけ（入力の `CApiString` は TB-2）。ログのカテゴリは `Common` と `Notification` だけ |
| Notification | `NotificationEntry.swift`、`NotificationReceiver.swift` | `ntk_notification_install` だけ。`.installed` → `NONE`、`.notMainThread` → `WRONG_THREAD`。`NotificationDelegateInstallResult` は別のモジュールから `@frozen` でないので `@unknown default`（`UNKNOWN` とログ。今は通らない） |
| プロジェクト | `ios/IosLibraryCApi/IosLibraryCApi.xcodeproj`（scheme は `IosLibraryCApi`）、`IosWorkspace.xcworkspace` に 1 行 | 第 1 部 5.4 の設定。雛形の xcodeproj の gem（1.25.1）は synchronized group を書けないので、`IosLibrary` と同じ形（objectVersion 77、synchronized group、`IosLibrary.framework` を `BUILT_PRODUCTS_DIR` で参照して暗黙の依存）で書いた。生成に使った手元のスクリプトは入れない。入るのは `project.pbxproj` だけ |
| テスト | `ios/IosLibraryCApiTests/`（`CommonEntryTests.swift`、`NotificationInstallTests.swift`、`StructLayoutTests.m`、`TestThreads.swift`）、`ios/IosLibraryCApiTestHost/` | XCTest 25 件と、配置の `_Static_assert` 147 行（`StructLayoutTests.m`。ビルドで効くので XCTest の件数に入らない。3.7 の C-1）。ホストは権限を求めない専用のアプリ（bundle id は `...IosLibraryCApiTestHost`） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `entries`、`complete`、`public`、`modulemap`、`compile`、`layout`、`settings`、`install` を足した（3.3）。`NOT_IMPLEMENTED_YET` |
| 照合の自己テスト | `scripts/tests/test_check_c_abi_contract_ios.py` | 215 → 277 件。雛形の木に capi のソース、プロジェクト、配置のテストを写す |
| 文書（この作業） | 第 2 部の TB-10、TB-11、TB-12 の行、`scripts/README.md` | `--require-complete`、`--require-compile`、capi の xcframework は Release だけ。照合の説明、件数を 676 に |
| 文書（別の作業） | 第 1 部 5.1、5.4、第 2 部の P2-26、8.4、9 章 | **この実装ではなく、メインのセッションが直した**。第 1 部は 5.1 の木に `IosLibraryCApiTestHost/`、5.4 に Debug の違い（3.2）。第 2 部の 3 か所は `check_design_consistency.py` の 3 件が消える形（3.6）。理由はここでは確かめていない |

- **実装した関数は 12 個で、依頼の 13 個ではない**: `Common.h` の 11 と `ntk_notification_install`。付録 A の `Common.h` の関数は 11（`ntk_version`、`ntk_last_system_code`、`ntk_string_*` 3、`ntk_bytes_*` 3、`ntk_string_list_*` 3）で、数え違いがあるとすれば依頼の側。一覧は 122 個
- **`MainQueue.swift` は作っていない**: `ntk_notification_install` は積まず、`installDelegate()` がスレッドを見る。TB-1 で使う所が無いので、使う人のいない関数を足さず TB-2 に送る。`Clipboard/`、`Dialog/`、`Share/` のフォルダーも中身が来るまで無い（git は空のフォルダーを持てない）
- `IosLibraryCApiTestHost` は、`IosLibraryCApiTests` が synchronized group で、その中に置くとテストのターゲットに入るので、`IosLibraryTestHost` と同じくテストと並べた。実装のときは第 1 部 5.1 の木に無く、今は 5.1 に行がある
- `MARKETING_VERSION` は 2.0.0、`IosLibrary` は 1.3.0 のまま。P1-19 の「同じ版の組」の確かめは TB-2（C-9）と TB-11 で、版を上げるのはリリースの作業

### 3.2 第 1 部 5.4 の Debug の違い（実装者の提案。持ち主の承認待ち）

**`@testable import IosLibraryCApi` は、第 1 部 5.4 の設定のままでは使えない**。第 2 部 12.1 はこれを前提にしているが、確かめられていなかった。TB-1 でも、公開の関数でハンドルを作る口がまだ無いので `Handle.make*` を呼ぶのに要る。

| 設定 | 起きたこと |
|---|---|
| `SWIFT_INSTALL_MODULE=NO` | framework に `.swiftmodule` が無く、`@testable import` は **C の clang モジュールを黙って読んで成功する**。`Handle` が `cannot find 'Handle' in scope` になる |
| `EXPORTED_SYMBOLS_FILE`（`_ntk_*`） | Swift の内部のシンボルが出ないので、モジュールを見せてもテストがリンクできない |

**Debug だけを次にした（Release は 5.4 の表のとおり）**: `SWIFT_INSTALL_MODULE=YES`、`OTHER_LDFLAGS` に `-Wl,-exported_symbol,_$$s14IosLibraryCApi*`。`-exported_symbols_list` はそのままなので、Debug の公開シンボルは `_ntk_*` に `_$s14IosLibraryCApi*` が足されたものだけ。

**扱い**: この違いは**実装者の提案**で、第 1 部 5.4 の `SWIFT_INSTALL_MODULE` の行に書いてある（メインのセッションが書いた）。**2026-11-03 に持ち主が推奨のとおり決めた**。

**止め**: 5.4 の行は TB-11 の `Modules/` の照合を挙げるが、それはまだ無い。TB-1 では `settings` の照合が、Release の 5.4 の設定と、Debug との差がこの 2 つだけであること、archive が Release であることを見る（3.3）。TB-11 の行に、capi の xcframework は Release だけを受けると書いた（今のビルドのスクリプトは `--configuration debug` を受ける）。

**限り**: `_$s14IosLibraryCApi*` は標準の型の拡張（`$sSS14IosLibraryCApi…E…`）に当たらない。TB-2 以降で `extension String` を内部で足してテストから呼ぶと、テストのリンクで止まる（レビューの指摘。試していない）。

### 3.3 照合に足したこと

| ID | 比べるもの | 落ちる例 |
|---|---|---|
| `entries` | H と E（第 1 部 5.5）。`@c @implementation public func` の名前 | `NOT_IMPLEMENTED_YET` にあるのに入口がある、どちらにも無い、一覧にあってヘッダーに無い、入口があってヘッダーに無い、一覧の重なり。**一覧に名前を足す変更は通る** |
| `complete` | 一覧が空（H = E そのもの） | `--require-complete` のとき、一覧が空でない。旗なしは `SKIP`（`OK` の中に埋めない）。一覧に足して関数を隠す変更を止めるのはこれだけで、TB-10、TB-11、TB-12 が付ける |
| `public` | E = P。`public` と、宣言の `open` がすべて入口 | 入口でない `public`（内部の型のメンバーを含む）。コメント、文字列、`open` という名前のメソッドは数えない |
| `modulemap` | 第 1 部 5.1 の形だけを受け、`header` の集合 = `include/NativeToolkitC/*.h` | 抜け、余り、重なり、`private header` など別の形、`export *` なし。順は見ない |
| `compile` | 各ヘッダー × C99・C11・C++11・Objective-C × framework の枝と写しの枝で 40 回。`-Wall -Wextra -Werror -pedantic`、`arm64-apple-ios18.0`。**配置のテストを 3 つのスライス（実機の arm64、シミュレーターの arm64 と x86_64）で 3 回** | 言語ごと、枝ごと、旗ごとに落ちることを確かめた。Xcode が無ければ SKIP（TA-2 の照合と同じ）、`--require-compile` なら落ちる |
| `layout` | ヘッダーのすべての構造体と項目に、配置のテストの行がある。`#` の行が決まった 7 行だけ（`#if 0` や別の `#define` で行を無効にできない）。プロジェクトがこのファイルを名指ししない（synchronized group から外せない） | 行の抜け、余り、重なり、コメントにした行、読めない項目。数は `_Static_assert` がコンパイラーと比べる |
| `settings` | framework の Release が第 1 部 5.4 のとおり（プロジェクトの設定を継ぐものを含む）。Debug との差が 3.2 の 2 つだけ。条件つきの設定なし。archive が Release | `SWIFT_INSTALL_MODULE` を Release で戻す、Release に `-exported_symbol`、Debug の別の差、xcconfig（読めないので落ちる）。`MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS` と 5.4 の署名、ビルドの Xcode は見ていない |
| `install` | `NotificationDelegateInstallResult` の全 case に、受け口の `case .x:` がある | 新しい case（`@unknown default` があるのでコンパイラーは警告だけで、`UNKNOWN` になる） |
| `symbols`（変えた） | `_ntk_*` と 8.2 から一覧を引いたもの | 一覧の関数を公開した。**依頼には無いが、変えないと TB-10 まで本物のバイナリで `--library` が必ず落ちる** |

- `-pedantic` は 12.3 に無い。付けないと clang の `-std=c99` の意味がほとんど無く、付けても付録 A は通ったので足した
- **`--design-only` は本物の木で落ちるようになった**（`.h` があるので。予定どおり）。`entries`、`public`、`modulemap`、`compile`、`layout`、`settings`、`install` はその回では SKIP
- `signatures` が本物のヘッダーで初めて流れ、最初から通った（345 件の宣言）。**付録 A との食い違いは無い**

### 3.4 コマンドと結果

Xcode 26.6 は `DEVELOPER_DIR` で選び、`xcode-select` は 26.3 のまま。

```
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,id=<UDID>[,arch=x86_64]' -derivedDataPath <scratch> [-enableThreadSanitizer YES] test
```

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2、arm64） | 25/25（レビューの直しの後。直す前は配置の 4 件を含む 29/29） |
| 同（iPhone 16 / 18.3、arm64） | 25/25 |
| 同（iPhone 16 / 18.3、**x86_64**。Rosetta） | 25/25。配置の表はこのスライスでもビルドで効く |
| 同 TSan（iPhone 17 Pro / 26.2） | 25/25。報告 0 件。framework は `libclang_rt.tsan_iossim_dynamic` にリンクしている |
| framework の Release（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`） | 組めた。arm64 の thin。`Modules/` は `module.modulemap` だけ、`-Swift.h` なし |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`） | 組めた。x86_64 と arm64 の fat。同じ中身 |
| モジュールの検証 | Debug も Release も走った（`--language c`、`c++`、`objective-c`、`objective-c++`、`--standard c99`、`gnu11`、`c++11`、`gnu++17`） |
| テストの `build-for-testing`（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`） | 組めた。流していない（実機は使わない）。配置の表は実機のスライスでここで効く |
| 公開シンボル（`nm -gU`。Release） | 実機の arm64、シミュレーターの arm64 と x86_64 のどれも次の 12 個だけ: `_ntk_version`、`_ntk_last_system_code`、`_ntk_string_data`、`_ntk_string_size`、`_ntk_string_free`、`_ntk_bytes_data`、`_ntk_bytes_size`、`_ntk_bytes_free`、`_ntk_string_list_count`、`_ntk_string_list_at`、`_ntk_string_list_free`、`_ntk_notification_install` |
| `check_c_abi_contract_ios.py --library <実機> --architectures arm64` | `OK symbols`（12 symbols、1 architectures）。TA-1 の後で初めて本物の iOS のバイナリに当てた |
| `check_c_abi_contract_ios.py --library <シミュレーター> --architectures arm64,x86_64` | `OK symbols`（12 symbols、2 architectures） |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP は `complete` と `symbols`。関数 134、宣言 345、入口 12（残り 122）、module map 5、コンパイル 43、構造体 16、項目 131 |
| `python3 scripts/check_c_abi_contract_ios.py --require-complete` | exit 1。`FAIL complete`（122 個。今は落ちるのが正しい） |
| `python3 scripts/check_design_consistency.py`（第 2 部） | exit 0。FAIL 0（3.6） |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 277 tests、OK。116 秒 |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_manual_c_examples_ios.py'` | Ran 33 tests、OK。本物のヘッダーができても変わらない |
| `check_manual_c_examples_ios.py` | exit 0、`SKIP`（例が無い） |

**既存のものが変わっていないこと**:

| 確かめ | 結果 |
|---|---|
| `git status`、`git diff` | `ios/IosLibrary`、`ios/IosLibraryExample` に差なし。スキームのファイルも同じ |
| `xcodebuild -list -workspace`（26.3） | `IosLibrary`、`IosLibraryCApi`、`IosLibraryCApiTestHost`、`IosLibraryExample`、`IosLibraryTestHost`。足されたのは `IosLibraryCApi*` の 2 つ（`IosLibraryCApiTestHost` は `IosLibraryTestHost` と同じく自動の scheme） |
| サンプルの `build-for-testing`（26.3 と 26.6、`generic/platform=iOS Simulator`） | 組めた。ログに `IosLibraryCApi` は 0 行 |
| `IosLibrary` の `build`（26.3） | 組めた。ログに `IosLibraryCApi` は 0 行 |
| `IosLibraryTests` | 流していない。プロジェクトに触れていない |

### 3.5 壊して確かめたこと（使い捨ての写し）

**照合（1 回目）**: 57 個を、変異なしの回が通る（55 件）ことを確かめてから流した。**57/57 が落ちた**。`entries` の 5 つの判定と読み取り（`public`・`@implementation` なし、コメントを読む、探す場所）、一覧の増減（名前を消す、実装済みの名前を足す、知らない名前を足す）、`public` の 5 つ、`modulemap` の 7 つ、`compile` の 21 個（言語、標準、旗、枝、結果の無視、`--clang`、`--require-compile`）、`layout` の 7 つ、`symbols`、`--design-only`。一覧の増減は、壊さない木を確かめる `setUpClass` で落ちる。形を変えても契約を保つ書き方（複数行の入口、別のフォルダーの入口、module map の順とコメント）は通ることをテストで固定した。

**照合（レビューの直しの後）**: 上の 57 個に新しい 25 個（`complete`、`settings`、`install`、`layout`）を足した 82 個を流し、76 個が落ちて 6 個が残った。テストの穴と余分な判定で、次のとおり塞いだ。**塞いだ後に流し直したのはこの 5 個だけで、全部の回はしていない**（5/5 が落ちた）。

| 残った変異 | 原因 | 直し |
|---|---|---|
| 条件つきの設定を許す | テストが片方の構成だけに足していて、構成の差で落ちていた | 両方の構成に足す |
| xcconfig を許す | 判定が余分だった。xcconfig のある構成は読み取りから外れて、別の判定で落ちる | 判定を消した（残りは 81 個） |
| case を 1 つも読めなくても通す | テストが無かった | enum の名前を変えるテストを足した |
| `.x` の言及を case と数える | テストが `case` の行を消すだけだった | `case` でない言及を残すテストを足した |
| スライスを 1 つにする、全部を実機の target で流す | テストが照合の `LAYOUT_SLICES` を読み、自分と比べていた。名前だけのテストでは target を見ていない | スライスの名前を手で書く。1 つの target でだけ定義される `__x86_64__` と `__APPLE_EMBEDDED_SIMULATOR__` で壊すテストを足した |

また、自己テストを足す途中で本物の穴が 2 つ見つかって直した: `"KEY[sdk=...]"` のキーを読めていなかった、Release の `OTHER_LDFLAGS` を見ていなかった。

**framework と C のテスト**（iPhone 17 Pro / 26.2。変異なしの回が通ることを確かめた）: 33 個に後の 1 個を足して 34 個。下の表はレビューの前の版の結果で、`out_size` と配置の行は、この節の最後の流し直しに置き換わる。

| 壊し方 | 落ちたテスト |
|---|---|
| U+0000 を残す、`?` にする | `testStringReplacesU0000WithFFFD`、`testStringListItems` |
| `NSString` の `data(using:)` を通す（1a で測った失敗の形） | `testStringReplacesUnpairedSurrogatesWithFFFD` ほか |
| 終端の NUL が無い | `testStringKeepsItsText` ほか 4 つ |
| 空のバイト列が `NULL`、バイト列を文字列として扱う | `testBytesOfSizeZeroHaveAPointer`、`testBytesAreKeptAsTheyAre` |
| 違う型を読めるようにする（2 通り） | `testReadingAHandleAsAnotherTypeGivesNullOrZero` |
| `_free` が何もしない | `testAHandleHoldsItsObjectUntilItsFree` |
| 失敗でも `out_size` を書く | `testStringListNull` ほか 3 つ |
| 負の添字を見ない、最後の 1 つ先まで通す | プロセスが落ちる（`Restarting after unexpected exit`）。両方とも検出 |
| 常に最初の項目、最初の項目の大きさ | `testStringListItems` |
| `ntk_string_size` が 1 多い | `testStringKeepsItsText` ほか 3 つ |
| `ntk_last_system_code` が 1 | `testLastSystemCodeIsAlwaysZero` |
| 版（入口、ヘッダーの `NTK_VERSION`、`MARKETING_VERSION`） | `testVersionIsTheOneOfTheHeader`、`testVersionIsTheOneOfTheFramework` |
| `notMainThread` を `NONE` に、`WRONG_THREAD` の番号を 17 に、`installed` を `UNKNOWN` に | `testEveryResultOfTheLibraryIsMapped` ほか、`testTheNumbersAreThoseOfTheTable` |
| 入れない | `testOnTheMainThread…` ほか 4 つ |
| main 以外: 返しつつ後で入れる / main を待つ | `testOffTheMainThread…`（後者は `testLastSystemCodeIsAlwaysZero` も） |
| main: 積むだけで返す | `testOnTheMainThread…` ほか |
| main キューかどうかで判定（`__dispatch_queue_get_label`） | `testInsideASerialQueueOnTheMainThreadItIsTheMainThread` |
| ヘッダーの項目を大きくする、2 つ入れ替える | `testNotificationStructs`、`testDialogStructs` |
| ヘッダーの項目（詰め物を含む）を消す（2 通り） | テストが**組めない**（`no member named`）。検出だが XCTest の失敗ではない |
| 表の `sizeof`、`offsetof` の数 | `testShareStructs`、`testNotificationStructs` |
| TSan: 読み取りに競合を入れる | `Swift access race`、スタックは `Handle.stringSize` → `ntk_string_size` → `testHandlesAreReadFromManyThreadsAndFreedOnAnother`。ホストが止まる |

- **1 個は最初に残った**: 「`OperationQueue.current != .main` で判定する」は通った。main スレッドの上の `DispatchQueue(label:).sync` の中でも `OperationQueue.current` は main を返すので、キューで判定する変異になっていなかった（同じ動きの変異）。`__dispatch_queue_get_label` に直すと落ちた
- 変異で落としたホストの crash report（`~/Library/Logs/DiagnosticReports` の `IosLibraryCApiTestHost-*.ips` 4 つ）は、ここに記録してから消した

**レビューの直しの後に流し直した分**（変異なしの回で、テストと実機のスライスのビルドが通ることを確かめた）: 9/9 が落ちた。

| 壊し方 | 落ち方 |
|---|---|
| 失敗で `out_size` を書かない、1 を書く | `testStringListNull`、`testStringListEmpty`、`testStringListOutOfRange`、`testReadingAHandleAsAnotherTypeGivesNullOrZero` |
| 項目があるのに `out_size` を書かない | `testStringListItems` |
| 入れない（proxy が `nil` のまま） | `testCallAfterTheHostReplaced…` ほか |
| 表の `sizeof`、`offsetof`（シミュレーター） | ビルドが `static assertion failed` で止まる |
| 表の `sizeof`（**実機のスライス**。`generic/platform=iOS`） | 同じ。流さずに止まる |
| ヘッダーの項目を大きくする、2 つ入れ替える | 同じ |

### 3.6 確かめられていないこと、残っているもの

- **実機では何も流していない**（指定どおり）。実機のスライスは組めることと、公開シンボルと、配置の静的な確かめだけ。実機の `IosLibraryCApiTests` は 2b の DoD の区切り（P1-20）
- **シミュレーターは指定の 2 台**。第 2 部 15.2 の iPhone 17 / 26.2 と iPad Pro 11-inch (M4) / 18.3 では流していない（`test_ios.sh` につなぐ TB-12）。ASan も流していない（依頼は TSan だけ）
- **Xcode 26.3 では capi を組まない**（`@c` に Swift 6.3 が要る）。ワークスペースに入っていても、サンプルと `IosLibrary` の scheme は capi に触れないことを確かめた。Xcode 26.3 で開いたときの画面は見ていない
- **ホストが権限を求めないことを守るテストは無い**: 答えなければ状態は `notDetermined` のままで、テストでは区別できない。今はコードに要求が無いこととコメントだけ
- `check_design_consistency.py` は、TB-1 の実装の時点では第 2 部で 3 件落ちていた（`OP set`、`OP ids ascending`、`markdown table column counts`。HEAD の版でも同じ）。**メインのセッションが第 2 部を直した後の今は FAIL 0**（流して確かめた）
- C-9（最初の呼び出しの版の確かめ）、`StructReader`、`Registry`、入力の `CApiString`、`MainQueue` は TB-2
- 第 2 部 12.1 の「8.2 の名前がテストのソースに現れる」、実行時のクラスのテストは足していない
- **`storage.deallocate()` を消す変異を落とすテストは無い**（レビューの C-7）。`testAHandleHolds…` はハンドルの解放だけを見る。リークは ASan でも普通は出ないので、メモリの回（`leaks` か `malloc_zone_statistics` の差）で見るまで確かめていない
- 第 1 部 6 章の「ヘッダーの `/* sizeof N */` と照らす」: 付録 A にその形のコメントは無く、第 2 部 12.3 のとおり期待値はテストの中に置いた。数は付録 A から LP64 の規則で計算したもの（コンパイラーの出力を写していない）

### 3.7 レビュー（Claude。A 1、B 3、C 8）と直したこと

Codex は Common のコードに A も B も無し。各指摘は実物で確かめてから直した。**退けたものは無い**（C-8 だけ持ち主の判断に回した）。

| 指摘 | 確かめたこと | 直し |
|---|---|---|
| **A-1**: `ntk_string_list_at` が失敗で `out_size` を書かない | **Android（`Common/Handles.cpp`）も Windows（同）も `*out_size = 0`**。Windows のテスト（`CApiCommonTest.cpp`）は 99 から 0 になることを確かめている。Android の Clipboard・Notification の `At` と Windows の Notification の読み取りも同じ形。**私が第 1 部 1.1 の「値の出力は成功したときだけ」を、列挙・真偽値・要求の ID のほかの読み取りにまで広げて読んだ誤り** | 失敗で 0 を書く。逆を固定していた 4 つのテストを反転した。iOS で `out_size` を持つ読み取りは今これだけ。**TB-3 以降の読み取りも同じ形にする**（付録 A の "An index out of range gives NULL or 0"） |
| **B-1**: 一覧に足せば関数を隠し続けられる | `check_entries` に入口なしの名前を一覧つきで与えて `True` を確かめた | `--require-complete` と `complete` の行。第 2 部の TB-10、TB-11、TB-12 の行。「only shrinks」の文を直した。`check_ios_dist.py` への組み込みと 15.2 の文は TB-11 に任せた |
| **B-2**: 記録が今の木と違う | そのとおり | 3.1、3.2、3.6 を直した |
| **B-3**: Debug の止めが TB-11 だけ | Release を `YES` に戻しても何も落ちなかった | `settings`。TB-11 の行に「Release だけ」 |
| **C-1**: `layout` は行の文字を読むだけで、メソッド名を変えても `#if 0` でも通る | そのとおり。3 つのスライスで `_Static_assert` が通ることを確かめた | 配置のテストを `_Static_assert` にし、XCTest のメソッドを無くした（29 → 25 件）。`#` の行を固定。照合が 3 スライスでコンパイルする。**12.1 の「3 つのスライス」に届いた** |
| **C-2**: 配列や関数ポインタの項目で traceback | そのとおり | 配列を読み、読めないものは `layout` の FAIL |
| **C-3**: `--require-compile` を付ける所が無い | そのとおり | TB-12 の行 |
| **C-4**: `isDelegateInstalled` の比較がほぼ無意味 | 全件の回ではいつも真 | 比較を消した。残りの 1 行に「単独で流すときだけ効く」 |
| **C-5**: `nil === nil` で通る | そのとおり | `XCTAssertNotNil(proxy)` を 2 か所 |
| **C-6**: 新しい case が `UNKNOWN` になる | そのとおり | `install` の行 |
| **C-7**: `deallocate` を消す変異が落ちない | そのとおり | 直していない。3.6 に書いた（今のテストの形では見られない） |
| **C-8**: `ios.md` と `common.md` に capi の行が無い、XCTest の記述 | そのとおり | **直していない**。`agent-rules` はこの作業で触らない。持ち主の判断 |

## 4. TB-2

### 4.1 足したもの

| ファイル（`ios/IosLibraryCApi/IosLibraryCApi/`） | 中身 |
|---|---|
| `Common/StructReader.swift` | `read`（`NULL` は拒否）、`readIfPresent`（`NULL` は nil）、`readArray`。Windows の設計書 7.8 の規則と P2-5。`struct_size` の 4 バイトを見てから残りを読み、どの読み取りも `struct_size` を越えない。読み取りは位置が揃わなくても落ちない。投げる値は `EntryError` で、機能のエラーに写して `release` を呼ぶのは受け口 |
| `Common/CApiString.swift`（足した） | `required`、`optional`、`orEmpty`（E-15 の 3 つの `NULL` の意味）。`String(validatingCString:)`。ログは有無だけで中身を出さない |
| `Common/Registry.swift` | `RegistrationState`、`CancellableRequest`（`.dialog`、`.clipboardLoad`。P1-24 の 2 つと箱の閉じ方）、`OwnedResult`（`.file` の渡した印と削除）、`RegistryEntry`、`Registration<Callback>`、`Registry`（ID の表、`accept`、`tryRelease`、`cancel`、`removeListener`）、`EventLedger<Event, Callback>`（帳簿と保ち） |
| `Common/MainQueue.swift` | `DispatchQueue.main.async` と `MainActor.assumeIsolated` だけ。待つ形なし |
| `Common/EntryError.swift` | `EntryError`（1〜3）、`Entry.accepted`（0）、`Entry.reject`（C-3。呼び出しスレッドで `release`）。**第 1 部 5.1 の木に無いファイル**（4.6 の 1） |
| `Common/VersionCheck.swift` | C-9、P1-19。`Bundle(for: RequestBox.self)` の版とヘッダーの版を比べ、違えば 1 回だけ `.error` のログ。止めない。**第 1 部 5.1 の木に無いファイル** |
| `Notification/NotificationReceiver.swift` | `install` の 2 行目に `VersionCheck.run()` |

- `@unchecked Sendable` は `Registration` の 1 つだけ（P1-17 の (1)(2)。関数ポインタと `user_data` の箱を別に作らず、第 1 部 5.6 の「または `Registration`」で運ぶ）。`nonisolated(unsafe)` は無い
- 完了の印 `isCompleted` は `@MainActor` の項目なので、main 以外から触るとコンパイルで止まる。帳簿も `@MainActor` のクラスで、`add` と `init` だけ `nonisolated`
- `public` は増えていない。プロジェクトは synchronized group なので `project.pbxproj` は変わらない

テストは `ios/IosLibraryCApiTests/` に 100 件（25 → 125 件）:

| ファイル | 件数 | 中身 |
|---|---|---|
| `RegistryTests.swift` | 32 | 第 1 部 5.7 の完了、取り消し、順序の表、`.file` の扱い、競合。テストの本体が main にいるので、積んだものは `runMainQueue` まで動かず、`onAnotherThread` は main を止めたまま別のスレッドで呼ぶ |
| `EventLedgerTests.swift` | 23 | 帳簿、解除、再入、AP-21、32 件の上限、最初の挿入の口、2 つの callback の型 |
| `StructReaderTests.swift` | 31 | 規則と配列。`GuardedMemory`（`mmap` して後ろのページを `PROT_NONE`）で、構造体の外を読むとプロセスが落ちる形にして、読み取りの範囲を確かめる |
| `CApiStringInputTests.swift` | 6 | 第 1 部 6 章の 5 つの列と、RFC 3629 が除く 10 の列、そのすぐ隣の正しい値 |
| `EntryFoundationTests.swift` | 8 | 番号を 4 つのヘッダーと照らす、`MainQueue`、版の確かめ |
| `RegistryTestSupport.swift` | - | テスト専用の操作とイベント、C の callback、`RaceStart`（競合の両側を同時に始める） |

### 4.2 コマンドと結果

Xcode 26.6 は `DEVELOPER_DIR` で選び、`xcode-select` は 26.3 のまま。

```
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath <scratch> [-enableThreadSanitizer YES | -enableAddressSanitizer YES] test
```

**最後のソースで流した結果**:

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 125/125 |
| 同（iPhone 16 / 18.3） | 125/125 |
| 同 TSan（iPhone 17 Pro / 26.2） | 125/125。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 125/125。報告 0 件 |
| framework の Release（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。組むだけ） | 組めた。警告 0。`--library --architectures arm64` は `OK symbols`（12 symbols） |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`） | 組めた。`--library --architectures arm64,x86_64` は `OK symbols`（12 symbols） |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP は `complete` と `symbols`（TB-1 と同じ） |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 277 tests、OK |

- `git status`、`git diff`: `ios/IosLibrary`、`ios/IosLibraryExample`、UI テスト、`include/NativeToolkitC/` に差なし
- **競合のテストは両方の結果を踏んでいる**（1 回の実行の数え。測った後で数える行は消した）: 取り消しと完了（300 回）は、完了が勝つのが 7〜12 回、取り消しが勝つのが残り。解除と配送（200 回）は、配られた件数が 0 件の回が約 190、1 件以上の回が残り。1 回目の形は完了が 300/300 で勝っていて、競合になっていなかった。`RaceStart` と待ちのずらしを足して直した

### 4.3 壊して確かめたこと（使い捨ての写し）

写しは `ios/` から `Build`、`Docs`、`UnityIosPlugin`、`IosLibraryExample` を除いたもの（2 MB）で、ワークスペースからもサンプルの行を外した。**変異なしの回が通ることを、流すたびに確かめた**。

**112 個のうち 110 個が落ちた**。1 回目の 110 個は 101 個が落ち、7 個が残り、2 個はこちらの変異の書き間違いでコンパイルが通らなかった。

依頼で挙げられた形:

| 壊し方 | 落ちたテスト（数） |
|---|---|
| `tryRelease` の CAS を外す | `testACompletionOfAMarkedActiveRegistrationOnlyReleases` など計 7 |
| `transition` が比べずに書く | 落ちた |
| `release` を 2 回呼ぶ | 28 |
| `tryRelease` が勝っていなくても `release` | 落ちた |
| 取り消しの CAS を外す | `testACompletionAfterRemovalDoesNothing` など計 9 |
| 解除の CAS を外す | 11（プロセスも 2 回落ちる） |
| 取り消しの後の完了が結果を渡す | `testCancelWithTheCompletionQueuedBehindIt…`、`testAResultOfACancelledRequest…` |
| `RELEASED` の後の完了が結果を渡す | 落ちた |
| 渡した印を付けない | `testAHandedOverFileStays` など計 4 |
| 渡した印をコールバックの後に付ける | `testACancelInsideTheCallbackDoesNotDeleteTheFileItWasGiven`（中で印を読む） |
| `RELEASED` の後の結果を消さない | `testAResultAfterReleased…`、`testASecondResult…` |

ほかの範囲（どれも落ちた）: `tryRelease` のそのほか（`release` なし、表に残す、鍵の中で `release`）、取り消しの 7 つ（箱、外す、別の種類、箱を後で閉じる、機能ごとの閉じ方）、完了の印の 7 つ、ファイルの削除の 6 つ、「外す」の 4 つ、開始の 8 つ、帳簿の 18 個（状態の確かめ、保ち、AP-21 の配り方 3 通り、上限の 31 と 33、最初の挿入、`add`）、`MainQueue` の 3 つ、`StructReader` の 23 個（規則ごと、prototype の形を含む）、文字列の 5 つ、エラーと版の 13 個。

**プロセスが落ちる形で検出したもの**: 鍵の中の `release`、印なしの `CANCELED` の再帰、保たない帳簿での `removeFirst`、保持しないハンドル、`StructReader` の範囲外の読み取り（`GuardedMemory`）、版の確かめの `fatalError`。`DispatchQueue.main.sync`（Q02）は 420 秒で打ち切って検出とした。

**1 回目に残った 7 個と、その扱い**:

| 残った変異 | 原因 | 直し |
|---|---|---|
| 指名した `reserved` の最初の 1 つだけ見る | テストの穴 | `testEveryNamedReservedFieldCounts` |
| 最初の挿入の口を帳簿に入れる前に呼ぶ | 口の中のイベントが保ちに回り、結局届くので同じに見えた | 口の中で届いたことを読む |
| `Task { @MainActor in }` で積む | 順序も main も同じに見える | `testABlockIsNotATask`（ブロックの中に現在の `Task` が無い） |
| `accept`、`install` から版の確かめを呼ばない | ログは 1 回なので区別できない | **`VersionCheck.runCount`（テスト用）を足した**。`testEveryFirstCallRunsTheCheck`。`reject`、`add` の同じ変異も足した |
| 「外す」の状態の確かめを外す | **同じ動きの変異**。`RELEASED` の登録は印が立っているか解除で帳簿から外れた後で、`tryRelease` も失敗する | 第 1 部 5.7 の表の形のまま残した |
| 保ったイベントを `ACTIVE` な全登録に配る | **今の経路では同じ動きの変異**。保ちが空でなく別の `ACTIVE` な登録が帳簿にいる状態は、ネストした run loop でも作れなかった | 直していない |

直した 5 個と、書き間違いの 2 個、足した 2 個の計 9 個を流し直し、9/9 が落ちた。**全部の回はやり直していない**（4.5）。

**TSan**: 状態を `Atomic` でない素の項目に変える変異を TSan で流すと、`transition` と `currentState` の `data race` が報告され、ホストが止まった（`removeListener` と `receive`、`cancel` と `complete` の 2 通り）。報告が出ることはこれで確かめた。

変異で落としたホストの crash report は、ここに記録してから消した（`~/Library/Logs/DiagnosticReports` の `IosLibraryCApiTestHost-*.ips`、計 27 個と作業の途中の 2 個）。

### 4.4 実装の途中で見つかったこと

| 見つけたこと | 直し |
|---|---|
| **`tryRelease(expected: .released)` が `RELEASED` → `RELEASED` の CAS に成功し、`release` を 2 回呼ぶ**。テストで見つけた。受け口は渡さないが、形として塞いだ | 先頭で `false` を返す |
| 競合のテストが競合していなかった（4.2） | `RaceStart` |
| テストの 1 つが `Recorder` を保持せず、`user_data` が解放された後を指して落ちた | テストの誤り |
| `XCTestCase` に `add(_:)` があるので、テストの関数名がぶつかった | テストの関数名を変えた |

### 4.5 確かめられていないこと、かかった時間

- **実機では何も流していない**（指定どおり。`devicectl` も実機の実行先も使っていない）。`generic/platform=iOS` は組むだけ
- 第 2 部 15.2 の iPhone 17 / 26.2 と iPad Pro 11-inch (M4) / 18.3、x86_64 のスライスのテストは流していない（TB-12）
- **TB-2 に公開の非同期の関数は無い**。第 1 部 6 章の表は `@testable import` のテスト専用の操作で確かめ、C の関数を通してはいない（TB-3 以降）
- **本物の `.file` の読み込みは通していない**。ファイルと親のフォルダーはテストが作った。TB-4 で確かめる
- **「関数が戻る前に main が挿入と完了を処理する」順は決まった形で再現できていない**（第 1 部 5.7 の表の 1 行目）。止める場所が無いので、8 スレッド × 25 回の同時の呼び出しと TSan で見た。`accept` は積んだ後に登録に触れないのがコードの形
- **`ACTIVE` のまま保ちに回る窓**（`receive` の判定と別のスレッドの CAS の間）は、配ったかを数えて保つ形にしたが、狙って踏むテストは無い
- `testEveryStructOfTheHeadersIsAMultipleOf8` の 16 個は手書きの一覧。新しい構造体はここに足す必要がある（`common.md` の両辺の導出は満たさない。`layout` の照合に入れるなら別の作業）
- 版の確かめのログは今のところ毎回出る: `IosLibrary` が 1.3.0、capi が 2.0.0 のため（3.1）。版を上げるとテストの期待値は自動で 0 行に変わるが、その形はまだ流れていない。**「同じ」の分岐は `compare` の単体テストだけ**
- 入力のバイト列（第 1 部 5.9 の行）は足していない。依頼の範囲にも無く、使う人のいる TB-3 で足す
- **時間**: 実装とテストより変異が長かった。1 回目の 110 個は 2 台のシミュレーターに分けて約 90 分（19:36〜21:06）、1 個あたり 60〜80 秒。流し直しは約 10 分。全体で約 2 時間半。**個数は依頼より多く、全部の回は 1 回だけ**

### 4.6 設計書が読み切れなかった所と、読み方

ヘッダーが変わる所は無かった。**「設計書と食い違う所は無かった」とここに書いていたのは誤りだった**: `Registry.swift` が Dialog と Clipboard の Manager を呼び、第 2 部 5.1 の表（`Registry.swift` に Manager は無い）と違っていた（レビューの B-1。4.7 で直した）。1、2、7、9 の読み方は 4.7 で設計書に書いた。11 の `.file` の消し方は `Clipboard/` に移した。

| # | 所 | 読み方 |
|---|---|---|
| 1 | 第 1 部 5.1 の木に、エラーの土台と版の確かめのファイルが無い | `Common/EntryError.swift`、`Common/VersionCheck.swift` を足した。**木の行を足すかは持ち主の判断**（設計書は変えていない） |
| 2 | 第 1 部 5.7 の完了の行「完了を呼んで印を立てる」 | **印を呼ぶ前に立てる**。コールバックの中の run loop で「外す」が動いても二重にならない。Android も同じ。第 2 部 5.3 の「渡す前に印」とも合う |
| 3 | 「`struct_size` の 5 つの規則」が 2 通りある（Windows 7.8 の番号と、第 1 部 6 章の 5 つの場合） | 両方をテストにした。**規則 5 は項目を足す人の規則なので、読み取りでは見ない**（8 の倍数でない `struct_size` も、規則 1〜4 を満たせば受ける。Windows と Android も見ない）。ヘッダーの 16 の構造体が 8 の倍数であることは見る |
| 4 | 規則 3 と「大きさの小さい呼び出し側」: 2.0.0 では最小が `sizeof` なので起きない | `minimumSize` の引数を持たせ、項目を足した仮の型で確かめた（Windows の CT-07 と同じ考え） |
| 5 | 規則 1 の途中の `reserved` | 汎用の読み手には分からないので、受け口が `reserved: [\.reserved1]` で名指しする。全部 `uint32_t`。名指しを忘れても止まらないので、**TB-3 以降で 12.1 の `reserved` の行を構造体ごとに確かめる必要がある** |
| 6 | 配列の `NULL` と件数 0 | 件数 0 は何も読まず `[]`（`NULL` でも）。`EMPTY_*` を返すのは呼ぶ側。`size_t` が `Int.max` を超えた負の値と、掛け算のあふれは `INVALID_PARAMETER`。**あふれない大きな件数は読みに行く**（呼び出し側の誤りで、止める手段が無い） |
| 7 | 第 1 部 5.7 の「最初の呼び出し」（C-9） | `accept`、`add`、`reject`、`install` の 4 か所。読み取り、`_free`、`ntk_version`、`ntk_last_system_code` は、5.15 の先頭のログの除外と同じに読んで含めない。ビルダーの setter だけを呼ぶ間は走らない（次の受け付けで走る） |
| 8 | 別の機能の ID（`ntk_dialog_cancel` に読み込みの ID） | 第 1 部は「知らない ID」としか書いていない。Android と同じく**何もしない**とした |
| 9 | 第 2 部 5.4 の「保ち」に、配っている途中に新しいイベントが来たときの順が書かれていない | **保ちが空でなければ後ろに並べる**（届いた順を保つ。Android の 12.1 の「再入で配っている途中も 32 件を超えない」と合う）。保ったものは次の登録 1 つだけに配る（P2-18） |
| 10 | `ntk_notification_listener_remove` は 2 つの callback の型の登録を取る | 解除の関数からは型が分からないので、`RegistryEntry` を通す（`as?`）。違うハンドルは約束の外で、`as?` が外れれば何もしない |
| 11 | `.file` の「親のフォルダーを消す」 | ライブラリの `discardUndelivered` は形を確かめるが `internal`。受け口は `IosClipboardManager` の DocC（「ファイルと親のディレクトリの持ち主」）を頼りに `deletingLastPathComponent()` を消す |
| 12 | P1-17 の (1) を `UInt(bitPattern:)` で減らせるか（「2b で試す」） | 試していない。`Registration` が運ぶので箱そのものが無く、`@unchecked` は 1 つで済んだ |

### 4.7 レビュー（Codex: 並行と寿命。Claude: 設計との一致と層）と直したこと

レビューの本文は受け取っていない。指摘はメインのセッションの要約で受け、持ち主の側で確かめてあるのは A、イベントの順の経路、B-1 だけと聞いた。**残りも実物で確かめ、誤りだった指摘は無かった**（下の表の「確かめ」）。

| # | 指摘 | 確かめ | 直し |
|---|---|---|---|
| 1 | **A（Codex）**: コールバックの中で `release` が動く。入れ子の `complete` が `tryRelease` を呼び、私のテスト（`RegistryTests` の 94 行）がそれを正しいとしていた | そのとおり。`CANCEL_REQUESTED` の枝も、コールバックが回した run loop の上の「外す」も同じ | `Registration.runCallback`（main だけの深さ）を完了、`CANCELED`、イベントの配送のすべてに通す。`tryRelease` は深さが 0 でなければ状態を変えず覚えるだけで、いちばん外が戻ったときに**そのときの状態から**行う。`tryRelease` の中に置いたので、回り道はできない。`Recorder.timeline` に入りと戻りを記録し、`assertReleasedOnceOutsideCallbacks` が重なりと回数を見る |
| 2 | B（Codex）: 配っている途中に同期に届いたイベントで、B が `[2, 1]` になる | そのとおり（変異 N12 で再現） | `EventLedger` の `arrivedDuringDelivery`。いちばん外の配送の後に、届いた順に、そのとき `ACTIVE` な登録へ。保っているものがあればその後ろ。誰もいなければ保つので、32 件の意味と P2-18 は変わらない |
| 3 | B（Codex。Claude は C）: `min(size, known)` が項目を途中まで埋める | そのとおり（N21 で再現） | `size < known` なら 8 バイト単位で切り捨てる。`testAFieldCoveredInPartIsZero`。コメントを直した |
| 4 | B-1: Common が機能を知っている | そのとおり | Common は `CancellableKind`（名前と閉じ方の closure）と `OwnedResult(discard:)` だけ。`DialogReceiver.cancelKind`、`ClipboardReceiver.loadCancelKind`、`ClipboardReceiver.loadedFile(at:)` を第 2 部 5.1 の名前のファイルに置いた。ログのカテゴリ `Clipboard` を足した。4.6 の文を直した |
| 5 | B-2: `reserved` の既定値で書き忘れが通る | そのとおり | 既定値を消した。`reserved: []` まで書く |
| 6 | B-3: `tryRelease` が main だけと型に書かれていない | そのとおり | `@MainActor`。呼ぶ所はすべて main で、そのまま組めた |
| 7 | B-4: 開始の前の取り消しが箱を閉じることを確かめていない。`testTheBoxIsThereBeforeTheFirstMainTurn` は最初の回の後に見ていた | そのとおり | テスト専用の種類で閉じた回数を記録する `testACancelBeforeTheStartClosesTheBox` に置き換えた |
| 8 | B-5: `RELEASED` の開始、挿入、配送のテストが無い | そのとおり（N26〜N28 は新しいテストでだけ落ちる） | 3 件足した |
| 9 | B-6: 規則 5 の手書きの一覧 | そのとおり | `layout` が `LAYOUT_SIZE` の数の 8 の倍数を見る。**構造体の集合はヘッダーから、数は `compile` がコンパイラーと比べる**。数の判定に clang は要らないが、clang が無い回（`compile` が SKIP）は表の数が本物かは確かめられない。自己テスト 1 件、変異 1 件。手書きのテストは消した |
| 10 | B-7: 先頭のログの引数の抜け | そのとおり | 指定の 8 か所を `provided` / `nil` で埋めた |
| 11 | 小さいもの | そのとおり | テスト名（342 行）、`finished.wait()` を期限つきに（期限切れは失敗）、テストのコメントの日本語、`reserved0Offset`、`VersionCheck.run` のコメント（「main は待たない。同時の呼び出しは最初の読み取りを待つ」） |

**run loop の測り**（iPhone 17 Pro / 26.2、1 回）: メインのセッションの記憶は測りと合っていた。**main キューのブロックの中で回した run loop は、次のブロックを動かさない**（保ったイベントを配るのは挿入のブロックの中なので、そのテストの `runMainQueue` が 10 秒で期限切れになった）。テストの本体から回せば動く（`runMainQueue` が中で確かめる）。18.3 では、ブロックの中の形は測っていない。設計はこれに頼っていない。テストは、動く形の上で深さの経路を確かめ、ブロックの中の形は「戻った後に `release`」として確かめる。

**設計書の文**（持ち主に見せる差分）: 第 1 部 5.1 の木に `EntryError.swift` と `VersionCheck.swift`（機能のファイルは今の `<機能>Receiver.swift` の行に入るので足していない）。5.7 の完了と「外す」の行を「印を立ててから呼ぶ」に、**`release` がコールバックと重ならない規則を 1 段落**。C-9 の行にどの呼び出しが走らせるか。第 2 部 5.4 に配っている途中のイベントの順。`check_design_consistency.py` は 2 つとも exit 0、FAIL 0。

**そのほかに変えたもの**: `scripts/check_c_abi_contract_ios.py`（`layout`）、`scripts/README.md`（件数を 677 に）、`test_no_swift_sources`（**自己テストが 1 件落ちた**: `Dialog/`、`Clipboard/` が増えたので「Swift のソースが無い」にならなくなった。全部の `.swift` を消す形に直した。テストの名前のとおりの状態になった）。

#### 結果（最後のソース）

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 141/141 |
| 同（iPhone 16 / 18.3） | 141/141 |
| 同 TSan（17 Pro） | 141/141。報告 0 件 |
| 同 ASan（17 Pro） | 141/141。報告 0 件 |
| Release（`generic/platform=iOS`。組むだけ）`--library --architectures arm64` | `OK symbols`（12 symbols） |
| Release（シミュレーター）`--library --architectures arm64,x86_64` | `OK symbols`（12 symbols） |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP は `complete` と `symbols` |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `check_design_consistency.py`（第 1 部、第 2 部） | どちらも exit 0、FAIL 0 |

テストの増減: `RegistryTests` 38、`EventLedgerTests` 33、`StructReaderTests` 31、`EntryFoundationTests` 8、`CApiStringInputTests` 6、TB-1 の 25。

#### 変異（今回変えた所だけ。30 個）

**28 個が落ちた**。プロセスが落ちた回は無い（crash report は 0 個）。変異なしの回が通ることを、2 台それぞれで確かめた。

| 範囲 | 個数 | 落ちなかったもの |
|---|---|---|
| 遅らせた `release`: 外す、遅らせた後に 2 回、呼ばない、`ACTIVE` からだけ、戻るたび、`runCallback` を通さない（3 通り）、入れ子の「外す」を飛ばす（漏れ）、深さが減らない | 11 | N05 |
| 配送の列: 外す、後入れ先出し、流さない、1 つだけ流す、保ったものの配送を配送と数えない、印が戻らない、列を保ちより先に見る、誰もいないときに捨てる、保ちを追い越す | 9 | N17 |
| `min(size, known)` | 1 | - |
| 種類、閉じ方、削除、箱を後で閉じる | 5 | - |
| `RELEASED` の開始、挿入、配送 | 3 | - |
| `layout` の 8 の倍数（写しの中の自己テスト） | 1 | - |

| 残った変異 | 扱い |
|---|---|
| N05 `callbackDepth == 0` を外す（戻るたび） | **同じ動きの変異**。内側の戻りで `tryRelease` を呼んでも、深さが残っているのでまた覚えるだけ。読みやすさのために条件は残した |
| N17 `deliverToActive` が保ちを見ない | **判定が余分だった**。流す時点で保ちがあるのは誰も `ACTIVE` でないときで、結局保つ。判定を消した（消した後は変異にならないので流していない） |

**流していないもの**: 前の 112 個と TSan の競合の変異は、今回のソースでは流し直していない（指定どおり）。4.3 の数は前のソースの数で、`complete`、`runRemoval`、`receive` はその後に変わった。

#### やらないと決めたもの（メインのセッションの判断。持ち主にはコミットの前に伝えた。ここに理由を残す）

| 指摘 | 理由 |
|---|---|
| ID が `UInt64.max` で一周する | 実際には届かない |
| 競合の回数に下限を置かない | 片側が 7〜12/300 で、下限を置くと揺れて落ちる。両側は順を決めたテストが確かめる |
| `VersionCheck.runCount` を残す | `internal` で公開されない。どの関数が走らせるかを見分ける方法がほかに無い |
| C-6 の揺れの余地（`TestThreads` の 5 秒、`testAMismatch…` を単独で流したとき、版を上げた後の 0 行の期待） | どの回でも落ちていない。版を上げる回（TB-11）で見る |
| `CApiStringInputTests` の 92 行 | NUL の後ろのバイトが値に入らないことは確かめている。NUL より後ろのメモリに触れないことまでは確かめていないが、読むのは `String(validatingCString:)` で、ここの直しでは変わらない |

#### 確かめられていないこと

- 実機では何も流していない。`generic/platform=iOS` は組むだけ
- 「ブロックの中の run loop は次のブロックを動かさない」は 26.2 の 1 回だけ
- **本物の経路で入れ子の `complete` や run loop の上の「外す」を起こしてはいない**。`IosLibrary` の完了はブロックの中から来る見込みで、そこで「外す」が入れ子に動くかは Dialog の handler などが本物になる TB-4、TB-5 で見る
- 配っている途中の列に上限は無い（配る相手がいる限り捨てない）。コールバックが同期にイベントを起こし続ければ止まらない。今の `IosLibrary` の口がコールバックの中から同期に届くかは確かめていない（TB-8）
- 時間: この節の作業は約 40 分（21:38〜22:17。うち変異が約 19 分）。目標の 40〜50 分の中

#### 直しの後の確かめ（メインのセッション）

- 実装者とは別に、iPhone 17 Pro / 26.2 の 141/141、`check_c_abi_contract_ios.py` の FAIL 0、その単体テストの OK、`check_design_consistency.py` の 2 つの FAIL 0 を流した。18.3、TSan、ASan、Release、変異は実装者の結果で、流し直していない
- Claude のレビューは直しの前の 1 回だけ。直しの後は Codex が読んで確かめた（ビルドもテストも流していない）。結果は A、B なし
- Codex の C（直していない）:
  - 配送の列に上限が無い。コールバックが同期にイベントを起こし続けると main を占める。そうなる本物の経路は見つかっていない（TB-8 で見る）
  - `StructReader` の切り捨ては項目ではなく 8 バイト単位。公開の構造体はすべて 8 の倍数（`layout` が見る）なので今は起きない
  - `EventLedgerTests` の 268、313 行と `RegistryTests` の 545 行は、直しを外しても通る境界のテストで、直しの検出は別のテストが受け持つ（EventLedgerTests の 241 行、RegistryTests の 82、467 行）
  - テストに無い形: 3 つの登録、配っている途中の挿入、8 の倍数でない大きさ

## 5. TB-2b

### 5.1 足したもの

| 区分 | ファイル | 中身 |
|---|---|---|
| アプリ | `ios/IosLibraryCApiUITestApp/` | bundle id は `com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp`（ホストの `...IosLibraryCApiTestHost` と別。第 2 部 12.1）。SwiftUI と `UIApplicationDelegateAdaptor`（サンプルと同じ形）。iPhone と iPad |
| 行の形 | `CApiRow.swift`、`Rows/CommonRows.swift`、`Rows/NotificationRows.swift` | 1 回の C の呼び出しが `CApiRow` の値 1 つ。**TB-3 以降は `Rows/` に値を足すだけで、画面の行、2 通りの起こし方、結果の行が付く**。機能が増えるときは節を `CApiRowCatalog.sections` に足す |
| 2 通りの起こし方 | `RowRunner` | `row.<id>.run`（この main の回）と `row.<id>.runAfterDelay`（3 秒後）。後者が第 1 部 6 章の「後ろにいるまま操作を起こすテスト専用の口」。結果の行が呼んだときの状態を持つ: `[<行>@<シーンの状態>] <値>` |
| 結果 | `ResultLog.swift`、`RowListView.swift` | `result.count` と `result.line.<n>`。イベントや完了の後からの報告も同じ列に入る。リストでなくスタックなので、画面の外の行も木にある |
| 起動の中 | `UITestAppMain.swift`、`NotificationRows.runAtLaunch()` | `ntk_notification_install()` を起動の中で呼ぶ（第 1 部 1.4。12.2 のコールドスタートの前提）。`FreshInstallMarker` は削除だけが消す印 |
| UI テスト | `ios/IosLibraryCApiUITests/` | 7 件。`CApiRoundTripUITests` 6 件、`CApiFreshInstallUITests` 1 件。基底 `CApiUITestCase` は実機なら何もせず失敗する（第 2 の守り）。割り込みの監視は何も押さない |
| プロジェクト | `IosLibraryCApi.xcodeproj` に 2 つのターゲット、共有の scheme `IosLibraryCApiUITestApp` | **`IosLibraryCApi` の scheme には入れない**（そちらは実機の ASan でも流す。第 2 部 12.2）。テストのターゲットは Swift 5 の言語モードと `minimal`（サンプルの UI テストと同じ。`setUpWithError` から `XCUIApplication` を触るため） |
| ランナー | `scripts/test_ios.sh --capi-ui`、`scripts/ios_ui_runner.py` の `capi-*` | 5.2 |
| 自己テスト | `scripts/tests/test_ios_ui_runner.py`（144 → 176 件）、`ios_ui_runner_mutations.py`（`capi-ui:` 13 個）、`scripts/README.md` | 全体の件数を 709 に |

**C を通っていることの確かめ**: アプリの `Rows/` の `import` は `Foundation`、`IosLibraryCApi`、`os`（レビューの指摘で直した。前の版は「`IosLibraryCApi` だけ」と書いていて誤り）。`IosLibrary` は framework のために埋め込むだけで、`import` するとコンパイルは通るので、`capi-check-sources` が止める。組んだアプリの `nm -u` の `_ntk_*` は `_ntk_version`、`_ntk_last_system_code`、`_ntk_notification_install` の 3 つで、`IosLibrary` の Swift のシンボルは 0 個。**この照合が緩かったことと直したことは 5.10**。

**今 TB-2b で書かなかったもの**: springboard の操作（バナー、権限のダイアログを押す、Share のシート）、C のコールバックの包み。どれも使う関数が来る TB-3 以降で足す。権限のダイアログをこのターゲットから押せることは 5.3 の使い捨ての写しで確かめた。

### 5.2 ランナーの区分（`--capi-ui`）

- シミュレーターだけ。実機は 3 か所で止まる: `test_ios.sh` の `KIND` の確かめ（exit 2。build の前）、`capi_make_plan`、`sim_xcodebuild`（元からある）。基底のクラスも止める
- `--udid` のほかの選択肢を受けない
- サンプルの段（宣言の表、基準、許可、ボタンの網羅）を通らない。`capi-check-sources` → build → 列挙 → `capi-plan` → 流す → `capi-record` → `capi-summary`
- `CAPI_UI_CLASSES` の表と列挙のクラスがちょうど同じでなければ流さない。`True` のクラスは 1 件ずつ、アプリを消してから流す。列挙にほかのターゲットがあれば止まる
- 結果は計画のテストとちょうど同じで、すべて `passed` のときだけ exit 0。skip も失敗
- **`xcodebuild` を呼ぶ前に毎回シミュレーターを再起動する**（5.4）
- `capi-check-sources` は、アプリとホストの bundle id、`IosLibraryCApiTests` のホストがホストのままであること、UI テストの対象、`IosLibraryCApi` の scheme に UI テストが無いこと、アプリの `import` を見る

**実機の守りに触れた所**: 緩めたものは無い。`TRUSTED_FILES`、`SIMULATOR_ONLY_TESTS`、許可、台帳、`device_guard`、`select_tests` は変えていない。信頼する部分のハッシュも変わらない（`trusted_part_changes` は空）。今あるコードで変えたのは次だけ。

| 所 | 変更 | 理由 |
|---|---|---|
| `record_invocation` | 引数 `target=UI_TARGET` を足した。既定はこれまでと同じ | 同じ判定を別のターゲットに使うため。`cmd_record` は渡さない |
| `test_ios.sh` の選択肢の解析、`KIND` の後 | `--capi-ui` の受け取りと拒否を足した | 上のとおり |
| `test_ios.sh` の `check-sources` の前 | `CAPI_UI=1` のときだけの枝を足し、`exit` する | `CAPI_UI=0` のときは通らない |
| FAKE の `xcodebuild`、`xcrun`（自己テスト） | `FAKE_CAPI_ENUMERATION` のときの枝と、`simctl` の 3 つ | `--capi-ui` を最後まで流すため |

`xcode-select` は使っていない（`test_ios.sh` も使わない）。**`--capi-ui` は `DEVELOPER_DIR` で Xcode 26.6 を選ばないと組めない**（26.3 は `@c` を知らず exit 65。`unknown attribute 'c'`）。

### 5.3 権限を未決に戻す方法（測った）

**`simctl uninstall` で足りる。`erase` は要らない（使っていない）。** TB-2b の完了の条件の確かめ。

使い捨ての写し（`<scratch>/tb2b/perm/`）で、同じ bundle id のアプリに `UNUserNotificationCenter` を直に呼ぶ行と測るテストを足した。**リポジトリには入れていない**（C の権限の関数が無い）。xcodebuild は毎回 `test-without-building`（アプリを入れる手順を通る。上書きされたことそのものは確かめていない）。値は `authorizationStatus` の raw value（0 未決、1 拒否、2 許可）。

| 測ったこと | iPhone 17 Pro / 26.2 | iPhone 16 / 18.3 |
|---|---|---|
| 許可（2）→ `uninstall` → 0 | 3/3 | 3/3 |
| 拒否（1）→ `uninstall` → 0 | 3/3 | 3/3 |
| 未決から要求するとダイアログが出て押せる（「“IosLibraryCApiUITestApp” Would Like to Send You Notifications」） | 6/6（許可 3、拒否 3） | 6/6 |
| 対照: 消さずに次の xcodebuild で 2 のまま | 3/3 | 3/3 |
| 対照: 消さずに `shutdown` と起動の後も 2 のまま | 3/3 | 3/3 |
| 対照: 消さずに次の xcodebuild で 1 のまま | 3/3 | 3/3 |
| 入っていないアプリへの `simctl uninstall` | exit 0 | exit 0 |

- 測った値は `uninstall` の直後（待ちなし）の次の xcodebuild の最初の読み取り。全部で 19 回の実行が 1 台ずつ、すべて exit 0。**リセットの回数は 1 台 6 回**
- 第 2 部 13 章の表の「確かめた」の中身はこの表。段階 0a（26.2 の 1 回）と同じ結果で、18.3 と拒否の場合が新しい
- `xcodebuild` の後のシミュレーターはこの回では `Booted` のままで、0c の記録（「xcodebuild の後は Shutdown」）とは違った（26.6）。理由は確かめていない。`--capi-ui` は毎回 `bootstatus -b` を呼ぶので、どちらでも動く
- `simctl privacy reset` は試していない（依頼の範囲にない。0a の記録では効かない）

### 5.4 答えていない権限のダイアログは `uninstall` の後も残る（測って見つけた）

**測りの最後に、ダイアログに答えないまま次の行を押すテスト（`testF`）を 1 回ずつ流した**。監視は何も押さず、テストは `Failed to tap ... Handler claimed to have handled ... but it's still interrupting` で落ちた（押さないことの確かめ）。その後:

| 起きたこと | 確かめ |
|---|---|
| ダイアログが `simctl uninstall` と入れ直しの後も画面に残り、**アプリの別の版のテストも同じ文で落ちる** | 17 Pro で `--capi-ui` が 2 passed、5 problem(s)。16 で変異の回も同じ |
| `simctl shutdown` と起動で消える | 17 Pro で再起動の後に `CApiRoundTripUITests` 6/6 |
| 再起動は権限を変えない | 5.3 の対照 |

- 持ち主の判断を待たずに、**`--capi-ui` が `xcodebuild` の前に毎回再起動する**形にした（第 2 部の文は変えない）。1 回あたり約 15 秒増える（5.3 の測りの `shutdown` と起動）。止まるのは次の `xcodebuild` と次の回への波及だけ。**再起動は xcodebuild の 1 回ごとなので、1 回で流すクラスの中では、ダイアログを残したテストの後ろのテストは今も一緒に落ちる**（前の版の「同じ回の後ろのテスト」は誤り）。新しいインストールのクラスは 1 件ずつなので波及しない
- **確かめ**: ダイアログが残ったままの 16 で、直した `--capi-ui` が 7/7
- 落ちるのは安全な側（誤って通ることは無い）。**残ったダイアログが新しいインストールの権限に効くかは確かめていない**（再起動で消すので、この経路では起きない）
- サンプルの権限の段（`NotificationPermissionUITests`）にも同じことが起きうる。ランナーの今の動きは変えていない（範囲の外）

### 5.5 コマンドと結果（最後のソース）

```
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
  scripts/test_ios.sh --udid <UDID> --capi-ui        # scripts と ios の写しの中で（出力を <scratch> に置くため）
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath <scratch> test
```

| 実行 | 結果 |
|---|---|
| `--capi-ui`（iPhone 17 Pro / 26.2） | 7/7。exit 0 |
| `--capi-ui`（iPhone 16 / 18.3）。ダイアログが残った状態から | 7/7。exit 0 |
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 141/141 |
| UI テストのターゲットの `build-for-testing`（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。組むだけ） | 組めた。流していない |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP は `complete` と `symbols`（TB-2 と同じ） |
| `test_ios_ui_runner.py` | Ran 176 tests、OK |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| サンプルの `build-for-testing`（26.3、`generic/platform=iOS Simulator`） | 組めた。ログに `IosLibraryCApi` は 0 行 |
| `xcodebuild -list -workspace`（26.6） | 足されたのは `IosLibraryCApiUITestApp` だけ |
| `git status`、`git diff` | `ios/IosLibrary`、`ios/IosLibraryExample`、`include/NativeToolkitC/`、capi のソースに差なし |

`check_design_consistency.py` は流していない（設計書を変えていない）。

### 5.6 壊して確かめたこと

**ランナーの 13 個**（`ios_ui_runner_mutations.py --only capi-ui`。変異なしの回は通る。本物の台帳は変わらない）: **13/13 が落ちた**。スクリプトと計画がそれぞれ実機を通す、ほかの選択肢を受ける、計画の削除の印、スクリプトが消さない、サンプルを消す、新しいインストールのテストをまとめて流す、知らないクラス、bundle の照合を外す、定数をホストの bundle id にする、アプリが `import IosLibrary`、要約が止めない、再起動なし。

- 1 回目は 12 個（再起動の前）で、11 個が落ちて「ほかの選択肢」が残った。`--device-allow` などは後ろの判定でも止まる**同じ動きの変異**で、判定が余分だったので消し、残りの選択肢を壊す形に直した
- 1 回目の変異なしの回が `test_signals_and_exit_remove_the_device_results` で落ちた。**私が `nohup` で起動したので HUP が無視のまま継がれた**のが原因で、`nohup` を外して流し直した（`run_in_background` で通る）。ランナーの問題ではない
- 再起動を足した後に、変えた所に関わる 4 個（ほかの選択肢、再起動、スクリプトが消さない、サンプルを消す）を流した（4/4 が落ちた）。**残りの 9 個は再起動を足す前のソースの結果で、流し直していない**

**本物のアプリとシミュレーターの 5 個**（使い捨ての写し。iPhone 16 / 18.3。合わせて 18 個で、依頼の目安より 3 個多い）。待ちと C を呼ばない行は、残ったダイアログで別の理由で落ちたので、再起動してから流し直した結果:

| 変異 | 結果 |
|---|---|
| アプリの bundle id をホストのものにして `xcodebuild` で直に流す | 落ちた（`Application info provider returned nil`）。`capi-check-sources` は build の前に止める（自己テスト） |
| スクリプトの削除を外して 2 回流す | 落ちた（`[launch.freshInstall@none] false`。exit 1）。ダイアログが残っていた回で、ほかの 5 件もそのせいで落ちている。この 1 件の文は削除のせい |
| 3 秒の待ちを 0 にする | 落ちた（`[common.version@foregroundActive]` と `@background` の比較）。後ろで呼んだことを行の状態が見ている |
| 行の id を重ねる | 落ちた（`matches 2 elements`） |
| **行が C を呼ばず、決まった文字列を返す（`report("0x020000")`）** | **残った**。UI テストからは見分けられない。`Rows/` のどれかが C を呼ぶことしか照合は見ない。止めるのはレビューで、**行の中身を確かめる形は作っていない** |

**使い捨ての確かめ（変異ではない）**: 行を 60 個足して、画面の外の最後の行を 25 回押し、`result.line.26` を読む → 通った（156 秒。行が多いと 1 回のタップが約 6 秒）。自動のスクロールで届き、結果の列が画面から外れても読める。

変異で落ちたアプリの crash report は 0 個（`~/Library/Logs/DiagnosticReports` に `IosLibraryCApiUI*` なし）。消したものは無い。

### 5.7 設計書が読み切れなかった所と、読み方（設計書は変えていない）

| # | 所 | 読み方。持ち主に見てほしいこと |
|---|---|---|
| 1 | 第 2 部 13 章「`test_ios.sh` のランナーの区分」。「区分」は UI テストの設計書 U-9 の 6 つ（`systemui` など）と同じ言葉 | U-9 に 7 つ目を足す話ではなく、**流し方の 1 つ**（`--capi-ui`）と読んだ。U-9 の区分は実機の許可の単位で、このテストは実機で流れない |
| 2 | 第 1 部 6.1 の最後の行「`test_ios.sh` に C ABI のテストを 3 通りで流す区分を足す（2b の成果物）」と TB-2b、TB-12 | **`IosLibraryCApiTests` の 3 通りは TB-12** のまま（TB-12 の行に書いてある）。TB-2b は UI テストだけ |
| 3 | 第 2 部 12.1 の「前面」の行は環境を書いていない。12.2 の「上の行はシミュレーターだけ」は 12.2 の話 | 12.1 の前面の行もシミュレーターだけと読んだ（同じアプリで流し、そのアプリの UI テストに実機の守りが無い。P1-20 の実機は ASan と smoke だけ） |
| 4 | 第 1 部 5.1 の木に `IosLibraryCApiUITestApp/`、`IosLibraryCApiUITests/` が無い | **足すことを勧める**（TB-1 の `IosLibraryCApiTestHost/` と同じ。木の 2 行）。依頼のとおり変えていない |
| 5 | 第 1 部 6 章、第 2 部 15.2 の iPad Pro 11-inch (M4) / 18.3 | アプリは iPad の設定を持つ（`TARGETED_DEVICE_FAMILY = 1,2`）。指定の 2 台の外なので流していない。アクションシートと Share の行が来る TB-5、TB-9 で要る |
| 6 | 第 2 部 12.2 の「ランナーが書いた内容」、UI テストの設計書 6.3 の `test_ios.sh` の説明 | ランナーの名前は `IosLibraryCApiUITests-Runner` になる（貼り付けのダイアログの文）。6.3 には `--capi-ui` が無い。文書は `scripts/README.md` だけ直した |

**第 2 部の 13 章の完了の条件「12.1 の前面の行と 12.2 を流せる」の読み方**: 関数がまだ無いので**流した**のではなく、**流す道を 1 本ずつ通した**。

| 行 | 道 | 通したもの |
|---|---|---|
| 12.1 前面 | `runAfterDelay` → 後ろで C → `@background` の行 → 戻って読む | `testACallCanBeMadeInTheBackground`（`ntk_version`） |
| 12.2 コールドスタート | 起動の中の `ntk_notification_install` | `testTheLaunchInstallsTheDelegateThroughC`（通知からの起動は未） |
| 12.2 権限、許可の後 | 消す → 未決 → 押す → 状態 | 5.3（写しの中。C でなく直の API） |
| 12.2 Dialog、Share、Clipboard、バナー | 行と結果の行だけ | **未**。C の関数が無い |

### 5.8 確かめられていないこと

- **実機では何も流していない**。基底のクラスの実機の守りは組めることだけで、動いたことは無い
- `foregroundInactive`（Control Center）の道。`runAfterDelay` で足りるはずだが通していない
- このアプリから Dialog、Share のシート、バナーを出すこと（C の関数が来る TB-5、TB-7、TB-9 で）。`ForegroundLocator` が見つける画面はサンプルと同じ形のはずだが、**見ていない**
- コールドスタート（通知のタップからの起動）。`launch.*` の行は `App` の中の順しか見ていない
- iPad、x86_64、ASan、TSan でのこのアプリ
- 5.6 の行の中身（C を呼ばない行）

### 5.9 時間

22:53〜23:45 ごろ（約 50 分）。うち権限の測りが約 10 分（23:07〜23:18。2 台を並べて）、変異が約 15 分。**目標の 2 時間の中**。

### 5.10 レビューの直し（Codex: 実機の守りと誤った成功。Claude: 設計と形）

レビューの本文のうち Codex の分は読み、Claude の分はメインのセッションの要約で受けた。指摘は実物で確かめてから直した。

**5.1〜5.9 のうち今は違う所**: UI テストは 8 件（`testOnlyTheNamedSectionIsDrawn` を足した）。5.5 の「`generic/platform=iOS` で組めた」は、今は組めないのが正しい（下の 1）。5.6 の「C を呼ばない行が残る」は、今は照合が止める（下の 2。ただし C も呼ぶ行は残る）。5.3 の測りは再起動なしの順で、今の順の測りは下の 9。5.1 と 5.4 の誤りはその場で直した。

| # | 区分 | 指摘 | 確かめ | 直したこと |
|---|---|---|---|---|
| 1 | A | 2 つのターゲットが実機向けに組めて入る | **そのとおり**。`-showdestinations` に `platform:iOS` と `platform:macOS, variant:Designed for [iPad,iPhone]` が出た。Xcode から Test / Run すれば `setUpWithError` の前に入る（入れてはいない） | `SDKROOT`、`SUPPORTED_PLATFORMS` を `iphonesimulator` に。`DEVELOPMENT_TEAM` を消した（無くても組める）。`capi_project_problems` が求める（設定ごと、`[sdk=` と xcconfig も拒む）。`setUpWithError`、`tearDownWithError` を `final`。`launchApp` と `CApiUITestApp.launch` も確かめる。**結果: `-showdestinations` は `platform:iOS Simulator` だけ。`generic/platform=iOS` の build は exit 70（`Unable to find a destination`）** |
| 2 | A | 7 つの形が 0 件で通る | **そのとおり**（`rev/t.py` で 7/7 が `[]`） | 下の表。`rev/t.py` は 7/7 が問題ありになった |
| 3 | B | 26.3 で遅く、Xcode の話をせず落ちる | そのとおり | 枝の最初で 26.6 でなければ exit 2、`DEVELOPER_DIR` の形を出す。切り替えない。`xcode-select` に触れない。自己テスト、偽物の build 失敗、README、usage |
| 4 | B | 1 つの画面に全部の行。60 行で 1 タップ約 6 秒、3 秒の窓が危ない | **半分だけ**。6 秒は私の 5.6 の測りで、変異と並行の負荷の下、かつ番号で読む古い形だった。測り直すと下の表のとおり約 3 秒で、60 行でも `@background` になった（各 1 回）。**ただ、行の数に比例して倍になるのは本当なので直した** | `NTK_CAPI_SECTION` の launchEnvironment で選んだ節だけを描く。指定が無い起動（人、システムが起こしたプロセス）は全部を描く。知らない節は何も描かない |
| 5 | B | 再起動が、通ったテストの残したダイアログを隠す | そのとおり | 基底の `tearDownWithError` が springboard の alert を見て落とす。文に springboard のラベルを入れない（監視の文からもラベルを消した）。シミュレーターだけ |
| 6 | B | TB-3、TB-5 が割れる補助 | そのとおり | `start(rowId)`（待たない）、`waitForLine(ofRow:occurrence:timeout:)`、`run` と `runInTheBackground` に `timeout:`。番号で読むテストを移し、`result.count` と番号の口を消した |
| 7 | B | README に再起動が書いてない | そのとおり | README と usage。既に起動しているときに警告を 1 行。**ロックは無く、走っている間ほかに何も流さないのが決まり**と書いた |
| 8 | C | `shutdown` の失敗を `|| true` が捨てる | そのとおり（読んで確かめた。失敗は起こしていない。偽物だけ） | `shutdown` の後に状態を読み、`Shutdown` でなければ止める。`bootstatus`、`uninstall` の失敗に文 |
| 9 | C | 今の順（再起動 → 消す）を測っていない | そのとおり | 下の表 |
| 10 | C | 型ごとの logger、エラーのパス、5.1、5.4、変異の流し直し | そのとおり | `CApiRow.swift` を 4 つの logger に。`FreshInstallMarker` は domain と code。文を直した。変異は下 |

**2 の直し**: 既にあるランナーの字句解析（`lex`）を使った（`check_c_abi_contract_ios.py` の `strip_comments` は文字列を消すだけで、つなぐと依存が増える）。コメントと文字列は判定に入らない。

| 形 | 今の結果 |
|---|---|
| `internal` / `public` / `package import IosLibrary` | 止まる（前に何かある、知らないモジュール） |
| `import os; import IosLibrary` | 止まる |
| `@_spi(X) import IosLibrary` | 止まる |
| すべての行を決まった報告に。`runAtLaunch` だけ残す | 止まる（**行ごとに、閉包の中に本物の呼び出しを求める**。呼び出しはヘッダーの 134 関数の名前に `(` が続くもの） |
| `ntk_` がコメントだけ | 止まる。文字列、`ntk_x` の括弧なし、型の変換 `ntk_notification_error(0)` も呼び出しに数えない |
| `Rows/` で `UIPasteboard.general` | 止まる。`Rows/` の `import` は `Foundation`、`IosLibraryCApi`、`os` だけにした |
| `.m` | 止まる（`.swift` のほかのファイルをすべて拒む）。**TB-7 で添付の固定のファイルをアプリに持つならここを広げる** |

- **直に呼ぶと止める名前**（私の判断）: `UIPasteboard`、`UIPasteControl`、`PasteButton`、`UNUserNotificationCenter`、`UIAlertController`、`UIActivityViewController`、`ShareLink`、`confirmationDialog`、`openSettingsURLString`、`NSClassFromString`、`objc_getClass`、`dlopen`、`dlsym`。SwiftUI の `.alert` は入れていない（ありふれた名前で誤って止める）。**この表は閉じていない**
- **build の後**: アプリの本体と `.debug.dylib` を `nm -u`、`otool -L` で読み、`10IosLibrary`・`14IosLibraryCApi` の記号なし、`IosLibrary.framework` を載せない、`IosLibraryCApi.framework` を載せる、`_ntk_*` がソースの呼び出しとちょうど同じ、を見る。**アプリの Frameworks の段から `IosLibrary` を外した**（依頼には無い。外しても組めて動き、`otool -L` で見分けられるようになる。埋め込みは残す）
- **本物の build で確かめた**（使い捨ての写し）: `import IosLibrary` と `IosDialogManager.shared` を足すと、組めて、`capi_binary_problems` が `_$s10IosLibrary...` と `IosLibrary.framework` の 2 件を返した
- **`_ = ntk_version(); report("0x020000")` のように C も呼ぶ行は、どの照合でも止まらない。レビューの範囲**

**測り（9、4、5。使い捨ての写し。bundle id は同じ。権限は `UNUserNotificationCenter` を直に読む）**

| 測ったこと | iPhone 17 Pro / 26.2 | iPhone 16 / 18.3 |
|---|---|---|
| 許可（2）→ 再起動 → 消す → 0 | 0（1 回） | 0（1 回） |
| 拒否（1）→ 再起動 → 消す → 0 | 0（1 回） | 0（1 回） |
| 再起動の `simctl list` の状態（`shutdown` の直後） | `Shutdown`（5/5） | `Shutdown`（5/5） |
| ダイアログを残して通るテスト | `the test left a system alert open; nothing was pressed` で失敗（1 回） | 同じ（1 回） |
| 1 回の `run`（6 回）: 2 行の節 | 1.49〜1.71 秒 | 1.50〜1.69 秒 |
| 1 回の `run`（6 回）: 62 行の節 | 2.90〜3.98 秒 | 2.42〜3.04 秒 |
| 後ろの呼び出し: 2 行の節 | `@background`（1 回） | `@background`（1 回） |
| 後ろの呼び出し: 62 行の節 | `@background`（1 回） | `@background`（1 回） |

`erase` は今回も使っていない。

**流していないのに直したもの**: 1 の基底の守りの実機の枝（`#if !targetEnvironment(simulator)`）は、ターゲットがシミュレーターだけになったので今はコンパイルされない。`capi_test_source_problems` が文字の上で残っていることを見るだけ。

#### やらないこと（指定どおり。理由）

| 指摘 | 理由 |
|---|---|
| C-3 `CAPI_UI_CLASSES` の 3 つ目の値 | TB-7 の話。今は要らない |
| C-4 期待値の 0 | delegate の確かめは TB-8 |
| C-6 名前 | 直さない |
| Codex: `capi-record --results` の任意のパス、`capi-plan --kind` がラベルを信じる | どちらも実機に触れない。普通の流れではスクリプトが渡す |
| Codex: scheme そのものを照らさない（`testPlan` を見ない） | **依頼に無いので直していない**。スクリプトが scheme を決め打ちし、列挙と結果がターゲットを見る |
| Codex: `test_the_sample_still_refuses_these_names` が新しいコードなしでも通る | **依頼に無いので残した**。害は無い |

#### 設計書の文（持ち主にコミットのときに見せる。作業ツリーにある）

| 所 | 変更 |
|---|---|
| 第 1 部 5.1 の木 | `IosLibraryCApiUITestApp/`、`IosLibraryCApiUITests/` |
| UI テストの設計書 6.3 | `--capi-ui` は流し方の 1 つで U-9 の 7 つ目の区分ではない |
| 第 2 部 15.2 | **12.1 の前面の行はシミュレーターの 2 機種で、サニタイザーなし。サニタイザーの網羅は `IosLibraryCApiTests`。メインのセッションからの推奨で、持ち主が 2026-11-04 に決めた** |
| 第 2 部 13 章 | TB-5、TB-9 の完了の条件に iPad Pro 11-inch (M4) / 18.3。TB-8 にアプリへ起動の形を伝える口（ファイル。SA-18 と同じ）。作っていない |
| README 7.4 の `ios-arm64` の行 | 「UI テスト」はサンプルのもの。`IosLibraryCApiUITests` はシミュレーターだけ。実機の行で、その時点で C の UI テストが無かったので、この読みで明らかと判断した |

`check_design_consistency.py` は 4 つとも exit 0、FAIL 0。

#### 最後のソースの結果

| 実行 | 結果 |
|---|---|
| `--capi-ui`（iPhone 17 Pro / 26.2。`DEVELOPER_DIR` は 26.6） | 8/8。exit 0 |
| `--capi-ui`（iPhone 16 / 18.3。同じ） | 8/8。exit 0。起動していたので警告が 1 行 |
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 141/141 |
| `check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP は `complete` と `symbols` |
| `test_ios_ui_runner.py` | Ran 204 tests、OK |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `git diff` | `ios/IosLibrary`、`ios/IosLibraryExample`、`include/NativeToolkitC/`、capi のソース、信頼する UI テストのファイルに差なし |

#### 変異（最後のソース。全部）

`ios_ui_runner_mutations.py` の全部の表（137 個と変異なしの回。今までの 95 個と `capi-ui` の 42 個）を 5 並列で流した（00:20〜01:05）。**変異なしの回は通り、136 個が落ち、1 個が残った。`NOT APPLIED` は 0 個**。本物の台帳は変わらない。

| 範囲 | 個数 | 結果 |
|---|---|---|
| 今までの表 | 95 | 95 個が落ちた |
| `capi-ui`（5.6 の 13 個と今回の 29 個） | 42 | 41 個が落ち、1 個が残った |

- **残った 1 個**（`capi-ui simulator only: the tests not checked`。`capi-check-sources` が UI テストのソースを見ない）: 判定の関数のテストはあるが、スクリプトから呼ぶことのテストが無かった。`test_a_test_source_without_its_guard_stops_it_before_the_build` を足し、この 1 個を流し直して落ちた
- **限り**: このテストを足したのは全部の回の途中（46 個が終わった後）で、足した後に全部は流していない。変えたのはテストのファイルだけで、ランナーとスクリプトは全部の回の間変わっていない。テストが増えれば落ちるものは増えるだけなので、数は下がらない
- 1 回目の全部の回は途中で止めた。23 個のところで、自分の直しの重なりで `pillar 1 naming: an empty -only-testing list` が `NOT APPLIED` になっていたため（`capi_only_testing_arguments` の文が同じだった）。同じ原因の 2 個（スクリプトの `-derivedDataPath` の行）と合わせて、**今までの変異は変えず、私の新しい行の文と順を変えて**当たるようにした。`capi-ui check: other languages pass` は変異の文を直した

5.6 の本物のアプリの 5 個は、今回は流し直していない（`--capi-ui` の 8 件と上の本物の build の 1 個だけ）。

#### 確かめられていないこと

- 実機では何も流していない。`-showdestinations` の変化は確かめたが、Xcode の画面から実機を選べないことは見ていない
- iPad、ASan、TSan でのこのアプリ。Dialog、Share、バナー（5.8 のまま）
- `simctl shutdown` が本当に失敗する場面は起こしていない（偽物だけ）
- クラスの中でダイアログを残したテストの後ろは一緒に落ちる（5.4）

時間: 23:55〜01:10 ごろ（約 75 分）。目標の 45 分を超えた。多くは全部の変異の 45 分。途中で知らせた。

#### Codex の再チェック（A なし。B を直した）

| # | 指摘 | 確かめ | 直したこと |
|---|---|---|---|
| 1 | 知らない `NTK_CAPI_SECTION` で 0 行になり、行を名指ししないテストが通る | そのとおり（`launch.*` の行は描く行によらない。読んで確かめた） | アプリが `[launch.section@none] <節 / all / unknown>` を書く。`CApiUITestApp.launch` が読み、選んだ節でなければ止める。補助は enum `CApiSection` だけを受け、表に無い名前はコンパイルで止まる。enum にあってアプリに無い節は `launch` で止まる。本物の回で、enum に `nosuch` を足して流すと `the app did not draw the section nosuch: [launch.section@none] unknown` で落ちた（使い捨ての写し。18.3、1 回） |
| 2 | `-f` がファイルを黙って飛ばす | そのとおり | 本体が無ければ止まる。`otool -L` が `@rpath/...debug.dylib` を挙げるのに無ければ止まる。本体だけの形（dylib を使わない）は通る |
| 3 | `simctl list` に時間の限りが無い。最後の `shutdown` の結果を見ない | そのとおり | `capped 120` と失敗の文。`restore_simulator` は状態を読み、`Shutdown` でなければ警告 1 行で、**通った回を落とさない**。この関数はサンプルのシミュレーターの回にも通る（警告が増えるだけ） |
| 4 | 取り除いても残る自己テスト | そのとおり | 止める名前をテストに書き出した。ガードの照合を関数の先頭からのトークンの完全一致にした（`throw` が無い、`print` に変わる、前に別の文、`try?`、文字列の補間でラベルを入れる、はどれも止まる）。偽物の `nm`、`otool` がファイルごとに別の答えを返す |
| 5 | 「whatever starts the build」は誤り | **そのとおり**。`-sdk iphoneos SUPPORTED_PLATFORMS=iphoneos SDKROOT=iphoneos CODE_SIGNING_ALLOWED=NO` の `build` が exit 0 で `Debug-iphoneos` を作った（組むだけ。実機には何も入れていない）。`-destination 'generic/platform=iOS'` だけは同じ上書きでも exit 70 | コメント、基底のコメント、README を「宛先に実機が出ない。上書きで組めはするが、そこは `device-testing.md` の決まりが受け持つ」に直した。**1 の表の「今は組めないのが正しい」は普通の呼び方の話** |

**偽物の `nm` の注意**: 本体にも C の関数を持たせている。本物の本体は持たない。どちらのファイルを読み落としても変わるようにするためで、本物の形ではない。

**ガードの照合で見えないまま残るもの**（トークンの限り）: そのコードが実際に動くこと。実機の枝はコンパイルされない。`requireSimulator` を呼ぶ関数を別に増やして `XCUIApplication` を直に操作すること。`tearDown` の照合は形だけで、ダイアログを見つけることは本物の 1 回（`testG`）しか確かめていない。

#### 残すもの（指定どおり）

| 指摘 | 扱い |
|---|---|
| 行から呼ぶ補助がシステムを読む（`UIApplication` など） | レビューの範囲 |
| 止める名前の表のほかの抜け道 | わざわざ工夫しないと通れないので、これ以上広げない |
| Xcode の版の文字の変種（`Xcode 26.6 garbage` など） | 直さない |
| `tearDown` の確かめが 1 回の読み取りだけ（後から出るダイアログは見えない） | 直さない |

#### 再チェックの後の結果

| 実行 | 結果 |
|---|---|
| `--capi-ui`（iPhone 17 Pro / 26.2。26.6） | 8/8。exit 0。最初が Shutdown で、終わりも Shutdown（警告なし） |
| `--capi-ui`（iPhone 16 / 18.3。26.6） | 8/8。exit 0。起動していたので再起動の警告が 1 行 |
| `test_ios_ui_runner.py` | Ran 210 tests、OK |
| 変異（ここで変えた所だけ 10 個） | **10/10 が落ちた**。変異なしの回は通る。本物の台帳は変わらない |

`IosLibraryCApiTests`、contract の照合、全部の変異の表はこの直しの後に流していない（指定の範囲の外。capi の本体、ヘッダー、照合のスクリプトは変えていない）。表は 145 個になった。上の 10 個は、足した 8 個（dylib だけ読む、本体が無い、dylib が無い、`list` の時間の限り、最後の警告、2 つのガードの `throw`、`dlopen`）と、スクリプトの文が変わって書き直した 2 個（本体だけ読む、状態の確かめ）。**残りの 135 個はこの直しの前のソースの結果**（`NOT APPLIED` にならないことだけは 146 行すべてで確かめた）。

時間: 01:14〜01:27 ごろ（約 13 分）。

#### 持ち主の決定と、直しの後の確かめ（メインのセッション）

- 第 2 部 15.2 の文は、持ち主が 2026-11-04 に「判断が要るものは推奨でいい」と決めたので、推奨のとおり決定とした
- 実装者とは別に、最後のソースで `--capi-ui`（iPhone 17 Pro / 26.2）の 8/8、`IosLibraryCApiTests` の 141/141、`test_ios_ui_runner.py` の 210 件、`check_c_abi_contract_ios.py` の FAIL 0 を流した。`--capi-ui`（iPhone 16 / 18.3）と変異は実装者の結果で、流し直していない
- レビューは Claude と Codex が直しの前に 1 回ずつ、Codex が 1 回目の直しの後に読んだ（ビルドも実行もしていない。A なし）。2 回目の直しの後のレビューはしていない
