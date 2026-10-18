#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#define NTK_API __attribute__((visibility("default")))
/* 1 when JNI_OnLoad has run (libntk.so loaded through System.loadLibrary). */
NTK_API int ntk_spike_onload_called(void);
/* Number of VMs from JNI_GetCreatedJavaVMs, or -1; *same is 1 when it equals the JNI_OnLoad VM. */
NTK_API int ntk_spike_created_vms(int* same);
/* Calls NtkNative.onNativeCallback(value) from the calling thread, attaching it if needed. */
NTK_API int ntk_spike_call_kotlin(int value);
/* Same, from a new native thread; returns after the thread finished. */
NTK_API int ntk_spike_call_kotlin_from_new_thread(int value);
/* Uses libc++ (std::string, std::vector) so that c++_static is linked in. */
NTK_API int ntk_spike_cxx_check(void);
#ifdef __cplusplus
}
#endif
