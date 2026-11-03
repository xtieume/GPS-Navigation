#import "ListSheet.h"

@interface ListSheet ()
@property NSMutableArray<NSString *> *items;
@property NSString *symbol;
@property(copy) void (^selectItem)(NSUInteger);
@property(copy) void (^deleteItem)(NSUInteger);
@end

@implementation ListSheet
- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSString *> *)items
                       symbol:(NSString *)symbol
                       select:(void (^)(NSUInteger))select
                       delete:(void (^)(NSUInteger))deleteItem {
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
  if (self) {
    self.title = title;
    self.items = [items mutableCopy];
    self.symbol = symbol;
    self.selectItem = select;
    self.deleteItem = deleteItem;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                    target:self
                                                    action:@selector(close)];
  [self updateEmptyState];
}

- (void)close {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateEmptyState {
  if (self.items.count) {
    self.tableView.backgroundView = nil;
    return;
  }
  UIStackView *empty = UIStackView.new;
  empty.axis = UILayoutConstraintAxisVertical;
  empty.alignment = UIStackViewAlignmentCenter;
  empty.distribution = UIStackViewDistributionEqualCentering;
  empty.spacing = 12;
  UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.symbol]];
  image.tintColor = UIColor.secondaryLabelColor;
  UILabel *label = UILabel.new;
  label.text = [NSString stringWithFormat:@"No %@ yet", self.title.lowercaseString];
  label.textColor = UIColor.secondaryLabelColor;
  label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  [empty addArrangedSubview:image];
  [empty addArrangedSubview:label];
  UIView *background = UIView.new;
  empty.translatesAutoresizingMaskIntoConstraints = NO;
  [background addSubview:empty];
  [NSLayoutConstraint activateConstraints:@[
    [empty.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
    [empty.centerYAnchor constraintEqualToAnchor:background.centerYAnchor]
  ]];
  self.tableView.backgroundView = background;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:@"item"];
  }
  cell.textLabel.text = self.items[indexPath.row];
  cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  cell.textLabel.adjustsFontForContentSizeCategory = YES;
  cell.imageView.image = [UIImage systemImageNamed:self.symbol];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  NSUInteger index = indexPath.row;
  [self dismissViewControllerAnimated:YES
                           completion:^{
                             if (self.selectItem)
                               self.selectItem(index);
                           }];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
  return self.deleteItem != nil;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)indexPath {
  if (style != UITableViewCellEditingStyleDelete || !self.deleteItem)
    return;
  self.deleteItem(indexPath.row);
  [self.items removeObjectAtIndex:indexPath.row];
  [tableView deleteRowsAtIndexPaths:@[ indexPath ]
                   withRowAnimation:UITableViewRowAnimationAutomatic];
  [self updateEmptyState];
}
@end
