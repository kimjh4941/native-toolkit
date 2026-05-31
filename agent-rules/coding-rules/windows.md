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
