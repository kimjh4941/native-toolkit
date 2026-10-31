# iOS コーディングルール

## 適用対象

このルールは以下に適用する。

- Swift 実装（`ios/IosLibrary/`, `ios/UnityIosPlugin/` 配下）
- Objective-C 実装（Bridge層 `.h` / `.m`）

---

## ログ（`os.Logger`）

全メソッドの先頭1行目に、全パラメータを含むログを必ず入れる（秘密の値は下の「秘密の値を伏せる」の例外）。

- `IosLibrary` は `os.Logger` を呼ぶ所で直に呼ぶ（2026-10-31、段階 1b。`artifact/topics/ios-c-abi/designs/2026-10-31-ios-c-abi-swift-api-design.md` の S-P21・8.7）。`Log`（`print`）は deprecated で、ライブラリの中では使わない
- 通常ログ: `logger.log(level: .libraryDebug, "...")`（`.debug`。Debug ビルドのログのテストの間だけ `.info` に上がる。`OSLogStore` が `.debug` を返さないため。`Common/LogLevel.swift`）
- エラーログ: `logger.error("...")`。知らせ: `logger.info("...")`
- サンプル（`IosLibraryExample`）も自分の `os.Logger`（subsystem はサンプルの bundle id）を使う。サンプルは `logger.debug` でよい

### Swift フォーマット

```swift
import os

// The file's logger: subsystem is the library's, category is the type name.
private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "FullClassName")

public func sample(identifier: String, title: String, password: String, count: Int) {
    logger.log(level: .libraryDebug, "[sample] identifier: \(identifier, privacy: .public), title: \(title, privacy: .private), password: \(LogRedaction.redact(password), privacy: .public), count: \(count, privacy: .public)")
    // existing logic...
}
```

| 項目 | 規則 |
|---|---|
| logger の持ち方 | ファイルの `private let logger`。generic の型・`@MainActor` の型・`nonisolated` の関数・`deinit` からも使える。1 つのファイルに型が複数あれば、型ごとに名前を分ける（`handleLogger` など）。generic でない型の中に置くなら `nonisolated private static let` でもよいが、generic の型はファイルの `private let` だけ |
| category | 型名の文字列 |
| privacy | 補間ごとに必ず付ける。関数名・識別子（通知・category・アクションの id、ライブラリが作った id）・件数・長さ・列挙・真偽値・エラーの case・`FailureDetail` は `.public`。そのほかの利用者の値（Dialog の題と本文、ボタンの文言、trigger、UTI など）は `.private` |
| 秘密の値 | `.private` でも補間に入れない。`LogRedaction.redact(_:)`（`<redacted, length=N>`）か `LogRedaction.length(_:)` を `.public` で入れる |
| エラー | `\(LogRedaction.describe(error), privacy: .public)`（ライブラリの enum のエラーは `<型>.<case>`、ほかは `NSError` の domain と code）。`localizedDescription` と関連値は出さない |
| 型の制約 | `OSLogInterpolation` は `CustomStringConvertible` を求めるので、列挙などは `String(describing:)` で包む。closure の中で property を補間するときは `self.` を書く |
| Release | `#if DEBUG` で消さない（`.debug` は OS が保存しない） |
| 確かめ | 秘密の値の名前が補間に入っていないかを `grep` で照らし、`LibraryLogPrivacyTests`（UT-15）が番兵の値で読み返す |

### Objective-C フォーマット

ブリッジ（`ios/UnityIosPlugin`。段階 3 で消す）の Objective-C は、消すまで今の `Log` のまま（D-22。ブリッジには手を入れない）。

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

### 秘密の値を伏せる（例外）

全パラメータを出す規則の例外として、秘密になりうる値はログに出さない（2026-10-31。`artifact/topics/ios-c-abi/designs/2026-10-31-ios-c-abi-swift-api-design.md` の 8.7）。

| 項目 | 規則 |
|---|---|
| 伏せる値 | パスワード、Dialog の入力欄の値、通知の返信（`userText`）、通知の内容（`title`、`subtitle`、`body`、userInfo の値。キーは出す）、Share の内容（テキスト、URL、件名、題、ファイルの名前）、クリップボードの本文 |
| 書き方 | 長さ・有無・件数・種類だけを出す。今の公開の型の `description` は変えず、ログの所で伏せる。新しい型は `description` で伏せてよい。エラーの値が URL やパスを持つときは、case の名前だけを出す |
| 出してよい値 | 関数名、長さ、件数、識別子（通知・category・アクションの id）、種類、列挙、真偽値、エラーの case |
| 先頭のログ | 残す。伏せる値を持つ引数は長さだけを出す |
| OS の違い | Android（`android.md`）は通知のタイトルとメッセージを出してよい値とするが、iOS は通知の内容をすべて伏せる |
| ログの出し方 | `os.Logger` で補間ごとに `privacy:` を付ける（上の「Swift フォーマット」） |

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
- **例外（投げない `async`）**: system の API が失敗を返さない問い合わせ（通知の一覧、権限の状態、category の登録と削除など）のネイティブ版は、投げない `async` にしてよい（2026-10-31）
- **例外（サンプル）**: 段階 0c の UI テストの基準になっている今のボタンは、callback 版のまま残してよい。新しく足すボタンは `async` 版を使う（2026-10-31）
- **`PresenterSelection` を取る口**: 画面を出す口（Dialog・Share）と、システムの画面を出しうる口（通知の権限の要求、設定の画面）は `presenter: PresenterSelection` を取る。callback の新しい口は既定を持たず、`async` 版と今の口の拡張は既定 `.firstActiveScene`（今の探し方。待たない。今の動作のまま）にする。**例外**: Dialog の callback の新しい口 `show(_:presenter:requestBox:completion:)` は既定 `.firstActiveScene` を持つ（Swift の API の設計書の付録 A のとおり。2026-10-31）。既定を持たない規則は、今の callback の口と引数のラベルだけで呼び分けが決まる口（Share の `share(content:completion:)` と新しい `share(content:presenter:completion:)`。S-P18）のためで、Dialog の今の口は名前が別（`showAlert` など）なので、既定を持たせても呼び分けが崩れない。探し方と表示の手順は `Common/Presentation/`（`ForegroundLocator`・`PresentationProcedure`）の 1 か所だけに置き、機能の中に `getRootViewController()` を写さない（2026-10-31）
- **UseCase を置かない口**: Data 層に届かない口は UseCase を置かず、Manager から直に持ち主を呼んでよい。対象は、受け手の登録・解除、要求の取り消し、前面の問い合わせ、通知の delegate を入れる口、状態を持たない純粋な関数（2026-10-31。Android の `android.md` と同じ条件）
- **例外**: 待機や結果の非同期到着を伴わず即時完了する control 操作（監視の開始・停止、キャンセル、真偽値の即時判定など）および factory 操作（UI コンポーネントの生成など）は、callback 版 / `async throws` 版を設けず同期形式のまま公開してよい。詳細と適用条件は `common.md`「システム API に合わせた同期・非同期設計」の「例外（同期 control / factory API）」を参照する。上記「必ず `async throws` にする」はこの例外に該当しない操作に適用する

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
