# レビュー結果（段階 2c の申し送り・1 回目と 2 回目）

- 日付: 2026-10-10
- レビュー対象: `results/2026-10-10-android-c-abi-stage2c-handoff.md`（最初の版）
- レビュアー: 2 本。観点が 2 つあるため
  - Claude のサブエージェント（設計書・ヘッダー・コードとの一致）
  - Codex（`unity-native-plugin` の今の作りに照らして、このとおりに移して成功するか）
- 総合評価: **要修正（重大）**（A が Claude 5 件、Codex 8 件。重なりを除いて 10 件）

ID の `H-C` は Claude、`H-X` は Codex。区分は 2b のレビューと同じ（A: このとおりにすると実装を誤る、または必須の項目が無い。B: 不正確、または文脈が足りない。C: 小さなもの）。

## 確かめて合っていたこと

- 関数の数（155）、ヘッダー（6 つ）、ABI（`arm64-v8a` と `x86_64`）、依存の表、OP の数（OP-01〜56）、8.3 の 69 メソッド、参照した節と ID の大半、スレッドの規則、`release` と `user_data` が NULL でよいこと、コールバックのハンドルが所有権ごと渡ること、Unity の対象の版、32 ビットと R8 の扱い（自動の経路）
- `unity-native-plugin` の Direct Share の androidlib とサンプルの controller は `android.unity.*` を参照していない

## 区分 A

| ID | 問題 | 対処 |
|---|---|---|
| H-C1、H-X5 | 「`user_data` を NULL にし、要求の ID と表で照合してよい」は成り立たない。UnityMain から呼ぶと ID が書かれる前に完了が来うる。ID を持たないコールバックがある（Share を開く、設定の画面、Clipboard の変更）。設計（第 1 部 1.3）は `user_data` で対応付けると決めている | 登録ごとに別の `user_data`（呼ぶ前に表に入れたキーか `GCHandle`）を渡す形にした（4.3） |
| H-C2、H-X6 | 差し替え型のリスナーが「古いものを外して足す」だけで、C-6 の本体（今のハンドルでなければ UnityMain で捨てる）が無い | C-6 を写した（4.5） |
| H-X7 | 要求の ID は 64 ビット。Windows の `uint` の宣言を写すとメモリを壊す | `ulong` にすると書いた（4.3） |
| H-X8 | 今の `AndroidJavaProxy` の形は、コールバックのスレッドで manager の表を変えている。そのまま写すと UnityMain とぶつかる | コールバックでは写して積むだけ、状態は UnityMain で変える、と書いた（4.2） |
| H-C3 | C# の宣言を OS ごとに書く決まり（AP-5、RP-5）が無く、「Windows と同じ形」を強く打ち出していた | 共通は `Common.h` だけ、と書いた（1 章、4.4） |
| H-C4、H-X1 | `m2/` を Gradle のリポジトリにする案を推奨していたが、Unity の Gradle は `PREFER_SETTINGS` と flatDir で使われない（README 3 章で決めていた）。依存を足す今の処理はビルドの後で、asmdef の定義が無いと組まれない | AAR を写して依存を明示的に足す形を推奨にし、足す時期（Gradle の前）と有効にする条件を書いた（3.3） |
| H-C5、H-X4 | `NativeToolkitCApi.init` は `object` のインスタンスのメソッドで、`CallStatic` では呼べない。戻り値の扱いが無い。keep の規則に入っていない | `INSTANCE` を引いて呼ぶ形、`InitResult` ごとの扱い、Minify のときの keep を書いた（4.1、3.4） |
| H-X2 | `PreBuildProcessor` の前方一致（`android-native-toolkit-`）に capi も入り、取り違える | `VERSION.txt` の完全なファイル名か、`-capi-` を外すと書いた（3.3） |
| H-X3、H-C7 | 作業用の作り方（`--m2` だけ）では capi が出ず、版も 1.3.0 になる | 完全なコマンドを書いた（7 章） |

## 区分 B と C

| ID | 対処 |
|---|---|
| H-X9 | テストの件数を直した（EditMode 約 116、実機の Player で流す PlayMode 11。「Android の Player テストは無い」は誤りだった）（6 章） |
| H-X10 | 今の Build Profile は IL2CPP だけなので、Mono 用の手順が要ると書いた（6 章） |
| H-X11 | JSON の扱いを機能ごとに分けた（4.7） |
| H-X12、H-C11 | `ntk_android_error` が別の列挙であることと、`NOT_INITIALIZED` の例外を書いた（2 章、4.1、4.4） |
| H-C6 | `GCHandle` の `Target` はコールバックの中で引く、`release` の後は配送が来ない、と書いた（4.3） |
| H-C8 | AP-8 の一覧を 16 章のとおりに写し、リソースの型の制約を足した（4.6） |
| H-C9 | NT-04 の違い（起動の Intent の action、受け手が無い間のタップ）を足した（4.6） |
| H-C10 | 完了や `release` を同期で待たない、main を塞がない、と書いた（4.2） |
| H-C12、H-C13 | 節の番号（3.3）と「第 1 部 AC-23」を直した |
| H-C14 | 「同じ実体」を確かめた方法を正確にした（4.1） |
| H-C15 | `release` が呼び出しスレッドで来る場合に受け付けの失敗を足し、プロセスの終わりには来ないと書いた（4.3） |
| H-C16 | AAR の中身に `NativeToolkitCApi` と `NtkInitializer` を足した（3.2） |

設計書の第 2 部 16 章の「約 60 件」は、数え直した約 79 件に直した。

## 2 回目（書き直した版）

- レビュアー: 同じ 2 本。1 回目の指摘が直ったかと、書き直しで新しく入った誤りを見た
- 結果: 1 回目の指摘はすべて直っていた。新しい指摘は A が Codex 2 件、B が Claude 4 件、C が Claude 5 件

ID の `H2-C` は Claude、`H2-X` は Codex。

| ID | 区分 | 問題 | 対処 |
|---|---|---|---|
| H2-X1 | A | `IPostGenerateGradleAndroidProject` の `path` は `unityLibrary` のルートで、足す先が書かれていない。今の patcher にそのまま渡すと依存が足されない | 足す先（`unityLibrary/build.gradle`）、`launcher` に重ねないこと、`path` の親が Gradle のルートであることを書いた（3.3） |
| H2-X2 | A | Minify のときの keep は、Custom Proguard File を有効にしないと取り込まれない（今は無効） | 有効にする手順と、そのまま貼れる規則を書いた（3.4） |
| H2-C1 | B | 完了の直後に同じ main のメッセージで `release` が来るので、キーのまま UnityMain に積むと、引く前に消えている | コールバックの中で引いてから積む、と書き、「`user_data` の表」と「manager の表」を分けた（4.3） |
| H2-C2 | B | Share を開く要求は Sharesheet が開いた時点で `release` されるので、ID を `user_data` の物に書き足せない | ID は manager の表（UnityMain）に置き、直前の Share の要求の ID と照らす、と書いた（4.3） |
| H2-C3 | B | 4.7（Clipboard と Share は payload から直接）が、8.3 と 16 章の JSON の文言とぶつかる | Clipboard と Share では 4.7 を優先すると書き、16 章にも同じ注記を足した |
| H2-C4 | B | ビルドのスクリプトの `-v` は必須で、`gradle.properties` を書き換える | 直して書き足した（7 章） |
| H2-C5〜H2-C9 | C | Share の完了を使う関数の数（6）、`release` の時期（操作とイベントの登録）、`NATIVE_SETUP_REQUIRED` の意味、16 章の件数の文の重複、AP-21 の対象 | 直した。README の「約 60 件」も 79 件に直した |
