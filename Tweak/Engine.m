#import <Foundation/Foundation.h>
#import <notify.h>
#import <math.h>
#import <string.h>
#import "../Shared/Geo.h"
#import "../Shared/Log.h"
static NSString *const configPath=@"/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist";
static NSString *const progressPath=@"/var/mobile/Library/Preferences/com.xtieume.gpsnav.progress.plist";
@interface GPSNavEngine : NSObject
@property NSMutableDictionary *config;
@property GPSPoint point;
@property NSInteger index, direction;
@property double fraction, lastRandom;
@property float speed, course;
@property int latToken, lonToken, flagsToken, motionToken;
@end
@implementation GPSNavEngine
- (instancetype)init { if ((self=[super init])) {
 notify_register_check("com.xtieume.gpsnav.lat", &_latToken); notify_register_check("com.xtieume.gpsnav.lon", &_lonToken); notify_register_check("com.xtieume.gpsnav.flags", &_flagsToken); notify_register_check("com.xtieume.gpsnav.motion", &_motionToken);
 [self reload];
 int token; notify_register_dispatch("com.xtieume.gpsnav.reload", &token, dispatch_get_main_queue(), ^(int t){ [self reload]; });
 [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
 } return self; }
- (void)reload {
 GPSNavLog(@"Reload preferences %@", configPath);
 NSDictionary *old=self.config; self.config=[NSMutableDictionary dictionaryWithContentsOfFile:configPath] ?: NSMutableDictionary.new;
 BOOL changed = !old || ![old[@"revision"] isEqual:self.config[@"revision"]];
 if (changed) {
 NSDictionary *progress=[NSDictionary dictionaryWithContentsOfFile:progressPath];
 BOOL resume=!old && [progress[@"revision"] isEqual:self.config[@"revision"]];
 self.point=(GPSPoint){[self.config[@"latitude"] doubleValue], [self.config[@"longitude"] doubleValue]};
 self.index=0; self.direction=1; self.fraction=0; self.lastRandom=0;
 if (resume) { self.point=(GPSPoint){[progress[@"lat"] doubleValue],[progress[@"lon"] doubleValue]}; self.index=[progress[@"index"] integerValue]; self.direction=[progress[@"direction"] integerValue] ?: 1; self.fraction=[progress[@"fraction"] doubleValue]; self.lastRandom=[progress[@"lastRandom"] doubleValue]; }
 }
 [self publish];
}
- (void)publish {
 uint64_t lat,lon; memcpy(&lat,&_point.lat,8); memcpy(&lon,&_point.lon,8);
 uint32_t s,c; memcpy(&s,&_speed,4); memcpy(&c,&_course,4);
 notify_set_state(self.latToken,lat); notify_set_state(self.lonToken,lon); notify_set_state(self.motionToken,((uint64_t)c<<32)|s); notify_set_state(self.flagsToken,[self.config[@"enabled"] boolValue]?1:0); notify_post("com.xtieume.gpsnav.changed");
}
- (void)tick {
 self.speed=0; self.course=0;
 if ([self.config[@"enabled"] boolValue]) {
 NSString *mode=self.config[@"mode"] ?: @"fixed";
 if ([mode isEqual:@"random"]) {
 double now=NSDate.date.timeIntervalSince1970, interval=MAX(1,[self.config[@"interval"] doubleValue]);
 if (now-self.lastRandom>=interval) { GPSPoint center={[self.config[@"latitude"] doubleValue],[self.config[@"longitude"] doubleValue]}; double u=(double)arc4random()/UINT32_MAX, v=(double)arc4random()/UINT32_MAX; self.point=gps_offset(center,MAX(0,[self.config[@"radius"] doubleValue])*sqrt(u),360*v); self.lastRandom=now; }
 } else if ([mode isEqual:@"route"]) {
 NSArray *points=self.config[@"route"]; NSInteger n=points.count; double remaining=MAX(0,[self.config[@"speed"] doubleValue]/3.6); double requested=remaining; NSInteger iterations=0;
 while (n>1 && remaining>0 && iterations++<n*2+2) {
 NSInteger next=self.index+self.direction;
 if (self.index<0 || self.index>=n || next<0 || next>=n) { if (![self.config[@"loop"] boolValue]) break; self.direction=-self.direction; next=self.index+self.direction; }
 if (next<0 || next>=n) break;
 NSArray *a=points[self.index], *b=points[next]; if (![a isKindOfClass:NSArray.class] || ![b isKindOfClass:NSArray.class] || a.count<2 || b.count<2) break;
 GPSPoint start={[a[0] doubleValue],[a[1] doubleValue]}, end={[b[0] doubleValue],[b[1] doubleValue]}; double length=gps_distance(start,end), left=length*(1-self.fraction);
 self.course=gps_bearing(start,end);
 if (length<0.01 || remaining>=left) { remaining-=left; self.point=end; self.index=next; self.fraction=0; if ((self.index==0 || self.index==n-1) && ![self.config[@"loop"] boolValue]) break; }
 else { self.fraction+=remaining/length; self.point=gps_interpolate(start,end,self.fraction); remaining=0; }
 }
 self.speed=(float)(requested-remaining);
 }
 }
 [self publish];
 if (self.config[@"revision"]) { NSDictionary *p=@{@"revision":self.config[@"revision"],@"lat":@(self.point.lat),@"lon":@(self.point.lon),@"index":@(self.index),@"direction":@(self.direction),@"fraction":@(self.fraction),@"lastRandom":@(self.lastRandom)}; [p writeToFile:progressPath atomically:YES]; }
}
@end
void GPSNavStartEngine(void) { GPSNavSetLogComponent(@"engine"); GPSNavLog(@"Engine starting bundle=%@", NSBundle.mainBundle.bundleIdentifier); static GPSNavEngine *engine; if (!engine) engine=GPSNavEngine.new; }
