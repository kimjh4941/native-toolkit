#include "Share/Share.h"

#include <cstdint>
#include <initializer_list>
#include <cstring>
#include <string>
#include <string_view>

#include "Common/Accept.h"
#include "Common/Errors.h"
#include "Common/Export.h"
#include "Common/Handles.h"
#include "Common/Jni.h"
#include "Common/Log.h"
#include "Common/Registry.h"
#include "Common/Runtime.h"
#include "Common/StructSize.h"
#include "Common/Utf8.h"
#include "NativeToolkitC/Share.h"

namespace nativetoolkit::share {
namespace {

constexpr int32_t kKindOpen = 400;       // ShareBridge.KIND_OPEN
constexpr int32_t kKindChooser = 401;    // ShareBridge.KIND_CHOOSER_ACTION
constexpr int32_t kKindSelection = 402;  // ShareBridge.KIND_SELECTION

jclass g_bridge = nullptr;
jmethodID g_share_text = nullptr;
jmethodID g_share_image = nullptr;
jmethodID g_share_images = nullptr;
jmethodID g_share_file = nullptr;
jmethodID g_share_files = nullptr;
jmethodID g_share_for_selection = nullptr;
jmethodID g_cancel_selection = nullptr;
jmethodID g_register_direct_target = nullptr;
jmethodID g_remove_direct_targets = nullptr;
jmethodID g_add_chooser_listener = nullptr;
jmethodID g_add_selection_listener = nullptr;

// --- completions and events (main thread) ---

// ShareBridge.nativeDone: the Sharesheet opened (NONE), or why it did not.
void JNICALL NativeDone(JNIEnv* /*env*/, jclass /*type*/, jlong id, jint error) {
    NTK_LOGD("[NativeDone] id: %lld, error: %d", static_cast<long long>(id), error);
    registry::CompleteOnMain(static_cast<uint64_t>(id), [error](registry::Registration& registration) {
        reinterpret_cast<ntk_share_done_fn>(registration.callback)(registration.user_data, error, 0);
    });
}

// A Java string from Utf8.encode (already valid UTF-8); nullopt for null or on a JNI failure.
std::optional<std::string> ReadText(JNIEnv* env, jbyteArray bytes) {
    NTK_LOGD("[ReadText] env: %p, bytes: %p", static_cast<void*>(env), static_cast<void*>(bytes));
    std::string text;
    bool is_null = false;
    if (utf8::FromJava(env, bytes, &text, &is_null) != kErrorNone || is_null) return std::nullopt;
    return text;
}

// ShareBridge.nativeChooserAction: an action of the current share was pressed. Each registration
// gets an ntk_string of its own.
void JNICALL NativeChooserAction(JNIEnv* env, jclass /*type*/, jlong id, jbyteArray action_id) {
    NTK_LOGD("[NativeChooserAction] id: %lld", static_cast<long long>(id));
    std::optional<std::string> text;
    try {
        text = ReadText(env, action_id);
    } catch (...) {
        NTK_LOGE("[NativeChooserAction] out of memory, the event is dropped");
        return;
    }
    if (!text) {
        jni::TakeException(env, "NativeChooserAction");
        return;
    }
    registry::DeliverOnMain(static_cast<uint64_t>(id), [&text](registry::Registration& registration) {
        ntk_string* value = handles::MakeString(*text);
        if (value == nullptr) return;
        reinterpret_cast<ntk_share_chooser_action_fn>(registration.callback)(registration.user_data, value);
    });
}

// ShareBridge.nativeSelection: the app picked in the Sharesheet of request_id; package_name is
// null when Android did not report it.
void JNICALL NativeSelection(JNIEnv* env, jclass /*type*/, jlong id, jlong request_id, jbyteArray package_name) {
    NTK_LOGD("[NativeSelection] id: %lld, request_id: %lld", static_cast<long long>(id),
             static_cast<long long>(request_id));
    std::optional<std::string> text;
    try {
        text = ReadText(env, package_name);
    } catch (...) {
        NTK_LOGE("[NativeSelection] out of memory, the event is dropped");
        return;
    }
    jni::TakeException(env, "NativeSelection");
    registry::DeliverOnMain(static_cast<uint64_t>(id), [&text, request_id](registry::Registration& registration) {
        ntk_string* value = nullptr;
        if (text) {
            value = handles::MakeString(*text);
            if (value == nullptr) return;
        }
        reinterpret_cast<ntk_share_selection_fn>(registration.callback)(registration.user_data,
                                                                        static_cast<uint64_t>(request_id), value);
    });
}

// --- the entry ---

// A call rejected at the entry releases on the calling thread before it returns (part 1, 1.3).
ntk_share_error Reject(ntk_release_fn release, void* user_data, int32_t error) {
    NTK_LOGD("[Reject] error: %d", error);
    registry::ReleaseRejected(release, user_data);
    return error;
}

ntk_share_error Enter(JNIEnv** env) {
    NTK_LOGD("[Enter]");
    if (!runtime::IsReady()) return NTK_SHARE_ERROR_NOT_INITIALIZED;
    *env = jni::Env();
    return *env == nullptr ? NTK_SHARE_ERROR_UNKNOWN : NTK_SHARE_ERROR_NONE;
}

// NULL (the default) or strict UTF-8 within a Java array's length.
bool ValidText(const char* text) {
    NTK_LOGD("[ValidText] text: %p", static_cast<const void*>(text));
    size_t length = 0;
    return text == nullptr || (utf8::Length(text, &length) && utf8::IsStrict(std::string_view(text, length)));
}

bool ValidTexts(std::initializer_list<const char*> texts) {
    for (const char* text : texts) {
        if (!ValidText(text)) return false;
    }
    return true;
}

// The text content (AP-19): the struct, the strings, then an empty text (a blank one is Kotlin's).
int32_t ReadContent(const ntk_share_text_content* in, ntk_share_text_content* out) {
    NTK_LOGD("[ReadContent] in: %p", static_cast<const void*>(in));
    if (int32_t error = structs::Read(in, out, false); error != kErrorNone) return error;
    if (out->text == nullptr ||
        !ValidTexts({out->text, out->title, out->subject, out->mime_type, out->preview_title,
                     out->preview_thumbnail_path})) {
        return NTK_SHARE_ERROR_INVALID_PARAMETER;
    }
    return out->text[0] == '\0' ? NTK_SHARE_ERROR_EMPTY_CONTENT : NTK_SHARE_ERROR_NONE;
}

// The chooser actions (AP-19, 6.4): an empty or repeated ID, or no icon, is INVALID_CHOOSER_ACTION;
// a string that is not UTF-8 is INVALID_PARAMETER. A NULL label is "".
int32_t CheckActions(const ntk_share_chooser_action* actions, size_t count) {
    NTK_LOGD("[CheckActions] actions: %p, count: %zu", static_cast<const void*>(actions), count);
    if (count == 0) return NTK_SHARE_ERROR_NONE;
    if (actions == nullptr || count > static_cast<size_t>(INT32_MAX)) return NTK_SHARE_ERROR_INVALID_PARAMETER;
    for (size_t i = 0; i < count; ++i) {
        const ntk_share_chooser_action& action = actions[i];
        if (!ValidTexts({action.id, action.label})) return NTK_SHARE_ERROR_INVALID_PARAMETER;
        if (action.id == nullptr || action.id[0] == '\0') return NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION;
        // A repeated ID, compared with the earlier ones: no container, so no bad_alloc can leave
        // this C entry (part 1, 1.1). The actions are few.
        for (size_t j = 0; j < i; ++j) {
            if (std::strcmp(actions[j].id, action.id) == 0) return NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION;
        }
        if (action.icon == nullptr || action.icon_size == 0) return NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION;
        if (action.icon_size > static_cast<size_t>(INT32_MAX)) return NTK_SHARE_ERROR_INVALID_PARAMETER;
    }
    return NTK_SHARE_ERROR_NONE;
}

// A list of paths or IDs: none is the given empty error, and no item may be NULL.
int32_t CheckList(const char* const* items, size_t count, int32_t empty_error) {
    NTK_LOGD("[CheckList] items: %p, count: %zu", static_cast<const void*>(items), count);
    if (count == 0) return empty_error;
    if (items == nullptr || count > static_cast<size_t>(INT32_MAX)) return NTK_SHARE_ERROR_INVALID_PARAMETER;
    for (size_t i = 0; i < count; ++i) {
        if (items[i] == nullptr || !ValidText(items[i])) return NTK_SHARE_ERROR_INVALID_PARAMETER;
    }
    return NTK_SHARE_ERROR_NONE;
}

// Java values for a request; the arguments were checked already, so only a JNI failure stops it.
struct Java {
    JNIEnv* env;
    int32_t error = kErrorNone;

    jbyteArray Text(const char* text) {
        jbyteArray array = nullptr;
        if (error == kErrorNone) error = utf8::ToJavaOrNull(env, text, &array);
        return array;
    }

    jbyteArray Bytes(const uint8_t* data, size_t size) {
        if (error != kErrorNone) return nullptr;
        jbyteArray array = env->NewByteArray(static_cast<jsize>(size));
        if (array != nullptr) {
            env->SetByteArrayRegion(array, 0, static_cast<jsize>(size), reinterpret_cast<const jbyte*>(data));
        }
        Check(array, "NewByteArray");
        return array;
    }

    jobjectArray Arrays(size_t count) {
        if (error != kErrorNone) return nullptr;
        jclass byte_array = env->FindClass("[B");
        jobjectArray array =
            byte_array == nullptr ? nullptr : env->NewObjectArray(static_cast<jsize>(count), byte_array, nullptr);
        Check(array, "NewObjectArray");
        return array;
    }

    void Set(jobjectArray array, size_t index, jbyteArray item) {
        if (error != kErrorNone) return;
        env->SetObjectArrayElement(array, static_cast<jsize>(index), item);
        env->DeleteLocalRef(item);
        Check(array, "SetObjectArrayElement");
    }

    jobjectArray Texts(const char* const* items, size_t count) {
        jobjectArray array = Arrays(count);
        for (size_t i = 0; i < count && error == kErrorNone; ++i) Set(array, i, Text(items[i]));
        return array;
    }

    void Check(const void* made, const char* where) {
        jni::Failure failure = jni::TakeException(env, where);
        if (failure != jni::Failure::kNone || made == nullptr) {
            error = ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
        }
    }
};

// Accepts an opening of the Sharesheet: registered, then posted to the bridge (part 1, 5.7).
template <class Post>
ntk_share_error Open(JNIEnv* env, ntk_share_done_fn callback, void* user_data, ntk_release_fn release, Post&& post,
                     uint64_t* out_request_id) {
    NTK_LOGD("[Open] callback: %p, user_data: %p", reinterpret_cast<void*>(callback), user_data);
    return nativetoolkit::Accept(env, kKindOpen, reinterpret_cast<void*>(callback), user_data, release, nullptr,
                                 std::forward<Post>(post), out_request_id);
}

// A synchronous call that returns an ntk_share_error (Direct Share).
ntk_share_error Synchronous(JNIEnv* env, jint result, const char* where) {
    NTK_LOGD("[Synchronous] result: %d, where: %s", result, where);
    jni::Failure failure = jni::TakeException(env, where);
    return failure != jni::Failure::kNone ? ErrorOf(failure) : result;
}

template <class Callback>
ntk_share_error AddListener(int32_t kind, jmethodID add, const char* where, Callback callback, void* user_data,
                            ntk_release_fn release, ntk_share_listener** out_listener) {
    NTK_LOGD("[AddListener] kind: %d, where: %s, callback: %p, user_data: %p, out_listener: %p", kind, where,
             reinterpret_cast<void*>(callback), user_data, static_cast<void*>(out_listener));
    if (out_listener != nullptr) *out_listener = nullptr;
    if (callback == nullptr || out_listener == nullptr) {
        return Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = Enter(&env); error != kErrorNone) return Reject(release, user_data, error);
    jni::LocalFrame frame(env, 4);
    if (!frame.ok()) return Reject(release, user_data, kErrorOutOfMemory);
    uint64_t id = 0;
    int32_t error = nativetoolkit::Accept(env, kind, reinterpret_cast<void*>(callback), user_data, release, nullptr,
                                          [add](JNIEnv* e, jlong registration) {
                                              return e->CallStaticBooleanMethod(g_bridge, add, registration);
                                          },
                                          &id);
    if (error == kErrorNone) *out_listener = reinterpret_cast<ntk_share_listener*>(id);
    return error;
}

}  // namespace

classes::ClassSpec ClassSpec() {
    NTK_LOGD("[share::ClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/ShareBridge",
        &g_bridge,
        {
            // id, text, title, subject, mime type, preview title, preview thumbnail, action ids,
            // action labels, action icons
            {"shareText", "(J[B[B[B[B[B[B[[B[[B[[B)Z", &g_share_text},
            {"shareImage", "(J[B[B)Z", &g_share_image},
            {"shareImages", "(J[[B)Z", &g_share_images},
            {"shareFile", "(J[B)Z", &g_share_file},
            {"shareFiles", "(J[[B)Z", &g_share_files},
            // id, text, title, subject, mime type, preview title, preview thumbnail
            {"shareForSelection", "(J[B[B[B[B[B[B)Z", &g_share_for_selection},
            {"cancelSelection", "(J)Z", &g_cancel_selection},
            // id, label, category, icon
            {"registerDirectTarget", "([B[B[B[B)I", &g_register_direct_target},
            {"removeDirectTargets", "([[B)I", &g_remove_direct_targets},
            {"addChooserActionListener", "(J)Z", &g_add_chooser_listener},
            {"addSelectionListener", "(J)Z", &g_add_selection_listener},
        },
        {
            {"nativeDone", "(JI)V", reinterpret_cast<void*>(NativeDone)},
            {"nativeChooserAction", "(J[B)V", reinterpret_cast<void*>(NativeChooserAction)},
            {"nativeSelection", "(JJ[B)V", reinterpret_cast<void*>(NativeSelection)},
        },
    };
}

}  // namespace nativetoolkit::share

namespace share = nativetoolkit::share;
namespace jni = nativetoolkit::jni;
namespace registry = nativetoolkit::registry;
using nativetoolkit::kErrorNone;
using nativetoolkit::kErrorOutOfMemory;

// --- opening the Sharesheet (OP-43 to OP-47, OP-50) --------------------------------------------

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_text(const ntk_share_text_content* content,
                                                   const ntk_share_chooser_action* actions, size_t action_count,
                                                   ntk_share_done_fn callback, void* user_data,
                                                   ntk_release_fn release) {
    NTK_LOGD("[ntk_share_text] content: %p, actions: %p, action_count: %zu, callback: %p, user_data: %p",
             static_cast<const void*>(content), static_cast<const void*>(actions), action_count,
             reinterpret_cast<void*>(callback), user_data);
    if (callback == nullptr) return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    ntk_share_text_content c{};
    if (int32_t error = share::ReadContent(content, &c); error != kErrorNone) {
        return share::Reject(release, user_data, error);
    }
    if (int32_t error = share::CheckActions(actions, action_count); error != kErrorNone) {
        return share::Reject(release, user_data, error);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);  // the action arrays' items are deleted one by one
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jbyteArray text = java.Text(c.text);
    jbyteArray title = java.Text(c.title);
    jbyteArray subject = java.Text(c.subject);
    jbyteArray mime_type = java.Text(c.mime_type);
    jbyteArray preview_title = java.Text(c.preview_title);
    jbyteArray preview_thumbnail = java.Text(c.preview_thumbnail_path);
    jobjectArray ids = java.Arrays(action_count);
    jobjectArray labels = java.Arrays(action_count);
    jobjectArray icons = java.Arrays(action_count);
    for (size_t i = 0; i < action_count && java.error == kErrorNone; ++i) {
        java.Set(ids, i, java.Text(actions[i].id));
        java.Set(labels, i, java.Text(actions[i].label == nullptr ? "" : actions[i].label));
        java.Set(icons, i, java.Bytes(actions[i].icon, actions[i].icon_size));
    }
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_text, id, text, title,
                                                             subject, mime_type, preview_title, preview_thumbnail, ids,
                                                             labels, icons);
                       },
                       nullptr);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_image(const char* path, const char* mime_type,
                                                    ntk_share_done_fn callback, void* user_data,
                                                    ntk_release_fn release) {
    NTK_LOGD("[ntk_share_image] path: %p, mime_type: %p, callback: %p, user_data: %p", static_cast<const void*>(path),
             static_cast<const void*>(mime_type), reinterpret_cast<void*>(callback), user_data);
    if (callback == nullptr || path == nullptr || !share::ValidTexts({path, mime_type})) {
        return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jbyteArray path_bytes = java.Text(path);
    jbyteArray mime_bytes = java.Text(mime_type == nullptr ? "image/*" : mime_type);
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_image, id, path_bytes,
                                                             mime_bytes);
                       },
                       nullptr);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_images(const char* const* paths, size_t count,
                                                     ntk_share_done_fn callback, void* user_data,
                                                     ntk_release_fn release) {
    NTK_LOGD("[ntk_share_images] paths: %p, count: %zu, callback: %p, user_data: %p", static_cast<const void*>(paths),
             count, reinterpret_cast<void*>(callback), user_data);
    if (callback == nullptr) return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    if (int32_t error = share::CheckList(paths, count, NTK_SHARE_ERROR_EMPTY_FILE_LIST); error != kErrorNone) {
        return share::Reject(release, user_data, error);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);  // the items are deleted one by one
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jobjectArray array = java.Texts(paths, count);
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_images, id, array);
                       },
                       nullptr);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_file(const char* path, ntk_share_done_fn callback, void* user_data,
                                                   ntk_release_fn release) {
    NTK_LOGD("[ntk_share_file] path: %p, callback: %p, user_data: %p", static_cast<const void*>(path),
             reinterpret_cast<void*>(callback), user_data);
    if (callback == nullptr || path == nullptr || !share::ValidText(path)) {
        return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jbyteArray path_bytes = java.Text(path);
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_file, id, path_bytes);
                       },
                       nullptr);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_files(const char* const* paths, size_t count,
                                                    ntk_share_done_fn callback, void* user_data,
                                                    ntk_release_fn release) {
    NTK_LOGD("[ntk_share_files] paths: %p, count: %zu, callback: %p, user_data: %p", static_cast<const void*>(paths),
             count, reinterpret_cast<void*>(callback), user_data);
    if (callback == nullptr) return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    if (int32_t error = share::CheckList(paths, count, NTK_SHARE_ERROR_EMPTY_FILE_LIST); error != kErrorNone) {
        return share::Reject(release, user_data, error);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);  // the items are deleted one by one
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jobjectArray array = java.Texts(paths, count);
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_files, id, array);
                       },
                       nullptr);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_text_for_selection(const ntk_share_text_content* content,
                                                                 ntk_share_done_fn callback, void* user_data,
                                                                 ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_share_text_for_selection] content: %p, callback: %p, user_data: %p, out_request_id: %p",
             static_cast<const void*>(content), reinterpret_cast<void*>(callback), user_data,
             static_cast<void*>(out_request_id));
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return share::Reject(release, user_data, NTK_SHARE_ERROR_INVALID_PARAMETER);
    ntk_share_text_content c{};
    if (int32_t error = share::ReadContent(content, &c); error != kErrorNone) {
        return share::Reject(release, user_data, error);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return share::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return share::Reject(release, user_data, kErrorOutOfMemory);
    share::Java java{env};
    jbyteArray text = java.Text(c.text);
    jbyteArray title = java.Text(c.title);
    jbyteArray subject = java.Text(c.subject);
    jbyteArray mime_type = java.Text(c.mime_type);
    jbyteArray preview_title = java.Text(c.preview_title);
    jbyteArray preview_thumbnail = java.Text(c.preview_thumbnail_path);
    if (java.error != kErrorNone) return share::Reject(release, user_data, java.error);
    // The request ID is the registration ID (AP-17): the bridge pairs it with Kotlin's token.
    return share::Open(env, callback, user_data, release,
                       [&](JNIEnv* e, jlong id) {
                           return e->CallStaticBooleanMethod(share::g_bridge, share::g_share_for_selection, id, text,
                                                             title, subject, mime_type, preview_title,
                                                             preview_thumbnail);
                       },
                       out_request_id);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_cancel_selection(uint64_t request_id) {
    NTK_LOGD("[ntk_share_cancel_selection] request_id: %llu", static_cast<unsigned long long>(request_id));
    // Always posted to the main thread, where the bridge looks the token up (AP-17); before the
    // initialization no request can exist, so there is nothing to cancel.
    if (!nativetoolkit::runtime::IsReady()) return NTK_SHARE_ERROR_NONE;
    JNIEnv* env = jni::Env();
    if (env == nullptr) return NTK_SHARE_ERROR_UNKNOWN;
    jni::LocalFrame frame(env, 4);
    jboolean posted =
        env->CallStaticBooleanMethod(share::g_bridge, share::g_cancel_selection, static_cast<jlong>(request_id));
    if (jni::Failure failure = jni::TakeException(env, "ShareBridge.cancelSelection"); failure != jni::Failure::kNone) {
        return nativetoolkit::ErrorOf(failure);
    }
    return posted == JNI_TRUE ? NTK_SHARE_ERROR_NONE : NTK_SHARE_ERROR_UNKNOWN;
}

// --- Direct Share (OP-48, OP-49) ----------------------------------------------------------------

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_register_direct_target(const ntk_share_direct_target* target) {
    NTK_LOGD("[ntk_share_register_direct_target] target: %p", static_cast<const void*>(target));
    ntk_share_direct_target t{};
    if (int32_t error = nativetoolkit::structs::Read(target, &t, false); error != kErrorNone) return error;
    if (t.id == nullptr || t.label == nullptr || !share::ValidTexts({t.id, t.label, t.category})) {
        return NTK_SHARE_ERROR_INVALID_PARAMETER;
    }
    if (t.icon == nullptr || t.icon_size == 0) return NTK_SHARE_ERROR_INVALID_ICON;
    if (t.icon_size > static_cast<size_t>(INT32_MAX)) return NTK_SHARE_ERROR_INVALID_PARAMETER;
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return error;
    jni::LocalFrame frame(env, 8);
    if (!frame.ok()) return kErrorOutOfMemory;
    share::Java java{env};
    jbyteArray id = java.Text(t.id);
    jbyteArray label = java.Text(t.label);
    jbyteArray category = java.Text(t.category == nullptr ? "android.shortcut.conversation" : t.category);
    jbyteArray icon = java.Bytes(t.icon, t.icon_size);
    if (java.error != kErrorNone) return java.error;
    jint result = env->CallStaticIntMethod(share::g_bridge, share::g_register_direct_target, id, label, category, icon);
    return share::Synchronous(env, result, "ShareBridge.registerDirectTarget");
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_remove_direct_targets(const char* const* ids, size_t count) {
    NTK_LOGD("[ntk_share_remove_direct_targets] ids: %p, count: %zu", static_cast<const void*>(ids), count);
    if (int32_t error = share::CheckList(ids, count, NTK_SHARE_ERROR_EMPTY_ID_LIST); error != kErrorNone) return error;
    JNIEnv* env = nullptr;
    if (int32_t error = share::Enter(&env); error != kErrorNone) return error;
    jni::LocalFrame frame(env, 16);  // the items are deleted one by one
    if (!frame.ok()) return kErrorOutOfMemory;
    share::Java java{env};
    jobjectArray array = java.Texts(ids, count);
    if (java.error != kErrorNone) return java.error;
    jint result = env->CallStaticIntMethod(share::g_bridge, share::g_remove_direct_targets, array);
    return share::Synchronous(env, result, "ShareBridge.removeDirectTargets");
}

// --- events (OP-52 to OP-54) ---------------------------------------------------------------------

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_add_chooser_action_listener(ntk_share_chooser_action_fn callback,
                                                                        void* user_data, ntk_release_fn release,
                                                                        ntk_share_listener** out_listener) {
    NTK_LOGD("[ntk_share_add_chooser_action_listener] callback: %p, user_data: %p, out_listener: %p",
             reinterpret_cast<void*>(callback), user_data, static_cast<void*>(out_listener));
    return share::AddListener(share::kKindChooser, share::g_add_chooser_listener,
                              "ShareBridge.addChooserActionListener", callback, user_data, release, out_listener);
}

NTK_EXPORT ntk_share_error NTK_CALL ntk_share_add_selection_listener(ntk_share_selection_fn callback, void* user_data,
                                                                   ntk_release_fn release,
                                                                   ntk_share_listener** out_listener) {
    NTK_LOGD("[ntk_share_add_selection_listener] callback: %p, user_data: %p, out_listener: %p",
             reinterpret_cast<void*>(callback), user_data, static_cast<void*>(out_listener));
    return share::AddListener(share::kKindSelection, share::g_add_selection_listener,
                              "ShareBridge.addSelectionListener", callback, user_data, release, out_listener);
}

NTK_EXPORT void NTK_CALL ntk_share_listener_remove(ntk_share_listener* listener) {
    NTK_LOGD("[ntk_share_listener_remove] listener: %p", static_cast<void*>(listener));
    // Removes the registration only: the selection wait and the current actions stay (AP-11).
    if (listener != nullptr) registry::Cancel(reinterpret_cast<uint64_t>(listener), {share::kKindChooser, share::kKindSelection});
}
