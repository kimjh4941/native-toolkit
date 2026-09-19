# レビュー結果

- 日付: 2026-06-21
- 対象ファイル: `artifact/designs/share/2026-06-21-android-share-sample-app-design-v4.md`
- 機能名: share
- 対象 OS: Android 12 以降

---

## 強み

- Custom Chooser Actions、callback 付き rich preview、`subject`、明示的な callback cancel について、既存の公開 API と変更箇所の対応が明確である。
- Custom Chooser Actions の API 34 境界、`PendingIntent`、アプリ内 receiver、`Base64.NO_WRAP` まで記載され、end-to-end の操作像が具体的である。
- rich preview のサムネイルを既存 FileProvider の `<cache-path>` 配下に生成する方針は、現在の Manifest と `file_paths.xml` に整合している。
- 変更対象をサンプルアプリの 3 ファイルに限定しており、「ライブラリ側は変更しない」というスコープが明瞭である。

## 改善点

### 高優先度

#### 1. `cancelPendingCallback` の手動確認手順と期待ログが実装に整合しない

- 対象: 「4. cancelPendingCallback の明示呼び出し」「完了条件」「手動確認手順」
- 問題: `cancelPendingCallback()` は `ShareCallbackCoordinator.cancel()` から pending receiver を unregister する。そのためキャンセル後の broadcast は通常 receiver に到達せず、`[onReceive] stale or cancelled registration; ignoring` は出力されない。また、Sharesheet を閉じて画面へ戻った時点で、その chooser 上で後から共有先を選択する操作もできない。
- 影響: 記載された手順では「押下後に pending callback が解除された」ことを期待どおり検証できず、完了条件が再現不能になる。
- 改善案: 手動確認は、callback share をキャンセルして画面へ戻る、明示キャンセルボタンを押す、Logcat で `CancelPendingShareCallbackUseCase`、`ShareRepositoryImpl`、`ShareCallbackCoordinator` の cancel/unregister ログを確認する、という手順に変更する。`stale or cancelled registration` を期待ログから外し、必要なら coordinator の既存単体テストを根拠として併記する。

#### 2. 「ライブラリ機能を全網羅」という主張に対して `ShareContent.title` が未デモのまま

- 対象: 「概要」「未デモ機能一覧」「完了条件」
- 問題: 公開モデル `ShareContent` には chooser dialog title 用の `title` があるが、現行サンプルにも v4 の追加案にも指定例がない。rich preview の `SharePreviewOptions.title` は別の値であり、代替にならない。
- 影響: v4 完了後も公開 API の利用例が一つ欠けるため、「全網羅」という完了判定が成立しない。
- 改善案: `Share with Subject` などの追加例に `ShareContent.title = "Choose an app"` を併記し、Sharesheet の chooser title 確認を完了条件と手動確認へ追加する。対象外とするなら、全網羅の表現を「今回確認した未デモ 4 機能を補完」に限定し、`title` を対象外一覧へ明記する。

### 中優先度

#### 3. 画像準備コードの失敗処理が既存サンプルより弱い

- 対象: Custom Chooser Actions、callback + rich preview のコード例
- 問題: 両例とも `BitmapFactory.decodeResource()` の null を扱わず、Custom Chooser Actions 例は bitmap 圧縮や JSON 作成を含む IO coroutine 全体の例外も捕捉していない。callback + rich preview 例もファイル生成失敗を捕捉していない。
- 影響: drawable decode やファイル IO に失敗すると coroutine の未処理例外になり、status 表示へ失敗内容を反映できない。既存の rich preview 実装が採用している `?: run { ...; return@launch }` と外側の `try/catch` にも整合しない。
- 改善案: 既存の `Share Text with Rich Preview` と同じく、decode の null 分岐、IO 全体の `try/catch`、Main dispatcher 上の `File preparation failed` 表示をコード例へ含める。`ByteArrayOutputStream` は `use` で閉じる。

#### 4. `Log.d` 必須要件がコード例に反映されていない

- 対象: 4 ボタンのコード例、作成・変更ファイル一覧
- 問題: 文末では「全 onClick の主要処理に `Log.d`」を要求している一方、提示された全コード例に押下時ログがない。
- 影響: 設計書をそのまま実装すると、完了条件および Android コーディングルールの確認で不足が生じる。
- 改善案: 各 `onClick` の先頭に一意な操作名を含む `Log.d(SHARE_TAG, "[onClick...]" )` を明記し、非同期処理では入力値や生成結果のサイズなど必要なパラメータも記録する。

### 低優先度

#### 5. 入力バリデーション方針が明示されていない

- 対象: 詳細設計全体
- 問題: 今回は固定値のみでユーザー入力がないため UI バリデーションは不要だが、その判断と、`ShareContent.text` の検証を use case に委ねる方針が記載されていない。
- 改善案: 「ユーザー入力項目は追加しない。固定サンプル値を使用し、ドメイン入力検証は既存 use case に委譲する」と明記する。

## 不足項目

- `ShareContent.title` のデモ方針と手動確認項目
- `cancelPendingCallback` で実際に観測可能なログを使った検証手順
- bitmap decode／ファイル生成失敗時の UI 表示と処理中断方法
- 各追加ボタンに入れる `Log.d` の具体的な位置とメッセージ
- UI 入力がないことを含む入力バリデーション方針

## 総合評価

追加する 4 操作の選定と既存 API への接続方針は概ね妥当で、変更範囲も適切である。ただし、明示キャンセルの完了条件は現在の coordinator 実装では記載どおりに観測できず、さらに「全網羅」の主張に対して `ShareContent.title` が漏れている。この 2 点は実装開始前に修正が必要である。画像準備時のエラー処理とログ要件を既存 `ShareSampleScreen` の実装パターンへ合わせれば、実装可能な計画になる。
