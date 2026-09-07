# iOS Clipboard 実装結果 v4（M-08 の文言訂正とリリース判断）

## 基本情報

- 日付: 2026-08-15
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 実装結果 v3: `artifact/results/clipboard/2026-08-15-ios-clipboard-implement-sample-app-result-v3.md`
- 機能設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 実機: iPhone XS / iOS 18.7.2
- 対応タスク: 設計書 T-13（M-08）/ T-14（DocC 見直し）

v3 で **open risk** として残していた M-08 について、**K-4 の長時間測定を待たずに文言訂正を行い、
残りを制限事項として扱う**判断をした。本レポートはその判断根拠と訂正内容を記録する。

**コードのロジック変更はない。** 変更はすべてコメント・ドキュメント。

---

## 1. 判断: K-4 を待たずにリリースする

### 1.1 何を待たないことにしたか

v3 §4.4 で、K-4 の測定に交絡があると記録した。

> 確認のたびにアプリを起動しているため、「作成アプリが動いていない状態が 15 分続いた」とは
> 厳密には言えない。OS が「同一バンドルの起動で寿命を延長する」挙動を持つ場合、
> 測定行為が回収を妨げていることになる。

これを潰すには「アプリを一切起動しない区間」を数時間置く必要があり、結論が出るまで時間が読めない。
**この測定の完了を待たずにリリースする**と判断した。

### 1.2 なぜ待たずに出せるのか

**K-4 の 3 通りの結果すべてに対して正しい文言が書けるため。**

確定している事実は次のとおり。

| 事実 | 確度 |
|---|---|
| アプリを強制終了して**再起動した後**、終了前に書き込んだ内容を読み取れた | **実測**（preflight 済み・iPhone XS / iOS 18.7.2） |
| いずれ回収されるのか、されないのか | 未確定 |

交絡があっても、この事実は揺らがない。内容を読むには必ずアプリを起動する必要があり、
**そのとき読めた**というのが観測だからである。これは「アプリを終了して再起動したら前のデータが
残っていた」という、**利用者が実際に遭遇する状況そのもの**にあたる。

訂正後の文言は 3 通りのどの結果でも偽にならない。

| K-4 の結果 | 訂正後の文言の正しさ |
|---|---|
| いずれ回収される | 「回収タイミングは保証されない」で正しい |
| 回収されない | 「ただちに破棄されるとは限らない」で正しい（控えめだが誤りではない） |
| 中身だけ回収される | 「明示削除せよ」で対応できる |

### 1.3 訂正前の何が問題だったか

旧文言は**残らないことを前提に読ませていた**。

```
exists **only while the creating app is running** — it is not a persistent store.
For anything that must survive the creating app quitting,
use an App Group shared container instead
```

これを信じた実装者は、機微データを名前付きペーストボードに置いたまま
「アプリを終了すれば消える」と考えて明示削除しない可能性がある。
**誤った約束を含む文書を出荷するのは、文書がないより悪い。**

### 1.4 コード変更が解にならない理由

「ライブラリが `deinit` で削除すればよいのでは」という案を検討したが、**成立しない**。

iOS は強制終了時に `deinit` を実行しない。今回測定したのは App Switcher からのスワイプ終了であり、
`deinit` では救えない経路である。**手当てにならない対策を入れるより、明示削除を促す文言のほうが正しい。**

この点は DocC 記事にも明記した（利用者が「ライブラリが自動で消してくれるのでは」と誤解しないため）。

---

## 2. 訂正内容

### 2.1 訂正した箇所

| ファイル | 種別 |
|---|---|
| `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift` | 公開 DocC（`## Named pasteboard lifetime`） |
| `ios/IosLibrary/IosLibrary/Clipboard/Domain/Model/PasteboardScope.swift` | 公開 DocC（`- Note:` と `.general` の記述） |
| `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/PasteboardResolver.swift` | internal コメント 2 か所 |
| `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md` | DocC 記事（`### Named / unique pasteboards ...`） |
| `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md` | **正誤追記**（本文は保持） |

`grep` で `only while the app that created` / `non-persistent` / `not persistent` の残存が
0 件であることを確認済み。

### 2.2 訂正後の文言（DocC 記事）

```
### Named / unique pasteboards are not a persistent store

A pasteboard created via `createPasteboard(.named(_:))` or `.unique` is not meant to persist, but
its contents are **not guaranteed to be discarded when the creating app quits** either. Measured
on iOS 18.7.2: after force-quitting the app and relaunching it, a named pasteboard written before
the quit was still readable. The system does not specify when such a pasteboard is reclaimed.

Use these scopes only to hand data between live apps, and **delete sensitive data explicitly with
`removePasteboard(_:)`** — do not rely on app termination to discard it. Note that a force-quit
does not run `deinit`, so no cleanup the library could perform on teardown would help here.
```

### 2.3 `.general` の記述も修正した

`PasteboardScope.general` のコメントが `The only persistent pasteboard`（唯一の永続）だった。
名前付きも残りうると分かった以上、**排他的な主張は成立しない**。

```swift
/// The systemwide general pasteboard, shared with every app and persisted across launches.
case general
```

### 2.4 設計書は本文を残し正誤を追記した

設計書 1675 行の DoD が
「名前付きペーストボードが非永続であることを明記した」というチェック項目になっており、
**この指示に従うと誤った文書が再生産される**。本文は履歴として保持し、冒頭に正誤を追記して
影響する行番号（24 行 / 1675 行）を明示した。

### 2.5 検証

| 項目 | 結果 |
|---|---|
| `xcodebuild build`（iOS 26.2 Simulator） | `** BUILD SUCCEEDED **` |
| ロジック変更 | **なし**（コメント・ドキュメントのみ） |
| 自動テストへの影響 | なし |

---

## 3. 制限事項として残すもの

以下は**リリース後の既知の制限**として扱う。

### 3.1 M-08: 名前付きペーストボードの回収タイミング

| 項目 | 内容 |
|---|---|
| 事象 | 作成プロセス終了後も、内容が読み取れる場合がある |
| 実測 | iPhone XS / iOS 18.7.2 で 15 分後も残存（Simulator では 90 秒 / 43 read） |
| 未確定 | いずれ回収されるのか、回収が遅いだけなのか |
| 利用者への影響 | **なし**（DocC が明示削除を指示済み） |
| 追跡 | T-13 の long-duration measurement |
| ライブラリ側の不具合か | **否**。`removePasteboard` は正常。OS 側の挙動 |

### 3.2 その他（v3 から継続）

| 項目 | 状態 |
|---|---|
| T-00 プライバシー 16 ケース | 未計測。**DocC が「未計測・自分で検証せよ」と明記済み**のため文書上の誤りはない |
| M-06 / M-16（2 台必要） | macOS Clipboard 機能の完成後に Mac を端末 B として実施（v3 §7.3） |
| ブリッジ統合テスト | `artifact/BRIDGE_TESTING.md`。既存 3 機能と同条件のため本機能を止めない |
| M-12 の active session 除外 / M-13 の 100 MP | harness へ委譲 |

---

## 4. リリース判断

### 4.1 ブロッカーは解消した

| # | 項目 | 状態 |
|---|---|---|
| 1 | M-08 の文言訂正 | **完了**（2 章） |
| 2 | T-14 DocC | **既存**。M-08 反映の見直しを本作業で実施 |
| 3 | ブリッジ統合テスト | 別課題（`BRIDGE_TESTING.md`） |
| 4 | T-00 | DocC が未計測と明記済み。文書上の誤りなし |

### 4.2 解消済みの要検証項目

| 項目 | 解消の根拠 |
|---|---|
| `UIColor` の UTI（`"com.apple.uikit.color"`） | **U-13 が実機で `hasColors=true` を確認**。iOS がエントリを色として認識している |
| `public.data` の end-to-end | U-11 が Simulator / 実機の両方で `fileSize=64` を確認（v3） |
| L-3 の対応外 fixture | PDF / zip が使えることを実機で確認（v3 §2.2） |
| Detect の未検出 2 種 | 隔離 fixture で両方とも検出。API は正常（v3 §2.1） |

### 4.3 判定

**リリース可。**

M-08 は制限事項として文書化し、利用者に明示削除を指示している。
残る未実施項目はいずれも、**誤った記述を出荷することにはならない**。

---

## 5. 次工程

| 区分 | 内容 |
|---|---|
| リリース | `/release` ワークフロー。`project.pbxproj` のバージョン更新と `dist/1.9.0/` の扱いを含む |
| T-13 | M-08 の long-duration measurement（制限事項の解消） |
| T-13 | M-06 / M-16（macOS Clipboard 完成後） |
| T-00 | プライバシー実機スパイク 16 ケース |
| 別課題 | ブリッジ統合テスト（`BRIDGE_TESTING.md`） |
| 別課題 | Swift 6 移行（`MIGRATION.md`） |
