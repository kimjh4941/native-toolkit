// macOS C ABI 1a-9 probe: Main.cpp of Unity's "Create Xcode Project" export (6000.4.2f1), with the
// call that installs the notification delegate before PlayerMain (D-4). Replace the exported Main.cpp
// with this file (or add the marked lines to it). Choose the form with NTK_1A9_INSTALL_AT and rebuild:
//   0: nothing (the host without a native reference to the notification installer)
//   1: register an NSApplicationWillFinishLaunchingNotification observer here; it calls
//      ntk_notification_install when Unity's NSApplication posts it (the recommended form to check)
//   2: call ntk_notification_install here, directly (NSApp does not exist yet; the probe never creates it)
//   3: the same as 1 with NSApplicationDidFinishLaunchingNotification (for comparison; may be late)
// Plain C++: the two functions are declared here, so no header search path and no extra system framework
// is needed. They are in NtkProbeMacCApi.framework (linked and embedded in the app target).
#include <stdint.h>

int PlayerMain(int argc, const char *argv[]);

#if UNITY_ASAN
extern "C"
{
    extern void unity_asan_configure();
}
#endif

// --- native-toolkit 1a-9 probe (begin) ---
#ifndef NTK_1A9_INSTALL_AT
#define NTK_1A9_INSTALL_AT 1
#endif
extern "C" int32_t ntk_notification_install(void);                 // Notification.h
extern "C" int32_t ntk_probe_notification_install_at(int32_t when); // ProbeNotification.h
// --- native-toolkit 1a-9 probe (end) ---

int main(int argc, const char *argv[])
{
#if UNITY_ASAN
    unity_asan_configure();
#endif

    // --- native-toolkit 1a-9 probe (begin) ---
#if NTK_1A9_INSTALL_AT == 2
    (void)ntk_notification_install();
#elif NTK_1A9_INSTALL_AT == 1 || NTK_1A9_INSTALL_AT == 3
    (void)ntk_probe_notification_install_at(NTK_1A9_INSTALL_AT);
#endif
    // The results (and the order of willFinishLaunching, didFinishLaunching, didBecomeActive and the
    // install) are read later from C# with ntk_probe_notification_describe().
    // --- native-toolkit 1a-9 probe (end) ---

    return PlayerMain(argc, argv);
}
