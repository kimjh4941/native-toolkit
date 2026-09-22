// The same checks as smoke.c, compiled as C++: a C++ caller includes the C
// ABI's headers and gets C linkage, so the names it links against are the
// unmangled ones the .def exports (CT-21).
#include "smoke.c"
