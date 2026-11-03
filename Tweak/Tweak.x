#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <string.h>
#import "../Shared/Log.h"
extern void GPSNavStartEngine(void);
static int latToken, lonToken, flagsToken, motionToken;
static BOOL blacklisted;
static CLLocation *fakeLocation(void) {
 if (blacklisted) return nil;
 uint64_t flags=0,lat=0,lon=0,motion=0; notify_get_state(flagsToken,&flags); if (!(flags&1)) return nil;
 notify_get_state(latToken,&lat); notify_get_state(lonToken,&lon); notify_get_state(motionToken,&motion);
 double a,b; float speed,course; uint32_t s=(uint32_t)motion,c=(uint32_t)(motion>>32); memcpy(&a,&lat,8); memcpy(&b,&lon,8); memcpy(&speed,&s,4); memcpy(&course,&c,4);
 if (!CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(a,b))) return nil;
 static NSTimeInterval lastLog;
 @synchronized (CLLocation.class) {
  NSTimeInterval now = NSDate.date.timeIntervalSince1970;
  if (now - lastLog >= 10) {
   lastLog = now;
   GPSNavLog(@"Fake location bundle=%@ lat=%.8f lon=%.8f speed=%f course=%f", NSBundle.mainBundle.bundleIdentifier, a, b, speed, course);
  }
 }
 return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(a,b) altitude:0 horizontalAccuracy:5 verticalAccuracy:5 course:course speed:speed timestamp:NSDate.date];
}
@interface GPSNavDelegate : NSProxy <CLLocationManagerDelegate>
@property (nonatomic, weak) id<CLLocationManagerDelegate> target;
@property (nonatomic, weak) CLLocationManager *manager;
@property (nonatomic, strong) NSTimer *timer;
- (void)start;
- (void)stop;
@end
@implementation GPSNavDelegate
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [(id)self.target methodSignatureForSelector:s] ?: [NSObject instanceMethodSignatureForSelector:@selector(init)]; }
- (void)forwardInvocation:(NSInvocation *)inv { if ([self.target respondsToSelector:inv.selector]) [inv invokeWithTarget:self.target]; }
- (BOOL)respondsToSelector:(SEL)s { return s==@selector(locationManager:didUpdateLocations:) || [(id)self.target respondsToSelector:s]; }
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations { id<CLLocationManagerDelegate> target=self.target; if ([target respondsToSelector:_cmd]) { CLLocation *fake=fakeLocation(); [target locationManager:manager didUpdateLocations:fake ? @[fake] : locations]; } }
- (void)tick:(NSTimer *)timer { CLLocation *fake=fakeLocation(); id<CLLocationManagerDelegate> target=self.target; CLLocationManager *manager=self.manager; if (!manager || !target) { [self stop]; return; } if (fake && [target respondsToSelector:@selector(locationManager:didUpdateLocations:)]) [target locationManager:manager didUpdateLocations:@[fake]]; }
- (void)start { if (!self.timer) self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES]; }
- (void)stop { [self.timer invalidate]; self.timer=nil; }
@end
static const void *proxyKey=&proxyKey, *activeKey=&activeKey;
%hook CLLocationManager
- (CLLocation *)location { return fakeLocation() ?: %orig; }
- (void)setDelegate:(id<CLLocationManagerDelegate>)delegate {
 GPSNavDelegate *old=objc_getAssociatedObject(self,proxyKey); [old stop];
 if (!delegate || blacklisted) { objc_setAssociatedObject(self,proxyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); %orig(delegate); return; }
 GPSNavDelegate *proxy=[GPSNavDelegate alloc]; proxy.target=delegate; proxy.manager=self; objc_setAssociatedObject(self,proxyKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC); %orig((id)proxy);
 if ([objc_getAssociatedObject(self,activeKey) boolValue]) [proxy start];
}
- (id<CLLocationManagerDelegate>)delegate { GPSNavDelegate *proxy=objc_getAssociatedObject(self,proxyKey); return proxy ? proxy.target : %orig; }
- (void)startUpdatingLocation { objc_setAssociatedObject(self,activeKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [objc_getAssociatedObject(self,proxyKey) start]; %orig; }
- (void)stopUpdatingLocation { objc_setAssociatedObject(self,activeKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [objc_getAssociatedObject(self,proxyKey) stop]; %orig; }
- (void)requestLocation { %orig; }
%end
%ctor { @autoreleasepool {
 NSString *bundle=NSBundle.mainBundle.bundleIdentifier;
 if ([bundle isEqualToString:@"com.apple.springboard"]) { dispatch_async(dispatch_get_main_queue(), ^{ GPSNavStartEngine(); }); return; }
 if (!bundle.length || [bundle isEqualToString:@"com.xtieume.gpsnav"] || ![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) return;
 GPSNavSetLogComponent(@"tweak");
 GPSNavLog(@"Installing hooks bundle=%@", bundle);
 NSArray *list=[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist"][@"blacklist"]; blacklisted=[list containsObject:bundle];
 GPSNavLog(@"Hook configuration bundle=%@ blacklisted=%d", bundle, blacklisted);
 notify_register_check("com.xtieume.gpsnav.lat",&latToken); notify_register_check("com.xtieume.gpsnav.lon",&lonToken); notify_register_check("com.xtieume.gpsnav.flags",&flagsToken); notify_register_check("com.xtieume.gpsnav.motion",&motionToken); %init;
} }
