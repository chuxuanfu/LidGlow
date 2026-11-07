#import <Foundation/Foundation.h>
@interface LGHardware : NSObject
@property(nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) BOOL hasRecovery;
@property(nonatomic, readonly) double maximumNits;
@property(nonatomic, readonly) NSString *detail;
- (BOOL)setLevel:(double)level error:(NSError **)error;
- (BOOL)restore:(NSError **)error;
@end
