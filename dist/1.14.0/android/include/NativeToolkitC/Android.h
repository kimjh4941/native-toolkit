/**
 * @file Android.h
 * @brief Initializing the C ABI on Android: ntk_android_init for apps that disable androidx.startup
 *        or load libntk.so with dlopen only, and ntk_android_is_initialized.
 *
 * Rules for the whole C ABI (C ABI design part 1, chapter 1): every function may be called from any
 * thread and never waits for the main thread; completions, events and accepted releases arrive on
 * the main thread; strings are NUL-terminated UTF-8; this header is C99, includes only <stddef.h>
 * and <stdint.h>, and is ASCII only. The declarations are those of Appendix A of the C ABI design
 * part 2, which scripts/check_c_abi_contract_android.py compares with this file.
 */
#ifndef NATIVETOOLKITC_ANDROID_H
#define NATIVETOOLKITC_ANDROID_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_android_error;
enum {
    NTK_ANDROID_ERROR_NONE = 0,
    NTK_ANDROID_ERROR_INVALID_PARAMETER = 1,
    NTK_ANDROID_ERROR_CLASS_NOT_FOUND = 2,
    NTK_ANDROID_ERROR_JNI_FAILURE = 3,
    NTK_ANDROID_ERROR_IN_PROGRESS = 4
};

/** env: JNIEnv* of the calling thread. context: any Context (jobject). Never waits. */
ntk_android_error NTK_CALL ntk_android_init(void* env, void* context);
/** Nonzero once both the native tables and the Kotlin side are ready. */
int32_t           NTK_CALL ntk_android_is_initialized(void);

#ifdef __cplusplus
}
#endif
#endif
