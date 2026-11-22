# レビュー結果

- 日付: 2026-10-31
- 対象: `designs/2026-10-31-ios-c-abi-swift-api-design.md`（段階 1b の Swift の API の設計書、v3。レビュー v2 の SR2-1〜SR2-11 を反映したもの）
- 判定: **要修正**（A 1 件。直し方は数行）
- 別モデルによる独立レビュー: 実施済み。これまでと同じ 2 者で並行。範囲は「SR2 が書いたとおりに直ったか」「新しい S-P28 と書き直した所が正しいか」「v3 で入った新しい A」に絞った。Claude のサブエージェントは Xcode 26.3 の swiftc 6.2.4（Swift 6）で試した。Codex（設定のモデル）は 1 回目の依頼で「何も実行しない」と書いたため読むコマンドも使わずに止まり、「読むだけのコマンドは使ってよい」と書き直して頼み直した
- Codex: 新しい A は 0。SR2-2・SR2-3 は直った。S-P28 に二重の再開や完了の抜けは無い
- Claude: SR2-2・SR2-3・SR2-4・SR2-7・SR2-8・SR2-10・SR2-11 は直った。SR2-5・SR2-6・SR2-9 はほぼ直った（下の C）。SR2-1 は半分（下の A）

区分: A = 決める前に必ず直す、B = 直す、C = 軽い。「対応」は設計書の v4 で埋める。

## A

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| SR3-1 | Claude A-1 | S-P28、8.5.6 の「順」、8.9、9 章 | プロジェクトは `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = NO` なので、nonisolated の `async` の関数は呼ばれるとまず汎用の executor へ移ってから本体を動かし、列に積むのはその後になる。「呼んだ時点で同期に積む」は callback 版にしか当たらない。8.9 と第 1 部 5.6 は C ABI が main の `Task` の中で `async` 版を待つとしているので、C から `register(A)` → `remove(A)` と呼んでも A が残りうる。MainActor の `Task` を 8 つ順に起こして `async` 版を待つ形を 300 回試すと、257 回で順が違い、`nonisolated(nonsending)` にすると 0 回だった | (1) 8.9 と 9 章に「category は callback 版を main のブロックの中で呼ぶ（同期に積む）」と書く、(2) 2 つの `async` 版を `nonisolated(nonsending)` で宣言し、最初の中断の前に積むと書く、のどちらか、または両方。8.5.6 の「順」を「callback 版は呼んだ時点、`async` 版は同じ `Task` の中の順（(2) なら呼んだ側の executor の順）」に直す。UT-28 に「main の `Task` を続けて起こして `async` 版を呼ぶ」場合を足す（壊し方は `nonsending` を外す）。9 章の UseCase の列を「`enqueue` を足した UseCase」に直す | v4: 両方の直しを入れた。(1) 8.9 と 9 章に「category は C ABI の受け口が callback 版を main のブロックの中で呼ぶ（同期に積む）」と書いた。(2) 2 つの `async` 版を `nonisolated(nonsending)` で宣言し、最初の中断の前に積むとした（S-P28、8.5.6 の届き方、付録 A）。8.5.6 の「順」を callback 版・`async` 版・C ABI に分けて書き直した。UT-28 に main の `Task` を 8 つ続けて起こす場合（300 回。壊し方は `nonsending` を外す）と C ABI の形を足した。9 章の UseCase の列を「同期の `enqueue` を足した UseCase」にした |

## C（Claude）

| ID | 所 | 指摘 | 対応 |
|---|---|---|---|
| SR3-2 | S-P21 の D、8.7.1、4.2 の (1) | 「型の中に置くなら `nonisolated private static let`」は generic の型では組めない（`NotificationEventHub<Event>`）。「generic の型はファイルの `private let` だけ」と書く | v4: S-P21 の D、8.7.1、4.2 の (1) に「generic の型はファイルの `private let` だけ。`nonisolated private static let` は generic でない型の中だけ」と書いた |
| SR3-3 | 15.2 の T-01 | 「`Log` の deprecated と `os.Logger` への送り」が v2 の言い回しのまま。Y1 に合わせて「deprecated（中身は `print` のまま）」に | v4: T-01 を「`Log` の deprecated（中身は `print` のまま。Y1）」に直した |
| SR3-4 | S-P27 | `IosNotificationManager` の `private let permissionHelper` と internal の `init(repository:permissionHelper:)` が deprecated の型の名前を使うので、ライブラリの中に警告が出る（テストもこの `init` を使う）。プロパティと引数を消し、テストの作り方を直すと書く | v4: S-P27 に、`private let permissionHelper` と `init(repository:permissionHelper:)` の引数を消し、テストは `init(repository:)` で Mock を渡す形に直すと書いた |
| SR3-5 | S-P23、SA-18 | Clipboard のテスト（`XCUIApplication().launch()` で直に起動）と人がホームから起動したときは、前に残した試験の形を読む。「基底を通らない起動は前の形を読む（Clipboard には効かない）」と書くか、通知のテストの後片付けで `none` に戻すと書く | v4: SA-18 に、基底を通らない起動は前の形を読むので、通知のテストは後片付けで `none` の形で起動し直してファイルを戻すと書いた |
| SR3-6 | 8.5.6 の「完了」 | port の `completion` は `@Sendable` でどのスレッドからでも呼ばれる。「Manager が `DispatchQueue.main.async` で 1 回積む」と書く | v4: 8.5.6 の「完了」を、列は port の `@Sendable` の `completion` を呼び、Manager が `DispatchQueue.main.async` で利用者の完了を 1 回積む、に直した |
| SR3-7 | 17 章、14 章 | DoD が「MS-01〜MS-13」で MS-14 が入っていない。14 章の表で MS-14 が MS-13 の前にある | v4: DoD を MS-01〜MS-14 にし、14 章の表で MS-14 を MS-13 の後に並べ直した |

## 問題なしとされた所

- Claude: S-P28 の protocol extension の既定の実装（`enqueueCategoryChange` を持たない今の利用者の型が組める。`any NotificationRepository` から呼ぶと `Impl` の上書きが選ばれる。既定の実装の中の `Task` は Swift 6 の complete で組める。`withCheckedContinuation` の本体は同期に動く）。S-P25 の Foundation の型の辞書（`as? Bool`・`as? Int`・`as? Double`・`as? UInt64` などが今の経路と同じ結果。`init` の振り分けも正しい）。S-P21 の D と Y1 の筋（ファイルの `private let logger` は generic の型・`@MainActor` の型・nonisolated の関数・`deinit` で組める）。S-P23 の筋。v3 で増えた A は SR3-1 のほかに無い
- Codex: SR2-2（同じ `Mutex` の中で足す・印を見る・起こす権利を取ると、空を見る・印を下ろすを行うので、取り残しも並行の取り出しも起きない）、SR2-3（引数なしの起動でも保存したファイルを読み、受けたプロセスの経路を確かめる）、S-P28（二重の再開や完了の抜けは無い。既定の port の順は文書に書いてあり、Manager の main への配送とも両立する）
