#include "pch.h"
#include "../WindowsLibrary/WindowsClipboardHistoryCoordinator.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// This suite exercises ClipboardHistoryCoordinator directly against a mock
// IClipboardHistoryBackend, bypassing ClipboardManager/WindowsClipboardWindow
// and the real WM_APP_CLIPBOARD_* message pump. OnStartQueuedRequest/
// OnCancelMessage/OnDrainMessage are invoked directly to simulate "as if" the
// dispatch window's WndProc had already routed the posted message - this
// keeps the suite C++17/STA-free while still covering the Queued -> Running
// -> Finished state machine, cancellation races and the shutdown drain.
// See the implementation result report for why WindowsClipboardManager.cpp /
// WindowsClipboardHistoryWinRt.cpp are intentionally NOT linked into this
// test project.
// ============================================================================

namespace WindowsClipboardHistoryCoordinatorTest
{

namespace
{
    // ---- Recording ClipboardRequestCallback (function pointer, no captures) ----
    struct CallbackRecord
    {
        int callCount = 0;
        uint32_t lastId = 0;
        DWORD lastError = 0xFFFFFFFFu;
        std::wstring lastJson;
        bool lastJsonWasNull = true;
    };
    CallbackRecord g_cb;

    void RecordingCallback(uint32_t id, DWORD error, const wchar_t* json)
    {
        g_cb.callCount++;
        g_cb.lastId = id;
        g_cb.lastError = error;
        g_cb.lastJsonWasNull = (json == nullptr);
        g_cb.lastJson = json ? json : L"";
    }

    // ---- Recording history event callbacks (function pointers) ----
    int g_historyChangedCount = 0;
    void OnHistoryChangedCb() { g_historyChangedCount++; }
    int g_newHistoryChangedCount = 0;
    void OnNewHistoryChangedCb() { g_newHistoryChangedCount++; }

    int g_historyEnabledChangedCount = 0;
    BOOL g_lastHistoryEnabled = FALSE;
    void OnHistoryEnabledChangedCb(BOOL enabled) { g_historyEnabledChangedCount++; g_lastHistoryEnabled = enabled; }

    int g_roamingEnabledChangedCount = 0;
    BOOL g_lastRoamingEnabled = FALSE;
    void OnRoamingEnabledChangedCb(BOOL enabled) { g_roamingEnabledChangedCount++; g_lastRoamingEnabled = enabled; }

    void ResetRecorders()
    {
        g_cb = CallbackRecord{};
        g_historyChangedCount = 0;
        g_newHistoryChangedCount = 0;
        g_historyEnabledChangedCount = 0;
        g_lastHistoryEnabled = FALSE;
        g_roamingEnabledChangedCount = 0;
        g_lastRoamingEnabled = FALSE;
    }

    // A message-only-style top-level window using a stock window class, purely
    // so Accept()/CancelRequest() have a real HWND to PostMessageW to. Nothing
    // ever dispatches these messages; tests drive the state machine directly.
    HWND MakeTestWindow()
    {
        return ::CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 0, 0,
                                 nullptr, nullptr, ::GetModuleHandleW(nullptr), nullptr);
    }

    bool TakePostedHistoryEvent(HWND hwnd, WPARAM& eventId, LPARAM& generation)
    {
        MSG msg{};
        if (!::PeekMessageW(&msg, hwnd, WM_APP_CLIPBOARD_HISTORY_EVENT,
                            WM_APP_CLIPBOARD_HISTORY_EVENT, PM_REMOVE))
        {
            return false;
        }
        eventId = msg.wParam;
        generation = msg.lParam;
        return true;
    }

    // ------------------------------------------------------------------------
    // MockHistoryBackend - records calls; completes synchronously by default,
    // or defers (storing the callback for the test to invoke manually) when
    // deferCompletion is set, so tests can control Running-state timing.
    // ------------------------------------------------------------------------
    class MockHistoryBackend final : public IClipboardHistoryBackend
    {
    public:
        bool deferCompletion = false;

        DWORD availabilityError = CLIPBOARD_ERROR_NONE;
        ClipboardHistoryAvailability availability{};
        DWORD itemsError = CLIPBOARD_ERROR_NONE;
        std::vector<ClipboardHistoryEntry> items;
        DWORD statusError = CLIPBOARD_ERROR_NONE;

        HistoryAvailabilityCallback pendingAvailability;
        HistoryItemsCallback pendingItems;
        HistoryStatusCallback pendingSetItem;
        HistoryStatusCallback pendingDelete;
        HistoryStatusCallback pendingClear;

        int startWatchCalls = 0;
        int replaceEventsCalls = 0;
        int stopWatchCalls = 0;
        bool startWatchFails = false;
        bool stopWatchFails = false;
        bool canDestroyReturn = true;
        DWORD historyEnabledQueryError = CLIPBOARD_ERROR_NONE;
        DWORD roamingEnabledQueryError = CLIPBOARD_ERROR_NONE;
        bool queriedHistoryEnabled = true;
        bool queriedRoamingEnabled = false;
        int historyEnabledQueryCalls = 0;
        int roamingEnabledQueryCalls = 0;
        std::shared_ptr<const ClipboardHistoryEvents> lastEvents;

        void GetAvailabilityAsync(HistoryAvailabilityCallback done) override
        {
            if (deferCompletion) { pendingAvailability = std::move(done); return; }
            done(availabilityError, availability);
        }
        void GetItemsAsync(HistoryItemsCallback done) override
        {
            if (deferCompletion) { pendingItems = std::move(done); return; }
            done(itemsError, items);
        }
        void SetItemAsContentAsync(const std::wstring&, HistoryStatusCallback done) override
        {
            if (deferCompletion) { pendingSetItem = std::move(done); return; }
            done(statusError);
        }
        void DeleteItemAsync(const std::wstring&, HistoryStatusCallback done) override
        {
            if (deferCompletion) { pendingDelete = std::move(done); return; }
            done(statusError);
        }
        void ClearUnpinnedAsync(HistoryStatusCallback done) override
        {
            if (deferCompletion) { pendingClear = std::move(done); return; }
            done(statusError);
        }
        DWORD QueryHistoryEnabled(bool& enabled) override
        {
            historyEnabledQueryCalls++;
            enabled = queriedHistoryEnabled;
            return historyEnabledQueryError;
        }
        DWORD QueryRoamingEnabled(bool& enabled) override
        {
            roamingEnabledQueryCalls++;
            enabled = queriedRoamingEnabled;
            return roamingEnabledQueryError;
        }
        DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events) override
        {
            startWatchCalls++;
            lastEvents = events;
            if (startWatchFails) return CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED;
            watching_ = true;
            return CLIPBOARD_ERROR_NONE;
        }
        void ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events) override
        {
            replaceEventsCalls++;
            lastEvents = events;
        }
        bool StopWatch() override
        {
            stopWatchCalls++;
            if (stopWatchFails) return false;
            watching_ = false;
            return true;
        }
        bool CanDestroy() const override { return canDestroyReturn; }

    private:
        bool watching_ = false;
    };

    struct TestWindowGuard
    {
        HWND hwnd = nullptr;
        TestWindowGuard() : hwnd(MakeTestWindow()) {}
        ~TestWindowGuard() { if (hwnd) ::DestroyWindow(hwnd); }
    };
}

TEST_CLASS(ClipboardHistoryCoordinatorTest)
{
public:
    TEST_METHOD_INITIALIZE(MethodSetup)
    {
        ResetRecorders();
    }

    // -------------------------------------------------------------------
    // Acceptance / rejection
    // -------------------------------------------------------------------

    TEST_METHOD(Test_RequestGetItems_NoDispatchWindow_RejectsWithNotInitialized)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        Assert::AreEqual(0u, id);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NOT_INITIALIZED), err);
        Assert::AreEqual(0, g_cb.callCount); // rejection never retains the callback
    }

    TEST_METHOD(Test_RequestGetItems_NullCallback_ReturnsInvalidParameter)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(nullptr, &err);
        Assert::AreEqual(0u, id);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_RequestRestoreItem_EmptyId_ReturnsInvalidParameter)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestRestoreItem(L"", &RecordingCallback, &err);
        Assert::AreEqual(0u, id);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_RequestDeleteItem_EmptyId_ReturnsInvalidParameter)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestDeleteItem(L"", &RecordingCallback, &err);
        Assert::AreEqual(0u, id);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    // -------------------------------------------------------------------
    // Queued -> Running -> Finished, normal completion
    // -------------------------------------------------------------------

    TEST_METHOD(Test_RequestGetItems_Accepted_CompletesOnlyAfterOnStartQueuedRequest)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->items.push_back(ClipboardHistoryEntry{ L"item-1", std::wstring(L"hello"), { L"Text" }, 123 });
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        Assert::AreNotEqual(0u, id);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), err);
        Assert::AreEqual(0, g_cb.callCount); // still Queued - start() has not run yet

        coordinator->OnStartQueuedRequest(id);
        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(id, g_cb.lastId);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), g_cb.lastError);
        Assert::IsFalse(g_cb.lastJsonWasNull);
        Assert::IsTrue(g_cb.lastJson.find(L"item-1") != std::wstring::npos);
    }

    TEST_METHOD(Test_RequestGetAvailability_Accepted_DeliversAvailabilityJson)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->availability = ClipboardHistoryAvailability{ true, false };
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetAvailability(&RecordingCallback, &err);
        coordinator->OnStartQueuedRequest(id);

        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), g_cb.lastError);
        Assert::IsTrue(g_cb.lastJson.find(L"historyEnabled") != std::wstring::npos);
    }

    TEST_METHOD(Test_RequestClearUnpinned_BackendError_PropagatesErrorWithNullJson)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->statusError = CLIPBOARD_ERROR_HISTORY_DISABLED;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestClearUnpinned(&RecordingCallback, &err);
        coordinator->OnStartQueuedRequest(id);

        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_HISTORY_DISABLED), g_cb.lastError);
        Assert::IsTrue(g_cb.lastJsonWasNull);
    }

    // -------------------------------------------------------------------
    // Cancellation races
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CancelBeforeStart_DeliversCanceled_AndStartNeverRuns)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);

        coordinator->OnCancelMessage(id);
        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_CANCELED), g_cb.lastError);

        // The (now-orphaned) start message arrives afterward - must be a no-op.
        coordinator->OnStartQueuedRequest(id);
        Assert::AreEqual(1, g_cb.callCount); // unchanged: no double delivery, backend never invoked
    }

    TEST_METHOD(Test_CancelAfterStart_WhileRunning_DeliversCanceledOnce_LateBackendCompletionIgnored)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->deferCompletion = true;
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        coordinator->OnStartQueuedRequest(id); // now Running; backend has stored pendingItems
        Assert::AreEqual(0, g_cb.callCount);
        Assert::IsTrue(static_cast<bool>(mock->pendingItems));

        coordinator->OnCancelMessage(id);
        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_CANCELED), g_cb.lastError);

        // Backend eventually completes anyway (as if the coroutine had already been in flight).
        mock->pendingItems(CLIPBOARD_ERROR_NONE, {});
        Assert::AreEqual(1, g_cb.callCount); // the completion right was already taken by cancel
    }

    TEST_METHOD(Test_DuplicateBackendCompletion_OnlyFirstDelivers)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->deferCompletion = true;
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        coordinator->OnStartQueuedRequest(id);

        mock->pendingItems(CLIPBOARD_ERROR_NONE, {});
        mock->pendingItems(CLIPBOARD_ERROR_NONE, {}); // simulates a misbehaving backend calling twice
        Assert::AreEqual(1, g_cb.callCount);
    }

    TEST_METHOD(Test_CancelRequest_UnknownId_ReturnsFalse)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        Assert::IsFalse(coordinator->CancelRequest(999, &err));
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_CancelRequest_ZeroId_ReturnsFalse)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);

        DWORD err = 0;
        Assert::IsFalse(coordinator->CancelRequest(0, &err));
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_INVALID_PARAMETER), err);
    }

    TEST_METHOD(Test_CancelRequest_KnownQueuedId_ReturnsTrue)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        Assert::IsTrue(coordinator->CancelRequest(id, &err));
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), err);
    }

    // -------------------------------------------------------------------
    // Shutdown drain
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CloseAndDrain_QueuedRequest_DrainsWithCanceled_AndCanDestroyGatesOnIt)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        Assert::AreNotEqual(0u, id);

        bool fullyDrained = coordinator->CloseAndDrain();
        Assert::IsFalse(fullyDrained); // one item was moved into the drain queue
        Assert::IsFalse(coordinator->CanDestroy());
        Assert::AreEqual(0, g_cb.callCount); // not delivered until OnDrainMessage runs

        coordinator->OnDrainMessage();
        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_CANCELED), g_cb.lastError);
        Assert::IsTrue(coordinator->CanDestroy());
    }

    TEST_METHOD(Test_CloseAndDrain_NoOutstandingRequests_ReturnsTrueImmediately)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        Assert::IsTrue(coordinator->CloseAndDrain());
        Assert::IsTrue(coordinator->CanDestroy());
    }

    TEST_METHOD(Test_CloseAndDrain_RunningRequest_NotYetCompleted_AlsoDrains)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->deferCompletion = true;
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        DWORD err = 0;
        uint32_t id = coordinator->RequestGetItems(&RecordingCallback, &err);
        coordinator->OnStartQueuedRequest(id); // Running: backend holds pendingItems

        Assert::IsFalse(coordinator->CloseAndDrain());
        coordinator->OnDrainMessage();
        Assert::AreEqual(1, g_cb.callCount);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_CANCELED), g_cb.lastError);

        // The backend's late completion (as if the real async op eventually finished)
        // must not deliver a second callback - the entry was already dropped by drain.
        mock->pendingItems(CLIPBOARD_ERROR_NONE, {});
        Assert::AreEqual(1, g_cb.callCount);
    }

    // -------------------------------------------------------------------
    // SetHistoryCallbacks / StartWatch / StopWatch semantics
    // -------------------------------------------------------------------

    TEST_METHOD(Test_SetHistoryCallbacks_AllNull_WhenNotWatching_IsNoop)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        DWORD result = coordinator->SetHistoryCallbacks(nullptr, nullptr, nullptr);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), result);
        Assert::AreEqual(0, mock->stopWatchCalls);
    }

    TEST_METHOD(Test_SetHistoryCallbacks_FirstRegistration_CallsStartWatch)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        DWORD result = coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, &OnHistoryEnabledChangedCb, &OnRoamingEnabledChangedCb);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_NONE), result);
        Assert::AreEqual(1, mock->startWatchCalls);
        Assert::AreEqual(0, mock->replaceEventsCalls);
        Assert::IsNotNull(mock->lastEvents.get());
    }

    TEST_METHOD(Test_SetHistoryCallbacks_SecondRegistration_ReplacesEvents_NoReToken)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, &OnHistoryEnabledChangedCb, nullptr);

        Assert::AreEqual(1, mock->startWatchCalls); // token acquired exactly once
        Assert::AreEqual(1, mock->replaceEventsCalls);
    }

    TEST_METHOD(Test_SetHistoryCallbacks_StartWatchFails_ReturnsBackendError_StaysNotWatching)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->startWatchFails = true;
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        DWORD result = coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED), result);

        // Not watching, so a retry calls StartWatch again rather than ReplaceEvents.
        mock->startWatchFails = false;
        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        Assert::AreEqual(2, mock->startWatchCalls);
        Assert::AreEqual(0, mock->replaceEventsCalls);
    }

    TEST_METHOD(Test_SetHistoryCallbacks_StopWatchFails_KeepsPreviousRegistration)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        mock->stopWatchFails = true;

        DWORD result = coordinator->SetHistoryCallbacks(nullptr, nullptr, nullptr);
        Assert::AreEqual(static_cast<DWORD>(CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED), result);

        // Still considered watching internally -> next non-null call replaces, doesn't re-StartWatch.
        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        Assert::AreEqual(1, mock->startWatchCalls);
        Assert::AreEqual(1, mock->replaceEventsCalls);
    }

    // Backend event handlers only post an event id + watch generation. The UI
    // thread consumes the immutable callback snapshot and queries flag values
    // through the backend there.
    TEST_METHOD(Test_SetHistoryCallbacks_EventsFireThroughToUserCallbacks)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, &OnHistoryEnabledChangedCb, &OnRoamingEnabledChangedCb);
        Assert::IsNotNull(mock->lastEvents.get());

        // Firing the WinRT-side handler only posts; it must not invoke anything itself.
        mock->lastEvents->onHistoryChanged();
        mock->lastEvents->onHistoryEnabledChanged();
        mock->lastEvents->onRoamingEnabledChanged();
        Assert::AreEqual(0, g_historyChangedCount);

        // Simulate the WndProc delivering the three posted messages on the UI thread.
        for (int i = 0; i < 3; ++i)
        {
            WPARAM eventId = 0;
            LPARAM generation = 0;
            Assert::IsTrue(TakePostedHistoryEvent(window.hwnd, eventId, generation));
            coordinator->OnHistoryEventMessage(eventId, generation);
        }

        Assert::AreEqual(1, g_historyChangedCount);
        Assert::AreEqual(1, g_historyEnabledChangedCount);
        Assert::IsTrue(g_lastHistoryEnabled == TRUE);
        Assert::AreEqual(1, g_roamingEnabledChangedCount);
        Assert::IsTrue(g_lastRoamingEnabled == FALSE);
        Assert::AreEqual(1, mock->historyEnabledQueryCalls);
        Assert::AreEqual(1, mock->roamingEnabledQueryCalls);
    }

    TEST_METHOD(Test_OnHistoryEventMessage_Replacement_UsesImmutableEntrySnapshot)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        auto oldEvents = mock->lastEvents;
        oldEvents->onHistoryChanged();
        coordinator->SetHistoryCallbacks(&OnNewHistoryChangedCb, nullptr, nullptr);

        WPARAM eventId = 0;
        LPARAM generation = 0;
        Assert::IsTrue(TakePostedHistoryEvent(window.hwnd, eventId, generation));
        coordinator->OnHistoryEventMessage(eventId, generation);

        Assert::AreEqual(1, g_historyChangedCount);
        Assert::AreEqual(0, g_newHistoryChangedCount);
    }

    TEST_METHOD(Test_OnHistoryEventMessage_AfterStopAndReregister_DropsOldGeneration)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        mock->lastEvents->onHistoryChanged();

        WPARAM oldEventId = 0;
        LPARAM oldGeneration = 0;
        Assert::IsTrue(TakePostedHistoryEvent(window.hwnd, oldEventId, oldGeneration));
        coordinator->SetHistoryCallbacks(nullptr, nullptr, nullptr);
        coordinator->SetHistoryCallbacks(&OnNewHistoryChangedCb, nullptr, nullptr);
        coordinator->OnHistoryEventMessage(oldEventId, oldGeneration);

        Assert::AreEqual(0, g_historyChangedCount);
        Assert::AreEqual(0, g_newHistoryChangedCount);
    }

    TEST_METHOD(Test_OnHistoryEventMessage_UnknownId_IsSafeNoop)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        TestWindowGuard window;
        coordinator->AttachDispatchWindow(window.hwnd);
        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);

        coordinator->OnHistoryEventMessage(static_cast<WPARAM>(99), static_cast<LPARAM>(1));
        Assert::AreEqual(0, g_historyChangedCount);
    }

    TEST_METHOD(Test_StopWatch_WhenNotWatching_ReturnsTrue_WithoutCallingBackend)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        Assert::IsTrue(coordinator->StopWatch());
        Assert::AreEqual(0, mock->stopWatchCalls);
    }

    TEST_METHOD(Test_StopWatch_WhenWatching_CallsBackendStopWatch)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        auto* mock = backend.get();
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);

        coordinator->SetHistoryCallbacks(&OnHistoryChangedCb, nullptr, nullptr);
        Assert::IsTrue(coordinator->StopWatch());
        Assert::AreEqual(1, mock->stopWatchCalls);
    }

    // -------------------------------------------------------------------
    // CanDestroy boundary conditions
    // -------------------------------------------------------------------

    TEST_METHOD(Test_CanDestroy_TrueWhenBackendReadyAndNoDrainWork)
    {
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        Assert::IsTrue(coordinator->CanDestroy());
    }

    TEST_METHOD(Test_CanDestroy_FalseWhenBackendNotReady)
    {
        ClipboardLifecycle lifecycle;
        auto backend = std::make_unique<MockHistoryBackend>();
        backend->canDestroyReturn = false;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle);
        Assert::IsFalse(coordinator->CanDestroy());
    }

    // -------------------------------------------------------------------
    // Data/Application boundary isolation
    // -------------------------------------------------------------------

    TEST_METHOD(Test_MockBackend_NeverSeesRequestIdOrLease)
    {
        // Compile-time/structural check: IClipboardHistoryBackend's methods take
        // only Domain types (std::wstring id, callbacks) - no uint32_t request id
        // and no ClipboardLifecycle::Lease parameter exists anywhere on the Port,
        // which is what keeps the Data layer ignorant of the Application-layer
        // pending table. This is asserted implicitly by MockHistoryBackend above
        // compiling against IClipboardHistoryBackend's exact signatures.
        ClipboardLifecycle lifecycle;
        auto coordinator = std::make_shared<ClipboardHistoryCoordinator>(
            std::make_unique<MockHistoryBackend>(), lifecycle);
        Assert::IsNotNull(coordinator.get());
    }
};

} // namespace WindowsClipboardHistoryCoordinatorTest
