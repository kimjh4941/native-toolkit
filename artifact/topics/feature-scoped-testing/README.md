# 変えた機能のテストだけを流せるようにする（全 OS）

- 記録日: 2026-10-10
- 分類: テスト基盤（横断課題）
- 状態: 未着手
- 関連: [feature-split-distribution](../feature-split-distribution/README.md)（機能ごとの配布物。境目が同じ）、[android-c-abi](../android-c-abi/README.md)（2b のレビューの対処で、関係するテストだけを流して確かめた）

## 何が問題か

全件の実行は時間がかかり、端末も占有する（Android は両方の端末で数時間）。利用者の方針は「全件は本当に要るとき（DoD、基準の取り直し）だけ。ふだんは変えたところに関係するテストだけ」（2026-10-10）。今は、関係するテストを人（エージェント）が毎回選んで、絞り込みの引数を手で組み立てている。機能の名前、または変えたファイルから、その機能のテストをまとめて流せる口があれば、選び漏れが減り、早く確かめられる。機能が増えるほど効く。

## 今あるもの

| OS | テストのスクリプト | 絞り込み | 機能ごとに分かれているもの |
|---|---|---|---|
| Android | `scripts/test_android.sh` | `--filter <Category>`（サンプルの UI テストのカテゴリ）、`HostState`・`Library`・`Probe`・`CApi`（決まった区分）。Gradle の `tests_regex` は手で渡す | C ABI の GoogleTest の名前（`Clipboard.*`、`Share.*` など）、サンプルの UI テストのカテゴリの印、Kotlin の単体テストのパッケージ（`...clipboard` など） |
| Windows | `scripts/test_windows.ps1` | `-Filter`（dotnet test のフィルター。例: `TestCategory=Notification`） | UI テストの `TestCategory` |
| iOS / macOS | 共通のスクリプトは無い（`xcodebuild test -scheme ...` を手で流す） | `xcodebuild` の `-only-testing:` | テストのクラス |

## 足すもの（案）

- **機能の名前で絞る口**: 機能の名前 1 つ（例: `--feature Share`）で、その OS のすべての層のテスト（C ABI、ライブラリの単体と計装、サンプルの UI）をまとめて選ぶ。今の OS ごとの絞り込み（`--filter`、`-Filter`、`-only-testing:`）に写す
- **変えたファイルから機能を引く口**: `git diff` のパスから機能を決める対応表（例: `.../Clipboard/`、`.../clipboard/` は Clipboard）。対応表に無いパスは、安全のため全機能にする
- **いつも入れるもの**:
  - 共通の部分（Android なら登録の表、初期化、JNI、帳簿。Windows なら C ABI の共通部分）を変えたら、その OS の全機能
  - 機能をまたぐテスト（初期化の前の全操作、main を待たない、公開面の照合）は、どの機能を変えても入れる
- **全件の実行は残す**: 対応表の漏れを拾う最後の砦として、DoD と基準の取り直しでは全件を流す（今の方針のまま）

## 対応方針（案）

- 対応表は、機能の一覧（Clipboard、Dialog、Notification、Share など）を全 OS で同じにして、OS ごとにパスとテストの名前の形だけを持つ
- 着手は Android と Windows から（スクリプトがあり、テストの名前が機能ごとに分かれている）。iOS / macOS は、テストのスクリプトを作るところからになるので、C ABI 化（[feature-split-distribution](../feature-split-distribution/README.md) と同じく、ほかの OS の C ABI 化が先）と合わせる
- 機能ごとの配布物（feature-split-distribution）と境目（共通部分と機能ごと）が同じなので、対応表はそちらと共有できる形にする

## 着手するときに確かめること

- Android: GoogleTest の名前、Kotlin のパッケージ、サンプルのカテゴリで、機能の名前がそろっているか（そろっていなければ、名前の対応も表に持つ）
- Windows: C ABI のテスト（`WindowsLibraryCApiTest`）と C++ のテストに、機能ごとの絞り込みの印があるか
- 絞った実行の結果を、基準と比べるときの扱い（今の Android と Windows は、絞った実行では消えたケースを失敗にしない。この扱いのままでよいか）
