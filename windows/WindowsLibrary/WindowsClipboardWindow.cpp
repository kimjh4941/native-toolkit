#include "pch.h"
#include "WindowsClipboardWindow.h"
#include "WindowsClipboardManagerInternal.h"
#include "WindowsClipboardHistoryCoordinator.h" // WM_APP_CLIPBOARD_* message ids
#include "common.h"

static const wchar_t* TAG = L"WindowsClipboardWindow";
static const wchar_t* kClassName = L"NativeToolkitClipboardWindow";

namespace
{
    LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
    {
        // Every case below eventually reaches a Manager/Coordinator method that
        // may allocate (std::vector/std::wstring/std::function/WinRT JSON) or
        // invoke a caller-supplied C callback/provider. None of that may let an
        // exception cross this Win32 window-procedure boundary (H3).
        try
        {
            switch (msg)
            {
            case WM_CLIPBOARDUPDATE:
                ClipboardManager::GetInstance().OnClipboardUpdate();
                return 0;
            case WM_RENDERFORMAT:
                ClipboardManager::GetInstance().OnRenderFormat(static_cast<UINT>(wp));
                return 0;
            case WM_RENDERALLFORMATS:
                ClipboardManager::GetInstance().OnRenderAllFormats(hwnd);
                return 0;
            case WM_DESTROYCLIPBOARD:
                ClipboardManager::GetInstance().OnDestroyClipboardMsg();
                return 0;
            case WM_APP_CLIPBOARD_REQUEST:
                ClipboardManager::GetInstance().OnHistoryRequestMessage(static_cast<uint32_t>(wp));
                return 0;
            case WM_APP_CLIPBOARD_CANCEL:
                ClipboardManager::GetInstance().OnHistoryCancelMessage(static_cast<uint32_t>(wp));
                return 0;
            case WM_APP_CLIPBOARD_DRAIN:
                ClipboardManager::GetInstance().OnHistoryDrainMessage();
                return 0;
            case WM_APP_CLIPBOARD_HISTORY_EVENT:
                ClipboardManager::GetInstance().OnHistoryEventMessage(wp, lp);
                return 0;
            default:
                return ::DefWindowProcW(hwnd, msg, wp, lp);
            }
        }
        catch (...)
        {
            DFLog(TAG, L"[WndProc] handler threw. msg=0x%04x", msg);
            return 0;
        }
    }

    ATOM RegisterWindowClassOnce()
    {
        static ATOM atom = 0;
        if (atom != 0) return atom;
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = WndProc;
        wc.hInstance = ::GetModuleHandleW(nullptr);
        wc.lpszClassName = kClassName;
        atom = ::RegisterClassExW(&wc);
        return atom;
    }
}

namespace WindowsClipboardWindow
{
    HWND Create()
    {
        DLog(TAG, L"[Create]");
        if (RegisterWindowClassOnce() == 0)
        {
            DFLog(TAG, L"[Create] RegisterClassExW failed. err=%lu", ::GetLastError());
            return nullptr;
        }
        // Hidden top-level window (not HWND_MESSAGE): message-only windows are not used
        // for this feature because WM_CLIPBOARDUPDATE delivery to them is unverified.
        HWND hwnd = ::CreateWindowExW(0, kClassName, kClassName, WS_POPUP, 0, 0, 0, 0,
                                      nullptr, nullptr, ::GetModuleHandleW(nullptr), nullptr);
        if (!hwnd)
        {
            DFLog(TAG, L"[Create] CreateWindowExW failed. err=%lu", ::GetLastError());
            return nullptr;
        }
        return hwnd;
    }

    void Destroy(HWND hwnd)
    {
        DFLog(TAG, L"[Destroy] hwnd: %p", hwnd);
        if (hwnd) ::DestroyWindow(hwnd);
    }
}
