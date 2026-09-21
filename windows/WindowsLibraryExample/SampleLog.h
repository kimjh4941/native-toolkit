#pragma once

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <string>
#include <vector>

// Debug output for the sample. The toolkit's own logging lives in its private
// headers, which a consumer of the C++ API does not get, so the sample keeps a
// copy of the two helpers it uses. Output goes to the debugger, as "TAG message".

inline void DLog(const wchar_t* tag, const wchar_t* message)
{
    std::wstring out = std::wstring(tag) + L" " + message + L"\n";
    ::OutputDebugStringW(out.c_str());
}

inline void DFLog(const wchar_t* tag, const wchar_t* format, ...)
{
    va_list args;
    va_start(args, format);
    const int needed = _vscwprintf(format, args);
    va_end(args);
    if (needed < 0)
    {
        DLog(tag, format);
        return;
    }

    std::vector<wchar_t> buffer(static_cast<size_t>(needed) + 1, L'\0');
    va_start(args, format);
    vswprintf_s(buffer.data(), buffer.size(), format, args);
    va_end(args);
    DLog(tag, buffer.data());
}
