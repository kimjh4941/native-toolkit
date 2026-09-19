# レビュー結果

- 日付: 2026-08-08
- 対象ファイル: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- 参照企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 参照設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 参照実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review.md`

---

## 強み

- 前回レビューの高優先度4件は、24ケースの正式エラーコード表、`.file`所有権と削除helper、XCUITest計画、T-00ケース12〜15の専用harness分離として反映されている。
- Error Casesの11操作は実装の`ClipboardError.errorCode`と一致し、不正UTI、不正URL、不正色などの固定入力も到達根拠まで明記されている。
- 外部由来のclipboard値、URL、path、pasteboard名を画面にもログにも出さず、件数・長さ・kind・errorCodeだけを扱う方針が一貫している。
- P-11のキャンセルについて、callerへの`CLIPBOARD_CANCELLED`、`Progress.cancel()`の試行、late resultの破棄、OS処理中断の非保証を分離できている。
- named scopeのcreateなし参照、remove後probe、観測中のscope操作無効化、`onDisappear`時の停止が具体化され、前版の状態遷移不足が解消されている。
- Paste Controlがgeneral pasteboard固定であること、生成失敗の非同期通知、部分成功の集約表示が明記されている。
- UI testの自動化対象と実機・外部アプリ依存の手動対象を分け、表示文字列ではなくaccessibility identifierで操作する方針を採っている。
- Detection fixtureについて、11パターンすべての検出を断定せず、OS・locale・fixtureの切り分けを要検証として残している。

## 改善点

### 高優先度

#### 1. `Copy Custom Data`から`Load File (public.data)`が成功する保証がない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:342`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:606`
- `Copy Custom Data`は未登録の`com.jonghyunkim.nativetoolkit.example.custom`というidentifierだけでDataを書き込む。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardMappers.swift:90`
- `.file(utType:)`は、providerが要求identifierへconformするときだけ対象を選ぶ。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift:127`
- syntacticに許可された未登録custom UTIが`public.data`へconformする宣言はないため、手動確認#11は`CLIPBOARD_NO_MATCHING_ITEM`になり得る。この場合、#12のcaller cleanup経路にも到達しない。
- `Load File`を`.file(utType: Self.customTypeIdentifier)`へ変更し、CopyとLoadで同じ定数を使うこと。`public.data`を維持するなら、実際に`public.data`として書き込む専用fixtureを追加すること。

#### 2. T-00対応表がなお複数ケースを「実施可能」と過大評価している

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:536`
- 企画書の16ケースは「直前の状況」と「操作」の組であり、同じAPIを押せるだけではケースを満たさない。
  - `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md:384`
- 現在の表には少なくとも次の不一致がある。

| ケース | v2の記載 | 問題 |
|---|---|---|
| 1〜3 | 自アプリcopy → Read | case 2は他アプリ由来のbody read、case 3は他アプリ由来でbodyを読まないinspectであり、case 1と同一手順ではない |
| 5〜6 | Detect button | 企画書は他アプリ由来を前提とするが、通常手動手順は自アプリのfixture copyを前提としている |
| 7 | Paste Control tap | 現在のcontrolはtap後に必ずreceiver内のloadへ進むため、case 16の「tap → load」と分離できない |
| 8 | receiverがresponder chainに入るため可 | 標準編集menuを表示し、receiverをfirst responderとしてpasteを実行するUI導線がない。hierarchy参加だけでは実施手順にならない |
| 10 | Check Foreground Change | 企画書はchangeCount比較後、変化時のbody readまで要求するが、表は比較だけで完了としている |

- 対応表を「直前の状況 / サンプル操作 / 判定 / 実施可否」の4列へ改めること。case 1〜3を分割し、外部copyを明記すること。
- case 7と16を分離できないなら経路全体のcase 16だけをサンプルで観測し、case 7・8・12〜15をT-00 harnessへ移すこと。case 8をサンプルで扱うなら、標準編集menuを起動できる明示的なpaste受信UIとfirst-responder手順が必要である。
- case 10は`Check Foreground Change`がtrueのときだけ`Read`するところまで手順化すること。

#### 3. Paste Controlの「対応外型のみ → all failure」は実装上到達しない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:484`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:616`
- receiverの`canPaste`は、providerにaccepted typeが1件もなければ`false`を返す。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteReceiverView.swift:42`
- そのため「他アプリで対応外の型のみをコピー」した場合はPaste Controlが無効になり、`paste(itemProviders:)`も`onPasteFailure`も呼ばれない。`items=0, failures=1`という期待結果には到達しない。
- 対応外型のみの期待値を「controlが無効、callback 0回」へ訂正すること。
- all failure / partial failureを確認するには「accepted typeを宣言するがloadに失敗するprovider」が必要である。通常サンプルで決定的に作れないなら、ライブラリunit/integration testへ委譲し、サンプルの手動DoDから外すこと。

### 中優先度

#### 1. accessibility identifierの単一情報源がUI test targetから参照できる構成になっていない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:570`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:653`
- v2は`ClipboardSampleIdentifiers`をapp targetの`ClipboardSampleView.swift`内に置き、ViewとUI testの双方から参照するとしている。
- XCUITest bundleはappとは別target・別processであり、app targetのinternal enumをそのまま参照する前提にはできない。現行UI test fileも`XCTest`だけをimportしている。
  - `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift:8`
- 次のどちらかに確定すること。
  - app側だけをenumで一元化し、UI test側は契約済みidentifier文字列をprivate定数として持つ。
  - identifier専用Swift fileを両targetへ所属させ、必要なproject設定変更も変更ファイル一覧へ含める。

#### 2. UI testの非同期待機とScrollView操作が不足している

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:693`
- `waitForExistence`はelementの出現だけを待ち、既に存在する`clipboard.result`や`clipboard.status`のlabel変更は待たない。async API結果や観測eventを即時部分一致で読むとflakyになる。
- Error Casesなど画面下部のbuttonについて、off-screen elementを確実に表示してからtapする方法も未定義である。
- `XCTNSPredicateExpectation`または`XCTWaiter`でlabelの期待値を待つhelperと、`isHittable`になるまでscrollするhelperを計画へ追加すること。
- U-5はEvents増加をstatus labelのpredicateで待ち、停止後は短いsettle期間を置いてevent countが変わらないことを比較するなど、positive / negative assertionを分けること。

#### 3. 一時ファイルの手動確認でrequest directoryとsession directoryを混同している

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:607`
- `consumeLoadedFile`が削除するのは返却URLの親であるrequest directoryであり、session directoryではない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/File/ClipboardTemporaryFileStore.swift:13`
- active session directoryは残り得るため、「返却されたsession directoryが残っていない」を期待すると正常実装を失敗扱いする。
- #12を「`<sessionID>/<requestID>`のrequest directoryが残らない。active session directory自体の残存は許容」へ訂正すること。

#### 4. M-12 / M-13を実施可能とするためのfixtureと手順がない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:635`
- M-12は「他sessionかつ24時間より古いdirectory」を用意し、別processの最初のfile store初期化を起こす必要がある。単なる時刻操作だけでは、残留物の作成・app強制終了・再起動後の初回load・削除確認という前後条件が不足する。
- M-13で64 MiB / 100 MP境界も扱うとしているが、画面が提供するのは小さなbundle画像だけであり、境界fixtureの生成・import手順がない。1.5の「サンプルでは扱わない」とも表現が揺れている。
- M-12は専用実機手順を追加するかT-13側のharnessへ委譲すること。M-13は通常fixtureでのInstruments計測とlimit境界unit testを分離し、「境界を本サンプルで扱う」という記載を撤回すること。

#### 5. cleanup失敗を成功表示だけで終えるとサンプルから契約違反を検出できない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:365`
- 削除失敗をconsole logだけへ出し、load自体を成功表示にすると、手動確認者はstorage leakを結果領域から識別できない。
- load成功とcleanup失敗を区別し、例えば`fileSize=<n>, cleanup=failed`を警告表示すること。pathは不要であり、秘匿方針を維持できる。

#### 6. 自動化可能なError Casesと再起動ケースが手動へ残されている

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:676`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:685`
- Error Cases 11件はすべて固定入力であり、4件だけに絞る技術的理由がない。workflowの「自動化可能な手動観点をUI testへ実装する」という条件に対し不足する。
- named pasteboardの非永続性も、`XCUIApplication.terminate()`後に再`launch()`し、`Use Fixed Named Scope (no create)`を押せるため、「1セッションで完結しない」は自動化除外理由にならない。
- U-9はBack後のno-crashしか確認せず、対応先にした手動#18の「監視が停止する」を検証していない。
- Error Cases 11件を全自動化し、M-08のterminate / relaunchテストを追加すること。U-9は#18との対応を外し、監視停止は手動または状態を観測できるintegration testへ割り当てること。

#### 7. Observeの異常系操作でmanagerと画面の観測状態が不一致になり得る

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:512`
- `startObserving`は新しいscopeを解決する前に既存観測を停止する。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:326`
- 観測中にError Casesの`Observe Unresolvable Named`を押すと、manager側は既存観測を停止してからthrowする一方、画面の`isObserving`は`true`のまま残り、Start / StopとScope buttonの活性状態が実態とずれる。
- 当該Error Caseを観測中は無効化するか、実行前に`stopObserving()`と`isObserving = false`を行うこと。catch時の状態更新も明記すること。

### 低優先度

#### 1. 非`ClipboardError`の生成失敗mappingが擬似コードのままである

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:465`
- `.unknown(...)`は実装可能な式ではない。`ClipboardError.unknown(ClipboardFailureDetail(systemError: error))`など、既存public initializerを使う形へ確定すると実装差が減る。

#### 2. UI testで「各テストの冒頭にClear」の具体的な初期化順が不足している

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md:695`
- `Clear Active Scope`はClipboard画面内の下部buttonなので、launch直後には操作できない。
- `launch → menu遷移 → Clear buttonまでscroll → clear完了をwait → 対象sectionへ移動`を共通setup helperとして明記するとよい。

## 不足項目

- custom UTIのCopyから確実に`.file` loadへ到達する同一identifierのfixture
- T-00ケース1〜16の直前状態を含む正確な対応表と、case 7 / 8の実施境界
- Paste Controlのunsupported-only、all failure、partial failureを区別した期待契約
- app targetとUI test target間のaccessibility identifier管理方針
- label変化待機、off-screen button操作、観測停止後のnegative assertionを含むUI test helper
- 固定Error Cases全件とterminate / relaunchを含む自動化範囲、および観測異常時のstate遷移
- request directoryとsession directoryを区別したcleanup確認
- M-12の残留session作成・再起動手順、およびM-13のfixture範囲

## 総合評価

前回レビューの高優先度4件と中・低優先度の大半は適切に反映され、エラー契約、値の秘匿、キャンセル、scope状態、UI test導入方針は大きく改善した。

一方、固定シナリオの`Copy Custom Data`から`Load File (public.data)`はUTI conformanceを保証できず、file cleanup確認まで到達しない可能性がある。またT-00はcase 1〜3、7、8、10の前提・操作を正確に再現できず、Paste Controlのunsupported-onlyケースも期待callbackへ到達しない。

**現状は高優先度3件を修正してから実装へ進むべきである。** それらを直した上で、UI test target境界・自動化範囲・非同期wait、観測異常時のstate遷移、request/session directoryの用語、M-12/M-13の実施手順を具体化すれば、実装可能で検証結果を誤判定しにくい計画になる。
