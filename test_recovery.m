#import <Foundation/Foundation.h>
#import "Hardware.h"
#include <assert.h>
@interface LGMockBrightness : NSObject
@property(nonatomic) NSUInteger writes;
@end
@implementation LGMockBrightness
- (BOOL)setProperty:(id)value forKey:(NSString *)key { (void)value; (void)key; ++_writes; return YES; }
@end
int main(void) {
    @autoreleasepool {
        // Deliberately do not call hardware init: this fixture never opens the
        // private framework, detects a real device, or writes actual hardware.
        LGHardware *hardware = [LGHardware alloc];
        LGMockBrightness *mock = [LGMockBrightness new];
        NSDictionary *identity = @{@"model":@"test", @"osBuild":@"test", @"machineHash":@"test"};
        NSDictionary *snapshot = @{@"identity":identity, @"mapping":@[@[@0,@10],@[@1,@20]], @"mode":@2};
        NSString *missing = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [hardware setValue:mock forKey:@"client"];
        [hardware setValue:identity forKey:@"identity"];
        [hardware setValue:snapshot forKey:@"snapshot"];
        [hardware setValue:[NSURL fileURLWithPath:missing] forKey:@"snapshotURL"];
        [hardware setValue:@YES forKey:@"available"];
        [hardware setValue:@YES forKey:@"dirty"];
        [hardware setValue:@YES forKey:@"hasRecovery"];
        NSError *error = nil;
        assert([hardware restore:&error]);
        assert(error == nil && !hardware.hasRecovery && mock.writes == 3);
        assert([hardware restore:&error] && mock.writes == 3);
        puts("PASS: missing recovery cleanup after successful restore is safe and idempotent (mock only, no hardware writes)");
    }
    return 0;
}
