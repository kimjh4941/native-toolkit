/* A C consumer that uses only the Prefab header and libntk.so. */
#include <jni.h>
#include <stdio.h>
#include <NativeToolkitC/Spike.h>

int consumer_cxx_check(void);

JNIEXPORT jstring JNICALL
Java_com_example_ntkconsumer_MainActivity_runChecks(JNIEnv* env, jclass clazz) {
    int same = -1;
    int vms = ntk_spike_created_vms(&same);
    char buf[512];
    snprintf(buf, sizeof buf,
             "onload=%d created_vms=%d same_vm=%d call_kotlin=%d call_kotlin_new_thread=%d cxx=%d consumer_cxx=%d",
             ntk_spike_onload_called(), vms, same, ntk_spike_call_kotlin(41),
             ntk_spike_call_kotlin_from_new_thread(42), ntk_spike_cxx_check(), consumer_cxx_check());
    return (*env)->NewStringUTF(env, buf);
}
