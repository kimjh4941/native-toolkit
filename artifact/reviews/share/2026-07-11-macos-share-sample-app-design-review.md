# macOS Share サンプルアプリ設計レビュー結果

- 日付: 2026-07-11
- 対象ファイル: `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md`
- 対象OS: macOS
- 対象サンプルアプリ: `MacLibraryExample`
- レビュー種別: サンプルアプリ実装計画書 再レビュー
- 前回レビュー: `artifact/reviews/share/2026-07-11-macos-share-sample-app-design-review.md`

---

## レビュー概要

前回レビューの指摘 3 件を再確認した。

- Medium 1: macOS 側の既存画像アセットを使う前提に更新した方がよい -> **解消**
- Medium 2: picker の `mouseDown` 制約に対して `Task {}` 経由を「制約に沿う」と断定しない方がよい -> **解消**
- Low 1: 参照元に実装レビュー v3 を追加すると前提が追いやすい -> **解消**

## 重大な問題（high）

なし。

## 改善提案（medium）

なし。

## 軽微な指摘（low）

なし。

## 前回指摘の状態

### Medium 1: 既存画像アセット再利用方針

解消済み。

対象計画書は、サンプル画像について既存 `test-image` アセットを再利用し、新規アセットを追加しない方針へ更新されている。

- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:61`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:102`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:145`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:147`

また、`.imageFile(path:)` がファイルパスを要求する点について、`NSImage(named: "test-image")` で読み込み、temp PNG へ書き出して path を渡す橋渡しも明記されている。

- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:82`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:148`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:182`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:222`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:223`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:269`

ローカル確認でも、macOS Example 側に `Assets.xcassets/test-image.imageset` と `test.png` / `test 1.png` / `test 2.png` が存在しているため、計画とリポジトリ状態は整合している。

### Medium 2: `mouseDown` 制約の表現

解消済み。

対象計画書は、「設計書の mouseDown 制約に沿う」という断定を避け、サンプルは「実ユーザークリック起点で picker を実機確認するための導線」を提供するものとして整理されている。

- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:58`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:120`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:181`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:253`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:254`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:270`

`Task {}` 経由が `NSSharingServicePicker.show(...)` の `mouseDown` コンテキスト保持を保証しない点も、前提・操作導線・呼び出し境界・手動確認観点に反映されている。picker 系ボタンを実 UI 手動検証用、direct service / `canPerform` を相対的に安定した確認経路として分けた点も妥当。

### Low 1: 実装レビュー v3 の参照

解消済み。

基本情報に実装レビュー v3 が追加され、実機 / 実 UI 検証は次工程の手動確認で扱い、サンプル設計レビューの pass/fail には含めないという切り分けも明記されている。

- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:7`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:58`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:253`
- `artifact/designs/share/2026-07-11-macos-share-sample-app-design-v1.md:270`

## 確認できた良い点

- 既存 macOS Example の UI パターン（`ContentView` の `menuCard`、`sectionView`、`FullWidthPressableButtonStyle`、`updateResult`）を優先する方針が維持されている。
- `ShareError` の `errorCode` / `errorMessage` 表示、`alreadyInProgress`、`canPerform`、`excludedServiceTitles`、direct service のサンプル化が、実装結果 v2 と整合している。
- 画像アセットについて、既存資産の再利用と API 入力形式の橋渡しが明確になった。
- picker の実 UI 検証とコードレビュー範囲の切り分けが、実装レビュー v3 と整合している。

## 不足項目

なし。

## 総合評価

**LGTM**。

前回指摘した Medium 2 件、Low 1 件はいずれも解消済み。現在の計画書は、サンプルアプリ実装に進める内容として妥当。
