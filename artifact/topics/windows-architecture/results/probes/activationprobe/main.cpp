// Probe: does an unpackaged process receive a toast button activation?
//
// Reported from unity-native-plugin against the 1.x C ABI: the button is
// pressed, INotificationActivationCallback::Activate is never called, and no
// new process starts. This exercises the same path from a plain Win32 console
// program, outside Unity, with an AUMID that has no history on this machine.
//
// WARM (the process is running when the button is pressed):
//
//   sta        the main thread is an STA, as Unity's is
//   mta        the main thread is an MTA
//   sta-aumid  an STA, plus SetCurrentProcessExplicitAppUserModelID before
//              Manager::Create - the one part of the classic contract the
//              library never does
//
//   Shows one toast with one button and then pumps messages until the handler
//   fires or the timeout runs out. An STA needs the pump: COM dispatches
//   incoming calls through the message queue.
//
// COLD (no process is running when the button is pressed; added 2026-09-29):
//
//   cold       registers, shows the toast, and exits at once, leaving the
//              toast in the notification centre and no process running
//   (launched) pressing the button makes COM start this exe from LocalServer32
//              ("<exe> -ToastActivated", plus whatever COM appends). The
//              process creates the Manager again and records, in probe.log
//              next to the exe, its command line and every callback that
//              arrives within 20 seconds, so a duplicate shows up too.
//
// The icon is probe.png next to the exe unless a second argument names one.
// Exit codes: 0 activated (or cold: shown), 3 timed out, 1 setup failed.

#include <windows.h>
#include <shobjidl_core.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <string>

#include <NativeToolkit/Notification.h>

namespace Notification = NativeToolkit::Notification;

namespace {

const wchar_t* const kAumid = L"NativeToolkit ActivationProbe";

std::atomic<bool> g_activated{false};
std::atomic<int> g_count{0};
FILE* g_log = nullptr;

void Log(const wchar_t* format, ...)
{
    va_list args;
    va_start(args, format);
    std::vfwprintf(stdout, format, args);
    va_end(args);
    std::fflush(stdout);
    if (g_log)
    {
        va_start(args, format);
        std::vfwprintf(g_log, format, args);
        va_end(args);
        std::fflush(g_log);
    }
}

std::wstring NextToExe(const wchar_t* name)
{
    wchar_t exe[MAX_PATH];
    ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring path = exe;
    return path.substr(0, path.find_last_of(L'\\') + 1) + name;
}

void OnInvoked(const Notification::ActivationArgs& args)
{
    // Whatever thread the OS picked.
    const int n = ++g_count;
    Log(L"ACTIVATED #%d tid=%lu raw=[%ls] values=%zu\n", n, ::GetCurrentThreadId(),
        args.rawArguments.c_str(), args.values.size());
    for (const auto& pair : args.values)
    {
        Log(L"  %ls = %ls\n", pair.first.c_str(), pair.second.c_str());
    }
    g_activated.store(true);
}

/// Pumps messages until the handler fires or the deadline passes; with
/// untilDeadline, keeps pumping to the deadline to catch later callbacks.
bool WaitForActivation(int seconds, bool untilDeadline = false)
{
    const ULONGLONG deadline = ::GetTickCount64() + static_cast<ULONGLONG>(seconds) * 1000;
    while ((untilDeadline || !g_activated.load()) && ::GetTickCount64() < deadline)
    {
        MSG message;
        while (::PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
        {
            ::TranslateMessage(&message);
            ::DispatchMessageW(&message);
        }
        ::Sleep(50);
    }
    return g_activated.load();
}

}  // namespace

int wmain(int argc, wchar_t** argv)
{
    const bool launched = std::wstring(::GetCommandLineW()).find(L"-ToastActivated") != std::wstring::npos;
    if (launched)
    {
        _wfopen_s(&g_log, NextToExe(L"probe.log").c_str(), L"a, ccs=UTF-8");
        SYSTEMTIME now;
        ::GetLocalTime(&now);
        Log(L"==== launched %02d:%02d:%02d pid=%lu\n[cmdline] %ls\n", now.wHour, now.wMinute,
            now.wSecond, ::GetCurrentProcessId(), ::GetCommandLineW());
    }

    const std::wstring variant = launched ? L"launched" : (argc > 1 ? argv[1] : L"sta");
    const bool wantMta = variant == L"mta";
    const bool setAumid = variant == L"sta-aumid";
    // The same icon every run, so the launched process registers exactly what
    // the showing one did.
    const std::wstring iconPath = (!launched && argc > 2) ? argv[2] : NextToExe(L"probe.png");

    Log(L"[probe] variant=%ls aumid=%ls icon=%ls\n", variant.c_str(), kAumid, iconPath.c_str());

    const HRESULT comInit = ::CoInitializeEx(
        nullptr, wantMta ? COINIT_MULTITHREADED : COINIT_APARTMENTTHREADED);
    Log(L"[probe] CoInitializeEx(%ls) hr=0x%08lx\n",
        wantMta ? L"MTA" : L"STA", static_cast<unsigned long>(comInit));

    if (setAumid)
    {
        const HRESULT hr = ::SetCurrentProcessExplicitAppUserModelID(kAumid);
        Log(L"[probe] SetCurrentProcessExplicitAppUserModelID hr=0x%08lx\n",
            static_cast<unsigned long>(hr));
    }

    // The Windows App SDK runtime, as an unpackaged caller does it.
    auto runtime = Notification::Runtime::Initialize(Notification::RuntimeVersion{0x00010007});
    if (!runtime.has_value())
    {
        Log(L"[probe] Runtime::Initialize failed code=%u system=0x%08lx\n",
            static_cast<unsigned>(runtime.error().code),
            static_cast<unsigned long>(runtime.error().systemCode));
        return 1;
    }
    Notification::Runtime held = std::move(runtime).value();

    Notification::ManagerOptions options;
    options.onInvoked = &OnInvoked;
    options.isPackaged = false;
    options.displayName = kAumid;
    options.iconUri = iconPath;

    auto created = Notification::Manager::Create(options);
    Log(L"[probe] Manager::Create returned; callbacks so far=%d\n", g_count.load());
    if (!created.has_value())
    {
        Log(L"[probe] Manager::Create failed code=%u system=0x%08lx\n",
            static_cast<unsigned>(created.error().code),
            static_cast<unsigned long>(created.error().systemCode));
        return 1;
    }
    Notification::Manager manager = std::move(created).value();

    if (launched)
    {
        WaitForActivation(20, true);
        Log(L"[probe] RESULT launched: %d callback(s)\n", g_count.load());
        manager.Close();
        held.Close();
        if (SUCCEEDED(comInit)) ::CoUninitialize();
        if (g_log) std::fclose(g_log);
        return g_count.load() > 0 ? 0 : 3;
    }

    const auto setting = manager.GetSetting();
    Log(L"[probe] setting=%d\n", setting.has_value() ? static_cast<int>(setting.value()) : -1);

    Notification::NotificationContent content;
    content.title = L"Activation probe (" + variant + L")";
    content.body = L"Press Open in the notification centre";
    content.tag = L"probe";

    Notification::Button open;
    open.label = L"Open";
    open.args = Notification::ArgumentPairs{{L"action", L"open"}};
    content.buttons = {open};

    const auto shown = manager.Show(content);
    if (!shown.has_value())
    {
        Log(L"[probe] Show failed code=%u system=0x%08lx\n",
            static_cast<unsigned>(shown.error().code),
            static_cast<unsigned long>(shown.error().systemCode));
        return 1;
    }
    Log(L"[probe] shown. Open the notification centre (Win+N) and press Open.\n");

    if (variant == L"cold")
    {
        // Leave the toast and the registration; end the process.
        Log(L"[probe] cold: exiting with the toast left in place\n");
        manager.Close();
        held.Close();
        if (SUCCEEDED(comInit)) ::CoUninitialize();
        return 0;
    }

    const bool activated = WaitForActivation(90);
    Log(activated ? L"[probe] RESULT activated\n" : L"[probe] RESULT timed out\n");

    manager.RemoveAll();
    manager.Close();
    held.Close();
    if (SUCCEEDED(comInit)) ::CoUninitialize();
    return activated ? 0 : 3;
}
