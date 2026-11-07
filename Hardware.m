#import "Hardware.h"
#import "Signal.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <math.h>
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>
@protocol LGCoreBrightness
- (id)copyPropertyForKey:(NSString *)key;
- (BOOL)setProperty:(id)value forKey:(NSString *)key;
@end
static NSString *const MappingKey = @"LEPWMBrightnessNitsMapping";
static NSString *const ModeKey = @"LEBacklightMode";
static BOOL fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"LidGlow" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSString *systemValue(const char *key) {
    size_t size = 0;
    if (sysctlbyname(key, NULL, &size, NULL, 0) != 0 || !size || size > 4096) return nil;
    char *value = calloc(size + 1, 1);
    if (!value) return nil;
    NSString *result = nil;
    if (sysctlbyname(key, value, &size, NULL, 0) == 0) result = [NSString stringWithUTF8String:value];
    free(value); return result;
}
static BOOL signaturesMatch(id client) {
    NSMethodSignature *get = [client methodSignatureForSelector:@selector(copyPropertyForKey:)];
    NSMethodSignature *set = [client methodSignatureForSelector:@selector(setProperty:forKey:)];
    if (!get || !set || get.numberOfArguments != 3 || set.numberOfArguments != 4) return NO;
    return strcmp(get.methodReturnType, @encode(id)) == 0 &&
        (strcmp(set.methodReturnType, @encode(BOOL)) == 0 || strcmp(set.methodReturnType, "B") == 0) &&
        strcmp([get getArgumentTypeAtIndex:2], @encode(id)) == 0 &&
        strcmp([set getArgumentTypeAtIndex:2], @encode(id)) == 0 &&
        strcmp([set getArgumentTypeAtIndex:3], @encode(id)) == 0;
}
// Reject unknown shapes rather than infer a private framework's contract.
static double maximum(NSArray *mapping) {
    if (![mapping isKindOfClass:NSArray.class] || mapping.count < 1 || mapping.count > 4096) return 0;
    double cap = 0;
    for (id row in mapping) {
        if (![row isKindOfClass:NSArray.class] || [row count] != 2) return 0;
        for (id v in row) if (![v isKindOfClass:NSNumber.class] || !isfinite([v doubleValue]) || [v doubleValue] < 0) return 0;
        cap = fmax(cap, [row[1] doubleValue]);
    }
    return cap;
}
@implementation LGHardware {
    id<LGCoreBrightness> _client;
    NSURL *_snapshotURL;
    NSDictionary *_snapshot;
    BOOL _dirty;
    NSDictionary *_identity;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _detail = @"No supported logo backlight found. No settings will be written.";
#if !defined(__arm64__)
    return self;
#else
    io_registry_entry_t node = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pwm1/bklb-backlight");
    if (!node) return self;
    IOObjectRelease(node);
    if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW | RTLD_LOCAL)) return self;
    Class cls = NSClassFromString(@"BrightnessSystemClient");
    _client = (id<LGCoreBrightness>)[[cls alloc] init];
    if (![(id)_client respondsToSelector:@selector(copyPropertyForKey:)] || ![(id)_client respondsToSelector:@selector(setProperty:forKey:)]) return self;
    if (!signaturesMatch(_client)) { _detail = @"Private interface signature mismatch. No calls will be made."; return self; }
    NSString *model = systemValue("hw.model"), *build = systemValue("kern.osversion");
    io_service_t platform = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    NSString *machine = platform ? CFBridgingRelease(IORegistryEntryCreateCFProperty(platform, CFSTR("IOPlatformUUID"), kCFAllocatorDefault, 0)) : nil;
    if (platform) IOObjectRelease(platform);
    if (!model || !build || ![machine isKindOfClass:NSString.class] || !machine.length) return self;
    NSData *machineBytes = [machine dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(machineBytes.bytes, (CC_LONG)machineBytes.length, digest);
    NSMutableString *machineHash = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); ++i) [machineHash appendFormat:@"%02x", digest[i]];
    _identity = @{@"model":model, @"osBuild":build, @"machineHash":machineHash};
    NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    _snapshotURL = [[support URLByAppendingPathComponent:@"LidGlowLab" isDirectory:YES] URLByAppendingPathComponent:@"recovery.plist"];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:_snapshotURL.path];
    if (exists) {
        _snapshot = [NSDictionary dictionaryWithContentsOfURL:_snapshotURL];
        _dirty = YES;
        _hasRecovery = YES;
        if (![self validSnapshot:_snapshot]) { _detail = @"Recovery data is incompatible or damaged (the device or OS may have changed). No writes will be made."; return self; }
    } else {
        id mapping = [_client copyPropertyForKey:MappingKey];
        id mode = [_client copyPropertyForKey:ModeKey];
        if (!mapping || !mode) return self;
        _snapshot = @{@"mapping":mapping, @"mode":mode, @"identity":_identity};
        if (![self validSnapshot:_snapshot]) { _detail = @"The system returned an unsupported brightness mapping or mode. No writes will be made."; return self; }
    }
    _maximumNits = maximum(_snapshot[@"mapping"]);
    _available = YES;
    _detail = @"Logo backlight interface found. Experimental hardware control.";
    return self;
#endif
}
- (BOOL)validSnapshot:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"identity"] isEqual:_identity]) return NO;
    id mode = snapshot[@"mode"];
    return maximum(snapshot[@"mapping"]) > 0 && [mode isKindOfClass:NSNumber.class] && ([mode doubleValue] == 0 || [mode doubleValue] == 2);
}
- (BOOL)saveBeforeWrite:(NSError **)error {
    if (_dirty) return YES;
    // Re-read immediately before each new ownership session; don't overwrite settings changed while idle.
    id mapping = [_client copyPropertyForKey:MappingKey], mode = [_client copyPropertyForKey:ModeKey];
    NSDictionary *fresh = mapping && mode ? @{@"mapping":mapping, @"mode":mode, @"identity":_identity} : nil;
    if (![self validSnapshot:fresh]) return fail(error, @"Could not safely read the original settings. Write cancelled.");
    _snapshot = fresh;
    _maximumNits = maximum(fresh[@"mapping"]);
    if (![[NSFileManager defaultManager] createDirectoryAtURL:[_snapshotURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    if (![_snapshot writeToURL:_snapshotURL atomically:YES]) return fail(error, @"Could not save recovery data. Write cancelled.");
    chmod(_snapshotURL.fileSystemRepresentation, 0600);
    _dirty = YES;
    return YES;
}
- (BOOL)setLevel:(double)level error:(NSError **)error {
    if (!_available || _hasRecovery) return fail(error, @"Hardware unavailable, or previous settings must be restored first.");
    if (!isfinite(level) || level < 0 || level > 1) return fail(error, @"Brightness is out of range.");
    if (![self saveBeforeWrite:error]) return NO;
    double nits = lg_clamp(level) * _maximumNits;
    NSArray *mapping = @[@[@0, @(nits)], @[@(3.4e38), @(nits)]];
    if (![_client setProperty:mapping forKey:MappingKey] || ![_client setProperty:@(level == 0 ? 0 : 2) forKey:ModeKey] || ![_client setProperty:@1 forKey:@"DisplayPowerStateEvent"]) return fail(error, @"The system rejected a backlight write. Effects stopped; restore the original settings.");
    return YES;
}
- (BOOL)restore:(NSError **)error {
    if (!_dirty) return YES;
    if (!_available || ![self validSnapshot:_snapshot]) return fail(error, @"Recovery data is unavailable. No write was attempted.");
    // Attempt each original property even when another write fails.
    BOOL a = [_client setProperty:_snapshot[@"mapping"] forKey:MappingKey];
    BOOL b = [_client setProperty:_snapshot[@"mode"] forKey:ModeKey];
    BOOL c = [_client setProperty:@1 forKey:@"DisplayPowerStateEvent"];
    if (!a || !b || !c) return fail(error, @"Restore did not complete. Recovery data has been kept; please retry.");
    NSError *cleanupError = nil;
    if (![[NSFileManager defaultManager] removeItemAtURL:_snapshotURL error:&cleanupError]) {
        // All original properties are already restored. A concurrent OS quit /
        // reopen can finish cleanup first; missing data is not a restore failure.
        if (![cleanupError.domain isEqualToString:NSCocoaErrorDomain] || cleanupError.code != NSFileNoSuchFileError) {
            if (error) *error = cleanupError;
            return NO;
        }
    }
    _dirty = NO; _hasRecovery = NO;
    return YES;
}
@end
