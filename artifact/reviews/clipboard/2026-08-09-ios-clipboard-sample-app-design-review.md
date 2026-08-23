# レビュー結果

- 日付: 2026-08-09
- 対象ファイル: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- 参照企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 参照設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 参照実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review-v3.md`

---

## 強み

- 前回レビューv3の高3件・中8件・低2件は、すべて対応方針として反映されている。
- `checkForegroundChange`のtracker未作成時の初回falseをコード付きで説明し、case 10にbaseline確立を追加している。
- M-16をT-00へ戻し、識別可能なbody / append fixture、2台手順、D-8 / R-13への帰結を定義している。
- M-08をcreate、read成功、background維持、non-remove、terminate、no-create read失敗の一続きへ変更し、以前の偽陽性を解消している。
- T-00にiOS 18 / iOS 26 × 許可プロンプト / アクセス通知の観測軸を追加している。
- operation markerとpayloadの同時待機、双方向scroll、最大試行後の明示failにより、UI testの主要な偽陽性・停止不能要因を抑えている。
- M-12 / M-13 / 監視停止について、サンプルで観測できる範囲とharnessへ委譲する範囲を明確に分離している。
- `public.data`のend-to-endを未実測として扱い、固定64-byte payloadとU-11の受け入れ試験を定義している。
- Error Cases 11件はbutton固有marker、固定入力、正式errorCodeまで一致している。

## 改善点

### 高優先度

#### 1. M-16が`localOnly`単独と`append`の影響を分離できず、結論を誤る

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:627`
- 現在は端末Aで`localOnly: true` copy直後にappendし、その後で初めて端末Bを確認する。この順序では、次を区別できない。
  - `localOnly: true`自体が効かなかった
  - `localOnly: true`は効いたが、appendが既存bodyを含むpasteboard全体を再公開した
- 観測分岐も2 bitの4通りのうち「bodyだけ転送」を欠き、「copy本体も転送」を一括してlocalOnlyの異常としている。両方転送はappendによる全体再公開の可能性もある。
- 次の順序へ変更すること。
  1. Aで`localOnly: true` bodyをcopy
  2. **append前にBでbodyが転送されないことを確認**（M-06 negative control）
  3. Aでappend markerを追加
  4. Bで再確認
  5. `bodyTransferred` / `appendTransferred`の2 bitを記録
- 結果表は、none / append only / body only / bothの4通りを網羅し、それぞれD-8 / R-13への帰結を定義すること。

#### 2. T-00 case 4とcase 10でbaseline準備を共通化するとprivacy測定を汚染する

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:596`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:610`
- 企画書case 4の目的は、他アプリ由来の内容がある状態で`changeCount`だけを読んだときの許可プロンプト / アクセス通知を観測することであり、Boolの変化検出ではない。
  - `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md:389`
- case 4の前にbaseline確立用Checkを行うと、それ自体がprivacy契機だった場合に許可状態を変え、本番観測が偽陰性になる。
- case 4はfreshな許可状態で「外部copy → 初回Check」とし、戻り値falseは無視してprompt / notificationだけを記録すること。
- baselineの事前確立は、background差分を検出するcase 10だけに限定すること。6.1のcase 4にある「baseline確立が前提」を削除し、6.2でも両ケースを別手順として記載すること。

#### 3. U-10がM-08の「background中は解決可能」を自動化していない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:737`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:887`
- 手動#25はbackground / foreground後の2回目Read成功を必須としているが、U-10はcreate → copy → Read成功から直ちにterminateしている。
- 設計v4のM-08は「background中は解決できる」と「送信側終了後は解決できない」の両方を要求する。
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1538`
- U-10へhome/background → app activate → 2回目Read成功を追加し、その後にnon-remove terminate → relaunch → unavailableを確認すること。

### 中優先度

#### 1. UI側の「初回Check」とmanager内部trackerの有無が一致しない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:450`
- v4はView側でscopeごとの「Checkを押したこと」を保持し、初回だけ`baseline established`と表示する。しかしmanagerのtrackerは次でも作成・更新される。
  - `startObserving`時の`resync`
  - notification受信時の`markReported`
  - 前のView instanceでのCheck
- 逆に解決不能scopeでは`execute`がfalseを返してもtrackerは作られないため、UIだけが`established`と表示する可能性がある。
- `baseline established`をmanager内部状態の断定に使わず、例えば`first UI check; baseline updated`へ弱めること。case 10ではgeneral scope・Start Observing前という前提を固定し、1回目の戻り値にかかわらず「この呼び出し後のchangeCountが比較基準になった」と扱うこと。

#### 2. M-14がCheck後の遅延notificationによる二重報告を見逃す

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:822`
- v4はeventが届かなければCheck=trueを正常分岐とするが、Check後に遅延notificationが届くと同じ変更がBoolとeventの2経路で報告される。Events自体は1しか増えないため、「Eventsが2回増えない」という条件だけでは検出できない。
- `reportCount = eventDelta + (checkResult ? 1 : 0)`を定義し、Check後にもsettle期間を置いた最終値が**必ず1**であることを要求すること。
- foreground復帰後は一定時間notificationを待ってからCheckし、Check後もlate notificationの有無を観測する手順を追加すること。

#### 3. button単位markerだけでは同じ操作の再実行時にstale結果を拾う

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:934`
- marker + payloadが前回と同じ操作では、古いlabelがそのままpredicateへ一致する。U-10へbackground後の2回目Readを追加すると、同じ`[read]`と同じ成功payloadを待つため具体的に発生する。
- tap前labelから変化したことのassertを「必要に応じて」ではなく必須にするか、operation invocationごとのsequence IDをresultへ含めること。

#### 4. UI testの直列実行がscheme設定と一致しない

- 対象:
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:964`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:694`
- 計画はClipboard UI testを直列実行するとしているが、既存schemeでは`IosLibraryExampleUITests`が`parallelizable="YES"`である。
  - `ios/IosLibraryExample/IosLibraryExample.xcodeproj/xcshareddata/xcschemes/IosLibraryExample.xcscheme:46`
- 単一test class内で順次実行されることを根拠付きで保証するか、scheme / test planでparallelizationを無効化すること。設定変更する場合はxcschemeまたはtest planを変更ファイル一覧へ追加すること。

#### 5. M-16の観測結果を6.4へ保存できない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:651`
- 6.4はprompt / notificationの4列だけで、M-16の本体である`bodyTransferred`、`appendTransferred`、結論、D-8 / R-13判断欄を持たない。
- M-16専用のOS別結果表を追加し、少なくとも2 bitの転送結果、待機時間、Handoff設定、結論、追跡タスクを記録すること。

#### 6. M-16のfixtureを画面方針のまま区別する方法が未定義

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:633`
- 端末Bの`Read`はsecurity方針によりraw textを表示しないため、`LOCALONLY-BODY`と`APPENDED-MARKER-...`を文字列値で見分けられない。
- それぞれの固定文字数を異なる値にし、端末Bではitem index・text有無・文字数の組で判定するなど、raw valueを表示せず区別する方法を明記すること。
- `Copy (localOnly = true)`が実際に`LOCALONLY-BODY`を使うことも5.3で固定すること。

### 低優先度

#### 1. 実施不能なT-00ケースを空欄にすると未実施と区別できない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:663`
- 空欄では未着手、測定失敗、sample対象外を区別できない。`N/A (sample); harness: <result/ref>`のように移管状態と結果参照を記録すること。

#### 2. `public.data`代替fixtureへ切り替えた場合のU-11分類が未定義

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:365`
- Files由来fixtureへ切り替えると外部アプリ依存になり、現在の自動UI test U-11をそのまま維持できない。
- 切替時はU-11をmanual / harnessへ移し、自動試験では失敗理由を記録する条件を追加するとよい。

#### 3. operation marker一覧が全操作で明示されていない

- 対象: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v4.md:252`
- 「すべての結果にbutton固有marker」としているが、Copy、Copy Options、Append、Detectの表にはmarker列がない。
- 実装差を防ぐため、全結果生成操作のmarkerを一覧化するか、accessibility action名から機械的に導出する規約を定義するとよい。

## 不足項目

- M-16のappend前negative controlと4通りの転送結果
- case 4をfresh privacy観測、case 10をbaseline差分検出として分けた手順
- background / foreground成功を含む完全なU-10
- manager trackerとUI-local stateを混同しないCheck表示契約
- M-14の最終`reportCount == 1`判定
- invocation単位のstale-result防止
- schemeのparallel test設定と計画の直列実行方針の一致
- M-16のOS別転送結果・結論記録欄

## 総合評価

v4は前回レビューv3の全指摘を丁寧に反映し、T-00、M-08、M-12〜M-14、file fixture、UI testの検証能力は大きく改善した。

ただし、M-16はappend前のnegative controlがないためlocalOnlyとappendの影響を分離できず、転送結果も4通りを網羅していない。case 4はcase 10と異なりprivacy契機そのものの観測であるため、事前baseline操作を入れてはいけない。U-10もM-08のbackground維持確認を欠いている。

**現状は高優先度3件を修正してから実装へ進むべきである。** その上で、manager / UI baseline表示の境界、M-14のlate notification、invocation単位のUI待機、schemeの並列設定、M-16の記録方法を具体化すれば、実装着手可能な計画になる。
