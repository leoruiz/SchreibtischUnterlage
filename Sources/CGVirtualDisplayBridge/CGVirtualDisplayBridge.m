#import "CGVirtualDisplayBridge.h"

// Private Core Graphics declarations adapted from DeskPad:
// https://github.com/Stengo/DeskPad
// Copyright (c) 2022 Bastian Andelefski, licensed under the MIT License.

@interface CGVirtualDisplayMode : NSObject

- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(CGFloat)refreshRate;

@end

@interface CGVirtualDisplaySettings : NSObject

@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;

@end

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplay : NSObject

@property(readonly, nonatomic) CGDirectDisplayID displayID;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

@interface CGVirtualDisplayDescriptor : NSObject

@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;

- (void)setDispatchQueue:(dispatch_queue_t)queue;

@end

NSErrorDomain const STUVirtualDisplayErrorDomain = @"app.ruiz.Schreibtischunterlage.VirtualDisplay";

@implementation STUVirtualDisplayMode

- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}

@end

@interface STUVirtualDisplaySession ()

@property(readwrite, nonatomic) CGDirectDisplayID displayID;
@property(strong, nonatomic, nullable) CGVirtualDisplay *display;

@end

@implementation STUVirtualDisplaySession

- (nullable instancetype)initWithName:(NSString *)name
                        maxPixelsWide:(uint32_t)maxPixelsWide
                        maxPixelsHigh:(uint32_t)maxPixelsHigh
                   sizeInMillimeters:(CGSize)sizeInMillimeters
                            vendorID:(uint32_t)vendorID
                           productID:(uint32_t)productID
                        serialNumber:(uint32_t)serialNumber
                               modes:(NSArray<STUVirtualDisplayMode *> *)modes
                               error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    [descriptor setDispatchQueue:dispatch_get_main_queue()];
    descriptor.name = name;
    descriptor.maxPixelsWide = maxPixelsWide;
    descriptor.maxPixelsHigh = maxPixelsHigh;
    descriptor.sizeInMillimeters = sizeInMillimeters;
    descriptor.vendorID = vendorID;
    descriptor.productID = productID;
    descriptor.serialNum = serialNumber;

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (!display) {
        if (error) {
            *error = [NSError errorWithDomain:STUVirtualDisplayErrorDomain
                                         code:STUVirtualDisplayErrorCreationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Core Graphics rejected the virtual display descriptor."
                                     }];
        }
        return nil;
    }

    NSMutableArray<CGVirtualDisplayMode *> *displayModes =
        [NSMutableArray arrayWithCapacity:modes.count];
    for (STUVirtualDisplayMode *mode in modes) {
        CGVirtualDisplayMode *displayMode =
            [[CGVirtualDisplayMode alloc] initWithWidth:mode.width
                                                height:mode.height
                                           refreshRate:(CGFloat)mode.refreshRate];
        [displayModes addObject:displayMode];
    }

    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = 1;
    settings.modes = displayModes;

    if (![display applySettings:settings]) {
        if (error) {
            *error = [NSError errorWithDomain:STUVirtualDisplayErrorDomain
                                         code:STUVirtualDisplayErrorSettingsRejected
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Core Graphics rejected the virtual display settings."
                                     }];
        }
        return nil;
    }

    self.display = display;
    self.displayID = display.displayID;
    return self;
}

- (void)stop {
    self.display = nil;
    self.displayID = kCGNullDirectDisplay;
}

- (void)dealloc {
    [self stop];
}

@end
