// GoogleTest cases for libntk.so, run from an instrumented test through JNI.
#include <android/log.h>
#include <gtest/gtest.h>
#include <jni.h>
#include <NativeToolkitC/Spike.h>

TEST(Spike, OnLoadRan) { EXPECT_EQ(1, ntk_spike_onload_called()); }

TEST(Spike, CreatedVmIsTheOnLoadVm) {
    int same = 0;
    EXPECT_EQ(1, ntk_spike_created_vms(&same));
    EXPECT_EQ(1, same);
}

TEST(Spike, CallsKotlinFromANewThread) { EXPECT_EQ(0, ntk_spike_call_kotlin_from_new_thread(7)); }

TEST(Spike, LibcxxInsideLibntk) { EXPECT_EQ(6, ntk_spike_cxx_check()); }

namespace {
// Sends each failure to logcat, since stdout is not visible.
class LogcatListener : public testing::EmptyTestEventListener {
    void OnTestPartResult(const testing::TestPartResult& r) override {
        if (r.failed()) {
            __android_log_print(ANDROID_LOG_ERROR, "ntk_test", "%s:%d %s", r.file_name(),
                                r.line_number(), r.summary());
        }
    }
    void OnTestEnd(const testing::TestInfo& info) override {
        __android_log_print(ANDROID_LOG_INFO, "ntk_test", "%s.%s %s", info.test_suite_name(),
                            info.name(), info.result()->Passed() ? "passed" : "FAILED");
    }
};
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_example_capitest_NtkGTest_runAll(JNIEnv*, jclass) {
    int argc = 1;
    char arg0[] = "ntk_test";
    char* argv[] = {arg0, nullptr};
    testing::InitGoogleTest(&argc, argv);
    testing::UnitTest::GetInstance()->listeners().Append(new LogcatListener);
    return RUN_ALL_TESTS();
}
