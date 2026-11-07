#include "Signal.h"
#include <math.h>
#include <string.h>

double lg_clamp(double x) { return !isfinite(x) || x < 0 ? 0 : x > 1 ? 1 : x; }
double lg_breathe(double elapsed, double period) {
    if (!isfinite(elapsed) || !isfinite(period) || period < .5 || elapsed < 0) return 0;
    double phase = fmod(elapsed, period) / period;
    return lg_clamp((1 - cos(6.2831853071795864769 * phase)) * .5);
}
double lg_envelope(double previous, double target, double dt) {
    previous = lg_clamp(previous); target = lg_clamp(target);
    if (!isfinite(dt) || dt <= 0) return previous;
    double tau = target > previous ? .035 : .28;
    return lg_clamp(previous + (target - previous) * (1 - exp(-fmin(dt, 1) / tau)));
}
/* Compatibility only. Music mode uses LGMusicState, not absolute RMS gain. */
double lg_audio_target(double rms, double gain) {
    if (!isfinite(rms) || !isfinite(gain) || rms <= .002 || gain <= 0) return 0;
    return lg_clamp(sqrt(fmax(0, rms - .002) * fmin(gain, 20)));
}
int lg_should_write(double previous, double value) {
    if (!isfinite(previous) || previous < 0) return 1;
    if (value == 0 && previous != 0) return 1;
    return !isfinite(value) || fabs(value - previous) >= .005;
}

static double follow(double previous, double value, double dt, double tau) {
    return previous + (value - previous) * -expm1(-dt / tau);
}
void lg_music_reset(LGMusicState *state) {
    if (!state) return;
    memset(state, 0, sizeof(*state));
    state->sensitivity = 6;
    state->refractory = 1;
    state->armed = 1;
}
void lg_music_set_sensitivity(LGMusicState *state, double sensitivity) {
    if (!state) return;
    state->sensitivity = isfinite(sensitivity) ? fmax(1, fmin(20, sensitivity)) : 6;
}

static void music_window(LGMusicState *s, double rms, double bass, double peak, double dt) {
    const double sound_floor = .00004; /* Below typical audible digital output. */
    s->rms = rms;
    if (rms >= sound_floor || peak >= .00015) {
        s->active = 1;
        s->silence_seconds = 0;
    } else {
        s->silence_seconds += dt;
        if (s->silence_seconds >= .70) s->active = 0;
    }

    double old_energy = s->fast_energy, old_bass = s->fast_bass;
    s->fast_energy = follow(old_energy, rms, dt, .018);
    s->fast_bass = follow(old_bass, bass, dt, .026);
    s->refractory += dt;
    int onset = 0;
    if (!s->initialized && s->active && rms >= sound_floor) {
        s->initialized = 1;
        s->slow_energy = fmax(rms, sound_floor);
        s->slow_bass = fmax(bass, sound_floor * .25);
        s->floor_energy = s->fast_energy * .55;
        s->ceiling_energy = s->fast_energy;
        onset = 1;
    } else if (s->initialized) {
        double energy_base = fmax(s->slow_energy, sound_floor);
        double bass_base = fmax(s->slow_bass, sound_floor * .25);
        double novelty = fmax(s->fast_energy / energy_base - 1,
                             .90 * (s->fast_bass / bass_base - 1));
        double rise = fmax((s->fast_energy - old_energy) / energy_base,
                          .90 * (s->fast_bass - old_bass) / bass_base);
        double sensitivity = (s->sensitivity - 1) / 19;
        /* Sensitivity changes which accents qualify, never an absolute gain.
           Every accepted beat has the same full-scale, non-saturating pulse. */
        double threshold = .34 - .19 * sensitivity;
        if (novelty < threshold * .40) s->armed = 1;
        if (s->active && s->armed && s->refractory >= .115 &&
            novelty > threshold && rise > .003 * dt / .005) onset = 1;
        s->slow_energy = follow(s->slow_energy, rms, dt, .40);
        s->slow_bass = follow(s->slow_bass, bass, dt, .46);
    }

    s->floor_energy = follow(s->floor_energy, s->fast_energy, dt,
                            s->fast_energy < s->floor_energy ? .035 : 1.10);
    s->ceiling_energy = follow(s->ceiling_energy, s->fast_energy, dt,
                              s->fast_energy > s->ceiling_energy ? .006 : .95);
    double span = fmax(s->ceiling_energy - s->floor_energy,
                       fmax(s->ceiling_energy * .30, sound_floor));
    double dynamic = lg_clamp((s->fast_energy - s->floor_energy) / span);
    /* The quiet body is deliberately capped: compressed/loud music cannot
       pin the light at full brightness, even at maximum sensitivity. */
    double body = rms >= sound_floor ? .16 * dynamic * dynamic : 0;
    if (onset) {
        s->pulse = 1;
        s->pulse_hold = .020;
        s->refractory = 0;
        s->armed = 0;
        ++s->onset_count;
    } else {
        double release_dt = fmax(0, dt - s->pulse_hold);
        s->pulse_hold = fmax(0, s->pulse_hold - dt);
        s->pulse *= exp(-release_dt / .095);
    }
    s->level = lg_clamp(fmax(s->pulse, body));
    if (s->level < .001) s->level = 0;
    if (!s->active && s->silence_seconds >= .70) {
        s->initialized = 0;
        s->armed = 1;
        s->level = s->pulse = s->pulse_hold = 0;
    }
}

void lg_music_finish_buffer(LGMusicState *s) {
    if (!s || !s->window_frames || !s->channels || s->sample_rate <= 0) return;
    double count = (double)s->window_frames * s->channels;
    music_window(s, sqrt(fmax(0, s->energy_sum / count)),
                 sqrt(fmax(0, s->bass_sum / count)), s->window_peak,
                 s->window_frames / s->sample_rate);
    s->energy_sum = s->bass_sum = s->window_peak = 0;
    s->window_frames = 0;
}
void lg_music_push_frame(LGMusicState *s, const double *samples,
                         unsigned channels, double sample_rate) {
    if (!s || !samples || !channels || channels > LG_MUSIC_MAX_CHANNELS ||
        !isfinite(sample_rate) || sample_rate < 8000 || sample_rate > 384000) return;
    if (s->sample_rate != sample_rate || s->channels != channels) {
        lg_music_finish_buffer(s);
        memset(s->bass_filter, 0, sizeof(s->bass_filter));
        memset(s->dc_filter, 0, sizeof(s->dc_filter));
        s->sample_rate = sample_rate;
        s->channels = channels;
        s->bass_alpha = -expm1(-6.2831853071795864769 * 180 / sample_rate);
        s->dc_alpha = -expm1(-6.2831853071795864769 * 35 / sample_rate);
    }
    for (unsigned c = 0; c < channels; ++c) {
        double v = isfinite(samples[c]) ? fmax(-1, fmin(1, samples[c])) : 0;
        s->bass_filter[c] += s->bass_alpha * (v - s->bass_filter[c]);
        s->dc_filter[c] += s->dc_alpha * (v - s->dc_filter[c]);
        double bass = s->bass_filter[c] - s->dc_filter[c];
        s->energy_sum += v * v;
        s->bass_sum += bass * bass;
        s->window_peak = fmax(s->window_peak, fabs(v));
    }
    ++s->window_frames;
    if (s->window_frames >= (size_t)fmax(1, floor(sample_rate * .005)))
        lg_music_finish_buffer(s);
}
LGMusicOutput lg_music_read(const LGMusicState *s, double seconds_since_sample) {
    LGMusicOutput result = {0, 0, 0};
    if (!s) return result;
    double age = isfinite(seconds_since_sample) ? fmax(0, seconds_since_sample) : INFINITY;
    result.active = s->active && age < .70;
    if (age < .30) {
        result.rms = s->rms;
        result.level = lg_clamp(s->level * exp(-fmax(0, age - s->pulse_hold) / .095));
        if (result.level < .001) result.level = 0;
    }
    return result;
}
