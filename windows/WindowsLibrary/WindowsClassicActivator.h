#pragma once

// Windows.h must be included before this header (via pch.h).
// Classic shell headers are isolated in WindowsClassicActivator.cpp.

#include "WindowsNotificationBackend.h"
#include <string>

// Define NOTIFICATION_USER_INPUT_DATA and INotificationActivationCallback manually
// so that <NotificationActivationCallback.h> (which only forward-declares the struct
// in newer SDKs and can conflict with WinRT headers) does not need to be included
// in translation units that also include WinRT headers.

struct NOTIFICATION_USER_INPUT_DATA
{
    LPCWSTR Key;
    LPCWSTR Value;
};

// INotificationActivationCallback — classic COM activation callback interface.
// IID: {53E31837-6600-4A81-9395-75CFFE746F94}
MIDL_INTERFACE("53E31837-6600-4A81-9395-75CFFE746F94")
INotificationActivationCallback : public IUnknown
{
public:
    virtual HRESULT STDMETHODCALLTYPE Activate(
        LPCWSTR appUserModelId,
        LPCWSTR invokedArgs,
        const NOTIFICATION_USER_INPUT_DATA* data,
        ULONG dataCount) = 0;
};

// ============================================================================
// UnpackagedBackend — INotificationBackend implementation for unpackaged apps.
//
// Uses the classic Windows.UI.Notifications API throughout. Owns:
//  - classic COM activator (INotificationActivationCallback + IClassFactory)
//  - Start Menu shortcut creation (IShellLinkW + IPropertyStore)
//  - Registry entries (LocalServer32, AppUserModelId)
//  - CLSID derived deterministically from the AUMID (no fixed value)
// ============================================================================
class UnpackagedBackend final : public INotificationBackend
{
public:
    UnpackagedBackend(std::wstring aumid, std::wstring iconPath);
    ~UnpackagedBackend() override;

    void RegisterActivation(DWORD* pError) override;
    void UnregisterActivation() override;

    void Deliver(const DeliverPayload& payload, DWORD* pError) override;
    void Schedule(const DeliverPayload& payload, int64_t scheduledTimeMs, DWORD* pError) override;
    void CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError) override;
    void SetBadge(int value, DWORD* pError) override;
    void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                        double value, const wchar_t* valueStr,
                        const wchar_t* status, uint32_t seq, DWORD* pError) override;
    void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError) override;
    void RemoveAll(DWORD* pError) override;
    void RemoveById(uint32_t id, DWORD* pError) override;
    void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) override;
    int  Setting() override;

private:
    std::wstring m_aumid;
    std::wstring m_iconPath;
    GUID         m_activatorClsid;
    DWORD        m_comRegToken = 0;
};

// ============================================================================
// ClassicArgsToJson — converts classic activation arguments to argsJson.
//
// invokedArgs: "&"-delimited query string from the toast's arguments attribute.
// data/count:  NOTIFICATION_USER_INPUT_DATA array (text / combo user input).
// ============================================================================
std::wstring ClassicArgsToJson(
    const wchar_t* invokedArgs,
    const NOTIFICATION_USER_INPUT_DATA* data,
    unsigned long count);

bool TryGetLaunchActivationJson(std::wstring* argsJson);
