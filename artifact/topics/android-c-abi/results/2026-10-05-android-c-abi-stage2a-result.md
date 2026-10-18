# 段階 2a の結果: 照合のスクリプトを OS ごとにする

- 実施日: 2026-10-05
- 対象: `artifact/topics/android-c-abi/README.md` の段階 2a、C ABI の設計書 第 2 部（`designs/2026-10-05-android-c-abi-c-abi-design-part2.md`）の 0.3、12.3、13 章の TA-1・TA-2
- ブランチ: `feature/NTKIT-17`
- レビュー: `reviews/2026-10-05-android-c-abi-stage2a-review-v1.md`
- 判定: **完了**（TA-1・TA-2 の完了の条件を満たす。Android の照合は、ヘッダーができる 2b までは `--design-only` で付録 A を照らす）

## 1. 結論

2 つの照合のスクリプトを、利用者の決定（第 2 部 0.3）のとおり、共通のモジュールと OS ごとのファイルに分けた。

- Windows の照合は、分割の前と出力が同じ。
- Android の照合は、第 2 部 12.3 と第 1 部 5.2 の項目をすべて照らす。付録 A の上ではすべて通る。
- 照合を強めたことで、設計書の食い違いを 1 件見つけて直した。10 章の BH-45 が、第 3 版の AP-17 と合っていなかった（第 2 部 0.4）。

## 2. 作ったもの

| ファイル | 中身 |
|---|---|
| `scripts/c_abi_contract_common.py` | 共通: 報告、読み取り（無いファイルは失敗。R-30）、C の宣言の解析、ヘッダーに許す前処理の行、設計書の表、付録 A、OS に依らない照合（宣言、11 章、名前、ASCII）、OS 間の `Common.h`（第 1 部 5.2 の 4 区分） |
| `scripts/check_c_abi_contract_windows.py` | 分割の前の `check_c_abi_contract.py`。`.def` と C++ の API との写しを持つ。前処理の行の照合を足した（今の木では出力が同じ） |
| `scripts/check_c_abi_contract_android.py` | Android の照合（下の表）。`--design-only`、`--library`、`--nm` |
| `scripts/manual_c_examples_common.py` | 共通: 版、OS の章で区切った C ABI の節（見出しの書き間違いと、訳にだけある節は失敗）、coverage、symbols、parity、例の書き出し |
| `scripts/check_manual_c_examples_windows.py` | 分割の前の `check_manual_c_examples.py`。`.def`、前置き、MSBuild |
| `scripts/check_manual_c_examples_android.py` | Android: 6 つのヘッダーの関数、NDK の clang（`aarch64-linux-android31`、C99、`-Wall -Wextra -Werror`）。節が無い間は SKIP、`--require-examples` で失敗 |
| `scripts/tests/` | 自己テスト。Android の契約 76、Android のマニュアル 21、Windows の契約 20、Windows のマニュアル 12（全体で 181） |

**Android の照合の項目**:

| 項目 | 照らすもの |
|---|---|
| functions | 8.2 = ヘッダー = 付録 A（155）、行ごとの数、「8.1 の N 関数」、見出しの数 |
| signatures | 関数、コールバック、構造体、列挙の値、typedef。ヘッダーの形（許す前処理の行だけ、ガードが最初と最後、宣言がすべて `extern "C"` の中、構造体が `#pragma pack(push, 8)` の中） |
| operations | 8.1（56）と 9 章の OP、8.1 の C の関数が付録 A にあること |
| kotlin | 8.1 の Kotlin の口（55）が、その名前の唯一の型の一番上の段のメンバーとしてあること |
| behaviours | 10 章: ID の頭ごとの数が README 6 章の範囲と同じ、ID の頭と区分の組、区分と関数（完了のコールバック・受け手の追加・どちらでもない）と 9 章、コールバックを取る関数（19）がすべて行にあること |
| values | 11 章の表 = ヘッダー、AP-12 の 0〜5、11.3・11.4 の順 = Kotlin の宣言の順 |
| names、ascii | 名前の規則、ASCII |
| common | Windows の `Common.h` と比べる。一致させる宣言、`NTK_CALL`、版、Windows だけに許す定数 |
| symbols | `--library` のとき、`libntk.so` の公開 = 8.2 と `JNI_OnLoad` |

## 3. 確かめたこと

| 確かめ | 結果 |
|---|---|
| Windows の 2 つの照合の出力を、分割の前と比べる | 同じ（TA-1・TA-2 の完了の条件） |
| `check_c_abi_contract_android.py --design-only` | FAIL 0。signatures と symbols は SKIP |
| `check_c_abi_contract_android.py`（ヘッダーなし） | 6 つのヘッダーが「読めない」で失敗する（R-30） |
| `check_manual_c_examples_android.py` | 1.12.0 に Android の C ABI の節が無いので SKIP。Windows の章の節を借りない |
| `python3 -m unittest discover -s scripts/tests` | 181 件が通る。NDK r30 の clang でコンパイルのテストも流れた |
| レビューで足したテストを、直す前のスクリプトで流す | 30 件が落ちる（穴が実際にあった） |

## 4. 後の段に渡すこと

- **TB-1**: 6 つの公開ヘッダーを付録 A からまとめて作る。以後、`check_c_abi_contract_android.py` を `--design-only` なしで流す（ヘッダーが 1 つでもあると `--design-only` は失敗する）
- **TB-10・TB-11**: 各 ABI の `libntk.so` に `--library` を付けて流し、`test_android.sh` につなぐ
- **2b のテスト（12.1）**: `system_code` が 0 であること、構造体の `sizeof` と `offsetof`（照合は `#pragma pack` の有無と位置まで）
- **段階 4**: マニュアルに Android の C ABI の節を書いたら、`check_manual_c_examples_android.py --require-examples` を流す（verify-manual の手順に書いた）
- **Windows の `Common.h` を変えたとき**: OS 間の照合は Android の側にあるので、Android の照合も流す

## 5. 残したこと

| 事柄 | 理由 |
|---|---|
| マニュアルの coverage は、ヘッダーの関数を求める（実際の `libntk.so` の公開ではない） | 実際の公開は契約の照合の `--library` が照らす（J-X10） |
| Windows のマニュアルの照合が、Windows の章に節が無いときに後の章の節を借りなくなった | 誤って OK を出す穴を塞ぐ、意図した変更。今のマニュアルでは結果が同じ（J-X11） |
| Windows の MSBuild のコンパイルは、この Mac では SKIP | 前と同じ。書き出しの直し（ASCII で書けない例を報告する）は Windows で流したときに効く |
