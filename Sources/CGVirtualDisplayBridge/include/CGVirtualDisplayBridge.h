#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const STUVirtualDisplayErrorDomain;

typedef NS_ERROR_ENUM(STUVirtualDisplayErrorDomain, STUVirtualDisplayErrorCode) {
    STUVirtualDisplayErrorCreationFailed = 1,
    STUVirtualDisplayErrorSettingsRejected = 2,
};

@interface STUVirtualDisplayMode : NSObject

@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
@property(readonly, nonatomic) double refreshRate;

- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface STUVirtualDisplaySession : NSObject

@property(readonly, nonatomic) CGDirectDisplayID displayID;

- (nullable instancetype)initWithName:(NSString *)name
                        maxPixelsWide:(uint32_t)maxPixelsWide
                        maxPixelsHigh:(uint32_t)maxPixelsHigh
                   sizeInMillimeters:(CGSize)sizeInMillimeters
                            vendorID:(uint32_t)vendorID
                           productID:(uint32_t)productID
                        serialNumber:(uint32_t)serialNumber
                               modes:(NSArray<STUVirtualDisplayMode *> *)modes
                               error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
