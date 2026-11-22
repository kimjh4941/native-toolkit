# 同じ回に続けて出した表示の直し（SH-13）設計メモ

## 基本情報

| 項目 | 内容 |
|---|---|
| 作成日 | 2026-11-21（v3。v1・v2 のレビュー（Claude のサブエージェントと Codex）を反映） |
| 状態 | **決定（2026-11-21、利用者）**: D-1 は約束の外（v2 の「遅れた断りの見張り」は外した）、D-2 は「Share は共有のシートの上に重ねない」（MS-S2 の後に決め直した。4.4）、D-3 は 10 秒。v3 の後の実装で変えた所は 10 章 |
| 決定済み | SH-13 を不具合として扱い、2.0.0 のリリースの前に直して `dist/1.14.0` を作り直す（2026-11-21、利用者。段階 2 の作業の記録に書く） |
| 入力 | `unity-native-plugin` の報告（2026-11-15。同じリポジトリの `artifact/ios/share/results/2026-11-15-ios-share-cabi-implementation-result-v1.md` の 2 章）、第 1 部 5.13（`designs/2026-10-31-ios-c-abi-c-abi-design.md`）、Swift の設計書 6.3.3・6.3.4・8.2（`designs/2026-10-31-ios-c-abi-swift-api-design.md`） |
| レビュー | `reviews/2026-11-21-ios-c-abi-share-same-turn-design-review-v1.md`（v1 への。K-n と C-n）、`-v2.md`（v2 への。K2-n と C2-n） |
| 対象のコード | `ios/IosLibrary/IosLibrary/Common/Presentation/PresentationProcedure.swift`、`ReleaseWatch.swift`、`Share/Presentation/ShareSheetPresenter.swift`、`Dialog/Presentation/AlertDialogPresenter.swift` |
| 版 | `IosLibrary` と `IosLibraryCApi` は 2.0.0 のまま（まだリリースしていない）。ビルド番号は組み立てのスクリプトが上げる（8 章） |
| 名前 | この文書の「表示の失敗」は、Swift では `presentationFailed`（`ShareError`・`DialogError`）、C では `NTK_SHARE_ERROR_SHOW_FAILED`（19）と `NTK_DIALOG_ERROR_SHOW_FAILED`（10） |

## 1. 起きていること

`unity-native-plugin` の UI テスト SH-13（`dist/1.14.0`、iPhone 16 / iOS 18.3 のシミュレーターと、iPhone XS / iOS 18.7.2 の実機）:

- main の同じ回で `ntk_share_content_async` を 2 回呼ぶ（テキスト 1 つずつ、前面の既定）。2 回とも `NTK_SHARE_ERROR_NONE`（受け付け）が返る
- シートは 1 枚だけ出る。それを閉じると 1 つ目の callback が 1 回来る。**2 つ目の callback は来ない**（14 秒、前の回は 30 秒待った）
- Share.h の「受け付けた呼び出しには完了がちょうど 1 回」（第 1 部 1.3 の約束）と食い違う

報告の `.debug` のログ（2026-11-15、抜き出し。全文は向こうのリポジトリの記録にあり、こちらのリポジトリには無い）:

| 時刻 | 出来事 |
|---|---|
| 22.237 | 1 つ目: 落ち着いている → 見張りを付けて `present`（シート A） |
| 22.501 | 2 つ目: `[attempt] retried: false` → `isSettled` が**真**のまま → 見張りを付けて `present`（シート B） |
| 22.526 | UIKit: 「Attempt to present B on UnityDefaultViewController which is waiting for a delayed presention of A」（B を断った） |
| 23.729 | A の `markPresented`（`present` の完了） |
| 26.506 | A の `completionWithItemsHandler`（`completed: false`）→ 1 つ目の箱が閉じ、callback |
| 36.7 まで | B の `markPresented` も `deinit` も無い。2 つ目の箱は閉じない |

## 2. 原因

コードで確かめた（2026-11-15。報告の見立て、v1 のレビューの 2 者と同じ）。

1. **落ち着きの判定が、UIKit の「遅れた表示」を見分けない**。`UIActivityViewController` は、リモートの scene の用意ができるまで表示を遅らせる。その間、表示元の `presentedViewController` も `transitionCoordinator` もまだ立たないので、`isSettled`（`PresentationProcedure.swift:264-271`）は真を返す。`.firstActiveScene` の `isStableForLegacyPresentation`（273-276）も同じ
2. **断られたシートが解放されない**。Share は断られたことを解放の見張りだけで知る（`declineCheck: .releaseWatchOnly`。`present` の直後の `presentingViewController` は受け取ったシートでも後からしか立たないので、補いを使えない。1b の作業の記録 7.7）。ログが示すのは「A を閉じた 26.5 秒の後も、36.7 秒まで B の `deinit` が無い」ことまで。**誰が B を持ち続けるかは見立てで、確かめていない**
3. **1b で見逃した理由**: MS-03（SR-16）で測った「UIKit が断ったシートは約 0.03〜0.04 秒で解放」は、**既に別のものを出している ViewController に出す**場面だった。「遅れた表示の最中に出す」場面は測っていない

1.x（1.13.0）でも同じ場面で 1 つの結果が失われていた（1.13.0 の `ShareSheetPresenter` は `completionWithItemsHandler` でしか continuation を再開しない。`git show 1.13.0:` で確かめた）。2.0.0 で悪くなったものではない。

## 3. 約束との関係

- 第 1 部 P1-12 は D（落ち着いていなければ 1 回だけ待って重ねる）に決め、理由に「Unity の C# は同じフレームで続けて呼びやすい」を挙げている。同じ回の 2 回の呼び出しは約束の中の場面
- 第 1 部 5.13.1 の表で「UIKit が表示を断った」は「約束する」の行。断られたことを見張りで拾えない経路は、ホストの契約違反ではない
- よって、ライブラリの呼び出しどうしでは、2 つ目の呼び出しにも完了がちょうど 1 回来るようにする
- **ホストが自分で出した表示とぶつかる場面は約束の外にする**（D-1。4.5）

## 4. 直し方

### 4.1 方針

**ライブラリが自分で出したシートを、その `present` の完了が来るまで記録し、同じ window に出す要求はその間待たせる**。UIKit の「遅れた表示」の状態は公開の API で読めないので、自分が始めた表示だけを自分で数える。SH-13（ライブラリどうしの 2 回）は、2 つ目を遅れた表示の最中に出さないので起きなくなる。

**表示したシートの箱を、時刻だけで閉じることはしない**（v2 の 4.5 を外した。C2-1・C2-2・K2-1・K2-2。出るのが遅れただけのシートを失敗にし、その後に利用者が共有すると、失敗を受け取った呼び出し側がやり直して 2 重に共有しうる。第 1 部 P1-14 が時計の見張りを外した理由（R3-2）と同じ危険）。時計で失敗にするのは、**まだ何も表示していない、待っている要求だけ**。

### 4.2 途中のシートの記録

| 項目 | 決め方 |
|---|---|
| 入れ物 | 要求ごとの token の集まり（`PresentationRecords`。`@MainActor` の final class、internal） |
| 共有 | **要求どうしで同じ入れ物を使う**。`ShareSheetPresenter` と `AlertDialogPresenter` は要求のたびに `makeEnvironment()` を呼び、環境は struct なので、入れ物は環境の値でなく、外で作った参照を渡す（K2-3）。`UIKitPresentationEnvironment` は static の 1 つ（`PresentationRecords.shared`）を返す。偽の環境は init で入れ物を受け取り、テストが作った 1 つを `makeEnvironment` の closure に捕まえる。並べて走る単体テストどうしで漏れない |
| 環境に足す口 | `var records: PresentationRecords { get }`、`func windowIdentity(of node: Node) -> ObjectIdentifier?`（UIKit は `node.viewIfLoaded?.window`。C2-4・K2-7）、`func after(seconds: Double, _ body: @escaping @MainActor () -> Void)`（UIKit は `DispatchQueue.main.asyncAfter`、偽の環境は手で進める）。環境に適合する 6 つの型（`FakePresentationEnvironment`、`AlwaysSettledEnvironment`、`AnchorRecordingEnvironment`、`UnstableForLegacyEnvironment`、`DecliningPresentationEnvironment`、`AnimationRecordingEnvironment`）を直す |
| 記録するもの | **`.releaseWatchOnly` で出すシートだけ**。アラートは `present` の中で `presentingViewController` と `transitionCoordinator` が立つ（MS-01）ので、今の `isSettled` で見え、記録しない。Dialog→Dialog の振る舞いは今のまま |
| token の中身 | ID（`UInt64`、入れ物が振る）、表示したシート（`weak`。型は `AnyObject` に消す。C2-4）、範囲の印（`windowIdentity` の値。`nil` もそのまま 1 つの範囲として扱う）、始めた時刻 |
| 範囲 | **表示元の window ごと**。段 3 で見るのは、出そうとする表示元と同じ window の token だけ。iPad の別の window の要求や、`.viewController(_:)` で別の window を渡した要求は待たない |
| 始まり | 段 3（`show`）で、ID を振ってから見張りを作り（ID を `init` で渡す。K2-6）、記録して、`environment.present` を呼ぶ |
| 終わり（どれか早いもの。1 回だけ） | (1) その `present` の完了。(2) シートの解放（見張りの `deinit` が知らせる）。(3) 寿命（D-3。記録の始まりから 10 秒。`after(seconds:)` で起きる）。v2 の「箱が閉じた」は外した（要求の終わりと表示の移り変わりの終わりは別。Share の箱が `present` の完了の前に閉じる経路は、解放の見張りだけで、それは (2) で終わる。K2-5） |
| 終わりの理由 | (1)・(2) は「表示が片付いた」、(3) は「期限切れ」。待つ要求に理由を渡す（4.3。C2-3） |
| 古い知らせ | 終わりは token の ID で行う。既に終わった ID への知らせは何もしない |

持ち合い:

| 持つもの | 持ち方 | 理由 |
|---|---|---|
| `present` の完了の closure | 見張りを `weak`、入れ物を `weak`、token の ID だけ | 断られたシートの完了の closure は UIKit が持ち続ける（`aDeclinedViewControllerIsWatchedEvenWhileItsCompletionIsKept` の前提）。強く掴むと、ほかのシートや要求を道連れにする |
| 見張り | 今のまま、シートが唯一の持ち主。`let` で足すのは、解放を知らせる `@Sendable` の closure だけ（ID と入れ物の `weak` を捕まえ、main に積んで `end(id, .cleared)` を呼ぶ）。`deinit` は今どおり `self` もシートも捕まえない | `@unchecked` なしの `Sendable` を保つ（C2-5・K2-6）。`[weak]` の捕まえ方が Swift 6.0 の `Sendable` の検査を通るかは実装で確かめ、通らなければ、ID だけを受ける static の口を main に積む形にする |
| token | 入れ物が強く持つ。シートは `weak` | シートを持ち続けない |
| 待つ要求（`again`） | 入れ物の一覧が強く持つ。**起こしたとき、時計で起きたときに一覧から外す** | `again` は表示するもの・箱・`locate`（`.provided` では表示元）を強く持つので、外さないと持ち続ける |
| 時計の closure | 入れ物を `weak`、要求または token の ID | 同上 |

- `present` の完了の中の `onPresented`（Dialog の `didPresent()`。取り消しを `present` の完了まで待つ R4-2 の処理）は、**箱が閉じていても今のまま呼ぶ**

### 4.3 待ち方（段 3〜6 の直し）

| 段 | 今 | 直した後 |
|---|---|---|
| 3 | `isSettled(top)` が真なら出す | `isSettled(top)` が真で、**かつ同じ window に途中のシートが無い**ときに出す |
| 4 | `transitionCoordinator` の completion を 1 回待つ。無ければ待たない | 同じ window に途中のシートがあれば、**そのどれかの終わり**か、**待ちの上限**（D-3。待ち始めから 10 秒）のどちらか早いほうを 1 回待つ。途中のシートが無ければ今のまま。**両方あるとき**（ホストの移り変わりと途中のシート）は途中のシートを待ち、段 5 の探し直しでまだ移り変わりの途中なら段 6 で失敗する |
| 5 | main の次の回で、段 2 から 1 回だけやり直す | 起きた理由が「表示が片付いた」なら同じ。**「期限切れ」か待ちの上限なら、やり直さずに表示の失敗で閉じる**（C2-3。記録が消えたことを「落ち着いた」と取ると、元の不具合と同じく遅れた表示の最中に出しうる）。どちらも `again` を 1 回だけ通す今の印を使い、起きたら入れ物の一覧から外す |
| 6 | 2 回目も落ち着かなければ表示の失敗 | 同じ。2 回目も同じ window に途中のシートがあれば表示の失敗 |

- 時計で失敗にするのは、まだ何も表示していない要求だけなので、誤った結果を返さない（約束は「完了がちょうど 1 回」）
- 待つ間に要求の箱が閉じたら（Dialog の取り消し）、段 5 は今のとおり何もしない
- 待つ間にアプリが後ろに回り、上限が来たら表示の失敗になる。表示する前の要求なので、P1-15（表示した UI は後ろに回っても取り消さない）とは食い違わない。今も、待つ間に後ろに回れば段 5 の探し直しで前面でない（`NOT_FOREGROUND`）
- **待つ要求の一覧は、P1-12 の「待ちの列は持たない」から外れる**。順番を守る列ではなく、起こす相手の一覧で、各要求は今どおり 1 回だけやり直す。P1-12 に改訂の注を書く
- `.firstActiveScene` の `requireLegacyStability`（Share の今の口）: 待たない方針のまま、同じ window に途中のシートがあれば、今の「落ち着いていない」と同じくすぐ表示の失敗にする。**今の口の振る舞いが変わる所**（今は出して、2 つ目の完了が来ない）
- `.firstActiveScene` の `presentAnyway`（Dialog の今の口）: 記録を見ない（今のまま出す）。UIKit がアラートを断れば、`present` の直後の補い（`rightAfterPresent`）がその場で表示の失敗にする見込み（遅れた表示の最中に断られたアラートでも効くかは MS-S5 で測る）

### 4.4 2 つ目の行き先（D-2）

1 つ目の完了の後、段 5 の探し直しでは、前面の ViewController は 1 つ目のシート（A）になる。

**決定（2026-11-21、利用者。MS-S2 の後に決め直した）: Share は、前面が共有のシート（`UIActivityViewController`）なら出さず、表示の失敗で終わる**。どの `presenter` でも同じ（`.firstActiveScene` も、渡された ViewController も）。ホストが自分で出したシートの上でも同じ。Dialog は今どおり重ねて出す。同じ回の 2 回目の Share は、A の `present` の完了を待ち、探し直しで A を見つけて表示の失敗になる（SH-13 の期待値は「1 つ目は A を閉じた結果、2 つ目は表示の失敗」）。

- MS-S2 では、UIKit は A の上に重ねたシートを受け取った（iOS 26.2 と 18.3、各 3 回。A の `presentingViewController` から約 1.1〜1.2 秒後に重なって出た）。最初の決め方（4.4 の v3 の表）なら「重ねて出す」になる
- ただし MS-S8（5 章）で、**iOS 18.3 では、2 つ目が A の上に出る途中（約 0.6 秒）に A を外から閉じると、A も 2 つ目も解放されず、2 つとも完了しなかった**（ログ: 2 つ目の `present` の完了は来るが、A が 2 つ目を出したまま残る。iOS 26.2 では 2 つ目が表示の失敗、A が `dismissedBySystem` で 1 回ずつ来た）。重ねると、まれな外からの閉じ方で 2 つとも失われる。重ねなければこの経路は無い
- 2 枚の共有のシートを重ねても、利用者にとっての使い道は無い

### 4.5 ホストが自分で出した表示（D-1: 約束の外）

ホスト（または別のライブラリ）が自分で `UIActivityViewController` などを出し、その `present` の完了の前（遅れた表示の最中）に、同じ window に Share を呼ぶと、同じ形で完了が来ない見込み（MS-S4 で確かめて記録する）。ライブラリはホストの表示を数えられず、表示したシートを時刻で失敗にする方法は誤った結果を返しうる（4.1）。

- **約束の外にする**。範囲は「ホストが自分で出した表示が、まだ `present` の完了の前のときに、同じ window に Share を呼んだ」に絞る（ホストの移り変わりは今どおり段 4 で待つ。v1 の「ホストの表示の途中のすべて」より狭い。C-4）
- 避け方（ヘッダーとマニュアルに書く）: 自分で出したものの `present` の完了を待ってから Share を呼ぶ
- Dialog は `present` の直後の補いで拾える見込みなので、約束の中のまま（MS-S5）
- 書く所: 第 1 部 0.1・1.3・5.13.1 の「約束の外」の行、`Share.h` の `ntk_share_result_fn` の説明（第 2 部の付録 A の写しも）、Swift の DocC（`share(content:presenter:)` の 2 つの口）、マニュアル（段階 4）

### 4.6 決定

| ID | 内容 | 決定（2026-11-21、利用者） |
|---|---|---|
| D-1 | ホストが自分で出した表示の `present` の完了の前に、同じ window に Share を呼んだ場合 | 約束の外（4.5）。v2 の「遅れた断りの見張り」は入れない |
| D-2 | A の上に重ねたシートを UIKit が断る場合 | 4.4 の表の規則（MS-S2 の結果で行を選ぶ） |
| D-3 | 待ちの上限と記録の寿命 | 10 秒。`unity-native-plugin` の実機のログ（A の `present` から `markPresented` まで）をもらい、上回っていれば見直す。**結果**: 実機の時間は上限 2.56 秒で、10 秒は変えない（段階 2 の作業の記録 17.16） |

## 5. 測ること（シミュレーターだけ。実機は使わない）

iPhone 17 Pro / 26.2 と iPhone 16 / 18.3。iPad Pro 11-inch (M4) / 18.3 は MS-S6 だけ。サンプルの新しいボタン（6.3）と C ABI の UI テストのアプリ（6.4）で測る。MS-S4 と MS-S7 は、サンプルに残さない一時の手順（`results/probes`）で測る。

| ID | 測ること | 見込み | 決めるもの |
|---|---|---|---|
| MS-S1 | 直す前に、同じ回に Share を 2 回呼ぶ | SH-13 と同じく 2 つ目の完了が来ない（赤） | テストが不具合を捕まえること |
| MS-S2 | 直した後、2 つ目が A の上に重なるか。断られたら、解放までの時間 | - | 4.4 の行、S20 の期待値 |
| MS-S3 | 直した後、2 つ目が待った時間（A の `present` の完了まで）と、A の `presentingViewController` が立った時刻。5 回 | 1.5 秒前後 | D-3 の余裕 |
| MS-S4 | ホストの形（自分で `UIActivityViewController` を出し、同じ回に Share）。直した後 | 2 つ目の完了が来ない | 4.5 の記録（約束の外の根拠） |
| MS-S5 | 同じ回に Share → Dialog、Dialog → Share（直した後） | Share → Dialog は待って重なる見込み（今は Dialog がすぐ表示の失敗） | 振る舞いの変わり目、UI テストの D 系の期待値 |
| MS-S6 | iPad で、別の window に途中のシートがあるときの Share。同じ window の popover の SH-13 | 別の window は待たない。popover でも遅れた表示が起きるかを記録 | 範囲を window ごとにしたこと |
| MS-S7 | 遅れた表示の途中でホームに戻り、5 秒後と 15 秒後に戻る（直した後） | A の完了が戻った後に来るか、記録が期限切れになった後の 3 つ目の Share がどうなるか | 寿命が後ろに回っている間も進むことの影響（K2-1）。悪ければ、寿命を前面で active の間だけ数える形に直す |
| MS-S8 | 2 つ目が A の上に出る途中に A を外から閉じる（MS-S2 の後に足した。閉じるまでの間 0・0.3・0.6 秒） | - | D-2 の決め直し |

実機での確かめは、`unity-native-plugin` に、作り直した `dist/1.14.0` で SH-13 を流してもらう（向こうのセッションが利用者の許可を得て行う）。実機の `.debug` のログの時間（D-3）もそこで頼む。

## 6. テスト

### 6.1 単体テスト（`IosLibraryTests`。UT-04 に足す。偽の環境）

偽の環境は既に `present` の完了を呼ばずに持てる（`finishPresentations`）。足すのは、完了を 1 つずつ呼ぶ口、時計、記録の入れ物（init で受け取る）、ノードごとの window の印:

- 途中のシートがあると、同じ window の 2 つ目は出さずに待ち、1 つ目の完了の後の次の回で出す
- 同じ回の 3 回（3 つ目は 2 つ目の完了の前なら段 6 で失敗。期待値は実装の前に表で決める）
- 1 つ目の完了が上限までに来なければ、2 つ目は表示の失敗で 1 回閉じる。**その後に 1 つ目の完了が遅れて来ても、2 つ目は何も起きない**
- **A の寿命 → 2 つ目が起きる → 2 つ目は表示の失敗**（やり直さない。C2-3）。2 つ目の時計がその後に来ても何も起きない
- 完了 → 時計、時計 → 完了の両方の順で、やり直しは 1 回
- 待つ間に 1 つ目が解放されたら（見張りの知らせ）、時計を待たずに起きてやり直す
- 待つ間に 2 つ目の箱が閉じたら（Dialog の取り消し）、何も出さない
- 期限切れの token は、後から来た要求を待たせない
- 古い token の ID の知らせ（解放・完了）が、新しい token を終わらせない
- 別の window の token は待たない。`.viewController(_:)` で別の window の表示元を渡したときも待たない
- `.firstActiveScene` の `requireLegacyStability` は、同じ window に途中のシートがあれば待たずに表示の失敗。`presentAnyway` は記録を見ない
- アラート（`rightAfterPresent`）は記録を作らない
- 取り消した Dialog の `didPresent()` が、箱が閉じていても `present` の完了で呼ばれる（R4-2）
- 時計で起きた要求を一覧から外し、表示するもの・箱を手放す（`weak` で見て解放を確かめる）
- **`makeEnvironment` が要求ごとに新しい環境を作っても、同じ入れ物を見る**（`ShareSheetPresenter` を偽の環境で 2 回呼ぶ。K2-3）
- 記録がテストどうしで漏れない（テストごとの入れ物）
- 変異（mutations）: 段 3 の途中のシートの確かめを外す、終わり (1)〜(3) のそれぞれを外す、期限切れでやり直す（失敗にしない）、上限の時計を外す、一覧から外すのをやめる、範囲を window から全体にする、入れ物を要求ごとに作る。どれもどれかのテストで落ちること

### 6.2 本物の UIKit の単体テスト（`ShareSheetPresenterTests`。ホストの window）

- 同じ回に 2 回 `present(items:excluded:presenter: .foreground)` を呼び、2 つの結果がそれぞれ 1 回返る（SH-13 の再現。UI テストより速く、TSan・ASan の回にも入る）。シートを閉じる手順は今のテストの形を使う

### 6.3 サンプルと UI テスト（`IosLibraryExample`）

- サンプルの Share の画面の「Swift API (2.0.0)」の節に `ShareTwiceInOneTurn`（同じ回に `share(content:presenter: .foreground)` を 2 回）を足す
- UI テスト S20（シミュレーターだけ）: `ShareTwiceInOneTurn` → 出たシートを順に閉じる → 結果の行が 2 本。期待値は MS-S2 の後に 1 つに決める。30 秒待っても 2 本目が無ければ失敗
- Share → Dialog の期待値が変わる UI テストの D 系の行があれば直す（MS-S5）

### 6.4 C ABI の UI テスト（`IosLibraryCApiUITestApp`、`--capi-ui`）

- `share.twice` の行を足す（同じ回に `ntk_share_content_async` を 2 回。`user_data` は 1 と 2）。要求ごとに callback と release がそれぞれ 1 回、main で来て、結果を解放できることを確かめる。上限を過ぎるまで待っても増えないこと

### 6.5 流す範囲

関係するものだけ流す（`IosLibraryTests` の Presentation・Share・Dialog、S17〜S20、D 系の関係する行、`--capi-ui` の Share）。`dist` を作る前に、決まった全体の確かめ（`test_ios.sh --capi`、TSan・ASan の回）を 1 回流す。

## 7. 直す文書

| 文書 | 所 |
|---|---|
| 第 1 部 | 0.1 と 1.3 と 5.13.1 の「約束の外」の行（D-1）、5.13 の「既定の動作は変えない」と 5.13.2 の「既定（渡さない）」の行（`.firstActiveScene` の Share の変わり目）、5.13.2 の段 3〜5 と「同じ main の回で続けて呼んだ 2 つ」の行、P1-12 に改訂の注（待つ要求の一覧）、G-4・G-7（「断られたシートは約 0.03〜0.04 秒で解放」は測った場面が限られていた）。P1-15 は MS-S7 の結果しだい |
| 第 2 部 | 6.4 と付録 A の `Share.h` の写し（照らすスクリプトはコメントを外すので、食い違っても気づかない） |
| Swift の設計書 | 6.3.3 の段 3〜5 と `.firstActiveScene` の箇条書き、6.3.4、8.2 の「今の口」「表示の手順」の行 |
| README（トピック） | 4.1 と 1b の行（`.firstActiveScene` の Share の変わり目）、9 章の DoD に SH-13 の行 |
| UI テストの設計書 | S20、C ABI の `share.twice`、D 系の変わる行 |
| DocC | `ShareSheetPresenter` と `PresentationProcedure` の表、公開の Share の口（D-1 の約束の外と避け方）と Dialog の口の `presentationFailed` の説明 |
| Share.h | `ntk_share_result_fn` の説明に D-1 の 1 文と避け方 |
| 1b の作業の記録 | 7.7 に注（測った場面） |
| 段階 2 の作業の記録 | 17.16（決定、測り、結果） |
| マニュアル（段階 4） | 申し送り: 同じ回に続けて Share を呼んだときの振る舞い、D-1 と避け方、`.firstActiveScene` の Share の変わり目 |

## 8. `dist/1.14.0` の作り直し

- 17.14 と同じ: `DEVELOPER_DIR=<Xcode 26.6> scripts/build_ios_library_xcframework.sh -m IosLibrary -m IosLibraryCApi -v 2.0.0 --output-dir dist/1.14.0/ios`。スクリプトがビルド番号を上げて `project.pbxproj` の `CURRENT_PROJECT_VERSION` を書き換える（`IosLibrary` 18 → 19、`IosLibraryCApi` 2 → 3 の見込み。`build_ios_library_xcframework.sh:446-455`）ので、手で上げず、その差分を dist と同じコミットに入れる
- `include/NativeToolkitC` も作り直したもの（新しい `Share.h`）にする
- `check_ios_dist.py 1.14.0`、`check_c_abi_contract_ios.py`、`check_design_consistency.py`（直した設計書）を流す
- 署名し直しは、作り直した dist から作った**新しい**アーカイブで確かめる（`run_ios_capi_smoke.sh --dist dist/1.14.0/ios --device-build` と、17.15 と同じ `codesign`）。17.14・17.15・手順書の値（ビルド番号など）を直す
- `unity-native-plugin` に、**同じ版名（2.0.0、`dist/1.14.0`）で中身が変わった**ことと、D-1（約束の外）と `.firstActiveScene` の変わり目を知らせ、xcframework を確実に差し替えてもらう。そのうえで SH-13 の `XCTExpectFailure` を外して確かめてもらう

## 9. 順番と見込み

| 順 | すること | 見込み |
|---|---|---|
| 1 | MS-S1・MS-S4（直す前）、単体テストを先に書いて赤を確かめる（偽の環境の 6 つの型の直しを含む） | 2.5 時間 |
| 2 | 直す、単体テスト・変異、MS-S2・S3・S5・S6・S7 | 3 時間 |
| 3 | サンプル・S20・`share.twice`、文書の直し | 2.5 時間 |
| 4 | 実装のレビュー（2 者）と反映 | 1.5 時間 |
| 5 | 全体の確かめ、`dist` の作り直しと確かめ | 1.5 時間 |

## 10. 実装で分かったことと、v3 から変えた所（2026-11-21）

### 10.1 測りの結果

| ID | 環境 | 結果 |
|---|---|---|
| MS-S1 | iPhone 17 Pro / 26.2、`ShareSheetPresenterTests` の本物の UIKit のテスト（直す前） | 2 つ目の結果が来なかった（25 秒）。SH-13 を再現した |
| MS-S2 | iPhone 17 Pro / 26.2 と iPhone 16 / 18.3、各 3 回（一時の確かめのテスト。コミットしない） | 2 つ目は A の上に重なって出た（UIKit は受け取った）。A の `presentingViewController` は 0.05〜1.16 秒（初回が遅い）、2 つ目はその約 1.1〜1.2 秒後。外から閉じると 2 つとも `dismissedBySystem` が 1 回ずつ |
| MS-S4 | iPhone 17 Pro / 26.2 と iPhone 16 / 18.3（一時の確かめのテスト。直した後） | ホストが自分のシートを出した同じ回に Share: 12 秒たってもライブラリの Share の結果は来なかった（ホストのシートの `present` の完了は 1.0〜1.4 秒）。D-1 の約束の外の場面を確かめた |
| MS-S5 | 同じ 2 つ（直した後） | Share → Dialog: Dialog は約 1.1 秒待ってシートの上に出た。Dialog → Share: Share は約 0.5 秒でアラートの上に出た |
| MS-S6 | iPad Pro 11-inch (M4) / 18.3（popover） | `ShareSheetPresenterTests` と `PresentationProcedurePendingSheetTests` の 36 件が通った（同じ window の popover の 2 回も 1 回ずつ完了）。本物の複数の window では測っていない（範囲は偽の環境の単体テストで確かめた） |
| MS-S7 | iPhone 17 Pro / 26.2（一時の UI テスト） | 2 回呼んだ直後にホームに戻り、5 秒後・15 秒後に戻る: どちらも戻るとシートが出ていて、閉じると一方が `notCompleted`、もう一方が `presentationFailed` で 1 回ずつ（どちらが出るかは回で違った） |
| MS-S5 の残り | - | 今の口の Dialog（`.firstActiveScene` の `presentAnyway`）を、出る途中の共有のシートと同じ回に出す場面は測っていない（未確認）。理屈では、UIKit が断れば `present` の直後の補い（`rightAfterPresent`）がその場で表示の失敗にするので、完了は 1 回のまま（実装のレビュー、Claude 11） |
| MS-S8 | 同じ 2 つ | 閉じるまで 0 秒: 18.3 は 2 つとも 14 秒来ず、A も解放されない。26.2 は 2 つ目が表示の失敗、A が `dismissedBySystem`。0.3・0.6 秒: どちらも 2 つとも `dismissedBySystem` |

### 10.2 v3 から変えた所

| 所 | v3 | 実装 | 理由 |
|---|---|---|---|
| 4.4（D-2） | MS-S2 の結果で行を選ぶ | Share は共有のシートの上に出さない（`PresentationEnvironment.isShareSheet(_:)` を足した） | MS-S8。利用者が決め直した |
| 4.3 の段 4 | 途中のシートを待つ要求に、待ち始めから 10 秒の上限の時計を置く | 上限の時計は置かない。待つ要求は、待っている記録の終わり（遅くとも寿命）で起きる | 変異のテストで、この時計を外しても落ちるテストが無かった（M6）。待つ要求は必ず記録より後に始まるので、記録の寿命が先に来て、この時計は働かない |
| 4.4・6.3・6.4 の期待値 | 2 つ目が表示の失敗、1 つ目が閉じた結果 | **どちらか一方**が表示の失敗、もう一方が閉じた結果（どちらかは決まらない） | `--capi-ui` で 1 つ目が `SHOW_FAILED` になった。Share の口は呼び出しごとに `Task` を起こして中身を組み立ててから手順に入るので、手順に着く順は呼んだ順とは限らない。ヘッダーはもともと「複数の Share の callback の順は約束しない」。完了がちょうど 1 回ずつ来ることは変わらない |
| 4.2 の終わり (3) と 4.3 の段 5（実装のレビュー、Codex 1） | 寿命で記録を終える（消す） | 寿命を過ぎた記録は「行き詰まり」として、`present` の完了か解放まで残す。その間、同じ window の要求（Share と、新しい口の Dialog）は待たずに表示の失敗。待っていた要求は今どおり表示の失敗 | 寿命で消すと、シートが出るのに 10 秒を超えた後（後ろに回っていた、など）に呼んだ要求が、UIKit がまだ出す途中のシートの上に出て、SH-13 と同じく完了しなくなる。UIKit がそのシートを出す途中なら、その window には何を出しても断られるので、失敗で 1 回終わらせるほうが約束に合う。利用者が決めた（2026-11-21）。代わりに、約束の外（D-1）で断られて持ち続けられたシートがあると、それが解放されるまで、その window のライブラリの表示は表示の失敗になる（完了は 1 回ずつ来る） |
| 4.2 の範囲の印 | `ObjectIdentifier`（`windowIdentity(of:)`） | window を `weak` で持つ（環境の口は `window(of:)`）。window が無くなった記録は片付いたとみなす。起こす相手は、作ったときの識別子で比べる | 解放された window のアドレスを別の window が使い回すと、関係の無い window の要求が待たされる（実装のレビュー、Claude 5） |
| 6.3 の S20 の待ち | 固定で 3 秒待ってから閉じる | サンプルが Share ごとに結果の行を書き（終わっていないものは `pending`）、UI テストは 1 本目（表示の失敗）を待ってから閉じる | 固定の待ちは遅い環境でぶれる（実装のレビュー、Codex 2） |
| 待つ間に取り消した Dialog（実装のレビュー、Claude 4・Codex 3） | - | 直さない。記録が片付くか寿命が来るまで（最長 10 秒）、待つ要求の一覧がアラート・箱・表示元を持ち続ける。完了の回数は正しい | 箱の閉じ方を知らせる口が 1 つ（`attach`）しかなく、外すには箱の作りを変えることになる。持ち続けるのは最長 10 秒 |
| 6.3 の S20 | シミュレーターだけ | 実機でも流せる（`SIMULATOR_ONLY_TESTS` に入れない） | シートを開いて閉じるだけで、S11 と同じく実機で危ない操作が無い。実機の確かめは `unity-native-plugin` の SH-13 でも行う |
| 4.2 の環境の口 | 6 つの型を直す | `records`・`windowIdentity(of:)`・`after(seconds:_:)`・`isShareSheet(_:)` は、`Node == UIViewController` の環境には既定の実装（共有の入れ物、`viewIfLoaded?.window`、`asyncAfter`、`is UIActivityViewController`）を置き、偽の環境（`FakePresentationEnvironment`）だけが自分で実装する | UIKit を包むテストの環境は本物の振る舞いを使うので、同じ既定でよい |

### 10.3 変異のテスト

`PresentationProcedurePendingSheetTests` と `twoSharesInOneTurnEachEndOnce` に対して 11 通り（iPhone 17 Pro / 26.2）。M6 だけが残り、10.2 のとおり時計を外した。

| ID | 変異 | 結果 |
|---|---|---|
| M1 | 段 3 で途中のシートを見ない | 落ちた（7 件） |
| M2 | `present` の完了で記録を終えない | 落ちた（5 件） |
| M3 | 解放の知らせで記録を終えない | 落ちた（1 件） |
| M4 | 記録の寿命が無い | 落ちた（2 件） |
| M5 | 期限切れで起きた要求がやり直す | 落ちた（2 件） |
| M6 | 待つ要求の上限の時計が無い | 残った（時計を外した） |
| M7 | 起こした要求を一覧に残す | 落ちた（3 件） |
| M8 | 範囲を window から全体にする | 落ちた（1 件） |
| M9 | 入れ物を要求ごとに作る | 落ちた（`twoSharesInOneTurnEachEndOnce`） |
| M10 | 段 3 の前で、共有のシートの上に Share を出す | 落ちた（3 件） |
| M11 | `.firstActiveScene` で、共有のシートの上に Share を出す | 落ちた（1 件） |

記録を残す形にした後（10.2）、16 通り（iPhone 17 Pro / 26.2）。M1〜M4・M7〜M11 は上と同じ変異、M12〜M17 は新しい所。M5 だけが残った: 寿命で起きた要求がやり直しても、探し直しで記録が行き詰まりと分かり表示の失敗になるので、寿命のための別の分岐は要らなかった。分岐を外し、待つ要求はどの終わりでもやり直す形にした（結果は同じ）。

| ID | 変異 | 結果 |
|---|---|---|
| M12 | 行き詰まりの記録があっても失敗にしない | 落ちた（1 件） |
| M13 | 寿命で記録を消す | 落ちた（2 件） |
| M14 | 記録の終わりがすべての window の要求を起こす | 落ちた（1 件） |
| M15 | 読むときに、解放済みのシートの記録を片付けない | 落ちた（3 件） |
| M16 | 読むときに、無くなった window の記録を片付けない | 落ちた（1 件） |
| M17 | `.firstActiveScene` の安定の確かめが記録を見ない | 落ちた（1 件） |
