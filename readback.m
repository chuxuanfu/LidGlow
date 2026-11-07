#import <Foundation/Foundation.h>
#import <dlfcn.h>
@protocol Readback
- (id)copyPropertyForKey:(NSString *)key;
@end
int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW|RTLD_LOCAL)) return 1;
        id<Readback> client = (id<Readback>)[[NSClassFromString(@"BrightnessSystemClient") alloc] init];
        id mapping = [client copyPropertyForKey:@"LEPWMBrightnessNitsMapping"];
        id mode = [client copyPropertyForKey:@"LEBacklightMode"];
        NSDictionary *report = @{@"mapping":mapping ?: NSNull.null, @"mode":mode ?: NSNull.null};
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        if (!data) return 2;
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
