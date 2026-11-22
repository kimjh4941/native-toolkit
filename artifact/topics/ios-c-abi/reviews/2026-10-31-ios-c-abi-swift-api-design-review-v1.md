# レビュー結果

- 日付: 2026-10-31
- 対象: `designs/2026-10-31-ios-c-abi-swift-api-design.md`（段階 1b の Swift の API の設計書、初版。1076 行）
- 判定: **要修正**（A 2 件を直し、直した所を再レビューする）
- 別モデルによる独立レビュー: 実施済み。Claude のサブエージェント（観点: 入力に対する抜けと正しさ。B-1・B-2 は `swiftc` 6.2.4 で型検査して確かめた）と Codex（設定のモデル。観点: 並行・隔離・寿命）の 2 者で並行。第 1 部と同じく観点が 2 つに分かれるので 2 者にした。どちらも読むだけ。第 1 部の 0.1 で絞った約束の範囲を前提にした

区分: A = 決める前に必ず直す、B = 直す、C = 軽い。「対応」は設計書の v2 で埋める。

## A

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| SR-1 | Codex A | S-P14、8.5.6 | actor だけでは category の更新全体を直列にできない。`notificationCategories()` の `await` の間に別の要求が入り、両方が古い集合を読むと、後の書き戻しで変更が失われる。今の Manager の要求ごとの `Task` も呼んだ順を保たない | Manager の同期の受け付けで FIFO に積み、1 つの処理が読み取り・変更・書き戻し・確認まで終えてから次を処理する。完了は main に 1 回だけ届ける | v2: S-P14 を書き直した。プロセスで 1 つの `NotificationCategoryQueue` に、Manager の口が同期に（`Mutex` の中で）FIFO に積み、1 つの取り出しの `Task` が読み取り・変更・書き戻し・確認を終えてから次を取り出す。完了は main に 1 回。actor 案は B として残し、再入で失われる理由を書いた（8.5.6、9 章、UT-28） |
| SR-2 | Codex A | S-P13、付録 A | 一覧の `async` の戻り値（`ScheduledNotification`・`ActiveNotification`）は `[AnyHashable: Any]` を持つ `Sendable` でない型で、nonisolated の `async` を C ABI の main actor の `Task` から `await` すると、Swift 6 の境界を越えられない | 結果を `Sendable` な値に直すか、独立した結果を返す `sending` の戻り値を下の層まで設計する | v2: 新しい S-P25。`ScheduledNotification`・`ActiveNotification` の userInfo を値の木で持ち `Sendable` にし、`userInfo` は計算プロパティで読み方を保つ。`sending` を全部の層に付ける案と、一覧に `async` 版を足さない案を比べた。UT-32、8.5.2、付録 A |

## B

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| SR-3 | Codex B | S-P2、S-P22、6.3.2、8.6 | 箱を閉じるときの処理（hook）の隔離が決まっていない。どのスレッドからでも呼ぶ規則と、main で token や completion を付ける規則がつながっていない。hook が main actor を継ぐと、背景からの取り消しで落ちる | hook を nonisolated `@Sendable` とし、main へ積むことだけをさせる。token の操作と利用者の completion は main で行い、取り消し済みの箱への後付けも同じ経路を通す | v2: 6.3.2 に「閉じたときの処理は nonisolated の `@Sendable` で、main に積むだけ。token の操作と完了は main」「閉じた箱への後付けも同じ経路」を足した。6.2、S-P22、UT-30（TSan） |
| SR-4 | Claude B-1 | S-P13・S-P14・S-P19、付録 A、3.3 | `async` 版を足すと、`async` の文脈にある今の呼び出し（`setBadgeCount(1)`、`registerCategory`、`removeCategory`、`show`・`update`・`schedule`、`requestPermission()`）が `async` 版に決まり、組めなくなる（型検査で確かめた）。「今の呼び方のまま組める」「1b はほかの動作を変えない」に反する | 3.3 に破壊的変更として載せるか、`async` 版の名前かラベルを分ける。今の呼び出しを `async` の文脈に置いた型検査のテストを 13 章に足す | v2: 新しい S-P26（A: 同じ名前で破壊的変更として 3.3 に書く／B: 名前を分ける／C: ラベルを分ける／D: `async` 版を足さない）。推奨は A。3.3 に組めなくなる呼び出しを書き、UT-31 で型検査し、T-21 で一覧を写す |
| SR-5 | Claude B-2 | S-P1、付録 A | public な enum に internal な case は置けず、`PresenterSelection` の宣言が組めない（型検査で確かめた） | `public struct PresenterSelection: Sendable` にして中に internal な enum を持ち、`.firstActiveScene`・`.foreground` を static な値、`viewController(_:)` を static な関数にする（呼ぶ側の書き方は変わらない） | v2: S-P1 を `public struct PresenterSelection`（internal の enum、static の値と関数）に直した。6.3.1、付録 A |
| SR-6 | Claude B-3 | S-P21、8.7.1、18.1 の 10 | S-P21 は決めた P1-18（capi は利用者の値を `.private`）を決め直しているが、capi は `Log` を使わず `os.Logger` を直に呼ぶので「文字列を受けるので付けられない」は当たらない。選択肢も足りない | capi は P1-18 のまま。`IosLibrary` に案 D（TAG ごとの `static let logger` で `Logger` を直に呼び `privacy:` を付ける）を足す。`Log` を public のまま deprecated にする案も比べる | v2: S-P21 を書き直した。capi は P1-18 のまま。`IosLibrary` は案 D（型ごとの `static let logger` で `os.Logger` を直に呼び `privacy:` を付ける。164 か所）、`Log` は public のまま deprecated（案 Y）と、internal にする案 X を比べた。8.7.1、18.1 の 10、T-02 |
| SR-7 | Claude B-4 | UT-16、8.7.2、S-P7 | `ShareError` の文言は URL やパスを含み、UI テストもその全文を比べる。UT-16 の「入力の値を含まない」と「4 つの文言は今と同じ」は両立しない。`IosShareManager.swift:81` のエラーのログが URL とパスを出すのに 8.7.2 に無い。サンプルの `DialogSampleView.swift:169,198` も入力の値とパスワードをログに出す | UT-16 を「`ShareError` の 4 つは例外」と書き直す。ログは case 名だけにし、8.7.2 に足す。サンプルの 2 か所も足す | v2: UT-16 を「`ShareError` の URL・パスを含む 3 つと `noValidItems` は今の文言のまま」に直した。`IosShareManager.swift:81` とサンプルの `DialogSampleView.swift:169,198` を 8.7.2 に足した。10.1 に文言をログに出さないことを書いた |
| SR-8 | Claude B-5 | 8.2、8.5.5、RK-06、3.3 | port の破壊的変更（`ShareRepository.present(content:presenter:)`、`NotificationRepository.openNotificationSettings() async -> Bool`）が 3.3 に無い。公開の `NotificationPermissionHelper` の扱い（DocC が消す `.unknown` を挙げる、拒否を投げる、port が `async` になると同期の口が組めない）も無い | 3.3 に足し、helper をどうするかを決めて書く | v2: 3.3 に 2 つの port の破壊的変更を足した。`NotificationPermissionHelper` は新しい S-P27（deprecated で今の動作のまま、`openNotificationSettings()` は `Task` で包む）。8.5.5、6.1、付録 A |
| SR-9 | Claude B-6 | 8.3.3、8.5.3 | `NotificationRepositoryImpl.swift:46-47` は `removePendingNotificationRequests` を `makeUNContent` より先に呼ぶので、`makeUNContent` の前で予約したキーを拒むと、拒んだのに今の予約が消える（P1-9 の「拒む」に反する） | 検査（予約したキーと property list）を、消す前と入口の最初に置く。UT-17・UT-18 に `update` を足す | v2: 8.3.3・8.5.3 で、検査を入口の最初（`update` の今の予約を消す前）に置いた。UT-17・UT-18 に `update` で今の予約が消えないことを足した |
| SR-10 | Claude B-7 | 13.3、S-P23 | 足すボタンが識別子の照合（I1a〜I1d。設計書 5.1 と完全に一致するか比べる）を壊す。SA-06 で起動の処理をイベントの口に替えると、N25〜N33 が今の受け手を通らなくなる | I1a〜I1d と UI テストの設計書 5.1 の一覧の更新を 13.3 に足す。今の受け手の経路を、起動の引数で切り替えて残す | v2: S-P23 に起動の引数 `-ntkSampleLegacyReceivers` と N43〜N45（今の受け手の経路のタップ・テキスト入力・コールドスタート）を足した。13.3 に UI テストの設計書 5.1 の一覧と I1a〜I1d、3.7 の照合の更新を足した |
| SR-11 | Claude B-8 | MS-07、N40、SA-11、SA-13 | システムがアプリ内の通知の設定を出すのは `.providesAppNotificationSettings` を付けて権限を求めたアプリだけ（1a では付けていた）。サンプルは付けていないので、MS-07 が OS のせいでない理由で「呼ばせられない」と結論しかねない | SA-11 か SA-13 で、この選択肢を付けて求めると書く | v2: 8.5.4 と SA-13 で `.providesAppNotificationSettings` を付けて求めると書き、MS-07 と N40 は新しく入れたアプリでこのボタンから先に求める |

## C（Claude）

| ID | 所 | 指摘 | 対応 |
|---|---|---|---|
| SR-12 | 5.1 | ブリッジにしか無い既定の値（`repeats=false`、`notifyOnEntry=true`、`notifyOnExit=false`、知らない `interruptionLevel` を `.active`）が表に無い。第 2 部に送ると書く | v2: 5.1 に B16 を足し、8.9 で第 2 部に送った |
| SR-13 | S-P7 | 使われていない `attachmentInvalidURL` を残している。`ClipboardFailureDetail` を `FailureDetail` の typealias にする案が無い | v2: `attachmentInvalidURL` を消す case に足した。typealias は採らない: `ClipboardFailureDetail` は internal の `debugMessage` と、それを取る public の `init(domain:code:debugMessage:)` を持ち形が違う（S-P7 に理由） |
| SR-14 | S-P24、15.1 | 「C6 を先にしてよい」が C5 への依存（T-19→T-16、N38 は印に依存）と合わない。C1 で測る MS-01 は C2 で足す SA-02・SA-03 を使う | v2: 15.1 を「C6 は C5 の後にコミット（T-17・T-18 は先に作ってよい）」に直した。MS-01・MS-02 を C2（T-09）に移し、結果で C1 の部品を直すときは C2 で直すと書いた。Dialog の UI テストを T-22 に分けた |
| SR-15 | 15.2、17 章 | 型つき throws を Xcode 26.3 で読めるか（`typecheck-module-from-interface`）がタスクと DoD に無い | v2: T-21 と 17 章の DoD に、Xcode 26.3 の `typecheck-module-from-interface` で 3 つのスライスを読むことを足した |
| SR-16 | 6.3.3、6.3.4 | 第 1 部 5.13.1 の補い（`present` の直後に `presentingViewController` を見る）が手順に無い。UIKit が断った ViewController がいつ解放されるかを測る項目が無い | v2: 6.3.3 の段 3 に `presentingViewController` の補いを足した（MS-01 で直後に設定されなければ外す）。MS-03 に UIKit が断った ViewController の解放の時期を足した |
| SR-17 | 8.5.5、6.1、9 章 | `openNotificationSettings(presenter: .firstActiveScene)` の振る舞いが無い。9 章の新しい UseCase 2 つが 6.1 に無い。前面の判定を Manager と UseCase のどこで行うかが無い | v2: 8.5.5 に `.firstActiveScene` の振る舞いを書いた。6.1 に 2 つの UseCase と `NotificationPresentationGate` を足し、8.5.4 に判定は Presentation の gate、UseCase はデータの操作だけと書いた |
| SR-18 | S-P14 | `NotificationCategoryStore` はプロセスで 1 つにする必要がある（`NotificationRepositoryImpl` は public の `init` で何個でも作れ、`NotificationPermissionHelper.shared` も自分の分を作る） | v2: 列をプロセスで 1 つの `static let` にした（S-P14、8.5.6、UT-28） |
| SR-19 | 11 章の S-6 | 第 1 部は表示の口すべてに箱を求めるが、Share・権限・設定の画面は箱を取らない（取り消しが無いので妥当）。違いと理由を書く | v2: 11 章の S-6 の行と 18.1 の 12 に、箱の引数は取り消しのある Dialog と Clipboard だけで、ほかは口の中で作る理由を書いた |
| SR-20 | 8.1.4 | 今の口の失敗の文言を `"Failed to get root view controller"` のまま保つこと、今の口で `dismissedBySystem` になったとき何も呼ばないことを書く | v2: 8.1.4 に、前面が無いときの文言は今の `"Failed to get root view controller"` のまま、UIKit が断ったときは新しい固定の文言、今の口で `dismissedBySystem` のときは何も呼ばないことを書いた |
| SR-21 | 3.3 | 今の Share の callback の `errorMessage` が `presentationFailed` と `activityFailed` で変わることが無い | v2: 3.3 に Share の今の callback の `errorMessage` の変わり方（表示の失敗と活動の失敗）を足した |
| SR-22 | 8.5.2、S-P23 | `getScheduled` などを `async`（投げない）にするのは `ios.md:87` の「必ず `async throws`」と違う。サンプルで今のボタンを callback 版のまま残すのは `ios.md:89` の例外。どちらも `ios.md` に書く | v2: 4.2 の `ios.md` に足すものに (4) として 2 つの例外を足した。8.5.2、S-P23 |
| SR-23 | S-P8 | deprecated の受け手だけを使う利用者では、hub が 32 件を保ち続け、超えるたびに捨てたログを出す | v2: S-P8 と 8.4.2 に、捨てたときのログはプロセスで最初の 1 回だけ `.info`、以後は `.debug` と書いた |
| SR-24 | S-P11 | `integer(Int64)` では Int64 を超える `UInt64` の `NSNumber` を表せない。扱いを決める | v2: S-P11 に `unsignedInteger(UInt64)` を足し、`NSNumber` の変換の順を書いた。付録 A、UT-18 |
| SR-25 | 3.4 | 転送を入れた後も `cancelAll` と `removeAllDelivered` はホストや Unity のパッケージの通知まで消す。DocC と 3.4 に書く | v2: 3.4 に足し、8.9 で C のヘッダーの Doxygen にも書くとした |

## 問題なしとされた所

- Codex: 公開の `@MainActor @Sendable` の presenter の closure、イベントを配るときの写しと呼ぶ直前の登録の確かめ、`Sendable` な userInfo の木、状態を持たない Logger と伏せ方。C ABI の `RELEASED` の後の状態の確かめを守る前提で、use-after-release は見つからなかった
- Claude: 第 1 部の S-1〜S-16 は SR-19 を除いて具体的な口で満たす。7 章の対応表でブリッジの約束は失われていない。プライバシーの棚卸しは grep と一致（FileTimestamp だけ）。テストの件数、行番号、`Log` が public であること、`BUILD_LIBRARY_FOR_DISTRIBUTION=YES` は実物と合う。`@MainActor` の hub を nonisolated の manager に持たせる形は組めた
