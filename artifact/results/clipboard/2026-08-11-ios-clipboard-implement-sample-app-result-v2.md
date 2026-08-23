# iOS Clipboard サンプルアプリ実装結果 v2（レビュー v1 指摘反映）

## 基本情報

- 日付: 2026-08-11
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 計画ファイル: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md`
- 機能設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 実装結果 v1: `artifact/results/clipboard/2026-08-09-ios-clipboard-implement-sample-app-result-v1.md`
- レビュー: `artifact/reviews/clipboard/2026-08-11-ios-clipboard-implement-sample-app-review-v1.md`（総合評価: 要修正（重大））
- 対応タスク: 設計書 T-12

本レポートは v1 に対するレビュー v1 の指摘（高 1 / 中 2 / 低 2）を反映した差分をまとめる。
**画面実装・操作カバレッジ・変更ファイル一覧は M-01 の修正を除き v1 から変わらないため、変更点のみ記載する。**

v1 の記述のうち、**M-08 に関する結論は本レポートで訂正した**（3 章）。v1 の該当箇所は本レポートで置き換える。

---

## 1. レビュー指摘の反映内容

### 1.1 H-01（高）: U-10b が preflight を行わず M-08 の主要結論を証明できない

**指摘は妥当。v1 の結論の根拠に欠陥があった。**

`createPasteboard(.named(_:))` は `create: true` で**既存ペーストボードも解決する**。
v1 の U-10b は preflight なしで `createNamed` から始めていたため、開始時点で固定名の
ペーストボードが残存していた場合、「このプロセスが作成した」とは言えない。
その状態で terminate 後に読めても「作成プロセス終了後に OS が回収しなかった」証拠にならない。

実行順（`testU10a` → `testU10b`）と U-10a の後処理に暗黙依存していた点も、
計画 §9.4 の「U-10 は他テストと状態を共有しないよう独立させる」に反していた。

**修正**: U-10a と同じ preflight を U-10b の先頭にも追加した。

```
1. useFixedNamed（作成しない）
2. createNamed
3. removeActive
4. useFixedNamed（作成しない）
5. Read を poll し CLIPBOARD_UNAVAILABLE を確認 ← XCTAssertTrue で必須化
   ↓ ここで「固定名が解決できない」ことが証明される
6. createNamed（このプロセスが新規作成したことが担保される）
7. copyPlainText → read
8. terminate → launch → useFixedNamed → poll
```

対象: `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift`

### 1.2 M-01（中）: 到達可能なローカル失敗経路が表示契約を破る

計画 §4.5 は失敗を `❌ #<seq> [<marker>] errorCode=<code>, errorMessage=<message>` へ統一しているが、
次の 3 経路は `kind: .failure` なのに `errorCode=` を持っていなかった。

| 経路 | v1 の表示 |
|---|---|
| remove 前の `Probe Last Removed Scope` | `No pasteboard has been removed yet` |
| bundle 画像が見つからない `Copy Image File` / `Copy Image Data` | `Sample image not found in bundle` |
| resilient enum の未知 `ClipboardLoadedItem` | `unsupported loaded item kind` |

**修正**:

1. 固定文字列 `localFailureText` を追加し、3 経路すべてを同じ形式へ統一した。

```swift
/// Failure text for a screen-local precondition that has no `ClipboardError` behind it
/// (missing bundle asset, unknown enum case, absent probe target).
static let localFailureText =
    "errorCode=\(ClipboardError.unknownErrorCode), errorMessage=\(ClipboardError.unknownMessage)"
```

   具体的な理由は画面へ出さず `Log.e` へ記録する（`[probeRemoved] no pasteboard has been removed yet` 等）。

2. `Probe Last Removed Scope` は `lastRemovedScope == nil` の間 `.disabled` にした。
   到達自体を防ぐほうが、`ClipboardError` の裏付けがない失敗を作るより素直である。

対象: `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift`

> U-6（監視中に Scope 系が無効）と U-8（remove 後に probe）はいずれも影響を受けない。
> U-6 の時点では未 remove なので `probeRemoved` はどちらの条件でも無効であり、
> U-8 は必ず `removeActive` の後に押すため有効である。再実行で両方 passed を確認した。

### 1.3 L-01（低）: コメントと skip 文言が実測状態と一致しない

v1 の skip 文言は `Requires device verification (T-13).` のままだったが、
v1 の時点で iOS 18.7.2 実機でも同じ結果を測定済みであり、内容が古かった。

**修正**:

- skip 文言を、preflight 済みであることと「残っている確認内容」を示す表現へ変更

```
M-08 could not be decided here: after a preflight-verified fresh create, the named pasteboard
was still readable after <n> reads over <n>s following terminate()/launch(). Last result: "...".
Distinguishing "never reclaimed" from "reclaimed later" needs a controlled long-duration
measurement (T-13).
```

- U-10b の doc コメントを「Simulator では判定不能」から「Simulator でも実機でも観測できていない」へ修正
- クラス doc コメントを `U-1〜U-12` から `U-1〜U-20` へ更新し、U-13〜U-20 の位置づけを追記

### 1.4 L-02（低）: ユーザー固有の Xcode 状態ファイルが差分に混入

`ios/IosWorkspace.xcworkspace/xcuserdata/jonghyunkim.xcuserdatad/UserInterfaceState.xcuserstate`
を `git checkout` で復元し、差分から除外した。`git status` で消失を確認済み。

> Xcode を開いたまま作業すると再び差分が出る。コミット時に混入していないか確認すること。
> 追跡方針そのものの変更は別タスクとする。

### 1.5 M-02（中）: 受け入れ判定の分離

指摘のとおり、`xcodebuild` の成功と計画 §9.2 の U-10 完了は別物である。4 章で分離して記載した。

---

## 2. 修正後の検証結果

### 2.1 影響範囲の再実行（iOS 26.2 Simulator）

```
Executed 4 tests, with 1 test skipped and 0 failures (0 unexpected) in 497.657 seconds
** TEST EXECUTE SUCCEEDED **
```

| テスト | 結果 |
|---|---|
| U-6（M-01 の `.disabled` 追加の影響確認） | passed |
| U-8（同上） | passed |
| U-10a | passed |
| U-10b（H-01 修正後の再測定） | **skipped**（3 章） |
| `ClipboardSampleViewTests` 8 件 + 既存 1 件 | 9 passed |

### 2.2 全 21 件の通し実行

（別途実行。結果は 5 章）

---

## 3. M-08 の結論の訂正（v1 の該当記述を置き換える）

### 3.1 preflight 付きの測定結果

H-01 修正後、preflight が **`CLIPBOARD_UNAVAILABLE` を確認したうえで** fresh create している。
つまり「このプロセスが作成したペーストボード」であることが担保された状態での観測である。

```
after a preflight-verified fresh create, the named pasteboard was still readable
after 7 reads over 21s following terminate()/launch()
Last result: "✅ #8 [read] numberOfItems=1, items=[0:text(len=28) types=1 url=no]"
```

### 3.2 これまでの観測一覧

| 環境 | preflight | terminate 後の観測 |
|---|---|---|
| iOS 26.2 Simulator（v1・長時間プローブ） | なし | 90 秒 / 43 read で readable |
| iOS 18.7.2 実機（v1） | なし | 28 秒 / 1 read で readable |
| **iOS 26.2 Simulator（v2・H-01 修正後）** | **あり** | **21 秒 / 7 read で readable** |

### 3.3 結論（v1 から訂正）

| | v1 の記述 | v2 の記述 |
|---|---|---|
| OS 挙動 | 「OS がプロセス終了時に名前付きペーストボードを**回収しない**」 | 「**上限付きの観測時間内（最長 90 秒 / 43 read）では回収を確認できなかった**」 |
| 根拠の妥当性 | preflight がなく、既存ペーストボード再利用の可能性を排除できていなかった | preflight 済みで、対象がこのプロセスの作成物であることは担保された |
| ライブラリ判定 | 「ライブラリの不具合では**ない**」 | **判定保留。公開寿命契約との不一致として扱う**（下記） |

**「OS が回収しない」という無期限の断定は行わない。** 上限付きの観測は
「回収されない」ことと「回収が観測時間より遅い」ことを区別できないためである。
この切り分けには数分〜数十分オーダーの controlled long-duration measurement が必要で、**T-13 に残る**。

#### ライブラリ判定を「非不具合」から「判定保留」へ訂正した理由

v1 および v2 初稿は「ライブラリの不具合ではない」と断定していたが、**これは誤りである**。

ライブラリ自身が、名前付き / ユニークペーストボードの寿命を**公開契約として明記している**。

| 箇所 | 記述 |
|---|---|
| `IosClipboardManager.swift:35`（DocC「Named pasteboard lifetime」） | `Named/unique pasteboards are **not persistent**: they exist only while the app that created them is running.` |
| `PasteboardScope.swift:10`（DocC Note） | `Named and unique pasteboards are non-persistent: they exist only while the app that created them is running.` |

**観測結果はこの公開契約と一致していない。**

v1 / v2 初稿が非不具合の根拠にしていた 2 点は、いずれも寿命契約の正しさを示さない。

| 挙げていた根拠 | 実際に示せること | 示せないこと |
|---|---|---|
| 明示的な `removePasteboard` が即座に `CLIPBOARD_UNAVAILABLE` を返す | **P-8 の正常性**。remove 経路は正しい | プロセス終了時の寿命契約の成否。**別経路である** |
| サンプルが公開 API のみを使い `UIPasteboard` を直接操作していない | **サンプル実装の妥当性** | ライブラリ契約そのものの正しさ |

したがって現時点の正しい判定は次のとおり。

> **現時点では、ライブラリ実装の不具合とも非不具合とも確定できない。**
> 明示的な remove 経路は正常であり、サンプルも公開 API のみを使用している。
> 一方、観測結果はライブラリの公開寿命契約と一致しておらず、
> **OS の実際の寿命仕様・ライブラリの文書契約・実装責務のいずれを修正すべきかは T-13 で判断する。**

### 3.4 申し送り

不一致は 2 箇所にまたがる。

| 対象 | 記述 | 状態 |
|---|---|---|
| `IosClipboardManager.swift:35` / `PasteboardScope.swift:10` | ライブラリの**公開 DocC 契約** | 観測と不一致。**要再評価** |
| `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md` | 設計書の「非永続」記述 | 同上 |

T-13 の長時間測定の結果が出るまでは、次のいずれとも断定しないこと。

- 「終了後ただちに解決不能になる」（現在の公開契約・設計書の含意。観測と矛盾する）
- 「永続する」（観測時間を超える主張になる）
- 「ライブラリの不具合ではない」（公開契約との不一致が未解消のため）

T-13 の測定後に決めるべきは、**どこを直すか**である。

1. OS 実仕様が契約どおりなら → 測定条件を疑い、再測定する
2. OS が遅延回収するだけなら → DocC / 設計書へ「回収タイミングは保証されない」旨を追記する
3. OS が回収しないなら → 公開契約の記述を訂正し、必要なら明示 remove を促す API 指針を追加する

---

## 4. 受け入れ判定の分離（M-02 への対応）

| 判定軸 | 状態 |
|---|---|
| `xcodebuild test` の成否 | **成功**（0 failures） |
| 計画 §9.2 U-1〜U-9 / U-11 / U-12 | **達成** |
| 計画 §9.2 **U-10（M-08 終了後の解決不能）** | **未達**。U-10b は skip であり、期待値 `CLIPBOARD_UNAVAILABLE` を確認していない |
| 操作カバレッジ 52 / 52 | **達成** |
| 計画書整合性（全体） | **未達**（U-10 のみ） |

**「テストコマンドが成功した」ことをもって計画の U-10 完了とはしない。**

未達を解消する経路は 2 つあり、どちらも本タスクの範囲外である。

1. T-13 の controlled long-duration measurement で回収の有無を確定する
2. その結果に基づき設計 v6 §9.2 / 機能設計 v4 の期待値・観測期間・T-13 への移管条件を改訂する

それまで U-10 / M-08 は **open risk** として維持する。

---

## 5. 全 21 件の実行結果

### 5.1 iOS 26.2 Simulator（iPhone 17 Pro）

修正後のビルドで、UI テスト 21 件と単体テスト 9 件を通し実行した。

```
Executed 21 tests, with 1 test skipped and 0 failures (0 unexpected) in 2549.787 seconds
** TEST EXECUTE SUCCEEDED **
```

| 区分 | 件数 |
|---|---:|
| UI テスト passed | 20 |
| UI テスト skipped（U-10b のみ） | 1 |
| UI テスト failed | **0** |
| 単体テスト passed | 9 |

M-01 の `.disabled` 追加による回帰はなく、v1 の全 21 件ランと同じ結果である
（v1: 20 passed / 1 skipped / 0 failed、2549 秒 vs v1 の Simulator 2 ラン合計 2522 秒）。

操作カバレッジは 52 / 52 のまま変わらない。

### 5.2 実機（iPhone XS / iOS 18.7.2）— **未実施**

**v2 の修正後のビルドでは実機ランを行っていない。**

v1 の実機ラン（20 passed / 1 skipped / 0 failed、2868 秒）は
**H-01 / M-01 修正前のビルド**に対するものである。したがって現時点の
「実機動作確認済み」は v1 のコードに対する結果であり、v2 のコードには及んでいない。

v2 で挙動が変わりうる箇所は次の 2 点。

| 変更 | 実機で挙動が変わる可能性 |
|---|---|
| M-01: `Probe Last Removed Scope` の `.disabled` 追加 | 画面状態のみ。OS 依存なし |
| M-01: ローカル失敗 3 経路の表示文字列統一 | 到達には bundle 欠損等が必要で、通常経路では発生しない |
| H-01: U-10b の preflight 追加 | **テストコードのみ。アプリ側の変更なし** |

いずれもプラットフォーム依存の処理を含まないため、実機で結果が変わる可能性は低い。
ただし**「低い」は「確認済み」ではない**。実機カバレッジを v2 のコードへ揃えるには、
全 21 件の実機再実行（推定約 48 分）が必要である。

> **未確認事項として明示する**: v2 のコードに対する実機動作確認は未実施。

#### 実機再実行を行わない判断（決定記録）

レビュー v1 反映後、**全 21 件の実機再実行は行わない**と判断した。根拠は次のとおり。

| # | 根拠 |
|---|---|
| 1 | アプリ側の変更は OS 非依存の表示・無効化処理のみ |
| 2 | H-01 の変更は UI テストコードだけで、アプリ側に変更がない |
| 3 | Simulator で 21 件中 20 件成功、U-10b のみ意図どおり skip |
| 4 | U-10 / M-08 は完了扱いにせず、公開契約との不一致として open risk になっている |
| 5 | 実機固有の寿命検証は T-13 の責務として分離できている |

**実機確認を行う場合も、全 21 件ではなく、T-13 で preflight 付き U-10b 相当の
長時間測定だけを対象にするのが妥当である。** 全件再実行は約 48 分を要する一方、
上記 1・2 より新しい情報がほとんど得られない。

判定: **レビュー v1 の指摘反映完了。実機 v2 未確認と U-10 / M-08 の open risk を
引き継いで次工程へ進行可能。**

---

## 6. v1 から変更していない事項

次は v1 のままである。本レポートでは再掲しない。

- 画面構成（11 セクション / 結果 marker 50 / control-only 2）
- 結果表示形式、セキュリティ方針の実装、依存方向
- Android / iOS 共通実装パターンへの維持・拡張
- Swift 6 移行負債への対応（`@unknown default` 4 箇所）
- 手動確認観点の充足状況（T-00 / T-13 への移管を含む）
- 計画からの逸脱・追加判断 1〜13

M-01 の修正により、追加判断 7（`Probe Last Removed Scope` の失敗表示を例外扱いする）は**撤回**する。
例外を作らず、表示契約に合わせる形へ変更した。

---

## 7. ステップ8 実行確認

- 提示文: 「このサンプル実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま終了
- ユーザー回答: 未回答
