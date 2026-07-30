#include "pch.h"
#include "WindowsClipboardDeferredProvider.h"
#include "common.h"

static const wchar_t* TAG = L"WindowsClipboardDeferredProvider";

DeferredClipboard::Renderer MakeDeferredRenderer(ClipboardRenderCallback provider,
                                                  void* context,
                                                  std::wstring formatName)
{
    DFLog(TAG, L"[MakeDeferredRenderer] provider: %p, context: %p, format: %ls",
          provider, context, formatName.c_str());
    return [provider, context, formatName = std::move(formatName)]() -> GlobalMem
    {
        DWORD queriedSize = 0;
        DWORD err = CLIPBOARD_ERROR_UNKNOWN;
        try { err = provider(formatName.c_str(), context, nullptr, 0, &queriedSize); }
        catch (...) { DLog(TAG, L"[Renderer] provider size query threw"); return GlobalMem(); }
        if (err != CLIPBOARD_ERROR_NONE && err != CLIPBOARD_ERROR_BUFFER_TOO_SMALL) return GlobalMem();
        if (queriedSize == 0) return GlobalMem();

        GlobalMem mem(queriedSize);
        if (!mem.IsValid()) return mem;
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return GlobalMem();

        DWORD actualSize = queriedSize;
        try
        {
            err = provider(formatName.c_str(), context,
                           static_cast<BYTE*>(lock.Get()), queriedSize, &actualSize);
        }
        catch (...) { DLog(TAG, L"[Renderer] provider fill threw"); return GlobalMem(); }
        if (err != CLIPBOARD_ERROR_NONE) return GlobalMem();
        if (actualSize != queriedSize)
        {
            // A smaller size would expose an uninitialized HGLOBAL tail; a
            // larger size would exceed the supplied buffer.
            DFLog(TAG, L"[Renderer] provider size changed. queried=%lu actual=%lu",
                  queriedSize, actualSize);
            return GlobalMem();
        }
        return mem;
    };
}
