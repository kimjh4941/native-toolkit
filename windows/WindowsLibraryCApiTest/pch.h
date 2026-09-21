#pragma once

// The C ABI tests see the C ABI's headers and its internal src, never the
// core's internals: the core arrives as the static library, through the same
// consumer props the C ABI DLL uses.
#include <windows.h>

#include <CppUnitTest.h>

#include <cstdint>
#include <string>
