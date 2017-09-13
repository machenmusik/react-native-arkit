//
//  RCTARKitManager.h
//  RCTARKit
//
//  Created by HippoAR on 7/9/17.
//  Copyright © 2017 HippoAR. All rights reserved.
//

/* RCTARKitManager_h */

#import <React/RCTViewManager.h>

@interface RCTARKitManager : RCTViewManager

- (void)pause:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)resume:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;

- (void)setPlaneDetection:(BOOL)value resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;

- (void)snapshot:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)getCameraPosition:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)getCurrentFrameParams:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)getCurrentFramePointCloud:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)analyzeCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)barcodesCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;

- (void)addBox:(NSDictionary *)property;
- (void)addSphere:(NSDictionary *)property;
- (void)addCylinder:(NSDictionary *)property;
- (void)addCone:(NSDictionary *)property;
- (void)addPyramid:(NSDictionary *)property;
- (void)addTube:(NSDictionary *)property;
- (void)addTorus:(NSDictionary *)property;
- (void)addCapsule:(NSDictionary *)property;
- (void)addPlane:(NSDictionary *)property;
- (void)addText:(NSDictionary *)property;
- (void)addModel:(NSDictionary *)property;
- (void)addImage:(NSDictionary *)property;

@end
