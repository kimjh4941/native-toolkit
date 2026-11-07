// The smoke of the iOS C ABI, its Objective-C part (C ABI design part 2, 12.4): the host. It reads
// the C ABI through the framework's module, as an Objective-C user does, installs the notification
// delegate during launch (README 3.1) and starts the C steps once a scene is active.
@import IosLibraryCApi;
@import UIKit;

#include <stdio.h>
#include <stdlib.h>

#include "Smoke.h"

@interface SmokeAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface SmokeSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

// What ntk_notification_install returned; -1 until it ran.
static int32_t installResult = -1;

static void smokeFinished(int failures) {
    printf("SMOKE RESULT %s failures=%d\n", failures == 0 ? "PASS" : "FAIL", failures);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);
}

@implementation SmokeAppDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // On the main thread, before launching ends: what the C ABI asks of its host.
    installResult = ntk_notification_install();
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default"
                                                                         sessionRole:connectingSceneSession.role];
    configuration.delegateClass = [SmokeSceneDelegate class];
    return configuration;
}

@end

@implementation SmokeSceneDelegate {
    BOOL _started;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] init];
    label.text = @"IosLibraryCApiSmoke";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [root.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:root.view.centerYAnchor],
    ]];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    if (_started) {
        return;
    }
    _started = YES;
    smoke_run(installResult, smokeFinished);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SmokeAppDelegate class]));
    }
}
