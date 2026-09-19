# マニュアルの整合不良（画像・アンカー・index 機能一覧）

- 記録日: 2026-08-23（1・2）／ 2026-09-06 追記（3）
- 分類: 横断課題（Clipboard 固有ではない）
- 発見経緯: `/write-manual` で 1.9.0 を作成した際の画像検査、`/verify-manual` 新設時の検査、および 1.10.0 で macOS Clipboard を追加した際の目視で判明
- 検査手段: `./scripts/verify_manual.sh <version>`
- 対応方針: **1.9.0 / 1.10.0 のリリースには含めない。別途対応。**
- 最終確認: 2026-09-06（1.10.0 で再検査。内訳は下記「1.10.0 での再確認」）

# 1. 画像リンク切れ（30 件）

## 何が問題か

`manual/<version>/` 配下の Markdown が参照している画像のうち **30 件が実在しない**。
公開後の `docs/<version>/manual/` でも同じ 30 件が壊れて表示される。

`/write-manual` は画像プレースホルダーを挿入する仕組みだが、**挿入した参照に対して実体が
用意されたかを検証する手順がない**。そのため、撮り忘れが検出されずにバージョンを越えて
引き継がれてきた。

## 内訳（2026-08-23 実測 / 1.9.0）

全 433 参照中 30 件が切れている。Clipboard（iOS 30 枚・Android 10 枚）は 0 件。

| ファイル | 件数 | 参照先 |
|---|---|---|
| `index.md` / `index.ko.md` | 2 | `images/android/Example_AndroidDialogFragment.png` |
| `notification.md` / `notification.ko.md` | 28 | `images/mac/notification/Example_MacNotificationManager_*.png` 14 種 |

### mac notification で不足している 14 種

```
AuthorizationStatus      CancelAll                GetDelivered
GetScheduled             HasPermission            OpenNotificationSettings
RemoveAllDelivered       RemoveCategory           ScheduleCalendar
ScheduleTimeInterval     SetBadgeCount0           SetBadgeCount1
ShowCalendar             ShowTimeInterval
```

実在するのは次の 5 枚のみ。

```
Example_MacNotificationManager.png
Example_MacNotificationManager_RegisterCategory.png
Example_MacNotificationManager_RequestPermission.png
Example_MacNotificationManager_ShowImmediate.png
Example_MacNotificationManager_UpdateById.png
```

## 日本語版だけ壊れていない

`.ja.md` は 30 件とも切れていない。**参照している画像名が違う**ためである。

| ファイル | 参照 | 実体 |
|---|---|---|
| `index.ja.md` | `images/android/Example_Top.png` | あり |
| `index.md` / `index.ko.md` | `images/android/Example_AndroidDialogFragment.png` | **なし** |

つまり 3 言語版が同じ画像を指しておらず、**言語間で内容が食い違っている**。単なる撮り忘れ
ではなく、翻訳時に参照先がずれた可能性がある。修正時はどちらが正なのかを先に決める必要が
ある。

## いつ混入したか

| 対象 | 初出 | 状況 |
|---|---|---|
| mac notification 14 種 | **1.3.0** | mac の notification セクション追加時から一度も実体がない |
| android index 1 種 | **1.1.0** | 1.0.0 には実体があった。1.1.0 へのコピー時に画像だけ欠落 |

1.3.0 から 1.9.0 まで 7 バージョン、`manual/<prev>` をコピーして作る運用のため、
**壊れた参照がそのまま複製され続けている**。

## 対応案

1. **撮影して埋める** — mac サンプルアプリで 14 枚、Android で 1 枚。`.ja` と参照名を揃える
2. **参照を削除する** — 撮影しない操作（結果が画面に出ないものなど）なら参照ごと落とす
3. **`.ja` に合わせる** — index の android 画像は `Example_Top.png` に統一する

いずれの場合も、次を `/write-manual` のステップに追加しないと再発する。

```
生成後、manual/<version>/ 配下の全画像参照について実体の存在を検証し、
不足があればユーザーに提示する
```

## 検査コマンド

記録時点ではアドホックな `grep` で検査したが、現在は `/verify-manual` に取り込まれている。

```bash
./scripts/verify_manual.sh 1.9.0        # 検査1 が画像、検査3 がアンカー
```


---

# 2. 目次アンカー切れ（5 件）

`/verify-manual` の検査3 で新たに検出した。目次のリンクが実在しない見出しを指している。
クリックしても飛ばないだけで表示は壊れないため、これまで気づかれなかった。

すべて `notification.*` に集中しており、Clipboard 由来のものはない。

## 内訳

| # | ファイル | 壊れているリンク | 原因 |
|---|---|---|---|
| 1 | `notification.md` | `[Categories and Actions](#categories-and-actions)` | 見出しが `### Category and Actions`（単数）。正しいアンカーは `#category-and-actions` |
| 2 | `notification.md` | `[Show Notification](#show-notification-3)` | 実在は 3 件のみ。Windows 節の項目なので `#show-notification-1` が正 |
| 3 | `notification.ja.md` | `[通知の表示](#通知の表示-3)` | #2 と同じ。`#通知の表示-1` が正 |
| 4 | `notification.ko.md` | `[알림 표시](#알림-표시-3)` | #2 と同じ。`#알림-표시-1` が正 |
| 5 | `notification.ko.md` | `[오류 코드](#오류-코드-1)` | 韓国語訳の不統一。下記参照 |

## #2〜#4 は同じ原因

`Show Notification` に相当する見出しは 3 か所にしかない。

```
line  889  ## iOS     → #show-notification
line 1282  ## Windows → #show-notification-1
line 1674  ## macOS   → #show-notification-2
```

目次の Windows 項目が `-3`（4 番目）を指しており、2 つずれている。
以前 Android 節にも同名の見出しがあり、改名時に目次が追随しなかった可能性が高い。

3 言語とも同じ位置（62 行目）で同じずれ方をしているため、翻訳時に目次ごと複製されている。

## #5 は訳語の不統一と目次の連番ずれが重なっている

韓国語版だけ、同じ「Error Codes」に 2 つの訳語が使われている。

| プラットフォーム | 行 | en | ja | ko |
|---|---|---|---|---|
| Windows | 1535 | `### Error Codes` | `### エラーコード` | `### 오류 코드` |
| macOS | 2027 | `### Error Codes` | `### エラーコード` | **`### 에러 코드`** |

訳語が分かれた結果、重複見出しの連番が消え、目次と噛み合わなくなっている。

| | 見出しのアンカー | 目次の参照 | 判定 |
|---|---|---|---|
| Windows | `#오류-코드` | 80 行目 `#오류-코드-1` | **切れている** |
| macOS | `#에러-코드` | 112 行目 `#에러-코드` | 解決はする（訳語が不統一） |

en では Windows が `#error-codes`、macOS が `#error-codes-1` である。
韓国語版の 80 行目は en の macOS 側の連番（`-1`）を Windows 側に付けてしまっている。

見出し数は 3 言語とも 123 で一致しているため、節の欠落ではなく訳語と連番だけの問題である。

## 検出できなかった理由

`/verify-manual` 新設時に検査3 を実装するまで、アンカーを検証する手段がなかった。
画像と違い、アンカー切れは**表示が壊れない**ため目視でも気づきにくい。

## 対応案（検証済み・これで検査3 は 0 件になる）

`notification.*` に閉じており、他機能への影響はない。計 6 箇所の編集で済む。

| # | ファイル | 変更 |
|---|---|---|
| 1 | `notification.md` | 目次 `[Categories and Actions](#categories-and-actions)` → `[Category and Actions](#category-and-actions)` |
| 2 | `notification.md` | 目次 `[Show Notification](#show-notification-3)` → `(#show-notification-1)` |
| 3 | `notification.ja.md` | 目次 `[通知の表示](#通知の表示-3)` → `(#通知の表示-1)` |
| 4 | `notification.ko.md` | 目次 `[알림 표시](#알림-표시-3)` → `(#알림-표시-1)` |
| 5 | `notification.ko.md` | 見出し 2027 行 `### 에러 코드` → `### 오류 코드` |
| 6 | `notification.ko.md` | 目次 80 行 → `[오류 코드](#오류-코드)`、112 行 → `[오류 코드](#오류-코드-1)` |

**#5 だけを直すと #6 が壊れる**（`#에러-코드` を指す目次が孤立する）。
訳語の統一と目次の連番修正は必ずセットで行うこと。

`notification.md` の #1 は目次の表記を見出しに合わせる案である。
逆に見出しを `Category and Actions` → `Categories and Actions` に変えてもよいが、
その場合は ja / ko の対応する見出しも揃えること。

```bash
./scripts/verify_manual.sh 1.9.0   # 検査3 が OK になれば完了
```

---

# 補足: 検査3 の偽陽性を 1 件修正済み

当初 6 件検出したが、うち `index.md -> #feature-list` は**検査側のバグ**だった。
見出しの収集を `##`〜`######` に限定しており、`# Feature list`（H1）を見落としていた。
GitHub は H1 にもアンカーを生成するため、`scripts/verify_manual.sh` を修正済み。

---

# 1・2 の 1.10.0 での再確認（2026-09-06）

macOS Clipboard（NTKIT-15）のマニュアルを追加した後、`/verify-manual` を 1.10.0 に対して
実行した。**指摘の内容は 1.9.0 と 1 行も違わない。**

```bash
./scripts/verify_manual.sh 1.10.0   # FAIL 2 (画像30/アンカー5), WARN 3
./scripts/verify_manual.sh 1.9.0    # FAIL 2 (画像30/アンカー5), WARN 3
# バージョン番号を正規化して diff → 差分なし
```

つまり **1.10.0 で追加した macOS Clipboard 由来の指摘は 0 件**であり、上記 35 件は
すべて notification / index からの引き継ぎである。1.10.0 のリリースを止める理由にならない。

## Clipboard 側が 0 件であることの確認

検査2 は「マニュアルがサンプルにない値を書いた」方向しか見ない。**逆方向（マニュアルが
引数を書き落とした場合）は検出できない**ため、macOS セクションについては手で突き合わせた。

| 観点 | 結果 |
|---|---|
| `MacClipboardManager.shared.*` のメソッド | マニュアル・サンプルで過不足なし |
| 引数ラベルの組み合わせ | 一致（`copy` の `options:` + `scope:` を含む） |
| コールバック例の引数 | `ClipboardCallbackResult` の 4 引数と一致 |
| サンプルの読み込み | `ClipboardSampleView.swift` と `ClipboardSampleSupport.swift` の両方を走査 |

なお検査2 が `dialog.md [Android]` について出す `no sample screen found` は、
Android の dialog サンプルが `DialogSampleScreen.kt` という名前で存在しないためで、
Clipboard とは無関係である。

## この記録の修正案がまだ有効か

**有効。** 上の「対応案」に書いた編集箇所（アンカー 6 箇所、画像 3 案）は 1.10.0 でも
同じ行・同じ内容で成立する。検査コマンドのバージョンだけ読み替えること。

```bash
./scripts/verify_manual.sh 1.10.0
```

---

# 3. index 機能一覧の抜け（1.1.0〜1.3.0 / 修正済み: 1.10.0）

2026-09-06、1.10.0 で macOS Clipboard を追加した際、**マニュアル本体は書けているのに
`index` の機能一覧に項目が無い**という抜けが見つかった。目次のリンクはあったため、
ページには到達できるが一覧には載っていない状態だった。

原因は `write-manual` ステップ7 が「リンクを追加する」しか指示していなかったことである。
手順どおりに実行しても抜ける。ステップ7 を (a) 目次リンク / (b) 機能一覧 / (c) 追加予定機能
の 3 箇所に分けて修正した。

## 同じ抜けが過去にもある

`scripts/verify_manual.sh` に検査7 を追加して全バージョンに掛けたところ、**同じ欠落が
3 バージョンに残っている**ことが分かった。いずれも `notification` がその OS を書いているのに、
`index` の機能一覧が `Dialog` しか載せていない。

| バージョン | 件数 | 内容 |
|---|---|---|
| 1.1.0 | 9 | Windows / iOS / macOS の機能一覧に notification が無い（3 言語 × 3 OS） |
| 1.2.0 | 6 | Windows / macOS の機能一覧に notification が無い |
| 1.3.0 | 3 | Windows の機能一覧に notification が無い |
| 1.4.0〜1.9.0 | 0 | 通る |
| 1.10.0 | 0 | 修正済み |

1.0.0 は機能ページに分割される前で、内容がすべて `index.md` にあるため比較が成立しない
（検査7 は 12 件を報告するが、これは defect ではなく構造の違いである）。

**公開済みの過去バージョンは凍結しているため修正しない。** 1.4.0 以降は正しく、
最新（1.10.0）も正しいので、利用者が見るドキュメントに影響は残っていない。

## 再発防止

検査7 が停止項目として検出する。各ページの `## <OS>` 見出しと、`index` のその OS の
機能一覧の項目数を突き合わせる。両側をソースから導出しており、手で保つ一覧は無い。

```bash
./scripts/verify_manual.sh 1.10.0   # 検査7
```

4 通りの変異（項目削除 / 見出し改名 / 全見出し破壊 / 見出し重複）で落ちることを確認済み。
ただし**項目が 1 行あれば通る**ため、中身が本体と合っているかは見ていない。

## 検査できない残り

ステップ7 の (c)「追加予定機能から外す」は文章のため検査できない。1.10.0 では
「macOS / Windows 向けクリップボード連携」が出荷後も予定として残っていた。目視で確認すること。

---

# 関連

- 同種の横断課題: [BRIDGE_TESTING.md](BRIDGE_TESTING.md)
- 検査ワークフロー: `agent-rules/workflows/verify-manual/workflow.md`（`/verify-manual`）
- 検査の実体: `scripts/verify_manual.sh`
- リリース時のゲート: `agent-rules/workflows/release/workflow.md` ステップ3
