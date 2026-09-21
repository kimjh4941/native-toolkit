// CT-02 of the stage 5 design: the C ABI's public headers compile on their own
// as C++, may be included more than once, and do not clash with <windows.h>
// included after them.
//
// No precompiled header: MSVC ignores everything before #include "pch.h", so a
// PCH would hide exactly the missing includes this file is here to catch.
#include "NativeToolkitC/Common.h"
#include "NativeToolkitC/Common.h"

#include <windows.h>

#include "NativeToolkitC/Common.h"

// The C linkage the headers promise: a C++ caller gets the unmangled names the
// .def exports. Taking the addresses makes the linker resolve them.
extern "C" size_t ntk_test_headers_self_contained()
{
    const void* functions[] = {
        reinterpret_cast<const void*>(&ntk_version),
        reinterpret_cast<const void*>(&ntk_last_system_code),
        reinterpret_cast<const void*>(&ntk_string_data),
        reinterpret_cast<const void*>(&ntk_string_list_at),
    };
    return sizeof(functions);
}
