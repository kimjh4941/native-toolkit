// Debug builds only: a probe operation and a probe event that go through the same shared parts as
// the features (Accept, the registry, the Kotlin ledger, the main thread), so that the tests of
// design part 1, chapter 6 can drive every step - accept, complete, cancel, deliver, remove -
// without a feature. Not in a release build; the functions are declared for the tests in
// android_library_capi_test (ntk_debug_probe.h).
#pragma once

#include "Common/Classes.h"

namespace nativetoolkit::probe {

// capi.jni.ProbeBridge (src/debug of the module).
classes::ClassSpec ProbeClassSpec();

}  // namespace nativetoolkit::probe
