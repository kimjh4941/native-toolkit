#pragma once
#include <string>
#include "NativeToolkit/BuildStamp.h"

// The library's internal helpers. They were exported by the 1.x C ABI
// through common.h, which stage 5 removed (design E-6, 8.5); they are
// ordinary C++ functions of the core now.

// Writes a debug log line: [tag] message.
void DLog(const wchar_t* tag, const wchar_t* message);

// Writes a formatted debug log line with a fixed-size buffer.
void DFLog(const wchar_t* tag, const wchar_t* format, ...);

// Writes a formatted debug log line with a caller-chosen buffer size.
void DFLLog(const wchar_t* tag, size_t bufferSize, const wchar_t* format, ...);

// Converts a multibyte string (const char*) to std::wstring.
std::wstring ToWString(const char* mbstr);

// Concatenates two wchar_t* values and returns a new wchar_t*; the caller frees it with delete[].
wchar_t* ConcatWStrings(const wchar_t* s1, const wchar_t* s2);
