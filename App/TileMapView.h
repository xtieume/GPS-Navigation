#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
@interface TileMapView : UIView
@property (nonatomic, weak) id<MKMapViewDelegate> delegate;
@property (nonatomic) CLLocationCoordinate2D centerCoordinate;
@property (nonatomic) double zoom;
@property (nonatomic) CLLocationCoordinate2D userCoordinate;
@property (nonatomic) BOOL hasUserCoordinate;
@property (nonatomic) CGFloat course;
@property (nonatomic, copy) void (^longPressHandler)(CLLocationCoordinate2D coordinate);
@property (nonatomic, copy) void (^regionChangeHandler)(MKCoordinateRegion region);
@property (nonatomic, readonly) MKCoordinateRegion region;
@property (nonatomic, readonly) NSArray *annotations;
@property (nonatomic, readonly) NSArray *overlays;
@property (nonatomic, readonly) MKMapCamera *camera;
- (void)setCenterCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated;
- (void)setZoom:(double)zoom animated:(BOOL)animated;
- (void)setRegion:(MKCoordinateRegion)region animated:(BOOL)animated;
- (void)setVisibleMapRect:(MKMapRect)rect edgePadding:(UIEdgeInsets)padding animated:(BOOL)animated;
- (CLLocationCoordinate2D)convertPoint:(CGPoint)point toCoordinateFromView:(UIView *)view;
- (CGPoint)convertCoordinate:(CLLocationCoordinate2D)coordinate toPointToView:(UIView *)view;
- (void)addAnnotation:(id<MKAnnotation>)annotation;
- (void)addAnnotations:(NSArray *)annotations;
- (void)removeAnnotation:(id<MKAnnotation>)annotation;
- (void)addOverlay:(id<MKOverlay>)overlay level:(MKOverlayLevel)level;
- (void)removeOverlay:(id<MKOverlay>)overlay;
- (MKAnnotationView *)viewForAnnotation:(id<MKAnnotation>)annotation;
@end
