#import "LogSheet.h"
#import "../Shared/Log.h"
@interface LogSheet ()
@property UISegmentedControl *segments;
@property UITextView *textView;
@property (copy) void (^diagnostics)(void);
@end
@implementation LogSheet
- (instancetype)initWithDiagnostics:(void (^)(void))diagnostics {
  self = [super init];
  if (self) self.diagnostics = diagnostics;
  return self;
}
- (NSString *)component {
  return @[@"app", @"engine", @"tweak"][self.segments.selectedSegmentIndex];
}
- (UIBarButtonItem *)item:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol] style:UIBarButtonItemStylePlain target:self action:action];
  item.accessibilityLabel = label;
  return item;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Logs";
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
  self.segments = [[UISegmentedControl alloc] initWithItems:@[@"App", @"Engine", @"Tweak"]];
  self.segments.selectedSegmentIndex = 0;
  [self.segments addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
  self.segments.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.segments];
  self.textView = UITextView.new;
  self.textView.editable = NO;
  self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
  self.textView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.textView];
  UIToolbar *toolbar = UIToolbar.new;
  toolbar.translatesAutoresizingMaskIntoConstraints = NO;
  UIBarButtonItem *space1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *space2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *space3 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  UIBarButtonItem *space4 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  toolbar.items = @[[self item:@"arrow.clockwise" label:@"Refresh" action:@selector(refresh)], space1, [self item:@"stethoscope" label:@"Run diagnostics" action:@selector(runDiagnostics)], space2, [self item:@"doc.on.doc" label:@"Copy" action:@selector(copyLog)], space3, [self item:@"square.and.arrow.up" label:@"Share" action:@selector(share:)], space4, [self item:@"trash" label:@"Clear" action:@selector(clear)]];
  [self.view addSubview:toolbar];
  [NSLayoutConstraint activateConstraints:@[
    [self.segments.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
    [self.segments.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [self.segments.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [self.textView.topAnchor constraintEqualToAnchor:self.segments.bottomAnchor constant:8],
    [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.textView.bottomAnchor constraintEqualToAnchor:toolbar.topAnchor],
    [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
  ]];
  [self refresh];
}
- (void)refresh {
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:GPSNavLogPath(self.component) encoding:NSUTF8StringEncoding error:&error];
  self.textView.text = content ?: [NSString stringWithFormat:@"Unable to read log: %@", error.localizedDescription];
  if (self.textView.text.length) [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length - 1, 1)];
}
- (void)runDiagnostics {
  if (self.diagnostics) self.diagnostics();
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self refresh]; });
}
- (void)copyLog { UIPasteboard.generalPasteboard.string = self.textView.text; }
- (void)share:(UIBarButtonItem *)sender {
  NSURL *url = [NSURL fileURLWithPath:GPSNavLogPath(self.component)];
  if (![NSFileManager.defaultManager isReadableFileAtPath:url.path]) return;
  UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
  activity.popoverPresentationController.barButtonItem = sender;
  [self presentViewController:activity animated:YES completion:nil];
}
- (void)clear {
  NSError *error = nil;
  [@"" writeToFile:GPSNavLogPath(self.component) atomically:YES encoding:NSUTF8StringEncoding error:&error];
  [self refresh];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
