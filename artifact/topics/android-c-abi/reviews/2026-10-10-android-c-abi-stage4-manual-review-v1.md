# レビュー結果（段階 4 のマニュアル・英語の版・1 回目）

- 日付: 2026-10-10
- レビュー対象: `manual/1.13.0/{index,dialog,notification,share,clipboard}.md`（英語）の Android の部分。2.0.0 に書き直したもの（`manual/1.12.0` の写しとの差分）
- レビュアー: 3 本。観点が 3 つに分かれるため
  - Claude のサブエージェント 1（Kotlin の API の記述と例が、コード・サンプル・設計に合っているか）
  - Claude のサブエージェント 2（C ABI の節と index の導入の手順が、ヘッダー・実装・設計・配布物に合っているか）
  - Codex（利用者がこのとおりに進めて成功するか）
- 総合評価: **要修正**（A が 6 件）

ID の `M-K` は Claude 1、`M-C` は Claude 2、`M-X` は Codex。

## 確かめて合っていたこと

- Kotlin の 4 つの Manager の形、パラメーターの名前と既定値、結果とエラーの型、スレッドの規則、イベントの保持、予約の保存と 1.x の破棄、FileProvider の authority、サンプルとの一致（M-K）
- C の例 17 本が NDK の clang で組める。公開の 155 関数がすべて例に出る。エラーの名前と値、戻り値か完了かの区別、スレッド・`release`・所有権、初期化の戻り値、依存の版、要件の版、ファイルの間のアンカー（M-C）

## 区分 A

| ID | 問題 | 対処 |
|---|---|---|
| M-K1 | 1.x で表示中の通知が、更新の後はタップに反応しないこと（D-11 が書くよう求めた）が無い | index の移行の表と notification の「Changes from 1.x」に書く |
| M-C1 | 32 ビットも組む CMake では「`ntk::ntk` をリンクする部分を 64 ビットに限る」は誤り。AGP は CMake が組む ABI ごとに Prefab を確かめて `CXX1210` で止まる | CMake の ABI を `externalNativeBuild { cmake { abiFilters(...) } }` で 64 ビットに絞り、32 ビットの自前のコードは Prefab を使わない別のモジュールで組む、と書く（smoke と同じ形） |
| M-C2 | Dialog と Notification の章の組み込みの手順に、ABI を 64 ビットに絞る指定が無い | 4 つの章の例をそろえる |
| M-X1 | `android/build/m2` には 1.3.0 しか無く、2.0.0 を解決できない | 文書の誤りではない。リリースのビルドで 2.0.0 を作る（`build_android_library_aar.sh -v 2.0.0 -r 1.13.0 --m2`） |
| M-X2 | Share の `shortcuts.xml` の例にサンプルの `MainActivity` のクラス名 | 置き換える名前にし、自分の Activity にすると書く |
| M-X3 | index が「Android の全機能を C ABI から使える」と書くが、共有の受け取りには C ABI が無い | 受け取りを除くと書く |

## 区分 B と C

| ID | 対処 |
|---|---|
| M-K2 | 手動の初期化は `LibraryRuntime.ensureInitialized(activity)`（最初の Activity を渡す）にそろえる。Application の Context だけだと表示中の Activity を前面と認識しない |
| M-K3 | 権限の要求の callback の例が、画面が無くなった後に手元の状態に書く。サンプルの形にする |
| M-K4 | 利用者が `androidx.core.content.FileProvider` を自分で宣言すると、ライブラリの宣言と manifest の merge で衝突する。自前なら FileProvider のサブクラスにする。1.x のマニュアルで足した宣言を消す（移行の表） |
| M-K5〜M-K7 | 未初期化でも許可済みなら `Granted`、progress の 4 つは例外を投げる、過去の時刻の予約では `shown` が来ない |
| M-K8 | notification のコードの例の絵文字を外す |
| M-K9 | index の機能の一覧に、2.0.0 で足した見出し（権限、イベント、progress、前景サービス、選択のイベント、Dialog の取り消しとコルーチン）を足す |
| M-K10、M-C12 | Maven のリポジトリの置き場所と、Kotlin DSL のコードフェンスをそろえる |
| M-C3 | index の「`release` は main で来る」に、入口で拒んだときは呼び出しスレッドで来ることを足す |
| M-C4 | Unity から `NativeToolkitCApi.init` を呼ぶ形（`INSTANCE` を取る）を書く |
| M-C5 | 手動の初期化が要る場面（自分の ContentProvider、別のプロセス）と、待たずに返る値とやり直しを index に書く |
| M-C6 | capi が Kotlin の API を連れてくるのは実行時だけ。自分のコードが Kotlin の API を呼ぶなら両方を宣言する |
| M-C7 | 依存の一覧の照合は未実装 | 照合を実装する（配布物の照合に足す） |
| M-C8、M-C9 | Dialog の C ABI の未初期化と `INVALID_PARAMETER` の説明を、ほかの章にそろえる |
| M-C10 | リソース名は、内容を show / update / schedule / progress に渡した時点で解決する |
| M-C11 | 権限の要求に前面が要るのは、まだ許可されていないときだけ |
| M-X4 | Clipboard の例が、画面ごとに監視を止める（監視はプロセスで 1 つ）。監視を持つのは 1 か所にすると書く |
| M-X5 | 移行の表の「AAR が 2 つ」は、Kotlin のアプリも両方要ると読める |

## 範囲外で分かったこと

- 設計 8.13 で段階 3 に消すと決めた `NotificationShownSupport` と、Share の JSON の形（`ShareTextUseCase`、`ShareUseCases.shareText` の `chooserActionsJson`）が、コードに残っている（段階 3 の取りこぼし）。段階 3 で消す
- サンプルの Share の画面が、`ShareDomainError` の `message`（null）を表示している（サンプルの不具合）
