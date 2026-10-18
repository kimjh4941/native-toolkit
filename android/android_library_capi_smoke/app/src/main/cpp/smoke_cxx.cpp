// With an STL, the app's own C++ next to libntk.so (stage 1a 3.3): its libc++ is the app's, and
// libntk.so's is hidden inside it, so the two never meet.
#include <jni.h>

#include <string>

extern "C" JNIEXPORT jint JNICALL Java_com_jonghyunkim_nativetoolkit_smoke_Smoke_cxxLength(JNIEnv*, jclass) {
    std::string text = "ntk smoke";
    text += " with the app's own libc++";
    return static_cast<jint>(text.size());
}
