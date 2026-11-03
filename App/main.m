#import "MapController.h"
#import "../Shared/Log.h"
#import <UIKit/UIKit.h>
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {
  GPSNavSetLogComponent(@"app");
  GPSNavLog(@"Launch iOS=%@ bundle=%@ home=%@ prefsWritable=%d", UIDevice.currentDevice.systemVersion, NSBundle.mainBundle.bundlePath, NSHomeDirectory(), [NSFileManager.defaultManager isWritableFileAtPath:@"/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist"] || (![NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist"] && [NSFileManager.defaultManager isWritableFileAtPath:@"/var/mobile/Library/Preferences"]));
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = MapController.new;
  [self.window makeKeyAndVisible];
  return YES;
}
@end
int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
  }
}
