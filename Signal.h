#ifndef LG_SIGNAL_H
#define LG_SIGNAL_H
#include <stddef.h>
#include <stdint.h>

double lg_clamp(double x);
double lg_breathe(double elapsed, double period);
double lg_envelope(double previous, double target, double dt);
double lg_audio_target(double rms, double gain);
int lg_should_write(double previous, double value);

/* All detector times are seconds of audio, not callback or UI tick counts.
   Keep one state on the serial capture queue, or protect it with a lock. */
#define LG_MUSIC_MAX_CHANNELS 8
typedef struct {
    double sensitivity;
    double rms, fast_energy, slow_energy, fast_bass, slow_bass;
    double floor_energy, ceiling_energy, pulse, pulse_hold;
    double refractory, silence_seconds, level;
    double sample_rate, bass_alpha, dc_alpha;
    double bass_filter[LG_MUSIC_MAX_CHANNELS];
    double dc_filter[LG_MUSIC_MAX_CHANNELS];
    double energy_sum, bass_sum, window_peak;
    size_t window_frames;
    unsigned channels;
    uint64_t onset_count;
    int initialized, active, armed;
} LGMusicState;

typedef struct {
    double level;    /* Already smoothed 0..1. Multiply only by max brightness. */
    double rms;
    int active;      /* Immediate sound-on; 0.70-second silence-off hysteresis. */
} LGMusicOutput;

void lg_music_reset(LGMusicState *state);
void lg_music_set_sensitivity(LGMusicState *state, double sensitivity); /* 1..20 */
/* Normalized PCM frame, channel values -1..1. No storage/allocation of audio. */
void lg_music_push_frame(LGMusicState *state, const double *samples,
                         unsigned channels, double sample_rate);
/* Flush even a partial 5 ms window, so short final transients are not lost. */
void lg_music_finish_buffer(LGMusicState *state);
/* seconds_since_sample uses a monotonic clock. This function does not advance
   state, so repeated UI reads cannot change the detector's timing. */
LGMusicOutput lg_music_read(const LGMusicState *state, double seconds_since_sample);
#endif
