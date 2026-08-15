# iOS Clipboard サンプルアプリ実装結果 v3（手動確認の実施結果）

## 基本情報

- 日付: 2026-08-15
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 計画ファイル: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md`
- 実装結果 v2: `artifact/results/clipboard/2026-08-11-ios-clipboard-implement-sample-app-result-v2.md`
- レビュー: `artifact/reviews/clipboard/2026-08-11-ios-clipboard-implement-sample-app-review-v1.md`
- 実機: iPhone XS / iOS 18.7.2
- 対応タスク: 設計書 T-12

v2 までは自動テストのみの結果だった。本レポートは**ユーザーが実機で実施した手動確認の結果**と、
そこで見つかった不具合の修正、および未確定だった設計事項の決着をまとめる。

**v2 から画面実装・自動テストの構成は変わっていない部分が多いため、差分のみ記載する。**

---

## 1. 手動確認で見つかった不具合と修正

### 1.1 無効化されたボタンがグレー表示にならない

**手動確認でのみ検出できた不具合。** 自動テストは通過していた。

| | 内容 |
|---|---|
| 事象 | `.disabled(true)` のボタンが有効時と同じ青色で表示される |
| 影響 | 設計 §4.4 の活性条件と §8.1 #16「観測中は Scope セクションが無効」が**目視で確認できない** |
| 原因 | `FullWidthPressableButtonStyle` が `isEnabled` を参照していない。`ButtonStyle.Configuration` は `isPressed` しか持たず、かつ `ButtonStyle` は `View` ではないため `@Environment` が追随しない |

**修正**: `makeBody` からネストした `View` を返し、そこで `@Environment(\.isEnabled)` を読む形にした。

```swift
func makeBody(configuration: Configuration) -> some View {
    StyleBody(configuration: configuration)
}

private struct StyleBody: View {
    @Environment(\.isEnabled) private var isEnabled
    ...
    private var background: Color {
        guard isEnabled else { return Color.gray.opacity(0.45) }
        return configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue
    }
}
```

**自動テストで検出できなかった理由**: U-6 は `isEnabled == false` を判定しており、
**機能としては正しく無効化されていた**。XCUITest が見るのは描画ではなくアクセシビリティ属性である。
表示の問題は目視でしか検出できない。

影響範囲は `Probe Last Removed Scope` / Scope セクション 6 ボタン / `Start Observing` /
`Stop Observing` / `Observe Unresolvable Named` の全体。修正後、目視で確認済み。

---

## 2. 未確定だった設計事項の決着

### 2.1 Detect の未検出 2 種 — **fixture の構造的限界だった**

計画 §5.7 は「検出されなかったパターンは fixture の不備か API の挙動かを切り分けて記録する」
としていた。実機で切り分けた結果、**API は正常**である。

| fixture | 内容 | 検出数 | `number` | `probableWebSearch` |
|---|---|---:|---|---|
| `Copy Detection Fixture` | 4 行の混在テキスト | **9 / 11** | 未検出 | 未検出 |
| `Copy Number Fixture` | `42` のみ | — | **検出** | — |
| `Copy Search Fixture` | `swift concurrency` のみ | — | — | **検出** |

混在テキストからの検出結果（`Detect Patterns` / `Detect Values` で完全一致）:

```
calendarEvent, emailAddress, flightNumber, link, moneyAmount,
phoneNumber, postalAddress, probableWebURL, shipmentTrackingNumber
```

この 2 種は**クリップボードの内容全体がその値である場合にのみ報告される**。
他の内容が混ざった文章からは抽出されない。したがって「11 種すべてを 1 つの fixture に詰める」
という当初の方針では、構造的にこの 2 種を検証できなかった。

> **留保**: `probableWebURL` は同じ iOS 16 世代でありながら混在テキストからも検出されている。
> 「iOS 16 世代は全体評価、iOS 17 追加分は抽出」という単純な世代論では説明しきれない。
> 実務上の規則（この 2 種は単独 fixture が必要）は確立したが、内部の判定機構は断定しない。

**対応**: 隔離 fixture 2 つを Detect セクションへ追加（結果 marker 50 → 52）。
単体テストで「他パターンを含まないこと」（`http` / `@` / 改行を含まない）を固定した。

ロケール依存で落ちると想定していた `postalAddress`（米国住所形式）と `flightNumber`（`AA100`）は、
いずれも検出された。

### 2.2 L-3 の対応外 fixture — **作成可能だった**

計画 §1.6 / §8.1 #20 は「Files 由来 provider が `public.file-url` やプレビュー画像も広告しうるため、
対応外のみの fixture を作れない可能性がある。決定的な fixture を特定できなければ harness へ委譲する」
としていた。**この懸念は現実化しなかった。**

受付型は `public.plain-text` / `public.url` / `public.image` の 3 つ。

| 候補 | 広告された型識別子 | 受付型との一致 |
|---|---|---|
| **PDF（Files）** | `com.apple.DocumentManager.FPItem.File`, `com.adobe.pdf` | **なし** |
| **zip（Files）** | `com.apple.DocumentManager.FPItem.File`, `public.zip-archive` | **なし** |
| 連絡先 | `CNContactIdentifiersPboardType`, `CNLinkedContactsIdentifiersPboardType`, `public.vcard`, `com.apple.contacts.vCardDisplayNames`, `com.apple.contacts.contact.persisted`, `com.apple.uikit.useractivity` | なし |

`public.file-url` は広告されず、Apple 独自の `com.apple.DocumentManager.FPItem.File` が使われていた。
これは `public.url` に conform しないため受付型に一致しない。

**PDF と zip はどちらも決定的な L-3 fixture として使える。harness への委譲は不要。**

#### 副次的な発見: `has*` フラグは貼り付け可否の判定に使えない

連絡先のケースは `hasStrings=true` だが、受付型には一致しない。
`public.vcard` は `public.text` に conform する一方、`public.plain-text` とは兄弟関係にあるためである。

| 判定方法 | 連絡先での結果 | 正しいか |
|---|---|---|
| `hasStrings` | true | **誤り**。貼り付けできない |
| `acceptedTypes` の conform 判定 | 不一致 | 正しい |

ライブラリが `makePasteControl(acceptedTypes:)` という形を採る設計は妥当だった。

> この切り分けは、本作業で `Snapshot` に型識別子**名**の表示を追加したことで可能になった。
> 個数のみの表示では「何が広告されていたか」が分からない。

---

## 3. 手動確認の結果

実施環境: iPhone XS / iOS 18.7.2 実機。

| # | 項目 | 結果 |
|---|---|---|
| 1 | 無効表示がグレーになるか | **確認済み**（1.1 の修正後） |
| 3 | Paste Control L-1〜L-3 | **確認済み**（2.2） |
| 4 | M-15 ログに機微情報が出ていないこと | **確認済み**。検索語 12 件すべて 0 件 |
| 2 | K-4 named ペーストボードの終了後寿命 | **進行中**（4 章） |

A〜E / G〜J（基本・Copy・Append・Load・Scope・監視・Error Cases）は先行して実施済みで問題なし。

### 3.1 M-15 の検証内容

次の操作を一通り実行したうえでコンソールを検索した。

`Copy Plain Text` / `Copy URL` → `Load URL` / `Copy Image File` → `Load Image` /
`Copy File Fixture` → `Load File` / `Copy Detection Fixture` → `Detect Patterns` → `Detect Values` /
`Copy (localOnly = true)` / `Append Universal Marker` / `Create Unique Pasteboard` /
Error Cases 11 件 / `Snapshot`

検索語（すべて 0 件）:

```
Hello from / LOCALONLY / APPENDED-MARKER / apple.com / example.com / Infinite Loop /
996-1010 / 1Z999AA / app-icon-attachment / IosLibraryClipboard / /var/ / example.sample
```

クリップボードの値・ファイルパス・URL・pasteboard 名のいずれも出力されていない。
pasteboard 名は `redactedDescription` により `named(nameLength:44)` の形にとどまる。

> K-4 の測定を壊さないため、`Create Named Pasteboard` / `Remove Active Pasteboard` は使わず、
> `Create Unique Pasteboard` で同じ redaction 経路を検証した。

---

## 4. K-4 / M-08 の測定（**進行中**）

### 4.1 測定条件

preflight（`Create Named` → `Remove Active` → `Use Fixed Named Scope (no create)` → `Read` で
`CLIPBOARD_UNAVAILABLE` を確認）を経てから作成しているため、**測定対象がこのプロセスの作成物である
ことは担保されている**。

作成後に `Copy Plain Text`（28 文字）を書き込み、App Switcher から完全終了。

### 4.2 経過（2026-08-15 09:19 開始 / iPhone XS / iOS 18.7.2）

| 経過 | 結果 | 状態 |
|---|---|---|
| 1 分 | `numberOfItems=1, items=[0:text(len=28) ...]` | 存在あり・中身あり |
| 5 分 | `numberOfItems=1` | 存在あり・中身あり |
| 15 分 | `numberOfItems=1` | 存在あり・中身あり |
| 1 時間 | 未取得 | — |

**これまでの最長観測（Simulator 90 秒 / 実機 28 秒）を大きく上回る。**

### 4.3 現時点で言えること

ライブラリの公開 DocC はこう記述している。

```
they exist only while the app that created them is running
```

作成プロセスは終了済みで、15 分後も中身ごと読める。**この文言は書かれているとおりには成立していない。**

### 4.4 未解消の交絡 — 定期確認そのものが寿命を延ばしている可能性

確認のたびにアプリを起動しているため、「作成アプリが動いていない状態が 15 分続いた」とは
厳密には言えない。OS が「同一バンドルの起動で寿命を延長する」挙動を持つ場合、
**測定行為が回収を妨げている**ことになる。

**解消手順**: 1 時間確認の後、**アプリを一切起動しない区間**を数時間（可能なら翌朝まで）置き、
そのあと 1 回だけ確認する。

| 放置後の結果 | 結論 |
|---|---|
| `CLIPBOARD_UNAVAILABLE` | 定期確認が寿命を延ばしていた。頻繁な起動をやめれば回収される |
| `numberOfItems=1` | 起動と無関係に残る。**公開契約の記述を訂正する必要がある** |
| `numberOfItems=0` | 中身だけ回収された。存在と中身が別管理と確定 |

### 4.5 判定

**保留のまま。** v2 の判定（ライブラリ不具合とも非不具合とも確定できない）を維持する。
4.4 の交絡を潰すまで、観測データから結論を出さない。

---

## 5. T-13（実機手動確認）の部分実施結果

2 台目の端末を要しない 4 項目を実施した。実施環境は特記なき限り iPhone XS / iOS 18.7.2 実機。

| M-ID | 観点 | 結果 |
|---|---|---|
| **M-07** | `expirationDate` 経過後 | **合格** |
| **M-12** | 一時ファイル cleanup | **部分実施・合格**（Simulator） |
| **M-13** | 画像コスト | **部分実施**。有意差を検出できず |
| **M-14** | 二重報告なし | **合格** |

### 5.1 M-07 — 合格

`Copy (expires in 30s)`（`expirationDate = +30s`、`expiring body` = 13 文字）を general scope へ書き込み、
経過ごとに `Read` した。

| 経過 | 結果 |
|---|---|
| 0 秒 | `numberOfItems=1, items=[0:text(len=13) ...]` |
| 35 秒 | `numberOfItems=0, []` |
| 60 秒 | `numberOfItems=0, []` |
| 2 分 | `numberOfItems=0, []` |

**`expirationDate` は機能している。**

> **留保**: 35 秒時点で消えていたが、「30 秒経過で消えた」のか「35 秒の `Read` が契機で消された」のかは
> この試行では区別できない。切り分けるには、コピー後に一切アクセスせず 2 分放置してから初回 `Read` する
> 試行が要る。M-07 の DoD は満たしているため必須としない。

### 5.2 M-12 — 部分実施・合格（Simulator）

**実機では実施不可。** 手順に「session ディレクトリの更新日時を 24 時間より古くする」が必要だが、
実機のアプリ内 tmp の mtime は書き換えられない。設計 §8.2 の想定どおり Simulator（iOS 26.2）で実施した。

cleanup の仕様（実装から確認）:

| 項目 | 内容 |
|---|---|
| 実行契機 | `ClipboardTemporaryFileStore.init`（manager の初回参照時）。プロセスにつき 1 回 |
| 削除対象 | **他セッション**のディレクトリで、`contentModificationDate` が **24 時間以上前**のもの |
| 除外 | active session は必ず除外 |

**対照付きで検証した。**

| ディレクトリ | mtime | cleanup 後 |
|---|---|---|
| `AAAAAAAA-…-OLDSESSION01` | 3 日前（24h 超） | **削除された** |
| `BBBBBBBB-…-NEWSESSION01` | 現在時刻（24h 以内） | **残った**（mtime も保持） |

#### 対照が必須である理由（再測定時の注意）

検証中にアプリのデータコンテナ UUID が変わった（UI テスト実行時の再インストールによる）。
`NEWSESSION01` が mtime ごと残っていたことから**データは引き継がれており一括削除ではない**と判定できたが、
**対照がなければ「cleanup が消した」のか「再インストールで消えた」のか区別できなかった。**
T-13 で再測定する場合も 24 時間以内のディレクトリを必ず併置すること。

#### active session 除外は観測不能

session ディレクトリは `init` では作られず、`store()`（実ファイル load）で初めて作られる。
cleanup が走る時点では active session のディレクトリが存在しないため、
**「除外された」のか「そもそも無かった」のか区別できない。**
設計 §8.2 のとおり、`fileManager` と `sessionID` を注入できる harness へ委譲する。

### 5.3 M-13 — 部分実施・有意差なし

対象は 1024×1024 / 150 KB の PNG（バンドル画像）。Instruments の Allocations で
Generation 分析（`Mark Generation`）を用いた。

| Generation | Growth | # Persistent | 対応区間 |
|---|---:|---:|---|
| A | 13.36 MiB | 45,597 | `Copy Image Data` |
| B | 1.13 MiB | 3,925 | `Copy Image File` |
| C | 231 KiB | 524 | `Load Image` |
| D | 827 KiB | 2,449 | **操作なし**（ノイズ水準） |

**この指標では経路間のコストを比較できない。** Generation の `Growth` は
**Persistent（解放されずに残っている）バイト数**であり、画像のデコードと PNG 再エンコードは
確保後すぐ解放される **Transient** な処理のため、ほとんど現れない。

Generation A の 13.36 MiB も画像処理の実体ではなく、`IosClipboardManager` の初回構築
（use case 一式 + `ClipboardTemporaryFileStore`）と、ボタンを探すスクロールに伴う
SwiftUI 再描画を含む。最初の操作に一度だけ乗る費用である。

**観測結果:**

- 操作なし区間（Generation D）の増分が 827 KiB あり、画像操作区間（231 KiB〜1.13 MiB）と同水準
- したがって**経路間の有意差は測定できない**
- 一方で、**3 経路とも持続的なメモリを残していない**ことは確認できた（リークなし）

Generation の番号と操作の対応が 1 つずれる可能性があるが、A 以外はいずれも 1 MiB 未満で
ノイズと同水準のため、結論は変わらない。

**経路間のコスト比較と 100 MP 上限値の妥当性は、より大きな画像を扱える harness へ委譲する**
（設計 §8.2 の既定方針どおり）。

### 5.4 M-14 — 合格

判定式は `reportCount = eventDelta + (checkResult ? 1 : 0)`。settle 後の最終値が 1 であることを要求する。

**正の対照（observer が機能していることの確認）:**

| 操作 | 結果 |
|---|---|
| `Start Observing` → **フォアグラウンドのまま** `Copy Plain Text` | Events が 0 → 1 に増加 |

**本番測定:**

| 手順 | 記録 |
|---|---|
| `Start Observing` 後の Events 初期値 | 0 |
| background → 外部アプリでコピー → 復帰 → 5 秒 | Events 変化なし（`eventDelta = 0`） |
| `Check Foreground Change` | **`changed=true`** |
| さらに 5 秒（late notification 確認） | Events 変化なし |

```
reportCount = 0 + 1 = 1   → 合格
```

設計が想定する 2 つの正常パターンのうち、**「通知が届かず Check が拾う」側**に該当した。

#### 副次的な確認: iOS は background 中の変更を通知しない

正の対照でフォアグラウンドの変更は通知されることを確認したうえで、background 中の変更では
Events が増えなかった。**`UIPasteboard.changedNotification` は background 中の変更について
配信されない**ことが実証された。

これは `checkForegroundChange`（S9 / P-15）が存在する理由そのものであり、
設計の前提が実機で裏付けられたことになる。

---

## 6. v2 以降のコード変更

| 変更 | 目的 |
|---|---|
| `FullWidthPressableButtonStyle` が `isEnabled` を反映 | 1.1 の不具合修正 |
| `Copy Number Fixture` / `Copy Search Fixture` 追加（marker 50 → 52） | 2.1 の切り分け |
| 検出パターン名をログへ出力 | 手動確認での記録。型レベル情報のみ |
| `read` の `resolved` / `numberOfItems` をログへ出力 | 3 状態の判別。T-13 のスクリプト駆動測定の下地 |
| 失敗時の `errorCode` をログへ出力 | 失敗の分類 |
| `Snapshot` が型識別子**名**を表示・ログ出力 | 2.2 の診断 |
| UI テスト U-21 追加 | 隔離 fixture の測定。断定せず観測値付きで skip する設計 |
| 単体テスト `isolatedDetectionFixturesAreSingleValued` 追加、`markersAreDistinct` を 52 へ | fixture 純度と marker 一意性の固定 |

追加したログはいずれも型・件数・エラーコードのみで、値は出さない（M-15 で 0 件を確認済み）。

### 6.1 検証状況

| 環境 | 状態 |
|---|---|
| iOS 26.2 Simulator | U-15 / U-21 / U-3 / U-1 / U-6 / U-8 + 単体 10 件が green |
| iPhone XS / iOS 18.7.2 実機 | **上記コード変更後の全 21 件ランは未実施**。手動確認で該当機能は確認済み |

---

## 7. 残作業

### 7.1 T-13 の残り

| M-ID | 状態 |
|---|---|
| M-06 Universal Clipboard | **保留**。**macOS Clipboard 機能の完成後**に Mac を端末 B として実施（7.3） |
| M-07 | **完了**（5.1） |
| **M-08 名前付きの寿命** | **未決**。K-4 の放置区間確認 → controlled long-duration measurement |
| M-09 App Group | 対象外（entitlement と 2 アプリ目が必要） |
| M-10 / M-11 Paste Control・画像 | **完了**（L-1 / L-2、2.2） |
| M-12 | **部分完了**（5.2）。active session 除外は harness へ |
| M-13 | **部分完了**（5.3）。経路間比較と 100 MP は harness へ |
| M-14 | **完了**（5.4） |
| M-15 | **完了**（3.1） |
| M-16 | **保留**。同上（7.3） |

**2 台不要な項目はすべて完了した。** 残るのは M-08 の長時間測定と、2 台を要する M-06 / M-16。

**M-08 は 2 台目を必要としない。** macOS の完成を待たずに進められる唯一の未決事項であり、
公開 DocC の訂正が絡むため優先度が高い。

### 7.2 その他

| 区分 | 内容 |
|---|---|
| **本タスク** | K-4 の放置区間確認（4.4） |
| T-00 | プライバシー実機スパイク 16 ケース。**未着手** |
| T-11b | Bridge 統合テスト I-08 / I-09 / I-10。**未着手** |
| T-14 | DocC に Clipboard セクションを追記。**未着手**（M-08 の結論待ち） |
| harness | M-12 の active session 除外、M-13 の経路間比較と 100 MP 妥当性 |
| 設計側 | 計画 §8.1 に手順がない 6 件の追記（自動テストで担保済みの旨） |
| 設計側 | M-08 の結論に応じた公開 DocC / 設計書「非永続」記述の訂正 |
| 設計側 | §5.7 の fixture 方針に「全体評価系は単独 fixture が必要」を追記 |
| 設計側 | §8.1 #20 の「要検証」を解消（PDF / zip が使えることを反映） |
| 設計側 | §8.2 M-13 の手順に「Generation 分析は Persistent しか測れない」旨を追記 |

### 7.3 2 台を要する項目は macOS Clipboard 機能の完成後に実施する

M-06 / M-16 / T-00 ケース 11 は Universal Clipboard の転送を観測するため 2 台を要する。
現状 iPhone は 1 台しかない。**2 台目の iPhone を用意するのではなく、Mac を端末 B として使う。**

`mac/MacLibrary` は Dialog / Notification / Share が実装済みで Clipboard のみ未着手。
Clipboard が実装されれば、次が揃う。

| 必要なもの | macOS Clipboard 完成後の状態 |
|---|---|
| 転送経路 | Universal Clipboard は Mac ↔ iPhone で動作する |
| 端末 B での判別 | macOS 版の `Read` が item index / 文字数を表示すれば、14 / 24 / 31 文字の判別方式がそのまま使える |
| 端末 B の baseline 設定 | `Copy B Baseline (localOnly = true)` 相当の操作が実装され、設計 §6.3 手順 5 が実行可能になる |

使い捨ての観測スクリプト（`NSPasteboard` を直接読む harness）は不要になる。

#### プラットフォーム差の懸念は正の対照で排除できる

「Mac 相手だから転送されなかった」のか「`localOnly` が効いた」のかを区別できない懸念があるが、
設計 §6.3 は**正の対照を試行の有効条件**にしている。

```
手順 2  A で Copy (localOnly = false)
手順 3  B で転送を確認 ← 失敗した試行は invalid、D-8 / R-13 を判断しない
```

`localOnly = false` が Mac へ届くことを先に確認したうえで `localOnly = true` を試すため、
プラットフォーム差は排除される。**正の対照がある限り Mac を端末 B にしても判定は成立する。**

#### macOS Clipboard 設計への申し送り

macOS 側の企画・設計時に、次を要件として引き継ぐこと。

- **iOS の M-06 / M-16 で端末 B として使う**ため、`Read` 相当が
  **item ごとの index / テキスト有無 / 文字数**を表示すること（raw 値は表示しない）
- `localOnly` 相当のコピーオプションを持つこと（B 側 baseline を A へ同期させないため）
- これらが無いと iOS 側の M-06 / M-16 が実施できないまま残る

---

## 8. ステップ8 実行確認

- 提示文: 「このサンプル実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま終了
- ユーザー回答: 未回答
