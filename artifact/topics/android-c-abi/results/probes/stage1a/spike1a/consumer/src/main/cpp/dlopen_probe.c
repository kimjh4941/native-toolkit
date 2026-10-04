/* Opens libntk.so with dlopen only (as dart:ffi does), without System.loadLibrary. */
#include <dlfcn.h>
#include <jni.h>
#include <stdio.h>

JNIEXPORT jstring JNICALL
Java_com_example_ntkconsumer_MainActivity_runDlopenChecks(JNIEnv* env, jclass clazz) {
    char buf[256];
    void* h = dlopen("libntk.so", RTLD_NOW);
    if (h == NULL) {
        snprintf(buf, sizeof buf, "dlopen failed: %s", dlerror());
        return (*env)->NewStringUTF(env, buf);
    }
    int (*onload)(void) = (int (*)(void))dlsym(h, "ntk_spike_onload_called");
    int (*vms)(int*) = (int (*)(int*))dlsym(h, "ntk_spike_created_vms");
    int (*call)(int) = (int (*)(int))dlsym(h, "ntk_spike_call_kotlin");
    int same = -1;
    int n = vms(&same);
    snprintf(buf, sizeof buf, "dlopen onload=%d created_vms=%d same_vm=%d call_kotlin=%d",
             onload(), n, same, call(43));
    return (*env)->NewStringUTF(env, buf);
}
