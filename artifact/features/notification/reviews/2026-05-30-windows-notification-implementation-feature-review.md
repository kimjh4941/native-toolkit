# 実装レビュー結果

## 基本情報

- 日付: 2026-05-30
- ブランチ: feature/NTKIT-9（未コミット差分 + 未追跡ファイルを対象）
- 設計書: artifact/designs/notification/2026-05-30-windows-notification-implementation-v2.md
- 実装結果ファイル: artifact/results/notification/2026-05-30-windows-notification-implement-feature-result-v1.md
- OS: Windows

---

## レビュー概要

Windows App SDK (`AppNotificationManager`) を使用した Toast 通知機能を `WindowsLibrary` MFC DLL に追加する実装。`WindowsNotificationManager` クラス（シングルトン）・C Bridge API 12 関数・CppUnitTestFramework テストプロジェクト一式を新規作成し、既存の `pch.h`・`vcxproj`・`def`・`sln` を変更。

---

## 重大な問題（high）

### H-1: `Schedule()` の `notification.Payload()` — 型不一致によるコンパイルエラーの可能性

- ファイル: `windows/WindowsLibrary/WindowsNotificationManager.cpp`
- 対象:
  ```cpp
  auto notification = builder.BuildNotification();
  XmlDocument doc;
  doc.LoadXml(notification.Payload());
  ```
- 問題: Windows App SDK の `AppNotification.Payload` が `XmlDocument` を返す場合、`LoadXml(hstring)` に `XmlDocument` を渡すことになりコンパイルエラー。
- 修正案:
  ```cpp
  auto notification = builder.BuildNotification();
  auto doc = notification.Payload();  // XmlDocument をそのまま受け取る
  ScheduledToastNotification scheduled{ doc, scheduledTime };
  ```
  または `Payload()` が `hstring` を返すなら現状のままで良い。ビルド時に確認が必須。

### H-2: テストの `PropertySet` → `IMap<hstring, hstring>` キャストが実行時例外を投げる

- ファイル: `windows/WindowsLibraryTest/NotificationManagerTest.cpp`
- 対象:
  ```cpp
  winrt::Windows::Foundation::Collections::PropertySet args;
  args.Insert(L"key", winrt::box_value(winrt::hstring{ L"val\"ue" }));
  args.as<IMap<winrt::hstring, winrt::hstring>>()
  ```
- 問題: `PropertySet` は `IMap<hstring, IInspectable>` であり、`IMap<hstring, hstring>` へのキャストは `winrt::hresult_no_interface` を投げる。
- 修正:
  ```cpp
  winrt::Windows::Foundation::Collections::StringMap args;
  args.Insert(L"key", L"val\"ue");
  auto json = mgr.ArgsToJson(args, emptyMap);
  ```

---

## 改善提案（medium）

### M-1: AppNotificationBuilder の API 存在確認が必要

- `windows/WindowsLibrary/WindowsNotificationManager.cpp`
  - `builder.SetAudioUri(Uri{...}, looping)` — `AppNotificationAudioLooping` 引数付きオーバーロード
  - `builder.AddInlineImage(Uri{...})` — メソッドの存在確認
- ビルドが通れば問題なし。コンパイルエラーが出た場合は XML 直接操作への代替が必要。

### M-2: 未パッケージアプリの `Register(clsid, uri)` — API シグネチャ要確認

- `windows/WindowsLibrary/WindowsNotificationManager.cpp` Init() 内
- Windows App SDK 1.3+ では `Register(AppNotificationActivationInfo)` に変更されている可能性あり。ビルド時に確認し、コメントを追加すること。

### M-3: テスト間のシングルトン状態汚染リスク

- `windows/WindowsLibraryTest/NotificationManagerTest.cpp`
- テスト失敗時（例外発生時）に `m_initialized = false` が実行されず後続テストの前提が崩れる。
- 修正案: RAII ガードまたは `TEST_METHOD_CLEANUP` を使用する。
  ```cpp
  struct InitGuard {
      ~InitGuard() { WindowsNotificationManager::GetInstance().m_initialized = false; }
  } guard;
  ```

### M-4: `winrt::init_apartment()` のアパートメント型が暗黙的

- `windows/WindowsLibrary/WindowsLibrary.cpp`
- デフォルトは MTA。Unity から STA スレッドで呼び出す場合の注意をコメントに明記を推奨。

---

## 軽微な指摘（low）

### L-1: `CancelScheduled()` で tag・group 両方が空の場合に全スケジュール通知が削除される

- `windows/WindowsLibrary/WindowsNotificationManager.cpp` CancelScheduled()
- 意図した挙動か不明。コメントで明記するか早期リターンで防御することを検討。

### L-2: `using namespace winrt;` が広すぎる

- `windows/WindowsLibrary/WindowsNotificationManager.cpp`
- .cpp ファイルなので実害は少ないが、個別名前空間の指定を推奨。

### L-3: Win32 構成に AppSDK NuGet が含まれる

- `windows/WindowsLibrary/WindowsLibrary.vcxproj`
- AppSDK は x64 のみ対応。Condition で x64 に限定を推奨:
  ```xml
  <PackageReference Include="Microsoft.Windows.AppSDK" Condition="'$(Platform)'=='x64'">
    <Version>1.4.*</Version>
  </PackageReference>
  ```

---

## 設計書整合性チェック

| 項目 | 評価 | 備考 |
|-----|------|------|
| 企画書との整合性 | ○ | In Scope 全項目が実装されている |
| Clean Architecture 準拠 | ○ | Manager + Bridge のフラット構造（設計書記載の変形パターン）に準拠 |
| 既存実装との差分分析の正確性 | ○ | 設計書記載の変更対象ファイルと実際の差分が一致 |
| テスト設計の網羅性 | △ | 自動化対象 4 観点は実装済み。H-2 の PropertySet 問題でテストが実行時失敗 |
| ドメインエラー全ケース実装 | ○ | エラーコード 0〜7 すべて実装済み |
| エラーコード/メッセージ対応表との整合 | ○ | 各 DFLog メッセージが設計書のログ例と整合 |

---

## プロジェクトルール適合チェック

| 項目 | 評価 | 備考 |
|-----|------|------|
| common.md 準拠 | ○ | Bridge は薄く保つ・JSON 文字列渡し・Manager がコールバック所有 |
| windows.md 準拠 | ○ | 全メソッド先頭に DFLog/DLog・Doxygen コメント付与・英語コメント・wchar_t* 使用 |
| エラー契約反映 | ○ | 成功時 pError=0・失敗時 1〜7 の対応表が実装と一致 |
| 既存 API 互換性 | ○ | DialogManager API は無変更。破壊的変更なし |

---

## テストカバレッジ

カバーできている観点:
- `setBadge` の値バリデーション（-7, -100）
- 未初期化状態での Show / Schedule / UpdateProgress
- `ArgsToJson` の特殊文字エスケープ・UserInput マージ（H-2 修正後）
- `BuildFromJson` のボタン数超過・音声ループ制約・invokeUri 排他
- JSON パース失敗

不足している観点:
- `NOTIFICATION_ERROR_BADGE_FAILED`（T-29）のテストがない
- `CancelScheduled()` の tag/group 空文字列挙動テストがない
- T-01〜T-29 統合テスト（全件手動確認 — 設計書で許容済み）

---

## 総合評価

**要修正（重大）**

H-1（`notification.Payload()` 型問題）と H-2（PropertySet キャスト問題）の 2 件が修正必須。H-1 はビルドエラーの可能性があり、H-2 はテストが実行時例外で失敗する。その他の指摘は実装品質の問題であり、T-01〜T-29 手動確認の前提として H-1・H-2 を先に修正することを推奨。
