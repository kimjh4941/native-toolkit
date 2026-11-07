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

## 6. TB-3

第 2 部 13 章の TB-3（OP-01〜OP-10、OP-15、結果のハンドル）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。

### 6.1 足したもの

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Clipboard/ClipboardEntry.swift` | `@c @implementation` だけで 31 関数。各 1 行 |
| 受け口 | `Clipboard/ClipboardReceiver.swift` | OP ごとの関数。共通の `accept`（callback の `NULL` → 入口の写し → `Registry.accept`）と `finish`（`errorCode` の写し、ハンドルは `deliver` の中で作る） |
| 写し | `Clipboard/ClipboardMapping.swift` | 純粋な関数: `scope`、`requiredScope`、`creationRequest`、`content`、`options`、`utType`、`matchingTypes`、`patterns`、`bits`、`error(forCode:)`、`ClipboardRejection`（共通の値と `EMPTY_ITEMS`、`EMPTY_PATTERNS`） |
| ハンドル | `Clipboard/ClipboardHandles.swift` | `ClipboardReadResultHandle`、`ClipboardSnapshotHandle` と 18 の読み取り（ほかに `_free` が 2 つ） |
| JSON | `Clipboard/ClipboardValuesJson.swift` | P2-8 の形。キーの順は固定、`detectedPatterns` は並べる。有限でない数は `null` |
| Common（機能の知識なし） | `Common/CApiBytes.swift`（新規）、`CApiString.requiredArray`、`Handle.text(of:_:)`、`Handle.retained`（`private` をやめた） | 第 1 部 5.9 の入力のバイト列（4.5 で TB-3 に送ったもの）。`const char* const*` の配列 |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 31 個を外した（91 個が残る） |
| 行 | `IosLibraryCApiUITestApp/Rows/ClipboardRows.swift`、`CApiRow.swift` の節の一覧 | 20 行。どの行も `ntk_` を呼び、完了の値を書く |
| テスト | `IosLibraryCApiTests/ClipboardMappingTests.swift`（50）、`ClipboardEntryTests.swift`（42）、`ClipboardHandleTests.swift`（14）、`ClipboardValuesJsonTests.swift`（5）、`CApiStringInputTests.swift`（1 件足した）、`ClipboardTestSupport.swift` | 141 → 253 件（レビューの直しの後。直しの前は 244 件） |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`（8 件足した）、`CApiUITestApp.swift`（`CApiSection.clipboard`） | 7+1 → 15+1 件 |
| ランナーの自己テスト | `scripts/tests/test_ios_ui_runner.py` | 行が増えると落ちる 2 か所を直した: 偽の `nm` の記号（`FAKE_APP_MORE_SYMBOLS`）と `capi_source_calls` の決め打ちの集合。**`scripts/ios_ui_runner.py` は変えていない** |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイルは変えていない。

**`IosLibraryCApiTests` は名前付きのペーストボードだけを使う**（第 2 部 12.2。実機の ASan で流れるため）。`NULL` の scope は写しの関数か、入口で拒まれる呼び出しにしか渡さない。general に触れるのはシミュレーターだけの UI テスト用のアプリで、general を読む行は、その前にアプリか UI テストのランナーが決まった文字列を書いている。Mac のクリップボードを読むコードは足していない（**設計の意図で、確かめた事実ではない**。6.6）。

### 6.2 コマンドと結果（レビューの直しの前のソース。最後のソースの結果は 6.8）

Xcode 26.6 は `DEVELOPER_DIR`。`xcode-select` は触っていない。

```
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath <scratch> [-enableThreadSanitizer YES | -enableAddressSanitizer YES] test
scripts/test_ios.sh --udid <UDID> --capi-ui
```

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 244/244（TB-2b の 141 + 103） |
| 同（iPhone 16 / 18.3） | 244/244 |
| 同 TSan（iPhone 17 Pro / 26.2） | 244/244。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 244/244。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2） | 16/16（`CApiRoundTripUITests` 15、`CApiFreshInstallUITests` 1）。exit 0 |
| `--capi-ui`（iPhone 16 / 18.3） | 16/16。exit 0 |
| framework の Release（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。組むだけ）`--library --architectures arm64` | `OK symbols`（43 symbols、1 architectures）。capi の警告 0 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（43 symbols、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP 2（`complete` と `symbols`）。`entries` は 43 of 134、91 not implemented yet |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 278 tests、OK |
| `python3 scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `python3 scripts/check_design_consistency.py`（この記録） | FAIL 2。**どちらも TB-3 の前からある種類**: 770 行の表の列数（TB-2b の行）、OP の表が無い文書で OP の ID を書くこと（前は 151 行、今は 6 章の OP-03〜OP-11 も数える）。この記録は設計書でないので直していない |

最後の 2 回の Release、照合と自己テストは、テストのファイルを 1 つ直す前に流した（6.3 の 256 バイトの直し。製品のソースと `scripts/` はその後変えていない）。

### 6.3 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

40 個（`Clipboard/`、`CApiBytes`、`Handle.text` の引数の検査、所有権、ハンドル、写し）。1 個あたり 30〜50 秒。**最初の回で 38 個が落ち、1 個が組めず（変異の書き方の誤り）、1 個が生き残った。** 直した後は全部落ちた。

| 生き残り | 原因 | 直し |
|---|---|---|
| `CApiBytes.copied` を `Data(bytesNoCopy:)` にする | **テストが弱かった**: 3 バイトは `Data` が中に持つので写しになる | `testTheInputIsCopiedBeforeItReturns` を 256 バイトにした。落ちた |
| （組めなかった）`read_data_async` の「データなしは失敗」 | 変異の式の型 | 書き直して流した。`testReadDataGivesNullWhenThereIsNoItemOfTheType` で落ちた |

落ちたものの例: `reserved1` の名指しを消す（scope は `read` と `readIfPresent` で別に、content）、`requiredScope` が `NULL` を受ける、GENERAL が `name` を読む（読めないポインタで落ちる）、GENERAL を作れる、UNIQUE が `name` を読む、空の名前、空のパス、`EMPTY_ITEMS`・`EMPTY_PATTERNS` の入口を消す、重複の型、`not_local_only` の反転、有限でない期限、ビットの表、エラーの表の行、`release` を呼ばない 2 通り、ハンドルを渡さない、`append` が `copy` を呼ぶ、`copy` が選択肢を捨てる、完了の失敗が `NONE`、読み取りの取り違え、`matching_at` の -1、`has_matching`、`out_size` を書かない、U+0000、JSON の有限でない値とキー。

**変異で落ちたプロセスのクラッシュレポート**（`~/Library/Logs/DiagnosticReports/`。記録してから消した。どれも `IosLibraryCApiTestHost`、iPhone 16 のシミュレーター）: `IosLibraryCApiTestHost-2026-11-04-020848.ips`、`-020932.ips`、`-021218.ips`、`-021505.ips`、`-022404.ips`。

### 6.4 設計書が読み切れなかった所と、読み方（この表は実装の時点のもの。設計書の直しは 6.8）

| # | 所 | 読み方 |
|---|---|---|
| 1 | 13 章の「結果のハンドル」 | `read_result`（7）と `snapshot`（13）だけ。`loaded_item`（7）と `change`（8）は OP-11、OP-16 が作るので TB-4（依頼の「読み込みと監視は足さない」）。TB-3 は 31 関数で、実装は 43 / 134 |
| 2 | 6.1 の `HTML` の入口の検査「`NULL`」 | **`html` だけが必須で、`text` の `NULL` は `""`**。Android（`ntk_clipboard_copy_html`）と E-15 に合わせた。`text` が不正な UTF-8 なら拒む |
| 3 | 6.1 の `create_pasteboard_async` の「`NAMED` は `name` が必須」 | 同じ節の scope の「必須」と同じに読み、**`NULL` と空文字が入口で `INVALID_PARAMETER`**。空白だけは `IosLibrary` の `INVALID_NAME`（完了）。Android と Windows にこの関数は無い |
| 4 | 12.1「入口と完了の分け方」の `EMPTY_CONTENT` | Clipboard の `EMPTY_CONTENT` は 6.1 と 11.3 のとおり完了で返す（テストもその形）。12.1 の行は Share の `noValidItems` の話と読んだ |
| 5 | 検査の順（5.10 の並び）は 1 つの関数の引数の間の順を決めていない | `callback` の `NULL`（Android と同じく先）→ 宣言の順の引数。`EMPTY_ITEMS` は `options` より先に返る |
| 6 | 5.1 の表のファイルは `ClipboardReceiver.swift` だけ | Notification の `NotificationJson.swift` に倣って `ClipboardMapping`、`ClipboardHandles`、`ClipboardValuesJson` に分けた。**5.1 の表と第 1 部 5.1 の木に行を足すかは持ち主の判断**（`Common/CApiBytes.swift` も） |
| 7 | `Registry.accept` は `canceled` を必ず取る | 取り消せるのは読み込みだけなので、TB-3 の関数では呼ばれない。形だけ `CANCELED` を渡す（テストは無い） |
| 8 | P2-8 の `number`、`amount` に有限でない値 | `null`（キーを保ち、ほかの値を失わない）。`JSONSerialization.isValidJSONObject` はこれらの値に偽を返す（テスト `testJSONSerializationDoesNotTakeWhatIsNotFinite` で確かめた）。`ClipboardValuesJson.swift` は先にそれを問うので、値を残すと `text(of:)` は nil になり、受け口は `UNKNOWN` で完了する（**ここはコードを読んだ結論で、完了までは流していない**。前の版の「Objective-C の例外で落ちる」は誤りで、このコードでは起きない。1 回目の変異「JSON: not finite passes」は `crash=False` で落ちた） |
| 9 | `read_result_item_count` と `ClipboardReadResult.numberOfItems` | `items.count`。ライブラリでは同じ値 |
| 10 | 6.1 の `get_snapshot_async`「`matching_types` が `NULL` か件数 0 なら」 | コードは件数が 1 以上の `NULL` を `INVALID_PARAMETER` で拒む（ヘッダーと第 1 部 5.9 のとおり）。**コードを残し、6.1 の文を「`NULL` は件数 0 のときだけ」に直した**（6.8） |

### 6.5 実装の途中で分かったこと

- **プレーンテキストの型は `public.plain-text` で読む**: 名前付きのペーストボードで `read_data_async` に `public.utf8-plain-text` を渡すと `NULL`（`NONE`）。テストと行は `public.plain-text` にした。マニュアルの候補
- **URL の `kind` で書くと `detect_patterns` は `probableWebURL` を返さない**（名前付き。0 と `NONE`）。文字列で書くと返す。テストは文字列にした
- **空の名前付きのペーストボードの `detect_patterns_async`、`detect_values_async` は `DETECTION_FAILED`**（ログで見た。OS の失敗をライブラリが写したもの。テストは固定していない）
- `async` の `tearDown` の中では main キューが回らない（`runMainQueue` が 10 秒待って落ちた）。テストの片付けは積むだけにした
- **UI テストのクラスを足すと `test_ios_ui_runner.py` が多数落ちる**（`CAPI_UI_CLASSES` の表と偽の列挙が 2 クラスで決まっている。1 回の試しで 19 件、行の増加ぶんを含む）。`ios_ui_runner.py` を変えず、`CApiRoundTripUITests` に足した。**TB-5 以降でクラスを分けるなら、表と自己テストを直す作業が別に要る**
- 12.2 の貼り付けのダイアログは TB-3 の完了の条件ではないが、`read_async`・`read_data_async`・`detect_values_async` の拒否の値（M3）は C からしか確かめられないので 4 件を先に足した（許可 1、拒否 3）

### 6.6 確かめられていないこと

- **実機では何も流していない**（指定どおり。`generic/platform=iOS` は組むだけ）。iPad、x86_64 のスライスのテスト、iPhone 17 / 26.2 は流していない
- 12.1 の Clipboard の行のうち TB-4 のもの（`.file`、監視）。12.2 の `load_item_async` の貼り付け、`read_data_async` と `detect_values_async` の**許可**、取り消し
- 完了の `CONTENT_TOO_LARGE`、`IMAGE_LOAD_FAILED`、`IMAGE_ENCODE_FAILED`、`TIMED_OUT`（5 秒。答えない）、`UNKNOWN` は写しの関数のテストだけ。C からは起こしていない
- `not_local_only` と `expiration` が OS に効いたかは読めない（写しの関数と、過去の日時の `INVALID_EXPIRATION` まで）
- 第 1 部 6 章の 8 スレッド × 25 回の同時の呼び出しは Clipboard の関数では流していない。main を止めて別のスレッドから呼ぶのは 11 関数とも流した（すべての関数の網羅は TB-10）
- 12.1 の「8.2 の名前がテストのソースに現れる」の照合は 2a に無い（今のところ人の目）
- **色と画像ファイルは、OS に届いた値を比べていない**: `testACopiedColorShowsInTheColorFlagOfTheSnapshot`、`testACopiedImageFileShowsInTheImageFlagOfTheSnapshot` は `has_colors`、`has_images` の旗だけを見る（前の名前の「ラウンドトリップ」は言い過ぎだったので変えた）。12.1 の「9 種の `kind` のラウンドトリップ」は、この 2 種については旗まで
- **`testDetectingValuesTheUserDenies` は遅い回に落ちうる**: 検出の期限 5 秒はライブラリの既定（`ClipboardTimeouts.detection`）で、`init(timeouts:)` は C から使えないのでテストが決められない。テストはダイアログを最大 10 秒待つので、ダイアログが 5 秒より後に出ると `TIMED_OUT` になり、期待の `DETECTION_FAILED` と違って落ちる。**直せないので残す**。今までの回では起きていない
- **`HTML` の `text` の `NULL` は、読み返しでは `""` を確かめられない**: 名前付きのペーストボードに `<b>x</b>` を `text` の `NULL` で書いて `read_async` で読むと、`_item_text_at` は `""` でなく `x` を返した（iPhone 17 Pro / 26.2 で 1 回測った。18.3 では測っていない。HTML の本文から作られた文字列に見えるが、誰が作ったかは確かめていない）。OS の振る舞いなので固定せず、C からのテスト `testCopyingHtmlWithoutPlainTextKeepsTheHtml` は `NONE` と `public.html` の読み返しだけを見る。`""` になることは写しの関数のテスト（`testHtml`）まで。ヘッダーの `NULL is ""` は渡す値の説明で、読み返しの値の約束ではない
- **Mac のクリップボードとの同期は測っていない**: この Mac の `defaults read com.apple.iphonesimulator PasteboardAutomaticSync` は 1。03:03 の時点で Simulator.app は動いていなかった。UI テストのランナーはシミュレーターの general に書く（`CApiRoundTripUITests.swift` の `writeFromTheRunner` と `testDetectingValuesTheUserDenies`）。流した回が Mac のクリップボードに届くか、Mac のコピーが読む行に届くかは未確認。測るには持ち主の Mac のクリップボードに触れることになるので測らない。設定は変えず、Simulator.app も開かず、`pbcopy`、`pbpaste` も使っていない

### 6.7 時間

01:33〜02:50。うち変異が約 30 分（02:07〜02:39。別のシミュレーターで検証と並べて流した）、`--capi-ui` は 1 回 8 分。目標の 03:30 の中。

### 6.8 レビューの直し

レビューの指摘（Codex と、メインのセッションが読んで確かめたもの）をメインのセッションから受けて直した。

| 指摘 | 直したこと |
|---|---|
| A（必ず直す） | `CApiString.requiredArray`: `(size_t)1 << 61` のような件数は `Int` で正になり、配列の外を読んでいた。**要素を読む前に `multipliedReportingOverflow` であふれを拒む**（`StructReader.readArray` と同じログの形）。テスト: `testACountWhoseSizeOverflowsIsRejectedBeforeAnyRead`（1<<60、1<<61、`Int.max`）、C から `testAMatchingTypeCountThatOverflowsIsRejected`、`testATextCountThatOverflowsIsRejected`（戻り値、`release`、完了なし）。どれも最初の要素を読むとプロセスが落ちる形 |
| B1 | 第 2 部 6.1 の `get_snapshot_async` の文を「`NULL` は件数 0 のときだけ」に直した。コードは変えない（6.4 の 10） |
| B2 | `ClipboardMappingTests` に足した: 内容の知らない部分（0 と 0 以外）、選択肢の知らない部分（0 と 0 以外）、選択肢の上限 4097 |
| B3 | 第 2 部 6.1: `number`、`amount` の有限でない値は `null`。`HTML` は `html` だけが必須で `text` の `NULL` は `""`。`Clipboard.h` と付録 A の `text` のコメントに同じことを書いた（コメントだけ） |
| C1 | 第 2 部 5.1 の表と第 1 部 5.1 の木に `ClipboardMapping`、`ClipboardHandles`、`ClipboardValuesJson`、`CApiBytes` を足した |
| C2 | 色と画像ファイルのテストの名前を、見ているもの（旗）に変えた。6.6 に記録 |
| C3 | C からの `HTML` の `text` の `NULL` のテストを足した。**読み返しは `""` でなかった**ので、`NONE` と `public.html` だけを見る。6.6 に記録 |
| C4 | C から: 空のパス（`INVALID_PARAMETER`）、`MULTI_REPRESENTATION` の件数 0（`EMPTY_ITEMS`）を `copy` と `append` で。戻り値と `release` を見る |
| C5 | `testTheTextOfTheQueriesIsCopiedBeforeItReturns`: `read_data` の型、`get_snapshot` の型、`create` の名前を、関数が戻った後に壊して解放する |
| C6 | 6.4 の 8 と `ClipboardValuesJsonTests.swift` の誤った説明（Objective-C の例外で落ちる）を直した。`isValidJSONObject` が偽を返すことはテストで確かめ、`UNKNOWN` になることはコードから読んだ |
| C7 | `test_ios_ui_runner.py` の確かめを、どのヘッダーにも無い `ntk_never_a_row` に変えた（行が増えても壊れない。実際に呼ぶと数えることも足した）。検出の 5 秒はライブラリの既定でテストが決められないので、6.6 に記録 |
| C8 | 6.6 に記録し、6.1 の文を設計の意図に直した。測っていない |
| 注 | 6.1 の「20 の読み取り」を 18 の読み取りと 2 つの `_free` に直した |

**設計書の直し（B1、B3、C1）は、メインのセッションが、持ち主の「07:20 まで推奨のとおりに進める」という指示の下で採ったもの。持ち主はまだ読んでいない。持ち主が決めたものではない。**

#### A の変異（使い捨ての写し。iPhone 16 / 18.3）

A の検査を効かなくする変異 1 個（`guard stride > 0 || ...`）を、3 つのテストで 1 つずつ流した。**3 つとも落ちた**（`EXC_BAD_ACCESS`。落ちた所は 3 つとも `CApiString.validated` ← `required` ← `requiredArray`）。ほかの変異は流していない（新しいテストのうち A のほかは変異で確かめていない）。

クラッシュレポート（記録してから消した）: `IosLibraryCApiTestHost-2026-11-04-030737.ips`、`-030812.ips`、`-030844.ips`。

#### 最後のソースの結果

03:10〜03:30 に、下の順で続けて流した。シミュレーターの仕事は重ねていない。ソースのハッシュ（`ios/` の capi と UI テストの 4 フォルダーと `scripts/` の `.swift`、`.h`、`.m`、`.py`、`.sh`）は流す前と後で同じ。**流した後に変えたのはこの記録の、この表だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 253/253 |
| 同（iPhone 16 / 18.3） | 253/253 |
| 同 TSan（iPhone 17 Pro / 26.2） | 253/253。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 253/253。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 16/16。exit 0 |
| `--capi-ui`（iPhone 16 / 18.3。Xcode 26.6） | 16/16。exit 0 |
| framework の Release（`generic/platform=iOS`。組むだけ）`--library --architectures arm64` | `OK symbols`（43 symbols、1 architectures）。capi の警告 0 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（43 symbols、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP 2。`entries` は 43 of 134、91 not implemented yet |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 278 tests、OK |
| `python3 scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

A の変異と 1 回目の 40 個の変異は、この最後のソースより前に流した。1 回目の 40 個は流し直していない（指定どおり）。B2、C3、C4、C5 の新しいテストは変異で確かめていない。`check_design_consistency.py` は第 1 部と第 2 部の直しの後に FAIL なし（`HEAD` の版も同じ）、この記録は 6.2 の 2 つの種類の FAIL のまま。

時間: 03:03〜03:31（約 28 分）。

## 7. TB-4

第 2 部 13 章の TB-4（OP-11〜OP-14、OP-16、OP-17、`loaded_item` 7 と `change` 8 のハンドル）と、TB-3 が 6.6 で残したもの。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。

### 7.1 足したもの

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Clipboard/ClipboardEntry.swift` | 21 関数。各 1 行。**`Clipboard.h` の 52 関数がすべて実装された** |
| 受け口 | `Clipboard/ClipboardReceiver.swift` | `loadItem`、`finishLoad`、`cancelLoad`、`startObserving`、`stopObserving`、`addChangeListener`、`removeListener`、`changeLedger`（`holdLimit: 0`）。`Failure` が要求の ID を取る形になり、`canceled` は読み込みの完了の形で実際に呼ばれる |
| 写し | `Clipboard/ClipboardMapping.swift` | `loadRequest`、`scopeKind` |
| ハンドル | `Clipboard/ClipboardHandles.swift` | `ClipboardLoadedItemHandle`、`ClipboardChangeHandle` と 13 の読み取り（ほかに `_free` が 2 つ） |
| Common（機能の知識なし） | `Common/Registry.swift` | `RegistryEntry` に `requestBox`、テストのための `Registry.requestBox(id:)`（`requestCount` と同じ扱い） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から Clipboard の 21 個を外した（**実際に 21 個**。残りは Dialog、Notification、Share の 70 個）。`entries` は 64 of 134 |
| 行 | `IosLibraryCApiUITestApp/Rows/ClipboardRows.swift` | 8 行足して 28 行。`loadText`、`loadFile`、`loadAndCancel`、`startObserving`、`startObservingNamed`、`stopObserving`、`addListener`、`removeListener`。どの行も `ntk_` を呼び、返った値を書く |
| テスト | `IosLibraryCApiTests/ClipboardLoadTests.swift`（新規 23）、`ClipboardObservationTests.swift`（新規 19）、`ClipboardHandleTests.swift`（12 足した）、`ClipboardMappingTests.swift`（3 足した）、`ClipboardEntryTests.swift`（3 関数を表に足した）、`ClipboardTestSupport.swift` | 253 → 310 件 |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`（9 件足した）、`CApiUITestApp.swift`（`isDrawnLine`、`waitForLine(ofRow:matching:)`） | クラスは足していない（指定どおり）。15+1 → 24+1 件 |

設計書、公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py` は変えていない。**新しいファイルは製品のソースに無いので、5.1 の表も変えていない。**

**`IosLibraryCApiTests` が触れるペーストボードは名前付きだけ**（読み込み、監視とも）。general の読み込みと監視は UI テストだけで、シミュレーターの守りの後。`.file` の一時ファイルは `IosLibrary` の一時フォルダーの中で、テストが消す。

### 7.2 TB-3 の 6.6 から持ってきたものの結果

| 項目 | どこで | 結果 |
|---|---|---|
| 本物の `.file` の読み込み（4.5 で TB-4 に送った） | `testLoadingAFileGivesItAwayAndTheFreeLeavesIt`（名前付き）、`testLoadingWhatTheAppWrote`（general） | バイト列が届く。`_free` でファイルもフォルダーも消えない |
| 12.2 の `load_item_async` の許可と拒否 | `testALoadTheUserAllows`、`testALoadTheUserDenies` | 許可は値、拒否は `LOAD_FAILED`（24） |
| 12.2 の `read_data_async`、`detect_values_async` の**許可**（15.2） | `testReadDataTheUserAllows`、`testDetectingValuesTheUserAllows` | 値が届く |
| 取り消した読み込みでダイアログが出ない（12.2） | `testALoadCancelledAtOnceAsksNothing` | `CANCELED`（27）で、ダイアログは 3 秒待っても出ない |
| 読み込みの時間切れ（12.2） | `testALoadNotAnsweredTimesOut`（17 秒待つ 1 件） | `TIMED_OUT`（28）。その後に答えても 2 回目の完了は無い |
| C からの取り消し、`CANCEL_REQUESTED`、`CANCELED` | `ClipboardLoadTests` | 最初の main の回の前（読み込みが始まらず、ファイルも作られない）、別のスレッドから main を止めたまま、開始の後、完了の後、知らない ID、2 回目。**`Registry.accept` に渡す `canceled` は読み込みで実際に呼ばれる**（変異「canceled form gives another value」で確かめた）。ほかの操作は同じ 1 行を通るが、取り消せないので呼ばれない |

**イベントの帳簿と完了の本物の道**（4.5 の「本物の道で通していない」の行）:

| 場面 | 本物の道で | テスト、理由 |
|---|---|---|
| 配っている途中に届くイベント | **通った**。コールバックの中で `UIPasteboard` に直接書くと、書き込みが戻る前に通知が来る（テストの中の観察者で確かめている）。配っている途中に入れ子にならず、2 つの受け手が同じ順で受ける | `testAChangeArrivingDuringADeliveryComesAfterItForEveryone` |
| コールバックの中で自分を解除 | **通った**。`release` は戻った後、次の受け手には届く | `testAListenerRemovingItselfDuringItsCallback` |
| コールバックの間に別のスレッドから解除 | **通った**。解除は待たずに戻る | `testARemovalFromAnotherThreadDuringTheCallback` |
| コールバックの中で登録 | **通った**。今の変更は受けず、次の変更から | `testAListenerAddedDuringACallbackStartsWithTheNextChange` |
| 完了のコールバックの中で別の読み込みと取り消し | **通った** | `testALoadStartedInsideTheCompletionOfAnother` |
| 完了のコールバックの中の取り消し（渡したファイルは消えない） | **通った** | `testACancelInsideTheCallbackLeavesTheFileItWasGiven` |
| 成功が箱を閉じた後、受け口に届く前の取り消し（`.file` を受け口が消す） | **通った**（決まった順で。自分を積み直すブロックで、箱が閉じた次の回に取り消す） | `testACancelAfterTheLoadsSuccessClosedTheBoxDeletesTheFile` |
| **同じ登録の完了の入れ子**（コールバックの中で同じ登録の完了が来る） | **通らない**。main のキューのブロックは入れ子に動かない（コールバックの中で run loop を回しても main のキューは進まない。テストの片付けで 6.5 に書いたのと同じ理由）。ライブラリは同じ要求を 2 回完了しない。`RegistryTests` のテスト専用の操作だけ | `testTheCanceledCallbackMayTurnTheRunLoop` は run loop を回しても `release` が重ならず 1 回であることだけを見る |
| **`RELEASED` の後に届く成功**（「外す」が `onClose` より先に動く順） | **決まった順では通らない**。別のスレッドの取り消しが、箱の鍵を出てから `onClose` を積むまでの間に入る必要がある。`testACancelAgainstTheEndOfALoadLeavesNoFileBehind`（40 回の競合）が踏むかどうかは見ていない。`RegistryTests` だけ | - |
| 保ち（32 件、次の登録に配る） | **Clipboard では通らない**。`holdLimit: 0`。保たないことだけを確かめた（`testAChangeWithNoListenerIsNotHeld`）。通知（TB-8）で通す | - |

### 7.3 コマンドと結果（レビューの直しの前のソース。最後のソースの結果は 7.9）

Xcode 26.6 は `DEVELOPER_DIR`。`xcode-select` は触っていない。コマンドは 6.2 と同じ。04:16〜04:43 に下の順で続けて流し、シミュレーターの仕事は重ねていない。ソースのハッシュ（6.8 と同じ範囲）は流す前と後で同じ（`259f4696a757`）。**流した後に変えたのはこの記録の、この節と 7.8 だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 310/310 |
| 同（iPhone 16 / 18.3） | 310/310 |
| 同 TSan（iPhone 17 Pro / 26.2） | 310/310。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 310/310。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 25/25（`CApiRoundTripUITests` 24、`CApiFreshInstallUITests` 1）。exit 0 |
| `--capi-ui`（iPhone 16 / 18.3。Xcode 26.6） | 25/25。exit 0 |
| framework の Release（`generic/platform=iOS`。組むだけ）`--library --architectures arm64` | `OK symbols`（64 symbols、1 architectures）。capi の警告 0 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（64 symbols、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | exit 0。OK 27、FAIL 0、SKIP 2。`entries` は 64 of 134、70 not implemented yet |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 278 tests、OK |
| `python3 scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

`testACancelAgainstTheEndOfALoadLeavesNoFileBehind` の競合は両方の結果を踏んでいる（40 回のうち取り消しの勝ちと渡しの勝ち）: 17 Pro は 11 と 29、16 は 13 と 27、TSan は 13 と 27、ASan は 12 と 28。

### 7.4 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3。レビューの直しの前のソース。直しの後の 6 個は 7.9）

29 個（読み込みの入口、ID、取り消し、`canceled` の形、`.file` の持ち主、監視、R-8、解除、保ち、ハンドル、帳簿の配っている途中）。1 個あたり 40〜60 秒。**最初の回で 28 個が落ち、1 個が生き残った。** 生き残りをテストを足して流し直して 30 回。

| 生き残り | 原因 | 直し |
|---|---|---|
| `registration.complete(result: owned)` を `result: nil` にする（受け手に渡らなかった `.file` を受け口が消さない） | **本物の道を通るテストが無かった**。40 回の競合は、その回では、受け口が消す順を踏まなかった（箱を取り消しが先に閉じるとライブラリが消す） | `testACancelAfterTheLoadsSuccessClosedTheBoxDeletesTheFile` を足した（自分を積み直すブロックで、箱が閉じた次の回に取り消す。決まった順）。落ちた。変異なしでは通る |

落ちたものの例: `FILE` の型が要らない、`TEXT` が型を読む（読めないポインタで落ちる）、範囲外の `kind`、ID を書かない、取り消せない、`canceled` が別の値、失敗が ID を失う、フォルダーを消さない、別の種類の取り消し、`start` がエラーを失う、イベントが帳簿に届かない、`stop` が何もしない、R-8 の出力が残る、拒んだ登録の `release`、解除が何もしない、変更を保つ、`NULL` の -1（3 つ）、`out_size`、パスが URL、`REMOVED` が `CHANGED` になる、足した型と消した型の入れ替え、名前が無い、渡した印が無い、**配っている途中のイベントをその場で配る**（`testAChangeArrivingDuringADeliveryComesAfterItForEveryone` だけが落とした。本物の道で帳簿を守っている）。

**変異で落ちたプロセスのクラッシュレポート**（`~/Library/Logs/DiagnosticReports/`。記録してから消した。どれも `IosLibraryCApiTestHost`、iPhone 16 のシミュレーター）: `IosLibraryCApiTestHost-2026-11-04-` に続けて `034919.ips`、`035012.ips`、`035054.ips`、`035056.ips`、`040008.ips`、`040057.ips`、`040431.ips`、`040432.ips`、`040439.ips`、`040441.ips`。

この表の変異は、後で直したテストの形（`ClipboardLoadTests` の個数の比べ方を `<=` に）より前のソースで流した。

### 7.5 設計書の読み方（この表は実装の時点のもの。1 と 3 は 7.9 で第 2 部 6.1 に戻した。4 は 7.9 で置き換えた）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 6.1 の `load_item_async`「`FILE` は `ut_type` が必須」 | `NULL` と不正な UTF-8 は入口の `INVALID_PARAMETER`。**空文字は入口を通り、`IosLibrary` が持つ項目に無いので完了の `NO_MATCHING_ITEM`（23）**。`read_data_async` の空文字が `INVALID_TYPE` なのと違う（`loadItem` は型を検査しない。ライブラリのまま） | **戻すことを勧める**（6.1 に 1 文） |
| 2 | 第 1 部 5.7 の値の出力と R-8 | `out_listener` はハンドルなので、すべての道で先に `NULL` を書く。**`out_request_id` は値なので、拒むときは書かない**（第 1 部 5.7 の 2、6 章）。テストは番兵の 77 が残ることを見る。依頼の「出力の初期化」はハンドルの方と読んだ | 不要（第 1 部に書いてある） |
| 3 | `add_change_listener` の `out_listener` の `NULL` | `INVALID_PARAMETER` で `release` を呼ぶ。第 2 部に文が無い。Android の コールバックと出力のどちらかが `NULL` なら拒む形と同じ | **戻すことを勧める** |
| 4 | 6.1 の `changedDetectedOnForeground`「値を置かない」 | **レビューで置き換えた（7.9）**: 前の読み方（`CHANGED` で型は空）はやめ、受け手に届けない | 不要 |
| 5 | C-9 の版の確かめ | `cancel_load` と `listener_remove` は登録を作らないので走らせない（4.6 の 7 と同じ読み方） | 不要 |
| 6 | `start_observing_async` の `ClipboardError` でない失敗 | `UNKNOWN`。ライブラリは今 `pasteboardUnavailable` だけを投げるので起きない | 不要 |
| 7 | 第 1 部 5.3 の「P1-1」と `Registry.requestBox(id:)` | テストのための読み取りを Common に足した。機能の知識は無い。`requestCount` と同じ扱い | 不要 |

### 7.6 実装の途中で分かったこと

- **読み込みの時間切れの後もダイアログは残る**: `testALoadNotAnsweredTimesOut` はダイアログを 17 秒置いても閉じないことを前提に押している（押せなければ落ちる）。ヘッダーの「a later answer delivers nothing」のとおり
- **取り消された読み込みの一時ファイルは、取り消しの完了より後に消えることがある**: 回ごとに数えた最初のテストは、別の UI テストと重ねた回（iPhone 16 / 18.3）で、数が 2 秒より後に戻って落ちた。なぜ 2 秒を超えたかは確かめていない。**テストが示すのは、テストの終わりに 2 秒変わらなくなった時点で、前に無かったパスが残っていないことまで**（7.9）。それより後のことと、テストの外の動作は分からない
- 同じ `copy_async` で変更のイベントは 1 回とは限らない（テストは個数を決めず、2 つの受け手で同じ列であることを見る）
- `NSItemProvider` が取り消しのときに `Code=-1000` のログを出す（OS のログ。値には関係しない）

### 7.7 確かめられていないこと

- **実機では何も流していない**（指定どおり。`generic/platform=iOS` は組むだけ）。iPad、x86_64 のスライスのテスト、iPhone 17 / 26.2 は流していない
- 7.2 の「通らない」2 行。`RELEASED` の後に届く成功を本物の道で踏んだかは分からない
- `IMAGE`、`URL` の読み込みの貼り付けのダイアログ（`TEXT` だけ）。`FILE` の拒否
- 開始と同時の取り消し（ダイアログが出ることは約束しない。5.3）は UI テストに無い
- **ダイアログを出している間の取り消しは TB-10 か DoD に送る**。アプリの行を押せないので今の形では書けない。ヘッダーは `CANCELED` を約束しているが、C からは確かめていない
- **検出の 5 秒に晒されるテストは 2 件になった**（`testDetectingValuesTheUserDenies`、`testDetectingValuesTheUserAllows`）。今までの回では起きていないが、TB-12 の前に見直す
- **`testAChangeArrivingDuringADelivery` の前提（書き込みが戻る前に通知が来る）は、シミュレーターの 2 台で確かめただけで、実機では未確認**。同じ前提の 7.9 の 2 件も同じ
- `UNEXPECTED_TYPE`、`FILE_COPY_FAILED`、`IMAGE_ENCODE_FAILED`、読み込みの `CONTENT_TOO_LARGE` は写しの関数のテストだけ
- 6.6 の Mac のクリップボードとの同期は引き続き測っていない。設定は変えず、Simulator.app も開かず、`pbcopy`、`pbpaste` も使っていない
- 第 1 部 6 章の 8 スレッド × 25 回の同時の呼び出しは流していない（TB-10）

### 7.8 時間

03:35〜04:44（約 69 分）。うち変異が約 27 分（03:48〜04:15。別のシミュレーターで UI テストと重ねた回がある。最後の検証とは重ねていない）、`--capi-ui` は 1 回 9〜10 分。目標の 05:15 の中。

### 7.9 レビューの直し

レビューの指摘（Codex と、メインのセッションが読んで確かめたもの）をメインのセッションから受けて直した。

| 指摘 | 直したこと |
|---|---|
| A（必ず直す） | 第 2 部 6.1 の「積まれた配送も届かない」が破れていた: 配っている途中に届いた E2 が、`stop_observing_async` の完了の後に配られた。**`EventLedger.discardUndelivered()` を Common に足し**（機能の知識なし、`held` は触らない、Notification は呼ばない）、`stopObserving` が完了の前に呼ぶ。**道は本物で通った**: テストの本体は main のキューのブロックの中でないので、`setItems` で E1 が同期に来て、コールバックが書いて E2 が届き、`stop` を呼んで run loop を回すと完了が来る |
| A の広げた所 | **配っている途中の E1 の残りの受け手**も落とす（E1 が A に届いた中で止めると、B には届かない）。「完了の後は何も来ない」を保つため。依頼の文は E2 だけなので、要らなければ戻せる（`guard discards == discardCount`） |
| A の `start` | **`start_observing_async` も同じに落とす**（読み方。「2 回目は前を止める」。ライブラリも世代の印で前の購読の配送を新しい受け手に渡さない。失敗で `UNAVAILABLE` のときも前は止まっているので落とす）。監視は 1 つで、受け手の帳簿も 1 つなので、前の監視のイベントと新しい監視のイベントは区別されない |
| B-Codex | **C ABI が言えないイベントは受け手に届けない**。`ClipboardMapping.change(of:)` が nil を返し、`ClipboardReceiver.receive` がログを出して捨てる。対象は `changedDetectedOnForeground`、知らない種類、知らない scope。帳簿が持つのは `ClipboardChange`（新しい値の型）で、ハンドルは失敗しない。`scopeKind` は optional になった。**`scopeKind` を使うのはイベントだけ**で、ほかの道は無い |
| B1 | `temporaryFileCount` をやめ、パスの集合（リクエストのフォルダーとその中のファイル）にした。始めと終わりで、2 秒変わらなくなるまで待ち（30 秒で落ちる）、`後 - 前` が空であることを見る。`testACancelBeforeTheFirstMainTurn` も同じ形にした。その前のテスト（アルファベット順で `testACancelAgainst...`）は終わりに落ち着くのを待つので、遅れたファイルが次のテストの始めの基準に混ざらない。始めの基準も 2 秒待つ |
| B2 | 第 2 部 6.1 に 1 文ずつ足した: `FILE` の空の `ut_type`、`add_change_listener` の `out_listener` の `NULL`。コードは変えない |
| C1〜C4 | 7.1 の 23、`ClipboardRows.swift` のコメント、`requestBox(id:)` の先頭のログ、`XCTUnwrap`（`first.changes[0]`、`recorder.changes[0]`） |
| C5 | `testACancelOfALoadThatStartedEndsWithCanceled` の else に確かめを足した（`NONE`、`FILE`、ファイルが残る、1 回ずつ）。どちらの枝を通ったかを 1 行出す。**下の数えでは else は 1 度も通っていない** |
| C5 の UI | `testALoadAllowedAfterItTimedOutDeliversNothing` を足した（17 秒待つのでもう 1 件増える。12.2 の「15 秒待つ 1 件だけ」より多い）。時間切れの後の許可でも 2 回目の完了は来ない |

**設計書の直し（B2 の 2 文）は、メインのセッションが、持ち主の「07:20 まで推奨のとおりに進める」という指示の下で採ったもの。持ち主はまだ読んでいない。** A と B-Codex は設計書を変えていない（A は設計書の約束に合わせたコードの直し。`start` の読み方と E1 の残りは、設計書に戻すなら 6.1 の 1 文）。

`ClipboardLoadedItemHandle` の `@unknown default`（`kind` が -1 の `NONE`）は残した。指摘の対象でなく、正しく見える別の値にはならない。呼ぶ側には成功に -1 の種類が見える。

#### 枝の数え

`testACancelOfALoadThatStartedEndsWithCanceled` を `-test-iterations 30` で 1 回（iPhone 17 Pro / 26.2。別のシミュレーターで変異を流している間）: **取り消しの枝が 30 回、else は 0 回**。最後の検証の 4 回（17 Pro、16、TSan、ASan）と直しの直後の 1 回も、すべて取り消しの枝。**合わせて 35 回のうち else は 0 回で、else の確かめは動いたことが無い。**

#### 変異（使い捨ての写し。iPhone 16 / 18.3。テストの最後の形）

6 個。写しを取った後にソースとテストを変えていない（写しと比べて差が無いことを `diff -rq` で確かめた）。**6 個とも落ちた。クラッシュは 0 件**（消したレポートも無い）。

| 変異 | 落としたテスト |
|---|---|
| `stopObserving` が落とさない | `testAStopInsideADeliveryDropsWhatWasQueued` |
| `startObserving` が落とさない | `testASecondStartInsideADeliveryDropsWhatWasQueuedOfTheFirst` |
| 帳簿が待っているものを残す（`removeAll` を消す） | 上の 2 件と `testDiscardingDropsWhatWaitsForTheDeliveryInProgress` など |
| 配っている途中を続ける（`guard` を消す） | `testAStopInsideADeliveryDropsWhatWasQueued`、`testDiscardingEndsTheDeliveryInProgressForThoseAfter` |
| `registration.complete(result: nil)` | `testACancelAfterTheLoadsSuccessClosedTheBoxDeletesTheFile` |
| `ClipboardProviderLoadHandle.finish` の遅れた `discard` を消す（`ios/IosLibrary`。写しの中だけ） | `testACancelAgainstTheEndOfALoadLeavesNoFileBehind` |

#### 最後のソースの結果

05:08〜05:36 に下の順で続けて流し、シミュレーターの仕事は重ねていない。ソースのハッシュ（6.8 と同じ範囲）は流す前と後で同じ（`fabe31b3cf15`）。**流した後に変えたのはこの記録の、この節と枝の数えの 1 文だけ。** 7.4 の 29 個の変異はこの直しの前のソースで、流し直していない。上の 6 個はこのソースと同じ写しで流した。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 318/318 |
| 同（iPhone 16 / 18.3） | 318/318 |
| 同 TSan（iPhone 17 Pro / 26.2） | 318/318。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 318/318。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 26/26（`CApiRoundTripUITests` 25、`CApiFreshInstallUITests` 1）。rc 0 |
| `--capi-ui`（iPhone 16 / 18.3。Xcode 26.6） | 26/26。rc 0 |
| framework の Release（`generic/platform=iOS`。組むだけ）`--library --architectures arm64` | `OK symbols`（64 symbols、1 architectures）。capi の警告 0 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（64 symbols、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 64 of 134 |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 278 tests、OK |
| `python3 scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

40 回の競合の取り消しの勝ちと渡しの勝ち: 17 Pro は 16 と 24、16 は 15 と 25、TSan は 14 と 26、ASan は 16 と 24。

時間: 04:56〜05:37（約 41 分）。

## 8. TB-5

第 2 部 13 章の TB-5（OP-18〜OP-24、結果のハンドル）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。

### 8.1 足したもの

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Dialog/DialogEntry.swift` | 14 関数。各 1 行。**`Dialog.h` がすべて実装された** |
| 受け口 | `Dialog/DialogReceiver.swift` | 6 種の `show`、`cancel`、共通の `show` と `start`（`.foreground` と要求の箱）、`finish` |
| 写し | `Dialog/DialogMapping.swift` | 6 種の要求、`result(of:)`（`DialogResultValue`）、`error(for:)`。`reserved:` は text input と login が `[\.reserved1]`、ほかは `[]`。知らないボタンと入力は nil で、受け口は `UNKNOWN` で完了する |
| ハンドル | `Dialog/DialogHandles.swift` | `DialogResultHandle` と 6 つの読み取り（ほかに `_free`） |
| Common | `Common/CApiLog.swift` | `dialog` の logger（機能の知識なし） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 14 個を外した（**実際に 14 個**。残りは Notification と Share の 56 個）。`entries` は 78 of 134 |
| 行 | `IosLibraryCApiUITestApp/Rows/DialogRows.swift`、`CApiRow.swift` の節の一覧 | 17 行。どの行も `ntk_` を呼ぶ。文字列は `withCString` の中だけで有効なので、題が出ることが入力の写しの確かめにもなる |
| テスト | `IosLibraryCApiTests/DialogMappingTests.swift`（15）、`DialogEntryTests.swift`（18） | 318 → 351 件 |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`（21 件足した。**同じファイルの同じクラスの本体に置いた**。extension は `minimal` の下で列挙されるか確かめていないので使っていない）、`CApiUITestApp.swift`（`CApiSection.dialog` と Dialog の操作） | 25+1 → 46+1 件 |
| 設計書 | 第 2 部 5.1 の表、第 1 部 5.1 の木 | `DialogMapping`、`DialogHandles` の名前だけを足した。ほかは変えていない |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py` は変えていない。ペーストボード、Mac のクリップボード、シミュレーターの設定には触れていない。

**`IosLibraryCApiTests` は Dialog を出さない**（実機の ASan で流れるので）。受け付けた要求は同じ main の回で取り消す。結果の値は `DialogReceiver.finish` を直に呼んで確かめる。出すのは UI テストだけ。

### 8.2 12.1 と 12.2、4.x から持ってきたもの

| 項目 | どこで | 結果 |
|---|---|---|
| 12.1 前面: OP-18〜OP-23 を後ろから呼ぶ | `testEachKindCalledInTheBackgroundIsNotForeground`（6 種、`@background` の行で確かめる） | `NOT_FOREGROUND`（8）。戻っても何も出ない |
| 12.1 取り消し: 最初の main の回より前 | `testACancelBeforeTheFirstMainTurnCompletesEachKindAsCanceled`（6 種）、`testACancelInTheSameTurnShowsNothing` | `CANCELED`（6）。Dialog は出ない（UI テストで 2 秒見た） |
| 12.1 取り消し: 出ている Dialog | `testACancelClosesTheDialogOnTheScreen`（別のスレッドから） | 閉じて `CANCELED` が 1 回 |
| 12.1 取り消し: 上に画面が重なっている | `testACoveredDialogStaysWhenCancelled`（2 つ目の Dialog で覆う） | `CANCELED` が先に来て、覆いは閉じない。覆いを押すと下の Dialog が残っていて、そのボタンは何も報告しない |
| 12.1 知らない ID、完了の後の ID | `testIdsThatAreNotARunningRequestDoNothing`、`testACancelAfterTheAnswerAndOfAnUnknownIdDoNothing` | `NONE` で何もしない |
| 12.1 別の機能の ID | `testTheCancelOfTheOtherFeatureDoesNothing` | 効かない（両方向） |
| 12.2 Dialog を押して値を確かめる | 6 種それぞれの UI テスト | ボタン、ラベル、入力、`_option_index` |
| 6.2 アクションシートの外側のタップ（「測っていない」） | `testAnActionSheetClosedByATapOutside`（iPhone 17 Pro / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3） | **`NEGATIVE` で、ラベルは取り消しの文言**（8.4。iPhone 16 / 18.3 は検証の後に座標を直して 1 件だけ流した） |
| P1-12 同じ回の 2 つ | `testTwoRequestsInOneTurnAreBothShown` | 後の方が上に出て、両方答えられる |
| 完了のコールバックの中で次の Dialog と自分の取り消し（入れ子の本物の道） | `testACompletionMayShowTheNextDialog` | 2 回目の完了は来ず、次の Dialog が出る。呼び出しの中では何も動かない |
| `foregroundInactive`（第 1 部 6 章） | `testAnAlertRequestedUnderControlCenterIsShown`（D22 の形。シミュレーターだけ。ドラッグの座標はサンプルと同じで、信頼するファイルは変えていない） | 3 台で、Control Center の下で Alert が出て、閉じた後に答えられ、行は `@foregroundInactive` |
| E-9、P2-22 | `testATextInputThatIsRequired`、`testALoginThatIsRequired`、`testAZeroFilledAlertHasTheTextOfTheLibrary` | 反転した名前と既定の文言 |

**通っていないもの**:

| 場面 | 理由 |
|---|---|
| 同じ登録の完了の入れ子 | 7.2 と同じ。main のキューのブロックは入れ子に動かない。`RegistryTests` だけ |
| `CANCELED_BY_SYSTEM`（外から閉じる）、`SHOW_FAILED` を C から | 行は `UIKit` を `import` できないので外から閉じられない（`capi-check-sources`）。**写しの関数と `finish` を直に呼ぶテストだけ**。1b の Swift の UI テスト（D20）は別にある |
| 2 回目の取り消しが表示の途中に重なる順 | 決まった順で作れない |

### 8.3 iPad の最初の起動（iPad Pro 11-inch (M4) / 18.3）

**TB-2b のアプリは iPad で起動し、行を押せた。Dialog の UI テストは最初の回（直しの前の形）で 18 件すべて通った。** iPad の行のために変えたものは無い。行の見た目は目で見ていない（押せたことまで）。外側のタップのテスト（B3 の直しの後）の道: **iPhone 17 Pro / 26.2 は `region`、iPhone 16 / 18.3 は `coordinate`、iPad Pro 11-inch (M4) / 18.3 は `region`**。`region` は `Dismiss` が押せないことを、`coordinate` は点がシートのどのボタンの上にも無いことを確かめてから押す。Clipboard の貼り付けのテストは iPad で落ちた（8.7。日本語のシミュレーターのため）。

### 8.4 コマンドと結果（最後のソース）

06:07〜06:57 に指定の順で続けて流し、シミュレーターの仕事は重ねていない。ソースのハッシュ（6.8 と同じ範囲）は流す前と後で同じ（`8947007174e5`）。**iPhone 16 の `--capi-ui` が 1 件落ちた。その後でテストの 1 行を直した**（下）。

| 実行 | 結果 | ソース |
|---|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 351/351 | `8947007174e5` |
| 同（iPhone 16 / 18.3） | 351/351 | 同 |
| 同 TSan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 | 同 |
| 同 ASan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 | 同 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 45/45。rc 0 | 同 |
| `--capi-ui`（iPhone 16 / 18.3。Xcode 26.6） | **44/45。rc 1**。`testAnActionSheetClosedByATapOutside` が落ちた（`no line 0 of dialog.actionSheet after 10.0 s`） | 同 |
| `--capi-ui`（iPad Pro 11-inch (M4) / 18.3。Xcode 26.6） | 45/45。rc 0（Clipboard の貼り付けも） | 同 |
| framework の Release（`generic/platform=iOS`。組むだけ）`--library --architectures arm64` | `OK symbols`（78 symbols、1 architectures）。capi の警告 0 | 同 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（78 symbols、2 architectures）。capi の警告 0 | 同 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 78 of 134、56 not implemented yet | 同 |
| `python3 -m unittest discover -s scripts/tests -p 'test_check_c_abi_contract_ios.py'` | Ran 278 tests、OK | 同 |
| `python3 scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK | 同 |

**検証の後の直し（最後のソース。`84a7b339c1c6`）**: `CApiUITestApp.tapOutsideTheSheet` の座標を画面の高さの 0.05 から 0.2 に変えた（UI テストの 1 行だけ。製品のソース、ほかのテストは同じ）。**変更の後に流したのは次だけで、全件は流していない**（検証を 07:05 までに終える指定のため）。

| 実行（`xcodebuild test -only-testing:.../testAnActionSheetClosedByATapOutside`。`--capi-ui` でない） | 結果 |
|---|---|
| iPhone 16 / 18.3 | 1/1 |
| iPhone 17 Pro / 26.2 | 1/1 |
| iPad Pro 11-inch (M4) / 18.3 | 1/1 |
| `test_ios_ui_runner.py` の `CApiUiTestSources` | OK |

**これで 6.2 の「外側のタップは `NEGATIVE`」は 3 台で測れた。** iPhone 16 / 18.3 で 0.05 のときに閉じなかった理由（状態バーに当たった見込み）は確かめていない。

時間: 05:41〜07:00（約 79 分）。

### 8.5 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

20 個。最初に 18 個を流し（テストはレビューの直しの前の写し）、17 個が落ち、1 個が生き残った。**生き残りと残りの 2 個（`_option_index` の `NULL` が 0、U+0000）は、レビューの直しの後のソース `1ae9b84b3440` で流して 3 個とも落ちた（8.9）。**

| 生き残り | 原因 | 直し |
|---|---|---|
| `finish` の失敗の完了が ID を失う（`callback(userData, 0, error, ...)`） | テストが ID を見ていなかった | `completion(of:)` が `registration.id` と比べる形にした。直した後に流して落ちた（8.9） |

落ちたものの例: text input と login の `reserved1` の名指し、反転、既定の文言、`title` の `NULL`、`option` の 0、ボタンの取り違え、パスワード、`NOT_FOREGROUND` の写し、`release` を呼ばない 2 通り、ID を書かない、取り消せない、`canceled` の値、別の機能の取り消し、`_button` の `NULL`。**クラッシュは 0 件で、消したレポートは無い。**

### 8.6 設計書の読み方（5.1 の名前のほか、設計書は変えていない）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 6.2 の「アクションシートの外側のタップ…`NEGATIVE` になる見込み（測っていない）」 | 3 台で測って `NEGATIVE`。ラベルは取り消しの文言 | **戻すことを勧める**（「見込み」を「確かめた」に） |
| 2 | 11.1 の `INVALID_PARAMETER`「`DialogError.invalidRequest`」 | C は箱を使い回さないので届かないが、写しは表のとおり 1 にした | 不要 |
| 3 | 11.1 の `UNKNOWN`「届かない」 | 知らないボタン、知らない入力、知らない `DialogError` は `UNKNOWN` で完了する（依頼の「正しく見える値にしない」）。テストから踏めない | 不要 |
| 4 | `button_text` などの空文字 | 空のまま渡す。既定の文言に替えない（E-15） | 不要 |
| 5 | 第 1 部 5.7 の値の出力 | `out_request_id` は拒むときに書かない（7.5 の 2 と同じ） | 不要 |
| 6 | 12.2 の「Dialog と権限」 | 権限のダイアログは TB-7 と読み、ここでは Dialog だけ | **戻すことを勧める**（13 章に持ち主が無い。8.9 の提案 2） |

### 8.7 実装の途中で分かったこと

- **パスワードを入れたログインの後に行を押せなかった原因は、システムの「Save Password?」のシート**（レビューの B1。使い捨ての写しの試しのテストで調べた）。iPhone 17 Pro / 26.2 で、ログインの答えから約 0.5〜1 秒後に app の階層に `Sheet`（320×272、画面の中央）が出る。`isHittable` は 15 秒待っても偽のまま。**座標で行を押しても行は動かなかったので、XCTest の判定の誤りではなく、シートが本当に触れなくしている**。パスワード無しのテキスト入力の後は同じ位置の行が押せるので、行の位置やキーボードの領域のせいではない。入力せずに閉じたログインの後も押せる。iPhone 16 / 18.3 と iPad Pro 11-inch (M4) / 18.3 ではシートは出なかった。「Not Now」を押すと低い行がまた押せる（`testALowRowAfterALogin`。3 台で通った）。**これは `IosLibrary` や受け口の欠陥ではなく OS の振る舞いと読んだ**（`ios/IosLibrary` は変えていない）。ただし iOS 26.2 の利用者には、C のログインの Dialog の後にこのシートが出て、答えるまで下の画面に触れない。シートが出ている間に次の Dialog を要求したときにどうなるかは確かめていない。マニュアルの候補
- **この Mac の iPad Pro 11-inch (M4) / 18.3 のシミュレーターは日本語**だった。Clipboard の貼り付けのテスト（TB-3、TB-4）が iPad で落ちて分かった（アラートの文が日本語で、英語のボタンを探して見つからない。短い探りで `Alert` の行を読んだ）。設定は変えず、`answerPaste` が両方の文言を受ける形にした（文言はサンプルの `SystemLabels` と同じ）。Dialog の文言はテストの文字列か `OK` なので影響を受けなかった
- `@unknown default` の枝はテストから踏めない

### 8.8 確かめられていないこと

- **実機では何も流していない**（`generic/platform=iOS` は組むだけ）
- 8.2 の「通っていないもの」の表
- 入力の秘密がログに出ないことは、読むだけで確かめた（`DialogMapping`、`DialogReceiver`、`DialogHandles` の補間に入力が無い）。番兵の値で読み返すテストは無い
- 複数のウィンドウの iPad（6.2。マニュアルの候補）
- `dismissedBySystem` の後に来るはずの 1 回のちょうどさ（C から踏めない）

### 8.9 レビューの直しと、止めた所

レビュー（Codex は指摘なし。Claude は A なし）をメインのセッションから受けた。**持ち主の指示で 07:50 が上限になり、全件の検証は流していない。**

| 指摘 | 状態 |
|---|---|
| B1 | 済み。8.7。テストのコメントを直し、`testALowRowAfterALogin` を足した。試しのテストと結果の束は写しごと消した。スクリーンショットは書き出していない |
| B2 | 済み。`testAnAlertRequestedUnderControlCenterIsShown` が 3 台で通った |
| B3 | 済み。8.3 に道を記録した |
| C1〜C8 | 済み。C5 は `noDialogAppears`（`alerts`、`sheets`、ポップオーバーの `Alpha`）で、`testAnActionSheetOption` が 3 台で偽を返すこと（シートを見ること）を確かめた。C7 は「取り消しは何もしない」が誤りだった: 完了の中の取り消しは状態を進めて `release` を「外す」に回す。外から見えるのは 2 回目の完了が来ないことまで |
| C10 | 済み。直した変異（失敗が ID を失う）と、流していなかった 2 個（`_option_index` の `NULL` が 0、U+0000）を、ハッシュ `1ae9b84b3440` の写しで流した。**3 個とも落ちた**。8.5 のほかの 17 個は、製品のソースは同じで、テストはこの直しの前の形のまま流し直していない |

**どのソースで何を流したか（ハッシュ `1ae9b84b3440`。製品のソース、テストともこの直しの最後の形）**:

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 351/351 |
| 同（iPhone 16 / 18.3） | 351/351 |
| 同 TSan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 |
| UI テストの一部（`xcodebuild -only-testing`。`--capi-ui` でない）: `testAnAlertRequestedUnderControlCenterIsShown`、`testALowRowAfterALogin`、`testAnActionSheetClosedByATapOutside`、`testAnActionSheetOption`、`testACancelAfterTheAnswerAndOfAnUnknownIdDoNothing` | 3 台とも 5/5 |
| 同（iPhone 17 Pro だけ）: `testEachKindCalledInTheBackgroundIsNotForeground`、`testACancelInTheSameTurnShowsNothing`、`testAReadTheUserAllows`、`testAReadTheUserDenies` | 4/4 |
| framework の Release（2 つ）`--library` | `OK symbols`（78 symbols。1 architectures、2 architectures） |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

順序は依頼の全件の検証の順でなく、変更に関係するものを先に流した。流した後に変えたのはこの記録だけ。

**流していないもの**: `--capi-ui` の全件（3 台とも。1 台 12 分以上で 07:40 までに終わらないので始めなかった）。この直しの前の全件は 8.4（`8947007174e5`）とメインのセッションの 07:16 の回（iPhone 16 の 45/45）。

**続きの一覧（順に）**:

1. `--capi-ui` を iPhone 17 Pro、iPhone 16、iPad の順に、`1ae9b84b3440` で流す（47 件。1 台 12〜13 分）
2. 8.2 の表の残り: `CANCELED_BY_SYSTEM`、`SHOW_FAILED` を C から起こせないこと。シートが出ている間の次の Dialog（8.7）
3. 持ち主に見てもらう提案（設計書はこの回で変えていない）:
   - **提案 1、第 2 部 6.2**: 「アクションシートの外側のタップはキャンセルの handler が呼ばれて `NEGATIVE` になる見込み（測っていない。2b の 12.2 で確かめる）」を、「アクションシートの外側のタップはキャンセルの handler が呼ばれて `NEGATIVE` になる（iPhone 17 Pro / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3 で確かめた）」に直す
   - **提案 2、第 2 部 13 章の TB-7 の行**: 完了の条件に「12.2 の『Dialog と権限』の行のうち、権限のダイアログを C から押して完了の値を確かめること」を足す
   - **提案 3、`foregroundInactive` の持ち主**: TB-5 で通したので、第 2 部 13 章の TB-5 の行に「第 1 部 6 章の `foregroundInactive` を Dialog で確かめる」を足す。ほかの前面の操作（OP-35、OP-38、OP-46）の持ち主は決まっていない
   - **提案 4、第 2 部 6.1 の読み方**（7.5 の 1 と 3 は B2 で第 2 部に入っている。持ち主はまだ読んでいない）
4. TB-5 の承認とコミットは持ち主の判断（メインのセッションが受ける）
5. `testAnAlertRequestedUnderControlCenterIsShown` と `testALowRowAfterALogin` は `scripts/ios_ui_runner.py` の表を変えずに同じクラスに足した。TB-5 以降でクラスを分けるかは未決

### 8.10 持ち主の決定（2026-11-06）と、シートの直し

**持ち主の決定（2026-11-06。メインのセッションが作業ツリーに入れた）**:

- 8.9 の提案 1〜3 を採った: 第 2 部 6.2（外側のタップは `NEGATIVE`。3 台で確かめた）、13 章の TB-5 の行（第 1 部 6 章の `foregroundInactive` を Dialog で確かめる）、13 章の TB-7 の行（12.2 の「Dialog と権限」の権限のダイアログ）
- TB-3、TB-4 の変更（7.5 の 1 と 3 が第 2 部 6.1 に入ったものを含む）を、そのまま受けた
- `agent-rules/device-testing.md` に決まりを足した: UI テストを流す間は Simulator.app を開かない、Mac のクリップボードに触れない（`pbcopy`、`pbpaste`）、`PasteboardAutomaticSync` を変えない
- 期限まで待たずに進め、判断は推奨のとおり。実機は 2026-11-07 の 09:00 までは使わない

**メインのセッションの 21:51〜22:39 の `--capi-ui`**（ソースのハッシュ `08efd0e8de47`。`git status --short -- ios scripts` のファイルで数えたもの）: iPhone 16 / 18.3 は 47/47、iPad Pro 11-inch (M4) / 18.3 は 47/47、**iPhone 17 Pro / 26.2 は 46/47**。`testALowRowAfterALogin` が `CApiUITestApp.swift:232` の「the sheet after the login did not go away」で落ちた。「Not Now」を押した後、シートが 10 秒経っても消えなかった。

**調べたこと**:

- 落ちた回のログ: シートを見つけてから 0.25 秒後に「Not Now」を押していた。押した後、シートは 10 秒間ずっと在った
- `-test-iterations 10` で直す前の形を流した（iPhone 17 Pro / 26.2）: **10 回中 1 回失敗**。失敗した回は最初の回で、待ち始めてシートが在ると分かるまで約 2 秒（通った 9 回は約 1 秒）、押したのはその 0.7 秒後だった（通った 9 回は 0.12〜0.14 秒後）。**押すのが早すぎたという仮説は、この回では支持されない**
- 同じシートが残ったのか、別のシートか、戻ってきたのかは、階層を書き出せず（結果の束からの書き出しが空だった）**確かめられていない**
- 待ちの長さは理由でない（10 秒）

**直したこと**（`CApiUITestApp.declineTheOfferToSaveThePassword`。テストの補助だけ）: 押す前に、ボタンが押せて、シートが 0.3 秒動かないのを待つ。シートは最初のものの題で絞った問い合わせで追う（別のシートが代わりに数えられない）。消えなければ前と同じく落ちる。低い行を押す確かめもそのまま。**直した後に `-test-iterations 20` で流して 20 回中 0 回の失敗**（シートは 20 回とも出た）。失敗の率が 1/10 なので、20 回の 0 で直ったとは言い切れない。原因が確かめられていないので、**同じ失敗がまた出たら、階層を書き出して原因を見る**

**最後のソースの結果**:

22:53〜23:48 に指定の順で続けて流し、シミュレーターの仕事は重ねていない。ソースのハッシュは流す前と後で同じ: `8aed493f82e5`（メインのセッションと同じ数え方。`git status --short -- ios scripts` のファイル）、`cc2f9cd6b1a1`（6.8 と同じ範囲）。**流した後に変えたのはこの記録だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 351/351 |
| 同（iPhone 16 / 18.3） | 351/351 |
| 同 TSan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 351/351。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 47/47。rc 0 |
| `--capi-ui`（iPhone 16 / 18.3） | 47/47。rc 0 |
| `--capi-ui`（iPad Pro 11-inch (M4) / 18.3） | 47/47。rc 0 |
| framework の Release（2 つ）`--library` | `OK symbols`（78 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 78 of 134 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

変異はこの回では流していない（直したのはテストの補助だけ。8.5 と 8.9 の変異は製品のソースが同じ）。

**8.9 の続きの一覧の状態**:

1. `--capi-ui` の 3 台: **済み**（メインのセッションの 21:51 の回と、上の回）
2. 8.2 の表の残り（`CANCELED_BY_SYSTEM`、`SHOW_FAILED` を C から、シートが出ている間の次の Dialog）: **済んでいない**
3. 提案 1〜3: **持ち主が採った**。提案 4（第 2 部 6.1 の読み方）: **TB-3、TB-4 の変更として受けた**
4. TB-5 のコミット: メインのセッション
5. UI テストのクラスを分けるか: **未決**
## 9. TB-6

第 2 部 13 章の TB-6（通知のビルダーと userInfo の JSON、trigger、category）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。

### 9.1 足したもの

**TB-6 の C の関数は 14 個**（8.2 の「内容のビルダー」の行と `Notification.h`: `_create`、`_free`、`_set_*` が 11、`_add_attachment`）。trigger と category は構造体で、それを受ける関数（`show_async`、`update_async`、`schedule_async`、`register_category_async`）は TB-7 の OP-26〜OP-41 にある。**TB-6 では trigger と category の写しの関数だけを作り、C の関数は足していない。**

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Notification/NotificationEntry.swift` | 14 関数を足した。各 1 行 |
| ビルダー | `Notification/NotificationContentBuilder.swift` | `NotificationContentValue`（`Sendable` な写し。`makeContent()` が main で `NotificationContent` を作る。5.2）、`NotificationContentBuilder`（ハンドルの中身）、`NotificationContentBuilders`（`create` と setter。拒んだ setter はビルダーを変えない。`snapshot` は TB-7 の操作が取る写し） |
| JSON | `Notification/NotificationJson.swift` | 入力（`userInfo(_:)`）、`NotificationContent` への写し（`propertyList(of:)`）、出力（`text(of:)`。TB-8 の `_user_info_json` が使う） |
| 写し | `Notification/NotificationMapping.swift`（新規） | `trigger`（3 種）、`category`（アクションとテキスト入力のアクションの配列） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 14 個を外した。`entries` は 92 of 134（残り 42） |
| テスト | `IosLibraryCApiTests/NotificationBuilderTests.swift`（15）、`NotificationJsonTests.swift`（14）、`NotificationMappingTests.swift`（13） | 351 → 393 件。`@testable import IosLibrary` でライブラリの予約のキー、`isPropertyList`、`NotificationContent` の既定値と比べる |
| 設計書 | 第 2 部 5.1 の表、第 1 部 5.1 の木 | `NotificationMapping.swift`（新規）の行と、第 1 部の木に Notification の 3 つのファイル名を足した |

行と UI テストは足していない（TB-6 の完了の条件は 12.1 のビルダー・userInfo・trigger の行で、どれも UNUserNotificationCenter に触れずに確かめられる）。公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py` は変えていない。

**`IosLibraryCApiTests` は通知を出さず、権限も求めない**（実機の ASan で流れるため）。中身は `NotificationContentValue` と `makeContent()` で比べる。ログには、題・副題・本文・userInfo の値を出さない（有無、長さ、キーの数だけ）。`id` は識別子として `.public`（`ios.md` の表）。

### 9.2 12.1 の行

| 行 | どこで | 結果 |
|---|---|---|
| ビルダー: 既定値 | `testANewBuilderHasTheDefaultsOfTheLibrary` | ライブラリの `NotificationContent(id:title:)` と同じ（`sound` は `.default`） |
| ビルダー: `NULL` の setter、範囲外の値、空の `id`、`file://` でない添付 | `NotificationBuilderTests` | `NULL` は既定に戻す。拒んだ値はビルダーを変えない。R-8: `create` が拒むと出力は `NULL` |
| ビルダー: 渡した後に変更・解放しても内容が変わらない | `testTheCopyDoesNotChangeWithTheBuilder` | 写しを取った後に変えて解放しても、写しから作った `NotificationContent` は元のまま |
| userInfo: オブジェクトでない、不正な JSON、`1e400`、入れ子の `null`、最上位の予約のキー | `NotificationJsonTests`、`testTheUserInfo` | setter の戻り値で `INVALID_PARAMETER`。入れ子の同じキーは通る |
| userInfo: 予約のキーの写しがライブラリと同じ | `testTheReservedKeyIsTheLibrarys` | `NotificationMarker.key` と同じ |
| userInfo: 出力の変換表の全行（`date`、`data`、有限でない `double`） | `testEveryKindOfValueOut`、`testWhatIsNotFiniteIsNull` | 決まった形の文字列。落ちない |
| trigger: `isValid` の各分岐、範囲外の `interval`、`repeats` で 60 未満、`calendar_fields` の 0 と知らないビット、緯度・経度・半径 | `NotificationMappingTests` | 写しの関数で `INVALID_PARAMETER`。**C の関数を通した確かめ（12.1 の「C のテスト」）は TB-7**（受ける関数がそこにある） |
| 0 で埋めた構造体 | `testAZeroFilledTriggerIsRejected`、`testAZeroFilledCategoryNeedsOnlyItsIdentifier` | trigger は `interval` が 0 で拒まれる。category は識別子だけが要る |

### 9.3 コマンドと結果（最後のソース）

00:26〜00:50 に下の順で続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で Simulator.app が開いていないことを、流す前と途中で確かめた（ずっと閉じていた）。ソースのハッシュは流す前と後で同じ: `1ed2e22c9357`（メインのセッションと同じ数え方。`git status --short -- ios scripts` のファイル）、`e462334fbe0b`（6.8 と同じ範囲）。**流した後に変えたのはこの記録だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 393/393 |
| 同（iPhone 16 / 18.3） | 393/393 |
| 同 TSan（iPhone 17 Pro / 26.2） | 393/393。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 393/393。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6。行と UI テストは足していないので、ほかを壊していないことの確かめとして 1 回） | 47/47。rc 0 |
| framework の Release（2 つ）`--library` | `OK symbols`（92 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 92 of 134、42 not implemented yet |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |

`--capi-ui` の iPhone 16 と iPad は流していない（依頼のとおり）。

### 9.4 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

30 個。写しは最後のソースと同じ（流した後に `diff -rq` で差なしを確かめた）。最後の検証の前に流した（依頼の順では 4 番目だが、変異でテストを直すことになれば最後の検証をやり直すことになるため先にした）。**30 個とも落ちた。クラッシュは 0 件**（消したレポートも無い）。

| 区分 | 変異 |
|---|---|
| ビルダー（11） | 空の `id`、R-8 の出力が残る、`title` の `NULL`、`badge` の -1 が -1 のまま、`badge` の -2、空の音の名前、`NONE` が既定の音、`TIME_SENSITIVE` が `ACTIVE`、関連度の上限 2、`NULL` の userInfo で戻らない、`file://` でない添付 |
| JSON（8） | `null` を受ける、予約のキーを受ける、有限でない数を受ける、真偽が数になる、`UInt64` が `Int64` になる、出力の有限でない数が 0、日付の小数秒が無い、データが Base64 でない |
| trigger と category（11） | 無限大の間隔、`isValid` を見ない、`calendar_fields` の 0、知らない暦のビット、緯度 ±91、半径 0、両方知らせない組、trigger の `reserved1` の名指し、知らない category のビット、アクションの `reserved1` の名指し、時の項目を読まない |

### 9.5 設計書の読み方（5.1 の名前のほか、設計書は変えていない）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 13 章の TB-6「通知のビルダーと userInfo の JSON、trigger、category」 | C の関数はビルダーの 14 個。trigger と category は写しの関数だけで、それを受ける関数は TB-7 | **戻すことを勧める**（TB-6 の行に「trigger と category は写しの関数まで。C を通すのは TB-7」） |
| 2 | 12.1 の trigger の行の「C のテスト」 | TB-7 で `show_async`、`schedule_async` を通して行う | 1 と同じ文で足りる |
| 3 | 6.3 の `_create(id, title, &out)` の「必須の 2 つ」 | `id` は `NULL` と空文字を拒む（設計書のとおり）。`title` は `NULL` だけを拒み、空文字は通す | 不要 |
| 4 | `_set_sound` の `NAMED`「`name` が必須」 | `NULL` と空文字を拒む（Clipboard の名前と同じ「必須」の読み方） | 不要 |
| 5 | `_add_attachment` の `identifier` と URL | `identifier` は `NULL` だけを拒み、空文字は通す（ライブラリが受ける）。URL は 9.9 の D3 で決めた形。**前の版の「空白を含む URL は読めないので `INVALID_PARAMETER`」は誤り**: この SDK の `URL(string:)` は空白を符号化して読むので受ける（9.9 の D4。テストで固定） | 不要 |
| 6 | 6.3 の category の「`NULL` と空文字の識別子」 | category、アクション、テキスト入力のアクションの識別子のすべてに当てた | **戻すことを勧める**（どれの識別子かを明記） |
| 7 | userInfo の「不正な JSON」 | `JSONSerialization` の判定のまま。**末尾のカンマ（`{"a":1,}`）は受ける**（測った。テストで固定）。入れ子の深さと大きさの上限は置いていない（深さは 9.9 で macOS で測った） | 9.9 の D2 で第 2 部 6.3 に入った |
| 8 | userInfo の数 | 真偽は真偽、整数は `Int64`、`Int64` を超える正の整数は `UInt64`、どちらにも入らない整数（`JSONSerialization` が `NSDecimalNumber` で返すもの）と小数は有限な `double`。`1.0` は `double` になる（測った）。**前の版は `NSDecimalNumber` が `Int64` の端に丸められる場合があった**（9.9 の C-2） | 不要 |
| 9 | 知らない `NotificationUserInfoValue`、`NotificationSound` の case | 入力からは作られない。出力の JSON では `null`。`NotificationContent` への写しでは `NSNull`（ライブラリが `invalidUserInfo` で拒む） | 不要 |
| 10 | trigger の `CALENDAR` の各項目の範囲 | 見ない（`DateComponents` が受ける）。読むのはビットの立った項目だけ | 不要 |
| 11 | `CRITICAL` の割り込みの段階と `DEFAULT_CRITICAL` の音 | 入口では受ける。entitlement が要ることは確かめていない | 不要 |
| 12 | 11.2 のエラーの写し | 操作の完了で使うので TB-7 | 不要 |

### 9.6 実装の途中で分かったこと

- 自分のテストの補助の誤り（`struct_size` を書く前に `struct_size -= 8` をして桁あふれ）で、テストのホストが 2 回落ちた。テストを直した。クラッシュレポートは名前を記録してから消した（`IosLibraryCApiTestHost-2026-11-06-235843.ips`、`-235845.ips`。変異のものではない）
- `JSONSerialization` は末尾のカンマを受ける（9.5 の 7）

### 9.7 確かめられていないこと

- **実機では何も流していない**（`generic/platform=iOS` は組むだけ）
- trigger と category を C の関数を通して渡すこと（TB-7）。位置の trigger の権限と Info.plist
- userInfo の大きさと入れ子の深さの限り
- 写しを `NotificationContent` にした後、ライブラリが本当に要求を足せるか（権限のある UI テストの側。TB-7）
- 添付のファイルが無いときの `ATTACHMENT_LOAD_FAILED`、2 回目の操作での失敗（M4。TB-7）

### 9.8 時間

23:53〜00:51（約 58 分）。うち変異が約 25 分（00:01〜00:26）、`--capi-ui` が約 15 分。目標の 02:30 の中。

### 9.9 レビューの直し

レビュー（Codex は指摘なし。Claude は A なし、B 3、C 7）をメインのセッションから受けた。**D1〜D4 は、メインのセッションが持ち主の「推奨のとおりに進める」という指示の下で決めたもの。持ち主はまだ読んでいない。**

| 指摘 | 直したこと |
|---|---|
| D1（B-1） | 第 2 部 13 章の TB-6 の行に「trigger と category は写しの関数まで確かめた。C の関数を通す確かめは TB-7」、TB-7 の行に「12.1 の trigger の行の C のテスト（`INVALID_PARAMETER` でプロセスが落ちない）と、AP-19 の範囲外の trigger、category の C のテストが通る」を足した |
| D2（B-2） | 末尾のカンマは受ける。第 2 部 6.3 の userInfo に「入力は OS の JSON の解析器で読み、それが受けるものは受ける」と、測った例（末尾のカンマ、入れ子の深さ）を書いた。カンマを固定するテストは残し、Foundation の変化に気づくためのものとコメントに書いた |
| D3（C-1） | 添付の URL は、`file://` で始まる絶対の URL で、ホストが無いか `localhost` のものだけを受ける。`file:abc`、`file:/tmp/a.png`、相対のパス、`file://host/…`、`file://` は入口で `INVALID_PARAMETER`。**スキームの大文字は受ける**（RFC 3986 の 3.1: スキームは大文字と小文字を区別しない。`FILE:///tmp/a.png` を `URL` は `isFileURL` として読む）。それぞれをテストした（`testTheAttachmentURL`） |
| D4（B-3） | 9.5 の 5 を直した。空白は `URL(string:)` が符号化して受ける（`testASpaceInTheAttachmentURLIsEncoded`。Foundation の変化に気づくため） |
| C-2 | `Int64` にも `UInt64` にも入らない整数は `double` にした（前は `Int64(exactly:)` で `Int64.min` に丸められた）。`-9223372036854775809` は `double`、`9223372036854775808` は `UInt64` に入るので `unsignedInteger`（6.3 の表のとおり）、`18446744073709551616` は `double` |
| C-3 | `1.0` は `.double(1.0)` と比べる形にした |
| C-4 | `testTheCategoryRejects` は値として `INVALID_PARAMETER` を比べる |
| C-5 | 安いものを足した: テキスト入力のアクションの `NULL` の題、要素の大きさが混ざった配列（アクションとテキスト入力のアクション。P2-5）、5 つの不正な UTF-8 の列を `create` の 2 つ、添付の 2 つ、音の名前、userInfo で（`testEveryStringOfTheBuilderMustBeUTF8`）。**C の関数を通して trigger と category を渡すものは TB-7** |
| C-6 | 入れ子の深さの測り（下） |
| C-7 | 先頭のログを足した: `NotificationContentBuilder.init`、`update`、`builder`、`set`、`attachmentURL`、`NotificationJson.value` の 2 つ、`anyValue`、`jsonValue`、`NotificationMapping.dateComponents`、`requiredIdentifier`。値は出さない（`id` は識別子、題は長さ、ほかは有無か型の名前） |

**入れ子の深さの測り（macOS だけ）**: macOS 26.3 の `xcrun swift`（Xcode 26.6）で、`{"a":[[...]]}` の形を `JSONSerialization.jsonObject` に渡した。**最上位のオブジェクトを含めて 513 段まで受け、514 段で拒んだ**（512 段の配列までは受ける）。iOS のシミュレーターと実機では測っていない。同じ回で URL と数の読み方も測った（上の表の値はそれと、シミュレーターの上のテストによる）。

**変異（新しい検査だけ。6 個。使い捨ての写しは最後のソースと同じ。流した後に `diff -rq` で差なしを確かめた。iPhone 16 / 18.3）**: **6 個とも落ちた。クラッシュは 0 件。**

| 変異 | 落としたテスト |
|---|---|
| ホストを受ける | `testTheAttachmentURL` |
| スキームを大文字と小文字で区別する | `testTheAttachmentURL` |
| `file://` で始まらなくてもよい | `testTheAttachmentURL` |
| 相対や空のパスを受ける | `testTheAttachmentURL` |
| `localhost` を拒む | `testTheAttachmentURL` |
| 大きな整数を `Int64` に丸める（前の形） | `testAnIntegerOutsideTheIntegerTypesIsADouble` |

**最後のソースの結果**（01:06〜01:31。順に続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で流す前と途中に Simulator.app が閉じていることを確かめた）。ソースのハッシュは流す前と後で同じ: `73959bf15ca6`（メインのセッションと同じ数え方）、`a90d15f13cd7`（6.8 と同じ範囲）。**流した後に変えたのはこの記録だけ。** 上の 6 個の変異はこの検証の前に、同じソースの写しで流した。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 397/397 |
| 同（iPhone 16 / 18.3） | 397/397 |
| 同 TSan（iPhone 17 Pro / 26.2） | 397/397。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 397/397。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 47/47。rc 0 |
| framework の Release（2 つ）`--library` | `OK symbols`（92 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 92 of 134 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

テストは 393 → 397 件（`NotificationBuilderTests` 18、`NotificationJsonTests` 15、`NotificationMappingTests` 13）。時間: 00:57〜01:31（約 34 分）。

## 10. TB-7

第 2 部 13 章の TB-7（通知の操作 OP-26〜OP-41 と、権限の事前の確かめ）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。持ち主の不在の間に行った。持ち主の指示は「これから私が話しかけるまでは自動で作業を進める。判断が必要な場合、推奨案で、進める。明日朝9時までには実機は使わないでいい？」。

**10.1〜10.8 は直す前の記録。今の形は 10.9。**

### 10.1 足したもの

**TB-7 の C の関数は 24 個**: 操作が 16（OP-26〜OP-41: `show_async`、`update_async`、`schedule_async`、`remove_async`、`remove_all_async`、`cancel_scheduled_async`、`cancel_all_scheduled_async`、`get_scheduled_async`、`get_delivered_async`、`request_permission_async`、`get_authorization_status_async`、`has_permission_async`、`open_settings_async`、`set_badge_count_async`、`register_category_async`、`remove_category_async`）と、OP-33・OP-34 の完了のハンドル `ntk_notification_list` の読み取りが 8（`_count`、`_identifier_at`、`_title_at`、`_subtitle_at`、`_body_at`、`_category_at`、`_date_millis_at`、`_free`）。

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Notification/NotificationEntry.swift` | 24 関数を足した。各 1 行 |
| 受け口 | `Notification/NotificationReceiver.swift` | 16 の操作。`accept`（`NULL` の callback と入口の検査を拒み、`release` を呼び出しスレッドで）、`add`（P2-10 の事前の確かめと `async throws` の呼び出し。main の `Task`）、`finishDone`・`finishList`・`finishPermission`・`finishSettings`。`show`・`update`・`schedule` の 3 つの呼び出しと状態の読み取りは `Adding`（`@MainActor static var adding`）を通す: テストが差し替える口（12.1「`update_async` が `update` を呼ばないことは、受け口の中の口を差し替えて確かめる」） |
| 写し | `Notification/NotificationMapping.swift` | `scheduledTrigger`（`NULL` を拒む）、`requiredIdentifier` を内部に開いた、`permissionOptions`（P2-27）、`allowsAdding`（P2-10）、`status(of:)`、`error(for:)`（11.2）、`millis(of:)`、一覧の写し |
| ハンドル | `Notification/NotificationHandles.swift`（新規） | `NotificationListEntry`（`Sendable`）、`NotificationListHandle`、8 つの読み取り |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 24 個を外した。`entries` は 116 of 134（残り 18: TB-8 の通知のイベントと起動の 14、Share の 4） |
| テスト | `IosLibraryCApiTests/NotificationOperationTests.swift`（新規。27） | 397 → 424 件 |
| UI テスト | `IosLibraryCApiUITestApp/Rows/NotificationRows.swift`、`IosLibraryCApiUITests/CApiRoundTripUITests.swift` | 行 19 個と、テスト 2 件（`CApiRoundTripUITests` の中。`CApiSection.notification` は前からある） |
| 設計書 | 第 2 部 5.1 の表、第 1 部 5.1 の木 | `NotificationHandles.swift`（新規）の行だけ |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py`、README、メモリは変えていない。

**TB-7 のテストは、通知の追加・削除・一覧・バッジ・権限・設定に触れない**（実機の ASan で流れるため。TB-1 からある `NotificationInstallTests` は delegate を読み書きする。10.9 で直した書き方）。呼ぶのは、入口で拒まれるもの（登録の前に戻る）と、`Adding` を差し替えた `show`・`update`・`schedule` だけ。ほかの完了は、テストが作った登録に受け口の `finish*` を直接当てた（TB-5 の `DialogReceiver.finish` と同じ）。ログには題・本文・userInfo・添付の名前・識別子の値を出さない（有無と件数、エラーの番号だけ。`NotificationError` は中身に添付の識別子と OS の文を持つので、`String(describing:)` で出さない）。

### 10.2 12.1 と 12.2 の行

| 行 | どこで | 結果 |
|---|---|---|
| 12.1 写しの表（11.2 の全 case） | `testEveryNotificationError` | 11 case と `NotificationError` でない失敗（`UNKNOWN`）を手で書いて比べた |
| 12.1 権限の事前の確かめ（6 つの状態の全行） | `testTheStatuses`、`testThePreCheckOfEveryStatus` | `authorized`・`provisional`・`ephemeral` だけが通る。C の関数から入り、差し替えた口で 3 つの操作 × 6 状態を通した。拒むときはライブラリを呼ばない |
| 12.1 `update_async` が `update` を呼ばない | `testAnUpdateWithoutPermissionDoesNotCallTheLibrary` | 差し替えた口で確かめた |
| 12.1 OP-26〜OP-28 が `PERMISSION_DENIED` で完了 | UI テスト `testAskingForTheNotificationPermissionFromC` | **実際の未決の状態で**、3 つとも 10 で完了し、配信済みにも予約にも何も無い（M2 の「即時の分だけ配信済みに載る」が起きない） |
| 12.1 権限の要求の選択肢（P2-27） | `testThePermissionOptions`、`testUnknownPermissionBitsAreRejected` | 0 は `[.alert, .sound, .badge]`、各ビットが同じ `rawValue`、`PROVIDES_APP_SETTINGS` が渡る。`1 << 6`、`1 << 7`、`1 << 8`、`1 << 31` は戻り値で `INVALID_PARAMETER` |
| 12.1 前面 | UI テスト（同上） | 未決で後ろから呼んだ OP-35 と、後ろからの OP-38 が `NOT_FOREGROUND`（8）。決まった後の OP-35 は後ろからでも `granted=1` |
| 12.1 trigger の C のテスト・AP-19 の範囲外の trigger | `testATriggerOutOfRangeIsTheReturnValue` | `interval` の 0、-1、繰り返しで 59.9 と 30、NaN、±∞、`kind` 3、`calendar_fields` の 0 と知らないビット、緯度 90.5、経度 -180.5、半径 0 を `show`・`update`・`schedule` に渡し、どれも戻り値で 1、`release` が戻る前に 1 回、完了なし。事前の確かめにも届かない。**プロセスは落ちない** |
| 12.1 category の C のテスト | `testACategoryIsCheckedAtTheEntry` | 識別子の `NULL` と空文字、知らない category とアクションのビット、`reserved1`、`NULL` の構造体が戻り値で 1 |
| 12.1 入口の検査 | `testANullCallbackIsRejectedByEveryOperation` ほか | 16 の操作の `NULL` の callback（P2-28）、別スレッドの拒否は呼んだスレッドで `release`（main を待たない）、内容の `NULL` と別の型のハンドル、`update`・`schedule` の識別子（`NULL`、空文字、5 つの不正な UTF-8）、削除の識別子（`NULL`、不正な UTF-8）、`schedule` の `NULL` の trigger、構造体の大きさ・`reserved1`・知らない後ろの部分（`NOT_SUPPORTED`）、負のバッジ、`ntk_last_system_code` が 0 |
| 12.1 出力のハンドル | `testAListThroughC`、`testTheReadersOfNothing`、`testAnEmptyListIsNotNull` | 範囲外の添字・`NULL`・別の型は `NULL`（`out_size` 0）か 0。`_free(NULL)` は何もしない |
| 12.1 ビルダーの写しを呼んだ時点で取る | `testTheCopyOfTheContentIsTakenAtTheCall` | 戻った後にビルダーを変えて解放しても、操作に渡る値は元のまま |
| 12.2 Dialog と権限（権限のダイアログ） | UI テスト（同上） | C から求めた権限のダイアログで「許可」を押し、完了が `0 0 granted=1`。状態は 2（`AUTHORIZED`）、`has_permission` は 1 |
| 12.2 通知の順序と許可の後 | UI テスト `testTheNotificationOperationsInOrderAfterThePermission` | 許可の後に `schedule_async`・`update_async`・`show_async`（trigger つき）が pending に残る。`update_async` が同じ識別子の題を置き換える（1 件のまま）。`cancel_all_scheduled_async` の完了の中の `schedule_async` が残る。即時の `show_async` が配信済みに載り（時刻あり）、`remove_async` で消える。無い添付のファイルは完了で 17。バッジ、category の登録と削除、`cancel_all`、`remove_all` が `0 0` で完了 |

**権限の状態の作り方**（最初の形。10.9 で権限のテストを `CApiFreshInstallUITests` に移し、名前の順には頼らなくなった）: `CApiRoundTripUITests` は `CApiFreshInstallUITests` の後に流れ、その前にランナーがアプリを消している（`CAPI_UI_CLASSES`）。このクラスで権限を求めるのは上の 2 件だけなので、未決から始まる。XCTest はクラスの中を名前の順に流すので、未決を要るテスト（`testAsking…`）が先に、許可を要るテスト（`testThe…`）が後になる。後のテストは、未決なら自分で求めて許可する。権限を戻すのはランナーの削除とシミュレーターの再起動だけで、シミュレーターの設定は変えていない。

### 10.3 コマンドと結果（最後のソース）

02:28〜03:11 に下の順で続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で Simulator.app が開いていないことを、各実行の前（スクリプトの中）と途中で確かめた（ずっと閉じていた）。ソースのハッシュは流す前と後で同じ: `6abab5b93cea`（メインのセッションと同じ数え方。`git status --short -- ios scripts` のファイル）、`c3790b2f81d5`（6.8 と同じ範囲）。**流した後に変えたのはこの記録だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 424/424 |
| 同（iPhone 16 / 18.3） | 424/424 |
| 同 TSan（iPhone 17 Pro / 26.2） | 424/424。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 424/424。報告 0 件 |
| `--capi-ui --udid`（iPhone 17 Pro / 26.2。Xcode 26.6 の `DEVELOPER_DIR`） | 49/49。rc 0（新しい 2 件を含む。`20261107-023451-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 49/49。rc 0（`20261107-025127-iPhone_16-18.3.1`） |
| framework の Release（2 つ）`--library` | `OK symbols`（116 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 116 of 134、18 not implemented yet |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

開発の途中に、1 つ前のソース（無い添付の行を足す前）で `--capi-ui`（iPhone 17 Pro）を 1 回流し、49/49 だった。iPad は流していない。

### 10.4 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

30 個。写しは最後のソースと同じ（流す前に写し、流した後に `diff -rq` で差なし。ハッシュも同じ）。`NotificationOperationTests` と `NotificationMappingTests` だけを流した。依頼の順では 4 番目だが、最後の検証の前に流した（変異でテストを直すことになれば最後の検証をやり直すことになるため。TB-6 と同じ）。**30 個とも落ちた。**

| 区分 | 変異 |
|---|---|
| 受け口（11） | 事前の確かめをしない、`update` が `show` を呼ぶ、`update` と `show` が trigger を捨てる（2）、`schedule` が内容の `id` を使う、投げられた失敗が `NONE`、事前の確かめの拒否が `UNKNOWN`、負のバッジを受ける、`granted` が常に 1、権限の失敗が `NONE`、設定の成功が `UNKNOWN` |
| 写し（16） | `schedule` が `NULL` の trigger を受ける、空の識別子を受ける、`PROVIDES_APP_SETTINGS` が無い、0 が選択肢なし、`provisional` のビットを受ける、`ephemeral` を通さない、`unknown` を通す、`provisional` と `ephemeral` の取り違え、`.permissionDenied` が 10、`NotificationError` でない失敗が 18、添付の失敗が 18、設定の失敗が 8、バッジの失敗が 18、delegate の未設定が 4、ミリ秒の四捨五入、範囲外の時刻が最大値 |
| ハンドル（3） | 予約に時刻がある、副題の無いものが空文字、範囲外の添字の時刻が -1 |

**クラッシュ**: 「負のバッジを受ける」と「空の識別子を受ける」の 2 つで、テストのホストが落ちた（変異で受け付けられた要求の完了が、テストの終わった後に解放済みの記録の物に書いた。`ClipboardRecorder.record` の `EXC_BAD_ACCESS`）。どちらも先に失敗が記録されている。変異が作ったレポートは名前を記録してから消した: `IosLibraryCApiTestHost-2026-11-07-021107.ips`、`-021458.ips`、`-021459.ips`。同じ時間帯にシミュレーターの `AccessibilityControlsExtension` のレポート（`-021723.ips`、`-022027.ips`、最後の検証の間に `-023054.ips`）も出たが、自分のプロセスではないので消していない。**この 2 つの変異は、受け付けた要求がシミュレーターの通知の中心に届いた**（バッジの -1 と空の識別子の `update`。使い捨ての写しの上だけ）。

### 10.5 設計書の読み方（5.1 の名前のほか、設計書は変えていない）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 12.1「`IosLibraryCApiTests` で OP-26〜OP-28 が `PERMISSION_DENIED` で完了する」 | TB-7 のテストは通知の追加に届かない（依頼）。**差し替えた口で全状態を通し、実際の `PERMISSION_DENIED` は UI テストの未決の状態で確かめた** | **戻すことを勧める**（12.1 の行を「差し替えた口で全状態。実際の未決は 12.2 の UI テスト」に） |
| 2 | 6.3「削除の関数の識別子は `NULL` だけを拒み、空文字は `NONE`」（category の段落） | `remove_category_async` に加え、`remove_async` と `cancel_scheduled_async` にも当てた | **戻すことを勧める**（3 つの削除の関数に当たると明記） |
| 3 | 6 章冒頭「C の入力の形の規則」の「空の識別子」 | `update_async` と `schedule_async` の `identifier` は `NULL` と空文字を拒む（`_create` の `id` と同じ。M5） | 戻すことを勧める（6.3 の表に一言） |
| 4 | 内容のハンドル | `NULL` と別の型のハンドルは `INVALID_PARAMETER` | 不要 |
| 5 | 一覧の `_subtitle_at`、`_body_at` | 値が無い（ライブラリが空を `nil` にする）ときは `NULL`（`out_size` 0）。題と category は空文字 | **戻すことを勧める**（付録 A の宣言に「無ければ NULL」。公開ヘッダーのコメントなので設計書の決定が要る） |
| 6 | `_date_millis_at` | 切り捨てのミリ秒。`Int64` に入らない時刻は 0 | 不要 |
| 7 | 知らない `NotificationAuthorizationStatus` の case | 状態は `UNKNOWN`（5）、事前の確かめは通さない。知らない `NotificationError` は `UNKNOWN`（4） | 不要 |
| 8 | 取り消し | 通知の操作は取り消せない。登録の「取り消しの完了」は走らないが、走れば `UNKNOWN` を返す形にした（6 と 7 は欠番。P2-10） | 不要 |
| 9 | OP-35、OP-38 の表示元 | P2-1 のとおり `.foreground` | 不要 |
| 10 | 12.1 の「前面」の OP-38 | 後ろからの `NOT_FOREGROUND` だけを確かめた。前面で設定の App が開くことは確かめていない（アプリが前面から離れるため。TB-8 の MS-07 の方法で） | 不要（10.7 に記録） |
| 11 | UI テストの置き場所 | 依頼のとおり `CApiRoundTripUITests` の中。権限の順は名前の順と前のクラスの削除に頼る（10.2） | 戻すかは判断を仰ぐ（`CApiFreshInstallUITests` に置けば名前の順に頼らない） |

### 10.6 実装の途中で分かったこと

- 入口が受け付けた要求の完了は、テストの記録の物より後まで来うる（変異のクラッシュ）。本当のテストは、受け付けるものはすべて終わりまで待つ（`finished`）
- 未決のまま `show_async` を拒むと、配信済みにも何も載らない（M2 の「即時の分だけ載る」が C の経路では起きない）ことを UI テストで確かめた
- 前面でのバナーは、行のボタンを押すのを妨げなかった（`show_async` の即時の後に続けて押せた。2 つのシミュレーターで）

### 10.7 確かめられていないこと

- **実機では何も流していない**（`generic/platform=iOS` は組むだけ）
- 前面での `open_settings_async`（設定の App が開くこと）。`AUTHORIZATION_FAILED`、`SET_BADGE_COUNT_FAILED`、`ADD_REQUEST_FAILED`、`SETTINGS_NOT_OPENED` を C から起こすこと（写しの関数のテストだけ。12.1 のとおり）
- 権限の拒否（「許可しない」）を押したときの完了（1 回のインストールで 1 つしか選べず、順序のテストが許可を要るため。値は写しの関数で `NONE` と 0）
- 位置の trigger を実際に足すこと（位置の権限と Info.plist）
- category が本当に登録されたこと（C から読む口が無い。完了の値だけ）
- `ephemeral`・`provisional` の実際の状態（差し替えた口だけ）
- iPad では流していない

### 10.8 時間

01:33〜03:13（約 1 時間 40 分）。うち変異が約 24 分（02:04〜02:28）、最後の検証が約 43 分（02:28〜03:11。`--capi-ui` が 1 回約 16 分）。目標の 04:00 の中。

### 10.9 レビューの直しと決定

レビュー（Claude と Codex。どちらも A なし）をメインのセッションから受けた。**下の決定は、メインのセッションが持ち主の「判断が必要な場合、推奨案で、進める。」という指示の下で推奨案で決めたもの。持ち主はまだ読んでいない。**

| 指摘 | 直したこと |
|---|---|
| 記録の物の寿命（Codex B1、Claude C-6） | `NotificationOperationTests` は、C に渡す記録の物をテストの物の配列（`recorders`）に入れて、テストの物が生きている間（XCTest は流し終わるまで持つ）持ち続ける。`completion(of:)` の代わりに同じ形の `completed` を置き、そこでも持ち続ける。`finished` が時間切れになった後に来た完了も、生きている物に書く。`ClipboardTestSupport.swift` は変えていない |
| 失敗で閉じる既定（Claude B-2、Codex B2） | `setUpWithError` で `Adding` を「呼ばれたら `XCTFail`。状態の読み取りは `.denied` を返す」形にし、`tearDown` で `.manager` に戻す。受け付けを確かめるテストは今どおり `fake()` を入れる。**決定: 16 の操作すべてに口を足す案は採らない。** 削除・バッジ・category・権限・一覧・設定には口が無いので、**入口の検査が退行したときだけ、それらは本当の通知の中心に届きうる。届く先はテストのホスト自身の通知とバッジ**（ホストは権限を求めないので、追加は事前の確かめで止まる） |
| 削除の空文字（Claude B-1） | `removalIdentifier` を内部に開き、`""` が通り `NULL` が拒まれることを単体テストにした（`testAnEmptyRemovalIdentifierIsAccepted`）。UI テストの行 `removeEmpty`、`cancelScheduledEmpty`、`removeCategoryEmpty` で、3 つが `0 0` で完了し、予約が消えないことを確かめた |
| ログの識別子（Codex B3、Claude C-1） | C ABI の側の `NotificationContentBuilder.swift` の 4 か所（`makeContent`、`init`、`update`、`create`）で `id` の値を出していたのを、長さにした。受け口と写しは前から有無だけ。**決定: `IosLibrary` の側のログは TB-7 の範囲外として変えない。ライブラリは識別子を `.public` で出す。別の課題として持ち主に判断を仰ぐ** |
| 記録の言い過ぎ（Claude C-1） | 10.1 を「TB-7 のテストは通知の追加・削除・一覧・バッジ・権限・設定に触れない。TB-1 からある `NotificationInstallTests` は delegate を読み書きする」に直した |
| 未決のときの配信済み（Claude C-2） | 未決で 3 つを拒んだ後、2 秒待ってから配信済みを読む |
| 完了の写し（Claude C-3） | `finishStatus` と `finishHasPermission` を受け口の関数に出し、6 つの状態と真偽を単体テストで通した（`testTheStatusCompletions`、`testTheHasPermissionCompletions`） |
| 判定の集合（Claude C-4） | テストのターゲットは前から `@testable import IosLibrary` できる（設定は変えていない）。`NotificationPresentationGate.grants` と 6 つの状態を 1 行ずつ比べた（`testThePreCheckIsTheLibrarysSet`） |
| 型の置き場所（Claude C-5） | `NotificationListEntry` を `NotificationMapping.swift` に移した（Dialog の `DialogResultValue` と同じ置き方）。**`error(for: NotificationDelegateInstallResult)` は TB-2 のコードなので動かしていない**（受け口に残る） |
| UI テストの置き場所（10.5 の 11、Claude B-3） | `testAskingForTheNotificationPermissionFromC` を `CApiFreshInstallUITests` に移した。**ランナーと表は変えていない**（このクラスは前から `CAPI_UI_CLASSES` で「1 件ずつ、前にアプリを消す」クラスで、テストは列挙で拾われる）。名前の順に頼らなくなった。順序のテストは `CApiRoundTripUITests` に残した。このクラスは最後の fresh のテストのインストールを引き継ぐので、そのテストが許可していなければ未決で、そのときだけ自分で求めて許可する。2 つのクラスで使う `notificationLine`、`NotificationError`、`NotificationStatus`、`allowNotifications()` は `CApiUITestApp.swift` に移した |
| C-7（`["Allow", "許可"]` の重複） | **直さず記録だけ**（決定）。`SystemLabels.allow`（信頼するファイル）と、`CApiUITestApp.allowNotifications()` の 2 か所にある。`PasteAnswer` の貼り付けの名前と同じ扱い |

**設計書に戻したもの**（10.5 の 1・2・3・5。決定）:
- 第 2 部 12.1「権限の事前の確かめ」の行: 差し替えた口で 6 状態 × OP-26〜OP-28、`update_async` が `update` を呼ばないこと。実際の未決の `PERMISSION_DENIED` と許可の後は 12.2 の UI テスト。同じ表の「ビルダー」の行の括弧書きも合わせた
- 第 2 部 6.3: `update_async` と `schedule_async` の行に「`identifier` の `NULL` と空文字は `INVALID_PARAMETER`」。削除の行に「`remove_async`、`cancel_scheduled_async`、`remove_category_async` は識別子の `NULL` だけを拒み、空文字を受けて何も消さずに `NONE`（6 章冒頭の規則の例外）」。category の段落の同じ文から表を指した
- 付録 A と公開ヘッダー `Notification.h` のコメントだけ（宣言は変えていない）: `_subtitle_at`・`_body_at` は「NULL when the notification has none.」、`_title_at`・`_category_at` は「May be empty; NULL only for an index out of range.」（依頼の「never NULL」は範囲外の添字で `NULL` を返す動作と合わないので、範囲外のときだけ `NULL` と書いた）。照合は通る

10.5 の 1・2・3・5 は上で戻した。11 は上の移動で片づいた。

**変異（直しで足したテストだけ。6 個。使い捨ての写しは最後のソースと同じ。流した後に `diff -rq` で差なし。iPhone 16 / 18.3）**: **6 個とも落ちた。クラッシュは 0 件**（前の回の 2 件のクラッシュは、記録の物を持ち続けるようにして無くなった）。

| 変異 | 落としたテスト |
|---|---|
| 空の識別子を受ける（閉じた既定あり） | `testTheIdentifiersOfUpdateAndSchedule`、`testACategoryIsCheckedAtTheEntry`。受け付けた `update("")` は閉じた既定に届き、「a call reached the pre-check without a fake」で落ちた（状態は `.denied` を返し、通知の中心には届かない） |
| 同じ変異で、閉じた既定を `setUp` から外す | 同じテストで落ちた。**この場合は事前の確かめが本当の状態（ホストの `notDetermined`）を読んだ**（ログの `PERMISSION_DENIED: status notDetermined` が 1 件増えた）。追加は止まったが、閉じた既定が無いと中心まで届くことを示す |
| 削除が空文字を拒む | `testAnEmptyRemovalIdentifierIsAccepted` |
| 状態の完了が常に `UNKNOWN` | `testTheStatusCompletions` |
| 権限があるかが反転 | `testTheHasPermissionCompletions` |
| 事前の確かめが `unknown` を通す | `testThePreCheckIsTheLibrarysSet`、`testThePreCheckOfEveryStatus`、`testTheStatuses` |

`AccessibilityControlsExtension` のレポート（`-032817.ips`）が変異の間にまた出た。自分のプロセスではないので消していない。

**直した後の最後のソースの結果**（03:31〜04:14。順に続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で各実行の前と途中に Simulator.app が閉じていることを確かめた）。ソースのハッシュ: **直す前（10.3）は `6abab5b93cea` / `c3790b2f81d5`、直した後は流す前と後で同じ `a25d4a5a5a57`（メインのセッションと同じ数え方）/ `8ea959cc7c07`（6.8 と同じ範囲）**。**流した後に変えたのはこの記録だけ。** 上の 6 個の変異はこの検証の前に、同じソースの写しで流した。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 428/428 |
| 同（iPhone 16 / 18.3） | 428/428 |
| 同 TSan（iPhone 17 Pro / 26.2） | 428/428。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 428/428。報告 0 件 |
| `--capi-ui --udid`（iPhone 17 Pro / 26.2。Xcode 26.6） | 49/49。rc 0。`CApiFreshInstallUITests` が 2 件（`testAskingForTheNotificationPermissionFromC` と `testTheRunnerDeletedTheApp`。それぞれ前にアプリを消して 1 件ずつ）、`CApiRoundTripUITests` が 47 件（`20261107-033644-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 49/49。rc 0。同じ分け方（`20261107-035404-iPhone_16-18.3.1`） |
| framework の Release（2 つ）`--library` | `OK symbols`（116 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 116 of 134 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

テストは 424 → 428 件（`NotificationOperationTests` 31）。この間にシミュレーターの `AccessibilityControlsExtension-2026-11-07-033308.ips` と `maild-2026-11-07-035448.ips` が出た。自分のプロセスではないので消していない。時間: 03:21〜04:16（約 55 分）。

**読み直しの後の直し（コメントと文書だけ）**: 2 本の読み直し（どちらも A なし。Codex は B もなし）を受けた。**下の決定も、メインのセッションが持ち主の指示の下で推奨案で決めたもの。持ち主はまだ読んでいない。**

| 指摘 | 直したこと |
|---|---|
| 公開ヘッダーと付録 A の読み取り（Claude B-1、Codex C1） | `_title_at`・`_category_at` は「May be empty. NULL for a NULL list, a handle of another type or an index out of range; then out_size is 0.」、`_subtitle_at`・`_body_at` は「NULL when the notification has none, and for a NULL list, …; then out_size is 0.」（`Clipboard.h` の読み取りの書き方に揃えた） |
| ヘッダーの識別子の規則（C-1） | `update_async`・`schedule_async` に「identifier must not be empty.」、3 つの削除の関数に「"" removes nothing and completes with NONE.」。付録 A も同じ文 |
| 6.3 の例外の理由（C-2） | 「消すものが無いだけで、黙って失うものが無いため」を足した |
| 12.2 の行（C-3） | 「Dialog と権限」に「未決のうちは OP-26〜OP-28 が `PERMISSION_DENIED` で完了し、何も載らない」、「通知の順序と許可の後」に「空文字の削除 3 つが `NONE` で完了し、予約が残る」 |
| 10.1〜10.8（C-4） | 10 章の頭に「10.1〜10.8 は直す前の記録。今の形は 10.9」を足した（数字は書き換えていない） |
| 持ち主の指示の引用（C-5） | 10 章の頭と 10.9 の「」を原文にした |
| 未決の前提（C-6） | `CApiRoundTripUITests` のコメントと上の表を「最後の fresh のテストが許可していなければ未決。そのときだけ求める」にした。コードは変えていない |
| `NotificationMapping` の説明（C-7） | 第 2 部 5.1 の表と第 1 部の木を今の中身（trigger と category、権限の選択肢、状態と失敗の写し、一覧の値と `NotificationListEntry`、入口の検査）にした。**決定: `removalIdentifier` は受け口に残し、Mapping に移さない**（記録だけ） |

**確かめ**（04:22〜04:28）: `.swift` と `.h` の差分は `Notification.h` と `CApiRoundTripUITests.swift` のコメントだけ（コメントを除いたコードは直す前の写しと同じ。比べて確かめた）。そのため、シミュレーターのテストは流し直していない（依頼のとおり）。ソースのハッシュは、直す前が `a25d4a5a5a57` / `8ea959cc7c07`、直した後が流す前も後も `cec257ba99d5` / `cb915f7116fc`。

| 実行 | 結果 |
|---|---|
| framework の Release（2 つ）`--library` | `OK symbols`（116 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |


## 11. TB-8

第 2 部 13 章の TB-8（通知のイベント OP-42〜OP-45 と、UI テスト用のアプリに起動の形を伝える口）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。**判断の要るところは、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」）のもとで決めた形（推奨案）で進めた。持ち主はまだ読んでいない。**

### 11.1 足したもの

**TB-8 の C の関数は 14 個**: 登録と取得の 4 つ（`add_interaction_listener`、`add_settings_request_listener`、`get_launch_response_async`、`listener_remove`）、`ntk_notification_interaction` の読み取りと解放の 8 つ（`_kind`、`_notification_id`、`_action_id`、`_category_id`、`_user_text`、`_user_info_json`、`_is_launch`、`_free`）、`ntk_notification_settings_request` の 2 つ（`_notification_id`、`_free`）。`NOT_IMPLEMENTED_YET` から 14 個を外し、`entries` は 130 of 134（残りは Share の 4）。

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Notification/NotificationEntry.swift` | 14 関数。各 1 行 |
| 受け口 | `Notification/NotificationReceiver.swift` | `Events`（ライブラリの 2 つのハブと `launchResponse()`、delegate が入っているか。テストが差し替える口）、2 つの帳簿（`EventLedger`、32 件まで保つ）、`receive`、`addListener`（入口の検査の後に `NOT_INITIALIZED`。R-8）、`removeListener`、`finishLaunchResponse` |
| 写し | `Notification/NotificationMapping.swift` | `NotificationInteractionValue`、`kind(actionIdentifier:userText:)`、`interaction(of:)`（userInfo は TB-6 の `NotificationJson.text(of:)`） |
| ハンドル | `Notification/NotificationHandles.swift` | `NotificationInteractionHandle`、`NotificationSettingsRequestHandle` と読み取り |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 14 個 |
| テスト | `IosLibraryCApiTests/NotificationEventTests.swift`（新規。16） | 428 → 444 件 |
| UI テスト用のアプリ | `IosLibraryCApiUITestApp/LaunchShape.swift`（新規）、`CApiRow.swift`、`UITestAppMain.swift`、`Rows/NotificationRows.swift` | 起動の形（下）、起動の中の 2 つの受け手、行 6 個（`listen`、`unlisten`、`listenSettings`、`launchResponse`、`registerEventCategory`、`showEventSoon`） |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`、`CApiUITestApp.swift`、`CApiUITestCase.swift` | テスト 2 件。バナーの操作の補助（`eventBanner`、`expandEventBanner`、`tapEventAction`、`sendEventReply`、`pressHome`、`activate`）。`launchApp(section:listensAtLaunch:)` |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py` とその表、README、メモリ、設計書は変えていない（新しい受け口のファイルは無い。`LaunchShape.swift` は UI テスト用のアプリのファイルで、5.1 の表と第 1 部の木はアプリのファイルを並べていない）。

**起動の形（`LaunchShape`）**: UI テストは起動の環境に `NTK_CAPI_SECTION` と `NTK_CAPI_LISTEN_AT_LAUNCH`（`1` / `0`）を渡す。アプリはそれを Application Support の `ntk-capi-ui-launch-shape.txt`（`section=…`、`listen=…`）に書き、環境なしで起動されたとき（システムが通知のタップで起こしたコールドスタート）はそのファイルを読む。サンプルの SA-18 と同じ形（ファイルで、`UserDefaults` は使わない）。`listen=1` なら `didFinishLaunching` の中で `ntk_notification_install` の後に 2 つの受け手を登録し、イベントを `launch.interaction` と `launch.settings` の行に書く。どこから読んだかを `launch.shape` の行（`source=environment|file|defaults`）に書く。

**`IosLibraryCApiTests` は通知の中心にもライブラリのハブにも届かない**（TB-1 からある `NotificationInstallTests` の delegate の読み書きは別）。`setUp` で `Events` を「使われたら `XCTFail`。delegate は入っていない」形に差し替え、使うテストは偽物を入れる。イベントは、ライブラリの受け手が呼ぶのと同じ `NotificationReceiver.receive` に渡す。帳簿はプロセスで 1 つずつなので、各テストは先に、前のテストが残して保たれたイベントを受け取って捨てる。記録の物はテストの物が持ち続ける（TB-7 の 10.9 と同じ）。ログには識別子・題・本文・返信・userInfo の値を出さない（有無、長さ、件数、種類の番号だけ）。

### 11.2 12.1 と 12.2 の行

| 行 | どこで | 結果 |
|---|---|---|
| 12.1 イベント: 2 つの登録の両方に届く、ハンドルは登録ごと | `testAnInteractionReachesEveryRegistrationWithAHandleOfItsOwn` | 各コールバックが自分のハンドルを解放した後に次が読む（共有なら ASan が見る） |
| 12.1 イベント: 解除の後に届かない | 同上 | 解除の後の 1 件は届かず、`release` は 1 回 |
| 12.1 イベント: 保っていたイベントが次の登録の挿入のブロックで届く、33 件目で最も古いものを捨てる | `testWhatComesWithNoRegistrationWaitsForTheNext` | 33 件のうち後の 32 件が、呼び出しの中ではなく挿入で、順に届く |
| 12.1 イベント: 保ったものを配るコールバックの中で唯一の登録を外して新しく足す（AP-21） | `testReplacingTheRegistrationInsideAHeldEventsCallback` | 残りの 2 件が新しい登録に届く |
| 12.1 イベント: 設定の要求も次の登録まで保つ（5.4） | `testASettingsRequestWithNoRegistrationWaitsForTheNext` | 登録の無い間の 2 件が、挿入で届く |
| 12.1 イベント: ライブラリの受け手は最初の挿入で 1 回だけ足す（5.4） | `testTheLibrarysListenerIsAddedOnce` | 2 種類とも 1 回 |
| 12.1 イベント: ハンドルの値（`_kind` の 4 種、userInfo、`_is_launch`） | `testTheFourKinds`、`testAnInteractionThroughC`、`testASettingsRequestWithAndWithoutANotification` | 返信があれば既定の識別子でも `TEXT_INPUT`。空の返信は `""`。userInfo は JSON。設定の要求の識別子の無いものは `NULL` |
| 12.1 delegate: `NOT_INITIALIZED`（OP-42、OP-43、OP-45） | `testTheAddsRejectAtTheEntry`、`testTheLaunchResponseRejectsAtTheEntry` | 入口の検査（`NULL` の callback と出力）が先で、`NOT_INITIALIZED` が後。出力は `NULL`、`release` は呼び出しスレッドで戻る前に 1 回 |
| 12.1 delegate: 起動のきっかけ（P2-19） | `testNoLaunchResponseIsNull`、`testALaunchResponse`、`testALaunchResponseFailure`、UI テスト | `NULL` は `NONE`。値は `_is_launch` 1。失敗は写しのとおり。UI テストで 2 回呼んで同じ |
| 12.1 出力のハンドル | `testTheReadersOfNothing`、`testRemovingNullDoesNothing` | `NULL` と別の型は `NULL`（`out_size` 0）、`-1`、0。`_free(NULL)` と `_listener_remove(NULL)` は何もしない |
| 12.2 通知のイベント: `BODY_TAP`、`ACTION`、`TEXT_INPUT` | UI テスト `testNotificationEventsReachTheListenerOfC` | ホームに出てからバナーを押す、長押しして `Open`、長押しして `Reply` で送る。それぞれ C の受け手に 1 回、`_kind` と識別子、category、返信、userInfo（`{"k":1}`）、`_is_launch` 0 で届いた |
| 12.2 コールドスタートのタップと `_is_launch` | UI テスト `testATapThatStartsTheAppReachesCAsTheLaunch` | アプリを終了してからバナーを押すと、システムが起こしたプロセスがファイルから起動の形を読み（`source=file listen=1`）、起動の中の受け手に `_is_launch` 1 で届いた。`get_launch_response_async` を 2 回呼んで同じ値 |

**しなかったもの（12.2）**: `DISMISS` の UI テストと、`openSettingsFor`（MS-07）の UI テスト。`DISMISS` は通知センターで消す操作が要り、この形の操作はサンプルでも測っていない。`openSettingsFor` は最初の権限の要求に `PROVIDES_APP_SETTINGS` が要り（今の権限のテストは既定の選択肢）、設定の App の中の名前が iOS 26.2 と 18.3 で違う（サンプルは 26.2 の英語だけ）。どちらも写しと帳簿は単体テストで通した（`DISMISS` の種類、設定の要求の識別子の有無）。

### 11.3 コマンドと結果（最後のソース）

05:20〜06:07 に下の順で続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で各実行の前（スクリプトの中）と途中に Simulator.app が閉じていることを確かめた。ソースのハッシュ: **前（TB-7 のコミット `58c53e8b` のツリー）は `cec257ba99d5` / `cb915f7116fc`（TB-7 の 10.9 の最後と同じ）、最後のソースは流す前も後も `37aae231de2d`（メインのセッションと同じ数え方）/ `68605d592cff`（6.8 と同じ範囲）**。**流した後に変えたのはこの記録だけ。**

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 444/444 |
| 同（iPhone 16 / 18.3） | 444/444 |
| 同 TSan（iPhone 17 Pro / 26.2） | 444/444。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 444/444。報告 0 件 |
| `--capi-ui --udid`（iPhone 17 Pro / 26.2。Xcode 26.6） | 51/51。rc 0。新しい 2 件を含む（`20261107-052623-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 51/51。rc 0（`20261107-054502-iPhone_16-18.3.1`） |
| framework の Release（2 つ）`--library` | `OK symbols`（130 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 130 of 134、4 not implemented yet |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

開発の途中に、1 つ前のソース（11.4 のテストを足す前）で `--capi-ui`（iPhone 17 Pro）を 1 回流し、51/51 だった。iPad は流していない。最後の検証の間にシミュレーターの `maild-2026-11-07-054545.ips` が出た（自分のプロセスではないので消していない）。

### 11.4 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

24 個。最後の検証の前に流した（依頼のとおり）。`NotificationEventTests` だけを流した。

1 回目（写しはその時のソース `9eaa3f5b6aca` と同じ）: **23 個が落ち、「設定の要求を保たない」（`holdLimit` 0）が生き残った**（設定の要求を保つテストが無かった）。また 2 個（「受け手の登録が `NOT_INITIALIZED` を見ない」「操作を保たない」）でテストのホストが落ちた: 変異で `testReplacingTheRegistrationInsideAHeldEventsCallback` の 2 つ目の登録が作られず、テストが出力の初期値（`0x1` の印）を `_listener_remove` に渡した（テストの側の誤り）。どちらも先に失敗が記録されている。

直したこと: `testASettingsRequestWithNoRegistrationWaitsForTheNext` を足し、`testReplacingTheRegistrationInsideAHeldEventsCallback` の 2 つ目の出力を `NULL` から始めた（テストだけ。受け口は変えていない）。2 回目（写しは最後のソース `37aae231de2d` と同じ。流した後に `diff -rq` で差なし）: 生き残ったものとクラッシュした 2 つの 3 個を流し、**3 個とも落ち、クラッシュは 0 件**。**合わせて 24 個とも落ちた。**

| 区分 | 変異 |
|---|---|
| 受け口（13） | 受け手の登録が `NOT_INITIALIZED` を見ない、`NULL` の callback が `NOT_INITIALIZED`、出力を `NULL` にしない、操作を 31 件だけ保つ、操作を保たない、設定の要求を保たない、起動のきっかけが `NOT_INITIALIZED` を見ない、起動のきっかけの失敗が `NONE`、起動のきっかけを捨てる、設定の要求の識別子を捨てる、解除が何もしない、操作の受け手を足さない、設定の受け手を足さない |
| 写し（7） | 既定の識別子の返信が `BODY_TAP`、`DISMISS` が `ACTION`、`BODY_TAP` が `ACTION`、`_is_launch` を捨てる、category が action の識別子、空の返信が `NULL`、userInfo が常に `{}` |
| ハンドル（4） | `NULL` の `_kind` が 0、`NULL` の `_is_launch` が 1、返信の無いものが空文字、設定の要求の識別子の無いものが空文字 |

変異が作ったクラッシュレポートは名前を記録してから消した: `IosLibraryCApiTestHost-2026-11-07-045902.ips`、`-050207.ips`。同じ時間帯のシミュレーターの `AccessibilityControlsExtension-2026-11-07-050206.ips`、`-050251.ips`、`-051112.ips` は自分のプロセスではないので消していない。

### 11.5 設計書の読み方（設計書は変えていない）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 12.1「delegate」の `NOT_INITIALIZED` | delegate が入っているかは `IosNotificationManager.isDelegateInstalled`（C でも Swift でも入れれば真）。入口の検査（`NULL` の callback と出力）を先に、`NOT_INITIALIZED` を後に（11 章） | 不要 |
| 2 | 5.4「最初の登録のブロックの中でだけ受け手を 1 つ足し、以後は外さない」 | 種類ごとに 1 回。ライブラリの登録の物は受け口が持ち続ける。足すときにライブラリが拒んだら（delegate が無い等）ログだけ（その種類のイベントはそのプロセスでは来ない） | **戻すことを勧める**（拒まれたときの扱いを一言） |
| 3 | 保つ数 | 受け口の帳簿も 32 件（ライブラリのハブも 32 件保つが、受け口は最初の登録で受け手を足した後は全部を受ける） | 不要 |
| 4 | userInfo の JSON | TB-6 の出力の写しのまま。書けなかったときは `{}`（変換が全部の値を書ける形にするので起きない見込み。ログに出す） | 不要 |
| 5 | `_is_launch` の `NULL` | 0 | 不要 |
| 6 | 12.2 の `DISMISS` と `openSettingsFor` | 上のとおり UI テストはしていない | **戻すことを勧める**（12.2 の行に「`DISMISS` と `openSettingsFor` は手で、または測った後に」） |
| 7 | 起動の形のファイル | 13 章の TB-8 の「ファイルで」を `LaunchShape`（環境 → ファイル → 既定）にした。シミュレーターの UI テスト用のアプリだけ | 不要 |

### 11.6 確かめられていないこと

- **実機では何も流していない**（`generic/platform=iOS` は組むだけ）
- `DISMISS` と `openSettingsFor` の UI テスト（上）
- 背景のアクションの直後にアプリを前面に出したときに `_is_launch` で来ること（6.3 の注意。測っていない）
- ライブラリが受け手を拒んだときの動き（起きない見込み。ログだけ）
- iPad では流していない

### 11.7 時間

04:29〜06:08（約 1 時間 40 分）。うち変異が約 22 分（04:57〜05:20）、最後の検証が約 47 分（05:20〜06:07。`--capi-ui` が 1 回約 18 分）。目標の 06:30 の中。

### 11.9 レビューの直しと決定

レビュー（Claude と Codex。どちらも A なし）をメインのセッションから受けた。**下の決定は、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」）のもとで推奨案で決めたもの。持ち主はまだ読んでいない。** 11.1〜11.7 は直す前の記録で、今の形はこの節（依頼の番号に合わせて 11.9 とした。11.8 は無い）。

| 指摘 | 直したこと |
|---|---|
| 起動の形のファイルの書き込みの失敗（Codex B1） | 書く前に古いファイルを消し、書けなかったらファイルは無い（次のコールドスタートは既定）。`launch.shape` の行を `source=… section=… listen=… saved=1|0|-` にした（値は section と listen だけ。`saved` は環境から来たときだけ）。コールドスタートの UI テストは、終了させる前に `saved=1` を確かめる |
| 受け手の登録の行の上書き（Codex B2、Claude C-6） | `notification.listen` と `listenSettings` は前の登録を外してから登録する。`notification.unlistenSettings` を足した。行は消していない |
| ため置きのあふれの数（Codex C） | **第 1 部と第 2 部を確かめた: 「古いものから捨てる」（第 2 部 5.4）だけで、捨てた数の記録やログは求めていない**（ライブラリのハブは自分の捨てた数をログに出す）。**決定: コードは変えない。足すかは持ち主に判断を仰ぐ** |
| `DISMISS` と `openSettingsFor`（Claude B-1、提案 6） | 第 2 部 12.2 の「通知のイベント」の行、13 章の TB-10 の行、15.2 の DoD に、**TB-10 が受け持つ**と書いた（TB-9 は Share だけなので、指示のとおり TB-10）。測り方: `DISMISS` はシミュレーターの通知センターでの「消去」を iOS 26.2 で測ってから。`openSettingsFor` はアプリを消した直後のクラスで `PROVIDES_APP_SETTINGS` 付きの要求から始め、設定の App の文言が OS で違うので 26.2 だけ。**持ち主の決定を待つ項目**（TB-10 に入れてよいか） |
| 提案 2 | 第 2 部 5.4 に「ライブラリが受け手を拒んだらログだけ。その種類はそのプロセスでは来ず、C の登録は `ACTIVE` のまま何も受けない。再試行しない。入口で delegate を確かめるので起きない見込み」を足した |
| C-1 | `tearDown` で `.library` に戻すのをやめ、失敗で閉じる `Events` のまま残す（後から main で動くブロックもライブラリに届かない。このプロセスでイベントを使うのはこのクラスだけ）。`testARejectionOffTheMainThreadReleasesOnThatThread` の最後で main を流す |
| C-2 | `NotificationHandles.buffer` を `fileprivate` に戻した |
| C-3 | `[unowned first, unowned next]` |
| C-4 | 偽物の起動のきっかけを「`nil` → 値 → 値」と返し、3 回呼ぶテスト（`testTheLaunchResponseCanAppearLaterAndThenStays`。P2-19） |
| C-5 | コールドスタートの UI テストで、`launch.interaction` が 1 件だけ、`launch.settings` の行が無い（拒まれていない）ことを確かめる |
| C-7 | 予約と配信済みの片付けを `addTeardownBlock` に移した（失敗して途中で止まっても片付ける）。**割り込みで落ちたときは片付けない**（片付けの行を押すと、押さない方針に反するため。`checkInterruption` が止める） |
| C-8 | `ensureNotificationPermission` の最後に、状態が `AUTHORIZED` であることを確かめる |
| C-9 | `finishLaunchResponse` の先頭のログに、成功で値あり・成功で値なし・失敗のどれかだけを足した |
| C-10 | `withLaterTrigger` を `withTrigger(seconds: 3600)` の 1 行にした |
| C-11 | 変異に 2 つを足した（下）。あわせて、2 種類のハンドルを取り違えて読むと何も読めないテスト（`testTheEventHandlesAreNotTakenForEachOther`）を足した |

**持ち主の判断待ち**: (1) ため置きのあふれた数を記録・ログに出すか (2) `DISMISS` と `openSettingsFor` の UI テストを TB-10 に入れてよいか。

テストは 444 → 446 件（`NotificationEventTests` 18）。

**変異（直しで足したテストと C-11。2 個。写しは最後のソースと同じ。流した後に `diff -rq` で差なし。iPhone 16 / 18.3）**: **2 個とも落ちた。**

| 変異 | 結果 |
|---|---|
| 1 つのハンドルを登録の間で共有する | テストのホストが落ちた（2 つ目の登録が、1 つ目が解放したハンドルを `ntk_notification_interaction_user_info_json` で読み、`EXC_BAD_ACCESS`）。`testAnInteractionReachesEveryRegistrationWithAHandleOfItsOwn` の形が見つけるもの。レポートは名前を記録してから消した: `IosLibraryCApiTestHost-2026-11-07-062212.ips` |
| 設定の要求の読み取りが操作のハンドルの型で読む | `testTheEventHandlesAreNotTakenForEachOther`、`testASettingsRequestWithAndWithoutANotification`、`testASettingsRequestWithNoRegistrationWaitsForTheNext` で落ちた |

起動の形（`LaunchShape`）と行の上書きは UI テスト用のアプリの中なので、変異ではなく UI テストで確かめた（`saved=1` と `source=file … saved=-`）。同じ時間帯のシミュレーターの `AccessibilityControlsExtension-2026-11-07-062126.ips` は自分のプロセスではないので消していない。

**直した後の最後のソースの結果**（06:23〜07:10。順に続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で各実行の前と途中に Simulator.app が閉じていることを確かめた）。ソースのハッシュ: **直す前（11.3）は `37aae231de2d` / `68605d592cff`、直した後は流す前も後も `2ba9bebbf66d`（メインのセッションと同じ数え方）/ `0f3845838f0f`（6.8 と同じ範囲）**。**流した後に変えたのはこの記録だけ。** 上の 2 個の変異はこの検証の前に、同じソースの写しで流した。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 446/446 |
| 同（iPhone 16 / 18.3） | 446/446 |
| 同 TSan（iPhone 17 Pro / 26.2） | 446/446。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 446/446。報告 0 件 |
| `--capi-ui --udid`（iPhone 17 Pro / 26.2。Xcode 26.6） | 51/51。rc 0（`20261107-062916-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 51/51。rc 0（`20261107-064811-iPhone_16-18.3.1`） |
| framework の Release（2 つ）`--library` | `OK symbols`（130 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 27、FAIL 0、SKIP 2。`entries` は 130 of 134 |
| `test_check_c_abi_contract_ios.py` | Ran 278 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

時間: 06:17〜07:11（約 55 分）。

**読み直しの後の直し**（Claude と Codex の 2 本。どちらも A なし。Claude は B なし、Codex は B 1 件）。**決定は、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」）のもとで推奨案で決めたもの。持ち主はまだ読んでいない。**

| 指摘 | 直したこと |
|---|---|
| Codex B（`LaunchShape`） | コメントを正確にした: 古いファイルを先に消し、書けなかったらもう一度消す。2 回とも消せなかったときは古いファイルが残りうる。そのときは `saved=0` で、コールドスタートの UI テストは終了させる前に `saved=1` を確かめるので落ちる（`testATapThatStartsTheAppReachesCAsTheLaunch` の 2 つ目の文。`continueAfterFailure` は偽なので、そこで止まる）。コードは変えていない |
| Codex C | `NotificationEventTests` の `tearDown` で、`events` を明示的に失敗の形に戻してから super を呼ぶ |
| Claude C-1 | **決定: 偽物を入れる処理は共有の助けに移さない。イベントの入口を使うテストは自分で偽物を入れる。このクラスの後は失敗の形が残る**（`NotificationEventTests` のコメントにも書いた） |
| Claude C-2 | 上の表の C-7 の行に、割り込みで落ちたときは片付けないことを足した |
| Claude C-3 | 第 2 部 13 章の TB-8 の行の完了の条件を「12.1 のイベント・delegate の行と、12.2 の『通知のイベント』の行のうち `BODY_TAP`、`ACTION`、`TEXT_INPUT` とコールドスタート（`DISMISS` と `openSettingsFor` は TB-10）」にした |
| Claude C-4 | 15.2 の項目を「TB-10 で確かめ、通った。`openSettingsFor` は iOS 26.2 のシミュレーターだけ。`DISMISS` を流す OS は 26.2 で測ってから決める」と、終わりの条件として読める形にした |
| Claude C-5 | 上の表の下に持ち主の判断待ちの 1 行を足した。第 2 部 12.2・13 章（TB-8 と TB-10 の行）・15.2 に「（作業記録 11.9 の確認待ち）」の印を付けた |

**確かめ**（07:15〜07:20。順に流し、各実行の前に `pgrep -x Simulator` で Simulator.app が閉じていることを確かめた）: ソースの差分は `NotificationEventTests.swift` の `tearDown`（テストのコード）と、`LaunchShape.swift` と `NotificationEventTests.swift` のコメントだけ（`LaunchShape.swift` はコメントを除いたコードが直す前と同じ。UI テストとほかのファイルは変えていない）。そのため `--capi-ui` は流していない。ソースのハッシュは、直す前が `2ba9bebbf66d` / `0f3845838f0f`、直した後が流す前も後も `1b79c7f1f8e8` / `4d239028d027`。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 446/446 |
| 同（iPhone 16 / 18.3） | 446/446 |
| 同 ASan（iPhone 17 Pro / 26.2） | 446/446。報告 0 件 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。FAIL 0 |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |


## 12. TB-9

第 2 部 13 章の TB-9（Share、OP-46 と結果）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。**判断の要るところは、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」）のもとで決めた形（推奨案）で進めた。持ち主はまだ読んでいない。**

### 12.1 足したもの

**TB-9 の C の関数は 4 個**: `ntk_share_content_async`、`ntk_share_result_completed`、`ntk_share_result_activity_type`、`ntk_share_result_free`。`NOT_IMPLEMENTED_YET` は空になり、`entries` は 134 of 134。**`--require-complete` を付けても通った**（rc 0。`OK complete: every function of the headers has its entry`。TB-10 の条件なので、最後の検証では付けていない）。

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 入口 | `IosLibraryCApi/IosLibraryCApi/Share/ShareEntry.swift`（新規） | 4 関数。各 1 行 |
| 受け口 | `Share/ShareReceiver.swift`（新規） | `Sharing`（シートを出す口。テストが差し替える。既定は `IosShareManager.shared.share(content:presenter: .foreground, completion:)`。P2-1）、`share`、`finish`。取り消せない（P1-24）ので登録は箱を持たない |
| 写し | `Share/ShareMapping.swift`（新規） | `ShareRejection`（共通の値と `EMPTY_CONTENT`）、`content`、`item`、`result(of:)`、`error(for:)`（11.4） |
| ハンドル | `Share/ShareHandles.swift`（新規） | `ShareResultHandle` と読み取り |
| ログ | `Common/CApiLog.swift` | `share` の分類を 1 つ足した（ほかの機能と同じ形。Share の知識は入れていない） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` から 4 個を外し、空にした |
| 照合の自己テスト | `scripts/tests/test_check_c_abi_contract_ios.py` | 一覧が空になると、一覧の名前を借りていた 4 つの自己テストが動かなくなった（`NOT_IMPLEMENTED_YET[0]` で読み込みが落ちた）。一覧の働きは、一覧を書き換えた照合の写し（`run_checker_listing`。照合のスクリプトと `c_abi_contract_common.py` を一時のフォルダーに写す）で確かめる形にした。壊れていない木では `complete` が旗なしでも OK になることを確かめ、一覧が空であることのテストを 1 つ足した（278 → 279） |
| テスト | `IosLibraryCApiTests/ShareTests.swift`（新規。14） | 446 → 460 件 |
| UI テスト用のアプリ | `IosLibraryCApiUITestApp/Rows/ShareRows.swift`（新規）、`CApiRow.swift` | 行 3 個（`share.text`、`share.missingFile`、`share.empty`）。`share` のセクション |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`、`CApiUITestApp.swift` | テスト 3 件。シートの補助（`waitForShareSheet`、`noShareSheetAppears`、`closeShareSheet`）。`CApiSection.share`。TB-8 の `expandEventBanner` の印を直した（12.6） |
| 設計書 | 第 2 部 5.1 の表、第 1 部 5.1 の木 | `Share/ShareMapping.swift`、`Share/ShareHandles.swift` の行だけ |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル、`scripts/ios_ui_runner.py` とその表、README、メモリは変えていない。

**`IosLibraryCApiTests` は共有のシートを出さない**（実機の ASan で流れるため）。`setUp` で `Sharing` を「呼ばれたら `XCTFail` して `SHOW_FAILED` で終える」形に差し替え、受け付けを確かめるテストは偽物を入れる。`tearDown` は失敗の形に戻し、このクラスの後もそのまま残る（ほかに共有するテストは無い）。記録の物はテストの物が持ち続ける。ログには共有する文字列・URL・パス・題・除く活動の値を出さない（有無、件数、種類の番号だけ）。

**UI テストはシートを開いて閉じるだけ**（依頼）。閉じ方: シートの外の閉じる領域（`PopoverDismissRegion`）があれば（iOS 26.2 と iPad は 1 つ、iPhone 16 / 18.3 は 2 つ）、画面の左上寄り（0.1, 0.15）を押す（下のシートの外で、iPad の中央に付く popover からも離れた所）。無ければ閉じるボタン（`Close` / `閉じる`）。何も選ばない。

### 12.2 12.1 と 12.2 の行

| 行 | どこで | 結果 |
|---|---|---|
| 12.1 入口の検査 | `ShareTests` | `NULL` の callback と要求、項目の `NULL` の配列と件数、範囲外の `kind`（4、-1）、`NULL` の値、5 つの不正な UTF-8（値、subject、preview title）、除く活動の `NULL` の配列と `NULL` の要素、構造体の大きさ（要求と項目）、項目の `reserved1`、知らない後ろの部分（`NOT_SUPPORTED`）、収まらない件数。どれも戻り値で、`release` は呼び出しスレッドで戻る前に 1 回、完了なし。別スレッドの拒否は呼んだスレッドで `release` |
| 12.1 AP-19 の `EMPTY_CONTENT` | `testNoItemIsEmptyContent`、UI テスト | 件数 0 は、配列を読む前に戻り値で 7（読めない配列でも） |
| 12.1 写しの表 | `testEveryShareError` | 9 case を手で書いて比べた |
| 12.1 0 で埋めた構造体 | `testAZeroFilledRequestOfEachKind`、`testAFullRequest` | 4 種の項目、subject と preview title の `NULL` は「無い」、空文字は空文字のまま、除く活動 |
| 12.1 完了 | `testACompletedShare`、`testAClosedSheet`、`testAFailureHasNoResult` | 偽物の口で、完了が main で戻った後に 1 回、`release` 1 回。成功はハンドル（閉じたのは `completed` 0 と活動 `NULL`）、失敗は `NULL` |
| 12.1 呼んだ時点の写し | `testTheContentIsCopiedAtTheCall` | 戻った後に文字列を書き換えて解放しても、口に渡る値は元のまま |
| 12.1 出力のハンドル | `testTheReadersOfNothing` | `NULL` と別の型は 0 と `NULL`（`out_size` 0） |
| 12.1 前面（OP-46） | UI テスト `testAShareFromTheBackgroundIsNotForeground` | 後ろから呼ぶと `NOT_FOREGROUND`（6）で完了し、シートは出ない |
| 12.2 Share | UI テスト `testTheShareSheetFromC` | C から開いたシートが出て、閉じると `0 0` で `completed` 0、活動 `NULL` |
| 完了で返る失敗 | UI テスト `testShareFailuresComeWhereTheDesignSays` | 無いファイルは完了で `FILE_NOT_FOUND`（9）、シートは出ない |

**12.2 の「コピー」を選ぶ確かめはしていない**（依頼: シートからほかへ送る操作をしない。「コピー」も押さない）。`completed` 1 と活動の識別子は偽物の口の単体テストだけ。

### 12.3 コマンドと結果（**止めた所までの状態**）

**09:30 の締めで止めた。最後の検証は全部はそろっていない。** 流したものは順に続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で各実行の前と途中に Simulator.app が閉じていることを確かめた。

1 回目の最後の検証（ソース `537e2970c80c` / `761330faf27a`。1 つ目の値は `git status --short -uall` で数えた: 新しいフォルダーがあると `-uall` が無い数え方は `shasum` が失敗するため）:

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 460/460 |
| 同（iPhone 16 / 18.3） | 460/460 |
| 同 TSan（iPhone 17 Pro / 26.2） | 460/460。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 460/460。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2） | 54/54。rc 0 |
| `--capi-ui`（iPhone 16 / 18.3） | 53/54。**`testTheShareSheetFromC` が落ちた**（閉じる領域が 2 つで、閉じるボタンが無い。12.6）。ここで止めて直した |

直した後（UI テストの補助 `closeShareSheet` だけ。ソース `5c6059ec70ad` / `1f1ee27091cc`）:

| 実行 | 結果 |
|---|---|
| `--capi-ui`（iPhone 16 / 18.3） | 54/54。rc 0 |
| `--capi-ui`（iPad Pro 11-inch (M4) / 18.3） | 1 回目はテストのランナーが起動で落ちた（`Failed to create a bundle instance …`。シミュレーターの側のエラーで、テストは 1 件も流れていない）。2 回目は 53/54: **Share の 3 件は通った**。**TB-8 の `testNotificationEventsReachTheListenerOfC` が落ちた**（長押しの後に `Open` のボタンが出ない。12.6） |
| framework の Release（2 つ）`--library` | `OK symbols`（134 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 28、FAIL 0、SKIP 1。`entries` は 134 of 134、0 not implemented yet。`--require-complete` を付けても rc 0、FAIL 0 |
| `test_check_c_abi_contract_ios.py` | 1 回目は読み込みで落ちた（`NOT_IMPLEMENTED_YET[0]`）。直した後（ソース `830a0980482c` / `644138d9bdc6`）に Ran 279 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0（最後のソースで流し直した） |

**流していないもの**: 最後のソース（`830a0980482c`）での iPhone 17 Pro の `--capi-ui`（1 回目の 54/54 は閉じ方を直す前のソース。直した閉じ方は iOS 26.2 では「領域がある」の側を通り、押す所が領域の中から画面の左上寄りに変わった）。単体テスト・TSan・ASan は 1 回目のソースで、その後の変更は UI テストの補助と照合の自己テストだけ（受け口と単体テストは変えていない）。

### 12.4 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3）

19 個。最後の検証の前に流した。写しはそのときのソース（`19d38b5a1feb` の数え方。新しいフォルダーで 1 つ目の値は `shasum` が失敗した / `761330faf27a`）と同じ（流した後に `diff -rq` で差なし）。`ShareTests` だけを流した。**19 個とも落ちた。クラッシュは 0 件。**

| 区分 | 変異 |
|---|---|
| 写し（15） | 件数 0 が `INVALID_PARAMETER`、URL が文字列、画像がファイル、ファイルが画像、範囲外の `kind` が文字列、`NULL` の値が空文字、項目の `reserved1` を名指ししない、subject を捨てる、preview title が subject、除く活動を捨てる、`.noRootViewController` が `SHOW_FAILED`、`.dismissedBySystem` が `SHOW_FAILED`、`.activityFailed` が `UNKNOWN`、`.invalidURL` が `INVALID_PARAMETER`、`.noValidItems` が `INVALID_PARAMETER` |
| 受け口（2） | 成功にハンドルが無い、失敗にハンドルがある |
| ハンドル（2） | `NULL` の `_completed` が 1、活動の識別子を捨てる |

同じ時間帯のシミュレーターの `AccessibilityControlsExtension-2026-11-07-075031.ips` と、検証の間の `-090338.ips` は自分のプロセスではないので消していない。

### 12.5 設計書の読み方（5.1 の名前のほか、設計書は変えていない）

| # | 所 | 読み方 | 設計書に戻すか |
|---|---|---|---|
| 1 | 12.2 の Share の行「『コピー』を選び、`completed` と `activity_type` を確かめる」 | 依頼のとおり押さない。閉じて `completed` 0 を確かめた。`completed` 1 は単体テストの偽物だけ | **持ち主の判断待ち**（「コピー」はシミュレーターの pasteboard に入るだけだが、押すかどうか） |
| 2 | 6.4 の項目の値の検査 | 入口は `NULL` と UTF-8 と `kind` の範囲だけ。空の文字列・URL の形・ファイルの有無はライブラリが完了で返す（AP-19 の基準）。空のパスも入口では拒まない（Clipboard の P2-9 の (8) は Share には書かれていない） | 戻すことを勧める（6.4 に「空の値は入口で拒まない」） |
| 3 | 11.4 の `.noRootViewController` | `NOT_FOREGROUND`（表のとおり。`.foreground` の口では届かない） | 不要 |
| 4 | 11.4 の `UNKNOWN` | 知らない case だけ。取り消しの完了（走らない）も `UNKNOWN` | 不要 |
| 5 | `_completed` の `NULL` | 0 | 不要 |
| 6 | iPad の閉じ方 | popover の外の領域の左上寄りを押す（6.2 のアクションシートの外側のタップと同じ考え） | 不要 |

### 12.6 実装の途中で分かったこと

- **TB-8 の UI テストが iPad（18.3）で落ちる。直っていない**: 通知の長押しの後に、展開した通知の識別子（`notification-expanded-view`。iOS 26.2 のシミュレーターで測った名前）が無い。印をアプリ自身の `Open` のボタンにしたが、それも出なかった。iPad の 18.3 では長押しで展開しないか、展開の形が違う（測っていない）。TB-8 は iPad では流していなかった（TB-8 の依頼の検証に iPad は無かった）。**持ち主の判断待ち**（12.8）
- iPad（18.3、日本語）でもシートの開閉と前面の確かめは最初の回から通った
- **iPhone 16 / 18.3 では閉じる領域が 2 つあり、閉じるボタンは見つからなかった**（最初の閉じ方は「領域が 1 つならそれ、無ければボタン」で、最後の検証の 1 回目で落ちた）。領域があれば画面の左上寄りを押す形にした

### 12.7 確かめられていないこと

- **実機では何も流していない**（`generic/platform=iOS` は組むだけ）
- 「コピー」などの活動を選んだときの完了（上の 1）。`ACTIVITY_FAILED`、`CANCELED_BY_SYSTEM`、`SHOW_FAILED`、`INVALID_URI`、`IMAGE_LOAD_FAILED` を C から起こすこと（写しの関数のテストだけ）
- 複数の窓の iPad でどの窓に出るか（ヘッダーのとおり決めていない）

### 12.8 持ち主の判断待ち（TB-9）

**3 つとも 12.10 で決めた（メインのセッションが利用者の指示のもとで推奨案で決めた。持ち主はまだ読んでいない）。**

1. 12.2 の Share の行の「コピー」を選ぶ確かめをするか（12.5 の 1）
2. 6.4 に「空の値は入口で拒まない」を書くか（12.5 の 2）
3. TB-8 の通知のイベントの UI テスト（長押しで展開する `ACTION` と `TEXT_INPUT`）を iPad で通すか。通すなら iPad の 18.3 で展開の操作を測る。通さないなら、その 2 つを iPad では飛ばす形にするか（今は落ちる）

### 12.9 時間

07:21〜09:30（約 2 時間 10 分）。目標の 08:45 を過ぎ、遅くとも 09:30 の締めで止めた。

### 12.10 仕上げ: 判断待ちの決定とレビューの直し

**下の決定は、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」「実機の区切りまでは自動で進めて」）のもとで推奨案で決めたもの。持ち主はまだ読んでいない。** 12.3〜12.9 は仕上げの前の記録で、今の形はこの節。

**12.8 の判断待ちの決定**:

| # | 決定 | したこと |
|---|---|---|
| 1 | 12.2 のとおり「コピー」を選ぶ（シミュレーターの general pasteboard に書くだけ。Clipboard の UI テストと同じ扱い。Simulator.app を閉じたまま、Mac の pbcopy / pbpaste と simctl pbsync は使わない。ほかの活動は選ばない。前の「押さない」は取り消し） | `testCopyingFromTheShareSheetFromC`: シートの `Copy` / `コピー` のセルを押し、完了が `0 0 completed=1 activity=com.apple.UIKit.activity.CopyToPasteboard`。差（12.5 の 1）は無くなった |
| 2 | 6.4 に「空の値は入口で拒まない」を書く | 第 2 部 6.4 に 1 行足した |
| 3 | iPad の TB-8 の長押し: 40 分を限りに測って通す | 下のとおり測って通す形にした（`XCTSkip` は使っていない） |

**iPad / 18.3 の長押しを測ったこと**（09:28〜09:36。調査用のテストを一時に足して `test-without-building` で iPad だけに流し、springboard の階層のうち自分の通知の範囲（題・本文・`Open`・`Reply`・展開・バナー）の行だけを出した。**調査用のテストは消した**。ほかに残っていないことを `grep` で確かめた）:
- バナーの長押し（0.8、1.5、3 秒。バナーとその中のボタンの両方）、下へ引く、左へ払う: どれも展開しない。3 秒の長押しではバナーが消えるだけ
- **通知センター（画面の上の中央から下へ引く）の中の同じ通知のセル（`ListCell`）を 1.5 秒押すと展開し、`Open` と `Reply` のボタンが出る**
- そこで `expandEventBanner` は、iPad で 3 秒以内に `Open` が出なければ、バナーが消えるのを待ち、通知センターを開き、セルを長押しする形にした（iPhone は今のまま）。印はアプリ自身の `Open` のボタン

**レビュー（Claude と Codex。ライブラリのコードに A なし）の直し**:

| 指摘 | 直したこと |
|---|---|
| A-1 | 調査用の `testProbeTheEventBannerOnTheIPad` を消した（元のファイルに戻した）。`PROBE`・`Probe` が `ios/IosLibraryCApi*` に無いことを確かめた（`scripts/test_android.sh` の Android の `Probe` は別のもの） |
| B-1 | `testTheStructRulesOfTheRequestAndTheItem`（`NULL`、要求と項目の `reserved0`、4096 を超える大きさ、後ろが 0 なら受ける、0 でなければ `NOT_SUPPORTED`）、`testTheItemsAreSteppedByTheirOwnSize`（P2-5: 要素の大きさで進む、要素の知らない部分、大きさの混ざった配列）、`testAnExcludedTypeMustBeUTF8` |
| B-2 | `testCountsThatDoNotFit`: 項目と除く活動のそれぞれの件数に -1（`SIZE_MAX`）と `1 << 61` で `INVALID_PARAMETER`（`EMPTY_CONTENT` ではない） |
| B-3 | `testAnAcceptedShareOffTheMainThreadDoesNotWaitForIt`（DialogEntryTests と同じ形） |
| Codex C | `testTwoSharesCompletedInTheOtherOrder`: 完了をため置く偽物で 2 つを受け、逆の順で完了させる。結果は別々、完了と `release` は 1 回ずつ、`release` は callback の後 |
| C-1 | `ShareMapping.content` の実行されない guard を消し、件数をそのまま渡す |
| C-2 | `item` は `kind` を先に見て、範囲外なら値を読まずに拒む（`testAnItemOfAKindOutOfRangeIsNotRead`: `kind` 4 と読めない値） |
| C-3 | 照合の自己テストに `test_a_listed_function_without_its_entry_or_symbol_only_stops_require_complete` を足した（一覧に載せた写しで、入口の行を消し、記号を落とした nm: 旗なしは rc 0 で `SKIP complete`、`--require-complete` では落ちるのは `complete` だけ）。`symbols` のテストの重複した `extra` を消した（nm の偽物は、モジュールの一覧が空なので、もとから全部の記号を出す） |
| C-4 | 「コピー」を行ったので差は無い |
| C-5 | `testTheActivityTypeOutput`: 空の活動の識別子は `NULL` でなく `""`（`out_size` 0）、U+0000 は U+FFFD |
| C-6 | TB-8 の iPad の補助（`expandEventBanner`）は上の測りの結果として TB-9 に入れた。落ちたまま残していない |

テストは 460 → 468 件（`ShareTests` 22）。照合の自己テストは 280 件。

**変異（直しで足したテスト。5 個。写しは最後のソースと同じ。流した後に `diff -rq` で差なし。iPhone 16 / 18.3。`ShareTests` だけ）**: **5 個とも落ちた。**

| 変異 | 結果 |
|---|---|
| `kind` より先に値を読む | テストのホストが落ちた（`kind` 4 の項目の読めない値を読んだ。`testAnItemOfAKindOutOfRangeIsNotRead` の形が見つけるもの）。レポートは名前を記録してから消した: `IosLibraryCApiTestHost-2026-11-07-094044.ips` |
| 除く活動を検査せずに読む | `testAnExcludedTypeMustBeUTF8`、`testCountsThatDoNotFit`、`testTheExcludedTypesAreChecked` |
| 空の活動の識別子が `NULL` | `testTheActivityTypeOutput` |
| `NULL` の配列なら件数 0 でも読む | `testNoItemIsEmptyContent` |
| 活動の識別子の U+0000 をそのまま出す | `testTheActivityTypeOutput` |

**最後のソースの結果**（09:44〜10:52。順に続けて流し、シミュレーターの仕事は重ねていない。`pgrep -x Simulator` で各実行の前と途中に Simulator.app が閉じていることを確かめた）。ソースのハッシュ（`git status --short -uall -- ios scripts` で数えた値 / 6.8 と同じ範囲）は流す前も後も **`a11fc464c05d` / `b33a02732d47`**。TB-9 の前は TB-8 のコミット `40232429`。**流した後に変えたのはこの記録だけ。** 上の 5 個の変異はこの検証の前に、同じソースの写しで流した。

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 468/468 |
| 同（iPhone 16 / 18.3） | 468/468 |
| 同 TSan（iPhone 17 Pro / 26.2） | 468/468。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 468/468。報告 0 件 |
| `--capi-ui --udid`（iPhone 17 Pro / 26.2。Xcode 26.6） | 55/55。rc 0（`20261107-095044-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 55/55。rc 0（`20261107-101050-iPhone_16-18.3.1`） |
| 同（iPad Pro 11-inch (M4) / 18.3、日本語） | 55/55。rc 0（`20261107-102922-iPad_Pro_11-inch_(M4)-18.3.1`）。ランナーの起動の失敗は無く、流し直していない。TB-8 の `testNotificationEventsReachTheListenerOfC` も通った（通知センターから展開） |
| framework の Release（2 つ）`--library` | `OK symbols`（134 symbols。1 architectures、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 28、FAIL 0、SKIP 1。`entries` は 134 of 134、0 not implemented yet |
| 同 `--require-complete` | rc 0、FAIL 0。`OK complete: every function of the headers has its entry` |
| `test_check_c_abi_contract_ios.py` | Ran 280 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

この間に出たレポートは、シミュレーターと Mac の `maild`、`nanoprefsyncd`、`remindd`、`proactive_event_tracker` のもので、自分のプロセスではないので消していない（古い Mac の `.diag` がいくつか消えたのは OS の入れ替えで、自分は消していない）。時間: 09:28〜10:55（約 1 時間 30 分）。

### 12.11 2 回目のレビューと、メインのセッションの直し

12.10 のソースを、Claude のサブエージェントと Codex に読むだけで見てもらった（2026-11-07 10:53〜11:05）。どちらも A は 0。直しはメインのセッションが、指摘をコードで確かめてから入れた。**持ち主はまだ読んでいない。**

| 指摘 | 確かめたこと | 扱い |
|---|---|---|
| Claude B-1 | 読み出しは NULL のハンドルにも 0 と NULL を返す（`testTheReadersOfNothing`）。逆順完了のテストの先の側は、まさにその値を期待していた | 直した: 2 つのハンドルが違う、error が NONE、ハンドルが NULL でない、release は main で 1 回、を足した |
| Claude C-1 / Codex C | 記録は callback の入口だけで、「release は callback が戻った後」を観測していなかった | 直した: 各 recorder の `onCompletion`（callback の中）で、release がまだ無いことを確かめる |
| Claude C-3 | `CApiUITestApp.swift` と `ShareRows.swift` のコメントが「何も選ばない」のままだった | 直した（コメントだけ） |
| Claude C-2 | 項目の件数 `1 << 61` は、桁あふれの検査が無くても ASan の外では別の理由で拒まれうる | 直さない。-1 と除く活動の側が効いている。読み方は共通の StructReader |
| Claude C-4 | `closeShareSheet` は閉じる領域を待たずに数える | 直さない。3 機種で起きていない。直すと UI テストを 3 機種で流し直す要がある。落ちたら直す |
| Claude C-5 | iPad の分岐は、前の回の通知が通知センターに残ると、まとめて表示されて見つからないことがある | 直さない。終わりに通知を消している。落ちたら直す |

直しの後に流したもの: `IosLibraryCApiTests`（iPhone 17 Pro / 26.2）と、UI テストのアプリとターゲットの build-for-testing。UI テストそのものは流し直していない（UI 側の変更はコメントだけ）。iPhone 16、TSan、ASan も流し直していない（変更は単体テストの 1 件だけ）。変異は流していない。

結果（11:00〜11:03）: `IosLibraryCApiTests` は 468/468（直した `testTwoSharesCompletedInTheOtherOrder` も通った）。build-for-testing は rc 0。警告は `appintentsmetadataprocessor` の「AppIntents が無い」の 4 件だけで、コードの警告は 0。照合（`--require-complete`）と第 1 部・第 2 部の設計書の照合は、直しの前の 10:53 にメインのセッションが流して FAIL 0（直しはこれらの対象に触れない）。

## 13. TB-10

第 2 部 13 章の TB-10（main を待たないことのテスト、競合の再現のテスト、`NOT_IMPLEMENTED_YET` と H = E、12.2 の「通知のイベント」の残りの `DISMISS` と `openSettingsFor`）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。**判断の要るところは、メインのセッションが利用者の指示（「判断が必要な場合、推奨案で、進める。」）のもとで決めた形（推奨案）で進めた。持ち主はまだ読んでいない。**

### 13.1 決めたこと（推奨案。持ち主の確認待ち）

| # | 決定 | 誰が | 理由 |
|---|---|---|---|
| 1 | `DISMISS` と `openSettingsFor` の UI テストを TB-10 に入れる（11.9 の確認待ちの (2)） | メインのセッション | 12.2 の行と 15.2 の DoD を TB-10 で閉じるため。設計書の「（作業記録 11.9 の確認待ち）」の印は「推奨案で進めた。持ち主の確認待ち」の形に直した（第 2 部 12.2・13 章の TB-8 と TB-10 の行・15.2） |
| 2 | `EventLedger` のあふれた数の記録・ログは入れない（11.9 の確認待ちの (1)） | メインのセッション | 持ち主の判断待ちのまま |
| 3 | **通知の受け口に差し替えの口 `NotificationReceiver.Operations` を足した**（OP-29〜OP-41 のうち `show`・`update`・`schedule` 以外の 13 操作が呼ぶライブラリの口。既定は `.manager` で、今までと同じ `IosNotificationManager` の callback の口を呼ぶ） | 実装者（推奨案） | この 13 操作は受け口から直に `IosNotificationManager` を呼んでいて、C から受け付けると単体テストから本物の通知の中心に届く。差し替えの口が無いと「受け付けたものは完了と `release` が後で main で 1 回ずつ」を 13 操作では確かめられない（入口で拒む形だけになる）。TB-7 の `Adding`、TB-8 の `Events`、TB-9 の `Sharing` と同じ形（受け口の中の closure の束。Ports & Adapters の形ではない）。`getScheduled`・`getDelivered` は写し（`NotificationMapping.entries`）を `.manager` の中に移し、受け口は `[NotificationListEntry]` を受ける。`IosLibraryCApiTests` は `setUp` で失敗で閉じる形を入れる（`FailClosed`。`NotificationOperationTests` にも足した） |
| 4 | `openSettingsFor` の UI テストは、iOS 26.2 では設定の App を辿って確かめ、**ほかの OS では `PROVIDES_APP_SETTINGS` 付きの要求が `granted=1` で通るところで終える** | 実装者（推奨案） | 指示は「26.2 だけ」。ランナーは skip を失敗と数える（`capi-summary`。「An intended skip does not exist here」）ので `XCTSkip` は使えず、`scripts/ios_ui_runner.py` は変えない約束なので、OS を見て早く戻る形にした。テストのコメントに書いた |
| 5 | `DISMISS` は 3 台とも流す | 実装者（推奨案。測った結果） | 26.2 で測って通った後、iPhone 16 / 18.3 と iPad / 18.3（日本語）でも測った。iPhone はセルの `swipeLeft` で「Clear」が出る。iPad は `swipeLeft` でセルが消え（ボタンは出ない）、セルの右寄りから中ほどまでの短いドラッグで「オプション」と「消去」が出た（13.4） |
| 6 | 作業記録 7.7（1171 行）の「ダイアログを出している間の取り消し」を UI テストにした | 実装者（推奨案） | 書ける形があった: アプリの行が読み込みを始め、4 秒後に別のスレッドから取り消す（`clipboard.loadThenCancelLater`）。UI テストは貼り付けのダイアログが出たのを確かめ、取り消しの後に「許可」を押し、完了が `CANCELED` の 1 回だけであることを見る（取り消しが効いていなければ（状態が `CANCEL_REQUESTED` に変わらなければ）、許可で `NONE` と本文が来る。箱を閉じたかどうかは見分けない。第 1 部 5.7 の「完了」の行）。DoD に送るものは無い |
| 7 | 新しい単体テストのクラスの名前を `ThreadContractTests` にした | 実装者 | `NotificationEventTests` の `testTheLibrarysListenerIsAddedOnce` が、プロセスで最初の挿入の回数を数えている。XCTest はクラスを名前の順に流すので、それより後に流れる名前にした（クラスのコメントに書いた） |

### 13.2 足したもの

| 区分 | ファイル（`ios/`） | 中身 |
|---|---|---|
| 受け口 | `IosLibraryCApi/IosLibraryCApi/Notification/NotificationReceiver.swift` | `Operations`（13.1 の 3）と `operations`。13 操作の `start` はこの口を呼ぶ。`set_badge_count` は口を `Task` の前に読む（`Adding` と同じ） |
| テスト | `IosLibraryCApiTests/ThreadContractTests.swift`（新規。6） | `FailClosed`（4 つの口の失敗で閉じる形）、`NotificationOperationsFake`。テストは 13.3 |
| テスト | `IosLibraryCApiTests/NotificationOperationTests.swift` | `setUp` で `operations` も失敗で閉じる（1 行） |
| UI テスト用のアプリ | `IosLibraryCApiUITestApp/Rows/NotificationRows.swift`、`Rows/ClipboardRows.swift` | 行 2 個: `notification.requestPermissionWithAppSettings`（`ALERT`・`SOUND`・`BADGE`・`PROVIDES_APP_SETTINGS`）、`clipboard.loadThenCancelLater`（読み込みを始め、4 秒後に別のスレッドから `ntk_clipboard_cancel_load`） |
| UI テスト | `IosLibraryCApiUITests/CApiRoundTripUITests.swift`、`CApiFreshInstallUITests.swift`、`CApiUITestApp.swift` | テスト 3 件（13.3）。補助: `clearEventInNotificationCenter`（通知センターのセルの「消去」）、`openTheAppsNotificationSettingsLink` と `pressSettingsRow`（サンプルの N40 の `Springboard.openSampleNotificationSettingsLink` と同じ辿り方を写した。信頼するファイルは変えていない） |
| 設計書 | 第 2 部 12.1 の「main を待たない」の行、12.2 の「通知のイベント」の行、13 章の TB-8 と TB-10 の行、15.2 | 13.1 の 1・3〜5 の印と、差し替えの口の一言 |

公開ヘッダー、`ios/IosLibrary`、信頼する UI テストのファイル（`ios/IosLibraryExample/IosLibraryExampleUITests/Support/` の 5 つ）、`scripts/ios_ui_runner.py` とその表、`scripts/check_c_abi_contract_ios.py`、README、メモリは変えていない。`android/.idea` には触れていない。

**`IosLibraryCApiTests` は通知の中心にも共有のシートにも届かない**: `ThreadContractTests` は `setUp` で `Adding`・`Operations`・`Events`・`Sharing` を失敗で閉じる形にし、受け付けを確かめるテストは、すぐに完了する偽物を入れる。Dialog は受け付けと同じ呼び出しの中で取り消す（最初の main の回より前なので出ない。`DialogEntryTests` と同じ）。Clipboard は名前付きのペーストボードだけ。`tearDown` は閉じる形に戻し、このクラスの後もそのまま残る。記録の物はテストの物が持ち続ける。

### 13.3 12.1・第 1 部 6 章・12.2 の行

| 行 | どこで | 中身 |
|---|---|---|
| 第 1 部 6 章「main を待たない」・12.1「main を待たない」 | `testNoFunctionWaitsForTheMainThread` | **134 関数すべて**を、main を止めた状態（テストの本体が main で、別のスレッドを期限 5 秒で待つ）で別のスレッドから呼ぶ。どれも期限内に期待の値で戻り（`ntk_notification_install` は `WRONG_THREAD`、ほかは `NONE` か同期の読み取り）、呼び出しの中では何も来ない。受け付ける 40 個（完了つきの非同期の 38 関数と、受け付けと同じ呼び出しの中で取り消す `ntk_dialog_cancel`・`ntk_clipboard_cancel_load`）は、main が動いた後に完了 1 回、`release` 1 回が main で来る（`finished`）。受け手の 5 個（追加と解除を同じ呼び出しの中で。`_listener_remove` の 2 つを含む）は `release` だけが main で 1 回。残りの 89 個（`ntk_notification_install` と、ビルダー・読み取り・解放など同期の 88 個）は後から何も来ない。読み取りと解放は `make*` で作った本物のハンドルに対して呼ぶ |
| 表が 134 関数を網羅すること | `testTheTableIsEveryFunction` | 表の名前が 134 個、重複なし、どれも `dlsym(RTLD_DEFAULT, …)` で引ける公開の関数。2a の照合が H = E = S を保つので、134 個の別々の公開の関数ならヘッダーの全関数（名前と呼び出しの一致は目で見た） |
| 第 1 部 6 章「スレッド」（8 スレッド × 25 回） | `testEightThreadsTimesTwentyFiveCalls` | main を止めた状態で 8 スレッドが 25 回ずつ、8 種類（Dialog の表示と取り消し、Clipboard の読み込み、変更の確かめ、通知の表示、予約の一覧、Share、通知の受け手の追加と解除、Clipboard の受け手の追加と解除）を同時に呼ぶ。200 件すべて `NONE` で戻り、呼び出しの中では何も来ない。完了つきの 150 件は完了 1 回と `release` 1 回が main で、受け手の 50 件は `release` 1 回が main で。要求の ID（Dialog と読み込みの 50 件）は重複しない |
| 5.7「main 以外の取り消しと、main の完了が重なる」 | `testCancelsFromEightThreadsAgainstTheMainThreadsCompletions` | 名前付きのペーストボードに書いた本文の読み込みを main から 200 件受け付け、8 スレッドが 25 件ずつ取り消す間に main が読み込みを進める。どれも完了は 1 回（`NONE` と本文、または `CANCELED` とハンドル `NULL`）で `release` 1 回。取り消しが先に勝ったものが 1 件以上ある |
| 第 1 部 6 章「競合を決まった順で再現する」 | `testADeliveryQueuedBeforeARemovalOffTheMainThreadIsNotDelivered` | C の関数で: 唯一の登録を入れた後、main を止めたまま、配送を積む → 別のスレッドから解除 → もう 1 つ配送を積む → main を放す。外した登録には 2 つとも届かず（配る直前の状態が `CANCEL_REQUESTED`）、`release` は main で 1 回。2 つは保たれ、次の登録に順に届く |
| 5.7 の解除と配送の競合 | `testRemovalOffTheMainThreadAgainstDeliveriesThroughC` | `EventLedgerTests` の 200 回の競合を C の関数（`ntk_notification_add_interaction_listener`、`ntk_notification_listener_remove`）と受け口の `receive` で。`release` は main で 1 回、`release` の後は届かず、届いたものは順に先頭から、届かなかったものは次の登録に順に届く |
| 12.2「通知のイベント」`DISMISS` | UI テスト `testClearingTheNotificationReachesCAsDismiss` | 起動の中で受け手を登録し、`CUSTOM_DISMISS_ACTION` の category の通知を出し、ホームに出て、バナーが消えるのを待ち、通知センターを上から引き出し、セルを払って「消去」を押す。C の受け手に `kind=2`、`action=com.apple.UNNotificationDismissActionIdentifier`、category・userInfo・`launch=0` で 1 回だけ届いた |
| 12.2「通知のイベント」`openSettingsFor` | UI テスト `testTheSettingsLinkReachesCAsASettingsRequest`（`CApiFreshInstallUITests`。アプリを消した直後） | 未決の状態から `PROVIDES_APP_SETTINGS` 付きで求めて許可し `granted=1`。26.2 では設定の App の「Apps」→ アプリ →「Notifications」→「IosLibraryCApiUITestApp Notification Settings」を押すと、起動の中で登録した設定の受け手に `settings id=NULL` が 1 回だけ届き、操作のイベントは来ない |
| 作業記録 7.7「ダイアログを出している間の取り消し」 | UI テスト `testALoadCancelledWhileThePasteAlertIsUp` | 13.1 の 6 |
| TB-10 の完了の条件の照合 | `check_c_abi_contract_ios.py` | `NOT_IMPLEMENTED_YET` は空のまま（TB-9 で空にした）。`entries` は 134 of 134。`--require-complete` でも通る。第 1 部 5.5 の H = E がそのまま成り立つ（`complete` が OK） |

テストは 468 → 474 件（`ThreadContractTests` 6）。UI テストは 55 → 58 件（`CApiRoundTripUITests` 2、`CApiFreshInstallUITests` 1）。

### 13.4 測ったこと（シミュレーター。`scripts/test_ios.sh` の外で `test-without-building` を 1 件ずつ。各回の前に `pgrep -x Simulator` で Simulator.app が閉じていることを確かめた）

| 何を | どこで | 結果 |
|---|---|---|
| `DISMISS`（通知センターのセルの「消去」） | iPhone 17 Pro / 26.2 | 最初の形（バナーが消えるのを待つ → 画面の上の中央から 0.7 まで引き下ろす → `ListCell` のセルを `swipeLeft` →「Clear」を押す）で通った。C の受け手に `kind=2` が 1 回 |
| 同 | iPhone 16 / 18.3 | 同じ形で通った |
| 同 | iPad Pro 11-inch (M4) / 18.3（日本語） | `swipeLeft` の後にセルが無くなり、「消去」が出ずに落ちた（払いが表紙の画面の別のページへ移したか、払い切ったかは確かめていない）。調べのコード（自分の通知の行の近くの要素だけを出す。測った後に消した。`PROBE` が `ios/IosLibraryCApi*` に無いことを `grep` で確かめた）で、**セルの右寄り（0.9）から中ほど（0.55）への短いドラッグで「オプション」と「消去」（`swipe-action-button-identifier`）が出る**ことを確かめ、その形で通った |
| `openSettingsFor`（設定の App のリンク） | iPhone 17 Pro / 26.2（新しく入れたアプリ） | 「Apps」→「IosLibraryCApiUITestApp」→ `NOTIFICATIONS` →「IosLibraryCApiUITestApp Notification Settings」で、アプリが前に来て設定の受け手に `settings id=NULL` が 1 回。18.3 では辿っていない（13.1 の 4） |
| 読み込みの取り消し（貼り付けのダイアログの間） | 3 台 | どれも `CANCELED` の 1 回だけ。**取り消しの後もダイアログは残った**（3 台とも `up`。26.2 は最後の検証の `--capi-ui` のログで確かめた） |

### 13.5 壊して確かめたこと（使い捨ての写し。iPhone 16 / 18.3。`ThreadContractTests` だけ）

7 個。最後の検証の前に流した。写しは最後のソースと同じ（流した後に `diff -rq` で差なし）。まず変異なしの写しで 6/6 が通ることを確かめた（M0）。**7 個とも落ちた。クラッシュは 0 件**（テストのホストのクラッシュレポートは出ていない）。M3 と M6 は最初の形が組めなかった（M3 は `import` が無いファイル、M6 は main actor の関数を別のスレッドから呼んだ）ので、組める形に直して流し直した。

| # | 変異 | 落ちたテスト |
|---|---|---|
| M1 | `ntk_notification_remove_async` が main 以外では `DispatchQueue.main.sync` で main を待つ | `testNoFunctionWaitsForTheMainThread`（`ntk_notification_remove_async did not return in time`） |
| M2 | `ntk_share_content_async` が main 以外では main に積んだブロックをセマフォで待つ | `testNoFunctionWaitsForTheMainThread`、`testEightThreadsTimesTwentyFiveCalls`（25 秒で戻らない） |
| M3 | 読み取りの `ntk_dialog_result_button` が main 以外では main を待つ | `testNoFunctionWaitsForTheMainThread`（`ntk_dialog_result_button did not return in time`） |
| M4 | 受け付けた `ntk_notification_set_badge_count_async` が完了しない | `testNoFunctionWaitsForTheMainThread`（完了と `release` が来ない） |
| M5 | 帳簿が解除を頼まれた登録（`CANCEL_REQUESTED`）にも配る | `testADeliveryQueuedBeforeARemovalOffTheMainThreadIsNotDelivered`（200 回の競合のテストは落ちない: 解除の後に配られたものも「先頭から順に」に収まるため。決まった順の方が見つける） |
| M6 | main 以外からの受け手の解除が、外すことも `release` もしない | `testNoFunctionWaitsForTheMainThread`、`testEightThreadsTimesTwentyFiveCalls`、`testADeliveryQueuedBeforeARemovalOffTheMainThreadIsNotDelivered`、`testRemovalOffTheMainThreadAgainstDeliveriesThroughC` |
| M7 | main 以外からの `ntk_clipboard_cancel_load` が何もしない | `testCancelsFromEightThreadsAgainstTheMainThreadsCompletions`（取り消しが 1 件も勝たない） |

UI テストの 3 件は変異にしていない（アプリの行と UI テストの中なので、13.4 の測りと 3 台の `--capi-ui` で確かめた）。`Operations.manager` の配線（13 操作が本物の口を呼ぶこと）は単体テストでは偽物に置き換わるので、`--capi-ui` の通知の行（`removeNow`、`delivered`、`badge`、`registerCategory` など）と、今回の `requestPermissionWithAppSettings` が受け持つ。

### 13.6 コマンドと結果（最後のソース）

11:41〜13:01 に下の順で続けて流し、シミュレーターの仕事は重ねていない（変異は 11:30〜11:41 に、検証の前に流した）。各実行の前（スクリプトの中）と後に `pgrep -x Simulator` で Simulator.app が閉じていることを確かめた。使い終えたシミュレーターは `xcrun simctl shutdown` した。ソースのハッシュ（`git status --short -uall -- ios scripts | cut -c4- | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-12`）は**流す前も後も `e5f7aa4de844`**。TB-10 の前は TB-9 のコミット `356c8c71`。**流した後に変えたのはこの記録だけ。**

```
xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -only-testing:IosLibraryCApiTests [-enableThreadSanitizer YES | -enableAddressSanitizer YES]
scripts/test_ios.sh --udid <UDID> --capi-ui
```

| 実行 | 結果 |
|---|---|
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2） | 474/474 |
| 同（iPhone 16 / 18.3） | 474/474 |
| 同 TSan（iPhone 17 Pro / 26.2） | 474/474。報告 0 件 |
| 同 ASan（iPhone 17 Pro / 26.2） | 474/474。報告 0 件 |
| `--capi-ui`（iPhone 17 Pro / 26.2。Xcode 26.6） | 58/58。rc 0（`20261107-114953-iPhone_17_Pro-26.2`） |
| 同（iPhone 16 / 18.3） | 1 回目は `CApiFreshInstallUITests` の 3 件が通り、`CApiRoundTripUITests` はテストのランナーが起動で落ちて 1 件も流れなかった（`Failed to create a bundle instance …`。12.3 の iPad の 1 回目と同じシミュレーターの側のエラー）。**推奨案で 1 回だけ流し直し、58/58。rc 0**（`20261107-123727-iPhone_16-18.3.1`） |
| 同（iPad Pro 11-inch (M4) / 18.3、日本語） | 58/58。rc 0（`20261107-121648-iPad_Pro_11-inch_(M4)-18.3.1`）。流し直していない |
| framework の Release（`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`）`--library --architectures arm64` | `OK symbols`（134 symbols、1 architectures）。capi の警告 0 |
| framework の Release（`generic/platform=iOS Simulator`、`ARCHS='arm64 x86_64'`）`--library --architectures arm64,x86_64` | `OK symbols`（134 symbols、2 architectures）。capi の警告 0 |
| `python3 scripts/check_c_abi_contract_ios.py` | rc 0。OK 28、FAIL 0、SKIP 1（`symbols`。`--library` なし）。`entries` は 134 of 134、0 not implemented yet |
| 同 `--require-complete` | rc 0、FAIL 0。`OK complete: every function of the headers has its entry` |
| `test_check_c_abi_contract_ios.py` | Ran 280 tests、OK |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 2 部、第 1 部） | どちらも rc 0、FAIL 0 |

単体テストのビルドの警告: 新しく足したものは 0（`ThreadContractTests` と `NotificationOperationTests` の main actor の 2 件は `MainActor.assumeIsolated` で直した）。前からある 3 件（`NotificationEventTests.swift:130`、`NotificationOperationTests.swift:59` の 2 件。`setUpWithError` から main actor の静的な値に触れる）は変えていない。検証の間に出たクラッシュレポートは、シミュレーターと Mac の `AccessibilityControlsExtension`、`maild`、`remindd` のもので、自分のプロセスではないので消していない。変異でもテストのホストのクラッシュレポートは出なかった。

### 13.7 確かめられていないこと

- **実機では何も流していない**（指示のとおり。`xcrun devicectl` も使っていない）。15.2 の実機の ASan と smoke は DoD の区切りで、持ち主の許可が要る
- `openSettingsFor` の設定の App を辿る操作は iOS 26.2（英語）だけ。18.3 と日本語の iPad では要求（`granted=1`）までしか見ていない（13.1 の 4）
- iPad の `swipeLeft` でセルが消えた理由（表紙の画面のページの移動か、払い切りか）。その時に `DISMISS` が届いたかも見ていない
- `DISMISS` は「消去」の 1 つの経路だけ。通知センターの「すべて消去」、ロック画面からの消去、バナーを上へ払う操作は測っていない
- 単体テストの「main を待たない」は、期限 5 秒の間に戻るかで見る。待つ時間に上限のある待ち（数秒で諦める待ち）が入っても、5 秒より短ければ見つけない
- 8 スレッド × 25 回は 1 回の実行で、繰り返していない。競合の 200 回（解除と配送）と 200 件（取り消しと完了）は、それぞれ 1 回の実行
- 名前と呼び出しの一致（表の `name` と、その closure が呼ぶ関数）は目で見た。`testTheTableIsEveryFunction` は名前の側だけを照らす
- Mac のクリップボードとの同期は引き続き測っていない（6.6）。Simulator.app は開かず、Mac の `pbcopy`・`pbpaste` と `simctl pbsync` は使っていない。UI テストのランナーは前と同じくシミュレーターの general に書く（今回の `testALoadCancelledWhileThePasteAlertIsUp` も）

### 13.8 持ち主の判断待ち

1. 13.1 の 1（`DISMISS` と `openSettingsFor` の UI テストを TB-10 に入れた）。11.9 の (2)
2. 13.1 の 2（ため置きのあふれた数の記録・ログ。入れていない）。11.9 の (1)
3. 13.1 の 3（受け口に `Operations` を足した。製品のコードの変更）
4. 13.1 の 4（`openSettingsFor` は 26.2 だけ辿り、ほかの OS は要求で終える形。ランナーが skip を数えられれば `XCTSkip` にする手もあるが、ランナーは変えていない）
5. 13.1 の 5・6（`DISMISS` を 3 台で流す、貼り付けのダイアログの間の取り消しを UI テストにした）

### 13.9 時間

11:04〜13:03（約 2 時間）。うち変異が約 11 分（11:30〜11:41。M3 と M6 の組み直しを含む）、最後の検証が約 80 分（11:41〜13:01。`--capi-ui` は 1 回約 20 分で、iPhone 16 の流し直しを含めて 4 回）。目標の 13:45 の中。

### 13.10 レビューと、メインのセッションの直し

13.6 のソース（`e5f7aa4de844`）を、Claude のサブエージェントと Codex に読むだけで見てもらった（2026-11-07 13:03〜13:10）。どちらも A は 0。直しはメインのセッションが、指摘をコードで確かめてから入れた。**持ち主はまだ読んでいない。**

| 指摘 | 確かめたこと | 扱い |
|---|---|---|
| Codex B1 / Claude C-1 | 取り消しのスレッドは、main が読み込みを始める前に 200 件すべてを取り消せた。その場合も `canceled > 0` は通り、競合は起きていない | 直した: 取り消しのスレッドは、読み込みより先に main に積んだ合図を待ってから始める。`NONE` と `CANCELED` の件数を出力する |
| Codex B2 | 20 秒で待ちを抜けた後、取り消しのスレッドが終わったかを見ていなかった | 直した: 終わったことを確かめる |
| Codex B3 / Claude B-1 | 判定が `majorVersion == 26` だけで、26.2 に限っていなかった | 直した: 26.2 に限り、ほかの OS では辿らなかったことを 1 行出力する |
| Claude B-2 | 第 2 部 12.1「main を待たない」の行だけ、持ち主の確認待ちの印が無かった | 直した |
| Claude B-3 | 13.1 の 6 の括弧の中は誤り。第 1 部 5.7 の「完了」の行（`CANCEL_REQUESTED` なら箱を閉じたかに関わらず `CANCELED`） | 直した |
| Claude C-2 | 8×25 の各スレッドは作られた順にすぐ走り、重ならないことがある | 直した: 8 スレッドが揃ってから一斉に始める |
| Codex C / Claude C-4 | 表の網羅のテストが作ったハンドルを解放しない | 直さない。テストの中だけの漏れ |
| Claude C-3 | 「待たない」の期限は 5 秒で、それより短く待つ形は見つけない | 直さない（13.7 に書いた） |
| Claude C-5 | `FailClosed` が `ThreadContractTests.swift` にあり、`NotificationOperationTests` から使う。tearDown の戻し方が揃っていない | 直さない。動きは正しい。補助のファイルへの移動は後で |
| Claude C-6〜C-9 | 設定を辿る補助にシミュレーターだけの守りが無い（ターゲットがシミュレーター専用なので今は害なし）、クラスのコメント、`NotificationEventTests` のコメントが古い、11.9 と 13.3 の参照 | 直さない。動きに関わらない |

直しの後に流したものは下に書く。

**取り消しと完了の競合の直しは 1 回で済まなかった**: 合図を待ってから始める形にしても、`canceled=200 loaded=0` のままだった（17 Pro、16、TSan の 3 回とも）。読み込みの完了は main が積んだ後もしばらく来ないため、取り消しが 25 ms ほどで全部先に着いていた。1 回ごとの間を 2 ms にしても 200/0 で、10 ms（1 スレッドで約 250 ms）にして初めて両方が出た。両方が出る割合は機械の速さで変わるので、テストは `canceled > 0` だけを確かめ、件数は出力する（`loaded > 0` は確かめない）。

**直しの後の結果**（メインのセッション。13:12〜13:44。1 台ずつ順に。各実行の前に `pgrep -x Simulator` で閉じていることを確かめた）

| 実行 | ソース | 結果 |
|---|---|---|
| `IosLibraryCApiTests`（17 Pro / 26.2） | 最後（`2c0525e90a59`） | 474/474。canceled=124 loaded=76 |
| 同（16 / 18.3） | 最後 | 474/474。canceled=156 loaded=44 |
| 同 TSan（17 Pro） | 最後 | 474/474、報告 0。canceled=138 loaded=62 |
| `--capi-ui`（17 Pro） | 間を 10 ms にする前（`fb83f51ed667`。違いは単体テストの 1 行だけ） | 58/58 |
| 照合 `--require-complete`、設計書の照合（第 1 部・第 2 部） | 最後 | rc 0、FAIL 0 |

流し直していないもの: ASan、`--capi-ui` の iPhone 16 と iPad（UI 側の変更は 26.2 の判定を狭めて 1 行出すだけで、18.3 では前も辿らずに終えていた）、変異。

## 14. TB-11

第 2 部 13 章の TB-11（dist、`check_ios_dist.py`、smoke。第 1 部 C-5）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。**判断の要るところは、メインのセッションが利用者の指示のもとで推奨案で決めたもの。持ち主はまだ読んでいない。**

### 14.1 決めたこと（推奨案。持ち主の確認待ち）

| # | 決定 | 理由 |
|---|---|---|
| 1 | **出力は `dist/` に作らない**。ビルドのスクリプトに `--output-dir <folder>`（2 つの xcframework と `include/NativeToolkitC/` をそこへ）、`--build-dir <folder>`（中間の archive）、`--keep-project-versions`（`project.pbxproj` の `MARKETING_VERSION`・`CURRENT_PROJECT_VERSION` を書かず、ビルド番号も上げない）を足し、検証はすべてスクラッチに出した | 版と `dist/<release>/` を決めるのは 2b の締め（利用者）。今のスクリプトは Release で pbxproj を書き換えるので、旗なしで流すと `ios/` が変わる |
| 2 | capi の xcframework は**同じ実行で組んだ `IosLibrary` の archive に対して組む**（`FRAMEWORK_SEARCH_PATHS`。`UnityIosPlugin` と同じ形）。capi のプロジェクトだけを組む | 配る `IosLibrary`（library evolution）と同じものにリンクするため。workspace の暗黙の依存だと、その場で組んだ別の `IosLibrary` を見る |
| 3 | **capi は Release だけ**: `-m IosLibraryCApi` に `--configuration debug` を渡すとスクリプトが止める。`BUILD_LIBRARY_FOR_DISTRIBUTION=YES` を capi には渡さない（プロジェクトの `NO` のまま。P1-19） | TB-11 の行（Debug には `.swiftmodule` と `_$s14IosLibraryCApi*` が入る。14.5 の M1 で確かめた） |
| 4 | **すべてのモジュールを `CODE_SIGNING_ALLOWED=NO` で archive する**（`IosLibrary` と、もう組まない `UnityIosPlugin` も） | D-18 の A。今の `IosLibrary` のプロジェクトは Automatic の署名で、旗なしの実機の archive は個人の証明書で署名する |
| 5 | `include/NativeToolkitC/` は、capi の xcframework の隣にスクリプトが木のヘッダーを写す | README 3 章の配布物の表。`check_ios_dist.py` が木・`include/`・framework の `Headers/` を照らす |
| 6 | `check_ios_dist.py` は README 7.3 の表の 10 項目に、**`modules`（framework の `module.modulemap` = 木）、`IosLibrary` の swiftinterface が全アーキテクチャにあること、`LC_BUILD_VERSION` の platform と minos、版 = 木の `Common.h` の `NTK_VERSION_*`、`_tlv_atexit`（Darwin の `thread_local` の後始末）、framework に `_CodeSignature/` が無いこと**を足した。README 7.3 の表は変えていない | どれも配布物だけで決まり、壊れても今の 10 項目では見えない形があった（`_CodeSignature/` は封をした framework、minos は `Info.plist` と食い違いうる） |
| 7 | プライバシーマニフェストの「宣言した理由とソースが使う API の一致」は、**Swift の API の設計書 8.8.1 の棚卸しの 5 種を正規表現で探し（コメントを除く）、宣言した種類の集合と比べる**。理由の値（C617.1）はソースから決まらないので、空でないことだけを見る。capi は使う API が無く、マニフェストを持たない（持つなら使う種類と一致を求める） | D-18 の「`IosLibraryCApi` は理由の申告が要る API を使わない見込みで、2b で確かめる」。0 件だった |
| 8 | **第 1 部 5.5 の「C のソースの `ntk_`」は `check_c_abi_contract_ios.py` の新しい `csources` で照らす**（`-Swift.h` と `.swiftmodule` は配布物の照合）。C のソースがあれば、`ntk_` の関数を定義せず、ヘッダーに無い `ntk_` の名前を使わない | ソースだけで照らせ、ビルドの前に流せる。capi は今 C のソースを持たない（0 件で OK） |
| 9 | smoke の形（第 2 部 12.4 に書いた）: `scripts/run_ios_capi_smoke.sh` が `ios/IosLibraryCApiSmoke` と 2 つの xcframework だけを新しい作業フォルダーに写して組む。Clipboard は**名前付きのペーストボード**、Dialog は**表示の 1.5 秒後に `ntk_dialog_cancel` で `CANCELED` の完了まで**。各要求の完了と `release` が main で 1 回ずつ来ることも数える。アプリは結果を `SMOKE ...` の行に書いて自分で終わり、スクリプトは `simctl launch --console-pty` で読む（1a の雛形と同じ読み方） | 「配布物だけで組む」を、リポジトリに届かない場所で組むことで示す。general のペーストボードを使わないので、実機の区切りでも私物のクリップボードを上書きしない。Dialog の完了を人の操作なしで通す |
| 10 | smoke のプロジェクトは `xcodeproj` の gem（1.25.1）で作った（`objectVersion = 63`。gem は 77 を知らない）。生成器はコミットしていない。シミュレーター向けは `CODE_SIGN_IDENTITY = "-"`（ad-hoc。鍵を使わない）、`DEVELOPMENT_TEAM` は空、実機向けはスクリプトが `CODE_SIGNING_ALLOWED=NO` を渡す。`GCC_TREAT_WARNINGS_AS_ERRORS = YES` と `-Wall -Wextra` で、利用者の側でヘッダーが警告を出さないことも見る | Team ID をファイルに書かない。個人の証明書に触れない |
| 11 | smoke の xcframework は作業フォルダーの `Frameworks/IosLibrary.xcframework`・`IosLibraryCApi.xcframework`（決まった名前）に置く。リポジトリの `ios/IosLibraryCApiSmoke/Frameworks/` は `.gitignore` で外した | プロジェクトが版の付いた名前を持たないように |
| 12 | README 7.4 の x86_64 の行（iOS 18.3 のシミュレーターで Rosetta で smoke を流す）を、`--archs x86_64` で 1 回試した（14.4） | 指示の範囲の外だが、スクリプトの旗 1 つで足りた |

### 14.2 足したもの・変えたもの

| 区分 | ファイル | 中身 |
|---|---|---|
| ビルド | `scripts/build_ios_library_xcframework.sh` | 14.1 の 1〜5 |
| 照合 | `scripts/check_ios_dist.py`（新規） | 14.1 の 6・7。項目は `files`、`slices`、`symbols`、`swift`、`modules`、`dependencies`、`exit`、`install`、`version`、`privacy`、`signature`、`headers`（18 行）。`symbols` は `check_c_abi_contract_ios.check_symbols` を使う |
| 自己テスト | `scripts/tests/test_check_ios_dist.py`（新規） | 組んだ配布物（`NTK_IOS_DIST`、無ければ `dist/<release>/ios/`）を一時フォルダーに写し、1 つ壊して、その項目だけが落ちることを確かめる。codesign の出力の読み方と、理由の要る API の見つけ方は純粋な関数のテスト（署名をしない） |
| 照合 | `scripts/check_c_abi_contract_ios.py` | `csources`（14.1 の 8）。docstring の「Not checked here」を直した |
| 自己テスト | `scripts/tests/test_check_c_abi_contract_ios.py` | `csources` の 5 件 |
| smoke | `ios/IosLibraryCApiSmoke/`（新規）: `IosLibraryCApiSmoke.xcodeproj`、`IosLibraryCApiSmoke/main.m`、`Smoke.c`、`Smoke.h`、`.gitignore` | 14.1 の 9〜11。C の側は `#include <IosLibraryCApi/NativeToolkitC/...>`、Objective-C の側は `@import IosLibraryCApi;` でヘッダーを読む |
| smoke | `scripts/run_ios_capi_smoke.sh`（新規） | 組む・アプリの中身を照らす（埋め込みは 2 つの framework だけ、アプリ自身は Swift の dylib を要さず `IosLibrary` の Swift のシンボルを import しない）・`--udid` で流す・`--device-build` で実機向けに署名なしで組む（入れない） |
| 文書 | `scripts/README.md` | 14.2 のスクリプトの説明、`run_` の接頭辞、自己テストの件数 |
| 設計書 | 第 2 部 12.4、13 章の TB-11 の行 | 14.1 の 8・9 の印 |

公開ヘッダー、`ios/IosLibrary`、`ios/IosLibraryCApi` のソースとプロジェクト、信頼する UI テストのファイル、`scripts/ios_ui_runner.py`、README、第 1 部は変えていない。`android/.idea` には触れていない。`dist/` には何も作っていない。

### 14.3 12.4・15.2・TB-11 の完了の条件

| 条件 | どこで | 結果（14.4） |
|---|---|---|
| 12.4: 配布物の 2 つの xcframework だけで組む C / Objective-C のアプリ | `ios/IosLibraryCApiSmoke`、`run_ios_capi_smoke.sh`（作業フォルダーに smoke の源と 2 つの xcframework だけを写して組む） | Swift のコードを持たず、埋め込みは `IosLibrary.framework`・`IosLibraryCApi.framework` だけ、アプリ自身は `libswift*` を要さない |
| 12.4: Xcode 26.6 と 26.3 の両方で組める | 同 | シミュレーター（arm64・x86_64）と実機向け（arm64、署名なし）を両方の Xcode で。警告 0 |
| 12.4: `ntk_notification_install`・Clipboard の書き込みと読み取り・Dialog（完了まで） | 同 `--udid`（シミュレーター） | iPhone 17 Pro / 26.2 と iPad Pro 11-inch (M4) / 18.3 で、両方の Xcode で通った。各要求の完了と `release` が main で 1 回ずつ |
| 15.2: README 7.3 の配布物の照合が通る | `check_ios_dist.py --dist` | 18 項目 OK |
| TB-11: 3 つのスライスで `--library` が `--architectures` と `--require-complete` つきで通る | `check_c_abi_contract_ios.py`。実機 arm64、シミュレーターの fat（arm64,x86_64）と、`lipo -thin` で分けた arm64・x86_64 の 4 回 | 4 回とも rc 0、134 symbols |
| TB-11: 第 1 部 5.5 の残り（`-Swift.h`、`.swiftmodule`、C のソースの `ntk_`） | `check_ios_dist.py` の `swift`、`check_c_abi_contract_ios.py` の `csources` | どちらも OK。壊すと落ちる（自己テストと 14.5） |
| TB-11: capi の xcframework は Release だけ | ビルドのスクリプト | `-m IosLibraryCApi -c debug` は止まる。Debug の capi を混ぜると `swift` と `symbols` が落ちる（14.5 の M1） |

### 14.4 コマンドと結果（最後のソース）

14:13〜14:29 に下の順で 1 つずつ流し、重ねていない（スクラッチのスクリプト 1 本で順に）。シミュレーターの各実行の前に `pgrep -x Simulator` で Simulator.app が閉じていることを確かめた（smoke はスクリプトの中でも確かめる）。Simulator.app は開いていない。Mac の `pbcopy`・`pbpaste` と `simctl pbsync` は使っていない（smoke のクリップボードは名前付きのペーストボードだけ）。使い終えたシミュレーターは停止に戻した（smoke のスクリプトは自分で起動したものを `shutdown` する）。出力はすべてスクラッチで、`dist/` と `ios/Build/` には何も作っていない。ソースのハッシュ（`git status --short -uall -- ios scripts | cut -c4- | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-12`）は**流す前も後も `03b8a145a9cd`**（TB-11 の前は `e3b0c44298fc`。TB-10 のコミット `42d0ac54` のまま）。`project.pbxproj` は書き換わっていない。**流した後に変えたのはこの記録だけ。**

```
DEVELOPER_DIR=<Xcode 26.6> scripts/build_ios_library_xcframework.sh -m IosLibrary -m IosLibraryCApi -v 2.0.0 \
  --output-dir <scratch>/dist2 --build-dir <scratch>/build2 --keep-project-versions
python3 scripts/check_ios_dist.py --dist <scratch>/dist2
NTK_IOS_DIST=<scratch>/dist2 NTK_REQUIRE_DIST_FIXTURE=1 python3 -m unittest scripts/tests/test_check_ios_dist.py
python3 scripts/check_c_abi_contract_ios.py --require-compile --require-complete --library <binary> --architectures <archs>
DEVELOPER_DIR=<Xcode 26.6 | 26.3> scripts/run_ios_capi_smoke.sh --dist <scratch>/dist2 --work <new folder> --udid <UDID> --device-build
xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryCApi -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -only-testing:IosLibraryCApiTests
```

| 実行 | 結果 |
|---|---|
| ビルド（Xcode 26.6。2 つの xcframework と `include/NativeToolkitC/`） | rc 0。約 1 分（前の組み立てが残っていた）。capi の警告 0 |
| 同 `-m IosLibraryCApi -c debug` | rc 1（`Error: IosLibraryCApi is built in release only.`） |
| `check_ios_dist.py --dist` | rc 0。OK 18、FAIL 0 |
| `test_check_ios_dist.py` | Ran 31 tests、OK |
| 照合 `--library`（`ios-arm64`、`--architectures arm64`） | rc 0。OK 30、FAIL 0、SKIP 0。134 symbols、1 architectures |
| 同（`ios-arm64_x86_64-simulator` の fat、`arm64,x86_64`） | rc 0。OK 30。134 symbols、2 architectures |
| 同（`lipo -thin` の arm64、`arm64`） | rc 0。OK 30。134 symbols |
| 同（`lipo -thin` の x86_64、`x86_64`） | rc 0。OK 30。134 symbols |
| 照合（旗なし） | rc 0。OK 29、FAIL 0、SKIP 1（`symbols`。`--library` なし）。`csources` は 0 C sources で OK |
| `test_check_c_abi_contract_ios.py` | Ran 285 tests、OK（280 + `csources` の 5） |
| smoke（Xcode 26.6、iPhone 17 Pro / 26.2） | rc 0。9 PASS、0 FAIL（シミュレーターと実機向けの組み立て・中身、16 段階の実行） |
| smoke（Xcode 26.6、iPad Pro 11-inch (M4) / 18.3、日本語） | rc 0。9 PASS、0 FAIL |
| smoke（Xcode 26.3、iPhone 17 Pro / 26.2） | rc 0。9 PASS、0 FAIL |
| smoke（Xcode 26.3、iPad Pro 11-inch (M4) / 18.3、日本語） | rc 0。9 PASS、0 FAIL |
| `IosLibraryCApiTests`（iPhone 17 Pro / 26.2、Xcode 26.6） | 474/474 |
| `IosLibrary` だけをビルドのスクリプトで（今の使い方。`-m IosLibrary`） | rc 0。`ios-native-toolkit-2.0.0.xcframework` |
| `scripts/tests/test_ios_ui_runner.py` | Ran 210 tests、OK |
| `check_design_consistency.py`（第 1 部、第 2 部） | どちらも rc 0、FAIL 0 |
| `python3 -m unittest discover -s scripts/tests`（`NTK_IOS_DIST` つき） | Ran 781 tests、OK |

最後の検証の前（13:51〜14:06）に流したもの: 同じ手順の 1 回目（`dist1`）、smoke の x86_64 だけ（`--archs x86_64`、iPhone 16 / 18.3、Xcode 26.6。16 段階 PASS。README 7.4 の x86_64 の行）、14.5 の変異。

### 14.5 壊して確かめたこと（使い捨ての写し）

**自己テスト**（`test_check_ios_dist.py`）: 組んだ配布物の写しを 1 つずつ壊す 26 件と、codesign の出力・理由の要る API の見つけ方の純粋な関数の 5 件（レビューの直しの後は 32 件と 10 件。14.9）。どれも名前の項目だけが落ちる（`assert_only_among`。x86_64 を抜いたときなど、続いて落ちてよい項目を名前で挙げる）。最初の形では、x86_64 を抜くとアーキテクチャごとの項目がすべて「その arch が無い」で落ちたので、アーキテクチャごとの項目はバイナリが持つものを回し、集合の食い違いは `slices` だけが言う形に直した。

**実際に誤った設定で組んだもの**（14:04〜14:06。Xcode 26.6 で capi を archive し、`dist1` の写しのスライスと差し替えて `check_ios_dist.py --dist` を流した）。6 個とも狙った項目で落ちた（rc 1）。

| # | 変異 | 落ちた項目 |
|---|---|---|
| M1 | capi を Debug で archive（`ios-arm64`） | `symbols`（`_$s14IosLibraryCApi…` を出す）、`swift`（`Modules/IosLibraryCApi.swiftmodule`） |
| M2 | Release で `EXPORTED_SYMBOLS_FILE=`（公開の一覧を外した） | `symbols`（`_IosLibraryCApiVersionNumber`、`_IosLibraryCApiVersionString`。1a 入口 4.1 と同じ） |
| M3 | Release で `SWIFT_INSTALL_MODULE=YES`（第 1 部 5.5 の「戻した」） | `swift` |
| M4 | シミュレーターを `ARCHS=arm64` で archive | `slices`、`symbols`（x86_64 が無い） |
| M5 | `IosLibrary` を 1.x の `dist/1.9.0/ios/ios-native-toolkit-1.3.0.xcframework` に差し替え（名前は 2.0.0） | `version`（1.3.0、`ios.library.IosLibrary`）、`privacy`（マニフェストが無い）、`signature`（署名と `_CodeSignature/` がある。名前と Team ID は出力に出さない） |
| M6 | `include/NativeToolkitC/` を Android のヘッダーに差し替え | `headers` |

`SWIFT_INSTALL_OBJC_HEADER=YES` でも組んでみたが、**ビルドそのものが止まった**（モジュールの検証が `IosLibraryCApi-Swift.h` を module map に見つけられない）ので、配布物にならない。`-Swift.h` が入った形は自己テストの `test_a_swift_header_in_the_capi` が受け持つ。

`csources` は自己テストの 5 件（ヘッダーの関数を C で定義、内部の `ntk_` の変数・関数・マクロ、フォルダーの外の `.m`、`ntkc_` の名前で通ること）。smoke そのものを壊す変異は流していない（14.6）。

### 14.6 確かめられていないこと

- **実機では何も流していない**（指示のとおり。`xcrun devicectl` も使っていない）。smoke の実機向けは署名なしで組んだだけで、入れていない。15.2 の実機の smoke は 2b の DoD の区切りで、持ち主の許可を得て流す（そのときは署名が要る。`--device-build` は署名しないので、実機に入れる手順はその区切りで決める）
- smoke の Dialog は、完了が `CANCELED`（表示を求めた 1.5 秒後の取り消し）で来たことまでで、**画面に出たことは見ていない**（UI を読まない。出せなければ `NOT_FOREGROUND` か `SHOW_FAILED` で完了するので、それが来ないことは確かめた）
- smoke を壊したときに落ちること（変異）は流していない。アプリの判定は `SMOKE PASS` の行と `SMOKE RESULT PASS failures=0` で、どれかの段階が FAIL を書けばスクリプトが落ちる
- 利用者のアプリの Release のアーカイブでの署名し直し（1a-4。`unity-native-plugin` の agent）、アーカイブのプライバシーのレポート（MS-10）
- `check_ios_dist.py` の `<release>` の形（`dist/<release>/ios/` を読む）は、`dist/` に何も作っていないので流していない。流したのは `--dist` の形だけ
- ビルドのスクリプトを旗なし（リリースの形）で capi に流したとき、`IosLibraryCApi.xcodeproj` の版とビルド番号を書き換える。書き換えた後に `check_c_abi_contract_ios.py` の `settings`（Debug と Release の違い）が通るかは流していない（両方の構成に同じ値を書くので通る見込み）
- x86_64 だけの smoke（README 7.4）は、iPhone 16 / 18.3 で Xcode 26.6 の 1 回だけ（14:05。最後の検証には入れていない）
- `test_ios.sh` へのつなぎ（smoke、`--library` と `--require-compile`、`--require-complete`）は TB-12。リリースの手順（`agent-rules/workflows/release/`）に `-m IosLibraryCApi` と `check_ios_dist.py` を足すことも、ここではしていない

### 14.7 持ち主の判断待ち

1. 14.1 の 1（出力先の旗 3 つ。リリースの時は旗なしで `dist/<release>/ios/` に出し、pbxproj を書く今の動きのまま）
2. 14.1 の 4（`IosLibrary` と `UnityIosPlugin` も署名しない。1.x の `ios-native-toolkit-1.3.0.xcframework` は、包みには署名が無く、中の framework は実機のスライスが個人の証明書、シミュレーターが ad-hoc で署名されていた（D-18 の B の「今のまま」のとおり。読むだけの `codesign -dv` で種類だけを見た。14.5 の M5））
3. 14.1 の 6（README 7.3 の表に無い項目を足した。表に書き足すか）
4. 14.1 の 8（`csources` を契約の照合に置いた）
5. 14.1 の 9（smoke の Dialog を取り消しで完了させる、Clipboard を名前付きのペーストボードにする）
6. 14.1 の 10（smoke のプロジェクトを gem で作り、生成器を置かない）

### 14.8 時間

13:46〜14:31（約 45 分）。うち最後の検証が約 16 分（14:13〜14:29）、変異が約 3 分。目標の 16:30 の中。

### 14.9 レビューと直し

14.4 のソース（`03b8a145a9cd`）を Claude のサブエージェントと Codex が読んだ（2026-11-07）。**指摘はメインのセッションがコードで確かめた。持ち主はまだ読んでいない。** 直しは実装者のサブエージェントが入れた（14:42〜）。

| 指摘 | 確かめたこと | 扱い |
|---|---|---|
| Codex A | `--output-dir ios/IosLibraryCApi` だと `include/NativeToolkitC` の写し先が木の公開ヘッダーと同じになり、`rm -rf` で消す | 直した: 写し先を実パス（シンボリックリンクを解く。まだ無い部分に `.` と `..` があれば止める）にし、木のヘッダーと同じ・その中・それを含むなら止める。xcodebuild の前に 1 回、消す直前にもう 1 回。自己テスト `test_build_ios_library_xcframework.py`（7 件。写しの木で、相対・`-o`・シンボリックリンク・`..`・木を含む出力先。止まり、ヘッダーが残ること） |
| Claude B1 | `check_ios_dist.py` の f 文字列の中の同じ引用符の入れ子は 3.12 から。`/usr/bin/python3`（3.9.6）で SyntaxError | 直した。新しい・変えた `.py` 5 つを `/usr/bin/python3 -c "import ast; ..."` で読めることを確かめ、`check_ios_dist.py` と `test_check_ios_dist.py` を 3.9 で流した（14.10） |
| Claude B2 | 署名の項目を実物で壊す自己テストが無い（`_CodeSignature/` を置くだけ） | 直した: 写しのバイナリに `codesign -s - -f`（ad-hoc。鍵も証明書も使わない）。実機のスライスと、シミュレーターをリンカー以外の ad-hoc で署名し直した形。どちらも `signature` だけが落ちる |
| Codex B2 / Claude C1 | `FRAMEWORK_SEARCH_PATHS` が空白を含むパスで割れる | 直した: 値の中を `"..."` で囲む |
| Codex B3 / Claude C9 | smoke のスクリプトで `nm`・`otool`・`lipo` の失敗が「見つからない」に読める。`simctl boot` の失敗で要約が出ない | 直した: 各ツールの終了の状態を先に見る。シミュレーターの部分を関数にし、`list`・`boot`・`bootstatus`・`install` の失敗を FAIL として記録して要約まで進む |
| Codex B4 | 起動の終了の状態を `|| true` で捨てていた | 直した: 0 以外（時間切れは 142）は PASS の行があっても FAIL。`NTK_SMOKE_LAUNCH_SECONDS` で時間を短くでき、14.10 の変異で確かめた。**最初の形（`perl -e 'alarm; exec'`）は変異で効かなかった**: `simctl launch` は SIGALRM を自分で受けて状態 0 で終わる（結果の行が無いので別の枝で FAIL にはなった）。perl が子を fork して待ち、時間切れなら子を KILL して 142 で終える形に直した |
| Codex B6 | 文字列の中の API 名を使用と数え、文字列の中の `//` の後を消していた | 直した: 簡単な字句処理（`code_only`。コメント（Swift の入れ子の `/* */` を含む）と文字列・文字のリテラルの中を空白にし、文字列の補間の中はコードとして残す）。自己テスト 4 件と、照合を通す 1 件 |
| Codex B7 | 理由が空でないかだけを見ていた | 直した: 種類ごとに Apple の承認された理由（5 種の表 `APPROVED_REASONS`）の中か、配列か、文字列か、知らない種類でないか。純粋な関数のテスト 7 通りと、木と両スライスを同じに変えて理由だけを違えた 1 件 |
| Codex B8 | ヘッダーの比較が直下のファイルだけ | 直した: 相対パスで再帰的に比べ、フォルダーも数える。片方だけのサブフォルダー（ファイル入り・空）の 2 件 |
| Codex B9 / Claude C6 | `csources` が戻り値の型を前の行に書く定義を見逃す | 直した: 型と名前の間の改行を許す。自己テスト 1 件（2 つの形） |
| Codex B10 | `Smoke.c` で、誤って main 以外に来た完了・`release` が同期なしに数を書く | 直した: スレッドを先に確かめ、main 以外なら `SMOKE FAIL` を書いてその場で `_exit(1)`。数は `atomic_int` |
| Codex B11 | `NTK_IOS_DIST` を明示したのに無いと skip で全体 OK | 直した: 明示したときは無ければ失敗（未指定の skip とは別）。無い場所を指して 32 件が失敗することを確かめた |
| Claude C7 | smoke の pbxproj に gem が足した存在しない `iPhoneOS14.0.sdk` の Foundation の参照 | 直した: その参照と空の group を消した（`xcodebuild -list` で読めること、両 Xcode で組めることを確かめた） |
| Claude C8 | `read_done` が `result` の NULL を守らない | 直した |
| Claude C11 | 14.5 の「純粋な関数の 7 件」 | 直した（実際は 5 件。直しの後は 10 件） |
| Claude C3 | `-m IosLibraryCApi` だけのときは capi だけが包まれる | usage に一言書いた（動きは変えていない） |
| Codex B5 | シミュレーターの arm64 の署名なしを許している | **直さない**: README 7.3 は「ad-hoc の署名だけを許す」で、署名なしを禁じていない。C として扱う |
| Claude C2 | `--output-dir` と `-c debug` で名前に `-debug` が付かない | **直さない**: capi は Debug を拒むので、Debug は IosLibrary だけ。リリースの形（旗なし）は今のまま `-debug` を付ける |
| Claude C4 | 足した項目の壊す確かめの残り | **直さない**（今回 B2・B6〜B8 の分を足した） |
| Claude C5 | 包み（xcframework）の `_CodeSignature` を名指しで照らさない | **直さない**: 包みに署名する手順が無い |
| Claude C10 | 借りた項目（`symbols`）の名前の書き換えが文言に頼る | **直さない**: 書き換えが効かなくても行は `symbols:` で始まるので、判定と自己テストの `assert_only_among` は変わらない（文言が元の照合のものになるだけ） |
| Claude C12 | `android/.idea` の変更 | **直さない**: コミットに入れない。メインのセッションが扱う |


### 14.10 直しの後の最後の検証

15:02〜15:20 に 14.4 と同じ一式を 1 つずつ順に流した（スクラッチのスクリプト 1 本。各シミュレーターの実行の前に `pgrep -x Simulator`。Simulator.app は開いていない。3 台とも停止に戻した）。ハッシュは**流す前も後も `853adb6da871`**、`project.pbxproj` は書き換わっていない。**流した後に変えたのはこの記録だけ。** 14:49 に始めた 1 回目は、自己テストの件数を README に入れ忘れたのと、V2 で時間切れの扱いの誤り（14.9 の Codex B4 の行）が分かったので途中で止め、直してから最初から流し直した。

| 実行 | 結果 |
|---|---|
| ビルド（Xcode 26.6）、`-c debug` の capi の拒否 | rc 0、capi の警告 0。拒否は rc 1 |
| `check_ios_dist.py --dist`（3.12 と `/usr/bin/python3` 3.9.6） | どちらも rc 0、18 OK、FAIL 0 |
| `test_check_ios_dist.py`（`NTK_IOS_DIST`、`NTK_REQUIRE_DIST_FIXTURE=1`。3.12 と 3.9） | どちらも Ran 42、OK（skip 0） |
| `test_build_ios_library_xcframework.py`（3.9） | Ran 7、OK |
| 照合 `--require-compile --require-complete --library`（実機 arm64、シミュレーターの fat、thin の arm64・x86_64） | 4 回とも rc 0、30 OK、FAIL 0、SKIP 0、134 symbols |
| 照合（旗なし）、`test_check_c_abi_contract_ios.py` | rc 0、29 OK、SKIP 1。Ran 286、OK |
| smoke（Xcode 26.6 と 26.3 × iPhone 17 Pro / 26.2 と iPad Pro 11-inch (M4) / 18.3） | 4 回とも rc 0、9 PASS、0 FAIL、16 段階。実機向けの組み立ても 4 回とも通過 |
| `IosLibraryCApiTests`（17 Pro） | 474/474 |
| `IosLibrary` だけのビルド | rc 0 |
| `test_ios_ui_runner.py` | Ran 210、OK |
| 設計書の照合（第 1 部・第 2 部） | どちらも rc 0、FAIL 0 |
| `scripts/tests` 全体 | Ran 800、OK |

直しを効かせた変異（使い捨ての写し）。4 個とも rc 1 で狙ったところが落ちた。

| # | 変異 | 結果 |
|---|---|---|
| V1 | 写しの木でビルドのスクリプトを `--output-dir ios/IosLibraryCApi` で流す（Codex A） | xcodebuild の前に止まり（`[archive]` 0 行）、写しのヘッダー 5 つが残った |
| V2 | smoke の起動の時間を 1 秒にする（Codex B4） | `the launch ended with status 142` で FAIL |
| V3 | capi のソースに `"https://example.com"; ... UserDefaults.standard`（Codex B6） | `privacy`（capi）だけが落ちた |
| V4 | `include/NativeToolkitC/extra/Other.h` を足す（Codex B8） | `headers` だけが落ちた |

B2（実物の署名）、B7（理由のコード）、B11（明示した fixture が無い）、B9（`csources` の改行）は自己テストで確かめた（14.9）。

### 14.11 2 回目のレビュー（直しの再レビュー）と、メインのセッションの直し

14.10 のソース（`853adb6da871`）を、Claude のサブエージェントと Codex に読むだけで見てもらった（2026-11-07 15:25〜15:40）。指摘はメインのセッションが確かめてから直した。**持ち主はまだ読んでいない。**

| 指摘 | 確かめたこと | 扱い |
|---|---|---|
| Codex A / Claude B-1 | ヘッダーの守りは文字列で比べていた。bash の組み込みの `pwd -P` は打った大文字小文字のまま返す（`/bin/bash -c 'cd ios/iosLibraryCApi/include && pwd -P'` は小文字のまま。`/bin/pwd -P` と zsh は正しい形）。APFS（区別しない）で `--output-dir ios/iosLibraryCApi` は守りを通り、木のヘッダーを消せた | 直した: 写し先と元の、すでにある祖先を `-ef`（デバイスと inode）で比べる。`cd -P` で `..` も物理で解く（Claude C-1）。自己テストに大文字小文字の違う 2 件を足した（区別する FS では skip）。比べ方を文字列に戻す変異で、この件だけが落ちることを確かめた（木のヘッダーは消えていない） |
| Codex B（生の文字列）/ Claude C-4 | 字句処理は `#"..."#` を知らず、中の `"` で文字列を閉じ、`\#(...)` の補間を文字列として消していた。今の `ios/IosLibrary` と capi のソースに生の文字列は無い | 直した: 文字列の状態に「複数行か」と `#` の数を持ち、閉じ・エスケープ・補間をその数で見る。`#if` などの `#` はコード。自己テスト 1 件（7 通り） |
| Codex B（孫のプロセス）/ Claude C-3 | 時間切れの KILL は直接の子だけに向いていた。秒数が数でないと `alarm 0` で時間切れが効かない。`waitpid` と `exit` の間の alarm | 直した: 子を自分のプロセスグループにし、時間切れでグループごと KILL。`waitpid` の後に `alarm 0`。秒数は正の整数だけ。stdin は `/dev/null`（端末の前面のグループでないため）。時間切れなどで状態が 0 でなければ `simctl terminate` でアプリも止める |
| Claude C-5 | 再帰の比較で `.DS_Store` があると正しい配布物の `headers` が落ちる | 直した: 両側で `.DS_Store` を除く。自己テスト 1 件 |
| Codex C（`uint32_t (ntk_version)(void)` の形）、Claude C-2（`-o` で xcframework の出力そのものの `rm -rf`。元からの動き）、Claude C-6（14.9 の B5 の行に「x86_64 はリンカーが署名しないので無署名を禁じると正しい配布物を落とす」を足すとよい） | 確かめた | 直さない。C のソースは 0 件。C-2 は今回の後退ではなく、どのモジュールでも元からある（後で `XCFRAMEWORK_TARGET` にも同じ照らしをかける候補）。C-6 の理由はここに書いた |

C のソースでは `#include <sys/statvfs.h>` が DiskSpace の使用と数えられる（Claude C-4 の補足）。今は C のソースが 0 件。

直しの後の結果は下に書く。

**直しの後の結果**（メインのセッション。15:31〜15:44。最後のソース `5d732a52a41e`、流す前と後で同じ。シミュレーターは 1 台ずつ、各回の前に `pgrep -x Simulator` で閉じていることを確かめた）

| 実行 | 結果 |
|---|---|
| ビルド（Xcode 26.6、2 つの xcframework、出力はスクラッチ。pbxproj は変わらない） | rc 0、capi の警告 0 |
| `check_ios_dist.py --dist`（3.12 と `/usr/bin/python3` 3.9.6） | どちらも rc 0、18 OK、FAIL 0 |
| `test_check_ios_dist.py`（3.9。`NTK_IOS_DIST` と `NTK_REQUIRE_DIST_FIXTURE=1`） | 44 件 OK、skip 0 |
| ヘッダーの守りの自己テスト（3.9） | 8 件 OK |
| smoke（Xcode 26.6 × 17 Pro / 26.2、26.3 × iPad / 18.3。実機向けのビルドつき） | どちらも rc 0、9 PASS、0 FAIL、16 段階 |
| 変異: smoke の起動の時間を 1 秒に | rc 1、状態 142 で FAIL。`simctl launch` は残っていない |
| `scripts/tests` 全体（`NTK_IOS_DIST` つき） | 803 件 OK |
| 設計書の照合（第 1 部・第 2 部） | どちらも FAIL 0 |

流し直していないもの: 照合の 3 つのスライスの `--library`（照合のスクリプトは今回変えていない。14.10 で通った）、`IosLibraryCApiTests`（Swift のソースは TB-11 で変えていない）、Xcode 26.6 × iPad と 26.3 × 17 Pro の smoke の組み合わせ。直しの後の 3 回目のレビューはしていない。

## 15. TB-12

第 2 部 13 章の TB-12（`test_ios.sh` に C ABI のテスト 3 通り、smoke、`--library` と `--require-compile`、`--require-complete` を付けた照合をつなぐ。第 1 部 C-6、6.1、P1-20）。実装者のサブエージェントの記録。コミットはメインのセッションがレビューの後に行う。**判断の要るところは、メインのセッションが利用者の指示のもとで推奨案で決めたもの。持ち主はまだ読んでいない。**

### 15.1 決めたこと（推奨案。持ち主の確認待ち）

| # | 決定 | 理由 |
|---|---|---|
| 1 | **新しい旗 `--capi`** にし、既定の流れ（サンプルの単体テストと UI テスト）と `--baseline` には入れない。`--capi-ui` と同じ形: `--udid` のほかの旗を取らない（`--capi-ui` との併用も拒む）、シミュレーターだけ（実機の UDID は何も組む前に exit 2）、Xcode 26.6（`DEVELOPER_DIR`。違えば exit 2） | 既定の流れの全件は基準（`test_ios.baseline.*.json`）と比べるもので、足すと全件の形と時間が変わる。基準の取り直しは段階 2 の区切りの仕事。C ABI の UI テストも別の旗（`--capi-ui`）なので揃えた。`@c @implementation` は Xcode 26.4 以降が要る |
| 2 | 流れ: `IosLibraryCApiTests` の通常・ASan・TSan（`-enableAddressSanitizer YES` / `-enableThreadSanitizer YES`。回ごとに別の DerivedData）→ 配布物のビルド（`-m IosLibrary -m IosLibraryCApi -v <木の Common.h の版> --output-dir <実行のフォルダー>/capi-dist --build-dir … --keep-project-versions`）→ `check_ios_dist.py --dist` → 照合 `--require-compile --require-complete --library <capi のスライス> --architectures`（`ios-arm64` は `arm64`、シミュレーターは fat で `arm64,x86_64`）→ smoke（`--udid` と `--device-build`） | 配布物は `ios/IosLibraryExample/build/test_ios/<実行>/`（`ios/.gitignore` が外す）に作り、`dist/` と pbxproj に触れない。版を `Common.h` から読むのは、`check_ios_dist.py` が版 = `Common.h` を照らすため。TB-11 の `lipo -thin` で分けた 2 回は入れない（fat の 1 回で両方のアーキテクチャを照らす） |
| 3 | **各段は失敗しても先へ進み、要約が決める**。配布物のビルドが落ちたら、それが要る 4 段は「not run」の FAIL。8 段がちょうど 1 回ずつ記録されなければ失敗 | 1 回で全部の結果が見える。段が黙って抜けた形も失敗にする |
| 4 | 判定は新しい `scripts/ios_capi_runner.py` に置いた（`ios_ui_runner.py` は信頼するファイルで変えない約束。Xcode の版の値 `CAPI_UI_XCODE` だけを読む） | `capi-check-xcode` の文言は `--capi-ui` を名指すので、`--capi` 用に同じ判定を置いた |
| 5 | 単体テストの各回が通る条件: 結果の要約で全件 PASS、skip 0、expectedFailures 0、件数 > 0 / `IosLibraryCApi` と `IosLibrary` の両 framework が**その回のサニタイザーのランタイムだけ**を読み込む（`otool -L`。通常の回は無し）/ xcodebuild のログと **xcresult の action のログ**にサニタイザーの報告の行（`ERROR: AddressSanitizer` など compiler-rt の形と UBSan の `runtime error:`）が無い / 3 回の件数が同じ | 旗が黙って効かない形と、テストは通ったが報告が出た形を止める。最初は xcresult の console のログを読む形にしたが、テストの xcresult には console のログが無かった（1 回目の実行。`content-availability` は `build` と `action` だけ）。テストのホストの標準エラーは xcodebuild のログと action のログの両方に出ていた（`IosLibraryCApiTestHost[…]` の行。action のログに 345 行）。今のソースのログで誤検出 0 |
| 6 | 照合の報告に `SKIP` が 1 行でもあれば、`OK   symbols` の行が無ければ FAIL。`check_ios_dist.py` は `FAIL` の行が無く `OK` の行があること。smoke は `simulator build`・`device build`・`simulator run` の PASS があり FAIL が無いこと。どれも終了の状態に加えて | 旗が落ちて照合が SKIP で通る形、smoke がシミュレーターで流れずに組むだけで通る形を止める |
| 7 | Simulator.app が開いていれば、`--capi` の始めと、シミュレーターを使う各段（3 回の単体テストと smoke）の前に exit 2 で止める。開かない・閉じない。`--capi-ui` には足していない（今の動きのまま） | `agent-rules/device-testing.md` の Mac のクリップボード。smoke のスクリプトも自分で確かめる |
| 8 | smoke は Xcode 26.6 の 1 回だけ。26.3（D-16）は `run_ios_capi_smoke.sh` を単独で流す（`scripts/README.md` に書いた） | `--capi` は Xcode 26.6 が要る（単体テストのため）。旗を増やさない |
| 9 | 配布物の archive は、ビルドのスクリプトの今の動きのまま Xcode の既定の DerivedData を使う（`test_ios.sh` が自分で呼ぶ xcodebuild は実行のフォルダーの DerivedData） | ビルドのスクリプトは変えない（TB-11 で決めた形） |
| 10 | 実機: `--capi` は実機を拒む。実機の `--dry-run` と `--approved` の経路は変えていない（新しい段はその経路に無い）。実機の ASan と smoke は 2b の区切りで利用者の許可を得て流す（12.2 の行のまま） | 指示の 5 |

### 15.2 足したもの・変えたもの

| 区分 | ファイル | 中身 |
|---|---|---|
| ランナー | `scripts/test_ios.sh` | 旗 `--capi`、その検査（ほかの旗・実機・Xcode・Simulator.app）、15.1 の 2 の段。usage。既存の段（サンプル、`--capi-ui`、実機の守り）は変えていない |
| 判定 | `scripts/ios_capi_runner.py`（新規） | `version`、`check-xcode`、`unit-record`、`step-record`、`summary`。`/usr/bin/python3`（3.9）で動く |
| 自己テスト | `scripts/tests/test_ios_capi_runner.py`（新規。この時点で 25 件。15.9 の直しの後は 31 件） | 純粋な関数（版、Xcode、報告の形、ランタイム、要約、各段の報告）と、偽物のツールと 4 つのスクリプトの代役で `test_ios.sh --capi` を端から端まで流すもの（旗と順と引数、実機・ほかの旗・Xcode・Simulator.app の拒否、14 通りの失敗、配布物のビルドの失敗、サンプルの実機の `--dry-run` と シミュレーターの `--dry-run` が新しい段に届かない） |
| 文書 | `scripts/README.md` | `--capi` の行・例・説明、自己テストの件数（828） |
| 設計書 | 第 2 部 12.1 の冒頭、13 章の TB-12 の行 | 15.1 の形の印（推奨案。持ち主の確認待ち） |

信頼するファイル（UI テストの `Support/` の 5 つ、`scripts/ios_ui_runner.py`）、公開ヘッダー、`ios/` のすべて、基準の JSON、第 1 部、README は変えていない。`android/.idea` には触れていない。`dist/` には何も作っていない。

### 15.3 TB-12 の完了の条件

| 条件 | 結果（15.4） |
|---|---|
| 3 通りの `IosLibraryCApiTests` が `test_ios.sh` から流れて通る | 17 Pro / 26.2 で 474 / 474 / 474、報告 0 |
| smoke | 9 PASS、16 段階（シミュレーターと実機向けの組み立て、シミュレーターの実行） |
| `--library` と `--require-compile`、`--require-complete` を付けた照合 | 2 つのスライスとも OK 30、FAIL 0、SKIP 0、134 symbols |
| 配布物の照合 | `check_ios_dist.py` OK 18、FAIL 0 |
| 既存の流れを壊さない | 15.4 の `--capi-ui`、自己テスト、実機の `--dry-run` |
| 実機で何も新しく流れない | `--capi` は実機を拒む。実機の `--dry-run` の一覧に新しいものが無い（15.4） |

**前の節から TB-12 に送られた項目の受け方**（15.9 のレビューの B-1 で足した。「全件が通る」は下の機種の結果）:

| 送られた項目 | どこから | 流したもの（15.10） | 流していないもの・受ける区切り |
|---|---|---|---|
| 第 2 部 15.2 のシミュレーター 2 台で 3 通り | 3.5（345 行）、4.4（482 行） | `--capi` を iPhone 17 Pro / 26.2 と iPad Pro 11-inch (M4) / 18.3（日本語）で。どちらも 8 段が通った | **iPhone 17（Pro でない）/ 26.2 は流していない。段階 2 は一貫して 17 Pro / 26.2 で流してきたので、17 Pro で代えた**（推奨案。持ち主の確認待ち。15.7）。新しいシミュレーターは作っていない |
| x86_64 のスライスのテスト | 4.4（482 行）、7.7 | `IosLibraryCApiTests` の通常の 1 回を x86_64 で。**iOS 26.2 には x86_64 の実行先が無い**（17 Pro に `arch=x86_64` を渡すと xcodebuild が rc 70 で、x86_64 の実行先として 18.3.1 のシミュレーターだけを挙げた。README 7.4 のとおり）ので、iPhone 16 / 18.3 で流した。**473/474**。落ちたのは `EntryFoundationTests/testAMismatchIsLoggedOnceAndStopsNothing` で、単独でも 2 回とも落ちた（15.9） | ASan・TSan の x86_64、x86_64 の smoke（smoke の x86_64 は TB-11 の 14.4 で 1 回）。`--capi` には入れていない（ランナーは arm64 の実行先だけ） |
| 検出の 5 秒に晒される UI テスト 2 件 | 7.7（1172 行） | 見直した（15.9）。15.10 の `--capi-ui` でどちらも通った | 直していない（`ios/` を変えない回。理由は 15.9） |

### 15.4 コマンドと結果（最後のソース）

最後のソース（ハッシュ `git status --short -uall -- ios scripts | cut -c4- | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-12`）は **`1d3921dd9a7f`で、流す前も後も同じ**（TB-12 の前は `e3b0c44298fc`。TB-11 のコミット `1a4b959e` のまま）。流したのは iPhone 17 Pro / 26.2 の 1 台だけで、実行を重ねていない（iPhone 16 / 18.3 と iPad は使っていない）。各実行の前に `pgrep -x Simulator` で Simulator.app が閉じていることを確かめた（`--capi` は自分でも確かめる）。Simulator.app は開いていない。Mac の `pbcopy`・`pbpaste` と `simctl pbsync` は使っていない。終わりに確かめると、3 台（使った 17 Pro と、使っていない iPhone 16・iPad）とも停止していた。`dist/` と pbxproj は変わっていない。実機と `xcrun devicectl` は使っていない。**流した後に変えたのはこの記録だけ。**

```
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer scripts/test_ios.sh --udid <17 Pro> --capi
DEVELOPER_DIR=… scripts/test_ios.sh --udid <17 Pro> --capi-ui
DEVELOPER_DIR=… scripts/test_ios.sh --udid 11111111-2222-3333-4444-555555555555 --capi
DEVELOPER_DIR=… scripts/test_ios.sh --udid 11111111-2222-3333-4444-555555555555 --enumerate-udid <17 Pro> --dry-run --device-allow systemui
NTK_IOS_DIST=<--capi の実行のフォルダー>/capi-dist NTK_REQUIRE_DIST_FIXTURE=1 /usr/bin/python3 -m unittest discover -s scripts/tests
```

| 実行 | 結果 |
|---|---|
| `--capi`（17 Pro / 26.2。16:01〜16:09、約 8 分） | rc 0、`[summary] 8 passed, 0 problem(s)`。通常・ASan・TSan とも 474/474、報告 0（両 framework が ASan の回は `libclang_rt.asan_iossim_dynamic`、TSan の回は `libclang_rt.tsan_iossim_dynamic` だけを読み込み、通常の回は無し）。配布物のビルド rc 0、`check_ios_dist.py` OK 18・FAIL 0、照合は `ios-arm64`（`arm64`）とシミュレーター（`arm64,x86_64`）の両方で OK 30・FAIL 0・SKIP 0・134 symbols、smoke 9 PASS・0 FAIL・16 段階（シミュレーターは x86_64 と arm64、実機向けは arm64 で署名なし） |
| 同、1 回目（15:51〜15:58。直す前の判定） | rc 1。単体テストの 3 回は 474/474 で通っていたが、無い console のログを求めて FAIL。ほかの 5 段は PASS（15.1 の 5 の直しのきっかけ） |
| `--capi-ui`（17 Pro / 26.2。16:10〜16:33、約 23 分） | rc 0、58 passed、0 problem（前と同じ。fresh 3 件と `CApiRoundTripUITests` 55 件） |
| `--capi` に実機の形の UDID | rc 2（`--capi runs on a simulator only`）。何も組まない |
| 実機の `--dry-run`（実在しない UDID、`--device-allow systemui`。実機に触れない） | rc 0、テストを流す前に止まった。一覧はサンプルの UI テストの 6 回・62 件だけで、`approval.json`・`plan.json`・出力に `capi`・`sanitizer`・`smoke`・`IosLibraryCApi` は 0 件。runner のファイルがコミットと違う警告（`SCRIPTS/TEST_IOS.SH DIFFERS FROM THE COMMIT`）はコミットの前なので期待どおり |
| `test_ios_capi_runner.py` と `test_ios_ui_runner.py`（3.9） | Ran 235、OK（25 + 210） |
| `scripts/tests` 全体（3.9、`NTK_IOS_DIST` と `NTK_REQUIRE_DIST_FIXTURE=1`） | Ran 828、OK（skip 0） |
| 照合（旗なし） | rc 0 |
| 設計書の照合（第 1 部・第 2 部） | どちらも rc 0、FAIL 0 |

16:34 に Mac に `maild-2026-11-07-163405.ips` が出た（シミュレーターの中の mail のデーモン。自分のプロセスではないので消していない。11 章の記録と同じ種類）。

### 15.5 壊して確かめたこと（使い捨ての写し）

リポジトリの追跡ファイル（`dist/` と `docs/` を除く）をスクラッチに写し、写しの `test_ios.sh --capi` を本物のまま流した（17 Pro / 26.2。16:33〜16:37。1 つずつ順に）。時間を省くため、写しでは xcodebuild の単体テストの回を、15.4 の最後の実行が残した本物の xcresult・ログ・組んだ framework を写して返す差し替え（PATH の先頭）にし、ビルドのスクリプトは同じ実行の配布物を写す代役、smoke は M3 のほかは同じ実行の smoke の報告を返す代役にした。`ios_capi_runner.py`、`check_ios_dist.py`、`check_c_abi_contract_ios.py` と、M3 の smoke は本物。

| # | 変異 | 結果 |
|---|---|---|
| M0 | 変異なし（仕掛けの対照） | rc 0、8 passed |
| M1 | ASan の回の出力に、テストが通ったまま ASan の報告の 2 行（`==…==ERROR: AddressSanitizer: heap-use-after-free …`、`SUMMARY: AddressSanitizer: …`）を足す | rc 1。`unit-asan` だけが FAIL（`2 sanitizer report line(s) in the test log`） |
| M2 | 写しの照合の `NOT_IMPLEMENTED_YET` に `ntk_share_result_free` を足す | rc 1。照合の 2 段が FAIL（`entries`、`complete`、`symbols` の 3 FAIL） |
| M3 | 本物の smoke を `NTK_SMOKE_LAUNCH_SECONDS=1` で流す | rc 1。`smoke` だけが FAIL（`the launch ended with status 142`、`no PASS simulator run`） |
| M4 | TSan の回に、通常の回の組み立て（TSan のランタイム無し。テストは 474/474 で通る）を返す（旗が黙って効かない形） | rc 1。`unit-tsan` だけが FAIL（両 framework が `no sanitizer runtime`） |
| M5 | 配布物の `include/NativeToolkitC/Common.h` に 1 行足す | rc 1。`dist-check` だけが FAIL（`headers`） |

最初の M0 と M2 は、駆動のスクリプトの誤り（`env … true bash …` で `true` を実行していた）でランナーが流れず rc 0 だったので、直して流し直した（上の表はその結果）。自己テスト（15.2）でも、14 通りの失敗と配布物のビルドの失敗、実機・ほかの旗・Xcode・Simulator.app の拒否を偽物のツールで確かめた。

### 15.6 確かめられていないこと

- **実機では何も流していない**（指示のとおり）。実機の ASan と smoke は 2b の区切りで、利用者の許可を得て流す。`--capi` は実機を拒むので、その回の流し方（実機向けの `IosLibraryCApiTests` の ASan と、署名して入れる smoke）はその区切りで決める
- **本物のサニタイザーの報告で落ちることは見ていない**（M1 は報告の行を偽った）。報告がホストの標準エラーに出て、それが xcodebuild のログと action のログに入ることは、ホストの普通の出力（`IosLibraryCApiTestHost[…]` の行）で確かめただけ。TSan の報告がホストを止めること（4.3）は、テストの失敗としても落ちる
- ~~`--capi` は iPhone 17 Pro / 26.2 だけで流した~~ → 15.10 で iPad Pro 11-inch (M4) / 18.3 でも流した。iPhone 17（Pro でない）/ 26.2 は流していない（17 Pro で代えた。15.7）
- x86_64 は通常の 1 回だけで、1 件が落ちる（15.9）。x86_64 の ASan・TSan は流していない
- smoke の Xcode 26.3 の回（D-16）は `--capi` に入れていない（15.1 の 8。TB-11 で単独で流した）
- 配布物の archive が Xcode の既定の DerivedData を使うこと（15.1 の 9）は変えていない
- `--capi` の時間の上限は、単体テストの各回と配布物のビルドと smoke が 3600 秒。照合と `check_ios_dist.py` には上限を付けていない
- 変異の仕掛け（15.5）はスクラッチにだけあり、コミットしない

### 15.7 持ち主の判断待ち

1. 15.1 の 1（新しい旗 `--capi`。既定の流れと `--baseline` に入れない）
2. 15.1 の 3（失敗しても先へ進み、要約が決める）
3. 15.1 の 5・6（各回・各段が通る条件。とくにサニタイザーのランタイムを `otool -L` で確かめること、照合の SKIP を失敗とすること）
4. 15.1 の 7（`--capi` だけが Simulator.app を確かめる。`--capi-ui` にも足すか）
5. 15.1 の 8（26.3 の smoke を `--capi` に入れない）
6. **第 2 部 15.2 の iPhone 17 / 26.2 を iPhone 17 Pro / 26.2 で代えること**（推奨案。段階 2 は一貫して 17 Pro / 26.2 で流してきた。新しいシミュレーターは使わない）
7. **x86_64 で落ちる `testAMismatchIsLoggedOnceAndStopsNothing` の扱い**（15.9。ライブラリはその行を出しているが、x86_64 では `OSLogStore` が 0 件を返す。推奨: x86_64 ではこのテストの `OSLogStore` の読み取りを確かめから外すか、テストの側で読み方を変える。`ios/` の変更なので次の回）
8. **`agent-rules/device-testing.md` に `--capi` を書き足すか**（15.9 の C-g。規則のファイルの変更なので持ち主の判断。候補の文: 「`scripts/test_ios.sh --capi` もシミュレーターだけで、実機の UDID を拒む。実機の `IosLibraryCApiTests` の ASan と smoke は区切りでだけ、この文書の許可を得て流す」）
9. 検出の 5 秒の 2 件を直さずに残すこと（15.9）
10. `--capi-ui` の旗の拒否を、値ではなく旗が渡されたかで見る形に変えたこと（今までの動きの変更。15.9）

### 15.8 時間

15:45〜16:42（約 1 時間）。うち最後の本番の実行が約 8 分、`--capi-ui` が約 23 分、変異が約 4 分、自己テストの全体が約 7 分（変異と重ねた。変異はシミュレーターをほとんど使わず、M3 だけが使う）。目標の 17:15 の中。

### 15.9 レビューと直し

15.4 のソース（`1d3921dd9a7f`）を Claude のサブエージェントと Codex が読んだ（2026-11-07。どちらも A は 0）。**指摘はメインのセッションがコードで確かめた。持ち主はまだ読んでいない。** 直しは実装者のサブエージェントが入れた（16:49〜）。

| 指摘 | 確かめたこと・直し | 扱い |
|---|---|---|
| Codex B（報告の形が狭い） | `AddressSanitizer:DEADLYSIGNAL`、`…Sanitizer: CHECK failed:`、`FATAL: …Sanitizer`、`ThreadSanitizer: reported N warnings`（N ≥ 1。`0` と `01` は拾わない）を足した（4 種のサニタイザーの名前で）。自己テストに 8 つの形と、拾わない行を足した。変異 M6a・M6b（15.10） | 直した |
| Codex B（`capped` で子が残る） | 新しい 2 段（配布物のビルドと smoke）を `capped_group` に替えた: 子を自分のプロセスグループにし、時間切れでグループごと KILL、子を回収して 142、stdin は `/dev/null`（`run_ios_capi_smoke.sh` の perl と同じ形）。既存の `capped` の使い方は変えていない。自己テスト `TimeLimit` 4 件（子と孫が残らない、自分の終了の状態、stdin、上限の値の検査、2 段がこれを使う）。**最初の形の自己テストは子の `sleep` が出力のパイプを持ったままで、`subprocess.run` が 30 秒待ってから生死を見ていたため、直接の子だけを KILL する変異（M7）を落とせなかった**。子の出力を `/dev/null` に向け、`capped_group` が戻った直後に bash の中で生死を記録する形に直し、M7 が落ちることを確かめた | 直した |
| Codex B（値で拒んでいた） | 引数を読むときに `--udid`・`--capi`・`--capi-ui`・`-h` のほかの旗が渡されたことを `OTHER_OPTIONS` に記録し、`--capi` と `--capi-ui` は値によらず拒む（どの旗かを文に出す）。**`--capi-ui` の今までの動きの変更**: `--feature ""`、`--enumerate-udid ""` が通り、`--approved ""`・`--devicectl-id ""` は後ろの検査も値で見るので通っていた（`--device-allow ""` は後ろで拒まれていた）。今は引数の検査で止まり、`simctl` も呼ばない。自己テスト 10 通り（2 つの旗 × 空の値の 5 つ）。変異 M8。`scripts/tests/ios_ui_runner_mutations.py` の「capi-ui: other options accepted」の行を新しい条件に合わせた | 直した |
| Claude B-1（送られた項目を受けていない） | 15.3 の表に受け方を書いた。`--capi` を iPad Pro 11-inch (M4) / 18.3 で、x86_64 の `IosLibraryCApiTests` を iPhone 16 / 18.3 で流した（17 Pro / 26.2 には x86_64 の実行先が無い）。iPhone 17 / 26.2 は 17 Pro で代えた（15.7 の 6） | 直した |
| 〃 x86_64 で落ちた 1 件 | `EntryFoundationTests/testAMismatchIsLoggedOnceAndStopsNothing` が 473/474 の 1 件（期待 1 に 0、`[]`）。**単独で 2 回流しても落ちた**。ホストの標準エラーには `[VersionCheck] IosLibrary is 1.3.0 and IosLibraryCApi is 2.0.0: …` の行が出ているので、ライブラリは行を出している。テストが読む `OSLogStore(scope: .currentProcessIdentifier)` が x86_64（Rosetta）では 0 件を返すと読んだ（arm64 の 18.3 の iPad では同じテストが通る）。**ライブラリの欠陥ではなく、テストの読み方の環境の限り**。`ios/` を変えない回なので直していない | 持ち主の判断待ち（15.7 の 7） |
| 〃 検出の 5 秒の 2 件 | `testDetectingValuesTheUserAllows` と `…Denies` は、要求から 5 秒（ライブラリの既定 `ClipboardTimeouts.detection`。C から `init(timeouts:)` を使えない）の中で貼り付けのダイアログに答える必要があり、`answerPaste` はダイアログを最大 10 秒待つ。15.4 の `--capi-ui` ではどちらも全体で約 7 秒（アプリの起動を含む）で通り、今までの回で落ちたことは無い。直すには、テストが期限を決める口か、ライブラリの既定を変える必要があり、どちらも TB-12 の外（`ios/` を変えない）。落ちたときは完了の値が `TIMED_OUT` の番号で出るので原因は読める | 直さない（15.7 の 9） |
| Claude C-a | dist-check の報告の `SKIP` も FAIL に。自己テスト 1 件 | 直した |
| Claude C-c | `pgrep` の終了の状態が 1 のときだけ「閉じている」。0 は開いている、2 以上は `pgrep failed` でどちらも exit 2。自己テスト 2 件（状態 2 と 3） | 直した |
| Claude C-d | usage の `--udid` の行の桁が 1 つずれていた（最初の編集で空白を 1 つ落とした）。戻した | 直した |
| Claude C-e | 「12 通り」を実数の 14 通りに | 直した |
| Claude C-f | 15.4 の「1 台だけ」と「3 台とも停止」を、使った台と終わりの状態に分けて書き直した | 直した |
| Claude C-b（action のログの「first:」の表示） | action のログは JSON で、出力が 1 つの文字列の中に入るので、報告の行の「first:」が長い JSON の行の先頭 200 文字になる。見つけることには関わらない（検出は行の中を探す） | 直さない |
| Claude C-g（`agent-rules/device-testing.md` に `--capi` を書く） | 規則のファイルの変更は持ち主の判断 | 直さない。15.7 の 8 に候補の文を書いた |

### 15.10 直しの後の最後の検証

最後のソースのハッシュ（15.4 と同じ式）は **`67994778ecda`で、流す前も後も同じ**（直しの前は `1d3921dd9a7f`）。下の 17 Pro の `--capi` だけは、その直前のソース `6b10d3e356cb` で流した（違いは自己テストの `TimeLimit` の 1 件の直しだけで、ランナーが読むファイル（`test_ios.sh`、`ios_capi_runner.py`、つなぐ 4 つのスクリプト）は同じ）。シミュレーターは 1 台ずつ順に使い（17 Pro、iPad、iPhone 16 の x86_64、17 Pro）、重ねていない。各実行の前に `pgrep -x Simulator` が状態 1（閉じている）を返すことを確かめた。Simulator.app は開いていない。Mac の `pbcopy`・`pbpaste` と `simctl pbsync` は使っていない。終わりに確かめると、3 台とも停止していた。実機と `xcrun devicectl` は使っていない。`dist/` と pbxproj は変わっていない。**流した後に変えたのはこの記録だけ。**

| 実行 | 結果 |
|---|---|
| `--capi`（iPhone 17 Pro / 26.2。16:53〜17:01） | rc 0、8 passed。474/474 × 3、報告 0、各回のランタイムは期待どおり。`check_ios_dist.py` OK 18・FAIL 0・SKIP 0、照合は 2 スライスとも OK 30・FAIL 0・SKIP 0、smoke 9 PASS・16 段階 |
| `--capi`（iPad Pro 11-inch (M4) / 18.3、日本語。17:01〜17:08） | rc 0、8 passed。474/474 × 3、報告 0（ASan と TSan の回は両 framework がそれぞれのランタイムを読み込む）。`check_ios_dist.py` OK 18、照合は 2 スライスとも OK 30・SKIP 0、smoke 9 PASS・16 段階（iPad の上で実行） |
| `IosLibraryCApiTests` x86_64（`xcodebuild test … arch=x86_64`。DerivedData と結果はスクラッチ） | 17 Pro / 26.2: rc 70（x86_64 の実行先が無い）。iPhone 16 / 18.3: 473/474、framework は `x86_64`。落ちた 1 件は 15.9 |
| 同、落ちた 1 件だけ（iPhone 16 / 18.3、x86_64） | 2 回とも落ちた（ホストの標準エラーには `[VersionCheck]` の行が出る） |
| 旗の拒否を本物のランナーで（`--capi` と `--capi-ui` のそれぞれに、`--feature ""`、`--enumerate-udid ""`、`--approved ""`、`--devicectl-id ""`、`--device-allow ""`、`--dry-run`、`--skip-unit`、`--feature Dialog`。`--capi --capi-ui`。実機の形の UDID に `--capi`） | 18 通りとも rc 2（どの旗かを文に出す）。何も組まない。実機の拒否は今までどおり作業フォルダーを作った後なので、`*-pending.*` のフォルダーが 2 つ残った（git が無視する場所） |
| `--capi-ui`（17 Pro。17:13〜17:36） | rc 0、58 passed（前と同じ） |
| 実機の `--dry-run`（実在しない UDID、`--device-allow systemui`） | rc 0。サンプルの 6 回・62 件だけで、`approval.json`・`plan.json`・出力に `capi`・`sanitizer`・`smoke` は 0 件 |
| ランナーの自己テスト（`test_ios_capi_runner.py` 31 件、`test_ios_ui_runner.py` 210 件。3.9） | どちらも OK |
| `scripts/tests` 全体（3.9、`NTK_IOS_DIST` は 17 Pro の最後の実行の配布物、`NTK_REQUIRE_DIST_FIXTURE=1`） | Ran 834、OK（skip 0） |
| 設計書の照合（第 1 部・第 2 部） | どちらも rc 0、FAIL 0 |

**変異**（15.5 と同じ写しと差し替え。同じ回の対照の M0 は rc 0・8 passed）:

| # | 変異 | 結果 |
|---|---|---|
| M6a | ASan の回の出力に `AddressSanitizer:DEADLYSIGNAL` だけを足す（ERROR・SUMMARY の行なし） | rc 1。`unit-asan` だけが FAIL |
| M6b | TSan の回の出力に `ThreadSanitizer: reported 2 warnings` だけを足す | rc 1。`unit-tsan` だけが FAIL |
| M7 | `capped_group` の時間切れで、グループではなく直接の子だけを KILL する | 自己テスト `TimeLimit` が落ちた（`the child is still running`）。最初の形の自己テストは落とせなかった（15.9） |
| M8 | `--capi` の拒否を値で見る形に戻す | 自己テストの空の値の 5 通りが落ちた |

M6a・M6b は写しの本物の `test_ios.sh --capi`（17 Pro の最後の実行の成果物を写して返す差し替え）、M7・M8 は写しの自己テストで流した。

直しと最後の検証の時間: 16:49〜17:45（約 1 時間。`--capi-ui` が約 23 分）。

### 15.11 直しの再レビュー（Codex だけ）と、メインのセッションの直し

15.10 のソース（`67994778ecda`）を、Codex にだけ読むだけで見てもらった（2026-11-07 17:47〜17:52）。Claude の再レビューはしていない。A は 0。指摘はメインのセッションが確かめてから扱いを決めた。**持ち主はまだ読んでいない。**

| 指摘 | 確かめたこと | 扱い |
|---|---|---|
| B1 中断のシグナル | `capped_group` の perl は ALRM だけを受けていた。端末の Ctrl-C は前面のグループに届くので、別のグループにした xcodebuild などに届かず残る | 直した: INT・TERM・HUP でもグループごと KILL し、子を回収して 128 + 番号で終える。自己テスト 1 件（perl に TERM を送り、状態 143 で子が残らない）。ハンドラーを外す変異でこのテストが落ちることを確かめた |
| B2 入れ子のグループ | smoke の中の `simctl launch` は smoke のスクリプトがさらに別のグループにする。外側の 3600 秒が来ると内側の監視の perl は消えるが、その simctl は残りうる | 直さない。smoke のビルドに 1 時間近くかかったときだけ起きる。内側には 120 秒の時間切れがある。候補として残す |
| B3 TSan の FATAL の形 | Xcode 26.6 の TSan のランタイムに `FATAL: Memory layout is incompatible with TSan.` がある。今の形はこれを拾わない。この形で止まるとテストが流れず、件数などの別の条件でも落ちる見込み | 直した: この形を足した。自己テストに 1 行足した |
| B4 値に旗を飲み込む | `--udid --dry-run --udid <id> --capi` で最初の `--udid` が `--dry-run` を値として取り、拒む仕掛けをすり抜けた（前からある読み方） | 直した: 値を取る 6 つの旗は、値が無いか `-` で始まるなら exit 2。自己テスト 1 件（`--capi` と `--capi-ui` の 3 通りずつと、値の無い旗） |

直しの後の結果は下に書く。

**直しの後の結果**（メインのセッション。17:55〜18:09。最後のソース `8b32359281e9`、流す前と後で同じ）

| 実行 | 結果 |
|---|---|
| `scripts/tests` 全体（`/usr/bin/python3` 3.9、`NTK_IOS_DIST` つき） | 836 件 OK |
| `test_ios.sh --capi`（`DEVELOPER_DIR` なし。既定の Xcode は 26.3） | rc 2 で止まり、何も組まない（26.6 だけを受ける守りのとおり） |
| `DEVELOPER_DIR=<Xcode 26.6> test_ios.sh --capi`（17 Pro / 26.2） | rc 0、8 passed（474 × 3、dist-check、照合 2 スライス、smoke）。終わった後に xcodebuild・`simctl launch` は残っていない |
| 設計書の照合（第 1 部・第 2 部） | どちらも FAIL 0 |

流し直していないもの: iPad の `--capi`、`--capi-ui`（引数の読み方の変更は自己テストが受け持つ）、x86_64 の単体テスト。直しの後の 2 回目の再レビューはしていない。
