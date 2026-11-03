#import <UIKit/UIKit.h>

@interface ListSheet : UITableViewController
- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSString *> *)items
                       symbol:(NSString *)symbol
                       select:(void (^)(NSUInteger index))select
                       delete:(void (^)(NSUInteger index))deleteItem;
@end
