# 必要な機能だけを入れられる配布物にする（全 OS）

- 記録日: 2026-10-10
- 分類: アーキテクチャ（横断課題）
- 状態: 未着手
- 関連: [android-c-abi](../android-c-abi/README.md)（2.0.0 は 1 つの成果物で出す）、[windows-architecture](../windows-architecture/README.md)（Windows の C ABI）

## 何が問題か

今の配布物は、どの OS でも全機能（Clipboard、Dialog、Notification、Share など）を 1 つの成果物に入れている。機能が増えるほど、1 つの機能しか使わないアプリにも、使わない機能のコードと依存のライブラリが入る。利用者が必要な機能だけを選んで入れられる形にしたい（利用者の発案。2026-10-10）。

## 今の配布物（1.12.0 と 2b の時点）

| OS | 成果物 | 形 | 使わない機能を落とせるか |
|---|---|---|---|
| Android | `android-native-toolkit`（Kotlin の API の AAR、約 0.7 MB）、`android-native-toolkit-capi`（C ABI の AAR、約 2.2 MB。大半はリンクとデバッグ用の Prefab の `libntk.so` で、アプリには入らない） | アプリに入るのは `libntk.so`（ABI ごとに約 220 KB）、Kotlin のクラス、依存のライブラリ（fragment、coroutines、media など） | **落とせない**。`libntk.so` は 1 つの共有ライブラリで、C の関数は Kotlin を名前で呼ぶので、R8 の keep の規則が `capi.jni` の全体を残す。依存のライブラリも全機能のぶんが付く |
| Windows | C++ の API（静的ライブラリ `.lib`、約 12 MB）、C ABI（DLL、約 580 KB）、NuGet | 静的ライブラリと DLL | C++ の API は、使わない部分をリンカーが落とせる（静的ライブラリなので）。**C ABI の DLL は落とせない** |
| iOS | `ios-native-toolkit` と Unity 向けの xcframework（動的な framework、arm64 で約 0.7 MB） | 動的な framework | **落とせない**（動的な framework は丸ごと入る） |
| macOS | `mac-native-toolkit` と Unity 向けの xcframework（動的な framework、universal で約 1.4 MB） | 動的な framework | **落とせない** |

## 分け方の案

| 案 | 中身 | 長所 | 短所 |
|---|---|---|---|
| A（推奨） | **共通部分と機能ごとの成果物に分け、今の名前は「全部入り」の入口として残す**。例: Android は `android-native-toolkit-capi-core` と `-clipboard`・`-dialog`・`-notification`・`-share`。C の側は共通の `.so`（初期化、登録の表、JNI）と機能ごとの `.so`（Prefab の 1 パッケージの中の複数のモジュール）。今の `android-native-toolkit-capi` と CMake の `ntk::ntk` は、全機能に依存する入口にする | Maven / NuGet / SwiftPM から取る利用者に効く。依存のライブラリも機能ごとに付く。入口を残すので、今の利用者は壊れない。C のヘッダーはすでに機能ごとに分かれている（`Clipboard.h` など） | 初期化と登録の表を、複数の共有ライブラリにまたがって 1 つにする作りが要る（Android: `JNI_OnLoad` と表づくり。Windows: DLL の間の共通の状態） |
| B | ソースから組む人向けに、機能を選ぶビルドの設定を作る（例: `-Pntk.features=clipboard,share`、CMake のオプション、Xcode の構成） | 作りが簡単 | 配布物（Maven など）から取る利用者には効かない |
| C | 静的ライブラリで配り、利用者のリンカーに使わない関数を落とさせる | 成果物は 1 つのまま | Android は Kotlin を名前で呼ぶので効果が薄い。Apple の OS は Swift の静的な framework への切り替えが要る |

## 対応方針（案）

- 2.0.0（Android の C ABI）は 1 つの成果物のまま出す。今分けると、2b で作った初期化と登録の表を作り直すことになり、手戻りが大きい
- **後で分けるときは、今の成果物の名前と CMake のターゲットを「全部入り」の入口として残す**（案 A）。こうすれば、分けることは利用者を壊さない変更になる
- **着手の時期: ほかの OS（iOS / macOS）の C ABI 化の後**（利用者の決定。2026-10-10）。分け方の境目（共通部分と機能ごと）は C ABI のヘッダーと初期化の作りで決まるので、全 OS に C ABI がそろってから、1 回の設計で全 OS を分ける。その時点で、OS ごとに「全部入り」と「1 機能だけ」でアプリの大きさの差を測り、分けるかどうかを決める

## 着手するときに確かめること

- 測る: OS ごとに、全部入りと 1 機能だけのアプリの大きさの差（Android は APK / AAB の `lib/` と dex、依存のライブラリ）
- Android: 複数の `.so` のときの `JNI_OnLoad` と初期化の状態の持ち方、Prefab の複数のモジュール、R8 の keep の規則を機能ごとに分けること、Maven の依存の向き（機能 → core）
- Windows: C ABI を機能ごとの DLL に分けるか、C++ の静的ライブラリと同じく利用者のリンクで落とす形にするか。NuGet のパッケージの分け方
- iOS / macOS: 動的な framework を機能ごとに分けるか、静的な framework にして利用者のリンカーに落とさせるか。Unity の橋渡しの成果物の扱い
- Unity（`unity-native-plugin`）: 機能ごとの成果物を、Unity のパッケージの側でどう選ばせるか
