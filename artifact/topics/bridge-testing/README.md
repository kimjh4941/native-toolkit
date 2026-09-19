# ブリッジ層の検証負債

- 記録日: 2026-08-15
- 分類: 横断課題（機能単位でも 1 チケット単位でもない）
- 関連: 設計書 `2026-08-02-ios-clipboard-design-v4.md` の T-11b（I-08 / I-09）

## 何が問題か

Unity から呼ばれる **Objective-C ブリッジ（`.m`）を通るテストが、iOS の 4 機能すべてに存在しない。**

```
Unity C# (DllImport)              ← unity-native-plugin リポジトリの担当
        ↓
UnityIos*ManagerBridge.m          ← ここを通るテストがゼロ
        ↓
UnityIos*Manager (Swift)
        ↓
Ios*Manager (Swift)
```

Clipboard 実装時に発見した。Clipboard 固有ではなく、**リポジトリの構造的な穴**である。

## iOS の現状（2026-08-15 実測）

| 機能 | Swift facade | ObjC ブリッジ | テスト |
|---|---|---|---|
| Clipboard | あり | `.m` あり | JsonParser 197 行 + CallbackContract 189 行 |
| Notification | あり | `.m` あり | JsonParser 414 行のみ |
| Share | あり | `.m` あり | JsonParser 97 行 + Manager 24 行 |
| **Dialog** | あり | `.m` あり | **なし** |

`UnityIosPluginTests.swift` は 17 行のテンプレート。
テストコード中の C 関数呼び出しは **0 件**（`grep -c "clipboard_\|dialog_\|notification_\|share_"`）。

**Notification / Dialog / Share は、この状態で v1.8.0 として出荷済み。**

## 他プラットフォーム

**未調査。** Android の JNI 層、Windows の C API 層にも同じ穴がある可能性がある。着手時にまず確認すること。

## 責任分界

Unity 側の実装・検証は `https://github.com/kimjh4941/unity-native-plugin` へ移管した。境界は次のとおり。

| 層 | 担当 |
|---|---|
| C# ↔ native | unity-native-plugin |
| **ObjC ブリッジ ↔ Swift facade** | **native-toolkit（本リポジトリ）** |
| Swift facade ↔ ライブラリ本体 | native-toolkit |

xcframework を渡す側として、**渡す前にブリッジ経路を検証しておく**のが本リポジトリの責任範囲。
C# 側のテストだけでは、不具合が C# / ObjC / Swift のどこにあるか切り分けられない。

## この層でしか出ない不具合

| 例 | なぜ他層で見つからないか |
|---|---|
| ブロック引数の `bool` と `BOOL` の不一致 | 型が合わないと C# からは「たまに壊れる」としか見えない |
| C 文字列の寿命（解放後参照） | 同上 |
| NULL ハンドラの扱い | Swift 側テストでは NULL を渡せない |
| callback の呼び出しスレッド | C# 側からは observable でないことがある |

## 優先度

カバレッジの薄い順。

```
Dialog（テストゼロ） > Notification > Share > Clipboard
```

Clipboard は 4 機能中もっとも手厚い。**この課題は Clipboard のリリースを止める理由にしない**
（既存 3 機能と同条件のため）。

## DoD（着手時）

- [ ] Android / Windows のブリッジ層に同じ穴があるか調査する
- [ ] 各機能の全 endpoint を ObjC 側から直接呼ぶ統合テストを追加する
- [ ] NULL ハンドラ、C 文字列の寿命、callback スレッドを含める
- [ ] Dialog を最優先で着手する
- [ ] 着手時にチケットを割り当てる（本ファイルはチケット化前の記録）

## 備考

本ファイルは**チケットを立てずに記録だけ残したもの**。着手を決めた時点でチケット化し、
必要なら企画書・設計書を `artifact/plans/` `artifact/designs/` へ起こす。
