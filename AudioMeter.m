#import "AudioMeter.h"
#import "Signal.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdint.h>
#import <stdlib.h>

@interface LGAudioMeter () <SCStreamOutput, SCStreamDelegate>
@end
@implementation LGAudioMeter {
    SCStream *_stream;
    SCStream *_acceptedStream;
    dispatch_queue_t _queue;
    NSUInteger _generation;
    LGMusicState _music;
    double _lastSample, _lastOutputCheck;
    BOOL _hasSample, _outputMuted;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("local.lidglow.audio", DISPATCH_QUEUE_SERIAL);
        lg_music_reset(&_music);
    }
    return self;
}
- (void)startWithCompletion:(void (^)(NSError *))completion {
    [self stop];
    NSUInteger generation = _generation;
    // This public API triggers macOS's capture authorization flow when needed.
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            if (error || !content.displays.count) {
                completion(error ?: [NSError errorWithDomain:@"LidGlowAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:@"No display is available for system audio capture."}]); return;
            }
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:content.displays.firstObject excludingWindows:@[]];
            SCStreamConfiguration *config = [SCStreamConfiguration new];
            config.capturesAudio = YES;
            config.excludesCurrentProcessAudio = YES;
            config.sampleRate = 48000;
            config.channelCount = 2;
            // System output only. No microphone, screen frames, recording, or networking.
            config.width = 2; config.height = 2;
            config.minimumFrameInterval = CMTimeMake(1, 1);
            SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            NSError *addError = nil;
            if (![stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:self->_queue error:&addError]) { completion(addError); return; }
            self->_stream = stream;
            @synchronized (self) { self->_acceptedStream = stream; }
            [stream startCaptureWithCompletionHandler:^(NSError *startError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self->_generation) { [stream stopCaptureWithCompletionHandler:^(NSError *e) { (void)e; }]; return; }
                    if (startError) [self stop];
                    completion(startError);
                });
            }];
        });
    }];
}
- (void)stop {
    ++_generation;
    SCStream *stream = _stream; _stream = nil;
    @synchronized (self) {
        _acceptedStream = nil;
        _lastSample = _lastOutputCheck = 0;
        _hasSample = _outputMuted = NO;
        lg_music_reset(&_music);
    }
    if (stream) [stream stopCaptureWithCompletionHandler:^(NSError *error) { (void)error; }];
}
/* Read-only: ScreenCaptureKit can expose pre-volume PCM even while the output
   device is muted. Devices without these properties use PCM silence detection. */
- (BOOL)outputIsMutedAtTime:(double)now {
    if (now - _lastOutputCheck < .20) return _outputMuted;
    _lastOutputCheck = now;
    _outputMuted = NO;
    AudioObjectPropertyAddress address = { kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr || device == kAudioObjectUnknown) return NO;
    address = (AudioObjectPropertyAddress){ kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain };
    UInt32 mute = 0; size = sizeof(mute);
    if (AudioObjectHasProperty(device, &address) &&
        AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &mute) == noErr && mute) {
        _outputMuted = YES; return YES;
    }
    address.mSelector = kAudioDevicePropertyVolumeScalar;
    Float32 volume = 1; size = sizeof(volume);
    if (AudioObjectHasProperty(device, &address) &&
        AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &volume) == noErr) {
        _outputMuted = isfinite(volume) && volume <= .00001f;
        return _outputMuted;
    }
    // Some USB/headphone devices expose only per-channel volume.
    BOOL foundVolume = NO, everyChannelZero = YES;
    for (UInt32 channel = 1; channel <= 8; ++channel) {
        address.mElement = channel;
        volume = 1; size = sizeof(volume);
        if (AudioObjectHasProperty(device, &address) &&
            AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &volume) == noErr) {
            foundVolume = YES;
            if (!isfinite(volume) || volume > .00001f) everyChannelZero = NO;
        }
    }
    _outputMuted = foundVolume && everyChannelZero;
    return _outputMuted;
}
- (LGAudioSignal)signalForSensitivity:(double)sensitivity {
    @synchronized (self) {
        lg_music_set_sensitivity(&_music, sensitivity);
        double now = CACurrentMediaTime();
        LGMusicOutput output = lg_music_read(&_music, _hasSample ? now - _lastSample : INFINITY);
        if ([self outputIsMutedAtTime:now]) output = (LGMusicOutput){0, 0, 0};
        return (LGAudioSignal){output.level, output.rms, output.active ? YES : NO};
    }
}
- (double)recentRMS {
    @synchronized (self) {
        LGMusicOutput output = lg_music_read(&_music, _hasSample ? CACurrentMediaTime() - _lastSample : INFINITY);
        return output.rms;
    }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (stream != self->_stream) return;
        [self stop];
        if (self.onError) self.onError(error.localizedDescription);
    });
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    @synchronized (self) { if (stream != _acceptedStream) return; }
    if (type != SCStreamOutputTypeAudio || !CMSampleBufferIsValid(sample) || !CMSampleBufferDataIsReady(sample)) return;
    CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sample);
    if (!description) return;
    const AudioStreamBasicDescription *format = CMAudioFormatDescriptionGetStreamBasicDescription(description);
    if (!format || format->mFormatID != kAudioFormatLinearPCM || (format->mFormatFlags & kAudioFormatFlagIsBigEndian)) return;
    BOOL floats = (format->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL integers = (format->mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;
    unsigned bits = format->mBitsPerChannel, bytes = bits / 8;
    if (!(format->mFormatFlags & kAudioFormatFlagIsPacked) || !((floats && (bits == 32 || bits == 64)) || (integers && (bits == 16 || bits == 32)))) return;
    if (!isfinite(format->mSampleRate) || format->mSampleRate < 8000 || format->mSampleRate > 384000 || !format->mChannelsPerFrame || format->mChannelsPerFrame > LG_MUSIC_MAX_CHANNELS) return;
    BOOL planar = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (format->mBytesPerFrame != bytes * (planar ? 1 : format->mChannelsPerFrame)) return;
    size_t needed = 0;
    OSStatus result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, &needed, NULL, 0, NULL, NULL, 0, NULL);
    (void)result; // The sizing call can return ArrayTooSmall with the required size.
    if (needed < sizeof(AudioBufferList) || needed > 1024 * 1024) return;
    AudioBufferList *list = malloc(needed);
    if (!list) return;
    CMBlockBufferRef retained = NULL;
    result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, NULL, list, needed, kCFAllocatorDefault, kCFAllocatorDefault, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &retained);
    if (result == noErr && list->mNumberBuffers > 0 && list->mNumberBuffers <= LG_MUSIC_MAX_CHANNELS &&
        offsetof(AudioBufferList, mBuffers) + list->mNumberBuffers * sizeof(AudioBuffer) <= needed) {
        CMItemCount sampleFrames = CMSampleBufferGetNumSamples(sample);
        size_t frames = sampleFrames > 0 ? (size_t)sampleFrames : 0;
        unsigned channels = 0;
        BOOL valid = frames > 0 && frames <= (size_t)(format->mSampleRate * .5);
        for (UInt32 b = 0; b < list->mNumberBuffers && valid; ++b) {
            AudioBuffer buffer = list->mBuffers[b];
            if (!buffer.mData || !buffer.mNumberChannels || buffer.mNumberChannels > LG_MUSIC_MAX_CHANNELS ||
                buffer.mDataByteSize / (bytes * buffer.mNumberChannels) < frames) valid = NO;
            channels += buffer.mNumberChannels;
            if (channels > LG_MUSIC_MAX_CHANNELS) valid = NO;
        }
        if (valid && channels == format->mChannelsPerFrame) {
            @synchronized (self) {
                if (stream == _acceptedStream) {
                    double now = CACurrentMediaTime();
                    // A discontinuity must not replay the previous stream's pulse.
                    if (_hasSample && now - _lastSample > .30) {
                        double sensitivity = _music.sensitivity;
                        lg_music_reset(&_music);
                        lg_music_set_sensitivity(&_music, sensitivity);
                    }
                    for (size_t frame = 0; frame < frames; ++frame) {
                        double values[LG_MUSIC_MAX_CHANNELS];
                        unsigned channel = 0;
                        for (UInt32 b = 0; b < list->mNumberBuffers; ++b) {
                            AudioBuffer buffer = list->mBuffers[b];
                            for (UInt32 c = 0; c < buffer.mNumberChannels; ++c) {
                                size_t i = frame * buffer.mNumberChannels + c;
                                values[channel++] = floats ? (bits == 32 ? ((const float *)buffer.mData)[i] : ((const double *)buffer.mData)[i]) :
                                    (bits == 16 ? ((const int16_t *)buffer.mData)[i] / 32768.0 : ((const int32_t *)buffer.mData)[i] / 2147483648.0);
                            }
                        }
                        // Per-channel bass energy avoids stereo phase cancellation.
                        lg_music_push_frame(&_music, values, channels, format->mSampleRate);
                    }
                    lg_music_finish_buffer(&_music);
                    _lastSample = CACurrentMediaTime();
                    _hasSample = YES;
                }
            }
        }
    }
    if (retained) CFRelease(retained);
    free(list);
}
@end
