// Stage 1a smoke: the Objective-C shell of a C consumer. Only UIKit and the module import live here.
@import UIKit;
@import IosLibraryCApi;   // the module map of IosLibraryCApi.framework
#include "Scenarios.h"
#include <stdio.h>

static void uncaught(NSException* exception) {
    printf("SMOKE uncaught exception name=%s reason=%s\n", exception.name.UTF8String, exception.reason.UTF8String);
    fflush(stdout);
}

static void finished(int failures) {
    printf("SMOKE RESULT failures=%d\n", failures);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);
}

@interface SmokeAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow* window;
@end

@implementation SmokeAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    setvbuf(stdout, NULL, _IOLBF, 0);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    NSSetUncaughtExceptionHandler(uncaught);
    printf("SMOKE ntk_version via @import = 0x%06x\n", ntk_version());

    NSString* scenario = [NSUserDefaults.standardUserDefaults stringForKey:@"scenario"] ?: @"basic";
    if ([scenario isEqualToString:@"basic"]) {
        [UIPasteboard pasteboardWithName:@"com.jonghyunkim.nativetoolkit.stage1a.probe" create:YES].string = @"smoke";
        smoke_run_basic(finished);
    } else {
        int32_t kind = (int32_t)scenario.integerValue;
        @try {
            printf("SMOKE raise kind=%d returned=%d\n", kind, smoke_raise(kind));
        } @catch (NSException* e) {
            printf("SMOKE caught synchronously: %s\n", e.name.UTF8String);   // not expected: the block is queued
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            printf("SMOKE still alive after 3 s\n");
            fflush(stdout);
            exit(0);
        });
    }
    return YES;
}
@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SmokeAppDelegate class]));
    }
}
