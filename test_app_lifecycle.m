// Exercise the production suspend/resume methods with no UI, capture or hardware.
#define main lidglow_unlaunched_main
#import "main.m"
#undef main
#include <assert.h>
@interface LGTestPicker : NSObject
@property(nonatomic) NSInteger indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
@end
@implementation LGTestPicker
- (void)selectItemAtIndex:(NSInteger)index { _indexOfSelectedItem = index; }
@end
@interface LGTestAudio : NSObject
@property(nonatomic) NSUInteger stops;
- (void)stop;
@end
@implementation LGTestAudio
- (void)stop { ++_stops; }
@end
@interface LGTestApp : LGApp
@property(nonatomic) BOOL restoreSucceeds;
@property(nonatomic) NSUInteger restoreCalls;
@property(nonatomic) NSUInteger resumeCalls;
@property(nonatomic) NSInteger resumedMode;
@property(nonatomic) NSUInteger failureCalls;
- (void)changeWhileSuspended;
@end
@implementation LGTestApp
- (BOOL)restore { ++_restoreCalls; return _restoreSucceeds; }
- (void)tune:(id)sender { (void)sender; }
- (void)changeMode:(id)sender {
    (void)sender; ++_resumeCalls;
    _resumedMode = [(LGTestPicker *)[self valueForKey:@"modePicker"] indexOfSelectedItem];
}
- (void)changeWhileSuspended { [super changeMode:nil]; }
- (void)effectFailed:(NSString *)message { (void)message; ++_failureCalls; }
@end
static NSNotification *event(NSString *name) { return [NSNotification notificationWithName:name object:nil]; }
static LGTestApp *fixture(NSInteger mode) {
    LGTestApp *app = [LGTestApp new]; app.restoreSucceeds = YES;
    LGTestPicker *picker = [LGTestPicker new]; picker.indexOfSelectedItem = mode;
    [app setValue:picker forKey:@"modePicker"];
    [app setValue:[LGTestAudio new] forKey:@"audio"];
    [app setValue:@(mode) forKey:@"mode"];
    [app setValue:@YES forKey:@"pendingAudio"];
    return app;
}
int main(void) {
    @autoreleasepool {
        for (NSInteger mode = LGSystem; mode <= LGAdaptive; ++mode) {
            LGTestApp *app = fixture(mode);
            [app suspend:event(NSWorkspaceScreensDidSleepNotification)];
            [app suspend:event(NSWorkspaceWillSleepNotification)];
            [app suspend:event(@"com.apple.screenIsLocked")];
            assert([[app valueForKey:@"suspended"] boolValue]);
            assert(![[app valueForKey:@"pendingAudio"] boolValue]);
            assert([[app valueForKey:@"mode"] integerValue] == LGSystem);
            assert([[app valueForKey:@"selection"] unsignedIntegerValue] == 3);
            [app resume:event(NSWorkspaceScreensDidWakeNotification)];
            [app resume:event(NSWorkspaceDidWakeNotification)];
            assert(app.resumeCalls == 0 && app.restoreCalls == 0);
            [app resume:event(@"com.apple.screenIsUnlocked")];
            assert(app.restoreCalls == 1 && app.resumeCalls == 1 && app.resumedMode == mode);
            assert(![[app valueForKey:@"suspended"] boolValue]);
            [app resume:event(@"com.apple.screenIsUnlocked")];
            assert(app.resumeCalls == 1); /* Duplicate wake cannot restart capture. */
        }
        LGTestApp *failed = fixture(LGAdaptive); failed.restoreSucceeds = NO;
        [failed suspend:event(NSWorkspaceScreensDidSleepNotification)];
        [failed resume:event(NSWorkspaceScreensDidWakeNotification)];
        assert(failed.restoreCalls == 1 && failed.resumeCalls == 0);
        assert([(LGTestPicker *)[failed valueForKey:@"modePicker"] indexOfSelectedItem] == LGSystem);
        LGTestApp *cancelled = fixture(LGMusic);
        [cancelled suspend:event(NSWorkspaceScreensDidSleepNotification)];
        [(LGTestPicker *)[cancelled valueForKey:@"modePicker"] selectItemAtIndex:LGOff];
        [cancelled changeWhileSuspended];
        [cancelled resume:event(NSWorkspaceScreensDidWakeNotification)];
        assert(cancelled.resumedMode == LGOff);
        LGTestApp *audioFirst = fixture(LGAdaptive);
        [audioFirst audioFailed:@"System stopped capture"];
        [audioFirst suspend:event(NSWorkspaceScreensDidSleepNotification)];
        [audioFirst resume:event(NSWorkspaceScreensDidWakeNotification)];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        assert(audioFirst.resumeCalls == 1 && audioFirst.resumedMode == LGAdaptive && audioFirst.failureCalls == 0);
        LGTestApp *realFailure = fixture(LGMusic);
        [realFailure audioFailed:@"Unrelated capture failure"];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        assert(realFailure.failureCalls == 1 && realFailure.resumeCalls == 0);
        puts("PASS: production app suspend/resume, all modes, pending capture cancellation, locked-wake deferral, restore failure, explicit Off, duplicate events and audio-error-before-sleep ordering (mock only)");
    }
    return 0;
}
