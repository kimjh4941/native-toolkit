# Windows Clipboard サンプルアプリ実装 再レビュー v4

## レビュー対象

- ブランチ: `feature/NTKIT-13`
- 対応コミット: `b7a952780900a5ae34275e349d6bf6c7016e85a8`
- 比較: `develop...HEAD`、およびレビュー v3 対応差分 `b7a95278^...b7a95278`
- 計画: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v3.md`
- 対象OS: Windows 11以降

## 検証結果

| 検証 | 結果 |
|---|---|
| `dotnet test ... --configuration Release --no-restore` | 33 passed / 0 failed、1分11秒 |
| テスト終了後の `WindowsLibraryExample` プロセス | 残存なし |
| `git diff --check b7a95278^ b7a95278` | 問題なし |
| C++サンプルの再ビルド | 対象コミットにアプリ側変更がないため省略。直前v3レビューではRelease / x64 Build成功 |

## レビュー概要

- 終了処理を `EnsureExited` に共通化し、通常teardownとmain window取得失敗の両経路が「待機、Kill、再待機、残存時例外」を通るようになった。
- 起動失敗とcleanup失敗が重なった場合は `AggregateException` で両方を保持し、後続テストの分離不能を隠さない。
- 実装結果§2.4は、request ownerとactive pageを照合する現在の配送方式へ更新された。
- `StaysFalse` と `Dispose` のXMLコメントは各memberの内容と一致した。
- v3の3件はすべて解消し、新たなコード指摘はない。

## 重大な問題（high）

なし。

## 改善提案（medium）

なし。

## 軽微な指摘（low）

なし。

## v3指摘対応状況

| v3指摘 | 評価 | 再レビュー結果 |
|---|---|---|
| M1 起動失敗時のKill後終了待機 | ○ | `EnsureExited` を両経路で使用し、cleanup失敗も例外として報告 |
| M2 §2.4の旧callback説明 | ○ | `g_requestOwners` / `g_activePageId`方式と変更経緯へ更新 |
| L1 XMLコメント位置 | ○ | `StaysFalse`と`Dispose`へ正しいコメントを配置 |

## 計画書整合性チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 48操作とMainMenu導線を実装 |
| API呼び出し方針の一致 | ○ | 同期worker、UI-affine API、非同期requestの方針がv5と一致 |
| システム設定の正確性 | ○ | MSIX設定・既存solution構成を維持 |
| 変更ファイル一覧とのdiff整合 | ○ | UIテスト14ファイルを含む最終状態を記録 |
| 追加判断のresult記録 | ○ | UI自動化、配送方式、レビュー対応を§5に記録 |

## サンプルアプリパターン適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| メニュー導線 | ○ | MainMenuからClipboardPageへ遷移 |
| 画面構成パターン | ○ | title、result、section、scroll、Backを既存形式で実装 |
| 成功/失敗表示フォーマット | ○ | resultとlogの役割を分離し既存形式を維持 |
| 共通UI部品の利用 | ○ | 既存WinUI 3サンプルの構成に準拠 |

## プロジェクトルール適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| `common.md`準拠 | ○ | アプリ内完結の対象を独立UIテストで直列実行 |
| `windows.md`準拠 | ○ | FlaUI Adapter、AutomationId、bounded polling、process isolationを実装 |
| Unityプラグイン非依存 | ○ | Sample / UI testともUnity参照なし |
| Log.d網羅性 | — | Android専用規約のため対象外 |
| KDoc網羅性 | — | Android専用規約のため対象外 |

## 手動確認観点の充足

記号: ○ = UIテストまたは実測で確認、△ = 外部アプリ・OS UI・別デバイス等の手動確認が未実施、× = 契約違反を確認。

### v5 §8.1 Interoperability

| No | 観点 | 評価 |
|---|---|---|
| 8.1-1 | CopyPlainText -> Notepad | △ |
| 8.1-2 | CopyHtml -> Word / browser | △ |
| 8.1-3 | CopyHtml -> Notepad | △ |
| 8.1-4 | CopyFiles <-> Explorer | △ |
| 8.1-5 | CopyImage <-> Paint | △ |
| 8.1-6 | CopyMultipleFormats -> Word / Notepad | △ |
| 8.1-7 | text + HTML -> GetPreferredFormat | △ |
| 8.1-8 | files only -> GetPreferredFormat | △ |
| 8.1-9 | image only -> GetPreferredFormat | △ |
| 8.1-10 | custom only -> GetPreferredFormat | △ |

### v5 §8.2 Monitoring / Deferred

| No | 観点 | 評価 | 備考 |
|---|---|---|---|
| 8.2-1 | Init -> external copy | △ | 外部操作未確認 |
| 8.2-2 | self copyの通知抑止 | ○ | 3秒間の負条件テスト成功 |
| 8.2-3 | Uninit TRUE -> external copy | △ | 外部操作未確認 |
| 8.2-4 | Reserve -> external paste | △ | 外部操作未確認 |
| 8.2-5 | Reserve -> Word paste | △ | 外部操作未確認 |
| 8.2-6 | Reserve -> enumerate | ○ | UIテスト成功 |
| 8.2-7 | Reserve -> app exit -> paste | △ | 外部操作未確認 |
| 8.2-8 | Reserve -> external copy | △ | 外部操作未確認 |

### v5 §8.3 History

| No | 観点 | 評価 |
|---|---|---|
| 8.3-1 | AvailabilityとWindows settingの一致 | △ |
| 8.3-2 | disabled -> GetHistory | △ |
| 8.3-3 | GetHistory callbackの順序・timestamp | △ |
| 8.3-4 | Restore callback待機 -> Paste | △ |
| 8.3-5 | Delete callback待機 -> GetHistory | △ |
| 8.3-6 | Clear callback待機 -> GetHistory | △ |
| 8.3-7 | history callbacks -> copy / setting change | △ |
| 8.3-8 | SENSITIVE -> Win+V | △ |
| 8.3-9 | EXCLUDE_ROAMING -> another device | △ |
| 8.3-10 | GetHistory -> Cancel | △ |

### v5 §8.4 Lifecycle / Thread / Busy

| No | 観点 | 評価 |
|---|---|---|
| 8.4-1 | Initializeを2回 | ○ |
| 8.4-2 | Request + Immediate Uninitialize | ○ |
| 8.4-3 | ShuttingDownで通常操作拒否 | ○ |
| 8.4-4 | ShuttingDownで通常Initialize拒否 | ○ |
| 8.4-5 | Force Initialize | ○ |
| 8.4-6 | drain後CanDestroy | ○ |
| 8.4-7 | Uninitialize retry | ○ |
| 8.4-8 | cleanup完了ログ | ○ |
| 8.4-9 | 再Initialize -> Copy | ○ |
| 8.4-10 | worker Reserve | ○ |
| 8.4-11 | worker Uninit | ○ |
| 8.4-12 | Back -> re-entry | ○ |
| 8.4-13 | request -> Back -> re-entry | ○ |
| 8.4-14 | delayed中に通常操作 | ○ |
| 8.4-15 | delayed中CanDestroy | ○ |
| 8.4-16 | delayed -> Back -> re-entry | ○ |
| 8.4-17 | delayed完了後busy解除 | ○ |

### v5 §8.5 Error cases

| No | 観点 | 評価 |
|---|---|---|
| 8.5-1 | null text | ○ |
| 8.5-2 | Paste after Clear | ○ |
| 8.5-3 | PasteHtml with text only | ○ |
| 8.5-4 | image size query | ○（CopyImage前提） |
| 8.5-5 | CF_BITMAP in multiple | ○ |
| 8.5-6 | duplicate format | ○ |
| 8.5-7 | CF_DIB + text payload | ○ |
| 8.5-8 | empty file array | ○ |
| 8.5-9 | Copy after Uninit | ○ |
| 8.5-10 | unknown cancel ID | ○ |

### v5 §8.6 Package

| 観点 | 評価 | 備考 |
|---|---|---|
| 配置済みMSIXの起動 | ○ | AUMIDから起動し33件成功 |
| Visual Studio Deploy + F5による手動確認 | △ | 未実施 |
| unpackaged history API | △ | 計画どおり未確認 |

## 総合評価

**LGTM**

- v1からv3までのコード指摘はすべて解消し、今回の再実行でもUIテスト33件が成功した。
- コードレビューは完了とする。
- 外部アプリ、Win+V、Windows設定、別デバイス、deferred renderingを使う26項目は未確認であり、リリース前の手動確認としてopenのまま残る。
