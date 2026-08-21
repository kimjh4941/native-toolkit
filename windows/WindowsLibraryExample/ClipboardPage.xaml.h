#pragma once

#include "ClipboardPage.g.h"

#include <windows.h>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <string>

namespace winrt::WindowsLibraryExample::implementation
{
    struct ClipboardPage : ClipboardPageT<ClipboardPage>
    {
        ClipboardPage();

        void OnNavigatedTo(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const& e);
        void OnNavigatedFrom(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const& e);

        void BackButton_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Init / Lifecycle
        void InitializeManager_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void SetHistoryCallbacks_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void Uninitialize_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CanDestroy_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Copy
        void CopyPlainText_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyPlainTextEmpty_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyHtml_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyFiles_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyImage_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyCustomFormat_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyMultipleFormats_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyMultipleFormatsWithImage_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Write options
        void CopySensitive_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyExcludeHistory_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CopyExcludeRoaming_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CleanupTempFiles_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Paste
        void PastePlainText_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void PasteHtml_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void PasteFiles_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void PasteImage_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void PasteCustomFormat_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Inspect / Clear
        void HasFormat_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void GetClipboardFormats_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void GetPreferredFormat_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ClearClipboard_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Deferred rendering
        void ReserveDeferredFormats_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void RecoverDeferredState_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // History
        void GetHistoryAvailability_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void GetClipboardHistory_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void RestoreHistoryItem_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void DeleteHistoryItem_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ClearUnpinnedHistory_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void CancelLastRequest_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void RequestAndImmediateUninitialize_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Threading
        void ReserveDeferredOnWorker_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void UninitializeOnWorker_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void DelayedWorkerCheck_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

        // Error cases
        void ErrCopyPlainTextNull_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrPasteAfterClear_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrPasteHtmlTextOnly_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrPasteImageSizeQuery_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrMultiCfBitmap_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrMultiDuplicate_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrMultiTypeMismatch_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrCopyFilesEmpty_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrCopyAfterUninitialize_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrForceInitialize_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
        void ErrCancelUnknownId_Click(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

    private:
        // How a worker operation finished. Sample-side failures are kept apart from
        // Bridge domain errors so the UI never reports one as the other.
        enum class WorkerOutcome
        {
            BridgeResult,
            SampleFailure,
            SampleOutOfMemory,
            SampleWinRtFailure,
        };

        // Single completion payload for every worker exit path. Declared here (not in
        // an anonymous namespace) so the page helpers below can name it.
        struct WorkerResult
        {
            WorkerOutcome outcome{ WorkerOutcome::SampleFailure };
            DWORD         bridgeError{ 0 };
            HRESULT       sampleHresult{ S_OK };
            std::wstring  detail;
            std::wstring  logLine;
            // Log the outcome without replacing the latest-result line. Used by the
            // temp-file cleanup that runs after a successful Uninitialize, so a
            // cleanup failure never overwrites the Uninitialize result.
            bool          logOnly{ false };
        };

        static WorkerResult MakeBridgeResult(DWORD err,
                                             std::wstring detail = {},
                                             std::wstring logLine = {});

        // Manager-state requirement a button imposes before calling the Bridge.
        enum class WorkerPrecondition
        {
            ReadyRequired,
            AnyState,
            ShuttingDownRequired,
            NoStateGuard,
        };

        // Result display / logging for a finished worker operation. Private: the
        // completion lambda is built inside a member function and therefore has
        // access, so there is no reason to widen it.
        void CompleteWorkerOperation(std::wstring const& method, WorkerResult const& result);

        bool CheckPrecondition(WorkerPrecondition value);
        // True when no worker operation holds the clipboard. CanDestroy passes
        // allowUnderBusy so the lifecycle race can still be observed.
        bool CheckNotBusy(bool allowUnderBusy = false);

        // Acquires busy, builds the busy token and hands the work to the thread pool.
        void StartWorkerOperation(std::wstring method,
                                  WorkerPrecondition precondition,
                                  std::function<WorkerResult()> work);
        // Runs work on the thread pool. Holds no state guard of its own.
        void RunOnWorker(std::wstring method,
                         std::function<WorkerResult()> work,
                         std::shared_ptr<void> busyToken);

        void SetResultText(std::wstring const& text);
        void ShowResult(std::wstring const& method, DWORD err, std::wstring const& detail);
        void ShowSampleFailure(std::wstring const& method, std::wstring const& detail);
        void AppendLog(std::wstring const& line);
        void RefreshStateText(std::wstring const& latest);

        void OnRequestCompleted(uint32_t requestId, DWORD error, winrt::hstring const& json);
        void RegisterHistoryRequest(uint32_t requestId, std::wstring const& method, DWORD acceptError);

        // Identity of this page instance, assigned on every navigation to it.
        // Callbacks name this so a completion cannot leak into a later instance.
        uint64_t                         m_pageId{ 0 };
        std::map<uint32_t, std::wstring> m_pendingRequests;
        uint32_t                         m_lastRequestId{ 0 };
        std::wstring                     m_lastHistoryItemId;
        std::deque<std::wstring>         m_logLines;
    };
}

namespace winrt::WindowsLibraryExample::factory_implementation
{
    struct ClipboardPage : ClipboardPageT<ClipboardPage, implementation::ClipboardPage>
    {
    };
}
