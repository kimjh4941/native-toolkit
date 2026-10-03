#include "pch.h"
#include "ClipboardPage.xaml.h"
#if __has_include("ClipboardPage.g.cpp")
#include "ClipboardPage.g.cpp"
#endif

#include "SampleLog.h"
#include "NativeToolkit/Clipboard.h"

#include <winrt/Windows.System.Threading.h>

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <ctime>
#include <optional>
#include <span>
#include <vector>

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using winrt::Windows::System::Threading::ThreadPool;

namespace Clipboard = NativeToolkit::Clipboard;

static const wchar_t* TAG = L"ClipboardPage";

namespace
{
    // -----------------------------------------------------------------------
    // Process-lifetime state
    //
    // The session outlives the page: navigating away does not close it, so the
    // "is it usable" state cannot live in a page member (a new page instance
    // would report false while the session is still open).
    // -----------------------------------------------------------------------

    // The one Session this process may have. Created and closed on the owner
    // UI thread only. Worker operations read it while the busy flag is held,
    // and the lifecycle buttons refuse to run under busy, so the two never
    // overlap.
    std::optional<Clipboard::Session> g_session;

    // Three states, not a bool: once the owner UI thread calls Close the
    // lifecycle gate is closed even when Close fails, so "open" and "usable"
    // are no longer the same thing.
    enum class ManagerState
    {
        Uninitialized,
        Ready,
        ShuttingDown,
    };

    std::atomic<ManagerState> g_managerState{ ManagerState::Uninitialized };
    std::atomic<bool> g_workerBusy{ false };

    // Releases the worker busy flag when the last copy of the token is
    // destroyed. This destructor is the only place that clears g_workerBusy,
    // so every worker exit path (normal completion, work exception, enqueue
    // failure, dead page) releases it without an explicit call.
    class BusyLease final
    {
    public:
        BusyLease() = default;
        ~BusyLease() noexcept { g_workerBusy.store(false); }
        BusyLease(const BusyLease&) = delete;
        BusyLease& operator=(const BusyLease&) = delete;
    };

    // Forwarding hub. The session's handlers are installed once, when it is
    // created, so they forward to these, which the active page registers on
    // navigation and clears on navigation away.
    winrt::Microsoft::UI::Dispatching::DispatcherQueue g_dispatcher{ nullptr };
    std::function<void(std::wstring)> g_logSink;
    std::function<void(uint32_t, DWORD, winrt::hstring)> g_requestSink;

    // Identifies the page instance that is currently on screen. Every navigation
    // to the page takes a fresh id, so work can name the page it belongs to and be
    // dropped when that page is gone. Zero means no page is showing.
    //
    // Tagging at post time is not enough on its own: a request completing after
    // the page was left would pick up whatever id is current, which is the id the
    // re-entered page runs under. Request completions therefore carry the id of
    // the page that issued them (see g_requestOwners).
    std::atomic<uint64_t> g_nextPageId{ 1 };
    std::atomic<uint64_t> g_activePageId{ 0 };

    // requestId -> id of the page that issued it. Only touched on the owner UI
    // thread (accept and completion both run there), so it needs no lock.
    std::map<uint32_t, uint64_t> g_requestOwners;

    // Deferred payloads are finalized at reservation time, so the provider
    // hands back exactly what was decided when the formats were offered.
    std::map<std::wstring, std::vector<std::byte>> g_deferredPayloads;

    const wchar_t* const kSampleText = L"Hello from native-toolkit";
    const wchar_t* const kSampleHtmlFragment = L"<b>Hello</b> from native-toolkit";
    const wchar_t* const kCustomFormatName = L"NativeToolkitSample";

    // ---- Results ----------------------------------------------------------

    // The error code a result is reported with: 0 for success, otherwise the
    // ClipboardError value (the same numbers as the C ABI's constants).
    constexpr DWORD kNoError = 0;

    DWORD CodeOf(Clipboard::ErrorCode code)
    {
        return static_cast<DWORD>(code);
    }

    template <class T>
    DWORD CodeOf(Clipboard::Result<T> const& result)
    {
        return result.has_value() ? kNoError : CodeOf(result.error().code);
    }

    // Runs call against the session, or reports NotInitialized when there is
    // none, which is what the session itself says once it is closed.
    template <class F>
    auto WithSession(F&& call) -> decltype(call(std::declval<Clipboard::Session&>()))
    {
        if (!g_session.has_value())
        {
            return NativeToolkit::Unexpected{ Clipboard::Error{ Clipboard::ErrorCode::NotInitialized } };
        }
        return call(*g_session);
    }

    // Closes the session. It is only dropped once Close succeeds: until then it
    // is still ours to close, and a later attempt can finish the job.
    bool CloseSession(DWORD& error)
    {
        error = kNoError;
        if (!g_session.has_value())
        {
            return true;
        }
        const auto closed = g_session->Close();
        if (!closed.has_value())
        {
            error = CodeOf(closed);
            return false;
        }
        g_session.reset();
        return true;
    }

    void PostLog(std::wstring line)
    {
        auto dispatcher = g_dispatcher;
        if (!dispatcher)
        {
            return;
        }
        // A live event belongs to the page that is showing when it happens.
        const uint64_t pageId = g_activePageId.load();
        if (pageId == 0)
        {
            return;
        }
        dispatcher.TryEnqueue([line = std::move(line), pageId]()
        {
            if (pageId != g_activePageId.load())
            {
                return;
            }
            if (g_logSink)
            {
                g_logSink(line);
            }
        });
    }

    // ---- JSON for display -------------------------------------------------
    //
    // History results arrive as values; the page shows them as JSON, the shape
    // a reader of the log is used to.

    // Escapes a path (or any short literal) for embedding in a JSON string.
    std::wstring JsonEscape(const std::wstring& value)
    {
        std::wstring out;
        out.reserve(value.size() + 8);
        for (const wchar_t c : value)
        {
            switch (c)
            {
            case L'\\': out += L"\\\\"; break;
            case L'"':  out += L"\\\""; break;
            case L'\n': out += L"\\n"; break;
            case L'\r': out += L"\\r"; break;
            case L'\t': out += L"\\t"; break;
            default:    out.push_back(c); break;
            }
        }
        return out;
    }

    std::wstring JsonString(const std::wstring& value)
    {
        return L"\"" + JsonEscape(value) + L"\"";
    }

    std::wstring JsonStringArray(const std::vector<std::wstring>& values)
    {
        std::wstring out = L"[";
        for (size_t i = 0; i < values.size(); ++i)
        {
            if (i > 0) out += L",";
            out += JsonString(values[i]);
        }
        return out + L"]";
    }

    std::wstring HistoryJson(const std::vector<Clipboard::HistoryItem>& items)
    {
        std::wstring out = L"[";
        for (size_t i = 0; i < items.size(); ++i)
        {
            const auto& item = items[i];
            if (i > 0) out += L",";
            out += L"{\"id\":" + JsonString(item.id);
            if (item.text.has_value())
            {
                out += L",\"text\":" + JsonString(*item.text);
            }
            out += L",\"contentTypes\":" + JsonStringArray(item.contentTypes);
            out += L",\"timestamp\":\"" + std::to_wstring(item.timestampTicks) + L"\"}";
        }
        return out + L"]";
    }

    std::wstring AvailabilityJson(const Clipboard::HistoryAvailability& availability)
    {
        return std::wstring(L"{\"historyEnabled\":") + (availability.historyEnabled ? L"true" : L"false") +
               L",\"roamingEnabled\":" + (availability.roamingEnabled ? L"true" : L"false") + L"}";
    }

    // ---- Session handlers (owner UI thread) -------------------------------

    void OnClipboardChanged()
    {
        DLog(TAG, L"[OnClipboardChanged]");
        PostLog(L"[Monitor] clipboard content changed");
    }

    void OnHistoryChanged()
    {
        DLog(TAG, L"[OnHistoryChanged]");
        PostLog(L"[History] a new item was added to the history");
    }

    void OnHistoryEnabledChanged(bool enabled)
    {
        DFLog(TAG, L"[OnHistoryEnabledChanged] enabled: %d", enabled ? 1 : 0);
        PostLog(std::wstring(L"[History] history enabled changed: ") + (enabled ? L"true" : L"false"));
    }

    void OnRoamingEnabledChanged(bool enabled)
    {
        DFLog(TAG, L"[OnRoamingEnabledChanged] enabled: %d", enabled ? 1 : 0);
        PostLog(std::wstring(L"[History] roaming enabled changed: ") + (enabled ? L"true" : L"false"));
    }

    // Every history request completes here, with its result already turned
    // into a code and a JSON string for display.
    void DeliverRequestCompletion(uint32_t requestId, DWORD error, std::wstring json)
    {
        DFLog(TAG, L"[DeliverRequestCompletion] id: %u, error: %lu", requestId, error);
        winrt::hstring payload{ json };
        auto dispatcher = g_dispatcher;
        if (!dispatcher)
        {
            return;
        }
        // Deliver only to the page that issued the request. Looking up the owner
        // here, rather than tagging with whatever page is current, is what keeps a
        // completion that arrives after the page was left out of the next page.
        uint64_t owner = 0;
        const auto entry = g_requestOwners.find(requestId);
        if (entry != g_requestOwners.end())
        {
            owner = entry->second;
            g_requestOwners.erase(entry);
        }

        dispatcher.TryEnqueue([requestId, error, payload, owner]()
        {
            if (owner == 0 || owner != g_activePageId.load())
            {
                return;
            }
            if (g_requestSink)
            {
                g_requestSink(requestId, error, payload);
            }
        });
    }

    void OnHistoryItems(Clipboard::RequestId id, Clipboard::Result<std::vector<Clipboard::HistoryItem>> result)
    {
        DeliverRequestCompletion(static_cast<uint32_t>(id), CodeOf(result),
                                 result.has_value() ? HistoryJson(result.value()) : std::wstring());
    }

    void OnAvailability(Clipboard::RequestId id, Clipboard::Result<Clipboard::HistoryAvailability> result)
    {
        DeliverRequestCompletion(static_cast<uint32_t>(id), CodeOf(result),
                                 result.has_value() ? AvailabilityJson(result.value()) : std::wstring());
    }

    void OnRequestDone(Clipboard::RequestId id, Clipboard::Result<void> result)
    {
        DeliverRequestCompletion(static_cast<uint32_t>(id), CodeOf(result), std::wstring());
    }

    uint32_t IdOf(Clipboard::Result<Clipboard::RequestId> const& accepted)
    {
        return accepted.has_value() ? static_cast<uint32_t>(accepted.value()) : 0u;
    }

    // Runs on the owner UI thread while the system asks for a deferred format:
    // must not touch XAML and must not block.
    Clipboard::Result<std::vector<std::byte>> RenderDeferredFormat(std::wstring_view formatName)
    {
        try
        {
            const std::wstring name{ formatName };
            const auto it = g_deferredPayloads.find(name);
            if (it == g_deferredPayloads.end())
            {
                return NativeToolkit::Unexpected{ Clipboard::Error{ Clipboard::ErrorCode::FormatUnavailable } };
            }
            PostLog(L"[Provider] format=" + name + L" phase=fill size=" +
                    std::to_wstring(it->second.size()) + L" result=0");
            return it->second;
        }
        catch (...)
        {
            return NativeToolkit::Unexpected{ Clipboard::Error{ Clipboard::ErrorCode::Unknown } };
        }
    }

    Clipboard::SessionOptions MakeSessionOptions()
    {
        Clipboard::SessionOptions options;
        options.onClipboardChanged = &OnClipboardChanged;
        return options;
    }

    // ---- Write options ----------------------------------------------------

    const Clipboard::WriteOptions kPlain{};
    // Sensitive is both exclusions at once.
    const Clipboard::WriteOptions kSensitive{ true, true };
    const Clipboard::WriteOptions kExcludeHistory{ true, false };
    const Clipboard::WriteOptions kExcludeRoaming{ false, true };

    // ---- Sample data ------------------------------------------------------

    std::string WideToUtf8(const std::wstring& value)
    {
        if (value.empty())
        {
            return std::string();
        }
        const int needed = ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                                 static_cast<int>(value.size()),
                                                 nullptr, 0, nullptr, nullptr);
        if (needed <= 0)
        {
            return std::string();
        }
        std::string out(static_cast<size_t>(needed), '\0');
        ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                              out.data(), needed, nullptr, nullptr);
        return out;
    }

    std::wstring Utf8ToWide(const std::string& value)
    {
        if (value.empty())
        {
            return std::wstring();
        }
        const int needed = ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                                 static_cast<int>(value.size()), nullptr, 0);
        if (needed <= 0)
        {
            return std::wstring();
        }
        std::wstring out(static_cast<size_t>(needed), L'\0');
        ::MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                              out.data(), needed);
        return out;
    }

    // 8x8, 32bpp, BI_RGB solid colour. Built in code so the sample needs no asset.
    std::vector<std::byte> BuildSampleDib()
    {
        const LONG width = 8;
        const LONG height = 8;
        const size_t pixelBytes = static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;

        std::vector<std::byte> dib(sizeof(BITMAPINFOHEADER) + pixelBytes, std::byte{ 0 });
        auto* header = reinterpret_cast<BITMAPINFOHEADER*>(dib.data());
        header->biSize = sizeof(BITMAPINFOHEADER);
        header->biWidth = width;
        header->biHeight = height;
        header->biPlanes = 1;
        header->biBitCount = 32;
        header->biCompression = BI_RGB;
        header->biSizeImage = static_cast<DWORD>(pixelBytes);

        std::byte* pixels = dib.data() + sizeof(BITMAPINFOHEADER);
        for (size_t i = 0; i < pixelBytes; i += 4)
        {
            pixels[i + 0] = std::byte{ 0xD7 }; // blue
            pixels[i + 1] = std::byte{ 0x78 }; // green
            pixels[i + 2] = std::byte{ 0x00 }; // red
            pixels[i + 3] = std::byte{ 0xFF }; // alpha
        }
        return dib;
    }

    std::vector<std::byte> ToBytes(const std::string& value)
    {
        const auto view = std::as_bytes(std::span(value.data(), value.size()));
        return std::vector<std::byte>(view.begin(), view.end());
    }

    // CF_HTML payload with a byte-offset header. Offsets are computed from fixed
    // prefix lengths, and the numeric fields use a fixed width so re-formatting
    // with the real values cannot change the header length.
    std::vector<std::byte> BuildCfHtmlBytes(const std::string& utf8Fragment)
    {
        const std::string prefix = "<html><body><!--StartFragment-->";
        const std::string suffix = "<!--EndFragment--></body></html>";
        const char* format =
            "Version:0.9\r\n"
            "StartHTML:%010zu\r\n"
            "EndHTML:%010zu\r\n"
            "StartFragment:%010zu\r\n"
            "EndFragment:%010zu\r\n";

        char probe[256] = {};
        const int headerLength = std::snprintf(probe, sizeof(probe), format,
                                               size_t{ 0 }, size_t{ 0 }, size_t{ 0 }, size_t{ 0 });
        if (headerLength <= 0)
        {
            return std::vector<std::byte>();
        }

        const size_t startHtml = static_cast<size_t>(headerLength);
        const size_t startFragment = startHtml + prefix.size();
        const size_t endFragment = startFragment + utf8Fragment.size();
        const size_t endHtml = endFragment + suffix.size();

        char header[256] = {};
        const int written = std::snprintf(header, sizeof(header), format,
                                          startHtml, endHtml, startFragment, endFragment);
        if (written != headerLength)
        {
            return std::vector<std::byte>();
        }

        std::string payload;
        payload.reserve(endHtml);
        payload.append(header, static_cast<size_t>(written));
        payload.append(prefix);
        payload.append(utf8Fragment);
        payload.append(suffix);

        return ToBytes(payload);
    }

    std::vector<std::byte> BuildUnicodeTextBytes(const std::wstring& text)
    {
        std::vector<std::byte> bytes((text.size() + 1) * sizeof(wchar_t), std::byte{ 0 });
        ::memcpy(bytes.data(), text.c_str(), text.size() * sizeof(wchar_t));
        return bytes;
    }

    std::wstring TempFilePath(int index)
    {
        wchar_t buffer[MAX_PATH] = {};
        const DWORD length = ::GetTempPathW(MAX_PATH, buffer);
        if (length == 0 || length > MAX_PATH)
        {
            return std::wstring();
        }
        return std::wstring(buffer) + L"native-toolkit-clipboard-sample-" + std::to_wstring(index) + L".txt";
    }

    bool WriteSampleFile(const std::wstring& path, const std::string& content)
    {
        HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return false;
        }
        DWORD written = 0;
        const BOOL ok = ::WriteFile(file, content.data(), static_cast<DWORD>(content.size()), &written, nullptr);
        ::CloseHandle(file);
        return ok != FALSE && written == content.size();
    }

    std::wstring Preview(const std::wstring& value, size_t limit)
    {
        if (value.size() <= limit)
        {
            return value;
        }
        return value.substr(0, limit) + L"...";
    }

    std::wstring Timestamp()
    {
        SYSTEMTIME now = {};
        ::GetLocalTime(&now);
        wchar_t buffer[16] = {};
        std::swprintf(buffer, 16, L"%02u:%02u:%02u", now.wHour, now.wMinute, now.wSecond);
        return std::wstring(buffer);
    }
}

namespace winrt::WindowsLibraryExample::implementation
{
    ClipboardPage::ClipboardPage()
    {
        InitializeComponent();
    }

    // -----------------------------------------------------------------------
    // Navigation
    // -----------------------------------------------------------------------

    void ClipboardPage::OnNavigatedTo(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const&)
    {
        DLog(TAG, L"[OnNavigatedTo] register clipboard handlers");

        // A fresh id per navigation: work tagged for the previous instance is
        // dropped even if the user comes straight back.
        m_pageId = g_nextPageId.fetch_add(1);
        g_activePageId.store(m_pageId);

        g_dispatcher = DispatcherQueue();

        auto weakPage = get_weak();
        g_logSink = [weakPage](std::wstring line)
        {
            if (auto page = weakPage.get())
            {
                page->AppendLog(line);
            }
        };
        g_requestSink = [weakPage](uint32_t requestId, DWORD error, winrt::hstring json)
        {
            if (auto page = weakPage.get())
            {
                page->OnRequestCompleted(requestId, error, json);
            }
        };

        RefreshStateText(L"Ready to test. Press InitializeManager first.");
    }

    void ClipboardPage::OnNavigatedFrom(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const&)
    {
        DLog(TAG, L"[OnNavigatedFrom] clear clipboard handlers");
        // No page is showing: anything still queued is dropped when it runs.
        g_activePageId.store(0);
        // Callbacks delivered while the page is away are dropped and are not
        // replayed on re-entry. The session itself stays open.
        g_logSink = nullptr;
        g_requestSink = nullptr;
    }

    void ClipboardPage::BackButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[BackButton_Click]");
        if (Frame() && Frame().CanGoBack())
        {
            Frame().GoBack();
        }
    }

    // -----------------------------------------------------------------------
    // Display helpers
    // -----------------------------------------------------------------------

    void ClipboardPage::SetResultText(std::wstring const& text)
    {
        ResultTextBlock().Text(winrt::hstring(text));
    }

    void ClipboardPage::RefreshStateText(std::wstring const& latest)
    {
        const wchar_t* state = L"Uninitialized";
        switch (g_managerState.load())
        {
        case ManagerState::Ready:        state = L"Ready"; break;
        case ManagerState::ShuttingDown: state = L"Shutting down"; break;
        default:                         state = L"Uninitialized"; break;
        }
        SetResultText(latest + L"\nmanager state: " + state);
    }

    void ClipboardPage::ShowResult(std::wstring const& method, DWORD err, std::wstring const& detail)
    {
        std::wstring text = (err == kNoError ? L"✅ " : L"❌ ") +
                            std::wstring(L"[") + method + L"] errorCode=" + std::to_wstring(err);

        switch (static_cast<Clipboard::ErrorCode>(err))
        {
        case Clipboard::ErrorCode::NotInitialized:
            // Press Initialize only helps when nothing is shutting down: while a
            // closed-but-not-finished session exists, a new one is refused.
            text += (g_managerState.load() == ManagerState::ShuttingDown)
                        ? L" - Press CanDestroy, then Uninitialize again."
                        : L" - Press InitializeManager first.";
            break;
        case Clipboard::ErrorCode::Empty:
            text += L" - The clipboard is empty.";
            break;
        case Clipboard::ErrorCode::FormatUnavailable:
            text += L" - The requested format is not on the clipboard.";
            break;
        case Clipboard::ErrorCode::HistoryDisabled:
            text += L" - Enable clipboard history in Windows Settings.";
            break;
        case Clipboard::ErrorCode::PartialState:
            text += L" - Press RecoverDeferredState.";
            break;
        case Clipboard::ErrorCode::WrongThread:
            text += L" - This API is limited to the owner UI thread.";
            break;
        case Clipboard::ErrorCode::Canceled:
            text += L" - Wait for the pending callbacks, then retry.";
            break;
        case Clipboard::ErrorCode::NotForeground:
            text += L" - Bring this app to the foreground and retry.";
            break;
        case Clipboard::ErrorCode::WrongApartment:
            text += L" - The calling thread is not an initialized STA.";
            break;
        default:
            break;
        }

        if (!detail.empty())
        {
            text += L"\n" + detail;
        }
        RefreshStateText(text);
    }

    void ClipboardPage::ShowSampleFailure(std::wstring const& method, std::wstring const& detail)
    {
        // Never reported as a Clipboard domain error: this is the sample failing,
        // not the toolkit.
        RefreshStateText(L"❌ [" + method + L"] Sample operation failed: " + detail);
    }

    void ClipboardPage::AppendLog(std::wstring const& line)
    {
        m_logLines.push_back(Timestamp() + L"  " + line);
        while (m_logLines.size() > 200)
        {
            m_logLines.pop_front();
        }

        std::wstring text;
        for (const auto& entry : m_logLines)
        {
            text += entry;
            text += L"\n";
        }
        LogTextBlock().Text(winrt::hstring(text));
        LogScrollViewer().ChangeView(nullptr, LogScrollViewer().ScrollableHeight(), nullptr);
    }

    // -----------------------------------------------------------------------
    // Guards and worker plumbing
    // -----------------------------------------------------------------------

    bool ClipboardPage::CheckPrecondition(WorkerPrecondition value)
    {
        const ManagerState state = g_managerState.load();
        switch (value)
        {
        case WorkerPrecondition::AnyState:
        case WorkerPrecondition::NoStateGuard:
            return true;

        case WorkerPrecondition::ReadyRequired:
            if (state == ManagerState::Ready)
            {
                return true;
            }
            RefreshStateText(state == ManagerState::ShuttingDown
                ? L"❌ Shutting down. Press CanDestroy, then Uninitialize again."
                : L"❌ Not initialized. Press InitializeManager first.");
            return false;

        case WorkerPrecondition::ShuttingDownRequired:
            if (state == ManagerState::ShuttingDown)
            {
                return true;
            }
            RefreshStateText(L"❌ Requires the shutting-down state. Press "
                             L"\"Request + Immediate Uninitialize\" first.");
            return false;
        }
        return false;
    }

    bool ClipboardPage::CheckNotBusy(bool allowUnderBusy)
    {
        if (allowUnderBusy || !g_workerBusy.load())
        {
            return true;
        }
        // Every copy and every deferred-rendering call takes the same self-write
        // mutex for the whole operation, so starting one from the UI thread while
        // a worker holds it would block the UI thread.
        RefreshStateText(L"❌ Busy: another clipboard operation is running");
        return false;
    }

    ClipboardPage::WorkerResult ClipboardPage::MakeApiResult(DWORD err,
                                                            std::wstring detail,
                                                            std::wstring logLine)
    {
        WorkerResult result;
        result.outcome = WorkerOutcome::ApiResult;
        result.apiError = err;
        result.detail = std::move(detail);
        result.logLine = std::move(logLine);
        return result;
    }

    void ClipboardPage::StartWorkerOperation(std::wstring method,
                                             WorkerPrecondition precondition,
                                             std::function<WorkerResult()> work)
    {
        if (!CheckPrecondition(precondition))
        {
            return;
        }
        if (g_workerBusy.exchange(true))
        {
            RefreshStateText(L"❌ Busy: another clipboard operation is running");
            return;
        }

        std::shared_ptr<void> busyToken;
        try
        {
            busyToken = std::make_shared<BusyLease>();
            RunOnWorker(method, std::move(work), busyToken);
        }
        catch (...)
        {
            // Only a failure before the lease exists needs an explicit clear;
            // once it exists, leaving this scope destroys it and releases busy.
            if (!busyToken)
            {
                g_workerBusy.store(false);
            }
            ShowSampleFailure(method, L"Could not start the worker operation");
        }
    }

    void ClipboardPage::RunOnWorker(std::wstring method,
                                    std::function<WorkerResult()> work,
                                    std::shared_ptr<void> busyToken)
    {
        auto weakPage = get_weak();
        auto dispatcher = DispatcherQueue();

        ThreadPool::RunAsync([weakPage,
                              dispatcher,
                              method = std::move(method),
                              work = std::move(work),
                              busyToken](auto&&)
        {
            WorkerResult result;
            try
            {
                result = work();
            }
            catch (std::bad_alloc const&)
            {
                // Only an enum is updated: building a string here could fail again.
                result.outcome = WorkerOutcome::SampleOutOfMemory;
            }
            catch (winrt::hresult_error const& e)
            {
                result.outcome = WorkerOutcome::SampleWinRtFailure;
                result.sampleHresult = e.code();
            }
            catch (...)
            {
                result.outcome = WorkerOutcome::SampleFailure;
            }

            try
            {
                dispatcher.TryEnqueue([weakPage,
                                       method,
                                       result,
                                       busyToken]()
                {
                    if (auto page = weakPage.get())
                    {
                        page->CompleteWorkerOperation(method, result);
                    }
                });
            }
            catch (...)
            {
                // No allocation and no UI access here. Destroying the captured
                // token releases the busy flag on the way out.
            }
        });
    }

    void ClipboardPage::CompleteWorkerOperation(std::wstring const& method, WorkerResult const& result)
    {
        if (!result.logOnly)
        {
            switch (result.outcome)
            {
            case WorkerOutcome::ApiResult:
                ShowResult(method, result.apiError, result.detail);
                break;
            case WorkerOutcome::SampleOutOfMemory:
                ShowSampleFailure(method, L"Out of memory in sample code");
                break;
            case WorkerOutcome::SampleWinRtFailure:
            {
                wchar_t code[48] = {};
                std::swprintf(code, 48, L"WinRT error 0x%08lX in sample code",
                              static_cast<unsigned long>(result.sampleHresult));
                ShowSampleFailure(method, code);
                break;
            }
            default:
                ShowSampleFailure(method, result.detail.empty()
                                              ? std::wstring(L"Unexpected sample-side failure")
                                              : result.detail);
                break;
            }
        }

        if (!result.logLine.empty())
        {
            AppendLog(result.logLine);
        }
    }

    // -----------------------------------------------------------------------
    // History request bookkeeping
    // -----------------------------------------------------------------------

    void ClipboardPage::RegisterHistoryRequest(uint32_t requestId,
                                               std::wstring const& method,
                                               DWORD acceptError)
    {
        if (requestId == 0)
        {
            // Rejected before acceptance: the handler will never run.
            ShowResult(method, acceptError, L"Request was not accepted");
            return;
        }

        m_pendingRequests[requestId] = method;
        m_lastRequestId = requestId;
        g_requestOwners[requestId] = m_pageId;
        RefreshStateText(L"✅ [" + method + L"] accepted requestId=" +
                         std::to_wstring(requestId) + L" (waiting for the callback)");
        AppendLog(L"[Request] accepted id=" + std::to_wstring(requestId) + L" " + method);
    }

    void ClipboardPage::OnRequestCompleted(uint32_t requestId, DWORD error, winrt::hstring const& json)
    {
        const auto it = m_pendingRequests.find(requestId);
        if (it == m_pendingRequests.end())
        {
            // Issued before navigating away: the UI state for it is gone.
            AppendLog(L"[Request] unknown request id=" + std::to_wstring(requestId) +
                      L" error=" + std::to_wstring(error));
            return;
        }

        const std::wstring method = it->second;
        m_pendingRequests.erase(it);

        std::wstring payload{ json };
        std::wstring detail;

        if (error == kNoError && !payload.empty())
        {
            detail = Preview(payload, 160);

            if (method.rfind(L"GetClipboardHistory", 0) == 0)
            {
                try
                {
                    auto items = winrt::Windows::Data::Json::JsonArray::Parse(json);
                    if (items.Size() > 0)
                    {
                        m_lastHistoryItemId = std::wstring(items.GetObjectAt(0).GetNamedString(L"id"));
                        detail = L"count=" + std::to_wstring(items.Size()) +
                                 L", first id=" + m_lastHistoryItemId + L"\n" + detail;
                    }
                    else
                    {
                        m_lastHistoryItemId.clear();
                        detail = L"count=0\n" + detail;
                    }
                }
                catch (...)
                {
                    AppendLog(L"[Request] history JSON parse failed");
                }
            }
        }

        ShowResult(method, error, detail);
        AppendLog(L"[Request] completed id=" + std::to_wstring(requestId) + L" " + method +
                  L" error=" + std::to_wstring(error));
    }

    // -----------------------------------------------------------------------
    // Init / Lifecycle
    // -----------------------------------------------------------------------

    void ClipboardPage::InitializeManager_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[InitializeManager_Click]");
        if (!CheckNotBusy())
        {
            return;
        }
        if (g_managerState.load() == ManagerState::ShuttingDown)
        {
            // The closing session still exists, so a new one would be refused;
            // point at the retry path instead.
            RefreshStateText(L"❌ Shutting down. Press CanDestroy, then Uninitialize again.");
            return;
        }

        DWORD err = kNoError;
        if (!g_session.has_value())
        {
            auto created = Clipboard::Session::Create(MakeSessionOptions());
            err = CodeOf(created);
            if (created.has_value())
            {
                g_session.emplace(std::move(created).value());
            }
        }
        // Otherwise it was opened on an earlier visit to the page and is still open.

        if (err == kNoError)
        {
            g_managerState.store(ManagerState::Ready);
        }
        ShowResult(L"InitializeManager", err, L"");
    }

    void ClipboardPage::SetHistoryCallbacks_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[SetHistoryCallbacks_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        Clipboard::HistoryHandlers handlers;
        handlers.onHistoryChanged = &OnHistoryChanged;
        handlers.onHistoryEnabledChanged = &OnHistoryEnabledChanged;
        handlers.onRoamingEnabledChanged = &OnRoamingEnabledChanged;
        const auto result = WithSession([&](Clipboard::Session& session)
        {
            return session.SetHistoryHandlers(std::move(handlers));
        });
        ShowResult(L"SetHistoryCallbacks", CodeOf(result), L"");
    }

    void ClipboardPage::Uninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[Uninitialize_Click]");
        if (!CheckNotBusy())
        {
            return;
        }
        if (g_managerState.load() == ManagerState::Uninitialized)
        {
            RefreshStateText(L"❌ Not initialized. Press InitializeManager first.");
            return;
        }

        DWORD err = kNoError;
        const bool done = CloseSession(err);
        AppendLog(L"[Lifecycle] uninit returned " + std::wstring(done ? L"TRUE" : L"FALSE") +
                  L" errorCode=" + std::to_wstring(err));

        if (done)
        {
            g_managerState.store(ManagerState::Uninitialized);
            RefreshStateText(L"✅ [Uninitialize] errorCode=" + std::to_wstring(err) +
                             L"\nUninitialize succeeded; temp cleanup pending");

            // Cleanup is a separate asynchronous step: its result is logged and
            // never replaces the Uninitialize result above.
            StartWorkerOperation(L"Temp cleanup", WorkerPrecondition::AnyState,
                []() -> WorkerResult
                {
                    int removed = 0;
                    int failed = 0;
                    for (int i = 1; i <= 2; ++i)
                    {
                        const std::wstring path = TempFilePath(i);
                        if (path.empty())
                        {
                            continue;
                        }
                        if (::DeleteFileW(path.c_str()))
                        {
                            ++removed;
                        }
                        else if (::GetLastError() != ERROR_FILE_NOT_FOUND)
                        {
                            ++failed;
                        }
                    }

                    WorkerResult result = MakeApiResult(kNoError);
                    result.logOnly = true;
                    result.logLine = failed == 0
                        ? L"[Cleanup] temp cleanup succeeded (removed " + std::to_wstring(removed) + L")"
                        : L"[Cleanup] temp cleanup failed (" + std::to_wstring(failed) + L" files)";
                    return result;
                });
            return;
        }

        g_managerState.store(ManagerState::ShuttingDown);
        std::wstring hint = L"Uninitialize pending: waiting for callbacks. "
                            L"Press CanDestroy, then Uninitialize again.";
        if (err == CodeOf(Clipboard::ErrorCode::MonitorRegisterFailed))
        {
            hint = L"Listener teardown failed. Press CanDestroy, then Uninitialize again.";
        }
        RefreshStateText(L"❌ [Uninitialize] returned FALSE, errorCode=" +
                         std::to_wstring(err) + L"\n" + hint);
    }

    void ClipboardPage::CanDestroy_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CanDestroy_Click]");
        // Allowed while a worker runs: this is how the lifecycle race is observed.
        if (!CheckNotBusy(true))
        {
            return;
        }

        // No session is as closable as it gets.
        const bool canClose = !g_session.has_value() || g_session->CanClose();
        ShowResult(L"CanDestroy", kNoError,
                   std::wstring(L"returned ") + (canClose ? L"TRUE" : L"FALSE"));
    }

    // -----------------------------------------------------------------------
    // Copy
    // -----------------------------------------------------------------------

    void ClipboardPage::CopyPlainText_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyPlainText_Click]");
        StartWorkerOperation(L"CopyPlainText", WorkerPrecondition::ReadyRequired,
            [text = std::wstring(kSampleText)]() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyText(text, kPlain);
                })));
            });
    }

    void ClipboardPage::CopyPlainTextEmpty_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyPlainTextEmpty_Click]");
        StartWorkerOperation(L"CopyPlainText (empty)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.CopyText(L"", kPlain);
                })), L"An empty string is a valid payload");
            });
    }

    void ClipboardPage::CopyHtml_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyHtml_Click]");
        StartWorkerOperation(L"CopyHtml", WorkerPrecondition::ReadyRequired,
            [html = std::wstring(kSampleHtmlFragment), text = std::wstring(kSampleText)]() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyHtml(html, text, kPlain);
                })));
            });
    }

    void ClipboardPage::CopyFiles_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyFiles_Click]");
        StartWorkerOperation(L"CopyFiles", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::wstring first = TempFilePath(1);
                const std::wstring second = TempFilePath(2);
                if (first.empty() || second.empty())
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = L"Could not resolve the temp directory";
                    return failure;
                }
                if (!WriteSampleFile(first, "Clipboard sample file 1") ||
                    !WriteSampleFile(second, "Clipboard sample file 2"))
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = L"Could not write the sample files";
                    return failure;
                }

                const std::vector<std::wstring> paths{ first, second };
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyFiles(paths, kPlain);
                });
                return MakeApiResult(CodeOf(result), L"2 files", L"[Copy] files: " + first + L", " + second);
            });
    }

    void ClipboardPage::CopyImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyImage_Click]");
        StartWorkerOperation(L"CopyImage", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<std::byte> dib = BuildSampleDib();
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyDib(dib, kPlain);
                });
                return MakeApiResult(CodeOf(result), L"8x8 32bpp DIB, " + std::to_wstring(dib.size()) + L" bytes");
            });
    }

    void ClipboardPage::CopyCustomFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyCustomFormat_Click]");
        StartWorkerOperation(L"CopyCustomFormat", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<std::byte> blob = ToBytes("native-toolkit-sample-payload");
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyCustom(kCustomFormatName, blob, kPlain);
                });
                return MakeApiResult(CodeOf(result), std::wstring(kCustomFormatName) + L", " +
                                                         std::to_wstring(blob.size()) + L" bytes");
            });
    }

    void ClipboardPage::CopyMultipleFormats_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyMultipleFormats_Click]");
        StartWorkerOperation(L"CopyMultipleFormats", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                // Richest format first, as the placement order is part of the contract.
                const std::vector<Clipboard::FormatPayload> items{
                    Clipboard::HtmlPayload{ L"HTML Format", kSampleHtmlFragment },
                    Clipboard::TextPayload{ L"CF_UNICODETEXT", kSampleText },
                };
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyMultiple(items, kPlain);
                });
                return MakeApiResult(CodeOf(result), L"HTML Format + CF_UNICODETEXT");
            });
    }

    void ClipboardPage::CopyMultipleFormatsWithImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyMultipleFormatsWithImage_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (with image)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<Clipboard::FormatPayload> items{
                    Clipboard::HtmlPayload{ L"HTML Format", kSampleHtmlFragment },
                    Clipboard::TextPayload{ L"CF_UNICODETEXT", kSampleText },
                    Clipboard::BytesPayload{ L"CF_DIB", BuildSampleDib() },
                };
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyMultiple(items, kPlain);
                });
                return MakeApiResult(CodeOf(result), L"HTML Format + CF_UNICODETEXT + CF_DIB");
            });
    }

    // -----------------------------------------------------------------------
    // Write options
    // -----------------------------------------------------------------------

    void ClipboardPage::CopySensitive_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopySensitive_Click]");
        StartWorkerOperation(L"CopyPlainText (SENSITIVE)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.CopyText(L"Sensitive sample value", kSensitive);
                })), L"Should not appear in Win+V");
            });
    }

    void ClipboardPage::CopyExcludeHistory_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyExcludeHistory_Click]");
        StartWorkerOperation(L"CopyPlainText (EXCLUDE_HISTORY)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.CopyText(L"History excluded sample value", kExcludeHistory);
                })), L"Should not appear in Win+V");
            });
    }

    void ClipboardPage::CopyExcludeRoaming_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyExcludeRoaming_Click]");
        StartWorkerOperation(L"CopyPlainText (EXCLUDE_ROAMING)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.CopyText(L"Roaming excluded sample value", kExcludeRoaming);
                })), L"Should not sync to another device");
            });
    }

    void ClipboardPage::CleanupTempFiles_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CleanupTempFiles_Click]");
        StartWorkerOperation(L"Cleanup Temp Files", WorkerPrecondition::AnyState,
            []() -> WorkerResult
            {
                int removed = 0;
                int failed = 0;
                for (int i = 1; i <= 2; ++i)
                {
                    const std::wstring path = TempFilePath(i);
                    if (path.empty())
                    {
                        continue;
                    }
                    if (::DeleteFileW(path.c_str()))
                    {
                        ++removed;
                    }
                    else if (::GetLastError() != ERROR_FILE_NOT_FOUND)
                    {
                        ++failed;
                    }
                }

                if (failed > 0)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = L"Could not delete " + std::to_wstring(failed) + L" file(s)";
                    return failure;
                }
                return MakeApiResult(kNoError, L"removed " + std::to_wstring(removed) + L" file(s)");
            });
    }

    // -----------------------------------------------------------------------
    // Paste
    // -----------------------------------------------------------------------

    void ClipboardPage::PastePlainText_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PastePlainText_Click]");
        StartWorkerOperation(L"PastePlainText", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto text = WithSession([](Clipboard::Session& session) { return session.PasteText(); });
                return MakeApiResult(CodeOf(text), text.has_value() ? Preview(text.value(), 100) : L"");
            });
    }

    void ClipboardPage::PasteHtml_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteHtml_Click]");
        StartWorkerOperation(L"PasteHtml", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto html = WithSession([](Clipboard::Session& session) { return session.PasteHtml(); });
                return MakeApiResult(CodeOf(html), html.has_value() ? Preview(html.value(), 100) : L"");
            });
    }

    void ClipboardPage::PasteFiles_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteFiles_Click]");
        StartWorkerOperation(L"PasteFiles", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto files = WithSession([](Clipboard::Session& session) { return session.PasteFiles(); });
                return MakeApiResult(CodeOf(files),
                                     files.has_value() ? Preview(JsonStringArray(files.value()), 160) : L"");
            });
    }

    void ClipboardPage::PasteImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteImage_Click]");
        StartWorkerOperation(L"PasteImage", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto pasted = WithSession([](Clipboard::Session& session) { return session.PasteDib(); });
                if (!pasted.has_value())
                {
                    return MakeApiResult(CodeOf(pasted));
                }
                const auto& dib = pasted.value();

                // The toolkit validates the DIB, but reading the header here is the
                // sample's own dereference and needs its own bounds check first.
                if (dib.size() < sizeof(BITMAPINFOHEADER))
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = L"Invalid DIB header: " + std::to_wstring(dib.size()) + L" bytes";
                    return failure;
                }

                BITMAPINFOHEADER header = {};
                ::memcpy(&header, dib.data(), sizeof(BITMAPINFOHEADER));
                if (header.biSize < sizeof(BITMAPINFOHEADER) || header.biSize > dib.size())
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = L"Invalid DIB header: biSize=" + std::to_wstring(header.biSize) +
                                     L", total=" + std::to_wstring(dib.size());
                    return failure;
                }

                return MakeApiResult(kNoError,
                                     std::to_wstring(dib.size()) + L" bytes, width=" +
                                         std::to_wstring(header.biWidth) + L", height=" +
                                         std::to_wstring(header.biHeight) + L", bitCount=" +
                                         std::to_wstring(header.biBitCount));
            });
    }

    void ClipboardPage::PasteCustomFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteCustomFormat_Click]");
        StartWorkerOperation(L"PasteCustomFormat", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto pasted = WithSession([](Clipboard::Session& session)
                {
                    return session.PasteCustom(kCustomFormatName);
                });
                if (!pasted.has_value())
                {
                    return MakeApiResult(CodeOf(pasted));
                }
                const auto& blob = pasted.value();

                const size_t shown = blob.size() > 32 ? 32 : blob.size();
                const std::string preview(reinterpret_cast<const char*>(blob.data()), shown);
                return MakeApiResult(kNoError, std::to_wstring(blob.size()) + L" bytes: " + Utf8ToWide(preview));
            });
    }

    // -----------------------------------------------------------------------
    // Inspect / Clear
    // -----------------------------------------------------------------------

    void ClipboardPage::HasFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[HasFormat_Click]");
        StartWorkerOperation(L"HasFormat (CF_UNICODETEXT)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto present = WithSession([](Clipboard::Session& session)
                {
                    return session.HasFormat(L"CF_UNICODETEXT");
                });
                const bool yes = present.has_value() && present.value();
                return MakeApiResult(CodeOf(present), std::wstring(L"returned ") + (yes ? L"TRUE" : L"FALSE"));
            });
    }

    void ClipboardPage::GetClipboardFormats_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetClipboardFormats_Click]");
        StartWorkerOperation(L"GetClipboardFormats", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto formats = WithSession([](Clipboard::Session& session) { return session.GetFormats(); });
                return MakeApiResult(CodeOf(formats),
                                     formats.has_value() ? Preview(JsonStringArray(formats.value()), 200) : L"");
            });
    }

    void ClipboardPage::GetPreferredFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetPreferredFormat_Click]");
        StartWorkerOperation(L"GetPreferredFormat", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto name = WithSession([](Clipboard::Session& session)
                {
                    return session.GetPreferredFormat();
                });
                if (!name.has_value())
                {
                    return MakeApiResult(CodeOf(name));
                }
                return MakeApiResult(kNoError,
                                     name.value().empty() ? std::wstring(L"(no candidate format)") : name.value());
            });
    }

    void ClipboardPage::ClearClipboard_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ClearClipboard_Click]");
        StartWorkerOperation(L"ClearClipboard", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.Clear();
                })));
            });
    }

    // -----------------------------------------------------------------------
    // Deferred rendering
    // -----------------------------------------------------------------------

    void ClipboardPage::ReserveDeferredFormats_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ReserveDeferredFormats_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        // Finalize both payloads now, so the provider hands back what was
        // decided when the formats were offered.
        g_deferredPayloads.clear();
        g_deferredPayloads[L"CF_UNICODETEXT"] = BuildUnicodeTextBytes(kSampleText);
        g_deferredPayloads[L"HTML Format"] = BuildCfHtmlBytes(WideToUtf8(kSampleHtmlFragment));

        const std::vector<std::wstring> formats{ L"HTML Format", L"CF_UNICODETEXT" };
        const DWORD err = CodeOf(WithSession([&](Clipboard::Session& session)
        {
            return session.ReserveDeferred(formats, &RenderDeferredFormat);
        }));
        ShowResult(L"ReserveDeferredFormats", err, L"");
        if (err == kNoError)
        {
            AppendLog(L"[Reserve] OK formats=[HTML Format, CF_UNICODETEXT] (provider not called yet)");
        }
    }

    void ClipboardPage::RecoverDeferredState_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RecoverDeferredState_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        const auto result = WithSession([](Clipboard::Session& session) { return session.RecoverDeferredState(); });
        ShowResult(L"RecoverDeferredState", CodeOf(result), L"");
    }

    // -----------------------------------------------------------------------
    // History
    // -----------------------------------------------------------------------

    void ClipboardPage::GetHistoryAvailability_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetHistoryAvailability_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        const auto accepted = WithSession([](Clipboard::Session& session)
        {
            return session.GetHistoryAvailability(&OnAvailability);
        });
        RegisterHistoryRequest(IdOf(accepted), L"GetHistoryAvailability", CodeOf(accepted));
    }

    void ClipboardPage::GetClipboardHistory_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetClipboardHistory_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        const auto accepted = WithSession([](Clipboard::Session& session)
        {
            return session.GetHistory(&OnHistoryItems);
        });
        RegisterHistoryRequest(IdOf(accepted), L"GetClipboardHistory", CodeOf(accepted));
    }

    void ClipboardPage::RestoreHistoryItem_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RestoreHistoryItem_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }
        if (m_lastHistoryItemId.empty())
        {
            RefreshStateText(L"❌ [RestoreHistoryItem] No captured id. Press GetClipboardHistory first.");
            return;
        }

        const auto accepted = WithSession([&](Clipboard::Session& session)
        {
            return session.RestoreHistoryItem(m_lastHistoryItemId, &OnRequestDone);
        });
        RegisterHistoryRequest(IdOf(accepted), L"RestoreHistoryItem", CodeOf(accepted));
    }

    void ClipboardPage::DeleteHistoryItem_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[DeleteHistoryItem_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }
        if (m_lastHistoryItemId.empty())
        {
            RefreshStateText(L"❌ [DeleteHistoryItem] No captured id. Press GetClipboardHistory first.");
            return;
        }

        const auto accepted = WithSession([&](Clipboard::Session& session)
        {
            return session.DeleteHistoryItem(m_lastHistoryItemId, &OnRequestDone);
        });
        const uint32_t id = IdOf(accepted);
        RegisterHistoryRequest(id, L"DeleteHistoryItem", CodeOf(accepted));
        if (id != 0)
        {
            // The captured id is consumed: require a fresh fetch before the next use.
            m_lastHistoryItemId.clear();
        }
    }

    void ClipboardPage::ClearUnpinnedHistory_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ClearUnpinnedHistory_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        const auto accepted = WithSession([](Clipboard::Session& session)
        {
            return session.ClearUnpinnedHistory(&OnRequestDone);
        });
        RegisterHistoryRequest(IdOf(accepted), L"ClearUnpinnedHistory", CodeOf(accepted));
    }

    void ClipboardPage::CancelLastRequest_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CancelLastRequest_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }
        if (m_lastRequestId == 0)
        {
            RefreshStateText(L"❌ [CancelLastRequest] No request id. Issue a history request first.");
            return;
        }

        const auto canceled = WithSession([&](Clipboard::Session& session)
        {
            return session.CancelRequest(Clipboard::RequestId{ m_lastRequestId });
        });
        ShowResult(L"CancelLastRequest", CodeOf(canceled),
                   std::wstring(L"id=") + std::to_wstring(m_lastRequestId) +
                       L", returned " + (canceled.has_value() ? L"TRUE" : L"FALSE"));
    }

    void ClipboardPage::RequestAndImmediateUninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RequestAndImmediateUninitialize_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        // Both calls happen in one handler on purpose: the request is only posted
        // to the dispatch window, so it is still queued when Close runs. Close
        // cancels it and delivers the cancellation itself, so it succeeds at the
        // first attempt and the request is answered once with CANCELED(15).
        // Splitting this across two clicks would let the pump start the request
        // first, and the cancellation path would never be shown.
        const auto accepted = WithSession([](Clipboard::Session& session)
        {
            return session.GetHistory(&OnHistoryItems);
        });
        const uint32_t id = IdOf(accepted);
        if (id != 0)
        {
            m_pendingRequests[id] = L"GetClipboardHistory (immediate uninit)";
            m_lastRequestId = id;
            g_requestOwners[id] = m_pageId;
        }

        DWORD uninitError = kNoError;
        const bool done = CloseSession(uninitError);
        g_managerState.store(done ? ManagerState::Uninitialized : ManagerState::ShuttingDown);

        AppendLog(L"[Lifecycle] request id=" + std::to_wstring(id) +
                  L" then uninit returned " + std::wstring(done ? L"TRUE" : L"FALSE") +
                  L" errorCode=" + std::to_wstring(uninitError));

        RefreshStateText(std::wstring(done ? L"✅ " : L"❌ ") +
                         L"[Request + Immediate Uninitialize] requestId=" + std::to_wstring(id) +
                         L", uninit returned " + (done ? L"TRUE" : L"FALSE") +
                         L", errorCode=" + std::to_wstring(uninitError) +
                         (done ? L"" : L"\nWait for the pending callback, press CanDestroy, then Uninitialize again."));
    }

    // -----------------------------------------------------------------------
    // Threading
    // -----------------------------------------------------------------------

    void ClipboardPage::ReserveDeferredOnWorker_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ReserveDeferredOnWorker_Click]");
        // Ready is required: a closed session reports NOT_INITIALIZED before it
        // ever checks the calling thread.
        StartWorkerOperation(L"ReserveDeferred (worker thread)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<std::wstring> formats{ L"CF_UNICODETEXT" };
                const auto result = WithSession([&](Clipboard::Session& session)
                {
                    return session.ReserveDeferred(formats, &RenderDeferredFormat);
                });
                return MakeApiResult(CodeOf(result), L"expected WRONG_THREAD(14)");
            });
    }

    void ClipboardPage::UninitializeOnWorker_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[UninitializeOnWorker_Click]");
        // Ready is required so there is a session to call Close on. The state is
        // deliberately left untouched: Close refuses another thread before it
        // closes the lifecycle gate.
        StartWorkerOperation(L"Uninitialize (worker thread)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const auto closed = WithSession([](Clipboard::Session& session) { return session.Close(); });
                return MakeApiResult(CodeOf(closed),
                                     std::wstring(L"returned ") + (closed.has_value() ? L"TRUE" : L"FALSE") +
                                         L", expected WRONG_THREAD(14)");
            });
    }

    void ClipboardPage::DelayedWorkerCheck_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[DelayedWorkerCheck_Click]");
        // Read-only work with a deliberate delay, so the busy behaviour can be
        // exercised without depending on how fast the tester clicks.
        StartWorkerOperation(L"Delayed Worker Check", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                ::Sleep(5000);
                const auto present = WithSession([](Clipboard::Session& session)
                {
                    return session.HasFormat(L"CF_UNICODETEXT");
                });
                const bool yes = present.has_value() && present.value();
                return MakeApiResult(CodeOf(present),
                                     std::wstring(L"after 5s, CF_UNICODETEXT present=") + (yes ? L"TRUE" : L"FALSE"),
                                     L"[Worker] delayed check finished");
            });
    }

    // -----------------------------------------------------------------------
    // Error cases
    // -----------------------------------------------------------------------

    void ClipboardPage::ErrCopyTextEmbeddedNul_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyTextEmbeddedNul_Click]");
        StartWorkerOperation(L"CopyText (embedded NUL)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                // CF_UNICODETEXT ends at the first NUL, so it could not carry the rest.
                const std::wstring text(L"before\0after", 12);
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyText(text, kPlain);
                })), L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrPasteAfterClear_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrPasteAfterClear_Click]");
        StartWorkerOperation(L"PastePlainText (after Clear)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const DWORD clearError = CodeOf(WithSession([](Clipboard::Session& session)
                {
                    return session.Clear();
                }));
                if (clearError != kNoError)
                {
                    return MakeApiResult(clearError, L"ClearClipboard failed before the paste");
                }

                // FORMAT_UNAVAILABLE, not EMPTY: the toolkit checks format availability
                // before it ever asks for the data.
                const auto text = WithSession([](Clipboard::Session& session) { return session.PasteText(); });
                return MakeApiResult(CodeOf(text), L"expected FORMAT_UNAVAILABLE(5)");
            });
    }

    void ClipboardPage::ErrPasteHtmlTextOnly_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrPasteHtmlTextOnly_Click]");
        StartWorkerOperation(L"PasteHtml (text only)", WorkerPrecondition::ReadyRequired,
            [text = std::wstring(kSampleText)]() -> WorkerResult
            {
                const DWORD copyError = CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyText(text, kPlain);
                }));
                if (copyError != kNoError)
                {
                    return MakeApiResult(copyError, L"CopyPlainText failed before the paste");
                }

                const auto html = WithSession([](Clipboard::Session& session) { return session.PasteHtml(); });
                return MakeApiResult(CodeOf(html), L"expected FORMAT_UNAVAILABLE(5)");
            });
    }

    void ClipboardPage::ErrMultiCfBitmap_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiCfBitmap_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (CF_BITMAP)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<Clipboard::FormatPayload> items{
                    Clipboard::BytesPayload{ L"CF_BITMAP", BuildSampleDib() },
                };
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyMultiple(items, kPlain);
                })), L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrMultiDuplicate_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiDuplicate_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (duplicate format)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<Clipboard::FormatPayload> items{
                    Clipboard::TextPayload{ L"CF_UNICODETEXT", L"first" },
                    Clipboard::TextPayload{ L"CF_UNICODETEXT", L"second" },
                };
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyMultiple(items, kPlain);
                })), L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrMultiTypeMismatch_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiTypeMismatch_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (CF_DIB + text)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                // CF_DIB only accepts a bytes payload.
                const std::vector<Clipboard::FormatPayload> items{
                    Clipboard::TextPayload{ L"CF_DIB", L"not a bitmap" },
                };
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyMultiple(items, kPlain);
                })), L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrCopyFilesEmpty_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyFilesEmpty_Click]");
        StartWorkerOperation(L"CopyFiles (empty array)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<std::wstring> none;
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyFiles(none, kPlain);
                })), L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrCopyAfterUninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyAfterUninitialize_Click]");
        // Deliberately bypasses the state guard so the toolkit's own error is observed.
        StartWorkerOperation(L"CopyPlainText (after Uninitialize)", WorkerPrecondition::NoStateGuard,
            [text = std::wstring(kSampleText)]() -> WorkerResult
            {
                return MakeApiResult(CodeOf(WithSession([&](Clipboard::Session& session)
                {
                    return session.CopyText(text, kPlain);
                })), L"expected NOT_INITIALIZED(2)");
            });
    }

    void ClipboardPage::ErrForceInitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrForceInitialize_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ShuttingDownRequired))
        {
            return;
        }

        // The closing session still exists, so Create refuses a second one and
        // the state must not move to Ready here.
        auto created = Clipboard::Session::Create(MakeSessionOptions());
        if (created.has_value())
        {
            // Not expected. Close the stray session at once so the page keeps one.
            created.value().Close();
        }
        ShowResult(L"Force Initialize while shutting down", CodeOf(created),
                   L"expected NOT_SUPPORTED(16): a session already exists and its gate stays closed. "
                   L"Press \"CopyPlainText (after Uninitialize)\" to see NOT_INITIALIZED(2).");
    }

    void ClipboardPage::ErrCancelUnknownId_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCancelUnknownId_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        const auto canceled = WithSession([](Clipboard::Session& session)
        {
            return session.CancelRequest(Clipboard::RequestId{ 0xFFFFFFFFu });
        });
        ShowResult(L"CancelClipboardRequest (unknown id)", CodeOf(canceled),
                   std::wstring(L"returned ") + (canceled.has_value() ? L"TRUE" : L"FALSE") +
                       L", expected FALSE + INVALID_PARAMETER(1)");
    }

    // -----------------------------------------------------------------------
    // Application shutdown
    // -----------------------------------------------------------------------

    void ShutdownClipboardManagerForAppExit()
    {
        DLog(TAG, L"[ShutdownClipboardManagerForAppExit]");
        if (!g_session.has_value())
        {
            return;
        }

        // Close is what destroys the owner window, and destroying it is the only
        // point at which the system sends WM_RENDERALLFORMATS. Without this call the
        // process simply exits and every format reserved for delayed rendering is
        // dropped from the clipboard instead of being materialized.
        DWORD err = kNoError;
        const bool done = CloseSession(err);

        // Single attempt by design. A failure means a request is still draining and
        // the documented recovery is to pump messages and retry, but the window is
        // already closing and cannot pump. Retrying here would block application exit.
        if (!done)
        {
            // Destroying an unclosed session abandons it, which asserts in Debug.
            // The process is about to end, so hand it to the heap and let it go.
            new Clipboard::Session(std::move(*g_session));
            g_session.reset();
        }
        g_managerState.store(done ? ManagerState::Uninitialized : ManagerState::ShuttingDown);
    }
}
