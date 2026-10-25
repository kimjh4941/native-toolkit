# リポジトリの大きさ（配布物とドキュメントの版ごとのコミット）

- 記録日: 2026-10-25
- 分類: リポジトリ運用（横断課題）
- 状態: 未着手
- 関連: `agent-rules/workflows/release/workflow.md`（dist の確認と `gh release create`）、`scripts/publish_docs.sh`（`docs/<版>` と `docs/latest`）、`scripts/check_android_dist.py`・`scripts/check_windows_dist.py`（dist の照合）

## 何が問題か

リリースのたびに、配布物（`dist/<版>/`）、API リファレンス（`docs/<版>/` と `docs/latest/`）、マニュアル（`manual/<版>/`）を版ごとに丸ごとコミットしている。版ごとのフォルダーは前の版を写して作るので、中身がほとんど同じでも作業ツリーは版の数だけ増える。git は一度コミットしたものを履歴から簡単には消せない。

今すぐ困ることは無い（GitHub のリポジトリの上限は 10 GB）。長く運用すると、上限より先に clone の時間と作業ツリーの大きさが効いてくる。

## 今の大きさ（2026-10-25、ブランチ `feature/NTKIT-18`）

| 測ったもの | 値 | 測り方 |
|---|---|---|
| GitHub の数字 | 約 126 MB（129,118 KB） | `gh api repos/kimjh4941/native-toolkit --jq .size` |
| 手元の履歴（圧縮後） | 127 MB（pack）、全オブジェクト 134 MiB | `git count-objects -vH`、`git rev-list --objects --all --disk-usage` |
| 作業ツリー | `docs/` 876 MB、`manual/` 393 MB、`dist/` 380 MB | `du -sh` |

圧縮後の履歴が作業ツリーよりずっと小さいのは、版ごとのフォルダーの多くが前の版と同じ中身で、git が同じ blob を 1 つにまとめているため。

圧縮後の履歴で大きいフォルダー: `dist/1.12.0` 46 MB、`docs/1.10.0` 29 MB、`docs/1.0.0` 6 MB、`windows/WindowsLibraryExample` 6 MB、`docs/1.13.0` 6 MB。

リリースごとの履歴の増え方（`git rev-list --objects --disk-usage <前のタグ>..<タグ>`）:

| 区間 | 増えた量 |
|---|---|
| 1.9.0 → 1.10.0 | 3.9 MiB |
| 1.10.0 → 1.11.0 | 2.0 MiB |
| 1.11.0 → 1.12.0 | 52.3 MiB（Windows の再編。DLL などの新しい配布物） |
| 1.12.0 → 1.13.0 | 11.9 MiB |
| 1.13.0 → 今 | 1.5 MiB |

1 リリースで数 MB〜50 MB ほど。このままでも 10 GB までは 100 回以上のリリースの余裕があるが、配布物のバイナリ（xcframework・AAR・DLL）は差分が効きにくく、OS や成果物が増えるほど 1 回の増え方が大きくなる（iOS 2.0.0 で xcframework が 2 つになる。[feature-split-distribution](../feature-split-distribution/README.md) で成果物を機能ごとに分けるとさらに増える）。

## 対応方針（案）

これから増やさない方から始める。過去の履歴を減らすには履歴の書き換え（`git filter-repo` など）と force push が要り、公開リポジトリでは clone した人やフォークへの影響が大きいので、最後の手段にする。

| 案 | 中身 | 良い点 | 気になる点 |
|---|---|---|---|
| A（第一の候補） | 配布物を GitHub Releases の添付にし、`dist/` に新しい版をコミットしない | リポジトリの容量に数えない。配布物の置き場として一般的 | 今は dist をコミットして照合（`check_*_dist.py`）、2c の検証、マニュアルの依存の照合に使っている。手元で作った dist を照合してから添付する流れに変える必要がある。`unity-native-plugin` が dist を参照していないかも確かめる |
| B | ドキュメント（`docs/`）を公開用のブランチか別のリポジトリに移し、履歴を持たない形で更新する | `main` の履歴が増えない | 今は GitHub Pages が有効でない（API が 404）。どこで公開しているか、`publish_docs.sh` と `docs/latest` の使われ方を確かめてから決める |
| C | Git LFS | 手軽 | LFS にも容量と転送の上限があり、公開リポジトリで clone する人にも LFS が要る。優先は低い |
| D | 古い版の `manual/` と `docs/` をリポジトリから消す（履歴には残る） | 作業ツリーと clone の後のチェックアウトが軽くなる | 履歴は減らない。古い版を読む人への案内が要る |

## 着手するときに確かめること

- dist を使っている所の全部（リリースの手順、照合のスクリプト、マニュアル、`unity-native-plugin`、移行の手引き）
- `docs/` の公開先と、`docs/latest` を参照している所
- 着手の時期: 今は ios-c-abi の作業中なので、その後に行う。案 A は、配布物の形が変わる [feature-split-distribution](../feature-split-distribution/README.md) と合わせて決めるのがよい
