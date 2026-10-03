# 調査結果: 履歴の復元は、履歴から除外された内容を置き換えない

- 実施日: 2026-09-26
- 対象: `Clipboard::Session::RestoreHistoryItem` と `ntk_clipboard_restore_history_item`（OP-43）
- ブランチ: `feature/NTKIT-16`
- きっかけ: `unity-native-plugin`（`feature/UNT-12`）からの報告。1.x の C ABI を Unity から呼び、復元が成功を返すのにクリップボードが変わらない場面に当たった

## 1. 何が起きるか

クリップボードの現在の内容が `excludeFromHistory`（C ABI の `NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY`。`SENSITIVE` はこれを含む）で書かれている場合、**復元は成功を返し、クリップボードは変わらない**。

利用者側から見た影響は、パスワードなどを `SENSITIVE` でコピーした直後に履歴から古い項目を復元すると、「成功した」と言われたままパスワードがクリップボードに残ることである。Unity に限らず、この API を呼ぶすべての利用者に当てはまる。

## 2. 原因

Windows の `Clipboard::SetHistoryItemAsContent` が `SetHistoryItemAsContentStatus::Success` を返す。この列挙には `Success` / `AccessDenied` / `ItemDeleted` しかなく、**「置き換えを断った」に当たる状態が存在しない**。

ライブラリはその戻り値をそのまま渡している。

- `windows/WindowsLibrary/src/Clipboard/Data/WindowsClipboardHistoryWinRt.cpp` の `RunSetItemAsContentAsync`（前面の確認 → 履歴の有効の確認 → id で項目を探して `SetHistoryItemAsContent`）
- 同ファイルの `MapSetHistoryItemStatus`（`Success` → `CLIPBOARD_ERROR_NONE`）
- `WindowsClipboardApi.cpp` の `Session::RestoreHistoryItem` と `ClipboardHistoryCApi.cpp` の `ntk_clipboard_restore_history_item` は素通しで、内容が変わったかを確かめていない

したがって 1.x と 2.0.0 で挙動は同じである（経路が同じ）。

## 3. 確かめ方と結果

サンプルアプリ（C++ API を使う）に対する使い捨ての UI テストで確かめた。3 ケースとも同じ形で、別プロセスからマーカーをコピーして履歴に入るまで待ち、`GetClipboardHistory` でその項目の id を捕まえ、**現在の内容を別のものに変えてから**復元し、別プロセスから最長 10 秒ポーリングして読む。

| 現在の内容 | 復元の完了 | 10 秒後のクリップボード | 判定 |
|---|---|---|---|
| `SENSITIVE`（`excludeFromHistory` + `excludeFromRoaming`） | `errorCode=0` | `Sensitive sample value` のまま | 再現 |
| `EXCLUDE_HISTORY` のみ | `errorCode=0` | `History excluded sample value` のまま | 再現 |
| 通常のコピー（対照） | `errorCode=0` | 古いマーカーに置き換わった | 正常 |

- **引き金は `excludeFromHistory` 単独**である。`excludeFromRoaming` は関係しない（報告時点の推測より 1 段絞れた）
- 対照が通るので、プローブと復元の経路自体には問題が無い
- 最初の実行では、復元後にクリップボードを 1 回しか読まなかったため対照も落ちた。読み取りが早すぎただけで、ポーリングに直したら対照は通った。`SetHistoryItemAsContent` を await していないので、**1 回読んで判断してはいけない**
- 測ったのは `Session::RestoreHistoryItem`（C++ API）である。C ABI は素通しなので同じだが、`ntk_clipboard_restore_history_item` 自体は測っていない

再現に使ったテストは残していない。プラットフォームの挙動を assert するテストは、Microsoft が直したときに失敗するだけで、こちらの不具合を知らせない。再現したい場合は上の手順をそのまま書き直せばよい（サンプルの `CopySensitive_Click` / `CopyExcludeHistory_Click` / `CopyPlainText_Click`、`GetClipboardHistory_Click`、`RestoreHistoryItem_Click` のボタンで足りる）。

## 4. 対処

**文書化する。検出はしない。**

| 項目 | 内容 |
|---|---|
| 公開ヘッダー | `Clipboard.h`（C++ API）の `RestoreHistoryItem` と `NativeToolkitC/Clipboard.h` の `ntk_clipboard_restore_history_item` に、成功の意味と `excludeFromHistory` の場合の振る舞い、確実にしたい場合の手段を書いた |
| マニュアル | `manual/1.12.0/clipboard{,.ja,.ko}.md` の「履歴項目の復元」に同じ内容を 3 言語で書いた |

検出しない理由:

- `SetHistoryItemAsContent` を await していないため、直後に `GetClipboardSequenceNumber` を比べると、**成功した復元まで失敗と報告してしまう**
- 確実にやるならオーナースレッドでのポーリングと期限が必要で、この API が全体として避けている作りになる
- 偽の「失敗」は、文書化された注意書きより悪い。利用者は成功した復元に対して再試行やエラー表示を行うことになる
- 確実性が必要な利用者は、クリップボードを読み戻すか `GetClipboardSequenceNumber` を 1 回比べれば済む

## 5. 申し送り

`unity-native-plugin` 側には、この結果と「現在の内容を通常のコピーにしてから復元する」という回避策を伝えた。あちらのテストとマニュアルは、既知の Windows の挙動として同じ記述にする。
