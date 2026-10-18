# 알림 기능

언어:

- 日本語: [notification.ja.md](notification.ja.md)
- English: [notification.md](notification.md)
- 한국어（이 페이지）

← [매뉴얼 상단으로 돌아가기](index.ko.md)

---

## 목차

- [Android](#android)
  - [AndroidNotificationManager](#androidnotificationmanager)
  - [1.x에서 바뀐 점](#1x에서-바뀐-점)
  - [설정](#설정)
    - [권한과 컴포넌트](#권한과-컴포넌트)
    - [초기화](#초기화)
    - [매니저 가져오기](#매니저-가져오기)
  - [권한](#권한)
    - [권한 상태 확인](#권한-상태-확인)
    - [권한 요청(콜백)](#권한-요청콜백)
    - [권한 요청(코루틴)](#권한-요청코루틴)
    - [권한 요청 취소](#권한-요청-취소)
    - [설정 화면 열기](#설정-화면-열기)
  - [채널 관리](#채널-관리)
  - [기본 알림 조작](#기본-알림-조작)
  - [알림 스타일](#알림-스타일)
  - [플랫폼 옵션](#플랫폼-옵션)
  - [커스텀 뷰 스타일](#커스텀-뷰-스타일)
  - [그룹 알림](#그룹-알림)
  - [인터랙션](#인터랙션)
    - [이벤트 수신](#이벤트-수신)
    - [본문 탭 이벤트](#본문-탭-이벤트)
    - [액션 버튼](#액션-버튼)
    - [DeleteIntent(닫기 이벤트)](#deleteintent닫기-이벤트)
    - [FullScreenIntent(전체 화면 표시)](#fullscreenintent전체-화면-표시)
  - [진행 상황 알림](#진행-상황-알림)
  - [포어그라운드 서비스 알림](#포어그라운드-서비스-알림)
  - [예약 알림](#예약-알림)
    - [예약 취소](#예약-취소)
    - [예약 여부 확인](#예약-여부-확인)
    - [기기 재부팅 후 복원](#기기-재부팅-후-복원)
    - [1.x가 저장한 예약](#1x가-저장한-예약)
  - [C ABI](#c-abi)
    - [초기화, 권한, 설정](#초기화-권한-설정)
    - [채널과 내용 빌더](#채널과-내용-빌더)
    - [스타일, 탭, 액션](#스타일-탭-액션)
    - [예약과 진행 상황](#예약과-진행-상황)
    - [인터랙션과 표시 이벤트](#인터랙션과-표시-이벤트)
    - [알림 오류](#알림-오류)
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
  - [NativeToolkit::Notification](#nativetoolkitnotification)
  - [설정](#설정-2)
    - [Package.appxmanifest(패키지 앱)](#packageappxmanifest패키지-앱)
    - [Manager 생성 패키지 앱](#manager-생성-패키지-앱)
    - [Manager 생성 비패키지 앱](#manager-생성-비패키지-앱)
    - [종료](#종료)
  - [초기화 / 설정](#초기화--설정)
    - [알림 설정 가져오기](#알림-설정-가져오기)
    - [알림 설정 열기](#알림-설정-열기-1)
  - [알림 표시](#알림-표시-1)
    - [기본](#기본)
    - [버튼 포함](#버튼-포함)
    - [이미지 포함](#이미지-포함)
    - [입력 포함](#입력-포함)
    - [진행률 포함](#진행률-포함)
    - [만료 포함](#만료-포함)
    - [사운드 포함](#사운드-포함)
  - [알림 예약](#알림-예약)
    - [예약 취소](#예약-취소-2)
  - [진행률 갱신](#진행률-갱신)
  - [배지](#배지-1)
  - [삭제 / 조회](#삭제--조회)
    - [전체 알림 가져오기](#전체-알림-가져오기)
    - [ID로 삭제](#id로-삭제)
    - [태그로 삭제](#태그로-삭제)
    - [전체 삭제](#전체-삭제)
  - [활성화 핸들러](#활성화-핸들러)
  - [오류 코드](#오류-코드)
  - [C ABI](#c-abi-1)
    - [런타임, 매니저, 활성화](#런타임-매니저-활성화)
    - [내용 구성, 표시, 예약](#내용-구성-표시-예약)
    - [진행률, 배지, OS 설정](#진행률-배지-os-설정)
    - [목록과 삭제](#목록과-삭제)
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

Android 12(API 31) 이상의 로컬 알림입니다. Android 라이브러리 2.0.0은 하나의 구현 위에 두 가지 공개 API를 제공하며, 샘플 앱은 Kotlin API를 사용합니다.

| API | 이름 | 패키지 / 헤더 | AAR |
|---|---|---|---|
| Kotlin API | `AndroidNotificationManager` | `com.jonghyunkim.nativetoolkit.notification` | `android-native-toolkit-2.0.0.aar` |
| C ABI | `ntk_notification_*` | `<NativeToolkitC/Notification.h>` | `android-native-toolkit-capi-2.0.0.aar` |

C ABI는 이 섹션 끝의 [C ABI](#c-abi)에서 설명합니다. 1.x에서 옮겨 오는 경우 [1.x에서 바뀐 점](#1x에서-바뀐-점)과 [Android 라이브러리를 2.0.0으로 마이그레이션](index.ko.md#android-라이브러리를-200으로-마이그레이션)을 읽어 주십시오.

### AndroidNotificationManager

- `AndroidNotificationManager.getInstance(context)`는 프로세스에 하나뿐인 매니저를 반환합니다. Application Context만 보관하므로 어떤 Context를 전달해도 됩니다.
- 알림을 게시, 변경, 삭제하는 작업은 `Result<Unit>`을 반환합니다. 예외는 진행 상황 포어그라운드 서비스 호출(`startProgress`, `updateProgress`, `completeProgress`, `stopProgress`)로, 이들은 `Unit`을 반환하고 Android가 서비스를 거부하면 예외를 던집니다. 조회(`hasPermission`, `areNotificationsEnabled`, `canScheduleExactAlarms`, `isScheduled`, `getActive`)는 값을 바로 반환합니다. 이 호출들은 동기식이며 어느 스레드에서든 호출할 수 있고, 메인 스레드를 기다리지 않습니다.
- `schedule`, `cancelScheduled`, `cancelAllScheduled`는 저장된 예약을 호출한 스레드에서 파일에 씁니다. 메인 스레드에서 호출하면 그곳에서 디스크에 접근하며, 다른 스레드의 쓰기를 기다릴 수 있습니다.
- `requestPermission`은 비동기입니다. 결과는 메인 스레드로 전달되며, 호출 안에서 전달되는 일은 없습니다.
- `interactions`와 `shown`은 이벤트 허브(`EventHub`)입니다. 리스너의 추가와 제거는 메인 스레드에서만 합니다(그 밖에서는 `IllegalStateException`). 리스너는 메인 스레드에서 호출되며, 리스너가 던진 예외는 잡혀서 로그에 기록됩니다.
- `NotificationUseCases`, `NotificationPermissionHelper`, `ProgressForegroundNotifications`는 1.x의 동작 그대로 공개되어 있습니다. 이 페이지에서는 매니저를 사용합니다.

---

### 1.x에서 바뀐 점

| 1.x | 2.0.0 |
|---|---|
| 패키지 `android.library.notification.*` | 패키지 `com.jonghyunkim.nativetoolkit.notification.*`. 하위 패키지(`domain.model`, `application.model`, `presentation.*`)는 같습니다 |
| `NotificationUseCases(context)` | `AndroidNotificationManager.getInstance(context)`. 작업 이름은 같습니다. `isScheduled(context, id)`는 `isScheduled(id, tag)`가 됩니다 |
| `NotificationPermissionHelper(activity).requestPermission { granted -> }` | `manager.requestPermission { result -> }` 또는 `suspend` 버전. Activity가 필요하지 않습니다 |
| `openNotificationSettings()` / `openExactAlarmSettings()` | `manager.openSettings(NotificationSettingsTarget.NOTIFICATIONS, activity)` / `manager.openSettings(NotificationSettingsTarget.EXACT_ALARM, activity)` |
| `ProgressForegroundNotifications.start(context, command)` 등 | `manager.startProgress(command)` / `updateProgress` / `completeProgress` / `stopProgress` |
| 액션 버튼과 닫기를 위한 자체 `BroadcastReceiver` | `NotificationEventIntents`와 `manager.interactions`([인터랙션](#인터랙션) 참조) |
| 매니페스트에 작성한 라이브러리의 `<service>`와 `<receiver>` | 필요하지 않습니다. AAR이 새 이름으로 선언합니다. 1.x 매뉴얼에 따라 추가한 `android.library.*` 항목은 삭제해 주십시오 |
| 1.x로 예약한 알림 | 앱이 처음 2.0.0으로 실행될 때 한 번 폐기됩니다([1.x가 저장한 예약](#1x가-저장한-예약) 참조) |
| 1.x가 표시했고 아직 화면에 남아 있는 알림 | 업데이트 후에는 탭에도 액션 버튼에도 반응하지 않습니다. 가리키는 리시버의 클래스 이름이 바뀌었기 때문입니다. 필요하면 다시 표시해 주십시오 |

---

### 설정

[매뉴얼 상단](index.ko.md#방법-a-maven-저장소권장)의 설명에 따라 AAR을 앱에 추가합니다.

#### 권한과 컴포넌트

알림에 필요한 것은 모두 AAR이 선언하며, 매니페스트 병합으로 앱에 추가됩니다. 앱 자체의 `AndroidManifest.xml`에 추가할 것은 없습니다.

- 권한: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `FOREGROUND_SERVICE_SPECIAL_USE`
- 컴포넌트: 알림 이벤트와 예약 알림을 위한 리시버(재부팅 후 예약을 복원하는 것을 포함합니다), 알림에서 앱을 여는 보이지 않는 Activity, 필요할 때 권한 대화상자를 띄우는 투명한 Activity, 진행 상황(`dataSync`)과 통화(`specialUse`) 포어그라운드 서비스

앱에서 사용하지 않는 권한을 제거하는 방법은 [앱에 추가되는 권한과 컴포넌트](index.ko.md#앱에-추가되는-권한과-컴포넌트)를 참조해 주십시오.

#### 초기화

라이브러리는 앱이 시작될 때 AndroidX App Startup을 통해 스스로 초기화합니다. App Startup을 비활성화한 앱은 첫 Activity의 `onCreate`에서 `LibraryRuntime.ensureInitialized(activity)`를 직접 호출하고 그 Activity를 전달합니다. 그때까지 권한 요청은 `Failed(NOT_INITIALIZED)`로 완료됩니다. 단, 권한이 이미 허용되어 있거나 기기가 Android 12L(API 32) 이하이면 초기화 전에도 `Granted`로 완료됩니다. 그 밖의 작업은 초기화 없이 동작합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime

// App Startup을 비활성화한 경우에만 첫 Activity의 onCreate에서 호출합니다. Activity를 전달합니다.
// 전달한 Activity가 포어그라운드 Activity로 취급됩니다.
when (LibraryRuntime.ensureInitialized(this)) {
    LibraryRuntime.InitState.DONE -> Unit        // 초기화됨(이후의 모든 호출에서도 같음)
    LibraryRuntime.InitState.IN_PROGRESS -> Unit // 다른 스레드가 초기화 중. 나중에 다시 호출합니다
    LibraryRuntime.InitState.ERROR -> Unit       // 이 호출은 실패했고 한 일을 되돌렸습니다. 재시도하려면 다시 호출합니다
}
```

#### 매니저 가져오기

```kotlin
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager

val manager = AndroidNotificationManager.getInstance(activity)
```

---

### 권한

#### 권한 상태 확인

```kotlin
// 런타임 권한이 없는 Android 12L(API 32) 이하에서는 항상 true입니다.
val permissionGranted: Boolean = manager.hasPermission()

// 사용자가 설정에서 앱의 알림을 끄면 false입니다.
val notificationsEnabled: Boolean = manager.areNotificationsEnabled()

// 정확한 알람이 허용되어 있는지("알람 및 리마인더").
val exactAlarmAllowed: Boolean = manager.canScheduleExactAlarms()
```

요청 전에 설명을 보여 줄지 판단하려면 Activity가 필요하므로 이 기능은 `NotificationPermissionHelper`에 남아 있습니다. 헬퍼는 Activity의 `onCreate`에서 생성해 주십시오. 헬퍼는 Activity Result 런처를 등록하는데, Activity는 시작되기 전에만 이를 받아들입니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.NotificationPermissionHelper

class MainActivity : AppCompatActivity() {

    private lateinit var notificationPermissionHelper: NotificationPermissionHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        notificationPermissionHelper = NotificationPermissionHelper(this)
    }

    fun shouldShowRationale(): Boolean =
        notificationPermissionHelper.shouldShowPermissionRationale()
}
```

#### 권한 요청(콜백)

라이브러리는 앱의 포어그라운드 Activity 위에 시스템 대화상자를 표시합니다. 호출하는 쪽은 Activity를 전달하지 않습니다. 어느 스레드에서든 호출할 수 있으며 요청 ID를 반환합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

// 요청은 Activity의 재생성을 넘어 이어지므로, 결과는 요청한 화면의 상태가 아니라
// 결과가 올 때 표시되어 있는 화면에 전달합니다.
val requestId: Long = manager.requestPermission { result ->
    // 메인 스레드에서 정확히 한 번, requestPermission 안이 아닌 곳에서 호출됩니다.
    ScreenResults.notificationStatus.deliver(when (result) {
        PermissionRequestResult.Granted -> "Notification permission granted."
        PermissionRequestResult.Denied ->
            "Notification permission is not granted. Use 'Open Notification Settings' above to enable it."
        is PermissionRequestResult.Canceled -> "Permission request ended: ${result.reason}"
        is PermissionRequestResult.Failed -> "Permission request ended: ${result.reason}"
    })
}
```

| 결과 | 조건 |
|---|---|
| `Granted` | 사용자가 허용함, 이미 허용되어 있었음, 또는 기기가 Android 12L 이하(뒤의 두 경우에는 대화상자를 표시하지 않습니다) |
| `Denied` | 사용자가 거부함, 또는 시스템이 묻지 않고 거부함 |
| `Canceled(CancelReason.REQUESTED)` | `cancelPermissionRequest`가 호출됨 |
| `Canceled(CancelReason.HOST_DESTROYED)` | 대화상자를 표시한 Activity가 소멸됨(구성 변경에 의한 것은 제외) |
| `Failed(UiUnavailableReason.NOT_FOREGROUND)` | 앱의 Activity가 포어그라운드에 없었음 |
| `Failed(UiUnavailableReason.NOT_INITIALIZED)` | 라이브러리가 초기화되지 않았고 권한도 아직 허용되지 않음([초기화](#초기화) 참조) |
| `Failed(UiUnavailableReason.HOST_START_FAILED)` | 라이브러리가 투명한 호스트 Activity를 시작하지 못함 |

`CancelReason`과 `UiUnavailableReason`은 `com.jonghyunkim.nativetoolkit.common.domain`에 있습니다.

- 다른 요청이 대화상자를 기다리는 동안 한 요청은 그 응답을 공유합니다.
- 요청은 Activity의 구성 변경을 넘어 이어지므로, 요청한 Activity가 사라진 뒤에 콜백이 올 수 있습니다. 요청한 화면의 상태에는 쓰지 마십시오. 샘플 앱은 그때 표시되어 있는 화면에 결과를 전달합니다(`ScreenResults.notificationStatus`. 표시 중인 화면이 연결하는 작은 보관 객체입니다).

#### 권한 요청(코루틴)

`suspend` 버전은 권한이 허용되었는지를 반환하며, 응답이 없으면 예외를 던집니다. 코루틴을 취소하면 요청도 취소됩니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.error.PermissionRequestDomainError

scope.launch {
    statusText = try {
        if (manager.requestPermission()) {
            "Notification permission granted (coroutine)."
        } else {
            "Notification permission is not granted (coroutine)."
        }
    } catch (e: PermissionRequestDomainError.Canceled) {
        "Permission request ended: ${e.reason}"
    } catch (e: PermissionRequestDomainError.Unavailable) {
        "Permission request ended: ${e.reason}"
    }
}
```

#### 권한 요청 취소

요청은 아직 결과가 없으면 `Canceled(REQUESTED)`로 완료됩니다. 시스템 대화상자가 표시되어 있으면 다른 요청을 위해 남습니다. 알 수 없는 ID는 무시됩니다.

```kotlin
manager.cancelPermissionRequest(requestId)
```

#### 설정 화면 열기

`openSettings`는 앱의 설정 화면 중 하나를 열고, 요청한 화면을 사용할 수 없으면 앱 정보 화면을 대신 엽니다. 열 때 기준이 되는 Activity를 전달합니다. `null`이면 Application Context에서 새 태스크로 엽니다. 앱이 포어그라운드에 있는지는 확인하지 않습니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget

// 앱의 알림 설정.
val opened = manager.openSettings(NotificationSettingsTarget.NOTIFICATIONS, activity) != NotificationSettingsOpenResult.FAILED

// 앱 정보 화면.
manager.openSettings(NotificationSettingsTarget.APP_DETAILS, activity)

// 사용자가 정확한 알람을 허용하는 "알람 및 리마인더".
manager.openSettings(NotificationSettingsTarget.EXACT_ALARM, activity)
```

| `NotificationSettingsOpenResult` | 의미 |
|---|---|
| `OPENED` | 요청한 화면이 열림 |
| `OPENED_FALLBACK` | 요청한 화면을 사용할 수 없어서 앱 정보 화면이 대신 열림 |
| `FAILED` | 어떤 화면도 열 수 없었음 |

---

### 채널 관리

알림은 채널에 게시됩니다. `show`는 내용의 채널이 아직 없으면 생성합니다. 채널 설정이 등록되는 시점을 제어하려면 채널을 미리 생성해 주십시오.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel

val sampleChannel = NotificationChannel(
    id = "native_toolkit_sample",
    name = "Native Toolkit Sample",
    description = "Notification sample channel"
)

// 생성
manager.createChannel(sampleChannel)
    .onFailure { Log.w(TAG, "[ensureChannel] failed: channelId=${sampleChannel.id}", it) }

// 여러 채널을 한 번에 생성
manager.createChannels(listOf(sampleChannel, scheduleSampleChannel))

// 삭제
manager.deleteChannel("native_toolkit_sample")
```

- 여기서의 `NotificationChannel`은 라이브러리의 타입(`com.jonghyunkim.nativetoolkit.notification.domain.model`)이며 `android.app.NotificationChannel`이 아닙니다.
- `importance`에는 `android.app.NotificationManager`의 상수를 지정합니다. 기본값은 `IMPORTANCE_DEFAULT`(3)입니다. `IMPORTANCE_MAX`처럼 라이브러리가 모르는 값은 `IMPORTANCE_DEFAULT`가 됩니다.
- Android는 채널의 중요도, 소리, 진동을 처음 생성했을 때의 값으로 유지하며, 이후에는 사용자가 관리합니다. 바꾸려면 새 채널 ID를 사용해 주십시오.

---

### 기본 알림 조작

#### 표시

알림은 `AndroidNotificationCommand`로 나타냅니다. 내용(`NotificationContent`)과 Android 전용 옵션(`AndroidNotificationPlatformOptions`, [플랫폼 옵션](#플랫폼-옵션) 참조)으로 이루어집니다.

```kotlin
import android.app.PendingIntent
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationStyle

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1001,
        title = "Native Toolkit",
        message = "Default style notification sample",
        channel = sampleChannel,
        subText = "Default",
        style = NotificationStyle.Default
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // 알림을 탭하면 MainActivity가 열립니다.
        contentIntent = AndroidPendingIntentRequest(
            intent = Intent(activity, MainActivity::class.java).apply {
                action = "native.toolkit.notification.open"
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            requestCode = 1001,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    )
)

// 권한이 없거나 알림이 꺼져 있으면 show는 아무것도 게시하지 않고 성공합니다.
if (!manager.hasPermission() || !manager.areNotificationsEnabled()) {
    statusText = "Unable to show notifications. Check permissions or notification settings."
    return
}

manager.show(command)
    .onSuccess { statusText = "Displayed Default style notification." }
    .onFailure { throwable ->
        statusText = "Failed to show notification: ${throwable.message ?: throwable::class.java.simpleName}"
    }
```

- `smallIconResId`를 지정하지 않으면 알림은 `android.R.drawable.ic_dialog_info`를 사용합니다.
- `NotificationContent`의 다른 속성(`tag`, `largeIconResId`, `priority`, `autoCancel`, `ongoing`, `showTimestamp`, `timestampMillis`, `soundUri`, `category`, `visibility`, `color`, `number`, `ticker`, `onlyAlertOnce`, `localOnly`, `silent`, `usesChronometer`, `timeoutAfterMillis`, 그리고 아래의 그룹과 진행 상황 속성)은 생략할 수 있습니다.

#### 업데이트

같은 `id`와 `tag`의 커맨드를 전달하면 표시 중인 알림을 교체합니다.

```kotlin
manager.update(updatedCommand)
```

#### 취소

```kotlin
// 알림 하나를 삭제
manager.cancel(command.content.id, command.content.tag)
    .onSuccess { statusText = "Deleted Default Style notification." }

// 앱의 모든 알림을 삭제
manager.cancelAll()
```

#### 활성 알림 가져오기

앱이 현재 표시하고 있는 알림을 반환합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.ActiveNotification

val activeList: List<ActiveNotification> = manager.getActive()
activeList.forEach { it.id; it.tag; it.channelId; it.title; it.message; it.isOngoing; it.groupKey }
```

---

### 알림 스타일

`NotificationContent`의 `style` 속성에 지정합니다. 아래 값은 샘플 앱의 값입니다.

#### Default

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
    bigText = "This is a BigText notification sample from Native Toolkit Example. Expand the notification to verify the full body text rendering.",
    summaryText = "BigText",
    bigContentTitle = "BigText Style"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigText.png" alt="Example_BigText" width="400" />
</p>

#### Inbox

펼치면 여러 줄을 목록 형식으로 표시합니다.

```kotlin
style = NotificationStyle.Inbox(
    lines = listOf(
        "• Permission status checked",
        "• Channel created successfully",
        "• Immediate notification sent",
        "• Scheduled notification ready"
    ),
    summaryText = "4 sample events",
    bigContentTitle = "Inbox Style"
)
```

<p align="center">
    <img src="images/android/notification/Example_Inbox.png" alt="Example_Inbox" width="400" />
</p>

#### BigPicture

알림을 펼치면 이미지를 표시합니다. 이미지는 `pictureResId` 또는 `pictureUriString`으로 지정합니다.

```kotlin
style = NotificationStyle.BigPicture(
    pictureResId = R.mipmap.ic_launcher,
    summaryText = "Launcher image preview",
    bigContentTitle = "BigPicture Style",
    largeIconResId = R.mipmap.ic_launcher_round  // 펼쳤을 때 표시. hideExpandedLargeIcon = true로 숨김
)
```

<p align="center">
    <img src="images/android/notification/Example_BigPicture.png" alt="Example_BigPicture" width="400" />
</p>

#### Messaging

채팅 기록을 대화 형식으로 표시합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationMessage

val now = System.currentTimeMillis()

style = NotificationStyle.Messaging(
    userDisplayName = "You",
    conversationTitle = "Native Toolkit Example",
    isGroupConversation = true,
    messages = listOf(
        NotificationMessage(
            text = "Can you verify the notification styles?",
            timestampMillis = now - 120_000L,
            senderName = "Alex"
        ),
        NotificationMessage(
            text = "Sure, BigText / Inbox / BigPicture / Messaging are ready.",
            timestampMillis = now - 60_000L,
            senderName = "Jordan"
        ),
        NotificationMessage(
            text = "Confirmed. This is the Messaging sample.",
            timestampMillis = now,
            senderName = "You"         // null = 기기의 사용자
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Messaging.png" alt="Example_Messaging" width="400" />
</p>

#### Media

미디어 플레이어 형식으로 표시합니다. `compactActionIndices`에는 접힌 보기에 표시할 액션 버튼을 지정합니다(최대 3개).

```kotlin
import androidx.core.app.NotificationCompat
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents

// 미디어 버튼은 탭을 이벤트로 알리고 앱을 앞으로 가져옵니다.
fun buildMediaActions(notificationId: Int): List<AndroidNotificationAction> {
    fun action(actionId: String, label: String, iconResId: Int) = AndroidNotificationAction(
        title = label,
        pendingIntent = NotificationEventIntents.action(
            context = activity,
            notificationId = notificationId,
            tag = null,
            actionId = actionId,
            data = mapOf("label" to label),
            launchApp = true
        ),
        iconResId = iconResId
    )
    return listOf(
        action("previous", "Previous", android.R.drawable.ic_media_previous),
        action("play", "Play", android.R.drawable.ic_media_play),
        action("next", "Next", android.R.drawable.ic_media_next)
    )
}

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1006,
        title = "Native Toolkit Player",
        message = "Media style notification sample",
        channel = sampleChannel,
        subText = "Media",
        largeIconResId = R.mipmap.ic_launcher_round,
        category = NotificationCompat.CATEGORY_TRANSPORT,
        priority = NotificationCompat.PRIORITY_LOW,
        ongoing = true,
        autoCancel = false,
        style = NotificationStyle.Media(compactActionIndices = listOf(0, 1, 2))
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // buildActivityPendingIntentRequest: 플랫폼 옵션 참조
        contentIntent = buildActivityPendingIntentRequest(2000, "native.toolkit.media.open"),
        actions = buildMediaActions(1006)
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Media.png" alt="Example_Media" width="400" />
</p>

`NotificationStyle.Call`(통화 알림)은 [Call Style FGS](#call-style-fgs통화-알림)에서 설명합니다.

---

### 플랫폼 옵션

`AndroidNotificationPlatformOptions`는 Android에만 있는 것을 담습니다. 각 `PendingIntent`는 `AndroidPendingIntentRequest`로 기술하며, 라이브러리가 알림을 게시할 때 `PendingIntent`로 변환합니다.

| 속성 | 타입 | 용도 |
|---|---|---|
| `contentIntent` | `AndroidPendingIntentRequest?` | 알림 본문을 탭했을 때 실행 |
| `deleteIntent` | `AndroidPendingIntentRequest?` | 알림이 닫혔을 때 실행 |
| `fullScreenIntent` | `AndroidPendingIntentRequest?` | 전체 화면 표시([FullScreenIntent](#fullscreenintent전체-화면-표시) 참조) |
| `actions` | `List<AndroidNotificationAction>` | 액션 버튼 |
| `largeIconBitmap` | `Bitmap?` | 비트맵으로 지정하는 큰 아이콘. `NotificationContent.largeIconResId`와 함께 쓰지 마십시오 |
| `callStyleOptions` | `AndroidNotificationCallPlatformOptions?` | `NotificationStyle.Call` 알림의 `answerIntent`, `declineIntent`, `hangUpIntent` |
| `customViewOptions` | `AndroidNotificationCustomViewPlatformOptions?` | 커스텀 뷰의 내용([커스텀 뷰 스타일](#커스텀-뷰-스타일) 참조) |

`AndroidPendingIntentRequest(intent, requestCode, type, flags, mutable)`는 감쌀 `Intent`, 요청 코드, 대상(기본값은 `AndroidPendingIntentType.ACTIVITY`. 그 밖에 `BROADCAST`, `SERVICE`, `FOREGROUND_SERVICE`), 추가 `PendingIntent` 플래그, `PendingIntent`를 변경 가능하게 할지(기본값은 `false`)를 받습니다. 샘플 앱은 Activity용 요청을 헬퍼로 만듭니다.

```kotlin
import android.app.PendingIntent
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest

fun buildActivityPendingIntentRequest(
    targetActivityClass: Class<*>,
    requestCode: Int,
    action: String
): AndroidPendingIntentRequest {
    return AndroidPendingIntentRequest(
        intent = Intent(activity, targetActivityClass).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        requestCode = requestCode,
        flags = PendingIntent.FLAG_UPDATE_CURRENT
    )
}

fun buildActivityPendingIntentRequest(requestCode: Int, action: String): AndroidPendingIntentRequest =
    buildActivityPendingIntentRequest(MainActivity::class.java, requestCode, action)
```

본문 탭, 액션 버튼, 닫기를 코드에서 받아야 한다면 대신 `NotificationEventIntents`가 만드는 요청을 사용해 주십시오. 라이브러리가 이를 이벤트로 전달하므로 자체 리시버가 필요하지 않습니다([인터랙션](#인터랙션) 참조).

`AndroidNotificationAction`은 `title`과 `pendingIntent`를 가지며, 선택적으로 `iconResId`, `allowGeneratedReplies`, `semanticAction`(`NotificationCompat.Action`의 상수), `contextual`, `showsUserInterface`를 가집니다.

`NotificationResourceResolver(context)`(`com.jonghyunkim.nativetoolkit.notification.presentation.resource`)는 아이콘이나 레이아웃 이름을 데이터로 가진 앱을 위해 리소스 이름을 ID로 바꿉니다. `resolve(name, type)`은 이름을 `type`(`drawable`, `mipmap`, `layout`, `id`. `null`이면 `drawable`, 다음으로 `mipmap`)으로 찾고, `defaultSmallIcon()`은 앱 아이콘을 반환합니다.

---

### 커스텀 뷰 스타일

자체 레이아웃으로 알림을 표시합니다. `RemoteViewAction`으로 뷰의 내용과 클릭 대상을 설정합니다.

#### DecoratedCustomView

```kotlin
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.RemoteViewAction
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCustomViewStyleData

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1007,
        title = "Native Toolkit",
        message = "Decorated custom view notification sample",
        channel = sampleChannel,
        subText = "DecoratedCustomView",
        style = NotificationStyle.DecoratedCustomView(
            customView = NotificationCustomViewStyleData(
                layoutResId = R.layout.notification_custom_style_sample,             // 접힌 보기
                bigLayoutResId = R.layout.notification_custom_style_sample_expanded  // 펼친 보기(선택)
            )
        )
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(2100, "native.toolkit.custom.open"),
        customViewOptions = AndroidNotificationCustomViewPlatformOptions(
            viewActions = listOf(
                // 텍스트 설정
                RemoteViewAction.SetText(R.id.notification_title, "Native Toolkit"),
                RemoteViewAction.SetText(R.id.notification_message, "Decorated custom view sample"),
                // 이미지 설정
                RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher_round),
                // 뷰 클릭은 이 액션 ID의 ACTION 이벤트로 전달됩니다
                RemoteViewAction.SetClickIntent(
                    viewId = R.id.notification_btn_dismiss,
                    pendingIntent = NotificationEventIntents.action(
                        context = activity,
                        notificationId = 1007,
                        tag = null,
                        actionId = "custom_view_dismiss",
                        data = mapOf("label" to "Dismiss")
                    )
                )
            )
        )
    )
)

manager.show(command)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedCustomView.png" alt="Example_DecoratedCustomView" width="400" />
</p>

> **참고:** `RemoteViews`의 제약으로 인해 클릭 가능한 요소에는 `Button` 대신 `LinearLayout` + `TextView`를 사용해 주십시오. 클릭 이벤트는 `setOnClickPendingIntent`로 설정됩니다.

#### DecoratedMediaCustomView

Media 스타일과 커스텀 뷰를 결합합니다.

```kotlin
style = NotificationStyle.DecoratedMediaCustomView(
    customView = NotificationCustomViewStyleData(
        layoutResId = R.layout.notification_media_custom_style_sample,
        bigLayoutResId = R.layout.notification_media_custom_style_sample_expanded
    ),
    compactActionIndices = listOf(0, 1, 2)
)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedMediaCustomView.png" alt="Example_DecoratedMediaCustomView" width="400" />
</p>

`customViewOptions`는 `DecoratedCustomView`와 같이 동작하며, 미디어 버튼은 [Media](#media)와 같이 `actions`에 지정합니다.

---

### 그룹 알림

여러 알림을 하나로 묶습니다.

```kotlin
val GROUP_SAMPLE_KEY = "native.toolkit.grouping.sample"

// 자식 알림 1
val child1 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1101,
        title = "Native Toolkit Group",
        message = "Group child notification #1",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "01"
    )
)

// 자식 알림 2
val child2 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1102,
        title = "Native Toolkit Group",
        message = "Group child notification #2",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "02"
    )
)

// 요약 알림(그룹 헤더)
val summary = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1100,
        title = "Native Toolkit Group Summary",
        message = "2 notifications grouped together",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        isGroupSummary = true,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "00",
        style = NotificationStyle.Inbox(
            lines = listOf("Group child notification #1", "Group child notification #2"),
            summaryText = "2 grouped notifications",
            bigContentTitle = "Grouping / Summary"
        )
    )
)

runCatching {
    listOf(child1, child2, summary).forEach { manager.show(it).getOrThrow() }
}
```

<p align="center">
    <img src="images/android/notification/Example_Group.png" alt="Example_Group" width="400" />
</p>

> **팁:** `groupAlertBehavior = GROUP_ALERT_SUMMARY`를 설정하면 소리와 진동은 요약 알림에서만 울리고, 자식 알림은 조용합니다.

---

### 인터랙션

2.0.0에서는 라이브러리가 본문 탭, 액션 버튼, 닫기를 이벤트로 코드에 전달합니다. 각각의 `AndroidPendingIntentRequest`는 `NotificationEventIntents`가 만듭니다. 이를 `AndroidNotificationPlatformOptions`에 지정하고 `manager.interactions`에서 수신합니다. 자체 `BroadcastReceiver`는 필요하지 않으며, 이 요청들은 예약 알림에서도 동작합니다.

| 함수 | 지정 위치 | `launchApp`의 기본값 |
|---|---|---|
| `NotificationEventIntents.bodyTap(context, notificationId, tag, data, launchApp)` | `contentIntent` | `true` |
| `NotificationEventIntents.action(context, notificationId, tag, actionId, data, launchApp)` | `AndroidNotificationAction.pendingIntent`, `RemoteViewAction.SetClickIntent` | `false` |
| `NotificationEventIntents.dismiss(context, notificationId, tag, data)` | `deleteIntent` | - |
| `NotificationEventIntents.fullScreenLaunch(context, notificationId, tag)` | `fullScreenIntent` | - |

- `data`는 이벤트와 함께 전달되는 문자열 맵입니다.
- `launchApp = true`이면 탭으로 앱도 열립니다. 라이브러리는 자체의 보이지 않는 Activity를 거쳐 이벤트를 알린 뒤, 런처와 같은 방식으로 앱의 시작 Activity를 실행합니다(실행 중인 앱은 앞으로 나옵니다). 알림에서 보낸 브로드캐스트로 Activity를 시작할 수 없는 Android 12 이상에서도 이 방식으로 동작합니다. `false`이면 이벤트는 브로드캐스트로 전달되고 앱은 그대로 있습니다.
- `fullScreenLaunch`는 앱의 시작 Activity를 전체 화면 인텐트로 엽니다. 시작 Activity가 없는 앱에서는 `null`을 반환합니다. 이벤트는 알리지 않습니다.
- 각 요청은 데이터 URI로 구별되고 요청 코드 0을 사용하므로, 두 알림이 같은 `PendingIntent`를 공유하는 일은 없습니다.

#### 이벤트 수신

`manager.interactions`는 `NotificationInteraction`을 전달합니다. `kind`(`BODY_TAP`, `ACTION`, `DISMISS`), `notificationId`, `tag`, `actionId`(`ACTION`일 때), `data`를 가집니다. `manager.shown`은 예약 알림이 실행되었을 때 `NotificationShown`(`notificationId`, `tag`, `channelId`)을 전달합니다.

샘플 앱은 `MainActivity.onCreate`에서 리스너를 등록하고 `onDestroy`에서 제거합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction

class MainActivity : AppCompatActivity() {

    private var eventRegistrations: List<EventHub.Registration> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val notifications = AndroidNotificationManager.getInstance(this)
        // 리스너가 없는 동안 라이브러리가 보관한 이벤트는 이 호출 안에서 전달됩니다.
        eventRegistrations = listOf(
            notifications.interactions.addListener { event, _ ->
                val label = event.data["label"] ?: "Notification"
                when (event.kind) {
                    NotificationInteraction.Kind.BODY_TAP -> { /* event.notificationId, event.tag */ }
                    NotificationInteraction.Kind.ACTION -> { /* event.actionId, label */ }
                    NotificationInteraction.Kind.DISMISS -> { /* "$label dismissed (deleteIntent)" */ }
                }
            },
            notifications.shown.addListener { event, _ ->
                // 예약 알림이 실행되었습니다: event.notificationId, event.tag, event.channelId
            }
        )
    }

    override fun onDestroy() {
        eventRegistrations.forEach { it.remove() }
        eventRegistrations = emptyList()
        super.onDestroy()
    }
}
```

- `interactions`는 리스너가 없는 동안 이벤트를 최대 32개까지 보관하고(가장 오래된 것부터 버립니다), 다음에 추가되는 리스너에게 `addListener` 안에서 도착한 순서대로 전달합니다. 따라서 앱을 시작시킨 탭은 첫 Activity의 `onCreate`에서 추가한 리스너에 도달합니다. `shown`은 아무것도 보관하지 않습니다.
- `addListener`와 `Registration.remove`는 메인 스레드 전용입니다. 리스너는 자신의 `Registration`을 두 번째 인수로 받으며, 그 안에서 자신을 제거할 수 있습니다.
- `NotificationInteraction.toString()`은 `data`의 값을 숨깁니다.

#### 본문 탭 이벤트

```kotlin
val EVENT_SAMPLE_NOTIFICATION_ID = 1120

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = EVENT_SAMPLE_NOTIFICATION_ID,
        title = "Native Toolkit Event",
        message = "Tap this notification to send a body tap event.",
        channel = interactionGroupingSampleChannel,
        subText = "Interaction / Body Tap Event"
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // 앱을 열고 BODY_TAP을 알립니다.
        contentIntent = NotificationEventIntents.bodyTap(
            context = activity,
            notificationId = EVENT_SAMPLE_NOTIFICATION_ID,
            tag = null,
            launchApp = true
        )
    )
)
```

#### 액션 버튼

```kotlin
val ACTION_SAMPLE_NOTIFICATION_ID = 1112

fun buildAcceptDeclineActions(): List<AndroidNotificationAction> {
    fun action(actionId: String, label: String, iconResId: Int) = AndroidNotificationAction(
        title = label,
        pendingIntent = NotificationEventIntents.action(
            context = activity,
            notificationId = ACTION_SAMPLE_NOTIFICATION_ID,
            tag = null,
            actionId = actionId,
            data = mapOf("label" to label),
            launchApp = false
        ),
        iconResId = iconResId
    )
    return listOf(
        action("accept", "Accept", android.R.drawable.ic_menu_call),
        action("decline", "Decline", android.R.drawable.ic_menu_close_clear_cancel)
    )
}

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = ACTION_SAMPLE_NOTIFICATION_ID,
        title = "Native Toolkit Action Sample",
        message = "Use Accept / Decline action buttons",
        channel = interactionGroupingSampleChannel,
        autoCancel = false
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(5130, "native.toolkit.notification.grouping.open"),
        actions = buildAcceptDeclineActions()
    )
)

// interactions 리스너 안에서:
// NotificationInteraction.Kind.ACTION -> "Action button pressed: ${event.data["label"]} (id=${event.actionId})"
```

<p align="center">
    <img src="images/android/notification/Example_ActionButtons.png" alt="Example_ActionButtons" width="400" />
</p>

#### DeleteIntent(닫기 이벤트)

사용자가 알림을 스와이프해서 닫으면 `DISMISS`로 알려집니다.

```kotlin
platformOptions = AndroidNotificationPlatformOptions(
    contentIntent = buildActivityPendingIntentRequest(5110, "native.toolkit.notification.grouping.open"),
    deleteIntent = NotificationEventIntents.dismiss(
        context = activity,
        notificationId = 1110,
        tag = null,
        data = mapOf("label" to "DeleteIntent Sample")
    )
)
```

#### FullScreenIntent(전체 화면 표시)

기기가 잠겨 있거나 화면이 꺼져 있을 때 전체 화면 Activity를 실행합니다(알람, 수신 전화 등). 샘플 앱은 자체 Activity를 엽니다.

```kotlin
// 높은 우선순위의 채널과 적절한 category가 필요합니다
val fullScreenSampleChannel = NotificationChannel(
    id = "native_toolkit_fullscreen_sample",
    name = "Native Toolkit FullScreen Sample",
    importance = NotificationManager.IMPORTANCE_HIGH,
    description = "Reference fullScreenIntent notification sample channel"
)

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1111,
        title = "Native Toolkit Alarm Sample",
        message = "Reference fullScreenIntent notification sample",
        channel = fullScreenSampleChannel,
        category = NotificationCompat.CATEGORY_ALARM,
        priority = NotificationCompat.PRIORITY_HIGH
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(5120, "native.toolkit.notification.grouping.open"),
        fullScreenIntent = buildActivityPendingIntentRequest(
            targetActivityClass = NotificationFullScreenSampleActivity::class.java,
            requestCode = 5121,
            action = "native.toolkit.notification.fullscreen.open"
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_FullScreenIntent.png" alt="Example_FullScreenIntent" width="400" />
</p>

대신 앱의 시작 Activity를 열려면 `NotificationEventIntents.fullScreenLaunch(activity, 1111, null)`을 전달합니다.

> **참고:** 기기 상태와 Android 정책에 따라 전체 화면이 아니라 헤드업 알림으로 표시될 수 있습니다.

---

### 진행 상황 알림

다운로드나 오래 걸리는 작업의 진행 상황을 진행률 표시줄로 표시합니다. 같은 `id`로 다시 표시하면 표시줄이 업데이트됩니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationProgress

fun buildProgressCommand(progressValue: Int, max: Int = 100): AndroidNotificationCommand {
    val safeProgress = progressValue.coerceIn(0, max)
    val isComplete = safeProgress >= max
    return AndroidNotificationCommand(
        content = NotificationContent(
            id = 1009,
            title = "Native Toolkit Download",
            message = if (isComplete) "Download completed" else "Downloading sample asset... $safeProgress%",
            channel = sampleChannel,
            subText = "Progress",
            ongoing = !isComplete,
            autoCancel = isComplete,
            progress = NotificationProgress(max = max, current = safeProgress, indeterminate = false)
        )
    )
}

manager.show(buildProgressCommand(progressValue = 50))

// 불확정 진행률 표시줄(max와 current는 무시됩니다)
val indeterminate = NotificationProgress(max = 0, current = 0, indeterminate = true)
```

<p align="center">
    <img src="images/android/notification/Example_Progress.png" alt="Example_Progress" width="400" />
</p>

---

### 포어그라운드 서비스 알림

아래 두 서비스는 AAR이 선언합니다. 매니페스트에 추가할 것은 없습니다.

#### Progress FGS(장시간 백그라운드 처리)

매니저는 `dataSync` 포어그라운드 서비스에 연결된 진행 상황 알림을 표시합니다. 이 호출들은 아무것도 반환하지 않으며, Android가 서비스의 시작이나 연결을 거부하면(예: 백그라운드에서 시작한 경우) 예외를 던지므로 `runCatching` 등으로 감싸 주십시오.

```kotlin
val progressForegroundSampleChannel = NotificationChannel(
    id = "native_toolkit_progress_fgs",
    name = "Native Toolkit Progress FGS",
    importance = NotificationManager.IMPORTANCE_LOW,
    description = "Foreground service progress sample channel"
)

// 포어그라운드 서비스 시작(알림 표시도 겸함)
runCatching { manager.startProgress(buildProgressForegroundCommand(progressValue = 10)) }
    .onFailure { throwable -> statusText = "Failed to start progress foreground service: ${throwable.message}" }

// 진행 상황 업데이트
runCatching { manager.updateProgress(buildProgressForegroundCommand(progressValue = 50)) }

// 완료(서비스를 중지하고 일반 알림을 남김)
runCatching { manager.completeProgress(buildProgressForegroundCompleteCommand()) }

// 강제 중지(알림도 삭제)
runCatching { manager.stopProgress() }
```

`buildProgressForegroundCommand`는 위의 `buildProgressCommand`와 같은 커맨드를 `id = 1011`, `channel = progressForegroundSampleChannel`, `ongoing = true`, `autoCancel = false`로 만듭니다. `buildProgressForegroundCompleteCommand`는 같은 `id`에 `ongoing = false`, `autoCancel = true`, `BigText` 스타일을 사용합니다.

<p align="center">
    <img src="images/android/notification/Example_ProgressForeground.png" alt="Example_ProgressForeground" width="400" />
</p>

#### Call Style FGS(통화 알림)

`CallStyleForegroundService`는 `specialUse` 포어그라운드 서비스에서 `CallStyle` 알림(수신, 통화 중, 스크리닝)을 표시합니다. 표시하는 것은 `CallStyleNotificationFactory`의 고정된 샘플 통화로, 시연용입니다. 실제 통화 앱은 `phoneCall` 포어그라운드 서비스를 사용하며, Android가 통화 앱에 요구하는 요건을 충족해야 합니다.

```kotlin
import androidx.core.content.ContextCompat
import com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleForegroundService
import com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleNotificationFactory

// 통화 알림이 사용하는 채널
manager.createChannel(CallStyleNotificationFactory.createChannel())

// 수신 전화 알림 시작
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createIncomingStartIntent(activity))

// 통화 중 알림으로 전환
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createOngoingStartIntent(activity))

// 스크리닝 알림으로 전환
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createScreeningStartIntent(activity))

// 중지
activity.startService(CallStyleForegroundService.createStopIntent(activity))
```

<p align="center">
    <img src="images/android/notification/Example_CallStyle.png" alt="Example_CallStyle" width="400" />
</p>

자체 통화 알림을 게시하려면 `style = NotificationStyle.Call(callType, person, isVideo, verificationText)`를 설정하고 버튼을 `callStyleOptions`에 지정합니다. `INCOMING`에는 `answerIntent`와 `declineIntent`, `ONGOING`에는 `hangUpIntent`, `SCREENING`에는 `hangUpIntent`와 `answerIntent`입니다.

---

### 예약 알림

지정한 시각에 알림을 표시합니다.

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule

manager.createChannel(scheduleSampleChannel)
if (!manager.hasPermission() || !manager.areNotificationsEnabled()) {
    statusText = "Unable to schedule notifications. Check permissions or notification settings."
} else if (!manager.canScheduleExactAlarms()) {
    statusText = "Exact alarms are not allowed. Use 'Open Exact Alarm Settings' above to enable them."
} else {
    val triggerAt = System.currentTimeMillis() + 15_000L // 지금부터 15초 후
    manager.schedule(
        buildScheduledCommand(),
        NotificationSchedule(triggerAtMillis = triggerAt)
    ).onSuccess {
        val command = buildScheduledCommand()
        val scheduled = manager.isScheduled(command.content.id, command.content.tag)
        statusText = "Scheduled a high-priority notification for 15 seconds later. (isScheduled=$scheduled)"
    }.onFailure { throwable ->
        statusText = "Failed to schedule notification: ${throwable.message ?: throwable::class.java.simpleName}"
    }
}
```

<p align="center">
    <img src="images/android/notification/Example_Scheduled.png" alt="Example_Scheduled" width="400" />
</p>

| `NotificationSchedule` 속성 | 기본값 | 의미 |
|---|---|---|
| `triggerAtMillis` | - | Unix 시간(밀리초). 0보다 커야 합니다(그렇지 않으면 `IllegalArgumentException`) |
| `exact` | `true` | 정확한 알람. 정확한 알람 권한이 없으면 라이브러리는 오류 없이 부정확한 알람을 대신 사용합니다 |
| `allowWhileIdle` | `true` | Doze 모드에서도 실행됩니다 |
| `persistAcrossBoot` | `true` | 저장되며, 재부팅이나 앱 업데이트 후 복원됩니다 |
| `alarmType` | `0`(`AlarmManager.RTC_WAKEUP`) | `AlarmManager`의 알람 유형 |

- 이미 지난 시각을 지정하면 알람 없이 바로 알림을 표시합니다. 이 경우 `manager.shown`은 알려지지 않습니다.
- `manager.shown`은 알람이 실행될 때 알려집니다. 권한은 그 시점에 확인합니다. 권한이 없으면 아무것도 표시되지 않지만 `manager.shown`은 알려집니다.
- 저장된 예약은 커맨드를 JSON으로 앱의 파일(`files/ntk/notification_schedules.json`. 자동 백업에 포함됩니다)에 보관합니다. 그 안의 `Intent`(예: `contentIntent` 안의 것)는 URI로 저장됩니다. 따라서 재부팅, 앱 재설치, 기기 이전 후 예약이 복원되면 문자열이나 기본형 값이 아닌 extras(`Parcelable`, 배열, `Bundle`, `Uri` 등)와 `ClipData`는 사라져 있습니다.

#### 예약 취소

```kotlin
// 예약 하나를 취소하고, 이미 실행되었을 경우에 대비해 알림도 삭제합니다.
manager.cancelScheduled(command.content.id, command.content.tag)
    .mapCatching { manager.cancel(command.content.id, command.content.tag).getOrThrow() }

// 저장된 모든 예약 취소
manager.cancelAllScheduled()
```

`cancelAllScheduled`가 취소하는 것은 저장된 예약(`persistAcrossBoot = true`)뿐입니다. 나머지는 ID로 취소해 주십시오.

#### 예약 여부 확인

```kotlin
val isScheduled: Boolean = manager.isScheduled(command.content.id, command.content.tag)
```

`isScheduled`가 보는 것은 저장된 예약(`persistAcrossBoot = true`)뿐입니다.

#### 기기 재부팅 후 복원

라이브러리는 재부팅 후(`BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`)와 앱 업데이트 후(`MY_PACKAGE_REPLACED`)에 저장된 예약을 스스로 복원합니다. 리시버는 AAR에 포함되어 있습니다. 다른 시점에 같은 일을 하려면 다음을 호출합니다.

```kotlin
manager.restoreScheduled()
```

#### 1.x가 저장한 예약

2.0.0은 예약을 새 형식으로 저장하며, 1.x가 저장한 것은 읽을 수 없습니다. 앱이 처음 2.0.0으로 실행될 때 라이브러리는 1.x가 저장한 예약의 알람을 취소하고 그 예약을 한 번 삭제합니다. 업데이트 후에 다시 예약해 주십시오. `persistAcrossBoot = false`로 만든 1.x의 예약은 찾을 수 없어서 Android에 남지만, 실행되어도 아무것도 표시하지 않습니다.

1.x가 표시했고 업데이트 후에도 화면에 남아 있는 알림은 탭에도 액션 버튼에도 반응하지 않습니다. 가리키는 리시버의 클래스 이름이 바뀌었기 때문입니다. 아직 필요하다면 2.0.0으로 다시 표시해 주십시오.

---

### C ABI

- C에서, 그리고 C 라이브러리를 호출할 수 있는 언어(C#, Rust, Dart, Go 등)에서 같은 알림을 사용하기 위한 API입니다. 함수는 `android-native-toolkit-capi-2.0.0.aar`의 `libntk.so`에 있으며, 앱에는 `android-native-toolkit-2.0.0.aar`도 필요합니다. 요건을 포함한 설정은 매뉴얼 상단의 [C ABI](index.ko.md#c-abi)에 있습니다.
- `libntk.so`는 64비트 ABI(`arm64-v8a`, `x86_64`)에만 있습니다. 32비트로 설치된 앱에서는 로드에 실패하지만 앱은 계속 실행됩니다.
- CMake를 사용하는 C와 C++는 Prefab을 통해 헤더와 라이브러리를 얻습니다. APK와 CMake 빌드를 모두 64비트 ABI로 제한해 주십시오. Android Gradle Plugin은 CMake가 빌드하는 모든 ABI에 대해 Prefab 패키지를 확인하며, 32비트 ABI에서는 `CXX1210`으로 멈춥니다(매뉴얼 상단의 [C ABI](index.ko.md#c-abi) 참조).

```kotlin
android {
    buildFeatures { prefab = true }
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
}
```

```cmake
find_package(ntk REQUIRED CONFIG)
target_link_libraries(your_library PRIVATE ntk::ntk)
```

- **스레드.** 모든 함수는 어느 스레드에서든 호출할 수 있으며, 메인 스레드를 기다리는 함수는 없습니다. 완료, 이벤트, 받아들여진 등록의 `release`는 Android 메인 스레드에서 호출되며, 그것을 등록한 호출 안에서 호출되는 일은 없습니다. 메인 스레드에서 호출하면 완료는 함수가 반환된 뒤에 옵니다. 다른 스레드에서 호출하면 함수가 반환되기 전에 올 수 있으므로 완료는 `user_data`로 대응시켜 주십시오.
- **`release`.** 등록은 `user_data`와 `release` 콜백을 동반하며, `release`는 정확히 한 번 호출됩니다. 입구에서 거부된 호출(잘못된 인수, 미초기화)은 오류를 반환하고 완료를 호출하지 않으며, 반환하기 전에 호출한 스레드에서 `release`를 호출합니다. 프로세스가 종료되면 완료도 `release`도 호출되지 않습니다.
- **핸들.** 내용과 채널 빌더는 라이브러리의 기본값에서 시작하고, 세터가 받은 것을 복사합니다. 초기화 전에도 사용할 수 있으며 스레드 안전하지 않습니다. `ntk_notification_content_free`와 `ntk_notification_channel_free`로 해제합니다. 콜백에 전달되는 이벤트 핸들은 받는 쪽의 것입니다. 콜백이 반환된 뒤에도 받는 쪽이 해제할 때까지 유효합니다.
- **요청 ID**는 `uint64_t`이며 재사용되지 않습니다. 완료 후나 알 수 없는 ID로 취소하면 아무 일도 하지 않습니다.
- **초기화.** App Startup이 앱 시작 시 C ABI를 초기화합니다. App Startup을 비활성화한 앱이나 기본 프로세스가 아닌 프로세스에서 호출하는 앱은 먼저 `ntk_android_init`을 호출합니다. 초기화 전에는 작업이 `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED`를 반환합니다(인수 오류가 먼저 보고되며, 취소는 `NONE`을 반환합니다).
- **포어그라운드.** `ntk_notification_request_permission`(권한이 아직 허용되지 않은 경우)과 `ntk_notification_open_settings_async`는 앱이 포어그라운드에 있어야 합니다. 백그라운드에서 호출하면 받아들여진 뒤 `NTK_NOTIFICATION_ERROR_NOT_FOREGROUND`로 완료됩니다. 반환값이 알려 주는 것은 요청이 받아들여졌는지뿐입니다.
- **콜백은 예외를 던지면 안 됩니다.** 콜백 밖으로 나가는 C++ 예외, C# 예외, Rust의 panic은 프로세스를 종료시킵니다.
- **조용한 보정은 없습니다.** Kotlin API가 값을 조정하는 곳에서 C ABI는 `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER`를 반환합니다. 채널 중요도는 0~4, 잠금 화면 표시와 `visibility`는 -1~1, `priority`는 -2~2, `group_alert_behavior`는 0~2, 타임스탬프와 타임아웃은 0 이상, 확정 진행률 표시줄은 `0 <= current <= max`, `alarm_type`은 0(`RTC_WAKEUP`) 또는 1(`RTC`)입니다. 문자열은 NUL로 끝나는 UTF-8이며, 세터에 `NULL`을 전달하면 그 항목은 기본값으로 돌아갑니다.
- **권한 확인.** Kotlin API가 아무것도 하지 않고 성공하는 곳에서 C ABI는 호출 시점에 먼저 확인합니다. `show`, `update`, 시각이 지난 예약은 권한이 없거나 알림이 꺼져 있으면 `PERMISSION_DENIED`를 반환하고, 미래 시각에 대한 정확한 예약은 정확한 알람 권한이 없으면 `EXACT_ALARM_NOT_ALLOWED`를 반환합니다. 확인 이후의 변화는 잡지 못합니다. 확인과 호출 사이에 알림이 꺼진 경우나, 몇 밀리초 뒤로 잡은 예약이 만들어질 때 이미 지나 있는 경우에는 `NONE`을 반환하고 아무것도 표시하지 않을 수 있습니다.
- **리소스 이름.** 아이콘, BigPicture 이미지, 레이아웃, 뷰 ID는 이름으로 지정하며, 내용이 `ntk_notification_show`, `_update`, `_schedule`, 진행 상황 함수에 전달될 때 찾습니다(아이콘과 이미지는 `drawable`, 다음으로 `mipmap`, 레이아웃은 `layout`, 뷰 ID는 `id`로). 찾지 못한 이름이 있으면 그 함수는 `RESOURCE_NOT_FOUND`를 반환합니다. 세터는 이름을 찾지 않습니다. 리소스 축소는 이름으로만 참조되는 리소스를 제거하므로, 예를 들어 `res/raw/keep.xml`에서 유지해 주십시오.

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification,@layout/notification_custom_style_sample" />
```

#### 초기화, 권한, 설정

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Notification.h>

/* App Startup을 비활성화한 앱이나 다른 프로세스에서 호출하는 앱만 사용합니다. env는
   호출한 스레드의 JNIEnv*, context는 아무 Context입니다. Activity가 있으면 Activity를 전달합니다. */
static void initialize_without_startup(void* env, void* context)
{
    ntk_android_error result = ntk_android_init(env, context);
    if (result == NTK_ANDROID_ERROR_IN_PROGRESS || result == NTK_ANDROID_ERROR_JNI_FAILURE) {
        /* 기다리지 않습니다. 나중에 다시 호출합니다. CLASS_NOT_FOUND는 재시도해도 해결되지 않습니다. */
    }
}

static void NTK_CALL on_permission(void* user_data, uint64_t request_id, ntk_notification_error error,
                                   uint32_t system_code, ntk_notification_permission_result result)
{
    /* Android 메인 스레드에서, 받아들여진 요청마다 한 번 호출됩니다. system_code는 항상 0입니다. */
    (void)user_data; (void)request_id; (void)system_code;
    if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_PERMISSION_RESULT_GRANTED) {
        /* 허용됨, 이미 허용되어 있었음, 또는 필요 없음(Android 12L 이하). */
    } else if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_PERMISSION_RESULT_DENIED) {
        /* 거부됨. */
    } else if (error == NTK_NOTIFICATION_ERROR_NOT_FOREGROUND) {
        /* 앱이 백그라운드에 있는 동안 요청함. */
    } else if (error == NTK_NOTIFICATION_ERROR_CANCELED || error == NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM) {
        /* 호출한 쪽이 취소했거나, 대화상자를 표시하던 Activity가 소멸됨. */
    }
}

static void NTK_CALL on_settings(void* user_data, ntk_notification_error error, uint32_t system_code,
                                 ntk_notification_settings_result result)
{
    (void)user_data; (void)system_code;
    if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_SETTINGS_RESULT_OPENED_FALLBACK) {
        /* 요청한 화면을 사용할 수 없어서 앱 정보 화면이 열림. */
    } else if (error == NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED) {
        /* 어떤 화면도 열 수 없었음. */
    }
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* 등록한 호출이 실패했을 때를 포함해, 등록마다 정확히 한 번 호출됩니다. */
    (void)user_data;
}

/* 헤더의 버전과 라이브러리의 버전. */
if (ntk_version() != NTK_VERSION) {
    return;
}
if (!ntk_android_is_initialized()) {
    return;   /* App Startup이 아직 실행되지 않았거나 initialize_without_startup이 필요합니다. */
}

/* 권한 상태. */
int32_t granted = 0;
int32_t enabled = 0;
int32_t exact_alarms = 0;
ntk_notification_error error = ntk_notification_has_permission(&granted);
error = ntk_notification_are_enabled(&enabled);
error = ntk_notification_can_schedule_exact_alarms(&exact_alarms);
uint32_t system_code = ntk_last_system_code();   /* Android에서는 항상 0 */

/* 권한 요청. */
uint64_t request_id = 0;
error = ntk_notification_request_permission(&on_permission, NULL, &release_user_data, &request_id);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    /* 입구에서 거부됨. on_permission은 호출되지 않으며 release_user_data는 이미 호출됨. */
}

/* 결과가 더 이상 필요 없는 경우. 아직 완료되지 않았으면 요청은 CANCELED로 완료됩니다. */
error = ntk_notification_cancel_permission_request(request_id);

/* 설정 화면: NOTIFICATIONS, APP_DETAILS, EXACT_ALARM 중 하나. */
error = ntk_notification_open_settings_async(NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM,
                                             &on_settings, NULL, &release_user_data);
```

#### 채널과 내용 빌더

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* 채널: id, 이름, 중요도(0~4. 3은 IMPORTANCE_DEFAULT). */
ntk_notification_channel* channel = NULL;
if (ntk_notification_channel_create("native_toolkit_sample", "Native Toolkit Sample", 3, &channel)
        != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}
ntk_notification_channel_set_description(channel, "Notification sample channel");
ntk_notification_channel_set_show_badge(channel, 1);
ntk_notification_channel_set_enable_lights(channel, 1);
ntk_notification_channel_set_light_color(channel, 0xFF2196F3u);   /* ARGB */
ntk_notification_channel_set_enable_vibration(channel, 1);
const int64_t pattern[] = { 0, 200, 100, 200 };                    /* 밀리초 */
ntk_notification_channel_set_vibration_pattern(channel, pattern, 4);
ntk_notification_channel_set_sound(channel, NULL);                 /* NULL: 기본 소리 */
ntk_notification_channel_set_lockscreen_visibility(channel, 1);   /* -1~1 */
ntk_notification_channel_set_group(channel, "samples", "Samples");
ntk_notification_error error = ntk_notification_create_channel(channel);

/* 내용: id, 제목, 메시지는 필수입니다. */
ntk_notification_content* content = NULL;
error = ntk_notification_content_create(1001, "Native Toolkit", "Default style notification sample", &content);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    ntk_notification_channel_free(channel);
    return;
}
ntk_notification_content_set_channel(content, channel);           /* 복사됩니다 */
ntk_notification_channel_free(channel);

/* 문구와 식별자. 모두 UTF-8이며, NULL은 항목을 기본값으로 되돌립니다. */
ntk_notification_content_set_tag(content, NULL);
ntk_notification_content_set_sub_text(content, "Default");
ntk_notification_content_set_ticker(content, "Native Toolkit");
ntk_notification_content_set_category(content, "status");
ntk_notification_content_set_sound(content, NULL);

/* 아이콘은 리소스 이름으로 지정하며, show, update, schedule, 진행 상황 함수가 찾습니다.
   작은 아이콘이 없으면 앱 아이콘을 사용합니다. */
ntk_notification_content_set_small_icon(content, "ic_notification");
ntk_notification_content_set_large_icon(content, "ic_launcher_round");

/* 숫자. priority는 -2~2, visibility는 -1~1. */
ntk_notification_content_set_priority(content, 0);
ntk_notification_content_set_visibility(content, 1);
ntk_notification_content_set_color(content, 0xFF2196F3u);
ntk_notification_content_set_number(content, 1);
ntk_notification_content_set_timestamp(content, 1760054400000);   /* Unix 밀리초 */
ntk_notification_content_set_timeout_after(content, 600000);      /* 10분 후 삭제 */

/* 플래그. */
ntk_notification_content_set_auto_cancel(content, 1);
ntk_notification_content_set_ongoing(content, 0);
ntk_notification_content_set_show_timestamp(content, 1);
ntk_notification_content_set_only_alert_once(content, 0);
ntk_notification_content_set_local_only(content, 0);
ntk_notification_content_set_silent(content, 0);
ntk_notification_content_set_uses_chronometer(content, 0);

/* 그룹: 키, 요약인지 여부, 어느 알림이 울리는지(0~2), 정렬 순서. */
ntk_notification_content_set_group(content, "native.toolkit.grouping.sample");
ntk_notification_content_set_group_summary(content, 0);
ntk_notification_content_set_group_alert_behavior(content, 1);    /* GROUP_ALERT_SUMMARY */
ntk_notification_content_set_sort_key(content, "01");

/* 진행률 표시줄: max, current, indeterminate. */
ntk_notification_content_set_progress(content, 100, 50, 0);

/* 표시, 교체, 삭제. */
error = ntk_notification_show(content);
if (error == NTK_NOTIFICATION_ERROR_PERMISSION_DENIED) {
    /* 권한이 없거나 앱의 알림이 꺼져 있음. */
} else if (error == NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND) {
    /* 아이콘, 이미지, 레이아웃, 뷰 중 어떤 이름을 찾지 못함. */
}
error = ntk_notification_update(content);
ntk_notification_content_free(content);

error = ntk_notification_remove(1001, NULL);   /* 태그 또는 NULL */
error = ntk_notification_remove_all();
error = ntk_notification_delete_channel("native_toolkit_sample");
```

#### 스타일, 탭, 액션

마지막으로 설정한 스타일이 적용됩니다. `add_message`와 `add_view_click`은 각각의 스타일을 먼저 설정해야 합니다.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
ntk_notification_error error = ntk_notification_content_create(1002, "Native Toolkit",
                                                               "BigText style notification sample", &content);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* BigText: big_text는 필수입니다. */
ntk_notification_content_set_style_big_text(content,
    "This is a BigText notification sample from Native Toolkit Example.", "BigText", "BigText Style");

/* Inbox. */
const char* const lines[] = { "Permission status checked", "Channel created successfully" };
ntk_notification_content_set_style_inbox(content, lines, 2, "2 sample events", "Inbox Style");

/* BigPicture: 이미지 이름 또는 URI(이름이 우선), 다음으로 펼친 보기의 큰 아이콘. */
ntk_notification_content_set_style_big_picture(content, "ic_launcher", NULL, "Launcher image preview",
                                               "BigPicture Style", "ic_launcher_round", 0);

/* Messaging: group_conversation이 -1이면 설정하지 않은 상태로 둡니다. 보낸 사람이 NULL이면 기기의 사용자입니다. */
ntk_notification_content_set_style_messaging(content, "You", "Native Toolkit Example", 1);
ntk_notification_content_add_message(content, "Can you verify the notification styles?", 1760054280000, "Alex");
ntk_notification_content_add_message(content, "Confirmed. This is the Messaging sample.", 1760054400000, NULL);

/* DecoratedCustomView: 레이아웃 이름, 다음으로 ACTION 이벤트로 전달되는 클릭. */
ntk_notification_content_set_style_custom_view(content, "notification_custom_style_sample",
                                               "notification_custom_style_sample_expanded");
ntk_notification_content_add_view_click(content, "notification_btn_dismiss", "custom_view_dismiss");

/* 본문 탭: OPEN_APP(기본값)은 앱을 열고 BODY_TAP을 보내며,
   EVENT_ONLY는 BODY_TAP만 보내고, NONE은 아무것도 하지 않습니다. */
ntk_notification_content_set_tap(content, NTK_NOTIFICATION_TAP_OPEN_APP);

/* 이 알림의 모든 이벤트(탭, 액션, 클릭, 닫기)와 함께 전달되는 문자열. */
ntk_notification_content_add_data(content, "label", "Sample");

/* DISMISS 이벤트는 기본으로 보내집니다. 0으로 끕니다. */
ntk_notification_content_set_dismiss_event(content, 1);

/* 앱의 시작 Activity를 여는 전체 화면 인텐트. */
ntk_notification_content_set_full_screen(content, 0);

/* 액션 버튼. */
ntk_notification_action accept;
memset(&accept, 0, sizeof(accept));
accept.struct_size = (uint32_t)sizeof(accept);
accept.title = "Accept";
accept.action_id = "accept";        /* ACTION 이벤트로 전달됩니다 */
accept.icon_name = NULL;            /* 또는 drawable / mipmap 이름 */
accept.launch_app = 0;              /* 0이 아니면 앱도 엽니다 */
error = ntk_notification_content_add_action(content, &accept);

error = ntk_notification_show(content);
ntk_notification_content_free(content);
```

#### 예약과 진행 상황

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
if (ntk_notification_content_create(1010, "Native Toolkit", "Scheduled notification sample", &content)
        != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* 0으로 채우고 trigger_at_millis를 설정하면: 정확, Doze 중에도 실행, 재부팅 후에도 유지, RTC_WAKEUP. */
const int64_t now_unix_ms = 1760054400000;   /* 현재 시각. 앱의 시계에서 가져옵니다 */
ntk_notification_schedule_options schedule;
memset(&schedule, 0, sizeof(schedule));
schedule.struct_size = (uint32_t)sizeof(schedule);
schedule.trigger_at_millis = now_unix_ms + 15000;

/* 저장된 예약을 호출한 스레드에서 씁니다. */
ntk_notification_error error = ntk_notification_schedule(content, &schedule);
if (error == NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED) {
    /* NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM으로 사용자에게 요청하거나 inexact를 설정합니다. */
} else if (error == NTK_NOTIFICATION_ERROR_STORAGE_FAILED) {
    /* 예약을 저장하지 못함. */
}
ntk_notification_content_free(content);

/* Kotlin API와 마찬가지로 저장된 예약(not_persist_across_boot == 0)만 대상입니다. */
int32_t scheduled = 0;
error = ntk_notification_is_scheduled(1010, NULL, &scheduled);
error = ntk_notification_cancel_scheduled(1010, NULL);
error = ntk_notification_cancel_all_scheduled();

/* 포어그라운드 서비스의 진행 상황 알림. ongoing, auto cancel, alert once는 라이브러리가
   설정합니다. 진행률 표시줄이 없는 내용은 INVALID_PARAMETER입니다. */
ntk_notification_content* progress = NULL;
if (ntk_notification_content_create(1011, "Native Toolkit Background Sync", "Running background sync... 10%",
                                    &progress) != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}
ntk_notification_content_set_progress(progress, 100, 10, 0);
error = ntk_notification_start_progress(progress);
if (error == NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED) {
    /* Android가 서비스 시작을 거부함(예: 백그라운드에서). */
}
ntk_notification_content_set_progress(progress, 100, 50, 0);
error = ntk_notification_update_progress(progress);
error = ntk_notification_complete_progress(progress);   /* 표시줄이 가득 차고 일반 알림이 남습니다 */
ntk_notification_content_free(progress);

error = ntk_notification_stop_progress();               /* 중지하고 알림을 삭제합니다 */
```

진행 상황 함수가 알려 주는 것은 요청이 서비스에 도달했는지입니다. 포어그라운드 서비스 권한이 없는 것처럼 서비스 안에서 일어난 실패는 logcat에만 나타납니다.

#### 인터랙션과 표시 이벤트

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

static void NTK_CALL on_interaction(void* user_data, ntk_notification_interaction* event)
{
    /* Android 메인 스레드에서 호출됩니다. 이벤트는 받은 쪽의 것입니다. 지금이든 나중이든 해제합니다. */
    ntk_notification_event_kind kind = ntk_notification_interaction_kind(event);
    int32_t id = ntk_notification_interaction_notification_id(event);
    const char* tag = ntk_notification_interaction_tag(event, NULL);              /* NULL: 태그 없음 */
    const char* action_id = ntk_notification_interaction_action_id(event, NULL);  /* ACTION일 때만 */
    size_t count = ntk_notification_interaction_data_count(event);
    size_t i;
    for (i = 0; i < count; ++i) {
        const char* key = ntk_notification_interaction_data_key_at(event, i, NULL);
        const char* value = ntk_notification_interaction_data_value_at(event, i, NULL);
        (void)key; (void)value;
    }
    if (kind == NTK_NOTIFICATION_EVENT_KIND_BODY_TAP) {
        /* 본문이 탭됨. */
    } else if (kind == NTK_NOTIFICATION_EVENT_KIND_ACTION) {
        /* 버튼 또는 커스텀 뷰 클릭: action_id. */
    } else if (kind == NTK_NOTIFICATION_EVENT_KIND_DISMISS) {
        /* 스와이프로 닫힘. */
    }
    (void)user_data; (void)id; (void)tag; (void)action_id;
    ntk_notification_interaction_free(event);
}

static void NTK_CALL on_shown(void* user_data, ntk_notification_shown* event)
{
    /* 예약 알림이 실행됨. */
    int32_t id = ntk_notification_shown_notification_id(event);
    const char* tag = ntk_notification_shown_tag(event, NULL);
    const char* channel_id = ntk_notification_shown_channel_id(event, NULL);
    (void)user_data; (void)id; (void)tag; (void)channel_id;
    ntk_notification_shown_free(event);
}

static void NTK_CALL release_user_data(void* user_data)
{
    (void)user_data;
}

/* 리스너가 없는 동안 온 탭, 액션, 닫기(최대 32개)는 처음 추가된 리스너에
   전달됩니다. 표시 이벤트는 보관되지 않습니다. */
ntk_notification_listener* interactions = NULL;
ntk_notification_error error = ntk_notification_add_interaction_listener(&on_interaction, NULL,
                                                                         &release_user_data, &interactions);
ntk_notification_listener* shown = NULL;
error = ntk_notification_add_shown_listener(&on_shown, NULL, &release_user_data, &shown);

/* 메인 스레드에서 호출하면 이것이 반환된 뒤 콜백에 도달하는 이벤트는 없습니다. 다른
   스레드에서 호출하면 release_user_data가 호출될 때까지 이벤트가 올 수 있습니다. 이후
   핸들은 무효입니다. 라이브러리가 스스로 리스너를 제거하는 일은 없습니다. */
ntk_notification_listener_remove(interactions);
ntk_notification_listener_remove(shown);
```

#### 알림 오류

`ntk_notification_error`입니다. 값 0~5는 Android C ABI의 모든 기능에서 같은 의미입니다.

| 값 | 이름 | 조건 |
|---|---|---|
| 0 | `NTK_NOTIFICATION_ERROR_NONE` | 성공 |
| 1 | `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER` | 잘못된 인수: `NULL`, 잘못된 UTF-8, 범위를 벗어난 값, 잘못된 `struct_size` |
| 2 | `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` | 초기화 전에 호출됨 |
| 3 | `NTK_NOTIFICATION_ERROR_NOT_SUPPORTED` | 이 버전이 모르는 부분에 구조체가 0이 아닌 값을 가지고 있음 |
| 4 | `NTK_NOTIFICATION_ERROR_UNKNOWN` | 그 밖의 실패 |
| 5 | `NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY` | 메모리가 부족함 |
| 6 | `NTK_NOTIFICATION_ERROR_CANCELED` | 권한 요청이 `ntk_notification_cancel_permission_request`로 취소됨 |
| 7 | `NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM` | 권한 대화상자를 표시하던 Activity가 소멸됨 |
| 8 | `NTK_NOTIFICATION_ERROR_NOT_FOREGROUND` | 권한 요청이나 설정 화면을 백그라운드에서 요청함 |
| 9 | `NTK_NOTIFICATION_ERROR_HOST_START_FAILED` | 라이브러리가 투명한 호스트 Activity를 시작하지 못함 |
| 10 | `NTK_NOTIFICATION_ERROR_PERMISSION_DENIED` | 권한이 없거나 알림이 꺼진 상태에서의 `show`, `update`, 지난 시각의 `schedule` |
| 11 | `NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED` | 정확한 알람 권한이 없는 상태에서 미래 시각에 대한 정확한 `schedule` |
| 12 | `NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND` | 아이콘, 이미지, 레이아웃, 뷰 중 어떤 이름을 찾지 못함 |
| 13 | `NTK_NOTIFICATION_ERROR_STORAGE_FAILED` | 저장된 예약을 쓰지 못함 |
| 14 | `NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED` | Android가 진행 상황 포어그라운드 서비스의 시작이나 연결을 거부함 |
| 15 | `NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED` | 어떤 설정 화면도 열 수 없었음 |

`ntk_android_init`은 `ntk_android_error`를 반환합니다. `NONE`(0), `INVALID_PARAMETER`(1, `env` 또는 `context`가 `NULL`), `CLASS_NOT_FOUND`(2, AAR의 클래스가 없거나 R8이 이름을 바꿈. 재시도해도 해결되지 않습니다), `JNI_FAILURE`(3, 일시적. 나중에 다시 호출합니다. 자세한 내용은 logcat 태그 `ntk`에 있습니다), `IN_PROGRESS`(4, 다른 스레드가 초기화 중. 나중에 다시 호출합니다)입니다.

| Kotlin API | C ABI |
|---|---|
| `AndroidNotificationManager.getInstance` | -(함수는 매니저가 필요 없습니다) |
| `LibraryRuntime.ensureInitialized` | `ntk_android_init` / `ntk_android_is_initialized` |
| `NotificationChannel` | `ntk_notification_channel_create`와 9개의 세터 |
| `AndroidNotificationCommand` | `ntk_notification_content_create`와 그 세터 |
| `NotificationEventIntents` | `ntk_notification_content_set_tap` / `_add_action` / `_add_view_click` / `_set_dismiss_event` / `_set_full_screen` / `_add_data` |
| `show` / `update` | `ntk_notification_show` / `ntk_notification_update` |
| `cancel` / `cancelAll` | `ntk_notification_remove` / `ntk_notification_remove_all` |
| `createChannel` / `deleteChannel` | `ntk_notification_create_channel` / `ntk_notification_delete_channel` |
| `schedule` / `cancelScheduled` / `cancelAllScheduled` / `isScheduled` | `ntk_notification_schedule` / `_cancel_scheduled` / `_cancel_all_scheduled` / `_is_scheduled` |
| `startProgress` / `updateProgress` / `completeProgress` / `stopProgress` | `ntk_notification_start_progress` / `_update_progress` / `_complete_progress` / `_stop_progress` |
| `hasPermission` / `areNotificationsEnabled` / `canScheduleExactAlarms` | `ntk_notification_has_permission` / `_are_enabled` / `_can_schedule_exact_alarms` |
| `requestPermission` / `cancelPermissionRequest` | `ntk_notification_request_permission` / `ntk_notification_cancel_permission_request` |
| `openSettings` | `ntk_notification_open_settings_async`(포어그라운드 Activity에서) |
| `interactions` / `shown` | `ntk_notification_add_interaction_listener` / `ntk_notification_add_shown_listener` |
| `EventHub.Registration.remove` | `ntk_notification_listener_remove` |

C ABI에 없는 것: `createChannels`, `getActive`, `restoreScheduled`, Media·DecoratedMediaCustomView·Call 스타일, `largeIconBitmap`, 자체 `PendingIntent`, 통화 포어그라운드 서비스입니다.

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

**패키지 앱**(MSIX)과 **비패키지 앱**(일반 Win32)을 모두 지원하는 토스트 알림입니다. Windows 11 이상이 필요합니다. Windows 라이브러리는 하나의 구현을 두 가지 공개 API로 제공하며, 샘플 앱은 C++ API를 사용합니다.

| API | 이름 | 헤더 | NuGet 패키지 |
|---|---|---|---|
| C++ API | `NativeToolkit::Notification` | `<NativeToolkit/Notification.h>` | `NativeToolkit` |
| C ABI | `ntk_notification_*` | `<NativeToolkitC/Notification.h>` | `NativeToolkit.CApi` |

### NativeToolkit::Notification

- `Notification::Manager`는 프로세스의 알림 서비스입니다. Windows는 프로세스마다 활성화 핸들러를 하나만 등록하므로 `Manager`도 한 번에 하나만 존재합니다. 두 번째 `Create`는 `ErrorCode::NotSupported`로 실패합니다.
- 모든 작업은 동기이며 호출한 스레드를 블로킹합니다.
- 반환값은 `Notification::Result<T>`입니다. `has_value()`로 성공과 실패를 구분하고, 실패 시 `error()`는 `Notification::ErrorCode`와 OS의 원래 값인 `systemCode`를 가집니다.
- `Manager::Create`는 호출한 스레드를 MTA(다중 스레드 아파트먼트)로 만듭니다. MTA가 된 스레드에서는 STA가 필요한 `Clipboard::Session`을 만들 수 없으므로, 같은 스레드에서 둘 다 사용한다면 먼저 그 스레드를 STA로 초기화해 주세요.
- 비패키지 앱에서는 `SetBadge`, `RemoveById`, `GetAll`이 `ErrorCode::NotSupported`가 됩니다. 플랫폼이 패키지 앱에만 제공하는 기능이기 때문입니다.

---

### 설정

#### Package.appxmanifest(패키지 앱)

토스트 활성화를 사용하려면 `<Application>` 요소 안에 다음 확장을 추가합니다.

```xml
<Extensions>
  <com:Extension Category="windows.comServer">
    <com:ComServer>
      <com:ExeServer Executable="YourApp.exe"
                     DisplayName="Native Toolkit Notification Activator"
                     Arguments="----AppNotificationActivated:">
        <com:Class Id="5F6A1B27-7C0B-4E1B-9070-6F1966502BAF"
                   DisplayName="Toast Activator"/>
      </com:ExeServer>
    </com:ComServer>
  </com:Extension>
  <desktop:Extension Category="windows.toastNotificationActivation">
    <desktop:ToastNotificationActivation
        ToastActivatorCLSID="5F6A1B27-7C0B-4E1B-9070-6F1966502BAF"/>
  </desktop:Extension>
</Extensions>
```

CLSID는 사용하시는 매니페스트에 등록한 값으로 바꿔 주세요. 샘플 앱은 `5F6A1B27-7C0B-4E1B-9070-6F1966502BAF`를 사용합니다.

#### Manager 생성 패키지 앱

```cpp
#include <NativeToolkit/Notification.h>

#include <optional>

namespace Notification = NativeToolkit::Notification;

// 이 프로세스의 유일한 Manager입니다. 이동 전용이므로
// 생성한 화면보다 오래 사는 위치에 둡니다.
std::optional<Notification::Manager> g_manager;

void OnNotificationInvoked(Notification::ActivationArgs const& args)
{
    // OS가 고른 스레드에서 호출됩니다. UI를 다루기 전에 UI 스레드로 옮겨 주세요.
    // 아래 "활성화 핸들러"를 참고해 주세요.
}

Notification::ManagerOptions options;
// 사용자가 알림을 조작했을 때 호출됩니다. 비워 두면 활성화가 버려집니다.
options.onInvoked = &OnNotificationInvoked;
// 패키지(MSIX) 앱은 표시 이름과 아이콘이 필요하지 않습니다.
options.isPackaged = true;

auto created = Notification::Manager::Create(options);
if (created.has_value())
{
    g_manager.emplace(std::move(created).value());
}
else
{
    // NotSupported: 이 프로세스에 이미 Manager가 있습니다.
    const Notification::ErrorCode code = created.error().code;
}
```

#### Manager 생성 비패키지 앱

패키지 식별자가 없는 앱은 먼저 Windows App SDK 런타임을 로드하고, 알림을 사용하는 동안 그 토큰을 유지합니다.

```cpp
#include <NativeToolkit/Notification.h>

namespace Notification = NativeToolkit::Notification;

// 1단계: Windows App SDK 런타임을 로드합니다. 0x00010007은 1.7입니다.
auto runtime = Notification::Runtime::Initialize(Notification::RuntimeVersion{ 0x00010007 });
if (!runtime.has_value())
{
    // HResultFailure: systemCode에 부트스트래퍼의 HRESULT가 들어갑니다.
    return;
}
// 파괴하면 런타임이 내려가므로 값을 계속 유지합니다.
Notification::Runtime held = std::move(runtime).value();

// 2단계: 표시 이름과 아이콘(둘 다 필수)을 지정해 Manager를 만듭니다.
Notification::ManagerOptions options;
options.onInvoked = &OnNotificationInvoked;
options.isPackaged = false;
options.displayName = L"MyApp";
options.iconUri = L"C:\\path\\to\\app-icon.png";

auto created = Notification::Manager::Create(options);
```

여기서 `displayName`은 표시 이름에 그치지 않고 앱의 AppUserModelID(AUMID)가 됩니다. `Create`는 이 이름으로 시작 메뉴 바로 가기를 만들고, 활성화 CLSID를 이 이름에서 도출하며, `HKCU\Software\Classes\AppUserModelId\<displayName>`을 기록합니다. 여기에는 실행 중인 프로세스로 활성화를 전달하는 `CustomActivator`도 포함됩니다. 기록은 덮어쓰기이므로 앱마다 다른 이름을 사용해 주세요. 같은 `displayName`을 사용하는 두 앱은 서로의 활성화를 가로챕니다. C ABI의 `display_name`도 마찬가지입니다.

#### 종료

```cpp
// 등록을 해제하고 활성화를 멈춥니다. 두 번 호출해도 아무 일도 일어나지 않습니다.
g_manager->Close();
g_manager.reset();
```

---

### 초기화 / 설정

#### 알림 설정 가져오기

```cpp
const auto setting = g_manager->GetSetting();
if (setting.has_value())
{
    switch (setting.value())
    {
    case Notification::NotificationSetting::Enabled:                break; // 0
    case Notification::NotificationSetting::DisabledForApplication: break; // 1
    case Notification::NotificationSetting::DisabledForUser:        break; // 2
    case Notification::NotificationSetting::DisabledByGroupPolicy:  break; // 3
    case Notification::NotificationSetting::DisabledByManifest:     break; // 4
    }
}
```

#### 알림 설정 열기

Windows 알림 설정 화면을 엽니다. `GetSetting`이 `Enabled` 외의 값을 반환했을 때 사용자가 알림을 다시 켜도록 안내할 때 사용합니다.

```cpp
const auto result = g_manager->OpenSettings();
```

---

### 알림 표시

토스트에 담을 수 있는 내용은 모두 `NotificationContent`에 있습니다. 샘플은 제목, 본문, 태그를 넣고 거기에서 하나씩 추가합니다.

```cpp
Notification::NotificationContent MakeContent(std::wstring title, std::wstring body, std::wstring tag)
{
    Notification::NotificationContent content;
    content.title = std::move(title);
    content.body = std::move(body);
    content.tag = std::move(tag);
    return content;
}
```

#### 기본

```cpp
const auto content = MakeContent(L"Hello", L"Basic toast", L"sample");
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowBasic.png" alt="Example_WindowsNotificationManager_ShowBasic" width="800" />
</p>

#### 버튼 포함

버튼은 자신의 인수를 가지며, 눌리면 활성화 핸들러로 전달됩니다. 버튼은 최대 5개입니다.

```cpp
Notification::Button MakeButton(std::wstring label, std::wstring action)
{
    Notification::Button button;
    button.label = std::move(label);
    // 키는 자유롭게 정할 수 있습니다. ActivationArgs::values로 돌아옵니다.
    button.args = Notification::ArgumentPairs{ { L"action", std::move(action) } };
    return button;
}

auto content = MakeContent(L"Actionable", L"Toast with buttons", L"sample");
content.buttons = { MakeButton(L"Open", L"open"), MakeButton(L"Dismiss", L"dismiss") };
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithButtons.png" alt="Example_WindowsNotificationManager_ShowWithButtons" width="800" />
</p>

#### 이미지 포함

```cpp
auto content = MakeContent(L"With Image", L"Toast with hero image", L"sample");
// 패키지 앱에서는 ms-appx:///를 사용할 수 있습니다. file:///이나 http(s):// 도 됩니다.
content.heroImage = L"ms-appx:///Assets/StoreLogo.png";
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithImage.png" alt="Example_WindowsNotificationManager_ShowWithImage" width="800" />
</p>

#### 입력 포함

사용자가 입력하거나 선택한 값은 필드 id를 키로 하여 활성화 핸들러로 전달됩니다.

```cpp
auto content = MakeContent(L"Reply", L"Type a reply and pick an option", L"sample");

Notification::TextInput reply;
reply.id = L"reply";
reply.placeholder = L"Type a message";
content.textInputs = { reply };

Notification::ComboInput status;
status.id = L"opt";
status.title = L"Status";
// items와 대조하지 않습니다. 없는 id를 지정하면 선택되지 않은 상태가 됩니다.
status.defaultSelection = L"busy";
status.items = { { L"free", L"Free" }, { L"busy", L"Busy" } };
content.comboInputs = { status };

content.buttons = { MakeButton(L"Send", L"send") };
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithInput.png" alt="Example_WindowsNotificationManager_ShowWithInput" width="800" />
</p>

#### 진행률 포함

진행률 표시줄을 보여 줍니다. 이후 같은 태그로 `UpdateProgress`를 호출하면 갱신할 수 있습니다.

```cpp
auto content = MakeContent(L"Downloading", L"In progress", L"progress-sample");

Notification::ProgressSpec progress;
progress.title = L"Toolkit.zip";
// 0.0 ~ 1.0입니다. 여기서는 범위를 검사하지 않습니다.
progress.value = 0.3;
progress.valueStr = L"30%";
progress.status = L"Downloading";
content.progress = progress;

const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithProgress.png" alt="Example_WindowsNotificationManager_ShowWithProgress" width="800" />
</p>

#### 만료 포함

지정한 시간이 지나면 알림이 알림 센터에서 사라집니다. 전달 시점 기준의 상대 시간이며, `Schedule`에서는 무시됩니다.

```cpp
auto content = MakeContent(L"Expires", L"This toast expires in 10 seconds", L"sample");
content.expiration = std::chrono::seconds(10);
const auto result = g_manager->Show(content);
```

#### 사운드 포함

```cpp
auto content = MakeContent(L"Reminder", L"Toast with reminder sound", L"sample");

Notification::AudioSpec audio;
// Event: 이름이 있는 시스템 사운드. Mute: 무음. Uri: audio.uri의 사운드.
audio.kind = Notification::AudioKind::Event;
audio.eventName = L"reminder";
content.audio = audio;

const auto result = g_manager->Show(content);
```

---

### 알림 예약

`Schedule`은 절대 시각을 `std::chrono::system_clock::time_point`로 받습니다. 예약에서는 `expiration`과 `progress`가 무시됩니다.

```cpp
#include <chrono>

const auto when = std::chrono::system_clock::now() + std::chrono::seconds(60);
const auto content = MakeContent(L"Scheduled", L"Fires in ~1 minute", L"scheduled");
const auto result = g_manager->Schedule(content, when);
```

> **참고:** 5분 이상 과거로 예약된 알림은 전달 시각에 앱이 실행 중이 아니었다면 OS가 버릴 수 있습니다.

#### 예약 취소

```cpp
// 예약한 알림의 태그와 그룹을 지정합니다.
const auto result = g_manager->CancelScheduled(L"scheduled", L"");
```

---

### 진행률 갱신

진행률 표시줄이 있는 알림을 갱신합니다. `ErrorCode::ProgressNotFound`는 해당 알림이 알림 센터에 없거나 시퀀스 번호가 오래되었다는 뜻입니다.

```cpp
Notification::ProgressUpdate update;
// Show에 전달한 태그, 그룹과 일치해야 합니다.
update.tag = L"progress-sample";
update.group = L"";
update.value = 0.6;
update.valueString = L"60%";
update.status = L"Downloading";
// 호출하는 쪽에서 증가시킵니다. 뒤로 간 갱신은 OS가 버립니다.
update.sequenceNumber = seq++;

const auto result = g_manager->UpdateProgress(update);
if (!result.has_value() && result.error().code == Notification::ErrorCode::ProgressNotFound)
{
    // 갱신할 대상이 없습니다. 먼저 진행률이 있는 알림을 표시해 주세요.
}
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_UpdateProgress.png" alt="Example_WindowsNotificationManager_UpdateProgress" width="800" />
</p>

---

### 배지

작업 표시줄 아이콘에 배지를 표시합니다. 패키지 앱 전용이며, 비패키지 앱에서는 `ErrorCode::NotSupported`가 됩니다.

```cpp
g_manager->SetBadge(5);   // 숫자 배지
g_manager->SetBadge(-1);  // 글리프: alert
g_manager->SetBadge(0);   // 배지 지우기
```

**글리프 값:** `-1`=alert, `-2`=activity, `-3`=newMessage, `-4`=available, `-5`=busy, `-6`=away. -6보다 작은 값은 `ErrorCode::InvalidParameter`입니다.

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_Badge.png" alt="Example_WindowsNotificationManager_Badge" width="800" />
</p>

---

### 삭제 / 조회

#### 전체 알림 가져오기

알림 센터에 있는 알림을 나열합니다. 패키지 앱 전용입니다.

```cpp
const auto result = g_manager->GetAll();
if (result.has_value())
{
    for (const Notification::NotificationRef& notification : result.value())
    {
        const uint32_t id = notification.id;
        const std::wstring& tag = notification.tag;
        const std::wstring& group = notification.group;
    }
}
```

#### ID로 삭제

`GetAll`이 알려 준 id로 한 건만 삭제합니다. 패키지 앱 전용입니다.

```cpp
const auto result = g_manager->RemoveById(notificationId);
```

#### 태그로 삭제

```cpp
const auto result = g_manager->RemoveByTag(L"sample", L"");
```

#### 전체 삭제

```cpp
const auto result = g_manager->RemoveAll();
```

---

### 활성화 핸들러

핸들러는 OS가 활성화를 전달한 스레드에서 실행되며, 호출하는 쪽의 스레드로 옮겨지지 않습니다. `ActivationArgs::values`에는 눌린 버튼의 인수와 모든 텍스트 필드, 선택 필드의 내용이 id를 키로 하여 함께 담깁니다. `rawArguments`는 가공하지 않은 인수 문자열입니다.

비패키지 앱이 토스트 클릭으로 시작된 경우(콜드 스타트)에도, 그 활성화는 다른 활성화와 같은 경로로 한 번만 전달됩니다. `Manager::Create`가 반환되기 전에 전달될 수 있으며, 호출한 스레드가 STA일 때는 `Create` 안에서 그 스레드로 전달되는 것을 확인했습니다. 따라서 핸들러는 자신이 속한 Manager가 이미 존재한다고 가정해서는 안 됩니다. 프로세스의 명령줄에는 COM이 시작했다는 표시(`-ToastActivated -Embedding`)만 있고, 토스트의 내용은 들어 있지 않습니다.

샘플 앱은 생성 시 핸들러를 한 번만 등록하고, 그때 화면에 있는 페이지로 전달합니다.

```cpp
namespace
{
    std::function<void(winrt::hstring)> g_notificationHandler;

    void OnNotificationInvoked(Notification::ActivationArgs const& args)
    {
        if (g_notificationHandler)
        {
            g_notificationHandler(winrt::hstring{ args.rawArguments });
        }
    }
}

// OnNavigatedTo에서 등록하고 UI 스레드로 옮깁니다.
auto weakText = winrt::make_weak(ResultTextBlock());
auto dq = DispatcherQueue();
g_notificationHandler = [weakText, dq](winrt::hstring args)
{
    dq.TryEnqueue([weakText, args]()
    {
        if (auto text = weakText.get())
            text.Text(L"\U0001F514 Notification invoked:\n" + args);
    });
};

// OnNavigatedFrom에서 해제합니다.
g_notificationHandler = nullptr;
```

---

### 오류 코드

`Notification::ErrorCode`(`NativeToolkit::NotificationError`)입니다. 같은 숫자가 C ABI의 `NTK_NOTIFICATION_ERROR_*`입니다.

| 코드 | 이름 | 설명 |
|---|---|---|
| 0 | `None` | 성공 |
| 1 | `NotInitialized` | `Create` 전 또는 `Close` 후에 사용했습니다 |
| 2 | `Disabled` | 이 앱 또는 사용자에 대해 알림이 꺼져 있습니다 |
| 3 | `InvalidPayload` | 예약된 값으로 반환되지 않습니다. 1.x C ABI에서 JSON을 해석하지 못했을 때의 값입니다 |
| 4 | `ProgressNotFound` | 갱신할 알림이 없거나 시퀀스 번호가 오래되었습니다 |
| 5 | `HResultFailure` | 등록, 바로 가기, 또는 런타임 로드에 실패했습니다 |
| 6 | `BadgeFailed` | 배지 갱신에 실패했습니다 |
| 7 | `InvalidParameter` | 인수가 잘못되었습니다(-6보다 작은 배지 값 등) |
| 8 | `NotSupported` | 이 앱 종류에서는 사용할 수 없거나(비패키지 앱의 `SetBadge` / `RemoveById` / `GetAll`), 두 번째 Manager입니다 |

### C ABI

- C에서, 그리고 C DLL을 호출할 수 있는 언어에서 같은 알림을 사용하기 위한 API입니다.
- 내용은 구조체가 아니라 핸들로 구성합니다. 세터를 하나씩 호출하고 `ntk_notification_content_free`로 해제합니다.
- 등록은 `user_data`와 `release`를 동반합니다. `release`는 등록마다 정확히 한 번 호출되며(등록 함수가 실패했을 때도 호출됩니다), 바인딩이 할당한 것을 여기서 해제합니다.
- 핸들은 `ntk_notification_manager_free`, `ntk_notification_runtime_free`, `ntk_notification_list_free`로 해제합니다.
- 모든 함수는 어느 스레드에서든 호출할 수 있습니다. 활성화는 OS가 고른 스레드로 전달되며, 거기서 받는 것은 그 호출 동안만 유효합니다.

#### 런타임, 매니저, 활성화

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

static void NTK_CALL on_invoked(void* user_data, const ntk_notification_activation* activation)
{
    /* OS가 고른 스레드에서 호출됩니다. 여기서 읽은 것은 호출 밖에서 쓸 수 없습니다. */
    size_t size = 0;
    const char* raw = ntk_notification_activation_raw_arguments(activation, &size);
    (void)raw; (void)user_data;

    /* 눌린 버튼의 인수와 사용자의 입력이 id를 키로 하여 함께 담겨 있습니다. */
    size_t count = ntk_notification_activation_value_count(activation);
    size_t i;
    for (i = 0; i < count; ++i) {
        const char* key = ntk_notification_activation_key_at(activation, i, NULL);
        const char* value = ntk_notification_activation_value_at(activation, i, NULL);
        (void)key; (void)value;
    }
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* 등록 함수가 실패했을 때를 포함해 정확히 한 번 호출됩니다. */
    (void)user_data;
}

/* 패키지 식별자가 없는 앱은 먼저 Windows App SDK 런타임을 로드하고, 알림을
   사용하는 동안 핸들을 유지합니다. 0x00010007은 1.7입니다.
   패키지 앱에서는 필요하지 않습니다. */
ntk_notification_runtime* runtime = NULL;
ntk_notification_error error = ntk_notification_runtime_initialize(0x00010007u, &runtime);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

ntk_notification_manager_options options;
memset(&options, 0, sizeof(options));
options.struct_size = (uint32_t)sizeof(options);
options.on_invoked = &on_invoked;
options.user_data = NULL;
options.release = &release_user_data;
options.is_unpackaged = 1;                 /* 패키지(MSIX) 앱이면 0 */
options.display_name = "MyApp";            /* 비패키지일 때는 필수 */
options.icon_uri = "C:\\path\\to\\app-icon.png";

ntk_notification_manager* manager = NULL;
error = ntk_notification_manager_create(&options, &manager);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    ntk_notification_runtime_free(runtime);
    return;
}

/* 나중에 핸들러를 교체하는 경우입니다. 이전 등록의 release는 그 등록으로
   실행 중이던 활성화가 모두 끝난 뒤에 호출됩니다. */
error = ntk_notification_manager_set_invoked_handler(manager, &on_invoked, NULL, &release_user_data);

/* 종료할 때는 close → 매니저 해제 → 런타임 해제 순서입니다. */
ntk_notification_manager_close(manager);
ntk_notification_manager_free(manager);
ntk_notification_runtime_free(runtime);
```

#### 내용 구성, 표시, 예약

OS가 필수로 요구하는 것 외에 세터는 모두 선택입니다. `add_button`과 `add_combo`는 추가한 항목의 인덱스를 돌려주고, 인수와 항목 세터는 그 인덱스를 지정합니다.

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
if (ntk_notification_content_create(&content) != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* 문구와 식별자입니다. 모두 UTF-8입니다. */
ntk_notification_content_set_title(content, "Hello");
ntk_notification_content_set_body(content, "Basic toast");
ntk_notification_content_set_tag(content, "sample");
ntk_notification_content_set_group(content, "");
ntk_notification_content_set_attribution(content, "native-toolkit");
ntk_notification_content_set_scenario(content, NTK_NOTIFICATION_SCENARIO_DEFAULT);
ntk_notification_content_set_duration(content, NTK_NOTIFICATION_DURATION_SHORT);

/* 이미지입니다. */
ntk_notification_content_set_hero_image(content, "ms-appx:///Assets/StoreLogo.png");
ntk_notification_content_set_inline_image(content, NULL);   /* NULL이면 해제 */
ntk_notification_content_set_app_logo(content, "ms-appx:///Assets/StoreLogo.png",
                                      NTK_NOTIFICATION_LOGO_CROP_CIRCLE);

/* 사운드입니다. 이름이 있는 시스템 사운드이며 반복하지 않습니다. */
ntk_notification_content_set_audio(content, NTK_NOTIFICATION_AUDIO_KIND_EVENT,
                                   "reminder", NULL, 0);

/* 버튼입니다. with_arguments를 0이 아닌 값으로 주면 인수 목록이 준비됩니다. */
size_t button = 0;
ntk_notification_content_add_button(content, "Open", NULL, 1, &button);
ntk_notification_content_add_button_argument(content, button, "action", "open");

/* 텍스트 필드와 선택 필드입니다. */
ntk_notification_content_add_text_input(content, "reply", "Type a message", NULL);

size_t combo = 0;
ntk_notification_content_add_combo(content, "opt", "Status", "busy", &combo);
ntk_notification_content_add_combo_item(content, combo, "free", "Free");
ntk_notification_content_add_combo_item(content, combo, "busy", "Busy");

/* 진행률 표시줄과 시각입니다. 둘 다 예약에서는 무시됩니다. */
ntk_notification_content_set_progress(content, "Toolkit.zip", 0.3, "30%", "Downloading");
ntk_notification_content_set_expiration(content, 10);            /* 전달 후 초 */
ntk_notification_content_set_expires_on_reboot(content, 0);      /* 패키지 앱 전용 */
ntk_notification_content_set_timestamp(content, 1758585600000);  /* Unix 밀리초 */

/* 지금 표시하는 경우입니다. */
ntk_notification_error error = ntk_notification_show(manager, content);

/* 절대 시각으로 예약하는 경우입니다. 시각은 Unix 밀리초입니다. */
error = ntk_notification_schedule(manager, content, 1758585660000);

ntk_notification_content_free(content);

/* 예약한 알림은 태그와 그룹으로 취소합니다. */
error = ntk_notification_cancel_scheduled(manager, "scheduled", "");
```

#### 진행률, 배지, OS 설정

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* 진행률 표시줄이 있는 알림을 갱신합니다. */
ntk_notification_progress_update update;
memset(&update, 0, sizeof(update));
update.struct_size = (uint32_t)sizeof(update);
update.tag = "progress-sample";      /* ntk_notification_show에 전달한 값 */
update.group = "";
update.value = 0.6;
update.value_string = "60%";
update.status = "Downloading";
update.sequence_number = 2;          /* 호출하는 쪽에서 증가시킵니다 */

ntk_notification_error error = ntk_notification_update_progress(manager, &update);
if (error == NTK_NOTIFICATION_ERROR_PROGRESS_NOT_FOUND) {
    /* 갱신할 대상이 없거나 시퀀스 번호가 오래되었습니다. */
}

/* 작업 표시줄 아이콘의 배지입니다. 패키지 앱 전용이며 그 외에는
   NOT_SUPPORTED입니다. 5는 숫자, -1은 alert 글리프, 0은 지우기입니다. */
error = ntk_notification_set_badge(manager, 5);

/* OS 설정 상태와, 그것을 바꾸는 화면입니다. */
ntk_notification_setting setting = NTK_NOTIFICATION_SETTING_ENABLED;
error = ntk_notification_get_setting(manager, &setting);
if (setting != NTK_NOTIFICATION_SETTING_ENABLED) {
    error = ntk_notification_open_settings(manager);
}
```

#### 목록과 삭제

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* 알림 센터에 있는 것들입니다. 패키지 앱 전용입니다. */
ntk_notification_list* list = NULL;
ntk_notification_error error = ntk_notification_get_all(manager, &list);
if (error == NTK_NOTIFICATION_ERROR_NONE) {
    size_t count = ntk_notification_list_count(list);
    size_t i;
    for (i = 0; i < count; ++i) {
        uint32_t id = ntk_notification_list_id_at(list, i);
        const char* tag = ntk_notification_list_tag_at(list, i, NULL);
        const char* group = ntk_notification_list_group_at(list, i, NULL);
        (void)id; (void)tag; (void)group;
    }
    /* 위의 포인터는 이 호출 전까지 유효합니다. */
    ntk_notification_list_free(list);
}

/* 삭제는 get_all이 알려 준 id(패키지 앱 전용), 태그와 그룹, 또는 이 앱이
   올린 것 전부의 세 가지입니다. */
error = ntk_notification_remove_by_id(manager, 1u);
error = ntk_notification_remove_by_tag(manager, "sample", "");
error = ntk_notification_remove_all(manager);
```

| C++ API | C ABI |
|---|---|
| `Runtime::Initialize` / 소멸자 | `ntk_notification_runtime_initialize` / `ntk_notification_runtime_free` |
| `Manager::Create` | `ntk_notification_manager_create` |
| `Manager::SetInvokedHandler` | `ntk_notification_manager_set_invoked_handler` |
| `Manager::Close` | `ntk_notification_manager_close` / `ntk_notification_manager_free` |
| `NotificationContent` | `ntk_notification_content_create`와 22개의 세터 |
| `ActivationArgs` | `ntk_notification_activation_raw_arguments` / `_value_count` / `_key_at` / `_value_at` |
| `Manager::Show` | `ntk_notification_show` |
| `Manager::Schedule` | `ntk_notification_schedule`(시각은 Unix 밀리초) |
| `Manager::CancelScheduled` | `ntk_notification_cancel_scheduled` |
| `Manager::UpdateProgress` | `ntk_notification_update_progress` |
| `Manager::SetBadge` | `ntk_notification_set_badge` |
| `Manager::GetAll` | `ntk_notification_get_all`과 `ntk_notification_list_*` |
| `Manager::RemoveById` / `RemoveByTag` / `RemoveAll` | `ntk_notification_remove_by_id` / `_by_tag` / `_all` |
| `Manager::GetSetting` | `ntk_notification_get_setting` |
| `Manager::OpenSettings` | `ntk_notification_open_settings` |

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
