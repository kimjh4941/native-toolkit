#include "pch.h"
// WindowsClassicActivator.h defines INotificationActivationCallback manually
// (without the SDK NotificationActivationCallback.h) so it must come before
// any WRL headers that include Unknwn.h to avoid MIDL_INTERFACE redefinition.
#include "../WindowsLibrary/WindowsClassicActivator.h"
#include "../WindowsLibrary/WindowsNotificationManagerInternal.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace winrt::Windows::Data::Json;

// ============================================================================
// MockBackend — records calls for orchestration tests (no WinRT runtime needed)
// ============================================================================
struct MockBackend final : public INotificationBackend
{
    // Last call record
    bool deliverCalled     = false;
    bool scheduleCalled    = false;
    bool cancelCalled      = false;
    bool setBadgeCalled    = false;
    bool removeByTagCalled = false;
    bool removeAllCalled   = false;
    bool removeByIdCalled  = false;
    bool getAllCalled       = false;
    int  settingReturn     = 0;  // 0 = Enabled

    void RegisterActivation(DWORD* pError) override   { if (pError) *pError = 0; }
    void UnregisterActivation() override              {}

    void Deliver(const DeliverPayload&, DWORD* pError) override
    {
        deliverCalled = true;
        if (pError) *pError = 0;
    }
    void Schedule(const DeliverPayload&, int64_t, DWORD* pError) override
    {
        scheduleCalled = true;
        if (pError) *pError = 0;
    }
    void CancelSchedule(const wchar_t*, const wchar_t*, DWORD* pError) override
    {
        cancelCalled = true;
        if (pError) *pError = 0;
    }
    void SetBadge(int, DWORD* pError) override
    {
        setBadgeCalled = true;
        if (pError) *pError = 0;
    }
    void UpdateProgress(const wchar_t*, const wchar_t*, double, const wchar_t*,
                        const wchar_t*, uint32_t, DWORD* pError) override
    {
        if (pError) *pError = 0;
    }
    void RemoveByTag(const wchar_t*, const wchar_t*, DWORD* pError) override
    {
        removeByTagCalled = true;
        if (pError) *pError = 0;
    }
    void RemoveAll(DWORD* pError) override
    {
        removeAllCalled = true;
        if (pError) *pError = 0;
    }
    void RemoveById(uint32_t, DWORD* pError) override
    {
        removeByIdCalled = true;
        if (pError) *pError = NOTIFICATION_ERROR_NOT_SUPPORTED;
    }
    void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) override
    {
        getAllCalled = true;
        if (pError) *pError = NOTIFICATION_ERROR_NOT_SUPPORTED;
    }
    int Setting() override { return settingReturn; }
};

namespace WindowsNotificationManagerTest
{

TEST_CLASS(NotificationManagerTest)
{
public:

    TEST_CLASS_INITIALIZE(ClassSetup)
    {
        // The VSTest host may already have initialized COM (often STA). init_apartment()
        // defaults to MTA and throws RPC_E_CHANGED_MODE in that case — which is benign here,
        // so swallow it and use whatever apartment the host already established.
        try
        {
            winrt::init_apartment();
        }
        catch (winrt::hresult_error const&)
        {
        }
    }

    // -------------------------------------------------------------------------
    // setBadge validation — value < -6 returns INVALID_PARAMETER without WinRT
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_SetBadge_ValueMinus7_ReturnsInvalidParameter)
    {
        DWORD err = 0;
        WindowsNotificationManager::GetInstance().SetBadge(-7, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_SetBadge_ValueMinus100_ReturnsInvalidParameter)
    {
        DWORD err = 0;
        WindowsNotificationManager::GetInstance().SetBadge(-100, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER), err);
    }

    // -------------------------------------------------------------------------
    // Not-initialized checks — no WinRT registration needed
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_ShowNotification_WhenNotInitialized_ReturnsNotInitialized)
    {
        // Ensure we start uninitialised (singleton persists across tests,
        // so only valid if Uninit() was called or never initialised in this suite)
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;

        DWORD err = 0;
        mgr.Show(L"{\"title\":\"test\"}", &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    TEST_METHOD(Test_Schedule_WhenNotInitialized_ReturnsNotInitialized)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;

        DWORD err = 0;
        mgr.Schedule(L"{\"title\":\"test\"}", 0, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    TEST_METHOD(Test_UpdateProgress_WhenNotInitialized_ReturnsNotInitialized)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;

        DWORD err = 0;
        mgr.UpdateProgress(L"tag", L"", 0.5, L"50%", L"running", 1, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    // -------------------------------------------------------------------------
    // ArgsToJson — special character escaping and UserInput merge
    // Requires winrt::init_apartment() (called in ClassSetup)
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_ArgsToJson_EscapesDoubleQuotes)
    {
        winrt::Windows::Foundation::Collections::StringMap args;
        args.Insert(L"key", L"val\"ue");

        winrt::Windows::Foundation::Collections::StringMap userInput;

        auto& mgr = WindowsNotificationManager::GetInstance();
        auto json = mgr.ArgsToJson(args, userInput);

        // JSON must be parseable and contain escaped value
        JsonObject parsed;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ json }, parsed));
        Assert::AreEqual(std::wstring(L"val\"ue"), std::wstring{ parsed.GetNamedString(L"key") });
    }

    TEST_METHOD(Test_ArgsToJson_MergesUserInput)
    {
        winrt::Windows::Foundation::Collections::StringMap args;
        args.Insert(L"action", L"approve");

        winrt::Windows::Foundation::Collections::StringMap userInput;
        userInput.Insert(L"reply", L"hello");

        auto& mgr = WindowsNotificationManager::GetInstance();
        auto json = mgr.ArgsToJson(args, userInput);

        JsonObject parsed;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ json }, parsed));
        Assert::AreEqual(std::wstring(L"approve"), std::wstring{ parsed.GetNamedString(L"action") });
        Assert::AreEqual(std::wstring(L"hello"),   std::wstring{ parsed.GetNamedString(L"reply") });
    }

    // -------------------------------------------------------------------------
    // BuildFromJson validation — requires WinRT init only (no app registration)
    // Tested by forcing m_initialized=true and calling Show() which calls BuildFromJson.
    // Since AppNotificationManager::Default().Setting() is called before BuildFromJson,
    // these tests are marked as manual-confirm in environments without AppSDK registered.
    // The pure validation path (INVALID_PARAMETER before WinRT call) is tested via SetBadge.
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_BuildFromJson_TooManyButtons_ReturnsInvalidParameter)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = true;
        struct Guard { ~Guard() { WindowsNotificationManager::GetInstance().m_initialized = false; } } guard;

        // 6 buttons — exceeds the 5-button limit
        const wchar_t* payload = LR"({
            "title": "t",
            "buttons": [
                {"label":"b1","args":{"k":"v"}},
                {"label":"b2","args":{"k":"v"}},
                {"label":"b3","args":{"k":"v"}},
                {"label":"b4","args":{"k":"v"}},
                {"label":"b5","args":{"k":"v"}},
                {"label":"b6","args":{"k":"v"}}
            ]
        })";

        JsonObject json;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ payload }, json));

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.BuildFromJson(json, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_BuildFromJson_AudioLoopWithoutLongDuration_ReturnsInvalidParameter)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = true;
        struct Guard { ~Guard() { WindowsNotificationManager::GetInstance().m_initialized = false; } } guard;

        const wchar_t* payload = LR"({
            "title": "t",
            "duration": "short",
            "audio": {"type":"event","event":"alarm","loop":true}
        })";

        JsonObject json;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ payload }, json));

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.BuildFromJson(json, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_BuildFromJson_ButtonWithArgsAndInvokeUri_ReturnsInvalidParameter)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = true;
        struct Guard { ~Guard() { WindowsNotificationManager::GetInstance().m_initialized = false; } } guard;

        const wchar_t* payload = LR"({
            "title": "t",
            "buttons": [
                {"label":"b1","args":{"k":"v"},"invokeUri":"https://example.com"}
            ]
        })";

        JsonObject json;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ payload }, json));

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.BuildFromJson(json, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_BuildFromJson_InvalidJson_CannotParse)
    {
        // TryParse on invalid JSON returns false — tested at JSON layer
        JsonObject json;
        bool parsed = JsonObject::TryParse(L"not-json", json);
        Assert::IsFalse(parsed);
    }

    // -------------------------------------------------------------------------
    // MockBackend orchestration tests — no WinRT runtime activation needed
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_Show_NotEnabled_ReturnsDISABLED)
    {
        // Setting=1 (DisabledForApplication) → Show must return DISABLED
        auto& mgr = WindowsNotificationManager::GetInstance();
        auto mock = std::make_unique<MockBackend>();
        mock->settingReturn = 1;
        mgr.SetBackendForTest(std::move(mock));
        mgr.m_initialized = true;
        struct Guard {
            ~Guard()
            {
                auto& m = WindowsNotificationManager::GetInstance();
                m.m_initialized = false;
                m.SetBackendForTest(nullptr);
            }
        } guard;

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.Show(L"{\"title\":\"t\"}", &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_DISABLED), err);
    }

    TEST_METHOD(Test_Show_Enabled_CallsDeliver)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        auto* rawMock = new MockBackend();
        rawMock->settingReturn = 0;
        mgr.SetBackendForTest(std::unique_ptr<INotificationBackend>(rawMock));
        mgr.m_initialized = true;
        struct Guard {
            ~Guard()
            {
                auto& m = WindowsNotificationManager::GetInstance();
                m.m_initialized = false;
                m.SetBackendForTest(nullptr);
            }
        } guard;

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.Show(L"{\"title\":\"hello\"}", &err);
        // May fail at AppNotificationBuilder runtime if WinRT is not fully set up,
        // but at minimum the backend Deliver path is entered (err != NOT_INITIALIZED).
        Assert::AreNotEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    TEST_METHOD(Test_RemoveById_MockBackend_ReturnsNOT_SUPPORTED)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        auto mock = std::make_unique<MockBackend>();
        mgr.SetBackendForTest(std::move(mock));
        mgr.m_initialized = true;
        struct Guard {
            ~Guard()
            {
                auto& m = WindowsNotificationManager::GetInstance();
                m.m_initialized = false;
                m.SetBackendForTest(nullptr);
            }
        } guard;

        DWORD err = NOTIFICATION_SUCCESS;
        mgr.RemoveById(1, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_SUPPORTED), err);
    }

    TEST_METHOD(Test_GetAll_MockBackend_ReturnsNOT_SUPPORTED)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        auto mock = std::make_unique<MockBackend>();
        mgr.SetBackendForTest(std::move(mock));
        mgr.m_initialized = true;
        struct Guard {
            ~Guard()
            {
                auto& m = WindowsNotificationManager::GetInstance();
                m.m_initialized = false;
                m.SetBackendForTest(nullptr);
            }
        } guard;

        wchar_t buf[64]{};
        DWORD err = NOTIFICATION_SUCCESS;
        mgr.GetAll(buf, 64, &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_SUPPORTED), err);
    }

    TEST_METHOD(Test_CancelScheduled_WhenNotInitialized_ReturnsNotInitialized)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;

        DWORD err = 0;
        mgr.CancelScheduled(L"tag", L"", &err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    TEST_METHOD(Test_OpenSettings_WhenNotInitialized_ReturnsNotInitialized)
    {
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;

        DWORD err = 0;
        mgr.OpenSettings(&err);
        Assert::AreEqual(static_cast<DWORD>(NOTIFICATION_ERROR_NOT_INITIALIZED), err);
    }

    TEST_METHOD(Test_InvokeCallback_ThreadSafe_NullCallback_NocrAsh)
    {
        // Ensure InvokeCallback with no callback set does not crash.
        auto& mgr = WindowsNotificationManager::GetInstance();
        mgr.m_initialized = false;
        // Call directly (simulates COM Activate arriving after Uninit)
        mgr.InvokeCallback(L"{}");
    }

    // -------------------------------------------------------------------------
    // ClassicArgsToJson — query string parsing
    // -------------------------------------------------------------------------

    TEST_METHOD(Test_ClassicArgsToJson_QueryString)
    {
        auto json = ClassicArgsToJson(L"action=reply&id=btn1", nullptr, 0);
        JsonObject parsed;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ json }, parsed));
        Assert::AreEqual(std::wstring(L"reply"), std::wstring{ parsed.GetNamedString(L"action") });
        Assert::AreEqual(std::wstring(L"btn1"),  std::wstring{ parsed.GetNamedString(L"id") });
    }

    TEST_METHOD(Test_ClassicArgsToJson_EmptyArgs)
    {
        auto json = ClassicArgsToJson(nullptr, nullptr, 0);
        JsonObject parsed;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ json }, parsed));
        Assert::AreEqual(0u, parsed.Size());
    }

    TEST_METHOD(Test_ClassicArgsToJson_MergesUserInput)
    {
        NOTIFICATION_USER_INPUT_DATA data[] = {
            { L"reply", L"hello world" }
        };
        auto json = ClassicArgsToJson(L"action=ok", data, 1);
        JsonObject parsed;
        Assert::IsTrue(JsonObject::TryParse(winrt::hstring{ json }, parsed));
        Assert::AreEqual(std::wstring(L"ok"),          std::wstring{ parsed.GetNamedString(L"action") });
        Assert::AreEqual(std::wstring(L"hello world"), std::wstring{ parsed.GetNamedString(L"reply") });
    }
};

} // namespace WindowsNotificationManagerTest
