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

// Synchronous render-owner events: call between render blocks, never concurrently.
// Do not mix these with circlr_synth_note on the same instance. No queue, heap
// allocation, mutex, or unbounded stream table; the existing 64-voice pool is shared.
// streamID and voiceID must be nonzero. The caller uses a fresh stream per source
// occurrence and does not reuse voice identities while an old note-off can arrive.
// pitch: 0...127; velocity: 1...127; semitones: finite -128.27...128.27.
// Return 1 on acceptance, 0 on invalid input without changing state. Note-on also
// rejects an active (streamID, voiceID), including a releasing voice. At capacity,
// note-on uses the legacy oldest-voice stealing policy. Off for a finished/stolen
// voice and bend for an empty stream succeed as no-ops. Bend changes only frequency
// of that stream's active/releasing voices; later note-ons receive their own seed.
int circlr_synth_owned_note_on(CirclrSynth *synth, uint64_t streamID, uint64_t voiceID, int pitch, int velocity, double semitones);
int circlr_synth_owned_note_off(CirclrSynth *synth, uint64_t streamID, uint64_t voiceID);
// Same render-owner/identity rules as owned events above. pedalDown must be 0/1.
// With pedalDown=1, key release defers envelope release; voice pitch/filter/phase
// and ownership remain intact. Already releasing voices cannot be recaptured.
// The old owned_note_off is exactly the pedalDown=0 path.
int circlr_synth_owned_note_off_pedal(CirclrSynth *synth, uint64_t streamID, uint64_t voiceID, int pedalDown);
// Pedal-up (or source-end): release only deferred, no-longer-key-held voices in
// this stream. Held keys and other streams are unchanged. Missing/stolen voices
// and repeated releases succeed as no-ops. Both functions return 0 for invalid
// input before any mutation, 1 otherwise; neither allocates or retains a table.
int circlr_synth_owned_sustain_release(CirclrSynth *synth, uint64_t streamID);
int circlr_synth_owned_pitch_bend(CirclrSynth *synth, uint64_t streamID, double semitones);

// Render-consumer only. Both buffers are optional, one value per sample.
// Resonance is finite 0...0.9; invalid samples fall back to the patch value.
// Engine v2/v3 apply resonance while preserving voice/filter/controller state.
void circlr_synth_render_filter(CirclrSynth *synth, float *left, float *right, const double *cutoffHz, const double *resonance, uint32_t frames);
