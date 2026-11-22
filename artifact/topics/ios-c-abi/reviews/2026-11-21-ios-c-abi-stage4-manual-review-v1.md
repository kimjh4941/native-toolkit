# 段階 4 のマニュアル（英語）のレビューの結果（v1）

- 日付: 2026-11-21
- 対象: `manual/1.14.0/{clipboard,dialog,notification,share}.md` の `## iOS`（最後に `### C ABI`）と目次、`manual/1.14.0/index.md` の iOS の部分（成果物の場所、版、機能の一覧、iOS の組み込み・プライバシーマニフェスト・通知の delegate・C ABI・2.0.0 への移行）。日本語と韓国語は、このレビューの直しの後に訳す
- レビューした者（どれも読むだけ）: 観点で 3 つに分けた。マニュアルの誤りは、Swift の API の説明、C の約束、組み込みの手順で出どころが違うため（Android の段階 4 と同じ分け方）
  - Claude のサブエージェント（Swift の観点。S-n）: 4 章の Swift の例を 2.0.0 の配布物に対して `swiftc`（Swift 6、`-emit-sil` で `sending` も）で組み、サンプルのリテラル、移行の表、機能の一覧を照らした
  - Claude のサブエージェント（C ABI の観点。K-n）: C ABI の節と index の組み込みを、ヘッダー・第 1 部・第 2 部・C の実装・smoke のプロジェクトと照らした
  - Codex（全体。C-n）: ソースと設計に照らした正しさと、手順どおりに進めて成功するか
- 頼みの文: `review-common.md`（対象、正とするもの、守る決まり、A・B・C の重さ、ソースで確かめたものだけを書く）

---

## 強み（3 者に共通）

- A（このとおりに進めると失敗する・誤解する）は 0 件
- C の約束（どのスレッドでも呼べて待たない、受け付け・拒否と `release` のちょうど 1 回、ハンドルの持ち主と `_free`、`struct_size`、UTF-8、`NOT_FOREGROUND`、iPad の複数の window、エラーの番号）が、ヘッダーと実装に一致する。例はすべてのハンドルを解放している
- Swift の例は、下の直したもののほかはすべて 2.0.0 で組め、サンプルのリテラルと一致する
- 組み込み（2 つの dynamic で署名なしの framework、Embed & Sign、include の 2 つの形、`@import IosLibraryCApi;`、プライバシーマニフェスト、bundle id）は配布物と smoke に一致する

## 改善点と対応

| ID | 重さ | 問題 | 対応 |
|---|---|---|---|
| S1・C-1 | B | 移行の表に、port の破壊的変更（`ShareRepository.present(content:presenter:)`、`NotificationRepository.openNotificationSettings() async -> Bool`、`enqueueCategoryChange` の追加、`NotificationRepositoryImpl()`）が無い。自分で port を実装したアプリが組めなくなる理由が書かれていない | 直した（行を足した。1.x と 2.0.0 の swiftinterface で確かめた） |
| S2 | B | 移行の表に、`getRootViewController()` の `@MainActor`、`content` の `sending`、`NotificationPermissionHelper`・`allowAnnouncement` の非推奨、`errorMessage` の固定の英文が無い | 直した |
| S3 | B | 通知の章の「1.x からの変更」が、消えた case と変わった case を名指ししていない | 直した（Share の章と同じ形） |
| S4 | B | Clipboard の `startObserving` の例が、最後の `catch` が無く組めない | 直した |
| K-B1 | B | 「C ABI に無いもの」に、provisional の許可と、年〜秒のほかの暦の条件（曜日など）が無い | 直した（index と通知の章） |
| C-2 | B | `ntk_clipboard_detect_values_async` の JSON の形（型、入れ子、無いときの値、非有限の数、日時の形）が書かれていない | 直した（第 2 部の表を英語にした） |
| S5〜S7 | C | 例のうち 3 つが単独では組めない（前の例の `content` を使い回す・`Task` が無い・`try` が `do` の外） | 直した（`content` は例ごとにサンプルのリテラルで作る） |
| S8 | C | 「完了と handler は `@MainActor @Sendable`」が広すぎる（通知の handler の typealias は `@Sendable` だけ、Clipboard の完了は変わらない） | 直した |
| S9 | C | Dialog の章が `final` を直す必要のある変更に数えている（1.x も `open` でなく継承できなかった） | 直した |
| S10 | C | 前の delegate を弱く持つことが書かれていない | 直した（アプリが強く持つ） |
| S11 | C | 2.0.0 の新しい presenter の一覧に、通知の設定の画面が無い | 直した |
| K-C1 | C | 手順の Xcode の版が、C だけのアプリの条件（Xcode 26 のどの版でもよい）と食い違う | 直した |
| K-C2 | C | XCFramework に要らない Framework Search Paths の手順 | 消した（smoke のプロジェクトにも無い） |
| K-C3 | C | C の例が暦と位置の予約に同じ識別子を使い、後のもので置き換わる | 直した（別の識別子と注） |
| K-C4 | C | 要件へのリンクが index の C ABI の見出しを指す | 直した（iOS の「Supported platform」の見出しへ。Share にも足した） |
| K-C5 | C | 変更のリスナーの `release` の時期（外した後）が一般の文と合わない | 直した |
| K-C6 | C | 「0 で埋めれば既定」が、必須の項目のある構造体に広すぎる | 直した（項目ごとに既定と必須を書いた） |
| K-C7 | C | 空の文字列の項目は Share で拒まれない（そのまま共有される） | 直した |
| K-C8 | C | index と Clipboard の章で「C ABI に無いもの」がそろっていない（`.changedDetectedOnForeground`） | 別の形で直した: 2.0.0 ではもともと届かないイベントなので「無いもの」には入れず、Clipboard の章で説明した |
| C-3 | C | Clipboard の Swift の例の文字列がサンプルと違う | 直した |

## 確かめたこと（直した後）

- `check_manual_c_examples_ios.py 1.14.0 --require-compile`: coverage 134、symbols、compile（18 の例）が OK。parity は日本語と韓国語がまだ無いので FAIL（訳した後に OK にする）
- `verify_manual.sh 1.14.0`: anchors と「anchors in OS sections」（段階 4 で足した検査）が OK
- 直した Swift の例は `swiftc -typecheck` と `-emit-sil`（Swift 6、iOS 18 のシミュレーター、2.0.0 の XCFramework）で組めた

## 総合評価

3 者とも A は無く、中心は移行の表の抜け（S1〜S3）と、例の組めない所（S4〜S7）、C ABI に無いものの書き漏らし（K-B1）だった。すべて直した。
