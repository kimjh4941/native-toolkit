# 段階 1a の作業の記録（通知の delegate の転送と、delegate を入れる関数）

- 記録日: 2026-10-31
- 段階: 1a（`README.md` の 5 章の 1a の行、8.2 の delegate と入れる関数の 2 行、D-4・D-6・D-7）
- 分担: この記録は C1（`UNUserNotificationCenter` の delegate の転送）と C2（入れる関数のスレッド）だけを扱う。C の入口・配布物は別の agent（`2026-10-31-ios-c-abi-stage1a-entry-working-notes.md`）、本物の Unity のビルドは `unity-native-plugin` の agent が後で行う
- ブランチ: `feature/NTKIT-18`（未コミット）
- 環境: Xcode 26.3（17C529）、Swift 6.2.4、iOS 26.2 SDK。シミュレーターは iPhone 16（iOS 18.3.1）と iPhone 16（iOS 26.2）だけ。**実機には触れていない**
- 状態: 8.2 の 2 行のうち、シミュレーターで確かめられることは確かめた。`openSettingsFor` をシステムから呼ばせることはできなかった（3.4）。バックグラウンドのアクションでの completion の遅れの影響は、シミュレーターでは区別できなかった（2.2）。実機と Unity で確かめることは 6 章

## 1. 測り方

使い捨てのアプリ `DelegateProbe` と、操作だけをする XCUITest で測った。ソースと手順は `probes/stage1a/delegate/`（`probes/README.md` の行）。アプリは `IosLibrary` に依存せず、`swiftc`（Swift 6 の言語モード）で組んだ。ログ（`events.log`）は scratchpad に置き、リポジトリには入れていない。

| 項目 | 方法 |
|---|---|
| アプリ | 2 つ組んだ。scene の無いもの（`Info.plist`）と scene のあるもの（`Info-scene.plist`。`UISceneDelegateClassName`）。起動ごとに筋書き（`PROBE_SCENARIO`）を読み、受けたものをすべて `Documents/events.log` に書く（時刻はプロセスの生成からの秒、スレッド、`applicationState`） |
| 試作の転送の delegate | `ForwardingDelegate.swift`。ライブラリが強く持ち、前の delegate を weak で持つ。動きは下の表 |
| 入れる関数の試作 | `Install.swift` の `@_cdecl("ntk_notification_install")`。アプリは C のシンボルを `dlsym` で引いて呼ぶ（ホストのネイティブのコードと同じ呼び方）。エラーの番号は仮（main 以外 16、差し替えを拒む設定で 17） |
| 前の delegate（ホスト） | `HostDelegate`（3 つのメソッドを実装し、振る舞いを選べる）と `BareHostDelegate`（何も実装しない）。ホストは起動の処理で配列に入れて強く持つ（ホストの AppDelegate と同じ） |
| 通知の種類 | lib: userInfo に印 `com.jonghyunkim.nativetoolkit` がある / host: 印が無い（`{"host":1}`）/ legacy: 印が無い 1.x の形（`{"k":"v"}`。1.x は利用者の userInfo しか入れないので、ホストの通知と中身で区別できない）/ push: `simctl push` で送った通知 |
| 操作 | XCUITest（サンプルの UI テストのターゲットを scratchpad に写し、試験のファイルだけを入れて組んだ。リポジトリは変えていない）。前面のバナーを待つ、ホームに戻ってバナーをタップする、アプリを止めてからバナーをタップする（コールドスタート）、バナーを長押しして背景のアクション（`options: []`）を押す |
| 見たもの | バナーが出たか（springboard の `NotificationShortLookView`）、表示中の一覧（`getDeliveredNotifications`）、`add(_:withCompletionHandler:)` の完了が返った時刻、アプリの状態（`XCUIApplication.state`。2 = 背景で停止、3 = 背景で動作中、4 = 前面）、システムのログ（`log show` の `com.apple.UserNotifications` と `UIKit:BackgroundTask`） |

前の delegate の振る舞い（どのメソッドに効かせるかは筋書きで選ぶ。2 回目以降の呼び出しは sync）:

| 名前 | 振る舞い |
|---|---|
| none | 前の delegate が無い |
| noimpl | 前の delegate はあるが、どのメソッドも実装しない（`responds(to:)` が偽） |
| sync | その場で completion を呼ぶ。`willPresent` は `[.banner]` |
| asyncMain / asyncBg | 1 秒後に main / グローバルのキューから呼ぶ |
| async5 | 5 秒後に main から呼ぶ |
| twice | その場で 2 回呼ぶ |
| never | 呼ばずに closure を捨てる |
| hold | 呼ばずに closure を持ち続ける |

試作の転送の delegate の動き:

| 通知 | 前の delegate がそのメソッドを実装している | 実装していない・前の delegate が無い |
|---|---|---|
| lib（印がある） | 前の delegate に渡さない。ライブラリが扱い、system の completion をその場で 1 回呼ぶ（`willPresent` はライブラリの表示の選択肢 `[.banner, .list]`） | 同じ |
| 印が無い（host・legacy・push） | 前の delegate に渡す。渡す completion は 1 回だけ system に通す包み（`Once`。2 回目以降は捨ててログに出す） | ライブラリが扱う（「誰も受けない通知」。ライブラリの表示の選択肢とイベント） |

ほかに、転送している間に同じ通知で戻ってきた呼び出しを止める仕組み（循環の防止）と、前の delegate が呼ばないときに system の completion を代わりに呼ぶ仕組み（watchdog。試験では 3 秒。既定は切ってある）を入れた。

## 2. システムの振る舞い（転送の delegate を入れない状態）

前の delegate だけを `UNUserNotificationCenter.delegate` に置いて測った（筋書き `raw.*`）。18.3 と 26.2 で同じ結果だった（26.2 は抜き出した 11 の組み合わせ）。

### 2.1 `willPresent`（前面）

| 振る舞い | バナー | 表示中の一覧 | `add` の完了 | 次の通知 |
|---|---|---|---|---|
| delegate が無い / noimpl | 出ない（`willPresent` は呼ばれない） | 入らない | すぐ返る | 同じく出ない |
| sync（`[.banner]`） | 出る | **入る**（`.list` が無くても） | completion の後 | 普通 |
| `[.list]` だけ | 出ない | 入る | completion の後 | 普通 |
| asyncMain / asyncBg（1 秒） | completion の後に出る | 入る | **completion を呼んだ後に返る** | 普通 |
| async5（5 秒） | 約 5 秒後に出る | 5 秒までは入らない | 5 秒後 | 普通 |
| twice | 出る。2 回目は何も起きない（落ちない、ログも無い） | 入る | 1 回目の後 | 普通 |
| never（closure を捨てる） | 出ない | 入らない | 捨てた直後に返る | 普通（出る） |
| hold（持ち続ける） | 出ない | 入らない | **返らない**（11 秒待っても） | 普通（出る） |

- `willPresent` は main スレッドで呼ばれた（全件）
- **アプリが背景に移った直後（ホームに戻ってから約 3 秒以内）でも `willPresent` が呼ばれ**（`applicationState` は background か inactive）、その答えでバナーが決まる。delegate が無いと、この間はバナーが出ない。12 秒後（停止した後）はシステムが `willPresent` を呼ばずにバナーを出した
- hold では、その要求の `add` の完了が返らない。つまり、前の delegate が completion を持ったままだと、その通知を `add` した側の完了も止まる
- システムは 2 回目の呼び出しも、呼ばれない completion も、ログに出さない（`com.apple.UserNotifications` に該当が無い）

### 2.2 `didReceive`

| 振る舞い | バナーのタップ（前面に来る） | 背景のアクション（`options: []`）の後のアプリの状態 |
|---|---|---|
| sync | 普通に前面に来る | 2 秒後に停止（2） |
| asyncMain / asyncBg / twice / never / hold | 違いは見えない（twice は落ちない） | never（捨てる）: 2 秒後に停止（2）。**hold: 50 秒以上動き続けた（3）**。async5（5 秒後に呼ぶ）: **これも 50 秒以上動き続けた（3）** |

- `didReceive` は main スレッドで呼ばれた。タップでは inactive、背景のアクションでは background
- 背景のアクションでは、completion を呼ばずに持ち続けるとアプリが背景で動き続ける。ただし、5 秒後に呼んだ場合も同じく動き続けたので、**シミュレーターでは「呼ばない」と「遅れて呼ぶ」を区別できない**。completion を呼んだときに UIKit はスナップショットの背景タスクを始めて終えている（ログ）ので、システムは completion を受け取っている。実機で確かめる（6 章）

### 2.3 delegate の参照と差し替えの検出

| 項目 | 結果 |
|---|---|
| `delegate` は weak か | weak（SDK のヘッダーの `weak`。誰も持たないオブジェクトを入れると、同じターンで `nil` になった） |
| KVO で差し替えを検出できるか | **できる**。`addObserver(forKeyPath: "delegate")` が、ホストの設定、こちらの設定のどちらでも呼ばれた（18.3・26.2） |
| `simctl push` の通知 | `trigger` が `UNPushNotificationTrigger`。payload の独自のキーは userInfo に入る。`willPresent` が呼ばれる |

### 2.4 コールドスタート（アプリを止めてからバナーをタップ）

起動の中の順番（秒はプロセスの生成から。1 回ずつの例）:

| アプリ | 版 | 順番 |
|---|---|---|
| scene 無し | 18.3 | `willFinishLaunching` 0.523 → `didFinishLaunching` 0.537 → `didFinishLaunchingNotification` 0.539 → **`didReceive` 0.539** → `applicationDidBecomeActive` 0.547 → `didFinishLaunching` で積んだ `DispatchQueue.main.async` 0.579 |
| scene 無し | 26.2 | `willFinish` 0.642 → `didFinish` 0.667 → 通知 0.668 → **`didReceive` 0.668** → main.async 0.747 → `didBecomeActive` 0.749 |
| scene あり | 18.3 | `willFinish` 0.491 → `didFinish` 0.522 → 通知 0.522 → `scene(_:willConnectTo:)` 0.530 → **`didReceive` 0.542** → `sceneDidBecomeActive` 0.551 → main.async 0.581 |
| scene あり | 26.2 | `willFinish` 0.602 → `didFinish` 0.636 → `willConnectTo` 0.646 → **`didReceive` 0.669** → main.async 0.744 → `sceneDidBecomeActive` 0.748 |

どの時期に入れるとタップが届くか（lib の通知。18.3 と 26.2 で同じ）:

| 入れる時期 | scene 無し | scene あり |
|---|---|---|
| `willFinishLaunching` | 届く | 届く |
| `didFinishLaunching` | 届く | 届く |
| `scene(_:willConnectTo:)` | - | 届く |
| `didFinishLaunching` から積んだ main.async | **届かない** | **届かない** |
| `applicationDidBecomeActive` / `sceneDidBecomeActive` | 届かない | 届かない |
| 1 秒後・3 秒後 | 届かない | 届かない |
| 入れない | 届かない | 届かない |
| 転送の delegate は入れず、1 秒後・3 秒後にホストの delegate だけを置く | 届かない | - |

- コールドスタートの応答は、`didFinishLaunching`（scene のアプリでは `scene(_:willConnectTo:)`）から戻った直後、main キューの次の処理より前に 1 回だけ渡される。**システムは delegate が置かれるまで応答を保たない**
- ホストの delegate を `willFinish` に置き、その後に転送の delegate を入れた場合（`cold.willFinish.host`、`cold.didFinish.host`）は、印の無い通知の応答がホストに渡った
- 後から取れる手がかり: scene 無しでは `launchOptions` に `UIApplicationLaunchOptionsLocalNotificationKey` がある（応答の中身ではない）。scene ありでは `launchOptions` は nil で、`connectionOptions.notificationResponse` に応答があった（入れていない場合も）。どちらもホストの delegate にしか渡らないので、ライブラリが後から自分で取ることはできない
- `applicationState` は、scene 無しでは `willFinish`・`didFinish` で inactive、scene ありでは **background**。どちらも前面に来た後は active

## 3. 転送の組み合わせの結果（18.3。26.2 は抜き出したもので同じ）

### 3.1 `willPresent`（前面。A を出し、その後に B を出す）

| 前の delegate | lib | host | legacy |
|---|---|---|---|
| none | ライブラリが即 1 回。バナーあり | 誰も受けない → ライブラリが即 1 回。バナーあり（転送の delegate が無いと出ない） | host と同じ |
| noimpl | 即 1 回、渡さない。バナーあり | 誰も受けない → ライブラリ。バナーあり | host と同じ |
| sync | 即 1 回、渡さない | 渡す → 前の delegate が 1 回。前の delegate の選択肢（`[.banner]`）のまま | host と同じ |
| asyncMain / asyncBg | 即 1 回、渡さない | 渡す。戻った時点では未完了、1 秒後に前の delegate が 1 回（asyncBg はグローバルのキューから。システムは受けた） | （測っていない。host と同じ動き） |
| twice | 即 1 回、渡さない | 1 回目を通し、2 回目を捨てた（`once.drop call=2`） | 同上 |
| never | 即 1 回、渡さない | 誰も呼ばない（closure が捨てられ、包みごと解放）。バナー無し（2.1 と同じ）。watchdog ありでは 3 秒後に `[]` で 1 回 | 同上 |
| hold | 即 1 回、渡さない | 誰も呼ばない。バナー無し、`add` の完了も返らない。watchdog ありでは 3 秒後に `[]` で 1 回呼び、その 15 ms 後に `add` の完了が返った | 同上 |

- どの組み合わせでも、system の completion が 2 回呼ばれることは無かった。lib の通知は前の delegate の振る舞いに左右されない（渡さないので）
- 表示の選択肢を合わせる処理は要らなかった。lib はライブラリの選択肢、渡したものは前の delegate の選択肢をそのまま、誰も受けないものはライブラリの選択肢
- B（2 回目）はどの組み合わせでも普通に出た

### 3.2 `didReceive`（ホームに戻り、背景で出たバナーをタップ）

| 前の delegate | lib | host | legacy |
|---|---|---|---|
| none / noimpl | ライブラリのイベント → 即 1 回 | 誰も受けない → ライブラリのイベント（印無しの扱い）→ 即 1 回 | 同じ（none と sync を測った） |
| sync | 渡さない。即 1 回 | 渡す → 前の delegate がその場で 1 回 | host と同じ |
| asyncMain / asyncBg | 渡さない | 渡す。1 秒後に前の delegate が 1 回（asyncBg はグローバルのキュー） | - |
| twice | 渡さない | 1 回目を通し、2 回目を捨てた | - |
| never / hold | 渡さない | 誰も呼ばない。前面に来るタップでは違いが見えない | - |
| hold + 背景のアクション | 渡さない。即 1 回 → 停止（2） | 動き続けた（3）。watchdog ありで 3 秒後に 1 回呼んでも動き続けた（2.2 の「遅れて呼ぶ」と同じで、シミュレーターでは区別できない） | - |

### 3.3 ホストが後から差し替える

| 筋書き | 結果 |
|---|---|
| ホスト 1 → 転送の delegate → 1 秒後にホスト 2 が上書き（転送しない） | KVO が呼ばれた。その後の lib の通知もホスト 2 に行き、ライブラリには届かない。入れる関数をもう一度呼ぶと、転送の delegate が戻り、前の delegate はホスト 2 になった（lib はライブラリ、host はホスト 2 へ）。ホスト 1 は鎖から外れたまま（ホスト 2 が転送しなかったので） |
| 同じで、差し替えを拒む設定 | 2 回目の呼び出しは 17 を返し、ホスト 2 がすべてを受け続けた |
| ホスト 2 が自分の前（転送の delegate）に転送する形 | 差し替えの後も、ホスト 2 → 転送の delegate の順で lib を受けられた。もう一度入れると転送の delegate → ホスト 2 → 転送の delegate の循環になり、**循環の防止で止まった**（`proxy.cycle`。system の completion は 1 回） |
| 同じで、循環の防止を切った | 無限の再帰でアプリが落ちた（`EXC_BAD_ACCESS`、「Thread stack size exceeded due to excessive recursion」） |

### 3.4 `openSettingsFor`

- システムから呼ばせることは**できなかった**。`openNotificationSettingsURLString` を開くと設定の App は最上位で止まり、「アプリ」の一覧にも検索にも `swiftc` で組んだ試験のアプリが出なかった（権限の要求には `.providesAppNotificationSettings` を入れた）。Xcode で組むアプリ（サンプル）なら一覧に出る見込みで、1b のテストで確かめる
- 転送の delegate のメソッドを直接呼んで、転送の判定だけを確かめた: 前の delegate が無い・実装しない → ライブラリ、実装する → 前の delegate にだけ渡した
- 1.x の `openSettingsFor` は `openNotificationSettings()`（設定の App を開く）を呼んでいる。これは「設定の App の中のリンクからアプリの設定の画面を開く」ための通知なので、設定の App を開き直すのは意味が逆になる。2.0.0 ではイベントとして利用者に渡すのがよい（第 1 部で決める）

### 3.5 通知の種類の見分け

- `simctl push` の通知は `UNPushNotificationTrigger` で見分けられた。ただし、試作は印を先に見るので、印を入れた push はライブラリの通知と判定した
- 1.x の通知とホストのローカルの通知は、中身でも trigger でも区別できない

## 4. 入れる関数（C2）

`c2` と `c2late` の筋書き（18.3）。26.2 でもコールドスタートの筋書きで同じ呼び方をした。

| 呼び方 | 結果 |
|---|---|
| グローバルのキューから（main は `DispatchSemaphore` で待っている） | 16 をすぐ返した（0.2〜0.4 ms）。main を待たないので固まらない。delegate は変わらない |
| `Thread` から | 16 |
| main（`willFinishLaunching`） | 0。**関数の中で戻る直前に `delegate === proxy` を確かめ、呼んだ側でも同じ**。前の delegate（ホスト）を覚えた |
| 2 回目（main） | 0（何もしない）。前の delegate はホストのまま（自分自身にならない） |
| main スレッドだが main キューでない（main から `DispatchQueue(label:).sync`） | `pthread_main_np` も `Thread.isMainThread` も真で、入れる処理に進む。その中の `MainActor.assumeIsolated` は 18.3 で止まらなかった |
| 起動が終わった後（2 秒後、active）に初めて呼ぶ | 0。delegate は設定されるが、コールドスタートのタップは取りこぼす（2.4） |
| C のシンボルを `dlsym` で引いて呼ぶ | 動く（上のすべて） |

「起動が終わった後か」を関数の中で正しく知る方法は無い。`applicationState` は scene のアプリでは起動の処理の中でも background なので、「active なら遅い」としか言えず、背景で起動した場合の誤りも残る。

## 5. 決定と設計への意味

| 決定 | 確かめたこと | 意味 |
|---|---|---|
| D-4（初期化） | 応答は `didFinishLaunching`（scene では `willConnectTo`）から戻った直後に 1 回だけ渡され、保たれない（2.4） | 「ホストのネイティブのコードが、起動の処理の中で同期に呼ぶ」契約は正しい。期限は **`didFinishLaunching` から戻るまで**（scene のアプリでは `scene(_:willConnectTo:)` から戻るまでなら間に合う）。main.async で後に回すと間に合わない。Unity の C#（起動の後に始まる）や `didBecomeActive` からでは間に合わない。`didFinishLaunchingNotification` の受け手からでも間に合う（応答より先に来る） |
| D-6（同期の例外） | main 以外は即 16、main では戻る前に設定済み、main を待たない（4 章） | 同期・main 限定・待たない、の形は成り立つ。main かどうかは `pthread_main_np`（main スレッド）で見る。main キューの判定（`dispatch_assert_queue` の類）にすると、`dispatch_sync` の中の main スレッドを拒むことになり、`MainActor.assumeIsolated` とも食い違う |
| D-6（イベントの配送） | system の completion は、ライブラリがその場で呼ぶと 1 回で済む（3 章） | C のコールバックは main に積んで後で呼ぶ（D-6）ので、`didReceive` の completion をその場で呼ぶと、イベントが利用者に届く前にシステムに「終わった」と伝えることになる。前面では問題が無いが、背景のアクションではアプリが止まりうる。**ライブラリの通知の `didReceive` は、イベントを積んだ main のブロックの中で、受け手を呼ぶか保つかした後に completion を呼ぶ**のがよい（シミュレーターでは確かめられない。6 章） |
| D-7（転送） | 3 章の全組み合わせで system の completion はちょうど 1 回以下、2 回目は包みで捨てた | 次の形を第 1 部に書ける: 転送の delegate はライブラリが強く持つ、前の delegate は weak、3 つのメソッドを常に実装し、前の delegate の `responds(to:)` は呼ぶたびに見る、ライブラリの通知は前の delegate に渡さない、渡す completion は 1 回だけ通す包みにする、循環の防止は必須（無いと落ちる）、差し替えは KVO で検出できる |
| D-7（completion を呼ばない前の delegate） | 捨てた場合はシステムが終わりとみなす。持ち続けた場合は `add` の完了が止まり、背景で動き続ける（2.1・2.2） | 代わりに呼ぶ仕組み（watchdog）は作れるが、早く呼ぶとホストの処理（ネットワークなど）の途中でアプリが止まりうる。前の delegate の不具合はライブラリが無くても同じ結果になるので、**watchdog は入れず、2 回目を捨てるだけにする**のを勧める（7 章の 3） |
| D-7（後から差し替え） | 差し替えられるとライブラリの通知も届かない。もう一度入れれば戻るが、差し替えた側が転送しないと元のホストは鎖から外れる（3.3） | 入れる関数の 2 回目が「差し替えられていたら入れ直す」か「エラーを返す」かを決める。どちらでも、KVO でログに出せる。自動で入れ直すと、ホストと奪い合いになる |
| 第 1 部（スレッド） | 3 つのメソッドはどれも main スレッドで呼ばれた。前の delegate は completion をほかのスレッドから呼べる（asyncBg） | 転送の delegate の中は main で動くと見てよいが、包み（`Once`）はスレッドをまたいで呼ばれるので、鍵で守る。Swift 6 では system の completion が `@Sendable` でないので、包みは `@unchecked Sendable` にする必要があった（1b で形を決める） |

8.2 の 2 行のうち、残るもの:

- `responds(to:)` をシステムがいつ見るか（設定したときか、呼ぶたびか）は測っていない。転送の delegate は 3 つを常に実装するので、設計には影響しない
- `openSettingsFor` をシステムから呼ばせること（3.4）
- 実機と Unity（6 章）

## 6. 実機・Unity でしか確かめられないこと

| 項目 | 理由 | 誰が |
|---|---|---|
| 背景のアクションで、completion を呼ぶ時期とアプリが止まる時期（呼ばない・遅れて呼ぶ・すぐ呼ぶ） | シミュレーターでは遅れて呼んでも止まらなかった（2.2） | 1b の後に実機（利用者の許可を得て）、または `unity-native-plugin` の agent |
| 背景に移った直後の `willPresent`（2.1）が実機でも起きるか、その長さ | シミュレーターの背景の扱いは実機と違いうる | 同上 |
| Unity の `.mm`（`AppDelegateListener` の `kUnityWillFinishLaunchingWithOptions` / `didFinishLaunching`）から入れたときのコールドスタート。Unity 6000.4 が scene を使うか。通知パッケージとの順番 | Unity のビルドが要る | `unity-native-plugin` の agent（8.2 の Unity の行） |
| `openSettingsFor` | 3.4 | 1b のサンプルの UI テスト（シミュレーター） |
| iOS 26 の実機 | 手元に無い（README 7.2） | 確かめない |

## 7. 利用者に決めてもらうこと

| # | 決めること | 選択肢 | 推奨 |
|---|---|---|---|
| 1 | 誰も受けない、印の無い通知（前の delegate が無いか、そのメソッドを実装しない） | A: ライブラリが扱う（ライブラリの表示の選択肢とイベント）/ B: 転送の delegate が無いときと同じにする（前面では出さず、イベントも出さない） | **A**。1.x の通知（印が無い）とホストの通知は区別できない（3.5）。B では、更新の前に 1.x で予約した通知が、ホストの delegate が無いアプリで前面に出なくなる。A でホストの通知が前面に出るのは 1.x と同じ（1.x はすべてを出していた）。移行ガイドに書く |
| 2 | ライブラリの通知を前の delegate にも見せるか | A: 見せない / B: 見せる（表示の選択肢を合わせる） | **A**。見せると、前の delegate が completion を持ったときにライブラリの通知の `add` の完了まで止まり（2.1）、表示の選択肢を合わせる規則も要る |
| 3 | 前の delegate が completion を呼ばないとき | A: 何もしない（2 回目を捨てるだけ）/ B: 一定時間で代わりに呼ぶ | **A**。早く呼ぶとホストの処理の途中でアプリが止まりうる。結果はライブラリが無いときと同じ |
| 4 | 入れた後にホストが差し替えたときの、入れる関数の 2 回目 | A: 入れ直して成功を返す（循環の防止つき）/ B: エラーを返して入れ直さない / C: KVO で検出して自動で入れ直す | **A**。ホストのネイティブのコードが明示的に呼んだ要求なので従う。C はホストと奪い合いになる。どの案でも KVO で検出してログに出す |
| 5 | main 以外から呼ばれたときのエラーの番号 | 機能のエラーの次の番号に新しく足す / 共通の番号のどれかを使う | **新しく足す**（例 `NTK_NOTIFICATION_ERROR_NOT_MAIN_THREAD`）。Android の Notification のエラーに当たるものが無い。第 1 部で番号を決める |
| 6 | 起動の後に呼ばれたとき | A: 成功を返し、ログに出す / B: 別の番号を返す | **A**。関数の中で正しく判定できない（4 章）。前面の表示と、その後の通知のイベントは受けられる。取りこぼすのはコールドスタートのタップだけで、マニュアルに書く |
| 7 | 印のある push | A: ライブラリの通知としない（push はいつも前の delegate へ）/ B: 印を信じる | **A**。ライブラリは push を出さないので、印のある push は送る側の誤りか偽り |
| 8 | ライブラリの通知の `didReceive` の completion を呼ぶ時期 | A: イベントを受け手に渡した（または保った）後に、main で呼ぶ / B: その場で呼ぶ | **A**。背景のアクションで、利用者のコールバックが動く前にアプリが止まるのを避ける（6 章で実機で確かめる） |
| 9 | ホストが自分の delegate から応答を渡す C の関数（D-7 の案 C の一部。起動の後に入れるホスト向け） | 2.0.0 で足す / 足さない | **足さない**。起動の処理で入れる契約で足りる。Unity の agent の結果で入れる時期が間に合わないと分かったら足す（後から足しても互換は壊れない） |

## 8. 残っていること

- C ABI の設計書 第 1 部の通知の delegate の節（5 章と 7 章の決定）
- 3 章の組み合わせの表を、1b の転送の delegate の単体テストにする（`UNUserNotificationCenter` を直接は作れないので、転送の判定と包みを分けてテストする形を 1b で決める）
- 6 章の実機と Unity の確認
