#include "pch.h"
#include "afxdialogex.h"
#include <windows.h>
#include <string>
#include "resource.h" // リソースIDを含むヘッダーファイル
#include "common.h"
#include "WindowsDialogManager.h"
#include <memory>


static const wchar_t* TAG = L"WindowsDialogManager";

// ダイアログクラスの実装
class WindowsDialogManager
{
public:
    WindowsDialogManager(CWnd* pParent = nullptr)
        : m_dlg(IDD_DIALOG, pParent) {
    }

    int ShowModal()
    {
        return static_cast<int>(m_dlg.DoModal());
    }

private:
    CDialogEx m_dlg;
};

// ダイアログを表示するエクスポート関数
int ShowModal()
{
    AFX_MANAGE_STATE(AfxGetStaticModuleState());
    DLog(TAG, L"ShowModal");
    DFLog(TAG, L"IDD_DIALOG: %d", IDD_DIALOG);

    auto windows_dialog_manager = std::make_unique<WindowsDialogManager>(CWnd::FromHandle(::GetActiveWindow()));
    int result = windows_dialog_manager->ShowModal();
    DFLog(TAG, L"ShowModal returned %d", result);

    return result;
}

int ShowAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options
)
{
    AFX_MANAGE_STATE(AfxGetStaticModuleState());
    DFLog(TAG, L"ShowAlertDialog title: %ls, message: %ls, buttons: %d, icon: %d, defbutton: %d, options: %d", title, message, buttons, icon, defbutton, options);
    DFLog(TAG, L"ShowAlertDialog IDD_DIALOG: %d", IDD_DIALOG);
    UINT type = buttons | icon | defbutton | options;

    int result = MessageBoxW(nullptr, message, title, type);
    DFLog(TAG, L"ShowAlertDialog returned %d", result);
    return result;
}
