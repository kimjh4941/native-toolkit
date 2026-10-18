// Logging to logcat under the tag ntk (C ABI design part 1, 5.12). Secrets - clipboard text,
// dialog input, share text, notification data values - are never logged: log their length.
#pragma once

#include <android/log.h>

#define NTK_LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "ntk", __VA_ARGS__)
#define NTK_LOGW(...) __android_log_print(ANDROID_LOG_WARN, "ntk", __VA_ARGS__)
#define NTK_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "ntk", __VA_ARGS__)
