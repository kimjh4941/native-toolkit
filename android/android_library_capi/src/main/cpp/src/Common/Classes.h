// The Java classes the C ABI uses, looked up once when the class table is built (C ABI design
// part 1, 5.3 and 5.6). Each part of the C ABI describes its classes here; Runtime builds them all
// or none.
#pragma once

#include <jni.h>

#include <vector>

namespace nativetoolkit::classes {

struct StaticMethod {
    const char* name;
    const char* signature;
    jmethodID* out;
};

struct ClassSpec {
    const char* name;  // in the slash form, such as com/jonghyunkim/nativetoolkit/capi/jni/Ledger
    jclass* out;       // a global reference once built; never deleted (design 5.5)
    std::vector<StaticMethod> methods;
    std::vector<JNINativeMethod> natives;
};

// Every class of the C ABI, NtkRuntime first.
std::vector<ClassSpec> All();

}  // namespace nativetoolkit::classes
