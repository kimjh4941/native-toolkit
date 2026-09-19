# レビュー結果（v8 変更差分）

- 日付: 2026-09-02
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v8.md`
- 比較元: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- レビュー範囲: ヘッダ、§12.6 MT-05、§12.6.1、§13 T-18 の変更箇所のみ
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- 機械照合: 22 / 22 通過、FAIL 0 件

---

## 強み

- v8、改訂日、前版 v7 のヘッダ更新は正しい。
- D&D UI を新たな出荷機能として追加しない判断は、macOS 企画書が D&D UI 実装を対象外にしたスコープと整合する。
- 現行 public API では drag harness を構築できないというサンプル設計レビューの問題に対し、サンプル側で `NSFilePromiseProvider` を再実装する回避策を採らなかった点は正しい。
- `clipboardProvideFilePromise(requestJson, scopeJson, callback)` が実在し、Unity から OP-16 の提供開始を呼べるという記述は実装と一致する。
- Finder の Cmd-V による履行が公式契約で確認できないことを「未確認事項」と明記し、保証済みと断定していない。
- 公開 OP 20 件、Bridge endpoint 19 件を変更せず、機械照合 22 / 22 を維持している。

## 改善点

### 高優先度

#### 1. §12.6.1 の許容分岐と T-18 の完了条件が矛盾している

- 対象: §12.6.1、§13 T-18（2342〜2351、2382 行）
- §12.6.1 は Finder が履行しない場合、MT-05 を「実施不能」として記録することを許容している。
- 一方 T-18 は「MT-05 を貼り付け経路で実施できること」を完了条件にしている。Finder が非対応なら、設計が認めた分岐どおりに記録しても T-18 は永久に完了できない。
- §15 の実装完了条件も MT-01〜MT-07 の実施を要求するため、「実施不能」を合格、保留、失敗のどれとして扱うかがない。
- 次のいずれかへ統一すること。
  1. Finder 対応を先行実機 probe で確認し、成功を確認できた場合だけ現在の T-18 完了条件を採用する。
  2. T-18 を「OP-16 の提供操作をサンプルから実行でき、MT-05 の互換性 probe を所定の判定項目で実施し、`fulfilled` または `consumerUnsupported` として記録できること」へ変更する。後者は MT-05 の成功ではなく互換性調査完了であることを明記する。
- より強い範囲内検証として、同一 scope 上で OP-16 → OP-18 を接続する loopback probe も候補になる。これが AppKit 上で成立するなら、provider 登録から receiver、delegate callback、ファイル生成までを D&D なしで必須成功条件にし、Finder Cmd-V は別の互換性 probe に分離できる。loopback 自体も未実測なので、まず小さな実機 probe で成立性を確認すること。

### 中優先度

#### 1. Bridge endpoint の存在と、成立済みの製品利用経路を混同している

- 対象: §12.6.1「さらに、ドラッグ経路は製品の利用者が通る道ではない」（2332〜2340 行）
- Bridge が provider を一般 pasteboard に登録できることは、consumer がそれを受け入れて destination URL を提示することを保証しない。
- Apple の `NSFilePromiseProvider` 資料は provider が `NSPasteboardWriting` に準拠することを示すが、具体的な利用例は D&D である。また Apple の File Promise サンプルは、通常の copy-and-paste clipboard と drag pasteboard が別であると説明している。
- 「貼り付け経路は出荷済みの producer 呼び出し経路だが、consumer interoperability は未確認」と表現を限定すること。Finder 非対応時は単なる MT-05 の都合ではなく、OP-16 の製品上の利用可能性に関する残存リスクとして扱うこと。
- 参照: [NSFilePromiseProvider](https://developer.apple.com/documentation/appkit/nsfilepromiseprovider)、[Supporting Drag and Drop Through File Promises](https://developer.apple.com/documentation/appkit/supporting-drag-and-drop-through-file-promises)

#### 2. 自動テストの説明が system integration まで検証済みであるように読める

- 対象: §12.6.1 末尾（2350〜2351 行）
- 現在の `FilePromiseProvisionTests` は provider / delegate の保持、writer / snapshot、複数履行、release race などを検証しているが、履行テストは delegate をテストから直接呼び出している。
- AppKit/Finder が一般 pasteboard から provider を読み、destination URL を提示して delegate を呼ぶ consumer interoperability は自動テストされていない。
- 「provider/delegate の内部 transaction・履行処理・寿命・競合は自動検証済み。一般 pasteboard → consumer の system integration は未検証」と限定すること。
- IT-13 / IT-14 だけでなく、実際の履行処理に対応する IT-21 / IT-22 / IT-44 など、主張ごとに正確なテスト ID を参照すること。

#### 3. MT-05 の判定手順では失敗原因を分類できない

- 対象: §12.6 MT-05、§12.6.1 の結果分岐（2316、2342〜2348 行）
- Finder にファイルが生成されなかった事実だけでは、Finder 非対応、provider callback 未発火、source / staging failure、handle の早期 release を区別できない。
- 次を固定すること。
  - 対象 OS / Finder バージョン、使用 scope、writable な destination
  - 固定 file name、固定 payload、期待 hash または byte count
  - OP-16 の成功 callback、返却 handle を保持する期間
  - `FilePromiseDelegate.writePromiseTo` の発火有無
  - ファイル名と内容の照合
  - OP-17 と生成物の cleanup
  - `fulfilled` / `consumerUnsupported` / `providerNotInvoked` / `fulfilmentFailed` の判定規則

#### 4. 新しい未確認事項がリスク台帳と要検証 ID に接続されていない

- 対象: §12.6.1、§14 / §14.1
- Finder Cmd-V 互換性は T-18 の完了可否と OP-16 の実用性へ直接影響するが、本文内の「未確認事項」に留まり、残存リスク表や DV-01〜DV-06 に入っていない。
- `DV-07` などの ID を付け、検証環境、操作、期待結果、非対応時の製品判断、記録先を §14.1 に追加すること。T-18 と §15 から同じ ID を参照すると、結果が宙に浮かない。

#### 5. sample-app design v1 が旧 T-18 のままである

- 対象: T-18 の下流成果物
- `2026-08-30-macos-clipboard-sample-app-design-v1.md` はヘッダ、§6.2、実装順、要検証項目で drag harness を必須のまま保持している。
- v8 を採用する場合は sample-app design v2 で `FilePromiseDragHost` と `.drag` scope の試行を削除し、新しい MT-05 probe、handle 保持・解放、結果分類へ差し替えること。
- これは v8 本文の不整合ではないが、T-18 を実行する前に必要な追随変更である。

### 低優先度

#### 1. drag が Bridge 非公開である理由が単純化されている

- 対象: §12.6.1 の経路表（2334〜2337 行）
- 「`NSView` を扱うため Bridge 非公開」だけでは不十分である。現行 API に drag endpoint がなく、drag session は `NSView` に加えて `NSEvent`、`NSDraggingItem`、`NSDraggingSource` を必要とし、C Bridge で AppKit オブジェクトを公開しないことが境界である。
- OP-19 との類推ではなく、この一連の理由へ書き換えると正確になる。

#### 2. Android に D&D の言及がないことは、範囲外と決定した根拠にはならない

- 対象: §12.6.1 のスコープ説明（2327〜2330 行）
- 記載がないことは、明示的な out-of-scope 決定とは異なる。
- 変更理由は macOS 企画書の明示的な D&D UI 対象外と、現行 macOS public API / Bridge 境界だけで十分である。Android の無言及を根拠から外すこと。

## 不足項目

- Finder 非対応時にも T-18 を閉じられる、一貫した完了条件
- producer 呼び出し成功と consumer interoperability を分けた記述
- MT-05 の固定 fixture、観測点、結果分類、cleanup
- 一般 pasteboard → consumer が自動テスト範囲外であることの明記
- Finder Cmd-V 互換性を追跡する DV ID と製品判断
- sample-app design v2 への T-18 変更の反映

## 総合評価

D&D を範囲外のまま維持し、実装済み API 数を変えずに検証経路を見直す方向は妥当である。ヘッダと件数整合にも問題はなく、機械照合は 22 / 22 通過した。

ただし、現在の v8 は「Finder が履行しなければ実施不能としてよい」と「貼り付け経路で実施できることが T-18 の完了条件」を同時に置いている。Apple の公式資料も Finder Cmd-V による一般 clipboard 上の File Promise 履行を保証していないため、この矛盾は実装工程へ渡せない。

**高優先度 1 件を修正すれば、v8 の変更方針は採用可能である。** その際、MT-05 を必須成功試験にするのか、consumer compatibility の結果記録にするのかを明確に分け、内部自動テストで保証できる範囲を過大評価しないこと。続いて sample-app design v2 を新しい T-18 に同期させる必要がある。
