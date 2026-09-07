# レビュー結果

- 日付: 2026-08-08
- 対象ファイル: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- 参照企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 参照設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 参照実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review-v2.md`

---

## 強み

- 前回レビューv2の高3件・中7件・低2件は、いずれも対応方針として反映されている。
- custom UTIと`public.data` fixtureを分け、CopyとLoadのidentifierを一致させたことで、provider選択の不一致を解消している。
- T-00を「直前の状況 / 操作 / 判定 / 実施可否」で再構成し、case 1〜3を分割、case 7 / 8 / 12〜15をharnessへ移管した境界は妥当である。
- Paste Controlのunsupported-onlyを「control無効・callback 0回」へ訂正し、partial / all failureを決定的なライブラリテストへ委譲している。
- request directoryとsession directoryを階層図で区別し、callerが削除する範囲とactive sessionの所有権を正しく記載している。
- cleanup失敗を警告として画面へ出しつつ、pathを画面・ログへ出さない方針を維持している。
- accessibility identifierのapp target / UI test target境界、label変化待機、off-screen操作、positive / negative assertionを具体化している。
- Error Cases 11件の正式コード、入力、観測中の異常系button制御は実装契約と一致している。
- M-13の通常fixture性能測定と64 MiB / 100 MPのunit test境界を分離し、v2内の矛盾を解消している。

## 改善点

### 高優先度

#### 1. `checkForegroundChange`のbaseline未確立によりT-00 case 4 / 10が成立しない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:560`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:566`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:646`
- `CheckForegroundChangeUseCase.execute`はtrackerがない場合、現在の`changeCount`をbaselineとしてtrackerを作り、その同じ値と比較する。このため**初回呼び出しは必ずfalse**になる。
  - `ios/IosLibrary/IosLibrary/Clipboard/Application/UseCase/CheckForegroundChangeUseCase.swift:43`
- v3は外部copy・foreground復帰後に初めて`Check Foreground Change`を押すため、case 10はfalseとなり、条件付きの`Read`へ到達しない。case 4も変化検出の手順としては成立しない。
- case 10を次の順序へ修正すること。
  1. foregroundで`Check Foreground Change`を一度実行しbaselineを確立
  2. appをbackgroundへ移動
  3. 外部アプリでcopy
  4. appへ復帰して再度Check
  5. trueの場合だけRead
- case 4は「初回falseはbaseline初期化である」ことを表示・記録し、必要ならbaseline確立後の2回目で変化を確認すること。

#### 2. T-00の必須観点M-16が実施計画から欠落している

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:317`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:550`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:658`
- 設計v4はT-00の必須観点として、`copy(localOnly: true)`直後の`append` itemがUniversal Clipboardへ転送されるかを2台で観測するM-16を定義している。
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1535`
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1554`
- v3は「T-00で変わりうる」とだけ記載し、操作手順、期待結果、記録先がない。このままではD-8 / R-13を判断できない。
- 8.2またはT-00節へM-16を追加し、次を定義すること。
  - 端末Aで`localOnly: true`の識別可能なfixtureをcopy
  - 別内容のfixtureをappend
  - 端末Bでcopy本体とappend itemを区別して転送有無を確認
  - iOS 18 / iOS 26ごとに結果を記録

#### 3. M-08が「存在していたnamed pasteboardの終了時消滅」を検証していない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:628`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:664`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:747`
- 手動#6とU-10は`terminate → launch → no create → Read`だけで、終了前にfixed named pasteboardを作成していない。最初から存在しない名前を読んでも`CLIPBOARD_UNAVAILABLE`になるため、テストが偽陽性になる。
- 手動表を順番に実施する場合も、#5でnamed pasteboardを明示removeした後に#6へ進むため、非永続性ではなくremove結果を再確認するだけになる。
- M-08を独立した一続きの手順へ変更すること。
  1. `Create Named Pasteboard` → Copy → Read成功
  2. background / foreground後もRead成功
  3. **removeせず**terminate
  4. launch → `Use Fixed Named Scope (no create)` → Read
  5. `CLIPBOARD_UNAVAILABLE`を確認
- U-10にも作成・成功確認・background確認・非removeという前提を含めること。

### 中優先度

#### 1. T-00の記録軸が企画書のOS別DoDを満たさない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:555`
- 企画書は16ケースをiOS 18 / iOS 26の双方で観測し、「許可プロンプト」と「アクセス通知」を別々に記録することを要求する。
  - `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md:384`
- v3の「プロンプト / 通知の有無」という1列では、両現象とOS差を分離して記録できない。
- 対応表とは別に、`許可プロンプト(iOS 18 / iOS 26)`と`アクセス通知(iOS 18 / iOS 26)`の4観測列を持つ結果テンプレートを追加すること。

#### 2. M-12のstartup cleanup契機とactive session確認が不正確

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:677`
- `ClipboardTemporaryFileStore`はmanagerのuse case構築時に生成され、initializer内でprocess単位cleanupを実行する。再起動後の最初の`Load File`が必ず初期化契機になるわけではない。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:61`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/File/ClipboardTemporaryFileStore.swift:31`
- cleanup時点では新session directoryがまだ作られていない場合がある。cleanup後のLoadで作成したnew sessionが残ることを確認しても、「cleanupが既存active sessionを除外した」証明にはならない。
- 「managerを最初に参照した時点でstartup cleanupが起こり得る」と訂正すること。サンプルではold session削除のみを観測し、active-session除外は注入可能なunit / integration harnessへ委譲すること。

#### 3. UI testのscroll helperが画面上方へ戻れない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:769`
- setupは画面下部のClearまでscrollするが、`scrollToHittable`は`swipeUp()`しか行わない。その後に上部のScope / Copy buttonを探す場合、さらに下へ進み続ける。
- scroll directionを引数化して`swipeUp()` / `swipeDown()`を使い分け、最大試行回数後に明示failすること。またはClear後に一度画面を離れて再遷移し、先頭位置へ戻すこと。

#### 4. 成功結果の待機がsetupの古い`✅`を拾って偽陽性になり得る

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:739`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:772`
- 共通setupのClear完了後、`clipboard.result`には既に`✅`が残る。以降のtestが単に`✅`を待つとpredicateは新しいoperation完了前に成立する。
- Error Casesにも同じerrorCodeが2回現れるため、codeだけの待機では直前buttonの結果を再利用して通る可能性がある。
- 各結果に`[Read]`、`[Snapshot]`、button固有labelなどのoperation markerを必須とし、markerと期待payload / errorCodeを同時に待つこと。必要ならtap前のlabelから変化したこともassertすること。

#### 5. 手動#18は監視停止を証明できず、9.3の説明とも矛盾する

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:640`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:759`
- 戻った画面は新しいView stateになり得るため、そのEventsが増えなくても、離脱した旧Viewのobserverが停止した証明にならない。9.3自身もUIから判定不能としている。
- #18を手動DoDから外し、manager / observerのtokenやcallbackを直接観測できるintegration testへ一本化すること。

#### 6. M-14の二重報告なしを判定する期待結果がない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:670`
- M-14は「通知経路で報告済みの変更がforeground checkで再報告されない」ことが要件だが、v3は操作列だけでevent countと`checkForegroundChange`結果の組を定義していない。
- baselineを確立してStart Observingした上で、foreground復帰時にnotificationでEventsが1増えた場合はCheckがfalseとなり、同一変更でEventsが2回増えないことを期待結果として記載すること。

#### 7. unsupported-only用のFiles fixtureはaccepted typeを広告しない保証がない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:643`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:650`
- Files由来providerは`public.file-url`やpreview imageなども広告し、accepted typeの`public.url` / `public.image`へ適合する可能性がある。「対応外型のみ」を決定的に作れるとは限らない。
- providerの広告UTIを実測して固定外部fixtureを指定するか、#21も決定的なharness / library testへ委譲すること。不確実なままなら「要検証」と明記すること。

#### 8. M-13は設計v4の受け入れ条件に対して部分実施である

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:669`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:686`
- 設計v4のM-13は経路比較だけでなく`maxImagePixelCount`の妥当性確認も要求する。
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1543`
- unit testは境界判定の正しさを確認できるが、100 MPという上限値自体が端末性能上妥当かは確認できない。
- サンプルの通常fixture測定を「部分実施」とし、上限値の性能妥当性はT-13 harnessへ明示的に移管すること。

### 低優先度

#### 1. File fixtureのpayloadと期待sizeが未確定

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:284`
- `.customData(_, utType: "public.data")`の`_`を固定byte列へ置き換え、U-11で期待する`fileSize`を具体値にすると判定が明確になる。

#### 2. `public.data` fixtureのend-to-end成功はまだ実測されていない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md:297`
- provider選択が成立することは実装から確認できるが、既存file load testは`registerFileRepresentation`したproviderを使っており、`UIPasteboard.items`へDataを書いた後の`itemProviders → loadFileRepresentation`経路とは異なる。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift:98`
- 「決定的に成功」と断定せず、U-11をend-to-end受け入れ試験として扱うこと。失敗時はFiles由来の既知file representationなどへfixtureを切り替える判断を記載するとよい。

## 不足項目

- `checkForegroundChange`のbaseline初期化を含むT-00 case 4 / 10手順
- T-00必須のM-16（append privacy継承）と2台検証手順
- create / background維持 / non-remove / terminateを含むM-08手順
- iOS 18 / iOS 26 × 許可プロンプト / アクセス通知の観測結果テンプレート
- M-14のevent countとforeground check結果を組み合わせた判定規約
- operation固有labelまで待つUI test helper
- active-session cleanup除外とM-13上限値妥当性のharness移管

## 総合評価

v3は前回レビューv2の全指摘を丁寧に反映し、file所有権、T-00の大部分、Paste Control、XCUITest、observer異常系の設計は大きく改善した。

一方、`checkForegroundChange`の初回falseという状態契約が手順へ反映されず、T-00 case 10はReadへ到達しない。M-16はT-00から欠落し、M-08は対象pasteboardを作らないままunavailableを確認するため偽陽性になる。

**現状は高優先度3件の修正後に実装へ進むべきである。** その上で、T-00のOS別記録、UI testの双方向scrollとstale-result対策、M-12 / M-13 / M-14の受け入れ境界を具体化すれば、検証能力を伴う実装計画になる。
