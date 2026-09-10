#include "CirclrSynth.h"
#include <math.h>
#include <stdlib.h>
#include <stdatomic.h>
#define VOICES 64
#define EVENTS 2048
#define TAU 6.28318530717958647692
typedef struct { int pitch, active, released; uint64_t streamID, voiceID; double lastL,lastR; double age, releaseAge, releaseLevel, level, velocity, frequency, phase[7], tinePhase, l1,l2,r1,r2; } Voice;
typedef struct { int pitch, velocity, on; } Event;
struct CirclrSynth { int style,version; double resonance,width,filterEnvelope,stealL,stealR; double cutoff,attack,decay,sustain,release,detune; Voice voices[VOICES]; Event events[EVENTS]; atomic_uint read,write; atomic_bool overflow; double character,motion,motionPhase; unsigned chorusWrite; float chorusL[2048],chorusR[2048]; };
CirclrSynth *circlr_synth_create(int style,double cutoff,double attack,double decay,double sustain,double release,double detune) {
    CirclrSynth *s=calloc(1,sizeof(*s)); if(!s) return NULL;
    s->style=style;s->cutoff=cutoff;s->attack=attack;s->decay=decay;s->sustain=sustain;s->release=release;s->detune=detune;
    atomic_init(&s->read,0);atomic_init(&s->write,0);atomic_init(&s->overflow,0);return s;
}
CirclrSynth *circlr_synth_create_v2(int style,double cutoff,double attack,double decay,double sustain,double release,double detune,double resonance,double width,double filterEnvelope) {
    CirclrSynth *s=circlr_synth_create(style,cutoff,attack,decay,sustain,release,detune);
    if(s){s->version=2;s->resonance=resonance;s->width=width;s->filterEnvelope=filterEnvelope;}
    return s;
}
static void render_v2(CirclrSynth *s,float *left,float *right,uint32_t frames,const double *cutoffHz,const double *resonance);
static void render_v3(CirclrSynth *s,float *left,float *right,uint32_t frames,const double *cutoffHz,const double *resonance);
CirclrSynth *circlr_synth_create_v3(int style,double cutoff,double attack,double decay,double sustain,double release,double detune,double resonance,double width,double filterEnvelope,double character,double motion) {
    CirclrSynth *s=circlr_synth_create_v2(style,cutoff,attack,decay,sustain,release,detune,resonance,width,filterEnvelope);
    if(s){s->version=3;s->character=character;s->motion=motion;}
    return s;
}
void circlr_synth_destroy(CirclrSynth *s){free(s);}
void circlr_synth_note(CirclrSynth *s,int pitch,int velocity,int on) {
    if(!s || pitch<0 || pitch>127) return;
    unsigned w=atomic_load_explicit(&s->write,memory_order_relaxed),r=atomic_load_explicit(&s->read,memory_order_acquire);
    if(w-r>=EVENTS){atomic_store(&s->overflow,1);return;}
    s->events[w%EVENTS]=(Event){pitch,velocity,on};atomic_store_explicit(&s->write,w+1,memory_order_release);
}
// These entry points are synchronous and belong exclusively to the render owner.
// Zero identities distinguish legacy queued voices; no controller table is retained.
static int owned_frequency(int pitch,double semitones,double *frequency) {
    if(pitch<0 || pitch>127 || !isfinite(semitones) || semitones < -128.27 || semitones > 128.27)return 0;
    // Keep the zero-bend arithmetic exactly equal to the legacy note-on path.
    double hz=440*pow(2,(pitch-69)/12.0);
    if(semitones!=0)hz*=pow(2,semitones/12.0);
    if(!isfinite(hz) || hz<=0)return 0;
    *frequency=hz;return 1;
}
int circlr_synth_owned_note_on(CirclrSynth *s,uint64_t streamID,uint64_t voiceID,int pitch,int velocity,double semitones) {
    double frequency;
    if(!s || !streamID || !voiceID || velocity<1 || velocity>127 || !owned_frequency(pitch,semitones,&frequency))return 0;
    for(int i=0;i<VOICES;i++){
        Voice *v=&s->voices[i];
        if(v->active && v->streamID==streamID && v->voiceID==voiceID)return 0;
    }
    int chosen=-1;double oldest=-1;
    for(int i=0;i<VOICES;i++){
        if(!s->voices[i].active){chosen=i;break;}
        if(s->voices[i].age>oldest){oldest=s->voices[i].age;chosen=i;}
    }
    Voice *v=&s->voices[chosen];
    if(s->version>=2 && v->active){s->stealL+=v->lastL;s->stealR+=v->lastR;}
    *v=(Voice){0};v->active=1;v->pitch=pitch;v->velocity=fmin(127,velocity)/127.0;v->frequency=frequency;
    v->streamID=streamID;v->voiceID=voiceID;
    for(int n=0;n<7;n++)v->phase[n]=fmod(n*0.173+pitch*0.019,1);
    return 1;
}
int circlr_synth_owned_note_off(CirclrSynth *s,uint64_t streamID,uint64_t voiceID) {
    if(!s || !streamID || !voiceID)return 0;
    for(int i=0;i<VOICES;i++){
        Voice *v=&s->voices[i];
        if(v->active && v->streamID==streamID && v->voiceID==voiceID && !v->released){
            v->released=1;v->releaseLevel=v->level;break;
        }
    }
    return 1;
}
int circlr_synth_owned_pitch_bend(CirclrSynth *s,uint64_t streamID,double semitones) {
    double frequencies[VOICES],validatedFrequency;
    if(!s || !streamID || !owned_frequency(69,semitones,&validatedFrequency))return 0;
    // Validate the whole bounded pool before mutation, including release voices.
    for(int i=0;i<VOICES;i++){
        Voice *v=&s->voices[i];
        if(v->active && v->streamID==streamID && !owned_frequency(v->pitch,semitones,&frequencies[i]))return 0;
    }
    for(int i=0;i<VOICES;i++){
        Voice *v=&s->voices[i];
        if(v->active && v->streamID==streamID)v->frequency=frequencies[i];
    }
    return 1;
}
static double blep(double p,double dt){if(p<dt){p/=dt;return p+p-p*p-1;}if(p>1-dt){p=(p-1)/dt;return p*p+p+p+1;}return 0;}
static double saw(double p,double dt){return 2*p-1-blep(p,dt);}
static double base_cutoff(const CirclrSynth *s,const double *values,uint32_t index) {
    if(!values)return s->cutoff;
    double hz=values[index];return isfinite(hz) && hz>=40 && hz<=20000 ? hz:s->cutoff;
}
static double base_resonance(const CirclrSynth *s,const double *values,uint32_t index) {
    if(!values)return s->resonance;
    double value=values[index];return isfinite(value) && value>=0 && value<=0.9 ? value:s->resonance;
}
void circlr_synth_render(CirclrSynth *s,float *left,float *right,uint32_t frames) {
    circlr_synth_render_cutoff(s,left,right,NULL,frames);
}
void circlr_synth_render_cutoff(CirclrSynth *s,float *left,float *right,const double *cutoffHz,uint32_t frames) {
    circlr_synth_render_filter(s,left,right,cutoffHz,NULL,frames);
}
void circlr_synth_render_filter(CirclrSynth *s,float *left,float *right,const double *cutoffHz,const double *resonance,uint32_t frames) {
    if(!s)return;
    unsigned r=atomic_load_explicit(&s->read,memory_order_relaxed),w=atomic_load_explicit(&s->write,memory_order_acquire);
    if(atomic_exchange(&s->overflow,0)){
        for(int i=0;i<VOICES;i++){Voice *v=&s->voices[i];if(s->version>=2 && v->active){v->released=1;v->releaseLevel=v->level;v->releaseAge=0;}else v->active=0;}r=w;
    }
    while(r<w){Event e=s->events[r++%EVENTS];
        if(e.on && e.velocity>0){int chosen=-1;double oldest=-1;
            for(int v=0;v<VOICES;v++){if(!s->voices[v].active){chosen=v;break;}if(s->voices[v].age>oldest){oldest=s->voices[v].age;chosen=v;}}
            Voice *v=&s->voices[chosen];
            if(s->version>=2 && v->active){s->stealL+=v->lastL;s->stealR+=v->lastR;}
            *v=(Voice){0};v->active=1;v->pitch=e.pitch;v->velocity=fmin(127,e.velocity)/127.0;v->frequency=440*pow(2,(e.pitch-69)/12.0);
            for(int n=0;n<7;n++)v->phase[n]=fmod(n*0.173+e.pitch*0.019,1);
        }else{for(int i=0;i<VOICES;i++){Voice *v=&s->voices[i];if(v->active && v->pitch==e.pitch && !v->released){v->released=1;v->releaseLevel=v->level;break;}}}
    }
    atomic_store_explicit(&s->read,r,memory_order_release);
    if(s->version==3){render_v3(s,left,right,frames,cutoffHz,resonance);return;}
    if(s->version==2){render_v2(s,left,right,frames,cutoffHz,resonance);return;}
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
            double cutoff=base_cutoff(s,cutoffHz,i)*(s->style==4 ? (.2+.8*exp(-v->age*8)) : 1);
            double alpha=1-exp(-TAU*cutoff/48000);v->l1+=alpha*(l/count-v->l1);v->l2+=alpha*(v->l1-v->l2);v->r1+=alpha*(rr/count-v->r1);v->r2+=alpha*(v->r1-v->r2);
            double gain=env*v->velocity*.28;
            left[i]+=(float)(v->l2*gain);right[i]+=(float)(v->r2*gain);v->age+=dt;
        }
    }
}

// TPT state-variable low-pass; trapezoidal state update (Simper, Cytomic 2013).
static double lowpass_v2(double input,double g,double k,double *s1,double *s2) {
    double a=1/(1+g*(g+k)),v1=a*(*s1+g*(input-*s2)),v2=*s2+g*v1;
    *s1=2*v1-*s1;*s2=2*v2-*s2;return v2;
}
static void render_v2(CirclrSynth *s,float *left,float *right,uint32_t frames,const double *cutoffHz,const double *resonance) {
    const double dt=1.0/48000;
    // Carry the stolen voice's last sample down over ~4 ms instead of a hard reset.
    for(uint32_t i=0;i<frames;i++){left[i]+=(float)s->stealL;right[i]+=(float)s->stealR;s->stealL*=0.97;s->stealR*=0.97;}
    for(int vi=0;vi<VOICES;vi++){
        Voice *v=&s->voices[vi];if(!v->active)continue;
        int count=(s->style==1 || s->style==2)?1:(s->style==3?7:3);
        double inc[7];for(int n=0;n<count;n++)inc[n]=fmin(.45,v->frequency*pow(2,((double)n-(count-1)*.5)*s->detune/(count>1?count-1:1)/1200)/48000);
        for(uint32_t i=0;i<frames;i++){
            double env;
            if(v->released){double t=fmax(0,1-v->releaseAge/s->release);env=v->releaseLevel*t*t;v->releaseAge+=dt;if(t<=0){v->active=0;v->lastL=v->lastR=0;break;}}
            else if(v->age<s->attack){double t=v->age/s->attack;env=t*t*(3-2*t);}
            else env=s->sustain+(1-s->sustain)*exp(-(v->age-s->attack)*4/s->decay);
            v->level=env;double l=0,r=0;
            for(int n=0;n<count;n++){
                double p=v->phase[n],value=0;
                if(s->style==1){
                    // One phase-coherent oscillator in the low end, no stereo beating.
                    double pulse=saw(p,inc[n])-saw(fmod(p+.48,1),inc[n]);
                    value=.68*sin(TAU*p)+.22*pulse;
                }else if(s->style==2){
                    // Velocity-shaped, integer partials; no unbounded FM sidebands.
                    value=sin(TAU*p);
                    const double levels[5]={.32,.16,.065,.035,.012};
                    for(int h=2;h<=6;h++)if(h*inc[n]<.43)
                        value+=levels[h-2]*pow(v->velocity,1.3)*exp(-v->age*(h*.9))*sin(TAU*p*h);
                    value*=.75;
                }else if(s->style==5)value=.62*sin(TAU*p)+.38*saw(p,inc[n]);
                else if(s->style==4)value=.7*saw(p,inc[n])+.3*sin(TAU*p);
                else value=saw(p,inc[n]);
                double width=(s->style==1 || s->style==2)?0:s->width;
                double pan=count==1?.5:.5+((double)n/(count-1)-.5)*width;
                l+=value*sqrt(1-pan);r+=value*sqrt(pan);
                v->phase[n]+=inc[n];v->phase[n]-=floor(v->phase[n]);
            }
            // Tracking preserves brightness across registers; envelope works in octaves.
            double tracking=pow(v->frequency/261.625565,.28);
            double sweep=s->filterEnvelope*exp(-v->age*4/fmax(.03,s->decay));
            double cutoff=fmin(18000,fmax(40,base_cutoff(s,cutoffHz,i)*tracking*(.65+.35*v->velocity)*pow(2,sweep)));
            double g=tan(TAU*.5*cutoff/48000),k=2-1.6*base_resonance(s,resonance,i);
            double gain=env*pow(v->velocity,1.35)*.32;
            v->lastL=lowpass_v2(l/count,g,k,&v->l1,&v->l2)*gain;
            v->lastR=lowpass_v2(r/count,g,k,&v->r1,&v->r2)*gain;
            left[i]+=(float)v->lastL;right[i]+=(float)v->lastR;v->age+=dt;
        }
    }
}


// Engine 3 is deliberately separate: saved engine 1/2 projects retain their samples.
static double pulse_v3(double p,double increment,double duty) {
    // Our rising saw has a negative sine fundamental. Align both with the sine body.
    return -.5*(saw(p,increment)-saw(fmod(p+duty,1),increment));
}
static float chorus_tap(const float *line,unsigned write,double delay) {
    double position=fmod((double)write+2048-delay,2048);
    unsigned index=(unsigned)position;double fraction=position-index;
    return (float)(line[index]*(1-fraction)+line[(index+1)&2047]*fraction);
}
static void render_v3(CirclrSynth *s,float *left,float *right,uint32_t frames,const double *cutoffHz,const double *resonance) {
    const double dt=1.0/48000;
    // Fixed stack scratch and preallocated delay lines: no allocation/lock in callback.
    for(uint32_t offset=0;offset<frames;offset+=256){
        uint32_t countFrames=frames-offset<256?frames-offset:256;
        float dryL[256]={0},dryR[256]={0};
        for(uint32_t i=0;i<countFrames;i++){
            dryL[i]=(float)s->stealL;dryR[i]=(float)s->stealR;s->stealL*=.97;s->stealR*=.97;
        }
        for(int vi=0;vi<VOICES;vi++){
            Voice *v=&s->voices[vi];if(!v->active)continue;
            int style=s->style,count=(style==1 || style==2 || style==6 || style==7)?1:(style==3?7:(style==9?5:3));
            double inc[7],panL[7],panR[7];
            double width=style==1?0:s->width;
            // Nonuniform tuning avoids all oscillators beating in lockstep.
            const double spread[7]={-1,-.61,-.23,0,.19,.57,.97};
            for(int n=0;n<count;n++){
                double spreadValue=count==7?spread[n]:(count==1?0:(2.0*n/(count-1)-1));
                inc[n]=fmin(.45,v->frequency*pow(2,spreadValue*s->detune*.5/1200)/48000);
                double pan=count==1?.5:.5+((double)n/(count-1)-.5)*width;
                panL[n]=sqrt(1-pan);panR[n]=sqrt(pan);
            }
            double tracking=pow(v->frequency/261.625565,.22);
            double normalization=count==1?1:sqrt((double)count)*1.25;
            double velocityGain=pow(v->velocity,1.15)*.33;
            for(uint32_t i=0;i<countFrames;i++){
                double env;
                if(v->released){double t=fmax(0,1-v->releaseAge/s->release);env=v->releaseLevel*t*t;v->releaseAge+=dt;if(t<=0){v->active=0;v->lastL=v->lastR=0;break;}}
                else if(v->age<s->attack){double t=v->age/s->attack;env=t*t*(3-2*t);}
                else env=s->sustain+(1-s->sustain)*exp(-(v->age-s->attack)*3/s->decay);
                v->level=env;double l=0,r=0;
                double movement=sin(TAU*(v->age*.31+vi*.113));
                double duty=.5+s->motion*.12*movement;
                for(int n=0;n<count;n++){
                    double p=v->phase[n],value=0,body=sin(TAU*p),edge=-saw(p,inc[n]);
                    if(style==1){
                        value=(.85-.3*s->character)*body+(.15+.3*s->character)*pulse_v3(p,inc[n],.43)*1.5;
                        if(inc[n]*2<.43)value+=.12*s->character*sin(TAU*p*2);
                    }else if(style==2 || style==6){
                        // Bell/tine partials are individually band limited. No unbounded FM.
                        value=body*(style==6?.78:.65);
                        const double bell[5]={.42,.22,.15,.06,.035};
                        const double tine[5]={.12,.33,.05,.11,.025};
                        for(int h=2;h<=6;h++)if(h*inc[n]<.43){
                            double level=(style==6?tine[h-2]:bell[h-2])*(.35+.95*s->character)*v->velocity;
                            value+=level*exp(-v->age*(style==6?.55:1.3)*h)*sin(TAU*p*h);
                        }
                        if(style==6 && inc[n]*7.01<.43)value+=.16*s->character*v->velocity*exp(-v->age*16)*sin(TAU*v->tinePhase);
                    }else if(style==7){
                        const int harmonics[6]={1,2,3,4,6,8};
                        const double levels[6]={.62,.35,.23,.12,.055,.025};
                        for(int h=0;h<6;h++)if(inc[n]*harmonics[h]<.43)
                            value+=levels[h]*(h==0?1:.3+s->character)*sin(TAU*p*harmonics[h]);
                        if(inc[n]*3<.43)value+=.22*exp(-v->age*18)*sin(TAU*p*3);
                    }else if(style==5){
                        value=.42*body+(.23+.25*s->character)*pulse_v3(p,inc[n],duty)+.22*edge;
                    }else if(style==4){
                        value=(.65-.2*s->character)*body+(.35+.2*s->character)*edge;
                    }else if(style==8){
                        value=.7*edge+.3*pulse_v3(p,inc[n],.32);
                    }else if(style==9){
                        value=.62*edge+.28*pulse_v3(p,inc[n],duty)+.1*body;
                    }else if(style==0){
                        value=.43*edge+(.25+.2*s->character)*pulse_v3(p,inc[n],duty)+.25*body;
                    }else {value=.86*edge+.14*body;}
                    l+=value*panL[n];r+=value*panR[n];
                    // Bass/keys stay exactly tuned; sustained ensembles have subtle drift.
                    double drift=(style==0 || style==9)?1+s->motion*.0008*movement:1;
                    v->phase[n]+=inc[n]*drift;v->phase[n]-=floor(v->phase[n]);
                }
                v->tinePhase+=inc[0]*7.01;v->tinePhase-=floor(v->tinePhase);
                double sweep=s->filterEnvelope*exp(-v->age*3/fmax(.03,s->decay));
                if(style==8)sweep+=1.1*env; // brass opens with its attack, not before it
                double motionOctaves=(style==0 || style==9)?s->motion*.22*movement:0;
                double cutoff=fmin(18000,fmax(40,base_cutoff(s,cutoffHz,offset+i)*tracking*(.55+.45*v->velocity)*pow(2,sweep+motionOctaves)));
                double g=tan(TAU*.5*cutoff/48000),k=2-1.6*base_resonance(s,resonance,offset+i);
                double gain=env*velocityGain;
                v->lastL=lowpass_v2(l/normalization,g,k,&v->l1,&v->l2)*gain;
                v->lastR=lowpass_v2(r/normalization,g,k,&v->r1,&v->r2)*gain;
                dryL[i]+=(float)v->lastL;dryR[i]+=(float)v->lastR;v->age+=dt;
            }
        }
        // Two independently modulated, spatialized taps. Dry body remains present in mono.
        double wet=s->style==1?0:s->motion*s->width*(s->style==9?.42:.26);
        for(uint32_t i=0;i<countFrames;i++){
            unsigned w=s->chorusWrite;
            s->chorusL[w]=dryL[i];s->chorusR[w]=dryR[i];
            double delayL=680+150*sin(TAU*s->motionPhase),delayR=790+170*sin(TAU*(s->motionPhase*1.17+.31));
            double l=dryL[i]+wet*chorus_tap(s->chorusR,w,delayL),r=dryR[i]+wet*chorus_tap(s->chorusL,w,delayR);
            left[offset+i]+=(float)l;right[offset+i]+=(float)r;
            s->chorusWrite=(w+1)&2047;s->motionPhase+=.27*dt;
        }
    }
}
