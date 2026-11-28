# 前提の確かめ: U-8 の監視が、何も押さずにテストを止める（VM）

- 日付: 2026-11-28
- 項目: `MAC_RUN_PREREQUISITES["u8MonitorStopsTheTest"]`（設計書 U-8、9.1「監視が何に来るか、`terminate` と `true` の後にテストが止まるか」、7 章「監視」）
- 場所: VM `ntk-macos-15-new`（macOS 15.8.3、Xcode 26.3）。リポジトリは `6d2ff80a`
- 結果: **通った**（3 回とも、監視が来て何も押さずにサンプルを止め、テストが落ちて止まった。押す枝を持たせた変異では、監視の中の押下が記録に出て区別できた）

## 道具（VM の写しにだけ置き、コミットしていない）

- `scripts/test_mac.sh --where vm --feature Dialog --skip-unit --keep-vm-run` で組んだ写し（47/47 passed）を `~/ntk/probe` に複製した
- 一時のテストのクラス `PrereqProbeUITests.testU8_unexpectedAlertBlocksThePress`（宣言の表の写しに `[]` で足した）:
  1. サンプルを起こして Dialog の画面を開く（Support の口）
  2. `dialog.button.ShowDialog` を、Support の押す前の確かめを通さずに XCTest で直に押す（テストの予期しないアラートを画面に出すため）
  3. 2 秒後に、Support の口で同じボタンを押す（アラートがボタンを塞いでいる）
- 変異の写し: `UnexpectedInterruptionGuard.handle` の `app.terminate()` の前に `element.buttons.firstMatch.click()` を足した（設計書 7 章「監視が押す枝を持つ形」）
- 結果のバンドルの手順（activities）から、監視の呼び出し、監視の中の `Click`・`Synthesize event`・`Type`、`Terminate` を数えた。スクリーンショットは読んでいない。バンドルは確かめた後に消した

## 結果

| 回 | 監視の呼び出し | 監視の中の押下 | 監視の中の Terminate | テスト | 失敗の文 |
|---|---|---|---|---|---|
| 1 | 1 | **0** | 1 | Failed | `UnexpectedInterruptionGuard.swift:30: Failed to get matching snapshot: Application … is not running` |
| 2 | 1 | **0** | 1 | Failed | 同じ |
| 3 | 1 | **0** | 1 | Failed | 同じ |
| 変異（押す枝） | 1 | **2** | 1 | Failed | 同じ（31 行） |

- XCTest は Support の押下（3）の前の「Check for interrupting elements」で、サンプル自身の `Dialog`（`{{382, 118}, {260, 314}}`）を割り込みと見て、`ntk-unexpected-interruption-guard` を呼んだ。監視はサンプルを止め、印を立てて `true` を返した。その後 XCTest が同じ要素を取り直そうとして「アプリが動いていない」で落ち、テストはそこで止まった（0c 1.6 と同じ形。Support の包む関数の throw までは届かない）。サンプルは回の後に残っていなかった
- 変異では、同じ監視の中に `Click` と `Synthesize event` が出た。何も押さないことを、この数え方で区別できる
- 監視が来るのは、XCTest が割り込みと見る要素（ここではテスト対象のアプリの `Dialog`）のとき。ほかのアプリの浮く窓は、押す前の確かめ（窓の持ち主。0c 1.6）が先に止める。2026-11-24 の途中の試し（記録を残していない回）では、ほかのアプリの浮くパネルや `NSAlert` は XCTest の割り込みに数えられず、押下は「hit point が無い」で落ちるか、塞がれていない点に届いた。この 2 つの守りの分担は 0c 1.6 の結論のまま

## 残したこと

- 26 で監視が同じに来るかは、26 の VM（`--where vm26`）の U-30 の適格性の段で見る（2026-11-28 の D-21 の見直しで、この Mac では UI テストを流さなくなった。ランナーのレビュー v7 の Codex C-1）
