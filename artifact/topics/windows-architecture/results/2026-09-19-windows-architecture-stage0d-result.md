# 段階 0d 結果: 検証スクリプトと基準の結果

- 実施日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 0d、`designs/2026-09-19-windows-architecture-ui-test-design.md` の 8 章
- ブランチ: `feature/NTKIT-16`
- 対象のコード: `e6185b1b`

## 1. 作ったもの

| ファイル | 内容 |
|---|---|
| `scripts/test_windows.ps1` | ユニットテスト、サンプルのビルドと配置、UI テスト、OS の設定の確認、基準との比較を 1 回で行う（設計書 8 章） |
| `scripts/test_windows.baseline.json` | 基準の結果。テストごとの結果（200 件）と、記録した日時とコミット |

段階 1 〜 6 では、段階の終わりに `powershell -File scripts\test_windows.ps1` を実行する。基準と結果が違うテストがあれば、スクリプトが一覧にする。基準は、動作を変えると決めた段階（3 以降で API が変わるときなど）で、確かめたうえで `-Baseline` で保存し直す。

## 2. 基準の結果（2026-09-19 14:51）

`powershell -File scripts\test_windows.ps1 -Baseline` の結果。

| 部分 | 件数 | 結果 | 所要時間 |
|---|---|---|---|
| ユニットテスト（`WindowsLibraryTest`、Debug） | 106 | すべて成功 | — |
| UI テスト（`WindowsLibraryExampleUITest`、サンプルは Release） | 94 | 93 件成功。1 件（履歴の `Clear`）は既定どおり実行されない（`NotExecuted`） | 8 分 17 秒 |
| 全体 | 200 | 失敗 0 | 8 分 36 秒（ビルドと配置を含む） |

テストが切り替えた OS の設定は、すべて元に戻った（記録のファイルが残っていない）。

基準は `-IncludeDestructive` を付けずに保存した。付けて実行すると、履歴の `Clear` は「結果が変わった」（`NotExecuted` → `Passed`）と表示される。

## 3. 確かめたこと

| 確認 | 結果 |
|---|---|
| ユニットテストと Dialog の UI テストだけの実行（`-Filter "TestCategory=Dialog"`） | 119 件成功（4 分 56 秒。ビルドを含む） |
| 全件の実行と基準の保存（`-Baseline`） | 2 章のとおり |
| 基準との比較（`-SkipUnitTests -Filter "TestCategory=Dialog"`） | `Same outcomes as the baseline` と表示された。絞った実行では、基準にあって実行しなかったテストは「無くなった」と数えない |
| 配置 | `.appxrecipe` の 15 件のうち 13 件をコピーし（2 件は元から AppX のフォルダの中）、登録先が今のビルドの AppX のフォルダであることを確かめた |
| 画面のロック | 開始時と、ビルドの後の UI テストの前に確かめる。ロック中は入力のデスクトップが `Default` でなくなることで判定する |

## 4. 段階 0b・0c から持ち越したことの対処

| 持ち越したこと | 対処 |
|---|---|
| 画面の消灯とスリープの抑止（段階 0b の結果の 4 章） | 実行中だけ `SetThreadExecutionState(ES_CONTINUOUS \| ES_SYSTEM_REQUIRED \| ES_DISPLAY_REQUIRED)`。終わったら `ES_CONTINUOUS` だけに戻す。今回の 8 分の実行で画面は消えなかった |
| 画面がロックされていたら止める | 3 章のとおり |
| テストの件数と所要時間の記録（段階 0c の結果の 5 章） | 2 章のとおり |
| CU-01 の初回の実行 | **合格**（5 章） |

## 5. CU-01（computer use）

Claude のデスクトップアプリ（Code タブ、このリポジトリのフォルダ、ワークツリー無し）から、`windows/WindowsLibraryExampleUITest/ComputerUse/CU-01-hero-image.md` の手順で実行した。

| 項目 | 内容 |
|---|---|
| 判定 | **合格** |
| 理由 | 「Native Toolkit Example」のグループに、タイトル `With Image`、本文 `Toast with hero image` の通知があり、画像が手順書 2 章の見え方と一致した（灰色の枠の上半分と、左上・右上から中央の下で交わる 2 本の斜線）。判定に迷った点は無い |
| サンプルの表示 | `✅ [InitializeManager] initialized. setting=0`、`✅ [ShowWithImage] errorCode=0` |
| スクリーンショット | `windows/WindowsLibraryExampleUITest/ComputerUse/evidence/CU-01/2026-09-19-0d.png`（327×292。通知 1 件だけ。画面は 1920×1080）。段階 0c で FlaUI で撮影した大きさ（334×295）とほぼ同じ |
| 後片付け | RemoveAll は `errorCode=0`。サンプルのプロセスは終了した |

手順と違ったことと、手順書への反映:

| 違ったこと | 影響 | 手順書への反映 |
|---|---|---|
| アプリを起動する操作を 2 回行い、サンプルのウィンドウが 2 つ開いた | 無し（操作したのは 1 つ。後片付けで両方閉じた） | 手順 1 に「起動の操作は 1 回だけ」と、開いてしまったときの扱いを足した |
| computer use の権限で、通知センターに `Esc` を送れなかった | 無し（サンプルのウィンドウをクリックして閉じた） | 手順 11 に、その場合の閉じ方を足した |
| 集中モードがオンだった | 無し（前提で「どちらでもよい」としている） | 変更無し |
