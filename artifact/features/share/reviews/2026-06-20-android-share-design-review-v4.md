# 第4回レビュー結果

- 日付: 2026-06-20
- 対象ファイル: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 関連ファイル: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 機能名: Share
- 対象 OS: Android 12 以降

---

## 強み

- 画像・複数画像受信のintent-filterが追加され、完了条件とManifest設計が一致した。
- preview thumbnailが確定済みのfile path方式へ統一された。
- `EXTRA_TEXT`を`CharSequence`として取得し、コード例のKDoc・コメントも英語へ統一された。
- callback parserの配置、Coordinatorのthread safety、cancel UseCase、API 36確認が親設計へ反映された。
- サンプルの`DisposableEffect`とUnityのlistener解除にcleanup方針が割り当てられた。

## 改善点

### 高優先度

#### 置換・cancel後に遅れて届く古いReceiverがcallbackを実行できる

- 対象: 親設計 `ShareCallbackCoordinator.onReceive`
- 問題: `onReceive`はtoken一致時だけ現在Receiverを解除するが、token不一致でもその後のparserと`onSelected`を無条件に実行する。また`cancel()`は`currentToken`を無効化しないため、cancel前にqueueされたbroadcastが後から届くとcallbackが発火し得る。
- 改善案: lock内でtokenが現在pendingな登録かを判定し、現在でなければcallback処理を中止する。`pendingRegistration(token, receiver)`をnullableで保持し、onReceiveが一致する登録をatomicにclaimできた場合だけparse・通知する。明示cancelではpendingをnullにして古いtokenを無効化する。置換後のstale onReceiveとcancel後のqueued onReceiveをテストする。

#### clearShareOperationListenerからCoordinatorへ到達する所有経路がない

- 対象: 親設計 `Unity cleanup`
- 問題: 既存`clearShareOperationListener()`はContext引数を持たず、ShareUseCasesやRepositoryも保持していない。設計は内部でcancelするとしているが、`ShareUseCases(context).cancelPendingCallback()`を作るためのContextがなく実装方法が未定義である。
- 改善案: `shareWithCallback`開始時にapplication-scopedなcancel handle/UseCaseをManagerへ保持する、Manager自体へapplication context初期化を追加する、または`clearShareOperationListener(context)`へ契約変更する、のいずれかを確定する。公開API・テスト・C#呼び出しへの影響も記載する。

#### システムBackではreceivedShareがclearされない

- 対象: サンプル設計 `受信時のルーティング`
- 問題: `ReceivedShareScreen`のボタンは`clearReceivedShare()`を呼ぶが、既存`AppRouter`の共通`BackHandler`は単に`currentScreen = MAIN_MENU`とする。システムBackではDoDの「Backでclear」を満たさず、受信状態が残る。
- 改善案: 共通`BackHandler`で`currentScreen == RECEIVED_SHARE`の場合に`activity.clearReceivedShare()`を呼んでから遷移するか、Received Share専用BackHandlerへ統一する。ボタンBackとシステムBackの両方を手動・UIテストへ追加する。

### 中優先度

#### main looper dispatchとexecuteOperationのエラー契約が未定義

- 対象: 親設計 `Manager入口のdispatch`
- 問題: 現行Unity Managerの`executeOperation`は同期try/catchで成功・失敗を通知する。処理だけをHandlerへpostすると、post前に成功通知したり、post先の例外を捕捉できなくなる。
- 改善案: `executeOperation`全体をmain looperで実行するhelperを設計し、成功・失敗通知もpost先のtry/catch内で行う。main threadから呼ばれた場合は即時実行する契約とテストを追加する。

#### IncomingShareParserの自動テスト設計がない

- 対象: サンプル設計 `受信 Intent パーサ`
- 問題: ACTION_SEND、ACTION_SEND_MULTIPLE、CharSequence、非共有Intent、shortcut IDを扱う新規ロジックに対して手動確認しか定義されていない。
- 改善案: parserの単体テストを追加し、text、single URI、multiple URI、shortcut ID、unsupported actionを網羅する。テストファイルを作成・変更一覧へ追加する。

### 低優先度

#### 親設計の整理表に旧関数名が残る

- 対象: 親設計 `整理フェーズ確定事項` #5
- 問題: 本文は`ShareCallbackResultParser`へ移設済みだが、表には`extractSelectedPackageApi35`が残っている。
- 改善案: `ShareCallbackResultParser.parseApi35`へ統一する。

## 不足項目

- stale/queued broadcastを無視するatomic claim設計
- Unity Managerからapplication-scoped cancel処理へ到達する具体的な所有経路
- システムBack時の`receivedShare` cleanup
- main thread dispatch後の成功・失敗通知契約
- `IncomingShareParser`の単体テスト

## 総合評価

前回までの指摘は親設計・サンプル設計へ適切に反映され、通常共有、Direct Share、rich previewの設計整合性は高い。残る主問題はcallback lifecycleの競合処理とUnity Managerの所有経路、およびシステムBack時の状態cleanupである。いずれも実装時に不具合へ直結するため、着手前に設計へ追記する必要がある。
