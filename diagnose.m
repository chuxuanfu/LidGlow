#import <Foundation/Foundation.h>
#import "Hardware.h"
int main(void) {
    @autoreleasepool {
        LGHardware *hardware = [LGHardware new];
        NSDictionary *report = @{@"available":@(hardware.available),
            @"hasRecovery":@(hardware.hasRecovery),
            @"maximumNits":@(hardware.maximumNits),
            @"detail":hardware.detail ?: @""};
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
