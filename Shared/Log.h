#import <Foundation/Foundation.h>

void GPSNavSetLogComponent(NSString *component);
void GPSNavLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *GPSNavLogPath(NSString *component);
