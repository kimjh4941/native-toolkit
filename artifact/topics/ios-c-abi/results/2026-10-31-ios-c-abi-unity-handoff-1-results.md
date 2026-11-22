# unity-native-plugin の 1 回目の確かめの結果（写し）

- 記録日: 2026-10-31
- 元の記録: `unity-native-plugin` の `artifact/topics/ios-c-abi-handoff/results/2026-10-31-ios-c-abi-handoff-1-results.md`（ブランチ `feature/UNT-14`。受け取った時点では未コミット）。ここには、向こうのセッション（`unity-native-plugin-15`）から届いた要約を写した
- 申し送り: `results/2026-10-31-ios-c-abi-unity-handoff-1.md`（雛形は `results/probes/stage1a/handoff1/`）
- 環境: Unity 6000.4.2f1、Xcode 26.3（ASan の版は 26.6）、実機 iPhone XS / iOS 18.7.2。実機の段階は、段階ごとに利用者の許可を得て流した（`agent-rules/device-testing.md`）。雛形は 2026-10-31 に組んだもの（`fbb03f70` と未コミットの変更）
- 組み込み方: 両方のリポジトリの外に作った使い捨ての Unity のプロジェクト。xcframework は手ではなく PostProcessBuild（PBXProject の API）で入れた（capi と `IosLibrary` を UnityFramework に Do Not Embed、アプリに Embed & Sign）。unity-native-plugin のパッケージは使っていない

## 結果

| 項目 | 結果 | 中身 |
|---|---|---|
| U-1 | 合格 | `version=0x020000`。読み取りは `error=6`・`release=1`。Dialog は `error=0`・`button=0`・`release=1`。完了と `release` は main で、関数が戻った後に届いた（同じ Unity のフレームの中。`Time.frameCount` は変わらない）。雛形からの警告は無い |
| U-2 | 合格 | `codesign --verify`（`IosLibrary`、`IosLibraryCApi`、アプリ）はどれも通り、Team ID はアプリと同じ。開発用の署名（Apple Development）だけで、配布用の署名と Organizer の Validate App は行っていない（App Store Connect とやりとりするため） |
| U-5 | 結果を記録 | Dialog を 20 秒出している間もフレームが進んだ（1266 → 1879、毎秒約 30）。Share も進んだ（1991 → 2681。最初の 1 秒は 4 フレーム、その後は毎秒約 30）。完了は Dialog が `error=0`・`button=1`・`release=1`、Share が `error=0`・`completed=0`・`release=1` |
| U-8 | 結果を記録 | `Start()` から出た。シーンを読む前（フレーム 0）でも出た。同じフレームに 2 つ呼ぶと 2 つとも出て、2 つ目が上 |
| U-9 | 落ちる | C# のコールバックが例外を投げると `libc++abi: terminating due to uncaught exception of type Il2CppExceptionWrapper` で止まる（signal 6）。`release` は来ない。シミュレーターでも同じ |
| U-10 | 結果を記録 | 実機の TSan は対応していない（Apple の文書: Diagnosing memory, thread, and crash issues early）。実機の ASan の報告は 0 件 |

止まったものは無い。Validate App は頼んでいないので行っていない。

## 設計への影響

| 結果 | 影響 |
|---|---|
| U-1・U-2 | D-9（dynamic の framework を 2 つ）と D-18（配る framework に署名しない）は、開発用の署名では成り立った。**配布用の署名（Distribution のアーカイブと Validate App）はまだ確かめていない**。リリースの前に確かめる（README 9 章の DoD に足す） |
| U-8 | P1-11（前面の定義）と P1-12（同じ回の 2 つの Dialog は両方出す）の推奨のとおりに動いた |
| U-5 | C ABI は変えない。マニュアルと unity-native-plugin の案内に「Dialog と Share を出している間もゲームは進む」と書く |
| U-9 | P1-16（コールバックの中の例外は禁止。出た場合の振る舞いは定めない）の想定どおり。マニュアルと 2c の C# の包みに「コールバックの中は必ず try / catch」と書く |
| U-10 | P1-20 のとおり（実機の TSan は使わない）。**ASan で組んだ xcframework は、アプリを組む Xcode と同じ版でないと動かない**（dyld が `___asan_version_mismatch_check_apple_clang_2100` で止まる）。ASan の版は配布物ではなくテスト用なので、テストの手順と 2b の ASan の段に書く |

## 申し送りとの違い（向こうが見つけたもの）

1. ASan の版の Xcode（上の U-10）。申し送りの「Xcode 26.3 以上ならどれでも」は ASan の版には当たらない
2. 2 回目の申し送りの `NtkHandoff2Installer.mm` は、UnityFramework に `UserNotifications.framework` を足さないとリンクで止まる（`_OBJC_CLASS_$_UNUserNotificationCenter` が無い）。`.mm` の Unity の名前（`AppDelegateListener.h`、`UnityRegisterAppDelegateListener`、`kUnityWillFinishLaunchingWithOptions`、`didFinishLaunching:`）は 6000.4.2f1 にそのまま有る（`didFinishLaunching:` は `LifeCycleListener` から）。通知のパッケージが無いとき、`kUnityWillFinishLaunching`・`didFinishLaunching`・`didBecomeActive` で入れる前の delegate は `nil`（シミュレーター）。2c の申し送りに書く
3. 署名: チームの Xcode が管理するワイルドカードの profile は自動の署名でしか使えない。App ID を登録しないよう `-allowProvisioningUpdates` を付けずに使った

2 回目（U-3・U-4・U-6・U-7）は、向こうが実機の段階ごとに利用者の許可を得てから流す。
