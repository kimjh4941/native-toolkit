//
//  UnityIosDialogManagerBridge.h
//
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h> // IosLibrary の Swift ヘッダーをインポート
#import <UnityIosPlugin/UnityIosPlugin-Swift.h> // 自動生成されるSwiftヘッダーをインポート

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
