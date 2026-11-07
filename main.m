#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>
#import "Hardware.h"
#import "AudioMeter.h"
#import "Signal.h"
#import "Lifecycle.h"
#import <math.h>

typedef NS_ENUM(NSInteger, LGMode) { LGSystem, LGOff, LGManual, LGBreathe, LGMusic, LGAdaptive };
@interface LGApp : NSObject <NSApplicationDelegate>
@end
@implementation LGApp {
    NSStatusItem *_item;
    NSPopover *_popover;
    NSWindow *_debugWindow;
    NSPopUpButton *_modePicker;
    NSSlider *_brightness, *_period, *_gain;
    NSButton *_login, *_loginSettings;
    NSTextField *_state, *_values, *_live, *_loginHint;
    NSLevelIndicator *_meter;
    LGHardware *_hardware;
    LGAudioMeter *_audio;
    NSTimer *_timer;
    LGMode _mode;
    LGLifecycle _lifecycle;
    NSUInteger _selection;
    double _started, _lastTick, _lastWritten, _autoBlend, _lastPreview;
    BOOL _pendingAudio, _suspended, _autoMusic, _audioDisclosureAccepted;
}
- (NSTextField *)label:(NSString *)text y:(CGFloat)y height:(CGFloat)height {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.frame = NSMakeRect(24, y, 340, height);
    field.font = [NSFont systemFontOfSize:12];
    return field;
}
- (NSSlider *)sliderAt:(CGFloat)y min:(double)min max:(double)max value:(double)value name:(NSString *)name in:(NSView *)view {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:self action:@selector(tune:)];
    slider.frame = NSMakeRect(24, y, 340, 24);
    slider.accessibilityLabel = name;
    [view addSubview:slider]; return slider;
}
- (double)setting:(NSString *)key fallback:(double)fallback min:(double)min max:(double)max {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return fallback;
    return fmax(min, fmin(max, [value doubleValue]));
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _hardware = [LGHardware new]; _audio = [LGAudioMeter new];
    _audioDisclosureAccepted = [NSUserDefaults.standardUserDefaults boolForKey:@"AudioDisclosureAccepted"];
    __weak LGApp *weakSelf = self;
    _audio.onError = ^(NSString *message) { [weakSelf audioFailed:message]; };
    _lastWritten = -1;
    _item = [[NSStatusBar systemStatusBar] statusItemWithLength:28];
    NSImage *symbol = [NSImage imageWithSize:NSMakeSize(20, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [NSColor.blackColor setStroke];
        NSBezierPath *lid = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3, 4, 14, 10) xRadius:2 yRadius:2];
        lid.lineWidth = 1.4; [lid stroke];
        NSBezierPath *glow = [NSBezierPath bezierPath]; glow.lineWidth = 1.8; glow.lineCapStyle = NSLineCapStyleRound;
        [glow moveToPoint:NSMakePoint(7, 9)]; [glow lineToPoint:NSMakePoint(13, 9)]; [glow stroke];
        NSBezierPath *base = [NSBezierPath bezierPath]; base.lineWidth = 1.3; base.lineCapStyle = NSLineCapStyleRound;
        [base moveToPoint:NSMakePoint(2, 2)]; [base lineToPoint:NSMakePoint(18, 2)]; [base stroke];
        return YES;
    }];
    symbol.template = YES;
    _item.button.image = symbol;
    _item.button.toolTip = @"LidGlow";
    _item.button.accessibilityLabel = @"LidGlow controls";
    _item.button.target = self; _item.button.action = @selector(show:);
    NSMenu *menu = [NSMenu new]; NSMenuItem *appMenu = [NSMenuItem new]; [menu addItem:appMenu];
    appMenu.submenu = [[NSMenu alloc] initWithTitle:@"LidGlow"];
    [appMenu.submenu addItemWithTitle:@"Quit LidGlow" action:@selector(terminate:) keyEquivalent:@"q"];
    NSApp.mainMenu = menu;
    NSViewController *controller = [NSViewController new];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 388, 620)]; controller.view = view;
    NSTextField *title = [self label:@"LidGlow" y:566 height:30];
    title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightSemibold]; [view addSubview:title];
    NSTextField *subtitle = [self label:@"Logo backlight · local and private" y:539 height:20];
    subtitle.textColor = NSColor.secondaryLabelColor; [view addSubview:subtitle];
    [view addSubview:[self label:@"Lighting mode" y:505 height:20]];
    _modePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 470, 340, 30) pullsDown:NO];
    [_modePicker addItemsWithTitles:@[@"Restore / System control", @"Off", @"Manual", @"Breathe", @"Music", @"Auto · Breathe + Music"]];
    _modePicker.accessibilityLabel = @"Lighting mode";
    _modePicker.target = self; _modePicker.action = @selector(changeMode:);
    _modePicker.enabled = _hardware.available; [view addSubview:_modePicker];
    _live = [self label:@"" y:439 height:23]; _live.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]; [view addSubview:_live];
    [view addSubview:[self label:@"Maximum brightness" y:405 height:20]];
    _brightness = [self sliderAt:378 min:0 max:1 value:[self setting:@"MaximumBrightness" fallback:.6 min:0 max:1] name:@"Maximum brightness" in:view];
    [view addSubview:[self label:@"Breathing period (seconds)" y:346 height:20]];
    _period = [self sliderAt:320 min:1 max:10 value:[self setting:@"BreathingPeriod" fallback:4 min:1 max:10] name:@"Breathing period" in:view];
    [view addSubview:[self label:@"Beat sensitivity" y:288 height:20]];
    _gain = [self sliderAt:262 min:1 max:20 value:[self setting:@"BeatSensitivity" fallback:6 min:1 max:20] name:@"Beat sensitivity" in:view];
    _values = [self label:@"" y:233 height:20]; _values.textColor = NSColor.secondaryLabelColor; [view addSubview:_values];
    _meter = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(26, 206, 336, 10)];
    _meter.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity; _meter.minValue = 0; _meter.maxValue = 1;
    _meter.warningValue = 1; _meter.criticalValue = 1; _meter.editable = NO; _meter.accessibilityLabel = @"Requested light level"; [view addSubview:_meter];
    NSTextField *preview = [self label:@"Effect preview · requested level, not measured light" y:182 height:20];
    preview.font = [NSFont systemFontOfSize:10]; preview.textColor = NSColor.secondaryLabelColor; [view addSubview:preview];
    _login = [NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];
    _login.frame = NSMakeRect(24, 147, 194, 24); [view addSubview:_login];
    _loginSettings = [NSButton buttonWithTitle:@"Login Settings…" target:self action:@selector(loginSettings:)];
    _loginSettings.frame = NSMakeRect(230, 147, 134, 24); _loginSettings.bezelStyle = NSBezelStyleInline; [view addSubview:_loginSettings];
    _loginHint = [self label:@"" y:124 height:20]; _loginHint.font = [NSFont systemFontOfSize:10]; _loginHint.textColor = NSColor.secondaryLabelColor; [view addSubview:_loginHint];
    [self refreshLogin];
    _state = [self label:_hardware.detail y:77 height:43]; _state.font = [NSFont systemFontOfSize:11]; [view addSubview:_state];
    NSButton *off = [NSButton buttonWithTitle:@"Off" target:self action:@selector(off:)];
    off.frame = NSMakeRect(24, 24, 74, 32); off.enabled = _hardware.available; [view addSubview:off];
    NSButton *restore = [NSButton buttonWithTitle:@"Restore" target:self action:@selector(system:)];
    restore.frame = NSMakeRect(110, 24, 94, 32); restore.enabled = _hardware.available; [view addSubview:restore];
    NSButton *quit = [NSButton buttonWithTitle:@"Restore & Quit" target:NSApp action:@selector(terminate:)];
    quit.frame = NSMakeRect(218, 24, 146, 32); [view addSubview:quit];
    _popover = [NSPopover new]; _popover.contentViewController = controller; _popover.behavior = NSPopoverBehaviorTransient;
    _timer = [NSTimer timerWithTimeInterval:1.0/30 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(suspend:) name:@"com.apple.screenIsLocked" object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(resume:) name:@"com.apple.screenIsUnlocked" object:nil];
    if (_hardware.hasRecovery) {
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [NSAlert new]; alert.messageText = @"An unfinished restore was found";
        alert.informativeText = @"LidGlow may not have quit normally. Effects remain off until the saved original settings are restored. Restore them now?";
        [alert addButtonWithTitle:@"Restore"]; [alert addButtonWithTitle:@"Not Now"];
        if ([alert runModal] == NSAlertFirstButtonReturn) [self restore];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--debug-window"]) {
        _debugWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 388, 620) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        _debugWindow.title = @"LidGlow"; _debugWindow.releasedWhenClosed = NO;
        _popover.contentViewController = nil; _debugWindow.contentViewController = controller; [_debugWindow center];
    }
    // Never restore a saved lighting mode: every normal launch starts with Breathe.
    if (_hardware.available && !_hardware.hasRecovery) { [_modePicker selectItemAtIndex:LGBreathe]; [self changeMode:nil]; }
    else [self tune:nil];
    [self performSelector:@selector(show:) withObject:nil afterDelay:0];
}
- (void)refreshLogin {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    _login.state = (status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval) ? NSControlStateValueOn : NSControlStateValueOff;
    _loginSettings.hidden = status != SMAppServiceStatusRequiresApproval;
    _loginHint.stringValue = status == SMAppServiceStatusEnabled ? @"LidGlow will open in Breathe mode when you sign in." : status == SMAppServiceStatusRequiresApproval ? @"Allow LidGlow in System Settings to finish enabling this." : @"Off until you enable it. Applies to this app at its current location.";
}
- (void)toggleLogin:(id)sender {
    (void)sender; SMAppService *service = SMAppService.mainAppService; NSError *error = nil;
    BOOL requested = _login.state != NSControlStateValueOff;
    if (service.status == SMAppServiceStatusRequiresApproval && requested) { [self loginSettings:nil]; [self refreshLogin]; return; }
    BOOL ok = requested ? [service registerAndReturnError:&error] : [service unregisterAndReturnError:&error];
    [self refreshLogin];
    if (!ok) [self alert:[NSString stringWithFormat:@"Launch at login could not be changed. %@", error.localizedDescription ?: @"Check Login Items in System Settings."]];
}
- (void)loginSettings:(id)sender { (void)sender; [SMAppService openSystemSettingsLoginItems]; }
- (void)show:(id)sender {
    (void)sender; [self refreshLogin];
    if (_debugWindow) { [NSApp activateIgnoringOtherApps:YES]; [_debugWindow makeKeyAndOrderFront:nil]; return; }
    if (_popover.shown) { [_popover close]; return; }
    [NSApp activateIgnoringOtherApps:YES]; [_popover showRelativeToRect:_item.button.bounds ofView:_item.button preferredEdge:NSRectEdgeMinY];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender; (void)flag; if (!_popover.shown) [self show:nil]; return YES;
}
- (void)tune:(id)sender {
    if (sender) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setDouble:_brightness.doubleValue forKey:@"MaximumBrightness"];
        [defaults setDouble:_period.doubleValue forKey:@"BreathingPeriod"];
        [defaults setDouble:_gain.doubleValue forKey:@"BeatSensitivity"];
    }
    _values.stringValue = [NSString stringWithFormat:@"Max %.0f%%   ·   %.1f s   ·   Sensitivity %.1f", _brightness.doubleValue * 100, _period.doubleValue, _gain.doubleValue];
    _modePicker.enabled = _hardware.available && !_suspended;
    _brightness.enabled = _hardware.available && !_suspended;
    _period.enabled = _hardware.available && !_suspended && (_mode == LGBreathe || _mode == LGAdaptive);
    _gain.enabled = _hardware.available && !_suspended && (_mode == LGMusic || _mode == LGAdaptive || _pendingAudio);
}
- (void)off:(id)sender { (void)sender; [_modePicker selectItemAtIndex:LGOff]; [self changeMode:nil]; }
- (void)system:(id)sender { (void)sender; [_modePicker selectItemAtIndex:LGSystem]; [self changeMode:nil]; }
- (BOOL)restore {
    NSError *error = nil; BOOL ok = [_hardware restore:&error];
    _state.stringValue = ok ? @"Original settings restored. The system controls the light." : error.localizedDescription;
    if (!ok) [self alert:error.localizedDescription]; return ok;
}
- (void)changeMode:(id)sender {
    (void)sender;
    if (_suspended) {
        // Explicit Off/Restore requests during suspension supersede the saved mode.
        _lifecycle.mode = (int)_modePicker.indexOfSelectedItem;
        return;
    }
    ++_selection; NSUInteger selection = _selection;
    [_audio stop]; _pendingAudio = NO; _autoMusic = NO; _autoBlend = 0;
    _mode = LGSystem; _lastWritten = -1; _meter.doubleValue = 0;
    LGMode desired = _modePicker.indexOfSelectedItem;
    if (desired == LGSystem) { _live.stringValue = @"System control"; [self restore]; [self tune:nil]; return; }
    if (!_hardware.available || _hardware.hasRecovery) { [_modePicker selectItemAtIndex:LGSystem]; [self restore]; [self tune:nil]; return; }
    _started = _lastTick = CACurrentMediaTime();
    if (desired == LGMusic || desired == LGAdaptive) {
        if (![self restore]) { [_modePicker selectItemAtIndex:LGSystem]; [self tune:nil]; return; }
        if (!_audioDisclosureAccepted) {
            NSAlert *alert = [NSAlert new]; alert.messageText = @"Use system audio for music lighting?";
            alert.informativeText = @"macOS may ask for Screen & System Audio Recording permission. LidGlow receives only output audio, never the microphone or screen frames. It does not save or upload audio. Auto mode keeps listening for sound while the light breathes. Protected content may be unavailable. Follow macOS instructions if permission or a restart is needed.";
            [alert addButtonWithTitle:@"Continue"]; [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] != NSAlertFirstButtonReturn) { [_modePicker selectItemAtIndex:LGBreathe]; [self changeMode:nil]; return; }
            _audioDisclosureAccepted = YES;
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"AudioDisclosureAccepted"];
        }
        if (selection != _selection) return;
        _pendingAudio = YES; _live.stringValue = @"Starting system audio…"; _state.stringValue = @"Waiting for macOS audio capture. No microphone is used."; [self tune:nil];
        __weak LGApp *weakSelf = self;
        [_audio startWithCompletion:^(NSError *error) {
            LGApp *strongSelf = weakSelf; if (!strongSelf || selection != strongSelf->_selection) return;
            strongSelf->_pendingAudio = NO;
            if (error) { [strongSelf audioFailed:error.localizedDescription]; return; }
            strongSelf->_mode = desired; strongSelf->_lastTick = CACurrentMediaTime();
            strongSelf->_state.stringValue = desired == LGAdaptive ? @"Auto: breathes in silence, follows beats when sound returns." : @"Music follows beats with adaptive contrast. Silence keeps a dim glow.";
            [strongSelf tune:nil]; [strongSelf tick:nil];
        }];
    } else {
        _mode = desired;
        _state.stringValue = @"Experimental hardware control. System brightness limits still apply.";
        [self tune:nil]; [self tick:nil];
    }
}
- (void)tick:(id)sender {
    (void)sender;
    if (_mode == LGSystem || _pendingAudio || _suspended) return;
    double now = CACurrentMediaTime(), dt = fmax(0, fmin(.25, now - _lastTick)); _lastTick = now;
    double value = 0, minimum = 0, maximum = 1; NSString *name = @"Off";
    BOOL musicEffect = _mode == LGMusic || _mode == LGAdaptive;
    if (_mode == LGManual) { value = _brightness.doubleValue; name = @"Manual"; }
    else if (_mode == LGBreathe) { value = lg_breathe(now - _started, _period.doubleValue) * _brightness.doubleValue; name = @"Breathe"; }
    else if (musicEffect) {
        LGAudioSignal signal = [_audio signalForSensitivity:_gain.doubleValue];
        if (_mode == LGAdaptive) {
            _autoMusic = signal.active;
            double target = _autoMusic ? 1 : 0;
            _autoBlend += (target - _autoBlend) * (1 - exp(-dt / (_autoMusic ? .045 : .35)));
            value = (1 - _autoBlend) * lg_breathe(now - _started, _period.doubleValue) + _autoBlend * signal.level;
            name = _autoMusic ? @"Auto · Music" : @"Auto · Breathe";
        } else { value = signal.level; name = @"Music"; }
        // Apply one floor after the Auto crossfade, including silence/beat troughs.
        // It scales with the user's maximum and never changes Breathe or Off.
        maximum = lg_clamp(_brightness.doubleValue);
        minimum = lg_music_light_level(0, maximum);
        value = lg_music_light_level(value, maximum);
    }
    value = lg_clamp(value);
    if (now - _lastPreview > .12) {
        _lastPreview = now; _meter.doubleValue = value;
        NSString *percentage = musicEffect && value > 0 && value < .01 ? @"<1%" :
            [NSString stringWithFormat:@"%.0f%%", value * 100];
        _live.stringValue = [NSString stringWithFormat:@"%@   ·   Requested %@", name, percentage];
    }
    // Keep the music write deadband relative to the selected maximum, so even a
    // very low cap retains contrast. A changed cap/floor must also apply at once.
    BOOL shouldWrite = musicEffect && maximum > 0 ?
        lg_should_write(_lastWritten / maximum, value / maximum) : lg_should_write(_lastWritten, value);
    if (!shouldWrite && _lastWritten >= minimum && _lastWritten <= maximum) return;
    NSError *error = nil;
    if (![_hardware setLevel:value error:&error]) { [self effectFailed:error.localizedDescription]; return; }
    _lastWritten = value;
}
- (void)audioFailed:(NSString *)message {
    if (_suspended) return;
    // ScreenCaptureKit may stop just before macOS posts sleep/lock notifications.
    // Stop immediately, but give those notifications one brief settling window
    // before converting the user's selection into a permanent error stop.
    NSUInteger selection = ++_selection;
    _mode = LGSystem; _pendingAudio = NO; [_audio stop]; _meter.doubleValue = 0;
    __weak LGApp *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LGApp *app = weakSelf;
        if (!app || app->_suspended || app->_selection != selection) return;
        [app effectFailed:message];
    });
}
- (void)effectFailed:(NSString *)message {
    ++_selection; _mode = LGSystem; _pendingAudio = NO; [_audio stop]; _meter.doubleValue = 0;
    [_modePicker selectItemAtIndex:LGSystem]; _live.stringValue = @"Effect stopped";
    NSError *restoreError = nil; BOOL restored = [_hardware restore:&restoreError];
    NSString *detail = [NSString stringWithFormat:@"%@\n%@", message, restored ? @"Effects stopped. Original settings restored." : restoreError.localizedDescription];
    _state.stringValue = detail; [self tune:nil]; [self alert:detail];
}
- (void)alert:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES]; NSAlert *alert = [NSAlert new];
    alert.messageText = @"LidGlow"; alert.informativeText = message ?: @"An unknown error occurred."; [alert addButtonWithTitle:@"OK"]; [alert runModal];
}
- (void)suspend:(NSNotification *)note {
    LGSuspendReason reason = [note.name isEqualToString:NSWorkspaceWillSleepNotification] ? LGSuspendSystem :
        [note.name isEqualToString:@"com.apple.screenIsLocked"] ? LGSuspendLock : LGSuspendDisplay;
    lg_lifecycle_suspend(&_lifecycle, reason, (int)_modePicker.indexOfSelectedItem);
    ++_selection; _mode = LGSystem; _pendingAudio = NO; [_audio stop];
    _suspended = YES; _meter.doubleValue = 0; _live.stringValue = @"Paused";
    _state.stringValue = @"Your mode and settings are kept. Effects resume after wake and unlock."; [self tune:nil];
}
- (void)resume:(NSNotification *)note {
    LGSuspendReason reason = [note.name isEqualToString:NSWorkspaceDidWakeNotification] ? LGSuspendSystem :
        [note.name isEqualToString:@"com.apple.screenIsUnlocked"] ? LGSuspendLock : LGSuspendDisplay;
    if (!lg_lifecycle_resume(&_lifecycle, reason)) return;
    _suspended = NO;
    LGMode saved = _lifecycle.mode >= LGSystem && _lifecycle.mode <= LGAdaptive ? (LGMode)_lifecycle.mode : LGSystem;
    _lifecycle.mode = LGSystem;
    // Restore the pre-sleep ownership session before safely reacquiring control.
    if (![self restore]) {
        [_modePicker selectItemAtIndex:LGSystem]; _live.stringValue = @"Resume stopped"; [self tune:nil]; return;
    }
    [_modePicker selectItemAtIndex:saved];
    [self changeMode:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender; ++_selection; _mode = LGSystem; _pendingAudio = NO; [_audio stop];
    [_modePicker selectItemAtIndex:LGSystem];
    if (_suspended) return NSTerminateNow;
    for (;;) {
        NSError *error = nil; if ([_hardware restore:&error]) return NSTerminateNow;
        NSAlert *alert = [NSAlert new]; alert.messageText = @"Original settings have not been restored";
        alert.informativeText = [NSString stringWithFormat:@"%@\nQuitting may leave the light at its last level. The recovery file will be kept for the next launch.", error.localizedDescription];
        [alert addButtonWithTitle:@"Retry Restore"]; [alert addButtonWithTitle:@"Cancel Quit"]; [alert addButtonWithTitle:@"Quit & Keep Recovery"];
        NSModalResponse choice = [alert runModal];
        if (choice == NSAlertSecondButtonReturn) return NSTerminateCancel;
        if (choice == NSAlertThirdButtonReturn) return NSTerminateNow;
    }
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        BOOL debugWindow = [NSProcessInfo.processInfo.arguments containsObject:@"--debug-window"];
        [app setActivationPolicy:debugWindow ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) LGApp *delegate = [LGApp new]; app.delegate = delegate; [app run];
    }
    return 0;
}
