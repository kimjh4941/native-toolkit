#include "Notification/Notification.h"

#include <string_view>
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
#include "Notification/Builders.h"
#include "Notification/Encoder.h"

namespace nativetoolkit::notification {
namespace {

constexpr int32_t kKindPermission = 300;  // NotificationBridge.KIND_PERMISSION
constexpr int32_t kKindSettings = 301;    // NotificationBridge.KIND_SETTINGS

jclass g_bridge = nullptr;
jmethodID g_show = nullptr;
jmethodID g_update = nullptr;
jmethodID g_remove = nullptr;
jmethodID g_remove_all = nullptr;
jmethodID g_create_channel = nullptr;
jmethodID g_delete_channel = nullptr;
jmethodID g_schedule = nullptr;
jmethodID g_cancel_scheduled = nullptr;
jmethodID g_cancel_all_scheduled = nullptr;
jmethodID g_start_progress = nullptr;
jmethodID g_update_progress = nullptr;
jmethodID g_complete_progress = nullptr;
jmethodID g_stop_progress = nullptr;
jmethodID g_has_permission = nullptr;
jmethodID g_are_enabled = nullptr;
jmethodID g_is_scheduled = nullptr;
jmethodID g_can_schedule_exact = nullptr;
jmethodID g_open_settings = nullptr;
jmethodID g_request_permission = nullptr;
jmethodID g_cancel_permission = nullptr;

// --- completions (main thread) ---

void PermissionCanceled(registry::Registration& registration) {
    NTK_LOGD("[PermissionCanceled] id: %llu", static_cast<unsigned long long>(registration.id));
    reinterpret_cast<ntk_notification_permission_fn>(registration.callback)(
        registration.user_data, registration.id, NTK_NOTIFICATION_ERROR_CANCELED, 0,
        NTK_NOTIFICATION_PERMISSION_RESULT_DENIED);
}

void JNICALL NativePermissionDone(JNIEnv* /*env*/, jclass /*type*/, jlong id, jint error, jint result) {
    NTK_LOGD("[NativePermissionDone] id: %lld, error: %d, result: %d", static_cast<long long>(id), error, result);
    registry::CompleteOnMain(static_cast<uint64_t>(id), [error, result](registry::Registration& registration) {
        reinterpret_cast<ntk_notification_permission_fn>(registration.callback)(registration.user_data, registration.id,
                                                                               error, 0, result);
    });
}

void JNICALL NativeSettingsDone(JNIEnv* /*env*/, jclass /*type*/, jlong id, jint error, jint result) {
    NTK_LOGD("[NativeSettingsDone] id: %lld, error: %d, result: %d", static_cast<long long>(id), error, result);
    registry::CompleteOnMain(static_cast<uint64_t>(id), [error, result](registry::Registration& registration) {
        reinterpret_cast<ntk_notification_settings_fn>(registration.callback)(registration.user_data, error, 0, result);
    });
}

// --- the entry ---

ntk_notification_error Enter(JNIEnv** env) {
    NTK_LOGD("[Enter]");
    if (!runtime::IsReady()) return NTK_NOTIFICATION_ERROR_NOT_INITIALIZED;
    *env = jni::Env();
    return *env == nullptr ? NTK_NOTIFICATION_ERROR_UNKNOWN : NTK_NOTIFICATION_ERROR_NONE;
}

int32_t ToJava(JNIEnv* env, const std::vector<uint8_t>& bytes, jbyteArray* out) {
    NTK_LOGD("[ToJava] env: %p, size: %zu", env, bytes.size());
    *out = env->NewByteArray(static_cast<jsize>(bytes.size()));
    if (jni::Failure failure = jni::TakeException(env, "NewByteArray"); failure != jni::Failure::kNone || *out == nullptr) {
        return ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    env->SetByteArrayRegion(*out, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<const jbyte*>(bytes.data()));
    jni::Failure failure = jni::TakeException(env, "SetByteArrayRegion");
    return failure == jni::Failure::kNone ? kErrorNone : ErrorOf(failure);
}

// The content as bytes; a C++ allocation failure is OUT_OF_MEMORY.
int32_t ContentBytes(JNIEnv* env, const ntk_notification_content* content, jbyteArray* out) {
    NTK_LOGD("[ContentBytes] env: %p, content: %p", env, static_cast<const void*>(content));
    try {
        return ToJava(env, EncodeContent(*content), out);
    } catch (const std::bad_alloc&) {
        return kErrorOutOfMemory;
    }
}

ntk_notification_error Result(JNIEnv* env, jint result, const char* where) {
    NTK_LOGD("[Result] result: %d, where: %s", result, where);
    jni::Failure failure = jni::TakeException(env, where);
    return failure != jni::Failure::kNone ? ErrorOf(failure) : result;
}

// An optional tag: NULL is no tag; anything else strict UTF-8.
int32_t Tag(JNIEnv* env, const char* tag, jbyteArray* out) {
    NTK_LOGD("[Tag] env: %p, tag: %p", env, tag);
    return utf8::ToJavaOrNull(env, tag, out);
}

// The synchronous operations that take a content builder (OP-20, OP-21, OP-29 to OP-31).
ntk_notification_error WithContent(const ntk_notification_content* content, jmethodID method, const char* where) {
    NTK_LOGD("[WithContent] content: %p, where: %s", static_cast<const void*>(content), where);
    if (content == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    jbyteArray bytes = nullptr;
    if (int32_t error = ContentBytes(env, content, &bytes); error != kErrorNone) return error;
    return Result(env, env->CallStaticIntMethod(g_bridge, method, bytes), where);
}

ntk_notification_error NoArguments(jmethodID method, const char* where) {
    NTK_LOGD("[NoArguments] where: %s", where);
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    return Result(env, env->CallStaticIntMethod(g_bridge, method), where);
}

// The queries that write an int32_t (OP-33, OP-34, OP-36).
ntk_notification_error Query(jmethodID method, int32_t* out_value, const char* where) {
    NTK_LOGD("[Query] out_value: %p, where: %s", static_cast<void*>(out_value), where);
    if (out_value == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    *out_value = 0;
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbooleanArray box = env->NewBooleanArray(1);
    if (jni::Failure failure = jni::TakeException(env, "NewBooleanArray"); failure != jni::Failure::kNone || box == nullptr) {
        return ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    ntk_notification_error error = Result(env, env->CallStaticIntMethod(g_bridge, method, box), where);
    if (error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jboolean value = JNI_FALSE;
    env->GetBooleanArrayRegion(box, 0, 1, &value);
    *out_value = value == JNI_TRUE ? 1 : 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

}  // namespace

classes::ClassSpec ClassSpec() {
    NTK_LOGD("[notification::ClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/NotificationBridge",
        &g_bridge,
        {
            {"show", "([B)I", &g_show},
            {"update", "([B)I", &g_update},
            {"remove", "(I[B)I", &g_remove},
            {"removeAll", "()I", &g_remove_all},
            {"createChannel", "([B)I", &g_create_channel},
            {"deleteChannel", "([B)I", &g_delete_channel},
            {"schedule", "([BJZZZI)I", &g_schedule},
            {"cancelScheduled", "(I[B)I", &g_cancel_scheduled},
            {"cancelAllScheduled", "()I", &g_cancel_all_scheduled},
            {"startProgress", "([B)I", &g_start_progress},
            {"updateProgress", "([B)I", &g_update_progress},
            {"completeProgress", "([B)I", &g_complete_progress},
            {"stopProgress", "()I", &g_stop_progress},
            {"hasPermission", "([Z)I", &g_has_permission},
            {"areEnabled", "([Z)I", &g_are_enabled},
            {"isScheduled", "(I[B[Z)I", &g_is_scheduled},
            {"canScheduleExactAlarms", "([Z)I", &g_can_schedule_exact},
            {"openSettings", "(JI)Z", &g_open_settings},
            {"requestPermission", "(J)Z", &g_request_permission},
            {"cancelPermissionRequest", "(J)Z", &g_cancel_permission},
        },
        {
            {"nativePermissionDone", "(JII)V", reinterpret_cast<void*>(NativePermissionDone)},
            {"nativeSettingsDone", "(JII)V", reinterpret_cast<void*>(NativeSettingsDone)},
        },
    };
}

}  // namespace nativetoolkit::notification

namespace notification = nativetoolkit::notification;
namespace jni = nativetoolkit::jni;
namespace registry = nativetoolkit::registry;
using nativetoolkit::kErrorNone;

// --- show, update, remove (OP-20 to OP-23) ---------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_show(const ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_show] content: %p", static_cast<const void*>(content));
    return notification::WithContent(content, notification::g_show, "NotificationBridge.show");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_update(const ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_update] content: %p", static_cast<const void*>(content));
    return notification::WithContent(content, notification::g_update, "NotificationBridge.update");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_remove(int32_t id, const char* tag) {
    NTK_LOGD("[ntk_notification_remove] id: %d, tag: %p", id, tag);
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbyteArray java_tag = nullptr;
    if (int32_t error = notification::Tag(env, tag, &java_tag); error != kErrorNone) return error;
    return notification::Result(env, env->CallStaticIntMethod(notification::g_bridge, notification::g_remove, id, java_tag),
                                "NotificationBridge.remove");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_remove_all(void) {
    NTK_LOGD("[ntk_notification_remove_all]");
    return notification::NoArguments(notification::g_remove_all, "NotificationBridge.removeAll");
}

// --- channels (OP-24, OP-25) -----------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_create_channel(const ntk_notification_channel* channel) {
    NTK_LOGD("[ntk_notification_create_channel] channel: %p", static_cast<const void*>(channel));
    if (channel == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbyteArray bytes = nullptr;
    try {
        if (int32_t error = notification::ToJava(env, notification::EncodeChannel(channel->data), &bytes); error != kErrorNone) {
            return error;
        }
    } catch (const std::bad_alloc&) {
        return NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY;
    }
    return notification::Result(env, env->CallStaticIntMethod(notification::g_bridge, notification::g_create_channel, bytes),
                                "NotificationBridge.createChannel");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_delete_channel(const char* channel_id) {
    NTK_LOGD("[ntk_notification_delete_channel] channel_id: %p", channel_id);
    if (channel_id == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbyteArray id = nullptr;
    if (int32_t error = nativetoolkit::utf8::ToJava(env, channel_id, &id); error != kErrorNone) return error;
    return notification::Result(env, env->CallStaticIntMethod(notification::g_bridge, notification::g_delete_channel, id),
                                "NotificationBridge.deleteChannel");
}

// --- schedules (OP-26 to OP-28) --------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_schedule(const ntk_notification_content* content,
                                                                  const ntk_notification_schedule_options* schedule) {
    NTK_LOGD("[ntk_notification_schedule] content: %p, schedule: %p", static_cast<const void*>(content),
             static_cast<const void*>(schedule));
    if (content == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    ntk_notification_schedule_options read{};
    if (int32_t error = nativetoolkit::structs::Read(schedule, &read, false); error != kErrorNone) return error;
    // trigger_at_millis is Unix time, so alarm_type is RTC_WAKEUP (0) or RTC (1) only (AP-22).
    if (read.trigger_at_millis < 1 || (read.alarm_type != 0 && read.alarm_type != 1)) {
        return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    }
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 8);
    jbyteArray bytes = nullptr;
    if (int32_t error = notification::ContentBytes(env, content, &bytes); error != kErrorNone) return error;
    // The zero-filled struct is Kotlin's default: exact, while idle, across boot (E-9).
    jint result = env->CallStaticIntMethod(notification::g_bridge, notification::g_schedule, bytes,
                                           static_cast<jlong>(read.trigger_at_millis),
                                           read.inexact == 0 ? JNI_TRUE : JNI_FALSE,
                                           read.not_allow_while_idle == 0 ? JNI_TRUE : JNI_FALSE,
                                           read.not_persist_across_boot == 0 ? JNI_TRUE : JNI_FALSE,
                                           static_cast<jint>(read.alarm_type));
    return notification::Result(env, result, "NotificationBridge.schedule");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(int32_t id, const char* tag) {
    NTK_LOGD("[ntk_notification_cancel_scheduled] id: %d, tag: %p", id, tag);
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbyteArray java_tag = nullptr;
    if (int32_t error = notification::Tag(env, tag, &java_tag); error != kErrorNone) return error;
    return notification::Result(
        env, env->CallStaticIntMethod(notification::g_bridge, notification::g_cancel_scheduled, id, java_tag),
        "NotificationBridge.cancelScheduled");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_cancel_all_scheduled(void) {
    NTK_LOGD("[ntk_notification_cancel_all_scheduled]");
    return notification::NoArguments(notification::g_cancel_all_scheduled, "NotificationBridge.cancelAllScheduled");
}

// --- progress (OP-29 to OP-32) ---------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_start_progress(const ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_start_progress] content: %p", static_cast<const void*>(content));
    return notification::WithContent(content, notification::g_start_progress, "NotificationBridge.startProgress");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_update_progress(const ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_update_progress] content: %p", static_cast<const void*>(content));
    return notification::WithContent(content, notification::g_update_progress, "NotificationBridge.updateProgress");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_complete_progress(const ntk_notification_content* content) {
    NTK_LOGD("[ntk_notification_complete_progress] content: %p", static_cast<const void*>(content));
    return notification::WithContent(content, notification::g_complete_progress, "NotificationBridge.completeProgress");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_stop_progress(void) {
    NTK_LOGD("[ntk_notification_stop_progress]");
    return notification::NoArguments(notification::g_stop_progress, "NotificationBridge.stopProgress");
}

// --- queries (OP-33 to OP-36) ----------------------------------------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_has_permission(int32_t* out_value) {
    NTK_LOGD("[ntk_notification_has_permission] out_value: %p", static_cast<void*>(out_value));
    return notification::Query(notification::g_has_permission, out_value, "NotificationBridge.hasPermission");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_are_enabled(int32_t* out_value) {
    NTK_LOGD("[ntk_notification_are_enabled] out_value: %p", static_cast<void*>(out_value));
    return notification::Query(notification::g_are_enabled, out_value, "NotificationBridge.areEnabled");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_can_schedule_exact_alarms(int32_t* out_value) {
    NTK_LOGD("[ntk_notification_can_schedule_exact_alarms] out_value: %p", static_cast<void*>(out_value));
    return notification::Query(notification::g_can_schedule_exact, out_value, "NotificationBridge.canScheduleExactAlarms");
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_is_scheduled(int32_t id, const char* tag, int32_t* out_value) {
    NTK_LOGD("[ntk_notification_is_scheduled] id: %d, tag: %p, out_value: %p", id, tag, static_cast<void*>(out_value));
    if (out_value == nullptr) return NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    *out_value = 0;
    JNIEnv* env = nullptr;
    if (ntk_notification_error error = notification::Enter(&env); error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jni::LocalFrame frame(env, 4);
    jbyteArray java_tag = nullptr;
    if (int32_t error = notification::Tag(env, tag, &java_tag); error != kErrorNone) return error;
    jbooleanArray box = env->NewBooleanArray(1);
    if (jni::Failure failure = jni::TakeException(env, "NewBooleanArray"); failure != jni::Failure::kNone || box == nullptr) {
        return nativetoolkit::ErrorOf(failure == jni::Failure::kNone ? jni::Failure::kOutOfMemory : failure);
    }
    ntk_notification_error error = notification::Result(
        env, env->CallStaticIntMethod(notification::g_bridge, notification::g_is_scheduled, id, java_tag, box),
        "NotificationBridge.isScheduled");
    if (error != NTK_NOTIFICATION_ERROR_NONE) return error;
    jboolean value = JNI_FALSE;
    env->GetBooleanArrayRegion(box, 0, 1, &value);
    *out_value = value == JNI_TRUE ? 1 : 0;
    return NTK_NOTIFICATION_ERROR_NONE;
}

// --- the settings screen and the permission (OP-37 to OP-39) ---------------------------------

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_open_settings_async(ntk_notification_settings_target target,
                                                                             ntk_notification_settings_fn callback,
                                                                             void* user_data, ntk_release_fn release) {
    NTK_LOGD("[ntk_notification_open_settings_async] target: %d, callback: %p, user_data: %p", target,
             reinterpret_cast<void*>(callback), user_data);
    ntk_notification_error error = NTK_NOTIFICATION_ERROR_NONE;
    JNIEnv* env = nullptr;
    if (callback == nullptr || target < NTK_NOTIFICATION_SETTINGS_TARGET_NOTIFICATIONS ||
        target > NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM) {
        error = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    } else {
        error = notification::Enter(&env);
    }
    if (error != NTK_NOTIFICATION_ERROR_NONE) {
        registry::ReleaseRejected(release, user_data);
        return error;
    }
    jni::LocalFrame frame(env, 4);
    return nativetoolkit::Accept(env, notification::kKindSettings, reinterpret_cast<void*>(callback), user_data, release,
                                 nullptr,
                                 [target](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(notification::g_bridge, notification::g_open_settings,
                                                                       id, static_cast<jint>(target));
                                 },
                                 nullptr);
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_request_permission(ntk_notification_permission_fn callback,
                                                                            void* user_data, ntk_release_fn release,
                                                                            uint64_t* out_request_id) {
    NTK_LOGD("[ntk_notification_request_permission] callback: %p, user_data: %p", reinterpret_cast<void*>(callback),
             user_data);
    if (out_request_id != nullptr) *out_request_id = 0;
    ntk_notification_error error = NTK_NOTIFICATION_ERROR_NONE;
    JNIEnv* env = nullptr;
    if (callback == nullptr) {
        error = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
    } else {
        error = notification::Enter(&env);
    }
    if (error != NTK_NOTIFICATION_ERROR_NONE) {
        registry::ReleaseRejected(release, user_data);
        return error;
    }
    jni::LocalFrame frame(env, 4);
    return nativetoolkit::Accept(env, notification::kKindPermission, reinterpret_cast<void*>(callback), user_data, release,
                                 notification::PermissionCanceled,
                                 [](JNIEnv* e, jlong id) {
                                     return e->CallStaticBooleanMethod(notification::g_bridge,
                                                                       notification::g_request_permission, id);
                                 },
                                 out_request_id);
}

NTK_EXPORT ntk_notification_error NTK_CALL ntk_notification_cancel_permission_request(uint64_t request_id) {
    NTK_LOGD("[ntk_notification_cancel_permission_request] request_id: %llu", static_cast<unsigned long long>(request_id));
    // As ntk_dialog_cancel: the removal completes it CANCELED, then the Kotlin request is canceled.
    if (!registry::Cancel(request_id)) return NTK_NOTIFICATION_ERROR_NONE;
    JNIEnv* env = jni::Env();
    if (env == nullptr) return NTK_NOTIFICATION_ERROR_NONE;
    jni::LocalFrame frame(env, 4);
    env->CallStaticBooleanMethod(notification::g_bridge, notification::g_cancel_permission, static_cast<jlong>(request_id));
    jni::TakeException(env, "NotificationBridge.cancelPermissionRequest");
    return NTK_NOTIFICATION_ERROR_NONE;
}
