# 実装結果レポート v4（アーキテクチャ訂正: ClipboardChangeMonitor の配置修正）

## 基本情報

- 日付: 2026-07-25
- 機能名: clipboard
- 対象OS: Android
- 設計書: artifact/designs/clipboard/2026-07-25-android-clipboard-design.md（**v5**）
- 実装結果 v1/v2/v3: artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v1.md / v2.md / v3.md
- ブランチ: feature/NTKIT-12

本レポートは v1〜v3 の記載と実コードの間に生じた乖離を訂正する。v1〜v3 は本訂正の対象範囲以外は変更なく有効。

---

## 1. 訂正の背景

v1〜v3 作成後、サンプルアプリ実装（`implement-sample-app`）の過程で、`agent-rules/coding-rules/common.md`「Unity Bridge 専用クラスにも Delegate を実装しない（native など別用途での利用ができなくなるため）」への違反が判明した。

- v1〜v3 時点の実装: `ClipboardChangeMonitor`（system `OnPrimaryClipChangedListener` の所有者）を `unity_android_plugin`（Unity Bridge 専用モジュール）に配置していた
- 問題: この配置では native サンプルアプリ（`AndroidLibraryExample`）が Unity Bridge に依存しない限り、クリップボード変更監視機能を利用できなかった
- 対応: 設計書を v5 に改訂し、`ClipboardChangeMonitor` を `android_library` の `presentation` 層へ移設。`UnityAndroidClipboardManager` は自身で system listener を持たず、移設後のクラスへ委譲する形に変更した（コミット `73de0358`）

この訂正は `implement-sample-app` の作業中に発見・対応されたため、`implementation-feature-result-v1〜v3.md` には反映されていなかった。

---

## 2. 訂正内容（v1〜v3 との差分）

### 2.1 ファイル配置の訂正

| ファイル | v1〜v3 の記載（誤り） | 正しい配置（現状） |
|---|---|---|
| `ClipboardChangeMonitor.kt` | `android/unity_android_plugin/src/main/java/android/unity/clipboard/ClipboardChangeMonitor.kt` | `android/android_library/src/main/java/android/library/clipboard/presentation/ClipboardChangeMonitor.kt` |
| `ClipboardChangeMonitorTest.kt` | `android/unity_android_plugin/src/androidTest/java/android/unity/clipboard/ClipboardChangeMonitorTest.kt` | `android/android_library/src/androidTest/java/android/library/clipboard/presentation/ClipboardChangeMonitorTest.kt` |

### 2.2 レイヤー説明の訂正

- v1〜v3: 「T10: `ClipboardChangeMonitor`（**Manager 層**、`unity_android_plugin` 配下）が system `OnPrimaryClipChangedListener` を単独所有」
- 訂正後: `ClipboardChangeMonitor` は **`android_library` の Presentation 層**が system `OnPrimaryClipChangedListener` を単独所有する。`unity_android_plugin` の `UnityAndroidClipboardManager` は listener を持たず、`ClipboardChangeMonitor.start(context, onChange)` / `stop()` を呼び出すだけの薄い委譲になっている

### 2.3 変更なし（訂正不要）

以下は v1〜v3 の記載どおりで、実コードと一致することを確認済み:

- `ClipboardRepository` / `ClipboardUseCases` の Port・API シグネチャ（copy/read/hasClip/getDescription/clear）
- `ClipboardDomainError` の全5ケース（`EmptyContent` / `EmptyItemList` / `InvalidUri` / `ClipboardUnavailable` / `ReadNotAllowed`）
- `UnityAndroidClipboardManager` の公開メソッド一覧（copyPlainText/copyHtmlText/copyUri/copyMultipleText/read/hasClip/getDescription/clear/startObserving/stopObserving/各種listener登録）
- エラーコード/メッセージ対応表
- テスト件数（コアUseCase 22件、JSON Parser 12件、ほか）

---

## 3. ビルド・テスト結果（再確認）

`android_library` / `unity_android_plugin` 双方のコンパイル・単体テスト・Lint・AAR生成が、移設後の配置で成功していることをこのセッション内で確認済み（詳細は本機能の実装過程のコミット `73de0358` を参照）。

---

## 4. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 実行する（write-manual workflow のソースファイルとして採用）
