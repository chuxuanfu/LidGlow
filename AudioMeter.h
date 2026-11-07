#import <Foundation/Foundation.h>

typedef struct {
    double level;
    double rms;
    BOOL active;
} LGAudioSignal;

@interface LGAudioMeter : NSObject
@property(nonatomic, copy) void (^onError)(NSString *message);
- (void)startWithCompletion:(void (^)(NSError *error))completion;
- (void)stop;
- (double)recentRMS;
/* Main/UI may read at any rate. level is already smoothed and normalized.
   active includes 0.70-second silence hysteresis for automatic mode. */
- (LGAudioSignal)signalForSensitivity:(double)sensitivity;
@end
