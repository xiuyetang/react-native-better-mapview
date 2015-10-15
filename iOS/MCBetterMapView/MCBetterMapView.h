/**
    The following source was copied from FaceBook's React Native RCTMap.h file and modified
    https://github.com/facebook/react-native
*/

#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

#import "RCTConvert+MapKit.h"
#import "RCTMap.h"

extern const CLLocationDegrees MCBetterMapViewDefaultSpan;
extern const NSTimeInterval MCBetterMapViewRegionChangeObserveInterval;
extern const CGFloat MCBetterMapViewZoomBoundBuffer;

@class RCTEventDispatcher;

@interface MCBetterMapView: RCTMap

@end
