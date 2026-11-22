# レビュー結果（v2）

- 日付: 2026-11-22
- 対象: v1（`2026-11-22-macos-c-abi-plan-review-v1.md`）を反映した企画（`plans/` の 3 つ、`README.md`、`results/2026-11-22-macos-c-abi-ios-lessons.md`）
- 判定: **要修正**（区分 A が 1 件。両方のレビュアーが独立に挙げた同じもの）
- 別モデルによる独立レビュー: v1 と同じ 2 者（Claude のサブエージェントと Codex）に続きとして頼んだ。互いの結果は見せていない。見たのは、v1 の各指摘が記録のとおりに直っているか、直しで新しい穴ができていないか、区分 A が残るか
- v1 の直り方: 両者とも、RA-2〜RA-5、RB-1、RB-3〜RB-13、RC-1〜RC-8、RC-11、RC-12 は記録のとおり直ったと判定した（実装済みという意味ではない）。RA-1・RA-6・RB-2・RC-9・RC-10 は一部が残った（下の表）

## 件数

| 区分 | Claude | Codex | 統合後 |
|---|---|---|---|
| A | 1 | 1 | 1（同じもの） |
| B | 1 | 4 | 5 |
| C | 5 | 2 | 6（1 件は B と重なる） |

## 区分 A

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R2A-1 | 両方 | v1 の RA-1 の直しで足した D-8 の A'（GCD のブロックの外から `runModal` に入る）は、`MacLibraryCApi` の `MainQueue.swift` の積み方を変えても実現できない。C ABI の受け口は `MacLibrary` の公開 API だけを呼び（P1-2）、`MacDialogManager` が中で `DispatchQueue.main.async` してから `runModal` を呼ぶ（`MacDialogManager.swift:320-327,361,507,666`）ので、二重に積まれて GCD のブロックの中に戻る。0e・0f で `Task { @MainActor }` / `@MainActor async` から入るよう書き直すと、main actor の仕事も main キューに積まれるので同じ問題が戻る | D-8 の A' を「`MacLibrary` の表示の手順を直す」に書き直し、Swift の利用者から見た動作も変わるので企画 4.1 と Swift の API の設計書に載せる、とした。どの案でも C の入口 → 公開の Manager → 表示の経路と、サンプルの Swift の経路に同じ契約を当てる。D-1 の許す差の例を直した（Dialog の出し方は `Common/` の写しに入らない）。1a-6 を公開 API の経路で、今の Swift 5 の経路と 0e・0f の後の `@MainActor` の経路の両方で測る形にし、0e・0f に「`runModal` に入る経路は D-8 で決めた形を崩さない」を足し、0e・0f の後に 1a-6 を流し直すことを 0f と DoD に足した。1b の「既定は変えない」を「Dialog の出し方は D-8 に従う」に直した（Codex C-2） |

## 区分 B

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R2B-1 | Claude B-1 | v1 の RA-6 の symlink の確かめに、Unity のパッケージの中の段（commit → git の URL での導入の `PackageCache` → AssetDatabase の取り込み）が無い。今の `Plugins/macOS` は git に symlink を持たない | 頼むことの 4、1a-9、DoD にこの段を足した（警告や二重の取り込みなしに残ること） |
| R2B-2 | Codex B-1 | v1 の RC-9 の残り: プロジェクトの階層だけを 15.0 にしても、`MacLibraryExampleTests` はターゲットに 15.1 を直に書いている（`MacLibraryExample.xcodeproj/project.pbxproj:485,503`。こちらで確かめた） | 企画 1.4・0e、D-15、8.3、知見の 11 に書き、0e で全ターゲット・全構成の実効の値を `-showBuildSettings` で確かめることにした |
| R2B-3 | 両方（Codex B-2、Claude C-1・C-3） | v1 の RB-2 の残り: VM の確かめ（1a-10）の期限が二重（0a と「1b の前まででよい」）。企画 7.5 の最後の段落が D-21 の「15.6 以上なら 26.3 が動く」を落としている | 1a-10 を 0a の完了の条件にした（企画 5 章と 8.2 の表の「前」の列）。7.5 の段落を直した |
| R2B-4 | Codex B-3 | v1 の RA-4 の検証の残り: sandbox のファイルの契約を、最後の dist で確かめる条件が無い（smoke と DoD は起動までしか見ていない） | 企画 7 章の smoke の行と DoD に、sandbox の C のホストでパネルの結果を後から読めることと、非同期の Share に渡せることを足した |
| R2B-5 | Codex B-4 | ヘッダーの置き場は 1a-1 で決めるのに、配布物の照合の条件が `Headers/NativeToolkitC/` に固定されている | 7.3 の 2 行を「1a-1 で決めた置き場」に直し、1a-1 に「決めた置き場を照合の条件にする」を足した |

## 区分 C

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R2C-1 | Claude C-2 | 企画 5 章の 1a の行の決定の並びに D-6・D-7・D-16・D-21 が無い。D-7 が条件付きの一覧に無い | 足した。条件付きの決定を D-4・D-6・D-7・D-8・D-24 とし、決定の表の見出しにも「条件付き」を付けた |
| R2C-2 | Claude C-4 | D-4 の本文に「差し込み口が見当たらない」と `Main.cpp` の口が並んで残っている | 「app delegate のサブクラスの差し込み口は無い。代わりの口が書き出しの `main` にある」に直した |
| R2C-3 | Claude C-5 | 企画 1.4 が、main キューが捌かれない仕組みを libdispatch の側と言い切っている | 「CFRunLoop と libdispatch のどちらの仕組みによるかも含めて確かめていない」に直した |
| R2C-4 | Codex C-1 | v1 の RC-10 の残り: 企画 5.2 に「`mac/Build` を消す」が残っている | 直した |
| R2C-5 | Codex C-2 | D-8 で方式が変わりうるのに、1b が「既定は変えない」と言い切っている | R2A-1 と一緒に直した |
| R2C-6 | Claude C-1 | 1a-10 の期限（R2B-3 と同じ） | R2B-3 で直した |

## 次

直した版を v3 に出す。
