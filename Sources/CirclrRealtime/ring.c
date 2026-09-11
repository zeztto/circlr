#include "CirclrRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
struct CirclrRing { uint32_t channels, frames, slots; _Atomic uint32_t read, write, overruns; uint32_t *lengths; float *data; };
CirclrRing *circlr_ring_create(uint32_t c, uint32_t f, uint32_t s) {
    if (!c || c > 32 || !f || f > 16384 || s < 2 || s > 256) return NULL;
    CirclrRing *r = calloc(1, sizeof(*r)); if (!r) return NULL;
    r->channels=c; r->frames=f; r->slots=s; r->lengths=calloc(s,sizeof(uint32_t)); r->data=calloc((size_t)c*f*s,sizeof(float));
    if (!r->data || !r->lengths) { circlr_ring_destroy(r); return NULL; }
    atomic_init(&r->read,0); atomic_init(&r->write,0); atomic_init(&r->overruns,0); return r;
}
void circlr_ring_destroy(CirclrRing *r) { if(r) { free(r->data); free(r->lengths); free(r); } }
bool circlr_ring_push(CirclrRing *r, const float *const *c, uint32_t n) {
    return circlr_ring_push_offset(r,c,0,n);
}
bool circlr_ring_push_offset(CirclrRing *r, const float *const *c, uint32_t offset, uint32_t n) {
    uint32_t w=atomic_load_explicit(&r->write,memory_order_relaxed), next=(w+1)%r->slots;
    if(n>r->frames || next==atomic_load_explicit(&r->read,memory_order_acquire)) { atomic_fetch_add_explicit(&r->overruns,1,memory_order_relaxed); return false; }
    for(uint32_t i=0;i<r->channels;i++) memcpy(r->data+((size_t)w*r->channels+i)*r->frames,c[i]+offset,n*sizeof(float));
    r->lengths[w]=n; atomic_store_explicit(&r->write,next,memory_order_release); return true;
}
uint32_t circlr_ring_pop(CirclrRing *r, float *const *c) {
    uint32_t x=atomic_load_explicit(&r->read,memory_order_relaxed);
    if(x==atomic_load_explicit(&r->write,memory_order_acquire)) return 0;
    uint32_t n=r->lengths[x]; for(uint32_t i=0;i<r->channels;i++) memcpy(c[i],r->data+((size_t)x*r->channels+i)*r->frames,n*sizeof(float));
    atomic_store_explicit(&r->read,(x+1)%r->slots,memory_order_release); return n;
}
uint32_t circlr_ring_overruns(CirclrRing *r) { return atomic_load_explicit(&r->overruns,memory_order_relaxed); }
