// WindowsLibrary.h : WindowsLibrary DLL のメイン ヘッダー ファイル
//

#pragma once

#ifndef __AFXWIN_H__
	#error "PCH に対してこのファイルをインクルードする前に 'pch.h' をインクルードしてください"
#endif

#include "resource.h"		// メイン シンボル


// CWindowsLibraryApp
// このクラスの実装に関しては WindowsLibrary.cpp をご覧ください
//

class CWindowsLibraryApp : public CWinApp
{
public:
	CWindowsLibraryApp();

// オーバーライド
public:
	virtual BOOL InitInstance();

	DECLARE_MESSAGE_MAP()
};
