# macOS コーディングルール

## 適用対象

このルールは以下に適用する。

- Swift 実装（`mac/MacLibrary/`, `mac/UnityMacPlugin/` 配下）
- Objective-C 実装（Bridge 層 `.h` / `.m`）

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

- `public` / `internal` Swift 関数
- `override` Swift 関数
- `@objc` 公開関数
- Objective-C の公開関数（Bridge C API 含む）
- 通知機能コード内のローカル関数

### 除外

- data model / enum / protocol 宣言
- private utility extension 関数
- 純粋 UI ユーティリティ
- 既にログがある箇所（重複追加しない）

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
- ユーザー向けメッセージ文言（UI テキスト、statusText、Toast、Dialog 文言）は英語で記述する
