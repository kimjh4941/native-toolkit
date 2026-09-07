# iOS Clipboard M-06 / M-16 実測結果 v1

## 基本情報

- 日付: 2026-09-03
- 機能名: clipboard（**iOS 側の観点。NTKIT-14**）
- 設計: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md` §6.3 / §6.5
- 実施ブランチ: `feature/NTKIT-15`（macOS 側。**端末 B として macOS サンプルを使ったため、記録もこちらに置く**）
- 端末 A: iPhone XS / iOS 18.7.2（iOS サンプルアプリ）
- 端末 B: MacBook Air (arm64) / macOS 26.3 / 25D125（`MacLibraryExample`）

> **iOS は既にリリース済みである。** 本測定は、リリース後まで開いていた設計判断
> （D-8 / R-13）に答えを出すものであり、**結果が `001` 系であれば公開済み API の不足**を
> 意味した。実測は `000` で、追加 API は不要という結論になった。

---

## 1. 端末 B の判別手段を用意した

設計 §6.3 は端末 B に **`index / hasText / textLength`** の表示を要求している。macOS サンプルの
`Read` は `items=N, bytes=N` しか出しておらず、**`bytes` は全 item・全 representation の合計**で
あるため fixture を判別できなかった（AppKit が `utf16-external-plain-text` を自動で足すので、
文字数とも一致しない）。

`Read` を item ごとの平文バイト数を出す形へ変更した（`ClipboardSampleView.swift`）。

```
[read] items=1, bytes=93, [0:text=30B public.utf16-external-plain-text|public.utf8-plain-text]
```

| 長さ | fixture | 置く端末 |
|---:|---|---|
| 14 | trial body（`LOCALONLY-BODY`） | A |
| 24 | append marker | A |
| **30** | 端末 B の baseline（`Copied from MacLibraryExample.`） | B |

**設計の 31 文字 sentinel は端末 B が iOS である前提の値。** 端末 B が macOS の場合は
サンプルの固定文字列 30 文字がその役割を果たす。14 / 24 と重ならないので判別に支障はない。

---

## 2. trial 結果表（設計 §6.5 の形式）

| trial | A端末 / OS build | B端末 / OS build | account・Handoff・Wi-Fi・BT | B Paste許可 | 正対照 / 秒 | B事前signature | 待機秒（前/後） | bodyBefore | bodyAfter | appendAfter | bit | 有効性 | 結論 | D-8 / R-13 | 追跡 |
|---|---|---|---|---|---|---|---|---:|---:|---:|---|---|---|---|---|
| M16-001 | iPhone XS / iOS 18.7.2 | MacBook Air / macOS 26.3 (25D125) | 同一 account、Handoff・Wi-Fi・BT 有効、近接 | 該当なし（B は macOS） | **成功 / 約 1 秒** | 未記録（下記参照） | 正対照実測以上 | **非転送** | **非転送** | **非転送** | **`000`** | **有効** | append は local-only を維持 | **D-8 維持 / R-13 追加 API 不要** | — |

### 記録規約に対する補足

- **`正対照`**: 手順 3 で `Copy (localOnly = false)` の 14B body が端末 B に到達。**成功**
- **`B Paste許可`**: 設計は端末 B が iOS である前提の欄。**端末 B が macOS のため該当しない**
  （macOS は貼り付け許可の事前状態を持たない）
- **`B事前signature`**: 手順 6 を明示的に記録していない。**ただし `000` という判定に限り、
  この欠落は結論を脅かさない**（§3 参照）

---

## 3. 手順 6 の欠落が `000` を脅かさない理由

設計 §6.3 は、事前 signature に 14 / 24 文字 item が無いことを試行の有効条件としている。今回は
その確認を明示的に記録していない。

**汚染は `1xx` を生む方向にしか働かない。** 端末 B に 14B が事前に残っていれば、⑧⑩の `Read` で
**14B が見えてしまう**。つまり汚染があると「転送された」と誤読する。**`000`（どこにも 14B が
現れない）を汚染で作ることはできない。**

**手順 6 が本当に効くのは `1xx` が出たとき**である。そのときは「今回の転送か前回の残りか」を
区別できないため、試行をやり直す必要がある。

---

## 4. 帰結

### M-16（append の privacy 継承）

> **append は、元の item が持つ local-only の状態を引き継ぐ。pasteboard 全体を再公開しない。**

`bodyBeforeAppend / bodyAfterAppend / appendAfterAppend` がすべて非転送であり、設計 §6.3 の
bit 表では `000` に該当する。**D-8 を維持し、R-13 での追加 API 検討は不要。**

**リリース後に確認した判断であるため、結果が `001`（append item に privacy option が継承
されない）だった場合は、公開済み API に不足があることになっていた。** 実測はそうならなかった。

### M-06（Universal Clipboard）

手順 3 で `localOnly = false` の内容が端末 B へ到達した。**成立。** 設計 §8.2 のとおり M-16 の
正の対照を共用して判定した。

### 双方向で確かめたこと

同日に macOS 側の MT-08（Mac → iPhone）も実施している。

| 測定 | 方向 | `localOnly = false` | `localOnly = true` |
|---|---|---|---|
| MT-08 | Mac → iPhone | 約 1 秒で到達 | **数分待っても届かない** |
| **M-16** | **iPhone → Mac** | 到達 | **append の前後とも届かない** |

**送り手を入れ替えても同じ結果である。** 片方向だけなら送信側 OS の挙動である可能性が残るが、
両方向で一致したことで、`.currentHostOnly`（`localOnly` の実体）が名前どおり働いていると言える。

---

## 5. この測定の範囲

| 確かめた | 確かめていない |
|---|---|
| macOS 26.3 ↔ iOS 18.7.2 の 1 組 | 他の端末・OS の組み合わせ |
| 平文での抑止 | 画像・ファイルなど他の型 |
| 数分の観測窓 | それ以上長い窓 |
| 1 trial | 設計 §6.5 は複数 trial の追記を想定している |

**設計 §6.5 は「有効な再試行は新しい trial ID で追記し、失敗した trial を上書きしない」と
定めている。** 本表は `M16-001` の 1 行のみであり、他の組み合わせでの trial は未実施である。
