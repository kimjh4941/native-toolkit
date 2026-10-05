// The functions of the public headers are compiled with -fvisibility=hidden like everything else;
// this marks the ones that leave libntk.so. The version script (libntk.map) is the second gate.
#pragma once

#define NTK_EXPORT extern "C" __attribute__((visibility("default")))
