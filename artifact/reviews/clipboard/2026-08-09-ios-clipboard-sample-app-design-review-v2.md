# レビュー結果

- 日付: 2026-08-09
- 対象ファイル: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md`
- 機能名: clipboard sample app
- 対象 OS: iOS 18 以降
- 参照企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 参照設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 参照実装: `ios/IosLibrary/IosLibrary/Clipboard`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-09-ios-clipboard-sample-app-design-review.md`

---

## 強み

- 前回レビューの高3件・中6件・低3件は、すべて方針として反映されている。
- T-00 case 4をfreshなprivacy観測、case 10をbaseline差分検出として分離し、case 4を事前Checkで汚染する問題を解消している。
- U-10へbackground / foreground後の2回目Readを追加し、M-08の「background中は解決可能」を自動試験へ含めている。
- M-14は`reportCount = eventDelta + (checkResult ? 1 : 0)`とCheck後のsettleを導入し、遅延notificationによる二重報告を判定できる。
- UI testのstale result対策としてinvocation sequenceを導入し、schemeの`parallelizable`を`NO`へ変更するファイルまで明示している。
- M-16はappend前のnegative control、raw値を表示しない14文字 / 24文字fixture、OS別の結果欄を追加している。
- 実施不能なT-00ケース、`public.data`不成立時のU-11、Paste Controlのpartial / all failureについて、sample・manual・harness・library testの境界が明確である。
- package identifierは`com.jonghyunkim.nativetoolkit`系で統一され、禁止された`jp.ubint`表記はない。

## 改善点

### 高優先度

#### 1. M-16は3つの観測値を必要とするのに、2 bit / 4通りへ縮約している

- 対象: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:682`
- 手順と6.5は、次の3値を別々に記録している。
  - `bodyBeforeAppend`: append前にbodyが端末Bへ現れたか
  - `bodyAfterAppend`: append後にbodyが端末Bへ現れたか
  - `appendAfterAppend`: append後にmarkerが端末Bへ現れたか
- しかし6.3の結果表は曖昧な`body` / `append`の2列しか持たない。実際、行#4自身が「手順4で非転送だった場合」と「手順4ですでに転送済みの場合」に再分岐しており、2 bit表ではないことを示している。
- `bodyBeforeAppend`がfalseで`bodyAfterAppend`がtrueなら、appendが既存bodyを再公開した可能性がある。両者を単一の`body`へ潰すと、`localOnly`単独の挙動とappend後の挙動を再び混同する。
- 結果表を`bodyBeforeAppend` / `bodyAfterAppend` / `appendAfterAppend`の3列へ変更し、到達可能な組合せと異常な組合せごとにD-8 / R-13への帰結を定義すること。6.5も同じキー名へ統一すること。

#### 2. M-16に正の対照と端末Bの事前条件がなく、「転送なし」を継承成功と誤判定しうる

- 対象:
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:677`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:709`
- 現在の手順は端末AだけをClearし、30秒後に端末BをReadする。次の状態はいずれも`body=false / append=false`に見える。
  - `localOnly`とappendが期待どおり非転送だった
  - Handoff / Universal Clipboardがその試行で機能していなかった
  - 端末Bの貼り付け許可が拒否・未確定だった
  - 待機時間が不足していた
- 逆に、端末Bの既存clipboardに14文字または24文字のtextがあると、文字数だけの判定は偽陽性になる。
- 同一2台・同一接続条件・同一セッションで、最初に`localOnly=false`の正の対照が端末Bへ届くことを確認すること。その後、端末Bの事前clipboardに対象signatureがないことと貼り付け許可状態を固定・記録してからM-16を実施すること。
- 端末BをClearする場合は、その操作の同期影響が収束してから端末Aのtrialを開始すること。固定14 / 24文字との衝突をpreflightで排除するか、run固有で衝突しにくい長さ・構成を使うこと。
- 6.5へ、正の対照結果、端末Bの事前signature、貼り付け許可状態、両端末のOS build / 端末、同一iCloud、Wi-Fi / Bluetooth、実待機時間を追加すること。これらを満たさない`none`から「R-13不要」と結論してはならない。

#### 3. 初回UI Checkが実際の戻り値を捨て、baseline更新も誤って断定する

- 対象:
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:488`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:986`
- v5は、managerのtrackerとView内の初回状態が一致しないことを正しく説明している。それにもかかわらず、View内の初回表示を常に`changed=false (first UI check; baseline updated)`へ固定している。
- trackerが前のView、`startObserving`の`resync`、notificationの`markReported`で既に作成され、その後にchangeCountが変わっていれば、View内の初回Checkでも実戻り値はtrueになりうる。falseへ固定すると検出結果を隠す。
- 解決不能scopeでは`CheckForegroundChangeUseCase.execute`が早期returnし、trackerを更新しない。それでも`baseline updated`と表示されるため、文言も事実と一致しない。
- 常に実戻り値の`changed=<bool>`を表示し、View内初回は`(first check in this screen)`のようなUI-local注記だけを加えること。公開Bool APIでは成功と解決不能を区別できないため、`baseline updated`は削除すること。
- U-12は、fresh process・general scope・未観測という条件で実際のfalseを検証するか、初回注記と実戻り値がそのまま表示されることだけを検証すること。

### 中優先度

#### 1. invocation sequenceの単調増加範囲と再起動後の初期値が未定義

- 対象:
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:246`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:993`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:1063`
- `resultSequence`は`@State`なので、View再生成やprocess再起動をまたぐグローバル単調値ではない。U-10は`terminate()` / `launch()`をまたぐため、終了前のseqを`after`として保持すると、再起動後に0から始まるseqが超えられずtimeoutする。
- 「単調増加」は同一View / process epoch内の契約と明記すること。launch後は旧seqを破棄し、初期placeholderを0またはnilとして再取得してからtapする手順を定義すること。代案はsession UUID + seqをmarkerへ含めること。
- `currentResultSequence()`について、resultがまだ存在しない場合、placeholderの場合、parse不能の場合の扱いも定義すること。

#### 2. U-10が前回実行の固定named pasteboard残存と終了直後の削除遅延を排除していない

- 対象: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:993`
- 固定名を使うため、前回失敗したUI testがpasteboardを残していると、今回のcreate / readが新規作成によるものか判別できない。
- test開始時に固定pasteboardをcreate → remove → no-createでunavailable確認してからfresh createすること。
- terminate後のno-create Readを1回だけ実行すると、OS側の終了処理との競合で不安定になりうる。上限時間つきpollで`CLIPBOARD_UNAVAILABLE`を待ち、timeout時は最後の状態を記録すること。

#### 3. case 4の画面表示自体がclipboard-aware UIを初期化しない保証がない

- 対象: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:645`
- case 4は「他の操作を一切行わず、初回Checkだけ」を要求するが、同じ画面には`UIPasteControl`が存在する。controlのtarget / paste configurationに応じてsystemがenabled状態を評価するため、厳密には`changeCount`だけにprivacy挙動を帰属できない可能性が残る。
- case 4専用起動引数・表示modeでPaste Controlを生成しない、または当該sectionを明示操作まで遅延生成することが望ましい。
- 少なくとも、画面mount時にmanager初期化以外のclipboard read / preflight / Paste Control生成が行われないことを検証し、case 4の前提として記録すること。

#### 4. M-16の記録単位が片側OSの列になっており、2台の組合せを表現できない

- 対象: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:745`
- 現在は列をiOS 18 / iOS 26、行を「端末BのOSバージョン」としているが、Universal Clipboardは端末A / Bの組合せに依存する。AがどのOS / buildなのか記録できず、列のiOSがどちらの端末を表すかも曖昧である。
- 1試行を1行とし、trial ID、A端末 / OS build、B端末 / OS build、接続条件、許可状態、正の対照、3つの観測値、結論を列に持つ形式へ変更すること。

### 低優先度

#### 1. marker一覧の件数と`cancelLoads`の位置づけが一致しない

- 対象:
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:279`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:410`
- 一覧を数えると、Scope 6 + Copy 12 + Copy Options 3 + Append 3 + Read 4 + Load 5 + Detect 2 + Observe 3 + Clear 1 + Error 11 = **50件**である。操作総数を明記する場合は、この内訳と一致させる必要がある。
- `cancelLoads`を「すべての結果」のmarker一覧へ含めている一方、Cancel操作はload completionの結果を待つcontrol APIであり、`[cancelLoads]`結果を生成する契約が書かれていない。Cancelがresultを即時上書きすると、後続の`.cancelled` completionと競合する。
- 結果生成操作とcontrol-only操作を分け、`cancelLoads`はbutton identifierだけを持つcontrolとして定義すること。Paste Controlは別の`pastedSummary`更新経路であることも一覧上で区別すること。

#### 2. U-2 / U-11の期待文字列が実際の表示形式と一致しない

- 対象:
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:976`
  - `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md:985`
- 実形式は`✅ #<seq> [read] ...`なので、U-2の`✅ [read]`やU-11の`✅ [loadFile]`は連続substringとして存在しない。
- 期待値を`marker=read` / `marker=loadFile`とpayload条件へ分け、9.4の`waitForResult(after:marker:contains:)`を使う表記へ統一すること。

## 不足項目

- M-16の3観測値に基づく結果モデル
- M-16と同一条件でのUniversal Clipboard正の対照
- 端末Bの事前clipboard、貼り付け許可、両端末OS / buildを含む試行記録
- 実戻り値を失わないCheck表示と、解決不能時にbaseline更新を断定しない文言
- process / View epochをまたぐinvocation sequenceの規約
- U-10の前回残存排除と終了後unavailableの上限つき待機
- case 4で画面mountの影響を排除または記録する条件

## 総合評価

v5は前回レビューの全指摘を丁寧に反映しており、case 4 / case 10、M-08、M-14、stale result、UI test並列化、sampleとharnessの境界は実装着手に近い精度になっている。

一方、M-16はappend前後で実際には3つの値を観測する設計なのに、結論表だけが2 bitへ縮約されている。また、正の対照・端末Bの事前状態・許可条件がないため、Handoff不調や既存clipboardをprivacy継承の結果として誤判定しうる。初回Checkも、manager状態とView状態が一致しないと認識しながら実戻り値をfalseへ固定している。

**現状は高優先度3件を修正してから実装へ進むべきである。** 中優先度4件は主に試験の再現性と測定帰属に関するため、高優先度と同じv6で具体化することを推奨する。
