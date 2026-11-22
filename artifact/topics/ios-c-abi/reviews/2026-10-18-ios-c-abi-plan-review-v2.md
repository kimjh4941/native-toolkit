# レビュー結果

- 日付: 2026-10-18
- 対象ファイル: `artifact/topics/ios-c-abi/README.md`（レビュー v1 を反映した版。コミット前）
- トピック名: ios-c-abi（企画書）
- 対象 OS: iOS 18 以降
- 判定: **要修正**（新しい区分 A が 2 件。README を直し、直した所だけを見る軽い再レビューで止める）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）
- 機械照合: 対象外

区分は v1 と同じ（A = 後の成果物の動作・API・契約が変わる、B = 検証の手段が変わる、C = 記述の整合だけ）。

---

## v1 の反映の確認

両方のレビュアーが、v1 の指摘（A-1〜A-10、B-1〜B-12、C-1〜C-10、不足 7 項目）を README の該当する節と照らした。

| 結果 | 項目 |
|---|---|
| 反映済み | A-2〜A-4、A-6〜A-10、B-1〜B-3、B-5〜B-12、C-1〜C-10、不足 7 項目 |
| 一部 | A-1（入れる関数の同期性と範囲が書かれていない → 下の A-1・A-2）、A-5 と B-4（署名の照らし方が実現できない → 下の B-5） |
| 採らなかった 1 件（段階 3 を 2c より先に） | 両方とも、却下の理由は成り立つとした。Codex は区分 C（表と本文の順の見え方）に下げた → 下の C-1 |

事実の再確認（両方）: `PreBuildProcessor.cs:477,704`、`PostBuildProcessor.cs:42-53,48,225`、`Tools/iOS/IosFrameworkPatcher.cs:40,130` は書いたとおり。Unity の `startUnity` は起動の後（scene の構成では `sceneWillEnterForeground` → `initUnityWithScene` → `startUnity`、scene の無い構成では `applicationDidBecomeActive`）。`ios/` に `Bundle(identifier:)`、os_log の subsystem、bundle id の文字列は無い（D-12 の影響は project の設定だけ）。D-6 は Android の設計書（1.3、5.x）の契約と一致する。

## 指摘と対応

### 区分 A

| ID | 出典 | 対象 | 指摘 | 対応 |
|---|---|---|---|---|
| A-1 | 両方 | D-4・D-6・3.1 | 3.2 で AC-4〜AC-6（main から呼ばれても積む）を引き継ぐので、`ntk_notification_install` も積む形に読める。そうすると delegate が入るのは `willFinishLaunching` から戻った後になり、守りたいコールドスタートのタップを取りこぼす | D-4 と D-6 に例外として書く: 入れる関数は main だけから呼べる同期の関数で、戻る前に proxy を強く持ち、`UNUserNotificationCenter.delegate` を設定し終える。main 以外から呼ばれたら積まずに同期のエラーを返す。`dispatch_sync` は使わない。2 回目以降の呼び出しは、前の delegate を proxy 自身で上書きしない |
| A-2 | Claude | D-4・3.1 | 「通知のイベントを受けるときだけ」入れる、としているが、前面にいるときの表示も delegate の `willPresent` で決まる（`IosNotificationManager.swift:327-331`）。1.x の Unity はいつも `notificationSetup` を呼んでいる。入れない C の利用者は、前面にいる間の通知が出なくなり、1.x から動作が変わる | 範囲を「通知の機能を使うなら（イベントと、前面での表示）」に直し、移行ガイドに書く |

### 区分 B

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| B-1 | Codex | 8.2 の delegate の試験が、D-7 で決める項目（3 つのメソッド、`responds(to:)`、前の delegate が completion を呼ばない場合）を網羅していない | 8.2 に組み合わせの表の軸を書く（メソッド 3 つ × 前の delegate の振る舞い × 通知の種類 × 入れる前後と後からの差し替え × `responds(to:)`） |
| B-2 | Codex | 0d は `UnityIosPluginTests` を基準に入れないとし、D-22 は 0d の時点で 83 件を記録するとしている | 「`test_ios.sh` の基準には入れないが、0e の直前に 83 件を一度流して `results/` に保存する」と書く |
| B-3 | Codex | 署名しない framework は、利用者のアプリで埋め込むときに署名し直される前提だが、アーカイブの中で確かめる手順が無い | 1a に Release のアーカイブを足し、`.app/Frameworks` の 2 つの framework を `codesign --verify --deep --strict` と Team ID で確かめる。可能なら Organizer の Validate App も行う |
| B-4 | Codex | 実行時のクラス名の確かめが `objc_getClass` の 1 つの名前だけ | `objc_copyClassList` と `class_getImageName` で `IosLibraryCApi` のクラスを全部挙げ、すべてが決めた接頭辞を持つことを照らす |
| B-5 | Claude | シミュレーターの arm64 はリンカーが必ず ad-hoc で署名する（`linker-signed`）ので、「全スライスに署名が無い」は照合で必ず落ちる（手元の clang で確かめた） | 照らす条件を、実機のスライスは署名が無い、シミュレーターは linker-signed の ad-hoc だけを許し Authority と TeamIdentifier が無い、に書き分ける |
| B-6 | Claude | 1a で本物の Unity に入れるとき、今の Pre / Post は `unity-ios-native-toolkit-` を必須にし、前方一致で capi を選ぶので、プラグインのビルドの経路では入らない | 1a では、書き出した Xcode プロジェクトに手で入れる（Unity と同じく Embed & Sign、`CodeSignOnCopy`）と書く。依頼の 3 つは 2b の前のまま |
| B-7 | Claude | Unity の通知パッケージも `kUnityWillFinishLaunchingWithOptions` で delegate を入れるので、どちらが後になるかはリンクの順で決まる。また Unity の `.mm` は、通知を使わないアプリでも delegate を入れる | 1a で、こちらが必ず後に入る形（`didFinishLaunching` の受け手など）も比べる。2c の申し送りに、入れるかどうかを利用者が選べる設定を入れる |
| B-8 | Claude | 0g で bundle id をそろえる範囲が決まっていない。サンプルのアプリの bundle id を変えると、7 章の更新のテストで 2.0.0 が上書きされず別のアプリになる。capi は 0g の時点でまだ無い | 0g で変えるのは framework の bundle id だけ（サンプルのアプリとテストのターゲットは変えない）。capi の bundle id は 2b で作るときに付ける |
| B-9 | Claude | 0e〜0g の各行は段階ごとに全件を流すと読め、7 章（全件は 0g の後と 1b の後）と食い違う | 各段は関係するテストだけ、全件は区切りで、に統一する |
| B-10 | Claude | 2c は `dist/<リリース版>` を使うが、リリース版を決めるのは段階 4 で、2c の後にある。Android は 2c の前に `dist/1.13.0` を作った | リリース版を決めて dist を作るのを 2b の終わりにする。依頼の時期もそれに合わせる |

### 区分 C

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| C-1 | Codex | 段階の表は 2c → 3 の順だが、本文は 3 を 2c より先にしてよいとしている | 「順番の理由」に依存の関係を書く（3 は 2b の後、2c とは独立。リリースは 2c と 3 の両方に依存） |
| C-2 | Codex | 「Swift の公開面が無い」が、D-10・D-11 で許す範囲（実行時の metadata）より強い | 「配る Swift のモジュールと interface、Swift 向けのヘッダーを持たず、利用者が import できる Swift の API を出さない。実行時の metadata は許す」にそろえる |
| C-3 | Claude | DoD に依頼の 3 つ目（development のビルド）が無い | DoD に足す |
| C-4 | Claude | 1a の行の「影響する決定」に D-4 と D-18 が無い | 足す |
| C-5 | Claude | D-4 の「Flutter はプラグインの AppDelegate」は不正確。プラグインは AppDelegate を持たず、`register(with:)` か `addApplicationDelegate` で入れる | 直す |
| C-6 | Claude | 1.4 と 5.2 の「黙って戻る」は不正確。`LogError` を出し、ビルドは止めずに埋め込まない（`PostBuildProcessor.cs:50-53,258-262`） | 直す |
| C-7 | Claude | D-11 (2) の接頭辞の付け方は D-10 の結果で変わる | 書く |
| C-8 | Claude | D-16 の「Xcode 26.0 は今の macOS 26.3 で動く」は確かめていない | 「未確認」を付ける |
