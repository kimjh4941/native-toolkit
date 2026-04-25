# Notification Feature

Language:

- 日本語: [notification.ja.md](notification.ja.md)
- English (this page)
- 한국어: [notification.ko.md](notification.ko.md)

← [Back to Manual Top](index.md)

---

## Table of Contents

- [Android](#android)
  - [Setup](#setup)
  - [Permission](#permission)
  - [Channel Management](#channel-management)
  - [Basic Notification Operations](#basic-notification-operations)
  - [Notification Styles](#notification-styles)
  - [Platform Options](#platform-options)
  - [Custom View Styles](#custom-view-styles)
  - [Group Notifications](#group-notifications)
  - [Interaction](#interaction)
  - [Progress Notifications](#progress-notifications)
  - [Foreground Service Notifications](#foreground-service-notifications)
  - [Scheduled Notifications](#scheduled-notifications)
- [iOS](#ios)
- [Windows](#windows)
- [macOS](#macos)

---

## Android

### Setup

#### AndroidManifest.xml

Add the permissions required for the features you use.

```xml
<!-- Required to post notifications on Android 13 and above -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Required for scheduled notifications (exact alarms) -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Required for foreground services -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

#### Initializing NotificationUseCases

```kotlin
import android.library.notification.data.repository.NotificationUseCases

val useCases = NotificationUseCases(context)
```

---

### Permission

```kotlin
import android.library.notification.presentation.permission.NotificationPermissionHelper

val permissionHelper = NotificationPermissionHelper(activity)

// Whether notification permission is granted (Android 13 and above)
val hasPermission: Boolean = permissionHelper.hasPermission()

// Whether app notifications are enabled
val enabled: Boolean = permissionHelper.areNotificationsEnabled()

// Whether exact alarm scheduling is permitted
val canSchedule: Boolean = permissionHelper.canScheduleExactAlarms()

// Request notification permission
permissionHelper.requestPermission { granted ->
    if (granted) { /* permission granted */ }
}

// Open settings screens
permissionHelper.openNotificationSettings()
permissionHelper.openExactAlarmSettings()
```

---

### Channel Management

A notification channel must be created before posting notifications.

```kotlin
import android.library.notification.domain.model.NotificationChannel

val channel = NotificationChannel(
    id = "my_channel",
    name = "My Channel",
    description = "Sample notification channel"
)

// Create
useCases.createChannel(channel)
    .onSuccess { /* done */ }
    .onFailure { /* handle error */ }

// Create multiple at once
useCases.createChannels(listOf(channel1, channel2))

// Delete
useCases.deleteChannel("my_channel")
```

---

### Basic Notification Operations

#### Show

```kotlin
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.NotificationContent

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1001,
        title = "Title",
        message = "Body text",
        channel = channel
    )
)

useCases.show(command)
    .onSuccess { /* shown */ }
    .onFailure { /* handle error */ }
```

#### Update

Pass a command with the same `id` / `tag` to overwrite an active notification.

```kotlin
useCases.update(updatedCommand)
```

#### Cancel

```kotlin
// Cancel a specific notification
useCases.cancel(id = 1001)
useCases.cancel(id = 1001, tag = "my_tag")

// Cancel all notifications
useCases.cancelAll()
```

#### Get Active Notifications

Retrieve the list of currently displayed notifications (Android 6.0 and above).

```kotlin
val activeList: List<ActiveNotification> = useCases.getActive()
activeList.forEach { it.id; it.title }
```

---

### Notification Styles

Set the `style` property on `NotificationContent`.

#### Default

```kotlin
style = NotificationStyle.Default
```

#### BigText

Displays long text when the notification is expanded.

```kotlin
style = NotificationStyle.BigText(
    bigText = "Long body text shown when the notification is expanded.",
    summaryText = "Summary",
    bigContentTitle = "Expanded title"
)
```

#### Inbox

Displays multiple lines in a list format when expanded.

```kotlin
style = NotificationStyle.Inbox(
    lines = listOf("• Item 1", "• Item 2", "• Item 3"),
    summaryText = "3 items",
    bigContentTitle = "Expanded title"
)
```

#### BigPicture

Displays an image when the notification is expanded.

```kotlin
style = NotificationStyle.BigPicture(
    pictureResId = R.drawable.my_image,  // or use pictureUriString
    summaryText = "Image description",
    bigContentTitle = "Expanded title"
)
```

#### Messaging

Displays chat history in conversation format.

```kotlin
import android.library.notification.domain.model.NotificationMessage

val now = System.currentTimeMillis()

style = NotificationStyle.Messaging(
    userDisplayName = "You",
    conversationTitle = "Group name",
    isGroupConversation = true,
    messages = listOf(
        NotificationMessage(
            text = "Message body",
            timestampMillis = now - 60_000L,
            senderName = "Alice"          // null = local user
        )
    )
)
```

#### Media

Displays in media player format. Specify the indices of action buttons to show in compact view.

```kotlin
style = NotificationStyle.Media(
    compactActionIndices = listOf(0, 1, 2)  // up to 3
)
```

Set action buttons via `AndroidNotificationPlatformOptions.actions` (see [Platform Options](#platform-options)).

---

### Platform Options

Use `AndroidNotificationPlatformOptions` to configure Android-specific behavior.

```kotlin
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidNotificationAction

val command = AndroidNotificationCommand(
    content = NotificationContent( /* ... */ ),
    platformOptions = AndroidNotificationPlatformOptions(
        // Intent launched when the notification is tapped
        contentIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MainActivity::class.java),
            requestCode = 1000
        ),
        // Intent fired when the notification is dismissed (swiped away)
        deleteIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MyReceiver::class.java),
            requestCode = 1001,
            type = AndroidPendingIntentType.BROADCAST
        ),
        // Intent for full-screen display (e.g. while the device is locked)
        fullScreenIntent = AndroidPendingIntentRequest(
            intent = Intent(context, FullScreenActivity::class.java),
            requestCode = 1002,
            type = AndroidPendingIntentType.ACTIVITY
        ),
        // Action buttons
        actions = listOf(
            AndroidNotificationAction(
                title = "Accept",
                pendingIntent = AndroidPendingIntentRequest(
                    intent = Intent(context, ActionReceiver::class.java).apply {
                        action = "ACTION_ACCEPT"
                    },
                    requestCode = 2000,
                    type = AndroidPendingIntentType.BROADCAST
                ),
                iconResId = android.R.drawable.ic_menu_call
            )
        )
    )
)
```

---

### Custom View Styles

Display notifications using a custom layout. Use `RemoteViewAction` to set view content and click events.

#### DecoratedCustomView

```kotlin
import android.library.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import android.library.notification.application.model.RemoteViewAction
import android.library.notification.domain.model.NotificationCustomViewStyleData

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1007,
        title = "Title",
        message = "Body",
        channel = channel,
        style = NotificationStyle.DecoratedCustomView(
            customView = NotificationCustomViewStyleData(
                layoutResId = R.layout.notification_custom,       // collapsed view
                bigLayoutResId = R.layout.notification_custom_big // expanded view (optional)
            )
        )
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        customViewOptions = AndroidNotificationCustomViewPlatformOptions(
            viewActions = listOf(
                // Set text
                RemoteViewAction.SetText(R.id.notification_title, "Custom title"),
                RemoteViewAction.SetText(R.id.notification_message, "Custom body"),
                // Set image
                RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher),
                // Set click intent on a button
                RemoteViewAction.SetClickIntent(
                    viewId = R.id.notification_btn_dismiss,
                    pendingIntent = AndroidPendingIntentRequest(
                        intent = Intent(context, ActionReceiver::class.java).apply {
                            action = "ACTION_DISMISS"
                        },
                        requestCode = 2100,
                        type = AndroidPendingIntentType.BROADCAST
                    )
                )
            )
        )
    )
)

useCases.show(command)
```

> **Note:** Due to `RemoteViews` constraints, use `LinearLayout` + `TextView` instead of `Button` for clickable elements. Click events are set via `setOnClickPendingIntent`.

#### DecoratedMediaCustomView

Combines Media style with a custom view.

```kotlin
style = NotificationStyle.DecoratedMediaCustomView(
    customView = NotificationCustomViewStyleData(
        layoutResId = R.layout.notification_media_custom
    ),
    compactActionIndices = listOf(0, 1, 2)
)
```

Usage of `customViewOptions` is the same as `DecoratedCustomView`.

---

### Group Notifications

Group multiple notifications together.

```kotlin
val GROUP_KEY = "my_group_key"

// Child notification 1
val child1 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1101,
        title = "Notification 1",
        message = "Group child notification #1",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "01"
    )
)

// Child notification 2
val child2 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1102,
        title = "Notification 2",
        message = "Group child notification #2",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "02"
    )
)

// Summary notification (group header)
val summary = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1100,
        title = "Group Summary",
        message = "2 notifications",
        channel = channel,
        groupKey = GROUP_KEY,
        isGroupSummary = true,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "00"
    )
)

useCases.show(child1)
useCases.show(child2)
useCases.show(summary)
```

> **Tip:** Setting `groupAlertBehavior = GROUP_ALERT_SUMMARY` makes only the summary play sound and vibration; child notifications are silent.

---

### Interaction

#### Action Buttons (BroadcastReceiver)

Add buttons to a notification and receive taps via a `BroadcastReceiver`.

```kotlin
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val actionId = intent?.getStringExtra("extra_action_id") ?: return
        // Handle action
    }
}
```

```kotlin
// Notification with action buttons
platformOptions = AndroidNotificationPlatformOptions(
    actions = listOf(
        AndroidNotificationAction(
            title = "Accept",
            pendingIntent = AndroidPendingIntentRequest(
                intent = Intent(context, NotificationActionReceiver::class.java).apply {
                    putExtra("extra_action_id", "accept")
                },
                requestCode = 5000,
                type = AndroidPendingIntentType.BROADCAST
            )
        ),
        AndroidNotificationAction(
            title = "Decline",
            pendingIntent = AndroidPendingIntentRequest(
                intent = Intent(context, NotificationActionReceiver::class.java).apply {
                    putExtra("extra_action_id", "decline")
                },
                requestCode = 5001,
                type = AndroidPendingIntentType.BROADCAST
            )
        )
    )
)
```

#### DeleteIntent (Dismiss Event)

Fired when the user swipes the notification away.

```kotlin
platformOptions = AndroidNotificationPlatformOptions(
    deleteIntent = AndroidPendingIntentRequest(
        intent = Intent(context, NotificationDeleteReceiver::class.java).apply {
            action = "ACTION_NOTIFICATION_DELETED"
        },
        requestCode = 5100,
        type = AndroidPendingIntentType.BROADCAST
    )
)
```

#### FullScreenIntent (Full-Screen Display)

Launches a full-screen activity when the device is locked or the screen is off (e.g. alarms, incoming calls).

```kotlin
// Requires a high-priority channel and an appropriate category
val content = NotificationContent(
    id = 1111,
    title = "Alarm",
    message = "Time to wake up",
    channel = highPriorityChannel,
    category = NotificationCompat.CATEGORY_ALARM,
    priority = NotificationCompat.PRIORITY_HIGH
)

platformOptions = AndroidNotificationPlatformOptions(
    fullScreenIntent = AndroidPendingIntentRequest(
        intent = Intent(context, AlarmActivity::class.java),
        requestCode = 5200,
        type = AndroidPendingIntentType.ACTIVITY,
        mutable = true
    )
)
```

> **Note:** Depending on device state and Android policy, the notification may appear as a heads-up notification instead of full-screen.

---

### Progress Notifications

Display a progress bar for downloads or long-running operations.

```kotlin
import android.library.notification.domain.model.NotificationProgress

// Determinate progress bar
val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1009,
        title = "Downloading",
        message = "50% complete",
        channel = channel,
        ongoing = true,
        autoCancel = false,
        progress = NotificationProgress(
            max = 100,
            current = 50,
            indeterminate = false
        )
    )
)

useCases.show(command)

// Indeterminate progress bar
val indeterminate = NotificationProgress(max = 0, current = 0, indeterminate = true)

// On completion (hide the bar and revert to a normal notification)
val complete = NotificationContent(
    id = 1009,
    ongoing = false,
    autoCancel = true,
    progress = NotificationProgress(max = 100, current = 100, indeterminate = false),
    /* ... */
)
```

---

### Foreground Service Notifications

#### Progress FGS (Long-Running Background Tasks)

Use `ProgressForegroundNotifications` to show a progress notification tied to a foreground service.

```kotlin
import android.library.notification.presentation.progress.ProgressForegroundNotifications

// Start the foreground service (also shows the notification)
ProgressForegroundNotifications.start(context, progressCommand)

// Update progress
ProgressForegroundNotifications.update(context, updatedProgressCommand)

// Complete (stop the service and demote to a regular notification)
ProgressForegroundNotifications.complete(context, completionCommand)

// Force stop (also removes the notification)
ProgressForegroundNotifications.stop(context)
```

Declare the service in `AndroidManifest.xml`.

```xml
<service
    android:name="android.library.notification.presentation.progress.ProgressForegroundService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

#### Call Style FGS (Call Notifications)

Show CallStyle notifications (incoming, ongoing, screening) via a foreground service.

```kotlin
import android.library.notification.presentation.call.CallStyleForegroundService
import androidx.core.content.ContextCompat

// Start incoming call notification
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createIncomingStartIntent(context)
)

// Switch to ongoing call notification
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createOngoingStartIntent(context)
)

// Stop
context.startService(CallStyleForegroundService.createStopIntent(context))
```

Declare the service in `AndroidManifest.xml`.

```xml
<service
    android:name="android.library.notification.presentation.call.CallStyleForegroundService"
    android:foregroundServiceType="specialUse"
    android:exported="false">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="call" />
</service>
```

---

### Scheduled Notifications

Automatically show a notification at a specified time.

```kotlin
import android.library.notification.domain.model.NotificationSchedule

val schedule = NotificationSchedule(
    triggerAtMillis = System.currentTimeMillis() + 15_000L, // 15 seconds from now
    exact = true,           // exact alarm (requires SCHEDULE_EXACT_ALARM)
    allowWhileIdle = true,  // fires even in Doze mode
    persistAcrossBoot = true // restored after device reboot
)

useCases.schedule(command, schedule)
    .onSuccess { /* scheduled */ }
    .onFailure { /* handle error */ }
```

#### Cancel Scheduled Notifications

```kotlin
useCases.cancelScheduled(id = 1010)
useCases.cancelAllScheduled()
```

#### Restore After Reboot

Use `RECEIVE_BOOT_COMPLETED` to restore schedules after a device reboot.

```kotlin
// Call inside BroadcastReceiver.onReceive
useCases.restoreScheduled()
```

Declare the receiver in `AndroidManifest.xml`.

```xml
<receiver
    android:name="android.library.notification.data.repository.ScheduledNotificationBootReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
    </intent-filter>
</receiver>
```

#### Check Scheduled Status

```kotlin
val isScheduled: Boolean = useCases.isScheduled(context, id = 1010)
```

---

## iOS

(Coming soon)

---

## Windows

(Coming soon)

---

## macOS

(Coming soon)
