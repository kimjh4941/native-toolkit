# Android ライブラリ Kotlin の API の補完 設計書

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/android-c-abi/README.md`（4 章、D-7、D-11、8.6） |
| 対象段階 | 段階 1b（Kotlin の API の補完）の前 |
| 対象 OS | Android 12（API 31）以降 |
| 作成日 | 2026-10-04（第 7 版。第 6 版で決定の後、利用者の決定で機能ごとの Manager を足した。直した所の確かめを経て**決定**。1b の実装中に、利用者の決定で Manager の置き場所を機能のパッケージの直下に改めた（0.7）） |
| ブランチ | `feature/NTKIT-17` |
| 前段階 | 段階 0（UI テストと基準、パッケージ名、ツールチェーン）、段階 1a（NDK のスパイク）、C ABI の設計書の第 1 部（決定） |
| 元にした文書 | C ABI の設計書 第 1 部（`designs/2026-10-04-android-c-abi-c-abi-design.md`。以下「C ABI の設計書」）の 9.1（K-1〜K-9）、0e の結果（`results/2026-10-04-android-c-abi-stage0e-result.md` 4 章。1.x の識別子）、ブリッジとサンプルの Receiver の洗い出し（2026-10-04。5 章） |
| 後に続く文書 | C ABI の設計書 第 2 部（2b の前。この設計書の口を C の関数に写す。8.15 の申し送り） |
| レビュー | `reviews/2026-10-04-android-c-abi-kotlin-api-design-review-v1.md`（1 回目。W-C1〜W-C34、W-X1〜W-X19）、`-v2.md`（2 回目。X-C、X-X1〜X-X12）、`-v3.md`（3 回目。Y-C1〜Y-C22、Y-X1〜Y-X6）、`-v4.md`（4 回目。Z-C1〜Z-C12、Z-X1〜Z-X4）、`-v5.md`（5 回目。V5-C1〜V5-C10、V5-X1〜V5-X4）、`-v6.md`（第 7 版の確かめ。V7-X1〜V7-X2） |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていないクラスと関数（`LibraryRuntime`、`ForegroundActivityTracker`、`EventHub` など）を定める。名前が実装に存在するかの照合は 1b の実装の後に行う（15 章）

## 0. レビューの反映

### 0.1 第 2 版での反映（v1 のレビュー）

| 指摘 | 反映 |
|---|---|
| 1b で既存の API の動作を変えていた（W-X1、W-C1） | 既存の口の動作をすべて残す形に改めた（K-9）。README は直さない（3.3） |
| Manager と `suspend` の版、1 操作 1 UseCase（W-X2） | Dialog と権限の要求に Manager の callback 版と `suspend` 版、操作ごとの UseCase |
| ちょうど 1 回の完了の状態機械（W-X11、W-C7、W-C9） | 要求の状態の表、共通の門、`showNow` / `commitNow` |
| 同期の配送の矛盾（W-X4、W-C2） | 6.2 の例外と、受け手に渡す `Registration` |

### 0.2 第 3 版での反映（v2 のレビュー）

| 指摘 | 反映 |
|---|---|
| Alarm の extra の Parcel（X-C1、X-X2） | Alarm の extra を JSON と OS の Parcelable に分けた（8.6） |
| 宿主の記録の寿命（X-C5）、権限の会と門（X-X3） | 8.3、8.7 の表 |
| 既存の `shareWithCallback` の 2 段の更新（X-C4）、結果を待つ Share の形（X-C7） | 今の動作に戻し、新しい口は「開く」と「選択のイベント」に分けた（8.9） |
| 全画面の Intent の data（X-C6） | `Intent.setIdentifier`（8.5） |
| 公開の宣言（X-X7） | 付録 A（16 章） |

### 0.3 第 4 版での反映（v3 のレビュー）

| 指摘 | 反映 |
|---|---|
| **予約（8.6）の A が 3 回続いた**（Y-C1〜Y-C4、Y-X1） | 仕組みを直した: **今の予約の流れ（順序、契機、対象、失敗の伝わり方）を 1 行ずつ写し、変えるのは直列化の形と書き方だけ**にした。8.6 の対応表で今のコードと並べる。`MY_PACKAGE_REPLACED` での置き直しを今の形に戻し、`toUri` で欠ける項目だけを扱う規則を足した。「その鍵の予約は無い」の約束はやめた。Alarm と保存する Intent からクラス名（component）を外した |
| port の例外（Y-X2） | 予約の保存の port を application に置くのをやめ、data の中に閉じた。例外が要らなくなった |
| `suspend` 版の形（Y-X3） | 答えを返し、取り消しと失敗は型のある例外で投げる |
| 既存の `shareWithCallback` の `onFinished`（Y-X4） | 選択でない結果の行を足し、既存の口の例外の伝わり方は今のままにした |
| そのほかの B・C | レビューの記録の表のとおり |

### 0.4 第 5 版での反映（v4 のレビュー）

| 指摘 | 反映 |
|---|---|
| component を使わない Intent は、targetSdk 34 以降で `exported=false` の受け手に届かないおそれがある（Y-C4 の残り。2 者の判断が分かれた） | 確かでない形を本線に置かない。**明示の component に戻し、受け手のクラス名を「変えない識別子」として固定する**（8.5、8.6）。クラスは 2.0.0 の後に動かさない |
| 発火の順序が今と違う（Z-C1、Z-X1） | 受け手は今と同じく main の上で同期に「出す → 保存から消す → shown」を行う（8.6） |
| `lossy` と `bootCount` が Auto Backup と両立しない（Z-C2） | インストールごとの印（`noBackupFilesDir`）を項目に保存し、印と起動回数の両方が同じときだけ「Alarm は生きている」とする（8.6） |
| `lossy` の規則が期限の過ぎた項目にもかかる（Y-C1、Y-C2 の残り） | 規則を「未来の項目を置き直す」分岐だけにかける。期限の過ぎた項目は今と同じく出して消す（8.6） |
| 既存の port の `isScheduled` の既定の実装が投げる（Z-X2、Z-C4） | 既存の port に足さない（第 6 版で、登録の仕組みもやめた。0.5） |
| 置き直した Alarm の世代（Z-C3）、受け手の中の失敗（Z-C5）、`ScheduleLock` の型と `send`（Z-C6）、読めない要素（Z-C7） | 8.6 |

### 0.5 第 6 版での反映（v5 のレビューと利用者の決定）

| 指摘 | 反映 |
|---|---|
| `isScheduled` の登録の仕組みが、登録の無い場面で今と動作を変え（V5-C1、V5-X1）、登録所が application に `Context` を持ち込む（V5-X2） | **利用者の決定（2026-10-04）: 既存の `NotificationUseCases.isScheduled(context, id, tag)` は、今と同じく data の保存を直接読む形を残す**。README 4 章の依存の向きの修正から、この 1 つの既存の口だけを外す（README の同じ行に理由を書いた）。登録の仕組み（`NotificationScheduleQuery`、`NotificationScheduleQueries`）はやめた（8.14） |
| `ScheduleLock` の範囲（V5-C2）、置き直しの読み直し（V5-C3）、K-9 の行の数（V5-C4） | 8.6、11 |
| tag `untagged` と tag 無しが今は同じ予約になる（Claude の C） | 予約の鍵は今と同じ形（tag が無ければ `untagged`）にした（8.6） |
| テスト（V5-X3、V5-X4） | IT-12、IT-23 |

### 0.6 第 7 版での反映（利用者の決定）

| 決定 | 反映 |
|---|---|
| ほかの OS（iOS・macOS の機能ごとの Manager、Windows の Manager）とそろえ、`android_library` にも機能ごとの Manager を置く。名前はほかの OS とそろえて `Android*Manager`。C ABI の受け口は機能ごとにこの Manager を呼ぶ（2026-10-04） | `AndroidClipboardManager`、`AndroidDialogManager`、`AndroidNotificationManager`、`AndroidShareManager` を入口だけの薄い層として置いた（6.3、付録 A）。第 6 版の `DialogManager`、`NotificationPermissionManager`、`NotificationSettingsManager` はこの 4 つにまとめた。イベントと監視の持ち主は internal にし、Manager から使う。既存の `*UseCases` などの公開の口は今のまま残す（K-9） |

### 0.7 1b の実装中の利用者の決定

| 決定 | 反映 |
|---|---|
| Manager は Presentation の上の別の層なので、ほかの OS（iOS・Windows はすべて、macOS は Clipboard を除く 3 つ）と同じく、機能のパッケージの直下に置き、層のパッケージと並べる。今後ほかの OS もこの形にそろえる（2026-10-04） | 4 つの Manager を `<機能>/presentation/` から `<機能>/` に移した（6.1、6.3、付録 A）。`common.md` の「層とモジュールの対応」と `android.md` の Manager の節に置き場所を書いた。macOS の Clipboard（`Clipboard/Manager/`）は別の作業として記録した |

### 0.8 1b の実装中の利用者の決定（T-21）

| 決定 | 反映 |
|---|---|
| IT-19・IT-22・IT-26 は、サンプルに flavor を足さず、`android_library` だけに依存する試験専用のアプリ（`android/AndroidLibraryExample/releaseProbe`、`testShareTarget` と同じ形のモジュール）で行い、確かめた後も残して `test_android.sh` の段で毎回流す（2026-10-05）。サンプルに flavor を足すと、ビルドの名前・スクリプト・全機能で共通のワークフロー・0d の基準の土台を作り直すことになり、確かめたいもの（ライブラリが利用者の R8・権限なし・更新のもとで壊れないか）より影響が大きいため | 12 章の IT-19・IT-22・IT-26 の行と、`test_android.sh` の段 |
| IT-26 の「後の版は JSON に欄を 1 つ足す」は行わない（ライブラリの本体に試験のための切り替えが要る。知らない欄を読み飛ばすことは IT-25 で確かめた）。代わりに、前の版と後の版で R8 の名前の付け方（obfuscation の辞書）を変え、ライブラリのクラスの名前が変わっても前の版の予約が後の版で発火して内容が同じことで、保存と Alarm が R8 の名前に頼らないことを確かめる（クラス名が入っていないことの直接の確かめは IT-24）。「複数の `Bitmap`」は、公開の口で `Bitmap` を持つ欄が `largeIconBitmap` だけなので 1 つにする | 同上 |
| T-23 の照合で、12 章の IT-21・IT-23 にテストが無く（タスク表のどの行にも割り当てていなかった）、ほかの行にも一部の欠けがあると分かった。IT-21・IT-23 と、利用者から見える動作の欠け（A: IT-01・IT-02 の Startup を無効にした経路と前面、IT-03・IT-07 のプロセスの死の後、IT-10・IT-11 のコールドスタート）を T-23 で書き、検証の穴（B）と記述（C）は安いものだけ埋めて、残りは理由つきで 1b の実装結果に書く（2026-10-05） | 12 章のテストと 1b の実装結果 |
| 1b の実装レビュー（2026-10-05、`reviews/2026-10-05-android-c-abi-stage1b-implementation-feature-review-v1.md`）で、直さずに残すもの: (1) 12 章の行の一部の欠け（実装結果 5.1 の △ と 5.2。上の決定のとおり、検証の穴と記述は安いものだけ埋めた）。(2) 型のある Chooser Action の受け手で、世代の照合と `emit` の間に新しい Share が世代を上げると、古いアクションが 1 度だけ届きうる（照合の時点を区切りとみなす。届くのは新しい Share を開く操作と同時に古い Chooser のアクションを押したときだけ）。(3) 公開の sealed class `ShareDomainError` に `InvalidChooserAction` を足したので、利用者の網羅的な `when` はコンパイルが通らなくなる（ソースの互換。10 章で決めた足し方で、K-9 の動作の互換には当たらない）。(4) `ShareTextUseCase` の `@Deprecated`（8.13）は、JSON を渡さない `ShareUseCases.shareText(content)` にも警告を出す（同じ関数のため） | 実装結果 5.1・7 章 |

### 0.9 C ABI の設計書 第 2 部を受けた直し（2026-10-05）

第 2 部（`designs/2026-10-05-android-c-abi-c-abi-design-part2.md` の 7 章、TB-12）で決めたことに合わせて、C ABI の側の写しを書いた行を直した。Kotlin の API は変えていない。

| 直した所 | 第 2 部の決定 |
|---|---|
| 5.1 の C1 と「共通」の行、7 章の「Clipboard と Share の操作を main で動かす」の行 | Clipboard の読み書きは同期（AP-3）。監視の開始と停止は main に積む（AP-2） |
| 7 章のキャンセルの戻り・Progress と style の行、8.15 のエラーの写し・Share の要求の ID・C ABI の側で持つもの | `HOST_START_FAILED` と `SHOW_FAILED` は別の値、`CancelReason` は 2 つに分ける（11.1）。Share の ID は C が付ける（AP-17）。style の代わりの値と `Dismissed` の写しは包み（AP-8、AP-13） |

## 1. 設計目的

- 今は Unity のブリッジ（`unity_android_plugin`）とサンプルの Receiver にしか無いロジックを `android_library` へ移し、**Kotlin の利用者が Kotlin だけで全機能を使えるようにする**（README 1.2、4 章）
- 足す口の形を、C ABI の要求（main からの非同期のコールバック、ちょうど 1 回の完了、複数の登録、保ったイベントの受け渡し）に合わせる。条件は C ABI の設計書 9.1 の K-1〜K-9
- **1b では既存の口の動作を変えない**（K-9、README の 1b の行）。今の不具合のうち、新しい口で避けられるものは新しい口で避け、既存の口のものは「1b で直さない」と書いて残す（3.3）

## 2. スコープ

### 2.1 in

| 機能 | 足す・直すもの |
|---|---|
| 共通 | 初期化（`LibraryRuntime`、`LibraryInitializer`）、前面の Activity を追う仕組み、透明な宿主の Activity、要求の完了の門、イベントの口（`EventHub`）、main への受け渡し、ログで秘密を伏せる仕組み |
| Notification | タップ・アクション・dismiss の Receiver とイベント、shown のイベント、リソース名の解決、新しい口の PendingIntent の同一性、予約の保存形式（JSON と `Intent.toUri`）と書き込みの確実さ、Alarm の extra の形、1.x の予約の破棄（D-11）、Activity の要らない `canScheduleExactAlarms` と設定の画面、Activity の要らない権限の要求、依存の向きの修正 |
| Share | 選択を要求の印つきのイベントで受ける新しい口、既存の `shareWithCallback` の古い選択の修正（README の 1b の行）、型のある Chooser Action とその動的 Receiver・イベント |
| Clipboard | エラーの分類（ブリッジの 7 つのコード）、プロセスで 1 つの変更の監視とイベント |
| Dialog | 層に分ける（domain・application・presentation と Manager）、前面の Activity の上に出す口、ちょうど 1 回の完了、回転で結果を失わないこと |
| 規則と配布 | `agent-rules/coding-rules/android.md`（ログの規則の例外、Android での Manager の役と UseCase を置かない口の条件）、既存のログの 2 か所、`consumer-rules.pro`、manifest のコンポーネントと権限の扱い |
| サンプル | サンプルの Receiver 3 つをライブラリの仕組みに置き換え、新しい API を使う画面を足す（design-sample-app で設計する） |

### 2.2 out

- C ABI の関数、C の型、エラーの値（C ABI の設計書 第 2 部）
- ブリッジ（`unity_android_plugin`）の変更（README 4 章。段階 3 で消す）。ブリッジのログ（パスワードを出す）は直さない。ブリッジは 2.0.0 に出ない（段階 3 と同じリリース。D-2）
- ブリッジの JSON の解析、操作の名前、エラーの文言、Progress の前景サービスの値の補正、style の代わりの値。これらは「引数の組み立て」で OS の資源を持たないので、C ABI の側（第 2 部）か Unity の包み（2c）が受け持つ（7 章）
- 既存の口の今の不具合の修正（3.3 の「1b で直さない」）

## 3. 前提と決定

### 3.1 企画書と C ABI の設計書から来る前提

| 前提 | 出典 |
|---|---|
| 1.2 のロジックを `android_library` へ移す。ブリッジには手を入れない。不具合は `android_library` の側だけを直す | README 4 章 |
| 1b で変わる動作は、1.x の予約の破棄と、Share の古い選択の修正だけ。Kotlin の利用者に androidx.startup の依存が入る | README 5 章の 1b の行 |
| 前面が `FragmentActivity` ならその上に出し、違えば透明な `FragmentActivity` を起動する | D-7 |
| 1.x の予約は更新の後に一度だけ破棄する。保存形式はライブラリのデータは JSON、利用者の `Intent` は `Intent.toUri`。`toUri` で残るのは、再起動をまたぐ予約の `Intent` の基本型と文字列の extra | D-11 |
| 予約の保存の書き込みを確実にする（今の `apply()` は失われうる） | README 8.6 |
| 前面の定義と、手動の初期化で渡された Activity を初期値にすること | C ABI の設計書 5.8、K-5 |
| `ensureInitialized` は 3 値、待たない、失敗したら未着手へ、C を知らない、「済んだら呼ぶ」を登録できる | C ABI の設計書 5.3、K-8 |
| 1b は既存の API の動作を変えない。前面の判定と `NOT_FOREGROUND` は C ABI の受け口が行う | K-9、C-4 |
| Share は要求ごとに別の PendingIntent（data の URI に印）。新しい Share は前の待ちを消す（今と同じ）。`NOT_FOREGROUND` で開かなかった Share は前の待ちを消さない | AC-22、K-4 |
| 保っていたイベントは、挿入のメッセージの中で受け取れる形にする | K-7 |

### 3.2 この設計書で決めること

| ID | 決めること | 決定 |
|---|---|---|
| KA-1 | 初期化の口 | `LibraryRuntime`（公開）と `LibraryInitializer`（8.1） |
| KA-2 | 前面の Activity を追う仕組み | `ForegroundActivityTracker`（`@RestrictTo(LIBRARY_GROUP)`、main だけ）（8.2） |
| KA-3 | 透明な宿主の契約（D-7） | `NtkHostActivity`、宿主の記録の寿命、要求の状態の表（8.3） |
| KA-4 | 同時の要求（D-7） | Dialog はそれぞれ出す（今と同じ）。権限の要求は出ている会に合流する。宿主の起動を待つ間の要求は、その宿主に積む（8.3、8.7） |
| KA-5 | イベントの口と保つ規則（README 4、README 8.6） | 機能ごとの `EventHub<T>`。保つのは通知のタップ・アクション・dismiss だけ、32 件、期限なし、受けた順、重複を除かない（8.4） |
| KA-6 | 通知のイベントの PendingIntent | `NotificationEventIntents`。アプリを開くものは見えない Activity を通す（8.5） |
| KA-7 | 新しい口の PendingIntent の同一性と宛先 | ライブラリの manifest の受け手へは明示の component（クラス名は変えない識別子）と、data の URI での区別。アプリの起動の Activity へは `Intent.setIdentifier`。request code は 0（8.5、8.6、8.9） |
| KA-8 | 予約の保存形式、Alarm の extra、排他 | **今の流れを写し、直列化の形と書き方だけを変える**。保存は再起動をまたぐ予約だけ、`AtomicFile` の JSON に同期で書く。Alarm の extra は JSON と OS の Parcelable。予約の操作は 1 つのロック（8.6） |
| KA-9 | 1.x の予約の破棄（D-11） | `LegacyScheduleCleaner`。状態と印のファイル、失敗したらやり直す（8.6） |
| KA-10 | Dialog の層と公開の範囲 | `AndroidDialogFragment` は今の場所と動作で公開のまま。新しい入口は `AndroidDialogManager`（8.8、6.3） |
| KA-11 | 権限の要求と設定の画面 | `AndroidNotificationManager` の `requestPermission`、`canScheduleExactAlarms`、`openSettings`（8.7） |
| KA-12 | Share の口 | 新しい口は「開く（同期、印を返す）」と「選択のイベント（`ShareEvents.selections`）」。既存の `shareWithCallback` は形と動作を変えず、中を要求ごとの PendingIntent に載せる（8.9） |
| KA-13 | Clipboard の口 | `ClipboardErrorCode.of`、`ClipboardObserver`、`ClipboardEvents`（8.10） |
| KA-14 | ログの規則の例外（README 8.6） | 秘密の値を伏せる。既存のログの 2 か所も直す（8.11） |
| KA-15 | manifest の権限 | 宣言は今のまま。7 つそれぞれの外し方と外したときの動作をマニュアルに書く（8.12） |
| KA-16 | ブリッジだけが使う口 | 1b では残し、段階 3 で消す（8.13） |
| KA-17 | 前面の判定の受け持ち | C ABI の受け口が C-4 のとおり判定する。Kotlin の側（`UiHost`）も判定し、受け口の判定の後に状況が変わった場合に同じ値で完了する（8.15） |
| KA-18 | Android での層の当て方 | ほかの OS とそろえ、機能ごとの入口 `AndroidClipboardManager`・`AndroidDialogManager`・`AndroidNotificationManager`・`AndroidShareManager`（入口だけの薄い層）を置く。C ABI の受け口はこれを呼ぶ。既存の `*UseCases` は今のまま残す。UseCase を置かない口の条件を `android.md` に書く（6.3） |

### 3.3 1b で変わる動作と、1b で直さない不具合

**1b で変わる動作**は README の 1b の行の 2 つだけである（README は直さない）。

| 変わること | 今 | 1b の後 |
|---|---|---|
| 1.x の予約の破棄（D-11） | 改名の後、1.x の予約は黙って捨てられ、戻せない | 更新の後に一度だけ取り消して消す（8.6） |
| Share の古い選択（AC-22） | 古い Chooser の選択が、新しい要求の結果として届きうる | 届かない（8.9） |

あわせて、README の決定（8.6 の書き込みの確実さ、D-11 の保存形式）の結果として、次の違いが出る。どれも決定から直接出るもので、それ以外の流れは今と同じ（8.6 の対応表）。

| 項目 | 今 | 1b の後 | 出どころ |
|---|---|---|---|
| 再起動をまたぐ予約の保存の書き込み | `apply()`（非同期。失敗は黙って失われる） | 呼び出しスレッドで同期に書き終える。書き込みの失敗は `Result.failure(IOException)`（そのとき Alarm は置かれたまま。8.6） | README 8.6 |
| `toUri` で欠ける extra を持つ予約（`lossy`）の置き直し | 再起動・更新の後に、Parcel から欠けずに置き直す | 未来の項目は、再起動の後（または入れ直し・端末の移行の後、起動回数が読めない端末）は欠けた内容で置き直す。同じインストールで再起動していない間（更新の後、公開の `restoreScheduled`）は置き直さない（Alarm は欠けていない内容を持ったまま残る）。そのため、OS がその Alarm を消していた場合（正確なアラームの権限の取り消し、強制停止）は次の再起動まで戻らない。期限の過ぎた項目は今と同じく出して消す（内容は欠けたもの。生きている Alarm が後で発火すると、同じ id の通知が欠けていない内容で出し直される） | D-11 |
| 発火の後に保存から消す条件 | id と tag が同じなら消す | 世代も同じときだけ消す（発火と同じ鍵の予約し直しが重なったときに、新しい予約を消さない） | 競合の修正（README 8.6 の確実さ） |
| 受け手の中の保存の書き込みの失敗 | `apply()` なので見えない | 捕まえてログを出し、続ける（発火の受け手は shown を出す。置き直しは次の項目へ進む）。アプリは落ちない | README 8.6 |

**1b で直さない既存の口の不具合**（K-9。直すかは 2.0.0 の後に決める）:

| 不具合 | 既存の口 | 新しい口では |
|---|---|---|
| `isScheduled` と `cancelAllScheduled` が、`persistAcrossBoot=false` の予約を見ない | `NotificationUseCases.isScheduled`、`cancelAllScheduled` | （新しい予約の口は作らない。C ABI は既存の口を写し、第 2 部の対応表に書く） |
| 過ぎた時刻で同じ id を予約し直すと、前の Alarm が残り、後で前の内容で出る | `ScheduleNotificationUseCase` | 同上 |
| Alarm を置くのに失敗すると、Alarm の PendingIntent の内容は新しく、保存は前のまま、と食い違う | 同上 | 同上 |
| 回転すると listener が消え、結果が届かない | `AndroidDialogFragment` の listener の形 | 起きない（8.8） |
| `ComponentActivity` の STARTED の前に作る必要があり、結果の枠が 1 つ | `NotificationPermissionHelper` | 起きない（8.7） |
| 強制停止で Alarm が消えても、保存は残る | 予約の口 | 同上（KDoc とマニュアルに書く） |

### 3.4 不足前提

| 項目 | 扱い |
|---|---|
| Android 12 以降で、**アプリが後ろにいるとき**、通知の broadcast から Activity を起動できない（トランポリンの禁止）。アプリが前面なら通る | 公式の文書（Android 12 の動作の変更）に基づく。IT-11 で、コールドスタート・後ろ・前面の 3 通りを両方の環境で確かめる |
| 1.x の Alarm が更新の後に発火したとき、配られずに捨てられること | IT-18 と人の確認 CU-03 で確かめる |
| `Intent.toUri` / `parseUri` が残す項目（8.6 の表） | Android の実装に基づく。IT-14 で表の全行を確かめ、違えば表を直す |
| 受け手のクラス名を 2.0.0 の後に動かさないこと | 明示の component で届けるので、クラス名が予約と出ている通知の識別子になる。8.5 の変えない識別子の表に入れ、IT-24 で値を固定する |
| API 32 以下の端末 | 試験の環境に無い（API 35、36）。分岐を差し替えて確かめ（UT-06）、端末では確かめないと結果に書く |
| Unity の `UnityPlayerActivity` の上に透明な Activity を出したときの止まり方 | D-7 で受け入れた（`onPause`）。2c で見る |

## 4. 方針の適用の確かめ

### 4.1 共通の方針（`agent-rules/coding-rules/common.md`）

| 方針 | 適合 | この設計での扱い |
|---|---|---|
| 層とモジュールの対応（Manager 層までネイティブのライブラリ） | 適合 | 移すロジックと Manager の役はすべて `android_library`（6.3） |
| 層の依存と Port の型の制約 | 適合 | 足す port（Dialog、権限、設定の画面）は domain の型だけ。予約の保存は data の中に閉じる。既存の port `NotificationCommandRepository` は変えない。既存の `NotificationUseCases.isScheduled(context, …)` が data を直接読むのは今のまま残す（利用者の決定。8.14）Share のアイコンは `ByteArray`。**例外（1b の実装レビューで記録、2026-10-05）**: data から presentation のイベントの持ち主と受け手への依存が 3 か所ある（`ShareRepositoryImpl` → `ShareChooserActionReceiver`、`ShareCallbackCoordinator` → `ShareEvents`、`ScheduledNotificationReceiver` → `NotificationEvents`）。6.1 の置き場所（イベントの持ち主と受け手は presentation）から出るもので、今の `ShareCallbackCoordinator` が受け手を持つのと同じ形 |
| Manager → UseCase → Repository、1 操作 1 UseCase | 適合 | data に届く公開の操作ごとに UseCase を置き、Manager の役から呼ぶ（6.3）。data に届かない口（受け手の登録、presentation の監視、factory、純粋な関数）は UseCase を置かない（6.3 の条件） |
| Manager の公開 API（callback 版とネイティブ版） | 適合 | 結果を待つ操作（Dialog、権限）は callback 版と `suspend` 版（答えを返し、取り消しと失敗は型のある例外で投げる）。Share の選択は完了ではなくイベント（AC-22）なので、開く操作は同期の 1 つだけ |
| システム API に合わせた同期・非同期 | 適合 | 同期で済むもの（保存、分類、問い合わせ、開く）は同期のまま（9 章） |
| Delegate の所有 | 適合 | 通知の Receiver、Chooser Action・Share の結果の Receiver、Clipboard の監視、`ActivityLifecycleCallbacks` をライブラリの 1 つのクラスが持つ |

### 4.2 Android の方針（`agent-rules/coding-rules/android.md`）

| 方針 | 適合 | この設計での扱い |
|---|---|---|
| モジュール配置 | 適合 | 5 章の移すものをすべて `android_library` へ |
| 全メソッドの先頭で全パラメータの `Log.d` | **直す** | 秘密の値を伏せる例外を足す（8.11） |
| Manager の置き場所（`manager/` が無い） | **書き足す** | Android での Manager の役と置き場所（機能のパッケージの直下。0.7）、UseCase を置かない口の条件（6.3） |
| KDoc | 適合 | 足す公開の口に付ける |
| Coroutine（`suspend fun` + 例外送出） | 適合 | `AndroidDialogManager.show` と `AndroidNotificationManager.requestPermission` の `suspend` 版 |

`android.md` の 2 つの書き足し（ログ、Manager の役）は、**この設計書の決定と同じ PR** で行う。

## 5. 既存実装の差分（洗い出しの結果）

ブリッジの公開メソッドは 69 = `getInstance` 4 + 操作・問い合わせ 45 + listener の set / clear 20。listener の枠は 13（README 6 章）。

### 5.1 ブリッジとサンプルにしか無いもの

| # | 機能 | ブリッジ・サンプルの中身 | `android_library` に足りないもの |
|---|---|---|---|
| C1 | Clipboard | 操作を main で動かし、結果を listener で返す | （C ABI は読み書きを呼び出しスレッドで同期に呼び、戻り値で返す。C ABI の設計書 第 2 部 AP-3） |
| C2 | Clipboard | 例外を 7 つのコードにする | コードの分類 |
| C6 | Clipboard | プロセスで 1 つの監視、listener の例外を捕まえる | `ClipboardChangeMonitor` は 1 つではなく、スレッドに安全でない |
| D1 | Dialog | Context を `FragmentActivity` に変えて出す | 前面から出す口 |
| D2 | Dialog | 出すときの失敗を listener で返す | 失敗の報告 |
| D4 | Dialog | 単一選択の `null` を `-1` にする | （C ABI の側の写し） |
| D6 | Dialog | パスワードを `Log.d` に出す | （ブリッジは直さない。ライブラリの入力欄のログは直す。8.11） |
| N5 | Notification | Context から `canScheduleExactAlarms` | Activity の要らない口 |
| N6 | Notification | 任意の Context から設定の画面。Activity でなければ `NEW_TASK`、代わりにアプリの詳細 | Activity の要らない口 |
| N8 | Notification | `getIdentifier` でリソース名を引く | 名前の解決 |
| N10、N11、N14 | Notification | タップ・dismiss・アクション・カスタムビューのクリックを 1 つの Receiver で受け、`data` の JSON を付け、`launchApp` ならアプリを開く。request code は `id`、`id + Int.MAX_VALUE/4`、`id*100+index`、`id*100+50+index`。全画面は `id + Int.MAX_VALUE/2` | Receiver、イベント、同一性の体系。今の式は衝突する（id=1 のアクション 0 と id=100 のタップがどちらも 100）。`FLAG_UPDATE_CURRENT` が無いので古い extra が残る |
| N15 | Notification | shown の listener を 1 つの枠に書く | 複数の受け手、解除 |
| S2 | Share | Chooser Action の動的 Receiver（世代の token）。次の Share まで登録したまま | Receiver、イベント |
| S3 | Share | 選ばれたアプリを listener に返す。listener を外すと待ちも消す | 要求の印（全要求が同じ PendingIntent。AC-22） |
| S4 | Share | Direct Share のアイコンの Base64 を解く | （C ABI はバイト列で渡す） |
| 共通 | - | Clipboard と Share は main に移して動かす | （Share と Clipboard の監視は C ABI の受け口が main に積む。Clipboard の読み書きは同期に呼ぶ。第 2 部 AP-2、AP-3） |
| サンプル | - | 通知のアクション・dismiss、Chooser Action の Receiver 3 つ | ライブラリのイベントの口 |

### 5.2 `android_library` の今の不備と、この設計での扱い

| 不備 | 場所 | 扱い |
|---|---|---|
| `AndroidDialogFragment` の listener は回転で消える | `dialog/AndroidDialogFragment.kt` | 新しい口は門で避ける（8.8）。listener の形は 3.3 |
| `AndroidDialogFragment` が入力の全文を `Log.d` に出す（333、349 行。Login ではパスワード） | 同上 | 1b で直す（8.11） |
| Share の `Log.d` が `ShareContent`（data class）を補間して本文を出す | `share/` | 1b で、ログの箇所で長さだけを出す（8.11） |
| `NotificationPermissionHelper` の制約 | `notification/presentation/permission/` | 新しい口（8.7）。既存は 3.3 |
| `NotificationShownSupport` は層の外の 1 つの枠 | `notification/NotificationShownSupport.kt` | 今の名前のまま残し、新しい `NotificationEvents.shown` を別に置く（8.13） |
| application が data に依存、presentation が data の型を使う | `notification/` | 既存の port と組み立ての根（8.14） |
| `ShareCallbackCoordinator` の待ちは全要求が同じ PendingIntent | `share/data/repository/` | 要求ごとの PendingIntent（8.9） |
| 予約の保存が Parcel と `apply()`、Alarm の extra がライブラリの Parcelable、Alarm の宛先がクラス名 | `NotificationSchedulerSupport.kt`、`NotificationRepositoryImpl.kt` | 直列化の形と宛先だけを変える（8.6） |

## 6. 実装アーキテクチャ

### 6.1 足すファイルと可視性

`android/android_library/src/main/java/com/jonghyunkim/nativetoolkit/` の下。ファイル名は 1b の実装に合わせた（2026-10-05、1b の実装結果 7 章。小さな型は 1 つのファイルにまとめた）。可視性の「RG」は `@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)`（同じ Maven の group の C ABI の AAR からだけ使う）。公開と RG の宣言は付録 A（16 章）。

| ファイル | 中身 | 可視性 |
|---|---|---|
| `common/runtime/LibraryRuntime.kt` | `ensureInitialized`、`isInitialized`、`addOnInitializedListener`、`InitState` | public |
| `common/runtime/LibraryInitializer.kt` | androidx.startup の Initializer | public（manifest から引く） |
| `common/runtime/InitializationState.kt` | 初期化の状態と「済んだら呼ぶ」の一覧（UT-01） | internal |
| `common/runtime/MainPoster.kt` | 1 つの `Handler(main)`、同期メッセージだけで積む | RG |
| `common/runtime/RuntimeSupport.kt` | `RequestIds`（使い回さない 64 ビットの ID。`AtomicLong`、1 から。RG）、`ProcessNonce`（プロセスごとの 64 ビットの乱数。`SecureRandom`、初めて使うときに作る。internal）、`LibraryExecutors`（ディスクの処理用の 1 本のスレッド。internal） | 型ごと |
| `common/event/EventHub.kt` | `EventHub<T>`、`Listener`、`Registration` | public |
| `common/domain/UiReasons.kt` | `UiUnavailableReason`、`CancelReason`（共通の値） | public |
| `common/presentation/ForegroundActivityTracker.kt` | `ActivityLifecycleCallbacks` | RG |
| `common/presentation/UiHost.kt`、`UiHostCore.kt` | 前面の `FragmentActivity` を得る、宿主の記録と見張り。`UiHostCore.kt` に `UiHostClient` と、状態の表を単体テスト（UT-03）で確かめるための `UiHostCore`・`UiHostEnvironment` を置く | internal |
| `common/presentation/UiRequestGate.kt` | 要求の ID ごとの「完了済み」の門（main だけ） | internal |
| `common/presentation/NtkHostActivity.kt` | 透明な宿主 | internal（manifest） |
| `common/logging/LogRedaction.kt` | `<redacted, length=N>` | RG |
| `clipboard/domain/error/ClipboardErrorCode.kt` | 7 つのコードと `of` | public |
| `clipboard/presentation/ClipboardObserver.kt` | プロセスで 1 つの監視（Delegate の持ち主） | internal |
| `clipboard/presentation/ClipboardEvents.kt` | `changes: EventHub<Unit>` | internal |
| `clipboard/AndroidClipboardManager.kt` | 入口（6.3。機能のパッケージの直下。0.7） | public |
| `dialog/AndroidDialogFragment.kt` | **今の場所のまま**。要求の ID を入れる internal の factory を足す（8.8） | public（今と同じ） |
| `dialog/domain/model/DialogRequest.kt`、`DialogResult.kt` | 要求と結果（`DialogRequest.kt` に `DialogOptions`・`DialogButton`、`DialogResult.kt` に `DialogValue`） | public |
| `dialog/domain/error/DialogError.kt` | 失敗の値 `DialogError` と、`suspend` 版が投げる例外 `DialogDomainError` | public |
| `dialog/application/port/DialogPresenter.kt` | port | public |
| `dialog/application/usecase/DialogUseCases.kt` | `ShowDialogUseCase`、`CancelDialogUseCase`（1 操作 1 クラス） | public |
| `dialog/presentation/FragmentDialogPresenter.kt` | port の実装 | internal |
| `dialog/AndroidDialogManager.kt` | 入口（6.3。機能のパッケージの直下。0.7） | public |
| `notification/domain/model/NotificationPermissionModels.kt` | `PermissionRequestResult`、`NotificationSettingsTarget`、`NotificationSettingsOpenResult`（結果と値） | public |
| `notification/domain/error/PermissionRequestDomainError.kt` | `suspend` 版が投げる例外 | public |
| `notification/application/port/NotificationPermissionPorts.kt` | `NotificationPermissionPort`、`NotificationSettingsPort` | public |
| `notification/application/usecase/NotificationPermissionUseCases.kt` | `RequestNotificationPermissionUseCase`、`CancelNotificationPermissionRequestUseCase`、`CanScheduleExactAlarmsUseCase`、`OpenNotificationSettingsUseCase`（1 操作 1 クラス） | public |
| `notification/data/repository/NotificationRepositoryImpl.kt`、`NotificationSchedulerSupport.kt`、`ScheduledNotificationReceiver.kt`、`ScheduledNotificationBootReceiver.kt`、`NotificationUseCasesFactory.kt` | (直す) 8.6 の対応表のとおり、保存・Alarm の extra・宛先・排他を置き換える | 今と同じ |
| `notification/application/usecase/NotificationUseCases.kt` | (直す) `isScheduled(context, …)` が新しい保存を直接読む（今と同じく data を直接呼ぶ。8.14） | public（今と同じ） |
| `notification/presentation/progress/ProgressForegroundServiceIntents.kt`、`ProgressForegroundService.kt`、`notification/presentation/call/CallStyleForegroundService.kt` | (直す) 8.14 | 今と同じ |
| `notification/data/repository/JsonNotificationScheduleStore.kt` | `AtomicFile` と JSON（data の中だけで使う）。今の data の中の型 `ScheduledNotificationEntry` もここに移し、`generation`、`lossy`、`installId`、`bootCount` を足す | internal |
| `notification/data/repository/NotificationJsonCodec.kt` | command・schedule と JSON | internal |
| `notification/data/repository/ScheduledAlarmExtras.kt` | Alarm の extra の形（8.6） | internal |
| `notification/data/repository/ScheduleLock.kt` | 予約の操作の排他。インストールごとの印（`noBackupFilesDir`）と起動の回数を返す `ScheduleIdentity`、IT-12・IT-13 の注入の口 `ScheduleTestHooks` も置く | internal |
| `notification/data/repository/LegacyScheduleCleaner.kt` | 1.x の破棄。状態の移り変わりを `LegacyScheduleDiscard`（UT-05）、端末の操作を `AndroidLegacyScheduleEnvironment` に分ける | internal |
| `notification/data/repository/AndroidNotificationSettingsGateway.kt` | 設定の画面の port の実装（Context を持つ） | internal |
| `notification/presentation/resource/NotificationResourceResolver.kt` | 名前の解決 | public |
| `notification/presentation/event/NotificationEvents.kt` | イベントの口と、イベントの型 `NotificationInteraction`・`NotificationShown`（型は public） | internal（型は public） |
| `notification/presentation/event/NotificationEventReceivers.kt` | manifest の Receiver `NotificationEventReceiver` と見えない Activity `NotificationLaunchActivity`（完全名は 8.5 の変えない識別子） | internal |
| `notification/presentation/event/NotificationEventIntents.kt` | PendingIntent の要求を作る（factory） | public |
| `notification/presentation/permission/FragmentPermissionRequester.kt` | port の実装と、画面の無い Fragment `PermissionRequestFragment` | internal |
| `notification/presentation/permission/PermissionSessions.kt` | 権限の要求の会の表（UT-06） | internal |
| `notification/AndroidNotificationManager.kt` | 入口（6.3。機能のパッケージの直下。0.7） | public |
| `share/domain/model/ShareChooserAction.kt`、`ShareSelection.kt` | 値 | public |
| `share/application/port/ShareRepository.kt` | (直す) 3 つの関数を既定の実装つきで足す | public（今と同じ） |
| `share/application/usecase/ShareForSelectionUseCase.kt`、`CancelShareSelectionUseCase.kt`、`ShareTextWithActionsUseCase.kt` | 1 操作 1 クラス | public |
| `share/domain/error/ShareDomainError.kt` | (直す) `InvalidChooserAction` を足す | public（今と同じ） |
| `share/presentation/ShareEvents.kt` | `chooserActions`、`selections` | internal |
| `share/AndroidShareManager.kt` | 入口（6.3。機能のパッケージの直下。0.7） | public |
| `share/presentation/ShareChooserActionReceiver.kt` | 動的 Receiver（プロセスで 1 つ） | internal |
| `share/data/repository/ShareCallbackCoordinator.kt` | (直す) 要求ごとの印、ロックの外での呼び出し | internal（今と同じ） |
| `share/data/repository/ShareRepositoryImpl.kt` | (直す) 要求ごとの PendingIntent、型のある Chooser Action | public（今と同じ。1.12.0 から public） |

ほかに:

| ファイル | 変更 |
|---|---|
| `android/android_library/src/main/AndroidManifest.xml` | `InitializationProvider` の `meta-data`、`NotificationEventReceiver`、`NotificationLaunchActivity`、`NtkHostActivity`（どれも `exported=false`、`<intent-filter>` なし。明示の component で届ける） |
| `android/android_library/src/main/res/values/ntk_themes.xml` | (新) 宿主と見えない Activity のテーマ（利用者のアプリの `themes.xml` とぶつからない名前） |
| `android/android_library/consumer-rules.pro` | 8.12 |
| `android/android_library/build.gradle.kts`、`android/gradle/libs.versions.toml` | `androidx.startup:startup-runtime:1.2.0`（README 8.3） |
| `agent-rules/coding-rules/android.md` | ログの規則の例外（8.11）、Android での Manager の役と UseCase を置かない口の条件（6.3）。**この設計書の決定と同じ PR** |

### 6.2 スレッドの規則（Kotlin の API）

| 規則 | 内容 |
|---|---|
| 呼べるスレッド | 結果を待つ操作、取り消し、`LibraryRuntime`、Share と設定の画面の口、同期の UseCase は、どのスレッドからでも呼べる。**main だけの口**: `EventHub` の足す・外す、`ForegroundActivityTracker`、`AndroidClipboardManager` の `startObserving` / `stopObserving` / `isObserving`（main 以外から呼ぶと `IllegalStateException`） |
| 待たない | どの口も main を待たない。main で動かす処理は `MainPoster.post` で積む（main から呼んでも積む） |
| コールバック | 新しい口の完了とイベントは、すべて main で呼ぶ。**呼び出しの中で同期に呼ばない。例外は `EventHub.addListener` が保っていたイベントを渡すことだけ**（K-7。8.4） |
| 積む順 | `MainPoster` は 1 つの `Handler(Looper.getMainLooper())` に同期メッセージだけを積む |
| ロック | 利用者のコールバックを呼ぶ間、ライブラリのロックを持たない（K-2） |
| 例外 | **新しい口**（`EventHub` の受け手、新しい完了のコールバック）が投げた例外は、ライブラリが捕まえてログを出し、ほかの受け手・待ちの処理を続ける。**既存の口**（`shareWithCallback` の `onResult` / `onFinished`、`AndroidDialogFragment` の listener など）の例外の伝わり方は今のまま |
| ディスク | 同期の予約の口は、呼び出しスレッドでファイルに書く（8.6）。main から呼ぶと、ディスクの書き込みと、ほかのスレッドの予約の操作の書き込みを待ちうる（StrictMode のディスクの書き込みに当たる）と KDoc に書く。予約の 2 つの受け手は今と同じく main の上で同期に行う（小さなファイル）。1.x の破棄だけを `LibraryExecutors` で行う |

### 6.3 機能ごとの Manager（KA-18）

ほかの OS（iOS・macOS の `Ios*Manager`・`Mac*Manager`、Windows の `Windows*Manager`）とそろえ、`android_library` に機能ごとの入口 `AndroidClipboardManager`、`AndroidDialogManager`、`AndroidNotificationManager`、`AndroidShareManager` を置く（利用者の決定。2026-10-04）。

| 規則 | 内容 |
|---|---|
| 役目 | 入口だけ（ファサード）。UseCase と、イベント・監視・宿主の持ち主に委ね、ロジックを持たない（common.md の「Manager 内でロジックを重複させない」） |
| 置き場所 | 機能のパッケージの直下（`<機能>/Android*Manager.kt`。パッケージは `com.jonghyunkim.nativetoolkit.<機能>`）。層のパッケージ（`domain`・`application`・`data`・`presentation`）には入れない。ほかの OS と同じ（0.7） |
| 形 | `class Android*Manager internal constructor(依存)` と `companion object { @JvmStatic fun getInstance(context: Context) }`。プロセスで 1 つ。持つのは Application の Context だけ（Activity を持ち続けない。前面の Activity はそのつど `ForegroundActivityTracker` から引く） |
| テスト | internal の constructor で UseCase と port を差し替える（iOS の `IosNotificationManager` が repository を受け取れるのと同じ） |
| 公開の API | 結果を待つ操作は callback 版と `suspend` 版、同期の操作は同期のまま（委ねる UseCase と同じ引数・戻り値・例外・スレッド）。**例外は `AndroidShareManager.shareText(content, preview)` だけ**で、Chooser Action の JSON の引数を出さず、`ShareTextUseCase(content, "[]", preview)` に委ねる（README 4 章の「Kotlin の API では Chooser Action を型にする」。型のある Chooser Action は `shareTextWithActions` で受ける）。宣言は付録 A |
| C ABI | C ABI の受け口（`capi.jni`）は、機能ごとにこの Manager を呼ぶ。C 特有の処理（UTF-8 の変換、ハンドル、登録の表と `release`、前面の判定 C-4）は受け口に残す（8.15） |
| 既存の入口 | `ClipboardUseCases`・`ShareUseCases`・`NotificationUseCases`・`AndroidDialogFragment`・`NotificationPermissionHelper`・`ProgressForegroundNotifications` などの既存の公開の口は、今の形と動作で残す（K-9）。マニュアルは Manager を勧める入口として書く（段階 4） |
| 持ち主の可視性 | `NotificationEvents`・`ShareEvents`・`ClipboardEvents`・`ClipboardObserver` は internal にし、Manager のプロパティと関数から使う |

**UseCase を置かない口の条件**（`android.md` に書く）: common.md の「Manager は必ず UseCase 経由で Data 層にアクセスする」は、Data 層に届く操作の規則である。次の口は Data 層に届かないので UseCase を置かない。(1) presentation の Delegate の持ち主への受け手の登録・解除と監視の開始・停止、(2) presentation の PendingIntent の要求の factory、(3) Context の資源の即時の問い合わせ（リソース名の解決）、(4) 状態を持たない純粋な関数（エラーの分類）、(5) 初期化。

| 公開の口 | Manager | UseCase | 委ねる先 |
|---|---|---|---|
| Clipboard の既存の操作（コピー 4 種、消去、読み取り、`hasClip`、説明） | `AndroidClipboardManager` | 既存の Clipboard の UseCase | `ClipboardRepositoryImpl` |
| Clipboard の監視の開始・停止、変更のイベント | `AndroidClipboardManager` | 置かない（条件 1） | `ClipboardObserver`、`ClipboardEvents` |
| Clipboard のエラーの分類 | `AndroidClipboardManager.errorCodeOf`（`ClipboardErrorCode.of` も公開） | 置かない（条件 4） | `ClipboardErrorCode` |
| Dialog を出す・取り消す | `AndroidDialogManager` | `ShowDialogUseCase`、`CancelDialogUseCase` | `FragmentDialogPresenter` |
| 通知の既存の操作（表示、更新、消去、チャンネル、予約、`getActive`、問い合わせ） | `AndroidNotificationManager` | 既存の Notification の UseCase | `NotificationRepositoryImpl` |
| 予約の有無 | `AndroidNotificationManager.isScheduled` | 既存の `NotificationUseCases.isScheduled(context, …)` に委ねる（今と同じく data の保存を直接読む。利用者の決定） | `JsonNotificationScheduleStore` |
| Progress の前景サービス | `AndroidNotificationManager` | 今の公開の `ProgressForegroundNotifications` に委ねる（今と同じ経路） | 前景サービス |
| 権限の要求・取り消し | `AndroidNotificationManager` | `RequestNotificationPermissionUseCase`、`CancelNotificationPermissionRequestUseCase` | `FragmentPermissionRequester` |
| 正確なアラームの可否、設定の画面 | `AndroidNotificationManager` | `CanScheduleExactAlarmsUseCase`、`OpenNotificationSettingsUseCase` | `AndroidNotificationSettingsGateway` |
| 通知のイベント（タップ・アクション・dismiss、shown） | `AndroidNotificationManager` | 置かない（条件 1） | `NotificationEvents` |
| Share の既存の操作（テキスト、画像、ファイル、Direct Share、`shareWithCallback` と取り消し） | `AndroidShareManager` | 既存の Share の UseCase | `ShareRepositoryImpl` |
| 選択をイベントで受ける Share、取り消し、選択のイベント | `AndroidShareManager` | `ShareForSelectionUseCase`、`CancelShareSelectionUseCase` | 同上、`ShareEvents` |
| 型のある Chooser Action つきの Share、アクションのイベント | `AndroidShareManager` | `ShareTextWithActionsUseCase` | 同上、`ShareChooserActionReceiver` |
| 通知のイベントの PendingIntent を作る | -（公開の factory `NotificationEventIntents`） | 置かない（条件 2） | - |
| リソース名の解決 | -（公開の `NotificationResourceResolver`） | 置かない（条件 3） | - |
| 初期化 | -（公開の `LibraryRuntime`） | 置かない（条件 5） | - |

## 7. 今のブリッジの約束の対応表（README 5.1）

「C ABI / 包み」は、Kotlin の API では持たず C ABI の受け口（第 2 部）か Unity の包み（2c）が持つもの。

| ブリッジの約束 | 新しい Kotlin の API | 違い |
|---|---|---|
| Clipboard の操作の結果を listener で返す（C1） | 同期の UseCase（今と同じ） | 結果の口は C ABI / 包み |
| 7 つのエラーコード（C2） | `AndroidClipboardManager.errorCodeOf(throwable)` | 文言は包み |
| `hasClip` は例外を偽にする（C4） | `ClipboardUseCases.hasClip()` は投げる（今と同じ） | 偽にするのは C ABI / 包み |
| 変更の監視はプロセスで 1 つ（C6） | `AndroidClipboardManager` の `startObserving` と `changes` | 受け手を複数持てる |
| Dialog を Context から出す、失敗を返す（D1、D2） | `AndroidDialogManager.show`。失敗は `DialogResult.Failed` | 前面でなければ `Failed(NOT_FOREGROUND)`。Activity でない前面では透明な宿主に出す |
| Dialog の listener は種類ごとに 1 つで差し替え（D5） | 要求ごとの `onResult` | 包みが 1 つの受け手に集める |
| 単一選択の `null` を `-1`（D4） | `DialogValue.SingleChoice(index: Int?)` | `-1` は C ABI / 包み |
| キャンセルの戻りが `"Cancel"`、入力が `""` | `DialogResult.Dismissed` | 包みが今の値に写す（C ABI は値の無い `DISMISSED` を返す。第 2 部 AP-13） |
| 通知の操作の結果を呼び出しスレッドで同期に返す（N1） | 同期の UseCase（今と同じ） | - |
| `canScheduleExactAlarms`、設定の画面（N5、N6） | `AndroidNotificationManager` の `canScheduleExactAlarms`、`openSettings` | - |
| リソース名の解決（N8） | `NotificationResourceResolver` | - |
| タップ・アクション・dismiss・カスタムビューのクリック（N10、N14） | `NotificationEventIntents` と `AndroidNotificationManager.interactions` | 受け手が 0 の間のものを保つ。アプリを開くものは見えない Activity を通す。起動の flags はランチャーと同じ（8.5）。起動の Intent の action を `actionId` に書き換えるのはやめる（このリポジトリに読む所が無い。2c で確かめる） |
| 全画面の Intent（`id + Int.MAX_VALUE/2`、起動の Intent） | `NotificationEventIntents.fullScreenLaunch` | request code 0、`setIdentifier` で区別（8.5） |
| request code の式（N11） | data の URI か `setIdentifier` で区別し、request code は 0 | 衝突しない |
| shown の listener（N15） | `AndroidNotificationManager.shown` | 受け手を複数持てる |
| Progress の値の補正（N12）、style の代わりの値（N9）、JSON の検査の文言（N16） | 持たない | Progress の補正は C ABI（第 2 部 AP-9）。style の代わりの値と文言は包み（C ABI は範囲外をエラーで返す。AP-8） |
| Chooser Action の Receiver（S2） | `AndroidShareManager` の `shareTextWithActions` と `chooserActions` | action の文字列はライブラリが決める |
| 選ばれたアプリの listener、listener を外すと待ちも消す（S3） | `AndroidShareManager` の `shareForSelection`、`selections`、`cancelShareSelection(token)` | 選択に印が付く。古い Chooser の選択は届かない |
| アイコンの Base64（S4） | バイト列（今と同じ） | Base64 は包み |
| Clipboard と Share の操作を main で動かす | 同期の UseCase（今と同じ） | Share は C ABI の受け口が main に積む。Clipboard の読み書きは呼び出しスレッドで同期に呼ぶ（第 2 部 AP-3）。監視の開始と停止は main に積む（AP-2） |

## 8. サブ機能別詳細設計

### 8.1 初期化（KA-1、K-8）

宣言は付録 A。状態（未着手・途中・済み）と「済んだら呼ぶ」の一覧は、1 つの短いロック（`lock`）の中だけで変える。ロックの中では I/O もコールバックもしない。

| 出来事 \ 状態 | 未着手 | 途中 | 済み |
|---|---|---|---|
| `ensureInitialized(context)` | ロックの中で途中にする → ロックの外で次を行う: Application の Context を保存、`ForegroundActivityTracker` を登録。成功ならロックの中で済みにし、一覧を外す → 外した一覧の各関数を `MainPoster.post` で積む → `DONE`。例外なら、登録を外し、保存を消し、ロックの中で未着手に戻す → `ERROR`（一覧は残す） | `IN_PROGRESS` | `DONE` |
| `addOnInitializedListener(f)` | ロックの中で一覧に足す | 同左 | ロックの外で `f` を `MainPoster.post` で積む |

- どの状態でも、`context` が Activity なら `ForegroundActivityTracker.seed(activity)` を `MainPoster.post` で積む（勝ち負けに関係なく。C ABI の設計書 5.3）
- 済みになった呼び出しは、`LegacyScheduleCleaner.runOnce` を `LibraryExecutors` に積む（8.6。初期化の成否に入れない）
- 一覧の各関数は、済みになったときに外されて 1 回だけ積まれるか、済みの後に足されて 1 回だけ積まれるかのどちらか（ロックの中で状態と一覧を一緒に見るので、取りこぼしも二重も無い）
- `Application` でない `applicationContext`（テストの Context など）は失敗（`ERROR`）
- Startup を無効にした Kotlin の利用者は `LibraryRuntime.ensureInitialized(activity)` を呼ぶ（マニュアル。段階 4）。呼ばないと、前面が要る口は `NOT_INITIALIZED` で完了する。それ以外の口は今と同じく初期化なしで動く

### 8.2 前面の Activity を追う仕組み（KA-2、K-5）

- 記録（`WeakHashMap<Activity, Record>`）: `started`、`stopped`、`stateSaved`、started の順の番号
- `onActivityStarted`: `started = true`、`stopped = false`、`stateSaved = false`、番号を新しくする。`onActivityStopped`: `stopped = true`。`onActivitySaveInstanceState`: `stateSaved = true`。`onActivityDestroyed`: 記録を消す
- `current()`: `started && !stopped && !stateSaved && !isFinishing` のうち番号が最大のもの（C ABI の設計書 5.8）。`currentFragmentActivity()`: `current()` が `FragmentActivity` で、その `supportFragmentManager.isStateSaved` が偽ならそれ
- `seed(activity)`: 記録がまだ無く、`isFinishing` でも `isDestroyed` でもなければ、started の記録を作る。`LifecycleOwner` なら `lifecycle.currentState` が STARTED 以上のときだけ。記録があれば何もしない
- 誤って後ろの Activity を前面とした場合は、宿主の起動の見張り（8.3）で `NOT_FOREGROUND` になる

### 8.3 透明な宿主と要求の状態（KA-3、KA-4、K-3）

**要求の門** `UiRequestGate`（main だけ）: 要求の ID ごとに `ACTIVE` の印を持つ。`tryComplete(id)` は、印があれば消して `true`、無ければ `false`。Dialog と権限の個々の要求のすべての完了は、`tryComplete` が `true` のときだけ利用者の関数を呼ぶ（ちょうど 1 回）。

**宿主の利用者** `UiHostClient`（main だけ）: `isActive(): Boolean`、`onReady(activity: FragmentActivity)`、`onUnavailable(reason: UiUnavailableReason)`。Dialog の要求は 1 つの要求が 1 つの利用者（`isActive` は門に印があるか）。権限の要求は会が 1 つの利用者（8.7）。

**`UiHost.acquire(client)`**（main だけ）:

| 状況 | 動き |
|---|---|
| 初期化されていない | `client.onUnavailable(NOT_INITIALIZED)` |
| `currentFragmentActivity()` がある | その場で `client.onReady(activity)` |
| 起動を待っている宿主の記録がある | その記録の一覧に足す（宿主を 2 つ起動しない） |
| 前面が `FragmentActivity` だが、状態を保存した後（`supportFragmentManager.isStateSaved`） | `client.onUnavailable(NOT_FOREGROUND)`（宿主を起動しない。1b の実装で足した行、2026-10-05） |
| `current()` があるが `FragmentActivity` でない | 宿主の記録（印 = `RequestIds.next()`、一覧 = この利用者）を作り、`current()` から `NtkHostActivity` を起動する（extra に印、`ActivityOptions.makeCustomAnimation(…, 0, 0)`）。`startActivity` が投げたら、記録を消し、一覧の `isActive` な利用者に `onUnavailable(HOST_START_FAILED)`。投げなければ 5 秒の見張りを `postDelayed` で積む |
| `current()` が無い | `client.onUnavailable(NOT_FOREGROUND)` |

**宿主の記録の寿命**: 宿主の記録は `UiHost` に 1 つまで。次のどれかで消える。

| 出来事 | 動き |
|---|---|
| 宿主の `onCreate`（`savedInstanceState == null`）で、extra の印が記録の印と同じ | 記録を消し、見張りを外す。一覧のうち `isActive` な利用者に `onReady(宿主)` を順に呼ぶ。その後 `finishIfIdle()` |
| 宿主の `onCreate`（`savedInstanceState == null`）で、印が違う・記録が無い（見張りで終わった、プロセスの死の後） | `finish()` |
| 見張り（5 秒） | 記録を消し、一覧の `isActive` な利用者に `onUnavailable(NOT_FOREGROUND)` |
| `startActivity` の例外 | 上の表のとおり |

**宿主が閉じる条件** `finishIfIdle()`: 宿主の `supportFragmentManager` に、タグが `ntk.` で始まる Fragment が 1 つも無ければ `finish()`。呼ぶ所: 宿主の `onCreate` の終わり（作り直しのときは `super.onCreate` が Fragment を戻した後）、**ライブラリの Fragment が宿主から外れるすべての経路**（Fragment の `onDestroy` が、Activity が設定の変化中でなければ、宿主に `MainPoster.post` で `finishIfIdle()` を積む。結果、取り消し、表示の失敗の後の後始末、戻された Fragment が自分を外す場合のどれも、この経路を通る）。`onReady` の中の `showNow` / `commitNow` が投げた場合も、利用者が失敗で完了した後に `finishIfIdle()` を積む（1b の実装では、Dialog は積み、権限の会は積まない。権限の会の `onReady` は宿主の `onCreate` の中で呼ばれ、その終わりに `finishIfIdle()` が呼ばれるので、閉じ損ねは起きない）。`showNow` / `commitNow` の `IllegalStateException` は、理由を問わず状態の保存とみなす

**Dialog の要求の状態**:

| 出来事 \ 状態 | 起動待ち | 出ている（Fragment がある） | 完了 |
|---|---|---|---|
| `onReady(activity)` | `showNow(fm, "ntk.dialog.<id>")`。投げたら、状態が保存済み（`IllegalStateException`）なら `Failed(NOT_FOREGROUND)`、それ以外は `Failed(SHOW_FAILED)` | - | （`isActive` が偽なので呼ばれない） |
| `onUnavailable(reason)` | `Failed(reason を写した値)` | - | 呼ばれない |
| 取り消し | `Canceled(REQUESTED)`（宿主が来ても渡さない） | `dismissAllowingStateLoss()` → `Canceled(REQUESTED)` | 何もしない |
| ボタン・戻る・外側のタップ | - | `Button` / `Dismissed` | 何もしない |
| Fragment の `onDestroy`（設定の変化中でない） | - | `Canceled(HOST_DESTROYED)` | 何もしない |
| Fragment の `onCreate` で ID が門に無い（プロセスの死の後に戻された） | - | `dismissAllowingStateLoss()` | - |

- 完了はすべて `tryComplete` を通すので、どの 2 つの出来事がどの順で来ても 1 回だけ
- Fragment は `showNow` / `commitNow` で足す（非同期の commit と `finishIfIdle()` の間に隙間を作らない）

**`NtkHostActivity` の契約**:

| 項目 | 決定 | 理由 |
|---|---|---|
| 基底 | `FragmentActivity` | DialogFragment と Activity Result |
| テーマ | 親は `@android:style/Theme.DeviceDefault.DayNight`。`windowIsTranslucent`、`windowBackground` 透明、`windowNoTitle`、`windowAnimationStyle` なし、`backgroundDimEnabled` false | Dialog の見た目を端末の既定とダークモードに合わせる（`appcompat` は外した） |
| タスク | 前面の Activity から `NEW_TASK` なしで起動し、同じタスクに積む | ゲームのタスクの中で出す。Recents の項目は増えない |
| `excludeFromRecents` | `true`（根になった場合の保険。根でなければ効かない） | |
| `exported` | `false` | |
| `configChanges` | 向き、画面の大きさ、レイアウト、最小幅、キーボード、ナビゲーション、UI モード、密度、文字の大きさ、言語、レイアウトの向き（manifest では縦棒でつなぐ） | 多くの変化で作り直さない。作り直された場合も上の表で続く |
| `windowSoftInputMode` | `adjustResize` | 入力欄の Dialog |

### 8.4 イベントの口（KA-5、K-1、K-2、K-7）

- **足す**: 登録を作って一覧の末尾に足す。保ちが空でなければ、**保ちを外してから**、この呼び出しの中で受けた順に、足した受け手に渡す（6.2 の例外。K-7）。受け手には `Registration` を引数で渡すので、戻り値を受け取る前でも自分を外せる
- **渡す途中で受け手が外された**: まだ渡していない残りは、一覧に残っている最も古い受け手に続けて渡す（受け手の中で足された受け手を含む）。残っている受け手が無ければ、保ちの先頭に戻す（次の `addListener` で渡す）
- **出す**: 一覧が空なら、保つ口は保ちの末尾に足す（容量を超えたら古いものから捨て、ログを出す）。保たない口は捨てる。一覧が空でなければ、一覧の写しを取り、各受け手を呼ぶ直前に外されていないかを見てから呼ぶ
- 保ちが溜まるのは一覧が空の間だけなので、受け取るのは次に足された 1 人目（K-7 の「誰に渡すか」）
- C ABI の受け口は、挿入のメッセージ（main）の中で `addListener` を呼ぶので、保ったイベントはその後に積まれたイベントより先に届く
- ロックは持たない（main だけ）。受け手の例外は捕まえて次へ進む

| 口 | 型 | 保つ |
|---|---|---|
| `NotificationEvents.interactions` | `NotificationInteraction` | 32 件 |
| `NotificationEvents.shown` | `NotificationShown` | 保たない |
| `ShareEvents.chooserActions` | `String`（アクションの id） | 保たない |
| `ShareEvents.selections` | `ShareSelection`（印、パッケージ名） | 保たない |
| `ClipboardEvents.changes` | `Unit` | 保たない |

**保つ規則**（README 4 章、README 8.6）:

| 項目 | 決定 | 理由 |
|---|---|---|
| 対象 | 通知のタップ・アクション・dismiss | コールドスタートで、受け手を足す前に届くのはこれだけ |
| 件数 | 32。超えたら古いものから捨てる | 人の操作なので足りる。メモリを限る |
| 期限 | なし（プロセスの寿命） | ディスクには保たない |
| 順序 | 受けた順 | |
| 重複 | 除かない | broadcast を OS は二度送らない。2 回のタップは 2 つのイベント |

### 8.5 通知のイベント（KA-6、KA-7）

- 利用者は `NotificationEventIntents` が返した要求を `AndroidNotificationPlatformOptions` の各欄に入れる（今の型のまま）
- **Intent の形**: 明示の component（`NotificationEventReceiver` か `NotificationLaunchActivity`）、action `com.jonghyunkim.nativetoolkit.notification.action.EVENT`、data `ntk-notification-event://<パッケージ>/<kind>/<id>/<tag の欄>/<actionId の欄>`。tag の欄は、tag があれば `t` + tag、無ければ `n`。actionId の欄も同じく `a` + id か `n`（`Uri.Builder.appendPath` で符号化）。`data` の Map は JSON の文字列 1 つの extra（`com.jonghyunkim.nativetoolkit.notification.extra.DATA`）。受け手のクラス名は予約した通知の中の Intent（保存と Alarm に入る）に残るので、下の変えない識別子に入れ、2.0.0 の後に動かさない（targetSdk 34 以降は、明示の component でないと `exported=false` の受け手に届かないおそれがあるため、component を使う）
- **同一性**（KA-7）: data の URI が通知・種類・アクションごとに違う。request code は 0、flags は `FLAG_UPDATE_CURRENT` と `FLAG_IMMUTABLE`
- **アプリを開かないもの**（`launchApp=false`、dismiss）: `NotificationEventReceiver`（`exported=false`）への broadcast。`onReceive`（main）で `emit`
- **アプリを開くもの**（`launchApp=true`）: `NotificationLaunchActivity`（`exported=false`、`Theme.NoDisplay`、`excludeFromRecents`、`taskAffinity=""`、`noHistory`）への Activity の PendingIntent。`onCreate` の中で `emit` し、`getLaunchIntentForPackage` に `FLAG_ACTIVITY_NEW_TASK` と `FLAG_ACTIVITY_RESET_TASK_IF_NEEDED` を付けて起動し（ランチャーと同じ。アプリを開いていればそのタスクを前に出す）、`finish()` する（`Theme.NoDisplay` は `onResume` の前に `finish` が要る）。起動の Intent は data を持たない。起動の Intent が無ければイベントだけ出して閉じる
- 今のブリッジの形（Receiver から起動）は、アプリが後ろにいるとき Android 12 以降で開かない（3.4）
- **全画面**: `fullScreenLaunch` は起動の Intent に `NEW_TASK` と `RESET_TASK_IF_NEEDED` を付け、**data は付けず `Intent.setIdentifier("ntk-notification-launch/<id>/<tag の欄>")` で区別**した Activity の PendingIntent（request code 0、`FLAG_UPDATE_CURRENT` と `FLAG_IMMUTABLE`）。`identifier` は `filterEquals` に入る。アプリの Activity は `getIntent().getIdentifier()` で読めるが、アプリが読まない限り、deep link の処理（data を読む）には混ざらない。起動の Intent が無ければ `null`
- **shown**: `ScheduledNotificationReceiver` が予約を表示した後に `NotificationEvents.shown.emit`。今と同じく、予約の発火で表示を試みたとき（権限が無くて出なかった場合を含む）だけ。段階 3 まで `NotificationShownSupport.shownListener` にも呼ぶ（8.13）
- **リソース名の解決**: `NotificationResourceResolver(context)`（presentation）。`resolve(name, type)`（型は `drawable`・`mipmap`・`layout`・`id`。`null` なら `drawable`、`mipmap` の順）、`defaultSmallIcon()`（`applicationInfo.icon`、無ければ `android.R.drawable.ic_dialog_info`）。名前でしか引かれないリソースは利用者のリソースの縮小で消えうるので、`tools:keep` の書き方をマニュアルに書く（段階 4）

**変えない識別子**（2.0.0 の後に変えると、出ている通知と予約が壊れる。IT-24 で値を固定する）:

| 識別子 | 値 |
|---|---|
| 受け手のクラス名 | `com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventReceiver`、`com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationLaunchActivity`、`com.jonghyunkim.nativetoolkit.notification.data.repository.ScheduledNotificationReceiver` |
| 通知のイベントの action | `com.jonghyunkim.nativetoolkit.notification.action.EVENT` |
| 通知のイベントの scheme と extra | `ntk-notification-event`、`com.jonghyunkim.nativetoolkit.notification.extra.DATA` |
| 予約の action と scheme | `com.jonghyunkim.nativetoolkit.notification.action.SHOW_SCHEDULED`、`ntk-notification-schedule` |
| 予約の Alarm の extra | 8.6 の 4 つ |
| 全画面の identifier の前置き | `ntk-notification-launch/` |

### 8.6 予約の保存、Alarm の extra、1.x の破棄（KA-8、KA-9、D-11）

**原則**: 今の予約の流れ（順序、契機、対象、失敗の伝わり方）を 1 行ずつ写し、変えるのは**直列化の形と書き方、Alarm の宛先**だけにする（3 回目のレビューの止め方。レビューの記録 v3）。

**今のコードとの対応**（`NotificationRepositoryImpl`、`NotificationSchedulerSupport`、2 つの Receiver）:

| 今の行 | 今の動き | 1b の後 | 変わる所 |
|---|---|---|---|
| `schedule`（過ぎた時刻） | `send` → `remove(id, tag)` | 同じ | `remove` の書き方 |
| `schedule`（未来） | PendingIntent を作る（extra に Parcel）→ `scheduleAlarm` → `persistAcrossBoot` なら `persist`、違えば `remove` | PendingIntent を作る（extra は下の形）→ `scheduleAlarm` → 同じく `persist` か `remove` | extra の形、宛先、書き方。`scheduleAlarm` の例外は今と同じく伝わる（UseCase が `Result.failure` にする。保存は変えない） |
| `cancelScheduled` | Alarm を消す → `remove` | 同じ | 書き方 |
| `cancelAllScheduled` | `loadAll` の各 Alarm を消す → `clear` | 同じ | 書き方 |
| `restoreScheduled`（公開の口、`BOOT_COMPLETED`・`LOCKED_BOOT_COMPLETED`・`MY_PACKAGE_REPLACED`） | 保存の全項目: 過ぎたものは `send` → `remove`、未来のものは Alarm を置き直す | 同じ。**ただし未来の `lossy` の項目は、Alarm が生きているとき（下）は置き直さない**。置き直すときは保存した世代をそのまま使う | 下の「欠ける項目」、世代 |
| 発火（`ScheduledNotificationReceiver`） | main の上で同期に、extra の Parcel を読む → `send` → `remove(id, tag)` → shown | main の上で同期に、extra を読む → `send` → 同じ世代のときだけ `remove` → shown | extra の形、世代の条件 |
| `isScheduled(context, id, tag)` | data の `loadAll` を直接呼び、同じ id と tag があるか | 同じ（data の保存を直接読む。渡された repository に関係なく、Startup や初期化にも関係なく動く） | 読む保存の形だけ |
| `loadAll` の読めない要素 | `runCatching` で黙って飛ばす（文字列の集合には残る） | 同じく飛ばしてログを出す。ファイルを書き直すときは、読めない要素を元の JSON のまま残す | - |

**欠ける項目**（`lossy`）: 保存するときに、command の中の `Intent` に `toUri` で残らないもの（下の表）が 1 つでもあれば `lossy = true` とし、`installId`（インストールごとの印。`noBackupFilesDir/ntk/install_id` に初めて使うときに乱数で作る。バックアップに入らないので、入れ直しと端末の移行で変わる）と `bootCount`（`Settings.Global.BOOT_COUNT`。読めなければ -1）と一緒に保存する。**Alarm が生きている**とは、項目の `installId` と `bootCount` がどちらも今と同じで、`bootCount` が -1 でないこと。`restoreScheduled` は、未来の `lossy` の項目で Alarm が生きていれば置き直さない（置き直すと欠けた内容に変わるため）。生きていなければ（再起動・入れ直し・端末の移行の後）、欠けた内容で置き直す（D-11）。期限の過ぎた項目と `lossy` でない項目は今と同じ（出して消す、または同じ内容で置き直す）。違いは 3.3 に書いた。

**保存**:

| 項目 | 今 | 1b の後 |
|---|---|---|
| 保存する予約 | `persistAcrossBoot=true` だけ | 同じ |
| 場所 | `SharedPreferences` `android.library.notification.scheduler`（Auto Backup の対象） | `filesDir/ntk/notification_schedules.json`（同じく Auto Backup の対象。端末の移行の後の動きを今と同じにする） |
| 形式 | Parcel を Base64 | JSON（`Intent` は `toUri`、`Bitmap` は PNG の Base64） |
| 書き方 | `apply()` | `AtomicFile` で呼び出しスレッドで書き終える（`finishWrite` は fsync してから置き換える。`startWrite` の後で投げたら `failWrite`）。書き込みの失敗は `IOException` で伝わり、UseCase が `Result.failure` にする |

- 書き込みの失敗のときの状態: `schedule` は Alarm が置かれたまま（今の `apply()` の失敗と同じ。再起動の後には戻らない）。`cancelScheduled` は Alarm が消えたまま保存に残る（再起動の後に戻りうる）。`cancelAllScheduled` も同じ。後始末はしない。KDoc に書く
- JSON として読めないファイルは `.corrupt` に名前を変え、空として扱いログを出す
- **版の規則**: `{"v":1, ...}`。読む側は知らない欄を無視し、無い欄は既定の値にする。欄を足すだけなら版を上げない。互換の無い変更をするときだけ版を上げ、前の版を読む処理を残す。知らない版のファイルは `notification_schedules.v<版>.json` に名前を変えて残し、空として扱う（新しい版から戻した場合に消さない）
- 保存の型 `ScheduledNotificationEntry`（data の中だけ）: 今の欄に `generation: Long`、`lossy: Boolean`、`installId: String`、`bootCount: Int` を足す

**`toUri` で残るもの**（再起動の後に戻すときだけ効く。D-11。IT-14 で全行を確かめ、違えば表を直す）:

| `Intent` の項目 | 残るか |
|---|---|
| action、data、type、categories、component、package、selector、flags | 残る（`parseUri` に `URI_INTENT_SCHEME` と `URI_ALLOW_UNSAFE` を渡す。ライブラリの中だけのファイルなので URI の権限の flags も戻してよい） |
| extra の `String`、`Boolean`、`Byte`、`Char`、`Short`、`Int`、`Long`、`Float`、`Double` | 残る |
| それ以外の extra（`String` でない `CharSequence`、配列、`ArrayList`、`Parcelable`、`Uri`、`Bundle`、`Serializable`） | 落ちる（`lossy`）。落ちた extra のキーを警告のログに出す（値は出さない） |
| `ClipData` | 落ちる（`lossy`） |
| `sourceBounds`、`identifier` | 残る（1b の IT-14 で API 35・36 で確かめた） |

**Alarm の Intent**:

| 項目 | 2.0.0 の値 |
|---|---|
| 宛先 | 明示の component `ScheduledNotificationReceiver`（今と同じクラス。2.0.0 の後は動かさない。8.5 の変えない識別子）、action `com.jonghyunkim.nativetoolkit.notification.action.SHOW_SCHEDULED` |
| data | `ntk-notification-schedule://<パッケージ>/<tag か untagged>/<id>`（予約の鍵は今と同じく、tag が無ければ `untagged`。tag `untagged` の予約と tag の無い予約は、今と同じく同じ鍵になる。保存の鍵も同じ） |
| extra | 下の表 |
| request code、flags | 0、`FLAG_UPDATE_CURRENT` と `FLAG_IMMUTABLE` |

1.x の値（0e の結果 4 章）と component・action・data がすべて違うので、新旧の Alarm は重ならない。

**Alarm の extra**（`ScheduledAlarmExtras`）:

| extra | 型 | 中身 |
|---|---|---|
| `com.jonghyunkim.nativetoolkit.notification.extra.COMMAND_JSON` | `String` | command の JSON（`NotificationJsonCodec`。版の規則は上と同じ）。`Intent` と `Bitmap` の欄は、下の 2 つの並びの番号（`{"$intent":0}`、`{"$bitmap":0}`）で指す |
| `com.jonghyunkim.nativetoolkit.notification.extra.INTENTS` | `ArrayList<Intent>` | command の中の利用者の `Intent`（PendingIntent の要求の中身） |
| `com.jonghyunkim.nativetoolkit.notification.extra.BITMAPS` | `ArrayList<Bitmap>` | command の中の `Bitmap` |
| `com.jonghyunkim.nativetoolkit.notification.extra.GENERATION` | `Long` | 世代（保存しない予約にも新しい値を入れる。保存に無いので、発火の後の削除は何も消さない） |

- **ライブラリが Alarm に入れるもの**（JSON の文字列、`Intent`・`Bitmap` の並び、世代）には、ライブラリのクラス名が入らない。利用者が `Intent` に入れたもの（利用者自身の Parcelable、ライブラリの `ProgressForegroundServiceIntents` が作る前景サービスの Intent など）は、今と同じく利用者の責任とし、「予約する通知に前景サービスの Intent を入れると、更新をまたいで読めなくなりうる」と KDoc とマニュアルに書く
- 受け手は、extra を読む・JSON を解く・`Intent` と `Bitmap` を戻すのどこで失敗しても、例外を捕まえてログを出し、表示しない（アプリを落とさない）。世代の extra が読めれば、同じ世代の項目を保存から消す

**世代**: `schedule` のたびの新しい値。上位 32 ビットに `ProcessNonce` の下位 32 ビット、下位 32 ビットにプロセスの中の連番（`AtomicInteger`）。`restoreScheduled` が置き直す Alarm には、保存した項目の世代をそのまま入れる（発火の後に同じ世代で消えるため）。

**排他** `ScheduleLock`（`ReentrantLock`。同じスレッドの入れ子を許す）: 上の対応表の操作（`schedule`、`cancelScheduled`、`cancelAllScheduled`、`restoreScheduled`、発火の後の削除、`isScheduled`）の、**PendingIntent を作る処理（`FLAG_UPDATE_CURRENT` で extra と世代を書き換える）、`AlarmManager`、ファイルの部分**をロックの中で行う（同じ鍵の 2 つの予約が交わっても、Alarm の extra の世代と保存の世代が食い違わない）。`restoreScheduled` は保存の写しで回るが、項目ごとにロックを取り直したとき、保存にまだ同じ世代の項目があるかを読み直し、無ければ（その間に取り消し・予約し直しがあった）その項目を飛ばす。`send`（通知を組み立てて出す。`Bitmap` の URI の読み込みで利用者の ContentProvider を呼びうる）はロックの外で行い、対応表の順序（`send` → `remove` など）は保つ。ロックの中では利用者のコード（コールバック、ContentProvider）を呼ばない。main から呼んだ口は、ほかのスレッドのファイルの書き込みの間ロックを待ちうる（6.2、RK-10）。

**受け手**:

| 受け手 | 動き |
|---|---|
| `ScheduledNotificationReceiver` | 今と同じく main の上で同期に: extra を読む → `send`（投げたら今と同じく伝わる）→ 同じ世代のときだけ `remove`（書き込みの失敗は捕まえてログ）→ shown |
| `ScheduledNotificationBootReceiver`（`BOOT_COMPLETED`、`LOCKED_BOOT_COMPLETED`、`MY_PACKAGE_REPLACED`） | 今と同じく main の上で同期に `restoreScheduled`（上の対応表。項目ごとの書き込みの失敗は捕まえてログを出し、次の項目へ進む。公開の `RestoreScheduledNotificationsUseCase` から呼んだときも同じで、最後に失敗があれば `Result.failure(IOException)`）。1.x の破棄は `LibraryExecutors` に積む |

**1.x の破棄**（`LegacyScheduleCleaner.runOnce(context)`。KA-9）:

| 状態 | 意味 |
|---|---|
| 未着手 | まだ、または前の試みが失敗した |
| 実行中 | ほかのスレッドが行っている（`AtomicInteger` の CAS で取る。取れなければ何もしない） |
| 済み | 印のファイルがある |

1. 印のファイル `noBackupFilesDir/ntk/legacy_v1_discarded` があれば済み（端末ごとの印なので、バックアップに入れない）
2. `SharedPreferences` `android.library.notification.scheduler` の `entries` の各要素から、JSON のキー `android.intent.extra.shortcut.ID` の値を取る。**最後の `::` で分け**、後ろが整数でなければその要素は取り消せないので飛ばす（ログ。やり直しても同じなので失敗に数えない）。前が `untagged` なら tag なし
3. 1.x の Intent を組み直す（0e の結果 4 章: コンポーネント `<パッケージ>/android.library.notification.data.repository.ScheduledNotificationReceiver`、action `android.library.notification.action.SHOW_SCHEDULED`、data `native-toolkit-notification://<パッケージ>/<tag か untagged>/<id>`、`setPackage`）
4. `PendingIntent.getBroadcast(context, "<tag か untagged>::<id>".hashCode(), intent, FLAG_NO_CREATE | FLAG_IMMUTABLE)` が引ければ `alarmManager.cancel` と `PendingIntent.cancel`。要素ごとの例外は捕まえて「失敗した要素がある」と覚え、次の要素へ進む
5. 失敗した要素が無ければ `deleteSharedPreferences("android.library.notification.scheduler")` → 印のファイルを書いて済み
6. 失敗した要素がある、または 5 が失敗したら、`SharedPreferences` が残っていればそのまま残し、未着手に戻す（次の契機でやり直す。取り消しはやり直しても同じ結果になる。印だけが書けなかった場合は、次の試みで空の要素のまま 5 に進む）

- 呼ぶ所: `LibraryRuntime` が済みになったとき、`ScheduledNotificationBootReceiver`（`MY_PACKAGE_REPLACED`、`BOOT_COMPLETED`）、`NotificationUseCasesFactory` が初めて UseCase を作るとき。どれも `LibraryExecutors` に積む
- 保存しなかった 1.x の予約は列挙できないので消せない。発火しても受け手のクラスが無いので何も出ない（D-11。IT-18）
- `HostPhaseTest` が 1.x の `SharedPreferences` の名前で `commit()` している補い（`apply()` の遅れのため）は、1b で消す（UI テストを直す理由として結果に書く）

### 8.7 通知の権限の要求と設定の画面（KA-11、K-6）

**権限の要求**: `AndroidNotificationManager.requestPermission(onResult)` は、Manager が持つ Application の Context を持つ `FragmentPermissionRequester`（プロセスで 1 つ。port の実装）を使い、`RequestNotificationPermissionUseCase` を呼ぶ。UseCase は ID を `RequestIds` から取り、port の `request(id, onResult)` を呼んで ID を返す。port の実装は main に積み、門に ID を `ACTIVE` で入れてから、次の表で扱う。port の宣言は Context を持たない（実装が Application の Context を持つ）。

`suspend fun requestPermission(): Boolean` は許可されたかを返し、取り消しと失敗は `PermissionRequestDomainError`（`Canceled(reason)`、`Unavailable(reason)`）を投げる。コルーチンの取り消しでは `cancel(id)` を呼び、`CancellationException` を投げる（Kotlin の決まりのとおり）。

会（`session`）は 1 つまで。会の ID は門に入れない。会は `UiHostClient` で、`isActive()` は「この会が今の会で、待ちが 1 つ以上あるか、Fragment を足した後か」。

| 出来事 \ 会の状態 | 無い | 宿主待ち（待ちの一覧） | Fragment を足した（待ちの一覧） |
|---|---|---|---|
| `request(id)` | (1) API 32 以下か、Application の Context で許可済みなら `Granted` で完了。(2) 初期化されていなければ `Failed(NOT_INITIALIZED)`。(3) 会を作って「宿主待ち」にし、待ちに `id` を足し、`UiHost.acquire(会)` | (1)(2) と同じ判定の後、待ちに足す | (1)(2) と同じ判定の後、待ちに足す（待ちが 0 でも合流する） |
| `cancel(id)` | 何もしない（`tryComplete` が偽） | 待ちから外して `Canceled(REQUESTED)`。待ちが 0 になったら会を消す（`isActive` が偽になるので、宿主が来ても渡さない） | 待ちから外して `Canceled(REQUESTED)`。会は続ける（OS のダイアログは消せない） |
| `onReady(activity)` | - | `PermissionRequestFragment`（引数に会の ID、タグ `ntk.permission.<会の ID>`）を `commitNow` で足し、「Fragment を足した」へ。投げたら、状態が保存済みなら `NOT_FOREGROUND`、それ以外は `HOST_START_FAILED` で下の `onUnavailable` と同じに扱う | - |
| `onUnavailable(reason)` | - | 待ちを外し、会を消し、各待ちを `Failed(reason)` | - |
| 結果（`true` / `false`） | - | - | 待ちを外し、会を消し、Fragment を外し、各待ちを `Granted` / `Denied` |
| Fragment の `onDestroy`（設定の変化中でない） | - | - | 待ちを外し、会を消し、各待ちを `Canceled(HOST_DESTROYED)` |
| Fragment の `onCreate` で、引数の会の ID が今の会でない（プロセスの死の後に戻された） | 自分を外す（`launch` しない） | 同左 | 同左 |

- Fragment は `onCreate` で `registerForActivityResult(RequestPermission())`、`onStart` で 1 回だけ `launch`（起動したかを `savedInstanceState` に保つ）。回転では Fragment が作り直され、Activity Result の登録簿が結果を新しい Fragment に渡す
- 個々の待ちの完了はすべて `tryComplete` を通す。待ちの一覧は先に外してから 1 人ずつ呼び、各呼び出しの例外は捕まえて次へ進む
- 既存の `NotificationPermissionHelper` は今の形と動作のまま残す（3.3）

**設定の画面**: `AndroidNotificationManager.openSettings(target, from: Context? = null)` は `AndroidNotificationSettingsGateway(from ?: Application の Context)`（port の実装。`from` が Activity ならそれから開き、無ければ Application の Context と `NEW_TASK`）を作り、`OpenNotificationSettingsUseCase` を呼ぶ。今のブリッジ（N6）と同じく、開けなければアプリの詳細の画面で `OPENED_FALLBACK`、それも開けなければ `FAILED`。前面かどうかは見ない（C ABI の受け口が C-4 のとおり判定し、前面の Activity を渡す）。`canScheduleExactAlarms()` も同じ形。

### 8.8 Dialog（KA-10、K-3）

宣言は付録 A。

- 否定のボタンの値は `DialogValue.None`、肯定のボタンは種類ごとの値。`DialogValue.Text` と `Login` の `toString()` は値を伏せる（新しい型なので既存の動作に関係しない）
- `ShowDialogUseCase` は入力を検査して投げる（選択肢が空、`checked` の数が違う、`checkedIndex` が範囲の外）。検査の後、ID を `RequestIds` から取り、port の `show(id, request, onResult)` を呼んで ID を返す。port の実装（`FragmentDialogPresenter`）は main に積み、門に ID を入れて `UiHost.acquire` する（8.3）
- `AndroidDialogManager.show(request, onResult): Long` は callback 版（`DialogResult` の 4 つのどれかを 1 回）。`suspend fun AndroidDialogManager.show(request): DialogResult.Answer` はネイティブ版で、答え（`Button` か `Dismissed`）を返し、取り消しと失敗は `DialogDomainError`（`Canceled(reason)`、`Unavailable(error)`）を投げる。コルーチンの取り消しでは `cancel(id)` を呼び、`CancellationException` を投げる
- 要求の ID は、`AndroidDialogFragment` の **internal の factory**（`AndroidDialogFragment.newRequestInstance(requestId, request)`）で引数に入れる。公開の `newInstance` は今のまま

`AndroidDialogFragment` の変更（**`ARG_REQUEST_ID` があるときだけ動く**。無ければ今の listener の動作のまま。K-9）:

| 出来事 | `ARG_REQUEST_ID` があるとき |
|---|---|
| ボタン | `Button(...)` で完了 |
| `onCancel`（戻る、外側のタップ） | `Dismissed` で完了 |
| `onCreate` で、ID が門に無い | `dismissAllowingStateLoss()` |
| `onDestroy` で、Activity が設定の変化中 | 何もしない（作り直された Fragment が同じ ID で続ける。回転で結果を失わない） |
| `onDestroy` で、それ以外 | `Canceled(HOST_DESTROYED)` で完了（完了済みなら何もしない）。宿主なら `finishIfIdle()` を積む |
| 選択中の値 | `onSaveInstanceState` に保ち、作り直しで戻す |

- ファイルの場所は変えない（`com.jonghyunkim.nativetoolkit.dialog.AndroidDialogFragment`。K-9。ブリッジの import も変わらない）。層の新しいクラスは `dialog/{domain,application,presentation}/` に置く
- 入力欄のログは 8.11 のとおり直す（`ARG_REQUEST_ID` に関係なく。ログだけの変更）

### 8.9 Share（KA-12、K-4、AC-22）

**印**: `token: Long`（プロセスの中の連番。1 から）。PendingIntent の data には `ProcessNonce` と印の両方を入れるので、プロセスが作り直されても前のプロセスの URI と重ならない。

**`ShareCallbackCoordinator`**（状態はロックで守る。**ロックの中では印の照合と待ちの取り出し・入れ替えだけを行い、利用者の関数とイベントはロックの外で呼ぶ**）:

| 操作 | 動き |
|---|---|
| `register(mode)`（`mode` は「既存の口の `onSelected` / `onFinished`」か「イベント」） | ロックの中で新しい印を作り、今の待ちをこの要求に入れ替える（**前の待ちは消える。今と同じ。K-4**。前の待ちの `onFinished` は呼ばない。今と同じ）。data `ntk-share-result://<パッケージ>/<ProcessNonce>/<印>`（action `com.jonghyunkim.nativetoolkit.share.action.RESULT`、`setPackage`、request code 0、`FLAG_UPDATE_CURRENT` と `FLAG_MUTABLE`）の PendingIntent と印を返す |
| Chooser の起動の失敗 | `cancel(token)`（今の待ちがこの要求のときだけ消す。今と同じ）→ 投げる |
| 受けた broadcast（印が違う） | 捨てる |
| 受けた broadcast（印が今の待ち、結果が選択 `Selected`） | ロックの中で待ちを取り出して消す。ロックの外で、既存の口は `onSelected(pkg)` を呼び、`finally` で `onFinished()` を 1 回（今と同じ）。イベントの口は `ShareEvents.selections.emit(ShareSelection(token, pkg))` |
| 受けた broadcast（印が今の待ち、結果が選択でない `Ignored`。API 35 以降の Copy・Edit など） | ロックの中で待ちを取り出して消す。ロックの外で、既存の口は `onFinished()` を 1 回（`onSelected` は呼ばない。今と同じ）。イベントの口は何も出さない |
| `cancel(token)` | 印が今の待ちなら消す。違えば何もしない |
| `cancel()` | 今の待ちを消す（今と同じ） |

- 既存の口の `onSelected` / `onFinished` が投げた例外は、今と同じく捕まえない（6.2）
- 動的 Receiver はプロセスで 1 つを登録したままにする（action と data の scheme・authority の `IntentFilter`、`RECEIVER_NOT_EXPORTED`）。受けたら main の上で上の表を行う
- `NOT_FOREGROUND` で開かなかった Share は、C ABI の受け口が Kotlin を呼ぶ前に判定する（C-4）ので、`register` は呼ばれず前の待ちは残る（AC-22）

**口**:

| 口 | 動き |
|---|---|
| 既存 `ShareWithCallbackUseCase` / `ShareUseCases.shareWithCallback` | **形と動作は今のまま**（戻り値 `Unit`、`onResult` / `onFinished`）。中は要求ごとの PendingIntent に載る。変わるのは README の 1b の行の修正（古い選択が届かない）だけ |
| 既存 `CancelPendingShareCallbackUseCase` | 今のまま（今の待ちを消す） |
| 新 `AndroidShareManager.shareForSelection`（`ShareForSelectionUseCase`） | 上の仕組みで開き、印を返す（同期。開けなければ投げる。今の `shareWithCallback` と同じ検査と例外）。選択は `ShareEvents.selections` に印つきで届く。Chooser を閉じたときと選択でない結果のときは何も来ない |
| 新 `AndroidShareManager.cancelShareSelection`（`CancelShareSelectionUseCase`） | 印が今の待ちなら消す |

- 新しい口は「開く操作（同期）」と「選択のイベント」で、待つ操作が無いので `suspend` 版は要らない（C ABI の設計書 AC-22 と同じ形。4.1）
- `ShareRepository`（公開の port）に足す 3 つの関数は、既定の実装（`UnsupportedOperationException` を投げる）を持つ interface の関数にする（既存の利用者の実装を壊さない）。`ShareRepositoryImpl` が実装する

**Chooser Action**:

- `AndroidShareManager.shareTextWithActions(content, actions, preview)`（`ShareTextWithActionsUseCase`）
- 各アクションの PendingIntent: action `com.jonghyunkim.nativetoolkit.share.action.CHOOSER_ACTION`、data `ntk-share-action://<パッケージ>/<ProcessNonce>/<世代>/<id>`、`setPackage`、request code 0、`FLAG_UPDATE_CURRENT` と `FLAG_IMMUTABLE`。アイコンのバイト列（`BitmapFactory` で読める形式）を `Bitmap` にするのは data の層
- **順序**: 入力の検査（`id` が空・重複、アイコンが画像として読めない → `ShareDomainError.InvalidChooserAction(id)` を投げる。このときは世代を上げないので、前の Share のアクションは生きたまま）→ 世代を上げる（アクションが空でも上げる。今のブリッジが、空のリストでも起動の前に前の Receiver を外すのと同じ）→ Chooser を起動する
- `ShareChooserActionReceiver`（動的、プロセスで 1 つ、登録したまま）は、nonce と世代が今のものなら main の上で `ShareEvents.chooserActions.emit(id)`
- API 33 以下ではアクションを付けない（今と同じ）
- JSON の文字列を取る今の形はブリッジが使うので段階 3 まで残す（8.13）。こちらの世代はブリッジの Registry が持つ（今と同じ）

### 8.10 Clipboard（KA-13）

- `ClipboardErrorCode.of` はブリッジの表（5.1 の C2）と同じ対応。投げる例外の型は変えない
- `ClipboardObserver` は 1 つの `ClipboardChangeMonitor` を持ち、変更を `ClipboardEvents.changes` に出す。開始・停止は冪等。既存の `ClipboardChangeMonitor` は今のまま

### 8.11 ログの規則の例外（KA-14、README 8.6）

`agent-rules/coding-rules/android.md` の「ログ（Log.d）」に次を足す（この設計書の決定と同じ PR）。

| 項目 | 規則 |
|---|---|
| 伏せる値 | Clipboard の本文（テキスト、HTML、URI）、Dialog の入力（テキスト、ユーザー名、パスワード）、Share の本文（`text`、`subject`）、通知の `data` の値（キーは出す）、`Intent` の extra の値 |
| 書き方 | `LogRedaction.redact(value)` で `<redacted, length=N>`（`null` は `null`）。**既存の公開の型の `toString()` は変えず、ログの箇所で長さや種類だけを出す**。新しい型は `toString()` で伏せてよい |
| 出してよい値 | 長さ、件数、ID、種類、真偽値、通知のタイトルとメッセージ |
| C / C++ | `__android_log_print`、タグ `ntk`。同じ値を伏せる（C ABI の設計書 5.12） |
| 先頭の `Log.d` | 残す。伏せる値を持つ引数は `redact` を通すか、長さだけを出す |

**1b で直す既存のログ**（ログだけの変更で、動作は変えない）:

| 場所 | 今 | 直し方 |
|---|---|---|
| `AndroidDialogFragment` の `afterTextChanged`（2 か所） | 入力の全文 | 長さだけ |
| Share の `ShareRepositoryImpl`・UseCase の先頭の `Log.d` が `content: $content` で補間する所 | 本文 | `ShareContent` の拡張関数 `logSafeDescription()`（Clipboard と同じ形。`textLength`、`mimeType`、`hasSubject` など）を出す |

Clipboard の既存のログはすでに伏せている（`logSafeDescription`）。通知の command の `toString` はタイトル・メッセージと `Intent`（`Intent.toString` は extra の値を出さない）だけなので変えない。

### 8.12 manifest、権限、`consumer-rules.pro`（KA-15、README 8.6）

| 項目 | 決定 |
|---|---|
| 足すコンポーネント | `NotificationEventReceiver`、`NotificationLaunchActivity`、`NtkHostActivity`（どれも `exported=false`）、`InitializationProvider` の `meta-data`（`LibraryInitializer`、`tools:node="merge"`） |
| 宛先 | 3 つの受け手（`NotificationEventReceiver`、`NotificationLaunchActivity`、`ScheduledNotificationReceiver`）は明示の component で届ける。`<intent-filter>` は付けない。クラス名は 8.5 の変えない識別子 |
| 権限 | 7 つの宣言は変えない。下の表をマニュアルに書く（段階 4） |

| 権限 | 外したときの動作 | 外し方 | 確かめ方 |
|---|---|---|---|
| `POST_NOTIFICATIONS` | API 33 以降で通知が出ない。`hasPermission` が偽、権限の要求は OS がすぐ拒否を返す（`Denied`） | `tools:node="remove"` | IT-19（実行） |
| `RECEIVE_BOOT_COMPLETED` | 再起動の後に予約が戻らない | 同上 | IT-19 |
| `SCHEDULE_EXACT_ALARM` | 正確でない Alarm になる（`canScheduleExactAlarms` が偽。今のコードが分岐する） | 同上 | IT-19 |
| `USE_FULL_SCREEN_INTENT` | 全画面の Intent が heads-up になる（OS の動作） | 同上 | IT-19 |
| `FOREGROUND_SERVICE` | Progress と CallStyle の前景サービスが `startForeground` で失敗しうる | **外すなら 2 つの `<service>` も外し、その API を呼ばない** | merge した manifest の静的な検査（IT-19 の版で、外した権限に対応する `<service>` が残っていないこと）とマニュアル |
| `FOREGROUND_SERVICE_DATA_SYNC` | Progress の前景サービスが同様 | 外すなら `ProgressForegroundService` の `<service>` も外す | 同上 |
| `FOREGROUND_SERVICE_SPECIAL_USE` | CallStyle の前景サービスが同様 | 外すなら `CallStyleForegroundService` の `<service>` も外す | 同上 |

- IT-19 の版は、試験専用のアプリ（0.8）の flavor の manifest で作る
- `consumer-rules.pro`: `-keep class com.jonghyunkim.nativetoolkit.common.runtime.LibraryInitializer { <init>(); }`。manifest のコンポーネントは AAPT の規則で守られる。ライブラリが Alarm と保存に入れるクラス名は manifest の受け手の名前だけ（AAPT の規則で R8 が名前を変えない）なので、それ以外は要らない

### 8.13 ブリッジだけが使う公開の口（KA-16）

| 口 | 1b | 段階 3 |
|---|---|---|
| `com.jonghyunkim.nativetoolkit.notification.NotificationShownSupport` | **今の名前と場所のまま**、`@Deprecated`。`ScheduledNotificationReceiver` が、新しい `NotificationEvents.shown` と、この枠の両方に出す | 消す |
| `ShareTextUseCase` と `ShareUseCases.shareText` の `chooserActionsJson: String` の形 | `@Deprecated`。今の動作のまま | 消す |

段階 3 と 2.0.0 は同じリリースなので（D-2）、消すものは 2.0.0 に出ない。`AndroidDialogFragment` と `NotificationPermissionHelper` は公開の API として残す。

### 8.14 notification の依存の向き（README 4 章）

| 今 | 直し方 |
|---|---|
| `NotificationUseCases.isScheduled` が data の `NotificationSchedulerSupport` を呼ぶ | **今のまま残す**（利用者の決定。2026-10-04）。この口は `Context` を受け取る既存の公開の口で、repository を介さずにライブラリの保存を読むことが今の動作である。port や登録の仕組みに替えると、Startup を無効にした場面などで結果が変わる（K-9）。中は新しい保存（`JsonNotificationScheduleStore`）を直接読む。README 4 章の依存の向きの修正から、この 1 つの既存の口だけを外す（README の同じ行に書いた）。新しく足す口は層の規則どおり |
| 前景サービス 2 つが `NotificationRepositoryImpl` を直接作る | `NotificationUseCasesFactory`（data）が作る UseCase を使う。data のファクトリーは組み立ての根（composition root）として presentation から使ってよい（Clipboard・Share の `*UseCases(context)` と同じ形。`android.md` に書く） |
| `ProgressForegroundServiceIntents` が data の payload の変換（`toPayload` / `toCommand`）を直接使う | `NotificationUseCasesFactory` が渡す変換（data の実装）を使う。port は作らない（プロセスの中の Intent の受け渡しで、application の規則に関わらないため） |
| `NotificationShownSupport` が層の外 | 新しいイベントは `notification/presentation/event/NotificationEvents.kt` に置く。`NotificationShownSupport` は 8.13 のとおり今の場所に残す |

### 8.15 C ABI の設計書 第 2 部への申し送り

- **呼ぶ先**（KA-18）: C ABI の受け口は、機能ごとに `AndroidClipboardManager`・`AndroidDialogManager`・`AndroidNotificationManager`・`AndroidShareManager` を呼ぶ（`getInstance` で得る）。第 2 部の対応表は、この Manager の口と C の関数を並べる
- **前面の判定の受け持ち**（KA-17）: C ABI の受け口は C-4 のとおり、Dialog・権限の要求・Share の Chooser・設定の画面の前に前面を判定し、前面でなければ Kotlin を呼ばずに `NOT_FOREGROUND` で完了する。Dialog と権限は、受け口の判定の後に前面が変わった場合に `UiHost` が同じ `NOT_FOREGROUND` で完了するので、受け口はそれをそのまま写す
- C ABI は Dialog と権限で callback 版を使う（`suspend` 版は使わない）
- エラーの写し（第 2 部 11.1。第 2 部で改めた）: `UiUnavailableReason.NOT_INITIALIZED` → `NOT_INITIALIZED`、`NOT_FOREGROUND` → `NOT_FOREGROUND`、`HOST_START_FAILED` → `HOST_START_FAILED`、`DialogError.SHOW_FAILED` → `SHOW_FAILED`、`CancelReason` は `CANCELED` と `CANCELED_BY_SYSTEM` に分ける
- Share（第 2 部 AP-17。第 2 部で改めた）: `shareForSelection` が返す印は main で前面を確かめた後に初めてできるので、C ABI の要求の ID は C が受け付けの時点で付け、帳簿で印と対にする。選択のイベントは `ShareEvents.selections` の受け手として足す
- 既存の口の「1b で直さない」不具合（3.3）を、C ABI でどう扱うか（写すか、受け口で避けるか）を対応表に書く
- Progress の値の補正と単一選択の `-1` は C ABI の側で、style の代わりの値と Dialog の `Dismissed` の今の値への写しは Unity の包みで持つ（7 章。第 2 部 AP-8、AP-9、AP-13、OP-15。第 2 部で改めた）

## 9. API 設計の一覧と同期・非同期レイヤー対応表

足す口だけを挙げる。Bridge の列は C ABI の受け口（第 2 部）。Manager の列は 6.3 の Manager の役。

| 操作 | System API と実行方式 | Repository / 実装 | UseCase | Manager callback | Manager native | Bridge（C ABI） | thread | キャンセル・資源の持ち主 | 方式を変える理由 |
|---|---|---|---|---|---|---|---|---|---|
| 初期化 | `registerActivityLifecycleCallbacks`（同期） | - | - | - | `LibraryRuntime.ensureInitialized`（同期、待たない） | `ntk_android_init` などが呼ぶ | どれでも | - | - |
| Dialog を出す | `DialogFragment.showNow`（main） | `FragmentDialogPresenter` | `ShowDialogUseCase` | `AndroidDialogManager.show(request, onResult)`（main で 1 回） | `suspend AndroidDialogManager.show(request): DialogResult.Answer`（失敗は例外） | 完了つきの操作（callback 版） | 呼ぶのはどれでも、完了は main | `cancel(id)`、門 | 利用者の操作を待つので非同期 |
| Dialog の取り消し | `dismissAllowingStateLoss`（main） | 同上 | `CancelDialogUseCase` | - | `AndroidDialogManager.cancel`（同期、積む） | 取り消し | どれでも | - | 即時の control |
| 権限の要求 | `RequestPermission`（main、非同期） | `FragmentPermissionRequester` | `RequestNotificationPermissionUseCase` | `AndroidNotificationManager.requestPermission(onResult)` | `suspend ...requestPermission(): Boolean`（失敗は例外） | 完了つきの操作（callback 版） | 同上 | `cancel(id)`、会 | 同上 |
| 権限の要求の取り消し | - | 同上 | `CancelNotificationPermissionRequestUseCase` | - | `AndroidNotificationManager.cancelPermissionRequest`（同期、積む） | 取り消し | どれでも | - | 即時の control |
| 正確なアラームの可否 | `canScheduleExactAlarms`（同期） | `AndroidNotificationSettingsGateway` | `CanScheduleExactAlarmsUseCase` | - | `AndroidNotificationManager.canScheduleExactAlarms` | 同期の問い合わせ | どれでも | - | - |
| 設定の画面 | `startActivity`（同期） | 同上 | `OpenNotificationSettingsUseCase` | - | `AndroidNotificationManager.openSettings` | 前面の Activity を渡す | どれでも | - | - |
| 予約の保存（既存の口の中） | `AtomicFile`（同期） | `JsonNotificationScheduleStore` | 今の UseCase | - | 今の UseCase（`Result`） | 同期 | どれでも | `ScheduleLock` | `apply()` から同期の書き込みへ（README 8.6） |
| 通知のイベント | broadcast / Activity（main） | Receiver、見えない Activity | - | `AndroidNotificationManager.interactions` の受け手 | - | イベントの登録 | main | `Registration.remove` | - |
| shown | broadcast（main） | `ScheduledNotificationReceiver` | - | `AndroidNotificationManager.shown` の受け手 | - | イベントの登録 | main | 同上 | - |
| 選択をイベントで受ける Share | `createChooser` + `startActivity`（同期） | `ShareRepositoryImpl`、`ShareCallbackCoordinator` | `ShareForSelectionUseCase` | `AndroidShareManager.selections` の受け手 | `AndroidShareManager.shareForSelection`（同期、印を返す） | 開く操作の完了と選択のイベント | 呼ぶのはどれでも、選択は main | `cancelShareSelection(token)` | - |
| Chooser Action つきの Share | 同上 | 同上、`ShareChooserActionReceiver` | `ShareTextWithActionsUseCase` | `AndroidShareManager.chooserActions` の受け手 | `AndroidShareManager.shareTextWithActions` | 開く操作とイベントの登録 | 同上 | `Registration.remove` | - |
| Clipboard の監視 | `OnPrimaryClipChangedListener`（main） | `ClipboardChangeMonitor` | - | `AndroidClipboardManager.changes` の受け手 | `AndroidClipboardManager.startObserving` / `stopObserving`（同期） | 監視の開始・停止とイベント | main | `stop`、`Registration.remove` | - |
| Clipboard のエラーの分類 | - | - | - | - | `AndroidClipboardManager.errorCodeOf`（同期） | エラーの値 | どれでも | - | - |

## 10. ドメインエラーの一覧とエラーの対応表

| 型 | 値 | 出る場面 |
|---|---|---|
| `LibraryRuntime.InitState` | `DONE`、`IN_PROGRESS`、`ERROR` | 8.1 |
| `UiUnavailableReason` | `NOT_INITIALIZED`、`NOT_FOREGROUND`、`HOST_START_FAILED` | 初期化されていない、前面が無い・宿主が 5 秒で始まらない・状態が保存済み、宿主の `startActivity` か権限の Fragment の `commitNow` が投げた |
| `DialogError` | `NOT_INITIALIZED`、`NOT_FOREGROUND`、`HOST_START_FAILED`、`SHOW_FAILED`（`UiUnavailableReason` から同じ名前の値に写す `from`） | `showNow` の `IllegalStateException` 以外の例外が `SHOW_FAILED` |
| `CancelReason` | `REQUESTED`、`HOST_DESTROYED` | 取り消し、Activity・Fragment が設定の変化でなく壊れた |
| `DialogResult` | `Button`、`Dismissed`（この 2 つが `Answer`）、`Canceled`、`Failed` | 8.8 |
| `DialogDomainError`（`suspend` 版が投げる） | `Canceled(reason)`、`Unavailable(error)` | 8.8 |
| `PermissionRequestResult` | `Granted`、`Denied`、`Canceled`、`Failed` | 8.7 |
| `PermissionRequestDomainError`（`suspend` 版が投げる） | `Canceled(reason)`、`Unavailable(reason)` | 8.7 |
| `NotificationSettingsOpenResult` | `OPENED`、`OPENED_FALLBACK`、`FAILED` | 8.7 |
| `ClipboardErrorCode` | 7 つ | 8.10 |
| `ShareDomainError` | 今の 9 つ + `InvalidChooserAction(id)` | 8.9 |
| 予約の `Result.failure` | 今のもの + `IOException`（保存の書き込みの失敗） | 8.6 |

C ABI のエラーの値への写しは 8.15 と第 2 部。

## 11. C ABI の設計書 9.1 の条件との照合

| # | 条件 | この設計書 |
|---|---|---|
| K-1 | イベントの元を、main に積める形で受け口へ渡せる | 8.4 |
| K-2 | 配送の間、利用者のコールバックから届きうるロックを持たない | 6.2、8.1、8.4、8.6（`ScheduleLock` の中でコールバックを呼ばない）、8.9（ロックの外で呼ぶ） |
| K-3 | 完了と権限の要求が、ライブラリの側で終わる場面も含めてちょうど 1 回。同時の要求 | 8.3（門、宿主の記録、Dialog の状態の表）、8.7（会の表）、8.8。Clipboard・Notification・Share の操作の結果は同期の口なので、受け口が 1 回完了させる |
| K-4 | Share の要求ごとの PendingIntent と印での取り消し。新しい Share は前の待ちを消す（今と同じ） | 8.9 |
| K-5 | 前面の定義と手動の初期化の初期値 | 8.2 |
| K-6 | 権限の要求の判定と、登録の時期の制約 | 8.7 |
| K-7 | 保ったイベントを挿入のメッセージの中で渡し、誰に渡すかを決める | 8.4 |
| K-8 | `ensureInitialized` の 3 値と失敗の戻し、C を知らない | 8.1 |
| K-9 | 既存の API の動作を変えない | 3.3（変わるのは README の 1b の行の 2 つと、README 8.6・D-11 から直接出る 3.3 の表の項目だけ）、8.6 の対応表、8.8、8.9、8.11。IT-23 で前後を比べる |

## 12. テストの設計

`android_library` の `src/test` は `isReturnDefaultValues = true` で Robolectric と `org.json` の実装を持たないので、**フレームワークと JSON に触れるものは `src/androidTest` に置く**。`src/test` には純粋な Kotlin の部分（Android の呼び出しと main の判定を差し替えられる形にしたもの）だけを置く。

### 12.1 単体テスト（`src/test`）

| ID | 対象 | 中身 |
|---|---|---|
| UT-01 | `LibraryRuntime` の状態と一覧 | 未着手 → 済み、同時の呼び出し、途中の例外で未着手に戻る、やり直し、「済んだら呼ぶ」を済ませることと競わせて必ず 1 回 |
| UT-02 | `EventHub` | 保つ（32 を超えたら古いものから）、1 人目にだけ足す呼び出しの中で渡す、受け手の中で自分を外す（残りが次の受け手に続く、無ければ保ちに戻る）、受け手の中で足す・外す、例外を捕まえて次へ、`remove` 2 回 |
| UT-03 | `UiRequestGate`、宿主の記録、Dialog の状態の表 | 表の全セル。2 つの出来事の両順（取り消しと結果、見張りと宿主、宿主の破棄と結果、起動待ちの取り消しと宿主の到着） |
| UT-04 | `ClipboardErrorCode.of` | 7 つ |
| UT-05 | 1.x の鍵の解析と破棄の状態 | 鍵の文字列の解析（`untagged::1`、`a::b::2` は最後の `::`、整数でない後ろ）、要素の取り消しの失敗で印を書かずに未着手へ、印だけが書けなかったときのやり直し（JSON の取り出しは IT-18） |
| UT-06 | 権限の要求の会の表 | 表の全セル。API 32 以下（SDK の判定を差し替え）、許可済み、合流、宿主待ちで待ちが 0 になったときに宿主へ渡さない、Fragment を足した後の取り消しの後の合流、`commitNow` の失敗 |
| UT-07 | `LogRedaction`、新しい型の `toString`、`ShareContent.logSafeDescription()` | 番兵の値が出ない |
| UT-08 | `ShareCallbackCoordinator` | 印の照合、古い印と古い nonce を捨てる、`Selected` と `Ignored` で既存の口の `onFinished` が 1 回、受けた後に利用者の関数の中から `cancel` と次の `register` を呼んでも止まらない（ロックの外で呼ぶ）、`onSelected` が投げても `onFinished` が 1 回で、例外は今と同じく伝わる |

### 12.2 instrumented テスト（`android_library` の `src/androidTest`）と UI テスト（サンプル）

| ID | 対象 | 中身 |
|---|---|---|
| IT-01 | 初期化 | Startup の既定の経路。Startup を無効にした構成で `ensureInitialized(activity)` の後に前面が取れる |
| IT-02 | 前面 | 前面、ホームへ戻した後、別の Activity を重ねた後の `current()`、`seed` |
| IT-03 | Dialog（`FragmentActivity`） | 6 種の表示と結果（callback 版と `suspend` 版。`suspend` 版の取り消しと失敗の例外）、回転の後に結果が届く、`cancel(id)`、プロセスの死の後に戻った Fragment が閉じる（`am kill`） |
| IT-04 | Dialog（`FragmentActivity` でない前面） | 透明な宿主に出る、完了で閉じる、取り消しで閉じる、表示の失敗で閉じる、2 つ同時（起動待ちの間の 2 つ目が同じ宿主に積まれる）、2 つ目の直後に 1 つ目を完了しても 2 つ目が残る |
| IT-05 | Dialog（前面でない） | 後ろで呼ぶと `NOT_FOREGROUND`。誤った `seed` の後に見張りで `NOT_FOREGROUND`。起動待ちの間の取り消しで、宿主が来ても出さずに閉じる |
| IT-06 | Dialog（壊れた） | 宿主を外から `finish` すると `Canceled(HOST_DESTROYED)` が 1 回 |
| IT-07 | 権限の要求 | 許可済みで `Granted`、未許可でダイアログを UiAutomator で許可・拒否、2 つ同時で同じ結果、回転、後ろで `NOT_FOREGROUND`、プロセスの死の後に戻った Fragment が `launch` しない、`suspend` 版の例外 |
| IT-08 | 設定の画面 | Activity と Application の Context、代わりの画面 |
| IT-09 | 通知のイベント | タップ・アクション・dismiss・カスタムビューのクリックと `data` |
| IT-10 | 保つ | 受け手の無い間のタップを保ち、1 人目にだけ渡る。コールドスタート |
| IT-11 | トランポリンと全画面 | `launchApp=true` でアプリが前に出る。コールドスタート・後ろ・前面の 3 通り。比べとして、Receiver から起動する形は後ろのとき開かない。全画面の起動の Intent に data が無い |
| IT-12 | 予約の流れ | 8.6 の対応表の各行が今と同じ結果（保存する・しないの発火、`isScheduled`、`cancelAllScheduled`、過ぎた時刻）。発火の後の削除と予約し直しの重なりで新しい項目が残る。2 つの予約の交差、置き直しと予約の交差（壁で順序を作る）。`MY_PACKAGE_REPLACED` の置き直し（`lossy` でない項目は今と同じく置き直す、未来の `lossy` の項目は Alarm が生きていれば置き直さない、期限の過ぎた `lossy` の項目は出して消す）。入れ直し（バックアップから保存が戻る）の後の置き直し。置き直した Alarm が発火した後に保存から消える（世代）。shown の受け手の中で `isScheduled` が偽（発火の順序）。注入できる `send` に壁を置き、壁の間に同じ鍵を予約し直し、放した後も新しい世代の項目が残り、shown が削除の判定の後に来ること（ロックの外の `send`）。tag `untagged` と tag 無しが今と同じく同じ予約になる。OS が Alarm を消した後の更新（正確なアラームの権限を取り消す）。更新の途中に期限が来た Alarm が更新の後に配られる（3.4。成り立たなければ、`lossy` でない項目は今と同じく置き直しで出るので影響は `lossy` の項目だけと結果に書く） |
| IT-13 | 予約の書き込み | 予約の直後にプロセスを止めても、再起動の後に戻る。保存の失敗（注入）で `IOException` とその後の状態が 8.6 のとおり。Alarm の失敗（注入）で今と同じく `Result.failure`、保存が変わらない |
| IT-14 | 再起動の後の `toUri` | 8.6 の表の全行。`lossy` の予約が、発火（再起動の前）では全部、再起動の後は表のとおりで出る |
| IT-15 | Share の待ち | 2 回続けて開き、前の Chooser で選んでも届かない。印の取り消し、前の印の取り消しは新しい待ちを消さない。プロセスを止めて開き直したとき前の選択が届かない。既存の口の `onFinished` の回数が今と同じ（選択、Copy） |
| IT-16 | Chooser Action | 型のあるアクションが届く。前の Share のアクションは届かない。アクションの無い Share の後に前のアクションが届かない。検査で投げたときは前のアクションが生きている |
| IT-17 | Clipboard の監視 | 開始・停止と複数の受け手 |
| IT-18 | 1.x の破棄（自動） | テストが 1.x の `SharedPreferences` と 1.x の Intent の Alarm（0e の値）を作り、`MY_PACKAGE_REPLACED` の経路と初めて使う経路で破棄し、`dumpsys alarm` に残らないこと、保存が消えること、印、やり直し（途中の失敗の注入） |
| IT-19 | 権限を外した版 | 試験専用のアプリ（0.8）の、8.12 の 4 つを外した flavor で結果が表のとおり。前景サービスの 3 つは merge した manifest の静的な検査 |
| IT-20 | PendingIntent の同一性 | 実物の PendingIntent の同一性（tag なし・空の tag・符号化の要る文字、同じ鍵の extra の更新、違う鍵の分離、`setIdentifier`）、Share の `IntentFilter` の照合の正と負 |
| IT-21 | ログ | 番兵の値（パスワード、Clipboard の本文、Share の本文、通知の `data`）で各操作を行い、アプリの logcat に番兵が出ないこと |
| IT-22 | R8 | 試験専用のアプリ（0.8）の release（R8 有効）で、Startup・宿主・見えない Activity・Receiver・予約の発火が動く |
| IT-23 | 既存の口の前後 | `AndroidDialogFragment` の listener の形、`NotificationPermissionHelper`、JSON の `shareText`、`shareWithCallback`、`isScheduled` / `cancelAllScheduled` が 0c の基準と同じ。利用者が自分で実装した `NotificationCommandRepository` を渡した `NotificationUseCases` の `isScheduled(context, ...)` が今と同じくライブラリの保存を引く。Startup を無効にし、初期化もファクトリーも受け手も通さずに、保存だけがある状態で最初に `isScheduled` を呼んで真になる |
| IT-24 | 変えない識別子と Alarm の extra | 8.5 の変えない識別子の値（受け手のクラス名を含む）。予約した Alarm の PendingIntent の component が変えない識別子のクラス名で、extra が 8.6 の 4 つだけで、ライブラリのクラスの Parcelable が無いこと |
| IT-25 | codec | command の全部の欄（内容の約 30 欄、style ごと、アクション、CallStyle の 3 つの Intent、カスタムビューの動作、`Bitmap`、`null` と既定の値）を Alarm の extra の形と保存の形の両方で符号化して戻し、等しいこと（`Intent` は `filterEquals` と extra のキーと値。保存の形は `toUri` の表のとおり）。版の規則（版 1 に欄を足した JSON を読める、知らない欄の無視、無い欄の既定の値、知らない版のファイルを名前を変えて残す） |
| IT-26 | 更新をまたぐ Alarm | 試験専用のアプリ（0.8）の 2 つの版の APK（R8 有効。後の版は obfuscation の辞書を変える）で、前の版で `Intent` と `Bitmap` を持つ予約を置き、`adb install -r` で後の版にし、発火した通知の内容が同じこと |
| IT-27 | Manager | 4 つの Manager の各口が、委ねる先（UseCase、イベントの持ち主、既存の口）と同じ結果・例外・スレッドになること。`AndroidShareManager.shareText(content, preview)` が `ShareTextUseCase(content, "[]", preview)` と同じ結果になること。`getInstance` がプロセスで 1 つを返し、Activity を持ち続けないこと（`LeakCanary` の代わりに、Activity を閉じた後の弱い参照が消えることで確かめる） |

- 人の確認 CU-03: 1.12.0 のタグから組んだサンプル（同じ applicationId と署名）で予約し、2.0.0 を `adb install -r` で入れ、保存した予約が取り消され、保存しない予約が発火しても何も出ず、新しく予約できる（README 9 章の DoD）
- `test_android.sh` の全 317 件（0d の基準）が 1b の後も同じ結果になること。サンプルの Receiver を置き換えたテストと `HostPhaseTest` の補いを消したテストは、理由を結果に書く
- 移すロジックに当たるブリッジのテスト（エラーの分類、Chooser Action の登録、リソースの解決など）を `android_library` のテストとして書き直し、対応を 1b の結果に書く
- `test_android.sh` に IT-18、IT-19、IT-22、IT-26 の段を足す

## 13. 実装タスク分解

| ID | 内容 | 見積 | 依存 |
|---|---|---|---|
| T-01 | `LogRedaction` と既存のログの 2 か所 | 0.5日 | - |
| T-02 | `LibraryRuntime`、`LibraryInitializer`、`MainPoster`、`LibraryExecutors`、`RequestIds`、`ProcessNonce`、Startup の依存 | 1.0日 | - |
| T-03 | `ForegroundActivityTracker` | 1.0日 | T-02 |
| T-04 | `EventHub` | 0.5日 | T-02 |
| T-05 | `UiHost`、`UiRequestGate`、`NtkHostActivity` | 1.5日 | T-03 |
| T-06 | Dialog の domain と application | 1.0日 | T-02 |
| T-07 | Dialog の presentation（`FragmentDialogPresenter`、`AndroidDialogFragment` の要求の ID） | 1.5日 | T-05、T-06 |
| T-08 | 権限の要求（port、UseCase、`FragmentPermissionRequester`） | 1.5日 | T-05 |
| T-09 | 設定の画面の port・UseCase・gateway | 0.5日 | T-02 |
| T-10 | 通知のイベント | 1.5日 | T-04 |
| T-11 | リソース名の解決 | 0.5日 | - |
| T-12 | 予約の保存（JSON、`AtomicFile`、版の規則、`lossy`・`installId`・`bootCount`） | 1.5日 | T-02 |
| T-13 | Alarm の extra と宛先、`ScheduleLock`、受け手、Boot | 1.5日 | T-12 |
| T-14 | 1.x の破棄 | 1.0日 | T-12 |
| T-15 | 依存の向きの修正と shown のイベント | 1.0日 | T-10、T-12 |
| T-16 | Share の要求ごとの PendingIntent、印、選択のイベント | 1.0日 | T-04 |
| T-17 | 型のある Chooser Action と Receiver | 1.0日 | T-04 |
| T-18 | Clipboard のエラーの分類と監視 | 1.0日 | T-04 |
| T-19 | manifest、`consumer-rules.pro` | 0.5日 | T-02、T-05、T-10 |
| T-20 | サンプル: Receiver の置き換えと新しい画面（design-sample-app で設計する） | 1.5日 | T-24 |
| T-21 | 1.x の破棄・権限を外した版・R8・更新をまたぐ Alarm のテスト、`test_android.sh` | 1.5日 | T-13、T-14、T-19 |
| T-22 | ブリッジのテストの書き直し | 1.0日 | T-10、T-11、T-17、T-18 |
| T-23 | 全体の実行と基準との比べ合わせ、CU-03 | 1.0日 | T-20、T-21、T-22 |
| T-24 | 4 つの Manager（委ねるだけの入口、`getInstance`、テスト用の constructor）と IT-27 | 1.0日 | T-07、T-08、T-09、T-10、T-15、T-16、T-17、T-18 |

合計見積: 約 25.5 日

- `android.md` は、この設計書の決定と同じ PR で直す（タスクに入れない）
- 機能ごとに関係するテストだけを両方の環境で流し、全体の実行は T-23 で行う（README 7 章）

## 14. リスクと緩和策

| ID | リスク | 緩和策 |
|---|---|---|
| RK-01 | 透明な宿主の起動が後ろからの起動として止められ、完了が来ない | 5 秒の見張り（8.3） |
| RK-02 | `seed` で渡された Activity が実は後ろにある | `LifecycleOwner` なら状態を確かめる。違えば見張り |
| RK-03 | 同期の書き込みが呼び出しスレッドを塞ぐ | 再起動をまたぐ予約だけ。KDoc に書く。README 8.6 の確実さを優先する |
| RK-04 | 再起動の後に戻した予約で extra が落ちる | D-11 の範囲。表（8.6）とマニュアル、警告のログ |
| RK-05 | `NotificationLaunchActivity` が `onResume` の前に `finish` しないと落ちる | `onCreate` の中で必ず `finish`。IT-11 |
| RK-06 | 名前でしか引かれないリソースが縮小で消える | マニュアルに `tools:keep` |
| RK-07 | `AndroidDialogFragment` に足す処理が既存の利用者の動作を変える | `ARG_REQUEST_ID` があるときだけ動かす。IT-23 |
| RK-08 | ブリッジと `android_library` に同じロジックが 2 か所ある間に片方だけが直る | ブリッジは直さない。段階 3 で消す |
| RK-09 | Alarm の extra の形や識別子を後で変えると、更新の前の Alarm と出ている通知が壊れる | 版の規則と変えない識別子（8.5、8.6）。IT-24、IT-25、IT-26 |
| RK-10 | main から呼んだ予約の口が、ほかのスレッドの書き込みの間 `ScheduleLock` を待つ | ロックの中は `AlarmManager` とファイルだけで、`send` と利用者のコードはロックの外。書き込みは予約の数だけの小さなファイル。KDoc に「main から呼ぶと待ちうる」と書く |
| RK-11 | 受け手のクラスを後で動かすと、予約と出ている通知が壊れる | クラス名を変えない識別子にし（8.5）、IT-24 で固定する |

## 15. Definition of Done

- [ ] 6.1 のファイルと可視性、付録 A の宣言があり、8 章の動き、9 章のスレッド、取り消しの契約と一致している
- [ ] `PLANNED_SYMBOLS_EXEMPT` の名前を実装と照合した
- [ ] 5.1 のロジックがすべて `android_library` にあるか、7 章で C ABI / 包みの受け持ちと決めている
- [ ] `agent-rules/coding-rules/android.md` に 2 つの書き足し（ログ、Manager の役と UseCase を置かない口の条件）があり、IT-21 が通る
- [ ] 12 章のテストが両方の環境で通り、`test_android.sh` の全件が 0d の基準と同じ（直したテストは理由を記録）。IT-23 で既存の口の動作が変わっていない
- [ ] IT-18 と CU-03 が通る
- [ ] AAR の manifest に 8.12 のコンポーネントがあり、`consumer-rules.pro` が 8.12 のとおりで、IT-22、IT-24、IT-26 が通る
- [ ] C ABI の設計書 9.1 の K-1〜K-9 を 11 章の表で確かめている

## 16. 付録 A: 公開の宣言

**擬似宣言**: 関数の本体を省いた宣言の一覧で、そのままではコンパイルしない（クラスの本体の `fun` に本体を付けると実装になる）。`RG` は `@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)`。KDoc は省く。

```kotlin
// common.runtime
object LibraryRuntime {
    enum class InitState { DONE, IN_PROGRESS, ERROR }
    fun ensureInitialized(context: Context): InitState
    fun isInitialized(): Boolean
    fun addOnInitializedListener(listener: () -> Unit)
}
class LibraryInitializer : androidx.startup.Initializer<Unit> {
    override fun create(context: Context)
    override fun dependencies(): List<Class<out androidx.startup.Initializer<*>>>
}
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP) object MainPoster { fun post(block: () -> Unit): Boolean }
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP) object RequestIds { fun next(): Long }

// common.event
class EventHub<T> internal constructor(/* retention */) {
    fun interface Listener<T> { fun onEvent(event: T, registration: Registration) }
    class Registration internal constructor(/* hub, listener */) { @MainThread fun remove() }
    @MainThread fun addListener(listener: Listener<T>): Registration
}

// common.domain
enum class UiUnavailableReason { NOT_INITIALIZED, NOT_FOREGROUND, HOST_START_FAILED }
enum class CancelReason { REQUESTED, HOST_DESTROYED }

// common.presentation, common.logging (RG)
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object ForegroundActivityTracker : Application.ActivityLifecycleCallbacks {
    @MainThread fun current(): Activity?
    @MainThread fun currentFragmentActivity(): FragmentActivity?
}
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP) object LogRedaction { fun redact(value: CharSequence?): String }

// clipboard.domain
enum class ClipboardErrorCode {
    EMPTY_CONTENT, EMPTY_ITEMS, INVALID_URI, UNAVAILABLE, READ_NOT_ALLOWED, SECURITY, UNKNOWN;
    companion object { fun of(error: Throwable): ClipboardErrorCode }
}
// clipboard (feature root: Manager layer)
class AndroidClipboardManager internal constructor(/* use cases, observer, events */) {
    fun copyPlainText(content: ClipContent.PlainText)                 // same exceptions as the existing use cases
    fun copyHtmlText(content: ClipContent.HtmlText)
    fun copyUri(content: ClipContent.UriContent)
    fun copyMultipleText(content: ClipContent.MultipleText)
    fun clear()
    fun read(): ClipReadResult?
    fun hasClip(): Boolean
    fun getDescription(): ClipDescriptionInfo?
    @MainThread fun startObserving()
    @MainThread fun stopObserving()
    @MainThread fun isObserving(): Boolean
    val changes: EventHub<Unit>
    fun errorCodeOf(error: Throwable): ClipboardErrorCode
    companion object { @JvmStatic fun getInstance(context: Context): AndroidClipboardManager }
}

// dialog.domain
data class DialogOptions(val cancelable: Boolean = true, val cancelableOnTouchOutside: Boolean = true)
enum class DialogButton { POSITIVE, NEGATIVE }
sealed interface DialogRequest {
    val title: String
    val options: DialogOptions
    data class Alert(override val title: String, val message: String, val buttonText: String = "OK",
                     override val options: DialogOptions = DialogOptions()) : DialogRequest
    data class Confirm(override val title: String, val message: String, val negativeText: String = "No",
                       val positiveText: String = "Yes", override val options: DialogOptions = DialogOptions()) : DialogRequest
    data class SingleChoice(override val title: String, val items: List<String>, val checkedIndex: Int? = 0,
                            val negativeText: String = "Cancel", val positiveText: String = "OK",
                            override val options: DialogOptions = DialogOptions()) : DialogRequest
    data class MultiChoice(override val title: String, val items: List<String>, val checked: List<Boolean>,
                           val negativeText: String = "Cancel", val positiveText: String = "OK",
                           override val options: DialogOptions = DialogOptions()) : DialogRequest
    data class TextInput(override val title: String, val message: String, val hint: String = "",
                         val negativeText: String = "Cancel", val positiveText: String = "OK",
                         val enablePositiveWhenEmpty: Boolean = false,
                         override val options: DialogOptions = DialogOptions()) : DialogRequest
    data class Login(override val title: String, val message: String, val usernameHint: String = "Username",
                     val passwordHint: String = "Password", val negativeText: String = "Cancel",
                     val positiveText: String = "Login", val enablePositiveWhenEmpty: Boolean = false,
                     override val options: DialogOptions = DialogOptions()) : DialogRequest
}
sealed interface DialogValue {
    data object None : DialogValue
    data class SingleChoice(val index: Int?) : DialogValue
    data class MultiChoice(val checked: List<Boolean>) : DialogValue
    class Text(val text: String) : DialogValue                                 // equals/hashCode by value; toString redacts
    class Login(val username: String, val password: String) : DialogValue      // equals/hashCode by value; toString redacts
}
enum class DialogError { NOT_INITIALIZED, NOT_FOREGROUND, HOST_START_FAILED, SHOW_FAILED;
    companion object { fun from(reason: UiUnavailableReason): DialogError } }
sealed interface DialogResult {
    sealed interface Answer : DialogResult
    data class Button(val which: DialogButton, val text: String, val value: DialogValue) : Answer
    data object Dismissed : Answer
    data class Canceled(val reason: CancelReason) : DialogResult
    data class Failed(val error: DialogError) : DialogResult
}
sealed class DialogDomainError : Exception() {
    data class Canceled(val reason: CancelReason) : DialogDomainError()
    data class Unavailable(val error: DialogError) : DialogDomainError()
}

// dialog.application
interface DialogPresenter {
    fun show(requestId: Long, request: DialogRequest, onResult: (DialogResult) -> Unit)   // any thread
    fun cancel(requestId: Long)                                                           // any thread
}
class ShowDialogUseCase(private val presenter: DialogPresenter) {
    operator fun invoke(request: DialogRequest, onResult: (DialogResult) -> Unit): Long   // throws IllegalArgumentException
}
class CancelDialogUseCase(private val presenter: DialogPresenter) { operator fun invoke(requestId: Long) }

// dialog (feature root: Manager layer)
class AndroidDialogManager internal constructor(/* use cases */) {
    fun show(request: DialogRequest, onResult: (DialogResult) -> Unit): Long
    suspend fun show(request: DialogRequest): DialogResult.Answer          // throws DialogDomainError
    fun cancel(requestId: Long)
    companion object { @JvmStatic fun getInstance(context: Context): AndroidDialogManager }
}

// notification.domain
sealed interface PermissionRequestResult {
    data object Granted : PermissionRequestResult
    data object Denied : PermissionRequestResult
    data class Canceled(val reason: CancelReason) : PermissionRequestResult
    data class Failed(val reason: UiUnavailableReason) : PermissionRequestResult
}
sealed class PermissionRequestDomainError : Exception() {
    data class Canceled(val reason: CancelReason) : PermissionRequestDomainError()
    data class Unavailable(val reason: UiUnavailableReason) : PermissionRequestDomainError()
}
enum class NotificationSettingsTarget { NOTIFICATIONS, APP_DETAILS, EXACT_ALARM }
enum class NotificationSettingsOpenResult { OPENED, OPENED_FALLBACK, FAILED }

// notification.application
interface NotificationPermissionPort {
    fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit)   // any thread
    fun cancel(requestId: Long)                                                 // any thread
}
class RequestNotificationPermissionUseCase(private val port: NotificationPermissionPort) {
    operator fun invoke(onResult: (PermissionRequestResult) -> Unit): Long
}
class CancelNotificationPermissionRequestUseCase(private val port: NotificationPermissionPort) {
    operator fun invoke(requestId: Long)
}
interface NotificationSettingsPort {
    fun canScheduleExactAlarms(): Boolean
    fun open(target: NotificationSettingsTarget): NotificationSettingsOpenResult
}
class CanScheduleExactAlarmsUseCase(private val port: NotificationSettingsPort) { operator fun invoke(): Boolean }
class OpenNotificationSettingsUseCase(private val port: NotificationSettingsPort) {
    operator fun invoke(target: NotificationSettingsTarget): NotificationSettingsOpenResult
}

// notification (feature root: Manager layer)
class AndroidNotificationManager internal constructor(/* use cases, ports, events */) {
    // existing operations (same arguments, results and exceptions as the existing use cases)
    fun show(command: AndroidNotificationCommand): Result<Unit>
    fun update(command: AndroidNotificationCommand): Result<Unit>
    fun cancel(id: Int, tag: String? = null): Result<Unit>
    fun cancelAll(): Result<Unit>
    fun createChannel(channel: NotificationChannel): Result<Unit>
    fun createChannels(channels: List<NotificationChannel>): Result<Unit>
    fun deleteChannel(channelId: String): Result<Unit>
    fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Result<Unit>
    fun cancelScheduled(id: Int, tag: String? = null): Result<Unit>
    fun cancelAllScheduled(): Result<Unit>
    fun restoreScheduled(): Result<Unit>
    fun isScheduled(id: Int, tag: String? = null): Boolean                // delegates to NotificationUseCases.isScheduled(context, ...)
    fun getActive(): List<ActiveNotification>
    fun hasPermission(): Boolean
    fun areNotificationsEnabled(): Boolean
    fun startProgress(command: AndroidNotificationCommand)                // delegates to ProgressForegroundNotifications
    fun updateProgress(command: AndroidNotificationCommand)
    fun completeProgress(command: AndroidNotificationCommand)
    fun stopProgress()
    // new operations
    fun requestPermission(onResult: (PermissionRequestResult) -> Unit): Long
    suspend fun requestPermission(): Boolean                             // throws PermissionRequestDomainError
    fun cancelPermissionRequest(requestId: Long)
    fun canScheduleExactAlarms(): Boolean
    fun openSettings(target: NotificationSettingsTarget, from: Context? = null): NotificationSettingsOpenResult
    val interactions: EventHub<NotificationInteraction>
    val shown: EventHub<NotificationShown>
    companion object { @JvmStatic fun getInstance(context: Context): AndroidNotificationManager }
}

// notification.presentation
class NotificationInteraction(val kind: Kind, val notificationId: Int, val tag: String?,
                              val actionId: String?, val data: Map<String, String>) {   // equals/hashCode by value; toString redacts data values
    enum class Kind { BODY_TAP, ACTION, DISMISS }
}
data class NotificationShown(val notificationId: Int, val tag: String?, val channelId: String)
object NotificationEventIntents {
    fun bodyTap(context: Context, notificationId: Int, tag: String?, data: Map<String, String> = emptyMap(),
                launchApp: Boolean = true): AndroidPendingIntentRequest
    fun action(context: Context, notificationId: Int, tag: String?, actionId: String,
               data: Map<String, String> = emptyMap(), launchApp: Boolean = false): AndroidPendingIntentRequest
    fun dismiss(context: Context, notificationId: Int, tag: String?, data: Map<String, String> = emptyMap()): AndroidPendingIntentRequest
    fun fullScreenLaunch(context: Context, notificationId: Int, tag: String?): AndroidPendingIntentRequest?
}
class NotificationResourceResolver(context: Context) {
    fun resolve(name: String, type: String? = null): Int?
    fun defaultSmallIcon(): Int
}

// share.domain
class ShareChooserAction(val id: String, val label: String, val iconBytes: ByteArray)   // equals/hashCode by value
data class ShareSelection(val token: Long, val packageName: String?)
sealed class ShareDomainError : Exception() {
    // ... existing 9 subclasses unchanged ...
    data class InvalidChooserAction(val id: String) : ShareDomainError()
}

// share.application
interface ShareRepository {                                      // existing port; three functions added
    // ... existing functions unchanged ...
    fun shareForSelection(content: ShareContent, preview: SharePreviewOptions): Long =
        throw UnsupportedOperationException()
    fun cancelShareSelection(token: Long): Unit = throw UnsupportedOperationException()
    fun shareTextWithActions(content: ShareContent, actions: List<ShareChooserAction>, preview: SharePreviewOptions): Unit =
        throw UnsupportedOperationException()
}
class ShareForSelectionUseCase(private val repository: ShareRepository) {
    operator fun invoke(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions()): Long
}
class CancelShareSelectionUseCase(private val repository: ShareRepository) { operator fun invoke(token: Long) }
class ShareTextWithActionsUseCase(private val repository: ShareRepository) {
    operator fun invoke(content: ShareContent, actions: List<ShareChooserAction>, preview: SharePreviewOptions = SharePreviewOptions())
}

// share (feature root: Manager layer)
class AndroidShareManager internal constructor(/* use cases, coordinator, events */) {
    // existing operations (same arguments, results and exceptions as the existing use cases)
    fun shareText(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions())   // delegates to ShareTextUseCase(content, "[]", preview)
    fun shareImage(filePath: String, mimeType: String)
    fun shareImages(filePaths: List<String>)
    fun shareFile(filePath: String)
    fun shareFiles(filePaths: List<String>)
    fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray)
    fun removeDirectShareTargets(ids: List<String>)
    fun shareWithCallback(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions(),
                          onResult: (String?) -> Unit, onFinished: () -> Unit = {})
    fun cancelPendingCallback()
    // new operations
    fun shareTextWithActions(content: ShareContent, actions: List<ShareChooserAction>,
                             preview: SharePreviewOptions = SharePreviewOptions())
    fun shareForSelection(content: ShareContent, preview: SharePreviewOptions = SharePreviewOptions()): Long
    fun cancelShareSelection(token: Long)
    val chooserActions: EventHub<String>
    val selections: EventHub<ShareSelection>
    companion object { @JvmStatic fun getInstance(context: Context): AndroidShareManager }
}
```

- 既定の値（`"OK"`、`"Cancel"` など）は今のブリッジの既定の値と同じ
- `AndroidDialogFragment.newRequestInstance(requestId, request)` は internal（8.8）
