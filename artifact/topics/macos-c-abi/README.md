# macOS の汎用 C ABI

- 分類: アーキテクチャ（横断課題。機能追加ではない）
- 状態: **企画中**（2026-11-22。調査が済み、企画を書いた。Claude と Codex のレビューを 3 回通し、v3 で区分 A が 0 になった。D-1〜D-24 が決まった（2026-11-22、利用者。D-21 は利用者の案: 15 は VM の 15.8.3、26 はこの Mac で、どちらも各メジャーの最新の版。27 は対応予定）。実装には着手していない）
- チケット: NTKIT-19（ブランチ `feature/NTKIT-19` の名前から。中身は未確認）
- 手本: [ios-c-abi](../ios-c-abi/README.md)（1.14.0、iOS 2.0.0）

## 要約

Windows・Android・iOS と同じ汎用の C ABI（`ntk_*`）を macOS に作る。`UnityMacPlugin`（Objective-C の `.m` の Unity 専用の 44 関数）のロジックを `MacLibrary` へ移し、`@c @implementation` で書く dynamic の `MacLibraryCApi` を足して、`UnityMacPlugin` を消す（macOS 2.0.0）。iOS の規約と作り方をほぼそのまま使い、macOS で決め直すのは主に次のもの:

- Dialog がアプリ全体のモーダル（`runModal`）で main を塞ぎ、開いている間ほかの完了と取り消しが止まりうること（D-8。0e の前に 1a で測って決める）
- Share のピッカーが基点の view と mouseDown の文脈を要ること
- 通知の delegate を起動の中で入れる口が Unity の macOS のプレイヤーにあるか（D-4、D-24）
- 版付きの framework、symlink、Library Validation と署名し直し（D-9〜D-11、D-18）
- シミュレーターが無く、テストがこの Mac の上で私物（一般の貼り付け板、通知センター、画面）に触れること（D-21、D-23）

## 次にすること

1. ~~D-16 を決め直すか~~ → 決め直さない（2026-11-22、利用者。26.3 以上のまま。15 の VM で Xcode 26.3 を使うので、ソースが 26.3 で組めることはどのみち保たれる）
2. `unity-native-plugin` に macOS の版の固定を頼む（次にどの OS でも `dist/` を作る前に。企画 5 章）→ **頼んだ**（2026-11-22、利用者の指示でセッション `unity-native-plugin-cd` に。企画 5 章の 1〜4 をまとめて送り、1 は急ぎ、2〜4 は 2b で dist を置く前と伝えた）。**1〜3 は済んだ**（向こうの `feature/UNT-15` の `cbdf82c`、push の前。`Plugins/macOS/VERSION.txt` に `dist_version: 1.14.0` と `unity-mac-native-toolkit-1.3.0.xcframework` を書き、名前が dist に無ければビルドを止める。3 か所の探索は `VERSION.txt` との完全一致で、2.0.0 では `xcframeworks` に 2 つの名前を並べる。`-debug` の扱いは共通の手順に寄せた。EditMode 1601 件中 1600 件が通り、skip 1）。4 も済んだ（`b1367a8`、`cbdf82c` の上。push の前。向こうの記録は `artifact/topics/macos-c-abi-handoff/README.md`）。**依頼と違う結果**: Unity 6000.4.2f1 の Package Manager は、git の URL で入れたパッケージを `Library/PackageCache` に置くときに symlink をすべて落とす（git に mode 120000 で入っていても）。そのため向こうは、書き出しへのコピーの後に版付きの framework の symlink を作り直す形にした（`MacFrameworkLinks.cs`。版のフォルダーが 1 つで、上の階の項目が `Versions/<版>` と同じ名前のときだけ。入れ子の framework も対象）。こちらは dist に今までどおり symlink のある形で置けばよい。あわせて、書き出しの Xcode のプロジェクト名（`<書き出し先のフォルダー名>.xcodeproj`）を決め打ちしない形にも直した（企画 5.2 では 2c の項目だった）。確かめは試しの版付きの xcframework と本物の 1.3.0 で、リポジトリの形と git の URL の利用者の形の両方で `xcodebuild` が通り、`.app` 全体で `codesign --verify --deep --strict` が通った（EditMode 1607 件中 1606 件、skip 1）。残りは本物の 2.0.0 での通し（dist を置いてから）と IL2CPP（2c）。**出し済みの 1.3.0 の不具合**: 1.10.0〜1.14.0 の `unity-mac-native-toolkit-1.3.0` を埋め込んだ `.app` は、`codesign --verify --strict` が「bundle format is ambiguous」で通っていなかった（`rsync -aL` の symlink の実体化による。向こうの作り直しで直る）。向こうの気づき: `dist/1.14.0/mac` の 2 つのバイナリのファイルのモードが、向こうは 100755、こちらは 100644 で、git の木のハッシュが違う（中身は同じ）。リリースの照合で木のハッシュを比べるときに当たる（2b で dist を作るときに扱いを決める）
3. この Mac を macOS 26.7.3 に上げる（利用者が行う。0d で基準を取る前に。D-21）→ **済んだ**（2026-11-22。Xcode 26.3・26.6 とも動くことを確かめた）
4. `agent-rules/device-testing.md` に macOS の節を書き（D-23）→ **書いた**（2026-11-22）。次は段階 0a と 1a-前（0e の前に終える）
5. 段階 0a と 1a-前（2026-11-22 夜〜11-23、自律で進めた。`results/2026-11-22-macos-c-abi-stage0a-working-notes.md`）: 15 の VM を 15.8.3 にした（元の 15.4.1 では更新が当たらず、Cirrus Labs の 15.7.7 から作り直した）。0a の XCUITest のスパイクは通知・共有・Dialog・パネル・貼り付けのすべてを扱えた。1a-6（Dialog）は A' で基準を満たす見込み、1a-7（Share）は main に積んでも出た、1a-8（通知の起動）は P1-22 の規則が成り立った。**1a-9（Unity）の申し送りを送った**（2026-11-23 4 時ごろ。`results/2026-11-23-macos-c-abi-unity-handoff-1a9.md`、雛形は `results/probes/1a9-unity-handoff/`、レビュー v1〜v3 で区分 A が 0。OS の更新の再起動で向こうのセッションの名前が `unity-native-plugin-8f` に、こちらは `native-toolkit-89` に変わった。返事待ち）。次は UI テストの設計書（0b の前）

## 文書

| 文書 | 中身 |
|---|---|
| [plans/2026-11-22-macos-c-abi-plan.md](plans/2026-11-22-macos-c-abi-plan.md) | 企画: 調べたこと、何が問題か、なぜ今やるか、目標の構成、Swift の API の方針、段階、公開面の規模、検証方法（章の番号は iOS の README に合わせた） |
| [plans/2026-11-22-macos-c-abi-decisions.md](plans/2026-11-22-macos-c-abi-decisions.md) | 決めること（D-1〜D-24）、1a で確かめること、ツールチェーンの版、決めないこと、出典、設計で決めること |
| [plans/2026-11-22-macos-c-abi-dod.md](plans/2026-11-22-macos-c-abi-dod.md) | DoD |
| `reviews/2026-11-22-macos-c-abi-plan-review-v{1,2,3}.md` | 企画のレビュー（Claude と Codex の 2 者、3 回。v3 で区分 A が 0） |
| [results/2026-11-22-macos-c-abi-ios-lessons.md](results/2026-11-22-macos-c-abi-ios-lessons.md) | iOS から引き継ぐ知見と、macOS で新しく分かったこと |
| `results/2026-11-22-macos-c-abi-survey-{a-surface,b-ios-carryover,c-prerequisites,d-toolchain}.md` | 企画の調査の全文（今の公開面、iOS からの引き継ぎ、macOS の前提、ツールチェーンとテストの基盤） |

この課題は `topic-document-size` の案に沿って、README には状態とリンクだけを置く。段階の経過は、この README の状態の行と `results/` の作業の記録に書き、企画の段階の表には書き足さない。

## 関連

- [ios-c-abi](../ios-c-abi/README.md) と [終わりの記録](../ios-c-abi/results/2026-11-22-ios-c-abi-closing.md)（3 章の 14: `unity-native-plugin` の macOS の版の固定をこの課題に回した）
- [android-c-abi](../android-c-abi/README.md)、[windows-architecture](../windows-architecture/README.md)（規約の出典）
- [migration](../migration/README.md)（macOS の Swift 6。D-14 で統合する）
- [bridge-testing](../bridge-testing/README.md)（残りは macOS の `UnityMacPlugin`。C ABI のテストで置き換える）
- [memory-sanitizers](../memory-sanitizers/README.md)（macOS の ASan / TSan）
- [feature-split-distribution](../feature-split-distribution/README.md)、[feature-scoped-testing](../feature-scoped-testing/README.md)（どちらも全 OS の C ABI の後、または macOS の C ABI と合わせる）
- [topic-document-size](../topic-document-size/README.md)（この課題の文書の形）
- `agent-rules/device-testing.md`（macOS の節を足す。D-23）、`agent-rules/coding-rules/mac.md`（ログの規則の例外を 1b の前に足す。Objective-C の節を段階 3 で外す）
