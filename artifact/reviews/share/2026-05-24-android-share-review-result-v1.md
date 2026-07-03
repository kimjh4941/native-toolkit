# レビュー結果レポート

## 基本情報

- 日付: 2026-05-24
- ブランチ: feature/NTKIT-8（未コミット差分）
- 設計書: artifact/designs/share/2026-05-24-android-share-implementation-v2.md
- 実装結果ファイル: artifact/results/share/2026-05-24-android-share-implementation-result-v1.md
- 対象OS: Android

---

### レビュー概要

ブランチ `feature/NTKIT-8`（未コミット差分）の Android シェア機能実装を対象とする。
Clean Architecture に準拠した Domain → Application → Data → Manager 構成で、Unity Bridge 経由の全 8 操作を実装している。テスト 54 件は全件 PASSED。主な指摘は中程度のバグ（JSON injection）と設計仕様との差分（DeadCode・テスト漏れ）。

---

### 重大な問題（high）

なし

---

### 改善提案（medium）

**1. `buildChooserActionsJson` で手動 JSON 文字列結合 → malformed JSON リスク**

`android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt:316-325`

```kotlin
// 現在: 手動結合。label / intentAction に " や \ が含まれると JSON が壊れる
sb.append("""{"label":"${action.label}","iconBase64":"${action.iconBase64}","intentAction":"${action.intentAction}"}""")
```

`iconBase64` は Base64 文字セット（`[A-Za-z0-9+/=]`）のみなので安全だが、`label` と `intentAction` は任意文字列。修正方針: `JSONObject` で構築する。

```kotlin
val obj = JSONObject().apply {
    put("label", action.label)
    put("iconBase64", action.iconBase64)
    put("intentAction", action.intentAction)
}
```

---

**2. `ShareDomainError.NoShareTarget` が定義されているが、実装上到達不能**

`android/android_library/src/main/java/android/library/share/domain/error/ShareDomainError.kt:10`

設計書のエラー一覧では `NoShareTarget` を "受信アプリなし（ActivityNotFoundException）" に対応付けているが、RepositoryImpl も Manager も `NoShareTarget` を throw しない。Manager の `executeOperation` が `ActivityNotFoundException` を直接キャッチして "No app available..." を返す実装になっている。

`NoShareTarget` を throw する箇所を追加するか、設計書との差分として正式に記録する必要がある。

---

**3. `ShareTextUseCase.invoke` の Log.d に `chooserActionsJson` パラメータが欠落**

`android/android_library/src/main/java/android/library/share/application/usecase/ShareTextUseCase.kt:21`

```kotlin
operator fun invoke(content: ShareContent, chooserActionsJson: String = "[]") {
    Log.d(TAG, "[invoke] content: $content")  // chooserActionsJson が未ログ
```

android.md 違反: 全パラメータをログに含める必要がある。

修正:
```kotlin
Log.d(TAG, "[invoke] content: $content, chooserActionsJson: $chooserActionsJson")
```

---

**4. `ShareUseCasesTest` にテスト漏れあり（設計書指定）**

設計書テスト設計と実装の差分:

| 設計書テストケース | 状態 |
|---|---|
| ファイルシェア正常系 `ShareFileUseCase` — `repository.shareFile` が呼ばれる | 未実装 |
| ファイルシェア `IllegalFileAccess` — `ShareFileUseCase` | 未実装（UseCase からは到達不能のため設計書の記述が誤り: RepositoryImpl テストが正） |
| 複数ファイルシェア正常系 `ShareMultipleFilesUseCase` — `repository.shareFiles` が呼ばれる | 未実装 |

正常系テストの不在により、UseCase が repository を正しいパスで呼んでいるかの保証がない。
また `FakeShareRepository.shareFile` / `shareFiles` に呼び出し確認用のフィールドがない。

---

**5. 複数ファイル UseCase と単一ファイル UseCase でバリデーション層が不統一**

- `ShareFileUseCase`: UseCase でファイル存在確認（`File.exists()`）を行う
- `ShareImageUseCase`, `ShareMultipleImagesUseCase`, `ShareMultipleFilesUseCase`: UseCase でファイル存在確認を行わず RepositoryImpl に委ねる

設計書の制御フロー記述（セクション 2: 画像シェア）には UseCase 段でのファイル存在確認の記述がなく、意図的な非対称設計の可能性がある。ただし画像シェアでの FileNotFound は UseCase ではなく RepositoryImpl 経由でのみ確認できる状態になっている。
設計書に「画像シェアは RepositoryImpl で FileNotFound を処理する」と明記するか、UseCase に存在確認を追加して統一することを推奨。

---

### 軽微な指摘（low）

**L1. `ShareWithCallbackUseCase.invoke` の Log.d に `onResult` ラムダが未ログ**

`android/android_library/src/main/java/android/library/share/application/usecase/ShareWithCallbackUseCase.kt:22`

ラムダ型パラメータのログ出力は実用上の価値が低いが、android.md の「全パラメータ」原則との整合性のため `onResult: (String?) -> Unit` の存在を明記するか、除外対象とプロジェクトルールに追記することを推奨。

**L2. `ShareRepository` インターフェースの KDoc が最小限**

`android/android_library/src/main/java/android/library/share/application/port/ShareRepository.kt:6-8`

設計書では `chooserActionsJson` を Port に追加することを「Domain 汚染を避けた実用的妥協」と説明しているが、KDoc にその理由が記載されていない。Port を読んだ人が `chooserActionsJson: String = "[]"` の意図を把握できるよう補足を推奨。

**L3. `ShareDomainError` の class-level KDoc が最小限**

`android/android_library/src/main/java/android/library/share/domain/error/ShareDomainError.kt:4-6`

"Domain errors for share operations." のみ。sealed subtype のドキュメントは十分だが class 自体の説明が薄い。

---

### 設計書整合性チェック

- 企画書との整合性: ○（全サブ機能が実装されている）
- Clean Architecture 準拠: ○（Domain に Android 型なし、Manager → UseCase → Repository 経路を維持）
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（正常系 shareFile/shareFiles テスト欠落、IllegalFileAccess 扱いの齟齬）
- ドメインエラー全ケース実装: △（`NoShareTarget` が定義されているが実際には throw されない）
- エラーコード/メッセージ対応表との整合: ○（全エラーメッセージが設計書と一致）

---

### プロジェクトルール適合チェック

- common.md 準拠: ○
- android.md 準拠: △（`ShareTextUseCase.invoke` の Log.d パラメータ漏れ）
- エラー契約反映: ○（全 ShareDomainError サブタイプが Manager の executeOperation でキャッチされている）
- 既存 API 互換性: ○（破壊的変更なし）

---

### テストカバレッジ

カバーできている観点:
- UseCase の全エラー系（EmptyContent / InvalidMimeType / EmptyFileList / EmptyIdList / FileNotFound）
- JSON パーサーの正常系・異常系・各フィールドバリデーション（17 件）
- Manager のエラー変換（parser 経由エラーメッセージを含む、10 件）
- MIME タイプマッピング（12 件）
- shareWithCallback のコールバック正常系・キャンセル系

不足している観点:
- `ShareFileUseCase` の正常系（repository が正しいパスで呼ばれることの検証）
- `ShareMultipleFilesUseCase` の正常系
- `ShareImageUseCase` / `ShareMultipleImagesUseCase` の FileNotFound（RepositoryImpl 経由のため UseCase テストでは確認不能）
- `NoShareTarget` エラーパス（現実装では到達不能）

---

### 総合評価

**要修正（軽微）**

重大なロジックバグはなく、全テストも通過している。ただし `buildChooserActionsJson` の JSON インジェクションリスクと、設計書に記載されたテストケースの漏れを修正してから確定することを推奨する。
