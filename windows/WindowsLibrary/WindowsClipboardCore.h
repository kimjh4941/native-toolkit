/**
 * @file WindowsClipboardCore.h
 * @brief Win32 clipboard operations (synchronous, RAII-guarded).
 * @details
 *  Thin, mechanical wrapper over the Win32 clipboard API. Every entry point
 *  opens the clipboard, performs one operation, and closes it. Ownership of
 *  clipboard-bound memory (GlobalAlloc handles) is tracked with RAII so a
 *  handle is freed on every failure path and released to the system exactly
 *  once, on success.
 */
#pragma once

#include <windows.h>
#include <string>
#include <vector>
#include <functional>
#include <map>
#include <set>

// ---------------------------------------------------------------------------
// IClipboardWin32Api - thin function table over the Win32 clipboard API.
// Production code uses DefaultWin32Api(); tests inject a stub that can fail
// on demand (SetWin32ApiForTest) to exercise otherwise-unreachable error paths.
// ---------------------------------------------------------------------------
class IClipboardWin32Api
{
public:
    virtual ~IClipboardWin32Api() = default;
    virtual BOOL   OpenClipboard(HWND owner) = 0;
    virtual BOOL   CloseClipboard() = 0;
    virtual BOOL   EmptyClipboard() = 0;
    virtual HANDLE SetClipboardData(UINT format, HANDLE hMem) = 0;
    virtual HANDLE GetClipboardData(UINT format) = 0;
    virtual HWND   GetClipboardOwner() = 0;
    virtual BOOL   IsClipboardFormatAvailable(UINT format) = 0;
    virtual BOOL   AddClipboardFormatListener(HWND hwnd) = 0;
    virtual BOOL   RemoveClipboardFormatListener(HWND hwnd) = 0;
    virtual DWORD  GetClipboardSequenceNumber() = 0;
};

IClipboardWin32Api& DefaultWin32Api();
// Test-only injection point. Pass nullptr to restore the default (real) API.
void SetWin32ApiForTest(IClipboardWin32Api* api);

// Currently active API (DefaultWin32Api() unless overridden for a test).
IClipboardWin32Api& ActiveWin32Api();

// ---------------------------------------------------------------------------
// RAII helpers
// ---------------------------------------------------------------------------

// Opens the clipboard with a bounded retry: another process may hold it briefly.
class ClipboardScope
{
public:
    explicit ClipboardScope(HWND owner);
    ~ClipboardScope();
    ClipboardScope(const ClipboardScope&) = delete;
    ClipboardScope& operator=(const ClipboardScope&) = delete;
    bool IsOpen() const { return opened_; }

private:
    bool opened_ = false;
};

// Owns an HGLOBAL until it is handed to the clipboard. Release() is called only
// after SetClipboardData succeeds, because ownership then moves to the system.
class GlobalMem
{
public:
    GlobalMem() = default; // invalid (IsValid() == false); does not call GlobalAlloc
    explicit GlobalMem(SIZE_T bytes);
    ~GlobalMem();
    GlobalMem(GlobalMem&& other) noexcept;
    GlobalMem& operator=(GlobalMem&& other) noexcept;
    GlobalMem(const GlobalMem&) = delete;
    GlobalMem& operator=(const GlobalMem&) = delete;

    bool IsValid() const { return h_ != nullptr; }
    HGLOBAL Get() const { return h_; }
    HGLOBAL Release();

private:
    HGLOBAL h_ = nullptr;
};

class GlobalLockScope
{
public:
    explicit GlobalLockScope(HGLOBAL h);
    ~GlobalLockScope();
    GlobalLockScope(const GlobalLockScope&) = delete;
    GlobalLockScope& operator=(const GlobalLockScope&) = delete;
    bool IsValid() const { return p_ != nullptr; }
    void* Get() const { return p_; }

private:
    HGLOBAL h_;
    void* p_;
};

// Places one format and transfers ownership only on success.
bool PutFormat(UINT format, GlobalMem& mem);

// ---------------------------------------------------------------------------
// Copy / paste
// ---------------------------------------------------------------------------

// outMutated (nullable): set to true as soon as the OS clipboard is actually
// changed (EmptyClipboard succeeds), independent of the function's own return
// code. A caller-side self-write suppression must key off this, not off
// success, because a write that empties the clipboard and then fails to place
// a format (or to place a write-option marker) still changes real clipboard
// content and would otherwise be misreported to the caller as an external
// change (H4, 2026-07-29 v2 review).
DWORD CopyPlainText(HWND owner, const std::wstring& text, DWORD options, bool* outMutated = nullptr);
DWORD PastePlainText(HWND owner, std::wstring& out);

DWORD CopyHtml(HWND owner, const std::string& utf8Fragment, const std::wstring& plainFallback, DWORD options, bool* outMutated = nullptr);
DWORD PasteHtmlFragment(HWND owner, std::string& outUtf8);

DWORD CopyFiles(HWND owner, const std::vector<std::wstring>& paths, DWORD options, bool* outMutated = nullptr);
DWORD PasteFiles(HWND owner, std::vector<std::wstring>& out);

DWORD CopyDib(HWND owner, const std::vector<BYTE>& dib, DWORD options, bool* outMutated = nullptr);
DWORD PasteDib(HWND owner, std::vector<BYTE>& out);

DWORD CopyCustom(HWND owner, const std::wstring& formatName, const std::vector<BYTE>& blob, DWORD options, bool* outMutated = nullptr);
DWORD PasteCustom(HWND owner, const std::wstring& formatName, std::vector<BYTE>& out);

// Pre-encoded payload for one clipboard format, in placement order (richest first).
struct FormatPayload
{
    UINT format = 0;
    std::vector<BYTE> data;
};
DWORD CopyMultipleFormats(HWND owner, const std::vector<FormatPayload>& items, DWORD options, bool* outMutated = nullptr);

// ---------------------------------------------------------------------------
// Inspection / clear
// ---------------------------------------------------------------------------

DWORD ListFormats(HWND owner, std::vector<UINT>& out);
DWORD FormatName(UINT format, std::wstring& out);
int   PickPreferredFormat();
DWORD ClearClipboard(HWND owner);
bool  HasFormat(UINT format);

// Places the CanIncludeInClipboardHistory / CanUploadToCloudClipboard registered
// formats. Must be called inside the same Open/Empty/Close sequence as the data
// they apply to (i.e. from inside one of the Copy* functions above).
bool ApplyWriteOptions(DWORD options);

// ---------------------------------------------------------------------------
// F-10: Deferred rendering
// ---------------------------------------------------------------------------

class DeferredClipboard
{
public:
    using Renderer = std::function<GlobalMem()>; // returns an owned HGLOBAL, or invalid on failure

    DWORD Reserve(HWND owner, std::map<UINT, Renderer> renderers, bool* outMutated = nullptr);
    DWORD RecoverFromPartialState(bool* outMutated = nullptr);
    bool  IsPartial() const { return partial_; }

    void OnRenderFormat(UINT format);       // WM_RENDERFORMAT handler; must not call OpenClipboard
    void OnRenderAllFormats(HWND hwnd);     // WM_RENDERALLFORMATS handler
    void OnDestroyClipboard();              // WM_DESTROYCLIPBOARD handler

private:
    void Clear();

    HWND owner_ = nullptr;
    bool partial_ = false;
    std::map<UINT, Renderer> renderers_;
    std::set<UINT> rendered_;
};

// ---------------------------------------------------------------------------
// F-09: Change monitoring
// ---------------------------------------------------------------------------

#include <mutex>
#include <unordered_set>

class ClipboardWatcher
{
public:
    class SelfWriteTransaction
    {
    public:
        SelfWriteTransaction(SelfWriteTransaction&&) noexcept = default;
        SelfWriteTransaction& operator=(SelfWriteTransaction&&) noexcept = default;
        SelfWriteTransaction(const SelfWriteTransaction&) = delete;
        SelfWriteTransaction& operator=(const SelfWriteTransaction&) = delete;

        // Records the current clipboard sequence while the transaction still
        // excludes WM_CLIPBOARDUPDATE classification.
        void NoteMutation();

    private:
        friend class ClipboardWatcher;
        explicit SelfWriteTransaction(ClipboardWatcher& owner);

        ClipboardWatcher* owner_ = nullptr;
        std::unique_lock<std::mutex> lock_;
    };

    bool Start(HWND hwnd);
    bool Stop();
    bool IsRegistered() const { return registered_; }

    SelfWriteTransaction BeginSelfWrite();
    void NoteSelfWrite();               // any thread: record current sequence number
    bool TakeSelfWrite(DWORD seq);      // UI thread: true if seq was a self-write
    void OnClipboardUpdate();           // UI thread: WM_CLIPBOARDUPDATE; returns via IsSelfWrite check

    // Set by the owner to be notified on a genuine (non-self) content change.
    std::function<void()> onChanged;

private:
    void NoteSelfWriteLocked();
    bool TakeSelfWriteLocked(DWORD seq);

    // UI-thread-only state
    HWND  hwnd_ = nullptr;
    bool  registered_ = false;
    DWORD lastProcessedSeq_ = 0;

    // Cross-thread state
    mutable std::mutex        selfWriteMutex_;
    std::unordered_set<DWORD> selfWriteSeq_;
};
