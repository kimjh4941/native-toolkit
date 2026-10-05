#include "Common/Utf8.h"

#include <climits>
#include <cstring>

#include "Common/Errors.h"
#include "Common/Jni.h"
#include "Common/Log.h"

namespace nativetoolkit::utf8 {

bool IsStrict(std::string_view text) {
    NTK_LOGD("[IsStrict] length: %zu", text.size());
    const auto* p = reinterpret_cast<const unsigned char*>(text.data());
    const auto* end = p + text.size();
    while (p < end) {
        unsigned char c = *p;
        if (c < 0x80) {
            ++p;
            continue;
        }
        int extra;
        uint32_t code;
        uint32_t minimum;
        if ((c & 0xE0) == 0xC0) {
            extra = 1; code = c & 0x1F; minimum = 0x80;
        } else if ((c & 0xF0) == 0xE0) {
            extra = 2; code = c & 0x0F; minimum = 0x800;
        } else if ((c & 0xF8) == 0xF0) {
            extra = 3; code = c & 0x07; minimum = 0x10000;
        } else {
            return false;  // a continuation byte first, or F8 to FF
        }
        if (end - p <= extra) return false;
        for (int i = 1; i <= extra; ++i) {
            if ((p[i] & 0xC0) != 0x80) return false;
            code = (code << 6) | (p[i] & 0x3F);
        }
        if (code < minimum) return false;                     // overlong
        if (code >= 0xD800 && code <= 0xDFFF) return false;   // a surrogate
        if (code > 0x10FFFF) return false;
        p += extra + 1;
    }
    return true;
}

bool Length(const char* text, size_t* out_length) {
    NTK_LOGD("[Length] text: %p", text);
    // strnlen stops at the limit, so a string without a terminator within it is rejected
    // without reading further.
    size_t length = strnlen(text, static_cast<size_t>(INT32_MAX) + 1);
    if (length > static_cast<size_t>(INT32_MAX)) return false;
    *out_length = length;
    return true;
}

int32_t ToJava(JNIEnv* env, const char* text, jbyteArray* out) {
    // The text itself may be a secret (clipboard, dialog input): only its address is logged.
    NTK_LOGD("[ToJava] env: %p, text: %p, out: %p", env, text, out);
    *out = nullptr;
    if (text == nullptr) return kErrorInvalidParameter;
    size_t length = 0;
    if (!Length(text, &length) || !IsStrict(std::string_view(text, length))) return kErrorInvalidParameter;
    jbyteArray array = env->NewByteArray(static_cast<jsize>(length));
    if (jni::Failure failure = jni::TakeException(env, "NewByteArray"); failure != jni::Failure::kNone || array == nullptr) {
        return ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    env->SetByteArrayRegion(array, 0, static_cast<jsize>(length), reinterpret_cast<const jbyte*>(text));
    if (jni::Failure failure = jni::TakeException(env, "SetByteArrayRegion"); failure != jni::Failure::kNone) {
        return ErrorOf(failure);
    }
    *out = array;
    return kErrorNone;
}

int32_t ToJavaOrNull(JNIEnv* env, const char* text, jbyteArray* out) {
    NTK_LOGD("[ToJavaOrNull] env: %p, text: %p, out: %p", env, text, out);
    *out = nullptr;
    return text == nullptr ? kErrorNone : ToJava(env, text, out);
}

int32_t FromJava(JNIEnv* env, jbyteArray bytes, std::string* out, bool* is_null) {
    NTK_LOGD("[FromJava] env: %p, bytes: %p", env, bytes);
    out->clear();
    *is_null = bytes == nullptr;
    if (bytes == nullptr) return kErrorNone;
    jsize length = env->GetArrayLength(bytes);
    try {
        out->resize(static_cast<size_t>(length));
    } catch (const std::bad_alloc&) {
        return kErrorOutOfMemory;
    }
    // One copy for the whole array (design 5.10).
    env->GetByteArrayRegion(bytes, 0, length, reinterpret_cast<jbyte*>(out->data()));
    if (jni::Failure failure = jni::TakeException(env, "GetByteArrayRegion"); failure != jni::Failure::kNone) {
        return ErrorOf(failure);
    }
    return kErrorNone;
}

}  // namespace nativetoolkit::utf8
