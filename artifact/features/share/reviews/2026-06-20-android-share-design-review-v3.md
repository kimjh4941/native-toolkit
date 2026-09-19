# 第3回レビュー結果

- 日付: 2026-06-20
- 対象ファイル: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 関連ファイル: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 機能名: Share
- 対象 OS: Android 12 以降

---

## 強み

- nullable Stringを内部sealed型へ置き換え、Copy/Edit/Unknownを公開callbackから除外できる設計になった。
- Receiver所有をapplication scopeへ移し、UnityがRepositoryを毎回生成する問題を解消している。
- cancel専用UseCase、suite登録、Unity operationが追加され、ManagerからRepositoryへの依存経路が規約に沿った。
- chooser起動失敗時のcleanupと、その直接テストが追加された。
- optional thumbnail、Direct Share quota、API別callbackのテスト観点が具体化された。

## 改善点

### 高優先度

#### CallbackResultと抽出関数の配置が別ファイル構成と整合しない

- 対象: `#1`、`#2 ShareCallbackCoordinator`
- 問題: `CallbackResult`と`extractCallbackResult`はprivateとして提示され、対象ファイルは`ShareRepositoryImpl.kt`とされている。一方、それらを呼ぶ`ShareCallbackCoordinator`は新しい別ファイルである。Kotlinのprivate top-level宣言はファイルprivate、class privateならclass外から参照できないため、この構成のままではCoordinatorから呼べない。
- 改善案: `CallbackResult`と抽出処理を`ShareCallbackCoordinator.kt`内へ配置するか、`internal ShareCallbackResultParser`として明示的に分離する。対象ファイル一覧と単体テスト対象も同じ配置へ統一する。

#### サンプル設計へ振り分けた指摘が未反映

- 対象: `android-share-sample-app-design-v3.md`
- 問題: 親設計は反映済みとしているが、関連サンプル設計には以下が残る。
  - `previewThumbnailBase64 = file.toBase64()`と方式未確定の注記
  - image受信用`ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent-filterの欠落
  - `getStringExtra(Intent.EXTRA_TEXT)`
  - 日本語KDoc・コードコメント
- 改善案: `previewThumbnailPath = file.absolutePath`、image filters、`getCharSequenceExtra()?.toString()`、英語コメントへ更新する。画像受信の完了条件を維持するならManifest変更を作成・変更ファイル一覧にも含める。

### 中優先度

#### Coordinatorのmain-thread前提がAPI契約で強制されていない

- 対象: `ShareCallbackCoordinator`
- 問題: コード例は「main threadから安全にアクセス」とコメントするだけで、Unity公開APIは任意threadから呼び得る。並行したregister/cancelで`pendingReceiver`の競合や、片方の起動失敗が別呼び出しのReceiverをcancelする可能性がある。
- 改善案: Manager入口でmain looperへdispatchするか、Coordinatorの全操作を同期化する。より堅牢にするなら登録tokenを返し、起動失敗時は自分のtokenに対応するReceiverだけを解除する。

#### Unity cleanupの具体的な実装点がまだ曖昧

- 対象: `cleanup 呼び出しタイミング`
- 問題: 「listener解除時 / plugin teardown時」とあるが、既存の`clearShareOperationListener()`がcancelも実行するのか、C#側が別APIを必ず呼ぶのかが未確定である。
- 改善案: `clearShareOperationListener()`内で`cancelPendingShareCallback`相当を実行する、またはC# lifecycle契約と呼び出しコードを対象ファイル・DoDに明記する。

#### API 36が確認マトリクスにない

- 対象: テスト設計、手動確認
- 問題: 対象はAndroid 12以降であり、現在の最新対象であるAPI 36もAPI 35+経路を通るが、確認対象がAPI 35で止まっている。
- 改善案: callback、Receiver、リッチプレビューの代表確認にAPI 36を追加する。

### 低優先度

#### 旧関数名がDoDに残る

- 対象: Definition of Done
- 問題: 本文では`extractCallbackResultApi35`へ変更済みだが、DoDには`extractSelectedPackageApi35`改名後と残っている。
- 改善案: `extractCallbackResult` / `extractCallbackResultApi35`へ統一する。

#### レビュー反映一覧にLP2が重複する

- 対象: `レビュー反映`末尾
- 問題: `EXTRA_TEXT`のLP2が2回記載されている。
- 改善案: 重複行を削除する。

## 不足項目

- CallbackResultとparserの確定配置
- Coordinatorのthread safetyまたはmain-thread dispatch契約
- Unity listener解除とpending callback解除の一体化仕様
- API 36の動作確認項目
- サンプル設計v3への振り分け指摘の実反映

## 総合評価

親設計のcallback・Receiver・UseCase・起動失敗cleanupに関する前回の重大指摘は解消された。残る親設計上の主問題は、privateなcallback抽出ロジックの配置とthread ownershipであり、修正範囲は限定的である。一方、関連するサンプル設計v3は前回指摘をまだ反映していないため、設計一式としては未完了である。上記を整合させれば実装着手可能な水準になる。
