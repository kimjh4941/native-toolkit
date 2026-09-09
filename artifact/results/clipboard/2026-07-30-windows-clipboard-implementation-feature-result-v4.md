# 実装結果レポート v4（レビュー v3 対応）

## 基本情報

- 日付: 2026-07-30
- 機能名: Windows Clipboard Manager
- 対象OS: Windows
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- ブランチ: `feature/NTKIT-13`
- 対応レビュー: `artifact/reviews/clipboard/2026-07-30-windows-clipboard-implementation-feature-review-v3.md`

## 1. 実装サマリー

### 1.1 レビュー指摘由来の実装

- H1: WinRT の履歴設定変更イベントは event thread で Clipboard API を呼ばず、event id と watch generation だけを owner UI thread へ送るよう変更した。値は UI thread で `QueryHistoryEnabled` / `QueryRoamingEnabled` を呼んで解決する
- H2/M4: pending event table に immutable callback snapshot を保持し、stop 成功時に generation を無効化する。stop → re-register 後の旧メッセージは no-op になる
- H3: `ReserveDeferredFormats` / `RecoverDeferredState` が Core の mutation flag を受け取り、成功可否ではなく実 mutation に基づいて自己書き込みを記録する
- H4: 二相 provider の fill 実サイズは query サイズとの完全一致を必須にした。小さい場合の未初期化 HGLOBAL 末尾公開と、大きい場合のバッファ超過を拒否する
- H5: `ClipboardWatcher::SelfWriteTransaction` を追加し、書き込み開始から sequence 登録までと `WM_CLIPBOARDUPDATE` 判定を同じ mutex で直列化した
- H6: owner-thread 限定 API は `AcquireOwnerContext` で initialized / ownerThreadId / lifecycle lease / HWND / coordinator snapshot を `initMutex_` 配下で一括取得する
- M1: `copyMultipleFormats` の標準 format/payload 対応を明示した。`CF_UNICODETEXT` / `CF_TEXT` は text、`HTML Format` は html、DIB/HDROP は base64、custom は base64 のみ。`CF_BITMAP` は HBITMAP 所有経路がないため拒否する
- M2: `ReserveDeferredFormats` の JSON parse で `std::bad_alloc` を再送出し、Bridge 外周で `OUT_OF_MEMORY` に変換する
- M3: Manager の lifecycle を未初期化時は closed にし、全 fallible setup 成功後だけ `Reopen()` する
- M5: 設計書の文字コード方針を、Clipboard source は ASCII-only、非 ASCII が必要な個別 file のみ UTF-8 BOM または file 単位 `/utf-8`、project-wide 適用は別 task、へ更新した
- M6: DIB の正の width、RLE4/8 と bit depth、top-down 禁止、`biSizeImage` 範囲、end-of-bitmap、BITFIELDS の bit depth を検証する

### 1.2 実装時の追加判断

- provider adapter を `WindowsClipboardDeferredProvider.{h,cpp}` に分離し、WinRT/Manager をリンクしない MSTest から二相サイズ契約を直接検証できるようにした
- format/payload 対応判定を `ClipboardFormats::IsMultiFormatPayloadAllowed` へ抽出し、全組合せの代表ケースを純ロジックテストにした
- `CF_TEXT` の text payload は UTF-16LE バイト列ではなく `CP_ACP` の NUL 終端データへ変換する

## 2. 変更ファイル

### 2.1 新規作成

- `windows/WindowsLibrary/WindowsClipboardDeferredProvider.h`
- `windows/WindowsLibrary/WindowsClipboardDeferredProvider.cpp`
- `windows/WindowsLibraryTest/ClipboardDeferredProviderTest.cpp`
- `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`

### 2.2 既存変更

- `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- `windows/WindowsLibrary/WindowsClipboardCore.h`
- `windows/WindowsLibrary/WindowsClipboardCore.cpp`
- `windows/WindowsLibrary/WindowsClipboardFormats.h`
- `windows/WindowsLibrary/WindowsClipboardFormats.cpp`
- `windows/WindowsLibrary/WindowsClipboardHistoryBackend.h`
- `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.h`
- `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp`
- `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp`
- `windows/WindowsLibrary/WindowsClipboardManagerInternal.h`
- `windows/WindowsLibrary/WindowsClipboardManager.cpp`
- `windows/WindowsLibrary/WindowsLibrary.vcxproj`
- `windows/WindowsLibraryTest/ClipboardCoreTest.cpp`
- `windows/WindowsLibraryTest/ClipboardFormatsTest.cpp`
- `windows/WindowsLibraryTest/ClipboardHistoryCoordinatorTest.cpp`
- `windows/WindowsLibraryTest/WindowsLibraryTest.vcxproj`

### 2.3 非変更

- `windows/UnityWindowsPlugin`: 既存構成を含め変更していない
- `windows/WindowsLibrary/WindowsLibrary.rc`: 成果物生成で 1.1.0 を再スタンプしたが、実行前後の Git 差分はない

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- 既存の `CLIPBOARD_ERROR_*` 一覧は変更なし
- provider/query/WinRT 例外の既存分類を維持した
- `ReserveDeferredFormats` の allocation failure は `CLIPBOARD_ERROR_OUT_OF_MEMORY` へ到達する
- format/payload 不一致と `CF_BITMAP` は `CLIPBOARD_ERROR_INVALID_PARAMETER`
- DIB 構造不正は `CLIPBOARD_ERROR_INVALID_DATA`

### 3.2 errorCode / errorMessage 対応反映

- 同期 Bridge は `DWORD* pError` で返す既存契約を維持
- 履歴 request callback の error/json 契約は変更なし
- 履歴 flag event は値 query に失敗した場合、誤った bool を公開せずログして配送を中止する

### 3.3 success時契約

- 同期 API 成功時の `pError == CLIPBOARD_ERROR_NONE` を維持
- request callback 成功時の error 0 / JSON payload 契約を既存テストで確認

## 4. ビルド結果

- 実行コマンド:
  - `MSBuild.exe windows\WindowsLibraryTest\WindowsLibraryTest.vcxproj /t:Rebuild /p:Configuration=Debug /p:Platform=x64 /m`
  - `MSBuild.exe windows\WindowsLibrary\WindowsLibrary.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /m`
  - `powershell -File scripts\build_windows_library_dll.ps1 -c release -m WindowsLibrary -v 1.1.0 -o "$env:TEMP\windows-native-toolkit-clipboard-review-v3-fix.dll"`
- 結果: SUCCESS
- 成果物:
  - `%TEMP%\windows-native-toolkit-clipboard-review-v3-fix.dll`
  - `%TEMP%\windows-native-toolkit-clipboard-review-v3-fix.lib`
- 既存警告:
  - `MSB3106`（Windows App SDK の既存参照）
  - `C4190`（`common.h` の既存 C linkage）
  - Notification/ClassicActivator 等の既存 `C4819`
- Clipboard 新規ソースの C4819/C4828: なし

## 5. テスト結果

- 実行コマンド:
  - `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`
- 結果:
  - 実行件数: 106
  - 成功: 106
  - 失敗: 0

### 5.1 追加した主なテスト

| テスト観点 | 結果 |
|---|---|
| history event の UI 配送後 query | ○ |
| callback 置換時の immutable snapshot | ○ |
| stop → re-register 後の旧 generation 破棄 | ○ |
| deferred reserve/recover の mutation flag | ○ |
| provider actual size `<` / `==` / `>` query size | ○ |
| worker self-write と UI update の競合 | ○ |
| format/payload 対応と CF_BITMAP 拒否 | ○ |
| DIB width / RLE bit depth / truncation / terminator | ○ |

### 5.2 未実施ケース

| テスト観点 | 未実施理由 |
|---|---|
| `AcquireOwnerContext` と実 Manager の concurrent Uninit | Manager/Window/実 WinRT を MSTest DLL に直接リンクしない現行構成のため。ロック境界はコードレビューと Release build で確認 |
| `std::bad_alloc` の Bridge error 値 | WinRT JSON allocator の失敗注入 seam がないため。catch 順序をコードレビューで確認 |
| Windows 11 実機での WinRT event thread / foreground | 実 STA、foreground、OS clipboard history が必要 |
| MSIX / 未パッケージ、他 application 相互運用 | 実機手動確認が必要 |

## 6. Definition of Done

- ○ レビュー v3 の High 6件をコードへ反映
- ○ Medium M1〜M6をコードまたは設計書へ反映
- ○ Debug x64 test build / Release x64 library build 成功
- ○ 自動テスト 106/106 passed
- ○ 配布 DLL/lib 生成スクリプト成功
- △ Windows 11 実機・MSIX・他 application 相互運用は未確認

## 7. 設計差分

- 差分有無: あり（設計書へ反映済み）
- 差分:
  - 履歴 flag event は変更通知だけを post し、UI thread で値を query する
  - history event message は event id + watch generation を持ち、pending table が immutable callback snapshot を保持する
  - source encoding は project-wide `/utf-8` ではなく Clipboard source の ASCII-only を既定にする
  - provider adapter を独立ファイルへ抽出する

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま終了
- ユーザー回答:
  - 未回答
