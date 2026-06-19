# Windows Notification Implementation Review v2

## Basic Information

- Date: 2026-06-13
- Target OS: Windows
- Target feature: notification
- Review scope: current workspace implementation and the actual Unity sample controller used by the package consumer
- Design document: `artifact/designs/notification/2026-05-30-windows-notification-design-v3.md`
- Primary result reference: `artifact/results/notification/2026-05-30-windows-notification-implement-feature-result-v1.md`

---

## Review Summary

The core architecture introduced by v3 is mostly present in code: backend separation exists, `NOTIFICATION_ERROR_NOT_SUPPORTED(8)` exists, backend injection for tests exists, and callback synchronization was added. The remaining gaps are behavioral. They are concentrated in cold-start activation recovery, unpackaged registration failure handling, WinAppSDK bootstrap behavior, and sample-side communication of unsupported operations.

---

## Findings

### High

#### H-1: Cold-start fallback defined by v3 is not fully implemented

- Design expectation:
  - Task 0 fixes policy B and requires `-ToastActivated` startup argument fallback so an unpackaged app can recover activation data even when COM callback timing is unreliable during cold start.
- Implementation status:
  - `WindowsClassicActivator.cpp` detects `-ToastActivated` and logs a wait path, but it does not reconstruct callback payload from startup arguments and does not forward restored activation data into the manager callback path.
- Impact:
  - The most important unpackaged reliability requirement in v3 remains open. A user click that launches the app from a terminated state can still miss the notification callback contract expected by the design.

### Medium

#### M-1: Classic registration prerequisite failures are warnings, not initialization failures

- Design expectation:
  - Shortcut creation and registry registration are functional prerequisites for classic unpackaged delivery and should fail initialization with `NOTIFICATION_ERROR_HRESULT_FAILURE(5)` when they cannot be established.
- Implementation status:
  - `WindowsClassicActivator.cpp` logs warnings and continues when shortcut creation or registry registration fails.
- Impact:
  - The manager can report successful initialization while required classic delivery prerequisites are absent. This leaves the caller in a partially initialized state that is hard to diagnose.

#### M-2: Unpackaged `initWinAppSdk()` behavior still diverges from v3

- Design expectation:
  - v3 explicitly requires unpackaged bootstrap to skip `DeploymentManager::Initialize()` and rely only on `MddBootstrapInitialize`, because package-identity-dependent deployment initialization is not a valid runtime precondition for unpackaged apps.
- Implementation status:
  - `WindowsAppSdkBootstrap.cpp` still calls `DeploymentManager::Initialize()` and handles the no-package case after the fact.
- Impact:
  - The implementation still depends on the exception-filtering path the design intended to remove, and it keeps the risk of rejecting valid unpackaged environments for the wrong reason.

#### M-3: Sample-side unsupported-operation guidance is still generic

- Design expectation:
  - For unpackaged apps, `removeNotificationById` and `getAllNotifications` should surface `NOTIFICATION_ERROR_NOT_SUPPORTED(8)` as an explicit unsupported-state message so users understand the limitation and the intended alternative.
- Implementation status:
  - The packaged WinUI sample reports generic failures.
  - The actual Unity sample controller at `C:\Users\User\Desktop\unity-native-plugin\Packages\com.jonghyunkim.nativetoolkit\Runtime\UI\Windows\Notification\WindowsNotificationManagerExampleController.cs` is not unhandled, but it also formats failures generically through `FormatResult(...)` and does not branch on `NOT_SUPPORTED(8)`.
- Impact:
  - The previous interpretation of the Unity sample as "missing handling" was too strong. The corrected issue is narrower: unsupported operations are surfaced, but not explained. That means the API contract exists, while the user-facing guidance required by v3 is still incomplete.

### Low

#### L-1: Public API comments still describe failure codes as `1-7`

- Design expectation:
  - Public API documentation should reflect the addition of `NOTIFICATION_ERROR_NOT_SUPPORTED(8)`.
- Implementation status:
  - `WindowsNotificationManager.h` still contains comments describing failures as `1-7` in several APIs.
- Impact:
  - Callers reading the header can get outdated error-contract information.

#### L-2: v3 compatibility section still mentions `pError==7` for unsupported sample behavior

- Design expectation:
  - v3 standardized unsupported operations on `NOTIFICATION_ERROR_NOT_SUPPORTED(8)`.
- Documentation status:
  - The compatibility section in the design document still says the Unity sample handles `pError==7` for unsupported operations.
- Impact:
  - The design document contains an internal inconsistency between the standardized error code and the sample guidance.

---

## Confirmed Implemented Items

- Backend separation via `INotificationBackend` is present.
- `NOTIFICATION_ERROR_NOT_SUPPORTED(8)` exists in the public contract.
- Unpackaged backend returns not-supported for unsupported operations such as `RemoveById` and `GetAll`.
- Test seams such as backend injection and callback-safety coverage are present.

These points reduce the scope of remaining work. The architecture is not missing; the unresolved work is concentrated in a small number of behavioral and documentation gaps.

---

## Overall Assessment

Status: **Needs targeted follow-up fixes**

The implementation already reflects the main v3 restructuring, so this is no longer a broad redesign problem. The required follow-up is localized:

1. Finish cold-start fallback behavior for unpackaged activation.
2. Convert classic registration prerequisite failures into hard init failures.
3. Align unpackaged WinAppSDK bootstrap with the documented v3 policy.
4. Update sample messaging and public/docs comments for `NOT_SUPPORTED(8)`.