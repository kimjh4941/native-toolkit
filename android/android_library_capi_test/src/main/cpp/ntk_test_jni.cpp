// The JNI helpers of the C ABI tests and the GoogleTest runner (C ABI design part 1, chapter 6,
// AC-14). Each GoogleTest case is one JUnit case: NtkGoogleTest lists the cases and runs one.
#include <android/log.h>
#include <gtest/gtest.h>
#include <jni.h>
#include <unistd.h>

#include <string>
#include <vector>

#include <NativeToolkitC/Android.h>

#include "TestSupport.h"
#include "ntk_debug_probe.h"

#define TEST_LOG(...) __android_log_print(ANDROID_LOG_INFO, "ntk_test", __VA_ARGS__)

namespace {

// Sends each failure to logcat, since stdout is not visible.
class LogcatListener : public testing::EmptyTestEventListener {
    void OnTestPartResult(const testing::TestPartResult& result) override {
        if (result.failed()) {
            __android_log_print(ANDROID_LOG_ERROR, "ntk_test", "%s:%d %s", result.file_name(),
                                result.line_number(), result.summary());
        }
    }
};

void InitGoogleTestOnce(const std::string& filter) {
    static bool initialized = false;
    if (!initialized) {
        int argc = 1;
        char arg0[] = "ntk_test";
        char* argv[] = {arg0, nullptr};
        testing::InitGoogleTest(&argc, argv);
        testing::UnitTest::GetInstance()->listeners().Append(new LogcatListener);
        initialized = true;
    }
    GTEST_FLAG_SET(filter, filter);
}

}  // namespace

// libntk_test.so has a JNI_OnLoad of its own. Without one, ART would find libntk.so's through
// the dependency and run it (stage 1a 3.2); with it, loading this library leaves libntk.so opened
// by the linker only, as an app that opens it with dlopen does (design part 1, 1.4).
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    TEST_LOG("[JNI_OnLoad] libntk_test.so");
    ntktest::SetVm(vm);
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_init(JNIEnv* env, jclass, jobject context) {
    return ntk_android_init(env, context);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_initWithoutEnv(JNIEnv*, jclass, jobject context) {
    return ntk_android_init(nullptr, context);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_isInitialized(JNIEnv*, jclass) {
    return ntk_android_is_initialized();
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_listCases(JNIEnv* env, jclass) {
    InitGoogleTestOnce("*");
    std::vector<std::string> names;
    testing::UnitTest* unit = testing::UnitTest::GetInstance();
    for (int i = 0; i < unit->total_test_suite_count(); ++i) {
        const testing::TestSuite* suite = unit->GetTestSuite(i);
        for (int j = 0; j < suite->total_test_count(); ++j) {
            names.push_back(std::string(suite->name()) + "." + suite->GetTestInfo(j)->name());
        }
    }
    jclass string_class = env->FindClass("java/lang/String");
    jobjectArray result = env->NewObjectArray(static_cast<jsize>(names.size()), string_class, nullptr);
    for (size_t i = 0; i < names.size(); ++i) {
        jstring name = env->NewStringUTF(names[i].c_str());
        env->SetObjectArrayElement(result, static_cast<jsize>(i), name);
        env->DeleteLocalRef(name);
    }
    return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_runCase(JNIEnv* env, jclass, jstring name) {
    const char* chars = env->GetStringUTFChars(name, nullptr);
    std::string filter = chars;
    env->ReleaseStringUTFChars(name, chars);
    InitGoogleTestOnce(filter);
    int failed = RUN_ALL_TESTS();
    const testing::UnitTest* unit = testing::UnitTest::GetInstance();
    TEST_LOG("[runCase] %s ran %d, failed %d", filter.c_str(), unit->test_to_run_count(), failed);
    return unit->test_to_run_count() == 1 && failed == 0 ? JNI_TRUE : JNI_FALSE;
}

// For the uninitialized case of the probe (noStartup): the error, and whether release ran on the
// calling thread before the call returned (design part 1, 1.3, 1.4).
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_probeStartRejected(JNIEnv* env, jclass) {
    ntktest::Recorder recorder;
    uint64_t id = 99;
    int32_t error = ntk_debug_probe_start(ntktest::Recorder::Done, &recorder, ntktest::Recorder::Release, &id);
    std::vector<ntktest::Record> records = recorder.Records();
    bool released_here = records.size() == 1 && records[0].what == "release" && records[0].thread == gettid();
    jint values[] = {error, released_here ? 1 : 0, static_cast<jint>(id)};
    jintArray result = env->NewIntArray(3);
    env->SetIntArrayRegion(result, 0, 3, values);
    return result;
}
