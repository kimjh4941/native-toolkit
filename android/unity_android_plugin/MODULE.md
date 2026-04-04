# Module unity_android_plugin

Unity-facing wrapper exposing JNI-friendly singletons for:
- dialogs via `UnityAndroidDialogManager`
- notifications via `UnityAndroidNotificationManager`

The module reuses `android_library` implementations and provides Unity-oriented entry points that are easier to call from C# / JNI.

## Features
- Display multiple dialog patterns via `AndroidDialogFragment` from Unity
- Display / update / cancel native Android notifications from Unity
- Schedule notifications through `AlarmManager`
- Start / update / complete / stop progress foreground-service notifications
- Query notification permission state and open app notification settings
- Singleton access: `UnityAndroidDialogManager.getInstance()`
- Singleton access: `UnityAndroidNotificationManager.getInstance()`
- Per-variant listener registration (Java side)
  - `setDialogListener(...)`, `setConfirmDialogListener(...)`, `setSingleChoiceItemDialogListener(...)`, `setMultiChoiceItemDialogListener(...)`, `setTextInputDialogListener(...)`, `setLoginDialogListener(...)`
- Dialog methods (Java): `showDialog`, `showConfirmDialog`, `showSingleChoiceItemDialog`, `showMultiChoiceItemDialog`, `showTextInputDialog`, `showLoginDialog`
- Control: outside-touch / back-press cancellation flags, positive button gating for TextInput / Login
- Result propagation: dedicated Java listener per variant → mapped to C# events
- Unity C# high-level wrapper `AndroidDialogManager`:
  - Singleton (DontDestroyOnLoad)
  - Initializes Java singleton + registers all listeners in Awake
  - Dispatches Java callbacks onto Unity main thread via `UnityMainThreadDispatcher`
  - Public methods: `ShowDialog`, `ShowConfirmDialog`, `ShowSingleChoiceItemDialog`, `ShowMultiChoiceItemDialog`, `ShowTextInputDialog`, `ShowLoginDialog`
  - Public events: `DialogResult`, `ConfirmDialogResult`, `SingleChoiceItemDialogResult`, `MultiChoiceItemDialogResult`, `TextInputDialogResult`, `LoginDialogResult`

## Notification Bridge (Initial Release Scope)

The initial Unity notification bridge intentionally focuses on the most practical release surface:

- Basic notifications
  - `showNotification(context, notificationJson)`
  - `updateNotification(context, notificationJson)`
  - `cancelNotification(context, id, tag)`
  - `cancelAllNotifications(context)`
- Channels
  - `createChannel(context, channelJson)`
  - `deleteChannel(context, channelId)`
- Schedule notifications
  - `scheduleNotification(context, scheduleJson)`
  - `cancelScheduledNotification(context, id, tag)`
  - `cancelAllScheduledNotifications(context)`
- Progress foreground service
  - `startProgressForegroundService(context, notificationJson)`
  - `updateProgressForegroundService(context, notificationJson)`
  - `completeProgressForegroundService(context, notificationJson)`
  - `stopProgressForegroundService(context)`
- Settings / capability helpers
  - `hasPermission(context)`
  - `areNotificationsEnabled(context)`
  - `openNotificationSettings(context)`
  - `openAppDetailsSettings(context)`
  - `openExactAlarmSettings(context)`

Not included in v1 Unity bridge:
- CallStyle
- inline reply / `RemoteInput`
- custom `RemoteViews`
- `fullScreenIntent`
- media / decorated custom styles

These remain available in `android_library`, but are intentionally excluded from the first Unity-facing API to keep the bridge stable and easy to integrate.

## Notification JSON Contract

### Basic notification JSON
```json
{
  "id": 1001,
  "title": "Native Toolkit",
  "message": "Hello from Unity",
  "tag": "demo",
  "launchAppOnTap": true,
  "launchAction": "native.toolkit.unity.OPEN_MAIN",
  "channel": {
    "id": "general",
    "name": "General",
    "description": "General notifications",
    "importance": 3
  },
  "smallIcon": {
    "name": "ic_launcher",
    "type": "mipmap"
  },
  "style": {
    "type": "bigText",
    "bigText": "Expanded message from Unity.",
    "summaryText": "Summary"
  }
}
```

### Supported style JSON types
- `default`
- `bigText`
- `inbox`
- `bigPicture`
- `messaging`

Examples:

```json
{
  "type": "inbox",
  "lines": ["Line 1", "Line 2", "Line 3"],
  "summaryText": "+3 items"
}
```

```json
{
  "type": "bigPicture",
  "picture": {
    "name": "sample_big_picture",
    "type": "drawable"
  },
  "bigContentTitle": "Picture",
  "summaryText": "Preview"
}
```

```json
{
  "type": "messaging",
  "userDisplayName": "Me",
  "conversationTitle": "Team Chat",
  "isGroupConversation": true,
  "messages": [
    { "text": "Hi", "senderName": "Alice", "timestampMillis": 1710000000000 },
    { "text": "Hello", "senderName": "Bob", "timestampMillis": 1710000005000 }
  ]
}
```

### Scheduled notification JSON
```json
{
  "notification": {
    "id": 2001,
    "title": "Scheduled",
    "message": "This was scheduled from Unity",
    "channel": {
      "id": "general",
      "name": "General"
    }
  },
  "schedule": {
    "triggerAtMillis": 1893456000000,
    "exact": true,
    "allowWhileIdle": true,
    "persistAcrossBoot": true,
    "alarmType": 0
  }
}
```

### Progress FGS JSON
```json
{
  "id": 3001,
  "title": "Background Sync",
  "message": "Syncing... 25%",
  "channel": {
    "id": "progress_fgs",
    "name": "Progress"
  },
  "progress": {
    "max": 100,
    "current": 25,
    "indeterminate": false
  }
}
```

`completeProgressForegroundService(...)` automatically normalizes the notification into a completion-style state (`ongoing=false`, `autoCancel=true`, `progress.current=max`).

## Unity C# usage sketch for notifications

```csharp
var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer");
var activity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity");
var cls = new AndroidJavaClass("android.unity.notification.UnityAndroidNotificationManager");
var mgr = cls.CallStatic<AndroidJavaObject>("getInstance");

string notificationJson = @"{
  \"id\": 1001,
  \"title\": \"Native Toolkit\",
  \"message\": \"Hello from Unity\",
  \"channel\": { \"id\": \"general\", \"name\": \"General\" }
}";

bool shown = mgr.Call<bool>("showNotification", activity, notificationJson);
```

## Notification integration notes

- Resource references in JSON use resource names, not generated `R` ids.
  - Example: `{"name":"ic_launcher","type":"mipmap"}`
- If `smallIcon` is omitted, the bridge falls back to the application icon, then to `android.R.drawable.ic_dialog_info`.
- `launchAppOnTap=true` adds a default content intent that launches the host app.
- The bridge does not request `POST_NOTIFICATIONS` at runtime in v1; Unity should handle permission UX at the app level and can use `hasPermission(...)` / settings helpers.
- Scheduled notifications and progress FGS rely on the merged manifest entries already provided by `android_library`.

## Callback Interfaces
Exact interfaces (Kotlin side) provided by `UnityAndroidDialogManager`:
```kotlin
interface DialogListener {
    fun onDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface ConfirmDialogListener {
    fun onConfirmDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface SingleChoiceItemDialogListener {
    fun onSingleChoiceItemDialog(buttonText: String?, checkedItem: Int, isSuccessful: Boolean, errorMessage: String?)
}
interface MultiChoiceItemDialogListener {
    fun onMultiChoiceItemDialog(buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?)
}
interface TextInputDialogListener {
    fun onTextInputDialog(buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface LoginDialogListener {
    fun onLoginDialog(buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?)
}
```
Notes:
- `buttonText` typically "OK", "Cancel", "Yes", "No"
- Cancel (outside / back) routes through the fragment and invokes the same listener
- Single-choice cancel: `checkedItem = -1` (normalized to null in C#)
- Multi-choice cancel: `checkedItems` may be null
- C# wrapper maps these to events; internal errors trigger events with `isSuccessful = false` and an error message

## Usage (Kotlin, in-app or for reference)
```kotlin
UnityAndroidDialogManager.setDialogListener(object : UnityAndroidDialogManager.DialogListener {
    override fun onDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {}
})
UnityAndroidDialogManager.setConfirmDialogListener(object : UnityAndroidDialogManager.ConfirmDialogListener {
    override fun onConfirmDialog(buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {}
})
UnityAndroidDialogManager.setSingleChoiceItemDialogListener(object : UnityAndroidDialogManager.SingleChoiceItemDialogListener {
    override fun onSingleChoiceItemDialog(buttonText: String?, checkedItem: Int, isSuccessful: Boolean, errorMessage: String?) {}
})
UnityAndroidDialogManager.setMultiChoiceItemDialogListener(object : UnityAndroidDialogManager.MultiChoiceItemDialogListener {
    override fun onMultiChoiceItemDialog(buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {}
})
UnityAndroidDialogManager.setTextInputDialogListener(object : UnityAndroidDialogManager.TextInputDialogListener {
    override fun onTextInputDialog(buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {}
})
UnityAndroidDialogManager.setLoginDialogListener(object : UnityAndroidDialogManager.LoginDialogListener {
    override fun onLoginDialog(buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {}
})

UnityAndroidDialogManager.showDialog(this, "Notice", "Operation completed")
UnityAndroidDialogManager.showConfirmDialog(this, "Delete", "Are you sure?")
UnityAndroidDialogManager.showSingleChoiceItemDialog(this, "Color", arrayOf("Red","Green","Blue"), 1)
UnityAndroidDialogManager.showMultiChoiceItemDialog(this, "Tags", arrayOf("A","B","C"), booleanArrayOf(false,true,false))
UnityAndroidDialogManager.showTextInputDialog(this, "Input", "Enter name", "Name", enablePositiveButtonWhenEmpty = false)
UnityAndroidDialogManager.showLoginDialog(this, "Sign In", "Credentials", "User", "Password", enablePositiveButtonWhenEmpty = false)
```

## Unity C# Wrapper (Recommended High-level API)
The C# `AndroidDialogManager` hides JNI details and exposes events.

Event signatures (C#):
```csharp
public event Action<string?, bool, string?> DialogResult;
public event Action<string?, bool, string?> ConfirmDialogResult;
public event Action<string?, int?, bool, string?> SingleChoiceItemDialogResult;
public event Action<string?, bool[]?, bool, string?> MultiChoiceItemDialogResult;
public event Action<string?, string?, bool, string?> TextInputDialogResult;
public event Action<string?, string?, string?, bool, string?> LoginDialogResult;
```

Example:
```csharp
var mgr = AndroidDialogManager.Instance;

mgr.DialogResult += (btn, ok, err) => Debug.Log($"Simple => {btn}, ok={ok}, err={err}");
mgr.TextInputDialogResult += (btn, text, ok, err) => {
    if (btn == "OK" && ok) Debug.Log($"Input: {text}");
};

mgr.ShowDialog("Notice", "Completed");
mgr.ShowConfirmDialog("Delete", "Are you sure?");
mgr.ShowSingleChoiceItemDialog("Color", new []{"Red","Green","Blue"}, 1);
mgr.ShowMultiChoiceItemDialog("Tags", new []{"A","B","C"}, new []{false,true,false});
mgr.ShowTextInputDialog("Input", "Enter name", "Name", enablePositiveButtonWhenEmpty:false);
mgr.ShowLoginDialog("Sign In", "Credentials", "Username", "Password");
```

## Direct JNI Bridge (Optional / Low-level)
(Previous sample) Implement `AndroidJavaProxy` directly and register `setXxxListener` to build a custom dispatch layer. Use this only when the high-level C# wrapper is not suitable.
```csharp
public class DialogBridge : AndroidJavaProxy {
    AndroidJavaObject mgr;
    AndroidJavaObject activity;

    public DialogBridge()
      : base("android.unity.dialog.UnityAndroidDialogManager$DialogListener") {} // One proxy per listener type if needed

    void Init() {
        var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer");
        activity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity");
        var cls = new AndroidJavaClass("android.unity.dialog.UnityAndroidDialogManager");
        mgr = cls.CallStatic<AndroidJavaObject>("getInstance");

        // Register listeners (create additional proxy subclasses or dynamic proxies for each interface)
        mgr.Call("setDialogListener", this);
        // mgr.Call("setConfirmDialogListener", new ConfirmProxy(...));
        // etc.
    }

    // ---- Listener methods (match the DialogListener interface) ----
    public void onDialog(string buttonText, bool isSuccessful, string errorMessage) {
        UnityEngine.Debug.Log($"Simple dialog: {buttonText} success={isSuccessful} err={errorMessage}");
    }

    // Example invocation methods
    public void ShowAll() {
        mgr.Call("showDialog", activity, "Notice", "Completed", "OK", true, true);
        mgr.Call("showConfirmDialog", activity, "Delete", "Are you sure?", "No", "Yes", true, true);
        mgr.Call("showSingleChoiceItemDialog", activity, "Color",
            new string[]{"Red","Green","Blue"}, 0, "Cancel", "OK", true, true);
        mgr.Call("showMultiChoiceItemDialog", activity, "Tags",
            new string[]{"A","B","C"}, new bool[]{false,true,false}, "Cancel", "OK", true, true);
        mgr.Call("showTextInputDialog", activity, "Input", "Enter name", "Name", "Cancel", "OK", false, true, true);
        mgr.Call("showLoginDialog", activity, "Sign In", "Credentials", "User", "Password",
            "Cancel", "OK", false, true, true);
    }
}
```
(For other listener interfaces create corresponding AndroidJavaProxy subclasses implementing the required method names.)

## Threading
All dialog construction and showing must occur on the Android UI thread.
Additional wrapper guarantees:
- `AndroidDialogManager` forces `UnityMainThreadDispatcher` initialization in Awake
- Java → C# callbacks are re-dispatched to the Unity main thread via an internal `PostToMainThread`
- Callers of `Show*` methods do not need manual `runOnUiThread`

## Mapping Overview
| Variant | Java Method | C# Wrapper Method | C# Event | Payload (success OK path) |
|--------|-------------|-------------------|----------|---------------------------|
| Simple | showDialog | ShowDialog | DialogResult | (buttonText) |
| Confirm | showConfirmDialog | ShowConfirmDialog | ConfirmDialogResult | (buttonText) |
| SingleChoice | showSingleChoiceItemDialog | ShowSingleChoiceItemDialog | SingleChoiceItemDialogResult | (buttonText, checkedItem) |
| MultiChoice | showMultiChoiceItemDialog | ShowMultiChoiceItemDialog | MultiChoiceItemDialogResult | (buttonText, bool[] states) |
| TextInput | showTextInputDialog | ShowTextInputDialog | TextInputDialogResult | (buttonText, inputText) |
| Login | showLoginDialog | ShowLoginDialog | LoginDialogResult | (buttonText, username, password) |

## Error Handling
- If the hosting context is not a `FragmentActivity` the Java manager logs and invokes the listener with `isSuccessful = false`
- Exceptions while constructing/showing are caught; listener receives `isSuccessful = false` and an error message
- C# wrapper: if `pluginInstance` is null or a JNI call throws, the corresponding event fires immediately with `isSuccessful = false` and `errorMessage = "Internal error: <message>"`

## Cancellation Behavior
- Back press or (if enabled) outside tap triggers fragment `onCancel`, forwarding a "Cancel" style callback
- Single-choice: `-1` index mapped to null in C#
- Multi-choice: cancel may supply null array (distinguishable from a real selection)
- Text / Login dialogs provide empty or null input on cancel

## Dokka
Generate API docs:
```
./gradlew :unity_android_plugin:clean :unity_android_plugin:dokkaHtml
```
Output directory: `unity_android_plugin/build/dokka/html`.
