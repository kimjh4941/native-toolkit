# レビュー結果

- 日付: 2026-05-30
- 対象ファイル: artifact/designs/notification/2026-05-30-windows-notification-implementation.md
- 機能名: notification
- 対象 OS: windows

---

## 強み

- 既存 WindowsDialogManager のフラット構造（Manager + C Bridge）に合わせた変形アーキテクチャを明示的に判断しており現実的
- common.md / windows.md 準拠チェック表で各方針の対応状況を可視化
- エラー一覧・エラーコード/メッセージ対応表を独立セクションとして整備
- 企画書のスヌーズ Deprecated 判断（Reminder/Alarm ボタン方式）を正しく引き継いでいる
- 未起動時 COM アクティベーション（Kind==Launch）を OnNotificationInvoked で統一処理する方針が反映されている
- co_await ブロッキング変換のデッドロック回避（UI スレッド呼び出し禁止）を明記
- MFC→WinRT の pch.h 順序、InitInstance() での init_apartment() 制約を具体的なコード設計に落とし込んでいる
- タスク分解に依存関係・工数・完了条件・テスト番号の紐づけがある

## 改善点

### 高優先度

**[ドメインエラー一覧 / エラーコード対応表 / API設計]**
- 問題: `getNotificationSetting()` は `int` 直接返却で `pError` なし。`setBadge` の不正値（例: `value < -6`）のエラーコードが未定義。設定値（0-4）とエラーコード（0-6）が同じ int 空間で混在し衝突リスクがある
- 提案: 全公開 API の返却型・pError 有無・成功/失敗値を一枚の対応表に統一。設定値とエラーコードの非衝突を明示。不正 value への INVALID_PAYLOAD 相当の扱いを定義

**[ドメインエラー一覧（全ケース）]**
- 問題: 企画書が指摘する以下のエラーケースに対応する定数がない: (1)ボタン最大5個超過、(2)音声ループに Long Duration が必要な制約違反、(3)スケジュール通知5分デリバリーウィンドウ超過、(4)AddArgument と SetInvokeUri の併用不可
- 提案: 専用コードを設けるか「HRESULT_FAILURE/INVALID_PAYLOAD に集約」の方針を明記する

**[スコープ / 企画書との整合性]**
- 問題: 企画書 In Scope の以下機能がサイレントに脱落: (1)コンボボックス（AddComboBox）、(2)通知一覧取得（GetAllAsync）、(3)スケジュール通知キャンセル（RemoveFromSchedule）、(4)有効期限設定（Expiration/ExpiresOnReboot）— 企画書がリスクとして明記
- 提案: 設計に追加するか Out of Scope へ明示移動し理由を記載。Expiration は企画書がリスク指摘しているため対応要否を必ず明記

**[通知ハンドリング / argsJson 仕様]**
- 問題: テキストボックス入力値（reply）は `Arguments()` ではなく `AppNotificationActivatedEventArgs.UserInput` から取得する別 API が必要。現設計では reply が argsJson に含まれない実装になる
- 提案: UserInput マップも取得して argsJson にマージする処理を制御フローに追加。JSON 例の reply フィールドの取得元を明記

### 中優先度

**[テスト設計]**
- 問題: NOTIFICATION_ERROR_HRESULT_FAILURE(5) と NOTIFICATION_ERROR_BADGE_FAILED(6) を発火させる異常系テストが存在しない。テキスト入力の reply 取得テストもない
- 提案: 全エラーコード（1〜6）を 1 対 1 で発火させる異常系テストを追加

**[タスク分解 / 依存関係]**
- 問題: Task 2 完了条件 T-02（ボタン）・T-05（Alarm）はコールバック（Task 4）なしに確認できず依存が逆転。.def への export 追加が Task 5 のみで Task 2 時点でリンク確認できない
- 提案: OnNotificationInvoked を Task 2 に含めるか完了条件を調整。.def 追加を各タスクに分散させる

**[リスクと緩和策]**
- 問題: 未パッケージアプリの COM サーバーレジストリ登録手順が設計に一切なく、Register(CLSID, launchUri) を呼ぶだけでは通知が機能しない可能性が高い
- 提案: COM サーバー登録手順を設計に明記するか、未パッケージは Out of Scope と割り切って明示

**[既存実装差分サマリー / vcxproj変更設計]**
- 問題: 最小 OS の記載が「Windows 10 Build 19041+」だが、対象は Windows 11 以上が正しい。framework.h の include 内容を未確認のまま「MFC を包含」と断定
- 提案: 最小 OS を Windows 11 に修正する。framework.h の実際の内容を確認して事実ベースで記述する

**[JSON エスケープ / ペイロード処理]**
- 問題: ArgsToJson でのキー・値の特殊文字エスケープ処理が未設計。ユーザー入力が JSON を破壊して C# 側パースが失敗するリスク
- 提案: WinRT JSON API（JsonObject/JsonValue）を用いた安全なシリアライズを明記

### 低優先度

**[Clean Architecture 準拠性]**
- 問題: BuildFromJson にテキスト/ボタン/画像/音声/進捗が全同居し責務が肥大化する見込み
- 提案: サブ要素ビルダー単位で内部関数を分割する構成を設計に示す

## 不足項目

- 公開 API 全体の統一返却仕様対応表（返却型・pError 有無・成功/失敗値）
- UserInput（テキストボックス返信）の取得処理と argsJson へのマージ
- JSON シリアライズ時の安全なエスケープ/エンコード方針
- コンボボックス（AddComboBox）の JSON ペイロード仕様と設計
- 通知一覧取得（GetAllAsync）とスケジュールキャンセル（RemoveFromSchedule）の API 設計
- 通知有効期限（Expiration / ExpiresOnReboot）設定
- 未パッケージアプリの COM サーバーレジストリ登録手順（または非サポートの明示）
- HRESULT_FAILURE / BADGE_FAILED 異常系テストケース
- バリデーション系エラー（ボタン数超過・併用不可・音声ループ制約）の扱い方針
- 最小 OS の修正（Windows 10 Build 19041+ → Windows 11）
- WindowsLibrary.def の具体的な export 関数リスト
- Unity C# 側 P/Invoke シグネチャ例（コールバックマーシャリング・文字列解放責任）

## 総合評価

構造は良いが、エラー網羅性・公開API整合・In Scope 充足・入力値取得の正確性の4点で実装着手前の改訂を要するレベル。特に「テキストボックス reply が UserInput から取得すべきである点が制御フローに未反映」と「企画書 In Scope のコンボボックス等がサイレント脱落」は重大。HRESULT_FAILURE/BADGE_FAILED の異常系テスト欠落、未パッケージ COM 登録手順の欠落、Task 2 とコールバック実装の依存逆転も是正が必要。
