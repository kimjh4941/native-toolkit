# unity-native-plugin の 2 回目の確かめの結果（写し）

- 記録日: 2026-10-31
- 元の記録: `unity-native-plugin` の `artifact/topics/ios-c-abi-handoff/results/2026-10-31-ios-c-abi-handoff-2-results.md`（ブランチ `feature/UNT-14`。受け取った時点では未コミット）。ここには、向こうのセッション（`unity-native-plugin-15`）から届いた要約を写した
- 申し送り: `results/2026-10-31-ios-c-abi-unity-handoff-2.md`（雛形は `results/probes/stage1a/handoff2/`）
- 環境: Unity 6000.4.2f1、Xcode 26.3、実機 iPhone XS / iOS 18.7.2。実機の段階は、段階ごとに利用者の許可を得て流した。雛形は 2026-10-31 に組んだもの（`ac83ad3b` と未コミットの変更）。Unity の通知パッケージは `com.unity.mobile.notifications` 2.5.0
- 向こうの手の入れ方: コールドスタートのログを残すため、写した `.mm` の先頭に 2 行（`#import "NtkProbeLog.h"`、`#define NSLog NtkProbeNSLog`）を足した。こちらのソースは変えていない。proxy の `os_log` は、向こうが起動したときだけ `OS_ACTIVITY_DT_MODE=YES` で読んだので、コールドスタートの分は無い
- 試作のアプリ（`NtkCAbiProbe`）は利用者の iPhone に入ったまま。消すかどうかは利用者が決める

## 結果

| 項目 | 結果 |
|---|---|
| U-3 | `kUnityWillFinishLaunching`（at=1）でも `didFinishLaunching`（at=2）でも入れられ（戻り値 0）、コールドスタートのタップのイベントが `launch=1` で 1 回だけ届いた（C# の `Start()` で受け手を登録した後）。取得の関数は `u3-cold` を返した。起動の順: `kUnityWillFinishLaunching` → `didFinishLaunching` → `sceneWillEnterForeground` → C# の開始 → `applicationWillEnterForeground` → `sceneDidBecomeActive` → `applicationDidBecomeActive` → `BeforeSceneLoad`（+1.8 秒）→ `Start`。保っていたイベントは、受け手を登録する関数から戻った約 0.44 秒後（Unity の最初のフレームの後）に届いた |
| U-4 | 既定のリンクの順では、パッケージが先に delegate を入れ、ライブラリがその後に入った（at=1・at=2 とも）。前にいるのは `IosLibraryCApi` の proxy。パッケージの通知はパッケージへ（proxy を通る。ライブラリは扱わない）、ライブラリの通知はライブラリへ届いた。コールドスタートのタップ（at=2）も届いた。リンクの順を変える（at=1 で installer をパッケージより前にリンク）と、パッケージが前になり、ライブラリの通知はパッケージに取られ、前面のバナーも出なかった。Unity 本体は delegate を設定しない。パッケージは前の delegate を持たず、転送しない。C# の `AuthorizationRequest` を呼ぶとパッケージが delegate を入れ直し、その後のライブラリの通知は失われた |
| U-6 | (1) 背景のアクションのイベントは 1 回だけ、アプリが後ろにいる状態で届いた（Unity のフレームは止まっていて、C# のコールバックは proxy の `didReceive` の 1 ms 後に動いた）。(2) 止めた状態から背景のアクションを押すと、アプリは後ろで起動したが、IL2CPP / C# はそこでは動かず、約 50 秒後に利用者がアプリを開いたとき（同じプロセス）に動いた。保っていたイベントはそのとき `launch=1` で届いた。アプリは止められなかった。(3) 返信のイベントは 1 回だけ、文字の長さ 3 で届いた |
| U-7 | 後ろに移る 1 秒前・2 秒前に出した通知は、`willPresent` が呼ばれバナーも出た。後ろに移ってから 0.33 秒後に来た通知も `willPresent` が呼ばれた。約 2.9 秒後に来た通知では `willPresent` は呼ばれず、バナーは出た（シミュレーターの約 3 秒と同じ） |

パッケージ 2.5.0 の振る舞い（向こうがパッケージのソース `Runtime/iOS/Plugins` で確かめた）:

- `UnityNotificationLifeCycleManager` の `+load` が `kUnityWillFinishLaunchingWithOptions` の受け手を登録し、その中で `center.delegate = manager` にする（前の delegate は持たない）
- `_RequestAuthorization`（C# の `AuthorizationRequest`）も、呼ばれるたびに `center.delegate = manager` にする
- `willPresent` と `didReceive` は転送しない。`willPresent` は自分の印（`showInForeground`）の無い通知に何も返さない（ライブラリの通知はバナーが出ない）。`didReceive` はすべての応答を `lastReceivedNotification` に保つ
- 既定の `RequestAuthorizationOnAppLaunch=true` の起動の時の要求は、delegate を入れ直さない

## 決めたこと（2026-10-31、利用者。どれも推奨のとおり）

| ID | 決めたこと | 理由 |
|---|---|---|
| H2-1 | **P1-22 を絞る**: 起動のきっかけは、アプリを前面に出す応答（通知の本体のタップ、前面に出すアクション）だけ。背景のアクションでの起動は、ふつうのイベントとして届け、`launch` の印を付けない | U-6 (2)。今の定義では、背景のアクションで後ろに起動され、後で利用者が開いたときに「起動のきっかけ」になり、「通知から開いた」と読む C# が誤る |
| H2-2 | **Unity では `didFinishLaunching` で `ntk_notification_install` を呼ぶ**（2c の `.mm`） | U-4。リンクの順に関わらずパッケージの後に入り、U-3 でコールドスタートのタップに間に合った。`kUnityWillFinishLaunching` はリンクの順しだいでパッケージより前になる |
| H2-3 | **パッケージが後から delegate を入れ直す問題は、1a-10（自動では入れ直さない）のまま、ホストが入れ直す**: unity-native-plugin の C# の包み（2c）は、パッケージの `AuthorizationRequest` を呼んだ後に `ntk_notification_install` をもう一度呼ぶ。マニュアルにも書く。ライブラリは差し替えを見張ってログに警告を出す（第 1 部 5.12） | 自動で入れ直すとホストと奪い合う。入れ直せば戻ることは 1b のシミュレーターのテストで確かめる |

ほかに分かったこと:

- 1a-13（ホストから応答を渡してもらう C の関数）は足さない。U-3 で、どちらの時期に入れてもコールドスタートのタップに間に合った
- P1-21 の循環は、パッケージが転送しないので起きない（入れ直しの at=3 で、2 回目の入れる関数は何もしなかった）。U-4 の合格の条件の「パッケージが同期に転送する」は当たらない
- 2c の `.mm` は、UnityFramework に `UserNotifications.framework` を足す必要がある（1 回目の結果の「申し送りとの違い」2）
