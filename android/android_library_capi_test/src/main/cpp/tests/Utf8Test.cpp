// The strict UTF-8 check and the Java byte arrays (C ABI design part 1, 5.10, AC-8), on the
// sources of libntk.so compiled into this test library.
#include <gtest/gtest.h>

#include <string>

#include "../TestSupport.h"
#include "Common/Errors.h"
#include "Common/Utf8.h"

using nativetoolkit::utf8::IsStrict;

TEST(Utf8, AcceptsEveryLengthUpToTheLastCodePoint) {
    EXPECT_TRUE(IsStrict(""));
    EXPECT_TRUE(IsStrict("plain ascii"));
    EXPECT_TRUE(IsStrict("\xC3\xA9"));            // U+00E9
    EXPECT_TRUE(IsStrict("\xE3\x81\x82"));        // U+3042
    EXPECT_TRUE(IsStrict("\xEF\xBF\xBD"));        // U+FFFD
    EXPECT_TRUE(IsStrict("\xF0\x9F\x98\x80"));    // U+1F600, outside the BMP
    EXPECT_TRUE(IsStrict("\xF4\x8F\xBF\xBF"));    // U+10FFFF
    EXPECT_TRUE(IsStrict("\xED\x9F\xBF"));        // U+D7FF, just below the surrogates
    EXPECT_TRUE(IsStrict("\xEE\x80\x80"));        // U+E000, just above them
}

TEST(Utf8, RejectsSurrogates) {
    EXPECT_FALSE(IsStrict("\xED\xA0\x80"));  // U+D800
    EXPECT_FALSE(IsStrict("\xED\xBF\xBF"));  // U+DFFF
    EXPECT_FALSE(IsStrict("\xED\xA0\xBD\xED\xB8\x80"));  // a surrogate pair written as UTF-8 (CESU-8)
}

TEST(Utf8, RejectsOverlongForms) {
    EXPECT_FALSE(IsStrict("\xC0\x80"));          // U+0000 the Modified UTF-8 way
    EXPECT_FALSE(IsStrict("\xC1\xBF"));
    EXPECT_FALSE(IsStrict("\xE0\x80\x80"));
    EXPECT_FALSE(IsStrict("\xE0\x9F\xBF"));
    EXPECT_FALSE(IsStrict("\xF0\x80\x80\x80"));
    EXPECT_FALSE(IsStrict("\xF0\x8F\xBF\xBF"));
}

TEST(Utf8, RejectsValuesAboveTheLastCodePoint) {
    EXPECT_FALSE(IsStrict("\xF4\x90\x80\x80"));  // U+110000
    EXPECT_FALSE(IsStrict("\xF5\x80\x80\x80"));
    EXPECT_FALSE(IsStrict("\xF8\x88\x80\x80\x80"));
    EXPECT_FALSE(IsStrict("\xFF"));
}

TEST(Utf8, RejectsBrokenSequences) {
    EXPECT_FALSE(IsStrict("\x80"));              // a continuation byte first
    EXPECT_FALSE(IsStrict("a\xE3\x81"));         // cut short at the end
    EXPECT_FALSE(IsStrict("\xE3\x81" "a"));      // a lead byte followed by ASCII
    EXPECT_FALSE(IsStrict("\xC3\xC3\xA9"));
}

TEST(Utf8, AJavaArrayHoldsTheSameBytes) {
    JNIEnv* env = ntktest::Env();
    const char* text = "A\xC3\xA9\xF0\x9F\x98\x80";
    jbyteArray array = nullptr;
    ASSERT_EQ(nativetoolkit::kErrorNone, nativetoolkit::utf8::ToJava(env, text, &array));
    ASSERT_NE(nullptr, array);
    std::string back;
    bool is_null = true;
    ASSERT_EQ(nativetoolkit::kErrorNone, nativetoolkit::utf8::FromJava(env, array, &back, &is_null));
    EXPECT_FALSE(is_null);
    EXPECT_EQ(std::string(text), back);
    env->DeleteLocalRef(array);
}

TEST(Utf8, TheEntryRejectsWhatIsNotStrictAndNull) {
    JNIEnv* env = ntktest::Env();
    jbyteArray array = reinterpret_cast<jbyteArray>(1);
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, nativetoolkit::utf8::ToJava(env, "\xED\xA0\x80", &array));
    EXPECT_EQ(nullptr, array);
    EXPECT_EQ(nativetoolkit::kErrorInvalidParameter, nativetoolkit::utf8::ToJava(env, nullptr, &array));
    EXPECT_EQ(nativetoolkit::kErrorNone, nativetoolkit::utf8::ToJavaOrNull(env, nullptr, &array));
    EXPECT_EQ(nullptr, array);
    std::string back = "stale";
    bool is_null = false;
    EXPECT_EQ(nativetoolkit::kErrorNone, nativetoolkit::utf8::FromJava(env, nullptr, &back, &is_null));
    EXPECT_TRUE(is_null);
    EXPECT_TRUE(back.empty());
}
