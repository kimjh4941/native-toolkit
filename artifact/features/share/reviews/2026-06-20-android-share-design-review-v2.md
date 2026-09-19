# 再レビュー結果

- 日付: 2026-06-20
- 対象ファイル: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 関連ファイル: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 機能名: Share
- 対象 OS: Android 12 以降

---

## 強み

- 前回指摘した API 35 の `ChooserResult.type`、Receiver 蓄積、optional thumbnail fallback、Direct Share quota、直接検証テストが親設計へ反映されている。
- `ChooserResult` と `ChooserAction` の API レベルを明確に分離している。
- 不正なプレビュー画像だけを無視し、本文共有の失敗は維持するエラー境界が明確になった。
- Direct Share quota の問題を高度な管理ではなく基本登録の正しさとして扱っている。

## 改善点

### 高優先度

#### Copy/Edit でも提示コードは `onResult(null)` を呼ぶ

- 対象: `#1 HP1`、`#2 HP2`
- 問題: 仕様では Copy/Edit/Unknown は `onResult` を呼ばないとしているが、`extractSelectedPackageApi35` はそれらで `null` を返し、Receiver は無条件に `onResult(extractSelectedPackage(intent))` を実行する。結果として Copy/Edit で `onResult(null)` が呼ばれる。
- 改善案: nullable String だけでは「SELECTED_COMPONENTだがpackage取得不可」と「非選択操作」を区別できない。内部結果を `Selected(packageName: String?)` / `Ignored` のような sealed型または通知可否付き結果にし、`Selected` の場合だけ公開callbackを呼ぶ。

#### Repositoryフィールドによる単一Receiver制御がUnity経路で成立しない

- 対象: `#2 HP2`
- 問題: 現行の `UnityAndroidShareManager` は各操作で `ShareUseCases(context)` を生成し、そのfactoryは毎回新しい `ShareRepositoryImpl` を作る。したがって新しいRepositoryから前回Repositoryの `pendingCallbackReceiver` を解除できず、設計どおり「常に最大1個」にならない。新設予定のcancel APIも別インスタンスへ委譲すると効果がない。
- 改善案: `UnityAndroidShareManager`がapplicationContext単位で同じ`ShareUseCases`を保持する、またはapplication scopeのcallback coordinatorをDIして全Repositoryで共有する。サンプルとUnityの両経路についてインスタンス寿命を図示する。

#### callback解除操作にUseCaseがなく共通アーキテクチャ規約に反する

- 対象: `#2 HP2` の対象ファイル一覧
- 問題: PortとManagerへ`cancelPendingCallback`を追加する一方、対応するUseCaseと`ShareUseCases` suiteへの追加がない。ManagerがRepositoryへ直接到達するか、実装不能な設計になる。
- 改善案: `CancelPendingShareCallbackUseCase`を追加し、`ShareUseCases.cancelPendingCallback`経由でManagerから呼ぶ。対象ファイル、単体テスト、Unity公開operationを設計へ追記する。

#### Sharesheet起動失敗時のReceiver解除が定義されていない

- 対象: `#2 HP2`
- 問題: Receiver登録後に`startActivity`が`NoShareTarget`等で失敗すると、選択も次回開始もない場合Receiverが残る。
- 改善案: chooser起動をtry/catchし、起動失敗時はその場でReceiverを解除してから例外を再throwする。対応テストを追加する。

### 中優先度

#### サンプル設計への振り分け指摘がまだ未反映

- 対象: `android-share-sample-app-design-v3.md`
- 問題: 親設計末尾では次フェーズ対応としているが、同名v3サンプル設計には次が残っている。
  - Manifestがtext/plainのみなのに画像・複数画像受信を完了条件にしている
  - `previewThumbnailBase64` / `file.toBase64()`が残っている
  - `EXTRA_TEXT`を`getStringExtra`で取得している
  - コード例のKDoc・コメントが日本語
- 改善案: 親設計を確定扱いにする前に、関連するサンプル設計v3も同時に更新する。

#### cleanup責務の呼び出しタイミングが曖昧

- 対象: `#2 HP2`
- 問題: サンプルは「破棄時」、Unityは公開APIで解除するとしているだけで、Composeの`DisposableEffect`、Activityの`onDestroy`、Unity lifecycleのどこから呼ぶかが確定していない。
- 改善案: サンプルは`DisposableEffect(shareUseCases)`の`onDispose`、Unityはlistener解除またはplugin teardown時など、具体的な呼び出し点を定義する。

### 低優先度

#### 親設計のコード例にも日本語コメントが残る

- 対象: `extractSelectedPackageApi35`、`resolveOptionalPreviewUri`等のコード例
- 問題: 実装へ転記されるコメントが共通規約の「コメントは英語」に合わない。
- 改善案: コードフェンス内のKDoc・コメントを英語にする。

## 不足項目

- callback抽出の内部結果型と通知可否の契約
- Unity経路でRepositoryまたはcallback coordinatorを保持する所有モデル
- `CancelPendingShareCallbackUseCase`とsuite登録
- chooser起動失敗時のReceiver cleanupテスト
- サンプル・Unity双方のcleanup呼び出しタイミング

## 総合評価

前回レビューの論点は親設計へ概ね反映され、リッチプレビューとDirect Shareの設計は実装可能な水準に近づいた。一方、callback設計はnullable Stringではresult typeを表現できず、さらにRepositoryの寿命がUnityの生成方式と一致していない。この2点を直さないまま実装するとCopy/Edit誤通知とReceiver蓄積が残る。サンプル設計への反映も完了していないため、現時点では実装着手前にもう一度整合させる必要がある。
