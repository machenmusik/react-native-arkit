//
//  RCTARKit.m
//  RCTARKit
//
//  Created by HippoAR on 7/9/17.
//  Copyright © 2017 HippoAR. All rights reserved.
//

#import "RCTARKit.h"
#import "Plane.h"
@import CoreLocation;
@import Vision;
#import "Inceptionv3.h"
#import "SqueezeNet.h"
#import "MobileNet.h"
#import "AgeNet.h"
#import "GenderNet.h"
#import "CNNEmotions.h"

@interface RCTARKit () <ARSCNViewDelegate> {
    RCTPromiseResolveBlock _resolve;
}

@property (nonatomic, strong) ARSession* session;
@property (nonatomic, strong) ARWorldTrackingConfiguration *configuration;
@property (nonatomic, strong) NSMutableDictionary *timestamps;
@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) NSString *modelName;

@end


@implementation RCTARKit

+ (instancetype)sharedInstance {
    static RCTARKit *instance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        if (instance == nil) {
            ARSCNView *arView = [[ARSCNView alloc] init];
            instance = [[self alloc] initWithARView:arView];
        }
    });
    return instance;
}

- (instancetype)initWithARView:(ARSCNView *)arView {
    if ((self = [super init])) {
        self.arView = arView;
        
        // delegates
        arView.delegate = self;
        arView.session.delegate = self;
        
        // configuration(s)
        arView.autoenablesDefaultLighting = YES;
        arView.scene.rootNode.name = @"root";
        
        // local reference frame origin
        self.localOrigin = [[SCNNode alloc] init];
        self.localOrigin.name = @"localOrigin";
        [arView.scene.rootNode addChildNode:self.localOrigin];
        
        // camera reference frame origin
        self.cameraOrigin = [[SCNNode alloc] init];
        self.cameraOrigin.name = @"cameraOrigin";
        //        self.cameraOrigin.opacity = 0.7;
        [arView.scene.rootNode addChildNode:self.cameraOrigin];
        
        // init cahces
        self.nodes = [NSMutableDictionary new];
        self.planes = [NSMutableDictionary new];
        
        // start ARKit
        [self addSubview:arView];
        [self resume];

    ////////////////////////////////////////////////////////////
    // Imported device orientation listening from WebARonARKit.
    ////////////////////////////////////////////////////////////

        self.near = 0.001;
        self.far = 10000;
    // Calculate the orientation of the device
    UIDevice *device = [UIDevice currentDevice];
    [device beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(deviceOrientationDidChange:)
               name:UIDeviceOrientationDidChangeNotification
             object:nil];
    _deviceOrientation = [device orientation];
    [self updateOrientation];

    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.arView.frame = self.bounds;
}

- (void)pause {
    [self.session pause];
}

- (void)resume {
    [self.session runWithConfiguration:self.configuration];
}

- (void)restart {
    [self.session runWithConfiguration:self.configuration options:ARSessionRunOptionResetTracking];
}

#pragma mark - setter-getter

- (ARSession*)session {
    return self.arView.session;
}

- (BOOL)debug {
    return self.arView.showsStatistics;
}

- (void)setDebug:(BOOL)debug {
    if (debug) {
        self.arView.showsStatistics = YES;
        self.arView.debugOptions = ARSCNDebugOptionShowWorldOrigin | ARSCNDebugOptionShowFeaturePoints;
    } else {
        self.arView.showsStatistics = NO;
        self.arView.debugOptions = SCNDebugOptionNone;
    }
}

- (BOOL)planeDetection {
    ARWorldTrackingConfiguration *configuration = self.session.configuration;
    return configuration.planeDetection == ARPlaneDetectionHorizontal;
}

- (void)setPlaneDetection:(BOOL)planeDetection {
    // plane detection is on by default for ARCL and cannot be configured for now
    ARWorldTrackingConfiguration *configuration = self.session.configuration;
    if (planeDetection) {
        configuration.planeDetection = ARPlaneDetectionHorizontal;
    } else {
        configuration.planeDetection = ARPlaneDetectionNone;
    }
    [self resume];
}

- (BOOL)lightEstimation {
    ARConfiguration *configuration = self.session.configuration;
    return configuration.lightEstimationEnabled;
}

- (void)setLightEstimation:(BOOL)lightEstimation {
    // light estimation is on by default for ARCL and cannot be configured for now
    ARConfiguration *configuration = self.session.configuration;
    configuration.lightEstimationEnabled = lightEstimation;
    [self resume];
}

- (NSDictionary *)readCameraPosition {
    return @{
             // Is passing array(s) better?
             // Is it better to send over current frame camera.transform?
             @"x": @(self.cameraOrigin.position.x),
             @"y": @(self.cameraOrigin.position.y),
             @"z": @(self.cameraOrigin.position.z),
             @"eulerX": @(self.session.currentFrame.camera.eulerAngles[0]),
             @"eulerY": @(self.session.currentFrame.camera.eulerAngles[1]),
             @"eulerZ": @(self.session.currentFrame.camera.eulerAngles[2])
            };
}

- (NSDictionary *)readCurrentFrameParams {
    ARFrame* currentFrame = self.session.currentFrame;
    ARCamera* camera = currentFrame.camera;
    ARLightEstimate* lightEstimate = currentFrame.lightEstimate;
    
    // FIXME: should be [UIApplication statusBarOrientation] but can only call that on main thread
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    CGSize size = {UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height};
    // TODO: get dynamic values
    CGFloat zNear = self.near;
    CGFloat zFar = self.far;
    matrix_float4x4 projectionMatrix =
      [camera projectionMatrixForOrientation:orientation viewportSize:size zNear:zNear zFar:zFar];
    
    matrix_float4x4 rotatedMatrix = matrix_identity_float4x4;
    // rotation  matrix
    // [ cos    -sin]
    // [ sin     cos]
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            rotatedMatrix.columns[0][0] = 0;
            rotatedMatrix.columns[0][1] = 1;
            rotatedMatrix.columns[1][0] = -1;
            rotatedMatrix.columns[1][1] = 0;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            rotatedMatrix.columns[0][0] = -1;
            rotatedMatrix.columns[0][1] = 0;
            rotatedMatrix.columns[1][0] = 0;
            rotatedMatrix.columns[1][1] = -1;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            rotatedMatrix.columns[0][0] = 0;
            rotatedMatrix.columns[0][1] = -1;
            rotatedMatrix.columns[1][0] = 1;
            rotatedMatrix.columns[1][1] = 0;
            break;
        default:
            break;
    }
    matrix_float4x4 transform = matrix_multiply(camera.transform, rotatedMatrix);
    
    return @{
             @"timestamp": @(currentFrame.timestamp),
             @"projectionMatrix": @[
              @(projectionMatrix.columns[0][0]),
              @(projectionMatrix.columns[0][1]),
              @(projectionMatrix.columns[0][2]),
              @(projectionMatrix.columns[0][3]),
              @(projectionMatrix.columns[1][0]),
              @(projectionMatrix.columns[1][1]),
              @(projectionMatrix.columns[1][2]),
              @(projectionMatrix.columns[1][3]),
              @(projectionMatrix.columns[2][0]),
              @(projectionMatrix.columns[2][1]),
              @(projectionMatrix.columns[2][2]),
              @(projectionMatrix.columns[2][3]),
              @(projectionMatrix.columns[3][0]),
              @(projectionMatrix.columns[3][1]),
              @(projectionMatrix.columns[3][2]),
              @(projectionMatrix.columns[3][3])
             ]
             ,
             @"transform": @[
              @(transform.columns[0][0]),
              @(transform.columns[0][1]),
              @(transform.columns[0][2]),
              @(transform.columns[0][3]),
              @(transform.columns[1][0]),
              @(transform.columns[1][1]),
              @(transform.columns[1][2]),
              @(transform.columns[1][3]),
              @(transform.columns[2][0]),
              @(transform.columns[2][1]),
              @(transform.columns[2][2]),
              @(transform.columns[2][3]),
              @(transform.columns[3][0]),
              @(transform.columns[3][1]),
              @(transform.columns[3][2]),
              @(transform.columns[3][3])
             ],
             @"imageResolution": @{
              @"width": @(camera.imageResolution.width),
              @"height": @(camera.imageResolution.height)
             },
             @"intrinsics": @[
              @(camera.intrinsics.columns[0][0]),
              @(camera.intrinsics.columns[0][1]),
              @(camera.intrinsics.columns[0][2]),
              @(camera.intrinsics.columns[1][0]),
              @(camera.intrinsics.columns[1][1]),
              @(camera.intrinsics.columns[1][2]),
              @(camera.intrinsics.columns[2][0]),
              @(camera.intrinsics.columns[2][1]),
              @(camera.intrinsics.columns[2][2])
             ],
             @"lightEstimate": @{
              @"ambientIntensity": @(lightEstimate.ambientIntensity),
              @"ambientColorTemperature": @(lightEstimate.ambientColorTemperature)
             }
           };
}

- (NSDictionary *)readCurrentFramePointCloud {
    ARFrame* currentFrame = self.session.currentFrame;
    ARPointCloud* pointcloud = currentFrame.rawFeaturePoints;
    NSMutableArray* points = [[NSMutableArray alloc] initWithCapacity:pointcloud.count];
    for (unsigned i=0; i<pointcloud.count; i++) {
        [points addObject: @(pointcloud.points[i].x)];
        [points addObject: @(pointcloud.points[i].y)];
        [points addObject: @(pointcloud.points[i].z)];
    }
    return @{
             @"timestamp": @(currentFrame.timestamp),
             @"points": points
             };
}

- (void)analyzeUsingModel:(NSString*)name {
    if ([name isEqual:@""]) { name = @"inceptionv3"; }
    
    if ([name isEqual:self.modelName]) { return; }
    self.modelName = [name lowercaseString];
    
    if ([self.modelName isEqual:@"mobilenet"]) {
        self.model = [[[MobileNet alloc] init] model];
    } else
    if ([self.modelName isEqual:@"squeezenet"]) {
        self.model = [[[SqueezeNet alloc] init] model];
    } else
    if ([self.modelName isEqual:@"age"]) {
        self.model = [[[AgeNet alloc] init] model];
    } else
    if ([self.modelName isEqual:@"gender"]) {
        self.model = [[[GenderNet alloc] init] model];
    } else
    if ([self.modelName isEqual:@"emotion"]) {
        self.model = [[[CNNEmotions alloc] init] model];
    } else
    {
        self.model = [[[Inceptionv3 alloc] init] model];
    }
}

- (void)analyzeCurrentFrame:(NSString*)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    [self analyzeUsingModel:name];
    [self analyzeCurrentFrame:resolve reject:reject withModel:self.model];
}

- (void)analyzeCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    [self analyzeCurrentFrame:@"" resolve:resolve reject:reject];
}

- (void)analyzeCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject withModel:(MLModel*)model {
    ARFrame* currentFrame = self.session.currentFrame;
    //ARCamera* camera = currentFrame.camera;
    
    // make Vision call
    VNCoreMLModel* vnmodel = [VNCoreMLModel modelForMLModel:model error:nil];
    VNCoreMLRequest* rq = [[VNCoreMLRequest alloc] initWithModel: vnmodel completionHandler: (VNRequestCompletionHandler) ^(VNRequest *request, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            // fulfill promise by building the results
            // NOTE: using SqueezeNet there were 997 results, many of which were exceedingly low confidence;
            // let's truncate to top ten for now
            NSMutableArray* results = [[NSMutableArray alloc] init];
            for (NSUInteger i=0; i<request.results.count && i<10; i++) {
                VNClassificationObservation* thisResult = (VNClassificationObservation *)request.results[i];
                [results addObject: @{ @"confidence": @(thisResult.confidence), @"identifier": thisResult.identifier}];
            }
            resolve(@{
                      @"timestamp": @(currentFrame.timestamp),
                      @"results": results
                      });
        });
    }];
    
    rq.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;
    
    NSDictionary *d = [[NSDictionary alloc] init];
    NSArray *a = @[rq];
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
                                      initWithCVPixelBuffer:currentFrame.capturedImage options:d];
    dispatch_async(dispatch_get_main_queue(), ^{
        [handler performRequests:a error:nil];
    });
}

- (void)barcodesCurrentFrame:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    ARFrame* currentFrame = self.session.currentFrame;
    ARCamera* camera = currentFrame.camera;
    
    // make Vision call
    VNDetectBarcodesRequest* rq = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler: (VNRequestCompletionHandler) ^(VNRequest *request, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            // fulfill promise by building the results
            // NOTE: using SqueezeNet there were 997 results, many of which were exceedingly low confidence;
            // let's truncate to top ten for now
            NSMutableArray* results = [[NSMutableArray alloc] init];
            for (NSUInteger i=0; i<request.results.count && i<10; i++) {
                VNBarcodeObservation* thisResult = (VNBarcodeObservation *)request.results[i];
                [results addObject: @{ @"payload": thisResult.payloadStringValue, @"symbology": (NSString*)(thisResult.symbology) }];
            }
            resolve(@{
                      @"timestamp": @(currentFrame.timestamp),
                      @"results": results
                      });
        });
    }];
    
    NSDictionary *d = [[NSDictionary alloc] init];
    NSArray *a = @[rq];
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
                                      initWithCVPixelBuffer:currentFrame.capturedImage options:d];
    dispatch_async(dispatch_get_main_queue(), ^{
        [handler performRequests:a error:nil];
    });
}

#pragma mark - Lazy loads

-(ARWorldTrackingConfiguration *)configuration {
    if (_configuration) {
        return _configuration;
    }
    
    if (!ARWorldTrackingConfiguration.isSupported) {}
    
    _configuration = [ARWorldTrackingConfiguration new];
    _configuration.planeDetection = ARPlaneDetectionHorizontal;
    return _configuration;
}



#pragma mark - Methods

- (void)snapshot:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    UIImage *image = [self.arView snapshot];
    _resolve = resolve;
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(thisImage:savedInAlbumWithError:ctx:), NULL);
}

- (void)thisImage:(UIImage *)image savedInAlbumWithError:(NSError *)error ctx:(void *)ctx {
    if (error) {
    } else {
        _resolve(@{ @"success": @(YES) });
    }
}


#pragma mark add models in the scene
- (void)addBox:(NSDictionary *)property {
    CGFloat width = [property[@"width"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    CGFloat length = [property[@"length"] floatValue];
    CGFloat chamfer = [property[@"chamfer"] floatValue];
    
    SCNBox *geometry = [SCNBox boxWithWidth:width height:height length:length chamferRadius:chamfer];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addSphere:(NSDictionary *)property {
    CGFloat radius = [property[@"radius"] floatValue];
    
    SCNSphere *geometry = [SCNSphere sphereWithRadius:radius];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCylinder:(NSDictionary *)property {
    CGFloat radius = [property[@"radius"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    
    SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:radius height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCone:(NSDictionary *)property {
    CGFloat topR = [property[@"topR"] floatValue];
    CGFloat bottomR = [property[@"bottomR"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    
    SCNCone *geometry = [SCNCone coneWithTopRadius:topR bottomRadius:bottomR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addPyramid:(NSDictionary *)property {
    CGFloat width = [property[@"width"] floatValue];
    CGFloat length = [property[@"length"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    
    SCNPyramid *geometry = [SCNPyramid pyramidWithWidth:width height:height length:length];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addTube:(NSDictionary *)property {
    CGFloat innerR = [property[@"innerR"] floatValue];
    CGFloat outerR = [property[@"outerR"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    SCNTube *geometry = [SCNTube tubeWithInnerRadius:innerR outerRadius:outerR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addTorus:(NSDictionary *)property {
    CGFloat ringR = [property[@"ringR"] floatValue];
    CGFloat pipeR = [property[@"pipeR"] floatValue];
    
    SCNTorus *geometry = [SCNTorus torusWithRingRadius:ringR pipeRadius:pipeR];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCapsule:(NSDictionary *)property {
    CGFloat capR = [property[@"capR"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    
    SCNCapsule *geometry = [SCNCapsule capsuleWithCapRadius:capR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addPlane:(NSDictionary *)property {
    CGFloat width = [property[@"width"] floatValue];
    CGFloat height = [property[@"height"] floatValue];
    
    SCNPlane *geometry = [SCNPlane planeWithWidth:width height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addText:(NSDictionary *)property {
    // init SCNText
    NSString *text = property[@"text"];
    CGFloat depth = [property[@"depth"] floatValue];
    if (!text) {
        text = @"(null)";
    }
    if (!depth) {
        depth = 0.0f;
    }
    CGFloat fontSize = [property[@"size"] floatValue];
    CGFloat size = fontSize / 12;
    SCNText *scnText = [SCNText textWithString:text extrusionDepth:depth / size];
    scnText.flatness = 0.1;
    
    // font
    NSString *font = property[@"name"];
    if (font) {
        scnText.font = [UIFont fontWithName:font size:12];
    } else {
        scnText.font = [UIFont systemFontOfSize:12];
    }
    
    // chamfer
    CGFloat chamfer = [property[@"chamfer"] floatValue];
    if (!chamfer) {
        chamfer = 0.0f;
    }
    scnText.chamferRadius = chamfer / size;
    
    // color
    if (property[@"color"]) {
        CGFloat r = [property[@"r"] floatValue];
        CGFloat g = [property[@"g"] floatValue];
        CGFloat b = [property[@"b"] floatValue];
        SCNMaterial *face = [SCNMaterial new];
        face.diffuse.contents = [[UIColor alloc] initWithRed:r green:g blue:b alpha:1.0f];
        SCNMaterial *border = [SCNMaterial new];
        border.diffuse.contents = [[UIColor alloc] initWithRed:r green:g blue:b alpha:1.0f];
        scnText.materials = @[face, face, border, border, border];
    }
    
    // init SCNNode
    SCNNode *textNode = [SCNNode nodeWithGeometry:scnText];
    
    // position textNode
    SCNVector3 min, max;
    [textNode getBoundingBoxMin:&min max:&max];
    textNode.position = SCNVector3Make(-(min.x + max.x) / 2, -(min.y + max.y) / 2, -(min.z + max.z) / 2);
    
    SCNNode *textOrigin = [[SCNNode alloc] init];
    [textOrigin addChildNode:textNode];
    textOrigin.scale = SCNVector3Make(size, size, size);
    [self addNodeToScene:textOrigin property:property];
}

- (void)addModel:(NSDictionary *)property {
    CGFloat scale = [property[@"scale"] floatValue];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:property[@"file"] withExtension:nil];
    SCNNode *node = [self loadModel:url nodeName:property[@"node"] withAnimation:YES];
    node.scale = SCNVector3Make(scale, scale, scale);
    [self addNodeToScene:node property:property];
}


#pragma mark model loader

- (SCNNode *)loadModel:(NSURL *)url nodeName:(NSString *)nodeName withAnimation:(BOOL)withAnimation {
    SCNScene *scene = [SCNScene sceneWithURL:url options:nil error:nil];
    
    SCNNode *node;
    if (nodeName) {
        node = [scene.rootNode childNodeWithName:nodeName recursively:YES];
    } else {
        node = [[SCNNode alloc] init];
        NSArray *nodeArray = [scene.rootNode childNodes];
        for (SCNNode *eachChild in nodeArray) {
            [node addChildNode:eachChild];
        }
    }
    
    if (withAnimation) {
        NSMutableArray *animationMutableArray = [NSMutableArray array];
        SCNSceneSource *sceneSource = [SCNSceneSource sceneSourceWithURL:url options:@{SCNSceneSourceAnimationImportPolicyKey:SCNSceneSourceAnimationImportPolicyPlayRepeatedly}];
        
        NSArray *animationIds = [sceneSource identifiersOfEntriesWithClass:[CAAnimation class]];
        for (NSString *eachId in animationIds){
            CAAnimation *animation = [sceneSource entryWithIdentifier:eachId withClass:[CAAnimation class]];
            [animationMutableArray addObject:animation];
        }
        NSArray *animationArray = [NSArray arrayWithArray:animationMutableArray];
        
        int i = 1;
        for (CAAnimation *animation in animationArray) {
            NSString *key = [NSString stringWithFormat:@"ANIM_%d", i];
            [node addAnimation:animation forKey:key];
            i++;
        }
    }
    
    return node;
}


#pragma mark executors of adding node to scene

- (void)addNodeToScene:(SCNNode *)node property:(NSDictionary *)property {
    node.position = [self getPositionFromProperty:property];
    
    NSString *key = [NSString stringWithFormat:@"%@", property[@"id"]];
    if (key) {
        [self registerNode:node forKey:key];
    }
    [self.localOrigin addChildNode:node];
}

- (SCNVector3)getPositionFromProperty:(NSDictionary *)property {
    CGFloat x = [property[@"x"] floatValue];
    CGFloat y = [property[@"y"] floatValue];
    CGFloat z = [property[@"z"] floatValue];
    
    if (property[@"x"] == NULL) {
        x = self.cameraOrigin.position.x - self.localOrigin.position.x;
    }
    if (property[@"y"] == NULL) {
        y = self.cameraOrigin.position.y - self.localOrigin.position.y;
    }
    if (property[@"z"] == NULL) {
        z = self.cameraOrigin.position.z - self.localOrigin.position.z;
    }
    
    return SCNVector3Make(x, y, z);
}


#pragma mark node register

- (void)registerNode:(SCNNode *)node forKey:(NSString *)key {
    [self removeNodeForKey:key];
    [self.nodes setObject:node forKey:key];
}

- (SCNNode *)nodeForKey:(NSString *)key {
    return [self.nodes objectForKey:key];
}

- (void)removeNodeForKey:(NSString *)key {
    SCNNode *node = [self.nodes objectForKey:key];
    if (node == nil) {
        return;
    }
    [node removeFromParentNode];
    [self.nodes removeObjectForKey:key];
}



#pragma mark - ARSCNViewDelegate

- (void)renderer:(id <SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    if (![anchor isKindOfClass:[ARPlaneAnchor class]]) {
        return;
    }
    
    SCNNode *parent = [node parentNode];
    NSLog(@"plane detected");
    //    NSLog(@"%f %f %f", parent.position.x, parent.position.y, parent.position.z);
    
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;
    
    //    NSLog(@"%@", @{
    //            @"id": planeAnchor.identifier.UUIDString,
    //            @"alignment": @(planeAnchor.alignment),
    //            @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
    //            @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
    //            @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
    //            @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
    //            });

    if (self.onPlaneDetected) {
        self.onPlaneDetected(@{
                               @"id": planeAnchor.identifier.UUIDString,
                               @"alignment": @(planeAnchor.alignment),
                               @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
                               @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
                               @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) },
                               @"transform": @[
                                   @(planeAnchor.transform.columns[0][0]),
                                   @(planeAnchor.transform.columns[0][1]),
                                   @(planeAnchor.transform.columns[0][2]),
                                   @(planeAnchor.transform.columns[0][3]),
                                   @(planeAnchor.transform.columns[1][0]),
                                   @(planeAnchor.transform.columns[1][1]),
                                   @(planeAnchor.transform.columns[1][2]),
                                   @(planeAnchor.transform.columns[1][3]),
                                   @(planeAnchor.transform.columns[2][0]),
                                   @(planeAnchor.transform.columns[2][1]),
                                   @(planeAnchor.transform.columns[2][2]),
                                   @(planeAnchor.transform.columns[2][3]),
                                   @(planeAnchor.transform.columns[3][0]),
                                   @(planeAnchor.transform.columns[3][1]),
                                   @(planeAnchor.transform.columns[3][2]),
                                   @(planeAnchor.transform.columns[3][3]),
                               ]
                               });
    }

    Plane *plane = [[Plane alloc] initWithAnchor: (ARPlaneAnchor *)anchor isHidden: ([self debug] ? NO : YES)];
    [self.planes setObject:plane forKey:anchor.identifier];
    [node addChildNode:plane];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer willUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;
    
    SCNNode *parent = [node parentNode];
    //    NSLog(@"%@", parent.name);
    //    NSLog(@"%f %f %f", node.position.x, node.position.y, node.position.z);
    //    NSLog(@"%f %f %f %f", node.rotation.x, node.rotation.y, node.rotation.z, node.rotation.w);
    
    
    //    NSLog(@"%@", @{
    //                   @"id": planeAnchor.identifier.UUIDString,
    //                   @"alignment": @(planeAnchor.alignment),
    //                   @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
    //                   @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
    //                   @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
    //                   @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
    //                   });

    if (self.onPlaneUpdate) {
        self.onPlaneUpdate(@{
                             @"id": planeAnchor.identifier.UUIDString,
                             @"alignment": @(planeAnchor.alignment),
                             @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
                             @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
                             @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) },
                             @"transform": @[
                                     @(planeAnchor.transform.columns[0][0]),
                                     @(planeAnchor.transform.columns[0][1]),
                                     @(planeAnchor.transform.columns[0][2]),
                                     @(planeAnchor.transform.columns[0][3]),
                                     @(planeAnchor.transform.columns[1][0]),
                                     @(planeAnchor.transform.columns[1][1]),
                                     @(planeAnchor.transform.columns[1][2]),
                                     @(planeAnchor.transform.columns[1][3]),
                                     @(planeAnchor.transform.columns[2][0]),
                                     @(planeAnchor.transform.columns[2][1]),
                                     @(planeAnchor.transform.columns[2][2]),
                                     @(planeAnchor.transform.columns[2][3]),
                                     @(planeAnchor.transform.columns[3][0]),
                                     @(planeAnchor.transform.columns[3][1]),
                                     @(planeAnchor.transform.columns[3][2]),
                                     @(planeAnchor.transform.columns[3][3]),
                                     ]
                             });
    }

    Plane *plane = [self.planes objectForKey:anchor.identifier];
    if (plane == nil) {
        return;
    }
    
    [plane update:(ARPlaneAnchor *)anchor];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    if (self.onPlaneRemoved) {
        self.onPlaneRemoved(@{ @"id": planeAnchor.identifier.UUIDString });
    }

    [self.planes removeObjectForKey:anchor.identifier];
}


#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
    //    self.cameraOrigin.transform = self.arView.pointOfView.transform;
    
    simd_float4 pos = frame.camera.transform.columns[3];
    self.cameraOrigin.position = SCNVector3Make(pos.x, pos.y, pos.z);
    simd_float4 z = frame.camera.transform.columns[2];
    self.cameraOrigin.eulerAngles = SCNVector3Make(0, atan2f(z.x, z.z), 0);

    //////////////////////////////////////////////////////////////////
    // Add WebARonARKit's SetData call here (including planes).
    // NOTE: still need to inject desired Javascript initially.
    // NOTE: can send objects through RN, not just JavaScript string.
    // NOTE: assumes fullscreen webview size.
    //////////////////////////////////////////////////////////////////

    // If the window size has changed, notify the JS side about it.
    // This is a hack due to the WKWebView not handling the
    // window.innerWidth/Height
    // correctly in the window.onresize events.
    // TODO: Remove this hack once the WKWebView has fixed the issue.

    // Send the per frame data needed in the JS side
    matrix_float4x4 viewMatrix =
        [frame.camera viewMatrixForOrientation:_interfaceOrientation];
    matrix_float4x4 modelMatrix = matrix_invert(viewMatrix);
    matrix_float4x4 projectionMatrix = [frame.camera
        projectionMatrixForOrientation:_interfaceOrientation
/*
                          viewportSize:CGSizeMake(self->wkWebView.frame.size.width,
                                                  self->wkWebView.frame.size.height)
*/
                          viewportSize:CGSizeMake(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height)

                                 zNear:self.near
                                 zFar:self.far];

    const float *pModelMatrix = (const float *)(&modelMatrix);
    const float *pViewMatrix = (const float *)(&viewMatrix);
    const float *pProjectionMatrix = (const float *)(&projectionMatrix);

    simd_quatf orientationQuat = simd_quaternion(modelMatrix);
    const float *pOrientationQuat = (const float *)(&orientationQuat);
    float position[3];
    position[0] = pModelMatrix[12];
    position[1] = pModelMatrix[13];
    position[2] = pModelMatrix[14];

    // TODO: Testing to see if we can pass the whole frame to JS...
    //  size_t width = CVPixelBufferGetWidth(frame.capturedImage);
    //  size_t height = CVPixelBufferGetHeight(frame.capturedImage);
    //  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(frame.capturedImage);
    //  void* pixels = CVPixelBufferGetBaseAddress(frame.capturedImage);
    //  OSType pixelFormatType =
    //  CVPixelBufferGetPixelFormatType(frame.capturedImage);
    //  NSLog(@"width = %d, height = %d, bytesPerRow = %d, ostype = %d", width,
    //  height, bytesPerRow, pixelFormatType);

    NSString *anchors = @"[";
    for (int i = 0; i < frame.anchors.count; i++) {
        ARPlaneAnchor *anchor = (ARPlaneAnchor *)frame.anchors[i];
        matrix_float4x4 anchorTransform = anchor.transform;
        const float *anchorMatrix = (const float *)(&anchorTransform);
        //NSLog(@"Plane extent (native) %@", [NSString stringWithFormat: @"%f,%f,%f", anchor.extent.x, anchor.extent.y, anchor.extent.z]);
        NSString *anchorStr = [NSString stringWithFormat:
                                            @"{\"modelMatrix\":[%f,%f,%f,%f,%f,%f,%f,%"
                                            @"f,%f,%f,%f,%f,%f,%f,%f,%f],"
                                            @"\"identifier\":%i,"
                                            @"\"alignment\":%i,"
                                            @"\"center\":[%f,%f,%f],"
                                            @"\"extent\":[%f,%f]}",
                                            anchorMatrix[0], anchorMatrix[1], anchorMatrix[2],
                                            anchorMatrix[3], anchorMatrix[4], anchorMatrix[5],
                                            anchorMatrix[6], anchorMatrix[7], anchorMatrix[8],
                                            anchorMatrix[9], anchorMatrix[10], anchorMatrix[11],
                                            anchorMatrix[12], anchorMatrix[13], anchorMatrix[14],
                                            anchorMatrix[15],
                                            (int)anchor.identifier,
                                            (int)anchor.alignment,
                                            anchor.center.x, anchor.center.y, anchor.center.z,
                                            anchor.extent.x, anchor.extent.z];
        if (i < frame.anchors.count - 1) {
            anchorStr = [anchorStr stringByAppendingString:@","];
        }
        anchors = [anchors stringByAppendingString:anchorStr];
    }
    anchors = [anchors stringByAppendingString:@"]"];

    NSString *jsCode = [NSString
        stringWithFormat:@"if (window.WebARonARKitSetData) "
                         @"window.WebARonARKitSetData({"
                         @"\"position\":[%f,%f,%f],"
                         @"\"orientation\":[%f,%f,%f,%f],"
                         @"\"viewMatrix\":[%f,%f,%f,%f,%f,%f,%f,%"
                         @"f,%f,%f,%f,%f,%f,%f,%f,%f],"
                         @"\"projectionMatrix\":[%f,%f,%f,%f,%f,%f,%f,%"
                         @"f,%f,%f,%f,%f,%f,%f,%f,%f],"
                         @"\"anchors\":%@"
                         @"});",
                         position[0], position[1], position[2],
                         pOrientationQuat[0], pOrientationQuat[1],
                         pOrientationQuat[2], pOrientationQuat[3], pViewMatrix[0],
                         pViewMatrix[1], pViewMatrix[2], pViewMatrix[3],
                         pViewMatrix[4], pViewMatrix[5], pViewMatrix[6],
                         pViewMatrix[7], pViewMatrix[8], pViewMatrix[9],
                         pViewMatrix[10], pViewMatrix[11], pViewMatrix[12],
                         pViewMatrix[13], pViewMatrix[14], pViewMatrix[15],
                         pProjectionMatrix[0], pProjectionMatrix[1],
                         pProjectionMatrix[2], pProjectionMatrix[3],
                         pProjectionMatrix[4], pProjectionMatrix[5],
                         pProjectionMatrix[6], pProjectionMatrix[7],
                         pProjectionMatrix[8], pProjectionMatrix[9],
                         pProjectionMatrix[10], pProjectionMatrix[11],
                         pProjectionMatrix[12], pProjectionMatrix[13],
                         pProjectionMatrix[14], pProjectionMatrix[15],
                         anchors];

    if (self.onWebARSetData) {
        // FIXME: this isn't getting through!
        self.onWebARSetData(@{ @"js": jsCode });
    }
    //This needs to be called after because the window size will affect the
    //projection matrix calculation upon resize
    
    if (_updateWindowSize) {
/*
        int width = self->wkWebView.frame.size.width;
        int height = self->wkWebView.frame.size.height;
 */
        int width = UIScreen.mainScreen.bounds.size.width;
        int height = UIScreen.mainScreen.bounds.size.height;

        NSString *updateWindowSizeJsCode = [NSString
            stringWithFormat:
                @"if(window.WebARonARKitSetWindowSize)"
                @"WebARonARKitSetWindowSize({\"width\":%i,\"height\":%i});",
                width, height];

        if (self.onWebARUpdateWindowSize) {
            self.onWebARUpdateWindowSize(@{ @"js": updateWindowSizeJsCode });
        }
        _updateWindowSize = false;
    }
}

//////////////////////////////////////////////////////////////////
// Import proposed notification hooks from WebARonARKit.
// NOTE: can send objects through RN, not just JavaScript string.
//////////////////////////////////////////////////////////////////

- (void)session:(ARSession *)session didAddAnchors:(nonnull NSArray<ARAnchor *> *)anchors
{
    // The session added anchors; update the lookaside timestamps array accordingly for each.
    long currentTime = (long)(NSTimeInterval)([[NSDate date] timeIntervalSince1970]);
    for (int i=0; i<anchors.count; i++) {
        [self.timestamps setObject:@(currentTime) forKey: anchors[i].identifier];
    }
}

- (void)session:(ARSession *)session didUpdateAnchors:(nonnull NSArray<ARAnchor *> *)anchors
{
    // The session updated anchors; update the lookaside timestamps array accordingly for each.
    long currentTime = (long)(NSTimeInterval)([[NSDate date] timeIntervalSince1970]);
    for (int i=0; i<anchors.count; i++) {
        [self.timestamps setObject:@(currentTime) forKey: anchors[i].identifier];
    }
}

- (void)session:(ARSession *)session didRemoveAnchors:(nonnull NSArray<ARAnchor *> *)anchors
{
    // The session removed anchors; remove from the lookaside timestamps array accordingly for each.
    for (int i=0; i<anchors.count; i++) {
        [self.timestamps removeObjectForKey: anchors[i].identifier];
    }
}



- (void)deviceOrientationDidChange:(NSNotification *)notification
{
    [self updateOrientation];
    _updateWindowSize = true;
}

- (void)updateOrientation
{
    _deviceOrientation = [[UIDevice currentDevice] orientation];
    switch (_deviceOrientation) {
        case UIDeviceOrientationPortrait: {
            _interfaceOrientation = UIInterfaceOrientationPortrait;
        } break;

        case UIDeviceOrientationPortraitUpsideDown: {
            _interfaceOrientation = UIInterfaceOrientationPortraitUpsideDown;
        } break;

        case UIDeviceOrientationLandscapeLeft: {
            _interfaceOrientation = UIInterfaceOrientationLandscapeRight;
        } break;

        case UIDeviceOrientationLandscapeRight: {
            _interfaceOrientation = UIInterfaceOrientationLandscapeLeft;
        } break;

        default:
            break;
    }
    //[self->_renderer setInterfaceOrientation:interfaceOrientation];
}



- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera {
    if (self.onTrackingState) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onTrackingState(@{
                                   @"state": @(camera.trackingState),
                                   @"reason": @(camera.trackingStateReason)
                                   });
        });
    }
}


#pragma mark - dealloc
-(void) dealloc {
}

@end

