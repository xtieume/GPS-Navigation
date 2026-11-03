#import "TileMapView.h"
#import "Mercator.h"
#import "../Shared/Log.h"
@interface TileMapView ()
@property NSMutableArray *markerList;
@property NSMutableArray *overlayList;
@property NSCache *cache;
@property NSMutableDictionary *requests;
@property NSMutableDictionary *retryAfter;
@property NSURLSession *session;
@property CGPoint panCenter;
@property double pinchZoom;
@property NSUInteger successes;
@property NSUInteger minuteOK;
@property NSUInteger minuteFail;
@property NSUInteger animationGeneration;
@end
@implementation TileMapView
- (instancetype)init {
  self = [super initWithFrame:CGRectZero];
  if (!self) return nil;
  self.backgroundColor = UIColor.systemGray5Color;
  self.contentMode = UIViewContentModeRedraw;
  _zoom = 13;
  _markerList = NSMutableArray.new;
  _overlayList = NSMutableArray.new;
  _cache = NSCache.new;
  _cache.countLimit = 300;
  _requests = NSMutableDictionary.new;
  _retryAfter = NSMutableDictionary.new;
  NSURLSessionConfiguration *config = NSURLSessionConfiguration.defaultSessionConfiguration;
  config.HTTPMaximumConnectionsPerHost = 6;
  _session = [NSURLSession sessionWithConfiguration:config];
  [NSFileManager.defaultManager createDirectoryAtPath:@"/var/mobile/Library/Caches/com.xtieume.gpsnav/tiles" withIntermediateDirectories:YES attributes:nil error:nil];
  [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
  [self addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)]];
  UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
  doubleTap.numberOfTapsRequired = 2;
  [self addGestureRecognizer:doubleTap];
  UITapGestureRecognizer *twoTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(twoTap:)];
  twoTap.numberOfTouchesRequired = 2;
  [self addGestureRecognizer:twoTap];
  UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
  press.minimumPressDuration = 0.4;
  [self addGestureRecognizer:press];
  __weak typeof(self) weakSelf = self;
  [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
    TileMapView *map = weakSelf;
    if (!map) { [timer invalidate]; return; }
    GPSNavLog(@"Tiles last minute ok=%lu fail=%lu", (unsigned long)map.minuteOK, (unsigned long)map.minuteFail);
    map.minuteOK = 0;
    map.minuteFail = 0;
  }];
  return self;
}
- (NSArray *)annotations { return self.markerList; }
- (NSArray *)overlays { return self.overlayList; }
- (MKMapCamera *)camera { return MKMapCamera.camera; }
- (double)worldSize { return 256.0 * pow(2.0, self.zoom); }
- (void)changed {
  [self setNeedsDisplay];
  if (self.regionChangeHandler) self.regionChangeHandler(self.region);
  if ([self.delegate respondsToSelector:@selector(mapView:regionDidChangeAnimated:)])
    [self.delegate mapView:(MKMapView *)self regionDidChangeAnimated:NO];
}
- (void)setCenterCoordinate:(CLLocationCoordinate2D)coordinate { [self setCenterCoordinate:coordinate animated:NO]; }
- (void)setCenterCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {
  coordinate.longitude = gps_lon(gps_x(coordinate.longitude) - floor(gps_x(coordinate.longitude)));
  coordinate.latitude = gps_lat(gps_y(coordinate.latitude));
  NSUInteger generation = ++self.animationGeneration;
  if (!animated) {
    _centerCoordinate = coordinate;
    [self changed];
    return;
  }
  double startX = gps_x(self.centerCoordinate.longitude);
  double startY = gps_y(self.centerCoordinate.latitude);
  double dx = gps_x(coordinate.longitude) - startX;
  dx -= round(dx);
  double dy = gps_y(coordinate.latitude) - startY;
  CFTimeInterval start = CACurrentMediaTime();
  __weak typeof(self) weakSelf = self;
  [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
    TileMapView *map = weakSelf;
    if (!map || map.animationGeneration != generation) { [timer invalidate]; return; }
    double t = fmin(1, (CACurrentMediaTime() - start) / 0.25);
    double eased = t * (2 - t);
    double x = startX + dx * eased;
    map->_centerCoordinate = CLLocationCoordinate2DMake(gps_lat(startY + dy * eased), gps_lon(x - floor(x)));
    [map changed];
    if (t >= 1) [timer invalidate];
  }];
}
- (void)setZoom:(double)zoom { [self setZoom:zoom animated:NO]; }
- (void)setZoom:(double)zoom animated:(BOOL)animated {
  zoom = fmax(2, fmin(19, zoom));
  NSUInteger generation = ++self.animationGeneration;
  if (!animated) {
    _zoom = zoom;
    [self changed];
    return;
  }
  double initial = self.zoom;
  CFTimeInterval start = CACurrentMediaTime();
  __weak typeof(self) weakSelf = self;
  [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
    TileMapView *map = weakSelf;
    if (!map || map.animationGeneration != generation) { [timer invalidate]; return; }
    double t = fmin(1, (CACurrentMediaTime() - start) / 0.25);
    map->_zoom = initial + (zoom - initial) * t * (2 - t);
    [map changed];
    if (t >= 1) [timer invalidate];
  }];
}
- (MKCoordinateRegion)region {
  CLLocationCoordinate2D a = [self convertPoint:CGPointZero toCoordinateFromView:self];
  CLLocationCoordinate2D b = [self convertPoint:CGPointMake(self.bounds.size.width, self.bounds.size.height) toCoordinateFromView:self];
  return MKCoordinateRegionMake(self.centerCoordinate, MKCoordinateSpanMake(fabs(a.latitude - b.latitude), fmin(360, self.bounds.size.width / self.worldSize * 360)));
}
- (void)setRegion:(MKCoordinateRegion)region animated:(BOOL)animated {
  _centerCoordinate = region.center;
  double width = MAX(self.bounds.size.width, 375);
  _zoom = fmax(2, fmin(19, log2(width * 360 / (256 * MAX(region.span.longitudeDelta, 0.00001)))));
  [self changed];
}
- (void)setVisibleMapRect:(MKMapRect)rect edgePadding:(UIEdgeInsets)padding animated:(BOOL)animated {
  MKMapPoint middle = MKMapPointMake(MKMapRectGetMidX(rect), MKMapRectGetMidY(rect));
  _centerCoordinate = MKCoordinateForMapPoint(middle);
  double width = MAX(1, self.bounds.size.width - padding.left - padding.right);
  double height = MAX(1, self.bounds.size.height - padding.top - padding.bottom);
  double scale = fmin(width / MAX(rect.size.width, 1), height / MAX(rect.size.height, 1));
  _zoom = fmax(2, fmin(19, log2(scale * MKMapSizeWorld.width / 256.0)));
  double world = self.worldSize;
  _centerCoordinate = CLLocationCoordinate2DMake(gps_lat(gps_y(_centerCoordinate.latitude) + (padding.bottom - padding.top) / (2 * world)), gps_lon(gps_x(_centerCoordinate.longitude) + (padding.right - padding.left) / (2 * world)));
  [self changed];
}
- (CGPoint)convertCoordinate:(CLLocationCoordinate2D)c toPointToView:(UIView *)view {
  double dx = gps_x(c.longitude) - gps_x(self.centerCoordinate.longitude);
  dx -= round(dx);
  CGPoint p = CGPointMake(self.bounds.size.width / 2 + dx * self.worldSize, self.bounds.size.height / 2 + (gps_y(c.latitude) - gps_y(self.centerCoordinate.latitude)) * self.worldSize);
  return [self convertPoint:p toView:view];
}
- (CLLocationCoordinate2D)convertPoint:(CGPoint)point toCoordinateFromView:(UIView *)view {
  CGPoint p = [self convertPoint:point fromView:view];
  double x = gps_x(self.centerCoordinate.longitude) + (p.x - self.bounds.size.width / 2) / self.worldSize;
  double y = gps_y(self.centerCoordinate.latitude) + (p.y - self.bounds.size.height / 2) / self.worldSize;
  return CLLocationCoordinate2DMake(gps_lat(fmax(0, fmin(1, y))), gps_lon(x - floor(x)));
}
- (void)pan:(UIPanGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan) self.panCenter = CGPointMake(gps_x(self.centerCoordinate.longitude), gps_y(self.centerCoordinate.latitude));
  CGPoint delta = [gesture translationInView:self];
  [self setCenterCoordinate:CLLocationCoordinate2DMake(gps_lat(fmax(0, fmin(1, self.panCenter.y - delta.y / self.worldSize))), gps_lon(self.panCenter.x - delta.x / self.worldSize)) animated:NO];
}
- (void)pinch:(UIPinchGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan) self.pinchZoom = self.zoom;
  [self setZoom:self.pinchZoom + log2(gesture.scale) animated:NO];
}
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
  if (gesture.state == UIGestureRecognizerStateBegan && self.longPressHandler)
    self.longPressHandler([self convertPoint:[gesture locationInView:self] toCoordinateFromView:self]);
}
- (void)doubleTap:(UITapGestureRecognizer *)gesture { [self setZoom:self.zoom + 1 animated:YES]; }
- (void)twoTap:(UITapGestureRecognizer *)gesture { [self setZoom:self.zoom - 1 animated:YES]; }
- (void)addAnnotation:(id<MKAnnotation>)annotation { if (annotation && ![self.markerList containsObject:annotation]) [self.markerList addObject:annotation]; [self setNeedsDisplay]; }
- (void)addAnnotations:(NSArray *)annotations { for (id a in annotations) [self addAnnotation:a]; }
- (void)removeAnnotation:(id<MKAnnotation>)annotation { [self.markerList removeObject:annotation]; [self setNeedsDisplay]; }
- (void)addOverlay:(id<MKOverlay>)overlay level:(MKOverlayLevel)level { if (overlay) [self.overlayList addObject:overlay]; [self setNeedsDisplay]; }
- (void)removeOverlay:(id<MKOverlay>)overlay { [self.overlayList removeObject:overlay]; [self setNeedsDisplay]; }
- (MKAnnotationView *)viewForAnnotation:(id<MKAnnotation>)annotation { return nil; }
- (void)loadTile:(NSString *)key url:(NSURL *)url {
  if (self.requests[key]) return;
  NSDate *retry = self.retryAfter[key];
  if (retry && retry.timeIntervalSinceNow > 0) return;
  [self.retryAfter removeObjectForKey:key];
  NSString *file = [@"/var/mobile/Library/Caches/com.xtieume.gpsnav/tiles" stringByAppendingPathComponent:[key stringByAppendingString:@".png"]];
  UIImage *disk = [UIImage imageWithContentsOfFile:file];
  if (disk) { [self.cache setObject:disk forKey:key]; [self setNeedsDisplay]; return; }
  if (self.requests.count >= 6) return;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setValue:@"GPSNav/1.0.3" forHTTPHeaderField:@"User-Agent"];
  __block NSURLSessionDataTask *task = nil;
  task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self.requests[key] == task) [self.requests removeObjectForKey:key];
      NSInteger status = [(NSHTTPURLResponse *)response statusCode];
      UIImage *image = data ? [UIImage imageWithData:data] : nil;
      if (error.code == NSURLErrorCancelled) { [self setNeedsDisplay]; return; }
      if (error || status != 200 || !image) {
        self.minuteFail++;
        self.retryAfter[key] = [NSDate dateWithTimeIntervalSinceNow:30];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self setNeedsDisplay]; });
        GPSNavLog(@"Tile failure URL=%@ status=%ld error=%@", url, (long)status, error);
        [self setNeedsDisplay];
      } else {
        self.minuteOK++;
        if (self.successes++ < 20) GPSNavLog(@"Tile success URL=%@ bytes=%lu", url, (unsigned long)data.length);
        [self.cache setObject:image forKey:key];
        [data writeToFile:file atomically:YES];
        [self setNeedsDisplay];
      }
    });
  }];
  self.requests[key] = task;
  [task resume];
}
- (void)drawRect:(CGRect)rect {
  CGContextRef cg = UIGraphicsGetCurrentContext();
  int z = (int)floor(self.zoom);
  int count = 1 << z;
  double tileSize = 256 * pow(2, self.zoom - z);
  double cx = gps_x(self.centerCoordinate.longitude) * count;
  double cy = gps_y(self.centerCoordinate.latitude) * count;
  double left = cx - self.bounds.size.width / (2 * tileSize);
  double top = cy - self.bounds.size.height / (2 * tileSize);
  NSMutableSet *visible = NSMutableSet.new;
  for (int y = floor(top); y <= floor(top + self.bounds.size.height / tileSize); y++) {
    if (y < 0 || y >= count) continue;
    for (int x = floor(left); x <= floor(left + self.bounds.size.width / tileSize); x++) {
      int wrapped = ((x % count) + count) % count;
      NSString *key = [NSString stringWithFormat:@"%d-%d-%d", z, wrapped, y];
      [visible addObject:key];
      CGRect tile = CGRectMake((x - left) * tileSize, (y - top) * tileSize, tileSize + 0.5, tileSize + 0.5);
      UIImage *image = [self.cache objectForKey:key];
      if (image) [image drawInRect:tile];
      else [self loadTile:key url:[NSURL URLWithString:[NSString stringWithFormat:@"https://tile.openstreetmap.org/%d/%d/%d.png", z, wrapped, y]]];
    }
  }
  for (NSString *key in self.requests.allKeys) if (![visible containsObject:key]) { [self.requests[key] cancel]; [self.requests removeObjectForKey:key]; }
  CGContextSetStrokeColorWithColor(cg, UIColor.systemBlueColor.CGColor);
  CGContextSetLineWidth(cg, 5);
  CGContextSetLineCap(cg, kCGLineCapRound);
  CGContextSetLineJoin(cg, kCGLineJoinRound);
  for (id overlay in self.overlayList) if ([overlay isKindOfClass:MKPolyline.class]) {
    MKPolyline *line = overlay;
    for (NSUInteger i = 0; i < line.pointCount; i++) {
      CGPoint p = [self convertCoordinate:MKCoordinateForMapPoint(line.points[i]) toPointToView:self];
      if (i == 0) CGContextMoveToPoint(cg, p.x, p.y); else CGContextAddLineToPoint(cg, p.x, p.y);
    }
    CGContextStrokePath(cg);
  }
  for (id<MKAnnotation> marker in self.markerList) {
    CGPoint p = [self convertCoordinate:marker.coordinate toPointToView:self];
    NSString *title = [marker respondsToSelector:@selector(title)] ? marker.title : @"";
    BOOL engine = [title isEqual:@"Engine position"];
    UIColor *color = [title isEqual:@"A"] ? UIColor.systemGreenColor : (engine ? UIColor.systemBlueColor : UIColor.systemRedColor);
    if (engine) {
      CGContextSaveGState(cg);
      CGContextTranslateCTM(cg, p.x, p.y);
      CGContextRotateCTM(cg, self.course * M_PI / 180);
      CGContextSetFillColorWithColor(cg, color.CGColor);
      CGContextMoveToPoint(cg, 0, -21);
      CGContextAddLineToPoint(cg, -6, -8);
      CGContextAddLineToPoint(cg, 6, -8);
      CGContextFillPath(cg);
      CGContextRestoreGState(cg);
      CGContextSetFillColorWithColor(cg, UIColor.whiteColor.CGColor);
      CGContextFillEllipseInRect(cg, CGRectMake(p.x - 11, p.y - 11, 22, 22));
      CGContextSetFillColorWithColor(cg, color.CGColor);
      CGContextFillEllipseInRect(cg, CGRectMake(p.x - 8, p.y - 8, 16, 16));
    } else {
      CGContextSetFillColorWithColor(cg, color.CGColor);
      CGContextMoveToPoint(cg, p.x, p.y);
      CGContextAddLineToPoint(cg, p.x - 9, p.y - 16);
      CGContextAddLineToPoint(cg, p.x + 9, p.y - 16);
      CGContextFillPath(cg);
      CGContextFillEllipseInRect(cg, CGRectMake(p.x - 9, p.y - 27, 18, 18));
      if ([title isEqual:@"A"] || [title isEqual:@"B"]) [title drawAtPoint:CGPointMake(p.x - 4, p.y - 25) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:12], NSForegroundColorAttributeName:UIColor.whiteColor}];
    }
  }
  if (self.hasUserCoordinate) {
    CGPoint p = [self convertCoordinate:self.userCoordinate toPointToView:self];
    CGContextSetFillColorWithColor(cg, UIColor.whiteColor.CGColor);
    CGContextFillEllipseInRect(cg, CGRectMake(p.x - 8, p.y - 8, 16, 16));
    CGContextSetFillColorWithColor(cg, UIColor.systemBlueColor.CGColor);
    CGContextFillEllipseInRect(cg, CGRectMake(p.x - 6, p.y - 6, 12, 12));
  }
}
@end
