#include "Signal.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void unit(double x) { assert(isfinite(x) && x >= 0 && x <= 1); }
static void legacy_checks(void) {
    assert(lg_breathe(0, 4) == 0);
    assert(fabs(lg_breathe(2, 4) - 1) < 1e-12);
    assert(lg_breathe(4, 4) == 0);
    assert(lg_breathe(INFINITY, 4) == 0);
    assert(lg_breathe(1, NAN) == 0);
    assert(lg_breathe(-1, 4) == 0);
    assert(lg_breathe(1, 0) == 0);
    assert(lg_clamp(NAN) == 0 && lg_clamp(INFINITY) == 0);
    assert(lg_clamp(-1) == 0 && lg_clamp(2) == 1);
    assert(lg_audio_target(.002, 6) == 0);
    assert(lg_audio_target(NAN, 6) == 0);
    assert(lg_audio_target(1, INFINITY) == 0);
    assert(lg_envelope(.5, 1, 0) == .5);
    assert(lg_envelope(.5, 1, NAN) == .5);
    assert(lg_should_write(-1, 0));
    assert(!lg_should_write(0, 0));
    assert(lg_should_write(.0020537446688473056, 0));
    assert(!lg_should_write(.2, .201));
    assert(lg_should_write(.2, .21));
    double last = .0020537446688473056;
    if (lg_should_write(last, 0)) last = 0;
    assert(last == 0); // Regression: music silence must not leave a dim residual.
    srand(42);
    for (int i = 0; i < 100000; ++i) {
        double a = (double)rand() / RAND_MAX, b = (double)rand() / RAND_MAX;
        double dt = (double)rand() / RAND_MAX;
        double v = lg_envelope(a, b, dt);
        unit(v); assert(v >= fmin(a, b) - 1e-12 && v <= fmax(a, b) + 1e-12);
        unit(lg_breathe(a * 1e9, .5 + b * 10));
        unit(lg_audio_target(a * 10, b * 30));
    }
    double e = 1;
    for (int i = 0; i < 100; ++i) e = lg_envelope(e, 0, .05);
    assert(e < 1e-7);
    puts("PASS: signal edge cases and 300,000 randomized invariant checks");
}


#define SAMPLE_RATE 48000
#define TAU 6.2831853071795864769

typedef struct {
    double min, max, sum;
    unsigned count;
} Stats;
static void observe(Stats *s, double value) {
    unit(value);
    s->min = fmin(s->min, value);
    s->max = fmax(s->max, value);
    s->sum += value;
    ++s->count;
}
static double sample_at(double time, double amplitude, double frequency, int beats) {
    double phase = fmod(time, .5);
    double envelope = beats ? .025 + (phase < .16 ? exp(-phase / .038) : 0) : 1;
    return amplitude * envelope * (beats ? .75 * sin(TAU * 62 * time) + .25 * sin(TAU * 620 * time) : sin(TAU * frequency * time));
}
/* Deterministic audio/UI event simulation. Audio callbacks and 30 Hz reads are
   independent, including callbacks shorter than a 5 ms feature window. */
static LGMusicState simulate(double sensitivity, double amplitude, double frequency,
                             int beats, int uneven, Stats *peaks, Stats *valleys,
                             Stats *steady) {
    LGMusicState s;
    lg_music_reset(&s);
    lg_music_set_sensitivity(&s, sensitivity);
    const unsigned blocks[] = {48, 177, 960, 63, 512, 240, 17, 701, 401};
    unsigned block_index = 0;
    size_t frame = 0, total = SAMPLE_RATE * 6;
    double last_callback = 0, next_ui = 0;
    while (frame < total) {
        size_t block = uneven ? blocks[block_index++ % (sizeof(blocks) / sizeof(blocks[0]))] : 480;
        if (block > total - frame) block = total - frame;
        double callback_time = (frame + block) / (double)SAMPLE_RATE;
        while (next_ui < callback_time) {
            LGMusicOutput output = lg_music_read(&s, next_ui - last_callback);
            unit(output.level);
            if (next_ui >= 2) {
                double phase = fmod(next_ui, .5);
                if (peaks && phase < .12) observe(peaks, output.level);
                if (valleys && phase > .30 && phase < .49) observe(valleys, output.level);
                if (steady) observe(steady, output.level);
            }
            next_ui += 1.0 / 30;
        }
        for (size_t i = 0; i < block; ++i) {
            double t = (frame + i) / (double)SAMPLE_RATE;
            double v = sample_at(t, amplitude, frequency, beats);
            double channels[] = {v, -v}; // Opposite phase must not cancel bass.
            lg_music_push_frame(&s, channels, 2, SAMPLE_RATE);
        }
        lg_music_finish_buffer(&s);
        frame += block;
        last_callback = callback_time;
    }
    return s;
}
static void beat_checks(void) {
    for (int gain = 1; gain <= 20; ++gain) {
        for (int uneven = 0; uneven <= 1; ++uneven) {
            double averages[2];
            for (int volume = 0; volume < 2; ++volume) {
                Stats peaks = {1, 0, 0, 0}, valleys = {1, 0, 0, 0}, all = {1, 0, 0, 0};
                double amplitude = volume ? .65 : .001;
                LGMusicState s = simulate(gain, amplitude, 0, 1, uneven, &peaks, &valleys, &all);
                fprintf(stderr, "Beat sensitivity=%2d amplitude=%.3f uneven=%d: peak=%.3f valley=%.3f onsets=%llu\n",
                        gain, amplitude, uneven, peaks.max, valleys.max, (unsigned long long)s.onset_count);
                assert(peaks.count && valleys.count);
                assert(peaks.max >= .82);
                assert(valleys.max <= .20);
                assert(peaks.max - valleys.max >= .65);
                assert(s.onset_count >= 10 && s.onset_count <= 16);
                assert(s.active);
                averages[volume] = all.sum / all.count;
            }
            assert(fabs(averages[0] - averages[1]) < .10);
        }
    }
    puts("PASS: strong beat contrast at all 20 sensitivity levels, quiet/loud audio, uneven callbacks, opposite-phase stereo");
}
static void steady_checks(void) {
    const double frequencies[] = {40, 80, 440, 6000};
    for (int gain = 1; gain <= 20; gain += (gain == 1 ? 5 : 14)) {
        for (size_t f = 0; f < sizeof(frequencies) / sizeof(frequencies[0]); ++f) {
            Stats steady = {1, 0, 0, 0};
            LGMusicState s = simulate(gain, .3, frequencies[f], 0, 1, NULL, NULL, &steady);
            fprintf(stderr, "Steady %.0f Hz sensitivity=%d: max=%.3f mean=%.3f onsets=%llu\n",
                    frequencies[f], gain, steady.max, steady.sum / steady.count, (unsigned long long)s.onset_count);
            assert(s.active);
            assert(steady.max < .20);
            assert(s.onset_count <= 3);
        }
    }
    puts("PASS: sustained bass/mid/treble tones do not repeatedly trigger or saturate");
}
static void silence_and_transient_checks(void) {
    LGMusicState s;
    lg_music_reset(&s);
    LGMusicOutput o = lg_music_read(&s, 0);
    assert(!o.active && !o.level && !o.rms);
    for (int i = 0; i < SAMPLE_RATE; ++i) {
        double zeros[] = {0, 0};
        lg_music_push_frame(&s, zeros, 2, SAMPLE_RATE);
    }
    lg_music_finish_buffer(&s);
    assert(!lg_music_read(&s, 0).active);
    // Even a one-frame final buffer must be detected, not discarded.
    double click[] = {.5, -.5};
    lg_music_push_frame(&s, click, 2, SAMPLE_RATE);
    lg_music_finish_buffer(&s);
    o = lg_music_read(&s, 0);
    assert(o.active && o.level == 1 && o.rms == .5);
    assert(lg_music_read(&s, 1.0 / 30).level > .85);
    assert(lg_music_read(&s, .31).level == 0);
    assert(!lg_music_read(&s, .71).active);
    assert(!lg_music_read(&s, INFINITY).active);
    assert(!lg_music_read(&s, NAN).active);
    // Reads are observations, not extra release steps.
    assert(lg_music_read(&s, .05).level == lg_music_read(&s, .05).level);
    for (int i = 0; i < SAMPLE_RATE * .80; ++i) {
        double zeros[] = {0, 0};
        lg_music_push_frame(&s, zeros, 2, SAMPLE_RATE);
        if (i == SAMPLE_RATE / 2) assert(lg_music_read(&s, 0).active);
    }
    lg_music_finish_buffer(&s);
    o = lg_music_read(&s, 0);
    assert(!o.active && o.level == 0);
    lg_music_push_frame(&s, click, 2, SAMPLE_RATE);
    lg_music_finish_buffer(&s);
    assert(lg_music_read(&s, 0).active && lg_music_read(&s, 0).level == 1);
    lg_music_reset(&s);
    assert(!lg_music_read(&s, 0).active && lg_music_read(&s, 0).level == 0);
    puts("PASS: digital silence, activity hysteresis, short transients, restart and stale-data rejection");
}
static void input_checks(void) {
    LGMusicState s;
    lg_music_reset(&s);
    double values[LG_MUSIC_MAX_CHANNELS] = {NAN, INFINITY, -INFINITY, 0, 1, -1, .3, -.3};
    lg_music_push_frame(NULL, values, 2, SAMPLE_RATE);
    lg_music_push_frame(&s, NULL, 2, SAMPLE_RATE);
    lg_music_push_frame(&s, values, 0, SAMPLE_RATE);
    lg_music_push_frame(&s, values, LG_MUSIC_MAX_CHANNELS + 1, SAMPLE_RATE);
    lg_music_push_frame(&s, values, 2, NAN);
    lg_music_push_frame(&s, values, 2, 1);
    assert(!s.window_frames);
    lg_music_set_sensitivity(&s, NAN); assert(s.sensitivity == 6);
    lg_music_set_sensitivity(&s, -100); assert(s.sensitivity == 1);
    lg_music_set_sensitivity(&s, 100); assert(s.sensitivity == 20);
    const double rates[] = {8000, 44100, 48000, 96000, 192000};
    srand(91);
    for (int i = 0; i < 300000; ++i) {
        for (unsigned c = 0; c < LG_MUSIC_MAX_CHANNELS; ++c) {
            values[c] = (i % 127 == 0) ? NAN : ((double)rand() / RAND_MAX - .5) * 3;
        }
        unsigned channels = i % LG_MUSIC_MAX_CHANNELS + 1;
        lg_music_push_frame(&s, values, channels, rates[(i / 997) % 5]);
        if (i % 113 == 0) {
            lg_music_finish_buffer(&s);
            lg_music_set_sensitivity(&s, (double)(rand() % 21));
            LGMusicOutput o = lg_music_read(&s, (rand() % 100) / 100.0);
            unit(o.level); unit(o.rms);
        }
    }
    lg_music_finish_buffer(&s);
    unit(lg_music_read(&s, 0).level);
    puts("PASS: invalid PCM, nonfinite values, sample-rate/channel changes and randomized detector invariants");
}

static uint64_t weak_accent_count(double sensitivity, double depth) {
    LGMusicState s;
    lg_music_reset(&s);
    lg_music_set_sensitivity(&s, sensitivity);
    uint64_t warmup = 0;
    for (int frame = 0; frame < SAMPLE_RATE * 6; ++frame) {
        double time = frame / (double)SAMPLE_RATE;
        double phase = fmod(time, .5);
        double value = .15 * (1 + depth * exp(-phase / .050)) * sin(TAU * 440 * time);
        double channels[] = {value, -value};
        lg_music_push_frame(&s, channels, 2, SAMPLE_RATE);
        if (frame % 257 == 0) lg_music_finish_buffer(&s);
        if (frame == SAMPLE_RATE * 2) warmup = s.onset_count;
    }
    lg_music_finish_buffer(&s);
    return s.onset_count - warmup;
}
static void sensitivity_accent_checks(void) {
    const double depths[] = {.15, .25, .35, .45, .60};
    int meaningful_difference = 0;
    for (size_t i = 0; i < sizeof(depths) / sizeof(depths[0]); ++i) {
        uint64_t low = weak_accent_count(1, depths[i]);
        uint64_t high = weak_accent_count(20, depths[i]);
        fprintf(stderr, "Weak accent depth=%.2f: sensitivity 1 onsets=%llu, sensitivity 20 onsets=%llu\n",
                depths[i], (unsigned long long)low, (unsigned long long)high);
        assert(high >= low);
        if (high >= low + 4) meaningful_difference = 1;
    }
    assert(meaningful_difference);
    puts("PASS: maximum sensitivity detects weak accents that minimum sensitivity rejects");
}

int main(void) {
    legacy_checks();
    beat_checks();
    steady_checks();
    sensitivity_accent_checks();
    silence_and_transient_checks();
    input_checks();
    puts("PASS: all adaptive music tests");
    return 0;
}
