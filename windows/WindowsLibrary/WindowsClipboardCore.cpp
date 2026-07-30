#include "pch.h"
#include "WindowsClipboardCore.h"
#include "WindowsClipboardFormats.h"
#include "WindowsClipboardManager.h"
#include "common.h"
#include <shellapi.h>
#include <shlobj_core.h>

static const wchar_t* TAG = L"WindowsClipboardCore";

using ClipboardFormats::CheckedAdd;
using ClipboardFormats::CheckedMul;
using ClipboardFormats::CheckedToUInt;

// =============================================================================
// IClipboardWin32Api
// =============================================================================

namespace
{
    class RealWin32Api final : public IClipboardWin32Api
    {
    public:
        BOOL   OpenClipboard(HWND owner) override { return ::OpenClipboard(owner); }
        BOOL   CloseClipboard() override { return ::CloseClipboard(); }
        BOOL   EmptyClipboard() override { return ::EmptyClipboard(); }
        HANDLE SetClipboardData(UINT format, HANDLE hMem) override { return ::SetClipboardData(format, hMem); }
        HANDLE GetClipboardData(UINT format) override { return ::GetClipboardData(format); }
        HWND   GetClipboardOwner() override { return ::GetClipboardOwner(); }
        BOOL   IsClipboardFormatAvailable(UINT format) override { return ::IsClipboardFormatAvailable(format); }
        BOOL   AddClipboardFormatListener(HWND hwnd) override { return ::AddClipboardFormatListener(hwnd); }
        BOOL   RemoveClipboardFormatListener(HWND hwnd) override { return ::RemoveClipboardFormatListener(hwnd); }
        DWORD  GetClipboardSequenceNumber() override { return ::GetClipboardSequenceNumber(); }
    };

    RealWin32Api g_realApi;
    IClipboardWin32Api* g_testApi = nullptr;
}

IClipboardWin32Api& DefaultWin32Api() { return g_realApi; }

void SetWin32ApiForTest(IClipboardWin32Api* api) { g_testApi = api; }

IClipboardWin32Api& ActiveWin32Api() { return g_testApi ? *g_testApi : g_realApi; }

// =============================================================================
// RAII helpers
// =============================================================================

ClipboardScope::ClipboardScope(HWND owner)
{
    DFLog(TAG, L"[ClipboardScope] owner: %p", owner);
    for (int i = 0; i < 10 && !opened_; ++i)
    {
        opened_ = (ActiveWin32Api().OpenClipboard(owner) != FALSE);
        if (!opened_) ::Sleep(10);
    }
    if (!opened_)
    {
        DFLog(TAG, L"[ClipboardScope] OpenClipboard failed after retries. err=%lu", ::GetLastError());
    }
}

ClipboardScope::~ClipboardScope()
{
    if (opened_) ActiveWin32Api().CloseClipboard();
}

GlobalMem::GlobalMem(SIZE_T bytes) : h_(::GlobalAlloc(GMEM_MOVEABLE, bytes)) {}

GlobalMem::~GlobalMem() { if (h_) ::GlobalFree(h_); }

GlobalMem::GlobalMem(GlobalMem&& other) noexcept : h_(other.h_) { other.h_ = nullptr; }

GlobalMem& GlobalMem::operator=(GlobalMem&& other) noexcept
{
    if (this != &other)
    {
        if (h_) ::GlobalFree(h_);
        h_ = other.h_;
        other.h_ = nullptr;
    }
    return *this;
}

HGLOBAL GlobalMem::Release() { HGLOBAL h = h_; h_ = nullptr; return h; }

GlobalLockScope::GlobalLockScope(HGLOBAL h) : h_(h), p_(h ? ::GlobalLock(h) : nullptr) {}

GlobalLockScope::~GlobalLockScope() { if (p_) ::GlobalUnlock(h_); }

bool PutFormat(UINT format, GlobalMem& mem)
{
    if (format == 0 || !mem.IsValid()) return false;
    if (!ActiveWin32Api().SetClipboardData(format, mem.Get())) return false; // mem frees itself
    mem.Release(); // ownership moved to the system
    return true;
}

// =============================================================================
// Write options (F-11)
// =============================================================================

namespace
{
    bool PlaceExclusionDword(UINT format)
    {
        if (format == 0) return false;
        GlobalMem mem(sizeof(DWORD));
        if (!mem.IsValid()) return false;
        {
            GlobalLockScope lock(mem.Get());
            if (!lock.IsValid()) return false;
            *static_cast<DWORD*>(lock.Get()) = 0; // 0 = exclude
        }
        return PutFormat(format, mem);
    }
}

bool ApplyWriteOptions(DWORD options)
{
    bool ok = true;
    if (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY)
    {
        static const UINT fmt = ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
        if (!PlaceExclusionDword(fmt))
        {
            DLog(TAG, L"[ApplyWriteOptions] failed to place CanIncludeInClipboardHistory");
            ok = false;
        }
    }
    if (options & CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING)
    {
        static const UINT fmt = ::RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
        if (!PlaceExclusionDword(fmt))
        {
            DLog(TAG, L"[ApplyWriteOptions] failed to place CanUploadToCloudClipboard");
            ok = false;
        }
    }
    return ok;
}

namespace
{
    // Every defined CLIPBOARD_WRITE_OPTION_* bit; anything outside this mask
    // is rejected rather than silently ignored.
    constexpr DWORD kKnownWriteOptionBits = CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY | CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING;

    bool IsValidWriteOptions(DWORD options) { return (options & ~kKnownWriteOptionBits) == 0; }

    // Marker placement (history/roaming exclusion) is not best-effort for
    // CLIPBOARD_WRITE_OPTION_SENSITIVE: it is a privacy contract, so a failure
    // to place it must roll back the whole write rather than leave the main
    // payload exposed to history/cloud sync while reporting success.
    DWORD FinalizeWriteOptions(DWORD options)
    {
        if (ApplyWriteOptions(options)) return CLIPBOARD_ERROR_NONE;
        DLog(TAG, L"[FinalizeWriteOptions] marker placement failed; rolling back the write");
        if (!ActiveWin32Api().EmptyClipboard())
        {
            DFLog(TAG, L"[FinalizeWriteOptions] rollback failed. err=%lu", ::GetLastError());
            return CLIPBOARD_ERROR_PARTIAL_STATE;
        }
        return CLIPBOARD_ERROR_UNKNOWN;
    }
}

// =============================================================================
// Copy / paste
// =============================================================================

DWORD CopyPlainText(HWND owner, const std::wstring& text, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyPlainText] owner: %p, length: %zu, options: %lu", owner, text.size(), options);
    if (!owner || !IsValidWriteOptions(options)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    size_t bytes = 0;
    if (!CheckedAdd(text.size(), 1, bytes)) return CLIPBOARD_ERROR_INVALID_PARAMETER;
    if (!CheckedMul(bytes, sizeof(wchar_t), bytes)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;

    GlobalMem mem(bytes);
    if (!mem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(lock.Get(), text.c_str(), bytes);
    }
    if (!PutFormat(CF_UNICODETEXT, mem)) return CLIPBOARD_ERROR_UNKNOWN;

    return FinalizeWriteOptions(options);
}

DWORD PastePlainText(HWND owner, std::wstring& out)
{
    DFLog(TAG, L"[PastePlainText] owner: %p", owner);
    if (!ActiveWin32Api().IsClipboardFormatAvailable(CF_UNICODETEXT)) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    HANDLE hMem = ActiveWin32Api().GetClipboardData(CF_UNICODETEXT);
    if (!hMem) return CLIPBOARD_ERROR_EMPTY;

    const SIZE_T bytes = ::GlobalSize(hMem);
    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return CLIPBOARD_ERROR_INVALID_DATA;

    size_t chars = 0;
    if (!ClipboardFormats::ValidateUnicodeTextBlock(static_cast<const BYTE*>(lock.Get()), bytes, chars))
    {
        return CLIPBOARD_ERROR_INVALID_DATA;
    }
    out.assign(static_cast<const wchar_t*>(lock.Get()), chars);
    return CLIPBOARD_ERROR_NONE;
}

DWORD CopyHtml(HWND owner, const std::string& utf8Fragment, const std::wstring& plainFallback, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyHtml] owner: %p, fragmentBytes: %zu, options: %lu", owner, utf8Fragment.size(), options);
    if (!owner || !IsValidWriteOptions(options)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    const UINT cfHtml = ::RegisterClipboardFormatW(L"HTML Format");
    if (cfHtml == 0) return CLIPBOARD_ERROR_UNKNOWN;

    const std::string payload = ClipboardFormats::BuildCfHtml(utf8Fragment);
    if (payload.empty()) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    size_t htmlBytes = 0;
    if (!CheckedAdd(payload.size(), 1, htmlBytes)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    size_t textBytes = 0;
    if (!CheckedAdd(plainFallback.size(), 1, textBytes)) return CLIPBOARD_ERROR_INVALID_PARAMETER;
    if (!CheckedMul(textBytes, sizeof(wchar_t), textBytes)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    // Build and fill every payload BEFORE emptying the clipboard.
    GlobalMem htmlMem(htmlBytes);
    GlobalMem textMem(textBytes);
    if (!htmlMem.IsValid() || !textMem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    {
        GlobalLockScope l(htmlMem.Get());
        if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(l.Get(), payload.c_str(), htmlBytes);
    }
    {
        GlobalLockScope l(textMem.Get());
        if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(l.Get(), plainFallback.c_str(), textBytes);
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;

    if (!PutFormat(cfHtml, htmlMem)) return CLIPBOARD_ERROR_UNKNOWN;
    if (!plainFallback.empty())
    {
        if (!PutFormat(CF_UNICODETEXT, textMem)) return CLIPBOARD_ERROR_UNKNOWN;
    }

    return FinalizeWriteOptions(options);
}

DWORD PasteHtmlFragment(HWND owner, std::string& outUtf8)
{
    DFLog(TAG, L"[PasteHtmlFragment] owner: %p", owner);
    const UINT cfHtml = ::RegisterClipboardFormatW(L"HTML Format");
    if (cfHtml == 0 || !ActiveWin32Api().IsClipboardFormatAvailable(cfHtml)) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    HANDLE hMem = ActiveWin32Api().GetClipboardData(cfHtml);
    if (!hMem) return CLIPBOARD_ERROR_EMPTY;

    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes == 0) return CLIPBOARD_ERROR_INVALID_DATA;

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return CLIPBOARD_ERROR_INVALID_DATA;

    const auto* src = static_cast<const char*>(lock.Get());
    const size_t len = ::strnlen(src, bytes);
    if (len == bytes) return CLIPBOARD_ERROR_INVALID_DATA; // no NUL inside the block

    const std::string payload(src, len);
    ClipboardFormats::CfHtmlOffsets off{};
    if (!ClipboardFormats::ParseCfHtmlHeader(payload, off)) return CLIPBOARD_ERROR_INVALID_DATA;

    outUtf8.assign(payload, off.startFragment, off.endFragment - off.startFragment);
    return CLIPBOARD_ERROR_NONE;
}

DWORD CopyFiles(HWND owner, const std::vector<std::wstring>& paths, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyFiles] owner: %p, count: %zu, options: %lu", owner, paths.size(), options);
    if (!owner || !IsValidWriteOptions(options)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    std::vector<BYTE> block;
    if (!ClipboardFormats::BuildDropFiles(paths, block)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    GlobalMem mem(block.size());
    if (!mem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    {
        GlobalLockScope l(mem.Get());
        if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(l.Get(), block.data(), block.size());
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;
    if (!PutFormat(CF_HDROP, mem)) return CLIPBOARD_ERROR_UNKNOWN;

    return FinalizeWriteOptions(options);
}

DWORD PasteFiles(HWND owner, std::vector<std::wstring>& out)
{
    DFLog(TAG, L"[PasteFiles] owner: %p", owner);
    if (!ActiveWin32Api().IsClipboardFormatAvailable(CF_HDROP)) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    auto hDrop = static_cast<HDROP>(ActiveWin32Api().GetClipboardData(CF_HDROP));
    if (!hDrop) return CLIPBOARD_ERROR_EMPTY;

    const SIZE_T totalBytes = ::GlobalSize(hDrop);
    {
        GlobalLockScope lock(hDrop);
        if (!lock.IsValid()) return CLIPBOARD_ERROR_INVALID_DATA;
        if (!ClipboardFormats::ValidateDropFiles(static_cast<const BYTE*>(lock.Get()), totalBytes))
        {
            return CLIPBOARD_ERROR_INVALID_DATA;
        }
    }

    const UINT count = ::DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
    if (count == 0) return CLIPBOARD_ERROR_INVALID_DATA;

    out.clear();
    for (UINT i = 0; i < count; ++i)
    {
        const UINT len = ::DragQueryFileW(hDrop, i, nullptr, 0);
        if (len == 0) return CLIPBOARD_ERROR_INVALID_DATA;

        size_t withNul = 0;
        if (!CheckedAdd(static_cast<size_t>(len), 1, withNul)) return CLIPBOARD_ERROR_INVALID_DATA;
        UINT withNulU = 0;
        if (!CheckedToUInt(withNul, withNulU)) return CLIPBOARD_ERROR_INVALID_DATA;

        std::wstring path(withNul, L'\0');
        if (::DragQueryFileW(hDrop, i, path.data(), withNulU) == 0) return CLIPBOARD_ERROR_INVALID_DATA;
        path.resize(len);
        out.push_back(std::move(path));
    }
    return CLIPBOARD_ERROR_NONE;
}

DWORD CopyDib(HWND owner, const std::vector<BYTE>& dib, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyDib] owner: %p, size: %zu, options: %lu", owner, dib.size(), options);
    if (!owner || !IsValidWriteOptions(options) || !ClipboardFormats::ValidateDib(dib.data(), dib.size()))
    {
        return CLIPBOARD_ERROR_INVALID_PARAMETER;
    }

    GlobalMem mem(dib.size());
    if (!mem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    {
        GlobalLockScope l(mem.Get());
        if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(l.Get(), dib.data(), dib.size());
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;
    if (!PutFormat(CF_DIB, mem)) return CLIPBOARD_ERROR_UNKNOWN;

    return FinalizeWriteOptions(options);
}

DWORD PasteDib(HWND owner, std::vector<BYTE>& out)
{
    DFLog(TAG, L"[PasteDib] owner: %p", owner);
    if (!ActiveWin32Api().IsClipboardFormatAvailable(CF_DIB)) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    HANDLE hMem = ActiveWin32Api().GetClipboardData(CF_DIB);
    if (!hMem) return CLIPBOARD_ERROR_EMPTY;

    const SIZE_T bytes = ::GlobalSize(hMem);
    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return CLIPBOARD_ERROR_INVALID_DATA;

    const auto* src = static_cast<const BYTE*>(lock.Get());
    if (!ClipboardFormats::ValidateDib(src, bytes)) return CLIPBOARD_ERROR_INVALID_DATA;

    out.assign(src, src + bytes);
    return CLIPBOARD_ERROR_NONE;
}

DWORD CopyCustom(HWND owner, const std::wstring& formatName, const std::vector<BYTE>& blob, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyCustom] owner: %p, format: %ls, size: %zu, options: %lu",
          owner, formatName.c_str(), blob.size(), options);
    if (!owner || formatName.empty() || blob.empty() || !IsValidWriteOptions(options)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    const UINT fmt = ::RegisterClipboardFormatW(formatName.c_str());
    if (fmt == 0) return CLIPBOARD_ERROR_UNKNOWN;

    GlobalMem mem(blob.size());
    if (!mem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    {
        GlobalLockScope l(mem.Get());
        if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        ::memcpy(l.Get(), blob.data(), blob.size());
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;
    if (!PutFormat(fmt, mem)) return CLIPBOARD_ERROR_UNKNOWN;

    return FinalizeWriteOptions(options);
}

DWORD PasteCustom(HWND owner, const std::wstring& formatName, std::vector<BYTE>& out)
{
    DFLog(TAG, L"[PasteCustom] owner: %p, format: %ls", owner, formatName.c_str());
    if (formatName.empty()) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    const UINT fmt = ::RegisterClipboardFormatW(formatName.c_str());
    if (fmt == 0 || !ActiveWin32Api().IsClipboardFormatAvailable(fmt)) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    HANDLE hMem = ActiveWin32Api().GetClipboardData(fmt);
    if (!hMem) return CLIPBOARD_ERROR_EMPTY;

    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes == 0) return CLIPBOARD_ERROR_INVALID_DATA;

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return CLIPBOARD_ERROR_INVALID_DATA;

    const auto* src = static_cast<const BYTE*>(lock.Get());
    out.assign(src, src + bytes);
    return CLIPBOARD_ERROR_NONE;
}

DWORD CopyMultipleFormats(HWND owner, const std::vector<FormatPayload>& items, DWORD options, bool* outMutated)
{
    DFLog(TAG, L"[CopyMultipleFormats] owner: %p, count: %zu, options: %lu", owner, items.size(), options);
    if (!owner || items.empty() || !IsValidWriteOptions(options)) return CLIPBOARD_ERROR_INVALID_PARAMETER;

    // Build and fill every payload BEFORE emptying the clipboard, so a late
    // allocation failure cannot leave a half-populated clipboard behind.
    std::vector<GlobalMem> mems;
    mems.reserve(items.size());
    for (const auto& item : items)
    {
        if (item.format == 0 || item.data.empty()) return CLIPBOARD_ERROR_INVALID_PARAMETER;
        GlobalMem mem(item.data.size());
        if (!mem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        {
            GlobalLockScope l(mem.Get());
            if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
            ::memcpy(l.Get(), item.data.data(), item.data.size());
        }
        mems.push_back(std::move(mem));
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;

    bool allOk = true;
    for (size_t i = 0; i < items.size(); ++i)
    {
        if (!PutFormat(items[i].format, mems[i])) { allOk = false; break; }
    }

    if (!allOk)
    {
        // Best-effort rollback: EmptyClipboard can itself fail, leaving partial content.
        if (!ActiveWin32Api().EmptyClipboard())
        {
            DFLog(TAG, L"[CopyMultipleFormats] rollback failed. err=%lu", ::GetLastError());
            return CLIPBOARD_ERROR_PARTIAL_STATE;
        }
        return CLIPBOARD_ERROR_UNKNOWN;
    }

    return FinalizeWriteOptions(options);
}

// =============================================================================
// Inspection / clear
// =============================================================================

DWORD ListFormats(HWND owner, std::vector<UINT>& out)
{
    DFLog(TAG, L"[ListFormats] owner: %p", owner);

    ::SetLastError(ERROR_SUCCESS);
    const int known = ::CountClipboardFormats();
    if (known == 0)
    {
        if (::GetLastError() != ERROR_SUCCESS) return CLIPBOARD_ERROR_UNKNOWN;
        out.clear();
        return CLIPBOARD_ERROR_NONE;
    }

    size_t capacity = 0;
    if (!CheckedMul(static_cast<size_t>(known), 2, capacity)) return CLIPBOARD_ERROR_INVALID_DATA;
    if (!CheckedAdd(capacity, 8, capacity)) return CLIPBOARD_ERROR_INVALID_DATA;
    out.assign(capacity, 0);

    UINT capacityU = 0;
    if (!CheckedToUInt(out.size(), capacityU)) return CLIPBOARD_ERROR_INVALID_DATA;

    UINT count = 0;
    if (::GetUpdatedClipboardFormats(out.data(), capacityU, &count))
    {
        if (count > out.size()) return CLIPBOARD_ERROR_UNKNOWN;
        out.resize(count);
        return CLIPBOARD_ERROR_NONE;
    }

    // Fallback: enumerate explicitly (requires the clipboard to be open).
    out.clear();
    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;

    ::SetLastError(ERROR_SUCCESS);
    for (UINT fmt = ::EnumClipboardFormats(0); fmt != 0; fmt = (::SetLastError(ERROR_SUCCESS), ::EnumClipboardFormats(fmt)))
    {
        out.push_back(fmt);
    }
    if (::GetLastError() != ERROR_SUCCESS) { out.clear(); return CLIPBOARD_ERROR_UNKNOWN; }
    return CLIPBOARD_ERROR_NONE;
}

DWORD FormatName(UINT format, std::wstring& out)
{
    switch (format)
    {
    case CF_UNICODETEXT: out = L"CF_UNICODETEXT"; return CLIPBOARD_ERROR_NONE;
    case CF_TEXT:        out = L"CF_TEXT";        return CLIPBOARD_ERROR_NONE;
    case CF_HDROP:       out = L"CF_HDROP";       return CLIPBOARD_ERROR_NONE;
    case CF_DIB:         out = L"CF_DIB";         return CLIPBOARD_ERROR_NONE;
    case CF_DIBV5:       out = L"CF_DIBV5";       return CLIPBOARD_ERROR_NONE;
    case CF_BITMAP:      out = L"CF_BITMAP";      return CLIPBOARD_ERROR_NONE;
    default: break;
    }

    wchar_t buffer[256] = {};
    const int len = ::GetClipboardFormatNameW(format, buffer, ARRAYSIZE(buffer));
    if (len <= 0) return CLIPBOARD_ERROR_FORMAT_UNAVAILABLE;
    out.assign(buffer, static_cast<size_t>(len));
    return CLIPBOARD_ERROR_NONE;
}

int PickPreferredFormat()
{
    UINT priority[] = { CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP };
    return ::GetPriorityClipboardFormat(priority, ARRAYSIZE(priority));
}

DWORD ClearClipboard(HWND owner)
{
    DFLog(TAG, L"[ClearClipboard] owner: %p", owner);
    if (!owner) return CLIPBOARD_ERROR_INVALID_PARAMETER;
    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    return ActiveWin32Api().EmptyClipboard() ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN;
}

bool HasFormat(UINT format)
{
    return ActiveWin32Api().IsClipboardFormatAvailable(format) != FALSE;
}

// =============================================================================
// F-10: Deferred rendering
// =============================================================================

DWORD DeferredClipboard::Reserve(HWND owner, std::map<UINT, Renderer> renderers, bool* outMutated)
{
    DFLog(TAG, L"[DeferredClipboard::Reserve] owner: %p, count: %zu", owner, renderers.size());
    if (!owner || renderers.empty()) return CLIPBOARD_ERROR_INVALID_PARAMETER;
    for (const auto& [fmt, fn] : renderers)
    {
        if (fmt == 0 || !fn) return CLIPBOARD_ERROR_INVALID_PARAMETER;
    }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;
    if (outMutated) *outMutated = true;

    // Store the table BEFORE placing anything: a WM_RENDERFORMAT can only arrive
    // for a format we already reserved, and we must be able to answer it.
    owner_ = owner;
    renderers_ = std::move(renderers);
    rendered_.clear();

    for (const auto& [fmt, fn] : renderers_)
    {
        ::SetLastError(ERROR_SUCCESS);
        ActiveWin32Api().SetClipboardData(fmt, nullptr);
        const bool ok = (::GetLastError() == ERROR_SUCCESS) &&
                        (ActiveWin32Api().GetClipboardOwner() == owner) &&
                        (ActiveWin32Api().IsClipboardFormatAvailable(fmt) != FALSE);
        if (!ok)
        {
            if (!ActiveWin32Api().EmptyClipboard())
            {
                DFLog(TAG, L"[DeferredClipboard::Reserve] rollback failed. err=%lu", ::GetLastError());
                partial_ = true;
                return CLIPBOARD_ERROR_PARTIAL_STATE;
            }
            Clear();
            return CLIPBOARD_ERROR_UNKNOWN;
        }
    }
    partial_ = false;
    return CLIPBOARD_ERROR_NONE;
}

DWORD DeferredClipboard::RecoverFromPartialState(bool* outMutated)
{
    DFLog(TAG, L"[DeferredClipboard::RecoverFromPartialState]");
    if (!partial_) return CLIPBOARD_ERROR_NONE;
    if (!owner_) { Clear(); return CLIPBOARD_ERROR_NONE; }

    ClipboardScope scope(owner_);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (ActiveWin32Api().GetClipboardOwner() != owner_)
    {
        Clear();
        return CLIPBOARD_ERROR_NONE;
    }
    if (!ActiveWin32Api().EmptyClipboard()) return CLIPBOARD_ERROR_PARTIAL_STATE;
    if (outMutated) *outMutated = true;
    Clear();
    return CLIPBOARD_ERROR_NONE;
}

void DeferredClipboard::OnRenderFormat(UINT format)
{
    DFLog(TAG, L"[DeferredClipboard::OnRenderFormat] format: %u", format);
    auto it = renderers_.find(format);
    if (it == renderers_.end()) return; // not ours: never place data for it

    GlobalMem mem = it->second();
    if (!mem.IsValid())
    {
        DFLog(TAG, L"[DeferredClipboard::OnRenderFormat] renderer failed. fmt=%u", format);
        return;
    }
    if (!ActiveWin32Api().SetClipboardData(format, mem.Get()))
    {
        DFLog(TAG, L"[DeferredClipboard::OnRenderFormat] SetClipboardData failed. fmt=%u err=%lu", format, ::GetLastError());
        return;
    }
    mem.Release();
    rendered_.insert(format);
}

void DeferredClipboard::OnRenderAllFormats(HWND hwnd)
{
    DFLog(TAG, L"[DeferredClipboard::OnRenderAllFormats] hwnd: %p", hwnd);
    if (!ActiveWin32Api().OpenClipboard(hwnd))
    {
        DFLog(TAG, L"[DeferredClipboard::OnRenderAllFormats] open failed. err=%lu", ::GetLastError());
        return;
    }
    if (ActiveWin32Api().GetClipboardOwner() != hwnd)
    {
        DLog(TAG, L"[DeferredClipboard::OnRenderAllFormats] ownership lost; not overwriting");
    }
    else
    {
        for (const auto& [fmt, fn] : renderers_)
        {
            if (rendered_.count(fmt)) continue;
            GlobalMem mem = fn();
            if (!mem.IsValid())
            {
                DFLog(TAG, L"[DeferredClipboard::OnRenderAllFormats] renderer failed. fmt=%u", fmt);
                continue;
            }
            if (!ActiveWin32Api().SetClipboardData(fmt, mem.Get()))
            {
                DFLog(TAG, L"[DeferredClipboard::OnRenderAllFormats] set failed. fmt=%u err=%lu", fmt, ::GetLastError());
                continue;
            }
            mem.Release();
            rendered_.insert(fmt);
        }
    }
    ActiveWin32Api().CloseClipboard();
}

void DeferredClipboard::OnDestroyClipboard()
{
    DLog(TAG, L"[DeferredClipboard::OnDestroyClipboard]");
    Clear();
}

void DeferredClipboard::Clear()
{
    renderers_.clear();
    rendered_.clear();
    owner_ = nullptr;
    partial_ = false;
}

// =============================================================================
// F-09: Change monitoring
// =============================================================================

bool ClipboardWatcher::Start(HWND hwnd)
{
    DFLog(TAG, L"[ClipboardWatcher::Start] hwnd: %p", hwnd);
    if (!hwnd) return false;
    if (registered_) return true;
    if (!ActiveWin32Api().AddClipboardFormatListener(hwnd))
    {
        DFLog(TAG, L"[ClipboardWatcher::Start] failed. err=%lu", ::GetLastError());
        return false;
    }
    hwnd_ = hwnd;
    registered_ = true;
    lastProcessedSeq_ = ActiveWin32Api().GetClipboardSequenceNumber();
    return true;
}

bool ClipboardWatcher::Stop()
{
    DLog(TAG, L"[ClipboardWatcher::Stop]");
    if (!registered_) return true;
    if (!ActiveWin32Api().RemoveClipboardFormatListener(hwnd_))
    {
        DFLog(TAG, L"[ClipboardWatcher::Stop] failed. err=%lu", ::GetLastError());
        return false; // stay registered: retryable
    }
    registered_ = false;
    hwnd_ = nullptr;
    return true;
}

ClipboardWatcher::SelfWriteTransaction::SelfWriteTransaction(ClipboardWatcher& owner)
    : owner_(&owner), lock_(owner.selfWriteMutex_)
{
}

void ClipboardWatcher::SelfWriteTransaction::NoteMutation()
{
    if (owner_) owner_->NoteSelfWriteLocked();
}

ClipboardWatcher::SelfWriteTransaction ClipboardWatcher::BeginSelfWrite()
{
    return SelfWriteTransaction(*this);
}

void ClipboardWatcher::NoteSelfWriteLocked()
{
    selfWriteSeq_.insert(ActiveWin32Api().GetClipboardSequenceNumber());
}

void ClipboardWatcher::NoteSelfWrite()
{
    std::lock_guard<std::mutex> lock(selfWriteMutex_);
    NoteSelfWriteLocked();
}

bool ClipboardWatcher::TakeSelfWriteLocked(DWORD seq)
{
    const bool found = selfWriteSeq_.erase(seq) > 0;
    selfWriteSeq_.clear(); // this sequence is now the newest processed one
    return found;
}

bool ClipboardWatcher::TakeSelfWrite(DWORD seq)
{
    std::lock_guard<std::mutex> lock(selfWriteMutex_);
    return TakeSelfWriteLocked(seq);
}

void ClipboardWatcher::OnClipboardUpdate()
{
    bool notify = false;
    {
        // The same mutex is held from the beginning of every toolkit write
        // until its resulting sequence is recorded. A UI update that races a
        // worker write therefore cannot classify the new sequence too early.
        std::lock_guard<std::mutex> lock(selfWriteMutex_);
        const DWORD seq = ActiveWin32Api().GetClipboardSequenceNumber();
        if (seq == lastProcessedSeq_) return; // coalesced/duplicate message
        lastProcessedSeq_ = seq;
        notify = !TakeSelfWriteLocked(seq);
    }

    if (notify && onChanged) onChanged();
}
