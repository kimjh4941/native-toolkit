# iOS コーディングルール

## 適用対象

このルールは以下に適用する。

- Swift 実装（`ios/IosLibrary/`, `ios/UnityIosPlugin/` 配下）
- Objective-C 実装（Bridge層 `.h` / `.m`）

---

## ログ（Log.d / Log.e）

全メソッドの先頭1行目に、全パラメータを含むログを必ず入れる。

- 通常ログ: `Log.d`
- エラーログ: `Log.e`

### Swift フォーマット

```swift
private let TAG = "FullClassName"

public func sample(param1: String, param2: Int) {
    Log.d(TAG, "[sample] param1: \(param1), param2: \(param2)")
    // existing logic...
}
```

### Objective-C フォーマット

```objective-c
static NSString *const TAG = @"FullClassName";

void sample(const char* value) {
    [Log d:TAG :[NSString stringWithFormat:@"[sample] value: %s", value]];
    // existing logic...
}
```

### 対象

- `public` / `internal` Swift関数
- `override` Swift関数
- `@objc` 公開関数
- Objective-C の公開関数（Bridge C API 含む）
- 通知機能コード内のローカル関数

### 除外

- data model / enum / protocol 宣言
- private utility extension 関数
- 純粋 UI ユーティリティ
- 既にログがある箇所（重複追加しない）

---

## Objective-C / Swift ブリッジの型

Swift の API を Objective-C から呼び出す際、completion ブロックの引数型を必ず Swift 側の型と合わせる。

| Swift 側の型 | ObjC ブロック引数で使う型 |
|---|---|
| `Bool` | `BOOL`（`bool` は不可） |
| `Int` | `NSInteger` |
| `String?` | `NSString * _Nullable` |

**NG 例（コンパイルエラーになる）:**
```objective-c
[manager doSomethingWithCompletion:^(bool isSuccess, NSInteger errorCode, NSString* errorMessage) {
```

**OK 例:**
```objective-c
[manager doSomethingWithCompletion:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
```

`bool`（C の `_Bool`）と `BOOL`（`signed char`）はブロックシグネチャ上で別型扱いされ、コンパイルエラーになる。

---

## Manager の公開 API（callback 版 + async throws 版）

方針は `common.md`「Manager の公開 API 方式」を参照。iOS では次の形で実装する。

- callback 版（Bridge 向け）: 既存どおり `(Bool, ..., String?) -> Void` 形式を維持する
- ネイティブ版（Swift 呼び出し元向け）: `async throws` で UseCase をそのまま公開する薄いラッパーを追加する（`@discardableResult` を付け、戻り値を無視できるようにする）
- 新規 Manager を作る場合は、両方式を最初から用意する（後から追加ではなく設計時点で決める）
- サンプルアプリ（`IosLibraryExample`）は `async throws` 版を使う（`Button` の action は同期クロージャのため `Task { await ... }` で橋渡しする）

### `async` の要否（重い処理か軽い処理か）

Manager の公開 API（ネイティブ版）は上記のとおり必ず `async throws` にするが、その内部で呼ぶ private helper まで一律 `async` にする必要はない。

- **`async` にすべきもの**: システム API 呼び出しが実際に非同期・待機を伴うもの（`UIActivityViewController` の完了待ち等）
- **`async` にしなくてよいもの**: `FileManager` を使ったローカルの一時ファイル書き込み・読み込みなど、同期的に完結する軽量処理。`ShareSampleView.swift` の `prepareSampleFileURL()` / `prepareSampleImagePaths(count:)` 等は plain な同期関数のままで、呼び出し元の `Task { }` ブロック内から同期呼び出しされている（これが確立された慣例）
- UI 状態の更新は `DispatchQueue.main.async { ... }` でメインスレッドに戻す（`updateResult(isSuccess:result:)` のパターンを参照）

---

## コメント（DocC / HeaderDoc）

### Swift

`public` なシンボルには DocC コメントを付ける。

**対象（必須）:**

- `public class` / `struct` / `enum` / `protocol`
- `public func`
- 非自明な `public` プロパティ

**除外:**

- `private` / `internal` 関数
- `override` 関数
- 自明な getter / setter

### Objective-C

公開ヘッダの関数・型には HeaderDoc 形式のコメントを付ける。

**対象（必須）:**

- `.h` の公開関数宣言
- callback typedef
- 非自明な公開定数

---

## コメントと言語ポリシー

- コメント本文（DocC、HeaderDoc、行コメント、ブロックコメント）は英語で記述する
- ユーザー向けメッセージ文言（UIテキスト、statusText、Toast、Dialog文言）は英語で記述する
