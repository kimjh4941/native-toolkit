// UnityWindowsPlugin.h : UnityWindowsPlugin DLL のメイン ヘッダー ファイル
//

#pragma once

#ifndef __AFXWIN_H__
	#error "PCH に対してこのファイルをインクルードする前に 'pch.h' をインクルードしてください"
#endif

#include "resource.h"		// メイン シンボル


// CUnityWindowsPluginApp
// このクラスの実装に関しては UnityWindowsPlugin.cpp をご覧ください
//

class CUnityWindowsPluginApp : public CWinApp
{
public:
	CUnityWindowsPluginApp();

// オーバーライド
public:
	virtual BOOL InitInstance();

	DECLARE_MESSAGE_MAP()
};
