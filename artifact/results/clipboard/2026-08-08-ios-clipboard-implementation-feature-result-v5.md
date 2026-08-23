# 実装結果レポート v5（strict 診断評価の訂正）

> **Errata（2026-08-08）**
> §2 の「129 対 21」という比較は**母集団が一致していない**（iOS の scheme 単位 129 と、
> iOS 13 + macOS 8 の合算 21 の比較）。差分を未診断数として数値化することはできない。
> また §2 のカテゴリ内訳は `sort -u` を掛けない raw 出現の集計であり、
> 正規化単位が `artifact/MIGRATION.md` §4.3 と異なる。
> いずれも v6 §1.3 で訂正済み。
> なお §3.3 の「残 16 件は Bridge 共通設計待ち」は **v6 で解消済み**（Clipboard 診断 0 件）。
> 訂正: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md`

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 前版: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v4.md`
- ブランチ: feature/NTKIT-14
- 種別: **訂正レポート**（レビュー v4 の指摘によるものではなく、計測方法の誤りの自主訂正）

---

## 1. 訂正の要旨

**v2 / v3 / v4 に記載した「Clipboard 由来の Swift 6 strict 診断 0 件」は誤りである。**
正しくは **19 件**（`IosLibrary` 1 + `UnityIosPlugin` 18）だった。

この誤りにより、次の記述も同時に無効となる。

| ドキュメント | 無効になる記述 |
|---|---|
| result v2 §1.1 H-07 / §4 | 「Clipboard 配下の strict error / warning は 0 件」 |
| result v3 §4 / §6 / §7.1 | 「Clipboard 由来は 0 件」「Clipboard 配下の strict concurrency error / warning が 0 件」 |
| result v4 §4 / §6 / §7.1 | 同上、および「新規追加した `isolated deinit` は strict build で新たな診断を発生させていない」 |
| result v2 §1.3 | **「`MainActor.assumeIsolated` は strict concurrency を同等に満たす」** |
| review v4 | 「Clipboard path を発生元とする strict error は確認されなかった」等（別途 Errata を追記） |

### 1.1 なぜ見逃したか

計測を `SWIFT_VERSION=6.0`（Swift 6 言語モード）でのみ行っていたことが原因である。

1. Swift 6 モードでは strict concurrency 違反が **error** になる
2. 既存 Notification / Dialog / Share に 13 件の error があり、**型検査段階でコンパイルが停止する**
3. `sending 'X' risks causing data races` 系の診断は**フロー解析段階**で出るため、停止により一切実行されない
4. さらに `UnityIosPlugin` は依存先 `IosLibrary` の失敗により、**自身のソースが一度もコンパイルされていなかった**

`grep Clipboard` の結果が 0 件だったのは「Clipboard に問題がない」ためではなく、
**Clipboard が診断されるところまで到達していなかった**ためである。

### 1.2 正しい計測方法

`SWIFT_VERSION=5.0` + `SWIFT_STRICT_CONCURRENCY=complete` を使う。
Swift 5 モードでは strict concurrency 違反が **warning** に留まるためコンパイルが完走し、
全ターゲット・全解析段階の診断が得られる。

```bash
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build
```

この方法は Swift 公式の段階的移行方針と一致する。
参照: [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)

運用ルールは `artifact/MIGRATION.md` §3.1 / §4.3 に定めた。

---

## 2. 再計測結果

| 計測 | ビルド | error | unique warning | うち Clipboard |
|---|---|---|---|---|
| 訂正前の認識（Swift 6 モード） | 失敗（exit 65） | 13 | 計測不能 | **0（誤り）** |
| 実測 A: 修正前（Swift 5 + strict） | **成功**（exit 0） | 0 | 129 | **19** |
| 実測 B: 修正後（Swift 5 + strict） | **成功**（exit 0） | 0 | **126** | **16** |

実測 A の領域別内訳:

| 領域 | 件数 |
|---|---|
| IosLibrary / Dialog | 63 |
| IosLibrary / Notification | 27 |
| UnityIosPlugin / Clipboard | 18 |
| IosLibrary / Share | 14 |
| UnityIosPlugin / Share | 2 |
| UnityIosPlugin / Notification | 2 |
| UnityIosPlugin / Dialog | 2 |
| IosLibrary / Clipboard | 1 |

Swift 6 モードの 21 件（IosLibrary 13 + MacLibrary 8）と実測 129 件の差が、
早期停止による未診断分である。**Swift 6 モードの件数を規模見積もりに使ってはならない。**

---

## 3. Clipboard 19 件の切り分けと処遇

Clipboard は `develop` に存在しない新規差分であるため、**19 件はすべて既存債務ではなく
NTKIT-14 が追加した診断**である。baseline へ取り込んで完了扱いにすることはできない。

| 箇所 | 件数 | 処遇 |
|---|---|---|
| `IosClipboardManager` の `sending 'note'` | 1 | 本レポートで修正 |
| `UnityIosClipboardJsonParser` の `ISO8601DateFormatter` static | 2 | 本レポートで修正 |
| `UnityIosClipboardManager` の `sending 'handler'` | 16 | Bridge 共通設計タスクで方針決定。**NTKIT-14 受け入れ前に解消** |

### 3.1 修正 1: `Notification` を actor 境界へ送らない

`ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift`

`MainActor.assumeIsolated` の採用自体は撤回していない。問題は非 Sendable な `Notification` を
その境界へ持ち込んでいた点にあるため、**payload の取り出しを境界の外側へ移動**した。

```swift
) { [weak self] note in
    // `Notification` is not `Sendable`, so its payload is extracted *before* the
    // main-actor boundary; only the resulting `[String]` values cross it.
    let added = note.userInfo?[UIPasteboard.changedTypesAddedUserInfoKey] as? [String] ?? []
    let removed = note.userInfo?[UIPasteboard.changedTypesRemovedUserInfoKey] as? [String] ?? []
    MainActor.assumeIsolated {
        guard let self, self.observingGeneration == generation else { return }
        ...
    }
}
```

これにより、main queue 上での**同期配信とイベント順序の維持**という当初の設計意図を保ったまま
診断が解消される。`Task { @MainActor }` への変更は不要だった。

### 3.2 修正 2: 共有 formatter を Sendable な値型へ

`ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift`

`ISO8601DateFormatter` は参照型で可変状態を持つため、Unity から任意スレッドで呼ばれる
`nonisolated` Manager と共有するのは不適切だった。

```swift
private static let iso8601Style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private static let iso8601StyleWithoutFractionalSeconds = Date.ISO8601FormatStyle()

private static func parseISO8601(_ value: String) -> Date? {
    (try? iso8601Style.parse(value)) ?? (try? iso8601StyleWithoutFractionalSeconds.parse(value))
}
```

`Date.ISO8601FormatStyle` は Sendable な値型。`@unchecked Sendable` による握りつぶしや、
呼び出し単位での formatter 生成は採用していない。シリアライズ側も同じ style を使う。

小数秒あり / なし双方の受理と不正値の拒否は既存テスト
（`expirationDateAcceptsISO8601WithAndWithoutFractionalSeconds` / `malformedExpirationDateIsRejected`）
で担保されており、置換後も green である。

### 3.3 残 16 件: Bridge callback actor-boundary

`UnityIosClipboardManager` の `sending 'handler'` 16 件は、`nonisolated` クラスから
C 関数ポインタ由来の handler を `Task { @MainActor }` へ渡す**Bridge 共通の構造**に起因する。
同じ診断は Notification / Dialog / Share の Bridge にも出ている（各 2 件）。
Clipboard の件数が多いのは 15 endpoint と API 面が広いためで、新種の欠陥ではない。

個別に手当てすると Bridge ごとに方針が食い違うため、**共通の先行設計タスクで決定する**。
有力案 2 つと検証項目は `artifact/MIGRATION.md` §6 に記載した。

**この 16 件は NTKIT-14 の受け入れ前に解消する。** 新規差分が追加した診断であり、
baseline として固定してはならないため。

---

## 4. ビルド・テスト結果（修正後）

| 対象 | 結果 |
|---|---|
| IosLibrary 通常ビルド | BUILD SUCCEEDED |
| UnityIosPlugin 通常ビルド | BUILD SUCCEEDED |
| IosLibrary tests | **186 passed / 0 failed** |
| UnityIosPlugin tests | **73 passed / 0 failed** |
| Swift 5 + strict（whole-module / clean） | 成功。unique warning 126（Clipboard 16） |
| Swift 6 language mode | 失敗（既存 13 error。Clipboard 由来なし ※早期停止のため証明にはならない） |

---

## 5. Definition of Done（再評価）

### 訂正により判定が変わった項目

- ~~○~~ → **×** Clipboard 配下の strict concurrency 診断が 0 件
  - 修正後も 16 件残存。Bridge 共通設計タスクの完了が前提
- ~~○~~ → **△** `MainActor.assumeIsolated` が strict concurrency を満たす
  - 修正により満たすようになった。当初の主張は未検証だった

### 維持される項目

- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ 公開エラーメッセージ・ログが URL / path / pasteboard name / invalid reason を含まない
- ○ 非同期処理のタイムアウト・キャンセル・exactly-once が P-11 と P-16 で同一実装を共有
- ○ copy / load / image / file の全 kind にサイズ上限が実装されている
- ○ 一時 file が失敗 / キャンセル / タイムアウト / loader 解放のすべてで削除される
- ○ 設計 D-16 の `isolated deinit` を 4 型すべてに実装
- ○ 既存 Notification / Dialog / Share のファイルに変更がない
- ○ 単体テスト 186 + 73 = 259 件 green

---

## 6. 影響を受ける過去ドキュメント

| ドキュメント | 対応 |
|---|---|
| result v2 / v3 / v4 | 冒頭に Errata を追記（本レポートへのリンク） |
| review v4 | 冒頭に Errata を追記。コード LGTM 判定は本レポートを受けて再評価が必要 |
| design v4 | I-10 の扱いは変更なし（別タスク分離の方針は維持）。ただし「Clipboard 差分が診断を追加しない」を DoD にする場合、**現時点では未達**である点に注意 |

過去レポートは書き換えず、Errata で参照を張る方式とした。監査性を残すため。

---

## 7. 残件

| # | 内容 | 前提 |
|---|---|---|
| 1 | Bridge callback actor-boundary の先行設計 → Clipboard へ適用（16 件解消） | **NTKIT-14 受け入れの前提** |
| 2 | 実装レビュー v5 の実施 | 本レポート |
| 3 | 設計 v5 での I-10 分離 | 移行タスクのチケット ID |
| 4 | I-08 / I-09 | - |
| 5 | T-00 / T-12 / T-13（実機・サンプルアプリ） | - |

移行管理全体の着手順は `artifact/MIGRATION.md` §8 を参照。

---

## 8. ステップ10 実行確認

- 提示文:
  - 「この訂正内容を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: 訂正を採用し、Bridge 先行設計へ進む
  - 修正する: 指摘内容を反映して再対応
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
