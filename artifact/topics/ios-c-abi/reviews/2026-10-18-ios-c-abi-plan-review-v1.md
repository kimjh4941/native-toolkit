# レビュー結果

- 日付: 2026-10-18
- 対象ファイル: `artifact/topics/ios-c-abi/README.md`（初版。コミット前。495 行）
- トピック名: ios-c-abi（企画書）
- 対象 OS: iOS 18 以降
- 判定: **要修正**（区分 A が残るので、README を直して再レビューする）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）
- 機械照合: 対象外（`check_design_consistency.py` は設計書用）

区分は review-document の止める基準に従う。A = このまま進むと後の成果物の動作・API・契約が変わる、B = 検証の手段が変わる、C = 記述の整合だけ。「出典」は指摘したレビュアー（Claude / Codex / 両方）。

---

## 強み

- 1.1〜1.4 の事実の大半が、実物と行の単位で合っている。関数の数（43、操作 37、制御 6、コールバックの型 16）、テストの件数、スレッドのばらつき、1.4 の不備、Unity の側の規模（両方）
- 6 章で、43 関数だけでなく振る舞いの集合を照合の対象にしている。Android のレビュー v1 の A-1 を最初から取り込んでいる（Claude）
- 1a に本物の Unity のビルドでの確認を入れ、`__cxa_atexit`、`dispatch_sync` の禁止、`release` の失敗の経路、照合の自己テスト、dist の固定を明示している。Android の知見の反映がよい（Claude）
- D-1 で macOS とまとめない根拠に数字がある（Claude）。D-10 で C の入口を手書きにし、Swift を内側の受け口に隔てる判断は妥当（Codex）
- 動的な xcframework 2 つと依存の向きは、今の配布物と一致する（Codex）
- 8.3 で、利用者の側の上限から版を逆算している（Claude）

## 事実の照合

| 主張 | 結果 | 根拠 |
|---|---|---|
| C の関数が 43 個（15 / 6 / 21 / 1）、操作 37・制御 6、コールバックの型 16、`DllImport("__Internal")` 43 本 | 正しい | `*Bridge.h` の宣言、dist の `nm -gU`、`unity-native-plugin` の `Ios*Manager.cs`（両方） |
| テストの件数 186 / 83 / 10 / 25 | 正しい。ただし 25 は Clipboard の 22 件と雛形の 3 件 | `@Test` と `func test*` を数えた（両方） |
| 2 つとも dynamic で、`@rpath/IosLibrary.framework` に依存する。`*Bridge.h` は配布物に無い | 正しい | `file`、`otool -L`、`Headers/`（両方） |
| **1.1「署名は無い」、D-18「1.x と同じ（署名しない）」** | **誤り** | xcframework そのものは署名されていないが、`ios-arm64` のスライスは 2 つとも `Apple Development: Jong Hyun Kim (545GVBT238)`、`TeamIdentifier=C9KYBZ33LV` で署名されている。シミュレーターのスライスは ad-hoc。どの pbxproj も `CODE_SIGN_STYLE = Automatic`（両方。こちらでも `codesign -dvv` で確かめた） |
| **1.2「既定の文言（OK / Cancel / Delete / Username / Password / Login）はブリッジにしか無い」** | **誤り** | ライブラリに既にある（`IosDialogManager.swift:175,201-202,233-234,267,317-318,384-387`）（Claude） |
| **1.2「Notification・Share のエラーの分類が無い」** | **言い過ぎ** | `NotificationError` と `ShareError` は enum として既にある（`NotificationError.swift:9-27`、`ShareError.swift:9-28`）。任意の `Error` を持つ case があり、C ABI 用の安定した番号への対応が無いのが問題。Dialog には型が無い（Codex。こちらでも確かめた） |
| 1.3 のスレッドの表 | 正しい | `UnityIosClipboardManager.swift:16-22,51-60`、`IosShareManager.swift:69`、`UnityIosDialogManager.swift:169-197`、`UnityIosNotificationManager.swift:48-67,193-202`（両方） |
| 1.4 の不備（delegate の上書き、static の受け手、`registerCategory`、observer、ログ、NULL、Error を Domain に持つ、`PrivacyInfo` が無い） | 正しい | 各ファイル（両方） |
| 前方一致で探すのは `IosFrameworkPatcher` だけ（1.4 / 5.2） | **一部** | `PreBuildProcessor.cs:477,704` と `PostBuildProcessor.cs:48,225` も `ios-native-toolkit-` の前方一致。並べると `capi-2.0.0` > `2.0.0`（'c' > '2'）なので capi の側が選ばれる（Claude） |
| `PostBuildProcessor` の development ビルドの疑い | **コードで確認** | `PostBuildProcessor.cs:42-53,225-236`。development では `-debug` しか探さず、見つからないと黙って戻る（Claude） |
| Unity の iOS のテスト | 正しい。PlayMode の 36 件が抜けている | `Tests/PlayMode/Ios*.cs`（Claude） |
| Unity の C# は main で動く | 正しい | トランポリンの `UnityAppController+Rendering.mm:28-34`（Claude） |
| Xcode 26.3 で作った swiftinterface を Xcode 26.0 の利用者が読める | 未確認 | 手元は 26.3 だけ（両方） |
| 外部の事実（App Store Connect の要件、Unity の通知パッケージ、Flutter / Dart、CocoaPods、SE-0495） | 未確認 | Claude は外部の文書を開いていない。Codex も個別には確かめていない |

## 指摘と対応

### 区分 A

| ID | 出典 | 対象 | 指摘 | 対応 |
|---|---|---|---|---|
| A-1 | 両方 | D-4 / D-7 / 3.1 | delegate は起動の終わりまでに入れる必要があるのに、D-4 は初期化の関数も `+load` も置かないとしている。Unity の C# は起動の後に始まり、`unity-native-plugin` にはネイティブのコードが無いので、早く入れる手段が無い。このままでは、コールドスタートのタップと起動のきっかけの通知が必ず失われる | D-4 を「一般の初期化は無い。通知だけは、ホストのネイティブのコードが起動の終わりまでに呼ぶ `ntk_notification_install`（仮。冪等）を必須にする」に改める。Unity の側の `.mm`（`AppDelegateListener` / `kUnityWillFinishLaunchingWithOptions`）を 2c の申し送りの必須の項目にする。1a の Unity の確認にコールドスタートのタップを足す |
| A-2 | Codex | D-6 / 3.2 | 「`release` も常に main へ非同期」は、Android・Windows の「入口で受け付けなかったときは、呼び出し元のスレッドで関数が戻る前に `release` を呼ぶ」と食い違う | D-6 に、入口で拒んだときは同期、受け付けた後は main に非同期、と書き分ける。状態（受け付けた / 拒んだ / 取り消した / 終わった）の表を第 1 部で作る |
| A-3 | Codex | D-7 | 転送の形の中身が決まっていない: proxy を誰が持つか（delegate は weak）、3 つの任意のメソッドすべての転送と `responds(to:)`、`willPresent` の表示の選択肢、`didReceive` の completionHandler をちょうど 1 回、前の delegate が completion を呼ばない場合、どの通知を誰に渡すか | D-7 に、第 1 部で決める項目として列挙する。本物の Unity の通知パッケージとの共存を 1a で確かめる。成り立たない組み合わせはマニュアルの契約にする |
| A-4 | 両方 | 5.2 / 2b / 2c | `unity-native-plugin` の版の固定と、前方一致の直しを 2c まで待つと、capi を含む dist を置いた時点で向こうのビルドが壊れる。`PreBuildProcessor` も前方一致。iOS だけの dist を置くと macOS のビルドも壊れる | 2b で dist を置く前に、向こうに 3 つを頼む: iOS と macOS の `VERSION.txt` での固定、3 か所（Pre / Post / Patcher）の完全一致、development ビルドの埋め込み。新しい dist にはいつも全 OS の成果物をそろえる |
| A-5 | 両方 | 1.1 / D-18 | 署名の前提が誤り。「1.x と同じ」にすると、個人の Apple Development の証明書（氏名と Team ID）で署名したスライスを配り続ける。「署名しない」と決めても、今のビルドでは実現しない | 1.1 を直す。D-18 を、署名しない（archive で `CODE_SIGNING_ALLOWED=NO`）/ 今のまま / 配布用の証明書で xcframework に署名、から決め直す。`check_ios_dist.py` でスライスごとの署名の状態を照らす |
| A-6 | Claude | D-12 | 「改名の理由が無い」は不正確。bundle id `ios.library.IosLibrary`、`unity.ios.plugin.*` は持っていない逆 DNS の名前で、Android の `android.library` と同じ状況 | 選択肢 C（モジュール名は保ち、bundle id を `com.jonghyunkim.nativetoolkit.*` にする）を足して推奨にする。`IosLibraryCApi` の bundle id も決める |
| A-7 | Codex | 1.2 / 4 | エラーの型は既にある。前提を誤ったまま新しい型を作ると、今の公開 API を要らずに置き換えかねない | 1.2 と 4 章を「型はあるが、任意の `Error` を持つ case があり、安定した番号への対応が無い。Dialog には型が無い」に直す。今の型を基にし、C ABI のエラーの表への対応表を設計書に置く |
| A-8 | 両方 | D-10 / 8.2 | 入口の `.m` の `@try` は、main に積んだ後に UIKit が投げる例外を止められない（入口はもう戻っている） | D-10 の根拠を、手書きのヘッダー・`_Thread_local`・照合・今の Xcode のまま始められること、に絞る。例外は「起こさない検査（popover の基点を必ず設定するなど）、起きたら落ちる」を基本にする（Android の `std::terminate` と同じ）。8.2 の試験は main に積んだブロックの中で起こす形にする |
| A-9 | 両方 | D-10 / D-11 | framework のターゲットでは、`.m` から Swift を呼ぶには受け口を `public @objc` にする必要があり、swiftinterface と `-Swift.h` に出る。`EXPORTED_SYMBOLS_FILE` と `nm -gU` では、Objective-C の実行時のクラス名の衝突を防げず、確かめられない | 1a で隠し方を比べる（capi の swiftmodule と `-Swift.h` を配らない / Swift が C の関数ポインタの表に登録する / 内側の `@_cdecl` と非公開のヘッダー）。要件を「リンクできる公開の ABI は `ntk_*` だけ」「実行時のクラス名がぶつからない（固有の接頭辞）」「内側の Swift の metadata は許す」に分ける。`objc_getClass` の試験を足す |
| A-10 | 両方 | 0e / 0f / 4 章 | 0e・0f で `IosLibrary` の公開 API が変わると、Swift 5 のままのブリッジが組めなくなる。「最小の直し」の範囲が決まっておらず、直し方によってはスレッドが変わる。基準にブリッジのテスト（83 件）を入れるかも書かれていない | D-22 を足す: 0e でブリッジをビルドと基準から外し、ソースは 1b の参照のために段階 3 まで残す（推奨）/ 最小の直しで組み続ける。4 章と 5.2 の「0f・1b」を「0e・0f・1b」に直す |

### 区分 B

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| B-1 | Codex | `common.md` は OS のシェルの UI と権限の初回の同意を「自動化しないもの」にしている。7.2 の「基本は自動化する」と食い違う | 7.2 に `common.md` の既定を書き、0a で確かめて自動化するものは例外として結果に理由を書く（Android の 0a と同じ扱い） |
| B-2 | Codex | スレッドと `release` の回数を UI テストでは証明できない | 7 章の C ABI のテストに、全コールバックの型について main で来ること・入口の中で呼ばれないこと・ちょうど 1 回、入口での拒否、取り消しを記録する試験を明記する |
| B-3 | 両方 | 「利用者は Xcode 26.0 以上」を確かめる手段が無い | Xcode 26.0 を入れて、smoke と `import IosLibrary` を 1a で確かめる。確かめられなければ D-16 を 26.3 以上に上げる |
| B-4 | 両方 | `check_ios_dist.py` で照らすものが無い | 照らす項目の表を 7 章に足す（`nm -gU`、`otool -L` / `-l`、`LC_ID_DYLIB`、`@rpath/libswift*` に依存しない、`__cxa_atexit`、`PrivacyInfo.xcprivacy` が両方のスライスに、`MinimumOSVersion`、`include/` と `Headers/` の一致、署名の状態、Swift の公開面が capi に無い） |
| B-5 | 両方 | 1.x から 2.0.0 への更新のテストが無い（Android にはある） | 7 章と DoD に足す |
| B-6 | 両方 | 通知からのコールドスタートと、ホストの通知のパッケージとの共存を確かめる試験が無い | 0a で XCUITest で扱えるかを確かめ、0c / 1b の UI テストに入れる。本物の Unity の通知パッケージとの共存を 1a と 2c で確かめる。Flutter は 8.4 に回す |
| B-7 | Claude | 手元の Flutter は 3.7.0（fvm）で、`NativeCallable.listener` も build hook も無い | 8.2 の Flutter の項目を外し、8.4 に回す |
| B-8 | Claude | TSan は実機で動かず、ASan と同時にも使えない | 7 章にスライス × サニタイザー × 環境の表を足す |
| B-9 | Claude | 0e の「Xcode 26 の推奨設定」で、既定の actor の isolation などの upcoming feature が入ると、公開 API の意味が変わりうる | 0e で変わる build setting の差分を全部記録し、`SWIFT_DEFAULT_ACTOR_ISOLATION` と upcoming feature を明示的に固定する |
| B-10 | Claude | `PostBuildProcessor` は development ビルドで埋め込まないので、1a の確認を development で行うと偽の失敗になる | 1a は release で行い、申し送りに直しを足す |
| B-11 | Claude | ミューテーションでの確かめが DoD では照合のスクリプトにしか無い | C ABI のテストと UI テストにも足す |
| B-12 | Codex | テストの件数の定義（Clipboard の 22 件と全体の 25 件） | 7 章に内訳を書き、基準はターゲット全体・機能ごと・雛形の 3 つで持つ |

### 区分 C

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| C-1 | Claude | 既定の文言は既にライブラリにある | 1.2 から消し、4 章は「0 で埋めた構造体のときの既定」として書き直す |
| C-2 | Claude | 3.1・D-7 で Unity の導入の手順をマニュアルに書くとしている。M-4（Unity の記載は `unity-native-plugin` に任せる）と食い違う | Unity の部分は `unity-native-plugin` のマニュアルに回すと書く |
| C-3 | Claude | 案 C は本来ブリッジの型の話で、D-14 と 0e で書き方が食い違う | 0e で行うのは「`IosLibrary` の完了を main で返し、handler を `@Sendable` にする」と書き分ける |
| C-4 | Claude | release の workflow に iOS を配置する手順は無い（dist がそろっているかの確認だけ） | 5.2 の説明を直す |
| C-5 | Claude | Unity の iOS の PlayMode 36 件が書かれていない | 足す |
| C-6 | Claude | 手元に iOS 18.3 のシミュレーターがある | D-21 に、実機がつながらないときの代わりとして書く |
| C-7 | Claude | 知見 4 章の「決めたら README の表をその場で直す」が運用の規則として書かれていない | 5.1 に足す |
| C-8 | Codex | 「`@_cdecl` から `@c` に移すと ABI が変わる」は、C のシンボルの名前と形を保てば C の利用者には当たらない | 「消えるのは Swift の名前のシンボルで、C の ABI は照合で確かめる」と直す |
| C-9 | Codex | ビルドの Swift の版の記録 | 8.3 に、配布物の swiftinterface の `swiftc` の版（6.2.4）と `DTXcodeBuild` を記録すると書く |
| C-10 | Codex | D-17 の「C は別のトピック」が C 言語にも読める | 「選択肢 C」と書く |

### 不足項目（README に足す）

- iOS の UTF-8 の変換: `NSString` は対になっていないサロゲートを持てる（ほかのアプリが置いたクリップボードなど）。`UTF8String` の振る舞いと U+0000 の扱い（AC-19 / E-16）を 8.6 に入れ、1a で確かめる（Claude）
- 戻り値の無い Notification の操作（`cancel*`、`remove*`、`openNotificationSettings`、`removeCategory`）を、C ABI で完了とエラーを返す形にするか（第 2 部。Claude）
- ホストの画面の型: Unity の root の ViewController の上に Dialog や Share のシートを出したときに、ゲームが止まるか（知見 1 章。Claude）
- ヘッダーのコンパイルの組み合わせ（C99 / C11 / C++、Objective-C）（Codex）
- 2.0.0 を出す条件と戻り先（1.x の固定、`unity-native-plugin` の公開の順、失敗したときの戻り先）（Codex）
- プライバシーマニフェストの理由の申告の一覧と、アーカイブのプライバシーのレポートでの確かめ（C617.1 が正しい理由かは未確認）（Codex）
- 既存の Swift のエラーの case と、C ABI の番号の対応表（第 2 部。Codex）

### 採らなかったもの

| 出典 | 指摘 | 採らない理由 |
|---|---|---|
| Codex（A-10） | 段階 3（ブリッジの削除）を 2c より先に進めてよいとする記述は、D-12 の一括の移行と、Unity での確認の前の戻り先の要件に反する | Unity が使うのは `dist/1.13.0/ios` の出し済みの xcframework で、リポジトリからブリッジを消しても影響しない。戻り先はタグ `1.13.0` と `dist/1.13.0` で、2.0.0 は 2c が成功するまで出さない（D-2）。Android も同じ順で問題なく進んだ（知見 1 章）。この理由を README の「順番の理由」に書く |
