// Hand-off 1 smoke: the Objective-C shell of a C consumer.
@import UIKit;
@import IosLibraryCApi;
#include "Scenarios.h"
#include <stdio.h>

static UIWindow* smokeWindow;

static void setWindowHidden(int hidden) {
    if (hidden) { smokeWindow.hidden = YES; } else { [smokeWindow makeKeyAndVisible]; }
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
    smokeWindow = self.window;
    printf("SMOKE ntk_version via @import = 0x%06x\n", ntk_version());
    smoke_run(setWindowHidden, finished);
    return YES;
}
@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SmokeAppDelegate class]));
    }
}
