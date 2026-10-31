# レビュー結果

- 日付: 2026-10-31
- 対象: `designs/2026-10-31-ios-c-abi-swift-api-design.md`（段階 1b の Swift の API の設計書、v2。レビュー v1 の SR-1〜SR-25 を反映したもの）
- 判定: **要修正**（A 1 件を直す）
- 別モデルによる独立レビュー: 実施済み。1 回目と同じ 2 者（Claude のサブエージェント: 抜けと正しさ。Xcode 26.3 の swiftc 6.2.4 で型検査した。Codex（設定のモデル）: 並行・隔離・寿命）で並行。範囲は「SR が書いたとおりに直ったか」と「新しく足した・変えた S-P が正しいか」に絞った。第 1 部の 0.1 の約束の範囲を前提にした
- v1 の確かめ: Claude は SR-1 を直っていない、SR-2・SR-6・SR-10 を半分、SR-4・SR-22 を細部のずれ、ほかを直ったとした。Codex は SR-1 を「更新が失われる所と同期の入口の順は直ったが、止め方の競合が残る」、SR-2・SR-3 を直ったとした

区分: A = 決める前に必ず直す、B = 直す、C = 軽い。「対応」は設計書の v3 で埋める。

## A

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| SR2-1 | Claude A-1 | S-P14、8.5.5、9 章、6.1 | 8.5.6 は「Manager の口が同期に積む」とするが、列は Data 層にあり、port（`registerCategory(_:) async`、`removeCategory(identifier:) async`）と UseCase（`execute(_:) async`）は今のまま。Manager → UseCase → port を通る限り、積むのは `Task` の中になり、呼んだ順を保てない（SR-1 の原因が残る）。`async` 版の完了を列の完了に結び付ける方法も無い | (1) port と UseCase に同期で積む口（例 `enqueueCategoryChange(_:completion:)`）を足し、port の破壊的変更として 3.3 に足す、または (2) Manager が列を直に持つ例外を `ios.md` に書く。どちらでも、`async` 版は `withCheckedContinuation` で同期の積みを包み、順は呼んだ時点で決めると書く | v3: 新しい S-P28。推奨 A は、port に同期の `enqueueCategoryChange(_:completion:)`（既定の実装は今の `async` の口を `Task` で呼ぶ。自分で実装した port は組めたまま、順は保たない）と UseCase に同期の `enqueue(_:completion:)` を足し、Manager → UseCase → port → 列と呼び出しの中で同期に届かせる。`async` 版は `withCheckedContinuation` の本体で同じ積みを呼び、順は積んだ時点で決まる。B（Manager が列を持ち `ios.md` に例外）、C（v2 のまま）と比べた。8.5.6、6.1、3.3、付録 A、UT-28、T-23 |

## B

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| SR2-2 | Codex B、Claude B-5 | 8.5.6、UT-28 | 列の止め方の手順が決まっていない。取り出しが空を見た後に新しい要求が積まれ、積む側は「走っている」と見て起こさず、取り出しが印を下ろして終わると要求が残る。「空から 1 件になったら起こす」だと、処理の途中で積んだ要求でもう 1 つの `Task` が起きうる | 「走っていなければ起こす」だけにし、取り出しは同じ `Mutex` の中で空を見たときに印を下ろす。積む側も、足す・印を見る・起こす権利を取るを一度に行う。UT-28 に終わり際と処理の途中で積む場合を足す | v3: 8.5.6 に、積む側は 1 回の `Mutex` の中で足す・印を見る・起こす権利を取る、取り出し側は同じ `Mutex` の中で空を見たら印を下ろす、と書いた。「空から 1 件で起こす」はやめた。UT-28 に処理の途中と終わり際に積む場合を足した |
| SR2-3 | Codex B、Claude B-4 | S-P23、N45、N36 | コールドスタートでは `terminate()` の後にバナーのタップでシステムが起こすので、`launchArguments`（`-ntkSampleLegacyReceivers`、`-ntkSampleDelayListener`）は渡らない見込み。N45 は今の受け手の経路を通らないまま通りうる | 引数で起動したときに印をファイルか `UserDefaults` に残し、次の起動でも読み、普通に起動したら消す。受けたプロセスが今の受け手の経路を使ったことも確かめる。シミュレーターで 1 回確かめて 13.2 に書く | v3: SA-18 を足した。試験の形を `-ntkSampleTestMode` で受けてアプリのコンテナのファイルに残し、引数の無い起動でも読む。UI テストは毎回形を明示する。受けた経路（`path=hub` / `path=legacy`）と読んだ形を `accessibilityValue` に出し、N36・N43〜N45 で確かめる。MS-14 で引数が渡らないことを 1 回確かめる |
| SR2-4 | Claude B-1 | S-P25、S-P8、3.3 | 値の木から Swift の `Int64`・`Bool`・`Double` で辞書を作り直すと、`as? Int`・`as? Double`・`as? Bool` が `nil` になる（今は `NSNumber`。型検査で確かめた）。deprecated の今の受け手も同じ。「property list でない値は `init` で落ちる」が、クラッシュとも捨てるとも読める | 計算プロパティと今の受け手に渡す辞書は `NSNumber`（真偽値は `kCFBoolean`）・`NSString`・`NSDate`・`NSData`・`NSArray`・`NSDictionary` で作り直すと書く。UT-18 に往復を足す。`init` は「property list でない値と String でないキーは捨て、ログに出す」と書く | v3: S-P25 と 3.3 に、作り直す辞書を `kCFBoolean*`・`NSNumber`・`NSString`・`NSDate`・`NSData`・`NSArray`・`NSDictionary` で作ること（今の受け手も同じ）、`init` は property list でない値と `String` でないキーを捨てて件数をログに出すことを書いた。UT-18 に `as?` の往復を足した |
| SR2-5 | Claude B-2 | S-P21 の D、8.7.1、6.1 | `category: TAG` は組めない（`TAG` はインスタンスの `private let`）。型ごとの `private static let logger` は generic の型（`NotificationEventHub<Event>`）で組めない。`@MainActor` の型ではこの static が main に隔離され、`nonisolated cancelLoad` や `deinit` から参照できない（型検査で確かめた） | 規則を「ファイルの `private let logger = Logger(…, category: "<型名>")`、または `nonisolated private static let`」に直し、`ios.md` にも書く（どちらも組めることを確かめた） | v3: S-P21 の D、6.1、8.7.1、4.2 の (1) を「ファイルの `private let logger = Logger(…, category: "<型名>")`、型の中なら `nonisolated private static let`」に直した |
| SR2-6 | Claude B-3 | S-P21 の Y、3.3 | `Log` を `.public` で `os.Logger` へ送ると、統合ログに入って Console や sysdiagnose から読める（今の `print` より見えやすい）。ブリッジは 1b の間もパスワードを出し続ける。重さを OS のレベルに写す規則が無い | Y では中身を `print` のままにするか、`.private` にして `d→debug`・`i→info`・`w→default`・`e→error` の表と見え方の変化を 3.3 に書く | v3: S-P21 の `Log` の扱いを X・Y1・Y2・Y3 にした。推奨は Y1（deprecated、中身は今の `print` のまま、見え方も同じ）。Y3（v2 の `.public` で送る形）は統合ログに入って見えやすくなる理由で採らない。3.3 の行も直した |

## C（Claude）

| ID | 所 | 指摘 | 対応 |
|---|---|---|---|
| SR2-7 | 3.3、S-P26 | 組めなくなる呼び出しの一覧が実際と少し違う（`trigger` を書かない `show` は壊れない。`await` を含む `Task` の closure の中は壊れる）。「`async` の関数の中」を「`async` の文脈（`await` を含む closure を含む）」に | v3: S-P26、3.3、8.5.2 を「`async` の文脈（`await` を含む closure を含む）」にし、`trigger` を書かない `show(content:)` は壊れないと書いた |
| SR2-8 | 6.1、17 章、18.1 | 「4.2 の 3 つ」「3 つの書き足し」が 4.2 の (4) と T-01 の「4 つ」に合わない。18.1 の番号の並び | v3: 6.1 と 17 章を「4.2 の 4 つ」に直し、18.1 の行を 11、12 の順に並べ直した |
| SR2-9 | S-P27 | Manager は中で `permissionHelper` を使っているので、helper を deprecated にするとライブラリの中で警告が出る。拒否の文言を Manager か UseCase に移し、helper を使わない形を書く | v3: S-P27 に、Manager は中で helper を使わず、今の `requestPermission(options:completion:)` は UseCase を呼び、拒否は `permissionDenied` の文言で今と同じ値を返すと書いた（T-18） |
| SR2-10 | UT-28 | `NotificationRepositoryImpl` は center を差し替えられない。列に internal な center の抽象を渡す形を書く | v3: 6.1 に internal の center の抽象 `NotificationCategoryCenter` を足し、UT-28 は偽物を渡す形にした |
| SR2-11 | S-P11、10.2 | `NSNumber` の振り分けで実数を整数より先に見ると書く。10.2 の「C の受け口は callback 版」と 8.9・S-P13 の「`async throws` 版を待つ」が食い違う | v3: S-P11 に `NSNumber` の振り分けの順（真偽値 → 実数 → `Int64` → `UInt64`）を書いた。10.2 を「`CancellationError` は C の値に写さない（Dialog などは callback 版、通知の `async throws` 版は受け口が `Task` を取り消さない）」に直し、8.9 と合わせた |

## 問題なしとされた所

- Claude: S-P1（iOS 18 の UIKit と library evolution で組め、呼ぶ側の書き方は enum と同じ）、S-P25 の形（`init` は今の引数のまま、`userInfo` を計算プロパティにして `Sendable`。今の呼び出しもそのまま組める。残りは SR2-4 だけ）、S-P26（黙って意味が変わる経路は無い。ブリッジの呼び出しはすべて同期の文脈）、S-P27（同期の `openNotificationSettings()` を `Task` で包む形は今と同じ動作）。v2 で増えた A は SR2-1 のほかに無い
- Codex: 完了を main に 1 回だけ積む規則、category の処理は投げないので取り出しが抜ける筋は無い、計算 `userInfo` の作り直しの重さは問題にならない（C ABI は値の木を使う）、S-P26 のソースの破壊は書かれている
