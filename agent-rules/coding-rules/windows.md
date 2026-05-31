# Windows コーディングルール

## 適用対象

このルールは以下に適用する。

- VC++ 実装（`windows/WindowsLibrary/` 配下）
- Bridge 層 C API（`.h` / `.cpp`）

---

## アーキテクチャ（VC++ 版 Clean Architecture）

`common.md` の Clean Architecture は Swift（iOS/macOS）イディオム前提で書かれている。Windows（VC++ / MFC + `extern "C"` C Bridge）では、その原則を以下のように対応づけて適用する。

### 基本構造（既定）

既定は **Manager + C Bridge のフラット構造**とする（既存 `WindowsDialogManager` パターンに合わせる）。

```
Unity C# (P/Invoke)
    │
    ▼
extern "C" C Bridge API   ← 薄いファサード（ロジックを持たない）
    │
    ▼
XxxManager (singleton)    ← 公開 API・システム Delegate 所有・ロジック集約
    │
    ▼
Windows / WinRT API
```

UseCase / Repository を**最初から作らない**。後述のトリガーが出た箇所にのみ層を足す。

### 層の VC++ 対応

| common.md の層 | VC++ での実現 |
|---|---|
| Domain（モデル・エラー型） | エラー定数（`XXX_ERROR_*`）・純粋 struct。WinRT / MFC 型を持ち込まない |
| Application（Port） | **抽象基底クラス**（純粋仮想関数のインターフェース） |
| Application（UseCase） | 1 操作 1 クラス。ただし**非自明なロジックを持つ操作のみ**作る |
| Data（Repository） | **WinRT 呼び出しを隔離する実装クラス**。ABI/Domain 型 ↔ WinRT 型の変換を集約 |
| Manager | 公開 API・システム Delegate（コールバック）所有・（あれば）UseCase 集約 |
| Bridge | `extern "C"` C API。Manager 呼び出し専用（薄く保つ） |

### 段階適用のトリガー（ROI 順）

層は「機能数」ではなく「次の痛み」が出た箇所に足す。

1. **純ロジックの抽出（必須・常時）** — バリデーション・JSON マッピング・ドメイン規則は **WinRT 非依存の関数/クラス**に切り出し、単体テストを書く。（例: `WindowsNotificationManager::ValidatePayload`）
2. **Manager の機能単位ファイル分割** — `Manager.cpp` が肥大化したら機能ごとに分割する。
3. **Repository 境界（抽象基底クラス）の導入** — 「Manager のロジックを WinRT 抜きでテストしたい」または「実装を差し替えたい」場合のみ。
4. **UseCase の導入** — その操作が非自明なロジック（状態機械・調整・リトライ等）を持つ場合のみ。**素通し（pass-through）の操作には作らない。**

### 原則（フラット／層化を問わず共通）

- **C Bridge は薄く保つ**（ビジネスロジックを持たず Manager に委譲。複雑なデータは JSON 文字列で渡す）。
- システム Delegate / コールバック（例: `NotificationInvoked`）は **Manager の 1 クラスのみが所有**する。
- WinRT / MFC 固有型を Domain 相当（エラー型・純粋モデル）に持ち込まない。
- WinRT 例外・`HRESULT` は Domain エラー定数へ正規化してから Bridge の out 引数（`DWORD* pError` 等）で返す。
- 純ロジックは WinRT ランタイム未登録でもテストできる形に保つ（活性化が必要な型の生成より前に検証を済ませる）。

---

## ログ（DLog / DFLog / DFLLog）

全メソッドの先頭1行目に、全パラメータを含むログを必ず入れる。

- 通常ログ: `DLog`
- フォーマットログ: `DFLog`
- 大きいバッファ指定ログ: `DFLLog`

### VC++ フォーマット

```cpp
static const wchar_t* TAG = L"FullClassName";

void Sample(const wchar_t* param1, int param2)
{
    DFLog(TAG, L"[Sample] param1: %ls, param2: %d", param1 ? param1 : L"null", param2);
    // existing logic...
}
```

### エラーログ例

```cpp
DFLog(TAG, L"[ShowDialog] failed. hr=0x%08lx", hr);
```

### 対象

- `extern "C"` の公開関数（Bridge C API 含む）
- クラスの公開メソッド
- クラスの内部メソッド（通知機能コード内のローカル関数を含む）

### 除外

- data model / enum / struct / class 宣言
- ヘッダの前方宣言
- 純粋 UI ユーティリティ
- 既にログがある箇所（重複追加しない）

---

## コメント（Doxygen / HeaderDoc）

公開ヘッダと公開 API には Doxygen/HeaderDoc 形式のコメントを付ける。

**対象（必須）:**

- `.h` の公開関数宣言
- `extern "C"` 公開 API
- 非自明な公開定数
- 公開クラスのメソッド（必要に応じて `@brief`, `@param`, `@return`）

**推奨:**

- 実装ファイルの公開 API 実装にも要約コメントを付ける
- `@copydetails` を使い、ヘッダコメントと重複を減らす

**除外:**

- `static` な内部ヘルパー関数
- 自明な getter / setter 相当の軽量処理

---

## コメントと言語ポリシー

- コメント本文（Doxygen、HeaderDoc、行コメント、ブロックコメント）は英語で記述する
- ユーザー向けメッセージ文言（UI テキスト、statusText、Toast、Dialog 文言）は英語で記述する

---

## 文字列・API 取り扱い方針

- 文字列は `wchar_t*` / `std::wstring` を優先して扱う
- 公開 API は `extern "C"` + `__declspec(dllexport/dllimport)` で公開する
- バッファを受け取る API では `buffer_size` を必須にし、境界チェックを行う
- エラー情報は `DWORD* pError` など out 引数で返す

### 参考実装

- ログ関数: `DLog`, `DFLog`, `DFLLog`
- 文字列変換: `ToWString`
- 文字列連結: `ConcatWStrings`

---

## 実装の落とし穴（WinUI 3 / MSIX / 通知）

ビルドが通っても実行時に初めて顕在化する Windows 固有の罠。実装・レビュー時に必ず確認する。

- **文字コード**: 非 ASCII（絵文字・日本語）を含む `.cpp`/`.h` は、UTF-8 BOM 付与または `/utf-8` コンパイルオプションを使う。無いと CP932 解釈で実行時に文字化けし、`warning C4819` が出る。絵文字は `\uXXXX` / `\UXXXXXXXX` のユニバーサル文字名でも安全に書ける。
- **WinRT 非同期と STA**: UI スレッド（WinUI は STA）で `IAsyncXxx::get()` をブロッキング待機しない。cppwinrt が `!is_sta_thread()` で assert する。バックグラウンド（非 STA）スレッドで待機する（例: `std::async` でラップ）。Bridge の同期インターフェース（`DWORD* pError`）は維持できる。
- **パッケージ済み通知のアクティベーション登録**: `AppNotificationManager::Register()` を使うパッケージ済み（MSIX）アプリは、`Package.appxmanifest` に `windows.comServer`（ExeServer + Class Id）と `windows.toastNotificationActivation`（`ToastActivatorCLSID`）の登録が必須。無いと初期化が `No COM servers are registered for this app`（0x80004005）で失敗する。
- **プロセス単位登録の冪等性**: `Register()` はプロセスで一度だけ。Manager の `Init` は既初期化時に再購読・再 `Register()` しないようガードする（二重 `Register()` は `0x80070490`「Must register event handlers before calling Register()」になる）。`Uninit` で状態を戻して再 `Init` できる形にする。
- **進捗バーの更新**: `UpdateAsync` で進捗を更新するには、表示時の進捗バーを**データバインド**（`BindValue`/`BindStatus` 等）にし、初期値を `AppNotification.Progress(AppNotificationProgressData)` で与える。リテラル値で組んだ進捗バーは更新できない（API は成功を返すが見た目が変わらない）。更新の sequence number は表示時より大きくする。
- **フォーマットログのバッファ**: `DFLog` 等は出力長に足りるバッファを確保する（`vswprintf_s` は溢れで `"Buffer too small"` assert）。長い JSON ペイロード等は `_vscwprintf` で必要長を算出して動的確保するか `DFLLog` を使う。
- **ビルド ≠ 表示確認**: トースト表示・コールバック・スケジュール・バッジは MSIX 実機実行（Visual Studio から配置→F5）でのみ確認できる。CLI ビルド成功だけで機能完了と判断しない。`Package.appxmanifest` を変更したらクリーン配置する。アプリ実行中は成果物がロックされ再リンクが `LNK1201` 等で失敗するため、再ビルド前に停止する。
