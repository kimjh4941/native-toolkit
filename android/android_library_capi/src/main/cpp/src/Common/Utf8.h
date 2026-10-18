// Strings between C and Kotlin (C ABI design part 1, 5.10, AC-8, AC-19). C to Kotlin: strict
// RFC 3629 UTF-8, checked at the entry, passed as a byte array (never Modified UTF-8). Kotlin to
// C: Kotlin replaces unpaired surrogates and U+0000 with U+FFFD before encoding (capi.jni.Utf8),
// and C copies the bytes.
#pragma once

#include <jni.h>

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace nativetoolkit::utf8 {

// Whether text is strict UTF-8: no overlong forms, no surrogates (ED A0 80 to ED BF BF), nothing
// above U+10FFFF, no truncated sequence.
bool IsStrict(std::string_view text);

// The length of a NUL-terminated string that may be passed to Java: false when it is longer than
// a Java array can hold (design 5.6).
bool Length(const char* text, size_t* out_length);

// Checks text (strict UTF-8 and the length) and makes a Java byte array of it. Returns
// kErrorInvalidParameter for text that fails the checks, an error of ErrorOf for a JNI failure,
// or kErrorNone with *out set. text must not be NULL.
int32_t ToJava(JNIEnv* env, const char* text, jbyteArray* out);

// The same for a string that may be NULL: NULL becomes a null array.
int32_t ToJavaOrNull(JNIEnv* env, const char* text, jbyteArray* out);

// Copies the bytes of a Java byte array that Kotlin made with capi.jni.Utf8. A null array is
// reported through *is_null. Returns kErrorNone or an error of ErrorOf.
int32_t FromJava(JNIEnv* env, jbyteArray bytes, std::string* out, bool* is_null);

}  // namespace nativetoolkit::utf8
