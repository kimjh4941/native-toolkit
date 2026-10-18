# レビュー結果

- 日付: 2026-10-18
- 対象ファイル: `artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md`（レビュー v2 を反映した版。コミット前）
- トピック名: ios-c-abi（UI テストの設計書。段階 0）
- 判定: **要修正**（区分 A が Claude 1 件、Codex 3 件）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行）
- あわせて、レビューで「確かめていない」とされた Xcode の振る舞いを、シミュレーターで確かめた（`results/2026-10-18-ios-c-abi-stage0a-spike-result.md` の 8 章）

## v2 の反映の確認

両方とも、v2 の項目はほぼすべて反映済みとした。件数（新規 77、全体 102）、識別子の数（新規 70）、U-n の参照に食い違いは無い。一部とされたのは、A-10（印の型まで `fileprivate` にしたのでコンパイルが通らない → A-16）、A-11（監視の中の失敗の記録と `continueAfterFailure` → B-17）、B-N2（`OpenNotificationSettings` と `RequestPermission` が印なしで押せる → B-3）。

一段目の評価（Claude）: サンプルは起動のときに delegate を入れて受け手を設定するだけで、どの画面にも `onAppear` / `.task` が無いので、テストが頼まないかぎりクリップボード・通知・ファイルに触れない。`-only-testing` で名指ししたメソッドとそのクラスの setUp / tearDown だけが走るが、バンドルを読み込んだ時点で走るコード（`NSPrincipalClass`、`XCTestObservationCenter`、`+load`）は名指しと関係なく走る。

## シミュレーターで確かめた事実（判断の根拠）

- 存在しない identifier を `-only-testing:` に混ぜても、**黙って無視され exit は 0**
- `setUpWithError` で `XCTSkip` を throw しても、**`tearDownWithError` は走る**
- `self.name` は `-[<クラス> <メソッド>]`。`.xcresult` の `nodeIdentifier` は `<クラス>/<メソッド>()`、列挙の identifier は `<ターゲット>/<クラス>/<メソッド>()`
- 列挙には、テストのメソッドを持たない基底クラスも 1 件として出る。シミュレーターでの列挙は端末を起動しなかった（実機は試していない）
- JSON は同期するグループに置くだけでテストのバンドルに入る

## 仕組みの直し（v1・v2 に続き、同じ種類が 3 回目）

v3 の A-1（Claude）・A-15・A-17（Codex）と B-1・B-2・B-5 は、いずれも「一段目（ランナーの選び方）が、宣言の表が正しいこと・名指しが効くことを前提にしているのに、その前提を照らしていない」という種類である。テストのコードではなく、ランナーの照合で次のように閉じる。

1. **宣言の下限をクラスで持つ**: ランナーが、クラスごとの最低の区分（`ClipboardUITests` は `clipboard`、`ShareUITests` は `sharesheet`、通知のイベントとコールドスタートのクラスは `systemui` など）を持ち、宣言の表がそれを満たすことを純粋な関数で照らす
2. **既存のクラスを固定する**: 既存の `ClipboardUITests` はメソッドの名前の一覧とファイルの中身のハッシュを固定し、変わったらランナーが止まる（新しいテストは新しいクラスに書く）。**雛形の 2 クラス（`testExample`、`testLaunchPerformance`、`testLaunch`）は役目が無く、`testLaunch` は UI の構成を切り替えるので消す**（全体は 102 から 99 件）
3. **実機では列挙しない**: 列挙は同じコミットのシミュレーターで行い、その一覧を実機の選び方に使う（実機の列挙がランナーを入れて起動しないことは確かめられていないため）
4. **名指しの前後を照らす**: 実機で xcodebuild を呼ぶ直前に、メソッドの名指しが 1 つ以上あることを確かめ、無ければ止める（空のまま呼ぶと全件が流れる）。流した後、**結果のテストの集合が名指しの集合とちょうど同じ**であることを照らし、1 件でも欠ける・多い・重なるときは実機の実行全体を止める
5. **setUp より前の入口を塞ぐ**: 基底で `setUp()`、`setUp() async throws`、`setUp(completion:)`、`invokeTest()` を `final override` にする。ソースの検査で `NSPrincipalClass`、`XCTestObservationCenter`、`class func setUp`、`defaultTestSuite`、`+load` を禁じ、UI テストのターゲットに `.m` / `.c` を置かせない
6. **シミュレーターか実機かを fail-closed で決める**: `simctl list -j` にある UDID だけをシミュレーターとし、ほかは実機として扱う。シミュレーターでは `NTK_DEVICE_ALLOW` を渡さず、外から受け継いだ値は消す
7. **単体テストはシミュレーターだけで流す**

## 指摘と対応

### 区分 A

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| A-1 | Claude | 既存の 3 クラスは本体が `app` を直接使うので二段目が及ばず、宣言を少なく書いても捕まらない。`ClipboardUITests` に宣言 `[]` のテストを足すと、実機の既定の実行で私物のクリップボードを書き換えうる | 上の 1・2。7 章に変異「`ClipboardUITests` に宣言 `[]` のテストを足す」「固定したファイルを変える」を足す |
| A-15 | Codex | 実機を宛先にした列挙が、ランナーを端末に入れて起動しないことを確かめていない。列挙は許可の一覧を作る前に行う | 上の 3。`--dry-run` は実機に触れない（シミュレーターの列挙と表だけで選ぶ） |
| A-16 | Codex | 印の型・init・発行の口をすべて 1 ファイルの `fileprivate` にすると、ほかのファイルから使えずコンパイルが通らない | 印の型は `internal`、init だけ `fileprivate`。基底に `internal` の `try token(.systemUI)` を置き、毎回 `self.name`・表・`NTK_DEVICE_ALLOW` を引いて、許されたときだけ返す（門番を通ったかの状態に頼らない） |
| A-17 | Codex | 結果が名指しの部分集合であることを照らしていない（存在しない名前は黙って無視されることを確かめた） | 上の 4 |

### 区分 B

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| B-1 | Claude | `-only-testing` を 1 つも渡さずに呼ぶと全件が流れる（fail-open） | 上の 4。`scripts/tests/` と 7 章に「空の一覧で呼ぶ」変異を足す |
| B-2 | Claude | `setUpWithError` より前に走る入口と、バンドルを読み込んだ時点のコード | 上の 5。0d で、選ばれなかったクラスの `class setUp` と `init` が走らないことをシミュレーターでログで確かめる |
| B-3 | Claude | `OpenNotificationSettings` と `RequestPermission` は印なしで押せる | `SystemUIToken` が要る口にする。RegisterCategory / RemoveCategory / SetBadgeCount を区分なしにする理由（サンプル自身の状態だけ）を書く |
| B-4 | Claude | 単体テストは一段目の外で、実機でも区分なしに流れる | 上の 7。今は安全である根拠（`withUniqueName()`、通知と Share はモック）も書く |
| B-5 | Claude | `--udid` がシミュレーターか実機かを決める方法が無い | 上の 6 |
| B-6 | Claude | `--dry-run` が実機にランナーを入れうる | 上の 3 で、実機に触れない |
| B-7 | Claude | 雛形の `testLaunch` は UI の構成を切り替え、私物の設定を変えうる | 上の 2 で消す |
| B-8 | Claude | 実機の `.xcresult` を消すのが正常の終わりだけ | 一時フォルダーに置き、`trap EXIT INT TERM` で消す。消せなかったときは場所を表示する |
| B-15 | Codex | 列挙の identifier を加工して組み立て直している | 列挙の identifier をそのまま実行に使い、表のキーとの対応は事実（8 章）に合わせた正規化の関数で取る。単体テストは実際の JSON を写した fixture で行う |
| B-16 | Codex | `self.name` の形を決め打ちしている | 8 章で `-[<クラス> <メソッド>]` と確かめた。正規化できなければ通常の Error を throw する |
| B-17 | Codex | `continueAfterFailure = false` のとき、監視の中で `XCTFail` すると `true` を返せる保証が無い | 監視は安全な操作・印の設定・`true` の返却だけを行う。XCUI の操作の直後に包む関数が印を読み、通常の Error を throw する。未知の割り込みは最初に terminate する |
| B-18 | Codex | skip の後も tearDown が走る（8 章で確かめた） | `gatePassed` を初めは false にし、確かめが終わったときだけ true にする。tearDown のすべての UI の操作を `gatePassed` と印の両方で守る。変異「skip の後の tearDown がアプリを起動しない」を足す |

### 区分 C

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| C-1 | Claude | `XCUIApplication(` は `XCUIApplication.init(` などで素通りする | 型の名前そのものを数える |
| C-2 | Claude | `self.name` の確かめの項目が 8.2 に無い | 8 章の事実で埋まった。8.2 から外す |
| C-3 | Claude | `UI_CLASSES` に雛形が入るか、CB2 の段が `--feature` のときに走るかが書かれていない | 雛形は消す。CB2 の条件を書く |
| C-4 | Claude | N24 の「登録を観測してから削除するので順は逆にならない」は正しくない（category は前から残っている） | RemoveCategory → 無い → Register → 有る → Remove → 無い、から始める |
| C-5 | Claude | 子のクラスがどの口で印を得るかが書かれていない | A-16 の `token(_:)` |
| C-6 | Claude | ランナーはソースの JSON を読み、テストはバンドルの写しを読む | ビルドの後に 2 つのハッシュの一致を照らす |
