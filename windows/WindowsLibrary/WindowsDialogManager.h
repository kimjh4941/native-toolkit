#pragma once

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSDIALOGMANAGER_API __declspec(dllexport)
#else
#define WINDOWSDIALOGMANAGER_API __declspec(dllimport)
#endif


// ダイアログを表示するエクスポート関数の宣言
extern "C" WINDOWSDIALOGMANAGER_API
int ShowModal();

extern "C" WINDOWSDIALOGMANAGER_API
int ShowAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options
);
