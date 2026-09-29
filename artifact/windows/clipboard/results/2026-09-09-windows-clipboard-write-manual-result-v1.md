# write-manual 実行結果 v1（Windows Clipboard / manual 1.11.0）

## 基本情報

- 日付: 2026-09-09
- 機能名: Windows Clipboard Manager
- 対象マニュアル: `manual/1.11.0/`
- ブランチ: `feature/NTKIT-13`
- 実行環境: Windows 11 Home 10.0.26200
- ソース: `2026-07-30-windows-clipboard-implementation-feature-result-v4.md`、`2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`

## 1. 状態: 完了

| ステップ | 内容 | 状態 |
|---|---|---|
| 1-2 | 対象確定、1.10.0 を 1.11.0 へコピーしてベースラインコミット | 完了（`f0ddb084`） |
| 3-4 | ソース読み込みと実装との照合 | 完了（矛盾なし。第 3 章） |
| 5-6 | マニュアル生成（en / ja / ko） | 完了（`bf13246a`） |
| 7 | `index` 3 言語の更新 | 完了 |
| 8 | `README` 3 言語の更新 | 完了 |
| 9 | 実行確認 | 完了（採用） |
| **10** | **`docs/` への公開** | **完了（`5e972e25`、macOS 側で実施。第 5 章）** |

## 2. 生成内容

`clipboard.md` / `.ja.md` / `.ko.md` に Windows 節を追加した。公開関数 27 個すべてを、サンプル画面と同じ順序（Setup → 初期化/ライフサイクル → コピー → 書き込みオプション → 貼り付け → 検査/クリア → 遅延レンダリング → 履歴 → エラー処理）で記載している。コード例のリテラルは `WindowsLibraryExample` から取得した。

シグネチャから読み取れない契約を明記した。

- オーナー UI スレッドは STA かつメッセージポンプが必要
- プロセス終了前に `uninitClipboardManager` を呼ばないと予約した遅延形式が失われる
- `onHistoryEnabledChanged` / `onRoamingEnabledChanged` は信頼できない
- クリップボード履歴が有効なとき、プロバイダーは外部貼り付けより先に呼ばれる
- サイズ問い合わせが返す `BUFFER_TOO_SMALL`(7) は正常な経路

索引では Windows の機能一覧に clipboard を追加し、**「追加予定機能」節を削除**した（4 OS すべてが対応済みになったため）。バージョン参照は 1.10.0 → 1.11.0、Windows ライブラリは 1.1.0 → 1.2.0 へ統一した。

### 2.1 スクリーンショット

1 枚のみとした。`Example_WindowsClipboardManager.png`（897x746px、表示幅 800px）。

macOS の判断（`0f4cf702`「a clipboard has no appearance」）を適用した結果である。macOS が 2 枚なのは PasteButton という可視コントロールがあるためで、Windows にはこれに相当するものがない。Win+V はシェルの UI でありライブラリの成果物ではない。

| プラットフォーム | 画像数 |
|---|---|
| Android | 10（旧方針のまま） |
| iOS | 30（旧方針のまま） |
| macOS | 2（Overview + PasteControl） |
| Windows | **1（Overview のみ）** |

## 3. ステップ4 の照合結果: 矛盾なし

| 照合項目 | 記載 | 実測 | 判定 |
|---|---|---|---|
| 変更ファイル（機能実装結果 v4 §2.1/2.2） | 16 ファイル | 16 ファイル実在 | 一致 |
| 単体テスト件数 | 106 | 106（`TEST_METHOD` 総数） | 一致 |
| エラーコード | 変更なし | ヘッダーに 0〜19 の 20 種 | 一致 |
| 公開 API | 27 関数 | `.def` の全 39 関数が DLL に存在 | 一致 |

## 4. verify_manual の結果: 新規の指摘は 0 件

コピー元の 1.10.0 と**完全に同一**である。

| 検査 | 1.10.0（継承元） | 1.11.0（現在） | 差分 |
|---|---|---|---|
| 1 画像参照 | FAIL 30 | FAIL 30 | なし |
| 2 サンプル整合 | WARN 2 | WARN 2 | なし |
| 3 アンカー | FAIL 5 | FAIL 5 | なし |
| 4 成果物名 | OK | OK | なし |
| 5 文体 ja/ko | WARN 2 | WARN 2 | なし |
| 6 言語差分 | WARN 14 | WARN 14 | なし |
| 7 索引の機能一覧 | OK | OK | なし |

**停止項目 35 件（画像 30 / アンカー 5）はすべて develop から引き継いだもので、今回の作業に由来するものは 1 件もない。** 内訳は macOS notification の画像参照と notification のアンカーである。

`/release` のステップ3ではこの 35 件により「manual 整合」が ❌ になる。上記の比較が、ワークフローが求める「今回のリリースで作り込んだものか、前バージョンから引き継いだものか」の区別にあたる。

## 5. ステップ10 を macOS で実施する理由

この作業ツリー（Windows）では実行できない。理由は 2 つある。

**(1) `docs/` が sparse-checkout で除外されている**

```
$ git config core.sparseCheckout
true
$ git sparse-checkout list
/*
!/docs/
```

`docs/` 配下の 32,742 ファイルすべてが skip-worktree であり、作業ツリーに展開されていない。ここで書き込んでも正しくコミットできない。

**(2) 4 OS 中 3 OS の生成ツールが存在しない**

| ツール | 用途 | Windows 環境 |
|---|---|---|
| doxygen | Windows API | あり |
| gradle | Android（Dokka） | なし |
| xcodebuild | iOS / macOS（DocC） | なし |

`publish_docs.sh` は `--os windows` を指定してもコピー段階が全体に対して走り、`rm -rf` の後に存在する出力だけを集める。この環境で実行すると **Windows とマニュアルだけの `docs/1.11.0` ができ、それが `docs/latest` を置き換える**。Android / iOS / macOS のドキュメントが失われる。

### 5.1 Windows 側で実施済みの分

`windows/WindowsLibrary/docs` は追跡対象（329 ファイル）であり、clipboard ヘッダー追加後に再生成されていなかったため、この環境で doxygen を実行してコミットした（`e15d4d69`、338 ファイル変更）。公開関数 27 個すべてがページに掲載されていることを確認済み。

**macOS に doxygen が入っていなくても `publish_docs.sh` は `[skip]` して進むため、この生成物がそのままコピーされる。**

### 5.2 macOS 側での実施結果

`5e972e25 docs(release): publish the 1.11.0 documentation site`（5,000 ファイル）で完了した。

| 確認項目 | 結果 |
|---|---|
| `docs/1.11.0/` の構成 | android / ios / mac / manual / windows |
| `docs/latest/VERSION.txt` | `1.11.0` |
| Windows の clipboard ページ | 115 ファイル（5.1 でコミットした生成物がコピーされた） |
| マニュアルの Windows 節 | 反映済み |

## 6. 環境に起因して修正した事項

Windows でチェッカーが動作しなかったため、リポジトリ側を修正した（`a14606a5`、`7ad27f0c`）。

| 問題 | 内容 | macOS |
|---|---|---|
| `python3` の解決先 | Microsoft Store のエイリアスに解決され、コードを実行せず exit 49。`verify_manual.sh` は検査を 1 件も走らせないまま成功を報告していた | 実体を指すため発生しない |
| 既定エンコーディング | cp932 のため UTF-8 のマニュアルを読めない | UTF-8 のため発生しない |
| `SOURCE_ROOTS` の機能名キー | 全 clipboard 設計書が macOS のソースへ振り分けられ、Windows 設計書が誤検出されていた | 偶然一致するため顕在化しない |
| `"/Build/"` の部分一致除外 | パス区切りが `\` のため何も除外していなかった | 発生しない |

いずれも macOS の挙動は変えていない。

## 7. 残作業

`/release`（feature → develop → main、タグ、GitHub Release）のみ。ステップ4〜7 は git と gh の操作だけでプラットフォーム依存はないため、どちらの環境でも実行できる。

実行時、ステップ3 のチェックリストで「manual 整合」が ❌ になる。第 4 章のとおり 35 件すべてが 1.10.0 からの継承であり、今回の作業に由来するものはない。
