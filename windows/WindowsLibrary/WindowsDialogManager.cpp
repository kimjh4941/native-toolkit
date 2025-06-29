#include "pch.h"
#include "afxdialogex.h"
#include <windows.h>
#include <string>
#include "resource.h" // リソースIDを含むヘッダーファイル
#include "common.h"
#include "WindowsDialogManager.h"
#include <memory>
#include <shobjidl.h> // IFileDialog, IFileOpenDialog


static const wchar_t* TAG = L"WindowsDialogManager";

// ダイアログクラスの実装
class WindowsDialogManager
{
public:
    // シングルトンインスタンス取得
    static WindowsDialogManager& Instance()
    {
        static WindowsDialogManager instance;
        return instance;
    }

    // コピー・ムーブ禁止
    WindowsDialogManager(const WindowsDialogManager&) = delete;
    WindowsDialogManager& operator=(const WindowsDialogManager&) = delete;

    int ShowAlertDialog(
        const wchar_t* title,
        const wchar_t* message,
        UINT buttons,
        UINT icon,
        UINT defbutton,
        UINT options,
        DWORD* pError = nullptr  // オプショナル
    )
    {
        UINT type = buttons | icon | defbutton | options;
        int result = MessageBoxW(nullptr, message, title, type);

        if (result == 0) {
            DWORD lastError = GetLastError();
            if (pError) {
                *pError = lastError;
            }
            // エラー時は必ずログ出力
            DFLog(TAG, L"ShowAlertDialog: MessageBoxW failed. GetLastError: %lu", lastError);
        }
        else if (pError) {
            *pError = 0;
        }

        return result;
    }

    BOOL ShowFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // オプショナル
    )
    {
        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"すべてのファイル\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;

        BOOL result = GetOpenFileNameW(&ofn);
        if (!result) {
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // エラーが発生した場合
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowFileDialog: GetOpenFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
            }
            else
            {
                // ユーザーがキャンセルした場合
                if (pError) {
                    *pError = 0;
                }
                DLog(TAG, L"ファイル選択がキャンセルされました。");
                result = TRUE; // キャンセル時はTRUEを返す
            }
            buffer[0] = L'\0';
        }
        return result;
    }

    int ShowMultiFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // オプショナル
    )
    {
        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"すべてのファイル\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_ALLOWMULTISELECT | OFN_EXPLORER;

        BOOL result = GetOpenFileNameW(&ofn);
        if (!result) {
            buffer[0] = L'\0';
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // エラーが発生した場合
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowMultiFileDialog: GetOpenFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
                return -1; // エラーが発生した場合は-1を返す
            }
            else
            {
                // ユーザーがキャンセルした場合
                if (pError) {
                    *pError = 0;
                }
                DLog(TAG, L"複数ファイル選択がキャンセルされました。");
                return 0; // キャンセル時は0を返す
            }
        }

        // 成功時
        if (pError) {
            *pError = 0;
        }

        // 複数ファイル選択時は、最初にフォルダ名、以降にファイル名が\0区切りで格納される
        int count = 0;
        wchar_t* p = buffer;
        while (*p) {
            ++count;
            // 次の文字列へ
            p += wcslen(p) + 1;
        }
        // 1つだけならフルパス、2つ以上なら最初がフォルダ名、以降がファイル名
        return count;
    }

    BOOL ShowSaveFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        const wchar_t* def_ext = nullptr,
        DWORD* pError = nullptr  // オプショナル
    )
    {
        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"すべてのファイル\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT;
        ofn.lpstrDefExt = def_ext;

        BOOL result = GetSaveFileNameW(&ofn);
        if (!result) {
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // エラーが発生した場合
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowSaveFileDialog: GetSaveFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
            }
            else
            {
                // ユーザーがキャンセルした場合
                if (pError) {
                    *pError = 0;
                }
                DLog(TAG, L"保存ファイル選択がキャンセルされました。");
                result = TRUE; // キャンセル時はTRUEを返す
            }
            buffer[0] = L'\0';
        }
        else {
            // 成功時
            if (pError) {
                *pError = 0;
            }
        }
        return result;
    }

    BOOL ShowFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"フォルダの選択",
        DWORD * pError = nullptr  // オプショナル
    )
    {
        // COM初期化（呼び出し元でCoInitialize済みなら不要）
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);

        IFileOpenDialog* pFileOpen = nullptr;
        hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFileOpen));
        if (FAILED(hr)) {
            if (needUninit) CoUninitialize();
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowFolderDialog: CoCreateInstance failed. hr=0x%08lx", hr);
            return FALSE;
        }

        // タイトル設定
        if (title) pFileOpen->SetTitle(title);

        // フォルダ選択モード
        DWORD dwOptions;
        pFileOpen->GetOptions(&dwOptions);
        pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);

        // ダイアログ表示
        hr = pFileOpen->Show(nullptr);
        if (SUCCEEDED(hr)) {
            IShellItem* pItem = nullptr;
            hr = pFileOpen->GetResult(&pItem);
            if (SUCCEEDED(hr)) {
                PWSTR pszFolderPath = nullptr;
                hr = pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszFolderPath);
                if (SUCCEEDED(hr)) {
                    size_t pathLen = wcslen(pszFolderPath);
                    if (pathLen + 1 > buffer_size) {
                        // バッファ不足
                        buffer[0] = L'\0';
                        if (pError) {
                            *pError = ERROR_INSUFFICIENT_BUFFER;
                        }
                        DFLog(TAG, L"ShowFolderDialog: buffer too small. required=%zu, buffer_size=%lu", pathLen + 1, buffer_size);
                        CoTaskMemFree(pszFolderPath);
                        pItem->Release();
                        pFileOpen->Release();
                        if (needUninit) CoUninitialize();
                        return FALSE;
                    }
                    wcsncpy_s(buffer, buffer_size, pszFolderPath, _TRUNCATE);
                    if (pError) {
                        *pError = 0;
                    }
                    CoTaskMemFree(pszFolderPath);
                    pItem->Release();
                    pFileOpen->Release();
                    if (needUninit) CoUninitialize();
                    return TRUE;
                }
                if (pszFolderPath) CoTaskMemFree(pszFolderPath);
                pItem->Release();
            }
        }
        pFileOpen->Release();
        buffer[0] = L'\0';
        if (needUninit) CoUninitialize();
        // キャンセル時はTRUE、エラー時はFALSE
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            if (pError) {
                *pError = 0;
            }
            DLog(TAG, L"フォルダ選択がキャンセルされました。");
            return TRUE;
        }
        else {
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowFolderDialog: failed. hr=0x%08lx", hr);
            return FALSE;
        }
    }

    int ShowMultiFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"フォルダの選択",
        DWORD* pError = nullptr  // オプショナル
    )
    {
        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));

        // COM初期化（呼び出し元でCoInitialize済みなら不要）
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);

        IFileOpenDialog* pFileOpen = nullptr;
        hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFileOpen));
        if (FAILED(hr)) {
            if (needUninit) CoUninitialize();
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowMultiFolderDialog: CoCreateInstance failed. hr=0x%08lx", hr);
            return -1;
        }

        // タイトル設定
        if (title) pFileOpen->SetTitle(title);

        // フォルダ選択＋複数選択
        DWORD dwOptions;
        pFileOpen->GetOptions(&dwOptions);
        pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS | FOS_ALLOWMULTISELECT | FOS_FORCEFILESYSTEM);

        // ダイアログ表示
        hr = pFileOpen->Show(nullptr);
        if (SUCCEEDED(hr)) {
            IShellItemArray* pItems = nullptr;
            hr = pFileOpen->GetResults(&pItems);
            if (SUCCEEDED(hr)) {
                DWORD count = 0;
                pItems->GetCount(&count);
                wchar_t* p = buffer;
                DWORD remain = buffer_size;
                bool bufferOverflow = false;
                for (DWORD i = 0; i < count; ++i) {
                    IShellItem* pItem = nullptr;
                    if (SUCCEEDED(pItems->GetItemAt(i, &pItem))) {
                        PWSTR pszPath = nullptr;
                        if (SUCCEEDED(pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszPath))) {
                            size_t len = wcslen(pszPath);
                            if (len + 1 < remain) {
                                wmemcpy(p, pszPath, len + 1); // +1 for null terminator
                                p += len + 1;
                                remain -= (DWORD)(len + 1);
                            }
                            else {
                                // バッファ不足
                                bufferOverflow = true;
                                if (pError) {
                                    *pError = ERROR_INSUFFICIENT_BUFFER;
                                }
                                DFLog(TAG, L"ShowMultiFolderDialog: buffer too small for folder %lu. required=%zu, remain=%lu", i + 1, len + 1, remain);
                                CoTaskMemFree(pszPath);
                                pItem->Release();
                                break;
                            }
                            CoTaskMemFree(pszPath);
                        }
                        pItem->Release();
                    }
                }
                pItems->Release();
                if (needUninit) CoUninitialize();
                // 複数選択時は、\0区切りで格納、最後は\0\0
                if (!bufferOverflow && count > 0 && remain > 0) *p = L'\0';
                if (bufferOverflow) {
                    buffer[0] = L'\0';
                    return -1;
                }
                // 成功時
                if (pError) {
                    *pError = 0;
                }
                return (int)count;
            }
        }
        pFileOpen->Release();
        buffer[0] = L'\0';
        if (needUninit) CoUninitialize();
        // キャンセル時は0、エラー時は-1
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            if (pError) {
                *pError = 0;
            }
            DLog(TAG, L"複数フォルダ選択がキャンセルされました。");
            return 0;
        }
        else {
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowMultiFolderDialog: failed. hr=0x%08lx", hr);
            return -1;
        }
    }

private:
    // コンストラクタはprivate
    WindowsDialogManager(CWnd* pParent = nullptr)
        : m_dialogEx(IDD_DIALOG, pParent)
    {

    }

    CDialogEx m_dialogEx;
};

int showAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options,
    DWORD* pError
)
{
    DFLog(TAG, L"showAlertDialog title: %ls, message: %ls, buttons: %d, icon: %d, defbutton: %d, options: %d", title, message, buttons, icon, defbutton, options);
    DFLog(TAG, L"showAlertDialog IDD_DIALOG: %d", IDD_DIALOG);

    int result = WindowsDialogManager::Instance().ShowAlertDialog(title, message, buttons, icon, defbutton, options, pError);
    if (result == 0) {
        DLog(TAG, L"ダイアログの表示に失敗しました。");
    }
    else if (result == IDOK) {
        DLog(TAG, L"ユーザーはOKをクリックしました。");
    }
    else if (result == IDCANCEL) {
        DLog(TAG, L"ユーザーはキャンセルをクリックしました。");
    }
    else if (result == IDYES) {
        DLog(TAG, L"ユーザーはYesをクリックしました。");
    }
    else if (result == IDNO) {
        DLog(TAG, L"ユーザーはNoをクリックしました。");
    }
    else {
        DFLog(TAG, L"その他の結果: %d", result);
	}
    DFLog(TAG, L"ShowAlertDialog returned %d", result);
    return result;
}

BOOL showFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DLog(TAG, L"showFileDialog");

    BOOL result = WindowsDialogManager::Instance().ShowFileDialog(buffer, buffer_size, filter, pError);
    if (result)
    {
        DFLog(TAG, L"選択されたファイル: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"ファイル選択でエラーが発生しました。");
    }
    DFLog(TAG, L"ShowFileDialog returned %d", result);
    return result;
}

int showMultiFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DLog(TAG, L"showMultiFileDialog");

    int count = WindowsDialogManager::Instance().ShowMultiFileDialog(buffer, buffer_size, filter, pError);
    DFLog(TAG, L"count(フォルダ名＋ファイル数): %d", count);
    if (count > 0)
    {
        // 複数ファイル選択時は、最初がフォルダ名、以降がファイル名（\0区切り）
        wchar_t* p = buffer;
        if (count == 1)
        {
            DFLog(TAG, L"選択ファイル: %ls", p);
        }
        else
        {
            std::wstring folder = p;
            p += wcslen(p) + 1;
            for (int i = 1; i < count; ++i)
            {
                std::wstring fullpath = folder + L"\\" + p;
                DFLog(TAG, L"選択ファイル %d: %ls", i, fullpath.c_str());
                p += wcslen(p) + 1;
            }
        }
    }
    else
    {
        if (count < 0)
        {
            DFLog(TAG, L"複数ファイル選択でエラーが発生しました。");
        }
        else
        {
            DFLog(TAG, L"複数ファイル選択がキャンセルされました。");
        }
    }
    return count;
}

BOOL showSaveFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    const wchar_t* def_ext,
    DWORD* pError
)
{
    DLog(TAG, L"showSaveFileDialog");
    BOOL result = WindowsDialogManager::Instance().ShowSaveFileDialog(buffer, buffer_size, filter, def_ext, pError);
    if (result)
    {
        DFLog(TAG, L"保存先ファイル: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"保存ファイル選択でエラーが発生しました。");
    }
    DFLog(TAG, L"ShowSaveFileDialog returned %d", result);
    return result;
}

BOOL showFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
) {
    DLog(TAG, L"showFolderDialog");

    BOOL result = WindowsDialogManager::Instance().ShowFolderDialog(buffer, buffer_size, title, pError);
    if (result)
    {
        DFLog(TAG, L"選択されたフォルダ: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"フォルダ選択でエラーが発生しました。");
    }
    DFLog(TAG, L"ShowFolderDialog returned %d", result);
    return result;
}

int showMultiFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
)
{
    DLog(TAG, L"showMultiFolderDialog");

    int count = WindowsDialogManager::Instance().ShowMultiFolderDialog(buffer, buffer_size, title, pError);
    DFLog(TAG, L"count(フォルダ数): %d", count);
    if (count > 0)
    {
        // 複数フォルダ選択時は、\0区切りで格納（最後は\0\0）
        wchar_t* p = buffer;
        for (int i = 0; i < count; ++i)
        {
            DFLog(TAG, L"選択フォルダ %d: %ls", i + 1, p);
            p += wcslen(p) + 1;
        }
    }
    else
    {
        if (count < 0)
        {
            DFLog(TAG, L"複数フォルダ選択でエラーが発生しました。");
        }
        else
        {
            DFLog(TAG, L"複数フォルダ選択がキャンセルされました。");
        }
    }
    return count;
}
