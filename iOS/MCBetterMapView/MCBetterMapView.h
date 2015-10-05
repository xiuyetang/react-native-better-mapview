/**
    The following source was copied from FaceBook's React Native RCTMap.h file and modified
    https://github.com/facebook/react-native
*/

#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

#import "RCTConvert+MapKit.h"

extern const CLLocationDegrees MCBetterMapViewDefaultSpan;
extern const NSTimeInterval MCBetterMapViewRegionChangeObserveInterval;
extern const CGFloat MCBetterMapViewZoomBoundBuffer;

@class RCTEventDispatcher;

@interface MCBetterMapView: MKMapView

@property (nonatomic, assign) BOOL followUserLocation;
@property (nonatomic, assign) BOOL hasStartedRendering;
@property (nonatomic, assign) CGFloat minDelta;
@property (nonatomic, assign) CGFloat maxDelta;
@property (nonatomic, assign) UIEdgeInsets legalLabelInsets;
@property (nonatomic, strong) NSTimer *regionChangeObserveTimer;
@property (nonatomic, strong) NSMutableArray *annotationIds;

- (void)setAnnotations:(RCTPointAnnotationArray *)annotations;

@end
