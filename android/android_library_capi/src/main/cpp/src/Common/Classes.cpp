#include "Common/Classes.h"

#include "Clipboard/Clipboard.h"

#include "Common/Log.h"
#include "Common/Registry.h"
#include "Common/Runtime.h"
#ifndef NDEBUG
#include "Debug/Probe.h"
#endif

namespace nativetoolkit::classes {

std::vector<ClassSpec> All() {
    NTK_LOGD("[All]");
    std::vector<ClassSpec> specs;
    specs.push_back(runtime::RuntimeClassSpec());
    specs.push_back(registry::LedgerClassSpec());
    specs.push_back(clipboard::ClassSpec());
#ifndef NDEBUG
    // Debug builds only: the probe operation of the C ABI tests.
    specs.push_back(probe::ProbeClassSpec());
#endif
    return specs;
}

}  // namespace nativetoolkit::classes
