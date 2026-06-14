# 実装結果レポート

## 基本情報

- 日付: 2026-05-30
- 機能名: notification
- 対象OS: Windows
- 設計書: artifact/designs/notification/2026-05-30-windows-notification-implementation-v2.md
- ブランチ: feature/NTKIT-9

## 1. 実装サマリー

### 1.1 設計書由来の実装

- Task 1: vcxproj 全構成に `/std:c++17`・`/await`・`/EHsc` を追加
- Task 1: `Microsoft.Windows.AppSDK 1.4.*` PackageReference を vcxproj に追加
- Task 1: pch.h に WinRT ヘッダを MFC 後の順序で追加（framework.h → winrt/base.h → AppNotifications → JSON）
- Task 1: `InitInstance()` に `winrt::init_apartment()` を追加
- Task 1: `WindowsLibrary.def` に全 12 Bridge 関数を追加
- Task 1: `WindowsLibraryTest.vcxproj`（Native Unit Test Project）を新規作成し `WindowsLibrary.sln` に追加
- Task 2: `WindowsNotificationManager.h` — エラー定数・コールバック型・全 Bridge 関数宣言
- Task 2: `WindowsNotificationManagerInternal.h` — 内部クラス宣言（friend class 付き）
- Task 2: Init / Uninit / Show / OnNotificationInvoked / ArgsToJson / BuildFromJson + サブビルダー実装
- Task 2: バリデーション（ボタン数超過・音声ループ制約・invokeUri 排他）実装
- Task 3: Schedule / CancelScheduled / UpdateProgress / SetBadge / RemoveById / RemoveByTag / RemoveAll / GetAll 実装
- Task 4: GetSetting 実装・未パッケージ初期化分岐実装（COM 登録は Task 4 動作確認が必要）

### 1.2 実装時の追加判断

- `WindowsNotificationManagerInternal.h` を新規追加（設計書には記載なし）
  - 理由: テストプロジェクトが内部クラスを直接テストするために必要。設計書の「内部クラス・関数を直接テスト」要件を満たすため
- テストで `m_initialized` に直接アクセスするため `friend class NotificationManagerTest` を追加
  - 理由: `BuildFromJson` バリデーション検証が `m_initialized` チェックの後段に存在するため
- 管理者権限チェックを `Init()` 内で実装
  - 理由: 設計書の「管理者権限実行でのサイレント失敗」リスク対応として早期警告が有効

## 2. 変更ファイル

### 2.1 新規作成

- windows/WindowsLibrary/WindowsNotificationManager.h
- windows/WindowsLibrary/WindowsNotificationManagerInternal.h
- windows/WindowsLibrary/WindowsNotificationManager.cpp
- windows/WindowsLibraryTest/WindowsLibraryTest.vcxproj
- windows/WindowsLibraryTest/pch.h
- windows/WindowsLibraryTest/pch.cpp
- windows/WindowsLibraryTest/NotificationManagerTest.cpp

### 2.2 既存変更

- windows/WindowsLibrary/pch.h — WinRT ヘッダ追加
- windows/WindowsLibrary/WindowsLibrary.cpp — winrt::init_apartment() 追加
- windows/WindowsLibrary/WindowsLibrary.def — Bridge 関数 12 個追加
- windows/WindowsLibrary/WindowsLibrary.vcxproj — C++17/await/EHsc/NuGet/新規ファイル追加
- windows/WindowsLibrary/WindowsLibrary.sln — WindowsLibraryTest プロジェクト追加

### 2.3 非変更（設計上対象だが未変更）

- windows/WindowsLibrary/WindowsLibrary.vcxproj.filters: 未更新。VS で開いた際に自動更新されるため手動更新は省略

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

| エラー定数 | 値 | 実装 |
|-----------|---|------|
| `NOTIFICATION_SUCCESS` | 0 | 全 Bridge 関数の pError 初期値 |
| `NOTIFICATION_ERROR_NOT_INITIALIZED` | 1 | `CheckInitialized()` で統一返却 |
| `NOTIFICATION_ERROR_DISABLED` | 2 | Show / Schedule で Setting() チェック後に返却 |
| `NOTIFICATION_ERROR_INVALID_PAYLOAD` | 3 | JsonObject::TryParse 失敗時に返却 |
| `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` | 4 | UpdateAsync 結果が Succeeded 以外の場合に返却 |
| `NOTIFICATION_ERROR_HRESULT_FAILURE` | 5 | 全 WinRT try/catch で返却 |
| `NOTIFICATION_ERROR_BADGE_FAILED` | 6 | SetBadge の WinRT 例外で返却 |
| `NOTIFICATION_ERROR_INVALID_PARAMETER` | 7 | バリデーション失敗（ボタン数超過・音声ループ・invokeUri 排他・badge value < -6・unpackaged 引数 null）で返却 |

### 3.2 errorCode 対応反映

設計書の統一 API 返却仕様表に完全に対応。各関数の pError に設計書通りのエラーコード範囲のみを返す。

### 3.3 success 時契約

- 成功時は `pError = 0`（`NOTIFICATION_SUCCESS`）を設定して返す
- `getNotificationSetting()` は pError を持たず、返却値 0〜4 がエラーコード体系と独立している

## 4. ビルド結果

- 実行コマンド: MSBuild `WindowsLibrary.vcxproj` / `WindowsLibraryTest.vcxproj`（Debug|x64 / Release|x64）
- 結果: 成功（DLL 生成確認済み）
  - WindowsLibrary Debug|x64 → `WindowsLibrary-Debug.dll` 生成
  - WindowsLibrary Release|x64 → `WindowsLibrary.dll` 生成
  - WindowsLibraryTest Debug|x64 / Release|x64 → `WindowsLibraryTest.dll` 生成
- 補足:
  - NuGet パッケージは `Microsoft.WindowsAppSDK 2.1.3`（packages.config 方式）を使用
  - AppSDK 2.x は C++/WinRT 射影ヘッダ（`winrt/Microsoft.Windows.*.h`）を同梱せず、ビルド時に cppwinrt で生成する。MFC + packages.config プロジェクトでは NuGet 統合の参照解決（RAR）が動かず自動生成されないため、Windows SDK 同梱の `cppwinrt.exe`（v2.0.250303.1）で生成する独自ターゲット `GenerateWindowsAppSDKProjection` を vcxproj に追加した。SDK 同梱 `winrt/base.h` とバージョンが一致するため `check_version` の static_assert を満たす
  - `<RegisterOutput>true</RegisterOutput>`（既存 MFC プロジェクト設定。型ライブラリの COM 自己登録）は管理者権限を要求する。Visual Studio はユーザーごとのリダイレクトで通常成功。非管理者の MSBuild CLI ではこのポストステップのみ MSB8011 となるが、コンパイル・リンク（DLL 生成）は成功している
  - Win32 構成は AppSDK 非対応のため対象外（x64 のみ）

## 5. テスト結果

- 実行したテスト: `vstest.console.exe WindowsLibraryTest.dll /Platform:x64`
- 結果サマリー: 成功 11 / 失敗 0（全 11 ケース合格）

### 5.1 テスト詳細（自動化対象）

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
|-----------|-------------|------------|------|------|
| setBadge 値バリデーション | NotificationManagerTest.cpp | Test_SetBadge_ValueMinus7_ReturnsInvalidParameter | ○ 合格 | |
| setBadge 値バリデーション | NotificationManagerTest.cpp | Test_SetBadge_ValueMinus100_ReturnsInvalidParameter | ○ 合格 | |
| 未初期化チェック | NotificationManagerTest.cpp | Test_ShowNotification_WhenNotInitialized_ReturnsNotInitialized | ○ 合格 | |
| 未初期化チェック | NotificationManagerTest.cpp | Test_Schedule_WhenNotInitialized_ReturnsNotInitialized | ○ 合格 | |
| 未初期化チェック | NotificationManagerTest.cpp | Test_UpdateProgress_WhenNotInitialized_ReturnsNotInitialized | ○ 合格 | |
| ArgsToJson エスケープ | NotificationManagerTest.cpp | Test_ArgsToJson_EscapesDoubleQuotes | ○ 合格 | StringMap 使用 |
| ArgsToJson マージ | NotificationManagerTest.cpp | Test_ArgsToJson_MergesUserInput | ○ 合格 | StringMap 使用 |
| ボタン数バリデーション | NotificationManagerTest.cpp | Test_BuildFromJson_TooManyButtons_ReturnsInvalidParameter | ○ 合格 | ValidatePayload で事前検証 |
| 音声ループ制約 | NotificationManagerTest.cpp | Test_BuildFromJson_AudioLoopWithoutLongDuration_ReturnsInvalidParameter | ○ 合格 | ValidatePayload で事前検証 |
| invokeUri 排他 | NotificationManagerTest.cpp | Test_BuildFromJson_ButtonWithArgsAndInvokeUri_ReturnsInvalidParameter | ○ 合格 | ValidatePayload で事前検証 |
| JSON パース失敗 | NotificationManagerTest.cpp | Test_BuildFromJson_InvalidJson_CannotParse | ○ 合格 | |

### 5.2 未実施ケース詳細（統合テスト — 手動確認必要）

| テスト観点 | テストケース | 未実施理由 |
|-----------|------------|----------|
| T-01〜T-29 全統合テスト | 通知表示・コールバック・スケジュール等 | AppNotificationManager のモックが困難 / OS 実機依存 |
| T-17 管理者権限サイレント失敗 | 管理者で起動 → Show() | 実行環境依存 |
| T-18 未パッケージ COM 登録 | isPackaged=FALSE で Init | COM 登録の環境依存（要検証） |
| T-28 WinRT 例外 | CLSID 不正など | HRESULT 再現が環境依存 |

## 6. Definition of Done

- △ `initNotificationManager()` の Init/Uninit が正常に動作する（要ビルド・実機確認）
- △ `showNotification()` でテキスト/画像/ボタン/コンボボックス/テキスト入力/進捗バーの Toast が表示できる（要実機確認）
- △ `showNotification()` の有効期限（expiration / expiresOnReboot）が機能する（要実機確認）
- △ `scheduleNotification()` で指定時刻の通知が届く（要実機確認）
- △ `cancelScheduledNotification()` でスケジュール通知がキャンセルされる（要実機確認）
- △ Reminder/Alarm シナリオでボタン方式のスヌーズが動作する（要実機確認）
- △ `updateNotificationProgress()` で通知の進捗値が更新される（要実機確認）
- △ `setBadge()` でバッジが数値・グリフ・クリアで動作する（要実機確認）
- △ `removeNotificationsByTag()` / `removeAllNotifications()` が動作する（要実機確認）
- △ `getAllNotifications()` が通知一覧を outJson に返す（要実機確認）
- △ `getNotificationSetting()` が値を返す（要実機確認）
- △ `NotificationInvokedCallback` が argsJson で呼び出される（要実機確認）
- △ argsJson にテキスト入力（reply）・コンボボックス選択値が含まれる（要実機確認）
- △ 未パッケージアプリでの初期化（要 COM 登録環境確認）
- ○ 管理者権限実行時のログ警告（Init 内で実装済み）
- ○ pError に適切なエラーコードが返される（全エラーケース 1〜7 実装済み）
- ○ 全メソッドに DFLog/DLog が付与されている
- ○ 公開 API に Doxygen コメントが付与されている
- ○ ビルドが Debug|x64 / Release|x64 の両構成で成功する（MSBuild で確認済み）
- ○ 自動化単体テスト 11 ケースが全て合格する（vstest.console.exe で確認済み）
- ○ `WindowsLibrary.def` に全 export 関数が記載されている

## 7. 設計差分

- 差分有無: あり（追加判断 + ビルド成立のための実 API 対応）
- 差分内容:
  - `WindowsNotificationManagerInternal.h` を追加（内部クラス宣言の分離）
  - テスト用 `friend class NotificationManagerTest` を内部クラスに追加
  - 管理者権限チェックを `Init()` 内で実装（設計書にはログ出力要件のみ記載）
  - **実 AppSDK 2.1.3 API への対応**（設計書が想定した API 名と実際の差異を修正）:
    - `builder.SetExpirationTime()/SetExpiresOnReboot()` は存在しない → `AppNotification` オブジェクト側の `Expiration()/ExpiresOnReboot()` に変更
    - `AppNotificationTextInputBox` クラスは存在しない → `builder.AddTextBox(id[, placeholder, title])` を使用
    - `builder.AddInlineImage()` → `builder.SetInlineImage()`
    - `AppNotificationAudioLooping::DoNotLoop` → `::None`
    - `AppNotificationSoundEvent::LoopingAlarm/LoopingCall` は存在しない → `Alarm/Call`（ループ可否は looping で制御）
  - **`ValidatePayload()` を新規抽出**: ボタン数・音声ループ・invokeUri 排他の検証をビルダ構築前の純 JSON チェックに分離。AppSDK ランタイム未登録でも検証パスを単体テスト可能にした
  - **`using namespace winrt::Windows::Foundation;` を個別 using に縮小**（レビュー L-2）: 当該広域 using が `winrt::Windows::Foundation::IUnknown` をグローバルに持ち込み、MFC のシェルヘッダ（shobjidl）の `::IUnknown` と衝突するため、`Uri`/`IAsyncOperation` のみの using-宣言に変更
  - **`InitInstance()` の `winrt::init_apartment()` を非スローの `CoInitializeEx` に置換**（レビュー M-4）: WinUI ホスト（`WindowsLibraryExample`）等が既に STA で COM 初期化済みのプロセスに DLL がロードされると `winrt::init_apartment()` が `RPC_E_CHANGED_MODE`（0x80010106）を送出する。try/catch では捕捉できてもデバッガに first-chance 例外として記録され続けるため、そもそもスローしない `CoInitializeEx(nullptr, COINIT_MULTITHREADED)` を用い、ホストが確立したアパートメントをそのまま使う（WinRT 通知 API の利用には十分）
  - **ビルド基盤**:
    - `Microsoft.WindowsAppSDK 2.1.3`（packages.config）を導入
    - AppSDK 2.x の C++/WinRT 射影ヘッダを Windows SDK 同梱 `cppwinrt.exe`（v2.0.250303.1）で生成する独自 MSBuild ターゲット `GenerateWindowsAppSDKProjection` を両 vcxproj に追加（NuGet 統合の射影が MFC/packages.config 環境で機能しないため）
    - vcxproj に C++/WinRT 関連設定を追加（`CppWinRTModernIDL=false`、`CppWinRTEnable*Projection=false`、SDK cppwinrt インクルードパス、`/await` 撤去 ＝ cppwinrt の `/await:strict` と重複回避）
    - **`CppWinRTGenerateWindowsMetadata=false` を WindowsLibrary に設定**: CppWinRT パッケージ導入により、`.idl` を持つ WindowsLibrary が「winmd を生成する WinRT コンポーネント」として宣言され、これを ProjectReference する `WindowsLibraryExample`（WinUI アプリ）の MIDL が存在しない `WindowsLibrary.winmd` を import しようとして失敗していた。WindowsLibrary.idl はクラシック COM タイプライブラリ（.tlb）であり winmd 非生成のため明示的に無効化。これにより WindowsLibraryExample.exe のビルドが復旧（`WindowsLibraryExample` プロジェクト自体は無変更）
    - テストプロジェクト `WindowsLibraryTest` は内部クラス検証のため実装 `.cpp`（`WindowsNotificationManager.cpp`/`common.cpp`）を直接コンパイルし、MFC 有効化・`WINDOWSLIBRARY_EXPORTS` 定義・`windowsapp.lib` リンク・import lib 二重リンク回避（`LinkLibraryDependencies=false`）を設定
    - `winrt::init_apartment()` を `TEST_CLASS_INITIALIZE` で try/catch（VSTest ホストが既に別アパートメントで COM 初期化済みの場合の `RPC_E_CHANGED_MODE` を許容）
  - `.gitignore` に Visual Studio / NuGet / cppwinrt 生成物の除外を追加
- レビュー指摘の対応:
  - H-1（`notification.Payload()` 型）: 実 API では `hstring` を返すため設計どおり `XmlDocument::LoadXml()` が正。レビューの懸念は不成立として元実装を維持
  - H-2（PropertySet → StringMap）: 修正済み
  - M-3（テストのシングルトン状態汚染）: RAII ガードを追加
  - L-2（広域 using）: 上記のとおり縮小
  - L-3（Win32 への AppSDK NuGet 混入）: x64 限定化（packages.config 方式により実質 x64 のみ対象）
- 影響範囲:
  - DialogManager 等の既存 API は無変更。Notification 機能の追加とビルド構成の変更に限定

## 8. ステップ10 実行確認

- 提示文: 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答: 実行する
