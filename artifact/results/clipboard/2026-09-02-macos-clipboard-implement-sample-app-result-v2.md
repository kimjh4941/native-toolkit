# サンプルアプリ実装結果 v2

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md`
- 対応タスク: T-18（機能設計 §13）
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md`
- 反映したレビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v1.md`

> **v1 との最大の違いは、UI テストが実行できたことである。** v1 は「環境で実行できない」と
> 記録したが、本版では 5 件すべてを実行し、そのうち 4 件が失敗した。失敗はいずれも本物で、
> 実装 1 件・テスト 3 件の欠陥だった（§3）。

---

## 1. レビュー v1 の 4 件

| 指摘 | 対応 | 反映 |
|---|---|---|
| Active scope の必須 Picker が未実装 | segmented `Picker` を追加。`scopeChoice` と `applyScopeChoice(_:)` | 反映 |
| `DetectMetadata` が arrange の失敗を握りつぶす | `try?` を `do/catch` に変更し、失敗時は検査せず失敗を表示 | 反映 |
| UI テストが前回の結果を新しい結果として受理する | `tap` はクリックしたボタン自身のラベルが結果に現れるまで待ち、出なければ `XCTFail` | 反映 |
| ST-05 が block comment 内の呼び出しを実コードとして数える | block comment → line comment → 文字列リテラルの順に除去 | 反映 |

無関係な `xcuserstate` の変更はコミット対象から除外した。

**Picker の追加は、この時点では未検証のまま入った。** 実際には後述 R-SA5 の欠陥を持ち込んで
いた。UI テストを実行して初めて分かったことである。

---

## 2. UI テストが実行できるようになった経緯

v1 では、起動したアプリのアクセシビリティ階層が空で要素が 1 つも取れなかった。本版で再実行
したところ、同じ症状が最初は再現し、その後は再現しなくなった。

| 時点 | 観測 |
|---|---|
| 再実行 1 回目 | XCUITest: `windows=0 buttons=0`。ツリーは MenuBar のみ、Application は Disabled |
| 同 | XCUITest 非経由の `AXUIElementCopyAttributeValue(kAXWindowsAttribute)` でも `count 0` |
| 同 | `CGWindowListCopyWindowInfo` では 903x644 の実ウィンドウが 1 枚存在 |
| 以降すべて | XCUITest: `windows=1 buttons=7`。以後 10 回連続で安定 |

**ウィンドウは常に存在していた。アクセシビリティ API がそれを公開していなかった。** XCUITest
非経由の probe でも同じ結果だったので、原因は XCUITest 側ではない。

**切り替わった正確な引き金は特定できていない。** Xcode は再実行時には起動していなかった。
AX クライアントが一度接続した後に見えるようになった、という順序関係は観測できたが、因果は
確認していない。**再発する可能性があるため、UI テストが 0 要素で失敗した場合はこの現象を
最初に疑う。**

v1 に書いた「既存の `ShareSampleViewUITests` も同一症状で失敗するので原因は外にある」は、
外にあるという結論自体は正しかったが、**TCC の権限問題という推定は裏付けが取れていない。**
本版では推定を落とし、観測のみを記録する。

---

## 3. UI テスト実行で見つかった 4 件

実行結果は 1 passed / 4 failed だった。内訳は次のとおり。

### R-SA5（実装の欠陥）: Picker の同期が Picker 自身の動作を起こす

- 症状: `RemoveCurrentPasteboard` の結果が画面に出ず、`[scopePicker] active scope is now
  general` に置き換わる。MS-03 が失敗。
- 原因: `onChange(of: scopeChoice)` は**コードによる代入でもクリックと同じように発火する**。
  `runScopeCreating` と `removeCurrentPasteboard` は最後に `scopeChoice` を実際のスコープへ
  合わせるので、その代入が `applyScopeChoice` を呼び、
  - `named` / `unique` では **`createPasteboard` がもう一度走る**
  - どの分岐でも、直前に書いた結果行を上書きする
- 修正: `syncScopeChoice(_:)` を追加し、コードからの同期では `isSyncingScopeChoice` を立てて
  `onChange` の本体を 1 回だけ飛ばす。値が変わらないときは `onChange` が発火しないため、
  フラグが残って次の利用者操作を飲み込まないようガードを置いた。

**レビュー v1 で追加した Picker が持ち込んだ欠陥である。** 画面の状態を 2 か所（`activeScope`
と `scopeChoice`）で持つ以上、同期経路と操作経路を区別しなければならない。

### R-SA6（テストの欠陥）: 画面外のボタンをクリックしたことにしていた

- 症状: MS-01 の最後の `CheckForegroundChange` だけが結果を返さない。
- 原因: スクロールして表示領域の外に出たボタンは、**存在もし、`isHittable` が true にも
  なる**。クリックはその座標に対して行われ、そこにあるヘッダに当たる。操作は走らず、前の
  結果が画面に残る。実測では `CheckForegroundChange` の frame は y=314、スクロールビューの
  表示領域より上だった。
- 修正: `scrollIntoView(_:_:named:)` を追加し、クリック前にボタンの frame をスクロールビュー
  の frame の内側へ入れる。スクロール量の符号は入力デバイスによって向きが変わるため、
  1 回目の移動方向を見て符号を決める。

### R-SA7（テストの欠陥）: 戻るボタンの識別子が実在しない

- 症状: MS-05 が `app.buttons["Main Menu"]` を見つけられない。
- 原因: macOS の `NavigationStack` の戻るコントロールは identifier が `chevron.backward`、
  label が `Back`。**戻り先の画面名では引けない。**
- 修正: `chevron.backward` で引く。

### R-SA8（テストの欠陥）: 秘匿の検査が文言を要求していた

- 症状: MS-07 が「メッセージに `not shown` が含まれること」を要求して失敗。実際の表示は
  `✅ [createEmptyNamedPasteboard] expected 1505 as designed`。
- 原因: **秘匿とは「出さない」ことであって「出さないと宣言する」ことではない。** 表示は
  正しく、検査が誤っていた。
- 修正: 名前が画面に現れないことを検査する。名前は
  `ClipboardSampleView.swift` の `sampleName` からソース経由で読み、リテラルを二重に持たない。

---

## 4. 修正が効いていることの確認（変異検査）

| 壊した内容 | 期待 | 結果 |
|---|---|---|
| `syncScopeChoice` からフラグを外し、直接代入に戻す | MS-03 が落ちる | **落ちた**（`RemoveCurrentPasteboard did not report`） |
| `tap` から `scrollIntoView` の呼び出しを削除 | MS-01 が落ちる | **落ちた**（`CheckForegroundChange did not report`） |

いずれも修正を戻すと元の失敗が再現する。**通ったから正しいのではなく、壊すと落ちることを
確認した。**

---

## 5. テスト結果

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` | 11 | 12 | 0 |
| `MacLibraryExampleUITests/ClipboardSampleViewUITests` | 5 | 5 | 0 |
| `MacLibrary` | 307 | 351 | 0 |
| `UnityMacPlugin` | 75 | 76 | 0 |

- 件数はすべて xcresult から取得した（`xcrun xcresulttool get test-results summary`）。
- Clipboard 由来のコンパイル警告 0 件。ログに残る唯一の `warning:` は
  `appintentsmetadataprocessor` の定型出力で、全ターゲット共通の既存事象である。

### MS の確認状況

| MS | 内容 | v1 | v2 |
|---|---|---|---|
| MS-01 | 各セクションの代表ボタンが必ず結果を更新する | 未確認 | **確認済み** |
| MS-02 | 期待どおり失敗した場合に成功として表示される（1508） | 未確認 | **確認済み** |
| MS-03 | Active scope が scope 引数を持つ操作に反映される | 未確認 | **確認済み** |
| MS-05 | 画面を離れると監視が停止する | 未確認 | **確認済み** |
| MS-07 | 利用者が付けた名前が画面に出ない（1505）／標準名は出る（1508） | 未確認 | **確認済み** |

---

## 6. 変更ファイル（v1 からの差分）

| パス | 内容 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | Picker 追加、`syncScopeChoice` 追加、`DetectMetadata` の失敗処理 |
| `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift` | `scrollIntoView` 追加、`tap` の待ち条件、戻るボタン、MS-07 の検査、実行不能の注記を削除 |
| `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift` | ST-05 の block comment 除去 |
| `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/xcschemes/` | 共有スキーム。CLI から `xcodebuild -scheme MacLibraryExample` を実行するために必要 |

---

## 7. 残作業

| 項目 | 状態 |
|---|---|
| MT-01 / MT-02 / MT-03 / MT-04 / MT-06 / MT-07 | **未実施**（手動確認） |
| MT-08 | **未実施**（端末 2 台が必要） |
| MT-09 | 判定保留 |
| 平文 `detectMetadata` が 1515 を返す件 | **要検証** |
| `PasteButton` が `supportedContentTypes` に一致しない provider を渡すか | **要検証**（MT-06 と 1521 到達に必要） |
| BT-01 / BT-08 / BT-12 / CT-05 | **未実装**（機能設計 §12.4 に記載済み） |
| `ShareSampleViewUITests` の再実行 | **未実施**。clipboard の範囲外だが、環境が直った今なら実行できる可能性がある |
