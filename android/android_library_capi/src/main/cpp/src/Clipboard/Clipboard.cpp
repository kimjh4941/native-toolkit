#include "Clipboard/Clipboard.h"

#include <climits>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "Common/Accept.h"
#include "Common/Errors.h"
#include "Common/Export.h"
#include "Common/Jni.h"
#include "Common/Log.h"
#include "Common/Registry.h"
#include "Common/Runtime.h"
#include "Common/StructSize.h"
#include "Common/Utf8.h"
#include "NativeToolkitC/Clipboard.h"

// The output handles (design part 1, 5.7: C heap, no JNI references). The text inside is the
// user's clipboard: it is never logged.
struct ntk_clipboard_content {
    struct Item {
        std::optional<std::string> text;
        std::optional<std::string> html;
        std::optional<std::string> uri;
        std::optional<std::string> coerced;
    };
    std::optional<std::string> label;
    std::vector<std::string> mime_types;
    std::vector<Item> items;
};

struct ntk_clipboard_description {
    std::optional<std::string> label;
    std::vector<std::string> mime_types;
    int32_t styled = 0;
    int32_t classification = -1;
};

namespace nativetoolkit::clipboard {
namespace {

constexpr int32_t kKindChange = 100;  // ClipboardBridge.KIND_CHANGE
constexpr int32_t kEmptyItems = NTK_CLIPBOARD_ERROR_EMPTY_ITEMS;

jclass g_bridge = nullptr;
jmethodID g_copy_text = nullptr;
jmethodID g_copy_html = nullptr;
jmethodID g_copy_uri = nullptr;
jmethodID g_copy_texts = nullptr;
jmethodID g_clear = nullptr;
jmethodID g_read = nullptr;
jmethodID g_has_clip = nullptr;
jmethodID g_get_description = nullptr;
jmethodID g_start_observing = nullptr;
jmethodID g_stop_observing = nullptr;
jmethodID g_add_listener = nullptr;

// ClipboardBridge.nativeChanged: a change for one registration, on the main thread.
void JNICALL NativeChanged(JNIEnv* /*env*/, jclass /*type*/, jlong id) {
    NTK_LOGD("[NativeChanged] id: %lld", static_cast<long long>(id));
    registry::DeliverOnMain(static_cast<uint64_t>(id), [](registry::Registration& registration) {
        reinterpret_cast<ntk_clipboard_change_fn>(registration.callback)(registration.user_data);
    });
}

// What every entry checks after its own arguments: the initialization (AC-3), then a JNIEnv.
ntk_clipboard_error Enter(JNIEnv** env) {
    NTK_LOGD("[Enter]");
    if (!runtime::IsReady()) return NTK_CLIPBOARD_ERROR_NOT_INITIALIZED;
    *env = jni::Env();
    return *env == nullptr ? NTK_CLIPBOARD_ERROR_UNKNOWN : NTK_CLIPBOARD_ERROR_NONE;
}

// The options as Kotlin takes them: the label (null when absent) and the sensitive flag.
ntk_clipboard_error ReadOptions(JNIEnv* env, const ntk_clipboard_copy_options* options, jbyteArray* label,
                                jboolean* sensitive) {
    NTK_LOGD("[ReadOptions] env: %p, options: %p", env, options);
    *label = nullptr;
    *sensitive = JNI_FALSE;
    ntk_clipboard_copy_options read{};
    int32_t error = structs::Read(options, &read, true);
    if (error != kErrorNone) return error;
    if (read.reserved1 != 0) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    *sensitive = read.sensitive != 0 ? JNI_TRUE : JNI_FALSE;
    return utf8::ToJavaOrNull(env, read.label, label);
}

// The arguments' checks, made before the initialization's (part 1, 1.3; review K-C3): a string is
// NULL (where allowed) or strict UTF-8, and the options follow the struct_size rules.
bool ValidText(const char* text) {
    NTK_LOGD("[ValidText] text: %p", static_cast<const void*>(text));
    size_t length = 0;
    return text == nullptr || (utf8::Length(text, &length) && utf8::IsStrict(std::string_view(text, length)));
}

ntk_clipboard_error CheckOptions(const ntk_clipboard_copy_options* options) {
    NTK_LOGD("[CheckOptions] options: %p", static_cast<const void*>(options));
    ntk_clipboard_copy_options read{};
    if (int32_t error = structs::Read(options, &read, true); error != kErrorNone) return error;
    if (read.reserved1 != 0 || !ValidText(read.label)) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    return NTK_CLIPBOARD_ERROR_NONE;
}

// Calls a bridge method that returns the error as an int.
ntk_clipboard_error ErrorFromCall(JNIEnv* env, jint result, const char* where) {
    NTK_LOGD("[ErrorFromCall] env: %p, result: %d, where: %s", env, result, where);
    jni::Failure failure = jni::TakeException(env, where);
    return failure != jni::Failure::kNone ? ErrorOf(failure) : result;
}

// Copies a Java byte array that may be null into an optional string.
ntk_clipboard_error OptionalString(JNIEnv* env, jobject bytes, std::optional<std::string>* out) {
    NTK_LOGD("[OptionalString] env: %p, bytes: %p", env, bytes);
    std::string text;
    bool is_null = false;
    int32_t error = utf8::FromJava(env, static_cast<jbyteArray>(bytes), &text, &is_null);
    if (error != kErrorNone) return error;
    if (is_null) {
        out->reset();
    } else {
        *out = std::move(text);
    }
    return NTK_CLIPBOARD_ERROR_NONE;
}

ntk_clipboard_error StringArray(JNIEnv* env, jobject array, std::vector<std::string>* out) {
    NTK_LOGD("[StringArray] env: %p, array: %p", env, array);
    auto strings = static_cast<jobjectArray>(array);
    jsize count = env->GetArrayLength(strings);
    for (jsize i = 0; i < count; ++i) {
        std::optional<std::string> value;
        jobject element = env->GetObjectArrayElement(strings, i);
        int32_t error = OptionalString(env, element, &value);
        env->DeleteLocalRef(element);
        if (error != kErrorNone) return error;
        out->push_back(value.value_or(std::string()));
    }
    return NTK_CLIPBOARD_ERROR_NONE;
}

const char* Text(const std::optional<std::string>& value, size_t* out_size) {
    if (out_size != nullptr) *out_size = value ? value->size() : 0;
    return value ? value->c_str() : nullptr;
}

const char* At(const std::vector<std::string>& values, size_t index, size_t* out_size) {
    if (index >= values.size()) {
        if (out_size != nullptr) *out_size = 0;
        return nullptr;
    }
    if (out_size != nullptr) *out_size = values[index].size();
    return values[index].c_str();
}

const std::optional<std::string>* ItemField(const ntk_clipboard_content* content, size_t index,
                                            std::optional<std::string> ntk_clipboard_content::Item::*field) {
    if (content == nullptr || index >= content->items.size()) return nullptr;
    return &(content->items[index].*field);
}

const char* ItemText(const ntk_clipboard_content* content, size_t index,
                     std::optional<std::string> ntk_clipboard_content::Item::*field, size_t* out_size) {
    const std::optional<std::string>* value = ItemField(content, index, field);
    if (value == nullptr) {
        if (out_size != nullptr) *out_size = 0;
        return nullptr;
    }
    return Text(*value, out_size);
}

}  // namespace

classes::ClassSpec ClassSpec() {
    NTK_LOGD("[clipboard::ClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/ClipboardBridge",
        &g_bridge,
        {
            {"copyText", "([B[BZ)I", &g_copy_text},
            {"copyHtml", "([B[B[BZ)I", &g_copy_html},
            {"copyUri", "([B[BZ)I", &g_copy_uri},
            {"copyTexts", "([[B[BZ)I", &g_copy_texts},
            {"clear", "()I", &g_clear},
            {"read", "([I)[Ljava/lang/Object;", &g_read},
            {"hasClip", "([Z)I", &g_has_clip},
            {"getDescription", "([I)[Ljava/lang/Object;", &g_get_description},
            {"startObserving", "()Z", &g_start_observing},
            {"stopObserving", "()Z", &g_stop_observing},
            {"addListener", "(J)Z", &g_add_listener},
        },
        {{"nativeChanged", "(J)V", reinterpret_cast<void*>(NativeChanged)}},
    };
}

}  // namespace nativetoolkit::clipboard

namespace clipboard = nativetoolkit::clipboard;
namespace jni = nativetoolkit::jni;
namespace utf8 = nativetoolkit::utf8;
namespace registry = nativetoolkit::registry;
using nativetoolkit::kErrorNone;

// --- writes (OP-01 to OP-05) -----------------------------------------------------------------

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(const char* text, const ntk_clipboard_copy_options* options) {
    NTK_LOGD("[ntk_clipboard_copy_text] text: %p, options: %p", text, options);
    if (text == nullptr || !clipboard::ValidText(text)) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    if (ntk_clipboard_error error = clipboard::CheckOptions(options); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jbyteArray java_text = nullptr;
    jbyteArray label = nullptr;
    jboolean sensitive = JNI_FALSE;
    if (int32_t error = utf8::ToJava(env, text, &java_text); error != kErrorNone) return error;
    if (int32_t error = clipboard::ReadOptions(env, options, &label, &sensitive); error != kErrorNone) return error;
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_copy_text, java_text, label, sensitive);
    return clipboard::ErrorFromCall(env, result, "ClipboardBridge.copyText");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(const char* html, const char* plain_text,
                                                             const ntk_clipboard_copy_options* options) {
    NTK_LOGD("[ntk_clipboard_copy_html] html: %p, plain_text: %p, options: %p", html, plain_text, options);
    if (html == nullptr || !clipboard::ValidText(html) || !clipboard::ValidText(plain_text)) {
        return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    }
    if (ntk_clipboard_error error = clipboard::CheckOptions(options); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jbyteArray java_html = nullptr;
    jbyteArray java_plain = nullptr;
    jbyteArray label = nullptr;
    jboolean sensitive = JNI_FALSE;
    if (int32_t error = utf8::ToJava(env, html, &java_html); error != kErrorNone) return error;
    // plain_text NULL is "" (part 2, 6.1); the bridge reads a null array that way.
    if (int32_t error = utf8::ToJavaOrNull(env, plain_text, &java_plain); error != kErrorNone) return error;
    if (int32_t error = clipboard::ReadOptions(env, options, &label, &sensitive); error != kErrorNone) return error;
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_copy_html, java_html, java_plain, label,
                                           sensitive);
    return clipboard::ErrorFromCall(env, result, "ClipboardBridge.copyHtml");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_copy_uri(const char* uri, const ntk_clipboard_copy_options* options) {
    NTK_LOGD("[ntk_clipboard_copy_uri] uri: %p, options: %p", uri, options);
    if (uri == nullptr || !clipboard::ValidText(uri)) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    if (ntk_clipboard_error error = clipboard::CheckOptions(options); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jbyteArray java_uri = nullptr;
    jbyteArray label = nullptr;
    jboolean sensitive = JNI_FALSE;
    if (int32_t error = utf8::ToJava(env, uri, &java_uri); error != kErrorNone) return error;
    if (int32_t error = clipboard::ReadOptions(env, options, &label, &sensitive); error != kErrorNone) return error;
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_copy_uri, java_uri, label, sensitive);
    return clipboard::ErrorFromCall(env, result, "ClipboardBridge.copyUri");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_copy_texts(const char* const* texts, size_t count,
                                                              const ntk_clipboard_copy_options* options) {
    NTK_LOGD("[ntk_clipboard_copy_texts] texts: %p, count: %zu, options: %p", static_cast<const void*>(texts), count,
             options);
    // No items is decided at the entry (part 2, AP-19).
    if (count == 0) return clipboard::kEmptyItems;
    if (texts == nullptr || count > static_cast<size_t>(INT32_MAX)) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    for (size_t i = 0; i < count; ++i) {
        if (texts[i] == nullptr || !clipboard::ValidText(texts[i])) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    }
    if (ntk_clipboard_error error = clipboard::CheckOptions(options); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jclass byte_array = env->FindClass("[B");
    jobjectArray java_texts = byte_array == nullptr ? nullptr
        : env->NewObjectArray(static_cast<jsize>(count), byte_array, nullptr);
    if (jni::Failure failure = jni::TakeException(env, "NewObjectArray"); failure != jni::Failure::kNone || java_texts == nullptr) {
        return nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    for (size_t i = 0; i < count; ++i) {
        jbyteArray item = nullptr;
        if (int32_t error = utf8::ToJava(env, texts[i], &item); error != kErrorNone) return error;
        env->SetObjectArrayElement(java_texts, static_cast<jsize>(i), item);
        env->DeleteLocalRef(item);
        if (jni::Failure failure = jni::TakeException(env, "SetObjectArrayElement"); failure != jni::Failure::kNone) {
            return nativetoolkit::ErrorOf(failure);
        }
    }
    jbyteArray label = nullptr;
    jboolean sensitive = JNI_FALSE;
    if (int32_t error = clipboard::ReadOptions(env, options, &label, &sensitive); error != kErrorNone) return error;
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_copy_texts, java_texts, label, sensitive);
    return clipboard::ErrorFromCall(env, result, "ClipboardBridge.copyTexts");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void) {
    NTK_LOGD("[ntk_clipboard_clear]");
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_clear);
    return clipboard::ErrorFromCall(env, result, "ClipboardBridge.clear");
}

// --- reads and queries (OP-06 to OP-08) ------------------------------------------------------

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_read(ntk_clipboard_content** out_content) {
    NTK_LOGD("[ntk_clipboard_read] out_content: %p", static_cast<void*>(out_content));
    if (out_content == nullptr) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    *out_content = nullptr;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jintArray error_box = env->NewIntArray(1);
    if (jni::Failure failure = jni::TakeException(env, "NewIntArray"); failure != jni::Failure::kNone || error_box == nullptr) {
        return nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    auto parts = static_cast<jobjectArray>(env->CallStaticObjectMethod(clipboard::g_bridge, clipboard::g_read, error_box));
    if (jni::Failure failure = jni::TakeException(env, "ClipboardBridge.read"); failure != jni::Failure::kNone) {
        return nativetoolkit::ErrorOf(failure);
    }
    jint error = 0;
    env->GetIntArrayRegion(error_box, 0, 1, &error);
    if (error != NTK_CLIPBOARD_ERROR_NONE || parts == nullptr) return error;
    try {
        auto content = std::make_unique<ntk_clipboard_content>();
        jobject label = env->GetObjectArrayElement(parts, 0);
        jobject mimes = env->GetObjectArrayElement(parts, 1);
        auto items = static_cast<jobjectArray>(env->GetObjectArrayElement(parts, 2));
        int32_t copy_error = clipboard::OptionalString(env, label, &content->label);
        if (copy_error == kErrorNone) copy_error = clipboard::StringArray(env, mimes, &content->mime_types);
        jsize fields = copy_error == kErrorNone ? env->GetArrayLength(items) : 0;
        for (jsize i = 0; copy_error == kErrorNone && i + 3 < fields; i += 4) {
            ntk_clipboard_content::Item item;
            std::optional<std::string>* targets[] = {&item.text, &item.html, &item.uri, &item.coerced};
            for (jsize j = 0; j < 4 && copy_error == kErrorNone; ++j) {
                jobject field = env->GetObjectArrayElement(items, i + j);
                copy_error = clipboard::OptionalString(env, field, targets[j]);
                env->DeleteLocalRef(field);
            }
            content->items.push_back(std::move(item));
        }
        if (copy_error != kErrorNone) return copy_error;
        *out_content = content.release();
        return NTK_CLIPBOARD_ERROR_NONE;
    } catch (const std::bad_alloc&) {
        return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    }
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int32_t* out_has_clip) {
    NTK_LOGD("[ntk_clipboard_has_clip] out_has_clip: %p", static_cast<void*>(out_has_clip));
    if (out_has_clip == nullptr) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    *out_has_clip = 0;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jbooleanArray box = env->NewBooleanArray(1);
    if (jni::Failure failure = jni::TakeException(env, "NewBooleanArray"); failure != jni::Failure::kNone || box == nullptr) {
        return nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    jint result = env->CallStaticIntMethod(clipboard::g_bridge, clipboard::g_has_clip, box);
    ntk_clipboard_error error = clipboard::ErrorFromCall(env, result, "ClipboardBridge.hasClip");
    if (error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jboolean has = JNI_FALSE;
    env->GetBooleanArrayRegion(box, 0, 1, &has);
    *out_has_clip = has == JNI_TRUE ? 1 : 0;
    return NTK_CLIPBOARD_ERROR_NONE;
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_get_description(ntk_clipboard_description** out_description) {
    NTK_LOGD("[ntk_clipboard_get_description] out_description: %p", static_cast<void*>(out_description));
    if (out_description == nullptr) return NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    *out_description = nullptr;
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jintArray error_box = env->NewIntArray(1);
    if (jni::Failure failure = jni::TakeException(env, "NewIntArray"); failure != jni::Failure::kNone || error_box == nullptr) {
        return nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    auto parts = static_cast<jobjectArray>(
        env->CallStaticObjectMethod(clipboard::g_bridge, clipboard::g_get_description, error_box));
    if (jni::Failure failure = jni::TakeException(env, "ClipboardBridge.getDescription"); failure != jni::Failure::kNone) {
        return nativetoolkit::ErrorOf(failure);
    }
    jint error = 0;
    env->GetIntArrayRegion(error_box, 0, 1, &error);
    if (error != NTK_CLIPBOARD_ERROR_NONE || parts == nullptr) return error;
    try {
        auto description = std::make_unique<ntk_clipboard_description>();
        int32_t copy_error = clipboard::OptionalString(env, env->GetObjectArrayElement(parts, 0), &description->label);
        if (copy_error == kErrorNone) {
            copy_error = clipboard::StringArray(env, env->GetObjectArrayElement(parts, 1), &description->mime_types);
        }
        if (copy_error == kErrorNone) {
            auto flags = static_cast<jintArray>(env->GetObjectArrayElement(parts, 2));
            jint values[2] = {0, -1};
            env->GetIntArrayRegion(flags, 0, 2, values);
            description->styled = values[0];
            description->classification = values[1];
        }
        if (copy_error != kErrorNone) return copy_error;
        *out_description = description.release();
        return NTK_CLIPBOARD_ERROR_NONE;
    } catch (const std::bad_alloc&) {
        return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    }
}

// --- observing and events (OP-09 to OP-12) ---------------------------------------------------

// Posted; NONE means accepted, not that observing started (part 2, 6.1).
static ntk_clipboard_error PostObserving(jmethodID method, const char* where) {
    NTK_LOGD("[PostObserving] where: %s", where);
    JNIEnv* env = nullptr;
    if (ntk_clipboard_error error = clipboard::Enter(&env); error != NTK_CLIPBOARD_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    if (!frame.ok()) return NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY;
    jboolean posted = env->CallStaticBooleanMethod(clipboard::g_bridge, method);
    if (jni::Failure failure = jni::TakeException(env, where); failure != jni::Failure::kNone) {
        return nativetoolkit::ErrorOf(failure);
    }
    return posted == JNI_TRUE ? NTK_CLIPBOARD_ERROR_NONE : NTK_CLIPBOARD_ERROR_UNKNOWN;
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_start_observing(void) {
    NTK_LOGD("[ntk_clipboard_start_observing]");
    return PostObserving(clipboard::g_start_observing, "ClipboardBridge.startObserving");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_stop_observing(void) {
    NTK_LOGD("[ntk_clipboard_stop_observing]");
    return PostObserving(clipboard::g_stop_observing, "ClipboardBridge.stopObserving");
}

NTK_EXPORT ntk_clipboard_error NTK_CALL ntk_clipboard_add_change_listener(ntk_clipboard_change_fn callback, void* user_data,
                                                                       ntk_release_fn release,
                                                                       ntk_clipboard_listener** out_listener) {
    NTK_LOGD("[ntk_clipboard_add_change_listener] callback: %p, user_data: %p, out_listener: %p",
             reinterpret_cast<void*>(callback), user_data, static_cast<void*>(out_listener));
    if (out_listener != nullptr) *out_listener = nullptr;
    ntk_clipboard_error error = NTK_CLIPBOARD_ERROR_NONE;
    JNIEnv* env = nullptr;
    if (callback == nullptr || out_listener == nullptr) {
        error = NTK_CLIPBOARD_ERROR_INVALID_PARAMETER;
    } else {
        error = clipboard::Enter(&env);
    }
    if (error != NTK_CLIPBOARD_ERROR_NONE) {
        registry::ReleaseRejected(release, user_data);
        return error;
    }
    jni::LocalFrame frame(env, 4);
    uint64_t id = 0;
    error = nativetoolkit::Accept(env, clipboard::kKindChange, reinterpret_cast<void*>(callback), user_data, release,
                                  nullptr,
                                  [](JNIEnv* e, jlong registration) {
                                      return e->CallStaticBooleanMethod(clipboard::g_bridge, clipboard::g_add_listener,
                                                                        registration);
                                  },
                                  &id);
    // The handle is the registration id, never reused (AC-17): a stale handle finds nothing.
    if (error == NTK_CLIPBOARD_ERROR_NONE) *out_listener = reinterpret_cast<ntk_clipboard_listener*>(id);
    return error;
}

NTK_EXPORT void NTK_CALL ntk_clipboard_listener_remove(ntk_clipboard_listener* listener) {
    NTK_LOGD("[ntk_clipboard_listener_remove] listener: %p", static_cast<void*>(listener));
    // Removes the registration only; observing goes on (part 2, AP-11).
    if (listener != nullptr) registry::Cancel(reinterpret_cast<uint64_t>(listener), {clipboard::kKindChange});
}

// --- readers (the output handles) ------------------------------------------------------------

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_label(const ntk_clipboard_content* content, size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_label] content: %p", static_cast<const void*>(content));
    if (content == nullptr) return clipboard::Text(std::nullopt, out_size);
    return clipboard::Text(content->label, out_size);
}

NTK_EXPORT size_t NTK_CALL ntk_clipboard_content_mime_type_count(const ntk_clipboard_content* content) {
    NTK_LOGD("[ntk_clipboard_content_mime_type_count] content: %p", static_cast<const void*>(content));
    return content == nullptr ? 0 : content->mime_types.size();
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_mime_type_at(const ntk_clipboard_content* content, size_t index,
                                                                size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_mime_type_at] content: %p, index: %zu", static_cast<const void*>(content), index);
    // No static empty list: its destructor would run at exit (part 1, 5.5).
    if (content == nullptr) return clipboard::At({}, index, out_size);
    return clipboard::At(content->mime_types, index, out_size);
}

NTK_EXPORT size_t NTK_CALL ntk_clipboard_content_item_count(const ntk_clipboard_content* content) {
    NTK_LOGD("[ntk_clipboard_content_item_count] content: %p", static_cast<const void*>(content));
    return content == nullptr ? 0 : content->items.size();
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_item_text_at(const ntk_clipboard_content* content, size_t index,
                                                                size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_item_text_at] content: %p, index: %zu", static_cast<const void*>(content), index);
    return clipboard::ItemText(content, index, &ntk_clipboard_content::Item::text, out_size);
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_item_html_at(const ntk_clipboard_content* content, size_t index,
                                                                size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_item_html_at] content: %p, index: %zu", static_cast<const void*>(content), index);
    return clipboard::ItemText(content, index, &ntk_clipboard_content::Item::html, out_size);
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_item_uri_at(const ntk_clipboard_content* content, size_t index,
                                                               size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_item_uri_at] content: %p, index: %zu", static_cast<const void*>(content), index);
    return clipboard::ItemText(content, index, &ntk_clipboard_content::Item::uri, out_size);
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_content_item_coerced_text_at(const ntk_clipboard_content* content,
                                                                        size_t index, size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_content_item_coerced_text_at] content: %p, index: %zu", static_cast<const void*>(content),
             index);
    return clipboard::ItemText(content, index, &ntk_clipboard_content::Item::coerced, out_size);
}

NTK_EXPORT void NTK_CALL ntk_clipboard_content_free(ntk_clipboard_content* content) {
    NTK_LOGD("[ntk_clipboard_content_free] content: %p", static_cast<void*>(content));
    delete content;
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_description_label(const ntk_clipboard_description* description,
                                                             size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_description_label] description: %p", static_cast<const void*>(description));
    if (description == nullptr) return clipboard::Text(std::nullopt, out_size);
    return clipboard::Text(description->label, out_size);
}

NTK_EXPORT size_t NTK_CALL ntk_clipboard_description_mime_type_count(const ntk_clipboard_description* description) {
    NTK_LOGD("[ntk_clipboard_description_mime_type_count] description: %p", static_cast<const void*>(description));
    return description == nullptr ? 0 : description->mime_types.size();
}

NTK_EXPORT const char* NTK_CALL ntk_clipboard_description_mime_type_at(const ntk_clipboard_description* description,
                                                                    size_t index, size_t* out_size) {
    NTK_LOGD("[ntk_clipboard_description_mime_type_at] description: %p, index: %zu",
             static_cast<const void*>(description), index);
    if (description == nullptr) return clipboard::At({}, index, out_size);
    return clipboard::At(description->mime_types, index, out_size);
}

NTK_EXPORT int32_t NTK_CALL ntk_clipboard_description_is_styled_text(const ntk_clipboard_description* description) {
    NTK_LOGD("[ntk_clipboard_description_is_styled_text] description: %p", static_cast<const void*>(description));
    return description == nullptr ? 0 : description->styled;
}

NTK_EXPORT int32_t NTK_CALL ntk_clipboard_description_classification_status(const ntk_clipboard_description* description) {
    NTK_LOGD("[ntk_clipboard_description_classification_status] description: %p",
             static_cast<const void*>(description));
    return description == nullptr ? -1 : description->classification;
}

NTK_EXPORT void NTK_CALL ntk_clipboard_description_free(ntk_clipboard_description* description) {
    NTK_LOGD("[ntk_clipboard_description_free] description: %p", static_cast<void*>(description));
    delete description;
}
