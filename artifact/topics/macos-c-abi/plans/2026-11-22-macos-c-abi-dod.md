# macOS の汎用 C ABI: DoD

- 記録日: 2026-11-22
- 企画: `2026-11-22-macos-c-abi-plan.md`、決定: `2026-11-22-macos-c-abi-decisions.md`
- 書き方: 済んだら `[x]` にし、確かめた日と記録（`results/` のファイルと章）を 1 行で添える。経過は書き足さない（作業の記録に書く）

## 企画と決定

- [x] この企画（plan・decisions・dod）のレビューで区分 A が 0 になっている（2026-11-22。Claude と Codex の 2 者で 3 回。`reviews/2026-11-22-macos-c-abi-plan-review-v1〜v3.md`）
- [x] D-1〜D-24 を決める（2026-11-22。D-21 のほかは推奨のとおり、D-21 は利用者の案（15 は VM の 15.8.3、26 はこの Mac））
- [ ] 条件付きの決定（D-4・D-6・D-7・D-8・D-24）を、1a-前（決定の文書の 8.2）の結果で 0e の前に確定している
- [ ] 0e・0f の後に 1a-6 の測り（出し方 A のまま）を流し直し、Dialog の間のほかの完了と取り消しの振る舞いが 0e の前と変わっていない
- [x] `agent-rules/device-testing.md` に macOS の節（D-23）があり、0a の前に書いた（2026-11-22）

## テストをそろえる（段階 0）

- [ ] 段階 0a のスパイクで、XCUITest と人の確認の分担を確定する（`common.md` の例外にした項目は理由を記録している）。D-21 の VM が使えるかも確かめた
- [ ] Clipboard / Dialog / Notification / Share のすべてにサンプルの UI テストがあり、通知のクリックからのコールドスタートを含む（段階 0c。UI テストの設計書の 95 件。コールドスタートは NC1〜NC3。この Mac で保留したテスト（`MAC_DEFERRED_TESTS`）は、U-30 の適格性の段の結果で解くか、理由つきで基準の `excluded` に記録している）
- [ ] `scripts/test_mac.sh` があり、私物に触れるテストを区分で選び（宣言の正しさを照らし）、毎回の許可を求める。今のコードの結果を D-21 の環境で基準として記録している（段階 0d）
- [ ] `UnityMacPluginTests` の 75 件を 0e の前に一度流し、結果を `results/` に保存している（D-22）
- [ ] `MacLibrary` とサンプルが Swift 6 の言語モードと strict concurrency complete で、警告が 0（段階 0e・0f。UI テストのターゲットは D-14 の例外）。公開 API の差分を `results/swiftinterface/` に記録している
- [ ] 0e〜0g と 1b の前後で、サンプルの UI テストの結果が変わらない（変えたテストは理由を記録している）

## Swift の API（段階 1）

- [ ] 段階 1a のスパイクで決定の文書の 8.2 を確かめる。本物の Unity の macOS の release ビルドで、雛形を呼び、起動の中で delegate を入れ、通知のクリックからのコールドスタートを受けている
- [ ] UI テスト・C ABI（2 部）・Swift の API の設計書を書き、別のモデルのレビューを通す（UI テストの設計書は 2026-11-23 に決定。レビュー v1〜v5、v5 で区分 A が 0）
- [ ] 1.2 のロジックがすべて `MacLibrary` にあり、ブリッジのテストのうち移すロジックに当たるものを書き直して通している（段階 1b）
- [ ] Dialog のヘルプで完了が 2 回来ない。Dialog のテストがある
- [ ] ログに秘密の値が出ない（`mac.md` に規則があり、テストで確かめる）
- [ ] 通知の delegate が前の delegate に転送し、ホストの通知が壊れない。起動の終わりまでに入れる関数でコールドスタートのクリックが届く（段階 1b のテストと 1a / 2c の Unity）
- [ ] bundle の無いプロセスで通知の関数が落ちずにエラーを返す
- [ ] 1.x（1.14.0 のサンプル）から 2.0.0 への更新のテストで、予約した通知・category・表示中の通知が壊れない（起動したコピーの道を記録している）
- [ ] 同じ main の回に続けて出した 2 つ目の表示（Dialog・ファイルのパネル・Share）にも、完了がちょうど 1 回来る（iOS の SH-13 に当たる）。Dialog が開いている間のほかの機能の完了と取り消しが、D-8 で決めた契約のとおりに届く（1b の後に Swift の経路で、2b の後に C の入口で）
- [ ] Xcode 26.6 で組んだ dist の `MacLibrary` の swiftinterface を、利用者の下限の Xcode 26.3 で読める（`import MacLibrary` で組める）
- [ ] 理由の申告が要る API を使っていない（1b の終わりの棚卸し。使っていたら D-18 を決め直す）

## C ABI（段階 2）

- [ ] `MacLibraryCApi` が企画 6 章の振る舞いの集合をすべて公開している（2a の機械照合）
- [ ] `check_mac_dist.py` の全項目（企画 7.3）が通る。公開シンボルが `ntk_*` だけで、capi が Swift のモジュール・interface・ヘッダーを配らず、版付きの構成の symlink があり、両方のアーキテクチャの minos が 15.0 で、署名が D-18 のとおり
- [ ] sandbox の C のホストで、ファイルのパネルの結果のパスを後から読めること、そのファイルを非同期の Share に渡せることを、最後の dist で確かめている（決定の文書の 8.6 の契約）
- [ ] macOS 15.8.3 の VM でサンプルの単体テスト・UI テストが通り、この Mac で組んだ dist の smoke（と、流せるなら C ABI のテストの束）が動く。確かめていない範囲（15.0〜15.8.2）と、macOS 27 は対応予定であることを、マニュアルとリリースの記録に書いている
- [ ] `ntk_notification_install` が、main から呼ぶと戻る前に delegate を設定し終え、main 以外からは同期のエラーを返す
- [ ] smoke が dist の 2 つの xcframework だけで組めて、arm64 と Rosetta の x86_64 で動く。利用者の下限の Xcode 26.3 でも組める。Hardened Runtime と sandbox の組み合わせ（企画 7 章）で起動する
- [ ] 照合のスクリプト（`check_c_abi_contract_mac.py`、`check_manual_c_examples_mac.py`、`check_mac_dist.py`）が通り、Windows・Android・iOS の照合も通る。照合の自己テストが、規則を 1 つずつ壊すと落ちる。`IosLibraryCApi/Common` と `MacLibraryCApi/Common` の写しの一致を照らしている
- [ ] C ABI のテストが通常・ASan・TSan で通る（企画 7.4）。足したテストは、守る対象を壊すと落ちることを確かめている
- [ ] `unity-native-plugin` が、版の固定（次の dist の前）と、完全一致の探索・development ビルドの埋め込み・symlink を保つコピー（2b で dist を置く前）を入れ、2c で C ABI を呼ぶ形に移り、macOS のテストを通している（別リポジトリ）
- [ ] 最後の dist で、パッケージ → git の URL で入れた `PackageCache`（Package Manager は symlink を落とす）→ AssetDatabase → 書き出し（コピーの後に作り直す）→ 最後の `.app` で framework が symlink を持ち、署名し直されて `codesign --verify` が通る。backend（Mono / IL2CPP）・Unity の版・アーキテクチャごとの表で、コールバック・`release`・GC を挟んだ寿命・通知の起動を確かめている

## 片付けとドキュメント（段階 3・4）

- [ ] `UnityMacPlugin` がリポジトリに残っていない（プロジェクト、スクリプト、README、ルール、`dist/` の新しい版）
- [ ] マニュアルの macOS の節に C ABI と 2.0.0 の移行ガイド（署名し直しと Hardened Runtime の注意を含む）があり、3 言語で一致している
- [ ] C ABI の Doxygen が `docs/<リリース版>/mac` にある

## 確かめないと決めたもの

- Developer ID での署名と公証（Apple Developer Program の登録が要る。D-18）。署名し直しは開発用の証明書と ad-hoc で確かめる
