#include "pch.h"
#include "Notification/WindowsNotificationManager.h"
#include "Notification/WindowsNotificationManagerInternal.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// The C ABI of the Notification feature, now that it sits on the C++ API
// (T-14).
//
// The unit tests around it check the C++ API and the manager; neither runs a
// line of the bridge. What the bridge now owns by itself is the answer to a
// call made before anything was initialised: it used to fall through to the
// manager, which reported NOT_INITIALIZED, and it now answers without asking.
// The value a C caller reads has to be the same one, which is the review
// point T-14 was given - "is pError still what it was".
//
// Everything past initialisation needs Manager::Create, which registers this
// process with the OS and cannot be done from a test host; the sample app's
// UI tests cover it against the recorded baseline (T-15).
// ============================================================================

namespace WindowsNotificationBridgeTest
{

TEST_CLASS(NotificationBridgeTest)
{
public:

    TEST_METHOD_INITIALIZE(StartFromNothing)
    {
        // Another suite may have left the manager marked initialised; the
        // bridge holds no manager either way, which is the state under test.
        WindowsNotificationManager::GetInstance().Uninit();
    }

    TEST_METHOD(Test_BeforeInit_EveryCallReportsNotInitialized)
    {
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { cancelScheduledNotification(L"t", L"g", e); }),
                         L"cancelScheduledNotification");
        Assert::AreEqual(Expected(), Answer([](DWORD* e) {
                             updateNotificationProgress(L"t", L"g", 0.5, L"50%", L"s", 1, e); }),
                         L"updateNotificationProgress");
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { removeNotificationById(1, e); }),
                         L"removeNotificationById");
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { removeNotificationsByTag(L"t", L"g", e); }),
                         L"removeNotificationsByTag");
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { removeAllNotifications(e); }),
                         L"removeAllNotifications");
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { openNotificationSettings(e); }),
                         L"openNotificationSettings");
    }

    TEST_METHOD(Test_BeforeInit_GetAllStillAsksTheManager)
    {
        // getAllNotifications is deliberately still on the manager, so it
        // answers the same way it always has.
        wchar_t buffer[8] = {};
        Assert::AreEqual(Expected(), Answer([&](DWORD* e) { getAllNotifications(buffer, 8, e); }));
    }

    TEST_METHOD(Test_BeforeInit_TheSettingIsMinusOne)
    {
        // Not an error code: -1 has always meant "could not ask" here, and it
        // shares no space with NOTIFICATION_ERROR_*.
        Assert::AreEqual(-1, getNotificationSetting());
    }

    TEST_METHOD(Test_BeforeInit_ABadBadgeValueIsStillInvalidParameter)
    {
        // The range check comes before the initialisation check (NTF-65), so
        // this one answers InvalidParameter rather than NotInitialized even
        // with nothing set up.
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER,
                                Answer([](DWORD* e) { setBadge(-7, e); }));
        Assert::AreEqual(Expected(), Answer([](DWORD* e) { setBadge(3, e); }),
                         L"a badge in range with nothing initialised");
    }

    TEST_METHOD(Test_UninitBeforeInit_DoesNothingAndDoesNotFault)
    {
        uninitNotificationManager();
        uninitNotificationManager();
    }

private:

    static DWORD Expected() { return NOTIFICATION_ERROR_NOT_INITIALIZED; }

    template <class Call>
    static DWORD Answer(Call call)
    {
        DWORD error = 0xFFFFFFFFu;
        call(&error);
        return error;
    }
};

}  // namespace WindowsNotificationBridgeTest
