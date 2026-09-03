# macOS Clipboard 手動確認結果 v1

## 基本情報

- 開始日: 2026-09-03
- 機能名: clipboard
- ブランチ: `feature/NTKIT-15`
- 対象: 機能設計 `2026-08-29-macos-clipboard-design-v9.md` の MT、サンプル計画 v5 の MS
- 実施環境: **macOS 26.3（Build 25D125）**、MacBook Air (arm64)
- サンプル: `MacLibraryExample.app`（`MacWorkspace.xcworkspace` / scheme `MacLibraryExample` でビルド）

> **環境について。** 機能設計の MT 表は環境欄を「macOS 15.x 実機」としているが、実施端末は
> **26.3** である。26.3 での動作は確認できるが、**15.x での動作を確認したことにはならない**。
> MT-07（15.4.1 と 15.2 の両方が必要）はこの端末では実施できない。

---

## A-1: MT-02 — サンプルでコピー → 他アプリで貼り付け

実施日: 2026-09-03 / 貼り付け先: TextEdit、Preview

| # | 操作 | サンプルの表示 | 貼り付け結果 | 判定 |
|---|---|---|---|---|
| 1 | `CopyText` | ✅ changeCount | `Copied from MacLibraryExample.` | ○ |
| 2 | `CopyURL` | ✅ changeCount | `https://www.apple.com` | ○ |
| 3 | `CopyImage` | ✅ changeCount | Preview で画像が開く | ○ |
| 4 | `CopyMultipleItems` | ✅ changeCount | **`first` と `second` の両方** | ○ |
| 5 | `CopyMultipleRepresentations` | ✅ changeCount | `Copied from MacLibraryExample.` | ○ |

**MT-02 は全項目クリア。**

### 4 について: 手順書の期待値が誤っていた

手順書は「macOS は先頭 item を使う」として `first` のみを期待値にしていたが、**根拠のない
思い込みだった。** `NSTextView` は `readObjects(forClasses:)` で全 item を読むため、両方が
貼られるのが正しい。

**実装・設計・DocC はいずれも正しい。**

- 設計 v9 の C-04〜C-06 除外理由が「`setString` 等は**先頭アイテムのみに作用し複数アイテム
  設計と噛み合わない**」と述べており、複数 item を全部載せる方針が最初から明示されている
- `ClipboardContent` の DocC は `An ordered list of pasteboard items.` / `in order.` と書くだけで、
  貼り付け側がどれを使うかについて何も主張していない。正しい粒度である

**確認できたこと**: 複数 item が欠落せずシステムのペーストボードへ渡り、**どう使うかは受け取る
側が決める**。C-07〜C-10（`writeObjects` 系）を採った設計判断が実機で裏づけられた。

---

## A-2: MT-01 — 他アプリでコピー → `Read`

実施日: 2026-09-03 / コピー元: TextEdit（平文・リッチテキスト）、Preview（画像）、Finder（ファイル）

| 入力 | ボタン | 結果 | 判定 |
|---|---|---|---|
| 平文 | `Read` / `Snapshot` / `SnapshotFiltered` | 読める | ○ |
| 平文 | `AccessBehavior` | **`alwaysAllow`** | ○ |
| リッチテキスト | `Read` | `public.rtf` / `public.utf8-plain-text` に加え **`public.utf16-external-plain-text`** | ○ |
| 画像 | `ReadDataPlainText` | **`no such type (success)`** | ○ |
| ファイル | `ReadDataPlainText` | **`present`** | ○ |

**MT-01 は全項目クリア。**

### 確認できた契約

**該当する型が無いときエラーにならない。** 画像だけがある状態で `readData(utType:
"public.utf8-plain-text")` を呼ぶと、例外ではなく「無い」が返る。**OP-04 の契約どおり。**
ここがエラーになる実装だと、利用者は型の有無を調べるために例外処理を書くことになる。

### 記録しておくこと

**1 item が持つ representation は、書いた側が意図した数より多い。** リッチテキストのコピーで
`public.utf16-external-plain-text` が出た。AppKit が複数のテキスト flavor を自動で載せるため
であり、異常ではない。**`Read` の types を件数や完全一致で判定する利用者コードは壊れる**ので、
マニュアル作成時に触れる価値がある。

**Finder のファイルコピーでは平文データが存在する（`present`）。** 中身は表示していないが、
一般に**ファイルの完全パス**が入る。サンプルは値を出さない設計なので画面には現れない
（§3.4）。ただし利用者が `readData` を平文で呼ぶと**パスが取れてしまう**ため、これは
マニュアルで注意を促すべき挙動である。ライブラリの欠陥ではない。

### 秘匿方針の確認（§3.4）

Finder で `/Users/jonghyunkim/Desktop/command.txt` をコピーして `Read` を押した実測:

```
[read] items=1, bytes=849836,
types=[com.apple.icns|public.file-url|public.utf16-external-plain-text|public.utf8-plain-text]
```

**完全パスは画面に現れない。** 型の一覧とバイト数だけである。`public.utf8-plain-text` と
`public.file-url` の中身にはパスが入っているが、`Read` はそれを表示しない。**§3.4 の要件を
満たしている。**

### bytes は「コピーしたファイルの大きさ」ではない

**約 850 KB。テキストファイル 1 個のコピーである。** 内訳は `com.apple.icns`（Finder が載せる
アイコン）が大半を占める。`totalBytes` は**全 item の全 representation の合計**であり、DocC も
`Total size of every representation across every item.` と正しく書いている。

利用者が「コピーした対象の大きさ」と読むと桁が合わない。**1506（`contentTooLarge`）の上限を
見積もる際にも、representation の数だけ膨らむ**ことを踏まえる必要がある。マニュアルで触れる。

### 環境依存の値

`AccessBehavior` = **`alwaysAllow`**。macOS の設定に依存する値なので、他の設定での値は未確認。

---

## A-3: MT-03 — append の所有権

実施日: 2026-09-03

| # | 経路 | 操作 | 結果 | 判定 |
|---|---|---|---|---|
| ① | 対照（邪魔なし） | `CopyText` → 直後に `AppendWithLastOwnership` | 成功 | ○ |
| ② | **他者所有** | `CopyText` → TextEdit で ⌘C → `AppendWithLastOwnership` | **1511** | ○ |
| ③ | 自所有の連続 | `CopyThenAppend` | 成功 | ○ |
| ④ | 自アプリが無効化 | `AppendWithStaleOwnership` | **1511**（期待どおり） | ○ |

**MT-03 は全項目クリア。機能設計の「append が自所有時のみ成功し、他者所有時は明示エラー」を
両方向で確認した。**

### ① を先に置いた理由

②で 1511 が出ただけでは、「他アプリに奪われたから失敗した」のか「このボタンが常に失敗する」
のかを区別できない。**①（邪魔しなければ成功する）を対照として先に置く**ことで、②の 1511 が
外部のコピーに由来すると言える。機能設計 §6.3 が MT-08 に正の対照を定めているのと同じ形。

### ② と ④ が同じコードであること

**ライブラリは「誰が所有権を奪ったか」を区別していない。** どちらも `changeCount` の不一致
だけで 1511 を返す。区別して別のコードを返す実装なら、Unity 側から**他アプリの存在を推測
できてしまう**。同じコードであることが正しい。

表示は異なる（② は ❌、④ は ✅）。④ は「失敗を期待して失敗した」ので成功表示、② は「起きた
ことをそのまま出す」ので失敗表示。**表示の違いは判定の違いであって、挙動の違いではない。**

### この経路は本日追加した

②の `AppendWithLastOwnership` は 2026-09-03 に追加したボタンである。**それまで MT-03 の
「他者所有時」に導線が無く、自アプリで無効化する経路（④）しか確認できなかった。**
機能設計が求める観点の半分が、5 ラウンドのレビューを経ても確認できない状態で残っていた。

---

## A-4: MT-04 — 監視

実施日: 2026-09-03

| # | 観点 | 結果 | 判定 |
|---|---|---|---|
| ① | 監視中に他アプリのコピーを検出する | 検出した | ○ |
| ② | 非アクティブでポーリングが止まる | `[suspendPolling]` を確認 | ○ |
| ③ | **復帰時に 1 回だけ照合する** | イベント 1 回、changeCount **72 → 75** | ○ |
| ④ | `CheckForegroundChange` が 1 回目 `true` / 2 回目 `false` | **監視停止後**に実施して期待どおり | ○ |
| ⑤ | `StopObserving` 後は他アプリのコピーに反応しない | 結果表示が変わらない | ○ |

**MT-04 は全項目クリア。**

### ③ の実測ログ

```
[suspendPolling]
[resumePolling] scope: scope(general)
[tick] generation: 2
[hasChanged] scope: scope(general), changeCount: 75      ← 直前は 72
[updateResult] [observed] ok                              ← イベントは 1 回だけ
[schedulePolling] interval: 0.5
[tick] ... changeCount: 75（以降イベントなし）
```

**非アクティブ中の 3 回のコピーが 1 イベントに畳まれている。** ペーストボードは履歴を持たない
ので、取りこぼした回数は復元できない。1 回にまとめるのが正しい。

ログが `[observed] ok` であり `changeCount=75` を含まないことも確認できた。画面には
`changeCount=75` が出る。**`SampleOutcome.logText` が detail を落とす設計（§4.2 / ST-04）が
実機で効いている**（MS-07 のログ側の一部を前倒しで確認）。

### ⑤ は自動テストが押さえていない範囲

`testObservationStopsWhenTheScreenIsLeft` は**画面を離れた場合**の停止を検査するが、
**`StopObserving` ボタンで止めた場合**を検査するものは無い。MS-01 は「ボタンが結果を返すこと」
しか見ないため、停止が実際に効いているかは自動では未確認だった。**本手動確認で初めて確認した。**

自動化は可能である（`StartObserving` → `Clear` などで changeCount を進める → `StopObserving`
→ もう一度進める → 結果が `[observed]` にならないことを確認）。ただし「一定時間何も起きない
こと」の待ちを含むため、実行時間と引き換えになる。**次の対応に回す候補として記録する。**

### ④ で見つかった DocC の欠落

**最初の手順は誤っていた。** ⑤（`StopObserving`）を ④ の後に置いたため、④ の時点で監視が
動いたままで、0.5 秒ごとのポーリングが既に変化を消費して基準を更新していた。`false` が正しい
答えだった。

`checkForegroundChange` と監視は**同じ tracker を共有する**。同じ変化を二重に報告しないための
設計で、`MacClipboardManager.swift:115` のコメントにその意図がある。

**しかし公開 DocC にも機能設計にも書かれていなかった。** 併用すると後者はほぼ常に `false` を
返すため、知らなければバグに見える。DocC に追記した。

> While observation is running this returns `false` almost always, because the poll has
> already seen the change and reported it through `onEvent`. Use this instead of observation,
> not alongside it.

**昨日の `clear` の戻り値と同じ形の欠落である**（契約は内部で決まっているのに公開側に無い）。
手順を書いた私自身がこの仕様を誤解しており、その誤解の出所が DocC の欠落だった。

---

## B: MT-06 — Paste Control、および要検証 2 件

実施日: 2026-09-03 / Active scope: `general`

| # | 操作 | 結果 | 判定 |
|---|---|---|---|
| B-1 | `CopyText` → Paste | `items=1, failures=0, partial=false` | ○ |
| B-1 | `CopyImage` → Paste | 同上 | ○ |
| B-2 | `CopyPartialPasteContent` → Paste | **`items=1, failures=0, partial=false`** | 要検証①の答え |
| B-3 | Finder のファイル → Paste | **`items=1, failures=0, partial=false`**。ボタンは押せる状態 | ○ |
| B-4 | `MakePasteButtonInvalidType` / `UndeclaredType` | 1504 | ○ |
| B-5 | `DetectPatterns` / `DetectValues` | 期待どおり | ○ |
| B-5 | `DetectMetadata` | **1515（`detectionFailed`）** | 要検証②の答え |
| - | 初回のシステム確認ダイアログ | **出ない** | 記録 |

### 要検証① の結論: 1521 は到達不能

**システムの `PasteButton` は `supportedContentTypes` に一致しない item を渡してこない。**
`partialPasteContent` は受け入れる型（平文）と受け入れない型（`com.example.unaccepted`）を
1 つずつ持つ 2 item だが、貼り付けた結果は `items=1, failures=0, partial=false` だった。
**受け入れない item はローダーに届かないので、load が失敗する状況を作れない。**

対応:

- 計画 §6.6 の分類を訂正。**1521 を「専用ボタンで到達（11）」から「到達手段なし（8）」へ**移動
- §5「2. Copy」の `CopyPartialPasteContent` の目的を「1521 を作る準備」から
  「**受け入れない型が落ちることを見せる**」へ書き直し
- §8.1 MT-06 の期待を「部分失敗表示」から「受け入れる型は読め、受け入れない型は落ちる」へ
- `ClipboardSampleFixtures.partialPasteContent` の DocC に実測結果を記載

**ライブラリ側の 1521 は担保されている**（`ClipboardPasteLoaderTests` が mock のローダーで
失敗経路を検査）。到達できないのは**サンプルからの経路**だけである。

### 要検証② の結論: 1515 は期待どおり

平文に対する `detectMetadata` は **1515（`detectionFailed`）** を返した。`DetectMetadata`
ボタンの期待値は正しい。**要検証を解除する。**

### B-3 で分かったこと

**Finder のファイルだけを置いた状態でも `items=1` が読める。** A-2 で確認したとおり、
ファイルのコピーは `public.utf8-plain-text` を持つ（中身は一般にパス）。それが accepted type
に一致するため、ローダーが 1 件返す。

つまり **`PasteButton` から「ファイルを貼る」と、パスの文字列が返る。** サンプルは件数しか
表示しないので画面には出ないが、利用者が items の中身を読めばパスが得られる。**A-2 の
`readData` 経由と同じ経路がここにもある。** マニュアルで触れる。

画面注記「受け入れる型が無くても押せる」も、押せる状態であることを確認した（ただしこの
入力は accepted type を含むため、**「受け入れる型が 1 つも無い」状態は未確認**。それを作る
導線がサンプルに無い）。

---

## D: MS-07 のログ側 / MT-09

実施日: 2026-09-03

### 方法

`Log.d` は `logger.debug` である。**debug レベルは既定でディスクに永続化されない**ため、
`log show` で過去分を取ろうとしても欠落する。`log stream` で実行中に取得した。

```
/usr/bin/log stream --predicate 'subsystem == "com.unity.native.toolkit"' \
  --level debug --style compact > logstream.txt
```

> zsh には `log` ビルトインがあるため、**`/usr/bin/log` と絶対パスで呼ぶ**こと。

**検索語はサンプルのソースから導出した**（`sampleName` / `plainText` / `urlString` /
`detectionText`）。手で並べると、書き忘れた値が検査対象から外れる。

### 結果: 漏洩 0 件

取得 84 行。8 操作（`createPasteboard` ×2 / `copy` ×3 / `read` / `readData` / `detectValues` /
`removePasteboard`）がログに乗っていることを確認したうえでの 0 件である。**空回りしていない。**

| 検索対象 | 出現 |
|---|---|
| `nt-sample`（利用者が付けた名前） | 0 |
| `Copied from MacLibraryExample.`（コピーした値） | 0 |
| `https://www.apple.com` | 0 |
| `See https://... support@example.com.`（検出対象の文字列） | 0 |
| `/Users/jonghyunkim/Desktop/command.txt`（完全パス） | 0 |
| `command.txt`（ファイル名） | 0 |
| `support@example.com` | 0 |

### 秘匿の効き方（実測）

```
[createPasteboard] request: request(named:96821895)   ← nt-sample がハッシュ化
[removePasteboard] scope: scope(named:96821895)       ← 同じ名前は同じハッシュ
[createPasteboard] request: request(named:5a27574c)   ← 空文字は別のハッシュ
[detectValues] patterns: 3, scope: scope(general)     ← 検出結果ではなく件数だけ
[read] / [readData]                                    ← 型とバイト数のみ
```

**`ClipboardLog.request(_:)` が実機で機能していることを初めて確認した。** これはサンプル計画
レビュー v2 の高 1（`createPasteboard` 系 5 箇所が pasteboard 名を verbatim 出力する）を受けて
ライブラリ側に追加したものである。**同じ名前が同じハッシュになる**ので、ログ上で同一性は
追えるが値は復元できない。

### MT-09: プライバシー表示

1〜8 の全操作、および B の Paste Control 操作を通じて、**システムのプライバシー表示は
一度も出なかった**（貼り付け確認ダイアログ、メニューバー通知とも）。

**合否は付けない。** 機能設計 RK-22 が「どの経路も『通知なし』を保証しない」としており、
MT-09 は判定保留の観察項目である。**本日の環境（macOS 26.3、通常のユーザー操作）では出ない**
という記録にとどめる。

---

## MT-08: `localOnly` の Universal Clipboard 抑止

実施日: 2026-09-03

### 試行条件

| | |
|---|---|
| 端末 A | MacBook Air (arm64)、macOS 26.3 / 25D125 |
| 端末 B | **iPhone XS、iOS 18.7.2** |
| 接続 | 同一 Apple ID、Handoff 有効、Wi-Fi / Bluetooth 有効、近接 |
| 端末 B の読み取り | メモ App への貼り付け |

### 手順と結果

| # | 端末 | 操作 | 結果 |
|---|---|---|---|
| ① | A | `localOnly` OFF → `CopyWithCurrentOptions` | - |
| ① | B | 貼り付け | **約 1 秒で到達**（正の対照成立） |
| ② | B | `iphone-baseline-0903` をコピー | 端末 B の内容を Mac 由来でないものにする |
| ③ | A | `localOnly` ON → `CopyWithCurrentOptions` | Mac 側には入る |
| ③ | B | 約 1 秒待って貼り付け | **基準のまま。Mac の内容は届かない** |

**MT-08 クリア。`localOnly` が Universal Clipboard を抑止している。**

### ② が必要だった理由（実測で裏づけた）

**サンプルは `localOnly` の on / off で同じ文字列を書く**（`Copied from MacLibraryExample.`）。
そのため「端末 B にその文字列がある」だけでは、対照で届いたのか試行で届いたのかを区別
できない。**端末 B 側に別の基準を置く**ことで初めて判定できる。iOS 側の設計 §6.3 が
`Copy B Baseline` を要求しているのと同じ理由である。

**転送された内容は、次に何かがコピーされるまで受け取り側に残る。** ①を単独で再実行し、
**10 分後（:49 → :59）も端末 B が `Copied from MacLibraryExample.` を保持している**ことを
確認した。

**この保持時間が ② の必要性そのものである。** ②を省いて①→③と進めると、③で見えるのは
①の残りであり、それを「③で届いた」と誤読する。**その場合の結論は「`localOnly` が効いて
いない」という誤った失敗判定になる。** 手順から ② を落とすと、正しい実装を不合格にする。

### DocC の但し書きを更新した

`ClipboardCopyOptions.localOnly` は **`Its practical effect has not been verified on real
hardware yet.`** と書いていた（企画書 V-8 / V-9 が未消化のため）。**本日の実測で解消**し、
測定条件つきの記述に置き換えた。

**「保証する」とは書いていない。** 1 組の実測を全環境の保証に広げないため、機種・OS・所要
時間を添えて「この組み合わせでの証拠」として記述した。

### この測定の限界

当初の否定側の観測窓は約 1 秒だった。正の対照が約 1 秒で届いたので、iOS 設計 §6.3 の
「正の対照に要した時間以上を待機下限にする」規則は満たしている。ただし
**`localOnly: true` が「抑止」ではなく「大幅な遅延」だった場合、1 秒の窓では区別できない。**

**数分後に端末 B を再確認したところ、基準（`iphone-baseline-0903`）のままだった。**
観測窓が数分に広がったので、**遅延ではなく抑止**と判定できる。

---

## E: macOS 15.4.1 での再確認（仮想環境）

実施日: 2026-09-03 / 環境: tart VM `sequoia-15.4.1-probe`、**macOS 15.4.1 / 24E263**、arm64、8 GB RAM

### 方法

**ホストでビルドした `MacLibraryExample.app` をそのまま VM へ持ち込んだ。VM に Xcode は無い。**

- `MacLibrary.framework` はアプリに同梱されており、VM 側に追加の依存は不要
- バイナリの `LC_BUILD_VERSION minos` は **15.0**（プロジェクト設定の 15.1 は設定値であり、
  実バイナリはより低い）
- **`scp -r` は使えない。** symlink を実体化してフレームワーク構造を壊し、署名が無効になる。
  `tar czf - | ssh 'tar xzf -'` で構造を保って転送すると署名は有効なまま
- 開発署名 + hardened runtime のまま Gatekeeper に止められず起動した（`scp` 経由なので
  quarantine 属性が付かない）

### 結果: 26.3 と同一

| 観点 | 26.3 | 15.4.1 |
|---|---|---|
| Paste Control（受け入れる型） | `items=1, failures=0, partial=false` | **同じ** |
| **Paste Control（`CopyPartialPasteContent`）** | **`items=1`**（受け入れない型は落ちる） | **同じ** |
| representation の顔ぶれ | `rtf` / `utf8` / `utf16-external` | **同じ** |
| 検出（`DetectPatterns` / `DetectValues` / `DetectMetadata`） | 検出成功 / 1515 | **同じ** |
| プライバシー表示（MT-09） | 出ない | **同じ** |

### この確認の意味

**「1521 は到達不能」という結論が 26.3 限定ではないことを確かめた。** システムの `PasteButton`
が `supportedContentTypes` で絞る挙動は 15.4.1 でも同じである。計画 §6.6 の訂正は、
**サポート範囲の下寄りでも成立する。**

MT-09 も同様で、**15.4.1 でもプライバシー表示は出なかった**。RK-22 の判定保留は維持する
（「出ない」を保証する根拠にはならない）。

### 仮想環境で確認できなかったもの

| 項目 | 理由 |
|---|---|
| 自動テスト 34 件 | **VM に Xcode が無い。** `xcodebuild` は CLT のスタブ、`xctest` は Xcode にしか無い。ホストの Xcode 26.3 は `LSMinimumSystemVersion 15.6` のため 15.4.1 では動かない |
| MT-07 の 1513 側 | 15.4 未満の環境が必要 |
| MT-08 | **VM は iCloud にサインインできず Handoff が使えない**（実機で実施済み） |

**自動テストを 15.4.1 で回しても新しい情報は出ない。** 34 件のうち OS バージョンで結果が
変わりうるのは検出まわりだけで、その分岐（`#available(macOS 15.4, *)`）は 15.4.1 でも 26.3 でも
同じ側を通る。**15.4 未満の環境を用意した場合に限り、自動テストの再実行に意味が出る。**

---

## 総括

### 実施状況

| 区分 | 観点 | 状態 |
|---|---|---|
| A-1 | MT-02 コピー → 他アプリで貼り付け | **完了** |
| A-2 | MT-01 他アプリでコピー → `Read` | **完了**（上記） |
| A-3 | MT-03 append の所有権 | **完了**（上記） |
| A-4 | MT-04 監視 | **完了** |
| B | MT-06 Paste Control / 要検証 2 件 | **完了**（要検証は 2 件とも解決） |
| C | MT-07 検出 | **実施不可**（15.4.1 と 15.2 が必要。実施端末は 26.3） |
| D | MS-07 のログ側 / MT-09 | **完了** |
| - | MT-08 `localOnly` | **完了**（iPhone XS / iOS 18.7.2） |
| - | MS-06 | **確認手段なし**（計画 v5 §8.2 に理由を記載） |

### 実装の欠陥: 0 件

**MT-01 / MT-02 / MT-03 / MT-04 / MT-06、および MS-07 のログ側は、すべて設計どおりだった。**
実装レビュー 5 ラウンドを経た後なので、ここは想定どおりである。

### 見つかったもの

| 種別 | 内容 | 対応 |
|---|---|---|
| **契約の訂正** | **1521 は到達不能**。システムの `PasteButton` が `supportedContentTypes` で絞る | 計画 §6.6 を 10 / 8 に訂正。`CopyPartialPasteContent` の目的を書き直し |
| 要検証の解除 | 平文の `detectMetadata` は 1515 | 期待値は正しかった |
| **DocC の欠落** | `checkForegroundChange` と監視が基準を共有すること | `MacClipboardManager` に追記 |
| 導線の欠落 | MT-03 の「他者所有時」 | `AppendWithLastOwnership` を追加（同日） |
| 自動化の取りこぼし | MS-04 / MT-03 | UI テスト化（同日） |
| 分類の誤り | MS-06 は「自動化不可」ではなく**確認手段なし** | 計画 §8.2 を訂正 |

### マニュアルに書くべき挙動（実機でしか分からないもの）

1. **複数 item は全部渡り、どれを使うかは受け取る側が決める**（TextEdit は全部貼る）
2. **representation は書いた側の意図より多くなる**（AppKit がテキスト flavor を自動で載せる）
3. **`bytes` は全 representation の合計**。ファイル 1 個のコピーで約 850 KB になる（`com.apple.icns` が大半）
4. **ファイルのコピーは平文表現を持ち、その中身は一般に完全パス**。`readData` でも `PasteButton` でも取得できる
5. **`checkForegroundChange` は監視と併用すると常に `false`**（基準を共有するため）

### 残り

| 項目 | 理由 |
|---|---|
| MT-07 | **実施不可**。15.4.1 と 15.2 の両方が必要で、実施端末は 26.3 |
| MT-08 | **完了**。ただし否定側の観測窓は約 1 秒（上記の限界） |
| MS-06 | 確認手段なし |
| MT-01〜MT-06 の 15.x での再確認 | **15.4.1（VM）で主要 4 観点を再確認し、26.3 と同一だった**（§E）。A-3 / A-4 は OS 依存が薄いため未再実施 |
| **検出のエラー系 2 件（1513 / 1514）** | **未実行。** 下記のとおり記録のみ残し、対応は次に回す |

---

## 付録: 手動確認の手順（訂正済み・再実行用）

**本日の実施で 3 箇所の誤りが見つかったため、訂正した版をここに残す。** macOS 15.x での再確認は
この手順で行う。

### 前提

```
cd mac
xcodebuild build -workspace MacWorkspace.xcworkspace -scheme MacLibraryExample -destination 'platform=macOS'
open ~/Library/Developer/Xcode/DerivedData/MacWorkspace-*/Build/Products/Debug/MacLibraryExample.app
```

- Active scope は **`general`** から始める（他 scope だと他アプリのコピーは見えない）
- 相手役: TextEdit（平文とリッチテキスト）、Preview（画像）、Finder（ファイル）
- ログを見る手順（D）では **`/usr/bin/log stream`** を先に開始する。zsh の `log` ビルトインを
  避けるため絶対パスで呼ぶ

### A-1: MT-02 — コピー → 他アプリで貼り付け

| # | 操作 | 期待 |
|---|---|---|
| 1 | `CopyText` → TextEdit で ⌘V | `Copied from MacLibraryExample.` |
| 2 | `CopyURL` → ⌘V | `https://www.apple.com` |
| 3 | `CopyImage` → Preview「ファイル > クリップボードから新規作成」 | 画像が開く |
| 4 | `CopyMultipleItems` → ⌘V | **`first` と `second` の両方**（受け取る側が全 item を使う） |
| 5 | `CopyMultipleRepresentations` → リッチテキストで ⌘V | `Copied from MacLibraryExample.` |

> **訂正 1**: 4 の期待値を「先頭のみ」から「両方」へ。`NSTextView` は全 item を読む。

### A-2: MT-01 — 他アプリでコピー → `Read`

| 入力 | ボタン | 期待 |
|---|---|---|
| 平文 | `Read` / `Snapshot` / `SnapshotFiltered` | 読める |
| 平文 | `AccessBehavior` | 値を記録（本日は `alwaysAllow`） |
| リッチテキスト | `Read` | `public.rtf` / `public.utf8-plain-text` ほか。**意図より多い**のが正常 |
| 画像 | `ReadDataPlainText` | **`no such type (success)`**（エラーではない） |
| ファイル | `Read` | **完全パスが画面に出ないこと**。`bytes` は全 representation の合計 |

### A-3: MT-03 — append の所有権

| # | 経路 | 操作 | 期待 |
|---|---|---|---|
| ① | **対照** | `CopyText` → 直後に `AppendWithLastOwnership` | **成功** |
| ② | 他者所有 | `CopyText` → 他アプリで ⌘C → `AppendWithLastOwnership` | **1511** |
| ③ | 自所有 | `CopyThenAppend` | 成功 |
| ④ | 自アプリが無効化 | `AppendWithStaleOwnership`（ボタン 1 つで完結） | `expected 1511 as designed` |

> ① を先に置く。②の 1511 が外部のコピーに由来すると言うための対照である。

### A-4: MT-04 — 監視

| # | 操作 | 期待 |
|---|---|---|
| ① | `StartObserving` → 他アプリで ⌘C ×2 | 0.5 秒以内に `[observed]` |
| ② | 非アクティブにして ⌘C ×3 | ログに `[suspendPolling]` |
| ③ | サンプルに戻る | `[resumePolling]` → **イベントは 1 回だけ**、changeCount は 3 進む |
| ④ | **先に `StopObserving`** → 他アプリで ⌘C → `CheckForegroundChange` ×2 | `true` → `false` |
| ⑤ | 停止したまま ⌘C | 結果が変わらない |

> **訂正 2**: ④ の前に `StopObserving` を置く。監視と `checkForegroundChange` は基準を共有する
> ため、監視中は `false` になる（それが正しい）。

### B: MT-06 — Paste Control

| # | 操作 | 期待 |
|---|---|---|
| 1 | `CopyText` → Paste ボタン | `items=1, failures=0, partial=false` |
| 2 | `CopyImage` → Paste | 同上 |
| 3 | `CopyPartialPasteContent` → Paste | **`items=1`**（受け入れない item は落ちる） |
| 4 | Finder のファイル → Paste | **`items=1`**（平文表現＝パスが読まれる） |
| 5 | `MakePasteButtonInvalidType` / `UndeclaredType` | 1504 |
| 6 | `DetectPatterns` / `DetectValues` / `DetectMetadata` | 期待どおり / 1515 |

> **訂正 3**: 3 の期待を「部分失敗（1521）」から「`items=1`」へ。1521 は到達不能（§6.6）。

### D: MS-07 のログ側 / MT-09

1. `/usr/bin/log stream --predicate 'subsystem == "com.unity.native.toolkit"' --level debug --style compact > log.txt` を開始
2. `CreateNamedPasteboard` / `CreateEmptyNamedPasteboard` / `RemoveCurrentPasteboard` /
   `CopyText` / `CopyURL` / `DetectValues` / ファイルを ⌘C して `Read` / `ReadDataPlainText`
3. ストリームを止め、**サンプルのソースから導出した値**で grep（手で並べない）
4. 操作がログに乗っていることを併せて確認する（**空回りしていないことの確認**）
5. 同時にプライバシー表示の有無を観察（MT-09、合否なし）

### MT-08: `localOnly`

前提: 同一 Apple ID、Handoff 有効、Wi-Fi / Bluetooth 有効、近接。両端末の機種・OS・ビルドを記録。

| # | 端末 | 操作 | 期待 |
|---|---|---|---|
| ① | A | `localOnly` OFF → `CopyWithCurrentOptions` → B で貼り付け | **届く**（所要時間を記録） |
| ② | B | 端末 B 側で別の文字列をコピー | 基準を置く |
| ③ | A | `localOnly` ON → `CopyWithCurrentOptions` | Mac 側には入る |
| ③ | B | ①の所要時間以上待って貼り付け | **基準のまま** |
| ④ | B | **5 分以上空けて再確認** | 基準のまま（遅延ではなく抑止） |

> ② が要る。**サンプルは on / off で同じ文字列を書く**ので、端末 B に別の基準を置かないと
> 対照と試行を区別できない。①が失敗した試行は無効（判定しない）。
>
> **②を省くと、正しい実装を不合格にする。** 転送された内容は次のコピーまで受け取り側に
> 残る（**10 分間の保持を実測**）。①→③と進めると、③で見えるのは①の残りであり、それを
> 「③で届いた」＝「`localOnly` が効いていない」と誤読する。

**④ の間に守ること**（破ると試行が無効になる）

| | 理由 |
|---|---|
| 端末 B で何もコピーしない | 基準が消え、「基準のまま」と言えなくなる |
| 端末 A で何もコピーしない | 新しい内容が載ると、届いたのがどちらか分からない |
| 端末 A をスリープさせない、アプリを終了しない | 転送は送り手が提供する。**寝ていて届かなかっただけ**なら抑止の証拠にならない |

貼り付け（読み取り）は何度行ってもよい。クリップボードは変わらない。

**5 分の根拠**: 正の対照が約 1 秒だった。300 倍の窓で届かなければ「遅延」では説明できない。
③ だけでは「1 秒以内には届かない」しか言えず、**抑止と遅延を区別できない**。

| ④ の結果 | 判定 |
|---|---|
| 基準のまま | **抑止。MT-08 確定** |
| 端末 A の内容 | **遅延だった。③ の判定を取り消し、DocC の記述も戻す** |
| 別の何か | 途中でコピーが入っている。**試行無効**、①からやり直し |

### 実施できない項目

| 項目 | 理由 |
|---|---|
| MT-07 | macOS 15.4.1 と 15.2 の 2 環境が必要 |
| MS-06 | 確認手段なし（遅い provider を作れない） |

---

## 付記: 未実行のまま残す検出エラー 2 件

検出まわりに、**どの環境でも一度も実行されていない分岐が 2 つ**ある。優先度が低いと判断し、
本リリースでは記録のみとする。

| コード | 発生条件 | 分岐の中身 | 未実行の重さ |
|---|---|---|---|
| **1513** `detectionUnavailable` | macOS 15.4 未満 | 定数 `detectionMinimumOS` を投げるだけ | **軽い** |
| **1514** `detectionDenied` | 利用者が読み取りを拒否 | **システムの `NSError` を判別している** | **重い** |

### 1513: API が存在しないだけ

`NSPasteboard.DetectedValues` と検出メソッド一式は **macOS 15.4 で新規に追加された**。
15.4 未満には型もメソッドも無く、`ClipboardDetectionMapper` 自体が `@available(macOS 15.4, *)`
である。**「挙動が変わる」のではなく「呼べるものが無い」。**

```swift
guard #available(macOS 15.4, *) else {
    throw ClipboardError.detectionUnavailable(minimumOS: Self.detectionMinimumOS)
}
```

コンパイラが `#available` の外で新 API を参照させないため、**この分岐に環境依存の余地はない。**
確認できていないのは「ガードに到達したとき 1513 が返るか」の一点であり、4 箇所とも同じ 1 行。

### 1514: システムのエラー判別に依存している（こちらが本題）

```swift
if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
    return .detectionDenied
}
return .detectionFailed(nsError.localizedDescription)
```

**この判別が実際に当たるかは、拒否を一度も起こしていないので分からない。** 外れていれば
1514 ではなく **1515（`detectionFailed`）** が返る。

**しかも 1515 は fallback なので、判別を間違えても何も壊れず、静かに別のコードが返る。**
Unity 側は「拒否された」を検出できず、通常の失敗として扱う。**失敗の仕方が静かである**点が、
1513 との違いである。

本日 `DetectMetadata` で 1515 を確認したが、**あれは「拒否ではない失敗」の経路**であり、
判別が正しいことの証拠にはならない。

### 確認手段そのものが未確定

検出の拒否をどう起こすかが分かっていない（システム設定で切るのか、初回ダイアログで拒否
するのか）。**26.3 でも 15.4.1 でも、検出に関するダイアログは一度も出なかった。**
拒否の導線が存在するのかも未確認である。

### 次に対応するときの手順

1. 拒否の導線を特定する（システム設定 / 初回ダイアログ / MDM 等）
2. 拒否状態で `DetectPatterns` を押し、**1514 が返ることを確認**する
3. 1515 が返った場合、`detectionError(from:)` の判別条件を実測した `NSError` に合わせる
4. 1513 は 15.4 未満の環境（VM で可）で 1 回押せば済む

---

## 付記: iOS M-06 / M-16（Mac を端末 B として実施）

実施日: 2026-09-03 / 端末 A: iPhone XS（iOS 18.7.2、NTKIT-14 サンプル） / 端末 B: 本 Mac（macOS 26.3）

**これは NTKIT-14（iOS）の観点である。** Mac は端末 B として使った。iOS 側の設計
`2026-08-09-ios-clipboard-sample-app-design-v6.md` §6.3 の手順に従う。
**iOS 側の §6.5 trial 結果表への記録は別途必要。**

### 端末 B の判別方法を用意した

iOS 設計 §6.3 は端末 B に **`index / hasText / textLength`** の表示を要求している。
本 Mac のサンプルは `items=N, bytes=N` しか出しておらず、**`bytes` は全 item・全 representation の
合計**なので fixture を判別できなかった（AppKit が `utf16-external` を足すため文字数とも一致しない）。

`Read` を **item ごとの平文バイト数**を出す形に変更した。

```
[read] items=1, bytes=93, [0:text=30B public.utf16-external-plain-text|public.utf8-plain-text]
```

| 長さ | 何か |
|---:|---|
| 14 | trial body（`LOCALONLY-BODY`、端末 A） |
| 24 | append marker（端末 A） |
| **30** | 端末 B の baseline（`Copied from MacLibraryExample.`。iOS 設計の 31 文字 sentinel に相当） |

### 結果

| 観測 | 値 |
|---|---|
| 手順 3（正の対照、`localOnly = false`） | **`text=14B` が端末 B に到達。試行は有効** |
| 手順 8（`bodyBeforeAppend`） | **30B のみ** |
| 手順 10（`bodyAfterAppend` / `appendAfterAppend`） | **30B のみ** |
| bit | **`000`** |

### 帰結

> **append は、元の item が持つ local-only の状態を引き継ぐ。pasteboard 全体を再公開しない。**

**D-8 を維持し、R-13 の追加 API は不要。** 企画段階で開いていた設計判断が 1 つ閉じた。

### 事前 signature 確認（手順 6）について

手順 6（端末 B に 14B / 24B の item が事前に無いこと）は明示的に記録していない。
**ただし `000` という判定に限っては、この確認は効かない。** 事前に 14B が残っていた場合、
⑧⑩で 14B が**見える**方向に働くため、汚染は `1xx` を生むのであって `000` を偽造できない。
**手順 6 が効くのは `1xx` が出たとき**である。

### M-06

手順 3 で `localOnly = false` の内容が端末 B へ到達した。**M-06（Universal Clipboard）は成立。**
iOS 設計 §8.2 のとおり、M-16 の正の対照を共用して判定した。
