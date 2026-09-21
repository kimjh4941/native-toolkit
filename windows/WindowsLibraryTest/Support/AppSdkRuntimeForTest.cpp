#include "pch.h"
#include "Support/AppSdkRuntimeForTest.h"

#include <appmodel.h>

#include <mutex>

namespace AppSdkRuntimeForTest {

namespace {

// The signatures are the ones MddBootstrap.h declares. The header itself is not
// included because including it is what creates the link-time dependency this
// is avoiding.
using MddBootstrapInitialize2Fn = HRESULT(__stdcall*)(uint32_t, PCWSTR, PACKAGE_VERSION, int32_t);

constexpr uint32_t kAppSdkMajorMinor = 0x00010007;  ///< Windows App SDK 1.7.

/// The folder this test DLL was loaded from.
std::wstring ThisModuleFolder()
{
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                                | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&ThisModuleFolder), &self)) {
        return {};
    }
    wchar_t path[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameW(self, path, MAX_PATH);
    if (length == 0 || length == MAX_PATH) {
        return {};
    }
    const std::wstring full{path, length};
    const size_t slash = full.find_last_of(L'\\');
    return slash == std::wstring::npos ? std::wstring{} : full.substr(0, slash + 1);
}

std::wstring Start()
{
    const std::wstring folder = ThisModuleFolder();
    if (folder.empty()) {
        return L"could not work out where this test DLL lives";
    }

    const HMODULE bootstrap =
        LoadLibraryW((folder + L"Microsoft.WindowsAppRuntime.Bootstrap.dll").c_str());
    if (!bootstrap) {
        return L"Microsoft.WindowsAppRuntime.Bootstrap.dll was not next to the test DLL; "
               L"the CopyAppSdkBootstrap build step should have put it there";
    }

    const auto initialize = reinterpret_cast<MddBootstrapInitialize2Fn>(
        GetProcAddress(bootstrap, "MddBootstrapInitialize2"));
    if (!initialize) {
        return L"the bootstrap DLL does not export MddBootstrapInitialize2";
    }

    // No options: a test must never be answered with the dialog the
    // bootstrapper shows when it finds no matching runtime.
    PACKAGE_VERSION anyVersion{};
    const HRESULT hr = initialize(kAppSdkMajorMinor, L"", anyVersion, 0);
    if (FAILED(hr)) {
        return L"the Windows App Runtime 1.7 could not be made available (hr="
               + std::to_wstring(static_cast<unsigned long>(hr)) + L")";
    }
    return {};
}

}  // namespace

const std::wstring& Ensure()
{
    static const std::wstring failure = Start();
    return failure;
}

}  // namespace AppSdkRuntimeForTest
