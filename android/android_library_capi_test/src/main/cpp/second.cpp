// Depends on libntk.so and defines no JNI_OnLoad (design part 1, chapter 6).
#include <NativeToolkitC/Common.h>

extern "C" __attribute__((visibility("default"))) uint32_t second_version(void) {
    return ntk_version();
}
