#include "pch.h"
#include "ClipboardPage.xaml.h"
#if __has_include("ClipboardPage.g.cpp")
#include "ClipboardPage.g.cpp"
#endif

#include "common.h"
#include "WindowsClipboardManager.h"

#include <winrt/Windows.System.Threading.h>

#include <atomic>
#include <cstdio>
#include <ctime>
#include <vector>

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using namespace winrt::Windows::Data::Json;
using winrt::Windows::System::Threading::ThreadPool;

static const wchar_t* TAG = L"ClipboardPage";

namespace
{
    // -----------------------------------------------------------------------
    // Process-lifetime state
    //
    // The manager outlives the page: navigating away does not uninitialize it,
    // so the "is it usable" state cannot live in a page member (a new page
    // instance would report false while the manager is still running).
    // -----------------------------------------------------------------------

    // Three states, not a bool: once the owner UI thread calls uninit the
    // lifecycle gate is closed even when uninit returns FALSE, so "initialized"
    // and "usable" are no longer the same thing.
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

    // Forwarding hub. The C bridge callbacks are free function pointers and
    // cannot capture state, so they forward to these, which the active page
    // registers on navigation and clears on navigation away.
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

    // Deferred payloads are finalized at reservation time. The toolkit requires
    // the fill size to match the queried size exactly, so the provider must not
    // rebuild the data on the second phase.
    std::map<std::wstring, std::vector<BYTE>> g_deferredPayloads;

    const wchar_t* const kSampleText = L"Hello from native-toolkit";
    const wchar_t* const kSampleHtmlFragment = L"<b>Hello</b> from native-toolkit";
    const wchar_t* const kCustomFormatName = L"NativeToolkitSample";

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

    // ---- Bridge callback thunks (owner UI thread) -------------------------

    void OnClipboardChangedThunk()
    {
        DLog(TAG, L"[OnClipboardChangedThunk]");
        PostLog(L"[Monitor] clipboard content changed");
    }

    void OnHistoryChangedThunk()
    {
        DLog(TAG, L"[OnHistoryChangedThunk]");
        PostLog(L"[History] a new item was added to the history");
    }

    void OnHistoryEnabledChangedThunk(BOOL enabled)
    {
        DFLog(TAG, L"[OnHistoryEnabledChangedThunk] enabled: %d", enabled ? 1 : 0);
        PostLog(std::wstring(L"[History] history enabled changed: ") + (enabled ? L"true" : L"false"));
    }

    void OnRoamingEnabledChangedThunk(BOOL enabled)
    {
        DFLog(TAG, L"[OnRoamingEnabledChangedThunk] enabled: %d", enabled ? 1 : 0);
        PostLog(std::wstring(L"[History] roaming enabled changed: ") + (enabled ? L"true" : L"false"));
    }

    void OnRequestCompletedThunk(uint32_t requestId, DWORD error, const wchar_t* json)
    {
        DFLog(TAG, L"[OnRequestCompletedThunk] id: %u, error: %lu", requestId, error);
        // The payload is only valid while this callback runs, so copy it before
        // anything is handed to the dispatcher queue.
        winrt::hstring payload{ json ? json : L"" };
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

    // Runs on the owner UI thread inside WM_RENDERFORMAT handling: must not
    // touch XAML, must not block, and must not let an exception cross the C
    // boundary.
    DWORD ClipboardRenderProviderThunk(const wchar_t* formatName,
                                       void* /*context*/,
                                       BYTE* buffer,
                                       DWORD bufferSize,
                                       DWORD* pRequiredSize)
    {
        try
        {
            if (!formatName || !pRequiredSize)
            {
                return CLIPBOARD_ERROR_INVALID_PARAMETER;
            }

            const auto it = g_deferredPayloads.find(formatName);
            if (it == g_deferredPayloads.end())
            {
                return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;
            }

            const DWORD needed = static_cast<DWORD>(it->second.size());
            *pRequiredSize = needed;

            if (!buffer || bufferSize < needed)
            {
                PostLog(std::wstring(L"[Provider] format=") + formatName +
                        L" phase=size required=" + std::to_wstring(needed));
                return CLIPBOARD_ERROR_BUFFER_TOO_SMALL;
            }

            ::memcpy(buffer, it->second.data(), needed);
            PostLog(std::wstring(L"[Provider] format=") + formatName +
                    L" phase=fill size=" + std::to_wstring(needed) + L" result=0");
            return CLIPBOARD_ERROR_NONE;
        }
        catch (...)
        {
            return CLIPBOARD_ERROR_UNKNOWN;
        }
    }

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
    std::vector<BYTE> BuildSampleDib()
    {
        const LONG width = 8;
        const LONG height = 8;
        const size_t pixelBytes = static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;

        std::vector<BYTE> dib(sizeof(BITMAPINFOHEADER) + pixelBytes, 0);
        auto* header = reinterpret_cast<BITMAPINFOHEADER*>(dib.data());
        header->biSize = sizeof(BITMAPINFOHEADER);
        header->biWidth = width;
        header->biHeight = height;
        header->biPlanes = 1;
        header->biBitCount = 32;
        header->biCompression = BI_RGB;
        header->biSizeImage = static_cast<DWORD>(pixelBytes);

        BYTE* pixels = dib.data() + sizeof(BITMAPINFOHEADER);
        for (size_t i = 0; i < pixelBytes; i += 4)
        {
            pixels[i + 0] = 0xD7; // blue
            pixels[i + 1] = 0x78; // green
            pixels[i + 2] = 0x00; // red
            pixels[i + 3] = 0xFF; // alpha
        }
        return dib;
    }

    std::string Base64Encode(const std::vector<BYTE>& data)
    {
        static const char* table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        std::string out;
        out.reserve(((data.size() + 2) / 3) * 4);

        size_t i = 0;
        while (i + 2 < data.size())
        {
            const unsigned v = (static_cast<unsigned>(data[i]) << 16) |
                               (static_cast<unsigned>(data[i + 1]) << 8) |
                               static_cast<unsigned>(data[i + 2]);
            out.push_back(table[(v >> 18) & 0x3F]);
            out.push_back(table[(v >> 12) & 0x3F]);
            out.push_back(table[(v >> 6) & 0x3F]);
            out.push_back(table[v & 0x3F]);
            i += 3;
        }

        const size_t remaining = data.size() - i;
        if (remaining == 1)
        {
            const unsigned v = static_cast<unsigned>(data[i]) << 16;
            out.push_back(table[(v >> 18) & 0x3F]);
            out.push_back(table[(v >> 12) & 0x3F]);
            out.push_back('=');
            out.push_back('=');
        }
        else if (remaining == 2)
        {
            const unsigned v = (static_cast<unsigned>(data[i]) << 16) |
                               (static_cast<unsigned>(data[i + 1]) << 8);
            out.push_back(table[(v >> 18) & 0x3F]);
            out.push_back(table[(v >> 12) & 0x3F]);
            out.push_back(table[(v >> 6) & 0x3F]);
            out.push_back('=');
        }
        return out;
    }

    // CF_HTML payload with a byte-offset header. Offsets are computed from fixed
    // prefix lengths, and the numeric fields use a fixed width so re-formatting
    // with the real values cannot change the header length.
    std::vector<BYTE> BuildCfHtmlBytes(const std::string& utf8Fragment)
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
            return std::vector<BYTE>();
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
            return std::vector<BYTE>();
        }

        std::string payload;
        payload.reserve(endHtml);
        payload.append(header, static_cast<size_t>(written));
        payload.append(prefix);
        payload.append(utf8Fragment);
        payload.append(suffix);

        return std::vector<BYTE>(payload.begin(), payload.end());
    }

    std::vector<BYTE> BuildUnicodeTextBytes(const std::wstring& text)
    {
        std::vector<BYTE> bytes((text.size() + 1) * sizeof(wchar_t), 0);
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

    // ---- Two-phase buffer helpers ----------------------------------------
    //
    // Deliberately not expressed in terms of WorkerResult: these live in the
    // anonymous namespace, while WorkerResult is a page-private type.

    struct BufferFetch
    {
        DWORD        error{ CLIPBOARD_ERROR_NONE };
        bool         sampleFailure{ false };
        std::wstring detail;
    };

    BufferFetch FetchWide(const std::function<DWORD(wchar_t*, DWORD, DWORD*)>& call, std::wstring& out)
    {
        out.clear();

        DWORD queryError = CLIPBOARD_ERROR_NONE;
        const DWORD needed = call(nullptr, 0, &queryError);
        if (queryError != CLIPBOARD_ERROR_BUFFER_TOO_SMALL)
        {
            if (queryError == CLIPBOARD_ERROR_NONE)
            {
                return { CLIPBOARD_ERROR_NONE, true, L"Size query unexpectedly reported success" };
            }
            return { queryError, false, L"" };
        }
        if (needed == 0)
        {
            // A wide payload always carries at least the NUL terminator.
            return { CLIPBOARD_ERROR_NONE, true, L"Size query returned zero elements" };
        }

        std::vector<wchar_t> buffer(needed, L'\0');
        DWORD fillError = CLIPBOARD_ERROR_NONE;
        const DWORD actual = call(buffer.data(), needed, &fillError);
        if (fillError != CLIPBOARD_ERROR_NONE)
        {
            // Do not retry: another application may keep growing the content.
            return { fillError, false, L"" };
        }
        if (actual > needed)
        {
            return { CLIPBOARD_ERROR_NONE, true, L"Returned size exceeds the allocated buffer" };
        }

        buffer[needed - 1] = L'\0';
        out.assign(buffer.data());
        return { CLIPBOARD_ERROR_NONE, false, L"" };
    }

    BufferFetch FetchBytes(const std::function<DWORD(BYTE*, DWORD, DWORD*)>& call, std::vector<BYTE>& out)
    {
        out.clear();

        DWORD queryError = CLIPBOARD_ERROR_NONE;
        const DWORD needed = call(nullptr, 0, &queryError);
        if (queryError != CLIPBOARD_ERROR_BUFFER_TOO_SMALL)
        {
            if (queryError == CLIPBOARD_ERROR_NONE)
            {
                return { CLIPBOARD_ERROR_NONE, true, L"Size query unexpectedly reported success" };
            }
            return { queryError, false, L"" };
        }
        if (needed == 0)
        {
            // Empty payload: the toolkit reports BUFFER_TOO_SMALL with zero bytes,
            // so this is a success and the second call must not be made.
            return { CLIPBOARD_ERROR_NONE, false, L"" };
        }

        std::vector<BYTE> buffer(needed, 0);
        DWORD fillError = CLIPBOARD_ERROR_NONE;
        const DWORD actual = call(buffer.data(), needed, &fillError);
        if (fillError != CLIPBOARD_ERROR_NONE)
        {
            return { fillError, false, L"" };
        }
        if (actual > needed)
        {
            return { CLIPBOARD_ERROR_NONE, true, L"Returned size exceeds the allocated buffer" };
        }

        buffer.resize(actual);
        out = std::move(buffer);
        return { CLIPBOARD_ERROR_NONE, false, L"" };
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
        // replayed on re-entry. The manager itself keeps running.
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
        std::wstring text = (err == CLIPBOARD_ERROR_NONE ? L"✅ " : L"❌ ") +
                            std::wstring(L"[") + method + L"] errorCode=" + std::to_wstring(err);

        switch (err)
        {
        case CLIPBOARD_ERROR_NOT_INITIALIZED:
            // Press Initialize only helps when nothing is shutting down: once the
            // gate is closed a fresh Init returns success without reopening it.
            text += (g_managerState.load() == ManagerState::ShuttingDown)
                        ? L" - Press CanDestroy, then Uninitialize again."
                        : L" - Press InitializeManager first.";
            break;
        case CLIPBOARD_ERROR_EMPTY:
            text += L" - The clipboard is empty.";
            break;
        case CLIPBOARD_ERROR_FORMAT_UNAVAILABLE:
            text += L" - The requested format is not on the clipboard.";
            break;
        case CLIPBOARD_ERROR_HISTORY_DISABLED:
            text += L" - Enable clipboard history in Windows Settings.";
            break;
        case CLIPBOARD_ERROR_PARTIAL_STATE:
            text += L" - Press RecoverDeferredState.";
            break;
        case CLIPBOARD_ERROR_WRONG_THREAD:
            text += L" - This API is limited to the owner UI thread.";
            break;
        case CLIPBOARD_ERROR_CANCELED:
            text += L" - Wait for the pending callbacks, then retry.";
            break;
        case CLIPBOARD_ERROR_NOT_FOREGROUND:
            text += L" - Bring this app to the foreground and retry.";
            break;
        case CLIPBOARD_ERROR_WRONG_APARTMENT:
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

    ClipboardPage::WorkerResult ClipboardPage::MakeBridgeResult(DWORD err,
                                                               std::wstring detail,
                                                               std::wstring logLine)
    {
        WorkerResult result;
        result.outcome = WorkerOutcome::BridgeResult;
        result.bridgeError = err;
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
            case WorkerOutcome::BridgeResult:
                ShowResult(method, result.bridgeError, result.detail);
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
            // Rejected before acceptance: the callback will never fire.
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

        if (error == CLIPBOARD_ERROR_NONE && !payload.empty())
        {
            detail = Preview(payload, 160);

            if (method.rfind(L"GetClipboardHistory", 0) == 0)
            {
                try
                {
                    JsonArray items = JsonArray::Parse(json);
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
            // A fresh Init succeeds here but does not reopen the lifecycle gate,
            // so refuse it and point at the retry path instead.
            RefreshStateText(L"❌ Shutting down. Press CanDestroy, then Uninitialize again.");
            return;
        }

        DWORD err = CLIPBOARD_ERROR_NONE;
        initClipboardManager(&OnClipboardChangedThunk, &err);
        if (err == CLIPBOARD_ERROR_NONE)
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        setClipboardHistoryCallbacks(&OnHistoryChangedThunk,
                                     &OnHistoryEnabledChangedThunk,
                                     &OnRoamingEnabledChangedThunk,
                                     &err);
        ShowResult(L"SetHistoryCallbacks", err, L"");
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const BOOL done = uninitClipboardManager(&err);
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

                    WorkerResult result = MakeBridgeResult(CLIPBOARD_ERROR_NONE);
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
        if (err == CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED)
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const BOOL canDestroy = canDestroyClipboardManager(&err);
        ShowResult(L"CanDestroy", err,
                   std::wstring(L"returned ") + (canDestroy ? L"TRUE" : L"FALSE"));
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
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(text.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err);
            });
    }

    void ClipboardPage::CopyPlainTextEmpty_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyPlainTextEmpty_Click]");
        StartWorkerOperation(L"CopyPlainText (empty)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(L"", CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"An empty string is a valid payload");
            });
    }

    void ClipboardPage::CopyHtml_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyHtml_Click]");
        StartWorkerOperation(L"CopyHtml", WorkerPrecondition::ReadyRequired,
            [html = std::wstring(kSampleHtmlFragment), text = std::wstring(kSampleText)]() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyHtml(html.c_str(), text.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err);
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

                const std::wstring json = L"[\"" + JsonEscape(first) + L"\",\"" + JsonEscape(second) + L"\"]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyFiles(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"2 files", L"[Copy] files: " + first + L", " + second);
            });
    }

    void ClipboardPage::CopyImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyImage_Click]");
        StartWorkerOperation(L"CopyImage", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::vector<BYTE> dib = BuildSampleDib();
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyImage(dib.data(), static_cast<DWORD>(dib.size()), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"8x8 32bpp DIB, " + std::to_wstring(dib.size()) + L" bytes");
            });
    }

    void ClipboardPage::CopyCustomFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyCustomFormat_Click]");
        StartWorkerOperation(L"CopyCustomFormat", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::string blob = "native-toolkit-sample-payload";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyCustomFormat(kCustomFormatName,
                                 reinterpret_cast<const BYTE*>(blob.data()),
                                 static_cast<DWORD>(blob.size()),
                                 CLIPBOARD_WRITE_OPTION_NONE,
                                 &err);
                return MakeBridgeResult(err, std::wstring(kCustomFormatName) + L", " +
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
                const std::wstring json =
                    L"[{\"format\":\"HTML Format\",\"html\":\"" + JsonEscape(kSampleHtmlFragment) + L"\"},"
                    L"{\"format\":\"CF_UNICODETEXT\",\"text\":\"" + JsonEscape(kSampleText) + L"\"}]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyMultipleFormats(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"HTML Format + CF_UNICODETEXT");
            });
    }

    void ClipboardPage::CopyMultipleFormatsWithImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyMultipleFormatsWithImage_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (with image)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::string base64 = Base64Encode(BuildSampleDib());
                const std::wstring json =
                    L"[{\"format\":\"HTML Format\",\"html\":\"" + JsonEscape(kSampleHtmlFragment) + L"\"},"
                    L"{\"format\":\"CF_UNICODETEXT\",\"text\":\"" + JsonEscape(kSampleText) + L"\"},"
                    L"{\"format\":\"CF_DIB\",\"base64\":\"" + Utf8ToWide(base64) + L"\"}]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyMultipleFormats(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"HTML Format + CF_UNICODETEXT + CF_DIB");
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
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(L"Sensitive sample value", CLIPBOARD_WRITE_OPTION_SENSITIVE, &err);
                return MakeBridgeResult(err, L"Should not appear in Win+V");
            });
    }

    void ClipboardPage::CopyExcludeHistory_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyExcludeHistory_Click]");
        StartWorkerOperation(L"CopyPlainText (EXCLUDE_HISTORY)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(L"History excluded sample value", CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY, &err);
                return MakeBridgeResult(err, L"Should not appear in Win+V");
            });
    }

    void ClipboardPage::CopyExcludeRoaming_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CopyExcludeRoaming_Click]");
        StartWorkerOperation(L"CopyPlainText (EXCLUDE_ROAMING)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(L"Roaming excluded sample value", CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING, &err);
                return MakeBridgeResult(err, L"Should not sync to another device");
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
                return MakeBridgeResult(CLIPBOARD_ERROR_NONE,
                                        L"removed " + std::to_wstring(removed) + L" file(s)");
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
                std::wstring text;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return pastePlainText(buffer, size, pError); },
                    text);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                return MakeBridgeResult(fetch.error, Preview(text, 100));
            });
    }

    void ClipboardPage::PasteHtml_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteHtml_Click]");
        StartWorkerOperation(L"PasteHtml", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                std::wstring html;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return pasteHtml(buffer, size, pError); },
                    html);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                return MakeBridgeResult(fetch.error, Preview(html, 100));
            });
    }

    void ClipboardPage::PasteFiles_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteFiles_Click]");
        StartWorkerOperation(L"PasteFiles", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                std::wstring json;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return pasteFiles(buffer, size, pError); },
                    json);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                return MakeBridgeResult(fetch.error, Preview(json, 160));
            });
    }

    void ClipboardPage::PasteImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[PasteImage_Click]");
        StartWorkerOperation(L"PasteImage", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                std::vector<BYTE> dib;
                const BufferFetch fetch = FetchBytes(
                    [](BYTE* buffer, DWORD size, DWORD* pError) { return pasteImage(buffer, size, pError); },
                    dib);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                if (fetch.error != CLIPBOARD_ERROR_NONE)
                {
                    return MakeBridgeResult(fetch.error);
                }

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

                return MakeBridgeResult(CLIPBOARD_ERROR_NONE,
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
                std::vector<BYTE> blob;
                const BufferFetch fetch = FetchBytes(
                    [](BYTE* buffer, DWORD size, DWORD* pError)
                    {
                        return pasteCustomFormat(kCustomFormatName, buffer, size, pError);
                    },
                    blob);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                if (fetch.error != CLIPBOARD_ERROR_NONE)
                {
                    return MakeBridgeResult(fetch.error);
                }

                std::string preview(blob.begin(), blob.size() > 32 ? blob.begin() + 32 : blob.end());
                return MakeBridgeResult(CLIPBOARD_ERROR_NONE,
                                        std::to_wstring(blob.size()) + L" bytes: " + Utf8ToWide(preview));
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
                DWORD err = CLIPBOARD_ERROR_NONE;
                const BOOL present = hasClipboardFormat(L"CF_UNICODETEXT", &err);
                return MakeBridgeResult(err, std::wstring(L"returned ") + (present ? L"TRUE" : L"FALSE"));
            });
    }

    void ClipboardPage::GetClipboardFormats_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetClipboardFormats_Click]");
        StartWorkerOperation(L"GetClipboardFormats", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                std::wstring json;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return getClipboardFormats(buffer, size, pError); },
                    json);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                return MakeBridgeResult(fetch.error, Preview(json, 200));
            });
    }

    void ClipboardPage::GetPreferredFormat_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetPreferredFormat_Click]");
        StartWorkerOperation(L"GetPreferredFormat", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                std::wstring name;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError)
                    {
                        return getPreferredClipboardFormat(buffer, size, pError);
                    },
                    name);
                if (fetch.sampleFailure)
                {
                    WorkerResult failure;
                    failure.outcome = WorkerOutcome::SampleFailure;
                    failure.detail = fetch.detail;
                    return failure;
                }
                return MakeBridgeResult(fetch.error,
                                        name.empty() ? std::wstring(L"(no candidate format)") : name);
            });
    }

    void ClipboardPage::ClearClipboard_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ClearClipboard_Click]");
        StartWorkerOperation(L"ClearClipboard", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                clearClipboard(&err);
                return MakeBridgeResult(err);
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

        // Finalize both payloads now so the provider returns the same size in the
        // size and fill phases.
        g_deferredPayloads.clear();
        g_deferredPayloads[L"CF_UNICODETEXT"] = BuildUnicodeTextBytes(kSampleText);
        g_deferredPayloads[L"HTML Format"] = BuildCfHtmlBytes(WideToUtf8(kSampleHtmlFragment));

        DWORD err = CLIPBOARD_ERROR_NONE;
        reserveDeferredFormats(L"[\"HTML Format\",\"CF_UNICODETEXT\"]",
                               &ClipboardRenderProviderThunk, nullptr, &err);
        ShowResult(L"ReserveDeferredFormats", err, L"");
        if (err == CLIPBOARD_ERROR_NONE)
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        recoverDeferredState(&err);
        ShowResult(L"RecoverDeferredState", err, L"");
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const uint32_t id = getClipboardHistoryAvailability(&OnRequestCompletedThunk, &err);
        RegisterHistoryRequest(id, L"GetHistoryAvailability", err);
    }

    void ClipboardPage::GetClipboardHistory_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetClipboardHistory_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        DWORD err = CLIPBOARD_ERROR_NONE;
        const uint32_t id = getClipboardHistory(&OnRequestCompletedThunk, &err);
        RegisterHistoryRequest(id, L"GetClipboardHistory", err);
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const uint32_t id = restoreHistoryItem(m_lastHistoryItemId.c_str(), &OnRequestCompletedThunk, &err);
        RegisterHistoryRequest(id, L"RestoreHistoryItem", err);
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const uint32_t id = deleteHistoryItem(m_lastHistoryItemId.c_str(), &OnRequestCompletedThunk, &err);
        RegisterHistoryRequest(id, L"DeleteHistoryItem", err);
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const uint32_t id = clearUnpinnedHistory(&OnRequestCompletedThunk, &err);
        RegisterHistoryRequest(id, L"ClearUnpinnedHistory", err);
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

        DWORD err = CLIPBOARD_ERROR_NONE;
        const BOOL queued = cancelClipboardRequest(m_lastRequestId, &err);
        ShowResult(L"CancelLastRequest", err,
                   std::wstring(L"id=") + std::to_wstring(m_lastRequestId) +
                       L", returned " + (queued ? L"TRUE" : L"FALSE"));
    }

    void ClipboardPage::RequestAndImmediateUninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RequestAndImmediateUninitialize_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        // Both calls happen in one handler on purpose: the request is only posted
        // to the dispatch window, so it is still queued when uninit drains it.
        // Splitting this across two clicks lets the pump complete the request and
        // the drain path is never exercised.
        DWORD requestError = CLIPBOARD_ERROR_NONE;
        const uint32_t id = getClipboardHistory(&OnRequestCompletedThunk, &requestError);
        if (id != 0)
        {
            m_pendingRequests[id] = L"GetClipboardHistory (immediate uninit)";
            m_lastRequestId = id;
            g_requestOwners[id] = m_pageId;
        }

        DWORD uninitError = CLIPBOARD_ERROR_NONE;
        const BOOL done = uninitClipboardManager(&uninitError);
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
        // Ready is required: when the manager is not initialized the toolkit
        // reports NOT_INITIALIZED before it ever checks the calling thread.
        StartWorkerOperation(L"ReserveDeferred (worker thread)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                reserveDeferredFormats(L"[\"CF_UNICODETEXT\"]",
                                       &ClipboardRenderProviderThunk, nullptr, &err);
                return MakeBridgeResult(err, L"expected WRONG_THREAD(14)");
            });
    }

    void ClipboardPage::UninitializeOnWorker_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[UninitializeOnWorker_Click]");
        // Ready is required for the same reason: an uninitialized manager returns
        // TRUE before the thread check. The state is deliberately left untouched,
        // because this call never reaches the code that closes the lifecycle gate.
        StartWorkerOperation(L"Uninitialize (worker thread)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                const BOOL done = uninitClipboardManager(&err);
                return MakeBridgeResult(err,
                                        std::wstring(L"returned ") + (done ? L"TRUE" : L"FALSE") +
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
                DWORD err = CLIPBOARD_ERROR_NONE;
                const BOOL present = hasClipboardFormat(L"CF_UNICODETEXT", &err);
                return MakeBridgeResult(err,
                                        std::wstring(L"after 5s, CF_UNICODETEXT present=") +
                                            (present ? L"TRUE" : L"FALSE"),
                                        L"[Worker] delayed check finished");
            });
    }

    // -----------------------------------------------------------------------
    // Error cases
    // -----------------------------------------------------------------------

    void ClipboardPage::ErrCopyPlainTextNull_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyPlainTextNull_Click]");
        StartWorkerOperation(L"CopyPlainText (null)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(nullptr, CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrPasteAfterClear_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrPasteAfterClear_Click]");
        StartWorkerOperation(L"PastePlainText (after Clear)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD clearError = CLIPBOARD_ERROR_NONE;
                clearClipboard(&clearError);
                if (clearError != CLIPBOARD_ERROR_NONE)
                {
                    return MakeBridgeResult(clearError, L"ClearClipboard failed before the paste");
                }

                std::wstring text;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return pastePlainText(buffer, size, pError); },
                    text);
                // FORMAT_UNAVAILABLE, not EMPTY: the toolkit checks format availability
                // before it ever asks for the data.
                return MakeBridgeResult(fetch.error, L"expected FORMAT_UNAVAILABLE(5)");
            });
    }

    void ClipboardPage::ErrPasteHtmlTextOnly_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrPasteHtmlTextOnly_Click]");
        StartWorkerOperation(L"PasteHtml (text only)", WorkerPrecondition::ReadyRequired,
            [text = std::wstring(kSampleText)]() -> WorkerResult
            {
                DWORD copyError = CLIPBOARD_ERROR_NONE;
                copyPlainText(text.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &copyError);
                if (copyError != CLIPBOARD_ERROR_NONE)
                {
                    return MakeBridgeResult(copyError, L"CopyPlainText failed before the paste");
                }

                std::wstring html;
                const BufferFetch fetch = FetchWide(
                    [](wchar_t* buffer, DWORD size, DWORD* pError) { return pasteHtml(buffer, size, pError); },
                    html);
                return MakeBridgeResult(fetch.error, L"expected FORMAT_UNAVAILABLE(5)");
            });
    }

    void ClipboardPage::ErrPasteImageSizeQuery_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrPasteImageSizeQuery_Click]");
        StartWorkerOperation(L"PasteImage (size query only)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                // Only the first phase, to show the required size contract.
                DWORD err = CLIPBOARD_ERROR_NONE;
                const DWORD needed = pasteImage(nullptr, 0, &err);
                return MakeBridgeResult(err, L"required size=" + std::to_wstring(needed) +
                                                 L", expected BUFFER_TOO_SMALL(7)");
            });
    }

    void ClipboardPage::ErrMultiCfBitmap_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiCfBitmap_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (CF_BITMAP)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::string base64 = Base64Encode(BuildSampleDib());
                const std::wstring json =
                    L"[{\"format\":\"CF_BITMAP\",\"base64\":\"" + Utf8ToWide(base64) + L"\"}]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyMultipleFormats(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrMultiDuplicate_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiDuplicate_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (duplicate format)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                const std::wstring json =
                    L"[{\"format\":\"CF_UNICODETEXT\",\"text\":\"first\"},"
                    L"{\"format\":\"CF_UNICODETEXT\",\"text\":\"second\"}]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyMultipleFormats(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrMultiTypeMismatch_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrMultiTypeMismatch_Click]");
        StartWorkerOperation(L"CopyMultipleFormats (CF_DIB + text)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                // CF_DIB only accepts a base64 payload.
                const std::wstring json = L"[{\"format\":\"CF_DIB\",\"text\":\"not a bitmap\"}]";
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyMultipleFormats(json.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrCopyFilesEmpty_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyFilesEmpty_Click]");
        StartWorkerOperation(L"CopyFiles (empty array)", WorkerPrecondition::ReadyRequired,
            []() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyFiles(L"[]", CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected INVALID_PARAMETER(1)");
            });
    }

    void ClipboardPage::ErrCopyAfterUninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCopyAfterUninitialize_Click]");
        // Deliberately bypasses the state guard so the Bridge error is observed.
        StartWorkerOperation(L"CopyPlainText (after Uninitialize)", WorkerPrecondition::NoStateGuard,
            [text = std::wstring(kSampleText)]() -> WorkerResult
            {
                DWORD err = CLIPBOARD_ERROR_NONE;
                copyPlainText(text.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);
                return MakeBridgeResult(err, L"expected NOT_INITIALIZED(2)");
            });
    }

    void ClipboardPage::ErrForceInitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrForceInitialize_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ShuttingDownRequired))
        {
            return;
        }

        // Shows that a fresh Init reports success while the gate stays closed, so
        // the state must not move to Ready here.
        DWORD err = CLIPBOARD_ERROR_NONE;
        initClipboardManager(&OnClipboardChangedThunk, &err);
        ShowResult(L"Force Initialize while shutting down", err,
                   L"Init reports success but the gate stays closed. "
                   L"Press \"CopyPlainText (after Uninitialize)\" to see NOT_INITIALIZED(2).");
    }

    void ClipboardPage::ErrCancelUnknownId_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ErrCancelUnknownId_Click]");
        if (!CheckNotBusy() || !CheckPrecondition(WorkerPrecondition::ReadyRequired))
        {
            return;
        }

        DWORD err = CLIPBOARD_ERROR_NONE;
        const BOOL queued = cancelClipboardRequest(0xFFFFFFFFu, &err);
        ShowResult(L"CancelClipboardRequest (unknown id)", err,
                   std::wstring(L"returned ") + (queued ? L"TRUE" : L"FALSE") +
                       L", expected FALSE + INVALID_PARAMETER(1)");
    }

    // -----------------------------------------------------------------------
    // Application shutdown
    // -----------------------------------------------------------------------

    void ShutdownClipboardManagerForAppExit()
    {
        DLog(TAG, L"[ShutdownClipboardManagerForAppExit]");
        if (g_managerState.load() == ManagerState::Uninitialized)
        {
            return;
        }

        // Uninit is what destroys the owner window, and destroying it is the only
        // point at which the system sends WM_RENDERALLFORMATS. Without this call the
        // process simply exits and every format reserved for delayed rendering is
        // dropped from the clipboard instead of being materialized.
        DWORD err = CLIPBOARD_ERROR_NONE;
        const BOOL done = uninitClipboardManager(&err);

        // Single attempt by design. A FALSE return means a request is still draining
        // and the documented recovery is to pump messages and retry, but the window is
        // already closing and cannot pump. Retrying here would block application exit.
        g_managerState.store(done ? ManagerState::Uninitialized : ManagerState::ShuttingDown);
    }
}
