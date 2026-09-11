#pragma once
#include <stdbool.h>
#include <stdint.h>
typedef struct CirclrCapture CirclrCapture;
CirclrCapture *circlr_capture_create(void);
void circlr_capture_destroy(CirclrCapture *capture);
void circlr_capture_limit(CirclrCapture *capture, uint64_t frames);
void circlr_capture_disable(CirclrCapture *capture);
void circlr_capture_interrupt(CirclrCapture *capture);
bool circlr_capture_interrupted(CirclrCapture *capture);
bool circlr_capture_enabled(CirclrCapture *capture);
uint32_t circlr_capture_enter(CirclrCapture *capture, uint32_t requested);
void circlr_capture_leave(CirclrCapture *capture, const float *const *channels, uint32_t count, uint32_t frames);
uint32_t circlr_capture_inflight(CirclrCapture *capture);
uint64_t circlr_capture_frames(CirclrCapture *capture);
bool circlr_capture_at_limit(CirclrCapture *capture);
float circlr_capture_peak(CirclrCapture *capture);
