# 調査結果: クリップボードの close の説明が、実際の振る舞いと合っていなかった

- 実施日: 2026-09-30
- 対象: `Clipboard::Session::Close` / `ntk_clipboard_session_close` の説明（公開ヘッダーと `manual/1.12.0/clipboard{,.ja,.ko}.md`）
- ブランチ: `feature/NTKIT-16`
- きっかけ: `unity-native-plugin-ba` からの報告（1.12.0 前の確認への返事、2026-09-30）。コードの変更は無く、説明だけを直した

## 1. 報告

Unity の Player（Mono と IL2CPP の両方）で、履歴の取得（`ntk_clipboard_get_history`）の WinRT の処理が走っている間に、オーナーのスレッドで close を呼んだ。

- 待っていた要求は、1 回目の close の中で `CANCELED` として届いた（説明どおり）
- close は `BUSY` を 2 回返し、3 回目で成功した。その間、オーナーのスレッド（メインスレッド）はフレームごとにメッセージを処理していた
- ほかのスレッドの読み書きは無かった

一方、ヘッダーの説明は次のとおりだった。

- 完了は close の中で届くので「メッセージループは要らない」
- 「`BUSY` のときだけ再試行する」。`BUSY` の理由は「ほかのスレッドの読み書き」

## 2. 確かめ方と結果

素の Win32 のアプリ（2.0.0 の C++ API、メインスレッドは STA）で確かめた。履歴の要求はプロセスが最前面でないと `NotForeground` で断られるので、小さなウィンドウを出してクリックで最前面にしてから行った。クリップボードには書き込んでいない。

手順: セッションを作る → `GetHistory` → 数ミリ秒だけメッセージを処理して WinRT の処理を始めさせる → `Close` を 20 ms ごとに 10 秒まで繰り返す。

| 再試行の合間 | 結果 |
|---|---|
| メッセージを処理しない | 1 回目の `Close` の中で完了が `Canceled` で届いた。**`Close` は 316 回、12.5 秒 `Busy` のまま**。その後メッセージを処理すると、約 0.5 秒で閉じた |
| メッセージを処理する | 1 回目の中で `Canceled` が届き、`Busy` の後、**14 回目（0.4 秒）で閉じた** |

原因はコードからも読める。`ClipboardHistoryWinRt::RunGetItemsAsync` は `co_await Clipboard::GetHistoryItemsAsync()` で待つ。STA で `co_await` した続きは、そのスレッドのメッセージを通じて再開する。要求を取り消しても始まった WinRT の処理は止まらず、それが終わるまで close は `Busy` を返す。`Close` が合間に処理するのは自分のウィンドウの drain のメッセージだけなので、それでは終わらない。

再試行してよい失敗もコードで確かめた（`ClipboardManager::Uninit`）。

| 失敗 | 理由 | 後の試行で解消するか |
|---|---|---|
| `WrongThread` | オーナー以外のスレッドから呼んだ | 解消しない。オーナーから呼ぶ |
| `MonitorRegisterFailed` | クリップボードまたは履歴のリスナーを外せなかった | する。次の試行で外し直す |
| `Canceled` | 取り消した要求の完了を、決まった回数の中で届けきれなかった | する |
| `Busy` | 別のスレッドの読み書き、または履歴の要求の WinRT の処理が残っている | する。WinRT の処理は、オーナーがメッセージを処理しているときにだけ終わる |
| `PartialState` | 書きかけの遅延描画を元に戻せなかった（ほかのプログラムがクリップボードを握っているなど） | する。次の試行で戻し直す |

`WrongThread` 以外の失敗では、どれもセッションは開いたままで、放棄にはならない。成功しないまま破棄（C では `_free`）すると放棄になり、そのプロセスではもう作れない。「`BUSY` のときだけ再試行する」をそのまま守ると、残りの 3 つで放棄することになる。

## 3. 対処（説明だけ）

- C++: `Session::Close` の説明と `@retval`、`Error.h` の `Busy`
- C: `ntk_clipboard_session_close` の説明、`NTK_CLIPBOARD_ERROR_BUSY` の注記
- マニュアル（英・日・韓）: C++ の Close の説明と例のコメント、`CanClose` の説明、C の例、エラー表の `Busy`

直した内容:

- 完了を届けるのにメッセージループは要らない。ただし、履歴の要求の WinRT の処理が終わるのを待つには、再試行の合間にオーナーのスレッドでメッセージを処理する必要がある。処理しなければ `Busy` のまま
- `WrongThread` 以外の失敗は、どれも後の試行で解消し得る。成功するまで、メッセージを処理しながら繰り返す

マニュアルでは、ほかに 2 つの誤りも直した。

- `CanClose` を「開いていて何も処理していないセッションは true」と説明していた。ヘッダーとコード（`ClipboardLifecycle::CanDestroy` は閉じ始めていることを条件にする）では、閉じ始めていない開いたセッションは false である
- C の例が「`can_close` が真なら close し、その後で必ず `free`」になっていた。開いたセッションの `can_close` は 0 なので、この例のとおり書くと一度も close せずに `free` して放棄する。close を成功するまで呼び、成功したら `free` する形に直した。`check_manual_c_examples.py` の 4 項目（全 105 関数の網羅、名前、3 言語のコードの一致、C としてのコンパイル）は OK

同じコミットで、Doxygen の警告から見つかった表示の誤りも直した。9/27 に通知のヘッダー（`ManagerOptions::displayName`、`ntk_notification_manager_options::display_name`）に書いたレジストリのパス `HKCU\Software\Classes\AppUserModelId\<displayName>` は、`\` が Doxygen のコマンドとして読まれ、生成した文書では最後の `\` が落ちていた。パスをコード表記にした。

## 4. 記録文書の訂正

`ba` から、ほかの文書の誤りも 3 つ指摘された。版の付いた文書なので書き換えず、ここで訂正する。

| 文書 | 箇所 | 元の記述 | 正しくは |
|---|---|---|---|
| `results/2026-09-23-windows-architecture-stage5-result.md` | 57 行目 | `ntk_notification_manager_create` は呼び出しスレッドを MTA にするので、同じスレッドを Clipboard のオーナーにできない | 先に STA で初期化してあれば兼ねられる（C ABI 設計書 1.3.3 のとおり。`Create` は `RPC_E_CHANGED_MODE` を受け入れる）。Unity のメインスレッドは STA で、両方を同じスレッドで使えている |
| 同 | 43 行目 | `release` は、登録した関数が失敗したときも必ず 1 回呼ばれる（呼び出しスレッドで、戻る前に） | 遅延描画の予約が `PARTIAL_STATE` で失敗したときは保持され、後の場面で呼ばれる（C ABI 設計書 7.5.3 の表のとおり） |
| `designs/2026-09-21-windows-architecture-c-abi-design.md` | 8.3 の表、638 行目 | `getPreferredClipboardFormat` の「変わること」が「-」 | 呼び出し側のバッファから `ntk_string` のハンドルに変わる（ほかの paste と同じ） |

## 5. 範囲外とした報告

`ba` は、`DeleteHistoryItem` の後に、消した ID は消えたのに同じ文字列の別の ID の項目が履歴に現れることがまれにある、とも伝えてきた（1.x と 2.0.0 で計 3 回）。報告者自身が Windows の履歴側の振る舞いと見ており、再現の手順も無いので、ここでは扱わない。
