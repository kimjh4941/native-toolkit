/* The smoke app's use of the C ABI, in C (C ABI design part 1, chapter 6; part 2, 12.4): what a
   consumer does first - initialize, show a notification, write and read the clipboard, show a
   dialog and get its answer, and start a progress notification. Called from Smoke.kt. */
#include <jni.h>
#include <pthread.h>
#include <string.h>
#include <time.h>

#include <android/log.h>

#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>

#define TAG "ntk-smoke"

JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_init(JNIEnv* env, jclass type, jobject context) {
    (void)type;
    return ntk_android_init(env, context);
}

JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_isInitialized(JNIEnv* env, jclass type) {
    (void)env;
    (void)type;
    return ntk_android_is_initialized();
}

static ntk_notification_content* Content(int32_t id, const char* title, int32_t progress) {
    ntk_notification_content* content = NULL;
    if (ntk_notification_content_create(id, title, "From the C ABI smoke", &content) != NTK_NOTIFICATION_ERROR_NONE) {
        return NULL;
    }
    if (progress) ntk_notification_content_set_progress(content, 100, 10, 0);
    return content;
}

JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_notify(JNIEnv* env, jclass type, jint id) {
    (void)env;
    (void)type;
    ntk_notification_content* content = Content(id, "NTK smoke", 0);
    if (content == NULL) return -1;
    ntk_notification_error error = ntk_notification_show(content);
    ntk_notification_content_free(content);
    return error;
}

/* 0 when the text read back is the one written, -1 when it differs, or the error. */
JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_clipboardRoundTrip(JNIEnv* env, jclass type,
                                                                                         jstring text) {
    (void)type;
    const char* chars = (*env)->GetStringUTFChars(env, text, NULL); /* ASCII: the same as UTF-8 */
    ntk_clipboard_error error = ntk_clipboard_copy_text(chars, NULL);
    jint result = error;
    if (error == NTK_CLIPBOARD_ERROR_NONE) {
        ntk_clipboard_content* content = NULL;
        error = ntk_clipboard_read(&content);
        size_t size = 0;
        const char* read = content == NULL ? NULL : ntk_clipboard_content_item_text_at(content, 0, &size);
        if (error != NTK_CLIPBOARD_ERROR_NONE) {
            result = error;
        } else {
            result = read != NULL && size == strlen(chars) && memcmp(read, chars, size) == 0 ? 0 : -1;
        }
        ntk_clipboard_content_free(content);
    }
    (*env)->ReleaseStringUTFChars(env, text, chars);
    return result;
}

/* The alert's completion, handed from the main thread to the thread that waits for it. */
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_answered = PTHREAD_COND_INITIALIZER;
static int g_done = 0;
static int g_error = -1;
static int g_answer = -1;

static void NTK_CALL OnAlert(void* user_data, uint64_t request_id, ntk_dialog_error error, uint32_t system_code,
                             ntk_dialog_result* result) {
    (void)user_data;
    (void)request_id;
    (void)system_code;
    pthread_mutex_lock(&g_mutex);
    g_error = error;
    g_answer = result == NULL ? -1 : ntk_dialog_result_answer(result);
    g_done = 1;
    pthread_cond_broadcast(&g_answered);
    pthread_mutex_unlock(&g_mutex);
    ntk_dialog_result_free(result);
}

JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_showAlert(JNIEnv* env, jclass type) {
    (void)env;
    (void)type;
    pthread_mutex_lock(&g_mutex);
    g_done = 0;
    pthread_mutex_unlock(&g_mutex);
    ntk_dialog_alert_request request;
    memset(&request, 0, sizeof(request));
    request.struct_size = sizeof(request);
    request.title = "NTK smoke";
    request.message = "Press OK";
    return ntk_dialog_show_alert_async(&request, OnAlert, NULL, NULL, NULL);
}

/* [error, answer] of the alert, or [-1, -1] after timeout_ms. */
JNIEXPORT jintArray JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_awaitAlert(JNIEnv* env, jclass type,
                                                                                    jint timeout_ms) {
    (void)type;
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_sec += timeout_ms / 1000;
    jint values[2] = {-1, -1};
    pthread_mutex_lock(&g_mutex);
    while (!g_done) {
        if (pthread_cond_timedwait(&g_answered, &g_mutex, &until) != 0) break;
    }
    if (g_done) {
        values[0] = g_error;
        values[1] = g_answer;
    }
    pthread_mutex_unlock(&g_mutex);
    jintArray result = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, result, 0, 2, values);
    return result;
}

/* A progress notification, whose foreground service Android refuses to start from the back
   (SERVICE_START_NOT_ALLOWED, part 2, 11.2; checked outside instrumentation, which is exempt). */
JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_startProgress(JNIEnv* env, jclass type) {
    (void)env;
    (void)type;
    ntk_notification_content* content = Content(77, "NTK smoke progress", 1);
    if (content == NULL) return -1;
    ntk_notification_error error = ntk_notification_start_progress(content);
    ntk_notification_content_free(content);
    __android_log_print(ANDROID_LOG_INFO, TAG, "start_progress: %d", error);
    return error;
}

JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_stopProgress(JNIEnv* env, jclass type) {
    (void)env;
    (void)type;
    return ntk_notification_stop_progress();
}
