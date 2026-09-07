#pragma once
#include <stdint.h>
#include <stdbool.h>
typedef struct CirclrRing CirclrRing;
CirclrRing *circlr_ring_create(uint32_t channels, uint32_t frames, uint32_t slots);
void circlr_ring_destroy(CirclrRing *ring);
bool circlr_ring_push(CirclrRing *ring, const float *const *channels, uint32_t frames);
uint32_t circlr_ring_pop(CirclrRing *ring, float *const *channels);
uint32_t circlr_ring_overruns(CirclrRing *ring);
