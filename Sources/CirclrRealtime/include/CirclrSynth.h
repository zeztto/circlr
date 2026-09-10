#pragma once
#include <stdint.h>
typedef struct CirclrSynth CirclrSynth;
CirclrSynth *circlr_synth_create(int style, double cutoff, double attack, double decay, double sustain, double release, double detune);
CirclrSynth *circlr_synth_create_v2(int style, double cutoff, double attack, double decay, double sustain, double release, double detune, double resonance, double width, double filterEnvelope);
CirclrSynth *circlr_synth_create_v3(int style, double cutoff, double attack, double decay, double sustain, double release, double detune, double resonance, double width, double filterEnvelope, double character, double motion);
void circlr_synth_destroy(CirclrSynth *synth);
// One producer; render is the sole consumer. No allocation or mutex in render.
void circlr_synth_note(CirclrSynth *synth, int pitch, int velocity, int on);
void circlr_synth_render(CirclrSynth *synth, float *left, float *right, uint32_t frames);
// Render-consumer only. cutoffHz contains one base-Hz value per frame; NULL uses patch cutoff.
// Values outside finite 40...20000 fall back to patch cutoff. Voice state is retained.
void circlr_synth_render_cutoff(CirclrSynth *synth, float *left, float *right, const double *cutoffHz, uint32_t frames);
