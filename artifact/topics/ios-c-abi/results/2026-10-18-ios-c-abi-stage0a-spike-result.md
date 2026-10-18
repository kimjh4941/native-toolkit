# 段階 0a のスパイクの結果: XCUITest で扱える項目

- 記録日: 2026-10-18
- 段階: 0a（`README.md` 5 章、7.2）
- 状態: **完了**（シミュレーターは 2〜6 章、実機（iPhone XS、iOS 18.7.2）は利用者の許可を得て 7 章。通知センターの操作は実機とシミュレーターで効き方が逆になると分かり、R-3 を 7.3 で改めた）
- 試したコード: `probes/stage0a/`（`Stage0aProbeTests.swift`、`run.sh`、`stability.sh`、`noscene/`）。動かし方は `probes/README.md`。テストのターゲットからは外した（グループはファイルシステムと同期する形なので、`project.pbxproj` は変わっていない）
- 製品のコード（`IosLibrary`、`UnityIosPlugin`）とサンプルの画面は変えていない

## 1. 環境

| 環境 | 版 | 表示の言語 |
|---|---|---|
| Xcode | 26.3（17C529） | - |
| シミュレーター（主） | iPhone 17、iOS 26.2 | en（地域 JP） |
| シミュレーター（版の差を見る） | iPhone 16、iOS 18.3.1 | **ja** |

2 台は表示の言語が違うので、システムの UI（springboard、権限、Share のシート）のラベルはそれぞれの言語で出る。プローブは両方の言語を受け付けるようにした。サンプルの Dialog のボタンの文字はアプリが渡す文字列なので、言語に左右されない。

## 2. 結論

- 次の項目は、XCUITest で自動化でき、**両方のシミュレーターで 3 回すべて通った**: Dialog（6 種）、通知の権限のダイアログ、通知のバナー（前面・背景）、バナーからのアクションのボタンとテキスト入力、通知センターを開いて通知を見つけること、通知からのコールドスタート、予約した通知の発火を待つこと、Share のシート（表示・Copy・Save to Files・閉じる・除外）、貼り付けの許可のダイアログ、`UIPasteControl`
- **自動化しないもの**:
  - 通知センターのセルを**タップ**して開くこと（両方の版で開かない。**右へスワイプすれば開く**ので、こちらを使う）
  - 通知センターのセルを**長押しして広げる**こと（18.3 では 1 回も広がらず、26.2 でも 5 回中 3 回。アクションのボタンはバナーから出せば安定する）
- **今のサンプルでは、通知を受け取ったことを確かめられない**。サンプルは通知のタップ・アクション・返信の文字を受けても `print` するだけで、画面に出さない。アプリの標準出力は xcodebuild のログに入らず、springboard から起動したとき（コールドスタート）は捨てられる。確かめられるのは、アプリが前面に来たことと、表示中の通知の件数が 0 になったことまで（4 章の R-1）

## 3. 項目ごとの結果

### 3.1 アプリ内の Dialog（`UIAlertController`）

| 項目 | 自動化 | 方法 | 18.3 と 26.2 の差 | 3 回 |
|---|---|---|---|---|
| alert / confirm / destructive | できる | `app.alerts["<題>"].buttons["<ボタン>"].tap()`。結果はサンプルの `staticTexts` を CONTAINS で読む | 無し | 3/3 |
| action sheet | できる | ボタンを押す。キャンセルは下の差のとおり | **26.2 では iPhone でも Popover で出て、Cancel のボタンが無い**。`PopoverDismissRegion`（label「dismiss popup」）を押すと Cancel の結果が返る。18.3 は Sheet で Cancel がある | 3/3 |
| text input | できる | `alert.textFields.firstMatch.typeText`。空のとき OK が無効なことを `isEnabled` で読める。日本語の入力も通った | 無し | 3/3 |
| login | できる | `textFields` と `secureTextFields` に入れる。ユーザー名だけでは Login が無効なことも読める | 無し | 3/3 |

### 3.2 通知の権限のダイアログ（初回の同意）

| 項目 | 自動化 | 方法・結果 |
|---|---|---|
| `addUIInterruptionMonitor` | できる | 権限の要求の後、アプリを操作したときに監視が呼ばれる |
| springboard から押す | できる | `springboard.alerts.firstMatch` が約 1.1 秒で出る。許可・拒否の両方の経路が通った（3/3） |
| 初めの状態に戻す | **アプリの削除だけ** | `simctl uninstall` の後は `notDetermined` に戻る |
| 前もって許可する | **できない** | `simctl privacy` の対象に通知が無く、`grant notifications` は「Operation not permitted」。`privacy reset all <bundle id>` でも通知は denied のまま。`XCUIProtectedResource` にも通知は無い。テストの準備で一度 Allow を押す |

**注意**: テストのハンドラが処理しないと、XCTest の「Default interruption handler」が **Allow を自動で押す**（両方の版）。ダイアログそのものを確かめるテストは、アプリを操作する前に springboard で明示的に処理しないと、権限が黙って許可される。

### 3.3 通知の表示

| 項目 | 自動化 | 方法 | 差 | 3 回 |
|---|---|---|---|---|
| 前面のバナー（`willPresent`） | できる | springboard の identifier `NotificationShortLookView`。label は「IOSLIBRARYEXAMPLE, now, <題>, <本文>」。約 1.1 秒で出る | 本文の identifier が 18.3 は `NotificationBody`、26.2 は `TextContent.Primary`。時刻の文字が「今」と「now」 | 3/3 |
| 背景のバナー | できる | ホームに戻って 5 秒の予約。約 4.5 秒後に見つかる | 無し | 3/3 |
| 通知センターを開いて見つける | できる | 上端（0.25, 0.005）から（0.25, 0.7）へドラッグ | 無し | 3/3 |
| 通知センターから開く | **タップでは開かない** | タップ（セル・内側のボタン・題・座標・2 回）はどれも開かない。`swipeRight()` で開く。開いた後の表示中の通知は 0 件 | 無し | swipeRight は 3/3 |
| バナーをタップして開く | できる | ホームに出たバナーをタップ | 無し | 3/3 |
| アクションのボタン | できる（バナーから） | バナーを 1.5 秒長押しするか下へドラッグすると、Open・Delete・Reply が出る。Open で前面に来る。背景で Delete を押すとアプリは背景のまま | 無し | 3/3 |
| 通知センターのセルを広げる | **不安定** | 長押し（1.5 / 2.5 / 3 秒、内側のボタン、座標） | 18.3 は 0 回、26.2 は 5 回中 3 回 | 不安定 |
| テキスト入力のアクション | できる（操作まで） | Reply で出るのは TextField ではなく **TextView**（placeholder「Type a message」）。`typeText` で入れて Send | 無し | 3/3 |

### 3.4 通知からのコールドスタート

| 項目 | 自動化 | 方法 | 3 回 |
|---|---|---|---|
| 通知センターから | できる | `app.terminate()` の後、通知センターを開いてセルを `swipeRight`。起動まで 26.2 は約 3.1 秒、18.3 は 0.7〜0.8 秒 | 3/3 |
| 止めた後に発火したバナーをタップ | できる | 5 秒の予約 → terminate → バナーが出る（アプリは notRunning）→ タップ | 3/3 |
| バナーの Open（止めた後） | できる | 長押しして Open | 3/3 |
| 通知センターの Open | 不安定 | セルを広げる操作が要る（3.3） | 26.2 で 1/3、18.3 は不可 |
| アプリが受けたこと | **確かめられない** | 起動した後の画面はメインメニューのままで、受けたことの表示が無い（R-1） | - |

### 3.5 予約した通知

10 秒・5 秒の time interval の予約は、`waitForExistence(timeout: 25)` で待てる。10 秒の予約は 10.1〜10.2 秒で出た（26.2 の最初の実験で 1 回だけ 11.2 秒）。カレンダーと位置の予約は試していない。

### 3.6 Share のシート（`UIActivityViewController`）

| 項目 | 自動化 | 方法 | 差 | 3 回 |
|---|---|---|---|---|
| 表示と Copy | できる | Copy は約 1.1 秒で出る。押すと `completed=true`、`activityType=com.apple.UIKit.activity.CopyToPasteboard` | 26.2 は identifier が `shareCell` / `actionGroupCell`。18.3（ja）は「“ファイル”に保存」など日本語（Copy は英語のまま） | 3/3 |
| Save to Files | できる | Files のピッカーで Save を押すと `com.apple.DocumentManagerUICore.SaveToFiles`。2 回目からは置き換えの確認が出る | **18.3 のシミュレーターでは「置き換え」が「Trash に移動できません」で失敗し、完了が返らない**。「両方とも残す」なら通る | 3/3（両方とも残す） |
| 閉じる | できる | 18.3 は「閉じる」のボタン。**26.2 は Popover で Close が無い**ので `PopoverDismissRegion` を押す。シートの上端を下へドラッグする方法は両方で通る。結果は `completed=false` | 上のとおり | 3/3 |
| 除外 | できる | 除外を指定すると Copy が無いことを確かめられる | 無し | 3/3 |

### 3.7 クリップボード

| 項目 | 自動化 | 方法・結果 |
|---|---|---|
| 今の Clipboard の UI テスト（22 件） | 通る | 21 件が成功、1 件は意図した skip（U10b）。**1 回に 51〜53 分**かかるので、3 回は流していない。どのテストもアプリ自身が書いてから読むので、貼り付けの許可のダイアログは出ない（外から書いた内容が残っていても 0 回） |
| 貼り付けの許可のダイアログ | できる | テストランナーか `simctl pbcopy` で書いた後にアプリで読むと、springboard に「would like to paste from …」が出る。「Allow Paste」で読める（3/3）。「Don't Allow」の経路は試していない |
| `UIPasteControl` | できる | label「Paste」のボタンをタップすると読める。ダイアログは出ない（3/3） |

### 3.8 scene と key window

| 項目 | 結果 |
|---|---|
| サンプル | SwiftUI の `App` と `WindowGroup`。scene がある |
| Unity 6000.4.2f1 | 書き出したアプリの Info.plist に `UIApplicationSceneManifest` があり、`UISceneDelegateClassName` は `UnityScene`。scene がある |
| ライブラリの探し方 | `IosDialogManager.getRootViewController` と `ShareSheetPresenter` は同じ処理（foregroundActive の `UIWindowScene` → key window → `presentedViewController` をたどる） |
| scene の無い構成 | 使い捨ての UIKit のアプリ（`probes/stage0a/noscene/`。manifest 無し、AppDelegate が window を持つ）で確かめた。UIKit が暗黙に `UIWindowScene` を 1 つ作り、foregroundActive になる。Dialog と Share の表示が成功した（18.3 と 26.2 で 1 回ずつ、起動の 1.5 秒後に呼んだ） |
| 試していない | 起動の直後（scene が active になる前。通知からのコールドスタートの直後を含む）、複数の scene、iPad |

### 3.9 x86_64 のシミュレーター（`README.md` 7.4）

`xcodebuild -showdestinations` には arm64 しか出ない。`ARCHS=x86_64` で組めるが、**iOS 26.2 のランタイムは x86_64 のアプリを受け付けない**（「Needs to Be Updated」）。**iOS 18.3.1 では Rosetta で x86_64 のまま動いた**（最初の画面まで 15〜30 秒）。

## 4. 後の段階に効くこと

| ID | こと | 扱い |
|---|---|---|
| R-1 | 通知のタップ・アクション・返信の文字を受けたことを、サンプルの画面に出す必要がある（今は `print` だけで、テストから読めない） | **段階 0b で、通知の画面に「最後に受けたイベント」の表示を足す**（`accessibilityIdentifier` 付き）。サンプルだけの変更で、ライブラリは変えない。README の 0b の「見た目も動作も変えない」を、この表示を除いて、に改める |
| R-2 | 表示の言語でシステムの UI のラベルが変わる。シミュレーターは en と ja、実機の言語は利用者の設定のまま | テストは、アプリの要素は `accessibilityIdentifier` で、システムの UI は identifier（`NotificationShortLookView` など）か、両方の言語のラベルで選ぶ。私物の実機の言語は変えない。基準のシミュレーター（iOS 26.2）は en のまま |
| R-3 | ~~通知センターからはタップでなく右スワイプで開く。セルを広げる操作は使わない~~ **実機では逆だった（7.3）**。通知センターを開く経路は UI テストに使わず、バナーを使う | UI テストの設計書に書く |
| R-4 | 権限のダイアログを初めの状態に戻すにはアプリの削除が要り、Default interruption handler が Allow を自動で押す | 権限のダイアログのテストは、シミュレーターでは毎回アプリを削除して流す。実機では削除に許可が要るので、自動の実行に入れず、基準を取るときだけ利用者の許可を得て行う（UI テストの設計書で決める） |
| R-5 | iOS 26 では action sheet と Share のシートが iPhone でも Popover で出て、Cancel / Close が無い | 閉じるのは `PopoverDismissRegion` かシートのドラッグ。ライブラリの action sheet と Share の基点（`README.md` 8.6）にも関わる |
| R-6 | 18.3 のシミュレーターでは Files の置き換えが失敗する | Save to Files のテストは毎回別の名前か「両方とも残す」にする |
| R-7 | Clipboard の 22 件だけで 1 回 51〜53 分、全体はさらに長い | `test_ios.sh` の全件の実行は区切りのときだけ（`README.md` 7 章のとおり）。時間は 0d で測る |
| R-8 | x86_64 のスライスは iOS 26 のシミュレーターで動かせない。18.3 なら Rosetta で動く | `README.md` 7.4 を直す: x86_64 の smoke の実行は iOS 18.3 のシミュレーターで行う |
| R-9 | 起動の直後（scene が active になる前）に Dialog や Share を呼んだときの振る舞いは試していない | C ABI の第 1 部の前面の扱い（8.6）と、1a の Unity のコールドスタートで確かめる |

1 件あたりの時間は、Dialog と Share が 9〜16 秒、権限が 10〜13 秒、通知が 26〜57 秒（設定の確かめと通知を消す準備に約 20 秒）。プローブの 1 回分（権限 3 件をアプリの削除を挟んで流す + 本体 24〜25 件）は 18.3 で約 690 秒、26.2 で約 800 秒。3 回のうちの失敗は、通知センターのセルを長押しして Open する N9 の 26.2 の 2 回だけ（R-3 で使わない）。

## 5. シミュレーターの後始末

- 2 台とも Shutdown に戻した
- 18.3 からサンプルを削除した（もとは入っていなかった）。26.2 にはサンプルが残り、通知は許可の状態
- 使い捨ての scene の無いアプリは両方から削除した
- テストランナーは両方に残っている。両方の Files の「このiPhone内」に `share-sample.txt` の写しがあり、クリップボードにテストの文字列が残っている
- 生のログ・スクリーンショット・ビルドの成果物（約 2.5 GB）は scratchpad にある（リポジトリには入れていない）

## 6. 実機で確かめ直すこと

どれも利用者の許可を得てから行う（実機は私物。`README.md` D-21）。許可を得た操作と結果は 7 章に足す。

| 項目 | 実機で行う操作 | 私物への影響 |
|---|---|---|
| サンプルとテストランナーを入れる | 今のコードでビルドし、入っている `com.jonghyunkim.ios.nativetoolkit.example` とテストランナーを上書きで入れる | サンプルとランナーだけ |
| Dialog 6 種と action sheet の形 | アプリ内の操作だけ | 無し |
| 通知のバナー・アクション・テキスト入力・予約・コールドスタート | サンプルから通知を出し、springboard と通知センターを操作する | 通知センターを開くので、私物の通知が画面に出る（テストはサンプルの通知だけを選んで触る。スクリーンショットは手元の scratchpad にだけ残る） |
| 通知センターのタップで開くか、セルを広げられるか | 同上 | 同上 |
| 権限のダイアログ | サンプルを一度削除して入れ直す（初めの状態に戻す方法が削除しか無い） | サンプルのデータが消える |
| Share のシートの Copy | Copy を押す | **クリップボードがテストの文字列で上書きされる** |
| Share のシートの Save to Files | Files に保存する | Files に `share-sample.txt` が残る |
| 貼り付けの許可のダイアログ、`UIPasteControl` | テストランナーがクリップボードに書き、サンプルで読む | **クリップボードが上書きされる** |
| 実在のアプリへの共有 | 行わない | - |

## 7. 実機の結果

2026-10-18 に、利用者が許可した 4 つの操作（サンプルとテストランナーの入れ直しと Dialog・通知、サンプルの削除による権限のダイアログ、クリップボードを上書きする操作、Files への保存）だけで行った。実在のアプリへの共有、サンプルのほかの通知、端末の設定には触れていない。各項目は 1 回、シミュレーターで不安定だった・差が出た項目は 3 回。テストの時間は合わせて約 27 分（ビルドを除く）。

### 7.1 環境

- iPhone XS、iOS 18.7.2、表示の言語は **ja-JP**（システムの UI は 18.3 のシミュレーターと同じ日本語のラベル）
- 自動ロックは利用者が「なし」にし、給電した
- `xcodebuild` は `devicectl` の識別子（`<実機の devicectl の識別子>`）を受け付けない（「Unable to find a device」）。`devicectl device info details` が示すハードウェアの UDID（`<実機のハードウェアの UDID>`）を `-destination 'platform=iOS,id=…'` に使う
- 署名はプロジェクトの Automatic のまま（`-allowProvisioningUpdates`）。pbxproj は変わっていない

### 7.2 結果

| 項目 | 実機の結果 | シミュレーターとの差 | 回数 |
|---|---|---|---|
| Dialog（alert、confirm、destructive、text input、login） | すべて通った | 無し | 各 1 |
| action sheet の形 | Sheet で、Cancel のボタンがある | 18.3 のシミュレーターと同じ。26.2 は Popover | 3/3 |
| 権限（`addUIInterruptionMonitor`、springboard からの許可、拒否） | すべて通った。ダイアログは約 1.1 秒で出る | 無し | 各 1 |
| 前面のバナー / 背景のバナー | 1.2 秒 / ホームの 4.7 秒後 | 0.1〜0.2 秒の差 | 各 1 |
| バナーのタップ・Open・背景での Delete・返信 | すべて通った | 無し | 各 1 |
| 予約の発火（10 秒） | 10.3 秒 | 0.1〜0.2 秒の差 | 1 |
| 通知センターを開いてサンプルの通知を見つける | 見つかった（リストの上の方） | シミュレーターでは下の方 | 7/7 |
| **通知センターのセルのタップで開く** | **開く** | **シミュレーターでは開かない** | 3/3 |
| **通知センターのセルの右スワイプで開く** | **開かない** | **シミュレーターでは開く** | 0/4 |
| **通知センターのセルの長押しで広げる** | **広がる（1.5 秒）。Open で前面に来る** | 18.3 のシミュレーターは 0 回、26.2 は不安定 | 3/3 |
| コールドスタート（止めた後のバナーのタップ、バナーの Open、通知センターのタップ、通知センターの長押し → Open） | すべて起動した（通知センターのタップから 1.3 秒） | 通知センターの右スワイプは実機で起動しなかった | 各 1 |
| Share の Copy、閉じる（「閉じる」のボタンとドラッグ）、除外 | すべて通った | 26.2 のシミュレーターは Popover | 各 1 |
| Save to Files | 通った。ただしピッカーが最初に開く場所が「このiPhone内」ではなく、「ブラウズ」→「このiPhone内」へ移る手順が要った | シミュレーターは最初から「このiPhone内」 | 1 |
| 貼り付けの許可（Allow） | 通った。ダイアログの出どころの名前は、ランナーではなくサンプルの名前 | 出どころの名前が違う | 1 |
| 貼り付けの拒否（Don't Allow） | 単独で流すと通り、読み込みは `CLIPBOARD_LOAD_FAILED` になった。許可 → 別のテスト → 拒否と続けて流したときは、ダイアログが出なかった（1 回。原因は未確認） | シミュレーターでは試していない | 単独で 1 |
| **`UIPasteControl` の合成したタップ** | **受け付けた**（ダイアログは出ない） | 無し | 3/3 |

### 7.3 実機の結果から決めること

- **R-3 を改める**: 通知センターの操作は環境で逆になる（実機はタップ・長押しが効き、右スワイプが効かない。シミュレーターはその逆）。**UI テストでは通知センターを開く経路を使わず、バナー（タップ、長押しのアクション）を使う**。バナーはどの環境でも安定している。通知センターでの操作は、UI テストの設計書で、環境ごとに分けて書くか人の確認にするかを決める
- R-2 のとおり、実機は ja、基準のシミュレーター（iOS 26.2）は en なので、システムの UI は両方の言語のラベルか identifier で選ぶ
- Save to Files は、保存先を「このiPhone内」に選び直す手順を入れる
- 貼り付けの拒否のダイアログが続けて流すと出なかった件は、UI テストの設計書で、拒否のテストを単独で（アプリの起動から）流す形にする

### 7.4 実機に残したもの

| もの | 状態 |
|---|---|
| サンプル（`com.jonghyunkim.ios.nativetoolkit.example`）とテストランナー | 今のコードで組んだものに上書きした。途中で 4 回削除して入れ直したので、もとのサンプルのデータは残っていない |
| サンプルの通知の権限 | 許可 |
| サンプルの表示中・予約中の通知 | 0 件 |
| 通知の category | サンプルの `sample-category`（Open / Delete / Reply）が登録されたまま |
| Files | 「このiPhone内」に `share-sample.txt` が 1 つ |
| クリップボード | テストランナーが書いた「deny-<時刻>」の文字列 |
| 端末の設定、ほかのアプリ、言語、構成プロファイル | 触れていない。再起動もしていない |

実機の `.xcresult` には、XCTest が自動で撮ったスクリーンショットと録画が入っており、私物の端末のホーム画面・ほかの通知・Share のシートの連絡先の候補が写っている可能性があった。scratchpad にだけあり、リポジトリには入れていない。**利用者の決定（2026-10-18）で 18 個とも消した**（中は開いていない）。今後も、実機の `.xcresult` は結果を書き写したら消す。

## 8. Xcode 26.3 の事実（UI テストの設計書のレビューのため）

2026-10-18 に、UI テストの設計書のレビュー（v3）で「確かめていない」とされた Xcode の振る舞いを、シミュレーター（iPhone 17、iOS 26.2）だけで確かめた。試したコードは `probes/xcode-facts/FactProbeTests.swift`（一時的にテストのターゲットに置き、終わったら外した）。

| 項目 | 結果 |
|---|---|
| `-enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path` | 動く。JSON は `{"errors":[], "values":[{"enabledTests":[{"identifier":…}], "disabledTests":[], "testPlan":…}]}`。identifier は `<ターゲット>/<クラス>/<メソッド>()`（末尾に `()` が付く）。**テストのメソッドを持たない基底クラスも `<ターゲット>/<クラス>` の 1 件として出る**。`-only-testing` を付けても、テストプランの全件（単体テストを含む）が出た。雛形の `testLaunch` は展開されず 1 件 |
| 列挙で端末を起動するか | シミュレーターは列挙の前後とも Shutdown のままだった（起動しなかった）。実機は試していない |
| 列挙の identifier をそのまま `-only-testing:` に渡す | 通る |
| **存在しない identifier を `-only-testing:` に混ぜる** | **黙って無視され、exit は 0**。結果にはその名前が出ない |
| `self.name` | `-[FactProbeTests testRuns]`（Swift のモジュール名は付かない）。xcodebuild のログでは `-[IosLibraryExampleUITests.FactProbeTests testRuns]` と出る |
| 基底の `final override func setUpWithError()` | コンパイルが通り、子のテストで呼ばれる |
| **`setUpWithError` で `XCTSkip` を throw した後** | テストの本体は走らないが、**`tearDownWithError` は走る** |
| `.xcresult` の名前 | `xcresulttool get test-results tests` の `nodeIdentifier` が `<クラス>/<メソッド>()`（ターゲット名は付かない）。skip の理由はその子の `nodeType: "Failure Message"` の `name`（`Test skipped - NTK-GATED:probe`） |
| JSON のリソース | 同期するグループ（objectVersion 77）に置くと、何もしなくても `IosLibraryExampleUITests.xctest/` に入り、`Bundle(for:)` で読める |
