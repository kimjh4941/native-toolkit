// Hand-off 2 smoke: the Objective-C shell (like Unity's .mm): installs in willFinishLaunching.
@import UIKit;
@import IosLibraryCApi;
#include "Scenarios.h"
#include <stdio.h>

static void finished(int failures) {
    printf("SMOKE RESULT failures=%d\n", failures);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);
}

@interface SmokeAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow* window;
@end

@implementation SmokeAppDelegate
- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    setvbuf(stdout, NULL, _IOLBF, 0);
    smoke_install();
    return YES;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    printf("SMOKE ntk_version = 0x%06x\n", ntk_version());
    smoke_run(finished);
    return YES;
}
@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SmokeAppDelegate class]));
    }
}
