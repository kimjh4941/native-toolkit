#pragma once
#include <string>

// The DLL's surface is the .def file and nothing else (D-5, design 7.6.1).
// These declarations carry no __declspec: the static core includes this header
// too, and an export macro there would either leak dllexport into whatever links
// the core, or make the core read its own functions as dllimport.


extern "C"
// グローバルデバッグログ関数
void DLog(const wchar_t* tag, const wchar_t* message);

extern "C"
void DFLog(const wchar_t* tag, const wchar_t* format, ...);

extern "C"
void DFLLog(const wchar_t* tag, size_t bufferSize, const wchar_t* format, ...);

extern "C"
// マルチバイト文字列（const char*）をワイド文字列（std::wstring）に変換
std::wstring ToWString(const char* mbstr);

extern "C"
// 2つのwchar_t*を結合し、動的に確保したwchar_t*を返す（呼び出し側でdelete[]が必要）
wchar_t* ConcatWStrings(const wchar_t* s1, const wchar_t* s2);
