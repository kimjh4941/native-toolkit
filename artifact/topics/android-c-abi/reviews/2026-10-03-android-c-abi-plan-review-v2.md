# レビュー結果（2 回目）

- 日付: 2026-10-03
- 対象ファイル: `artifact/topics/android-c-abi/README.md`（v1 を反映した版。534 行。コミット前の作業ツリー）
- トピック名: android-c-abi（企画書）
- 対象 OS: Android 12 以降（minSdk 31）
- 判定: **要修正**（新しい区分 A が出たので、README を直した。直した後の確認は 3 回目で行う）
- 別モデルによる独立レビュー: 実施済み（1 回目とは別の Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）
- 機械照合: 対象外（`check_design_consistency.py` は設計書用）

区分は 1 回目と同じ（A = 後の成果物を変える、B = 検証の手段、C = 記述の整合）。

---

## 1 回目の指摘の状態

2 者の判定を合わせた。どちらかが「解決していない」とした項目は、解決していない側に入れた。

| 状態 | 項目 |
|---|---|
| 解決 | A-1、A-5（座標は下の N-5）、A-6〜A-9、A-11、A-12、A-14、A-15、B-1（テストの入口の作りは設計書の領分）、B-3〜B-9、C-1〜C-4 |
| 一部解決 | A-10（前面の Activity を追う主体 → N-4）、A-13（Windows の側を直す段階 → N-8）、B-2（2b の時点で dist が無い → N-10） |
| 直したことで新しい問題が出た | A-2（→ N-1）、A-3（→ N-2、N-3）、A-4（→ N-4） |

8.6 への先送りは、段階の順序と成果物を変えないものに限って、企画書として許容できるという判定で 2 者が一致した。

## 新しい指摘

### 区分 A

| ID | 問題 | 出典 | 対処（README に反映済み） |
|---|---|---|---|
| N-1 | 64 ビットだけで出すのに、`NtkInitializer` が起動時に `System.loadLibrary` を呼ぶ。32 ビットで入ったアプリ（Flutter は既定で android-arm も組む。Unity は ARMv7 を選べる。32 ビットの TV や安価な端末は残っている）は、C ABI を使っていなくても起動時に落ちる | Claude | `UnsatisfiedLinkError` を捕まえて「C ABI は使えない」状態にし、アプリを落とさない。利用者の側の扱い（`DllNotFoundException` など、または `abiFilters`）をマニュアルの契約にする。32 ビットで入れるテストを足した（D-4、D-10、3.1、7 章、DoD） |
| N-2 | 「クラス名に依存しない JSON」と、Kotlin の公開 API が予約の中に任意の `Intent`（`AndroidPendingIntentRequest(intent: Intent)`）を受けることが両立しない | Claude | 利用者の `Intent` は `Intent.toUri` で保存し、再起動をまたぐ予約では extra が基本型と文字列だけになることを契約にする（**利用者の決定**。D-11） |
| N-3 | `persistAcrossBoot=false` の予約は保存されないので、更新の後に列挙できず取り消せない。「黙って残さない」と更新テストの期待値が成り立たない。0e で記録する項目も足りない | 両方 | 取り消せるのは保存した予約だけで、保存しなかった予約は発火しても何も表示されない、を契約にした。破棄の時期（`MY_PACKAGE_REPLACED` と初回、印を付けて一度だけ）、0e で記録する項目（request code の式、URI の scheme、flags）、更新テストの 2 種類、0a での「更新で Alarm が残るか」の確認を足した（D-11、0a、0e、7 章、DoD） |
| N-4 | `ForegroundActivityTracker` は `android_library` にあるのに Initializer は capi にしか無く、Kotlin だけの利用者で誰が登録するかが無い。Startup を無効にした遅い初期化では、既に前面にある Activity を取れない | 両方 | `android_library` に `LibraryInitializer` を置いて Tracker を登録し、capi の Initializer はそれに依存する。明示的な初期化で Activity を受け取れるようにする。Kotlin の利用者に androidx.startup の依存が入ることを書いた（3 章、3.1、4 章、D-4、D-7、1b） |
| N-5 | Maven の座標（groupId）が決まっていない。後で Maven Central に出すときに変わると破壊的変更になる | Claude | `io.github.kimjh4941`、artifactId は AAR の名前（**利用者の決定**。D-17、3 章、DoD） |
| N-6 | 0e の改名にブリッジ（`android.unity.*`）を含めるかが無い。D-2 で B に切り替えると C# の文字列が壊れる | Claude | D-2 の代わりの経路（B）を消したので、ブリッジは改名せず段階 3 で消す（D-2、D-15、0e、DoD） |
| N-7 | D-2 は A と決めながら「2c が間に合わなければ B」としていて、B の段階が無い | Codex | 2c が終わらなければ 2.0.0 のリリースを待つ（**利用者の決定**。D-2、5 章） |
| N-8 | `Common.h` を分けたときに Windows の側（ヘッダー、照合スクリプト、マニュアル）を直す段階が無い。共通の部分の置き場所も決まっていない | Claude | 2a で Windows の側も直す（名前と値は変えない）。置き場所を 8.6 に足した（3.3、2a、8.6） |
| N-9 | minSdk 31 を前提にしながら、下げるかの検討を設計書に回している | 両方 | D-18 として決定（31 のまま。**利用者の決定**） |
| N-10 | Unity と Flutter が Maven リポジトリを実際に使う手順と確認が無い | Codex | Unity は書き出す Gradle が `PREFER_SETTINGS` と flatDir なので m2 を使わず、2c で依存を明示的に足す。Flutter はアプリのプロジェクトにリポジトリを足す、を 3 章に書いた。2.0.0 で確かめる利用者は Unity と smoke だけで、Flutter などは「確かめていない」とマニュアルに書く（8.4。手元の Flutter は 3.7.0） |
| N-11 | C ABI の設計書の時期が、置き場所の図で「段階 2」になっていて、「1a の後、1b の前」と食い違う | 両方 | 図と 5.1 を「1a の後に書く。1b の前にスレッド・寿命・Context の章と残りの決定、2b の前に全体」にそろえた |

### 区分 B / C

| ID | 内容 | 出典 | 対処 |
|---|---|---|---|
| N-12 | smoke は dist の Maven リポジトリから解決するとしたが、2b の時点で dist は無い | Claude | 2b でビルドスクリプトに capi と Maven リポジトリの生成を足し、smoke は一時的なリポジトリから解決する（2b、5.2、7 章） |
| N-13 | 段階 3 で外す先に、ワークフロー（write-manual、implement-sample-app）、`coding-rules/common.md`、`check_design_consistency.py`、`scripts/README.md` が無い。リリースのワークフローの変更も無い | Claude | 段階 3 と 5.2 に足した |
| N-14 | 段階の名前のずれ（「段階 0 でテストをそろえる」は 0a〜0d、UI テストは 0c、1b の動作の変更が「無し」） | Claude | 直した |
| N-15 | D-7 の根拠「`registerForActivityResult` はホストの生成前に登録する必要がある」は不正確（`ActivityResultRegistry.register` は後から呼べる） | Claude | 根拠を直し、`FragmentActivity` のホストで権限を要求する手段は設計書で選ぶとした |
| N-16 | `hasCode="false"` の NativeActivity のアプリでは使えない | Claude | 3.1 の前提に足した |

## 確かめたこと（レビュアーによる）

- `filterEquals` はコンポーネント名を文字列で比べるので、クラスが無くても、古い名前で作り直した PendingIntent で Alarm を取り消せる（両方。PendingIntent と AlarmManager.cancel の公式の説明からの推論）
- 予約の保存データの `EXTRA_SHORTCUT_ID`（`tag::id`）は平文の JSON のキーで、Parcel を開かずに読める。request code は `"tag::id".hashCode()`、flags は `FLAG_UPDATE_CURRENT|FLAG_IMMUTABLE`（Claude）
- 既存の BootReceiver は `MY_PACKAGE_REPLACED` を受けている（Claude）
- `RegisterNatives` と、`ntk_*` と `JNI_OnLoad` だけを公開する version script は両立する（両方）
- androidx.startup で自動に初期化すれば、Activity より前に Callbacks を登録できる（Codex）
- `unity-native-plugin` の `AndroidTargetArchitectures` は 2（ARM64 だけ）。書き出した Gradle は `PREFER_SETTINGS` と flatDir（Claude）
- **確かめていないこと**: アプリの更新で `AlarmManager` の Alarm が残るか。段階 0a で確かめる

## 総合評価

1 回目の 15 個の区分 A のうち 12 個は解決した。段階の再編と 8.6 への先送りも許容できる。決め直した決定（D-7、D-10、D-11、D-17）から新しい区分 A が出たが、どれも README の決定の文を足すか直せば済み、段階の骨組みは変えなくてよい（2 者が一致）。4 つは利用者が決めた（D-2 の代わりの経路を消す、D-18、D-11 の保存形式、D-17 の座標）。直した後に、もう 1 回短くレビューする。
