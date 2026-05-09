# 共通実装方針

このファイルはプラットフォーム横断の実装方針を定義する。  
ここに書かれた原則は Android / iOS / macOS / Windows の全実装に適用する。  
プラットフォーム固有の詳細は各ルールファイルを参照すること。

---

## Clean Architecture

### 層の定義と依存方向

```
Domain → Application → Data
                  ↓
            Presentation
                  ↓
              Manager
                  ↓
            Unity Bridge
```

- **Domain**: 純粋モデル・エラー型（プラットフォーム依存なし、標準ライブラリのみ）
- **Application**: UseCase と Port（Repository protocol）。UseCase は 1 操作 1 クラスで `callAsFunction` / `invoke` を持つ
- **Data**: Repository 実装。Domain モデル → プラットフォーム型の変換を担う
- **Presentation**: Permission helper / UI 連携（プラットフォーム API 依存はここまで）
- **Manager**: Delegate 所有、UseCase 集約、Bridge 向け公開 API
- **Unity Bridge**: ネイティブ API と Unity C# の境界。プラットフォームごとに実装する

### 依存のルール

- 上位層が下位層に依存する（逆は禁止）
- Domain は他の層に依存しない
- Manager は UseCase 経由で Data 層にアクセスし、直接 Repository を呼ばない
- プラットフォーム固有の型（例: iOS の `UIKit` / `UserNotifications`、Android の `android.*`）を Domain / Application 層に持ち込まない

### Delegate・Callback の所有権

- システム Delegate / Listener（例: iOS の `UNUserNotificationCenterDelegate`）は Manager 層の 1 クラスのみが所有する
- RepositoryImpl に Delegate を実装しない（SRP 違反）
- Unity Bridge 専用クラスにも Delegate を実装しない（iOS-native など別用途での利用ができなくなるため）
- Manager クラスが初期化メソッドで Delegate 登録を行う

---

## テスト（TDD）

### 基本方針

- 新機能は UseCase 単位でテストを書く
- テストは実装と同時に書く（後からまとめて書かない）
- Mock は実際の Port（protocol）を実装し、UseCase に DI する

### Mock 設計パターン

```swift
// shouldFail フラグで成功・失敗を切り替え
final class MockNotificationRepository: NotificationRepository {
    var shouldFail = false

    // per-method call counter
    var showCallCount = 0

    // stubbed 戻り値は外部から注入
    var stubbedScheduled: [NotificationContent] = []
}
```

- `shouldFail: Bool` フラグで happy path / failure path を切り替える
- per-method call counter（`xxxCallCount`）で呼び出し回数を検証する
- stubbed 戻り値は `stubbedXxx` プロパティで外部から注入できるようにする

### テストフレームワーク（例）

| プラットフォーム    | フレームワーク                      | 備考                   |
| ------------------- | ----------------------------------- | ---------------------- |
| iOS 18+ / macOS 15+ | Swift Testing (`@Test` / `#expect`) | XCTest は使わない      |
| Android             | JUnit 4 / 5 + MockK                 | プロジェクト設定に従う |
| Windows             | xUnit / MSTest / NUnit              | プロジェクト設定に従う |

### テストの確認タイミング

- コードを修正・追加した後は、**必ず既存のテストコードを確認する**
  - 修正内容によって既存テストが壊れていないか確認する
  - 新機能・新フィールドに対してテストが不足していれば追加する
- テスト確認後、対象スキームのテストを実行してすべて passed であることを確認する

---

- エラー型は Domain 層に定義する
- Repository 実装がシステムエラーをドメインエラーに変換する
- Manager 層がドメインエラーを Bridge 向けの形式（例: `(isSuccess: Bool, errorMessage: String?)`）に変換する

```
システムエラー → RepositoryImpl → DomainError → Manager → (Bool, String?) → Bridge
```

---

## Unity Bridge パターン

### 共通原則

- Bridge 層は薄く保つ（ビジネスロジックを持たない）
- Manager の public API を呼び出すだけにする
- 複雑なデータは JSON 文字列で渡す
- Bridge 層の実装詳細は OS ごとに異なってよいが、責務分離の原則は共通とする

### iOS Bridge 構成（実装例）

- Swift facade: `@objcMembers public class XxxManager: NSObject` — singleton、Manager に委譲
- Obj-C ヘッダ (`.h`): callback typedef と `extern "C"` 関数宣言
- Obj-C 実装 (`.m`): 各 C 関数から Swift singleton を呼び出す

```c
// callback typedefs（iOS C-Bridge 実装例）
typedef void (*NativeCallback)(bool isSuccess, const char* errorMessage);
typedef void (*NativeJsonCallback)(const char* json);
typedef void (*NativeStatusCallback)(const char* status);
```

### Android Bridge 構成（実装例）

- Kotlin / Java の JNI または Unity の `AndroidJavaObject` 経由で呼び出す
- Bridge クラスはプラットフォームごとのプロジェクト設定に従う

### macOS / Windows Bridge 構成（実装指針）

- macOS / Windows でも Bridge 層は薄く保つ（Manager 呼び出し専用）
- OS 標準の相互運用方式（例: C API、P/Invoke、プラグイン境界）を用いる
- 例外・エラーは DomainError 相当へ正規化してから Bridge の戻り値形式へ変換する

---

## Minimum OS Versions

設計・実装時は、以下の最小バージョン以上で動作確認が必須。

- **Android**: 12 以降
- **iOS**: 18 以降
- **Windows**: 11 以降
- **macOS**: 15 以降
