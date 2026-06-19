// WindowsClassicActivator.cpp
//
// Translation-unit isolation strategy:
//   pch.h provides MFC + winrt basics. Classic shell headers are included HERE
//   and kept out of pch.h to avoid the ::IUnknown ambiguity that arises when
//   winrt::Windows::Foundation namespace is opened alongside <ShObjIdl.h>.
//   The COM activator uses WRL (not winrt::implements) so it inherits ::IUnknown
//   from <Unknwn.h> and avoids the WinRT ABI IUnknown entirely.
//   DO NOT add "using namespace winrt::Windows::Foundation;" in this file.

#include "pch.h"

// WRL for IClassFactory / INotificationActivationCallback implementation.
// Must precede shell headers so <Unknwn.h> is included in classic order.
#include <wrl/implements.h>
#include <wrl/module.h>

// Shell headers for shortcut creation
// NOTE: <NotificationActivationCallback.h> is NOT included here — INotificationActivationCallback
// and NOTIFICATION_USER_INPUT_DATA are defined manually in WindowsClassicActivator.h.
// The SDK header only forward-declares NOTIFICATION_USER_INPUT_DATA in newer SDKs (10.0.26100),
// which causes C2027 when combined with WinRT headers via pch.h.
#include <ShObjIdl.h>      // IShellLinkW, CLSID_ShellLink
#include <shlobj.h>        // SHGetSpecialFolderPathW
#include <propsys.h>       // IPropertyStore
#include <propkey.h>       // PKEY_AppUserModel_ID, PKEY_AppUserModel_ToastActivatorCLSID
#include <propvarutil.h>   // InitPropVariantFromString, InitPropVariantFromCLSID

#include "WindowsClassicActivator.h"
#include "WindowsNotificationManagerInternal.h"
#include "common.h"

// WinRT — used for toast delivery, XML, badge, JSON (all in WinRT classic APIs)
// DO NOT open winrt::Windows::Foundation namespace to avoid ::IUnknown collision.
using winrt::hstring;
using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonArray;
using winrt::Windows::Data::Json::JsonValue;
using winrt::Windows::Data::Xml::Dom::XmlDocument;
using winrt::Windows::UI::Notifications::ToastNotificationManager;
using winrt::Windows::UI::Notifications::ToastNotification;
using winrt::Windows::UI::Notifications::ScheduledToastNotification;
using winrt::Windows::UI::Notifications::ToastNotifier;
using winrt::Windows::UI::Notifications::BadgeUpdateManager;
using winrt::Windows::UI::Notifications::BadgeNotification;
using winrt::Windows::UI::Notifications::NotificationSetting;
using winrt::Windows::UI::Notifications::NotificationData;
using winrt::Windows::UI::Notifications::NotificationUpdateResult;

static const wchar_t* TAG = L"ClassicActivator";

// ============================================================================
// CLSID derivation — deterministic hash from AUMID (FNV-1a 64-bit × 2)
// Avoids hard-coded GUIDs so multiple apps using this DLL never collide.
// ============================================================================

static GUID NameToGuid(const std::wstring& name)
{
    // Two independent FNV-1a 64-bit hashes over the wchar_t code units
    constexpr uint64_t FNV_OFFSET_A = 14695981039346656037ULL;
    constexpr uint64_t FNV_OFFSET_B =  2166136261ULL;          // 32-bit seed, extended to 64
    constexpr uint64_t FNV_PRIME    =  1099511628211ULL;
    constexpr uint64_t FNV_PRIME_B  =     16777619ULL;

    uint64_t hashA = FNV_OFFSET_A;
    uint64_t hashB = FNV_OFFSET_B;

    for (wchar_t c : name)
    {
        hashA ^= static_cast<uint64_t>(c);
        hashA *= FNV_PRIME;
        hashB ^= static_cast<uint64_t>(c);
        hashB *= FNV_PRIME_B;
    }

    GUID guid;
    static_assert(sizeof(GUID) == 16, "GUID must be 16 bytes");
    memcpy(reinterpret_cast<uint8_t*>(&guid),     &hashA, 8);
    memcpy(reinterpret_cast<uint8_t*>(&guid) + 8, &hashB, 8);

    // Mark as RFC 4122 variant and version 4 (random-looking, stable for same input)
    guid.Data3 = (guid.Data3 & 0x0FFF) | 0x4000;
    guid.Data4[0] = (guid.Data4[0] & 0x3F) | 0x80;

    return guid;
}

// ============================================================================
// ClassicArgsToJson — query string + user input → JSON string
// ============================================================================

std::wstring ClassicArgsToJson(
    const wchar_t* invokedArgs,
    const NOTIFICATION_USER_INPUT_DATA* data,
    unsigned long count)
{
    JsonObject root;

    // Parse "key=value&key2=value2" query string
    if (invokedArgs && *invokedArgs)
    {
        std::wstring s{ invokedArgs };
        std::wstring::size_type pos = 0;
        while (pos < s.size())
        {
            auto amp = s.find(L'&', pos);
            if (amp == std::wstring::npos) amp = s.size();
            auto eq = s.find(L'=', pos);
            if (eq != std::wstring::npos && eq < amp)
            {
                root.Insert(hstring{ s.substr(pos, eq - pos) },
                            JsonValue::CreateStringValue(hstring{ s.substr(eq + 1, amp - eq - 1) }));
            }
            pos = amp + 1;
        }
    }

    // Merge user input (text boxes / combo selections)
    for (unsigned long i = 0; i < count; ++i)
    {
        if (data[i].Key)
        {
            root.Insert(hstring{ data[i].Key },
                        JsonValue::CreateStringValue(hstring{ data[i].Value ? data[i].Value : L"" }));
        }
    }

    return std::wstring{ root.Stringify() };
}

bool TryGetLaunchActivationJson(std::wstring* argsJson)
{
    DLog(TAG, L"[TryGetLaunchActivationJson]");

    const wchar_t* cmdLine = GetCommandLineW();
    if (!cmdLine || !*cmdLine)
        return false;

    constexpr wchar_t kLaunchMarker[] = L"-ToastActivated";
    const wchar_t* marker = wcsstr(cmdLine, kLaunchMarker);
    if (!marker)
        return false;

    const wchar_t* invokedArgs = marker + _countof(kLaunchMarker) - 1;
    while (*invokedArgs == L' ' || *invokedArgs == L'\t')
        ++invokedArgs;

    std::wstring normalizedArgs{ invokedArgs };
    if (normalizedArgs.size() >= 2 &&
        normalizedArgs.front() == L'"' &&
        normalizedArgs.back() == L'"')
    {
        normalizedArgs = normalizedArgs.substr(1, normalizedArgs.size() - 2);
    }

    if (argsJson)
        *argsJson = ClassicArgsToJson(normalizedArgs.c_str(), nullptr, 0);

    DFLog(TAG, L"[TryGetLaunchActivationJson] detected launch activation. invokedArgs=%ls",
          normalizedArgs.empty() ? L"<empty>" : normalizedArgs.c_str());
    return true;
}

// ============================================================================
// COM activator — WRL-based INotificationActivationCallback + IClassFactory
// WRL uses ::IUnknown (from <Unknwn.h>), not winrt::Windows::Foundation::IUnknown.
// ============================================================================

class NotificationActivationCallback
    : public Microsoft::WRL::RuntimeClass<
        Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
        INotificationActivationCallback>
{
public:
    IFACEMETHODIMP Activate(
        LPCWSTR /*aumid*/,
        LPCWSTR invokedArgs,
        const NOTIFICATION_USER_INPUT_DATA* data,
        ULONG count) noexcept override
    {
        DLog(TAG, L"[Activate] COM activator called");
        try
        {
            std::wstring json = ClassicArgsToJson(invokedArgs, data, count);
            WindowsNotificationManager::GetInstance().InvokeCallback(json);
        }
        catch (...)
        {
            DLog(TAG, L"[Activate] exception in callback relay");
        }
        return S_OK;
    }
};

class NotificationActivationCallbackFactory
    : public Microsoft::WRL::RuntimeClass<
        Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
        IClassFactory>
{
public:
    IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) noexcept override
    {
        if (outer) return CLASS_E_NOAGGREGATION;
        auto cb = Microsoft::WRL::Make<NotificationActivationCallback>();
        if (!cb) return E_OUTOFMEMORY;
        return cb->QueryInterface(riid, ppv);
    }
    IFACEMETHODIMP LockServer(BOOL) noexcept override { return S_OK; }
};

// ============================================================================
// Registry helpers
// ============================================================================

static bool WriteRegistryString(HKEY root, const std::wstring& keyPath,
                                const std::wstring& valueName, const std::wstring& value)
{
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(root, keyPath.c_str(), 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_SET_VALUE, nullptr, &hKey, nullptr) != ERROR_SUCCESS)
        return false;

    const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
    bool ok = RegSetValueExW(hKey, valueName.empty() ? nullptr : valueName.c_str(),
                             0, REG_SZ,
                             reinterpret_cast<const BYTE*>(value.c_str()),
                             bytes) == ERROR_SUCCESS;
    RegCloseKey(hKey);
    return ok;
}

static std::wstring GuidToString(const GUID& guid)
{
    wchar_t buf[40]{};
    swprintf_s(buf, L"{%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
        guid.Data1, guid.Data2, guid.Data3,
        guid.Data4[0], guid.Data4[1],
        guid.Data4[2], guid.Data4[3], guid.Data4[4],
        guid.Data4[5], guid.Data4[6], guid.Data4[7]);
    return buf;
}

// ============================================================================
// Shortcut helper — creates/updates the Start Menu .lnk for ClassicRegister
// ============================================================================

static bool EnsureShortcut(const std::wstring& aumid,
                            const std::wstring& iconPath,
                            const GUID& activatorClsid)
{
    // Destination: %APPDATA%\Microsoft\Windows\Start Menu\Programs\<displayName>.lnk
    wchar_t startMenu[MAX_PATH]{};
    if (!SHGetSpecialFolderPathW(nullptr, startMenu, CSIDL_PROGRAMS, TRUE))
        return false;

    std::wstring lnkPath = std::wstring(startMenu) + L"\\" + aumid + L".lnk";

    // Check whether an up-to-date shortcut already exists
    {
        Microsoft::WRL::ComPtr<IShellLinkW> existing;
        Microsoft::WRL::ComPtr<IPersistFile> pf;
        if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                       IID_PPV_ARGS(&existing))) &&
            SUCCEEDED(existing.As(&pf)) &&
            SUCCEEDED(pf->Load(lnkPath.c_str(), STGM_READ)))
        {
            Microsoft::WRL::ComPtr<IPropertyStore> ps;
            if (SUCCEEDED(existing.As(&ps)))
            {
                PROPVARIANT pv{};
                if (SUCCEEDED(ps->GetValue(PKEY_AppUserModel_ID, &pv)) &&
                    pv.vt == VT_LPWSTR && pv.pwszVal && aumid == pv.pwszVal)
                {
                    PropVariantClear(&pv);
                    DLog(TAG, L"[EnsureShortcut] shortcut already up-to-date; skipping");
                    return true;  // Already has correct AUMID; assume CLSID is also correct
                }
                PropVariantClear(&pv);
            }
        }
    }

    // Get current exe path
    wchar_t exePath[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exePath, MAX_PATH);

    Microsoft::WRL::ComPtr<IShellLinkW> link;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&link));
    if (FAILED(hr)) return false;

    link->SetPath(exePath);
    link->SetArguments(L"");
    if (!iconPath.empty())
        link->SetIconLocation(iconPath.c_str(), 0);

    Microsoft::WRL::ComPtr<IPropertyStore> ps;
    hr = link.As(&ps);
    if (FAILED(hr)) return false;

    // PKEY_AppUserModel_ID = AUMID
    {
        PROPVARIANT pv{};
        hr = InitPropVariantFromString(aumid.c_str(), &pv);
        if (FAILED(hr)) return false;
        ps->SetValue(PKEY_AppUserModel_ID, pv);
        PropVariantClear(&pv);
    }

    // PKEY_AppUserModel_ToastActivatorCLSID = activator CLSID
    {
        PROPVARIANT pv{};
        hr = InitPropVariantFromCLSID(activatorClsid, &pv);
        if (FAILED(hr)) return false;
        ps->SetValue(PKEY_AppUserModel_ToastActivatorCLSID, pv);
        PropVariantClear(&pv);
    }

    hr = ps->Commit();
    if (FAILED(hr)) return false;

    Microsoft::WRL::ComPtr<IPersistFile> pf;
    hr = link.As(&pf);
    if (FAILED(hr)) return false;

    hr = pf->Save(lnkPath.c_str(), TRUE);
    if (FAILED(hr))
    {
        DFLog(TAG, L"[EnsureShortcut] IPersistFile::Save failed. hr=0x%08lx", hr);
        return false;
    }

    DFLog(TAG, L"[EnsureShortcut] shortcut created at %ls", lnkPath.c_str());
    return true;
}

// ============================================================================
// UnpackagedBackend — constructor / destructor
// ============================================================================

UnpackagedBackend::UnpackagedBackend(std::wstring aumid, std::wstring iconPath)
    : m_aumid(std::move(aumid))
    , m_iconPath(std::move(iconPath))
    , m_activatorClsid(NameToGuid(m_aumid))
{
    DFLog(TAG, L"[UnpackagedBackend] aumid=%ls clsid=%ls",
          m_aumid.c_str(), GuidToString(m_activatorClsid).c_str());
}

UnpackagedBackend::~UnpackagedBackend()
{
    if (m_comRegToken)
        CoRevokeClassObject(m_comRegToken);
}

// ============================================================================
// RegisterActivation — shortcut + registry + CoRegisterClassObject
// ============================================================================

void UnpackagedBackend::RegisterActivation(DWORD* pError)
{
    DLog(TAG, L"[RegisterActivation]");

    // 1. CoRegisterClassObject — must come before shortcut/registry so the
    //    class object is already public when subsequent WNS delivery fires.
    {
        auto factory = Microsoft::WRL::Make<NotificationActivationCallbackFactory>();
        if (!factory)
        {
            DLog(TAG, L"[RegisterActivation] Make<Factory> failed (OOM)");
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
            return;
        }
        HRESULT hr = CoRegisterClassObject(m_activatorClsid, factory.Get(),
                                           CLSCTX_LOCAL_SERVER,
                                           REGCLS_MULTIPLEUSE,
                                           &m_comRegToken);
        if (FAILED(hr))
        {
            DFLog(TAG, L"[RegisterActivation] CoRegisterClassObject failed. hr=0x%08lx", hr);
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
            return;
        }
        DFLog(TAG, L"[RegisterActivation] CoRegisterClassObject ok. token=%lu", m_comRegToken);
    }

    // 2. Registry: LocalServer32 for cold-start exe launch, AppUserModelId for display name
    {
        wchar_t exePath[MAX_PATH]{};
        GetModuleFileNameW(nullptr, exePath, MAX_PATH);
        const std::wstring localServer32Val = std::wstring(exePath) + L" -ToastActivated";

        std::wstring clsidStr = GuidToString(m_activatorClsid);
        const std::wstring ls32Key  = L"Software\\Classes\\CLSID\\" + clsidStr + L"\\LocalServer32";
        const std::wstring aumidKey = L"Software\\Classes\\AppUserModelId\\" + m_aumid;

        if (!WriteRegistryString(HKEY_CURRENT_USER, ls32Key, L"", localServer32Val))
        {
            DLog(TAG, L"[RegisterActivation] LocalServer32 registry write failed");
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
            return;
        }

        if (!WriteRegistryString(HKEY_CURRENT_USER, aumidKey, L"DisplayName", m_aumid))
        {
            DLog(TAG, L"[RegisterActivation] AppUserModelId DisplayName registry write failed");
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
            return;
        }

        if (!m_iconPath.empty())
        {
            if (!WriteRegistryString(HKEY_CURRENT_USER, aumidKey, L"IconUri", m_iconPath))
            {
                DLog(TAG, L"[RegisterActivation] AppUserModelId IconUri registry write failed");
                if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
                return;
            }
        }

        DFLog(TAG, L"[RegisterActivation] registry written. LocalServer32=%ls", localServer32Val.c_str());
    }

    // 3. Start Menu shortcut (required for toast display and scheduled delivery)
    if (!EnsureShortcut(m_aumid, m_iconPath, m_activatorClsid))
    {
        DLog(TAG, L"[RegisterActivation] shortcut creation failed");
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        return;
    }

    if (TryGetLaunchActivationJson(nullptr))
        DLog(TAG, L"[RegisterActivation] cold-start marker detected; launch fallback is available");

    if (pError) *pError = NOTIFICATION_SUCCESS;
}

// ============================================================================
// UnregisterActivation — revoke COM class object
// ============================================================================

void UnpackagedBackend::UnregisterActivation()
{
    DLog(TAG, L"[UnregisterActivation]");
    if (m_comRegToken)
    {
        CoRevokeClassObject(m_comRegToken);
        m_comRegToken = 0;
    }
}

// ============================================================================
// Internal helper — create a ToastNotifier for this AUMID
// ============================================================================

static winrt::Windows::UI::Notifications::ToastNotifier MakeNotifier(const std::wstring& aumid)
{
    return ToastNotificationManager::CreateToastNotifier(hstring{ aumid });
}

// ============================================================================
// Deliver — show notification immediately
// ============================================================================

void UnpackagedBackend::Deliver(const DeliverPayload& payload, DWORD* pError)
{
    DLog(TAG, L"[Deliver]");
    try
    {
        XmlDocument doc;
        doc.LoadXml(hstring{ payload.xmlPayload });

        ToastNotification toast{ doc };
        if (!payload.tag.empty())   toast.Tag(hstring{ payload.tag });
        if (!payload.group.empty()) toast.Group(hstring{ payload.group });

        if (payload.hasExpiration)
        {
            toast.ExpirationTime(winrt::clock::now() +
                                 std::chrono::seconds(payload.expirationSec));
        }

        if (payload.hasProgress)
        {
            NotificationData nd;
            nd.Values().Insert(L"progressValue",
                               hstring{ std::to_wstring(payload.progressValue) });
            if (!payload.progressValueStr.empty())
                nd.Values().Insert(L"progressValueString", hstring{ payload.progressValueStr });
            if (!payload.progressStatus.empty())
                nd.Values().Insert(L"progressStatus", hstring{ payload.progressStatus });
            nd.SequenceNumber(1);
            toast.Data(nd);
        }

        MakeNotifier(m_aumid).Show(toast);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Deliver] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// ============================================================================
// Schedule / CancelSchedule
// ============================================================================

void UnpackagedBackend::Schedule(const DeliverPayload& payload, int64_t scheduledTimeMs,
                                  DWORD* pError)
{
    DFLog(TAG, L"[Schedule] scheduledTimeMs=%lld", scheduledTimeMs);
    try
    {
        auto tp = std::chrono::system_clock::time_point{
            std::chrono::milliseconds(scheduledTimeMs)
        };
        auto scheduledTime = winrt::clock::from_sys(tp);

        XmlDocument doc;
        doc.LoadXml(hstring{ payload.xmlPayload });

        ScheduledToastNotification scheduled{ doc, scheduledTime };
        if (!payload.tag.empty())   scheduled.Tag(hstring{ payload.tag });
        if (!payload.group.empty()) scheduled.Group(hstring{ payload.group });

        MakeNotifier(m_aumid).AddToSchedule(scheduled);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Schedule] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void UnpackagedBackend::CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[CancelSchedule] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");
    try
    {
        auto notifier  = MakeNotifier(m_aumid);
        auto scheduled = notifier.GetScheduledToastNotifications();

        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };

        for (auto const& item : scheduled)
        {
            bool tagMatch   = tagStr.empty()   || item.Tag()   == tagStr;
            bool groupMatch = groupStr.empty() || item.Group() == groupStr;
            if (tagMatch && groupMatch)
                notifier.RemoveFromSchedule(item);
        }
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[CancelSchedule] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// ============================================================================
// SetBadge
// ============================================================================

void UnpackagedBackend::SetBadge(int value, DWORD* pError)
{
    // BadgeUpdateManager requires a live-tile (package tile) registration which
    // unpackaged apps cannot create without MSIX identity. Return NOT_SUPPORTED.
    DFLog(TAG, L"[SetBadge] value=%d — NOT_SUPPORTED for unpackaged", value);
    if (pError) *pError = NOTIFICATION_ERROR_NOT_SUPPORTED;
}

// ============================================================================
// UpdateProgress
// ============================================================================

void UnpackagedBackend::UpdateProgress(const wchar_t* tag, const wchar_t* group,
                                        double value, const wchar_t* valueStr,
                                        const wchar_t* status, uint32_t seq, DWORD* pError)
{
    DFLog(TAG, L"[UpdateProgress] tag=%ls, value=%.2f, seq=%u",
          tag ? tag : L"null", value, seq);
    try
    {
        NotificationData nd;
        nd.Values().Insert(L"progressValue", hstring{ std::to_wstring(value) });
        if (valueStr) nd.Values().Insert(L"progressValueString", hstring{ valueStr });
        if (status)   nd.Values().Insert(L"progressStatus",      hstring{ status  });
        nd.SequenceNumber(seq);

        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };

        auto result = groupStr.empty()
            ? MakeNotifier(m_aumid).Update(nd, tagStr)
            : MakeNotifier(m_aumid).Update(nd, tagStr, groupStr);

        if (result != NotificationUpdateResult::Succeeded)
        {
            DFLog(TAG, L"[UpdateProgress] notification not found. tag=%ls", tag ? tag : L"null");
            if (pError) *pError = NOTIFICATION_ERROR_PROGRESS_NOT_FOUND;
        }
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[UpdateProgress] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// ============================================================================
// RemoveByTag / RemoveAll
// ============================================================================

void UnpackagedBackend::RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[RemoveByTag] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");
    try
    {
        auto history = ToastNotificationManager::History();
        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };
        hstring aumid   { m_aumid };

        if (groupStr.empty())
            history.Remove(tagStr, hstring{}, aumid);
        else
            history.Remove(tagStr, groupStr, aumid);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[RemoveByTag] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void UnpackagedBackend::RemoveAll(DWORD* pError)
{
    DLog(TAG, L"[RemoveAll]");
    try
    {
        ToastNotificationManager::History().Clear(hstring{ m_aumid });
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[RemoveAll] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// ============================================================================
// RemoveById / GetAll — NOT_SUPPORTED for unpackaged (no numeric ID concept)
// ============================================================================

void UnpackagedBackend::RemoveById(uint32_t id, DWORD* pError)
{
    DFLog(TAG, L"[RemoveById] id=%u — NOT_SUPPORTED for unpackaged", id);
    if (pError) *pError = NOTIFICATION_ERROR_NOT_SUPPORTED;
}

void UnpackagedBackend::GetAll(wchar_t* /*outJson*/, uint32_t /*bufferSize*/, DWORD* pError)
{
    DLog(TAG, L"[GetAll] — NOT_SUPPORTED for unpackaged");
    if (pError) *pError = NOTIFICATION_ERROR_NOT_SUPPORTED;
}

// ============================================================================
// Setting — NotificationSetting → common int
// ============================================================================

int UnpackagedBackend::Setting()
{
    try
    {
        auto s = MakeNotifier(m_aumid).Setting();
        switch (s)
        {
        case NotificationSetting::Enabled:                return 0;
        case NotificationSetting::DisabledForApplication: return 1;
        case NotificationSetting::DisabledForUser:        return 2;
        case NotificationSetting::DisabledByGroupPolicy:  return 3;
        case NotificationSetting::DisabledByManifest:     return 4;
        default:                                          return -1;
        }
    }
    catch (winrt::hresult_error const& ex)
    {
        // 0x80070490 = ERROR_NOT_FOUND: no settings entry for this AUMID yet.
        // The notification system creates the entry on first delivery, so absence
        // means the user has never disabled this app — treat as Enabled.
        if (static_cast<uint32_t>(ex.code()) == 0x80070490u) return 0;
        DFLog(TAG, L"[Setting] WinRT exception. hr=0x%08lx", ex.code().value);
        return -1;
    }
    catch (...) { return -1; }
}
