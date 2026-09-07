#include "CirclrSynth.h"
#include <math.h>
#include <stdlib.h>
#include <stdatomic.h>
#define VOICES 64
#define EVENTS 2048
#define TAU 6.28318530717958647692
typedef struct { int pitch, active, released; double age, releaseAge, releaseLevel, level, velocity, frequency, phase[7], l1,l2,r1,r2; } Voice;
typedef struct { int pitch, velocity, on; } Event;
struct CirclrSynth { int style; double cutoff,attack,decay,sustain,release,detune; Voice voices[VOICES]; Event events[EVENTS]; atomic_uint read,write; atomic_bool overflow; };
CirclrSynth *circlr_synth_create(int style,double cutoff,double attack,double decay,double sustain,double release,double detune) {
    CirclrSynth *s=calloc(1,sizeof(*s)); if(!s) return NULL;
    s->style=style;s->cutoff=cutoff;s->attack=attack;s->decay=decay;s->sustain=sustain;s->release=release;s->detune=detune;
    atomic_init(&s->read,0);atomic_init(&s->write,0);atomic_init(&s->overflow,0);return s;
}
void circlr_synth_destroy(CirclrSynth *s){free(s);}
void circlr_synth_note(CirclrSynth *s,int pitch,int velocity,int on) {
    if(!s || pitch<0 || pitch>127) return;
    unsigned w=atomic_load_explicit(&s->write,memory_order_relaxed),r=atomic_load_explicit(&s->read,memory_order_acquire);
    if(w-r>=EVENTS){atomic_store(&s->overflow,1);return;}
    s->events[w%EVENTS]=(Event){pitch,velocity,on};atomic_store_explicit(&s->write,w+1,memory_order_release);
}
static double blep(double p,double dt){if(p<dt){p/=dt;return p+p-p*p-1;}if(p>1-dt){p=(p-1)/dt;return p*p+p+p+1;}return 0;}
static double saw(double p,double dt){return 2*p-1-blep(p,dt);}
void circlr_synth_render(CirclrSynth *s,float *left,float *right,uint32_t frames) {
    if(!s)return;
    unsigned r=atomic_load_explicit(&s->read,memory_order_relaxed),w=atomic_load_explicit(&s->write,memory_order_acquire);
    if(atomic_exchange(&s->overflow,0)){for(int v=0;v<VOICES;v++)s->voices[v].active=0;r=w;}
    while(r<w){Event e=s->events[r++%EVENTS];
        if(e.on && e.velocity>0){int chosen=-1;double oldest=-1;
            for(int v=0;v<VOICES;v++){if(!s->voices[v].active){chosen=v;break;}if(s->voices[v].age>oldest){oldest=s->voices[v].age;chosen=v;}}
            Voice *v=&s->voices[chosen];*v=(Voice){0};v->active=1;v->pitch=e.pitch;v->velocity=fmin(127,e.velocity)/127.0;v->frequency=440*pow(2,(e.pitch-69)/12.0);
            for(int n=0;n<7;n++)v->phase[n]=fmod(n*0.173+e.pitch*0.019,1);
        }else{for(int i=0;i<VOICES;i++){Voice *v=&s->voices[i];if(v->active && v->pitch==e.pitch && !v->released){v->released=1;v->releaseLevel=v->level;break;}}}
    }
    atomic_store_explicit(&s->read,r,memory_order_release);
    const double dt=1.0/48000;
    for(int vi=0;vi<VOICES;vi++){Voice *v=&s->voices[vi];if(!v->active)continue;
        int count=s->style==3?7:(s->style==2?1:3);double increments[7];
        for(int n=0;n<count;n++)increments[n]=fmin(0.45,v->frequency*pow(2,((double)n-(count-1)*0.5)*s->detune/(count>1?count-1:1)/1200)/48000);
        for(uint32_t i=0;i<frames;i++){
            double env;
            if(v->released){env=v->releaseLevel*fmax(0,1-v->releaseAge/s->release);v->releaseAge+=dt;if(env<=0){v->active=0;break;}}
            else if(v->age<s->attack)env=v->age/s->attack;
            else env=s->sustain+(1-s->sustain)*exp(-(v->age-s->attack)*4/s->decay);
            v->level=env;double l=0,rr=0;
            for(int n=0;n<count;n++){
                double p=v->phase[n],value;
                if(s->style==2){double mod=2.3*exp(-v->age*3.5);value=sin(TAU*p+mod*sin(TAU*p*2))*.8+sin(TAU*p*3)*.08*exp(-v->age*6);}
                else if(s->style==1){double p2=fmod(p+.48,1);value=(saw(p,increments[n])-saw(p2,increments[n]))*.45+sin(TAU*p)*.55;}
                else if(s->style==5)value=.55*sin(TAU*p)+.45*saw(p,increments[n]);
                else value=saw(p,increments[n]);
                double pan=count==1?.5:(double)n/(count-1);l+=value*sqrt(1-pan);rr+=value*sqrt(pan);
                v->phase[n]+=increments[n];v->phase[n]-=floor(v->phase[n]);
            }
            double cutoff=s->cutoff*(s->style==4 ? (.2+.8*exp(-v->age*8)) : 1);
            double alpha=1-exp(-TAU*cutoff/48000);v->l1+=alpha*(l/count-v->l1);v->l2+=alpha*(v->l1-v->l2);v->r1+=alpha*(rr/count-v->r1);v->r2+=alpha*(v->r1-v->r2);
            double gain=env*v->velocity*.28;
            left[i]+=(float)(v->l2*gain);right[i]+=(float)(v->r2*gain);v->age+=dt;
        }
    }
}
