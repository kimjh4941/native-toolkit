#include "pch.h"
#include "Clipboard/Data/WindowsClipboardDeferredProvider.h"
#include "Common/CommonInternal.h"
#include "Clipboard/Domain/WindowsClipboardFormats.h"

#include <cstring>

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

DeferredClipboard::Renderer MakeDeferredRenderer(NativeToolkit::Clipboard::RenderProvider provider,
                                                  std::wstring formatName)
{
    DFLog(TAG, L"[MakeDeferredRenderer] format: %ls", formatName.c_str());
    return [provider = std::move(provider), formatName = std::move(formatName)]() -> GlobalMem
    {
        NativeToolkit::Clipboard::Result<std::vector<std::byte>> produced =
            NativeToolkit::Unexpected{NativeToolkit::Clipboard::Error{
                NativeToolkit::Clipboard::ErrorCode::Unknown, 0}};
        try
        {
            produced = provider(formatName);
        }
        catch (...)
        {
            // Nothing above is still listening, so the only honest outcome is
            // an empty format and a line in the log (N-3).
            DFLog(TAG, L"[Renderer] the provider for %ls threw", formatName.c_str());
            return GlobalMem();
        }

        if (!produced.has_value())
        {
            DFLog(TAG, L"[Renderer] the provider for %ls failed. code=%u",
                  formatName.c_str(), static_cast<unsigned>(produced.error().code));
            return GlobalMem();
        }

        const std::vector<std::byte>& bytes = produced.value();
        if (bytes.empty()) return GlobalMem();

        UINT size = 0;
        if (!ClipboardFormats::CheckedToUInt(bytes.size(), size))
        {
            DFLog(TAG, L"[Renderer] the provider for %ls returned too much", formatName.c_str());
            return GlobalMem();
        }

        GlobalMem mem(size);
        if (!mem.IsValid()) return mem;
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return GlobalMem();
        ::memcpy(lock.Get(), bytes.data(), bytes.size());
        return mem;
    };
}
