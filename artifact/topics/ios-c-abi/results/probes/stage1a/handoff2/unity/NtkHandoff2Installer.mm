// Hand-off 2 probe: installs the library's notification delegate from a Unity iOS build (U-3, U-4).
// Put it in Assets/Plugins/iOS/ (it is compiled into UnityFramework) or add it to the UnityFramework
// target of the exported project. Choose the timing with NTK_HANDOFF2_INSTALL_AT below and rebuild:
//   1: kUnityWillFinishLaunchingWithOptions (the same point as the Unity notification package)
//   2: AppDelegateListener didFinishLaunching (Unity's UIApplicationDidFinishLaunchingNotification)
//   3: both 1 and 2 (the second call re-installs if someone replaced the delegate in between)
// It also logs the class of UNUserNotificationCenter.delegate at each point, so U-4 can record which
// delegate ends up in front. Never call ntk_notification_install off the main thread or before
// UIApplicationMain (+load only registers the observers).
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "AppDelegateListener.h"
#include <IosLibraryCApi/NativeToolkitC/Notification.h>

#ifndef NTK_HANDOFF2_INSTALL_AT
#define NTK_HANDOFF2_INSTALL_AT 1
#endif

static void NtkLogDelegate(NSString* point) {
    id delegate = UNUserNotificationCenter.currentNotificationCenter.delegate;
    NSLog(@"[NTK-HANDOFF2] %@ delegate=%@", point, delegate ? NSStringFromClass([delegate class]) : @"nil");
}

static void NtkInstall(NSString* point) {
    NtkLogDelegate([point stringByAppendingString:@" before"]);
    ntk_notification_error error = ntk_notification_install();
    NSLog(@"[NTK-HANDOFF2] install at %@ -> %d", point, (int)error);
    NtkLogDelegate([point stringByAppendingString:@" after"]);
}

@interface NtkHandoff2Installer : NSObject <AppDelegateListener>
@end

@implementation NtkHandoff2Installer

+ (void)load {
    static NtkHandoff2Installer* installer;
    installer = [NtkHandoff2Installer new];
    UnityRegisterAppDelegateListener(installer);
    if (NTK_HANDOFF2_INSTALL_AT == 1 || NTK_HANDOFF2_INSTALL_AT == 3) {
        [[NSNotificationCenter defaultCenter] addObserverForName:kUnityWillFinishLaunchingWithOptions object:nil
                                                           queue:nil usingBlock:^(NSNotification* note) {
            NtkInstall(@"kUnityWillFinishLaunchingWithOptions");
        }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification* note) {
        NtkLogDelegate(@"didBecomeActive");
    }];
}

- (void)didFinishLaunching:(NSNotification*)notification {
    if (NTK_HANDOFF2_INSTALL_AT == 2 || NTK_HANDOFF2_INSTALL_AT == 3) {
        NtkInstall(@"didFinishLaunching");
    } else {
        NtkLogDelegate(@"didFinishLaunching");
    }
}

@end
