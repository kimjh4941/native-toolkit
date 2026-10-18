/* The probe operation and event of debug builds of libntk.so (android_library_capi
   src/main/cpp/src/Debug/Probe.h). Not part of the C ABI. */
#ifndef NTK_TEST_DEBUG_PROBE_H
#define NTK_TEST_DEBUG_PROBE_H

#include <stddef.h>
#include <stdint.h>

#include <NativeToolkitC/Common.h>

#ifdef __cplusplus
extern "C" {
#endif

/* error: 0 on completion with value, 6 when canceled. Called on the main thread. */
typedef void (*ntk_debug_probe_done_fn)(void* user_data, int32_t error, int64_t value);
typedef void (*ntk_debug_probe_event_fn)(void* user_data, int64_t value);

int32_t ntk_debug_probe_start(ntk_debug_probe_done_fn callback, void* user_data, ntk_release_fn release,
                              uint64_t* out_id);
int32_t ntk_debug_probe_finish(uint64_t id, int64_t value);
int32_t ntk_debug_probe_cancel(uint64_t id);
int32_t ntk_debug_probe_add_listener(ntk_debug_probe_event_fn callback, void* user_data, ntk_release_fn release,
                                     uint64_t* out_handle);
void ntk_debug_probe_listener_remove(uint64_t handle);
int32_t ntk_debug_probe_emit(int64_t value);
void ntk_debug_probe_fail_next_post(void);
/* The next removal a cancel posts to the main thread fails; the main thread runs it later. */
void ntk_debug_probe_fail_next_remove_post(void);
size_t ntk_debug_probe_registrations(void);
/* Runs hook in JNI_OnLoad and ntk_android_init between building the class table and marking the
   native side done (NULL removes it). */
void ntk_debug_runtime_before_native_done(void (*hook)(void));

#ifdef __cplusplus
}
#endif
#endif
