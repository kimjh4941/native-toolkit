#pragma once
#include <string>

// Internal declarations of the helpers that common.h publishes to C ABI consumers.
// The declarations are identical except that they carry no dllexport/dllimport:
// library code links the definitions directly, while the DLL exports the same
// symbols through WindowsLibrary.def. Library code must include this header and
// never common.h, so that the definitions stay usable once the implementation is
// built as a static library (stage 3 of the windows-architecture topic).

extern "C"
// Writes a debug log line: [tag] message.
void DLog(const wchar_t* tag, const wchar_t* message);

extern "C"
// Writes a formatted debug log line with a fixed-size buffer.
void DFLog(const wchar_t* tag, const wchar_t* format, ...);

extern "C"
// Writes a formatted debug log line with a caller-chosen buffer size.
void DFLLog(const wchar_t* tag, size_t bufferSize, const wchar_t* format, ...);

extern "C"
// Converts a multibyte string (const char*) to std::wstring.
std::wstring ToWString(const char* mbstr);

extern "C"
// Concatenates two wchar_t* values and returns a new wchar_t*; the caller frees it with delete[].
wchar_t* ConcatWStrings(const wchar_t* s1, const wchar_t* s2);
