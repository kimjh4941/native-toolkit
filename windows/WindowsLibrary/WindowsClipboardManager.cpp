#include "pch.h"
#include "WindowsClipboardManagerInternal.h"
#include "WindowsClipboardWindow.h"
#include "WindowsClipboardHistoryWinRt.h"
#include "WindowsClipboardFormats.h"
#include "WindowsClipboardDeferredProvider.h"
#include "common.h"
#include <map>
#include <set>
#include <type_traits>

using namespace winrt::Windows::Data::Json;

static const wchar_t* TAG = L"WindowsClipboardManager";

namespace
{
    void SetErr(DWORD* pError, DWORD value) { if (pError) *pError = value; }

    UINT ResolveFormatId(const std::wstring& name)
    {
        if (name == L"CF_UNICODETEXT") return CF_UNICODETEXT;
        if (name == L"CF_TEXT")        return CF_TEXT;
        if (name == L"CF_HDROP")       return CF_HDROP;
        if (name == L"CF_DIB")         return CF_DIB;
        if (name == L"CF_DIBV5")       return CF_DIBV5;
        if (name == L"CF_BITMAP")      return CF_BITMAP;
        return ::RegisterClipboardFormatW(name.c_str());
    }

    bool EncodeAnsiText(const std::wstring& text, std::vector<BYTE>& out)
    {
        const int needed = ::WideCharToMultiByte(CP_ACP, 0, text.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (needed <= 0) return false;
        out.resize(static_cast<size_t>(needed));
        return ::WideCharToMultiByte(CP_ACP, 0, text.c_str(), -1,
                                     reinterpret_cast<char*>(out.data()), needed,
                                     nullptr, nullptr) == needed;
    }

    DWORD WriteStringToBuffer(const std::wstring& value, wchar_t* buffer, DWORD bufferSize, DWORD* pError)
    {
        size_t neededSize = 0;
        if (!ClipboardFormats::CheckedAdd(value.size(), 1, neededSize))
        {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
            return 0;
        }
        UINT needed = 0;
        if (!ClipboardFormats::CheckedToUInt(neededSize, needed))
        {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
            return 0;
        }
        if (!buffer || bufferSize < needed)
        {
            SetErr(pError, CLIPBOARD_ERROR_BUFFER_TOO_SMALL);
            return needed;
        }
        ::wcscpy_s(buffer, bufferSize, value.c_str());
        SetErr(pError, CLIPBOARD_ERROR_NONE);
        return needed;
    }

    DWORD WriteBytesToBuffer(const std::vector<BYTE>& data, BYTE* buffer, DWORD bufferSize, DWORD* pError)
    {
        UINT needed = 0;
        if (!ClipboardFormats::CheckedToUInt(data.size(), needed))
        {
            SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
            return 0;
        }
        if (!buffer || bufferSize < needed)
        {
            SetErr(pError, CLIPBOARD_ERROR_BUFFER_TOO_SMALL);
            return needed;
        }
        if (needed > 0) ::memcpy(buffer, data.data(), needed);
        SetErr(pError, CLIPBOARD_ERROR_NONE);
        return needed;
    }
}

// =============================================================================
// ClipboardManager
// =============================================================================

ClipboardManager& ClipboardManager::GetInstance()
{
    static ClipboardManager instance;
    return instance;
}

ClipboardManager::ClipboardManager()
{
    DLog(TAG, L"[ClipboardManager] constructed");
    // The manager is not initialized yet, so admission starts closed. Init
    // reopens it only after all fallible setup has succeeded.
    lifecycle_.CloseAndReserveDrainWork(0);
}

bool ClipboardManager::AcquireSyncLease(DWORD* pError, std::optional<ClipboardLifecycle::Lease>& outLease, HWND& outHwnd) const
{
    // initialized_ check + lifecycle entry + dispatchHwnd_ snapshot must be one
    // atomic step under initMutex_: Uninit() flips all three under the same
    // mutex, and without this lock a caller could observe initialized_ == true
    // an instant before Uninit tears everything down, then successfully enter
    // a lifecycle that Uninit is about to (or already did) close/reopen (H1).
    std::lock_guard<std::mutex> lock(initMutex_);
    if (!initialized_) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return false; }
    outLease = lifecycle_.TryEnter();
    if (!outLease) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return false; }
    outHwnd = dispatchHwnd_;
    return true;
}

bool ClipboardManager::AcquireHistoryCoordinator(DWORD* pError, std::shared_ptr<ClipboardHistoryCoordinator>& outCoordinator) const
{
    std::lock_guard<std::mutex> lock(initMutex_);
    if (!initialized_) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return false; }
    outCoordinator = coordinator_; // local shared_ptr keeps it alive even if Uninit resets the member concurrently
    return true;
}

bool ClipboardManager::AcquireOwnerContext(
    DWORD* pError,
    std::optional<ClipboardLifecycle::Lease>& outLease,
    HWND& outHwnd,
    std::shared_ptr<ClipboardHistoryCoordinator>& outCoordinator) const
{
    DLog(TAG, L"[AcquireOwnerContext]");
    std::lock_guard<std::mutex> lock(initMutex_);
    if (!initialized_) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return false; }
    if (::GetCurrentThreadId() != ownerThreadId_)
    {
        SetErr(pError, CLIPBOARD_ERROR_WRONG_THREAD);
        return false;
    }
    outLease = lifecycle_.TryEnter();
    if (!outLease) { SetErr(pError, CLIPBOARD_ERROR_NOT_INITIALIZED); return false; }
    outHwnd = dispatchHwnd_;
    outCoordinator = coordinator_;
    return true;
}

void ClipboardManager::SetHistoryBackendFactoryForTest(std::unique_ptr<IClipboardHistoryBackend> (*factory)())
{
    testBackendFactory_ = factory;
}

void ClipboardManager::InitClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError)
{
    DLog(TAG, L"[InitClipboardManager]");
    std::lock_guard<std::mutex> lock(initMutex_);

    const DWORD callingThread = ::GetCurrentThreadId();
    if (initialized_)
    {
        if (callingThread != ownerThreadId_) { SetErr(pError, CLIPBOARD_ERROR_WRONG_THREAD); return; }
        SetErr(pError, CLIPBOARD_ERROR_NONE); // idempotent success from the owner thread
        return;
    }

    APTTYPE aptType = APTTYPE_MTA;
    APTTYPEQUALIFIER aptQualifier;
    const HRESULT hr = ::CoGetApartmentType(&aptType, &aptQualifier);
    if (FAILED(hr) || (aptType != APTTYPE_STA && aptType != APTTYPE_MAINSTA))
    {
        DFLog(TAG, L"[InitClipboardManager] calling thread is not an initialized STA. hr=0x%08lx aptType=%d",
              hr, static_cast<int>(aptType));
        SetErr(pError, CLIPBOARD_ERROR_WRONG_APARTMENT);
        return;
    }

    HWND hwnd = WindowsClipboardWindow::Create();
    if (!hwnd) { SetErr(pError, CLIPBOARD_ERROR_UNKNOWN); return; }

    // Owns the HWND until commit: any early return below (construction
    // throwing, or the watcher being required but failing to register)
    // destroys it instead of leaking it (H2).
    struct HwndGuard
    {
        HWND hwnd;
        bool armed = true;
        ~HwndGuard() { if (armed && hwnd) WindowsClipboardWindow::Destroy(hwnd); }
    } hwndGuard{ hwnd };

    try
    {
        std::unique_ptr<IClipboardHistoryBackend> backend = testBackendFactory_
            ? testBackendFactory_()
            : MakeClipboardHistoryWinRtBackend();
        coordinator_ = std::make_shared<ClipboardHistoryCoordinator>(std::move(backend), lifecycle_);
        coordinator_->AttachDispatchWindow(hwnd);
    }
    catch (const std::bad_alloc&)
    {
        coordinator_.reset();
        SetErr(pError, CLIPBOARD_ERROR_OUT_OF_MEMORY);
        return;
    }
    catch (...)
    {
        coordinator_.reset();
        DLog(TAG, L"[InitClipboardManager] backend/coordinator construction threw");
        SetErr(pError, CLIPBOARD_ERROR_UNKNOWN);
        return;
    }

    watcher_.onChanged = [this]()
    {
        if (onChanged_)
        {
            try { onChanged_(); }
            catch (...) { DLog(TAG, L"[OnClipboardUpdate] callback threw"); }
        }
    };
    if (!watcher_.Start(hwnd))
    {
        if (onChanged)
        {
            // The caller explicitly asked to be notified of changes; silently
            // continuing without that capability would hide a real failure (M5).
            DLog(TAG, L"[InitClipboardManager] ClipboardWatcher::Start failed with onChanged set; aborting init");
            coordinator_->DetachDispatchWindow();
            coordinator_.reset();
            SetErr(pError, CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED);
            return;
        }
        // No caller is listening for change notifications, so continuing
        // without that capability is a reasonable degrade.
        DLog(TAG, L"[InitClipboardManager] ClipboardWatcher::Start failed; continuing without change notifications");
    }

    // Commit only after every fallible setup step has succeeded. In
    // particular, a failed re-init after Uninit must leave the lifecycle
    // closed while initialized_ remains false.
    lifecycle_.Reopen();
    dispatchHwnd_ = hwnd;
    ownerThreadId_ = callingThread;
    onChanged_ = onChanged;
    initialized_ = true;
    hwndGuard.armed = false; // ownership transferred to the manager
    SetErr(pError, CLIPBOARD_ERROR_NONE);
}

BOOL ClipboardManager::Uninit(DWORD* pError)
{
    DLog(TAG, L"[Uninit]");
    std::lock_guard<std::mutex> lock(initMutex_);

    if (!initialized_) { SetErr(pError, CLIPBOARD_ERROR_NONE); return TRUE; }
    if (::GetCurrentThreadId() != ownerThreadId_) { SetErr(pError, CLIPBOARD_ERROR_WRONG_THREAD); return FALSE; }

    const bool drained = coordinator_ ? coordinator_->CloseAndDrain() : true;
    const bool watcherStopped = watcher_.Stop();
    const bool historyStopped = coordinator_ ? coordinator_->StopWatch() : true;

    if (!watcherStopped) { SetErr(pError, CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED); return FALSE; }
    if (!historyStopped) { SetErr(pError, CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED); return FALSE; }
    if (!drained) { SetErr(pError, CLIPBOARD_ERROR_CANCELED); return FALSE; }
    if (!lifecycle_.CanDestroy()) { SetErr(pError, CLIPBOARD_ERROR_BUSY); return FALSE; }
    if (coordinator_ && !coordinator_->CanDestroy()) { SetErr(pError, CLIPBOARD_ERROR_BUSY); return FALSE; }

    if (deferred_.IsPartial())
    {
        auto selfWrite = watcher_.BeginSelfWrite();
        bool mutated = false;
        const DWORD recErr = deferred_.RecoverFromPartialState(&mutated);
        if (mutated) selfWrite.NoteMutation();
        if (recErr != CLIPBOARD_ERROR_NONE) { SetErr(pError, recErr); return FALSE; }
    }

    if (coordinator_) coordinator_->DetachDispatchWindow();
    WindowsClipboardWindow::Destroy(dispatchHwnd_);
    dispatchHwnd_ = nullptr;
    coordinator_.reset();
    onChanged_ = nullptr;
    initialized_ = false;
    ownerThreadId_ = 0;
    // Deliberately NOT lifecycle_.Reopen() here: the lifecycle stays closed
    // until the next InitClipboardManager() commits (see there). Reopening it
    // on this path would create a window, between this Uninit and the next
    // real Init, where a concurrent any-thread caller's TryEnter() could
    // succeed against a manager that is not initialized (H1).

    SetErr(pError, CLIPBOARD_ERROR_NONE);
    return TRUE;
}

BOOL ClipboardManager::CanDestroy(DWORD* pError) const
{
    // Locked for the same reason as AcquireSyncLease: initialized_/coordinator_
    // must be read as a consistent snapshot relative to Uninit()'s teardown.
    std::lock_guard<std::mutex> lock(initMutex_);
    SetErr(pError, CLIPBOARD_ERROR_NONE);
    if (!initialized_) return TRUE;
    const bool coordOk = coordinator_ ? coordinator_->CanDestroy() : true;
    // A failed RemoveClipboardFormatListener in Uninit() leaves the watcher
    // registered; that must also block "safe to destroy" (v2 review H1).
    return (lifecycle_.CanDestroy() && coordOk && !watcher_.IsRegistered()) ? TRUE : FALSE;
}

void ClipboardManager::SetHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                           ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                           ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                           DWORD* pError)
{
    DLog(TAG, L"[SetHistoryCallbacks]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    std::shared_ptr<ClipboardHistoryCoordinator> coordinator;
    if (!AcquireOwnerContext(pError, lease, hwnd, coordinator)) return;
    const DWORD err = coordinator->SetHistoryCallbacks(onHistoryChanged, onHistoryEnabledChanged, onRoamingEnabledChanged);
    SetErr(pError, err);
}

// -----------------------------------------------------------------------
// Win32 synchronous core
// -----------------------------------------------------------------------

void ClipboardManager::CopyPlainText(const wchar_t* text, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyPlainText] options: %lu", options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!text) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyPlainText(hwnd, text, options, &mutated);
    SetErr(pError, err);
    // Keyed on whether the OS clipboard actually changed, not on success: a
    // write that empties the clipboard and then fails partway through still
    // changed real content and must not be reported to onChanged as external (H4).
    if (mutated) selfWrite.NoteMutation();
}

DWORD ClipboardManager::PastePlainText(wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[PastePlainText]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    std::wstring text;
    const DWORD err = ::PastePlainText(hwnd, text);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }
    return WriteStringToBuffer(text, buffer, bufferSize, pError);
}

void ClipboardManager::CopyHtml(const wchar_t* html, const wchar_t* plainText, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyHtml] options: %lu", options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!html) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    const std::string utf8 = ClipboardFormats::WideToUtf8(html);
    const std::wstring fallback = plainText ? plainText : L"";
    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyHtml(hwnd, utf8, fallback, options, &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

DWORD ClipboardManager::PasteHtml(wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[PasteHtml]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    std::string utf8;
    const DWORD err = ::PasteHtmlFragment(hwnd, utf8);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }
    return WriteStringToBuffer(ClipboardFormats::Utf8ToWide(utf8), buffer, bufferSize, pError);
}

void ClipboardManager::CopyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyFiles] options: %lu", options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!pathsJson) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::vector<std::wstring> paths;
    try
    {
        JsonArray arr = JsonArray::Parse(pathsJson);
        for (auto const& v : arr) paths.emplace_back(v.GetString());
    }
    // std::bad_alloc must reach SafeBridgeCall as OUT_OF_MEMORY, not be folded
    // into "the input was malformed" (M3): only a parse/type error is INVALID_PARAMETER.
    catch (const std::bad_alloc&) { throw; }
    catch (...) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyFiles(hwnd, paths, options, &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

DWORD ClipboardManager::PasteFiles(wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[PasteFiles]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    std::vector<std::wstring> paths;
    const DWORD err = ::PasteFiles(hwnd, paths);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }

    JsonArray arr;
    for (auto const& p : paths) arr.Append(JsonValue::CreateStringValue(p));
    return WriteStringToBuffer(std::wstring(arr.Stringify()), buffer, bufferSize, pError);
}

void ClipboardManager::CopyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyImage] size: %lu, options: %lu", dibSize, options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!dib || dibSize == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::vector<BYTE> blob(dib, dib + dibSize);
    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyDib(hwnd, blob, options, &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

DWORD ClipboardManager::PasteImage(BYTE* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[PasteImage]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    std::vector<BYTE> data;
    const DWORD err = ::PasteDib(hwnd, data);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }
    return WriteBytesToBuffer(data, buffer, bufferSize, pError);
}

void ClipboardManager::CopyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyCustomFormat] format: %ls, size: %lu, options: %lu", formatName ? formatName : L"", size, options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!formatName || !data || size == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::vector<BYTE> blob(data, data + size);
    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyCustom(hwnd, formatName, blob, options, &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

DWORD ClipboardManager::PasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD bufferSize, DWORD* pError)
{
    DFLog(TAG, L"[PasteCustomFormat] format: %ls", formatName ? formatName : L"");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;
    if (!formatName) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }

    std::vector<BYTE> data;
    const DWORD err = ::PasteCustom(hwnd, formatName, data);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }
    return WriteBytesToBuffer(data, buffer, bufferSize, pError);
}

void ClipboardManager::CopyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError)
{
    DFLog(TAG, L"[CopyMultipleFormats] options: %lu", options);
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    if (!itemsJson) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::vector<FormatPayload> items;
    std::set<UINT> seenFormats;
    try
    {
        JsonArray arr = JsonArray::Parse(itemsJson);
        for (auto const& v : arr)
        {
            JsonObject obj = v.GetObject();
            const std::wstring formatName(obj.HasKey(L"format") ? obj.GetNamedString(L"format") : L"");
            if (formatName.empty()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
            const UINT fmt = ResolveFormatId(formatName);
            if (fmt == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
            if (!seenFormats.insert(fmt).second) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; } // M1: duplicate format

            const bool hasText = obj.HasKey(L"text");
            const bool hasHtml = obj.HasKey(L"html");
            const bool hasBase64 = obj.HasKey(L"base64");
            const int payloadCount = (hasText ? 1 : 0) + (hasHtml ? 1 : 0) + (hasBase64 ? 1 : 0);
            if (payloadCount != 1) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

            const auto payloadKind = hasText
                ? ClipboardFormats::MultiFormatPayloadKind::Text
                : (hasHtml ? ClipboardFormats::MultiFormatPayloadKind::Html
                           : ClipboardFormats::MultiFormatPayloadKind::Base64);
            if (!ClipboardFormats::IsMultiFormatPayloadAllowed(formatName, fmt, payloadKind))
            {
                SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
                return;
            }

            FormatPayload payload;
            payload.format = fmt;
            if (hasText)
            {
                const std::wstring text(obj.GetNamedString(L"text"));
                if (fmt == CF_TEXT)
                {
                    if (!EncodeAnsiText(text, payload.data))
                    {
                        SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
                        return;
                    }
                }
                else
                {
                    size_t chars = 0, bytes = 0;
                    if (!ClipboardFormats::CheckedAdd(text.size(), 1, chars) ||
                        !ClipboardFormats::CheckedMul(chars, sizeof(wchar_t), bytes))
                    {
                        SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
                        return;
                    }
                    payload.data.resize(bytes);
                    ::memcpy(payload.data.data(), text.c_str(), bytes);
                }
            }
            else if (hasHtml)
            {
                const std::wstring html(obj.GetNamedString(L"html"));
                const std::string utf8 = ClipboardFormats::WideToUtf8(html);
                const std::string cf = ClipboardFormats::BuildCfHtml(utf8);
                if (cf.empty()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
                payload.data.assign(cf.begin(), cf.end());
                payload.data.push_back(0);
            }
            else if (hasBase64)
            {
                // Generic binary payload kind (M1): decoded as-is for custom
                // formats, and structurally validated for the known binary
                // formats we already have a validator for.
                const std::wstring b64w(obj.GetNamedString(L"base64"));
                std::vector<BYTE> decoded;
                if (!ClipboardFormats::Base64Decode(ClipboardFormats::WideToUtf8(b64w), decoded))
                {
                    SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
                    return;
                }
                if ((fmt == CF_DIB || fmt == CF_DIBV5) && !ClipboardFormats::ValidateDib(decoded.data(), decoded.size()))
                {
                    SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
                    return;
                }
                if (fmt == CF_HDROP && !ClipboardFormats::ValidateDropFiles(decoded.data(), decoded.size()))
                {
                    SetErr(pError, CLIPBOARD_ERROR_INVALID_DATA);
                    return;
                }
                payload.data = std::move(decoded);
            }
            else
            {
                SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER);
                return;
            }
            items.push_back(std::move(payload));
        }
    }
    // std::bad_alloc must reach SafeBridgeCall as OUT_OF_MEMORY, not be folded
    // into "the input was malformed" (M3): only a parse/type error is INVALID_PARAMETER.
    catch (const std::bad_alloc&) { throw; }
    catch (...) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = ::CopyMultipleFormats(hwnd, items, options, &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

BOOL ClipboardManager::HasClipboardFormat(const wchar_t* formatName, DWORD* pError)
{
    DFLog(TAG, L"[HasClipboardFormat] format: %ls", formatName ? formatName : L"");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return FALSE;
    if (!formatName) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return FALSE; }
    const BOOL has = ::HasFormat(ResolveFormatId(formatName)) ? TRUE : FALSE;
    SetErr(pError, CLIPBOARD_ERROR_NONE); // M3: a valid return also means the out-error must read NONE
    return has;
}

DWORD ClipboardManager::GetClipboardFormats(wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[GetClipboardFormats]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    std::vector<UINT> formats;
    const DWORD err = ::ListFormats(hwnd, formats);
    if (err != CLIPBOARD_ERROR_NONE) { SetErr(pError, err); return 0; }

    JsonArray arr;
    for (UINT fmt : formats)
    {
        std::wstring name;
        if (::FormatName(fmt, name) != CLIPBOARD_ERROR_NONE)
        {
            wchar_t hex[16];
            ::swprintf_s(hex, L"0x%04X", fmt);
            name = hex;
        }
        arr.Append(JsonValue::CreateStringValue(name));
    }
    return WriteStringToBuffer(std::wstring(arr.Stringify()), buffer, bufferSize, pError);
}

DWORD ClipboardManager::GetPreferredClipboardFormat(wchar_t* buffer, DWORD bufferSize, DWORD* pError)
{
    DLog(TAG, L"[GetPreferredClipboardFormat]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return 0;

    const int fmt = ::PickPreferredFormat();
    std::wstring name;
    if (fmt > 0) ::FormatName(static_cast<UINT>(fmt), name);
    return WriteStringToBuffer(name, buffer, bufferSize, pError);
}

void ClipboardManager::ClearClipboard(DWORD* pError)
{
    DLog(TAG, L"[ClearClipboard]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    if (!AcquireSyncLease(pError, lease, hwnd)) return;
    auto selfWrite = watcher_.BeginSelfWrite();
    const DWORD err = ::ClearClipboard(hwnd);
    SetErr(pError, err);
    if (err == CLIPBOARD_ERROR_NONE) selfWrite.NoteMutation();
}

// -----------------------------------------------------------------------
// Deferred rendering (UI-thread-only)
// -----------------------------------------------------------------------

void ClipboardManager::ReserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider,
                                              void* context, DWORD* pError)
{
    DLog(TAG, L"[ReserveDeferredFormats]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    std::shared_ptr<ClipboardHistoryCoordinator> coordinator;
    if (!AcquireOwnerContext(pError, lease, hwnd, coordinator)) return;
    if (!formatNamesJson || !provider) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::vector<std::wstring> names;
    try
    {
        JsonArray arr = JsonArray::Parse(formatNamesJson);
        for (auto const& v : arr) names.emplace_back(v.GetString());
    }
    catch (const std::bad_alloc&) { throw; }
    catch (...) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }
    if (names.empty()) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

    std::map<UINT, DeferredClipboard::Renderer> renderers;
    for (auto const& name : names)
    {
        const UINT fmt = ResolveFormatId(name);
        if (fmt == 0) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return; }

        renderers[fmt] = MakeDeferredRenderer(provider, context, name);
    }

    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = deferred_.Reserve(hwnd, std::move(renderers), &mutated);
    SetErr(pError, err);
    if (mutated) selfWrite.NoteMutation();
}

void ClipboardManager::RecoverDeferredState(DWORD* pError)
{
    DLog(TAG, L"[RecoverDeferredState]");
    std::optional<ClipboardLifecycle::Lease> lease;
    HWND hwnd = nullptr;
    std::shared_ptr<ClipboardHistoryCoordinator> coordinator;
    if (!AcquireOwnerContext(pError, lease, hwnd, coordinator)) return;
    auto selfWrite = watcher_.BeginSelfWrite();
    bool mutated = false;
    const DWORD err = deferred_.RecoverFromPartialState(&mutated);
    if (mutated) selfWrite.NoteMutation();
    SetErr(pError, err);
}

// -----------------------------------------------------------------------
// Async history
// -----------------------------------------------------------------------

uint32_t ClipboardManager::GetClipboardHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[GetClipboardHistory]");
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return 0;
    return coord->RequestGetItems(cb, pError);
}

uint32_t ClipboardManager::RestoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    DFLog(TAG, L"[RestoreHistoryItem] id: %ls", itemId ? itemId : L"");
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return 0;
    if (!itemId) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }
    return coord->RequestRestoreItem(itemId, cb, pError);
}

uint32_t ClipboardManager::DeleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    DFLog(TAG, L"[DeleteHistoryItem] id: %ls", itemId ? itemId : L"");
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return 0;
    if (!itemId) { SetErr(pError, CLIPBOARD_ERROR_INVALID_PARAMETER); return 0; }
    return coord->RequestDeleteItem(itemId, cb, pError);
}

uint32_t ClipboardManager::ClearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[ClearUnpinnedHistory]");
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return 0;
    return coord->RequestClearUnpinned(cb, pError);
}

uint32_t ClipboardManager::GetClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError)
{
    DLog(TAG, L"[GetClipboardHistoryAvailability]");
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return 0;
    return coord->RequestGetAvailability(cb, pError);
}

BOOL ClipboardManager::CancelClipboardRequest(uint32_t requestId, DWORD* pError)
{
    DFLog(TAG, L"[CancelClipboardRequest] id: %u", requestId);
    std::shared_ptr<ClipboardHistoryCoordinator> coord;
    if (!AcquireHistoryCoordinator(pError, coord)) return FALSE;
    return coord->CancelRequest(requestId, pError);
}

// -----------------------------------------------------------------------
// WndProc callbacks (owner UI thread only)
// -----------------------------------------------------------------------

void ClipboardManager::OnClipboardUpdate() { watcher_.OnClipboardUpdate(); }
void ClipboardManager::OnRenderFormat(UINT format) { deferred_.OnRenderFormat(format); }
void ClipboardManager::OnRenderAllFormats(HWND hwnd) { deferred_.OnRenderAllFormats(hwnd); }
void ClipboardManager::OnDestroyClipboardMsg() { deferred_.OnDestroyClipboard(); }
void ClipboardManager::OnHistoryRequestMessage(uint32_t id) { if (coordinator_) coordinator_->OnStartQueuedRequest(id); }
void ClipboardManager::OnHistoryCancelMessage(uint32_t id) { if (coordinator_) coordinator_->OnCancelMessage(id); }
void ClipboardManager::OnHistoryDrainMessage() { if (coordinator_) coordinator_->OnDrainMessage(); }
void ClipboardManager::OnHistoryEventMessage(WPARAM eventId, LPARAM generation)
{
    if (coordinator_) coordinator_->OnHistoryEventMessage(eventId, generation);
}

// =============================================================================
// Bridge (extern "C")
// =============================================================================
//
// Every Bridge entry point is routed through SafeBridgeCall (H2/L1): it logs
// the entry point name (satisfying the "log at every Bridge method" rule
// without repeating it at each call site) and converts any exception that
// escapes the Manager call (std::vector/std::wstring/std::make_shared/WinRT
// JSON allocation failures, etc.) into a pError value instead of letting it
// cross the C ABI boundary undefined.

namespace
{
    template <typename Fn>
    auto SafeBridgeCall(const wchar_t* name, DWORD* pError, Fn&& fn)
    {
        DFLog(TAG, L"[Bridge] %ls", name);
        using R = decltype(fn());
        if constexpr (std::is_void_v<R>)
        {
            try { fn(); }
            catch (const std::bad_alloc&) { SetErr(pError, CLIPBOARD_ERROR_OUT_OF_MEMORY); }
            catch (...) { DFLog(TAG, L"[Bridge] %ls threw", name); SetErr(pError, CLIPBOARD_ERROR_UNKNOWN); }
        }
        else
        {
            try { return fn(); }
            catch (const std::bad_alloc&) { SetErr(pError, CLIPBOARD_ERROR_OUT_OF_MEMORY); }
            catch (...) { DFLog(TAG, L"[Bridge] %ls threw", name); SetErr(pError, CLIPBOARD_ERROR_UNKNOWN); }
            return R{};
        }
    }
}

void initClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError)
{
    SafeBridgeCall(L"initClipboardManager", pError, [&] { ClipboardManager::GetInstance().InitClipboardManager(onChanged, pError); });
}

void setClipboardHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                  ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                  ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                  DWORD* pError)
{
    SafeBridgeCall(L"setClipboardHistoryCallbacks", pError, [&]
    {
        ClipboardManager::GetInstance().SetHistoryCallbacks(onHistoryChanged, onHistoryEnabledChanged, onRoamingEnabledChanged, pError);
    });
}

BOOL uninitClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"uninitClipboardManager", pError, [&] { return ClipboardManager::GetInstance().Uninit(pError); });
}

BOOL canDestroyClipboardManager(DWORD* pError)
{
    return SafeBridgeCall(L"canDestroyClipboardManager", pError, [&] { return ClipboardManager::GetInstance().CanDestroy(pError); });
}

void copyPlainText(const wchar_t* text, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyPlainText", pError, [&] { ClipboardManager::GetInstance().CopyPlainText(text, options, pError); });
}

DWORD pastePlainText(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pastePlainText", pError, [&] { return ClipboardManager::GetInstance().PastePlainText(buffer, buffer_size, pError); });
}

void copyHtml(const wchar_t* htmlFragment, const wchar_t* plainText, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyHtml", pError, [&] { ClipboardManager::GetInstance().CopyHtml(htmlFragment, plainText, options, pError); });
}

DWORD pasteHtml(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteHtml", pError, [&] { return ClipboardManager::GetInstance().PasteHtml(buffer, buffer_size, pError); });
}

void copyFiles(const wchar_t* pathsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyFiles", pError, [&] { ClipboardManager::GetInstance().CopyFiles(pathsJson, options, pError); });
}

DWORD pasteFiles(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteFiles", pError, [&] { return ClipboardManager::GetInstance().PasteFiles(buffer, buffer_size, pError); });
}

void copyImage(const BYTE* dib, DWORD dibSize, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyImage", pError, [&] { ClipboardManager::GetInstance().CopyImage(dib, dibSize, options, pError); });
}

DWORD pasteImage(BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteImage", pError, [&] { return ClipboardManager::GetInstance().PasteImage(buffer, buffer_size, pError); });
}

void copyCustomFormat(const wchar_t* formatName, const BYTE* data, DWORD size, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyCustomFormat", pError, [&] { ClipboardManager::GetInstance().CopyCustomFormat(formatName, data, size, options, pError); });
}

DWORD pasteCustomFormat(const wchar_t* formatName, BYTE* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"pasteCustomFormat", pError, [&] { return ClipboardManager::GetInstance().PasteCustomFormat(formatName, buffer, buffer_size, pError); });
}

void copyMultipleFormats(const wchar_t* itemsJson, DWORD options, DWORD* pError)
{
    SafeBridgeCall(L"copyMultipleFormats", pError, [&] { ClipboardManager::GetInstance().CopyMultipleFormats(itemsJson, options, pError); });
}

BOOL hasClipboardFormat(const wchar_t* formatName, DWORD* pError)
{
    return SafeBridgeCall(L"hasClipboardFormat", pError, [&] { return ClipboardManager::GetInstance().HasClipboardFormat(formatName, pError); });
}

DWORD getClipboardFormats(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardFormats", pError, [&] { return ClipboardManager::GetInstance().GetClipboardFormats(buffer, buffer_size, pError); });
}

DWORD getPreferredClipboardFormat(wchar_t* buffer, DWORD buffer_size, DWORD* pError)
{
    return SafeBridgeCall(L"getPreferredClipboardFormat", pError, [&] { return ClipboardManager::GetInstance().GetPreferredClipboardFormat(buffer, buffer_size, pError); });
}

void clearClipboard(DWORD* pError)
{
    SafeBridgeCall(L"clearClipboard", pError, [&] { ClipboardManager::GetInstance().ClearClipboard(pError); });
}

void reserveDeferredFormats(const wchar_t* formatNamesJson, ClipboardRenderCallback provider, void* context, DWORD* pError)
{
    SafeBridgeCall(L"reserveDeferredFormats", pError, [&] { ClipboardManager::GetInstance().ReserveDeferredFormats(formatNamesJson, provider, context, pError); });
}

void recoverDeferredState(DWORD* pError)
{
    SafeBridgeCall(L"recoverDeferredState", pError, [&] { ClipboardManager::GetInstance().RecoverDeferredState(pError); });
}

uint32_t getClipboardHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardHistory", pError, [&] { return ClipboardManager::GetInstance().GetClipboardHistory(cb, pError); });
}

uint32_t restoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"restoreHistoryItem", pError, [&] { return ClipboardManager::GetInstance().RestoreHistoryItem(itemId, cb, pError); });
}

uint32_t deleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"deleteHistoryItem", pError, [&] { return ClipboardManager::GetInstance().DeleteHistoryItem(itemId, cb, pError); });
}

uint32_t clearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"clearUnpinnedHistory", pError, [&] { return ClipboardManager::GetInstance().ClearUnpinnedHistory(cb, pError); });
}

uint32_t getClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError)
{
    return SafeBridgeCall(L"getClipboardHistoryAvailability", pError, [&] { return ClipboardManager::GetInstance().GetClipboardHistoryAvailability(cb, pError); });
}

BOOL cancelClipboardRequest(uint32_t requestId, DWORD* pError)
{
    return SafeBridgeCall(L"cancelClipboardRequest", pError, [&] { return ClipboardManager::GetInstance().CancelClipboardRequest(requestId, pError); });
}
