# 알림 기능

언어:

- 日本語: [notification.ja.md](notification.ja.md)
- English: [notification.md](notification.md)
- 한국어（이 페이지）

← [매뉴얼 상단으로 돌아가기](index.ko.md)

---

## 목차

- [Android](#android)
  - [설정](#설정)
  - [권한](#권한)
  - [채널 관리](#채널-관리)
  - [기본 알림 조작](#기본-알림-조작)
  - [알림 스타일](#알림-스타일)
  - [플랫폼 옵션](#플랫폼-옵션)
  - [커스텀 뷰 스타일](#커스텀-뷰-스타일)
  - [그룹 알림](#그룹-알림)
  - [인터랙션](#인터랙션)
  - [진행 상황 알림](#진행-상황-알림)
  - [포어그라운드 서비스 알림](#포어그라운드-서비스-알림)
  - [예약 알림](#예약-알림)
- [iOS](#ios)
  - [IosNotificationManager](#iosnotificationmanager)
  - [설정](#설정-1)
  - [권한](#권한-1)
    - [알림 권한 요청](#알림-권한-요청)
    - [권한 확인](#권한-확인)
    - [인증 상태 가져오기](#인증-상태-가져오기)
    - [알림 설정 열기](#알림-설정-열기)
  - [알림 표시](#알림-표시)
    - [즉시 표시](#즉시-표시)
    - [첨부 파일 포함 즉시 표시](#첨부-파일-포함-즉시-표시)
    - [시간 간격 트리거](#시간-간격-트리거)
    - [캘린더 트리거](#캘린더-트리거)
    - [위치 정보 트리거](#위치-정보-트리거)
  - [첨부 파일](#첨부-파일)
  - [알림 업데이트](#알림-업데이트)
  - [알림 취소 / 삭제](#알림-취소--삭제)
  - [예약 알림](#예약-알림-1)
    - [예약 취소](#예약-취소)
  - [조회](#조회)
  - [배지](#배지)
  - [카테고리와 액션](#카테고리와-액션)
    - [카테고리 등록](#카테고리-등록)
    - [카테고리를 알림에 연결](#카테고리를-알림에-연결)
    - [카테고리 삭제](#카테고리-삭제)
    - [액션 수신 콜백](#액션-수신-콜백)
- [Windows](#windows)
- [macOS](#macos)
  - [MacNotificationManager](#macnotificationmanager)
  - [설정](#설정-2)
  - [권한](#권한-2)
    - [권한 요청](#권한-요청)
    - [권한 확인](#권한-확인-1)
    - [인증 상태 가져오기](#인증-상태-가져오기-1)
    - [알림 설정 열기](#알림-설정-열기-1)
    - [알림 권한 초기화 (macOS 26.3)](#알림-권한-초기화-macos-263)
  - [알림 표시](#알림-표시-2)
    - [즉시 표시](#즉시-표시-1)
    - [시간 간격 트리거](#시간-간격-트리거-1)
    - [캘린더 트리거](#캘린더-트리거-1)
  - [업데이트 / 취소 / 삭제](#업데이트--취소--삭제)
    - [ID로 업데이트](#id로-업데이트)
    - [ID로 취소](#id로-취소)
    - [전체 취소](#전체-취소)
    - [전달된 알림 삭제](#전달된-알림-삭제)
    - [전달된 알림 전체 삭제](#전달된-알림-전체-삭제)
  - [예약](#예약)
    - [시간 간격으로 예약](#시간-간격으로-예약)
    - [캘린더로 예약](#캘린더로-예약)
    - [ID로 예약 취소](#id로-예약-취소)
    - [전체 예약 취소](#전체-예약-취소)
  - [조회](#조회-1)
    - [예약된 알림 조회](#예약된-알림-조회)
    - [전달된 알림 조회](#전달된-알림-조회)
  - [배지](#배지-1)
  - [카테고리](#카테고리)
    - [카테고리 등록](#카테고리-등록-1)
    - [카테고리 삭제](#카테고리-삭제-1)
  - [에러 코드](#에러-코드)

---

## Android

### 설정

#### AndroidManifest.xml

사용하는 기능에 따라 권한을 추가합니다.

```xml
<!-- Android 13 이상에서 알림을 전송하기 위해 필요 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- 예약 알림（정확한 알람）을 사용하는 경우 -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- 포어그라운드 서비스를 사용하는 경우 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

#### NotificationUseCases 초기화

```kotlin
import android.library.notification.data.repository.NotificationUseCases

val useCases = NotificationUseCases(context)
```

---

### 권한

```kotlin
import android.library.notification.presentation.permission.NotificationPermissionHelper

val permissionHelper = NotificationPermissionHelper(activity)

// 알림 권한이 허용되어 있는지（Android 13 이상）
val hasPermission: Boolean = permissionHelper.hasPermission()

// 앱 알림이 활성화되어 있는지
val enabled: Boolean = permissionHelper.areNotificationsEnabled()

// 정확한 알람 예약이 허용되어 있는지
val canSchedule: Boolean = permissionHelper.canScheduleExactAlarms()

// 알림 권한 요청
permissionHelper.requestPermission { granted ->
    if (granted) { /* 허용됨 */ }
}

// 설정 화면 열기
permissionHelper.openNotificationSettings()
permissionHelper.openExactAlarmSettings()
```

---

### 채널 관리

알림을 전송하기 전에 채널을 생성해야 합니다.

```kotlin
import android.library.notification.domain.model.NotificationChannel

val channel = NotificationChannel(
    id = "my_channel",
    name = "My Channel",
    description = "Sample notification channel"
)

// 생성
useCases.createChannel(channel)
    .onSuccess { /* 완료 */ }
    .onFailure { /* 오류 처리 */ }

// 여러 채널을 한 번에 생성
useCases.createChannels(listOf(channel1, channel2))

// 삭제
useCases.deleteChannel("my_channel")
```

---

### 기본 알림 조작

#### 표시

```kotlin
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.NotificationContent

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1001,
        title = "제목",
        message = "본문",
        channel = channel
    )
)

useCases.show(command)
    .onSuccess { /* 표시 완료 */ }
    .onFailure { /* 오류 처리 */ }
```

#### 업데이트

같은 `id` / `tag`를 지정하면 표시 중인 알림을 덮어써서 업데이트합니다.

```kotlin
useCases.update(updatedCommand)
```

#### 취소

```kotlin
// 특정 알림 취소
useCases.cancel(id = 1001)
useCases.cancel(id = 1001, tag = "my_tag")

// 모두 취소
useCases.cancelAll()
```

#### 활성 알림 가져오기

현재 표시 중인 알림 목록을 가져옵니다（Android 6.0 이상）.

```kotlin
val activeList: List<ActiveNotification> = useCases.getActive()
activeList.forEach { it.id; it.title }
```

---

### 알림 스타일

`NotificationContent`의 `style` 프로퍼티에 지정합니다.

#### Default（기본）

```kotlin
style = NotificationStyle.Default
```

<p align="center">
    <img src="images/android/notification/Example_Default.png" alt="Example_Default" width="400" />
</p>

#### BigText

알림을 펼치면 긴 텍스트를 표시합니다.

```kotlin
style = NotificationStyle.BigText(
    bigText = "알림을 펼쳤을 때 표시되는 긴 본문 텍스트",
    summaryText = "요약",
    bigContentTitle = "펼쳤을 때의 제목"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigText.png" alt="Example_BigText" width="400" />
</p>

#### Inbox

알림을 펼치면 여러 줄을 목록 형식으로 표시합니다.

```kotlin
style = NotificationStyle.Inbox(
    lines = listOf("• 항목 1", "• 항목 2", "• 항목 3"),
    summaryText = "3건",
    bigContentTitle = "펼쳤을 때의 제목"
)
```

<p align="center">
    <img src="images/android/notification/Example_Inbox.png" alt="Example_Inbox" width="400" />
</p>

#### BigPicture

알림을 펼치면 이미지를 표시합니다.

```kotlin
style = NotificationStyle.BigPicture(
    pictureResId = R.drawable.my_image,  // 또는 URI로 지정: pictureUriString
    summaryText = "이미지 설명",
    bigContentTitle = "펼쳤을 때의 제목"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigPicture.png" alt="Example_BigPicture" width="400" />
</p>

#### Messaging

채팅 기록 형식으로 표시합니다.

```kotlin
import android.library.notification.domain.model.NotificationMessage

val now = System.currentTimeMillis()

style = NotificationStyle.Messaging(
    userDisplayName = "나",
    conversationTitle = "그룹명",
    isGroupConversation = true,
    messages = listOf(
        NotificationMessage(
            text = "메시지 본문",
            timestampMillis = now - 60_000L,
            senderName = "Alice"          // null = 내 메시지
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Messaging.png" alt="Example_Messaging" width="400" />
</p>

#### Media

미디어 플레이어 형식으로 표시합니다. 컴팩트 표시 시 보여줄 액션 버튼의 인덱스를 지정합니다.

```kotlin
style = NotificationStyle.Media(
    compactActionIndices = listOf(0, 1, 2)  // 최대 3개
)
```

<p align="center">
    <img src="images/android/notification/Example_Media.png" alt="Example_Media" width="400" />
</p>

액션 버튼은 `AndroidNotificationPlatformOptions.actions`에 설정합니다（[플랫폼 옵션](#플랫폼-옵션) 참조）.

---

### 플랫폼 옵션

`AndroidNotificationPlatformOptions`로 Android 고유의 동작을 설정합니다.

```kotlin
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidNotificationAction

val command = AndroidNotificationCommand(
    content = NotificationContent( /* ... */ ),
    platformOptions = AndroidNotificationPlatformOptions(
        // 알림 탭 시 실행할 Intent
        contentIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MainActivity::class.java),
            requestCode = 1000
        ),
        // 알림을 삭제（스와이프）했을 때의 Intent
        deleteIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MyReceiver::class.java),
            requestCode = 1001,
            type = AndroidPendingIntentType.BROADCAST
        ),
        // 전체 화면 표시용 Intent（기기 잠금 중 등）
        fullScreenIntent = AndroidPendingIntentRequest(
            intent = Intent(context, FullScreenActivity::class.java),
            requestCode = 1002,
            type = AndroidPendingIntentType.ACTIVITY
        ),
        // 액션 버튼
        actions = listOf(
            AndroidNotificationAction(
                title = "승인",
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

### 커스텀 뷰 스타일

자체 레이아웃으로 알림을 표시합니다. `RemoteViewAction`을 사용하여 뷰의 내용과 클릭 이벤트를 설정합니다.

#### DecoratedCustomView

```kotlin
import android.library.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import android.library.notification.application.model.RemoteViewAction
import android.library.notification.domain.model.NotificationCustomViewStyleData

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1007,
        title = "제목",
        message = "본문",
        channel = channel,
        style = NotificationStyle.DecoratedCustomView(
            customView = NotificationCustomViewStyleData(
                layoutResId = R.layout.notification_custom,       // 일반 표시
                bigLayoutResId = R.layout.notification_custom_big // 펼침 표시（생략 가능）
            )
        )
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        customViewOptions = AndroidNotificationCustomViewPlatformOptions(
            viewActions = listOf(
                // 텍스트 설정
                RemoteViewAction.SetText(R.id.notification_title, "커스텀 제목"),
                RemoteViewAction.SetText(R.id.notification_message, "커스텀 본문"),
                // 이미지 설정
                RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher),
                // 버튼에 클릭 이벤트 설정
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

<p align="center">
    <img src="images/android/notification/Example_DecoratedCustomView.png" alt="Example_DecoratedCustomView" width="400" />
</p>

> **주의:** `RemoteViews`의 제약으로 인해 버튼에는 `Button` 클래스 대신 `LinearLayout` + `TextView`를 사용하세요. 클릭 이벤트는 `setOnClickPendingIntent`로 설정됩니다.

#### DecoratedMediaCustomView

Media 스타일과 조합하여 커스텀 뷰를 표시합니다.

```kotlin
style = NotificationStyle.DecoratedMediaCustomView(
    customView = NotificationCustomViewStyleData(
        layoutResId = R.layout.notification_media_custom
    ),
    compactActionIndices = listOf(0, 1, 2)
)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedMediaCustomView.png" alt="Example_DecoratedMediaCustomView" width="400" />
</p>

`customViewOptions` 사용법은 `DecoratedCustomView`와 동일합니다.

---

### 그룹 알림

여러 알림을 그룹으로 묶어 표시합니다.

```kotlin
val GROUP_KEY = "my_group_key"

// 자식 알림 1
val child1 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1101,
        title = "알림 1",
        message = "그룹 자식 알림 #1",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "01"
    )
)

// 자식 알림 2
val child2 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1102,
        title = "알림 2",
        message = "그룹 자식 알림 #2",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "02"
    )
)

// 요약 알림（그룹 헤더）
val summary = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1100,
        title = "그룹 요약",
        message = "알림 2건",
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

<p align="center">
    <img src="images/android/notification/Example_Group.png" alt="Example_Group" width="400" />
</p>

> **포인트:** `groupAlertBehavior = GROUP_ALERT_SUMMARY`로 설정하면 요약 알림만 소리와 진동이 울리고 자식 알림은 무음이 됩니다.

---

### 인터랙션

#### 액션 버튼（BroadcastReceiver）

알림에 버튼을 추가하고 탭을 BroadcastReceiver로 수신합니다.

```kotlin
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val actionId = intent?.getStringExtra("extra_action_id") ?: return
        // 액션 처리
    }
}
```

```kotlin
// 액션 버튼이 있는 알림
platformOptions = AndroidNotificationPlatformOptions(
    actions = listOf(
        AndroidNotificationAction(
            title = "승인",
            pendingIntent = AndroidPendingIntentRequest(
                intent = Intent(context, NotificationActionReceiver::class.java).apply {
                    putExtra("extra_action_id", "accept")
                },
                requestCode = 5000,
                type = AndroidPendingIntentType.BROADCAST
            )
        ),
        AndroidNotificationAction(
            title = "거절",
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

<p align="center">
    <img src="images/android/notification/Example_ActionButtons.png" alt="Example_ActionButtons" width="400" />
</p>

#### DeleteIntent（삭제 이벤트）

알림을 스와이프로 삭제했을 때의 콜백입니다.

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

#### FullScreenIntent（전체 화면）

기기 잠금 중이나 화면 꺼짐 시 전체 화면으로 실행됩니다（알람·수신 알림 등）.

```kotlin
// 높은 우선순위 채널과 category 설정이 필요
val content = NotificationContent(
    id = 1111,
    title = "알람",
    message = "기상 시각입니다",
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

<p align="center">
    <img src="images/android/notification/Example_FullScreenIntent.png" alt="Example_FullScreenIntent" width="400" />
</p>

> **주의:** 기기 상태 및 Android 정책에 따라 전체 화면 대신 heads-up 알림으로 표시될 수 있습니다.

---

### 진행 상황 알림

다운로드나 처리 진행 상황을 프로그레스 바로 표시합니다.

```kotlin
import android.library.notification.domain.model.NotificationProgress

// 확정 프로그레스 바
val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1009,
        title = "다운로드 중",
        message = "50% 완료",
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

// 불확정 프로그레스 바
val indeterminate = NotificationProgress(max = 0, current = 0, indeterminate = true)

// 완료 시（바를 숨기고 일반 알림으로 되돌리기）
val complete = NotificationContent(
    id = 1009,
    ongoing = false,
    autoCancel = true,
    progress = NotificationProgress(max = 100, current = 100, indeterminate = false),
    /* ... */
)
```

<p align="center">
    <img src="images/android/notification/Example_Progress.png" alt="Example_Progress" width="400" />
</p>

---

### 포어그라운드 서비스 알림

#### Progress FGS（장시간 백그라운드 처리）

`ProgressForegroundNotifications`를 사용하여 포어그라운드 서비스와 연동된 진행 상황 알림을 표시합니다.

```kotlin
import android.library.notification.presentation.progress.ProgressForegroundNotifications

// 포어그라운드 서비스 시작（알림 표시도 겸함）
ProgressForegroundNotifications.start(context, progressCommand)

// 진행 상황 업데이트
ProgressForegroundNotifications.update(context, updatedProgressCommand)

// 완료（서비스를 중지하고 일반 알림으로 강등）
ProgressForegroundNotifications.complete(context, completionCommand)

// 강제 중지（알림도 삭제）
ProgressForegroundNotifications.stop(context)
```

<p align="center">
    <img src="images/android/notification/Example_ProgressForeground.png" alt="Example_ProgressForeground" width="400" />
</p>

`AndroidManifest.xml`에 서비스를 선언합니다.

```xml
<service
    android:name="android.library.notification.presentation.progress.ProgressForegroundService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

#### Call Style FGS（통화 스타일）

착신·통화 중·스크리닝의 CallStyle 알림을 포어그라운드 서비스로 표시합니다.

```kotlin
import android.library.notification.presentation.call.CallStyleForegroundService
import androidx.core.content.ContextCompat

// 착신 알림 시작
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createIncomingStartIntent(context)
)

// 통화 중 알림으로 전환
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createOngoingStartIntent(context)
)

// 중지
context.startService(CallStyleForegroundService.createStopIntent(context))
```

<p align="center">
    <img src="images/android/notification/Example_CallStyle.png" alt="Example_CallStyle" width="400" />
</p>

`AndroidManifest.xml`에 서비스를 선언합니다.

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

### 예약 알림

지정한 시각에 알림을 자동으로 표시합니다.

```kotlin
import android.library.notification.domain.model.NotificationSchedule

val schedule = NotificationSchedule(
    triggerAtMillis = System.currentTimeMillis() + 15_000L, // 15초 후
    exact = true,           // 정확한 알람（SCHEDULE_EXACT_ALARM 필요）
    allowWhileIdle = true,  // Doze 모드 중에도 실행
    persistAcrossBoot = true // 기기 재부팅 후에도 복원
)

useCases.schedule(command, schedule)
    .onSuccess { /* 예약 완료 */ }
    .onFailure { /* 오류 처리 */ }
```

<p align="center">
    <img src="images/android/notification/Example_Scheduled.png" alt="Example_Scheduled" width="400" />
</p>

#### 예약 취소

```kotlin
useCases.cancelScheduled(id = 1010)
useCases.cancelAllScheduled()
```

#### 기기 재부팅 후 복원

`RECEIVE_BOOT_COMPLETED`를 사용하여 재부팅 후 스케줄을 복원합니다.

```kotlin
// BroadcastReceiver의 onReceive 내에서 호출
useCases.restoreScheduled()
```

`AndroidManifest.xml`에 Receiver를 선언합니다.

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

#### 예약 여부 확인

```kotlin
val isScheduled: Boolean = useCases.isScheduled(context, id = 1010)
```

---

## iOS

### IosNotificationManager

`IosNotificationManager`는 iOS 로컬 알림의 모든 작업을 제공하는 싱글톤 클래스입니다.

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager.png" alt="Example_IosNotificationManager" width="400" />
</p>

### 설정

앱 실행 시（예: `AppDelegate.application(_:didFinishLaunchingWithOptions:)`）에 `setup()`을 한 번 호출합니다.

```swift
import IosLibrary

IosNotificationManager.setup()
```

### 권한

#### 알림 권한 요청

```swift
IosNotificationManager.shared.requestPermission { isSuccess, errorMessage in
    if isSuccess {
        // 허용됨
    } else {
        // 거부됨. 설정에서 수동으로 활성화 필요
    }
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_RequestPermission.png" alt="Example_IosNotificationManager_RequestPermission" width="400" />
</p>

#### 권한 확인

```swift
IosNotificationManager.shared.hasPermission { hasPermission in
    print(hasPermission) // true / false
}
```

#### 인증 상태 가져오기

```swift
IosNotificationManager.shared.authorizationStatus { status in
    // .notDetermined / .denied / .authorized / .provisional / .ephemeral / .unknown
    print(status)
}
```

#### 알림 설정 열기

```swift
IosNotificationManager.shared.openNotificationSettings()
```

### 알림 표시

`NotificationContent`를 생성하고 `show()`를 호출합니다.

#### 즉시 표시

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification",
    body: "Displayed now",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediate.png" alt="Example_IosNotificationManager_ShowImmediate" width="400" />
</p>

#### 첨부 파일 포함 즉시 표시

앱에 포함된 이미지 파일을 첨부하여 알림을 표시합니다.
알림을 길게 누르면（확장 표시） 썸네일이 표시됩니다.

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification with Attachment",
    body: "Displayed with app icon attachment",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"],
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediateWithAttachment.png" alt="Example_IosNotificationManager_ShowImmediateWithAttachment" width="400" />
</p>

#### 시간 간격 트리거

```swift
IosNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(5.0, repeats: false)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### 캘린더 트리거

```swift
var components = DateComponents()
components.hour = 9
components.minute = 0

IosNotificationManager.shared.show(
    content: content,
    trigger: .calendar(components, repeats: true)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### 위치 정보 트리거

위치 정보 알림은 CoreLocation을 사용합니다. `Info.plist`에 위치 정보 사용 설명을 추가하세요.

```swift
IosNotificationManager.shared.show(
    content: content,
    trigger: .location(
        identifier: "tokyo-station",
        latitude: 35.6812,
        longitude: 139.7671,
        radius: 100,
        notifyOnEntry: true,
        notifyOnExit: false
    )
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 첨부 파일

`NotificationAttachment`를 사용하여 알림에 이미지, 오디오, 동영상을 첨부할 수 있습니다.
알림을 길게 누르면（확장 표시） 썸네일이 표시됩니다.

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "이미지가 있는 알림",
    body: "확장하여 이미지를 확인하세요",
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 알림 업데이트

보류 중인 알림의 내용이나 트리거를 업데이트합니다.

```swift
let updatedContent = NotificationContent(
    id: "sample-notification",
    title: "업데이트된 제목",
    body: "내용이 변경되었습니다"
)

IosNotificationManager.shared.update(
    identifier: "sample-notification",
    content: updatedContent,
    trigger: nil
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 알림 취소 / 삭제

```swift
// 특정 보류 중인 알림 취소
IosNotificationManager.shared.cancel(identifier: "sample-notification")

// 보류 중인 알림 모두 취소
IosNotificationManager.shared.cancelAll()

// 알림 센터에서 특정 배달된 알림 삭제
IosNotificationManager.shared.removeDelivered(identifier: "sample-notification")

// 알림 센터에서 배달된 알림 모두 삭제
IosNotificationManager.shared.removeAllDelivered()
```

### 예약 알림

특정 ID로 미래 알림을 예약합니다.

```swift
let content = NotificationContent(
    id: "scheduled-notification",
    title: "예약 알림",
    body: "10초 후에 표시됩니다"
)

IosNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(10.0, repeats: false),
    identifier: "scheduled-notification"
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### 예약 취소

```swift
// 특정 예약 알림 취소
IosNotificationManager.shared.cancelScheduled(identifier: "scheduled-notification")

// 모든 예약 알림 취소
IosNotificationManager.shared.cancelAllScheduled()
```

### 조회

```swift
// 보류 중인（미배달） 알림 목록 가져오기
IosNotificationManager.shared.getScheduled { requests in
    requests.forEach { print($0.identifier) }
}

// 배달된 알림 목록 가져오기
IosNotificationManager.shared.getDelivered { notifications in
    notifications.forEach { print($0.identifier) }
}
```

### 배지

```swift
// 배지 수 설정（0으로 초기화）
IosNotificationManager.shared.setBadgeCount(1) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}

IosNotificationManager.shared.setBadgeCount(0) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 카테고리와 액션

알림에 액션 버튼이나 텍스트 입력을 추가합니다.

#### 카테고리 등록

```swift
let category = NotificationCategory(
    identifier: "sample-category",
    actions: [
        NotificationAction(
            identifier: "open",
            title: "열기",
            options: [.foreground]
        ),
        NotificationAction(
            identifier: "delete",
            title: "삭제",
            options: [.destructive]
        )
    ],
    textInputActions: [
        TextInputNotificationAction(
            identifier: "reply",
            title: "답장",
            buttonTitle: "보내기",
            textInputPlaceholder: "메시지를 입력하세요"
        )
    ],
    options: [.customDismissAction, .allowAnnouncement]
)

IosNotificationManager.shared.registerCategory(category)
```

#### 카테고리를 알림에 연결

`NotificationContent`의 `categoryIdentifier`에 카테고리 ID를 지정합니다.
알림을 길게 누르면 액션 버튼이 표시됩니다.

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "액션이 있는 알림",
    body: "길게 눌러 액션을 확인하세요",
    categoryIdentifier: "sample-category"
)
```

#### 카테고리 삭제

```swift
IosNotificationManager.shared.removeCategory(identifier: "sample-category")
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_Category.png" alt="Example_IosNotificationManager_Category" width="400" />
</p>

#### 액션 수신 콜백

```swift
// 액션 버튼 탭을 수신
IosNotificationManager.shared.onActionReceived = { notificationId, actionId, userInfo in
    print("notification: \(notificationId), action: \(actionId)")
}

// 텍스트 입력 액션 제출을 수신
IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, userInfo in
    print("notification: \(notificationId), action: \(actionId), text: \(userText)")
}
```

---

## Windows

（준비 중）

---

## macOS

### MacNotificationManager

`MacNotificationManager`는 macOS의 로컬 알림 작업을 모두 제공하는 싱글톤 클래스입니다.

**요구 사항:** macOS 15 이상. 이전 OS 버전에서의 호출은 `unsupportedOS`(에러 코드 1001)를 반환합니다.

**스레드 안전성:** 공개 API는 어느 스레드에서든 호출할 수 있습니다. 모든 completion 콜백은 **메인 큐**에서 실행됩니다.

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager.png" alt="Example_MacNotificationManager" width="800" />
</p>

### 설정

앱 실행 시(예: `applicationDidFinishLaunching`) 한 번만 `setup()`을 호출합니다. 액션 수신 콜백은 여기서 등록합니다.

```swift
import MacLibrary

MacNotificationManager.shared.setup()

// 액션 버튼 탭 수신
MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
    print("액션 수신: \(notificationId), \(actionId)")
}

// 텍스트 입력 액션 제출 수신
MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
    print("텍스트 입력 수신: \(userText)")
}
```

### 권한

#### 권한 요청

```swift
MacNotificationManager.shared.requestPermission { result in
    // 메인 큐에서 실행
    switch result {
    case .success:
        print("알림 권한이 허가되었습니다")
    case .failure(let error):
        if error.errorCode == 1002 || error.errorCode == 1003 {
            // 거부됨 — 설정 앱에서 수동으로 알림을 활성화해야 합니다
            print("권한이 거부되었습니다. 설정에서 알림을 활성화해 주세요.")
        } else {
            print("에러 \(error.errorCode): \(error.errorMessage)")
        }
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RequestPermission.png" alt="Example_MacNotificationManager_RequestPermission" width="800" />
</p>

#### 권한 확인

알림이 허가되어 있는지 불리언으로 확인합니다.

```swift
MacNotificationManager.shared.getAuthorizationStatus { result in
    switch result {
    case .success(let status):
        let hasPermission = status == .authorized || status == .provisional
        print("권한 여부: \(hasPermission)")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_HasPermission.png" alt="Example_MacNotificationManager_HasPermission" width="800" />
</p>

#### 인증 상태 가져오기

상세한 인증 상태 값을 가져옵니다.

```swift
MacNotificationManager.shared.getAuthorizationStatus { result in
    switch result {
    case .success(let status):
        // .notDetermined / .denied / .authorized / .provisional / .unsupported
        print(status)
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_AuthorizationStatus.png" alt="Example_MacNotificationManager_AuthorizationStatus" width="800" />
</p>

#### 알림 설정 열기

```swift
MacNotificationManager.shared.openNotificationSettings { result in
    if case .failure(let error) = result {
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_OpenNotificationSettings.png" alt="Example_MacNotificationManager_OpenNotificationSettings" width="800" />
</p>

#### 알림 권한 초기화 (macOS 26.3)

개발 중 한 번 거부한 권한을 초기화하는 절차입니다.

1. **시스템 설정** → **알림** 열기
2. 앱 목록에서 대상 앱을 **우클릭**
3. **"알림 재설정..."** 선택
4. 확인 다이얼로그에서 **"알림 재설정"** 버튼 누르기
5. 다음 앱 실행 시 권한 다이얼로그가 다시 표시됨

### 알림 표시

`NotificationContent`를 생성하고 `show()`를 호출합니다.

**`NotificationContent` 제약 조건:**
- `id`: 1〜128자 (`[A-Za-z0-9\-_]`)
- `title`: 1〜128자
- `body`: 0〜1024자 (선택 사항)

#### 즉시 표시

```swift
import MacLibrary

let content = NotificationContent(
    id: "mac-sample-notification",
    title: "Immediate Notification",
    body: "Displayed now",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)

MacNotificationManager.shared.show(content: content) { result in
    // 메인 큐에서 실행
    switch result {
    case .success:
        print("알림을 표시했습니다")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ShowImmediate.png" alt="Example_MacNotificationManager_ShowImmediate" width="800" />
</p>

#### 시간 간격 트리거

```swift
MacNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(seconds: 10, repeats: false)
) { result in
    switch result {
    case .success:
        print("10초 후로 예약됨")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ShowTimeInterval.png" alt="Example_MacNotificationManager_ShowTimeInterval" width="800" />
</p>

#### 캘린더 트리거

```swift
let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
components.second = 0

MacNotificationManager.shared.show(
    content: content,
    trigger: .calendar(dateComponents: components, repeats: false)
) { result in
    switch result {
    case .success:
        print("1분 후로 예약됨")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ShowCalendar.png" alt="Example_MacNotificationManager_ShowCalendar" width="800" />
</p>

### 업데이트 / 취소 / 삭제

#### ID로 업데이트

보류 중인 알림을 새 내용으로 교체합니다.

```swift
let updatedContent = NotificationContent(
    id: "mac-sample-notification",
    title: "Updated Notification",
    body: "This content was updated",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)

MacNotificationManager.shared.update(
    identifier: "mac-sample-notification",
    content: updatedContent,
    trigger: .immediate
) { result in
    switch result {
    case .success:
        print("업데이트됨")
    case .failure(let error):
        // 알림을 찾을 수 없는 경우 에러 코드 1104
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_UpdateById.png" alt="Example_MacNotificationManager_UpdateById" width="800" />
</p>

#### ID로 취소

```swift
MacNotificationManager.shared.cancelScheduled(identifier: "mac-sample-notification")
```

#### 전체 취소

```swift
MacNotificationManager.shared.cancelAllScheduled()
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_CancelAll.png" alt="Example_MacNotificationManager_CancelAll" width="800" />
</p>

#### 전달된 알림 삭제

알림 센터에서 특정 알림을 삭제합니다.

```swift
MacNotificationManager.shared.removeDelivered(identifier: "mac-sample-notification")
```

#### 전달된 알림 전체 삭제

```swift
MacNotificationManager.shared.removeAllDelivered()
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RemoveAllDelivered.png" alt="Example_MacNotificationManager_RemoveAllDelivered" width="800" />
</p>

### 예약

`schedule()`을 사용하여 미래 알림을 등록합니다. 트리거는 `.immediate` 이외를 지정해야 합니다.

#### 시간 간격으로 예약

```swift
let content = NotificationContent(
    id: "mac-sample-scheduled",
    title: "Scheduled Notification",
    body: "Scheduled in 10 seconds",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-scheduled"],
    badge: nil
)

MacNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(seconds: 10, repeats: false)
) { result in
    switch result {
    case .success:
        print("예약됨")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ScheduleTimeInterval.png" alt="Example_MacNotificationManager_ScheduleTimeInterval" width="800" />
</p>

#### 캘린더로 예약

```swift
let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
components.second = 0

MacNotificationManager.shared.schedule(
    content: content,
    trigger: .calendar(dateComponents: components, repeats: false)
) { result in
    switch result {
    case .success:
        print("캘린더 예약됨")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ScheduleCalendar.png" alt="Example_MacNotificationManager_ScheduleCalendar" width="800" />
</p>

#### ID로 예약 취소

```swift
MacNotificationManager.shared.cancelScheduled(identifier: "mac-sample-scheduled")
```

#### 전체 예약 취소

```swift
MacNotificationManager.shared.cancelAllScheduled()
```

### 조회

#### 예약된 알림 조회

```swift
MacNotificationManager.shared.getScheduled { result in
    switch result {
    case .success(let items):
        let ids = items.map { $0.identifier }.joined(separator: ", ")
        print("예약됨: \(items.count)건, ids=[\(ids)]")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_GetScheduled.png" alt="Example_MacNotificationManager_GetScheduled" width="800" />
</p>

#### 전달된 알림 조회

```swift
MacNotificationManager.shared.getDelivered { result in
    switch result {
    case .success(let items):
        let ids = items.map { $0.identifier }.joined(separator: ", ")
        print("전달됨: \(items.count)건, ids=[\(ids)]")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_GetDelivered.png" alt="Example_MacNotificationManager_GetDelivered" width="800" />
</p>

### 배지

#### 배지 카운트 설정 (1)

```swift
MacNotificationManager.shared.setBadgeCount(1) { result in
    switch result {
    case .success:
        print("배지를 1로 설정했습니다")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_SetBadgeCount1.png" alt="Example_MacNotificationManager_SetBadgeCount1" width="800" />
</p>

#### 배지 초기화 (0)

```swift
MacNotificationManager.shared.setBadgeCount(0) { result in
    switch result {
    case .success:
        print("배지를 초기화했습니다")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_SetBadgeCount0.png" alt="Example_MacNotificationManager_SetBadgeCount0" width="800" />
</p>

### 카테고리

#### 카테고리 등록

```swift
let category = NotificationCategory(
    id: "mac-sample-category",
    actions: [
        NotificationAction(id: "open", title: "Open", isForeground: true),
        NotificationAction(id: "reply", title: "Reply", isTextInput: true, textInputPlaceholder: "Type message")
    ]
)

MacNotificationManager.shared.registerCategory(category) { result in
    switch result {
    case .success:
        // 알림을 전송하고 우클릭하면 액션(Open, Reply)이 표시됩니다
        print("카테고리를 등록했습니다")
    case .failure(let error):
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

`NotificationContent`의 `categoryIdentifier`를 설정하여 카테고리를 알림에 연결합니다.

```swift
let content = NotificationContent(
    id: "mac-sample-notification",
    title: "액션이 있는 알림",
    body: "우클릭하면 액션이 표시됩니다",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RegisterCategory.png" alt="Example_MacNotificationManager_RegisterCategory" width="800" />
</p>

#### 카테고리 삭제

```swift
MacNotificationManager.shared.removeCategory(identifier: "mac-sample-category") { result in
    if case .failure(let error) = result {
        print("에러 \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RemoveCategory.png" alt="Example_MacNotificationManager_RemoveCategory" width="800" />
</p>

### 에러 코드

| 코드 | 케이스 | 설명 |
|---|---|---|
| 1001 | `unsupportedOS` | macOS 15 이상 필요 |
| 1002 | `permissionDenied` | 사용자가 알림 권한 거부 |
| 1003 | `permissionRequestFailed` | 권한 요청 실패 |
| 1101 | `invalidContent` | id, title, 또는 body가 유효하지 않음 |
| 1102 | `invalidTrigger` | 트리거가 유효하지 않음 (예: timeInterval < 1초) |
| 1103 | `invalidCategory` | 카테고리가 유효하지 않음 |
| 1104 | `notificationNotFound` | 지정한 식별자의 보류 중 알림을 찾을 수 없음 |
| 1201 | `addFailed` | 알림 요청 추가 실패 |
| 1202 | `removeFailed` | 알림 삭제 실패 |
| 1203 | `queryFailed` | 알림 조회 실패 |
| 1204 | `setBadgeFailed` | 배지 카운트 설정 실패 |
| 1205 | `openSettingsFailed` | 알림 설정 열기 실패 |
| 1999 | `unknown` | 알 수 없는 에러 |
