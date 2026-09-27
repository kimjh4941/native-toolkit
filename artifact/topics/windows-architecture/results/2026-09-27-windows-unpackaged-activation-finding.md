# 調査結果: パッケージ化しないアプリに、通知の活性化が届かなかった

- 実施日: 2026-09-27
- 対象: パッケージ化しないアプリの通知の活性化（`UnpackagedBackend`、`windows/WindowsLibrary/src/Notification/Data/WindowsClassicActivator.cpp`）
- ブランチ: `feature/NTKIT-16`
- きっかけ: `unity-native-plugin`（`feature/UNT-12`）からの報告。1.x の C ABI を使うパッケージ化しない Unity アプリで、通知のボタンを押しても `INotificationActivationCallback::Activate` が一度も呼ばれず、新しいプロセスも起動しない

## 1. 何が起きていたか

パッケージ化しないアプリが起動したまま（warm）の状態で、通知のボタンを押しても活性化が届かなかった。通知の表示は正常で、押した通知は通知センターから消える（イベントログには id 3055「Some toast notifications have been cleared」だけが残る）。

**パッケージ化しないアプリの活性化は、この機能ができてから一度も動いていなかった**と考えてよい。このリポジトリのサンプルはパッケージ化（MSIX）されているので、UI テスト 89 件は `AppNotificationManager` の経路しか通らず、`UnpackagedBackend` の活性化には届いていなかった。記録上も「要実機確認」のままだった。

## 2. 原因

ライブラリは `AppUserModelId\<AUMID>` の **`CustomActivator` を書いていなかった**。

登録そのものは次の 3 つを行っていて、いずれも成功していた。

| 登録 | 内容 |
|---|---|
| COM のクラスオブジェクト | `CoRegisterClassObject(clsid, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE)`。CLSID は AUMID から導出（`NameToGuid`） |
| レジストリ | `HKCU\Software\Classes\CLSID\{...}\LocalServer32` と、`HKCU\Software\Classes\AppUserModelId\<AUMID>` の `DisplayName` / `IconUri` |
| ショートカット | スタートメニューに、`PKEY_AppUserModel_ID` と `PKEY_AppUserModel_ToastActivatorCLSID` を持つ `.lnk` |

ショートカットの `ToastActivatorCLSID` だけでは、起動中のプロセスへ活性化が届かなかった。`CustomActivator` を足すと届いた。

報告者の PC の `Unity NativeToolkit` には、以前の Windows App SDK の登録が残した `CustomActivator` があった。報告者はこれを古い登録と見て消したが、実際にはその AUMID に活性化先を与えていた唯一の値だった（ただし指していたのは旧 App SDK の CLSID で、これもこのライブラリには届かない）。**Windows App SDK がこの値を書くのは、それが活性化先を決める仕組みだからである。**

## 3. 確かめ方と結果

Unity を通さない素の Win32 のコンソールアプリ（2.0.0 の C++ API を使う）で確かめた。

- AUMID はこの PC に履歴の無い `NativeToolkit ActivationProbe`
- メインスレッドは STA（Unity と同じ）
- ボタン 1 つの通知を出し、通知センターから押して（この PC は応答不可が ON でバナーが出ないため）、90 秒待つ

| 回 | `CustomActivator` | 結果 |
|---|---|---|
| 1 | 無し（修正前のライブラリの登録のまま） | 届かず、時間切れ |
| 2 | 手で追加 | **届いた**（`raw=[{"action":"open"}]`、`action = open`） |
| 3 | 手で削除 | 届かず、時間切れ |
| 4 | 無し。修正したライブラリが自分で書く | **届いた**。実行後に `CustomActivator = {FE818D52-...}` が書かれていた |

同じ実行ファイル・同じ操作で、変えたのはレジストリの値 1 つだけである（1〜3）。4 回目で、修正したライブラリが自分で書いた値で届くことを確かめた。

- 新しい AUMID で再現したので、**PC の状態の問題ではなく実装の問題**である
- STA のまま届いたので、COM のアパートメント（報告者の仮説の 1 つ）は原因ではない。MTA は試していない
- `SetCurrentProcessExplicitAppUserModelID` はライブラリも呼んでおらず、プローブも呼ばずに届いた。原因ではない
- コールドスタート（プロセスが起動していないときの活性化）は試していない。ライブラリには、コマンドラインの `-ToastActivated` を `Init` で 1 回だけ受け取る別の経路がある。`CustomActivator` と `LocalServer32` はその起動にも使われるはずだが、測っていない

プローブのショートカットとレジストリ（`AppUserModelId\NativeToolkit ActivationProbe` と `CLSID\{FE818D52-...}`）は、確認後に削除した。

## 4. 対処

`UnpackagedBackend::RegisterActivation` が、`DisplayName` / `IconUri` を書いているのと同じキーに `CustomActivator`（活性化の CLSID）を書くようにした。

- 書き込みは上書きなので、以前の Windows App SDK の値が残った PC もこれで直る。別の後片付けは要らない
- 公開ヘッダー（C++ API の `ManagerOptions::displayName`、C ABI の `ntk_notification_manager_options::display_name`）に、パッケージ化しないアプリではこの名前が AUMID になり、ショートカット名・CLSID の導出元・レジストリのキー名を兼ねること、書き込みは上書きなので **同じ `displayName` を使う別のアプリの活性化先を奪う**ことを書いた

1.x と 2.0.0 は、この経路が同一のコードである（`WindowsClassicActivator.cpp` は T-12 の直前の `32a4dffb` と修正前の HEAD で差分が無い）。修正は **2.0.0（dist 1.12.0）だけに入れる**。1.x のパッチは出さない（2026-09-27 利用者の決定）。1.x を使うのは移行中の `unity-native-plugin` だけで、1.x を出すには T-12 で消したビルドの経路を `32a4dffb` から復活させ、2.0.0 を説明するマニュアルと食い違う DLL を配ることになるためである。出荷済みの 1.x（dist 1.11.0、`windows-native-toolkit-1.2.0.dll`）はこの不具合を持ったままで、パッケージ化しないアプリには 1.x の間、ボタンの活性化が届かない。

## 5. 申し送り

`unity-native-plugin` には、原因、修正、手元で試すなら `HKCU\Software\Classes\AppUserModelId\Unity NativeToolkit\CustomActivator = {C66BF59D-6D49-4213-BDDC-8EAD33B69E62}` を書けば動くことを伝えた。1.x には出さないことも伝えた。あちらは CI で値を手書きして通すことはせず（利用者が 1.x で踏む不具合を隠すため）、W-04 と W-11 をライブラリの修正待ちとしてスキップし、前提の確認を「`CustomActivator` がこの AUMID の CLSID であること」に改める。W-04 と W-11 は、C ABI への移行と一緒に戻る。
