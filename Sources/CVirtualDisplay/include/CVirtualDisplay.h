// Declarations for the private CoreGraphics virtual display API.
// Not in any public SDK header; the classes are resolved at runtime via
// NSClassFromString so a macOS release that removes them fails gracefully.
// Shapes validated on macOS 26.5 (see docs/superpowers/specs design doc).

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t _Nullable queue;
@property (retain, nonatomic) NSString *_Nullable name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (copy, nonatomic) void (^ _Nullable terminationHandler)(id sender, CGVirtualDisplay *display);
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@end

@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) double refreshRate;
@property (readonly, nonatomic) unsigned int height;
@property (readonly, nonatomic) unsigned int width;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

/// Factory that instantiates the private classes via NSClassFromString.
/// Direct class references from Swift would need link-time symbols that
/// CoreGraphics does not export; going through the runtime avoids that and
/// lets every method return nil when the API disappears in a future macOS.
@interface CVDApi : NSObject
+ (BOOL)available;
+ (CGVirtualDisplayDescriptor * _Nullable)makeDescriptor;
+ (CGVirtualDisplaySettings * _Nullable)makeSettings;
+ (CGVirtualDisplayMode * _Nullable)makeModeWithWidth:(unsigned int)width
                                               height:(unsigned int)height
                                              refresh:(double)refresh;
+ (CGVirtualDisplay * _Nullable)makeDisplayWithDescriptor:(CGVirtualDisplayDescriptor * _Nonnull)descriptor;
@end

NS_ASSUME_NONNULL_END
