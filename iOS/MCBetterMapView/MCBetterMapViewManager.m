/**
    The following source was copied from FaceBook's React Native RCTMapManager.m file and modified due to the
    nature of how the framework is designed and implemented.
    https://github.com/facebook/react-native
*/


#import "MCBetterMapViewManager.h"

#import "RCTBridge.h"
#import "RCTConvert+CoreLocation.h"
#import "RCTConvert+MapKit.h"
#import "RCTEventDispatcher.h"
#import "MCBetterMapView.h"
#import "UIView+React.h"
#import "RCTPointAnnotation.h"

#import <MapKit/MapKit.h>

static NSString *const MCBetterMapViewKey = @"MCBetterMapView";

@interface MCBetterMapViewManager() <MKMapViewDelegate>

@end

@implementation MCBetterMapViewManager

RCT_EXPORT_MODULE()

- (UIView *)view {
    MCBetterMapView *map = [MCBetterMapView new];
    map.delegate = self;
    return map;
}

RCT_EXPORT_VIEW_PROPERTY(showsUserLocation, BOOL)
RCT_EXPORT_VIEW_PROPERTY(zoomEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rotateEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(pitchEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(scrollEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(maxDelta, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(minDelta, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(legalLabelInsets, UIEdgeInsets)
RCT_EXPORT_VIEW_PROPERTY(mapType, MKMapType)
RCT_EXPORT_VIEW_PROPERTY(annotations, RCTPointAnnotationArray)
RCT_CUSTOM_VIEW_PROPERTY(region, MKCoordinateRegion, MCBetterMapView) {
    [view setRegion:json ? [RCTConvert MKCoordinateRegion:json] : defaultView.region animated:YES];
}



#pragma mark MKMapViewDelegate
- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    if (![view.annotation isKindOfClass:[MKUserLocation class]]) {

        RCTPointAnnotation *annotation = (RCTPointAnnotation *)view.annotation;
        NSString *title = view.annotation.title ?: @"";
        NSString *subtitle = view.annotation.subtitle ?: @"";

        NSDictionary *event = @{
                @"target"     : mapView.reactTag,
                @"action"     : @"annotation-click",
                @"annotation" : @{
                        @"id"       : annotation.identifier,
                        @"title"    : title,
                        @"subtitle" : subtitle,
                        @"latitude" : @(annotation.coordinate.latitude),
                        @"longitude": @(annotation.coordinate.longitude)
                    }
                };

        [self.bridge.eventDispatcher sendInputEventWithName:@"press" body:event];
    }
}

- (MKAnnotationView *)mapView:(__unused MKMapView *)mapView viewForAnnotation:(RCTPointAnnotation *)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }

    MKPinAnnotationView *annotationView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"RCTAnnotation"];

    annotationView.canShowCallout = true;
    annotationView.animatesDrop = annotation.animateDrop;

    annotationView.leftCalloutAccessoryView = nil;
    if (annotation.hasLeftCallout) {
        annotationView.leftCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
    }

    annotationView.rightCalloutAccessoryView = nil;
    if (annotation.hasRightCallout) {
        annotationView.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
    }

    return annotationView;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    // Pass to js
    RCTPointAnnotation *annotation = (RCTPointAnnotation *)view.annotation;
    NSString *side = (control == view.leftCalloutAccessoryView) ? @"left" : @"right";

    NSDictionary *event = @{
            @"target": mapView.reactTag,
            @"side": side,
            @"action": @"callout-click",
            @"annotationId": annotation.identifier
        };

    [self.bridge.eventDispatcher sendInputEventWithName:@"press" body:event];
}


- (void)mapView:(MCBetterMapView *)mapView didUpdateUserLocation:(MKUserLocation *)location {
    if (mapView.followUserLocation) {
        MKCoordinateRegion region;
        region.span.latitudeDelta = MCBetterMapViewDefaultSpan;
        region.span.longitudeDelta = MCBetterMapViewDefaultSpan;
        region.center = location.coordinate;
        [mapView setRegion:region animated:YES];

        // Move to user location only for the first time it loads up.
        mapView.followUserLocation = NO;
    }
}

- (void)mapView:(MCBetterMapView *)mapView regionWillChangeAnimated:(__unused BOOL)animated {
    [self _regionChanged:mapView];

    mapView.regionChangeObserveTimer = [NSTimer timerWithTimeInterval:MCBetterMapViewRegionChangeObserveInterval
                                                               target:self
                                                             selector:@selector(_onTick:)
                                                             userInfo:@{ MCBetterMapViewKey: mapView }
                                                              repeats:YES];

    [[NSRunLoop mainRunLoop] addTimer:mapView.regionChangeObserveTimer forMode:NSRunLoopCommonModes];
}

- (void)mapView:(MCBetterMapView *)mapView regionDidChangeAnimated:(__unused BOOL)animated {
    [mapView.regionChangeObserveTimer invalidate];
    mapView.regionChangeObserveTimer = nil;

    [self _regionChanged:mapView];

    // Don't send region did change events until map has
    // started rendering, as these won't represent the final location
    if (mapView.hasStartedRendering) {
        [self _emitRegionChangeEvent:mapView continuous:NO];
    };
}

- (void)mapViewWillStartRenderingMap:(MCBetterMapView *)mapView {
    mapView.hasStartedRendering = YES;
    [self _emitRegionChangeEvent:mapView continuous:NO];
}

#pragma mark Private

- (void)_onTick:(NSTimer *)timer {
    [self _regionChanged:timer.userInfo[MCBetterMapViewKey]];
}

- (void)_regionChanged:(MCBetterMapView *)mapView {
    BOOL needZoom = NO;
    CGFloat newLongitudeDelta = 0.0f;
    MKCoordinateRegion region = mapView.region;
    
    // On iOS 7, it's possible that we observe invalid locations during initialization of the map.
    // Filter those out.
    if (!CLLocationCoordinate2DIsValid(region.center)) {
        return;
    }
    
    // Calculation on float is not 100% accurate. If user zoom to max/min and then move, it's likely the map will auto zoom to max/min from time to time.
    // So let's try to make map zoom back to 99% max or 101% min so that there are some buffer that moving the map won't constantly hitting the max/min bound.
    if (mapView.maxDelta > FLT_EPSILON && region.span.longitudeDelta > mapView.maxDelta) {
        needZoom = YES;
        newLongitudeDelta = mapView.maxDelta * (1 - RCTMapZoomBoundBuffer);
    }
    else if (mapView.minDelta > FLT_EPSILON && region.span.longitudeDelta < mapView.minDelta) {
        needZoom = YES;
        newLongitudeDelta = mapView.minDelta * (1 + RCTMapZoomBoundBuffer);
    }
    
    if (needZoom) {
        region.span.latitudeDelta = region.span.latitudeDelta / region.span.longitudeDelta * newLongitudeDelta;
        region.span.longitudeDelta = newLongitudeDelta;
        mapView.region = region;
    }

    // Continously observe region changes
    [self _emitRegionChangeEvent:mapView continuous:YES];
}

- (void)_emitRegionChangeEvent:(MCBetterMapView *)mapView continuous:(BOOL)continuous {
    MKCoordinateRegion region = mapView.region;
    if (!CLLocationCoordinate2DIsValid(region.center)) {
        return;
    }
    
    MKMapRect visibleMapRect = mapView.visibleMapRect;
    NSSet *visibleAnnotations = [mapView annotationsInMapRect:visibleMapRect];
    
    NSMutableArray *allVisibleAnnotations = [NSMutableArray new];
    
    
    
    
    for (RCTPointAnnotation *annotation in visibleAnnotations) {
    
        NSString *title = annotation.title ?: @"";
        NSString *subtitle = annotation.subtitle ?: @"";

        [allVisibleAnnotations addObject: @{
            @"id"       : annotation.identifier, // Todo remove?
            @"title"    : title,
            @"subtitle" : subtitle,
            @"latitude" : @(annotation.coordinate.latitude),
            @"longitude": @(annotation.coordinate.longitude)
        
        }];
    
//        NSLog(@"%@", allVisibleAnnotations);
    }

#define FLUSH_NAN(value) (isnan(value) ? 0 : value)

    NSDictionary *event = @{
        @"target"     : mapView.reactTag,
        @"continuous" : @(continuous),
        @"region"     : @{
            @"latitude"       : @(FLUSH_NAN(region.center.latitude)),
            @"longitude"      : @(FLUSH_NAN(region.center.longitude)),
            @"latitudeDelta"  : @(FLUSH_NAN(region.span.latitudeDelta)),
            @"longitudeDelta" : @(FLUSH_NAN(region.span.longitudeDelta)),
            @"annotations"    : allVisibleAnnotations
        },
    };
    
//    NSLog(@"%@", event);

    
    [self.bridge.eventDispatcher sendInputEventWithName:@"change" body:event];
}

@end
