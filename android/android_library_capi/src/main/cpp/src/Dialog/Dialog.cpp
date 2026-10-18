#include "Dialog/Dialog.h"

#include <climits>
#include <initializer_list>
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
#include "NativeToolkitC/Dialog.h"

// The answer handed to the callback (part 2, 6.2). The values may be user input: never logged.
struct ntk_dialog_result {
    ntk_dialog_answer answer = NTK_DIALOG_ANSWER_DISMISSED;
    ntk_dialog_button button = NTK_DIALOG_BUTTON_POSITIVE;
    std::optional<std::string> button_text;
    int32_t checked_index = -1;
    std::vector<int32_t> checked;
    std::optional<std::string> text;
    std::optional<std::string> username;
    std::optional<std::string> password;
};

namespace nativetoolkit::dialog {
namespace {

constexpr int32_t kKindRequest = 200;  // DialogBridge.KIND_REQUEST

jclass g_bridge = nullptr;
jmethodID g_show_alert = nullptr;
jmethodID g_show_confirm = nullptr;
jmethodID g_show_single_choice = nullptr;
jmethodID g_show_multi_choice = nullptr;
jmethodID g_show_text_input = nullptr;
jmethodID g_show_login = nullptr;
jmethodID g_cancel = nullptr;

void Call(registry::Registration& registration, ntk_dialog_error error, ntk_dialog_result* result) {
    NTK_LOGD("[Call] id: %llu, error: %d", static_cast<unsigned long long>(registration.id), error);
    reinterpret_cast<ntk_dialog_result_fn>(registration.callback)(registration.user_data, registration.id, error, 0,
                                                                 result);
}

// A request canceled through ntk_dialog_cancel (part 2, 11.1: CANCELED).
void CompleteCanceled(registry::Registration& registration) {
    NTK_LOGD("[CompleteCanceled] id: %llu", static_cast<unsigned long long>(registration.id));
    Call(registration, NTK_DIALOG_ERROR_CANCELED, nullptr);
}

// A text of the answer: none for null. Its error (OUT_OF_MEMORY, a JNI failure) when it cannot be
// read, so that the answer is not reported as complete without it (review K-X7).
int32_t ReadText(JNIEnv* env, jbyteArray bytes, std::optional<std::string>* out) {
    NTK_LOGD("[ReadText] env: %p, bytes: %p", env, bytes);
    std::string text;
    bool is_null = false;
    if (int32_t error = utf8::FromJava(env, bytes, &text, &is_null); error != kErrorNone) return error;
    if (is_null) {
        out->reset();
    } else {
        *out = std::move(text);
    }
    return kErrorNone;
}

// DialogBridge.nativeAnswered: a button press or a dismissal, on the main thread.
void JNICALL NativeAnswered(JNIEnv* env, jclass /*type*/, jlong id, jint answer, jint button, jbyteArray button_text,
                            jint checked_index, jbooleanArray checked, jbyteArray text, jbyteArray username,
                            jbyteArray password) {
    NTK_LOGD("[NativeAnswered] id: %lld, answer: %d, button: %d, checked_index: %d", static_cast<long long>(id), answer,
             button, checked_index);
    ntk_dialog_result* result = new (std::nothrow) ntk_dialog_result;
    ntk_dialog_error error = NTK_DIALOG_ERROR_NONE;
    if (result == nullptr) {
        error = NTK_DIALOG_ERROR_OUT_OF_MEMORY;
    } else {
        try {
            result->answer = answer;
            result->button = button;
            if (int32_t read = ReadText(env, button_text, &result->button_text); read != kErrorNone) error = read;
            result->checked_index = checked_index;
            if (checked != nullptr) {
                jsize count = env->GetArrayLength(checked);
                std::vector<jboolean> values(static_cast<size_t>(count));
                env->GetBooleanArrayRegion(checked, 0, count, values.data());
                for (jboolean value : values) result->checked.push_back(value == JNI_TRUE ? 1 : 0);
            }
            for (auto [bytes, field] : {std::pair{text, &result->text}, std::pair{username, &result->username},
                                        std::pair{password, &result->password}}) {
                if (error != NTK_DIALOG_ERROR_NONE) break;
                if (int32_t read = ReadText(env, bytes, field); read != kErrorNone) error = read;
            }
        } catch (const std::bad_alloc&) {
            delete result;
            result = nullptr;
            error = NTK_DIALOG_ERROR_OUT_OF_MEMORY;
        }
    }
    bool handed = false;
    registry::CompleteOnMain(static_cast<uint64_t>(id), [&](registry::Registration& registration) {
        handed = true;
        Call(registration, error, error == NTK_DIALOG_ERROR_NONE ? result : nullptr);
    });
    // The result belongs to the callback once handed over; otherwise (canceled meanwhile, or no
    // registration) nobody has it.
    if (!handed || error != NTK_DIALOG_ERROR_NONE) delete result;
}

// DialogBridge.nativeFailed: an error and no result, on the main thread.
void JNICALL NativeFailed(JNIEnv* /*env*/, jclass /*type*/, jlong id, jint error) {
    NTK_LOGD("[NativeFailed] id: %lld, error: %d", static_cast<long long>(id), error);
    registry::CompleteOnMain(static_cast<uint64_t>(id), [error](registry::Registration& registration) {
        Call(registration, error, nullptr);
    });
}

// A call rejected at the entry releases on the calling thread before it returns (part 1, 1.3).
ntk_dialog_error Reject(ntk_release_fn release, void* user_data, int32_t error) {
    NTK_LOGD("[Reject] error: %d", error);
    registry::ReleaseRejected(release, user_data);
    return error;
}

// A string of a request: NULL (the default) or strict UTF-8 within a Java array's length.
bool ValidText(const char* text) {
    NTK_LOGD("[ValidText] text: %p", text);
    size_t length = 0;
    return text == nullptr || (utf8::Length(text, &length) && utf8::IsStrict(std::string_view(text, length)));
}

bool ValidTexts(std::initializer_list<const char*> texts) {
    for (const char* text : texts) {
        if (!ValidText(text)) return false;
    }
    return true;
}

// The items of a choice dialog: at least one, none NULL, all strict UTF-8 (part 2, 6.2; Kotlin
// rejects an empty list the same way).
bool ValidItems(const char* const* items, size_t count) {
    NTK_LOGD("[ValidItems] count: %zu", count);
    if (items == nullptr || count == 0 || count > static_cast<size_t>(INT32_MAX)) return false;
    for (size_t i = 0; i < count; ++i) {
        if (items[i] == nullptr || !ValidText(items[i])) return false;
    }
    return true;
}

// The checks after the request is read: the initialization and a JNIEnv.
int32_t Enter(JNIEnv** env) {
    NTK_LOGD("[Enter]");
    if (!runtime::IsReady()) return NTK_DIALOG_ERROR_NOT_INITIALIZED;
    *env = jni::Env();
    return *env == nullptr ? NTK_DIALOG_ERROR_UNKNOWN : NTK_DIALOG_ERROR_NONE;
}

// Java byte arrays for the strings of a request; the strings were checked already, so only a JNI
// failure can stop it.
struct JavaTexts {
    JNIEnv* env;
    int32_t error = kErrorNone;
    jbyteArray Of(const char* text) {
        jbyteArray array = nullptr;
        if (error == kErrorNone) error = utf8::ToJavaOrNull(env, text, &array);
        return array;
    }
};

int32_t JavaItems(JNIEnv* env, const char* const* items, size_t count, jobjectArray* out) {
    NTK_LOGD("[JavaItems] env: %p, count: %zu", env, count);
    *out = nullptr;
    jclass byte_array = env->FindClass("[B");
    jobjectArray array =
        byte_array == nullptr ? nullptr : env->NewObjectArray(static_cast<jsize>(count), byte_array, nullptr);
    if (jni::Failure failure = jni::TakeException(env, "NewObjectArray"); failure != jni::Failure::kNone || array == nullptr) {
        return ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    for (size_t i = 0; i < count; ++i) {
        jbyteArray item = nullptr;
        if (int32_t error = utf8::ToJava(env, items[i], &item); error != kErrorNone) return error;
        env->SetObjectArrayElement(array, static_cast<jsize>(i), item);
        env->DeleteLocalRef(item);
        if (jni::Failure failure = jni::TakeException(env, "SetObjectArrayElement"); failure != jni::Failure::kNone) {
            return ErrorOf(failure);
        }
    }
    *out = array;
    return kErrorNone;
}

jboolean Flag(int32_t not_value) { return not_value != 0 ? JNI_FALSE : JNI_TRUE; }

}  // namespace

classes::ClassSpec ClassSpec() {
    NTK_LOGD("[dialog::ClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/DialogBridge",
        &g_bridge,
        {
            {"showAlert", "(J[B[B[BZZ)Z", &g_show_alert},
            {"showConfirm", "(J[B[B[B[BZZ)Z", &g_show_confirm},
            {"showSingleChoice", "(J[B[[BI[B[BZZ)Z", &g_show_single_choice},
            {"showMultiChoice", "(J[B[[B[Z[B[BZZ)Z", &g_show_multi_choice},
            {"showTextInput", "(J[B[B[B[B[BZZZ)Z", &g_show_text_input},
            {"showLogin", "(J[B[B[B[B[B[BZZZ)Z", &g_show_login},
            {"cancel", "(J)Z", &g_cancel},
        },
        {
            {"nativeAnswered", "(JII[BI[Z[B[B[B)V", reinterpret_cast<void*>(NativeAnswered)},
            {"nativeFailed", "(JI)V", reinterpret_cast<void*>(NativeFailed)},
        },
    };
}

}  // namespace nativetoolkit::dialog

namespace dialog = nativetoolkit::dialog;
namespace jni = nativetoolkit::jni;
namespace registry = nativetoolkit::registry;
namespace structs = nativetoolkit::structs;
using nativetoolkit::kErrorNone;
using nativetoolkit::kErrorOutOfMemory;

// --- the six dialogs (OP-13 to OP-18) --------------------------------------------------------

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_alert_async(const ntk_dialog_alert_request* request,
                                                              ntk_dialog_result_fn callback, void* user_data,
                                                              ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_alert_async] request: %p, callback: %p, user_data: %p", static_cast<const void*>(request),
             reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_alert_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    if (!dialog::ValidTexts({r.title, r.message, r.button_text})) {
        return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray message = texts.Of(r.message);
    jbyteArray button = texts.Of(r.button_text);
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(dialog::g_bridge, dialog::g_show_alert, id, title,
                                                                       message, button, dialog::Flag(r.not_cancelable),
                                                                       dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_confirm_async(const ntk_dialog_confirm_request* request,
                                                                ntk_dialog_result_fn callback, void* user_data,
                                                                ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_confirm_async] request: %p, callback: %p, user_data: %p",
             static_cast<const void*>(request), reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_confirm_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    if (!dialog::ValidTexts({r.title, r.message, r.negative_text, r.positive_text})) {
        return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray message = texts.Of(r.message);
    jbyteArray negative = texts.Of(r.negative_text);
    jbyteArray positive = texts.Of(r.positive_text);
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(dialog::g_bridge, dialog::g_show_confirm, id, title,
                                                                       message, negative, positive,
                                                                       dialog::Flag(r.not_cancelable),
                                                                       dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_single_choice_async(const ntk_dialog_single_choice_request* request,
                                                                      ntk_dialog_result_fn callback, void* user_data,
                                                                      ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_single_choice_async] request: %p, callback: %p, user_data: %p",
             static_cast<const void*>(request), reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_single_choice_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    // -1 is none checked; anything else must be an item (Kotlin checks the same).
    bool valid = r.reserved1 == 0 && dialog::ValidItems(r.items, r.item_count) &&
                 r.checked_index >= -1 && r.checked_index < static_cast<int64_t>(r.item_count) &&
                 dialog::ValidTexts({r.title, r.negative_text, r.positive_text});
    if (!valid) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray negative = texts.Of(r.negative_text);
    jbyteArray positive = texts.Of(r.positive_text);
    jobjectArray items = nullptr;
    if (texts.error == kErrorNone) texts.error = dialog::JavaItems(env, r.items, r.item_count, &items);
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(dialog::g_bridge, dialog::g_show_single_choice, id,
                                                                       title, items, static_cast<jint>(r.checked_index),
                                                                       negative, positive, dialog::Flag(r.not_cancelable),
                                                                       dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_multi_choice_async(const ntk_dialog_multi_choice_request* request,
                                                                     ntk_dialog_result_fn callback, void* user_data,
                                                                     ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_multi_choice_async] request: %p, callback: %p, user_data: %p",
             static_cast<const void*>(request), reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_multi_choice_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    if (!dialog::ValidItems(r.items, r.item_count) || !dialog::ValidTexts({r.title, r.negative_text, r.positive_text})) {
        return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray negative = texts.Of(r.negative_text);
    jbyteArray positive = texts.Of(r.positive_text);
    jobjectArray items = nullptr;
    if (texts.error == kErrorNone) texts.error = dialog::JavaItems(env, r.items, r.item_count, &items);
    jbooleanArray checked = nullptr;
    if (texts.error == kErrorNone) {
        // NULL is none checked; otherwise item_count values, nonzero for checked. Set one by one:
        // no C++ buffer, so no bad_alloc can leave this C entry (part 1, 1.1).
        checked = env->NewBooleanArray(static_cast<jsize>(r.item_count));
        if (jni::Failure failure = jni::TakeException(env, "NewBooleanArray"); failure != jni::Failure::kNone || checked == nullptr) {
            texts.error = nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
        } else {
            for (size_t i = 0; r.checked != nullptr && i < r.item_count; ++i) {
                if (r.checked[i] == 0) continue;
                const jboolean on = JNI_TRUE;
                env->SetBooleanArrayRegion(checked, static_cast<jsize>(i), 1, &on);
            }
        }
    }
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(dialog::g_bridge, dialog::g_show_multi_choice, id,
                                                                       title, items, checked, negative, positive,
                                                                       dialog::Flag(r.not_cancelable),
                                                                       dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_text_input_async(const ntk_dialog_text_input_request* request,
                                                                   ntk_dialog_result_fn callback, void* user_data,
                                                                   ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_text_input_async] request: %p, callback: %p, user_data: %p",
             static_cast<const void*>(request), reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_text_input_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    if (r.reserved1 != 0 || !dialog::ValidTexts({r.title, r.message, r.hint, r.negative_text, r.positive_text})) {
        return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray message = texts.Of(r.message);
    jbyteArray hint = texts.Of(r.hint);
    jbyteArray negative = texts.Of(r.negative_text);
    jbyteArray positive = texts.Of(r.positive_text);
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(
                                         dialog::g_bridge, dialog::g_show_text_input, id, title, message, hint, negative,
                                         positive, r.enable_positive_when_empty != 0 ? JNI_TRUE : JNI_FALSE,
                                         dialog::Flag(r.not_cancelable), dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_show_login_async(const ntk_dialog_login_request* request,
                                                              ntk_dialog_result_fn callback, void* user_data,
                                                              ntk_release_fn release, uint64_t* out_request_id) {
    NTK_LOGD("[ntk_dialog_show_login_async] request: %p, callback: %p, user_data: %p", static_cast<const void*>(request),
             reinterpret_cast<void*>(callback), user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    if (callback == nullptr) return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    ntk_dialog_login_request r{};
    if (int32_t error = structs::Read(request, &r, false); error != kErrorNone) return dialog::Reject(release, user_data, error);
    if (r.reserved1 != 0 || !dialog::ValidTexts({r.title, r.message, r.username_hint, r.password_hint, r.negative_text,
                                                 r.positive_text})) {
        return dialog::Reject(release, user_data, NTK_DIALOG_ERROR_INVALID_PARAMETER);
    }
    JNIEnv* env = nullptr;
    if (int32_t error = dialog::Enter(&env); error != kErrorNone) return dialog::Reject(release, user_data, error);
    jni::LocalFrame frame(env, 16);
    if (!frame.ok()) return dialog::Reject(release, user_data, kErrorOutOfMemory);
    dialog::JavaTexts texts{env};
    jbyteArray title = texts.Of(r.title);
    jbyteArray message = texts.Of(r.message);
    jbyteArray username_hint = texts.Of(r.username_hint);
    jbyteArray password_hint = texts.Of(r.password_hint);
    jbyteArray negative = texts.Of(r.negative_text);
    jbyteArray positive = texts.Of(r.positive_text);
    if (texts.error != kErrorNone) return dialog::Reject(release, user_data, texts.error);
    return nativetoolkit::Accept(env, dialog::kKindRequest, reinterpret_cast<void*>(callback), user_data, release,
                                 dialog::CompleteCanceled,
                                 [&](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(
                                         dialog::g_bridge, dialog::g_show_login, id, title, message, username_hint,
                                         password_hint, negative, positive,
                                         r.enable_positive_when_empty != 0 ? JNI_TRUE : JNI_FALSE,
                                         dialog::Flag(r.not_cancelable), dialog::Flag(r.not_cancelable_on_touch_outside));
                                 },
                                 out_request_id);
}

// --- cancel (OP-19) ---------------------------------------------------------------------------

NTK_EXPORT ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id) {
    NTK_LOGD("[ntk_dialog_cancel] request_id: %llu", static_cast<unsigned long long>(request_id));
    // CANCEL_REQUESTED and the removal (CANCELED, release) as for any registration; then the
    // Kotlin dialog is closed. Unknown and finished ids do nothing.
    if (!registry::Cancel(request_id, {dialog::kKindRequest})) return NTK_DIALOG_ERROR_NONE;
    JNIEnv* env = jni::Env();
    if (env == nullptr) return NTK_DIALOG_ERROR_NONE;
    jni::LocalFrame frame(env, 4);
    env->CallStaticBooleanMethod(dialog::g_bridge, dialog::g_cancel, static_cast<jlong>(request_id));
    jni::TakeException(env, "DialogBridge.cancel");
    return NTK_DIALOG_ERROR_NONE;
}

// --- readers (the result) ---------------------------------------------------------------------

static const char* OptionalText(const std::optional<std::string>& value, size_t* out_size) {
    if (out_size != nullptr) *out_size = value ? value->size() : 0;
    return value ? value->c_str() : nullptr;
}

NTK_EXPORT ntk_dialog_answer NTK_CALL ntk_dialog_result_answer(const ntk_dialog_result* result) {
    NTK_LOGD("[ntk_dialog_result_answer] result: %p", static_cast<const void*>(result));
    return result == nullptr ? NTK_DIALOG_ANSWER_DISMISSED : result->answer;
}

NTK_EXPORT ntk_dialog_button NTK_CALL ntk_dialog_result_button(const ntk_dialog_result* result) {
    NTK_LOGD("[ntk_dialog_result_button] result: %p", static_cast<const void*>(result));
    return result == nullptr ? NTK_DIALOG_BUTTON_POSITIVE : result->button;
}

NTK_EXPORT const char* NTK_CALL ntk_dialog_result_button_text(const ntk_dialog_result* result, size_t* out_size) {
    NTK_LOGD("[ntk_dialog_result_button_text] result: %p", static_cast<const void*>(result));
    // Points into the result itself, never a copy: the pointer must live until the result is freed.
    if (result == nullptr) return OptionalText(std::nullopt, out_size);
    return OptionalText(result->button_text, out_size);
}

NTK_EXPORT int32_t NTK_CALL ntk_dialog_result_checked_index(const ntk_dialog_result* result) {
    NTK_LOGD("[ntk_dialog_result_checked_index] result: %p", static_cast<const void*>(result));
    return result == nullptr ? -1 : result->checked_index;
}

NTK_EXPORT size_t NTK_CALL ntk_dialog_result_checked_count(const ntk_dialog_result* result) {
    NTK_LOGD("[ntk_dialog_result_checked_count] result: %p", static_cast<const void*>(result));
    return result == nullptr ? 0 : result->checked.size();
}

NTK_EXPORT int32_t NTK_CALL ntk_dialog_result_checked_at(const ntk_dialog_result* result, size_t index) {
    NTK_LOGD("[ntk_dialog_result_checked_at] result: %p, index: %zu", static_cast<const void*>(result), index);
    return result == nullptr || index >= result->checked.size() ? 0 : result->checked[index];
}

NTK_EXPORT const char* NTK_CALL ntk_dialog_result_text(const ntk_dialog_result* result, size_t* out_size) {
    NTK_LOGD("[ntk_dialog_result_text] result: %p", static_cast<const void*>(result));
    // Points into the result itself, never a copy: the pointer must live until the result is freed.
    if (result == nullptr) return OptionalText(std::nullopt, out_size);
    return OptionalText(result->text, out_size);
}

NTK_EXPORT const char* NTK_CALL ntk_dialog_result_username(const ntk_dialog_result* result, size_t* out_size) {
    NTK_LOGD("[ntk_dialog_result_username] result: %p", static_cast<const void*>(result));
    // Points into the result itself, never a copy: the pointer must live until the result is freed.
    if (result == nullptr) return OptionalText(std::nullopt, out_size);
    return OptionalText(result->username, out_size);
}

NTK_EXPORT const char* NTK_CALL ntk_dialog_result_password(const ntk_dialog_result* result, size_t* out_size) {
    NTK_LOGD("[ntk_dialog_result_password] result: %p", static_cast<const void*>(result));
    // Points into the result itself, never a copy: the pointer must live until the result is freed.
    if (result == nullptr) return OptionalText(std::nullopt, out_size);
    return OptionalText(result->password, out_size);
}

NTK_EXPORT void NTK_CALL ntk_dialog_result_free(ntk_dialog_result* result) {
    NTK_LOGD("[ntk_dialog_result_free] result: %p", static_cast<void*>(result));
    delete result;
}
