# 2b の締め: 配布用の署名とプライバシーのレポート（利用者の手順）

- 作成日: 2026-11-14（別モデル 2 者のレビューを反映済み）
- 対象: `artifact/topics/ios-c-abi/README.md` の 9 章（DoD）の 2 項目
  - 配布用の署名（Distribution のアーカイブと Organizer の Validate App）で、2 つの framework がアプリの証明書で署名し直されることを確かめる（D-18）
  - `IosLibrary` のプライバシーマニフェストが、使っている理由の申告が要る API と一致する（アーカイブのプライバシーのレポートで確かめる。段階 1b の MS-10。1b の作業の記録 20.9）
- 行う人: 利用者（段階 2 の作業の記録 17.1 の決定 7）。Mac と Xcode と利用者の開発者のアカウントだけを使い、**実機は使わない**。配布用の書き出しには有料の Apple Developer Program のチームが要る（無料の Personal Team ではできない）
- **公開のリポジトリに書かないもの**: 利用者の名前、Team ID、証明書の名前。知らせてもらうのは「Apple Distribution で始まるか」「同じか」だけで、agent も表にそれ以外を書かない
- 行う時期: `dist/1.14.0` を作った後（17.13）。配る xcframework そのもので確かめるため
- agent は Xcode の画面を見ない。結果は文字で知らせてもらう

## 0. 準備（agent が行う）

agent が `dist/1.14.0/ios/` の 2 つの xcframework から、smoke（`IosLibraryCApiSmoke`）の写しを作る:

```sh
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
scripts/run_ios_capi_smoke.sh --dist dist/1.14.0/ios --work ~/Desktop/ntk-2b-signing --device-build
```

- smoke は C だけで書いたアプリで、`IosLibrary.framework` と `IosLibraryCApi.framework` を **署名なしのまま埋め込み、組むときに署名し直す**（Embed & Sign。`CodeSignOnCopy`）。2 つの framework の両方を 1 回のアーカイブで確かめられる
- 写しはリポジトリの外にあるので、何をしてもリポジトリは変わらない
- `--device-build` で、署名なしの実機向けの組み立て（アーカイブと同じ arm64）が通ることも先に確かめる。シミュレーターも実機も動かさない
- agent は、写しができたことと、2 つの組み立てが通ったことを知らせる

## 1. アーカイブを作る

1. Xcode 26.6 で `~/Desktop/ntk-2b-signing/IosLibraryCApiSmoke/IosLibraryCApiSmoke.xcodeproj` を開く
2. 左でプロジェクトを選び、ターゲット `IosLibraryCApiSmoke` の「Signing & Capabilities」で、「Automatically manage signing」をオンにし、Team に自分のチームを選ぶ（プロジェクトは手動の署名で、Team は空。写しの中だけが変わる）
3. 同じターゲットの「Build Settings」で「Code Signing Identity」を探し、Debug と Release のどちらも「Sign to Run Locally」（`-`）になっていれば「Apple Development」に変える。変えないと「automatically signed, but code signing identity - has been manually specified」の類のエラーになる見込み（プロジェクトの既定は `-`。2026-11-07 の実機の回では、組み立ての旗で同じ上書きをして通った。段階 2 の作業の記録 17.8）
4. 上の実行先で「Any iOS Device (arm64)」を選ぶ
5. メニューの「Product」→「Archive」。終わると Organizer が開き、`IosLibraryCApiSmoke` のアーカイブが出る

## 2. プライバシーのレポート（MS-10）

1. Organizer の「Archives」で今のアーカイブの行を Control キーを押しながらクリックし、「Generate Privacy Report」を選ぶ。保存先はリポジトリの外（デスクトップなど）
2. PDF を開き、次を見る:
   - (a) `IosLibrary.framework` の節があるか
   - (b) その中に「File Timestamp」と理由「C617.1」があるか
   - (c) トラッキングと、集めるデータが無いか
   - (d) ほかに出た節と、その中身（`IosLibraryCApi` はマニフェストを持たないので、その節は出ない見込み。出たら中身を知らせる）
3. レポートに framework ごとの節や理由の番号が出ない場合は、アーカイブの中のマニフェストを直接見る（Organizer でアーカイブを Control キーを押しながらクリック →「Show in Finder」で `.xcarchive` の場所が分かる）:

   ```sh
   plutil -p "<.xcarchive の道>/Products/Applications/IosLibraryCApiSmoke.app/Frameworks/IosLibrary.framework/PrivacyInfo.xcprivacy"
   ```

   `NSPrivacyAccessedAPICategoryFileTimestamp` と `C617.1` があるか、`NSPrivacyTracking` が 0（false）かを知らせる

## 3. 配布用の書き出しと、署名し直しの確かめ（D-18）

1. Organizer で今のアーカイブを選び、「Distribute App」を押す
2. 配り方は **「Release Testing」**（Ad Hoc）を選び、署名は自動のまま進める。自動の署名では、Apple Distribution の証明書と Ad Hoc のプロファイルを、Xcode が聞かずに作ることがある。作られたくなければ、先に Xcode の「Settings」→「Accounts」→「Manage Certificates」で Apple Distribution があるかを見ておく。Ad Hoc のプロファイルには、開発者のアカウントに登録した端末が 1 台以上要る（実機の回で開発用の署名に使った端末が登録済みなら足りる）。**端末をつなぐよう促されても、つながずに止めて知らせる**
3. 書き出し先はリポジトリの外（デスクトップなど）を選ぶ。Xcode はその中に `IosLibraryCApiSmoke <日付と時刻>` のフォルダーを作り、`.ipa`（`IosLibraryCApiSmoke.ipa`）などをそこに置く
4. ターミナルで、`.ipa` の中のアプリと 2 つの framework の署名を見る（`<書き出し先>` は 3 で Xcode が作った `IosLibraryCApiSmoke <日付と時刻>` のフォルダー。名前に空白があるので引用符で囲む）:

   ```sh
   cd "<書き出し先>"
   mkdir ipa && cd ipa && unzip -q ../IosLibraryCApiSmoke.ipa
   for f in Payload/IosLibraryCApiSmoke.app Payload/IosLibraryCApiSmoke.app/Frameworks/IosLibrary.framework \
            Payload/IosLibraryCApiSmoke.app/Frameworks/IosLibraryCApi.framework; do
     echo "== $(basename "$f")"
     codesign -dvv "$f" 2>&1 | grep -E '^Authority=' | head -1 | cut -c1-30
     codesign -dvv "$f" 2>&1 | grep -E '^TeamIdentifier=' | shasum | cut -c1-8
   done
   codesign --verify --deep --strict --verbose=2 Payload/IosLibraryCApiSmoke.app 2>&1 | tail -2
   ```

5. 知らせてほしいこと: 3 つ（アプリと 2 つの framework）の `Authority=` が **Apple Distribution** で始まるか（`cut` で名前の手前までしか出さない。`codesign` は詳しさ 2（`-dvv`）以上でないと `Authority=` を出さない）、3 つの 8 文字の値（`TeamIdentifier=` の行の要約）が同じか（「同じ」「違う」だけでよい）、最後の 2 行が `valid on disk` と `satisfies its Designated Requirement` か

## 4. Validate App（smoke では行わない）

- **smoke にはアプリのアイコンが無い**（asset catalog も `ASSETCATALOG_COMPILER_APPICON_NAME` も無く、iPhone と iPad の両方が対象）ので、App Store の検証はアイコンの欠けで失敗する見込みで、D-18 の判断に使えない。そこで **Validate App は 2c で `unity-native-plugin` の Unity のアプリのアーカイブで行う**ことを既定にする
- Organizer の「Validate App」は App Store Connect へ送る前の検証で、**その bundle ID（`com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke`）のアプリが App Store Connect に登録されていないと、検証まで進めない見込み**（agent は確かめていない）
- それでも smoke で行うなら（利用者が決める）: Organizer で今のアーカイブを選び、「Validate App」→ App Store Connect → 自動の署名で進める。アイコンのエラー（ITMS-90022・90023・90713 の類）は除いて読む。結果（出たエラーと警告の文面）を知らせる。**App Store Connect のアプリの記録を作る画面（名前と SKU の入力）が出たら、登録すると決めていない限り取り消す**。「Distribute App」で App Store Connect へ送ることはしない

## 5. 後片付け

- Organizer でアーカイブを削除する
- `~/Desktop/ntk-2b-signing`、書き出し先のフォルダー（`ExportOptions.plist` と `Packaging.log` にも Team ID が入る）、プライバシーのレポートの PDF を消す（どれもリポジトリに入れない）
- Xcode の画面で組んだ DerivedData（`~/Library/Developer/Xcode/DerivedData/IosLibraryCApiSmoke-*`）を消す
- 自動の署名で開発者のアカウントに登録された App ID（`com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke`。2026-11-07 の実機の回で既に登録された見込み）、プロファイル、証明書は、利用者のアカウントに残る（消すかは利用者が決める）

## 6. 知らせてほしいこと（agent がこの表に書く）

| 項目 | 結果 |
|---|---|
| アーカイブ（1） | |
| プライバシーのレポート（2 の (a)〜(d)） | |
| 署名し直し（3 の 5） | |
| Validate App（4。smoke で行った場合だけ） | |

作れない・進めないところがあれば、その場で止めて、出た文面を知らせる。
