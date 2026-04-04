## Plan: Unity通知機能 初期リリース設計

初期リリースは `android_library` の既存通知基盤を再利用しつつ、`unity_android_plugin` に Unity 向けの薄い通知ブリッジを追加する方針で進めます。対象は Basic 通知・Schedule・Progress FGS に限定し、CallStyle や高度な interaction は後続フェーズへ分離して、Unity 側の導入コストと Android 制約対応を抑えます。

### Steps
1. 整理する `unity_android_plugin/MODULE.md` に初期公開範囲を Basic / Schedule / Progress FGS と明記する。  
2. 追加する `UnityAndroidDialogManager.kt` と同じ方針で `UnityAndroidNotificationManager` を設計する。  
3. 包む `AndroidNotificationCommand`・`NotificationContent`・`NotificationStyle` を Unity DTO 層で単純化する。  
4. 接続する `NotificationPermissionHelper` と各 `UseCase` を、permission / channel / show / update / cancel / schedule API に橋渡しする。  
5. 活用する `ProgressForegroundNotifications` と `ProgressForegroundService` を Unity 用 progress API の背後実装に使う。  
6. 分離する `android_library/src/main/AndroidManifest.xml` 依存事項を整理し、Unity 初期版では schedule receiver と progress FGS 前提だけをガイド対象にする。  

### Further Considerations
1. Unity 入力形式は JSON DTO 推奨です。`Intent`・sealed class・JNI 配列変換の複雑さを抑えられます。  
2. 初期 style は Default / BigText / Inbox / BigPicture / Messaging まで推奨です。Media / customView は第2段階が安全です。  
3. これはドラフトです。次は `presentation.notification` の公開 API 粒度まで詰める形でよいですか。

