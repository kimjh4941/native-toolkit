// Calls from a thread Java does not know (C ABI design part 1, 5.6 and chapter 6): the library
// attaches it to call Kotlin, and detaches it when the thread ends, unless it is gone already.
#include <gtest/gtest.h>

#include <cstdint>
#include <thread>

#include <NativeToolkitC/Clipboard.h>

#include "../TestSupport.h"

namespace {

struct Seen {
    bool attached_before = true;
    ntk_clipboard_error error = NTK_CLIPBOARD_ERROR_UNKNOWN;
    bool attached_after = false;
    int64_t java_id = -1;
};

// Calls a function that calls Kotlin on this thread, and records what the library did to it.
Seen CallFromANewThread(bool detach_by_hand) {
    Seen seen;
    std::thread thread([&seen, detach_by_hand] {
        seen.attached_before = ntktest::CurrentThreadAttached();
        int32_t has_clip = -1;
        seen.error = ntk_clipboard_has_clip(&has_clip);
        seen.attached_after = ntktest::CurrentThreadAttached();
        seen.java_id = ntktest::CurrentJavaThreadId();
        if (detach_by_hand) ntktest::DetachCurrentThread();
    });
    thread.join();  // the thread's key destructors have run once it has ended
    return seen;
}

}  // namespace

TEST(Thread, AThreadTheLibraryAttachedIsDetachedWhenItEnds) {
    Seen seen = CallFromANewThread(false);
    ASSERT_FALSE(seen.attached_before);
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, seen.error);
    ASSERT_TRUE(seen.attached_after) << "the call did not attach the thread, so this tests nothing";
    ASSERT_GE(seen.java_id, 0);
    EXPECT_FALSE(ntktest::JavaThreadAlive(seen.java_id));
}

TEST(Thread, AThreadDetachedByHandAfterTheLibraryAttachedItEndsQuietly) {
    // The thread ends quietly although the library's key still marks it as attached (5.6). This
    // does not show that the library looks before it detaches: ART answers a detach of a thread
    // that is not attached with JNI_ERR, so the case passes without the look too (review v2, R-C13).
    Seen seen = CallFromANewThread(true);
    ASSERT_EQ(NTK_CLIPBOARD_ERROR_NONE, seen.error);
    ASSERT_TRUE(seen.attached_after);
    EXPECT_FALSE(ntktest::JavaThreadAlive(seen.java_id));
    // The library still works from yet another thread.
    EXPECT_EQ(NTK_CLIPBOARD_ERROR_NONE, CallFromANewThread(false).error);
}
