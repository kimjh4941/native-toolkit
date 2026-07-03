# レビュー結果

- 日付: 2026-05-24
- 対象ファイル: artifact/plans/share/2026-05-23-android-share-research.md
- 機能名: share
- 対象 OS: Android

---

## 強み

- 公式ドキュメントが9件網羅されており、AndroidX・Android Developer の主要リファレンスが揃っている
- 機能マップがツリー形式で整理されており、実装スコープが一目で把握できる
- API 全網羅表に最小条件・エラーケース・返却値が記載されており、実装者が迷わない構成になっている
- ChooserTargetService 廃止など実際に踏みやすいリスクが明示されている
- サンプルコードが各サブ機能ごとに独立した関数として分かれており、コピーペーストで試しやすい
- Definition of Done が機能単位でチェックリスト化されており、検収判断が明確

## 改善点

### 高優先度

**シェア結果コールバック（API 29+） — API バージョン非対応**
- 問題: `IntentCompat.getParcelableExtra` で `ChooserResult` を取得しているが、`ChooserResult` は API 34 以上でしか存在しない。API 29〜33 端末では `ClassNotFoundException` が発生する
- 改善: `Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE (34)` の分岐を追加し、API 34 未満では `selectedComponent` の取得をスキップするか、`ComponentName` のみを取り出す代替処理を記載する

**シェア結果コールバック（API 29+） — BroadcastReceiver のメモリリーク**
- 問題: `registerReceiver` が `unregisterReceiver` されていないため、Activity/Fragment のライフサイクル外でメモリリークが発生する
- 改善: `receiver` を呼び出し元に返すか、`onReceive` 内で `context.unregisterReceiver(this)` を呼ぶワンショット実装にする。また Android 14（API 34）以降は `registerReceiver` に `RECEIVER_NOT_EXPORTED` フラグが必要である点も注記する

**Direct Share ターゲット登録 — カテゴリ文字列の要件未明示**
- 問題: `setCategories` に渡す category 文字列の形式が明示されておらず、任意文字列を渡すと Sharesheet に表示されない
- 改善: `android.shortcut.conversation` など定義済み定数を使用する旨と、`ShortcutInfoCompat.Builder` の `setCategories` に渡す値の要件をコメントで明示する

### 中優先度

**API 全網羅表 — EXTRA_CHOSEN_COMPONENT 欠落**
- 問題: `ChooserResult.selectedComponent` は API 34 の行のみで、API 29〜33 における選択アプリ取得手段（`EXTRA_CHOSEN_COMPONENT`）が表に存在しない
- 改善: `Intent.EXTRA_CHOSEN_COMPONENT`（API 22+）を別行で追加し、API 29〜33 と API 34+ で取得方法が異なることを表中に注記する

**単一画像シェア — MIME 型ハードコード**
- 問題: `type` を `"image/jpeg"` にハードコードしているため、PNG や WebP の URI を渡すと MIME 不一致で表示されないアプリが出る
- 改善: ファイルシェアサンプルと同様に `getMimeType(uri)` で動的に判定するか、引数に `mimeType: String = "image/*"` を追加して呼び出し元が指定できるようにする

**Definition of Done — 検証 API バージョン未指定**
- 問題: テスト端末の API バージョン範囲が未指定のため、どの OS バージョンで検証すれば DoD 達成とみなせるか判断できない
- 改善: 最小確認バージョン（例: API 26, 29, 33, 34）を DoD に明記するか、別途テストマトリクスセクションを追加する

### 低優先度

**実装リスク — Predictive Back（API 33+）未記載**
- 問題: Android 13（API 33）以降で Predictive Back Gesture により Chooser UI の戻る動作が変化する点が未記載
- 改善: リスク行を追加し、API 33+ での Predictive Back の影響と `enableOnBackInvokedCallback` の設定不要（Chooser 側の制御）である旨を補足する

## 不足項目

- `EXTRA_CHOSEN_COMPONENT`（API 22+）によるコールバック取得方法 — `ChooserResult` が使えない API 29〜33 での代替手段
- `ChooserAction`（カスタムチューザーアクションボタン）の実装サンプル — 公式文書 URL は記載されているが API 表・サンプルコードが存在しない
- `ShareCompat.IntentBuilder` の実装サンプル — API 表に記載があるがサンプルコードがなく、従来 `Intent` との使い分け基準が不明
- `AndroidManifest.xml` への FileProvider 宣言例（`provider` タグ・`authority`・`resource` xml）
- `res/xml/file_paths.xml` のサンプル — FileProvider の paths 定義がなければ `getUriForFile` が `IllegalArgumentException` をスローする
- `getMimeType` ユーティリティ関数の実装例 — 複数サンプルで参照されているが定義が存在しない
- Android 14（API 34）以降での `registerReceiver` に必要な `RECEIVER_NOT_EXPORTED` / `RECEIVER_EXPORTED` フラグの説明
- Sharesheet カスタムタイトル・プレビュー設定（`EXTRA_TITLE`, `EXTRA_PREVIEW_IMAGE_URI`）の API 表への追加
- URL シェアの独立したサンプルコード — テキストシェアと同じ実装で済むなら明示的にその旨を記載すべき
- ProGuard / R8 設定 — `ShortcutInfoCompat` や `FileProvider` を難読化すると動作しなくなるケースへの言及
- 要検証事項の検証担当・期限 — 項目は列挙されているが誰がいつ検証するか未定義

## 総合評価

全体的に公式ドキュメントの参照範囲・API 網羅表・リスク分析の構成は良くまとまっており、設計書作成の土台として十分な情報量を持つ。一方、シェア結果コールバックサンプルにおける API バージョン非対応（`ChooserResult` を API 34 未満で使用）と `BroadcastReceiver` のリークという致命的なバグが含まれており、そのまま実装に使用するとクラッシュとメモリリークが発生する。FileProvider の Manifest・paths.xml 設定例や `getMimeType` の実装例など、サンプルコードを動かすために必須な補助コードも欠落している。これらを補完すれば実装設計書のインプットとして即時使用可能なレベルに達するため、高リスク項目を優先して修正することを推奨する。
