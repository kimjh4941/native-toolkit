# ツールチェーン移行管理

最終更新: 2026-08-08

各プラットフォームの言語モード・ツールチェーン移行を管理するインデックス。
個別の企画書・設計書・実装結果は各トピックのフォルダに置く。

> **現在の状態: baseline 未固定。** 本ファイルに記載する診断件数はすべて**暫定観測値**であり、
> baseline ではない。`artifact/baselines/` と `scripts/check_baseline.sh` が揃った時点で
> 「baseline 固定済み」へ移行し、本文中の件数はすべて生成ファイルへの参照に置き換える。

---

## 1. 目的

- 移行によって発生する**既存診断を baseline として固定**し、新規コードが債務を増やさないようにする
- 移行そのものは機能開発とは独立したトピックとして管理し、機能タスクの DoD に混入させない
- 件数・内訳を**人が文章に書き写さない**運用にして、記録ミスを構造的に排除する
- ツールチェーン更新時に診断が変動しても、**再現可能な比較**ができるようにする

### 背景: なぜこの仕組みが要るのか

Clipboard タスク（NTKIT-14）で、設計 DoD に次の 2 条件が同時に存在し、両立できない状態が発生した。

1. `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` で全モジュールが警告・エラーなし
2. 既存 Notification / Dialog / Share のファイルを変更しない

加えて、同タスクの計測・記録で**3 種類の誤り**が発生した。いずれも本ファイルの設計動機である。

| # | 誤り | 原因 | 対策 |
|---|---|---|---|
| 1 | 「strict error 5 件」と記載 → 実際は 13 件 | incremental ビルドの早期停止で後続バッチが未診断 | whole-module を必須化（4.3） |
| 2 | 「Notification 8 / Share 4」と記載 → 実際は 9 / 3 | 件数を本文へ手書きした際の分類ミス | 件数を本文に持たない（3.2） |
| 3 | **「Clipboard 由来の strict 診断 0 件」と記載 → 実際は 19 件** | Swift 6 モードが型検査段階のエラーで停止し、フロー解析（`sending` 系）まで到達しない。加えて依存先が失敗するため UnityIosPlugin 自体が一度もコンパイルされていなかった | **段階別 baseline**（3.1）。Swift 5 + strict で全ターゲットを診断する |

誤り 3 は影響が大きい。Clipboard の実装結果レポート v2 / v3 / v4 はいずれも
「Clipboard 由来 0 件」と記載しているが、**これは誤りである**（詳細は 4.2）。

---

## 2. トピック一覧

| トピック | 対象 | 現在 | 移行先 | baseline 状態 | チケット |
|---|---|---|---|---|---|
| `swift6-migration` / **Bridge callback actor-boundary** | ios / macos の Unity Bridge | `nonisolated` + `Task { @MainActor }` | **案 C 決定済み**（6 章）。Clipboard へ適用済み、他 3 機能は未適用 | - | 未採番 |
| `swift6-migration` | ios / macos | Swift 5.0 言語モード | Swift 6 | 暫定観測値のみ（4.2） | 未採番 |
| `android-toolchain-migration` | android | Kotlin 2.0.21 / AGP 8.9.1 | **未決定** | 未着手（7 章） | 未採番 |
| `windows-toolchain-migration` | windows | C++17（`stdcpp17`）/ Toolset v143 | **未決定** | 未着手（7 章） | 未採番 |

3 トピックは互いに依存しない。並行・順次のどちらでも進められる。

### 着手順の推奨

`swift6-migration` を先行させる。

- 暫定観測値が取れており、規模と診断の傾向が見えている
- Clipboard の設計 v5（I-10 分離）がこのトピックのチケット ID を待って止まっている

そのなかでも **Bridge callback actor-boundary は先行設計タスクとして切り出し済み**である。
NTKIT-14 の受け入れがこの方針決定に依存していたため、移行本体より先に決定した（6 章・案 C 採用）。
Clipboard への適用は完了しており、**Notification / Dialog / Share への一括適用が移行タスク本体の範囲**となる。

Android / Windows は**移行先バージョンが未決定**のため、baseline 生成の前に候補とサポート条件を決める（7 章）。

---

## 3. 管理方針

### 3.1 baseline を 3 系統に分ける

単一の「Swift 6 エラー一覧」では不十分である。ビルド条件が変われば検出できる診断が変わるため、目的別に 3 つ持つ。

| baseline | ビルド条件 | 目的 | ビルド成否 |
|---|---|---|---|
| `current-warnings` | 現行設定の clean build | deprecated など現在の品質債務 | 成功 |
| `swift5-concurrency-readiness` | Swift 5 + `SWIFT_STRICT_CONCURRENCY=complete` | 移行候補を **warning 段階で全ターゲット横断的に**検出 | 成功 |
| `swift6-language-mode` | Swift 6 | 実際に移行を阻害する error | 失敗（移行完了まで） |

**`swift5-concurrency-readiness` が中核である。** Swift 5 モードでは strict concurrency 違反が
warning に留まるためコンパイルが完走し、依存先が失敗して未診断になるターゲットが生じない。
Swift 6 モードは最初のエラーで止まるため、**移行の全体像を測る用途には使えない**。

これは Swift 公式の段階的移行方針と一致する。
参照: [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)

### 3.2 baseline は文章に書かず、生成ファイルで管理する

企画書・設計書・実装結果レポートには**件数や内訳を本文に書かない**。`artifact/baselines/` を参照するだけにする。

**得られるもの**

- 件数の書き間違いが構造的に起きない（本文に数字を持たない）
- 新しい診断の追加が `git diff` に現れ、レビュー可能になる
- 「この差分が診断を増やしていないか」を目視ではなくスクリプトの exit code で判定できる

### 3.3 判定は差分のみ

```
機能タスクの DoD:  変更差分が baseline に新規診断を追加しない
移行タスクの DoD:  6 章のチェックリストを満たす
```

---

## 4. baseline 運用

### 4.1 移行の段階と順序

```
1. Swift 5 strict readiness baseline を全 target で固定
        ↓
2. IosLibrary / MacLibrary を修正
        ↓
3. UnityIosPlugin / UnityMacPlugin
        ↓
4. Example / Test target
        ↓
5. archive・XCFramework 検証
        ↓
6. 全 configuration を Swift 6 へ変更
```

**依存先・基盤側から**順に修正していくことで、基盤を直すたびに利用側の未知の診断が噴き出す事態を避ける。
一方 baseline の**取得**は最初に全ターゲットまとめて行う（step 1）。段階的に取得すると、
各段階でどこまでが既知だったのかが追えなくなるため。

### baseline を生成してよいコミット

baseline は必ず**クリーンな `develop`、または明示した commit** から生成する。
feature branch 上で生成してはならない。

理由: feature branch には、そのタスクが**追加した診断**が含まれる。そこから baseline を作ると、
新規債務を「既存債務」として固定してしまい、以後のチェックをすり抜ける。
実際に NTKIT-14（Clipboard）は `develop` に存在しない新規差分であり、
その diagnostics はすべて既存債務ではなく**当該タスクが追加したもの**である（4.2）。

`manifest.json` に `sourceRevision` と基準 branch、worktree の dirty 状態を必ず記録し、
`check` 時に検証する（4.4）。

### 4.2 暫定観測値（2026-08-08 時点・baseline ではない）

> 以下は `artifact/baselines/` 生成前の観測値である。schema・スクリプト確定後に再計測し、
> 生成ファイルへ置き換えたうえで本節は削除する。

**A. Swift 5 + strict complete / whole-module / clean build（`UnityIosPlugin` scheme）**

ビルドは **成功**（exit 0 / error 0）。unique warning **129 件**。

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

**カテゴリ別内訳は上の領域別表とは観測段階が異なる。** 領域別表は初期観測の 129 件、
下のカテゴリ表は**局所 3 件修正後（案 C 適用前）の 126 件**である。混同しないこと。

4.3「集計の正規化単位」のコマンドによる unique 行数（**出現回数ではない**）。
シンボル名は `'X'` に正規化して集計している。

| 診断カテゴリ（局所 3 件修正後・計 126） | 件数 |
|---|---|
| `sending 'X' risks causing data races` | 32 |
| `passing closure as a 'X' parameter risks causing data races ...` | 17 |
| `static property 'X' is not concurrency-safe ...` | 14 |
| `main actor-isolated property 'X' can not be referenced from a nonisolated context` | 13 |
| `capture of 'X' with non-Sendable type 'X' in a 'X' closure` | 11 |
| `sending value of non-Sendable type 'X' risks causing data races` | 7 |
| その他 | 32 |

**Clipboard 関連は当初 19 件（IosLibrary 1 + UnityIosPlugin 18）だった。**
実装結果レポート v2 / v3 / v4 の「Clipboard 由来 0 件」は誤りであり、訂正が必要。

Clipboard は `develop` に存在しない新規差分であるため、**この 19 件は既存債務ではなく
NTKIT-14 が追加した診断**である。したがって baseline へ取り込んで完了扱いにしてはならない
（4.1 の「baseline を生成してよいコミット」を参照）。

該当箇所・性質・処遇:

| 箇所 | 件数 | 性質 | 処遇 |
|---|---|---|---|
| `IosClipboardManager` の `sending 'note'` | 1 | `MainActor.assumeIsolated` 内で非 Sendable な `Notification` を扱っていた。**実装レビュー v1 で `Task { @MainActor }` 案を退けて `assumeIsolated` を採用した際、「strict concurrency は同等に満たす」と述べたが、これは検証不足だった** | **Clipboard で修正済み**（下記） |
| `UnityIosClipboardJsonParser` の `static let iso8601Formatter` 系 | 2 | `ISO8601DateFormatter` は参照型で可変状態を持つ。任意スレッドから呼ばれる `nonisolated` Manager と相性が悪い。うち 1 件は本タスクで新規追加したコード | **Clipboard で修正済み**（下記） |
| `UnityIosClipboardManager` の `sending 'handler'` | 16 | Bridge 共通パターン。`nonisolated` クラスから C 関数ポインタ由来の handler を `Task { @MainActor }` へ渡す構造。Notification / Dialog / Share の Bridge も同じ診断を出しており、Clipboard は 15 endpoint と API 面が広いぶん出現数が多い | **Clipboard で修正済み**。先行設計で案 C を決定し適用（6 章） |

**修正済み 3 件の内容と検証（2026-08-08）**

| 箇所 | 件数 | 修正 |
|---|---|---|
| `IosClipboardManager` | 1 | `note.userInfo` の取り出しを `MainActor.assumeIsolated` の**外側**へ移動。actor 境界を越えるのは `[String]` のみになる。`assumeIsolated` 自体は撤回せず、main queue 上での同期配信とイベント順序を維持 |
| `UnityIosClipboardJsonParser` | 2 | `ISO8601DateFormatter`（参照型）を `Date.ISO8601FormatStyle`（Sendable な値型）へ置換。`@unchecked Sendable` は使用しない |
| `UnityIosClipboardManager` | 16 | 先行設計で決定した**案 C**（6 章）を適用。handler パラメータの型に `@Sendable` を付与 |

再計測結果（4.3 の正規化コマンドによる unique 行数）:

```
Swift 5 + strict complete / whole-module / clean build（UnityIosPlugin scheme）
  修正前:       exit 0 / error 0 / unique warning 129（うち Clipboard 19）
  局所 3 件修正: exit 0 / error 0 / unique warning 126（うち Clipboard 16）
  案 C 適用後:   exit 0 / error 0 / unique warning 110（うち Clipboard  0）
```

**Clipboard 由来の診断は 0 件になった。** 残る 110 件はすべて既存 Dialog / Notification / Share
由来であり、移行タスク本体の対象である。

**B. Swift 6 language mode / whole-module（参考）**

| ターゲット | error | 備考 |
|---|---|---|
| IosLibrary | 13 | Dialog 1 / Notification 9 / Share 3 |
| MacLibrary | 8 | Dialog 1 / Notification 1 / Share 6 |
| UnityIosPlugin / UnityMacPlugin | 計測不能 | 依存先が先に失敗し自身のソースが未コンパイル |

この数値は**移行の全体像を表さない**。型検査段階で停止するため、フロー解析段階の
`sending` 系診断が一切含まれていない。移行阻害要因の把握には使えるが、
**規模の見積もりに使ってはならない**。

**母集団を揃えた比較**（同一 scheme / 同一プラットフォームのみ）:

| 比較 | Swift 5 + strict | Swift 6 mode |
|---|---|---|
| iOS（`IosLibrary` scheme） | — | 13 |
| iOS（`UnityIosPlugin` scheme・下流含む） | 129 | 計測不能（依存先が先に失敗） |
| macOS（`MacLibrary` scheme） | 未計測 | 8 |

iOS の 129 と「iOS 13 + macOS 8 = 21」を直接引き算してはならない。対象 scheme も
プラットフォームも異なる。macOS の Swift 5 readiness を取得して初めて Apple 全体同士の
比較が成立する（4.2 D の未計測項目）。

**C. current-warnings（現行設定 clean build）**

| ターゲット | 件数 | 内容 |
|---|---|---|
| IosLibrary | 1 | `NotificationRepositoryImpl.swift:294` `allowAnnouncement` deprecated |
| UnityIosPlugin | 1 | `UnityIosNotificationManager.swift:169` `@unknown default` 欠落 |
| MacLibrary | 0 | - |
| UnityMacPlugin | 1 | `UnityMacNotificationJsonParser.swift:198` 同上 |

**D. 未計測**

- macOS の `swift5-concurrency-readiness`
- IosLibraryExample / MacLibraryExample / 各 Test target（全系統）
- Android / Windows（全系統）

### 4.3 計測コマンド

**swift5-concurrency-readiness（推奨・全体像用）**

```bash
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build
```

**swift6-language-mode（阻害要因確認用）**

```bash
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build
```

macOS は workspace を `mac/MacWorkspace.xcworkspace`、destination を `platform=macOS` に置き換える。

**必須条件**

| 条件 | 理由 |
|---|---|
| `SWIFT_COMPILATION_MODE=wholemodule` | 既定の incremental は最初にエラーを出したバッチで打ち切られ、後続ファイルが未診断のまま終了する |
| `clean` | 増分ビルドでは前回コンパイル済みファイルの warning が出力されない |
| 依存関係の**最下流**の scheme を指定 | 上流だけ指定すると下流ターゲットが計測対象に入らない |

### 集計の正規化単位（暫定・schema 確定まで）

**件数を出すときは必ず同じコマンドを使う。** 正規化単位が違うと同じログから違う数字が出る。

```bash
grep -oE "/[^ ]*\.swift:[0-9]+:[0-9]+: (warning|error): .*" "$LOG" \
  | sed 's|.*/ios/||' \
  | sort -u
```

- 単位は「**フルソース位置 + 診断文の unique 行**」であり、**出現回数ではない**
- カテゴリ別内訳もこの unique 集合から算出する。ログ全体の raw grep とは値が一致しない
- **比較する母集団を必ず揃える。** iOS の scheme 単位の数値と、iOS + macOS を合算した数値を
  直接比較してはならない

この正規化はあくまで暫定である。4.4 の JSON schema が確定した時点で、比較キーは
`sort -u` ではなく fingerprint に置き換わる。

### 4.4 baseline のファイル形式

`パス:行:列` を識別子にしてはならない。無関係な行追加だけで baseline 全体が変更されてしまうため。

**機械比較用 JSON と閲覧用 TXT の二層**とする。

```
artifact/baselines/swift6/
  manifest.json
  ios-library.json        比較キー
  ios-library.txt         人間用（行番号つき）
  unity-ios-plugin.json
  unity-ios-plugin.txt
  mac-library.json
  mac-library.txt
  ...
```

**比較キーに含めるもの**

- target
- severity（error / warning）
- repository 相対パス
- compiler diagnostic ID（取得可能な場合）
- 正規化した diagnostic message（`'...'` 内のシンボル名を除去、または保持のいずれかに統一）
- 該当ソース行の hash
- 同一診断の出現数

**比較キーに含めないもの**

- 行・列番号（表示情報として JSON には保存するが、比較からは外す）

**manifest.json に必ず記録するもの**

```json
{
  "xcode": { "version": "26.3", "build": "17C529" },
  "swiftCompiler": "6.2.4 (swiftlang-6.2.4.1.4 clang-1700.6.4.2)",
  "sdk": { "name": "...", "version": "...", "build": "..." },
  "configuration": "Debug",
  "destination": "generic/platform=iOS Simulator",
  "command": "xcodebuild ...",
  "source": {
    "revision": "3cde4de4...",
    "baseBranch": "develop",
    "dirtyWorktree": false
  },
  "generatedAt": "2026-08-08T00:00:00Z"
}
```

ツールチェーンが変わると診断そのものが変化する。バージョン情報がない baseline は再現できない。

**`source.revision` は必須。** これがないと、feature branch 上で baseline を生成して
新規債務を既存扱いにしてしまう事故（4.1）を検出できない。`dirtyWorktree: true` の baseline は
再現不能なので、`check` / `update` の入力として拒否する。

**`generatedAt` は provenance 情報であり、`check` の一致判定対象から除外する。**
同様に `command` の空白差なども判定に含めない。判定対象はツールチェーン識別子、
`configuration`、`destination`、`source`、および診断リストである。

### 4.5 検証スクリプト（未作成）

```
scripts/check_baseline.sh <baseline-name> [--mode check|update|rebaseline]
```

| モード | 動作 | 用途 |
|---|---|---|
| `check`（既定） | 現在値と baseline の一致を確認。不一致なら exit 1 | CI・機能タスクの DoD 判定 |
| `update` | **減少のみ許可**。新規診断が 1 件でもあれば失敗 | 移行タスクの進捗反映 |
| `rebaseline` | 診断の追加を許可。**理由とチケット ID を必須**とする | ツールチェーン更新時のみ |

**診断が減った場合も baseline 更新を必須とする。** 古い baseline を残すと、後から同じ診断が
再発しても「既存」として素通りしてしまう。

manifest のツールチェーン情報が現在の環境と一致しない場合、`check` は
「baseline が古い」ことを明示して失敗させる（黙って通さない）。

---

## 5. ディレクトリと命名

### 5.1 ドキュメント

既存の機能開発と同じ規約に従う。

```
artifact/plans/<topic>/     企画書
artifact/designs/<topic>/   設計書
artifact/results/<topic>/   実装結果
artifact/reviews/<topic>/   レビュー結果
```

命名: `<YYYY-MM-DD>-<platform>-<topic>-<doctype>-v<n>.md`

### 5.2 swift6-migration の構成: 共通企画・別実装

**Concurrency の判断原則は iOS / macOS 共通だが、実装は共通ではない。**
次の要素はプラットフォームごとに異なるため、設計以降を分ける。

- UIKit / AppKit
- Share presenter の構造
- Unity Bridge
- Objective-C interoperability
- build / archive 経路
- 公開 API への影響
- 実行環境とテスト

```
Epic: Swift 6 Migration

  共通
    baseline / CI 基盤
    共通 research（診断の分類と対処方針、actor isolation・公開 API 方針）

  iOS
    IosLibrary → UnityIosPlugin → IosLibraryExample → XCFramework

  macOS
    MacLibrary → UnityMacPlugin → MacLibraryExample → XCFramework
```

```
artifact/plans/swift6-migration/
  2026-XX-XX-apple-swift6-migration-research-v1.md

artifact/designs/swift6-migration/
  2026-XX-XX-ios-swift6-migration-design-v1.md
  2026-XX-XX-macos-swift6-migration-design-v1.md

artifact/results/swift6-migration/
  2026-XX-XX-ios-swift6-migration-implementation-feature-result-v1.md

artifact/reviews/swift6-migration/
  2026-XX-XX-ios-swift6-migration-implementation-feature-review-v1.md
```

### 5.3 baseline

```
artifact/baselines/<topic>/
```

ドキュメントではなく機械生成データのため、`plans` 等のサブフォルダには置かない。

---

## 6. 移行タスクの DoD

「baseline を 0 件にして Swift 6 へ切り替える」だけでは不十分。最低限これらを含める。

- [ ] Debug / Release / Test target のすべてが Swift 6 言語モード
- [ ] strict concurrency 診断 0 件（`swift5-concurrency-readiness` / `swift6-language-mode` の両方）
- [ ] 全 unit / integration test が成功
- [ ] Objective-C Bridge がコンパイル成功
- [ ] Swift 生成ヘッダの互換性確認
- [ ] サンプルアプリの build 成功
- [ ] archive / XCFramework 生成成功
- [ ] **公開 API 差分の確認**
- [ ] **actor isolation 追加による呼び出し規約変更の記録**
- [ ] breaking change がある場合の versioning 判断
- [ ] 対象 baseline が空、または baseline ファイルを削除
- [ ] `current-warnings` baseline に新規診断なし

### 特に注意すべき点

**`shared` シングルトンへの `@MainActor` 追加はソース互換性に影響する。**
単なるコンパイル修正として扱わず、**公開 API 差分としてレビューする**こと。
呼び出し側は非 main actor から `await MainActor.run { }` が必要になる。

**Share の Presenter は Port 設計の見直しが要る。**
`ShareSheetPresenter`（iOS）/ `SharePickerPresenter`（macOS）は `[Any]` を受け渡す
protocol requirement と `@MainActor` 実装の isolation が不一致であり、機械的な修正では済まない。

**Bridge の `sending 'handler'` は構造的な問題である。**
`nonisolated` クラスから C 関数ポインタ由来の handler を `Task { @MainActor }` へ渡す
パターンが Clipboard / Notification / Dialog / Share すべてに存在する。個別修正ではなく
**Bridge 共通の設計方針として一度に決める**べき対象。

### 先行設計タスク: Bridge callback actor-boundary（決定済み）

移行本体より先に方針を決める必要があった（2 章）。検討した案は 3 つ。

| 案 | 内容 | 評価 |
|---|---|---|
| A | Objective-C Bridge 側で main queue へ dispatch し、Swift facade 全体を `@MainActor` にする | 境界は明快だが、C 文字列と block の寿命、全 Bridge API への影響、Unity 側の呼び出し規約まで再検証が必要。影響範囲が大きい |
| B | callback を main actor へ転送する共通 `@unchecked Sendable` wrapper を作る | 差分は小さいが、要求を実装内部の unchecked な断言として隠してしまう。所有権と呼び出しスレッドをテストで保証する必要がある |
| **C（採用）** | **handler パラメータの型に `@Sendable` を付与し、main-thread delivery を全経路で監査・統一する** | unchecked な抜け道を使わない。Swift caller の closure transfer はコンパイラが検証する。Objective-C caller は capture 監査と Bridge 契約テストで担保する。`@Sendable` 自体は block 表現や実行 executor を変えないため、main-thread 実行は別途 delivery helper で保証する |

**案 C を採用した理由**

- Bridge の `.m` が渡す block は **C 関数ポインタしかキャプチャしていない**（`clipboardCopy` 等）。
  どのスレッドから呼んでも安全であり、`@Sendable` の表明は事実に即している
- 既存の公開ドキュメントが既に「callback は常に main thread で呼ばれる」と規定している
- 案 B のように `@unchecked Sendable` で断言を隠すより、**要求を API 境界に出すほうが検証可能**

**検証の担保範囲（正確な区別）**

| 呼び出し側 | 担保手段 |
|---|---|
| Swift caller | `@Sendable` によりコンパイラが型検査する |
| **Objective-C caller** | **コンパイラ検証は及ばない。** block の capture 監査（C 関数ポインタのみ）と Bridge 契約テストで担保する |

**`@Sendable` は closure を isolation 間で安全に「運べる」ことを表すだけで、
実行 executor を main actor に固定しない。** main thread 実行は別途、すべての経路を
`Task { @MainActor in }`（または main actor 経由の共通 delivery helper）に通すことで保証する。
早期 return する parse / validation 失敗経路も例外にしてはならない。

```swift
// before
public func copy(requestJson: String?, handler: ((Bool, String?, String?) -> Void)?)
// after
public func copy(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?)
```

**適用時の確認事項**

- Objective-C 側は無変更でビルドが通ること（`@Sendable` は block 表現に影響しない）
- callback が **main thread で exactly-once** に呼ばれること。**正常系だけでなく、
  parse / validation 失敗の早期 return 経路も、background thread から呼ばれた場合を含めて**検証する
- `nil` callback を渡しても trap しないこと
- 監視の start / stop 境界で handler が交差しないこと

Clipboard へ適用済み（4.2）。**Notification / Dialog / Share への一括適用は移行タスク本体で行う。**

---

## 7. Android / Windows の扱い

「移行先未定のまま baseline 計測」は移行 baseline にならない。次の 2 つを分ける。

| 種別 | 内容 | 移行先決定の要否 |
|---|---|---|
| **current-health inventory** | 現在のツールチェーンで出ている診断 | 不要（今すぐ取得可能） |
| **migration baseline** | 移行先バージョンを指定して発生する診断 | **必要** |

Android / Windows はまず**候補バージョンとサポート条件を決定**し、その後に migration baseline を
生成する。順序を逆にすると、候補が変わるたびに baseline を作り直すことになる。

決めるべきこと:

| プラットフォーム | 決定事項 |
|---|---|
| Android | Kotlin の移行先バージョン、AGP の移行先、compileSdk / targetSdk、minSdk 据え置きの可否、JDK |
| Windows | C++ 標準（C++20 / C++23）、PlatformToolset、`WindowsTargetPlatformVersion`、サポート対象 OS |

current-health inventory は移行先決定を待たずに取得してよい。

---

## 8. 推奨する着手順

| # | 作業 | 状態 |
|---|---|---|
| 1 | `swift6-migration` の Epic / チケット ID を採番（Bridge 先行設計タスクを含む） | 未 |
| 2 | Clipboard 設計 v5 から 1 の ID を参照し、I-10 を分離 | 未 |
| 3 | **Clipboard 局所 3 件の修正**（`Notification` 境界 / `ISO8601DateFormatter`） | **完了**（4.2） |
| 4 | **実装結果レポート v5 / v6 の作成と v2 / v3 / v4 への Errata 追記** | **完了** |
| 5 | **実装レビュー v4 への Errata 追記**（コード LGTM 判定の撤回・再評価） | **完了** |
| 6 | Bridge callback actor-boundary の先行設計（6 章）→ Clipboard へ適用 | **完了**（案 C・Clipboard 診断 0 件） |
| 7 | baseline schema（JSON / manifest）と `check_baseline.sh` を作成 | 未 |
| 8 | `swift5-concurrency-readiness` を**クリーンな `develop`** で全 target 取得・固定 | 未 |
| 9 | `swift6-language-mode` を取得 | 未 |
| 10 | `common.md` と `agent-rules/index.md` へ恒久ルールを追加 | 未 |
| 11 | iOS / macOS を別設計・別実装タスクとして進める | 未 |

- 1 が完了すると 2 のブロックが外れる
- 6 は Clipboard への適用まで完了。**Notification / Dialog / Share への一括適用は 11 の範囲**
- 8 は必ず `develop` から生成する。現在の feature branch から作ると NTKIT-14 の新規診断を既存債務として固定してしまう（4.1）

### 恒久ルール（7 で追加する文面）

`agent-rules/coding-rules/common.md` に 1 項目だけ置く。プラットフォーム別ルールファイル 4 つに
同じ内容を書くと必ず食い違うため。

> 新規追加・変更するコードは、対応する `artifact/baselines/` の診断を増やしてはならない。
> 既存の診断は baseline として固定し、`scripts/check_baseline.sh --mode check` の差分のみを
> 判定対象とする。移行そのものは `artifact/MIGRATION.md` の各トピックで管理する。

プラットフォーム固有の計測コマンドのみを `ios.md` / `android.md` / `windows.md` に記載する。

---

## 9. 企画書に書くべき内容（各トピック共通）

1. **baseline の参照**（件数は本文に書かず、`artifact/baselines/` を指す）
2. 移行先バージョンで何が変わるか。該当する変更のみに絞る
3. **診断パターンごとの章立て**（機能ごとではない）。一括処理できる群と個別設計が要る群を分ける
4. 公開 API 互換性への影響評価。特に呼び出し規約が変わるもの
5. 回帰テスト範囲
6. 段階（3.1 の 3 系統）ごとの完了条件

---

## 10. 関連

- Clipboard 設計 v4: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`（I-10 が現行定義のまま）
- Clipboard 実装結果 v4: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v4.md`（**「Clipboard 由来 0 件」の記載は誤り。4.2 参照**）
- Clipboard レビュー v4: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v4.md`（分離方針の合意）
- [Swift 6 Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)
