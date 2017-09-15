//
//  RCTARKit.h
//  RCTARKit
//
//  Created by HippoAR on 7/9/17.
//  Copyright © 2017 HippoAR. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import <ARKit/ARKit.h>

#import <React/RCTComponent.h>
#import <React/RCTBridgeModule.h>

@interface RCTARKit : UIView

+ (instancetype)sharedInstance;
- (instancetype)initWithARView:(ARSCNView *)arView;



#pragma mark - Properties
@property (nonatomic, strong) ARSCNView* arView;

@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL planeDetection;
@property (nonatomic, assign) BOOL lightEstimation;

@property (nonatomic, copy) RCTBubblingEventBlock onPlaneDetected;
@property (nonatomic, copy) RCTBubblingEventBlock onPlaneUpdate;
@property (nonatomic, copy) RCTBubblingEventBlock onPlaneRemoved;
@property (nonatomic, copy) RCTBubblingEventBlock onTrackingState;
@property (nonatomic, copy) RCTBubblingEventBlock onWebARUpdateWindowSize;
@property (nonatomic, copy) RCTBubblingEventBlock onWebARSetData;
@property (nonatomic, copy) RCTBubblingEventBlock onWebARAnchorEvent;

// origins for local frame and camera frame
@property (nonatomic, strong) SCNNode *localOrigin;
@property (nonatomic, strong) SCNNode *cameraOrigin;

@property NSMutableDictionary *nodes; // nodes added to the scene
@property NSMutableDictionary *planes; // plane detected

//////////////////////////////
// Imports from WebARonARKit.
//////////////////////////////

@property (nonatomic, assign) UIDeviceOrientation deviceOrientation;
@property (nonatomic, assign) UIInterfaceOrientation interfaceOrientation;
@property (nonatomic, assign) bool updateWindowSize;

@property (nonatomic, assign) float near;
@property (nonatomic, assign) float far;

#pragma mark - Public Method
- (void)pause;
- (void)resume;
- (void)restart;
- (void)snapshot:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;

- (NSDictionary *)readCameraPosition;
- (NSDictionary *)readCurrentFrameParams;
- (NSDictionary *)readCurrentFramePointCloud;
- (void)analyzeCurrentFrame:(NSString*)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;
- (void)barcodesCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject;


#pragma mark add
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



#pragma mark - Private
- (void)addNodeToScene:(SCNNode *)node property:(NSDictionary *)property;
- (SCNVector3)getPositionFromProperty:(NSDictionary *)property;

- (void)registerNode:(SCNNode *)node forKey:(NSString *)key;
- (SCNNode *)nodeForKey:(NSString *)key;
- (void)removeNodeForKey:(NSString *)key;
- (SCNNode *)loadModel:(NSURL *)url nodeName:(NSString *)nodeName withAnimation:(BOOL)withAnimation;



#pragma mark - Delegates
- (void)renderer:(id <SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;
- (void)renderer:(id <SCNSceneRenderer>)renderer willUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;
- (void)renderer:(id <SCNSceneRenderer>)renderer didUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;
- (void)renderer:(id <SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame;

- (void)session:(ARSession *)session didAddAnchors:(nonnull NSArray<ARAnchor *> *)anchors;
- (void)session:(ARSession *)session didUpdateAnchors:(nonnull NSArray<ARAnchor *> *)anchors;
- (void)session:(ARSession *)session didRemoveAnchors:(nonnull NSArray<ARAnchor *> *)anchors;

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera;

@end



#if __has_include("RCTARKitARCL.h")
#import "RCTARKitARCL.h"
@compatibility_alias ARKit RCTARKitARCL;
#else
@compatibility_alias ARKit RCTARKit;
#endif

