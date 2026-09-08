#include "CirclrCapture.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
struct CirclrCapture { _Atomic bool enabled, interrupted; _Atomic uint32_t inflight, peak; _Atomic uint64_t frames, limit; };
CirclrCapture *circlr_capture_create(void) {
    CirclrCapture *c=calloc(1,sizeof(*c)); if(!c) return NULL;
    atomic_init(&c->enabled,true); atomic_init(&c->interrupted,false); atomic_init(&c->inflight,0); atomic_init(&c->peak,0);
    atomic_init(&c->frames,0); atomic_init(&c->limit,UINT64_MAX); return c;
}
void circlr_capture_destroy(CirclrCapture *c) { free(c); }
void circlr_capture_limit(CirclrCapture *c,uint64_t frames) { atomic_store(&c->limit,frames); }
void circlr_capture_disable(CirclrCapture *c) { atomic_store_explicit(&c->enabled,false,memory_order_release); }
void circlr_capture_interrupt(CirclrCapture *c) { circlr_capture_disable(c); atomic_store(&c->interrupted,true); }
bool circlr_capture_interrupted(CirclrCapture *c) { return atomic_load(&c->interrupted); }
bool circlr_capture_enabled(CirclrCapture *c) { return atomic_load_explicit(&c->enabled,memory_order_acquire); }
uint32_t circlr_capture_enter(CirclrCapture *c,uint32_t requested) {
    atomic_fetch_add_explicit(&c->inflight,1,memory_order_acq_rel);
    uint64_t frames=atomic_load(&c->frames),limit=atomic_load(&c->limit);
    if(!circlr_capture_enabled(c) || frames>=limit || !requested) { atomic_fetch_sub(&c->inflight,1); return 0; }
    return (uint32_t)(limit-frames<requested ? limit-frames:requested);
}
void circlr_capture_leave(CirclrCapture *c,const float *const *channels,uint32_t count,uint32_t frames) {
    float peak=0;
    for(uint32_t ch=0;ch<count;ch++) for(uint32_t i=0;i<frames;i++) {
        float v=fabsf(channels[ch][i]); if(isfinite(v) && v>peak) peak=v;
    }
    uint32_t bits; memcpy(&bits,&peak,sizeof(bits)); uint32_t old=atomic_load(&c->peak);
    while(old<bits && !atomic_compare_exchange_weak(&c->peak,&old,bits)) {}
    atomic_fetch_add(&c->frames,frames); atomic_fetch_sub_explicit(&c->inflight,1,memory_order_release);
}
uint32_t circlr_capture_inflight(CirclrCapture *c) { return atomic_load_explicit(&c->inflight,memory_order_acquire); }
uint64_t circlr_capture_frames(CirclrCapture *c) { return atomic_load(&c->frames); }
bool circlr_capture_at_limit(CirclrCapture *c) { return atomic_load(&c->frames)>=atomic_load(&c->limit); }
float circlr_capture_peak(CirclrCapture *c) { uint32_t bits=atomic_exchange(&c->peak,0); float value; memcpy(&value,&bits,sizeof(value)); return value; }
