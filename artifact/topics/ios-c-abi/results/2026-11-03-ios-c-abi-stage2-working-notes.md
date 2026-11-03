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
