#pragma once

#include <string>
#include <Windows.h>

// ============================================================================
// DeliverPayload — neutral carrier for a built notification.
//
// Populated by WindowsNotificationManager::BuildPayload() (JSON fully parsed
// and builder output captured). Both PackagedBackend and UnpackagedBackend
// receive this struct; they never see raw JSON or classic WinRT concrete types
// (ToastNotifier / BadgeUpdater) through the INotificationBackend interface.
// ============================================================================
struct DeliverPayload
{
    std::wstring xmlPayload;
    std::wstring tag;
    std::wstring group;

    bool    hasExpiration    = false;
    int64_t expirationSec    = 0;
    bool    expiresOnReboot  = false;

    bool         hasProgress       = false;
    double       progressValue     = 0.0;
    std::wstring progressValueStr;
    std::wstring progressStatus;
};

// ============================================================================
// INotificationBackend — terminal API-dependent operations only.
//
// All common orchestration (JSON parsing, BuildFromJson, validation, error
// conversion) lives in WindowsNotificationManager. Backends receive completed
// payloads and perform the API-specific delivery call.
//
// json / ToastNotifier / BadgeUpdater are NOT exposed through this interface.
// ============================================================================
struct INotificationBackend
{
    virtual ~INotificationBackend() = default;

    virtual void RegisterActivation(DWORD* pError) = 0;
    virtual void UnregisterActivation() = 0;

    virtual void Deliver(const DeliverPayload& payload, DWORD* pError) = 0;
    virtual void Schedule(const DeliverPayload& payload, int64_t scheduledTimeMs, DWORD* pError) = 0;
    virtual void CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError) = 0;
    virtual void SetBadge(int value, DWORD* pError) = 0;
    virtual void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                                double value, const wchar_t* valueStr,
                                const wchar_t* status, uint32_t seq, DWORD* pError) = 0;
    virtual void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError) = 0;
    virtual void RemoveAll(DWORD* pError) = 0;
    virtual void RemoveById(uint32_t id, DWORD* pError) = 0;
    virtual void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) = 0;
    virtual int  Setting() = 0;
};
