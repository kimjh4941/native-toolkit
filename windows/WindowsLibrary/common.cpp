#include "pch.h"
#include "common.h"
#include <memory>

void DLog(const wchar_t* tag, const wchar_t* message)
{
    std::wstring wtag(tag);
    std::wstring out = wtag + L" " + message + L"\n";
    OutputDebugStringW(out.c_str());
}

// Formatted debug log output (default, auto-sized buffer).
void DFLog(const wchar_t* tag, const wchar_t* format, ...)
{
    va_list args;
    // Compute the required length so long messages (e.g. full JSON payloads)
    // are not truncated. vswprintf_s asserts ("Buffer too small") on overflow,
    // so the buffer must be sized to fit the formatted output.
    va_start(args, format);
    int needed = _vscwprintf(format, args);
    va_end(args);
    if (needed < 0)
    {
        DLog(tag, format);
        return;
    }

    std::unique_ptr<wchar_t[]> buf(new wchar_t[needed + 1]);
    va_start(args, format);
    vswprintf_s(buf.get(), needed + 1, format, args);
    va_end(args);
    DLog(tag, buf.get());
}

// Formatted debug log output (caller-specified buffer size).
void DFLLog(const wchar_t* tag, size_t bufferSize, const wchar_t* format, ...)
{
    std::unique_ptr<wchar_t[]> buf(new wchar_t[bufferSize]);
    va_list args;
    va_start(args, format);
    vswprintf_s(buf.get(), bufferSize, format, args);
    va_end(args);
    DLog(tag, buf.get());
}

// Convert a multi-byte string (const char*) to a wide string (std::wstring).
std::wstring ToWString(const char* mbstr)
{
    if (!mbstr) return L"";
    int len = MultiByteToWideChar(CP_ACP, 0, mbstr, -1, nullptr, 0);
    if (len <= 1) return L"";
    std::wstring wstr(len - 1, L'\0'); // -1 excludes the null terminator
    MultiByteToWideChar(CP_ACP, 0, mbstr, -1, &wstr[0], len);
    return wstr;
}

// Concatenate two wchar_t* into a heap-allocated wchar_t* (caller must delete[]).
wchar_t* ConcatWStrings(const wchar_t* s1, const wchar_t* s2)
{
    if (!s1) s1 = L"";
    if (!s2) s2 = L"";
    std::wstring ws1(s1);
    std::wstring ws2(s2);
    std::wstring result = ws1 + ws2;
    wchar_t* buf = new wchar_t[result.size() + 1];
    wcscpy_s(buf, result.size() + 1, result.c_str());
    return buf;
}
