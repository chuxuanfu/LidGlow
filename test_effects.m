// Exercise production mode changes/ticks without UI, capture, preferences or hardware.
#import <QuartzCore/QuartzCore.h>
static CFTimeInterval effectNow = 100;
static CFTimeInterval effectClock(void) { return effectNow; }
#define CACurrentMediaTime effectClock
#define main lidglow_unlaunched_main
#import "main.m"
#undef main
#undef CACurrentMediaTime
#include <assert.h>

static const double floorFraction = .01;
@interface LGEffectPicker : NSObject
@property(nonatomic) NSInteger indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
@end
@implementation LGEffectPicker
- (void)selectItemAtIndex:(NSInteger)index { _indexOfSelectedItem = index; }
@end
@interface LGEffectSlider : NSObject
@property(nonatomic) double doubleValue;
@end
@implementation LGEffectSlider
@end
@interface LGEffectText : NSObject
@property(nonatomic, copy) NSString *stringValue;
@end
@implementation LGEffectText
@end
@interface LGEffectHardware : NSObject
@property(nonatomic) NSUInteger writes, restores;
@property(nonatomic) double level;
- (BOOL)available;
- (BOOL)hasRecovery;
- (BOOL)setLevel:(double)level error:(NSError **)error;
- (BOOL)restore:(NSError **)error;
@end
@implementation LGEffectHardware
- (BOOL)available { return YES; }
- (BOOL)hasRecovery { return NO; }
- (BOOL)setLevel:(double)level error:(NSError **)error {
    (void)error;
    assert(isfinite(level) && level >= 0 && level <= 1);
    _level = level; ++_writes; return YES;
}
- (BOOL)restore:(NSError **)error { (void)error; ++_restores; return YES; }
@end
@interface LGEffectAudio : NSObject
@property(nonatomic) LGAudioSignal signal;
@property(nonatomic) NSUInteger starts, stops;
- (void)startWithCompletion:(void (^)(NSError *))completion;
- (void)stop;
- (LGAudioSignal)signalForSensitivity:(double)sensitivity;
@end
@implementation LGEffectAudio
- (void)startWithCompletion:(void (^)(NSError *))completion { ++_starts; completion(nil); }
- (void)stop { ++_stops; }
- (LGAudioSignal)signalForSensitivity:(double)sensitivity { (void)sensitivity; return _signal; }
@end
@interface LGEffectApp : LGApp
@end
@implementation LGEffectApp
- (void)tune:(id)sender { (void)sender; }
@end
static LGEffectApp *fixture(double maximum) {
    LGEffectApp *app = [LGEffectApp new];
    [app setValue:[LGEffectPicker new] forKey:@"modePicker"];
    [app setValue:[LGEffectHardware new] forKey:@"hardware"];
    [app setValue:[LGEffectAudio new] forKey:@"audio"];
    [app setValue:[LGEffectText new] forKey:@"live"];
    for (NSString *key in @[@"brightness", @"period", @"gain"]) {
        LGEffectSlider *slider = [LGEffectSlider new];
        slider.doubleValue = [key isEqualToString:@"brightness"] ? maximum : 4;
        [app setValue:slider forKey:key];
    }
    [app setValue:@YES forKey:@"audioDisclosureAccepted"];
    [app setValue:@(-1) forKey:@"lastWritten"];
    return app;
}
static LGEffectHardware *hardware(LGEffectApp *app) { return [app valueForKey:@"hardware"]; }
static LGEffectAudio *audio(LGEffectApp *app) { return [app valueForKey:@"audio"]; }
static double maximum(LGEffectApp *app) { return [[app valueForKey:@"brightness"] doubleValue]; }
static void selectMode(LGEffectApp *app, LGMode mode) {
    [[app valueForKey:@"modePicker"] selectItemAtIndex:mode];
    [app changeMode:nil];
}
static void tick(LGEffectApp *app, double phase) {
    double now = (effectNow += 1.0 / 30);
    [app setValue:@(now - phase) forKey:@"started"];
    [app setValue:@(now - 1.0 / 30) forKey:@"lastTick"];
    [app tick:nil];
}
static void assertLit(LGEffectApp *app) {
    double value = hardware(app).level, cap = maximum(app);
    assert(hardware(app).writes);
    assert(value >= cap * floorFraction - 1e-12 && value <= cap + 1e-12);
    assert(cap == 0 || value > 0);
}
static void silenceAndTroughs(void) {
    const double caps[] = {1, .6, .05, .001, .000001};
    const double blends[] = {0, .25, .5, .75, 1};
    for (size_t c = 0; c < sizeof(caps) / sizeof(caps[0]); ++c) {
        for (LGMode mode = LGMusic; mode <= LGAdaptive; ++mode) {
            LGEffectApp *app = fixture(caps[c]); selectMode(app, mode); assertLit(app);
            // Silence at startup, active beat troughs and all crossfade positions.
            for (int active = 0; active <= 1; ++active) {
                audio(app).signal = (LGAudioSignal){0, 0, active};
                for (size_t b = 0; b < sizeof(blends) / sizeof(blends[0]); ++b) {
                    [app setValue:@(blends[b]) forKey:@"autoBlend"];
                    tick(app, 0); assertLit(app);
                }
            }
            audio(app).signal = (LGAudioSignal){1, .2, YES};
            [app setValue:@1 forKey:@"autoBlend"]; tick(app, 2);
            assert(fabs(hardware(app).level - caps[c]) < 1e-10);
            // Stale/reset DSP output stays zero; only the lighting layer supplies a floor.
            LGMusicState detector; lg_music_reset(&detector);
            LGMusicOutput stale = lg_music_read(&detector, INFINITY);
            assert(stale.level == 0 && !stale.active);
            audio(app).signal = (LGAudioSignal){stale.level, stale.rms, stale.active};
            for (int i = 0; i < 300; ++i) { tick(app, 0); assertLit(app); }
            for (int i = 0; i < 600; ++i) {
                audio(app).signal = (LGAudioSignal){i % 3 ? 0 : 1, .01, (i / 30) % 2};
                tick(app, (i % 120) / 30.0); assertLit(app);
            }
        }
    }
    puts("PASS: production Music/Auto ticks retain a dim floor through silence, troughs, stale data, all blends and repeated sound transitions within every tested maximum (mock only)");
}
static void modesAndCaps(void) {
    for (LGMode mode = LGMusic; mode <= LGAdaptive; ++mode) {
        LGEffectApp *app = fixture(.6); selectMode(app, LGOff);
        assert(hardware(app).level == 0);
        selectMode(app, mode); assertLit(app);
        LGEffectSlider *brightness = [app valueForKey:@"brightness"];
        brightness.doubleValue = 0; [app setValue:@0 forKey:@"lastPreview"];
        tick(app, 0); assert(hardware(app).level == 0);
        assert([[[app valueForKey:@"live"] stringValue] containsString:@"Requested 0%"]);
        // Re-enable below the .005 write threshold without changing the mode.
        brightness.doubleValue = .001; [app setValue:@0 forKey:@"lastPreview"];
        tick(app, 0); assertLit(app);
        assert([[[app valueForKey:@"live"] stringValue] containsString:@"Requested <1%"]);
        brightness.doubleValue = .002; tick(app, 0); assertLit(app);
        audio(app).signal = (LGAudioSignal){1, .2, YES};
        [app setValue:@1 forKey:@"autoBlend"]; tick(app, 2); assertLit(app);
        brightness.doubleValue = .001; tick(app, 2); assertLit(app);
        selectMode(app, LGOff); assert(hardware(app).level == 0);
        selectMode(app, LGManual); assert(hardware(app).level == .001);
        brightness.doubleValue = 0; tick(app, 0); assert(hardware(app).level == 0);
        NSUInteger writes = hardware(app).writes, restores = hardware(app).restores;
        selectMode(app, LGSystem); tick(app, 0);
        assert(hardware(app).writes == writes && hardware(app).restores == restores + 1);
        selectMode(app, mode); writes = hardware(app).writes;
        [app setValue:@YES forKey:@"pendingAudio"]; tick(app, 0);
        [app setValue:@NO forKey:@"pendingAudio"];
        [app setValue:@YES forKey:@"suspended"]; tick(app, 0);
        assert(hardware(app).writes == writes);
    }
    // Breathe retains its original waveform rather than gaining a new floor.
    LGEffectApp *breathe = fixture(.6); selectMode(breathe, LGBreathe);
    tick(breathe, 0); assert(hardware(breathe).level < .000001);
    tick(breathe, 2); assert(fabs(hardware(breathe).level - .6) < 1e-10);
    assert(lg_breathe(0, 4) == 0 && lg_breathe(2, 4) == 1 && lg_breathe(4, 4) == 0);
    puts("PASS: zero maximum, sub-threshold re-enable/cap changes, Off/Manual/Restore, pending/suspended effects and unchanged Breathe waveform (mock only)");
}
int main(void) {
    @autoreleasepool { silenceAndTroughs(); modesAndCaps(); }
    return 0;
}
