# macOS の汎用 C ABI

- 分類: アーキテクチャ（横断課題。機能追加ではない）
- 状態: **企画中**（2026-11-22。調査が済み、企画を書いた。Claude と Codex のレビューを 3 回通し、v3 で区分 A が 0 になった。D-21 のほかは推奨のとおりに決まった（2026-11-22、利用者）。D-21（試験の環境）は話し合い中。実装には着手していない）
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

1. D-21（試験の環境）を決める。ほかの D-n は推奨のとおりに決まった（2026-11-22。レビューは `reviews/2026-11-22-macos-c-abi-plan-review-v1〜v3.md`。v3 で区分 A が 0）
2. `unity-native-plugin` に macOS の版の固定を頼む（次にどの OS でも `dist/` を作る前に。企画 5 章）→ **頼んだ**（2026-11-22、利用者の指示でセッション `unity-native-plugin-cd` に。企画 5 章の 1〜4 をまとめて送り、1 は急ぎ、2〜4 は 2b で dist を置く前と伝えた）。**1〜3 は済んだ**（向こうの `feature/UNT-15` の `cbdf82c`、push の前。`Plugins/macOS/VERSION.txt` に `dist_version: 1.14.0` と `unity-mac-native-toolkit-1.3.0.xcframework` を書き、名前が dist に無ければビルドを止める。3 か所の探索は `VERSION.txt` との完全一致で、2.0.0 では `xcframeworks` に 2 つの名前を並べる。`-debug` の扱いは共通の手順に寄せた。EditMode 1601 件中 1600 件が通り、skip 1）。4（symlink を保つコピー）は作業中。向こうの気づき: `dist/1.14.0/mac` の 2 つのバイナリのファイルのモードが、向こうは 100755、こちらは 100644 で、git の木のハッシュが違う（中身は同じ）。リリースの照合で木のハッシュを比べるときに当たる（2b で dist を作るときに扱いを決める）
3. `agent-rules/device-testing.md` に macOS の節を書き（D-23）、段階 0a と 1a-前（0e の前に終える）に入る

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
