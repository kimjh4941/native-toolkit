// WindowsLibrary.cpp : DLL の初期化ルーチンを定義します。
//

#include "pch.h"
#include "framework.h"
#include "WindowsLibrary.h"
#include <objbase.h>

#ifdef _DEBUG
#define new DEBUG_NEW
#endif

// CWindowsLibraryApp

BEGIN_MESSAGE_MAP(CWindowsLibraryApp, CWinApp)
END_MESSAGE_MAP()


// CWindowsLibraryApp の構築

CWindowsLibraryApp::CWindowsLibraryApp()
{
	// TODO: この位置に構築用コードを追加してください。
	// ここに InitInstance 中の重要な初期化処理をすべて記述してください。
}


// 唯一の CWindowsLibraryApp オブジェクト

CWindowsLibraryApp theApp;

const GUID CDECL _tlid = {0x4de616bc,0x18d3,0x4763,{0x87,0x54,0x06,0xf0,0x5a,0x9d,0x08,0x33}};
const WORD _wVerMajor = 1;
const WORD _wVerMinor = 0;


// CWindowsLibraryApp の初期化

BOOL CWindowsLibraryApp::InitInstance()
{
	CWinApp::InitInstance();

	// The host process may already have initialized COM on this thread as STA
	// (for example, a WinUI app main thread). In that case, requesting MTA here
	// returns RPC_E_CHANGED_MODE. That is not fatal for this DLL; it simply means
	// we must keep using the host-established apartment.
	const HRESULT hr = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
	{
		return FALSE;
	}

	if (!AfxSocketInit())
	{
		AfxMessageBox(IDP_SOCKETS_INIT_FAILED);
		return FALSE;
	}

	// すべての OLE サーバー ファクトリを実行中に登録してください。これにより、
	//  OLE ライブラリが他のアプリケーションからオブジェクトを作成できるようになります。
	COleObjectFactory::RegisterAll();

	return TRUE;
}

// DllGetClassObject - クラス ファクトリを返します。

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID* ppv)
{
	AFX_MANAGE_STATE(AfxGetStaticModuleState());
	return AfxDllGetClassObject(rclsid, riid, ppv);
}

// DllCanUnloadNow - COM が DLL をアンロードできるようにします。

STDAPI DllCanUnloadNow(void)
{
	AFX_MANAGE_STATE(AfxGetStaticModuleState());
	return AfxDllCanUnloadNow();
}

// DllRegisterServer - エントリをシステム レジストリに追加します。

STDAPI DllRegisterServer(void)
{
	AFX_MANAGE_STATE(AfxGetStaticModuleState());

	if (!AfxOleRegisterTypeLib(AfxGetInstanceHandle(), _tlid))
		return SELFREG_E_TYPELIB;

	if (!COleObjectFactory::UpdateRegistryAll())
		return SELFREG_E_CLASS;

	return S_OK;
}


// DllUnregisterServer - エントリをレジストリから削除します。

STDAPI DllUnregisterServer(void)
{
	AFX_MANAGE_STATE(AfxGetStaticModuleState());

	if (!AfxOleUnregisterTypeLib(_tlid, _wVerMajor, _wVerMinor))
		return SELFREG_E_TYPELIB;

	if (!COleObjectFactory::UpdateRegistryAll(FALSE))
		return SELFREG_E_CLASS;

	return S_OK;
}
