# レビュー結果

- 日付: 2026-05-24
- 対象ファイル: artifact/designs/share/2026-05-24-android-share-implementation.md
- 機能名: share
- 対象 OS: Android

---

## 強み

- Clean Architecture 層分離が明確で Domain に Android 型が混入しない方針が一貫している
- `ShareDomainError` が sealed class で網羅的に定義され、エラーコード/メッセージ対応表も整備されている
- API 31/34 のコールバック分岐設計が具体的
- BroadcastReceiver リーク・`RECEIVER_NOT_EXPORTED` 未設定など Android 固有リスクへの対策が実装レベルで具体的
- タスク分解が Domain → Port → UseCase → Data → Bridge の依存順に正しく並んでいる
- Manager → UseCase → Repository 経路が設計図で示されている
- 手動確認項目が API 31/34 両バージョンで網羅されている
- common.md・android.md 準拠チェック表が設計書内に組み込まれている

## 改善点

### 高優先度

**ChooserActionSpec のデータ構造未定義**
- 問題: `ShareContent` に `chooserActions: List<ChooserActionSpec>` を持たせると記載があるが `ChooserActionSpec` の定義が存在しない。また `ChooserAction` はプレゼンテーション層の概念のため Domain 型 `ShareContent` に持たせるのは責務外
- 改善: `ChooserActionSpec` のフィールド定義（label, iconBase64, intentAction 等）をデータ構造セクションに追加する。`ShareContent`（Domain）ではなく `UnityShareTextSpec` 側に保持し、RepositoryImpl には別引数として渡す設計に変更する

**`onShareResult` のシグネチャ不一致**
- 問題: 公開 API 定義では `onShareResult(operation: String, selectedPackageName: String?)` だが、設計書本文では `onShareResult(packageName)` と単一引数で記載されており不一致
- 改善: シグネチャを統一する。`shareWithCallback` 以外の API では `onShareResult` が呼ばれないことを明示する

### 中優先度

**`shareWithCallback` の Port 契約が不明瞭**
- 問題: `onResult` がワンショット保証であること・呼び出しタイミングが Port 定義に未記載
- 改善: KDoc に「シェア完了後に選択パッケージ名（キャンセル時は null）で一度だけ呼ばれる」旨を明記する

**UseCase テストのエラー系ケース欠落**
- 問題: `ShareImageUseCase` の mimeType 空文字・`ShareFileUseCase` の FileNotFound / IllegalFileAccess・`RegisterDirectShareTargetUseCase` の InvalidBase64Icon が未記載
- 改善: UseCase テスト表に上記エラー系テストケースを追加する

**Manager 層の単体テスト欠落**
- 問題: `UnityAndroidShareManager` の `executeOperation` エラー変換（`ShareDomainError` → `onShareOperation(isSuccessful=false, ...)`）のテストがない
- 改善: Task 7 に Manager のエラー変換テストケースを追加する

**Direct Share 登録上限超過リスク未記載**
- 問題: `pushDynamicShortcut` は上限超過時に例外ではなく `false` を返す場合があり、`DirectShareRegistrationFailed` だけでは区別できない
- 改善: `getMaxShortcutCountPerActivity` との比較ロジックを設計に含め、リスク表に追加する

### 低優先度

**`ShareContent` の使用範囲が不明瞭**
- 問題: `mimeType` バリデーションの責務が UseCase か RepositoryImpl かが不明確。テキスト系シェア専用であることが設計書から読み取りにくい
- 改善: テキスト系シェアのみに使う旨と `mimeType` バリデーションを UseCase に置くことを明示する

**既存実装との差分が抽象的**
- 問題: 既存 Manager（例: `UnityAndroidNotificationManager`）の `executeOperation` パターンへの参照がない
- 改善: 既存 Manager の実装パターンへの参照パスを記載し、ShareManager がどう踏襲するかを明示する

## 不足項目

- `ChooserActionSpec` のデータ構造定義（フィールド・型・JSON スキーマ）
- `UnityAndroidShareManager` の単体テスト（`executeOperation` エラー変換検証）
- `onShareResult` シグネチャの統一
- Direct Share 登録上限超過リスクと `pushDynamicShortcut` 戻り値チェック設計
- `shareImage` / `shareImages` / `shareFile` / `shareFiles` で `ShareContent` を使わない設計判断の明示
- `shareWithCallback` キャンセル時（`onResult(null)`）のテストケース
- `file_paths.xml` に定義するパス種別の列挙と対応ディレクトリ説明
- `UnityShareImageSpec`（単一画像用）のデータ構造定義（`UnityShareFileSpec` と共用か分離か）
- `clearShareOperationListener` と BroadcastReceiver の登録解除の関係設計
- `proguard-rules.pro` の具体的な keep ルール内容

## 総合評価

Clean Architecture 準拠・リスク対策・DoD の品質は高水準にある。`ChooserActionSpec` 定義欠落と `onShareResult` シグネチャ不一致は実装時に混乱を招く high severity 項目であり着手前に解消が必要。Manager 層のエラー変換テスト欠落も早期補完を推奨する。これらを修正すれば実装フェーズに移行できる品質水準に達している。
