/*
 * CT-01 of the stage 5 design: the C ABI's public headers compile as C.
 *
 * This file is compiled as C (/TC) at /W4 /WX with no precompiled header, and
 * includes each header on its own before anything else. A C++ construct, a
 * missing include or a warning in a header fails the build of the test
 * project, which is the check. The function below only gives the translation
 * unit something to link.
 */
#include "NativeToolkitC/Common.h"

size_t ntk_test_headers_compile_as_c(void)
{
    ntk_release_fn release = 0;
    return sizeof(release) + sizeof(NTK_VERSION);
}
