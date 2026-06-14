引数: $ARGUMENTS

## 対応 OS バージョン

- Android 12 以降
- iOS 18 以降
- Windows 11 以降
- macOS 15 以降

以下の手順を実行してください。

1. `$ARGUMENTS` を解析する（最小限）
   - `lang=ja` または指定なしは出力言語を日本語として扱う
   - `lang=en` が明示的にあれば英語

2. インタラクティブ入力でパラメータを確定する（必須）
   - ダイアログで「実装対象の設計書ファイルを指定してください」と促す
   - 入力がない場合は `artifact/designs/<feature>/` 配下の `*-design*.md` を探索し、同一ドキュメントの改訂版（`-v2`, `-v3` など）がある場合は最も大きいバージョンのみを候補として提示する
   - バージョンサフィックスがないファイルは `v1` とみなし、`vN` が存在する場合は `vN` を優先する
   - ダイアログで「対象OSを選択してください」と促す（ラジオボタン: Android / iOS / macOS / Windows）

3. 設計書を読み込み、実装前提を固定する（必須）
   - 設計書から次を抽出する:
     - スコープ（in / out）
     - サブ機能別詳細設計
     - API 設計（公開 / 内部）
     - ドメインエラー一覧（全ケース）
     - エラーコード/メッセージ対応表
     - テスト設計
     - 実装タスク分解（依存関係付き）
     - Definition of Done
   - 設計書に不足がある場合は「不足前提」を明記し、勝手に要件追加しない

4. 実装制約を固定する（必須）
   - `agent-rules/coding-rules/common.md` を読み込み、共通実装方針を固定する
   - 対象OSの個別ルールファイル（`agent-rules/coding-rules/<os>.md`）を読み込み、実装制約を固定する
   - ドメインエラーの全ケース一覧と返却メッセージ/エラーコード対応表を、実装・Bridge返却・テストへ反映する

5. 変更対象を確定する（必須）
   - 設計書にある変更対象ファイル群を実在パスで確認する
   - 新規作成 / 既存変更 / 非変更を分類する
   - 依存関係の順で実装順序を確定する（基盤 -> 機能 -> Bridge -> テスト -> ドキュメント）

6. 実装を行う（必須）
   - 設計書に沿ってファイルを作成・更新する
   - サブ機能単位で段階的に実装する
   - 公開APIのスレッド契約、メモリ契約、エラー契約をコードへ反映する
   - 既存API互換性を維持し、破壊的変更は明示承認なしで行わない

7. テストを実装・更新する（必須）
   - 設計書のテスト設計に従い、単体・統合・手動確認項目を反映する
   - ドメインエラー全ケースについて、errorCode/errorMessage 対応を検証する
   - `isSuccess == true` のとき `errorCode == 0` / `errorMessage == nil` を検証する

8. ビルド・テストを実行する（必須）
   - 対象OSモジュールのビルドを実行する
   - **Android / iOS / macOS / Windows の場合は、通常ビルドに加え成果物生成スクリプト（`scripts/`）を必ず実行し、成果物が問題なく生成できることを確認する**
     - Android: `./scripts/build_android_library_aar.sh -b release -m <module> -v <version> -o /tmp/<module>-verify.aar`
       - 成功確認: `[done] Created /tmp/<module>-verify.aar`
     - iOS: `./scripts/build_ios_library_xcframework.sh -c release -m <module> -v <version> -o /tmp/<module>-verify.xcframework`
       - 成功確認: `** ARCHIVE SUCCEEDED **` と `[done] ... Created ...xcframework`
     - macOS: `./scripts/build_xcode26_library_xcframework.sh -c release -m <module> -v <version> -o /tmp/<module>-verify.xcframework --minimum-macos 15.0`
       - 成功確認: `** ARCHIVE SUCCEEDED **` と `[done] ... Created ...xcframework`
     - Windows: `powershell -File scripts\build_windows_library_dll.ps1 -c release -m WindowsLibrary -v <version> -o "$env:TEMP\windows-native-toolkit-verify.dll"`
       - 成功確認: `[done] [WindowsLibrary] Created ...windows-native-toolkit-verify.dll and ...windows-native-toolkit-verify.lib`（終了コード 0）
       - 生成物: 配布名の `.dll` と `.lib`（`.def` の export が解決できること）。NuGet パッケージまで検証する場合は `-Package` を付ける（`dist/<version>/windows/nuget/NativeToolkit/NativeToolkit.<version>.nupkg` を生成、`nuget` が PATH 必須）
     - 失敗した場合はビルドログの `error:` / `[ERROR]` 行を特定し、原因を修正してから再実行する
   - **`dist/<toolkit-version>/` に配置するファイルのファイル名は、そのOSライブラリの実際のバージョンと一致させる**
     - OS ごとにライブラリバージョンは異なってよい（例: `dist/1.3.0/android/android-native-toolkit-1.1.0.aar`）
     - ビルドスクリプトの `-v <version>` には OS ライブラリの実際のバージョンを指定する
   - 追加・更新したテストを実行し、失敗時は原因を修正する
     - Android: `./gradlew :<module>:testReleaseUnitTest`（または対象テストタスク）
     - iOS / macOS: `xcodebuild test -scheme <scheme> -destination <destination>`
     - Windows: MSBuild でテストプロジェクトをビルド後、`vstest.console.exe <TestProject>\x64\Debug\<TestProject>.dll`（CppUnitTest）を実行し、全ケース passed を確認する
   - 実機依存で自動化できない項目は「手動確認が必要」と明記する

9. 実装結果を検証する（必須）
   - 設計書の Definition of Done に対して達成状況をチェックする
   - 変更ファイル一覧と、設計差分（計画通り/差分あり）を整理する
   - 設計差分が発生した場合は理由と影響範囲を明記する

10. 実行確認を行う

- 実装はそのまま実施し、実装完了後にのみ本確認を行う（実装前の事前確認はしない）
- ユーザーに次を確認する: 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了

11. 完了結果ファイルを保存する（必須）

- ステップ10の確認を提示した直後に、今回の実装結果をファイルへ保存する
- 保存先は `artifact/results/<feature>/` とし、必要に応じてディレクトリを作成する
- ファイル名は `YYYY-MM-DD-<os>-<feature>-implementation-feature-result-vN.md` を基本とする
- 同名が存在する場合は `vN` をインクリメントし、既存ファイルを上書きしない
- 記載内容は `agent-rules/workflows/implement-feature/IMPLEMENT_RESULT_TEMPLATE.md` に従う
- 最低限、以下を必ず含める:
  - 実装サマリー（設計書由来 / 実装時追加判断の分離）
  - ビルド結果（実行コマンド、成功/失敗）
  - テスト結果（実行項目、件数、失敗有無、未実施理由）
  - DoD達成状況
  - ステップ10の提示文と選択肢

12. 出力ルール

- 設計書由来の実装内容と、実装時の追加判断を明確に分離する
- 変更対象ファイルは可能な限り具体パスで示す
- ドメインエラー一覧とエラーコード/メッセージ対応表の実装反映状況を必ず報告する
- テスト結果は「実行したテスト」「失敗有無」「未実施理由」を明記する
- 不確実な事項は断定せず、要検証として明記する
- 文章は簡潔に、箇条書き中心で書く
- 絵文字は使用しない
