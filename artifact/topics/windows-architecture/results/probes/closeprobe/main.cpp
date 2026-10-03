// Probe: what does Clipboard::Session::Close return while a history request's
// WinRT work is still running, and does the answer change without a message
// loop on the owner thread?
//
// Reported from unity-native-plugin (2026-09-29): with GetHistory in flight,
// Close on the owner (Unity's main thread, pumping every frame) returned Busy
// twice and then succeeded. The header says Close needs no message loop.
//
// History requests are refused unless this process owns the foreground
// window, so the probe shows a small window and waits until it is in front
// (click it). Then, twice with a fresh session each time:
//
//   nopump  GetHistory, let it start, then retry Close with Sleep only, 10 s
//   pump    the same, pumping the thread's messages between retries
//
// Reads only; writes nothing to the clipboard.

#include <windows.h>

#include <cstdio>
#include <string>

#include <NativeToolkit/Clipboard.h>

namespace Clipboard = NativeToolkit::Clipboard;

namespace {

ULONGLONG g_start = 0;

double Ms() { return static_cast<double>(::GetTickCount64() - g_start); }

void Pump()
{
    MSG message;
    while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
    {
        ::TranslateMessage(&message);
        ::DispatchMessageW(&message);
    }
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_PAINT)
    {
        PAINTSTRUCT ps;
        HDC dc = ::BeginPaint(hwnd, &ps);
        const wchar_t* text = L"Clipboard close probe - click here";
        ::TextOutW(dc, 10, 10, text, static_cast<int>(wcslen(text)));
        ::EndPaint(hwnd, &ps);
        return 0;
    }
    return ::DefWindowProcW(hwnd, msg, wParam, lParam);
}

const wchar_t* Code(unsigned code)
{
    switch (code)
    {
    case 0: return L"ok";
    case 3: return L"Busy";
    case 12: return L"MonitorRegisterFailed";
    case 13: return L"PartialState";
    case 15: return L"Canceled";
    case 17: return L"NotForeground";
    default: return L"?";
    }
}

bool RunOnce(HWND hwnd, bool pump)
{
    std::wprintf(L"\n== %ls\n", pump ? L"pump between retries" : L"no pump between retries");
    auto created = Clipboard::Session::Create(Clipboard::SessionOptions{});
    if (!created.has_value())
    {
        std::wprintf(L"[probe] Create failed code=%u\n", static_cast<unsigned>(created.error().code));
        return false;
    }
    Clipboard::Session session = std::move(created).value();

    g_start = ::GetTickCount64();
    std::wprintf(L"  foreground is ours: %d\n", ::GetForegroundWindow() == hwnd ? 1 : 0);
    auto started = session.GetHistory(
        [](Clipboard::RequestId id, Clipboard::Result<std::vector<Clipboard::HistoryItem>> r) {
            const unsigned code = r.has_value() ? 0u : static_cast<unsigned>(r.error().code);
            std::wprintf(L"  %7.1f ms completion id=%u %ls items=%zu\n", Ms(), static_cast<unsigned>(id),
                         Code(code), r.has_value() ? r.value().size() : 0);
        });
    if (!started.has_value())
    {
        std::wprintf(L"[probe] request refused code=%u\n", static_cast<unsigned>(started.error().code));
    }

    // Let the queued request start its WinRT work: the owner starts it when it
    // handles its window's message. Stop as soon as that message is gone.
    for (int i = 0; i < 3; ++i) { Pump(); ::Sleep(1); }
    std::wprintf(L"  %7.1f ms request started; closing\n", Ms());

    int attempts = 0;
    unsigned last = 0xFFFFFFFF;
    const ULONGLONG deadline = ::GetTickCount64() + 10000;
    bool closed = false;
    while (::GetTickCount64() < deadline)
    {
        ++attempts;
        const auto result = session.Close();
        const unsigned code = result.has_value() ? 0u : static_cast<unsigned>(result.error().code);
        if (code != last)
        {
            std::wprintf(L"  %7.1f ms Close #%d -> %ls (%u), CanClose=%d\n", Ms(), attempts, Code(code), code,
                         session.CanClose() ? 1 : 0);
            last = code;
        }
        if (result.has_value()) { closed = true; break; }
        if (pump) Pump();
        ::Sleep(20);
    }
    std::wprintf(L"  RESULT: %ls after %d attempts, %.0f ms\n", closed ? L"closed" : L"NOT closed", attempts, Ms());

    if (!closed)
    {
        for (int i = 0; i < 500; ++i)
        {
            Pump();
            if (session.Close().has_value())
            {
                std::wprintf(L"  after pumping: closed at %.0f ms (attempt %d)\n", Ms(), i + 1);
                break;
            }
            ::Sleep(20);
        }
    }
    return true;
}

}  // namespace

int wmain()
{
    ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.lpszClassName = L"CloseProbeWindow";
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    ::RegisterClassW(&wc);
    HWND hwnd = ::CreateWindowExW(WS_EX_TOPMOST, wc.lpszClassName, L"Clipboard close probe",
                                  WS_OVERLAPPEDWINDOW | WS_VISIBLE, 200, 200, 420, 140,
                                  nullptr, nullptr, wc.hInstance, nullptr);
    ::SetForegroundWindow(hwnd);

    std::wprintf(L"[probe] waiting for the probe window to be in front (click it), up to 120 s\n");
    const ULONGLONG waitEnd = ::GetTickCount64() + 120000;
    while (::GetForegroundWindow() != hwnd && ::GetTickCount64() < waitEnd)
    {
        Pump();
        ::Sleep(50);
    }
    if (::GetForegroundWindow() != hwnd)
    {
        std::wprintf(L"[probe] the window never came to the front\n");
        return 1;
    }
    std::wprintf(L"[probe] in front\n");

    RunOnce(hwnd, false);
    ::SetForegroundWindow(hwnd);
    for (int i = 0; i < 20; ++i) { Pump(); ::Sleep(50); }
    RunOnce(hwnd, true);

    ::DestroyWindow(hwnd);
    ::CoUninitialize();
    return 0;
}
