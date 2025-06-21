#include "pch.h"
#include "common.h"

void DLog(const wchar_t* tag, const wchar_t* message)
{
    std::wstring wtag(tag);
    std::wstring out = wtag + L" " + message + L"\n";
    OutputDebugStringW(out.c_str());
}

// フォーマット付きデバッグログ出力関数
void DFLog(const wchar_t* tag, const wchar_t* format, ...)
{
    wchar_t buf[256];
    va_list args;
    va_start(args, format);
    vswprintf_s(buf, sizeof(buf) / sizeof(wchar_t), format, args);
    va_end(args);
    DLog(tag, buf);
}

// マルチバイト文字列（const char*）をワイド文字列（std::wstring）に変換
std::wstring ToWString(const char* mbstr)
{
    if (!mbstr) return L"";
    int len = MultiByteToWideChar(CP_ACP, 0, mbstr, -1, nullptr, 0);
    if (len <= 1) return L"";
    std::wstring wstr(len - 1, L'\0'); // -1は終端分
    MultiByteToWideChar(CP_ACP, 0, mbstr, -1, &wstr[0], len);
    return wstr;
}

// 2つのwchar_t*を結合し、動的に確保したwchar_t*を返す（呼び出し側でdelete[]が必要）
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
