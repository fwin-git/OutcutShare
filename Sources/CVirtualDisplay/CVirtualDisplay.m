#import "include/CVirtualDisplay.h"

@implementation CVDApi

+ (BOOL)available {
    return NSClassFromString(@"CGVirtualDisplayDescriptor") != nil
        && NSClassFromString(@"CGVirtualDisplaySettings") != nil
        && NSClassFromString(@"CGVirtualDisplayMode") != nil
        && NSClassFromString(@"CGVirtualDisplay") != nil;
}

+ (CGVirtualDisplayDescriptor *)makeDescriptor {
    return [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
}

+ (CGVirtualDisplaySettings *)makeSettings {
    return [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
}

+ (CGVirtualDisplayMode *)makeModeWithWidth:(unsigned int)width
                                     height:(unsigned int)height
                                    refresh:(double)refresh {
    CGVirtualDisplayMode *mode = [NSClassFromString(@"CGVirtualDisplayMode") alloc];
    return [mode initWithWidth:width height:height refreshRate:refresh];
}

+ (CGVirtualDisplay *)makeDisplayWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor {
    CGVirtualDisplay *display = [NSClassFromString(@"CGVirtualDisplay") alloc];
    return [display initWithDescriptor:descriptor];
}

@end
