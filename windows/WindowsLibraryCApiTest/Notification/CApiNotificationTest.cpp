#include "pch.h"

#include "NativeToolkitC/Notification.h"

#include "Notification/NotificationCApiInternal.h"
#include "Notification/NotificationConvert.h"
#include "Notification/NotificationRuntime.h"
#include "Notification/WindowsNotificationApiInternal.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace NativeToolkitC::Detail::Notification;

using NativeToolkit::Notification::Detail::TestAccess;

// ============================================================================
// The notification part of the C ABI without its content (stage 5 design,
// T-05): the runtime, the manager and its release (E-12), the operations,
// the list and the activation.
//
// Nothing here registers with the OS. The manager comes from a factory over
// TestAccess::MakeManager, activations are delivered with TestAccess::Activate,
// and the runtime's bootstrap is replaced with counters (CT-19). An operation
// on a live test manager would reach the OS, so the operations are exercised
// on the paths that return before it: their input checks, and a closed
// manager.
// ============================================================================

namespace CApiNotificationTest
{

namespace
{
    namespace Api = NativeToolkit::Notification;

    // -- What the factory does, and what it saw ------------------------------

    enum class FactoryMode { Succeed, Refuse, Throw };

    FactoryMode  g_mode = FactoryMode::Succeed;
    int          g_factoryCalls = 0;
    bool         g_sawPackaged = true;
    std::wstring g_sawName;
    std::wstring g_sawIcon;

    Api::Result<Api::Manager> TestFactory(const Api::ManagerOptions& options)
    {
        ++g_factoryCalls;
        g_sawPackaged = options.isPackaged;
        g_sawName = options.displayName;
        g_sawIcon = options.iconUri;
        switch (g_mode) {
        case FactoryMode::Refuse:
            return NativeToolkit::Unexpected{Api::Error{Api::ErrorCode::NotSupported, 0}};
        case FactoryMode::Throw:
            throw std::bad_alloc();
        default:
            break;
        }
        auto manager = TestAccess::MakeManager();
        manager.SetInvokedHandler(options.onInvoked);
        return manager;
    }

    // -- The runtime's bootstrap, counted (CT-19) ----------------------------

    int      g_initializeCalls = 0;
    int      g_shutdownCalls = 0;
    uint32_t g_initializeFailure = 0;   ///< Non-zero: initialize fails with this system code.

    ntk_notification_error CountingInitialize(uint32_t, uint32_t* systemCode)
    {
        ++g_initializeCalls;
        if (g_initializeFailure != 0) {
            *systemCode = g_initializeFailure;
            return NTK_NOTIFICATION_ERROR_HRESULT_FAILURE;
        }
        return NTK_NOTIFICATION_ERROR_NONE;
    }

    void CountingShutdown()
    {
        ++g_shutdownCalls;
    }

    constexpr RuntimeHooks kCountingHooks{&CountingInitialize, &CountingShutdown};

    // -- A caller's user_data: what its callbacks saw ------------------------

    struct Recorder {
        std::atomic<int>   invocations{0};
        std::atomic<int>   releases{0};
        std::atomic<DWORD> releaseThread{0};
        std::mutex         mutex;
        std::vector<std::string> events;   ///< "invoked" and "released", in order.
        std::string        lastRaw;
        std::vector<std::pair<std::string, std::string>> lastValues;

        void Add(const char* event)
        {
            std::lock_guard<std::mutex> lock(mutex);
            events.push_back(event);
        }
    };

    void NTK_CALL OnInvoked(void* userData, const ntk_notification_activation* activation)
    {
        auto* recorder = static_cast<Recorder*>(userData);
        recorder->lastRaw = ntk_notification_activation_raw_arguments(activation, nullptr);
        recorder->lastValues.clear();
        const size_t count = ntk_notification_activation_value_count(activation);
        for (size_t i = 0; i < count; ++i) {
            recorder->lastValues.emplace_back(ntk_notification_activation_key_at(activation, i, nullptr),
                                              ntk_notification_activation_value_at(activation, i, nullptr));
        }
        ++recorder->invocations;
        recorder->Add("invoked");
    }

    void NTK_CALL OnInvokedThrows(void* userData, const ntk_notification_activation*)
    {
        ++static_cast<Recorder*>(userData)->invocations;
        throw 42;
    }

    void NTK_CALL OnRelease(void* userData)
    {
        auto* recorder = static_cast<Recorder*>(userData);
        recorder->releaseThread = GetCurrentThreadId();
        ++recorder->releases;
        recorder->Add("released");
    }

    ntk_notification_manager_options Options(Recorder& recorder)
    {
        ntk_notification_manager_options options{};
        options.struct_size = static_cast<uint32_t>(sizeof(options));
        options.on_invoked = &OnInvoked;
        options.user_data = &recorder;
        options.release = &OnRelease;
        return options;
    }

    ntk_notification_manager* Create(Recorder& recorder)
    {
        auto options = Options(recorder);
        ntk_notification_manager* manager = nullptr;
        const auto result = ntk_notification_manager_create(&options, &manager);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, result);
        Assert::IsNotNull(manager);
        return manager;
    }

    // -- Holding a delivery between the copy of the handler and the call -----

    HANDLE g_deliveryHeld = nullptr;
    HANDLE g_deliveryGo = nullptr;

    void HoldDelivery()
    {
        SetEvent(g_deliveryHeld);
        WaitForSingleObject(g_deliveryGo, 10000);
    }

    /// A struct twice the size this version knows, the tail set to fill.
    template <class T>
    struct Grown {
        T             known;
        unsigned char tail[sizeof(T)];
    };

    template <class T>
    Grown<T> GrownFrom(const T& known, unsigned char fill)
    {
        Grown<T> grown{};
        grown.known = known;
        grown.known.struct_size = static_cast<uint32_t>(sizeof(grown));
        std::memset(grown.tail, fill, sizeof(grown.tail));
        return grown;
    }

    const std::string kInvalidUtf8 = "\xFF";
}

TEST_CLASS(CApiNotificationTest)
{
public:
    TEST_METHOD_INITIALIZE(SetUp)
    {
        g_mode = FactoryMode::Succeed;
        g_factoryCalls = 0;
        g_initializeCalls = 0;
        g_shutdownCalls = 0;
        g_initializeFailure = 0;
        SetManagerFactoryForTest(&TestFactory);
        SetRuntimeHooksForTest(&kCountingHooks);
        g_deliveryHeld = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        g_deliveryGo = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    }

    TEST_METHOD_CLEANUP(TearDown)
    {
        TestAccess::SetAfterHandlerCopy(nullptr);
        SetManagerFactoryForTest(nullptr);
        SetRuntimeHooksForTest(nullptr);
        CloseHandle(g_deliveryHeld);
        CloseHandle(g_deliveryGo);
    }

    // ------------------------------------------------------------------------
    // Creating the manager (OP-08)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Create_PassesTheOptionsToTheCppApi)
    {
        Recorder recorder;
        auto options = Options(recorder);
        options.is_unpackaged = 1;
        options.display_name = "App \xE2\x9C\x93";   // U+2713
        options.icon_uri = "C:\\icon.png";
        ntk_notification_manager* manager = nullptr;

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_manager_create(&options, &manager));
        Assert::IsFalse(g_sawPackaged);
        Assert::AreEqual(std::wstring(L"App ") + wchar_t(0x2713), g_sawName);
        Assert::AreEqual(std::wstring(L"C:\\icon.png"), g_sawIcon);
        Assert::AreEqual(0u, ntk_last_system_code());
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_Create_ZeroedOptionsArePackagedWithEmptyNames)
    {
        ntk_notification_manager_options options{};
        options.struct_size = static_cast<uint32_t>(sizeof(options));
        ntk_notification_manager* manager = nullptr;

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_manager_create(&options, &manager));
        Assert::IsTrue(g_sawPackaged);
        Assert::AreEqual(std::wstring(), g_sawName);
        Assert::AreEqual(std::wstring(), g_sawIcon);
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_Create_NullOptions_IsInvalidAndCallsNothing)
    {
        auto* sentinel = reinterpret_cast<ntk_notification_manager*>(1);
        ntk_notification_manager* manager = sentinel;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER,
                                  ntk_notification_manager_create(nullptr, &manager));
        Assert::IsNull(manager);
        Assert::AreEqual(0, g_factoryCalls);
    }

    TEST_METHOD(Test_Create_NullOutput_IsInvalidAndReleasesOnTheCallingThread)
    {
        Recorder recorder;
        auto options = Options(recorder);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER,
                                  ntk_notification_manager_create(&options, nullptr));
        Assert::AreEqual(1, recorder.releases.load());
        Assert::AreEqual(GetCurrentThreadId(), recorder.releaseThread.load());
        Assert::AreEqual(0, g_factoryCalls);
    }

    TEST_METHOD(Test_Create_MalformedOptions_AreRefusedAndReleasedWhenReadable)
    {
        struct Case {
            const wchar_t* name;
            void (*change)(ntk_notification_manager_options&);
            int32_t expected;
            int releases;
        };
        const Case cases[] = {
            {L"reserved0", [](ntk_notification_manager_options& o) { o.reserved0 = 1; }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 1},
            {L"reserved1", [](ntk_notification_manager_options& o) { o.reserved1 = 1; }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 1},
            {L"bad name", [](ntk_notification_manager_options& o) { o.display_name = kInvalidUtf8.c_str(); }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 1},
            {L"bad icon", [](ntk_notification_manager_options& o) { o.icon_uri = kInvalidUtf8.c_str(); }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 1},
            // Too small or too large: release cannot be trusted, so it is not called.
            {L"too small", [](ntk_notification_manager_options& o) { o.struct_size = 8; }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 0},
            {L"too large", [](ntk_notification_manager_options& o) { o.struct_size = 4097; }, NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, 0},
        };
        for (const auto& c : cases) {
            Recorder recorder;
            auto options = Options(recorder);
            c.change(options);
            ntk_notification_manager* manager = nullptr;
            Assert::AreEqual(c.expected, ntk_notification_manager_create(&options, &manager), c.name);
            Assert::IsNull(manager);
            Assert::AreEqual(c.releases, recorder.releases.load(), c.name);
        }
        Assert::AreEqual(0, g_factoryCalls);
    }

    TEST_METHOD(Test_Create_StructVersions)
    {
        Recorder zeroTail;
        auto grown = GrownFrom(Options(zeroTail), 0);
        ntk_notification_manager* manager = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE,
                                  ntk_notification_manager_create(&grown.known, &manager));
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, zeroTail.releases.load());

        Recorder setTail;
        auto newer = GrownFrom(Options(setTail), 1);
        manager = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED,
                                  ntk_notification_manager_create(&newer.known, &manager));
        Assert::IsNull(manager);
        Assert::AreEqual(1, setTail.releases.load());
    }

    TEST_METHOD(Test_Create_RefusedByTheCppApi_ReleasesBeforeReturning)
    {
        g_mode = FactoryMode::Refuse;
        Recorder recorder;
        auto options = Options(recorder);
        ntk_notification_manager* manager = nullptr;

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, ntk_notification_manager_create(&options, &manager));
        Assert::IsNull(manager);
        Assert::AreEqual(1, recorder.releases.load());
        Assert::AreEqual(GetCurrentThreadId(), recorder.releaseThread.load());
    }

    TEST_METHOD(Test_Create_ExceptionDoesNotCrossAndStillReleases)
    {
        g_mode = FactoryMode::Throw;
        Recorder recorder;
        auto options = Options(recorder);
        ntk_notification_manager* manager = nullptr;

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_HRESULT_FAILURE, ntk_notification_manager_create(&options, &manager));
        Assert::AreEqual(static_cast<uint32_t>(NTK_SYSTEM_CODE_E_OUTOFMEMORY), ntk_last_system_code());
        Assert::IsNull(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    // ------------------------------------------------------------------------
    // Activation and release (E-12, CT-18)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Activation_ReachesTheHandlerInUtf8)
    {
        Recorder recorder;
        auto* manager = Create(recorder);

        const std::wstring json = std::wstring(L"{\"action\":\"reply\",\"text\":\"h") + wchar_t(0x00E9) + L"\"}";
        TestAccess::Activate(json);

        Assert::AreEqual(1, recorder.invocations.load());
        Assert::AreEqual(std::string("{\"action\":\"reply\",\"text\":\"h\xC3\xA9\"}"), recorder.lastRaw);
        Assert::AreEqual(size_t{2}, recorder.lastValues.size());
        bool sawAction = false, sawText = false;
        for (const auto& [key, value] : recorder.lastValues) {
            if (key == "action") sawAction = value == "reply";
            if (key == "text") sawText = value == "h\xC3\xA9";
        }
        Assert::IsTrue(sawAction);
        Assert::IsTrue(sawText);
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_Release_OnClose_OnceOnTheClosingThread)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        Assert::AreEqual(0, recorder.releases.load());

        ntk_notification_manager_close(manager);
        Assert::AreEqual(1, recorder.releases.load());
        Assert::AreEqual(GetCurrentThreadId(), recorder.releaseThread.load());

        ntk_notification_manager_close(manager);
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_Release_OnFreeWithoutClose)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_Release_OnReplace_OldNowNewAtClose)
    {
        Recorder first, second;
        auto* manager = Create(first);

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE,
                                  ntk_notification_manager_set_invoked_handler(manager, &OnInvoked, &second, &OnRelease));
        Assert::AreEqual(1, first.releases.load());
        Assert::AreEqual(0, second.releases.load());

        TestAccess::Activate(L"{}");
        Assert::AreEqual(0, first.invocations.load());
        Assert::AreEqual(1, second.invocations.load());

        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, first.releases.load());
        Assert::AreEqual(1, second.releases.load());
    }

    TEST_METHOD(Test_Release_CloseDuringDelivery_WaitsForTheDelivery)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        TestAccess::SetAfterHandlerCopy(&HoldDelivery);

        DWORD deliveryThread = 0;
        std::thread delivery([&] {
            deliveryThread = GetCurrentThreadId();
            TestAccess::Activate(L"{}");
        });
        Assert::AreEqual(static_cast<DWORD>(WAIT_OBJECT_0), WaitForSingleObject(g_deliveryHeld, 10000));

        ntk_notification_manager_close(manager);
        Assert::AreEqual(0, recorder.releases.load(), L"released while a delivery still held the handler");

        SetEvent(g_deliveryGo);
        delivery.join();
        Assert::AreEqual(1, recorder.invocations.load());
        Assert::AreEqual(1, recorder.releases.load());
        Assert::AreEqual(deliveryThread, recorder.releaseThread.load());
        Assert::AreEqual(std::string("invoked"), recorder.events.front());
        Assert::AreEqual(std::string("released"), recorder.events.back());
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_Release_ReplaceDuringDelivery_WaitsForTheDelivery)
    {
        Recorder first, second;
        auto* manager = Create(first);
        TestAccess::SetAfterHandlerCopy(&HoldDelivery);

        DWORD deliveryThread = 0;
        std::thread delivery([&] {
            deliveryThread = GetCurrentThreadId();
            TestAccess::Activate(L"{}");
        });
        Assert::AreEqual(static_cast<DWORD>(WAIT_OBJECT_0), WaitForSingleObject(g_deliveryHeld, 10000));

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE,
                                  ntk_notification_manager_set_invoked_handler(manager, &OnInvoked, &second, &OnRelease));
        Assert::AreEqual(0, first.releases.load());

        SetEvent(g_deliveryGo);
        delivery.join();
        // The delivery had copied the first handler; it runs that one.
        Assert::AreEqual(1, first.invocations.load());
        Assert::AreEqual(0, second.invocations.load());
        Assert::AreEqual(1, first.releases.load());
        Assert::AreEqual(deliveryThread, first.releaseThread.load());

        TestAccess::SetAfterHandlerCopy(nullptr);
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, second.releases.load());
    }

    TEST_METHOD(Test_SetHandler_OnAClosedManager_RefusesAndReleasesAtOnce)
    {
        Recorder first, second;
        auto* manager = Create(first);
        ntk_notification_manager_close(manager);

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED,
                                  ntk_notification_manager_set_invoked_handler(manager, &OnInvoked, &second, &OnRelease));
        Assert::AreEqual(1, second.releases.load());
        Assert::AreEqual(GetCurrentThreadId(), second.releaseThread.load());
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_SetHandler_NullManager_RefusesAndReleases)
    {
        Recorder recorder;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER,
                                  ntk_notification_manager_set_invoked_handler(nullptr, &OnInvoked, &recorder, &OnRelease));
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_NullHandler_DropsActivationsAndStillReleases)
    {
        Recorder recorder;
        auto options = Options(recorder);
        options.on_invoked = nullptr;
        ntk_notification_manager* manager = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_manager_create(&options, &manager));

        TestAccess::Activate(L"{}");
        Assert::AreEqual(0, recorder.invocations.load());

        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_ThrowingHandler_DoesNotReachTheDelivery)
    {
        Recorder recorder;
        auto options = Options(recorder);
        options.on_invoked = &OnInvokedThrows;
        ntk_notification_manager* manager = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_manager_create(&options, &manager));

        TestAccess::Activate(L"{}");
        Assert::AreEqual(1, recorder.invocations.load());

        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, recorder.releases.load());
    }

    TEST_METHOD(Test_SecondManager_IsNotSupportedUntilTheFirstCloses)
    {
        // The real Create refuses a second manager; the test factory does not
        // reach it, so the C++ API is asked directly for the same answer.
        Recorder first;
        auto* manager = Create(first);
        const auto second = Api::Manager::Create(Api::ManagerOptions{});
        Assert::IsFalse(second.has_value());
        Assert::IsTrue(second.error().code == Api::ErrorCode::NotSupported);
        ntk_notification_manager_free(manager);
    }

    // ------------------------------------------------------------------------
    // Operations (OP-12..OP-20)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Operations_NullManager_AreInvalid)
    {
        ntk_notification_progress_update update{};
        update.struct_size = static_cast<uint32_t>(sizeof(update));
        ntk_notification_list* list = reinterpret_cast<ntk_notification_list*>(1);
        ntk_notification_setting setting = -1;
        const int32_t invalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

        Assert::AreEqual(invalid, ntk_notification_cancel_scheduled(nullptr, "t", "g"));
        Assert::AreEqual(invalid, ntk_notification_update_progress(nullptr, &update));
        Assert::AreEqual(invalid, ntk_notification_set_badge(nullptr, 1));
        Assert::AreEqual(invalid, ntk_notification_remove_by_id(nullptr, 1));
        Assert::AreEqual(invalid, ntk_notification_remove_by_tag(nullptr, "t", "g"));
        Assert::AreEqual(invalid, ntk_notification_remove_all(nullptr));
        Assert::AreEqual(invalid, ntk_notification_get_all(nullptr, &list));
        Assert::IsNull(list);
        Assert::AreEqual(invalid, ntk_notification_get_setting(nullptr, &setting));
        Assert::AreEqual<int32_t>(-1, setting);
        Assert::AreEqual(invalid, ntk_notification_open_settings(nullptr));
    }

    TEST_METHOD(Test_Operations_OnAClosedManager_AreNotInitialized)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_manager_close(manager);

        ntk_notification_progress_update update{};
        update.struct_size = static_cast<uint32_t>(sizeof(update));
        ntk_notification_list* list = reinterpret_cast<ntk_notification_list*>(1);
        ntk_notification_setting setting = -1;
        const int32_t closed = NTK_NOTIFICATION_ERROR_NOT_INITIALIZED;

        Assert::AreEqual(closed, ntk_notification_cancel_scheduled(manager, nullptr, nullptr));
        Assert::AreEqual(closed, ntk_notification_update_progress(manager, &update));
        Assert::AreEqual(closed, ntk_notification_set_badge(manager, 1));
        Assert::AreEqual(closed, ntk_notification_remove_by_id(manager, 1));
        Assert::AreEqual(closed, ntk_notification_remove_by_tag(manager, nullptr, nullptr));
        Assert::AreEqual(closed, ntk_notification_remove_all(manager));
        Assert::AreEqual(closed, ntk_notification_get_all(manager, &list));
        Assert::IsNull(list);
        Assert::AreEqual(closed, ntk_notification_get_setting(manager, &setting));
        Assert::AreEqual<int32_t>(-1, setting);
        Assert::AreEqual(closed, ntk_notification_open_settings(manager));
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_Operations_NullOutputs_AreInvalid)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, ntk_notification_get_all(manager, nullptr));
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, ntk_notification_get_setting(manager, nullptr));
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_Operations_InvalidUtf8_IsRefusedBeforeTheCppApi)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_manager_close(manager);   // valid input would say NOT_INITIALIZED
        const char* bad = kInvalidUtf8.c_str();
        const int32_t invalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

        Assert::AreEqual(invalid, ntk_notification_cancel_scheduled(manager, bad, nullptr));
        Assert::AreEqual(invalid, ntk_notification_cancel_scheduled(manager, nullptr, bad));
        Assert::AreEqual(invalid, ntk_notification_remove_by_tag(manager, bad, nullptr));
        Assert::AreEqual(invalid, ntk_notification_remove_by_tag(manager, nullptr, bad));
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_UpdateProgress_MalformedAndVersions)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_manager_close(manager);   // a well-formed update says NOT_INITIALIZED

        ntk_notification_progress_update update{};
        update.struct_size = static_cast<uint32_t>(sizeof(update));
        const int32_t invalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

        Assert::AreEqual(invalid, ntk_notification_update_progress(manager, nullptr));
        auto tooSmall = update;
        tooSmall.struct_size = 8;
        Assert::AreEqual(invalid, ntk_notification_update_progress(manager, &tooSmall));
        auto reserved = update;
        reserved.reserved1 = 1;
        Assert::AreEqual(invalid, ntk_notification_update_progress(manager, &reserved));
        auto badText = update;
        badText.status = kInvalidUtf8.c_str();
        Assert::AreEqual(invalid, ntk_notification_update_progress(manager, &badText));

        auto zeroTail = GrownFrom(update, 0);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED,
                                  ntk_notification_update_progress(manager, &zeroTail.known));
        auto setTail = GrownFrom(update, 1);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED,
                                  ntk_notification_update_progress(manager, &setTail.known));
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_ToProgressUpdate_ConvertsEveryField)
    {
        ntk_notification_progress_update update{};
        update.struct_size = static_cast<uint32_t>(sizeof(update));
        update.tag = "t";
        update.group = nullptr;
        update.value = 0.25;
        update.value_string = "1/4";
        update.status = "caf\xC3\xA9";
        update.sequence_number = 7;

        Api::ProgressUpdate converted;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ToProgressUpdate(&update, converted));
        Assert::AreEqual(std::wstring(L"t"), converted.tag);
        Assert::AreEqual(std::wstring(), converted.group);
        Assert::AreEqual(0.25, converted.value);
        Assert::AreEqual(std::wstring(L"1/4"), converted.valueString);
        Assert::AreEqual(std::wstring(L"caf") + wchar_t(0x00E9), converted.status);
        Assert::AreEqual(7u, converted.sequenceNumber);
    }

    TEST_METHOD(Test_SystemCode_FollowsTheLastCall)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_manager_close(manager);

        ntk_notification_remove_all(manager);
        const uint32_t closedCode = ntk_last_system_code();
        Assert::AreNotEqual(0u, closedCode);   // the C++ API reports NOT_INITIALIZED's value

        ntk_notification_runtime* runtime = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &runtime));
        Assert::AreEqual(0u, ntk_last_system_code());
        ntk_notification_runtime_free(runtime);
        ntk_notification_manager_free(manager);
    }

    // ------------------------------------------------------------------------
    // The list (OP-18's output) and the activation
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_List_ReadsEveryEntryInUtf8)
    {
        std::vector<Api::NotificationRef> refs{
            {7, L"tag", L"group"},
            {9, std::wstring(L"t") + wchar_t(0x00E9), L""},
        };
        ntk_notification_list* list = NewList(refs);

        Assert::AreEqual(size_t{2}, ntk_notification_list_count(list));
        Assert::AreEqual(7u, ntk_notification_list_id_at(list, 0));
        Assert::AreEqual(9u, ntk_notification_list_id_at(list, 1));
        size_t size = 99;
        Assert::AreEqual("tag", ntk_notification_list_tag_at(list, 0, &size));
        Assert::AreEqual(size_t{3}, size);
        Assert::AreEqual("group", ntk_notification_list_group_at(list, 0, nullptr));
        Assert::AreEqual("t\xC3\xA9", ntk_notification_list_tag_at(list, 1, &size));
        Assert::AreEqual(size_t{3}, size);
        Assert::AreEqual("", ntk_notification_list_group_at(list, 1, &size));
        Assert::AreEqual(size_t{0}, size);
        ntk_notification_list_free(list);
    }

    TEST_METHOD(Test_List_OutOfRangeAndNull_ReadAsNothing)
    {
        ntk_notification_list* list = NewList({{7, L"tag", L"group"}});
        size_t size = 99;
        Assert::AreEqual(0u, ntk_notification_list_id_at(list, 1));
        Assert::IsNull(ntk_notification_list_tag_at(list, 1, &size));
        Assert::AreEqual(size_t{0}, size);
        Assert::IsNull(ntk_notification_list_group_at(list, 1, nullptr));
        ntk_notification_list_free(list);

        Assert::AreEqual(size_t{0}, ntk_notification_list_count(nullptr));
        Assert::AreEqual(0u, ntk_notification_list_id_at(nullptr, 0));
        Assert::IsNull(ntk_notification_list_tag_at(nullptr, 0, nullptr));
        ntk_notification_list_free(nullptr);
    }

    TEST_METHOD(Test_Activation_OutOfRangeAndNull_ReadAsNothing)
    {
        Api::ActivationArgs args;
        args.rawArguments = L"{\"k\":\"v\"}";
        args.values = {{L"k", L"v"}};
        const auto activation = ToActivation(args);

        size_t size = 99;
        Assert::AreEqual("{\"k\":\"v\"}", ntk_notification_activation_raw_arguments(&activation, &size));
        Assert::AreEqual(size_t{9}, size);
        Assert::AreEqual(size_t{1}, ntk_notification_activation_value_count(&activation));
        Assert::IsNull(ntk_notification_activation_key_at(&activation, 1, &size));
        Assert::AreEqual(size_t{0}, size);
        Assert::IsNull(ntk_notification_activation_value_at(&activation, 1, nullptr));

        Assert::IsNull(ntk_notification_activation_raw_arguments(nullptr, nullptr));
        Assert::AreEqual(size_t{0}, ntk_notification_activation_value_count(nullptr));
        Assert::IsNull(ntk_notification_activation_key_at(nullptr, 0, nullptr));
    }

    TEST_METHOD(Test_Free_Null_DoesNothing)
    {
        ntk_notification_runtime_free(nullptr);
        ntk_notification_manager_close(nullptr);
        ntk_notification_manager_free(nullptr);
        ntk_notification_list_free(nullptr);
        Assert::AreEqual(0, g_shutdownCalls);
    }

    // ------------------------------------------------------------------------
    // The runtime (OP-07, CT-19)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_Runtime_SecondInitializeIsNotSupported)
    {
        ntk_notification_runtime* first = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &first));
        ntk_notification_runtime* second = reinterpret_cast<ntk_notification_runtime*>(1);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, ntk_notification_runtime_initialize(0x00010007, &second));
        Assert::IsNull(second);
        Assert::AreEqual(1, g_initializeCalls);

        ntk_notification_runtime_free(first);
        Assert::AreEqual(1, g_shutdownCalls);

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &first));
        ntk_notification_runtime_free(first);
        Assert::AreEqual(2, g_shutdownCalls);
    }

    TEST_METHOD(Test_Runtime_FreedWhileAManagerLives_ShutsDownAtTheLastClose)
    {
        ntk_notification_runtime* runtime = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &runtime));
        Recorder recorder;
        auto* manager = Create(recorder);

        ntk_notification_runtime_free(runtime);
        Assert::AreEqual(0, g_shutdownCalls);

        // Still loaded, so a new runtime is refused until the shutdown happens.
        ntk_notification_runtime* again = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_SUPPORTED, ntk_notification_runtime_initialize(0x00010007, &again));

        ntk_notification_manager_close(manager);
        Assert::AreEqual(1, g_shutdownCalls);
        ntk_notification_manager_free(manager);
        Assert::AreEqual(1, g_shutdownCalls);

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &again));
        ntk_notification_runtime_free(again);
        Assert::AreEqual(2, g_shutdownCalls);
    }

    TEST_METHOD(Test_Runtime_FreedAfterTheManagerCloses_ShutsDownAtOnce)
    {
        Recorder recorder;
        auto* manager = Create(recorder);
        ntk_notification_runtime* runtime = nullptr;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &runtime));

        ntk_notification_manager_free(manager);
        Assert::AreEqual(0, g_shutdownCalls);
        ntk_notification_runtime_free(runtime);
        Assert::AreEqual(1, g_shutdownCalls);
    }

    TEST_METHOD(Test_Runtime_FailedInitialize_ReportsAndLoadsNothing)
    {
        g_initializeFailure = 0x80070002;
        ntk_notification_runtime* runtime = reinterpret_cast<ntk_notification_runtime*>(1);
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_HRESULT_FAILURE, ntk_notification_runtime_initialize(0x00010007, &runtime));
        Assert::AreEqual(0x80070002u, ntk_last_system_code());
        Assert::IsNull(runtime);

        g_initializeFailure = 0;
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, ntk_notification_runtime_initialize(0x00010007, &runtime));
        ntk_notification_runtime_free(runtime);
        Assert::AreEqual(1, g_shutdownCalls);
    }

    TEST_METHOD(Test_Runtime_NullOutput_IsInvalid)
    {
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, ntk_notification_runtime_initialize(0x00010007, nullptr));
        Assert::AreEqual(0, g_initializeCalls);
    }
};

}  // namespace CApiNotificationTest
