#pragma once

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSDIALOGMANAGER_API __declspec(dllexport)
#else
#define WINDOWSDIALOGMANAGER_API __declspec(dllimport)
#endif


extern "C" WINDOWSDIALOGMANAGER_API
int showAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options,
    DWORD* pError
);

extern "C" WINDOWSDIALOGMANAGER_API
BOOL showFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
);

extern "C" WINDOWSDIALOGMANAGER_API
int showMultiFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
);

extern "C" WINDOWSDIALOGMANAGER_API
BOOL showSaveFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    const wchar_t* def_ext,
    DWORD* pError
);

extern "C" WINDOWSDIALOGMANAGER_API
BOOL showFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
);

extern "C" WINDOWSDIALOGMANAGER_API
int showMultiFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
);