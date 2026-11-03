#import "Log.h"
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *GPSNavComponent = @"app";
static dispatch_queue_t GPSNavLogQueue(void) {
  static dispatch_queue_t queue;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ queue = dispatch_queue_create("com.xtieume.gpsnav.log", DISPATCH_QUEUE_SERIAL); });
  return queue;
}
NSString *GPSNavLogPath(NSString *component) {
  return [@"/var/mobile/Library/Logs/GPSNav" stringByAppendingPathComponent:[component stringByAppendingString:@".log"]];
}
void GPSNavSetLogComponent(NSString *component) {
  @synchronized (NSObject.class) {
    GPSNavComponent = [component copy];
  }
}
void GPSNavLog(NSString *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  NSString *component;
  @synchronized (NSObject.class) {
    component = GPSNavComponent;
  }
  NSDate *date = NSDate.date;
  dispatch_async(GPSNavLogQueue(), ^{
    NSDateFormatter *formatter = NSDateFormatter.new;
    formatter.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n", [formatter stringFromDate:date], component, message];
    NSLog(@"%@", [line stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]);
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *file = GPSNavLogPath(component);
    [manager createDirectoryAtPath:file.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    chmod(file.stringByDeletingLastPathComponent.fileSystemRepresentation, 0777);
    NSString *lockPath = [file stringByAppendingString:@".lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0666);
    if (lock >= 0) {
      fchmod(lock, 0666);
      flock(lock, LOCK_EX);
    }
    NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:file] ?: NSMutableData.new;
    if (data.length > 1024 * 1024) {
      NSUInteger start = data.length / 2;
      const unsigned char *bytes = data.bytes;
      while (start < data.length && bytes[start - 1] != '\n') start++;
      [data replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    }
    [data appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [data writeToFile:file atomically:YES];
    chmod(file.fileSystemRepresentation, 0666);
    if (lock >= 0) {
      flock(lock, LOCK_UN);
      close(lock);
    }
  });
}
