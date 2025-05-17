//
//  UnityMacDialogManagerBridge.h
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h> // IosLibrary の Swift ヘッダーをインポート
#import <UnityMacPlugin/UnityMacPlugin-Swift.h> // 自動生成されるSwiftヘッダーをインポート

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*DialogManagerCallback)(const char* result);

void showDialog(const char* title,
                const char* message,
                DialogManagerCallback callback);

#ifdef __cplusplus
}
#endif
