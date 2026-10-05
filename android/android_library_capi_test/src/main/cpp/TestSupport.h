// What the GoogleTest cases need around the C ABI: the main thread (run on it, hold it, wait for
// it to catch up), the Kotlin ledger's size, and a recorder for callbacks and releases.
#pragma once

#include <jni.h>

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace ntktest {

void SetVm(JavaVM* vm);
JNIEnv* Env();
bool OnMain();

// Runs task on the main thread and waits for it.
void RunOnMain(std::function<void()> task);
// Waits until the main thread has run every message posted before this call.
void DrainMain();
// Holds the main thread until UnholdMain, so that messages queue up behind it.
void HoldMain();
void UnholdMain();
// The size of capi.jni.Ledger, read on the main thread.
int LedgerSize();
// The screen, through UiDriver (androidTest): each returns whether it happened.
bool UiWaitText(const char* text);
bool UiStaysAway(const char* text, int64_t ms);
bool UiGone(const char* text);
bool UiClick(const char* text);
bool UiType(int32_t index, const char* text);
void UiBack();
bool UiHome();
// The notification shade: open it and wait for text, swipe the notification showing text away.
bool UiOpenShade(const char* text);
bool UiSwipeAway(const char* text);
void UiCloseShade();
// Clicks text in a list, scrolling to it; presses Back until the app is in front again.
bool UiPick(const char* text);
bool UiSharesheetShown();
bool UiBackToApp();
// The simple class name of the app's foreground Activity once there is one, or "".
std::string UiForegroundActivity();
bool UiFinishForeground();
// How many Activities the app has created since the first call (the first call starts counting).
int32_t ActivitiesCreated();

// Notifications, through NotificationInspector (androidTest). Fields are strings; "<null>" when the
// notification or the field is not there.
void GrantNotifications();
void AllowExactAlarms();
bool WaitShown(int32_t id, const char* tag, int64_t ms = 5000);
bool WaitGone(int32_t id, const char* tag, int64_t ms = 5000);
std::string NotificationField(int32_t id, const char* tag, const char* name);
std::string ChannelField(const char* channel_id, const char* name);
std::string ResourceId(const char* name, const char* type);
// Sends a PendingIntent of a shown notification ("content", "delete" or "action:<index>") and
// returns once the library's receiver has handled it.
bool FireIntent(int32_t id, const char* tag, const char* which);

// Share, through ShareInspector (androidTest): a small PNG, a file in the cache directory (inside
// the FileProvider paths), the dynamic shortcut IDs joined by "|", the test app's package name,
// and a Sharesheet for selection opened from Kotlin directly.
std::vector<uint8_t> PngBytes();
std::string MakeShareFile(const char* name, bool image);
std::string DynamicShortcutIds();
std::string TestPackage();
void ShareFromKotlin(const char* text);

// Puts a plain-text clip from Kotlin, given as UTF-16 code units (so it may hold what C cannot).
void SetClipboardText(const std::u16string& text);

// A test's callback state, never freed. A case that fails half-way returns early, and a
// completion still on its way would then write into a destroyed object and could hang the main
// thread; each case runs in a process of its own, so nothing piles up.
template <class T>
T& Leaked() {
    return *new T();
}

// One callback or release, as it happened.
struct Record {
    std::string what;  // "done", "event", "release", or a marker
    int32_t error = 0;
    int64_t value = 0;
    bool on_main = false;
    pid_t thread = 0;
    std::string detail{};  // what an event carried, for the cases that compare it
};

// Collects records from any thread and waits for them.
class Recorder {
public:
    void Add(Record record);
    std::vector<Record> Records();
    // Waits until count records named what have arrived, or the timeout passes.
    bool WaitFor(const std::string& what, size_t count, std::chrono::milliseconds timeout = std::chrono::seconds(5));
    size_t Count(const std::string& what);

    // Callbacks with a Recorder* as user_data.
    static void Done(void* user_data, int32_t error, int64_t value);
    static void Event(void* user_data, int64_t value);
    static void Release(void* user_data);

private:
    std::mutex mutex_;
    std::condition_variable changed_;
    std::vector<Record> records_;
};

}  // namespace ntktest
