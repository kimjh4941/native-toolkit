# ``IosLibrary``

Swift APIs for in-app dialogs, local notifications, the system share sheet and the pasteboard.

## Overview

`IosLibrary` has four features, each behind one manager:

| Feature | Manager | What it does |
|---|---|---|
| Dialog | ``IosDialogManager`` | Presents `UIAlertController` alerts, confirmations, destructive actions, action sheets, text input and login prompts |
| Notification | ``IosNotificationManager`` | Shows, schedules, updates and removes local notifications; requests the permission; registers categories; receives the responses through its own `UNUserNotificationCenterDelegate` |
| Share | ``IosShareManager`` | Presents `UIActivityViewController` for text, URLs, images and files |
| Clipboard | ``IosClipboardManager`` | Copies, reads, inspects and observes `UIPasteboard`, loads item providers, detects patterns, and provides a `UIPasteControl` paste button |

Each manager is used through its `shared` instance. Most operations have a callback form and an
`async` form; the callback forms that existed in 1.x keep their `(isSuccess, ..., errorMessage)`
shape, and the forms added in 2.0.0 report a `Result` with a typed error.

The library is built in the Swift 6 language mode and needs iOS 18.0 or later.

## Quick Start

### Dialog

```swift
import IosLibrary

// One request, one result. Callable from any thread; the completion runs on the main thread.
let box = IosDialogManager.shared.show(
    .confirm(title: "Delete the file?", message: nil, confirmTitle: "Delete"),
    presenter: .foreground
) { result in
    switch result {
    case .success(let answer) where answer.button == .primary: print("confirmed")
    case .success: print("cancelled by the user")
    case .failure(let error): print(error.localizedDescription)
    }
}
// Later, if the dialog is no longer wanted: it is dismissed and the result is .canceled.
IosDialogManager.shared.cancel(box)

// The async form returns the answer, or throws a DialogError (CancellationError when the task is cancelled).
let answer = try await IosDialogManager.shared.show(
    .textInput(title: "Name", message: nil, placeholder: "Your name"),
    presenter: .foreground
)
if case .text(let name) = answer.input { print(name) }

// The 1.x methods remain: button callbacks, and a completion that reports the presentation.
IosDialogManager.shared.showAlert(
    title: "Notice",
    message: "Operation finished",
    onButton: { button, _, _ in print("tapped \(button ?? "")") },
    completion: { isSuccess, errorMessage in
        if !isSuccess { print(errorMessage ?? "") }
    }
)
```

### Notification

```swift
import IosLibrary
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // On the main thread, before launch ends.
        IosNotificationManager.installDelegate()
        do {
            try IosNotificationManager.shared.responses.addListener { event, _ in
                print(event.notificationIdentifier, event.actionIdentifier, event.userText ?? "")
            }
        } catch {
            print(error)
        }
        return true
    }
}

// Elsewhere, from any thread:
let granted = try await IosNotificationManager.shared.requestPermission(presenter: .foreground)
if granted {
    try await IosNotificationManager.shared.show(
        content: NotificationContent(id: "greeting", title: "Hello", body: "From IosLibrary"),
        trigger: nil
    )
}

IosNotificationManager.shared.schedule(
    content: NotificationContent(id: "reminder", title: "Reminder"),
    trigger: .timeInterval(60, repeats: false),
    identifier: "reminder"
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### Share

```swift
import IosLibrary

do {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.text("Hello"), .url("https://example.com")]),
        presenter: .foreground
    )
    // Closing the sheet without choosing an activity is not an error.
    print(result.completed ? "shared with \(result.activityType ?? "")" : "closed")
} catch {
    print(error.localizedDescription)  // a ShareError
}
```

### Clipboard

```swift
import IosLibrary
import UniformTypeIdentifiers

// On the main actor.
try await IosClipboardManager.shared.copy(.plainText("Hello"))

// Metadata only: no paste prompt and no access notification.
let snapshot = try await IosClipboardManager.shared.snapshot()
if snapshot.hasStrings {
    // Reads the contents: iOS may ask the user to allow the paste.
    let result = try await IosClipboardManager.shared.read()
    print(result.items.first?.text ?? "")
}

// A paste button: add the returned view to your hierarchy as it is.
let pasteView = try IosClipboardManager.shared.makePasteControl(
    acceptedTypes: [UTType.plainText.identifier],
    onPaste: { items in print(items) }
)
```

## Threading

| Manager | Where to call it | Where results arrive |
|---|---|---|
| ``IosDialogManager`` | Any thread. ``IosDialogManager/getRootViewController()`` and ``IosDialogManager/foregroundViewController()`` are `@MainActor` | Main thread, asynchronously (also when called on the main thread). The completion of `show` comes exactly once; each button callback at most once |
| ``IosShareManager`` | Any thread | Main thread, exactly once, never inside the call |
| ``IosNotificationManager`` | Any thread. ``IosNotificationManager/installDelegate()`` on the main thread only; ``IosNotificationManager/launchResponse()`` and adding or removing listeners on the main actor | Completions on the main thread, exactly once, asynchronously. Listeners on the main actor |
| ``IosClipboardManager`` | The main actor (the class is `@MainActor`). ``IosClipboardManager/cancelLoad(_:)-swift.type.method`` and its instance form can be called from any thread | The main actor |

The completions and handlers of the Dialog, Share and Notification managers are
`@MainActor @Sendable`: `@Sendable` because they are carried from the calling thread to the main
actor, and `@MainActor` so that a closure written on the main actor (for example in a SwiftUI
view) can use main-actor state directly. From a context that is not on the main actor, call the
Clipboard manager inside `await MainActor.run { ... }`.

## Errors

The forms added in 2.0.0 report typed errors. Each error has a fixed English `errorDescription`
that does not contain the values passed in (``ShareError`` is the exception for the URL or path it
names). The callback forms of 1.x report the same text as their `errorMessage`.

- ``DialogError``: why a ``DialogRequest`` ended without an answer: cancelled, dismissed by the
  system, not in the foreground, presentation failed, or a reused ``RequestBox``.
- ``ShareError``: invalid content, no view controller to present from, presentation failed,
  dismissed by the system, or the chosen activity failed. Closing the sheet is not an error:
  ``ShareResult/completed`` is `false`.
- ``NotificationError``: a failed system request, an invalid userInfo or trigger, not in the
  foreground, or a listener added before ``IosNotificationManager/installDelegate()``. The `async`
  forms are declared `async throws` and throw a ``NotificationError``. A denied permission is not
  an error in the forms that take a presenter: they report `false`.
- ``ClipboardError``: each case has a stable ``ClipboardError/errorCode`` (`CLIPBOARD_*`), which the
  callback forms report as `(isSuccess, ..., errorCode, errorMessage)`. A cancelled load is
  `CLIPBOARD_CANCELLED` (``ClipboardError/cancelled``), which callers may treat as a normal
  outcome.

An error that reports a failed system API keeps only the `NSError` domain and code: a
``FailureDetail`` in ``NotificationError`` and ``ShareError``, a ``ClipboardFailureDetail`` in
``ClipboardError``. The system error itself and its localized description are not kept.

## Presenters and Request Boxes

The operations that show system UI take a ``PresenterSelection`` to choose the view controller to
present from:

- ``PresenterSelection/firstActiveScene`` (the default): the topmost view controller of the first
  foreground active scene, searched once, without waiting. This is how 1.x chose it.
- ``PresenterSelection/foreground``: the topmost view controller of a foreground scene that is not
  being dismissed. Without one, the operation fails as not in the foreground instead of showing
  anything. Before presenting a dialog or a share sheet, a view controller in a transition is
  waited for once.
- ``PresenterSelection/viewController(_:)``: the view controller your closure returns, on the
  main thread. Use it on iPad when two scenes of the app can be active side by side.

They are taken by ``IosDialogManager/show(_:presenter:requestBox:completion:)``,
``IosShareManager/share(content:presenter:completion:)``,
``IosNotificationManager/requestPermission(options:presenter:completion:)`` and
``IosNotificationManager/openNotificationSettings(presenter:completion:)``, and their `async`
forms.

A ``RequestBox`` identifies one request so that it can be cancelled later, from any thread. Create
it before the call when you need to cancel from the moment the request starts, or use the box
`show` returns:

| Operation | Cancel with |
|---|---|
| ``IosDialogManager/show(_:presenter:requestBox:completion:)`` | ``IosDialogManager/cancel(_:)`` |
| ``IosClipboardManager/loadItem(_:scope:requestBox:completion:)`` | ``IosClipboardManager/cancelLoad(_:)-swift.method`` |

A box belongs to one request. The request ends when the box closes, and only the first close
counts, so the completion is called once. A box cancelled before its request starts makes that
request end at once as cancelled. A share cannot be cancelled.

## Notification Delegate and Events

The library receives notification responses through its own `UNUserNotificationCenterDelegate`.
Call ``IosNotificationManager/installDelegate()`` on the main thread before launch ends: before
`application(_:didFinishLaunchingWithOptions:)` returns, in `scene(_:willConnectTo:options:)`, or
in a SwiftUI app in `App.init` or the `UIApplicationDelegateAdaptor`. On another thread it does
nothing and returns ``NotificationDelegateInstallResult/notMainThread``. Installing later loses the
response that launched the app.

- The delegate that was set before is kept (weakly) and receives the notifications that are not
  the library's, when it implements the delegate method. The library marks its own notifications
  with a reserved userInfo key, `com.jonghyunkim.nativetoolkit`; a userInfo that uses the key is
  rejected, and the key is removed from every userInfo the library returns.
- When another object replaces the delegate later, the library logs a warning; call
  ``IosNotificationManager/installDelegate()`` again to restore it.
- ``IosNotificationManager/responses`` delivers taps, actions, text replies and the custom
  dismiss action as ``NotificationResponseEvent``s; ``IosNotificationManager/settingsRequests``
  delivers the system's requests to show your notification settings
  (``NotificationSettingsRequest``). While a hub has no listener it keeps up to 32 events and hands
  them to the next listener inside ``NotificationEventHub/addListener(_:)``, so a listener added
  after launch still receives the response that launched the app.
- ``IosNotificationManager/launchResponse()`` returns that response, or `nil`. The same response
  also arrives through ``IosNotificationManager/responses`` with
  ``NotificationResponseEvent/isLaunchResponse`` set: handle it in one place.
- Adding a listener or calling ``IosNotificationManager/launchResponse()`` before the delegate is
  installed throws ``NotificationError/delegateNotInstalled``.

The deprecated `setup()`, `onActionReceived` and `onTextInputActionReceived` still work, but the
receivers are called in addition to the listeners: use one or the other.

## Clipboard Notes

### Prompts and access notifications

`read`, `readData`, `detectValues` and `loadItem` read the pasteboard's contents, and may trigger
the paste permission prompt and the access notification, at the system's discretion. `read` and
`readData` wait on the main thread for the user's answer. Use `snapshot` or `detectPatterns` to
check first: they read no contents. `UIPasteControl` (``IosClipboardManager/makePasteControl(acceptedTypes:displayMode:onPaste:onPartialFailure:onPasteFailure:)``)
avoids the permission prompt, but Apple does not document it as avoiding the access notification;
verify on a device for your target versions before relying on either being silent.

### Named and unique pasteboards are not a persistent store

A pasteboard created with ``PasteboardCreationRequest/named(_:)`` or
``PasteboardCreationRequest/unique`` is not meant to persist, but its contents are not guaranteed
to be discarded when the creating app quits either: on iOS 18.7.2, a named pasteboard written
before a force-quit was still readable after relaunching. Use these pasteboards only to hand data
between running apps, and delete sensitive data explicitly with
``IosClipboardManager/removePasteboard(_:completion:)``. For data that must outlive the app, use an
App Group container instead.

### append has no privacy options

`append` cannot take ``ClipboardCopyOptions``, and does not guarantee that the `localOnly` or
`expirationDate` of an earlier `copy` apply to the appended item. Use `copy` for sensitive data.

### Loaded files

A `.file(URL)` delivered by `loadItem` or by the paste button belongs to you, with its temporary
parent directory: delete them when done. Files that are not delivered (a failure, a cancellation,
a timeout, or a result that lost to a cancellation) are deleted by the library.

### Cancelling a load

| Way | Thread | The cancelled load reports |
|---|---|---|
| ``IosClipboardManager/cancelLoad(_:)-swift.method`` with the ``RequestBox`` of ``IosClipboardManager/loadItem(_:scope:requestBox:completion:)`` | Any | `CLIPBOARD_CANCELLED`, once |
| `cancel()` of the ``ClipboardLoadToken`` that ``IosClipboardManager/loadItem(_:scope:completion:)`` returns | Main actor | `CLIPBOARD_CANCELLED`, once |
| Cancelling the task of ``IosClipboardManager/loadItem(_:scope:)`` | Any | Throws ``ClipboardError/cancelled`` |
| ``IosClipboardManager/cancelAllLoads()`` | Main actor | Each pending load of the manager, once |

A paste on ``ClipboardPasteControlContainerView`` that is cancelled (by a new paste, or by the
view going away) calls none of `onPaste`, `onPartialFailure` and `onPasteFailure`.

### Pattern detection has no cancellation token

`detectPatterns` and `detectValues` wrap system detection calls that cannot be cancelled. Cancelling
the task, or the detection timeout, returns control at once, but the system call may keep running;
its result is discarded.

### Placing the paste button

Add the single view that `makePasteControl` returns (a ``ClipboardPasteControlContainerView``) to
your hierarchy: it keeps the button and its receiver, and the receiver joins the responder chain.
``PasteControlFactory/makeComponents(acceptedTypes:displayMode:typeValidator:)`` returns the button
and the receiver separately for layouts that place them apart; you then retain the receiver and
add it to the hierarchy yourself.

## C ABI

The separate framework `IosLibraryCApi`, shipped as `ios-native-toolkit-capi-2.0.0.xcframework`,
exposes the four features as a C ABI: `ntk_*` functions declared in the `NativeToolkitC` headers,
for C, C++, Objective-C and other languages that can call C functions. It calls this library, so
ship it together with `ios-native-toolkit-2.0.0.xcframework`. Swift apps use this library directly.

## Versioning

`IosLibrary` follows semantic versioning. 2.0.0 is a major release with breaking changes from 1.x,
among them: completions and handlers typed `@MainActor @Sendable`; Notification and Share error
cases that carry a ``FailureDetail`` instead of a system error; the notification delegate installed
with ``IosNotificationManager/installDelegate()`` (the manager is no longer a
`UNUserNotificationCenterDelegate`); the reserved userInfo key; and `async` overloads that need
`await` where a callback form was called from an `async` context without a completion.

## Topics

### Dialog

- ``IosDialogManager``
- ``DialogRequest``
- ``DialogAnswer``
- ``DialogInput``
- ``DialogError``
- ``DialogPresenting``

### Notification

- ``IosNotificationManager``
- ``NotificationContent``
- ``NotificationTrigger``
- ``NotificationSound``
- ``NotificationInterruptionLevel``
- ``NotificationAttachment``
- ``NotificationAuthorizationStatus``
- ``ScheduledNotification``
- ``ActiveNotification``
- ``NotificationError``

### Notification Categories

- ``NotificationCategory``
- ``NotificationCategoryOptions``
- ``NotificationAction``
- ``NotificationActionOptions``
- ``TextInputNotificationAction``

### Notification Delegate and Events

- ``NotificationDelegateInstallResult``
- ``NotificationEventHub``
- ``NotificationEventRegistration``
- ``NotificationResponseEvent``
- ``NotificationSettingsRequest``
- ``NotificationUserInfoValue``
- ``NotificationActionHandler``
- ``NotificationTextInputActionHandler``

### Share

- ``IosShareManager``
- ``ShareContent``
- ``ShareItem``
- ``ShareResult``
- ``ShareError``

### Clipboard

- ``IosClipboardManager``
- ``ClipboardContent``
- ``ClipboardCopyOptions``
- ``PasteboardScope``
- ``PasteboardCreationRequest``
- ``ClipboardReadResult``
- ``ClipboardItemData``
- ``ClipboardSnapshot``
- ``ClipboardLoadRequest``
- ``ClipboardLoadedItem``
- ``ClipboardLoadToken``
- ``ClipboardDetectionPattern``
- ``ClipboardDetectedValues``
- ``ClipboardLabeledValue``
- ``ClipboardPostalAddress``
- ``ClipboardCalendarEvent``
- ``ClipboardFlightNumber``
- ``ClipboardMoneyAmount``
- ``ClipboardShipmentTracking``
- ``ClipboardChangeEvent``
- ``ClipboardError``
- ``ClipboardFailureDetail``
- ``ClipboardOperationKind``
- ``ClipboardTimeouts``
- ``ClipboardLimits``

### Clipboard Paste Button

- ``ClipboardPasteControlContainerView``
- ``ClipboardPasteReceiverView``
- ``PasteControlFactory``

### Presentation and Cancellation

- ``PresenterSelection``
- ``RequestBox``
- ``FailureDetail``

### Deprecated

- ``NotificationPermissionHelper``
- ``Log``
