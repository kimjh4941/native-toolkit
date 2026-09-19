#pragma once
#include <string>

#ifdef WINDOWSLIBRARY_EXPORTS
#define COMMON_API __declspec(dllexport)
#else
#define COMMON_API __declspec(dllimport)
#endif


extern "C" COMMON_API
// グローバルデバッグログ関数
void DLog(const wchar_t* tag, const wchar_t* message);

extern "C" COMMON_API
void DFLog(const wchar_t* tag, const wchar_t* format, ...);

extern "C" COMMON_API
void DFLLog(const wchar_t* tag, size_t bufferSize, const wchar_t* format, ...);

extern "C" COMMON_API
// マルチバイト文字列（const char*）をワイド文字列（std::wstring）に変換
std::wstring ToWString(const char* mbstr);

extern "C" COMMON_API
// 2つのwchar_t*を結合し、動的に確保したwchar_t*を返す（呼び出し側でdelete[]が必要）
wchar_t* ConcatWStrings(const wchar_t* s1, const wchar_t* s2);
