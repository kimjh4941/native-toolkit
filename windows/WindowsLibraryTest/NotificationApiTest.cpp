#include "pch.h"
#include "Notification/Data/WindowsClassicActivator.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Notification/WindowsNotificationApiInternal.h"
#include "Notification/Data/WindowsNotificationActivation.h"
#include "AppSdkRuntimeForTest.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// U-F of the stage 3 design, for the notification C++ API (OP-08..OP-20).
//
// The fourteen operations are meant to be the same operations the C ABI
// exposes, described in types instead of in pointers and DWORDs. What is worth
// testing is therefore not that they work - the code underneath is unchanged
// and already covered - but that nothing is lost or changed in the translation:
// that each one reaches the backend, that a raw DWORD becomes the matching
// case, and that the places where the C++ API deliberately differs (a second
// manager, GetSetting's -1, the activation dictionary) differ in the way the
// design says.
//
// Manager::Create registers this process with the OS, which a test host cannot
// do, so the manager comes from Detail::TestAccess and the backend is a mock -
// the same arrangement NotificationManagerTest uses for the C ABI.
// ============================================================================

namespace WindowsNotificationApiTest
{

namespace Api = NativeToolkit::Notification;
using Api::ErrorCode;

namespace
{
    /// Records what reached the backend. Kept separate from the one in
    /// NotificationManagerTest so the two tests cannot disturb each other.
    struct RecordingBackend final : public INotificationBackend
    {
        DeliverPayload lastPayload;
        std::wstring   lastTag;
        std::wstring   lastGroup;
        int64_t        lastScheduledMs = 0;
        int            lastBadge       = 0;
        uint32_t       lastId          = 0;
        double         lastProgressValue = 0.0;
        uint32_t       lastSequence    = 0;
        std::wstring   allJson         = L"[]";

        bool delivered   = false;
        bool scheduled   = false;
        bool canceled    = false;
        bool badgeSet    = false;
        bool progressed  = false;
        bool removedById = false;
        bool removedByTag = false;
        bool removedAll  = false;
        bool listed      = false;
        bool unregistered = false;

        int   settingReturn = 0;
        DWORD nextError     = NOTIFICATION_SUCCESS;

        void RegisterActivation(DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void UnregisterActivation() override            { unregistered = true; }

        void Deliver(const DeliverPayload& payload, DWORD* pError) override
        {
            delivered = true;
            lastPayload = payload;
            if (pError) *pError = nextError;
        }
        void Schedule(const DeliverPayload& payload, int64_t whenMs, DWORD* pError) override
        {
            scheduled = true;
            lastPayload = payload;
            lastScheduledMs = whenMs;
            if (pError) *pError = nextError;
        }
        void CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError) override
        {
            canceled = true;
            lastTag = tag ? tag : L"";
            lastGroup = group ? group : L"";
            if (pError) *pError = nextError;
        }
        void SetBadge(int value, DWORD* pError) override
        {
            badgeSet = true;
            lastBadge = value;
            if (pError) *pError = nextError;
        }
        void UpdateProgress(const wchar_t* tag, const wchar_t* group, double value,
                            const wchar_t* valueStr, const wchar_t* status,
                            uint32_t seq, DWORD* pError) override
        {
            progressed = true;
            lastTag = tag ? tag : L"";
            lastGroup = group ? group : L"";
            lastProgressValue = value;
            lastSequence = seq;
            (void)valueStr;
            (void)status;
            if (pError) *pError = nextError;
        }
        void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError) override
        {
            removedByTag = true;
            lastTag = tag ? tag : L"";
            lastGroup = group ? group : L"";
            if (pError) *pError = nextError;
        }
        void RemoveAll(DWORD* pError) override
        {
            removedAll = true;
            if (pError) *pError = nextError;
        }
        void RemoveById(uint32_t id, DWORD* pError) override
        {
            removedById = true;
            lastId = id;
            if (pError) *pError = nextError;
        }
        void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) override
        {
            listed = true;
            if (nextError == NOTIFICATION_SUCCESS) {
                wcsncpy_s(outJson, bufferSize, allJson.c_str(), _TRUNCATE);
            }
            if (pError) *pError = nextError;
        }
        int Setting() override { return settingReturn; }
    };
}

TEST_CLASS(NotificationApiTest)
{
public:

    TEST_CLASS_INITIALIZE(ClassSetup)
    {
        // The VSTest host may already hold an apartment; whichever it is, use it.
        try { winrt::init_apartment(); } catch (winrt::hresult_error const&) {}

        // Show and Schedule build the toast before they hand it to the
        // backend, and building one activates App SDK types.
        const std::wstring& failure = AppSdkRuntimeForTest::Ensure();
        if (!failure.empty()) {
            Assert::Fail(failure.c_str());
        }
    }

    TEST_METHOD_CLEANUP(ReleaseTheProcess)
    {
        // Every test takes the one manager this process may have, so give it
        // back even when an assertion left early.
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.m_initialized = false;
        backing.SetBackendForTest(nullptr);
    }

    // --- Lifetime -----------------------------------------------------------

    TEST_METHOD(Test_SecondManager_IsRefused)
    {
        // Windows registers one activation handler per process, so a second
        // manager is told so rather than quietly replacing the first.
        auto first = Open();

        const auto second = Api::Manager::Create(Api::ManagerOptions{});

        Assert::IsFalse(second.has_value());
        Assert::IsTrue(ErrorCode::NotSupported == second.error().code);
    }

    TEST_METHOD(Test_AfterClose_AnotherManagerCanBeCreated)
    {
        InstallBackend();
        {
            auto first = Open();
            first.Close();
        }
        // Close released the one slot a process has, so a manager can be had
        // again and works. Create itself is not used here because it would
        // register with the OS.
        InstallBackend();
        auto again = Open();
        Assert::IsTrue(again.Show(Simple()).has_value());
    }

    TEST_METHOD(Test_Close_IsIdempotentAndUnregisters)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        manager.Close();
        Assert::IsTrue(backend->unregistered);

        manager.Close();  // must not fault, must not unregister a second time
    }

    TEST_METHOD(Test_MovedFromManager_DoesNotClose)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        {
            Api::Manager moved = std::move(manager);
            Assert::IsFalse(backend->unregistered);
        }
        // The move destination closed at the end of the scope; the source must
        // not close again when it is destroyed.
        Assert::IsTrue(backend->unregistered);
    }

    // --- Delivery -----------------------------------------------------------

    TEST_METHOD(Test_Show_ReachesTheBackendWithTheBuiltPayload)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        Api::NotificationContent content = Simple();
        content.tag   = L"job";
        content.group = L"builds";

        Assert::IsTrue(manager.Show(content).has_value());
        Assert::IsTrue(backend->delivered);
        Assert::AreEqual(std::wstring(L"job"), backend->lastPayload.tag);
        Assert::AreEqual(std::wstring(L"builds"), backend->lastPayload.group);
        Assert::IsTrue(backend->lastPayload.xmlPayload.find(L"<toast") != std::wstring::npos);
    }

    TEST_METHOD(Test_Show_CarriesExpirationAndProgressMetadata)
    {
        // These do not live in the XML, so they have to be copied across
        // separately - exactly as the JSON path copies them from its keys.
        auto* backend = InstallBackend();
        auto manager = Open();

        Api::NotificationContent content = Simple();
        content.expiration      = std::chrono::seconds{600};
        content.expiresOnReboot = true;
        Api::ProgressSpec progress;
        progress.value    = 0.25;
        progress.valueStr = L"25%";
        progress.status   = L"Working";
        content.progress  = progress;

        Assert::IsTrue(manager.Show(content).has_value());
        Assert::IsTrue(backend->lastPayload.hasExpiration);
        Assert::AreEqual<int64_t>(600, backend->lastPayload.expirationSec);
        Assert::IsTrue(backend->lastPayload.expiresOnReboot);
        Assert::IsTrue(backend->lastPayload.hasProgress);
        Assert::AreEqual(0.25, backend->lastPayload.progressValue, 0.0001);
        Assert::AreEqual(std::wstring(L"25%"), backend->lastPayload.progressValueStr);
        Assert::AreEqual(std::wstring(L"Working"), backend->lastPayload.progressStatus);
    }

    TEST_METHOD(Test_Show_WhenNotificationsAreOff_ReportsDisabled)
    {
        auto* backend = InstallBackend();
        backend->settingReturn = 2;  // DisabledForUser
        auto manager = Open();

        const auto result = manager.Show(Simple());

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::Disabled == result.error().code);
        Assert::IsFalse(backend->delivered);
    }

    TEST_METHOD(Test_Show_WhenTheContentBreaksARule_ReportsInvalidParameter)
    {
        // A looping sound needs a long duration. The C ABI answers this with
        // INVALID_PARAMETER, so the C++ API answers with the matching case and
        // not with InvalidPayload, which is what a malformed JSON string gets.
        auto* backend = InstallBackend();
        auto manager = Open();

        Api::NotificationContent content = Simple();
        content.audio = Api::AudioSpec{};
        content.audio->loop = true;

        const auto result = manager.Show(content);

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::InvalidParameter == result.error().code);
        Assert::IsFalse(backend->delivered);
    }

    TEST_METHOD(Test_Show_WhenDisabledAndInvalid_StillReportsDisabled)
    {
        // The order of the two checks is observable, and it is the order the
        // JSON path already has.
        auto* backend = InstallBackend();
        backend->settingReturn = 1;
        auto manager = Open();

        Api::NotificationContent content = Simple();
        content.audio = Api::AudioSpec{};
        content.audio->loop = true;

        Assert::IsTrue(ErrorCode::Disabled == manager.Show(content).error().code);
    }

    TEST_METHOD(Test_Schedule_PassesTheTimeAsUnixMilliseconds)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        const auto when = std::chrono::system_clock::from_time_t(1700000000);

        Assert::IsTrue(manager.Schedule(Simple(), when).has_value());
        Assert::IsTrue(backend->scheduled);
        Assert::AreEqual<int64_t>(1700000000LL * 1000, backend->lastScheduledMs);
    }

    TEST_METHOD(Test_CancelScheduled_PassesTagAndGroup)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        Assert::IsTrue(manager.CancelScheduled(L"job", L"builds").has_value());
        Assert::IsTrue(backend->canceled);
        Assert::AreEqual(std::wstring(L"job"), backend->lastTag);
        Assert::AreEqual(std::wstring(L"builds"), backend->lastGroup);
    }

    TEST_METHOD(Test_UpdateProgress_PassesTheSequenceNumberTheCallerChose)
    {
        // NTF-44: the OS rejects a stale one, and the C++ API does not start
        // generating them on the caller's behalf.
        auto* backend = InstallBackend();
        auto manager = Open();

        Api::ProgressUpdate update;
        update.tag            = L"job";
        update.group          = L"builds";
        update.value          = 0.5;
        update.valueString    = L"50%";
        update.status         = L"Halfway";
        update.sequenceNumber = 7;

        Assert::IsTrue(manager.UpdateProgress(update).has_value());
        Assert::IsTrue(backend->progressed);
        Assert::AreEqual(0.5, backend->lastProgressValue, 0.0001);
        Assert::AreEqual<uint32_t>(7, backend->lastSequence);
    }

    // --- The action centre --------------------------------------------------

    TEST_METHOD(Test_SetBadge_PassesTheValue)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        Assert::IsTrue(manager.SetBadge(3).has_value());
        Assert::AreEqual(3, backend->lastBadge);
    }

    TEST_METHOD(Test_SetBadge_BelowTheGlyphRange_IsRejectedBeforeTheBackend)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        const auto result = manager.SetBadge(-7);

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::InvalidParameter == result.error().code);
        Assert::IsFalse(backend->badgeSet);
    }

    TEST_METHOD(Test_RemoveById_PassesTheId)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        Assert::IsTrue(manager.RemoveById(42).has_value());
        Assert::AreEqual<uint32_t>(42, backend->lastId);
    }

    TEST_METHOD(Test_RemoveByTag_And_RemoveAll_ReachTheBackend)
    {
        auto* backend = InstallBackend();
        auto manager = Open();

        Assert::IsTrue(manager.RemoveByTag(L"job", L"builds").has_value());
        Assert::IsTrue(backend->removedByTag);

        Assert::IsTrue(manager.RemoveAll().has_value());
        Assert::IsTrue(backend->removedAll);
    }

    TEST_METHOD(Test_GetAll_ReturnsTheListInsteadOfJsonInABuffer)
    {
        auto* backend = InstallBackend();
        backend->allJson =
            LR"([{"id":1,"tag":"a","group":"g"},{"id":2,"tag":"b","group":""}])";
        auto manager = Open();

        const auto result = manager.GetAll();

        Assert::IsTrue(result.has_value());
        Assert::AreEqual<size_t>(2, result.value().size());
        Assert::AreEqual<uint32_t>(1, result.value()[0].id);
        Assert::AreEqual(std::wstring(L"a"), result.value()[0].tag);
        Assert::AreEqual(std::wstring(L"g"), result.value()[0].group);
        Assert::AreEqual<uint32_t>(2, result.value()[1].id);
        Assert::AreEqual(std::wstring(L""), result.value()[1].group);
    }

    TEST_METHOD(Test_GetAll_EmptyListIsNotAFailure)
    {
        auto* backend = InstallBackend();
        backend->allJson = L"[]";
        auto manager = Open();

        const auto result = manager.GetAll();

        Assert::IsTrue(result.has_value());
        Assert::AreEqual<size_t>(0, result.value().size());
    }

    TEST_METHOD(Test_GetAll_WhenTheAppTypeCannotListThem_ReportsNotSupported)
    {
        auto* backend = InstallBackend();
        backend->nextError = NOTIFICATION_ERROR_NOT_SUPPORTED;
        auto manager = Open();

        const auto result = manager.GetAll();

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::NotSupported == result.error().code);
    }

    // --- Settings -----------------------------------------------------------

    TEST_METHOD(Test_GetSetting_ReturnsTheNamedCase)
    {
        auto* backend = InstallBackend();
        backend->settingReturn = 3;
        auto manager = Open();

        const auto result = manager.GetSetting();

        Assert::IsTrue(result.has_value());
        Assert::IsTrue(Api::NotificationSetting::DisabledByGroupPolicy == result.value());
    }

    TEST_METHOD(Test_GetSetting_WhenItCannotBeAsked_IsAFailureRatherThanMinusOne)
    {
        // The C ABI packs "could not ask" into the same int as the answer.
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.SetBackendForTest(nullptr);
        backing.m_initialized = false;
        auto manager = Api::Detail::TestAccess::MakeManager();

        const auto result = manager.GetSetting();

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::HResultFailure == result.error().code);
    }

    // --- Not initialised ----------------------------------------------------

    TEST_METHOD(Test_AfterClose_OperationsReportNotInitialized)
    {
        InstallBackend();
        auto manager = Open();
        manager.Close();

        const auto result = manager.Show(Simple());

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::NotInitialized == result.error().code);
    }

    // --- Activation ---------------------------------------------------------

    TEST_METHOD(Test_TheHandlerReceivesTheMergedDictionary)
    {
        InstallBackend();
        auto manager = Open();

        Api::ActivationArgs received;
        bool called = false;
        manager.SetInvokedHandler([&](const Api::ActivationArgs& args) {
            received = args;
            called = true;
        });

        WindowsNotificationManager::GetInstance().InvokeCallback(
            LR"({"action":"open","reply":"hello"})");

        Assert::IsTrue(called);
        Assert::AreEqual<size_t>(2, received.values.size());
        Assert::AreEqual(std::wstring(L"open"), Lookup(received, L"action"));
        Assert::AreEqual(std::wstring(L"hello"), Lookup(received, L"reply"));
        Assert::IsFalse(received.rawArguments.empty());
    }

    TEST_METHOD(Test_ReplacingTheHandlerTakesEffect)
    {
        // What a second initNotificationManager does today (N-10).
        InstallBackend();
        auto manager = Open();

        int first = 0;
        int second = 0;
        manager.SetInvokedHandler([&](const Api::ActivationArgs&) { ++first; });
        manager.SetInvokedHandler([&](const Api::ActivationArgs&) { ++second; });

        WindowsNotificationManager::GetInstance().InvokeCallback(LR"({"action":"open"})");

        Assert::AreEqual(0, first);
        Assert::AreEqual(1, second);
    }

    TEST_METHOD(Test_AnActivationWithNoHandler_IsDropped)
    {
        InstallBackend();
        auto manager = Open();

        // No handler installed; this must not fault.
        WindowsNotificationManager::GetInstance().InvokeCallback(LR"({"action":"open"})");
    }

    TEST_METHOD(Test_ActivationTextThatIsNotAnObject_KeepsTheRawValue)
    {
        // Nothing the OS sent is thrown away, even when it cannot be split
        // into pairs.
        const auto args = Api::Data::ParseActivationJson(L"not json at all");

        Assert::AreEqual<size_t>(0, args.values.size());
        Assert::AreEqual(std::wstring(L"not json at all"), args.rawArguments);
    }

private:

    static Api::NotificationContent Simple()
    {
        Api::NotificationContent content;
        content.title = L"t";
        return content;
    }

    /// Installs a fresh backend and reports it. Ownership stays with the manager.
    static RecordingBackend* InstallBackend()
    {
        auto backend = std::make_unique<RecordingBackend>();
        auto* raw = backend.get();
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.SetBackendForTest(std::move(backend));
        backing.m_initialized = true;
        return raw;
    }

    /// A manager that behaves as one Create returned, minus the registration.
    static Api::Manager Open()
    {
        return Api::Detail::TestAccess::MakeManager();
    }

    static std::wstring Lookup(const Api::ActivationArgs& args, const std::wstring& key)
    {
        for (const auto& [name, value] : args.values) {
            if (name == key) return value;
        }
        return L"<missing>";
    }
};

}  // namespace WindowsNotificationApiTest
