# macOS 共有（Share）機能 調査企画書

- 対象OS: macOS 15 以降
- 使用言語: Swift（AppKit）
- 作成日: 2026-07-11
- 出力言語: 日本語

---

## 1. 目的

macOS における「共有（Share）」機能を、公式ドキュメント（Apple Developer Documentation / AppKit）を最優先ソースとして API 全網羅で調査し、実装着手に耐える企画書としてまとめる。

iOS の Share（`UIActivityViewController` ベース、実装済み）に対応する macOS 版であり、AppKit の `NSSharingServicePicker` / `NSSharingService` を中心に、自アプリのコンテンツを共有先（Mail / Messages / AirDrop / メモ / SNS 等）へ渡す送信機能を対象とする。

---

## 2. 調査対象範囲（in / out）

### in（対象）

- 共有ピッカー表示: `NSSharingServicePicker`（ボタン等からポップオーバー/メニュー表示）
- ピッカーのカスタマイズ: `NSSharingServicePickerDelegate`（サービス絞り込み・選択通知）
- 個別サービスの直接実行: `NSSharingService`（`init(named:)` / `perform(withItems:)` / `canPerform(withItems:)`）
- カスタムサービス: `NSSharingService(title:image:alternateImage:handler:)`
- 共有アイテムのメタ設定: 書き込み可能な `recipients` / `subject` / `menuItemTitle`（本文・添付は items 側で表現。`messageBody` / `attachmentFileURLs` は readonly）
- 共有プレゼンテーション/完了ハンドリング: `NSSharingServiceDelegate`（willShare/didShare/didFailToShare、位置・アニメーション）
- 共有可能サービスの照会: `NSSharingService.sharingServices(forItems:)`（非推奨、注記付き）

### out（対象外）

- ツールバー統合 `NSSharingServicePickerToolbarItem`（`NSToolbar` に Share ボタンを常設するホストアプリ向け UI コンポーネント。ツールバーを自前で持たない Unity bridge 構成では、通常はボタン押下起点の `NSSharingServicePicker` を優先するため採用しない。概要のみ）
- 共同編集（Collaboration / iCloud 共有、`CollaborationModeRestriction`）は概要のみ、詳細実装は対象外
- 受信側（他アプリからの共有受け取り。macOS では Share Extension が必要で別ターゲット）
- Mac Catalyst 向け `UIActivityItemsConfiguration` 経路（本 toolkit は AppKit ネイティブ想定）

---

## 3. 公式文書一覧（最優先ソース）

| 区分 | タイトル | URL |
| --- | --- | --- |
| HIG | Sharing（Human Interface Guidelines） | https://developer.apple.com/design/human-interface-guidelines/sharing |
| AppKit | NSSharingServicePicker | https://developer.apple.com/documentation/appkit/nssharingservicepicker |
| AppKit | NSSharingServicePickerDelegate | https://developer.apple.com/documentation/appkit/nssharingservicepickerdelegate |
| AppKit | NSSharingService | https://developer.apple.com/documentation/appkit/nssharingservice |
| AppKit | NSSharingService.Name（サービス識別子） | https://developer.apple.com/documentation/appkit/nssharingservice/name |
| AppKit | NSSharingServiceDelegate | https://developer.apple.com/documentation/appkit/nssharingservicedelegate |
| AppKit | NSSharingServicePickerToolbarItem | https://developer.apple.com/documentation/appkit/nssharingservicepickertoolbaritem |
| AppKit | NSPasteboardWriting（共有アイテムの型） | https://developer.apple.com/documentation/appkit/nspasteboardwriting |
| AppKit | NSSharingServicePicker.standardShareMenuItem | https://developer.apple.com/documentation/appkit/nssharingservicepicker/standardsharemenuitem |

---

## 4. 補助ソース一覧（必要時のみ）

| 情報源 | 用途 | 信頼度 |
| --- | --- | --- |
| Apple Sample Code「SharingServices」 | ピッカー/サービスの実装例（アーカイブ） | high（Apple 公式サンプル） |
| Apple Developer Forums（Share menu 関連スレッド） | ドキュメントアプリの Share メニュー統合の落とし穴把握 | medium |

補足: 非公式ブログ等は本企画書には採用せず、公式ドキュメントと Apple 公式サンプルのみで構成した。

---

## 5. 機能マップ（サブ機能分解）

- S1. 共有ピッカーの表示 — `NSSharingServicePicker` + `show(relativeTo:of:preferredEdge:)`
- S2. ピッカーのサービス絞り込み・選択通知 — `NSSharingServicePickerDelegate`
- S3. 個別共有サービスの直接実行 — `NSSharingService`（named / perform / canPerform）
- S4. カスタム共有サービス — `NSSharingService(title:image:alternateImage:handler:)`
- S5. 共有アイテムのメタ設定 — 書き込み可: `recipients` / `subject` / `menuItemTitle`（本文・添付は items 側。`messageBody` / `attachmentFileURLs` は readonly）
- S6. 共有プレゼンテーション・完了ハンドリング — `NSSharingServiceDelegate`
- S7. 共有可能サービスの照会（補助） — `sharingServices(forItems:)`（非推奨）

---

## 6. API 全網羅表（サブ機能別）

共有アイテム（`items: [Any]`）に使える主な型: `String` / `NSString`, `URL`（Web/ファイル）, `NSImage`, `NSAttributedString`, `NSPasteboardWriting` 準拠オブジェクト。

### S1. 共有ピッカーの表示（NSSharingServicePicker, macOS 10.8+）

| API | 目的 | 主要引数 | 返却/コールバック | エラーケース | 最小利用条件 |
| --- | --- | --- | --- | --- | --- |
| `init(items:)` | 共有対象を指定してピッカー生成 | `items: [Any]` | インスタンス | items が空だと有効サービスが出ない | macOS 10.8+ |
| `show(relativeTo:of:preferredEdge:)` | ピッカーを指定ビュー基準で表示 | `NSRect`, `NSView`, `NSRectEdge` | - | view が window に無いと表示不可。ヘッダ上「**`mouseDown` で呼ぶ必要がある**」旨明記 | macOS 10.8+ |
| `close()` | ピッカーを閉じる | - | - | - | **macOS 13.0+** |
| `standardShareMenuItem` | 標準 Share メニュー項目を取得（`sharingServices(forItems:)` 相当の推奨代替） | - | `NSMenuItem` | - | **macOS 13.0+** |
| `delegate` | ピッカーの delegate | `NSSharingServicePickerDelegate?` | - | - | macOS 10.8+ |

補足: macOS 13 以降は「プレビュー付きポップオーバー」、12 以前は「サービス一覧メニュー」で表示される（`show` の呼び方は共通）。対象 OS は macOS 15 以降のため `close()` / `standardShareMenuItem`（いずれも macOS 13.0+）は利用可能。`standardShareMenuItem` は非推奨の `sharingServices(forItems:)`（S7）を自前で列挙する代わりに、標準 Share メニュー項目として組み込む推奨経路。

### S2. ピッカーのサービス絞り込み・選択通知（NSSharingServicePickerDelegate, macOS）

以下は **Swift シグネチャ**（対応する Objective-C selector を併記）。実装設計へは Swift 名で渡し、selector 名のブレをなくす。

| Swift メソッド | Objective-C selector | 目的 | 返却 | 必須/任意 |
| --- | --- | --- | --- | --- |
| `sharingServicePicker(_:sharingServicesForItems:proposedSharingServices:)` | `sharingServicePicker:sharingServicesForItems:proposedSharingServices:` | 表示するサービスを絞り込む/追加する | `[NSSharingService]` | 任意 |
| `sharingServicePicker(_:didChoose:)` | `sharingServicePicker:didChooseSharingService:` | ユーザーがサービスを選択した通知（`service == nil` は未選択で閉じた） | - | 任意 |
| `sharingServicePicker(_:delegateFor:)` | `sharingServicePicker:delegateForSharingService:` | 選択サービス用の `NSSharingServiceDelegate` を供給 | `NSSharingServiceDelegate?` | 任意 |
| `sharingServicePickerCollaborationModeRestrictions(_:)` | `sharingServicePickerCollaborationModeRestrictions:` | 共同編集モードの制限（概要のみ・対象外） | `[NSSharingServicePicker.CollaborationModeRestriction]` | 任意 |

### S3. 個別共有サービスの直接実行（NSSharingService, macOS 10.8+）

| API | 目的 | 主要引数 | 返却 | 備考 |
| --- | --- | --- | --- | --- |
| `init(named:)` | 名前で標準サービスを取得 | `NSSharingService.Name` | `NSSharingService?` | 非対応名は nil |
| `perform(withItems:)` | サービスを実行して共有 | `items: [Any]` | - | UI はサービス側が表示 |
| `canPerform(withItems:)` | サービスが対象を共有可能か判定 | `items: [Any]` | `Bool` | ボタン活性判定に使う |
| `sharingServices(forItems:)`（class） | items を共有できるサービス一覧 | `items: [Any]` | `[NSSharingService]` | **非推奨**（後述） |

SDK（Xcode 26.3 / `NSSharingService.h`）で確認できる主な `NSSharingService.Name`（macOS 15 でも有効）:

| 定数 | 用途 | 備考 |
| --- | --- | --- |
| `.composeEmail` | メール作成 | `recipients` / `subject` 設定可 |
| `.composeMessage` | メッセージ作成 | `recipients` 設定可 |
| `.sendViaAirDrop` | AirDrop 送信 | 環境（署名/entitlement）依存 |
| `.addToSafariReadingList` | Safari リーディングリスト追加 | URL 対象 |
| `.addToIPhoto` / `.addToAperture` | 写真アプリ連携 | 環境依存 |
| `.useAsDesktopPicture` | デスクトップピクチャ設定 | 画像対象 |
| `.cloudSharing` | iCloud 共有 | 共同編集系（詳細は対象外） |

deprecated / unavailable（macOS 15 では利用不可前提。歴史的 API として記載のみ、主経路には使わない）:

| 定数 | 状態 |
| --- | --- |
| `.postOnFacebook` / `.postOnTwitter` / `.postOnSinaWeibo` / `.postOnTencentWeibo` / `.postOnLinkedIn` | SNS 系。macOS 10.14 で system から除外・deprecated |

補足: 「メモ（Notes）へ追加」等は Picker の proposed services には出得るが、SDK 上に直接 `init(named:)` で取得できる `NSSharingService.Name` 定数（`.addToNotes` 等）は確認できないため、直接実行前提の一覧からは除外し、Picker 経由で扱う。

### S4. カスタム共有サービス（NSSharingService, macOS 10.8+）

| API | 目的 | 主要引数 | 返却 |
| --- | --- | --- | --- |
| `init(title:image:alternateImage:handler:)` | 独自アクションをピッカーに追加 | `String`, `NSImage`, `NSImage?`, `() -> Void` | インスタンス |

`sharingServicePicker(_:sharingServicesForItems:proposedSharingServices:)` の戻り値にカスタムサービスを追加してピッカーに載せる。

### S5. 共有アイテムのメタ設定（NSSharingService プロパティ, macOS 10.8+）

**書き込み可能（read/write。共有前に設定して挙動を制御する）** — Xcode 26.3 SDK `NSSharingService.h` で確認

| プロパティ | 型 | 目的 |
| --- | --- | --- |
| `recipients` | `[String]?` | 宛先（メール/メッセージ等） |
| `subject` | `String?` | 件名 |
| `menuItemTitle` | `String` | ピッカー/メニューでの表示名 |

**読み取り専用（readonly。共有アイテムや共有後の結果を参照する）**

| プロパティ | 型 | 目的 |
| --- | --- | --- |
| `messageBody` | `String?` | サービスが構成した本文（**readonly**。設定不可） |
| `attachmentFileURLs` | `[URL]?` | サービスが扱う添付ファイル URL（**readonly**。設定不可） |
| `title` | `String` | サービス表示名 |
| `image` / `alternateImage` | `NSImage` | サービスアイコン |
| `permanentLink` | `URL?` | 投稿後のパーマリンク |
| `accountName` | `String?` | アカウント名（対応サービスのみ） |

注意: `messageBody` / `attachmentFileURLs` は **readonly** のため直接代入できない。本文・添付は `perform(withItems:)` に渡す `items` 側で表現する（本文は `String`、添付はファイル `URL` を items に含める）。

### S6. 共有プレゼンテーション・完了ハンドリング（NSSharingServiceDelegate, macOS）

| API | 目的 | 主要引数 | 返却 |
| --- | --- | --- | --- |
| `sharingService(_:willShareItems:)` | 共有開始直前通知 | service, items | - |
| `sharingService(_:didShareItems:)` | 共有完了通知（成功） | service, items | - |
| `sharingService(_:didFailToShareItems:error:)` | 共有失敗通知（キャンセル含む場合あり） | service, items, `Error` | - |
| `sharingService(_:sourceFrameOnScreenForShareItem:)` | 遷移アニメの元フレーム | service, item | `NSRect` |
| `sharingService(_:transitionImageForShareItem:contentRect:)` | 遷移画像のカスタム | service, item, `*NSRect` | `NSImage?` |
| `sharingService(_:sourceWindowForShareItems:sharingContentScope:)` | 共有元ウィンドウ供給 | service, items, `*SharingContentScope` | `NSWindow?` |
| `anchoringView(for:showRelativeTo:preferredEdge:)` | ポップオーバーのアンカー供給 | service, `*NSRect`, `*NSRectEdge` | `NSView?` |

注意: `didFailToShareItems:error:` の `error` が「ユーザーキャンセル」を表すか失敗を表すかは要検証。iOS の completion のような明確な completed フラグは無い。

### S7. 共有可能サービスの照会（補助・非推奨）

| API | 目的 | 注記 |
| --- | --- | --- |
| `NSSharingService.sharingServices(forItems:)` | items を共有できるサービス配列を取得 | 公式ドキュメントで deprecated。`NSSharingServicePicker` の delegate（`sharingServicesForItems:proposedSharingServices:`）で proposed を使う方式、またはメニュー統合なら `NSSharingServicePicker.standardShareMenuItem`（macOS 13.0+）が推奨代替。カスタム UI を自前で組む場合のみ利用検討（要検証） |

---

## 7. 実装リスク（権限・制約・互換性）

| リスク | 内容 | 対応 |
| --- | --- | --- |
| ピッカー表示にビューが必須 | `show(relativeTo:of:)` は window に載った `NSView` が必要。ヘッドレス/バックグラウンドから呼べない | 表示元ビュー（ボタン等）を必須引数にする。root/key window 解決を helper 化 |
| ピッカー表示は `mouseDown` 起点が前提 | AppKit ヘッダで `show(relativeTo:of:preferredEdge:)` は「`mouseDown` イベント内で呼ぶ必要がある」旨が明記。Unity/native bridge から任意タイミングで呼ぶと表示が不安定になり得る | ピッカー表示はボタン押下等のユーザー操作イベントに紐づける。恒常的な導線が必要なら `standardShareMenuItem`（メニュー統合）も検討 |
| メインスレッド制約 | AppKit UI は main thread 必須 | 表示・delegate コールバックを `@MainActor` / main queue に固定 |
| 完了/キャンセルの区別 | iOS の `completed` に相当する明確な API が無い。`didShareItems` / `didFailToShareItems` で近似 | delegate で willShare/didShare/didFail を受け、キャンセルの扱いは要検証として明記 |
| `sharingServices(forItems:)` 非推奨 | 直接呼ぶと将来非対応の恐れ | ピッカー + delegate 方式を主とし、非推奨 API は使わない |
| サービスの環境依存 | Facebook 等一部サービスは OS/サインイン状態で非表示 | 除外/非表示は環境依存として手動確認前提 |
| ファイル共有のサンドボックス | サンドボックス App では共有ファイルへのアクセス権が必要 | Entitlement / security-scoped の要否を要検証 |
| App Sandbox と AirDrop | AirDrop 等は entitlement 依存の場合あり | 配布形態（署名/sandbox）ごとに要検証 |

---

## 8. 簡単なサンプルコード集（サブ機能別）

### S1. 共有ピッカーの表示（最小）

```swift
import AppKit

func showSharePicker(items: [Any], from view: NSView) {
    let picker = NSSharingServicePicker(items: items)
    // ボタンの下端からポップオーバー表示
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
}

// 使用例: showSharePicker(items: ["Shared text", URL(string: "https://example.com")!], from: shareButton)
```

### S2. ピッカーの delegate（サービス絞り込み + 選択通知）

```swift
import AppKit

final class SharePickerHandler: NSObject, NSSharingServicePickerDelegate {
    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        // 例: AirDrop を先頭に、コピー系を除外するなどの絞り込み
        return proposed
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        // service == nil はピッカーを閉じた（未選択）
        print("chosen:", service?.title ?? "none")
    }
}
```

### S3. 個別サービスの直接実行（AirDrop / Mail）

```swift
import AppKit

func shareViaAirDrop(items: [Any]) {
    guard let service = NSSharingService(named: .sendViaAirDrop),
          service.canPerform(withItems: items) else { return }
    service.perform(withItems: items)
}

func shareViaEmail(text: String, subject: String, to recipients: [String]) {
    guard let service = NSSharingService(named: .composeEmail) else { return }
    service.subject = subject
    service.recipients = recipients
    service.perform(withItems: [text])
}
```

### S4. カスタム共有サービス

```swift
import AppKit

func makeCustomService() -> NSSharingService {
    let icon = NSImage(named: NSImage.shareTemplateName) ?? NSImage()
    return NSSharingService(title: "Copy Link",
                            image: icon,
                            alternateImage: nil) {
        // 独自の共有アクション（例: クリップボードへコピー）
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://example.com", forType: .string)
    }
}
```

### S5. 共有アイテムのメタ設定（件名・宛先・添付）

`subject` / `recipients` は書き込み可能。本文（`messageBody`）と添付（`attachmentFileURLs`）は **readonly** なので代入せず、本文は `String`、添付はファイル `URL` として `perform(withItems:)` の items 側に渡す。

```swift
import AppKit

func shareFileByEmail(fileURL: URL, subject: String, body: String, to: [String]) {
    guard let service = NSSharingService(named: .composeEmail) else { return }
    service.subject = subject          // 書き込み可
    service.recipients = to            // 書き込み可
    // messageBody / attachmentFileURLs は readonly。items 側で表現する。
    service.perform(withItems: [body, fileURL])
}
```

### S6. 完了ハンドリング（NSSharingServiceDelegate）

```swift
import AppKit

final class ShareResultHandler: NSObject, NSSharingServiceDelegate {
    func sharingService(_ s: NSSharingService, willShareItems items: [Any]) {
        print("willShare:", items.count)
    }
    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) {
        print("didShare (success)")
    }
    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        // キャンセルか失敗かは error 内容で判定（要検証）
        print("didFail:", error.localizedDescription)
    }
}

// 使用例:
// let service = NSSharingService(named: .composeMessage)!
// service.delegate = resultHandler
// service.perform(withItems: ["Hello"])
```

### S7. 共有可能サービスの照会（非推奨・参考）

```swift
import AppKit

// 非推奨。カスタム UI を自前で組む場合のみ。通常は Picker + delegate を使う。
func availableServices(for items: [Any]) -> [NSSharingService] {
    return NSSharingService.sharingServices(forItems: items)
}
```

---

## 9. Definition of Done

- [ ] 共有ピッカー: `NSSharingServicePicker` をボタン等の `NSView` 基準で表示できる
- [ ] 共有アイテム種別: テキスト / URL / 画像（`NSImage`）/ ファイル URL を共有できる
- [ ] delegate: `sharingServicesForItems` でサービス絞り込み、`didChoose` で選択を取得できる
- [ ] 個別サービス: `NSSharingService(named:)` + `canPerform` + `perform` で AirDrop / Mail 等を直接実行できる
- [ ] カスタムサービス: `init(title:image:alternateImage:handler:)` でピッカーに独自アクションを追加できる
- [ ] メタ設定: 書き込み可能な `subject` / `recipients` / `menuItemTitle` が対応サービスに反映される
- [ ] 本文・添付: `perform(withItems:)` に渡した `String` 本文・ファイル `URL` 添付が共有先に反映される（`messageBody` / `attachmentFileURLs` は readonly のため代入しない）
- [ ] 完了ハンドリング: `NSSharingServiceDelegate` の will/did/didFail を受け取れる
- [ ] メインスレッドで表示・コールバック処理を行う
- [ ] ピッカー表示をユーザー操作イベント（ボタン押下 = `mouseDown` 起点）に紐づけ、任意タイミング表示にしていない
- [ ] 非推奨 API（`sharingServices(forItems:)`）を主経路に使っていない
- [ ] macOS 15 実機で送信・各共有先の受領を確認（要検証項目を消し込み）

---

## 10. 要検証（断定を避けた項目）

- `NSSharingServiceDelegate.didFailToShareItems:error:` が「ユーザーキャンセル」を表すケースの有無と、iOS の `completed=false` に相当する表現方法
- サンドボックス App でのファイル共有（`attachmentFileURLs`）に必要な entitlement / security-scoped resource の要否
- AirDrop 等一部サービスの entitlement・署名依存
- macOS 13+ のポップオーバー表示と 12 以前のメニュー表示で、delegate 挙動やプレビュー差異があるか
- `NSSharingServicePicker` が共有完了/キャンセルを picker 自身の delegate（`didChoose`）だけで十分に判定できるか、`NSSharingServiceDelegate` 併用が必要か
- 本企画書の各サンプルコードを Xcode（macOS 15 / Swift）で実際に typecheck し、delegate selector 名・プロパティの read/write 区分にコンパイルエラーがないことを実装着手前に確認する
- `standardShareMenuItem`（macOS 13.0+）を Unity bridge のメニュー導線に組み込む場合の実装可否と、`show(relativeTo:)` 経路との使い分け
