# レビュー結果

- 日付: 2026-06-20
- 対象ファイル: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 関連ファイル: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 機能名: Share
- 対象 OS: Android 12 以降

---

## 強み

- `ChooserResult` が API 35 追加であることを反映し、API 34 のクラッシュ要因を正しく特定している。
- キャンセル時に chooser の `IntentSender` が呼ばれない制約を明文化している。
- リッチプレビューを Unity の利用例に絞り、既存の FileProvider 経路を再利用する方針は実装範囲が明確である。
- ライブラリと利用側アプリの Direct Share 受信責務を分離している。

## 改善点

### 高優先度

#### API 35 の callback は「共有先選択時のみ」ではない

- 対象: `#2 キャンセル時コールバックの仕様明文化`
- 問題: API 35 の `ChooserResult` は共有先選択に加えて Copy、Edit、Unknown も通知する。現在の設計は `selectedComponent == null` を「選択されたが取得不可」と定義しているため、Copy/Edit を誤って同じ結果として Unity に返す。
- 改善案: `ChooserResult.type` を判定する。既存 API を維持するなら `CHOOSER_RESULT_SELECTED_COMPONENT` の場合だけ package callback を通知する。Copy/Edit も公開するなら `ShareResultType` と packageName を持つドメイン結果へ拡張する。

#### キャンセル時に BroadcastReceiver が解除されず蓄積する

- 対象: `#2 キャンセル時コールバックの仕様明文化`、`リスクと緩和策`
- 問題: 現行実装は `onReceive` 内でのみ Receiver を解除する。キャンセルでは callback が来ないため Receiver が残り、再実行のたびに Receiver と callback が蓄積する。後続の選択で過去の callback まで呼ばれる可能性がある。
- 改善案: callback の所有者とライフサイクルを設計する。少なくとも新規開始時に前回 Receiver を解除し、Activity の破棄時にも解除する。Repository に callback 所有を残す場合でも、登録解除 API、単一登録制御、重複呼び出しテストを定義する。

#### 画像受信の完了条件と Manifest が矛盾している

- 対象: サンプルアプリ設計 `受信の前提`、`完了条件`
- 問題: Manifest は `ACTION_SEND` + `text/plain` だけだが、完了条件ではギャラリー等からの画像受信と `ACTION_SEND_MULTIPLE` を要求している。このままではアプリが画像の共有先に表示されない。
- 改善案: 通常共有用に `ACTION_SEND` の `image/*` と `ACTION_SEND_MULTIPLE` の intent-filter を追加する。Direct Share の `<share-target>` を text/plain のみにする方針とは分けて記述する。

#### 不正なサムネイルパスの fallback が実装設計にない

- 対象: `#5 リッチプレビュー`、`リスクと緩和策`
- 問題: DoD は不正パスでもプレビューなしで共有を継続するとしているが、再利用予定の `fileToContentUri` は `FileNotFound` / `IllegalFileAccess` を throw する。例外をどこで握り、どのエラーだけを fallback 対象にするかが未定義である。
- 改善案: `resolveOptionalPreviewUri(path): Uri?` 相当の変換方針を定義し、サムネイル変換エラーだけを警告ログ後に null 化する。本文共有の起動失敗まで握りつぶさないことを明記し、Repository のテストケースを追加する。

### 中優先度

#### サンプル設計が確定済みの path 方式に追従していない

- 対象: サンプルアプリ設計 `リッチプレビュー送信ボタン`、`注意事項`
- 問題: 親設計は `previewThumbnailPath` に確定しているが、サンプル設計には `previewThumbnailBase64`、`file.toBase64()`、方式未確定という記述が残っている。
- 改善案: `previewThumbnailPath = file.absolutePath` に統一し、Base64 と未確定の注記を削除する。

#### Direct Share の基本登録にも quota 判定の既存不具合が残る

- 対象: `#6 スコープ外`、既存 Direct Share 登録
- 問題: 現行実装は dynamic shortcut 数が上限なら同じ ID の更新も登録前に拒否する。一方 `pushDynamicShortcut` は上限時の入れ替えを処理できる。これは高度なランキングではなく、in-scope の登録・更新の正しさに関わる。
- 改善案: 単純な `currentCount >= maxCount` の事前拒否を廃止するか、同じ ID の更新を許可した上で AndroidX の戻り値・例外をドメインエラーへ変換する設計を追加する。

#### テスト設計が主な修正箇所を直接検証しない

- 対象: `テスト設計（v3 差分）`
- 問題: API 分岐を「手動 / instrumented 寄り」とするだけで具体的なテストがなく、Receiver の解除、API 35 の result type、preview URI と grant flag、fallback を検証できない。
- 改善案: API 34/35 の instrumented test、または Android API をラップした adapter の単体テストを明記する。Receiver の重複登録・キャンセル後再実行も試験項目に含める。

### 低優先度

#### コード例のコメント・KDoc がリポジトリ規約と不一致

- 対象: サンプルアプリ設計の Kotlin コード例
- 問題: `ReceivedShareContent`、`IncomingShareParser`、`MainActivity` の KDoc とコメントが日本語だが、共通規約ではコメントを英語にする。
- 改善案: 実装へ転記されるコード例の KDoc とコメントを英語へ変更する。

#### EXTRA_TEXT の型を String に限定している

- 対象: サンプルアプリ設計 `IncomingShareParser`
- 問題: `Intent.EXTRA_TEXT` は `CharSequence` であり、`getStringExtra` では Spanned 等を取得できない。
- 改善案: `getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()` を使用し、`ACTION_SEND_MULTIPLE` に付随する text も必要なら同様に取得する。

## 不足項目

- API 35 の Copy/Edit/Unknown callback の公開仕様
- キャンセル後に残る Receiver の解除戦略とライフサイクル
- 画像・複数画像を受信する Manifest intent-filter
- optional thumbnail 変換失敗時の具体的な fallback 処理
- API 34/35/36 の callback 統合テスト
- Direct Share 選択時に受信した URI 権限をいつまで利用するかの試験条件

## 総合評価

API 35 判定修正、キャンセル制約、リッチプレビュー採用という方向性は妥当である。ただし callback の意味と Receiver の寿命に高優先度の欠落があり、現状のまま実装すると誤通知と Receiver 蓄積が残る。サンプル設計にも Manifest と完了条件、サムネイル入力形式の不整合があるため、実装着手前に v3 本文とサンプル設計を同時に改訂する必要がある。
