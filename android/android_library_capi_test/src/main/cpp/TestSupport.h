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
// Puts a plain-text clip from Kotlin, given as UTF-16 code units (so it may hold what C cannot).
void SetClipboardText(const std::u16string& text);

// One callback or release, as it happened.
struct Record {
    std::string what;  // "done", "event", "release", or a marker
    int32_t error = 0;
    int64_t value = 0;
    bool on_main = false;
    pid_t thread = 0;
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
