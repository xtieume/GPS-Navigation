#import "MapController.h"
#import "ListSheet.h"
#import "LogSheet.h"
#import "TileMapView.h"
#import "Mercator.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import "../Shared/Log.h"
#import <MapKit/MapKit.h>
#import <notify.h>
static NSString *const path = @"/var/mobile/Library/Preferences/com.xtieume.gpsnav.plist";
@interface MapController () <UISearchBarDelegate, CLLocationManagerDelegate, UITableViewDataSource, UITableViewDelegate>
@property TileMapView *map;
@property UISegmentedControl *mode;
@property UISwitch *enabled;
@property UILabel *status;
@property NSMutableDictionary *config;
@property NSMutableArray *bookmarks, *routes, *history;
@property MKPointAnnotation *selection, *current, *start, *end;
@property MKPolyline *line;
@property MKDirections *directions;
@property NSUInteger routeGeneration;
@property int latToken, lonToken, flagsToken, motionToken;
@property UILabel *speedLabel;
@property UITableView *searchHistoryTable;
@property BOOL moving;
@property CGFloat course;
@property CLLocationManager *locationManager;
@property UIButton *locationButton;
@property UIButton *primaryButton;
@property UIStackView *modeControls;
@property UISearchBar *searchBar;
@property NSInteger routeTarget;
@property UILabel *attribution;
@property BOOL didDumpLayout;
@property BOOL panelCollapsed;
@property BOOL pendingLocationCenter;
@property NSUInteger locationRequestGeneration;
@property UILabel *locationToast;
@property UIVisualEffectView *panel;
@end
@implementation MapController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"GPSNav";
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  self.config = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: NSMutableDictionary.new;
  GPSNavLog(@"Preferences read %@: %@", path, self.config);
  NSDictionary *defaults = @{
    @"latitude" : @10.7769,
    @"longitude" : @106.7009,
    @"mode" : @"fixed",
    @"speed" : @40,
    @"radius" : @500,
    @"interval" : @30,
    @"loop" : @NO,
    @"enabled" : @NO,
    @"revision" : NSUUID.UUID.UUIDString,
    @"transport" : @"automobile"
  };
  for (NSString *key in defaults)
    if (!self.config[key])
      self.config[key] = defaults[key];
  self.bookmarks = [self.config[@"bookmarks"] mutableCopy] ?: NSMutableArray.new;
  self.routes = [self.config[@"savedRoutes"] mutableCopy] ?: NSMutableArray.new;
  self.history = [self.config[@"history"] mutableCopy] ?: NSMutableArray.new;
  notify_register_check("com.xtieume.gpsnav.lat", &_latToken);
  notify_register_check("com.xtieume.gpsnav.lon", &_lonToken);
  notify_register_check("com.xtieume.gpsnav.flags", &_flagsToken);
  notify_register_check("com.xtieume.gpsnav.motion", &_motionToken);
  self.panelCollapsed = [NSUserDefaults.standardUserDefaults boolForKey:@"panelCollapsed"];
  self.routeTarget = -1;
  self.locationManager = CLLocationManager.new;
  self.locationManager.delegate = self;
  self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
  self.locationManager.distanceFilter = 5;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
  [self applyMapTiles];
  CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(
      [self.config[@"latitude"] doubleValue], [self.config[@"longitude"] doubleValue]);
  [self.map setRegion:MKCoordinateRegionMakeWithDistance(coord, 5000, 5000) animated:NO];
  if (self.locationManager.authorizationStatus == kCLAuthorizationStatusNotDetermined)
    [self.locationManager requestWhenInUseAuthorization];
  [self buildInterface];
  self.current = MKPointAnnotation.new;
  self.current.title = @"Engine position";
  [self restoreRoute];
  [self updateSelection:coord];
  [self poll];
  [self refreshControls];
  [self startLocationUpdatesIfAllowed];
  [NSTimer scheduledTimerWithTimeInterval:1
                                   target:self
                                 selector:@selector(poll)
                                 userInfo:nil
                                  repeats:YES];
}
- (UIButton *)button:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:title forState:UIControlStateNormal];
  [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
  button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  button.titleLabel.adjustsFontForContentSizeCategory = YES;
  button.accessibilityLabel = title.length ? title : symbol;
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return button;
}
- (UIVisualEffectView *)blurView {
  UIVisualEffectView *view = [[UIVisualEffectView alloc]
      initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  view.layer.cornerRadius = 12;
  view.clipsToBounds = YES;
  return view;
}
- (void)buildInterface {
  UIVisualEffectView *searchContainer = [self blurView];
  [self.view addSubview:searchContainer];
  UIStackView *searchRow = [self row];
  searchRow.translatesAutoresizingMaskIntoConstraints = NO;
  [searchContainer.contentView addSubview:searchRow];
  self.searchBar = UISearchBar.new;
  self.searchBar.placeholder = @"Search places";
  self.searchBar.delegate = self;
  self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
  [self.searchBar setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [self.searchBar.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
  [searchRow addArrangedSubview:self.searchBar];
  UIButton *settings = [self button:@"" symbol:@"gearshape.fill" action:@selector(settings)];
  settings.accessibilityLabel = @"Settings";
  [settings.widthAnchor constraintEqualToConstant:44].active = YES;
  [searchRow addArrangedSubview:settings];
  self.searchHistoryTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
  self.searchHistoryTable.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchHistoryTable.dataSource = self;
  self.searchHistoryTable.delegate = self;
  self.searchHistoryTable.hidden = YES;
  self.searchHistoryTable.layer.cornerRadius = 12;
  [self.view addSubview:self.searchHistoryTable];
  UIVisualEffectView *floating = [self blurView];
  [self.view addSubview:floating];
  UIStackView *floatStack = UIStackView.new;
  floatStack.axis = UILayoutConstraintAxisVertical;
  floatStack.translatesAutoresizingMaskIntoConstraints = NO;
  [floating.contentView addSubview:floatStack];
  self.locationButton = [self button:@"" symbol:@"location" action:@selector(myLocation)];
  self.locationButton.accessibilityLabel = @"My location";
  [floatStack addArrangedSubview:self.locationButton];
  UIButton *saved = [self button:@"" symbol:@"star.fill" action:@selector(bookmarksMenu)];
  saved.accessibilityLabel = @"Bookmarks";
  [floatStack addArrangedSubview:saved];
  UIButton *routes = [self button:@"" symbol:@"map.fill" action:@selector(routesMenu)];
  routes.accessibilityLabel = @"Routes";
  [floatStack addArrangedSubview:routes];
  UIButton *history = [self button:@"" symbol:@"clock.arrow.circlepath" action:@selector(historyMenu)];
  history.accessibilityLabel = @"History";
  [floatStack addArrangedSubview:history];
  UIButton *logs = [self button:@"" symbol:@"doc.text.magnifyingglass" action:@selector(showLogs)];
  logs.accessibilityLabel = @"Logs";
  [floatStack addArrangedSubview:logs];
  for (UIView *button in floatStack.arrangedSubviews) {
    [button.widthAnchor constraintEqualToConstant:44].active = YES;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
  }
  UIVisualEffectView *speedPill = [self blurView];
  [self.view addSubview:speedPill];
  self.speedLabel = UILabel.new;
  self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.speedLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  self.speedLabel.adjustsFontForContentSizeCategory = YES;
  [speedPill.contentView addSubview:self.speedLabel];
  UIImageView *speedIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speedometer"]];
  speedIcon.translatesAutoresizingMaskIntoConstraints = NO;
  speedIcon.tintColor = UIColor.systemBlueColor;
  [speedPill.contentView addSubview:speedIcon];
  speedPill.hidden = YES;
  UIVisualEffectView *panel = [self blurView];
  self.panel = panel;
  panel.layer.cornerRadius = 16;
  panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
  panel.clipsToBounds = NO;
  panel.layer.shadowColor = UIColor.blackColor.CGColor;
  panel.layer.shadowOpacity = 0.15;
  panel.layer.shadowRadius = 12;
  panel.layer.shadowOffset = CGSizeMake(0, -3);
  [self.view addSubview:panel];
  UIStackView *controls = UIStackView.new;
  controls.axis = UILayoutConstraintAxisVertical;
  controls.spacing = 8;
  controls.translatesAutoresizingMaskIntoConstraints = NO;
  [panel.contentView addSubview:controls];
  UIView *grabber = UIView.new;
  grabber.backgroundColor = UIColor.tertiaryLabelColor;
  grabber.layer.cornerRadius = 2.5;
  [grabber.widthAnchor constraintEqualToConstant:36].active = YES;
  [grabber.heightAnchor constraintEqualToConstant:5].active = YES;
  UIStackView *handle = [[UIStackView alloc] initWithArrangedSubviews:@[ grabber ]];
  handle.alignment = UIStackViewAlignmentCenter;
  handle.axis = UILayoutConstraintAxisVertical;
  handle.userInteractionEnabled = YES;
  handle.accessibilityLabel = @"Toggle panel";
  handle.isAccessibilityElement = YES;
  handle.accessibilityTraits = UIAccessibilityTraitButton;
  [handle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)]];
  [handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];
  [controls addArrangedSubview:handle];
  self.mode = [[UISegmentedControl alloc] initWithItems:@[ @"Fixed", @"Route", @"Random" ]];
  [self updateModeImages];
  self.mode.selectedSegmentIndex = [self.config[@"mode"] isEqual:@"route"]
                                       ? 1
                                       : ([self.config[@"mode"] isEqual:@"random"] ? 2 : 0);
  [self.mode addTarget:self
                action:@selector(modeChanged)
      forControlEvents:UIControlEventValueChanged];
  NSLayoutConstraint *modeHeight = [self.mode.heightAnchor constraintEqualToConstant:34];
  modeHeight.priority = UILayoutPriorityDefaultHigh;
  modeHeight.active = YES;
  [controls addArrangedSubview:self.mode];
  self.enabled = UISwitch.new;
  self.enabled.on = [self.config[@"enabled"] boolValue];
  self.status = UILabel.new;
  CGFloat statusSize = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote].pointSize;
  self.status.font = [UIFont monospacedDigitSystemFontOfSize:statusSize weight:UIFontWeightRegular];
  self.status.adjustsFontForContentSizeCategory = YES;
  self.status.numberOfLines = 1;
  [self.status.heightAnchor constraintEqualToConstant:16].active = YES;
  self.status.userInteractionEnabled = YES;
  self.status.accessibilityLabel = @"Copy coordinates";
  [self.status addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                        initWithTarget:self
                                                action:@selector(copyCoordinates)]];
  [controls addArrangedSubview:self.status];
  self.modeControls = UIStackView.new;
  self.modeControls.axis = UILayoutConstraintAxisVertical;
  self.modeControls.spacing = 4;
  NSLayoutConstraint *controlsHeight = [self.modeControls.heightAnchor constraintEqualToConstant:36];
  controlsHeight.priority = UILayoutPriorityDefaultHigh;
  controlsHeight.active = YES;
  [controls addArrangedSubview:self.modeControls];
  self.mode.hidden = self.panelCollapsed;
  self.modeControls.hidden = self.panelCollapsed;
  self.primaryButton = [self button:@"Start spoofing"
                             symbol:@"play.fill"
                             action:@selector(toggleEnabled)];
  self.primaryButton.layer.cornerRadius = 12;
  self.primaryButton.clipsToBounds = YES;
  [self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  self.primaryButton.tintColor = UIColor.whiteColor;
  [self.primaryButton.heightAnchor constraintEqualToConstant:44].active = YES;
  [controls addArrangedSubview:self.primaryButton];
  UILabel *attribution = UILabel.new;
  self.attribution = attribution;
  attribution.hidden = NO;
  attribution.text = @"© OpenStreetMap contributors";
  attribution.font = [UIFont systemFontOfSize:10];
  attribution.textColor = UIColor.labelColor;
  attribution.backgroundColor = UIColor.secondarySystemBackgroundColor;
  attribution.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:attribution];
  [NSLayoutConstraint activateConstraints:@[
    [searchContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                              constant:8],
    [searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [searchRow.topAnchor constraintEqualToAnchor:searchContainer.contentView.topAnchor],
    [searchRow.bottomAnchor constraintEqualToAnchor:searchContainer.contentView.bottomAnchor],
    [searchRow.leadingAnchor constraintEqualToAnchor:searchContainer.contentView.leadingAnchor],
    [searchRow.trailingAnchor constraintEqualToAnchor:searchContainer.contentView.trailingAnchor
                                             constant:-4],
    [self.searchHistoryTable.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:8],
    [self.searchHistoryTable.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor],
    [self.searchHistoryTable.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor],
    [self.searchHistoryTable.heightAnchor constraintEqualToConstant:220],
    [speedPill.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
    [speedPill.bottomAnchor constraintEqualToAnchor:panel.topAnchor constant:-12],
    [self.speedLabel.topAnchor constraintEqualToAnchor:speedPill.contentView.topAnchor constant:8],
    [self.speedLabel.bottomAnchor constraintEqualToAnchor:speedPill.contentView.bottomAnchor constant:-8],
    [speedIcon.leadingAnchor constraintEqualToAnchor:speedPill.contentView.leadingAnchor constant:12],
    [speedIcon.centerYAnchor constraintEqualToAnchor:self.speedLabel.centerYAnchor],
    [self.speedLabel.leadingAnchor constraintEqualToAnchor:speedIcon.trailingAnchor constant:8],
    [self.speedLabel.trailingAnchor constraintEqualToAnchor:speedPill.contentView.trailingAnchor constant:-12],
    [floating.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:12],
    [floating.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [floating.widthAnchor constraintEqualToConstant:44],
    [floatStack.topAnchor constraintEqualToAnchor:floating.contentView.topAnchor],
    [floatStack.bottomAnchor constraintEqualToAnchor:floating.contentView.bottomAnchor],
    [floatStack.leadingAnchor constraintEqualToAnchor:floating.contentView.leadingAnchor],
    [floatStack.trailingAnchor constraintEqualToAnchor:floating.contentView.trailingAnchor],
    [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [panel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [controls.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:8],
    [controls.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:16],
    [controls.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-16],
    [controls.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                          constant:-8],
    [attribution.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
    [attribution.bottomAnchor constraintEqualToAnchor:panel.topAnchor constant:-4]
  ]];
}
- (void)updateModeImages {
  NSArray *symbols = @[ @"mappin.and.ellipse", @"point.topleft.down.curvedto.point.bottomright.up", @"shuffle" ];
  NSArray *titles = @[ @"Fixed", @"Route", @"Random" ];
  for (NSUInteger i = 0; i < symbols.count; i++) {
    [self.mode setImage:[self segmentImage:symbols[i] title:titles[i]] forSegmentAtIndex:i];
  }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  if (self.mode && ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory])
    [self updateModeImages];
}
- (UIImage *)segmentImage:(NSString *)symbol title:(NSString *)title {
  UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
  UIImage *icon = [UIImage systemImageNamed:symbol];
  NSDictionary *attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.labelColor };
  CGSize textSize = [title sizeWithAttributes:attributes];
  CGFloat height = MAX(icon.size.height, textSize.height);
  CGSize size = CGSizeMake(icon.size.width + 4 + textSize.width, height);
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [icon drawAtPoint:CGPointMake(0, (height - icon.size.height) / 2)];
    [title drawAtPoint:CGPointMake(icon.size.width + 4, (height - textSize.height) / 2) withAttributes:attributes];
  }];
  return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
- (NSString *)radiusLabel:(NSNumber *)value {
  double meters = value.doubleValue;
  return meters >= 1000 ? [NSString stringWithFormat:@"%g km", meters / 1000] : [NSString stringWithFormat:@"%g m", meters];
}
- (NSString *)intervalLabel:(NSNumber *)value {
  double seconds = value.doubleValue;
  return seconds >= 60 ? [NSString stringWithFormat:@"%g min", seconds / 60] : [NSString stringWithFormat:@"%g s", seconds];
}
- (void)refreshControls {
  for (UIView *view in self.modeControls.arrangedSubviews.copy) {
    [self.modeControls removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  if (self.mode.selectedSegmentIndex == 0) {
    UIStackView *row = [self row];
    UILabel *hint = UILabel.new;
    hint.text = @"Long-press the map to pick a point";
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    hint.adjustsFontForContentSizeCategory = YES;
    [row addArrangedSubview:hint];
    UIButton *bookmark = [self button:@"" symbol:@"bookmark.fill" action:@selector(saveBookmark)];
    bookmark.accessibilityLabel = @"Save bookmark";
    [bookmark.widthAnchor constraintEqualToConstant:36].active = YES;
    [row addArrangedSubview:bookmark];
    [self.modeControls addArrangedSubview:row];
  } else if (self.mode.selectedSegmentIndex == 1) {
    UIStackView *row = [self row];
    NSString *a = self.start
                      ? [NSString stringWithFormat:@"A: %.4f, %.4f", self.start.coordinate.latitude,
                                                   self.start.coordinate.longitude]
                      : @"A: Set point";
    NSString *b = self.end
                      ? [NSString stringWithFormat:@"B: %.4f, %.4f", self.end.coordinate.latitude,
                                                   self.end.coordinate.longitude]
                      : @"B: Set point";
    UIButton *pointA = [self button:a symbol:@"circle.fill" action:@selector(targetA)];
    pointA.tintColor = UIColor.systemGreenColor;
    pointA.backgroundColor = UIColor.tertiarySystemFillColor;
    pointA.layer.cornerRadius = 12;
    UIButton *pointB = [self button:b symbol:@"mappin" action:@selector(targetB)];
    pointB.tintColor = UIColor.systemRedColor;
    pointB.backgroundColor = UIColor.tertiarySystemFillColor;
    pointB.layer.cornerRadius = 12;
    [row addArrangedSubview:pointA];
    [row addArrangedSubview:pointB];
    UIButton *swap = [self button:@"" symbol:@"arrow.up.arrow.down" action:@selector(swapRoute)];
    swap.accessibilityLabel = @"Swap route points";
    [row addArrangedSubview:swap];
    UIStackView *options = row;
    UIButton *speed = [self button:[NSString stringWithFormat:@"%@", self.config[@"speed"]]
                            symbol:@"speedometer"
                            action:@selector(routeOptions)];
    NSMutableArray *speedActions = NSMutableArray.new;
    for (NSNumber *value in @[ @5, @20, @40, @60, @80, @120 ]) {
      NSString *label = [value isEqual:@5]
                            ? @"Walk 5 km/h"
                            : ([value isEqual:@20] ? @"Bike 20 km/h"
                                                   : [NSString stringWithFormat:@"%@ km/h", value]);
      [speedActions addObject:[UIAction actionWithTitle:label
                                                  image:nil
                                             identifier:nil
                                                handler:^(__kindof UIAction *action) {
                                                  self.config[@"speed"] = value;
                                                  [self save:NO];
                                                  [self refreshControls];
                                                }]];
    }
    [speedActions addObject:[UIAction actionWithTitle:@"Custom…"
                                                image:nil
                                           identifier:nil
                                              handler:^(__kindof UIAction *action) {
                                                [self
                                                    numberPrompt:@"Speed (km/h)"
                                                           value:[self.config[@"speed"] doubleValue]
                                                      completion:^(double value) {
                                                        self.config[@"speed"] = @(value);
                                                        [self save:NO];
                                                        [self refreshControls];
                                                      }];
                                              }]];
    [speedActions addObject:[UIAction actionWithTitle:@"Route options"
                                                image:[UIImage systemImageNamed:@"gearshape.fill"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *action) {
                                                [self routeOptions];
                                              }]];
    speed.menu = [UIMenu menuWithChildren:speedActions];
    speed.showsMenuAsPrimaryAction = YES;
    [options addArrangedSubview:speed];
    UIButton *loop = [self button:@""
                           symbol:@"arrow.triangle.2.circlepath"
                           action:@selector(toggleLoop)];
    loop.accessibilityLabel = @"Toggle route loop";
    loop.tintColor =
        [self.config[@"loop"] boolValue] ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
    [options addArrangedSubview:loop];
    [options addArrangedSubview:[self button:@""
                                      symbol:@"bookmark.fill"
                                      action:@selector(saveRoute)]];
    for (UIButton *chip in @[pointA, pointB]) {
      chip.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
      chip.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
      [chip setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    }
    [pointA.widthAnchor constraintEqualToAnchor:pointB.widthAnchor].active = YES;
    for (UIButton *icon in @[swap, loop]) [icon.widthAnchor constraintEqualToConstant:30].active = YES;
    UIButton *saveRouteButton = options.arrangedSubviews.lastObject;
    saveRouteButton.accessibilityLabel = @"Save route";
    [saveRouteButton.widthAnchor constraintEqualToConstant:30].active = YES;
    speed.accessibilityLabel = @"Route speed";
    [self.modeControls addArrangedSubview:options];
  } else {
    UIStackView *row = [self row];
    UIButton *radius = [self button:[self radiusLabel:self.config[@"radius"]]
                             symbol:@"scope"
                             action:@selector(randomOptions)];
    UIButton *interval = [self button:[self intervalLabel:self.config[@"interval"]]
                               symbol:@"timer"
                               action:@selector(randomOptions)];
    NSMutableArray *radii = NSMutableArray.new;
    for (NSNumber *value in @[ @100, @500, @1000, @5000 ]) {
      [radii addObject:[UIAction actionWithTitle:[self radiusLabel:value]
                                           image:nil
                                      identifier:nil
                                         handler:^(__kindof UIAction *action) {
                                           self.config[@"radius"] = value;
                                           [self save:NO];
                                           [self refreshControls];
                                         }]];
    }
    radius.menu = [UIMenu menuWithChildren:radii];
    radius.showsMenuAsPrimaryAction = YES;
    NSMutableArray *intervals = NSMutableArray.new;
    for (NSNumber *value in @[ @10, @30, @60, @300 ]) {
      [intervals addObject:[UIAction actionWithTitle:[self intervalLabel:value]
                                               image:nil
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
                                               self.config[@"interval"] = value;
                                               [self save:NO];
                                               [self refreshControls];
                                             }]];
    }
    interval.menu = [UIMenu menuWithChildren:intervals];
    interval.showsMenuAsPrimaryAction = YES;
    [row addArrangedSubview:radius];
    [row addArrangedSubview:interval];
    [self.modeControls addArrangedSubview:row];
  }
  BOOL on = self.enabled.on;
  [self.primaryButton setTitle:on ? @"Stop" : @"Start spoofing" forState:UIControlStateNormal];
  [self.primaryButton setImage:[UIImage systemImageNamed:on ? @"stop.fill" : @"play.fill"]
                      forState:UIControlStateNormal];
  self.primaryButton.backgroundColor = on ? UIColor.systemRedColor : UIColor.systemBlueColor;
}
- (void)setPanelCollapsed:(BOOL)collapsed animated:(BOOL)animated {
  _panelCollapsed = collapsed;
  [NSUserDefaults.standardUserDefaults setBool:collapsed forKey:@"panelCollapsed"];
  void (^changes)(void) = ^{
    self.mode.hidden = collapsed;
    self.modeControls.hidden = collapsed;
    [self.view layoutIfNeeded];
  };
  if (animated) [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:changes completion:nil];
  else changes();
}
- (void)togglePanel { [self setPanelCollapsed:!self.panelCollapsed animated:YES]; }
- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateEnded) {
    CGFloat delta = [gesture translationInView:self.view].y;
    if (fabs(delta) > 8) [self setPanelCollapsed:delta > 0 animated:YES];
  }
}
- (CGFloat)panelInset { return self.view.bounds.size.height - CGRectGetMinY(self.panel.frame); }
- (void)centerOnCoordinate:(CLLocationCoordinate2D)coordinate {
  GPSNavLog(@"centerOnCoordinate latitude=%.8f longitude=%.8f", coordinate.latitude, coordinate.longitude);
  double zoom = MAX(self.map.zoom, 16);
  double y = gps_y(coordinate.latitude) + [self panelInset] / (2.0 * 256.0 * pow(2, zoom));
  [self.map setCenterCoordinate:CLLocationCoordinate2DMake(gps_lat(y), coordinate.longitude) zoom:zoom animated:YES];
}
- (void)toggleEnabled {
  self.enabled.on = !self.enabled.on;
  [self enabledChanged];
  [self refreshControls];
  [[[UINotificationFeedbackGenerator alloc] init]
      notificationOccurred:UINotificationFeedbackTypeSuccess];
}
- (void)copyCoordinates {
  BOOL active = [self.map.annotations containsObject:self.current];
  double latitude = active ? self.current.coordinate.latitude : [self.config[@"latitude"] doubleValue];
  double longitude = active ? self.current.coordinate.longitude : [self.config[@"longitude"] doubleValue];
  UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%.5f, %.5f", latitude, longitude];
}
- (BOOL)isFreshLocation:(CLLocation *)location {
  if (!location || location.horizontalAccuracy <= 0 || !CLLocationCoordinate2DIsValid(location.coordinate)) return NO;
  NSTimeInterval age = -location.timestamp.timeIntervalSinceNow;
  return age >= 0 && age <= 10;
}
- (void)startLocationUpdatesIfAllowed {
  CLAuthorizationStatus status = self.locationManager.authorizationStatus;
  if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
      (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse))
    [self.locationManager startUpdatingLocation];
}
- (void)appDidBecomeActive:(NSNotification *)notification { [self startLocationUpdatesIfAllowed]; }
- (void)appWillResignActive:(NSNotification *)notification { [self.locationManager stopUpdatingLocation]; }
- (void)finishWaitingForLocation {
  self.pendingLocationCenter = NO;
  self.locationRequestGeneration++;
  [self.locationToast removeFromSuperview];
  self.locationToast = nil;
}
- (void)showLocationToast {
  if (self.locationToast) return;
  UILabel *label = UILabel.new;
  label.text = @"Locating…";
  label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
  label.textColor = UIColor.whiteColor;
  label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.75];
  label.textAlignment = NSTextAlignmentCenter;
  label.layer.cornerRadius = 10; label.clipsToBounds = YES;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [label.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:80],
    [label.widthAnchor constraintEqualToConstant:110], [label.heightAnchor constraintEqualToConstant:36]
  ]];
  self.locationToast = label;
}
- (void)showLocation:(CLLocation *)location {
  self.map.userCoordinate = location.coordinate;
  self.map.horizontalAccuracy = location.horizontalAccuracy;
  self.map.userCourse = location.course;
  self.map.hasUserCoordinate = YES;
}
- (void)myLocation {
  CLAuthorizationStatus status = self.locationManager.authorizationStatus;
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    GPSNavLog(@"myLocation denied or restricted");
    [self finishWaitingForLocation];
    [self message:@"Allow location access in Settings to show your current location."];
    return;
  }
  CLLocation *location = self.locationManager.location;
  BOOL fresh = [self isFreshLocation:location];
  GPSNavLog(@"myLocation cached=%d fresh=%d waiting=%d", location != nil, fresh, !fresh);
  if (fresh && status != kCLAuthorizationStatusNotDetermined) {
    [self finishWaitingForLocation];
    [self showLocation:location];
    [self centerOnCoordinate:location.coordinate];
    return;
  }
  self.pendingLocationCenter = YES;
  NSUInteger generation = ++self.locationRequestGeneration;
  [self showLocationToast];
  if (status == kCLAuthorizationStatusNotDetermined) [self.locationManager requestWhenInUseAuthorization];
  else [self startLocationUpdatesIfAllowed];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    if (self.pendingLocationCenter && self.locationRequestGeneration == generation) {
      GPSNavLog(@"myLocation timed out waiting for a fresh fix");
      [self finishWaitingForLocation];
      [self message:@"Could not determine your location within 15 seconds."];
    }
  });
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  GPSNavLog(@"Location authorization=%ld", (long)manager.authorizationStatus);
  if (manager.authorizationStatus == kCLAuthorizationStatusDenied || manager.authorizationStatus == kCLAuthorizationStatusRestricted) {
    [manager stopUpdatingLocation];
    if (self.pendingLocationCenter) {
      [self finishWaitingForLocation];
      [self message:@"Allow location access in Settings to show your current location."];
    }
  } else [self startLocationUpdatesIfAllowed];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  for (CLLocation *location in locations) {
    NSTimeInterval age = -location.timestamp.timeIntervalSinceNow;
    GPSNavLog(@"Location update lat=%.8f lon=%.8f accuracy=%.2f age=%.2f", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy, age);
    [self showLocation:location];
    if (self.pendingLocationCenter && [self isFreshLocation:location]) {
      GPSNavLog(@"myLocation received fresh fix; centering");
      [self finishWaitingForLocation];
      [self centerOnCoordinate:location.coordinate];
    }
  }
  if (locations.count) [self.locationButton setImage:[UIImage systemImageNamed:@"location.fill"] forState:UIControlStateNormal];
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  GPSNavLog(@"Location error=%@", error);
  if (self.pendingLocationCenter) [self finishWaitingForLocation];
  [self message:[NSString stringWithFormat:@"Could not determine your location: %@", error.localizedDescription]];
}
- (void)targetA {
  self.routeTarget = 0;
}
- (void)targetB {
  self.routeTarget = 1;
}
- (void)toggleLoop {
  self.config[@"loop"] = @(![self.config[@"loop"] boolValue]);
  [self save:NO];
  [self refreshControls];
}
- (void)swapRoute {
  if (!self.start || !self.end)
    return;
  CLLocationCoordinate2D coordinate = self.start.coordinate;
  self.start.coordinate = self.end.coordinate;
  self.end.coordinate = coordinate;
  self.config[@"latitude"] = @(self.start.coordinate.latitude);
  self.config[@"longitude"] = @(self.start.coordinate.longitude);
  [self fetchRoute];
  [self refreshControls];
}
- (void)saveBookmark {
  [self namePrompt:@"Save bookmark"
        completion:^(NSString *name) {
          [self.bookmarks addObject:@{
            @"name" : name,
            @"lat" : self.config[@"latitude"],
            @"lon" : self.config[@"longitude"]
          }];
          [self save:NO];
        }];
}
- (void)saveRoute {
  NSArray *route = self.config[@"route"];
  if (route.count < 2) {
    [self message:@"Select a route first."];
    return;
  }
  [self namePrompt:@"Save route"
        completion:^(NSString *name) {
          [self.routes addObject:@{@"name" : name, @"route" : route}];
          [self save:NO];
        }];
}
- (UIStackView *)row {
  UIStackView *r = UIStackView.new;
  r.axis = UILayoutConstraintAxisHorizontal;
  r.distribution = UIStackViewDistributionEqualSpacing;
  r.alignment = UIStackViewAlignmentCenter;
  r.spacing = 8;
  return r;
}
- (UIStackView *)buttons:(NSArray *)titles selectors:(NSArray *)selectors {
  UIStackView *r = [self row];
  r.distribution = UIStackViewDistributionFillEqually;
  for (NSUInteger i = 0; i < titles.count; i++) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:titles[i] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13];
    [b addTarget:self
                  action:NSSelectorFromString(selectors[i])
        forControlEvents:UIControlEventTouchUpInside];
    [r addArrangedSubview:b];
  }
  return r;
}
- (void)save:(BOOL)reset {
  if (reset)
    self.config[@"revision"] = NSUUID.UUID.UUIDString;
  self.config[@"bookmarks"] = self.bookmarks;
  self.config[@"savedRoutes"] = self.routes;
  self.config[@"history"] = self.history;
  BOOL written = [self.config writeToFile:path atomically:YES];
  GPSNavLog(@"Preferences write %@ success=%d contents=%@", path, written, self.config);
  if (!written) {
    [self message:@"Could not save settings. Check jailbreak permissions."];
    return;
  }
  uint32_t result = notify_post("com.xtieume.gpsnav.reload");
  GPSNavLog(@"notify_post reload result=%u", result);
}
- (void)message:(NSString *)text {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GPSNav"
                                                             message:text
                                                      preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:a animated:YES completion:nil];
}
- (void)poll {
  uint64_t flags = 0;
  uint64_t a = 0;
  uint64_t b = 0;
  uint64_t motion = 0;
  notify_get_state(self.flagsToken, &flags);
  notify_get_state(self.latToken, &a);
  notify_get_state(self.lonToken, &b);
  notify_get_state(self.motionToken, &motion);
  double lat;
  double lon;
  float speed;
  float course;
  uint32_t speedBits = (uint32_t)motion;
  uint32_t courseBits = (uint32_t)(motion >> 32);
  memcpy(&lat, &a, sizeof(lat));
  memcpy(&lon, &b, sizeof(lon));
  memcpy(&speed, &speedBits, sizeof(speed));
  memcpy(&course, &courseBits, sizeof(course));
  BOOL active = (flags & 1) && CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon));
  self.moving = active && isfinite(speed) && speed > 0;
  self.course = isfinite(course) ? course : 0;
  self.map.course = self.course;
  [self.map setNeedsDisplay];
  self.speedLabel.superview.superview.hidden = !self.moving;
  self.speedLabel.text = [NSString stringWithFormat:@"%.0f km/h", speed * 3.6];
  if (active) {
    self.current.coordinate = CLLocationCoordinate2DMake(lat, lon);
    if (![self.map.annotations containsObject:self.current])
      [self.map addAnnotation:self.current];
  } else if ([self.map.annotations containsObject:self.current]) {
    [self.map removeAnnotation:self.current];
  }
  NSString *description = [NSString stringWithFormat:@"● %@ · %.5f, %.5f", active ? @"Spoofing" : @"Stopped",
                           active ? lat : [self.config[@"latitude"] doubleValue],
                           active ? lon : [self.config[@"longitude"] doubleValue]];
  NSMutableAttributedString *status = [[NSMutableAttributedString alloc] initWithString:description];
  [status addAttribute:NSForegroundColorAttributeName
                value:active ? UIColor.systemGreenColor : UIColor.systemGrayColor
                range:NSMakeRange(0, 1)];
  self.status.attributedText = status;
}
- (void)updateSelection:(CLLocationCoordinate2D)c {
  if (!self.selection) {
    self.selection = MKPointAnnotation.new;
    self.selection.title = @"Selected / random center";
    [self.map addAnnotation:self.selection];
  }
  self.selection.coordinate = c;
  [self syncSelectionVisibility];
  [self.map setNeedsDisplay];
}
- (void)syncSelectionVisibility {
  BOOL hide = self.mode.selectedSegmentIndex == 1 && self.start &&
    fabs(self.selection.coordinate.latitude - self.start.coordinate.latitude) < 1e-8 &&
    fabs(self.selection.coordinate.longitude - self.start.coordinate.longitude) < 1e-8;
  BOOL shown = [self.map.annotations containsObject:self.selection];
  if (hide && shown) [self.map removeAnnotation:self.selection];
  else if (!hide && !shown && self.selection) [self.map addAnnotation:self.selection];
}
- (void)modeChanged {
  self.config[@"mode"] =
      @[ @"fixed", @"route", @"random" ][(NSUInteger)self.mode.selectedSegmentIndex];
  [self save:YES];
  [self refreshControls];
  [self syncSelectionVisibility];
}
- (void)enabledChanged {
  if (self.enabled.on && self.mode.selectedSegmentIndex == 1 && [self.config[@"route"] count] < 2) {
    self.enabled.on = NO;
    [self message:@"Select two points and wait for a route first."];
    return;
  }
  self.config[@"enabled"] = @(self.enabled.on);
  [self save:NO];
}
- (void)mapTap:(UIGestureRecognizer *)gesture {
  if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] &&
      gesture.state != UIGestureRecognizerStateBegan)
    return;
  if ([gesture isKindOfClass:UITapGestureRecognizer.class] &&
      gesture.state != UIGestureRecognizerStateEnded)
    return;
  [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
  CLLocationCoordinate2D c = [self.map convertPoint:[gesture locationInView:self.map]
                               toCoordinateFromView:self.map];
  [self choose:c];
}
- (void)choose:(CLLocationCoordinate2D)c {
  if (self.mode.selectedSegmentIndex == 1) {
    if (self.routeTarget >= 0) {
      NSInteger target = self.routeTarget;
      self.routeTarget = -1;
      if (target == 0) {
        if (!self.start) {
          self.start = MKPointAnnotation.new;
          self.start.title = @"A";
          [self.map addAnnotation:self.start];
        }
        self.start.coordinate = c;
        self.config[@"latitude"] = @(c.latitude);
        self.config[@"longitude"] = @(c.longitude);
      } else {
        if (!self.end) {
          self.end = MKPointAnnotation.new;
          self.end.title = @"B";
          [self.map addAnnotation:self.end];
        }
        self.end.coordinate = c;
      }
      if (self.start && self.end)
        [self fetchRoute];
      else
        [self save:YES];
      [self syncSelectionVisibility];
      [self refreshControls];
      return;
    }
    if (!self.start || self.end) {
      [self clearRoute];
      self.start = MKPointAnnotation.new;
      self.start.title = @"A";
      self.start.coordinate = c;
      [self.map addAnnotation:self.start];
      self.config[@"latitude"] = @(c.latitude);
      self.config[@"longitude"] = @(c.longitude);
      [self save:YES];
    } else {
      self.end = MKPointAnnotation.new;
      self.end.title = @"B";
      self.end.coordinate = c;
      [self.map addAnnotation:self.end];
      [self fetchRoute];
    }
  } else {
    self.config[@"latitude"] = @(c.latitude);
    self.config[@"longitude"] = @(c.longitude);
    [self updateSelection:c];
    [self save:YES];
  }
  [self syncSelectionVisibility];
  [self refreshControls];
}
- (void)clearRoute {
  self.routeGeneration++;
  [self.directions cancel];
  if (self.start)
    [self.map removeAnnotation:self.start];
  if (self.end)
    [self.map removeAnnotation:self.end];
  if (self.line)
    [self.map removeOverlay:self.line];
  self.start = nil;
  self.end = nil;
  self.line = nil;
  [self.config removeObjectForKey:@"route"];
}
- (void)applyRoute:(MKPolyline *)line {
  if (self.line)
    [self.map removeOverlay:self.line];
  self.line = line;
  [self.map addOverlay:self.line level:MKOverlayLevelAboveLabels];
  NSUInteger count = line.pointCount;
  CLLocationCoordinate2D *coords = calloc(count, sizeof(*coords));
  [line getCoordinates:coords range:NSMakeRange(0, count)];
  NSMutableArray *points = NSMutableArray.new;
  for (NSUInteger i = 0; i < count; i++)
    [points addObject:@[ @(coords[i].latitude), @(coords[i].longitude) ]];
  free(coords);
  self.config[@"route"] = points;
  [self save:YES];
}
- (void)fetchJSON:(NSURL *)url completion:(void (^)(id, NSError *))completion {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setValue:@"GPSNav/1.0.5" forHTTPHeaderField:@"User-Agent"];
  [[[NSURLSession sharedSession]
      dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
          if (!error && [(NSHTTPURLResponse *)response statusCode] != 200)
            error = [NSError
                errorWithDomain:@"GPSNav"
                           code:[(NSHTTPURLResponse *)response statusCode]
                       userInfo:@{
                         NSLocalizedDescriptionKey : [NSString
                             stringWithFormat:@"Server returned HTTP %ld.",
                                              (long)[(NSHTTPURLResponse *)response statusCode]]
                       }];
          GPSNavLog(@"JSON request URL=%@ status=%ld bytes=%lu error=%@", url, (long)[(NSHTTPURLResponse *)response statusCode], (unsigned long)data.length, error);
          id json = nil;
          if (!error && data)
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
          GPSNavLog(@"JSON result URL=%@ result=%@ error=%@", url, json, error);
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(json, error);
          });
        }] resume];
}
- (void)fetchRoute {
  NSUInteger generation = ++self.routeGeneration;
  [self.directions cancel];
  CLLocationCoordinate2D start = self.start.coordinate, end = self.end.coordinate;
  BOOL walking = [self.config[@"transport"] isEqual:@"walking"];
  MKDirectionsRequest *request = MKDirectionsRequest.new;
  request.source =
      [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:start]];
  request.destination =
      [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:end]];
  request.transportType =
      walking ? MKDirectionsTransportTypeWalking : MKDirectionsTransportTypeAutomobile;
  self.directions = [[MKDirections alloc] initWithRequest:request];
  self.status.text = @"Loading route…";
  [self.directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response,
                                                              NSError *error) {
    GPSNavLog(@"MKDirections routes=%lu error=%@", (unsigned long)response.routes.count, error);
    if (generation != self.routeGeneration)
      return;
    MKRoute *route = response.routes.firstObject;
    if (!error && route.polyline.pointCount >= 2) {
      [self applyRoute:route.polyline];
      return;
    }
    NSString *url =
        [NSString stringWithFormat:@"https://router.project-osrm.org/route/v1/%@/"
                                   @"%.8f,%.8f;%.8f,%.8f?overview=full&geometries=geojson",
                                   walking ? @"foot" : @"driving", start.longitude, start.latitude,
                                   end.longitude, end.latitude];
    [self fetchJSON:[NSURL URLWithString:url]
         completion:^(id json, NSError *fallbackError) {
           if (generation != self.routeGeneration)
             return;
           NSArray *routes = [json isKindOfClass:NSDictionary.class] ? json[@"routes"] : nil;
           NSDictionary *first = [routes isKindOfClass:NSArray.class] ? routes.firstObject : nil;
           NSArray *coordinates =
               [first isKindOfClass:NSDictionary.class] ? first[@"geometry"][@"coordinates"] : nil;
           NSMutableArray *valid = NSMutableArray.new;
           if ([coordinates isKindOfClass:NSArray.class])
             for (id pair in coordinates)
               if ([pair isKindOfClass:NSArray.class] && [pair count] >= 2 &&
                   [pair[0] respondsToSelector:@selector(doubleValue)] &&
                   [pair[1] respondsToSelector:@selector(doubleValue)]) {
                 CLLocationCoordinate2D c =
                     CLLocationCoordinate2DMake([pair[1] doubleValue], [pair[0] doubleValue]);
                 if (CLLocationCoordinate2DIsValid(c))
                   [valid addObject:pair];
               }
           if (valid.count < 2) {
             NSString *reason=fallbackError.localizedDescription ?: ([json isKindOfClass:NSDictionary.class]?json[@"message"]:nil) ?: @"No route found.";
             [self message:reason];
             return;
           }
           CLLocationCoordinate2D *coords = calloc(valid.count, sizeof(*coords));
           for (NSUInteger i = 0; i < valid.count; i++)
             coords[i] =
                 CLLocationCoordinate2DMake([valid[i][1] doubleValue], [valid[i][0] doubleValue]);
           MKPolyline *line = [MKPolyline polylineWithCoordinates:coords count:valid.count];
           free(coords);
           [self applyRoute:line];
         }];
  }];
}
- (void)restoreRoute {
  NSArray *points = self.config[@"route"];
  if (points.count < 2)
    return;
  CLLocationCoordinate2D *coords = calloc(points.count, sizeof(*coords));
  for (NSUInteger i = 0; i < points.count; i++)
    coords[i] = CLLocationCoordinate2DMake([points[i][0] doubleValue], [points[i][1] doubleValue]);
  self.start = MKPointAnnotation.new;
  self.start.title = @"A";
  self.start.coordinate = coords[0];
  self.end = MKPointAnnotation.new;
  self.end.title = @"B";
  self.end.coordinate = coords[points.count - 1];
  [self.map addAnnotations:@[ self.start, self.end ]];
  self.line = [MKPolyline polylineWithCoordinates:coords count:points.count];
  [self.map addOverlay:self.line level:MKOverlayLevelAboveLabels];
  free(coords);
}
- (void)presentList:(NSString *)title
              items:(NSArray<NSString *> *)items
             symbol:(NSString *)symbol
             select:(void (^)(NSUInteger))select
             delete:(void (^)(NSUInteger))deleteItem {
  ListSheet *list = [[ListSheet alloc] initWithTitle:title
                                               items:items
                                              symbol:symbol
                                              select:select
                                              delete:deleteItem];
  UINavigationController *navigation =
      [[UINavigationController alloc] initWithRootViewController:list];
  navigation.modalPresentationStyle = UIModalPresentationPageSheet;
  navigation.sheetPresentationController.detents = @[
    [UISheetPresentationControllerDetent mediumDetent],
    [UISheetPresentationControllerDetent largeDetent]
  ];
  [self presentViewController:navigation animated:YES completion:nil];
}
- (void)showSearchItems:(NSArray<MKMapItem *> *)items {
  NSMutableArray *names = NSMutableArray.new;
  for (MKMapItem *item in items)
    [names addObject:item.name ?: @"Place"];
  [self presentList:@"Search results"
              items:names
             symbol:@"magnifyingglass"
             select:^(NSUInteger index) {
               CLLocationCoordinate2D coordinate = items[index].placemark.coordinate;
               [self centerOnCoordinate:coordinate];
               [self choose:coordinate];
             }
             delete:nil];
}
- (void)updateSearchHistoryVisibility {
  NSString *query = [self.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.searchHistoryTable.hidden = !self.searchBar.searchTextField.isFirstResponder || query.length > 0;
  [self.searchHistoryTable reloadData];
  if (!self.searchHistoryTable.hidden)
    [self.view bringSubviewToFront:self.searchHistoryTable];
}
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
  [self updateSearchHistoryVisibility];
}
- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
  self.searchHistoryTable.hidden = YES;
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
  [self updateSearchHistoryVisibility];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return MAX((NSInteger)self.history.count, 1);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"history"];
  if (!cell)
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"history"];
  cell.textLabel.text = self.history.count ? self.history[indexPath.row] : @"No history yet";
  cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  cell.textLabel.adjustsFontForContentSizeCategory = YES;
  cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
  cell.selectionStyle = self.history.count ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
  return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (!self.history.count)
    return;
  self.searchBar.text = self.history[indexPath.row];
  [self searchBarSearchButtonClicked:self.searchBar];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
  NSString *query =
      [bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!query.length)
    return;
  [bar resignFirstResponder];
  [self.history removeObject:query];
  [self.history insertObject:query atIndex:0];
  while (self.history.count > 20)
    [self.history removeLastObject];
  [self save:NO];
  MKLocalSearchRequest *req = MKLocalSearchRequest.new;
  req.naturalLanguageQuery = query;
  req.region = self.map.region;
  [[[MKLocalSearch alloc] initWithRequest:req]
      startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        GPSNavLog(@"MKLocalSearch query=%@ results=%lu error=%@", query, (unsigned long)response.mapItems.count, error);
        if (!error && response.mapItems.count) {
          [self showSearchItems:response.mapItems];
          return;
        }
        NSURLComponents *url =
            [NSURLComponents componentsWithString:@"https://nominatim.openstreetmap.org/search"];
        url.queryItems = @[
          [NSURLQueryItem queryItemWithName:@"format" value:@"json"],
          [NSURLQueryItem queryItemWithName:@"q" value:query],
          [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]
        ];
        [self fetchJSON:url.URL
             completion:^(id json, NSError *fallbackError) {
               NSMutableArray *items = NSMutableArray.new;
               if ([json isKindOfClass:NSArray.class])
                 for (id entry in json)
                   if ([entry isKindOfClass:NSDictionary.class] &&
                       [entry[@"lat"] respondsToSelector:@selector(doubleValue)] &&
                       [entry[@"lon"] respondsToSelector:@selector(doubleValue)]) {
                     CLLocationCoordinate2D c = CLLocationCoordinate2DMake(
                         [entry[@"lat"] doubleValue], [entry[@"lon"] doubleValue]);
                     if (!CLLocationCoordinate2DIsValid(c))
                       continue;
                     MKMapItem *item = [[MKMapItem alloc]
                         initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:c]];
                     item.name = [entry[@"display_name"] isKindOfClass:NSString.class]
                                     ? entry[@"display_name"]
                                     : @"Place";
                     [items addObject:item];
                   }
               if (items.count)
                 [self showSearchItems:items];
               else
                 [self message:fallbackError.localizedDescription ?: @"No places found."];
             }];
      }];
}
- (void)sheet:(NSString *)title actions:(NSArray<UIAlertAction *> *)actions {
  UIAlertController *a =
      [UIAlertController alertControllerWithTitle:title
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleActionSheet];
  for (UIAlertAction *action in actions)
    [a addAction:action];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                        style:UIAlertActionStyleCancel
                                      handler:nil]];
  a.popoverPresentationController.sourceView = self.view;
  a.popoverPresentationController.sourceRect =
      CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
  [self presentViewController:a animated:YES completion:nil];
}
- (void)namePrompt:(NSString *)title completion:(void (^)(NSString *))completion {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                             message:nil
                                                      preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
    f.placeholder = @"Name";
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                        style:UIAlertActionStyleCancel
                                      handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:@"Save"
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *x) {
                                        NSString *name = [a.textFields.firstObject.text
                                            stringByTrimmingCharactersInSet:
                                                NSCharacterSet.whitespaceAndNewlineCharacterSet];
                                        if (name.length)
                                          completion(name);
                                      }]];
  [self presentViewController:a animated:YES completion:nil];
}
- (void)bookmarksMenu {
  NSMutableArray *names = NSMutableArray.new;
  for (NSDictionary *entry in self.bookmarks)
    [names addObject:entry[@"name"] ?: @"Place"];
  [self presentList:@"Bookmarks"
      items:names
      symbol:@"star.fill"
      select:^(NSUInteger index) {
        NSDictionary *entry = self.bookmarks[index];
        CLLocationCoordinate2D coordinate =
            CLLocationCoordinate2DMake([entry[@"lat"] doubleValue], [entry[@"lon"] doubleValue]);
        [self centerOnCoordinate:coordinate];
        [self choose:coordinate];
      }
      delete:^(NSUInteger index) {
        [self.bookmarks removeObjectAtIndex:index];
        [self save:NO];
      }];
}
- (void)routesMenu {
  NSMutableArray *names = NSMutableArray.new;
  for (NSDictionary *entry in self.routes)
    [names addObject:entry[@"name"] ?: @"Route"];
  [self presentList:@"Saved routes"
      items:names
      symbol:@"map.fill"
      select:^(NSUInteger index) {
        NSDictionary *entry = self.routes[index];
        [self clearRoute];
        self.config[@"route"] = entry[@"route"];
        NSArray *first = [entry[@"route"] firstObject];
        self.config[@"latitude"] = first[0];
        self.config[@"longitude"] = first[1];
        self.mode.selectedSegmentIndex = 1;
        self.config[@"mode"] = @"route";
        [self restoreRoute];
        [self.map setVisibleMapRect:self.line.boundingMapRect
                        edgePadding:UIEdgeInsetsMake(80, 40, [self panelInset] + 20, 40)
                           animated:YES];
        [self save:YES];
        [self refreshControls];
      }
      delete:^(NSUInteger index) {
        [self.routes removeObjectAtIndex:index];
        [self save:NO];
      }];
}
- (void)historyMenu {
  [self presentList:@"History"
      items:self.history
      symbol:@"clock.arrow.circlepath"
      select:^(NSUInteger index) {
        self.searchBar.text = self.history[index];
        [self searchBarSearchButtonClicked:self.searchBar];
      }
      delete:^(NSUInteger index) {
        [self.history removeObjectAtIndex:index];
        [self save:NO];
      }];
}
- (void)numberPrompt:(NSString *)title value:(double)value completion:(void (^)(double))completion {
  UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                             message:@"Enter a positive number"
                                                      preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
    f.keyboardType = UIKeyboardTypeDecimalPad;
    f.text = [NSString stringWithFormat:@"%g", value];
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                        style:UIAlertActionStyleCancel
                                      handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:@"Save"
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *x) {
                                        double n = a.textFields.firstObject.text.doubleValue;
                                        if (isfinite(n) && n > 0)
                                          completion(n);
                                        else
                                          [self message:@"Enter a positive number."];
                                      }]];
  [self presentViewController:a animated:YES completion:nil];
}
- (void)routeOptions {
  NSMutableArray *actions = NSMutableArray.new;
  for (NSNumber *speed in @[ @5, @20, @40, @60, @80, @120 ])
    [actions addObject:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ km/h", speed]
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *a) {
                                                self.config[@"speed"] = speed;
                                                [self save:NO];
                                              }]];
  [actions addObject:[UIAlertAction actionWithTitle:@"Custom speed"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              [self numberPrompt:@"Speed (km/h)"
                                                           value:[self.config[@"speed"] doubleValue]
                                                      completion:^(double n) {
                                                        self.config[@"speed"] = @(n);
                                                        [self save:NO];
                                                      }];
                                            }]];
  [actions addObject:[UIAlertAction actionWithTitle:[self.config[@"loop"] boolValue]
                                                        ? @"Reverse loop: On (tap to turn off)"
                                                        : @"Reverse loop: Off (tap to turn on)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              self.config[@"loop"] =
                                                  @(![self.config[@"loop"] boolValue]);
                                              [self save:NO];
                                            }]];
  [actions addObject:[UIAlertAction actionWithTitle:[self.config[@"transport"] isEqual:@"walking"]
                                                        ? @"Transport: Walking (switch to driving)"
                                                        : @"Transport: Driving (switch to walking)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
                                              self.config[@"transport"] =
                                                  [self.config[@"transport"] isEqual:@"walking"]
                                                      ? @"automobile"
                                                      : @"walking";
                                              if (self.start && self.end)
                                                [self fetchRoute];
                                              [self save:NO];
                                            }]];
  [actions addObject:[UIAlertAction actionWithTitle:@"Clear route"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
                                              [self clearRoute];
                                              if (self.mode.selectedSegmentIndex == 1) {
                                                self.enabled.on = NO;
                                                self.config[@"enabled"] = @NO;
                                              }
                                              [self save:YES];
                                            }]];
  [self sheet:@"Route options" actions:actions];
}
- (void)randomOptions {
  [self sheet:@"Random mode"
      actions:@[
        [UIAlertAction
            actionWithTitle:[NSString stringWithFormat:@"Radius: %@ m", self.config[@"radius"]]
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *a) {
                      [self numberPrompt:@"Radius (meters)"
                                   value:[self.config[@"radius"] doubleValue]
                              completion:^(double n) {
                                self.config[@"radius"] = @(n);
                                [self save:NO];
                              }];
                    }],
        [UIAlertAction
            actionWithTitle:[NSString stringWithFormat:@"Interval: %@ s", self.config[@"interval"]]
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *a) {
                      [self numberPrompt:@"Interval (seconds)"
                                   value:[self.config[@"interval"] doubleValue]
                              completion:^(double n) {
                                self.config[@"interval"] = @(n);
                                [self save:NO];
                              }];
                    }]
      ]];
}
- (void)settings {
  [self
      presentList:@"Settings"
            items:@[ @"Blacklist apps", @"About GPSNav 1.0.5" ]
           symbol:@"gearshape.fill"
           select:^(NSUInteger index) {
             if (index == 0) {
               [self blacklist];
             } else {
               [self sheet:@"GPSNav 1.0.5"
                   actions:@[ [UIAlertAction
                               actionWithTitle:@"GitHub"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                         [UIApplication.sharedApplication
                                                       openURL:[NSURL URLWithString:
                                                                          @"https://github.com/"
                                                                          @"xtieume/gps-navigation"]
                                                       options:@{}
                                             completionHandler:nil];
                                       }] ]];
             }
           }
           delete:nil];
}
- (void)blacklist {
  UIAlertController *a = [UIAlertController
      alertControllerWithTitle:@"Blacklist"
                       message:@"One bundle ID per line. Restart affected apps after changes."
                preferredStyle:UIAlertControllerStyleAlert];
  [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
    f.placeholder = @"com.example.app, com.example.other";
    f.text = [(self.config[@"blacklist"] ?: @[]) componentsJoinedByString:@", "];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
  }];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                        style:UIAlertActionStyleCancel
                                      handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:@"Save"
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *x) {
                                        NSMutableArray *list = NSMutableArray.new;
                                        NSCharacterSet *separators = [NSCharacterSet
                                            characterSetWithCharactersInString:@",\n"];
                                        for (NSString *part in [a.textFields.firstObject.text
                                                 componentsSeparatedByCharactersInSet:separators]) {
                                          NSString *s = [part
                                              stringByTrimmingCharactersInSet:
                                                  NSCharacterSet.whitespaceAndNewlineCharacterSet];
                                          if (s.length && ![list containsObject:s])
                                            [list addObject:s];
                                        }
                                        self.config[@"blacklist"] = list;
                                        [self save:NO];
                                      }]];
  [self presentViewController:a animated:YES completion:nil];
}
- (void)applyMapTiles {
  self.map = TileMapView.new;
  self.map.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view insertSubview:self.map atIndex:0];
  [NSLayoutConstraint activateConstraints:@[
    [self.map.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [self.map.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
  ]];
  __weak typeof(self) weakSelf = self;
  self.map.longPressHandler = ^(CLLocationCoordinate2D coordinate) {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [weakSelf choose:coordinate];
  };
}
- (void)dumpMapState {
  GPSNavLog(@"Map frame=%@ hidden=%d alpha=%f window=%@ overlays=%lu annotations=%lu center=%f,%f span=%f,%f searchBar=%@", NSStringFromCGRect(self.map.frame), self.map.hidden, self.map.alpha, self.map.window, (unsigned long)self.map.overlays.count, (unsigned long)self.map.annotations.count, self.map.region.center.latitude, self.map.region.center.longitude, self.map.region.span.latitudeDelta, self.map.region.span.longitudeDelta, NSStringFromCGRect(self.searchBar.frame));
  for (UIView *view in self.view.subviews) GPSNavLog(@"Subview class=%@ frame=%@", NSStringFromClass(view.class), NSStringFromCGRect(view.frame));
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  if (!self.didDumpLayout) {
    self.didDumpLayout = YES;
    [self dumpMapState];
  }
}
- (void)runDiagnostics {
  GPSNavLog(@"Diagnostics started location authorization=%ld prefs=%@", (long)self.locationManager.authorizationStatus, [NSDictionary dictionaryWithContentsOfFile:path]);
  [self dumpMapState];
  CFTypeRef (*createTask)(CFAllocatorRef) = dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
  CFTypeRef (*copyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *) = dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
  CFTypeRef task = createTask && copyEntitlement ? createTask(kCFAllocatorDefault) : NULL;
  if (task) {
    for (NSString *key in @[@"application-identifier", @"com.apple.private.security.no-container", @"get-task-allow"]) {
      CFErrorRef error = NULL;
      CFTypeRef value = copyEntitlement(task, (__bridge CFStringRef)key, &error);
      GPSNavLog(@"Entitlement %@ value=%@ error=%@", key, (__bridge id)value, (__bridge id)error);
      if (value) CFRelease(value);
      if (error) CFRelease(error);
    }
    CFRelease(task);
  }
  NSArray *names = @[@"lat", @"lon", @"flags", @"motion"];
  int tokens[] = {self.latToken, self.lonToken, self.flagsToken, self.motionToken};
  for (NSUInteger i = 0; i < names.count; i++) {
    uint64_t value = 0;
    uint32_t status = notify_get_state(tokens[i], &value);
    GPSNavLog(@"Notify %@ state=%llu status=%u", names[i], (unsigned long long)value, status);
  }
  for (NSString *address in @[@"https://tile.openstreetmap.org/0/0/0.png", @"https://www.apple.com/library/test/success.html"]) {
    NSDate *start = NSDate.date;
    NSURL *url = [NSURL URLWithString:address];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      GPSNavLog(@"Diagnostic GET %@ status=%ld bytes=%lu error=%@ elapsed=%.3fs", url, (long)[(NSHTTPURLResponse *)response statusCode], (unsigned long)data.length, error, -start.timeIntervalSinceNow);
    }] resume];
  }
}
- (void)showLogs {
  __weak typeof(self) weakSelf = self;
  LogSheet *sheet = [[LogSheet alloc] initWithDiagnostics:^{ [weakSelf runDiagnostics]; }];
  UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:sheet];
  navigation.modalPresentationStyle = UIModalPresentationPageSheet;
  [self presentViewController:navigation animated:YES completion:nil];
}
@end
