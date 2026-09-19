# レビュー結果

- 日付: 2026-06-21
- 対象ファイル: `artifact/designs/share/2026-06-21-android-share-design-v4.md`
- 機能名: share
- 対象 OS: Android 12 以降（カスタムチューザーアクションは API 34 以降）

---

## 強み

- `ChooserAction` の対象を API 34 以降としており、API 35 以降の `ChooserResult` と混同していない。
- `ShareRepositoryImpl` が生成する `Intent(intentAction).setPackage(packageName)` と、動的 Receiver の `IntentFilter` を具体的に接続している。
- Receiver の責務を action 転送に限定し、listener の所有権を `UnityAndroidShareManager` に集約している。
- `applicationContext`、`RECEIVER_NOT_EXPORTED`、再登録前の解除を明記し、Receiver の累積を避ける方針が明確である。
- 変更ファイル、制御フロー、公開 API、タスク依存、Definition of Done が実装可能な粒度で整理されている。
- 新規ドメイン操作ではなく Unity 向け OS イベント受信であるため UseCase を追加しない判断に、既存通知パターンを根拠として示している。

## 改善点

### 高優先度

#### 1. 共有起動失敗時に Receiver が残留する

- 対象: 「shareText への組み込み」「ライフサイクル / 解除」
- 問題: Receiver 登録後に `ShareUseCases(context).shareText(...)` が失敗しても、今回の登録を解除する経路がない。Sharesheet が開かなかった場合にも Receiver が残り、後続の同一 action を誤って通知する可能性がある。
- 改善案: 登録処理から token または receiver identity を返し、`shareText` を `try/catch` で囲んで起動失敗時に今回の登録だけを解除してから再 throw する。後続登録を誤解除しないよう、既存 `ShareCallbackCoordinator` と同様の世代管理を採用する。

#### 2. listener の set/clear に順序競合がある

- 対象: 「追加 public API」「制御フロー」
- 問題: `clearShareChooserActionListener` は非 main thread から呼ぶと main looper へ post する一方、`setShareChooserActionListener` は即時代入する。`clear` の直後に `set` すると、遅延した `clear` が新しい listener を消す可能性がある。
- 改善案: listener と Receiver に関する set/clear/register/unregister をすべて main looper 上で直列化するか、同期化と世代 token を導入する。各 API の完了時点と callback 実行スレッドも公開仕様に明記する。

#### 3. callback 境界で listener 例外を封じ込めていない

- 対象: 「ShareChooserActionReceiver」「登録/解除ヘルパー」
- 問題: `listener.onChooserAction(actionId)` が例外を投げると、BroadcastReceiver の実行スレッドへ伝播してアプリがクラッシュする可能性がある。
- 改善案: listener 呼び出しを `try/catch` で保護し、`Log.e` へ記録して Receiver 境界から例外を漏らさない。listener が例外を投げるテストを追加する。

#### 4. 機能の核心となる登録経路の自動テストが任意になっている

- 対象: 「テスト設計」
- 問題: plain JVM では API ガードにより実際の `registerReceiver` 経路を検証できないにもかかわらず、API 34 以降の計装テストが任意である。`RECEIVER_NOT_EXPORTED`、filter、再登録、解除という主要要件が自動検証されない。
- 改善案: API 34 以降の計装テストを必須にし、登録後の broadcast、複数 action、clear、action 無し share、連続 share、起動失敗時 cleanup を検証する。JVM で担保する場合は SDK 判定と Receiver registry を注入可能な internal コンポーネントへ分離する。

### 中優先度

#### 1. 表示される action と登録される action の集合が一致しない

- 対象: 「登録対象 action の決定」「エラーコード / メッセージ対応表」
- 問題: Manager は parser が返した action を登録するが、`ShareRepositoryImpl` は不正 Base64 や Bitmap decode 失敗を黙って除外する。その結果、表示されない action の Receiver だけが残り、Unity は callback が利用不能であることを判別できない。
- 改善案: Unity 側で `label`、`iconBase64`、`intentAction`、画像 decode、1〜5 件、一意性を事前検証し、Receiver とライブラリへ同じ有効集合を渡す。登録失敗をベストエフォートとする場合も、共有起動結果と callback 登録結果を区別できる公開契約を定義する。

#### 2. 動的 Receiver 固有の保証範囲が公開契約にない

- 対象: 「ライフサイクル / 解除」「リスクと緩和策」
- 問題: context-registered receiver はアプリプロセスが動作している間だけ有効である。また、次の `shareText` で旧 Receiver を置換するため、複数 Sharesheet が同時に残る場合は最新 1 件以外の action を受信できない。
- 改善案: 「プロセス存続中のみ callback を保証」「同時に有効な chooser session は最新 1 件のみ」を公開仕様、リスク、手動確認へ追加する。要件上許容できない場合は、固定 action と識別 extra を使う manifest Receiver 方式を再検討する。

#### 3. `intentAction` の既定値と名前空間が識別用途に適さない

- 対象: 「API 設計」「リスクと緩和策」
- 問題: 現行 parser は未指定時に `android.intent.action.SEND` を補完するが、本設計では action 文字列自体を識別子として使うため、同一アプリ内の別 broadcast との衝突や複数 action の識別不能を招く。
- 改善案: callback を利用する chooser action では `intentAction` を必須かつ一意とし、`${applicationId}.share.action.*` のようなアプリ固有 namespace を入力契約として定義する。

#### 4. Android ログ規約との不整合がある

- 対象: 「個別実装方針の適用チェック」「ShareChooserActionReceiver」
- 問題: 提案コードの `TAG = "ShareChooserActionReceiver"` は `android.md` の full class name 規約に反する。また、解除例外を `Log.w` とする記述は、適用チェックの「エラーは `Log.e`」と一致しない。
- 改善案: TAG を `android.unity.share.ShareChooserActionReceiver` に変更する。未登録解除を警告扱いにするなら、規約例外として理由を明記する。

#### 5. private 実装のテスト方法が未確定である

- 対象: 「単体テスト」「実装タスク分解」
- 問題: `extractActionIds` は「reflection 経由 or 公開化検討」、listener 転送は「receiver ラムダ発火」とされており、実装時に使うテスト境界が決まっていない。
- 改善案: Receiver registry と action 正規化を internal クラスまたは internal 関数へ分離し、reflection を使わず直接テストできる構成を設計書で確定する。

### 低優先度

#### 1. タスクとテストの責任範囲が重複している

- 対象: 「実装タスク分解」
- 問題: T1〜T3 の完了条件にテストが含まれる一方、Manager テストを T4 にまとめており、TDD の実施単位が曖昧である。T2 の listener API 自体は T1 に依存しない。
- 改善案: T1 を Receiver と単体テスト、T2 を listener lifecycle と単体テスト、T3 を registration/session 管理と単体テスト、T4 を API 34 以降の計装・回帰テストとして整理する。

## 不足項目

- 共有起動失敗後に今回の Receiver だけを解除する設計とテスト
- set/clear/shareText の順序保証と callback 実行スレッド
- listener callback 例外を Bridge 境界で処理する仕様とテスト
- API 34 以降の実登録・解除を検証する必須の計装テスト
- 不正 icon、6 件以上、重複 action、未指定 action の入力仕様
- callback 登録失敗を Unity 側が検出できる公開 API 契約
- 複数 Sharesheet とプロセス終了時の保証範囲
- `RECEIVER_NOT_EXPORTED` で Sharesheet の PendingIntent を確実に受信できることの API 34 実機確認（要検証）

## 総合評価

既存 PendingIntent と動的 Receiver を接続する基本構造は具体的で、責務分離も概ね妥当である。一方、共有起動失敗時の Receiver 残留、listener の順序競合と例外伝播、主要経路の自動テスト不足が残っているため、このまま実装へ進むには信頼性が不足する。

特に Receiver の登録を session として管理し、失敗時 cleanup と main thread 上の直列化を設計へ追加する必要がある。そのうえで、実際に表示できる chooser action と登録対象を一致させ、API 34 以降の計装テストを必須化すれば、実装可能な設計になる。
