#import <UIKit/UIKit.h>
@interface LogSheet : UIViewController
- (instancetype)initWithDiagnostics:(void (^)(void))diagnostics;
@end
