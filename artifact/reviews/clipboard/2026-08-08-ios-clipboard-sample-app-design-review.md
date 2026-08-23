# レビュー結果

- 日付: 2026-08-08
- 対象ファイル: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md`
- 機能名: clipboard
- 対象 OS: iOS 18以降
- 参照設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 参照実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`

---

## 強み

- S1〜S11とP-1〜P-16を一覧化し、Unity Bridgeをサンプル対象外とする境界が明確である。
- `IosLibraryExample`から`IosLibrary`だけへ依存し、`UnityIosPlugin`やUIKitの直接代替実装へ逃げない方針はプロジェクトルールと一致する。
- Android Clipboardサンプルとの共通構成と、iOS既存サンプルの`NavigationStack`、`sectionView`、結果表示パターンの優先順位が整理されている。
- 9 content kind、3 scope kind、4 load kind、11検出パターンを画面操作へ対応付けており、機能の探索性が高い。
- pasteboard名、パス、URL、クリップボード値をログへ出さない方針と、名前付きpasteboardの非永続性、appendのprivacy非保証を画面注記へ反映している。
- T-00未実施によるP-15とappendの変更可能性を隠さず、追加判断を設計書由来の要件と分離している。
- `PBXFileSystemSynchronizedRootGroup`の採用は実プロジェクトで確認でき、Swiftファイル追加時にproject file変更が不要という分析は正しい。

## 改善点

### 高優先度

#### 1. Error Casesの期待コードが実装済みエラー契約と一致しない

- 対象: 5.8、5.11
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:333`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:365`
- 10行中、次の6行が`ClipboardError.errorCode`と不一致である。

| ケース | 計画の期待値 | 実装の期待値 |
|---|---|---|
| 存在しないimage file | `CLIPBOARD_IMAGE_LOAD_FAILED` | `CLIPBOARD_FILE_NOT_FOUND` |
| Copy Custom Dataの不正UTI | `CLIPBOARD_INVALID_TYPE_IDENTIFIER` | `CLIPBOARD_INVALID_TYPE` |
| Read Dataの不正UTI | `CLIPBOARD_INVALID_TYPE_IDENTIFIER` | `CLIPBOARD_INVALID_TYPE` |
| Remove General | `CLIPBOARD_INVALID_REQUEST`相当 | `CLIPBOARD_CANNOT_REMOVE_GENERAL` |
| unresolvable namedのobserve | `CLIPBOARD_PASTEBOARD_UNAVAILABLE` | `CLIPBOARD_UNAVAILABLE` |
| Detect Patternsの空Set | `CLIPBOARD_INVALID_REQUEST`相当 | `CLIPBOARD_EMPTY_PATTERNS` |

- 根拠:
  - `ios/IosLibrary/IosLibrary/Clipboard/Domain/Model/ClipboardError.swift:48`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardRepositoryImpl.swift:145`
- ボタン名と期待値を正式コードへ合わせ、不正UTIは`"not a valid identifier!!"`、不正URLは`"example.com"`など、既存unit testで拒否が固定されている入力を明記すること。
- 現状のまま実装すると、正常なライブラリエラーをサンプル側の失敗として誤判定する。

#### 2. `loadItem(.file)`の一時ファイル所有権とcleanupが設計されていない

- 対象: 5.6、8.1
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:304`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:462`
- `ClipboardLoadedItem.file(URL)`は、返却URLと親ディレクトリを呼び出し側が削除する契約である。
  - `ios/IosLibrary/IosLibrary/Clipboard/Domain/Model/ClipboardLoadRequest.swift:17`
- 計画はfile size表示だけを定義し、成功後の削除、削除失敗時の扱い、手動確認を定義していないため、ボタン操作のたびに一時ディレクトリが残る。
- `.file`を受け取ったらサイズ取得後に親ディレクトリを`defer`で削除するhelperを定義し、パスは画面にもログにも出さないこと。Paste Controlのaccepted typesを将来fileへ広げた場合も同じhelperを通すこと。
- 手動確認へ「Load File成功後に返却session directoryが残らない」を追加すること。

#### 3. 必須の自動UIテストが変更ファイルと検証計画から欠落している

- 対象: 7章、8章
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:426`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:451`
- `implement-sample-app` workflowは、自動化可能な手動観点を既存UI test targetへ追加してから実機確認することを必須としている。
- `IosLibraryExampleUITests` targetは既に存在するが、計画の変更ファイルは`ClipboardSampleView.swift`と`ContentView.swift`だけである。
  - `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift:1`
- 次を計画へ追加すること。
  - `IosLibraryExampleUITests.swift`の変更
  - Main Menu、各section、主要button、result領域への安定したaccessibility identifier
  - 自動化対象: 画面遷移、固定データのcopy / snapshot / clear、代表的Error Cases、結果の成功・失敗表示、画面離脱
  - 実機・他端末・system prompt依存として手動に残す対象の明示

#### 4. T-00のprivacy行列を「本サンプルで実施可能」とする記述が成立しない

- 対象: 6章、8.3
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:421`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:487`
- 企画書のケース13〜15は、`itemProviders` getterのみ、取得済みproviderへの`canLoadObject`のみ、実ロードを別々に実行して、通知・promptの契機を切り分ける試験である。
  - `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md:399`
- 現在の`IosClipboardManager.loadItem`はこれらを1操作へ内包し、サンプル画面の`Load`ボタンでは段階を分離できない。out-of-scopeとした`contains(pasteboardTypes:)`のケース12も実行できない。
- 「Snapshot / Check / Detect / LoadボタンでT-00を実施可能」という断定を撤回し、次のいずれかへ分離すること。
  - T-00専用の実験harnessでUIKit APIの各段階を個別観測する
  - サンプルアプリで実施できるprivacy観点だけをケース番号付きで列挙し、13〜15などを別タスクとして残す
- 分離できない操作を一括実行して、privacy契機を特定したと判断してはならない。

### 中優先度

#### 1. 名前付きpasteboardの寿命とremove後の確認手順が現在の状態設計では再現できない

- `Remove Active Pasteboard`成功後に`activeScope = .general`へ戻す一方、手動確認は「同scopeを解決できない」ことを要求している。
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:250`
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:460`
- M-08も、再起動後に固定名をcreateせず参照対象へ設定する導線がないため、create操作がpasteboardを再生成してしまう。
- `Use Fixed Named Scope (without create)`を追加するか`lastRemovedScope`を保持し、remove後・再起動後に`read` / `startObserving`して`CLIPBOARD_UNAVAILABLE`を確認できる手順を定義すること。

#### 2. P-11のキャンセル説明が「配信抑止のみ」となっており、実装契約を過度に単純化している

- 対象: 5.6
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:314`
- P-11はcancel時にcallerへ`CLIPBOARD_CANCELLED`を完了として返し、`Progress.cancel()`を試み、遅延結果を破棄する。OS処理そのものの中断だけが保証されない。
- 「配信抑止のみ」はP-9 / P-10の非協調的検出APIに近い説明である。P-11については、cancel結果の表示、late result破棄、OS中断非保証を分けて記載すること。
- 共通`run`は全`ClipboardError`を`❌`表示するが、設計v4はサンプルアプリで`CLIPBOARD_CANCELLED`を呼び出し側起点の通常系として示すことを要求している。cancelledだけは「Cancellation completed」などの中立表示へ分岐し、Cancel button直後の表示との上書き順も決めること。
- 実pasteboard loadは短時間で終わる可能性があるため、`Cancel All Loads`の確認に必要な事前データと操作タイミング、完了済みの場合の期待結果も明記すること。

#### 3. Paste Control生成失敗と部分成功のUI更新契約が実装可能な粒度に達していない

- 対象: 5.9
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:342`
- 提示された`UIViewRepresentable`には生成失敗callbackがないが、本文は空`UIView`を返して結果領域へエラー表示するとしている。
- `onCreationFailure`を型へ追加し、`makeUIView`中の同期的なSwiftUI state変更を避けてmain actorの次turnで通知するなど、状態更新方法を明記すること。
- 部分成功では`onPaste`の直後に`onPartialFailure`が呼ばれるため、単一`resultText`を順番に上書きすると成功itemの情報を失う。item件数とfailure code一覧を1つの結果へ集約する方針を決めること。

#### 4. クリップボード値の画面表示方針を実装時判断のまま残さない

- 5.5は「値そのものは表示しない」と断定した直後に、表示するかを実装時に確定するとしている。
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:299`
- 画面要件、security方針、`updateResult`のログ内容に影響するため、設計レビュー時点で決める必要がある。
- 推奨は、外部clipboard値は画面にもログにも表示せず、件数・byte数・kindだけを表示すること。sample自身が直前にcopyした固定文字列だけを表示する場合は、その限定条件と、`updateResult`がresult本文をログへ出さないことを明記すること。

#### 5. 抽出した境界値観点が画面操作または対象外理由へ結び付いていない

- 1.5は64 MiB上限ちょうどや100 MPを境界観点として挙げるが、実装詳細と手動確認には該当操作がない。
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:75`
- サンプルで扱うなら再現用データ生成手順とmemory負荷対策を追加すること。unit test / Instruments専用とするなら、サンプル対象外と理由を明記し、T-13のどこで確認するかを対応付けること。

#### 6. Paste Controlと手動確認用fixtureの前提が不足している

- `makePasteControl`にはscope引数がなく、Paste Controlは画面の`activeScope`とは独立してsystem general pasteboardを対象にする。この制約をPaste Controlセクションとactive scope表示へ明記すること。
- 手動確認で要求する次のケースには、現在の固定buttonだけでは再現可能な準備手順がない。
  - Paste Controlのpartial failure / all failure
  - 4 load kindそれぞれに適合するclipboard内容
  - 11検出パターンのうち、住所、calendar event、flight、shipment trackingなど（現在のfixtureはURL / email / phone / moneyだけ）
- 各観点を「準備操作 → 実行操作 → 期待結果」の表にし、外部アプリが必要なケースはその旨を明記すること。

#### 7. scope操作と観測sessionの状態遷移が未定義

- `activeScope`と`isObserving`を持つが、観測中のscope変更、観測対象のremove、画面離脱時にサンプルが作成したnamed / unique pasteboardをどう扱うかが決まっていない。
- 推奨は、scope変更・remove前に`stopObserving()`し、`isObserving`を更新すること。別案として観測中はscope操作をdisableする場合は、buttonの活性条件をtruth tableで示すこと。

### 低優先度

#### 1. project fileの同期rootは確認済みなので「要検証」を解消できる

- 対象: 7.3
  - `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md:446`
- `IosLibraryExample.xcodeproj/project.pbxproj`には`PBXFileSystemSynchronizedRootGroup`が存在する。計画上の要検証を「確認済み」へ変更できる。

#### 2. `pastedSummary`と`isObserving`の画面反映・活性条件を明記するとよい

- 状態一覧には両方があるが、wireframe上の表示位置とStart / Stop buttonのdisabled条件が確定していない。
- `pastedSummary`をresultへ統合するなら状態自体を削除し、別表示するなら位置をwireframeへ追加する。`isObserving`はStart無効／Stop有効のtruth tableを記載すると実装差が減る。

#### 3. `activeScopeLabel`は導出状態にするとよい

- `activeScopeLabel`は`activeScope`から計算できるため、独立した`@State`にすると更新漏れで表示が不一致になる。
- kindと名前長を返すcomputed propertyへ変更すると、秘匿方針を維持しながら状態を一元化できる。

## 不足項目

- 正式な`ClipboardError.errorCode`と一致するError Cases表、および確実に各errorへ到達する固定入力
- `.file`成功時に返却URLの親ディレクトリを削除する所有権処理と確認項目
- `IosLibraryExampleUITests`の変更、accessibility identifier、自動化対象／手動対象の分類
- T-00 privacy行列16ケースとサンプル画面操作の対応表、および実施不能ケースの専用harness方針
- remove後・アプリ再起動後にnamed scopeをcreateせず再参照する導線
- Paste Control生成失敗、部分成功、全失敗を単一結果領域へ反映する規約
- P-11キャンセルの事前条件、操作順、期待結果
- Paste Controlがactive scopeの影響を受けずgeneral pasteboardを対象とする旨
- load / detect / Paste Control partial failureの再現fixtureと操作順
- scope変更・remove・画面離脱と観測sessionの状態遷移
- サイズ・pixel境界をサンプルで扱うか、unit / Instrumentsへ委ねるかの明示

## 総合評価

S1〜S11の機能対応、ネイティブライブラリだけへの依存、既存iOS UI規約とAndroidペアの踏襲、機微情報を避ける方針はよく整理されている。一方で、Error Casesの過半数が実装済みerror codeと一致せず、`.file`の呼び出し側cleanupが欠落し、必須のUI test計画も存在しない。また、T-00のprivacy契機切り分けを現行の集約APIだけで実施可能としている点は、観測結果を誤って解釈する危険がある。

**現状は実装着手前に高優先度4件の修正が必要である。** エラー契約、リソース所有権、自動UI test、privacy試験の実施境界を直せば、実装可能で監査しやすいサンプルアプリ計画になる。
