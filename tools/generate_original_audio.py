#!/usr/bin/env python3
"""Offline renderer for original procedural PCM WAV assets; no external samples."""
import json, math, random, struct, wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'assets/sound/original'; RATE=22050; random.seed(35291)
def write(path,data):
 path.parent.mkdir(parents=True,exist_ok=True); peak=max(1e-6,max(map(abs,data))); data=[max(-1,min(1,x*min(1,.67/peak))) for x in data]
 with wave.open(str(path),'wb') as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(b''.join(struct.pack('<h',int(x*32767)) for x in data))
def sound(name,dur,a,b,noise=0,chord=False):
 data=[]
 for i in range(int(dur*RATE)):
  t=i/RATE;e=min(1,t/.006)*max(0,1-t/dur)**1.7;freq=a+(b-a)*t/dur
  v=(math.sin(math.tau*freq*t)+.22*math.sin(math.tau*freq*2*t))*e*.55
  if chord:v+=.30*math.sin(math.tau*freq*1.5*t)*e
  data.append(v+random.uniform(-noise,noise)*e)
 write(OUT/'sfx'/(name+'.wav'),data);return data
def sequence(name,dur,events):
 """Layered transient phrases for the hero interactions (time, length, hz, endhz, noise, harmony)."""
 data=[]
 for i in range(int(dur*RATE)):
  t=i/RATE;v=0.
  for start,length,a,b,n,h in events:
   q=t-start
   if 0<=q<length:
    e=min(1,q/.004)*max(0,1-q/length)**1.55;f=a+(b-a)*q/length
    v+=(math.sin(math.tau*f*q)+.18*math.sin(math.tau*f*2*q)+(.35*math.sin(math.tau*f*1.5*q) if h else 0))*e*.36+random.uniform(-n,n)*e
  data.append(v)
 write(OUT/'sfx'/(name+'.wav'),data);return data
def music(name,battle):
 data=[];base=146.83 if battle else 196.; # Nine 4/4 bars: a real progression, not a short repeated phrase.
 chords=[0,5,3,7,0,8,3,7,0]; melody=[0,3,7,10,7,3,5,7, 7,10,12,10,7,5,3,5, 3,7,10,7,3,5,7,10, 7,5,3,0,3,5,7,3, 0,7,10,12,10,7,3,5, 8,7,3,5,7,10,7,3, 3,5,7,10,12,10,7,5, 7,10,7,5,3,0,3,5, 0,3,7,10,7,5,3,0]
 phase=0.; bass_phase=0.; kick_phase=0.
 for i in range(36*RATE):
  t=i/RATE;beat=t*2;step=int(beat);local=beat-step;bar=min(8,step//8);note=melody[step];freq=base*2**(note/12)
  # Local envelope and phase accumulator prevent oscillator discontinuities at note changes.
  atk=min(1,local*28);rel=max(0,1-local)**1.8;amp=.15*atk*rel;phase+=freq/RATE
  bass=base*.5*2**(chords[bar]/12);bass_phase+=bass/RATE
  v=(math.sin(math.tau*phase)+.19*math.sin(math.tau*phase*2))*amp + math.sin(math.tau*bass_phase)*.055
  if not battle: v+=math.sin(math.tau*phase*1.498)*amp*.18
  if battle:
   kick_local=(beat%1);kf=82-28*min(1,kick_local/.22);kick_phase+=kf/RATE
   v+=max(0,1-kick_local/.20)**3*math.sin(math.tau*kick_phase)*.22
   if kick_local<.055 and step%4 in [1,3]:v+=random.uniform(-.025,.025)*(1-kick_local/.055)
  data.append(v)
 # A 12ms wrap taper prevents a discontinuity at the PCM loop boundary.
 ramp=int(.012*RATE)
 for j in range(ramp):
  data[j]*=j/ramp;data[-1-j]*=j/ramp
 data[0]=0.;data[-1]=0.
 write(OUT/'music'/(name+'.wav'),data)
S={'ui_click':(.10,720,610,0,0),'ui_hover':(.07,980,1060,0,0),'ui_select':(.17,520,760,0,1),'ui_cancel':(.14,530,310,0,0),'ui_error':(.25,190,145,.04,0),'ui_slider':(.08,430,520,0,0),'equip':(.30,280,740,.02,1),'lock':(.17,260,210,.01,0),'unlock':(.18,300,580,.01,0),'craft':(.34,220,620,.03,1),'upgrade':(.52,330,980,.01,1),'socket':(.32,480,860,.01,1),'dismantle':(.30,400,120,.09,0),'reward':(.35,520,880,0,1),'level_up':(.72,390,1100,0,1),'fire':(.20,280,95,.10,0),'explosion':(.48,115,44,.22,0),'damage':(.25,145,70,.13,0),'heal':(.42,420,1050,.01,1),'turn':(.20,510,680,0,1),'win':(.80,520,1040,0,1),'lose':(.70,290,110,.04,0),'step':(.12,150,95,.08,0),'charge':(.25,180,470,.02,0),'charge_cancel':(.16,430,170,.02,0),'power':(.35,200,760,.04,1),'warning':(.30,820,820,.01,0),'hazard':(.38,130,60,.16,0),'pause':(.18,640,380,0,0),'resume':(.18,380,640,0,0)}
def main():
 audition=[]; meta={'source':'original procedural synthesis; no external samples','sample_rate':RATE,'format':'PCM 16-bit WAV','music':{'town_loop':{'seconds':36,'structure':'9 distinct 4/4 bars','layers':'pluck melody, bell harmony, bass pad'},'battle_loop':{'seconds':36,'structure':'9 distinct 4/4 bars','layers':'melody, bass, integrated kick, percussion'}},'sfx':{}}
 for n,p in S.items():
  audition+=sound(n,*p)+[0]*int(.12*RATE);meta['sfx'][n]={'seconds':p[0],'frequency_hz':[p[1],p[2]],'noise':p[3],'chord':bool(p[4])}
 # Replace the most recognisable feedback with layered phrases: forge impacts,
 # glass socket shimmer, projectile body/tail, and distinct result fanfares.
 hero={
  'upgrade':(.64,[(0,.07,120,90,.08,0),(.12,.07,140,105,.08,0),(.24,.08,160,112,.07,0),(.31,.32,520,1040,.01,1)]),
  'craft':(.46,[(0,.08,180,110,.10,0),(.14,.08,210,125,.10,0),(.26,.20,330,660,.02,1)]),
  'socket':(.40,[(0,.04,1300,970,.01,0),(.08,.04,1580,1160,.01,0),(.16,.20,760,1340,0,1)]),
  'fire':(.28,[(0,.10,105,62,.14,0),(.05,.23,280,78,.06,0)]),
  'win':(.92,[(0,.18,523,523,0,1),(.19,.18,659,659,0,1),(.38,.18,784,784,0,1),(.57,.32,1046,1046,0,1)]),
  'lose':(.86,[(0,.20,330,330,.015,0),(.21,.20,247,247,.015,0),(.42,.32,165,132,.025,0)])}
 for n,(d,e) in hero.items(): sequence(n,d,e);meta['sfx'][n]['seconds']=d;meta['sfx'][n]['phrase']='layered original transient phrase'
 audition=[]
 for n in S: # audition uses the final replacement assets rather than generic drafts.
  with wave.open(str(OUT/'sfx'/(n+'.wav')),'rb') as f:
   frames=f.getnframes(); audition += list(struct.unpack('<%dh'%frames,f.readframes(frames)));meta['sfx'][n]['seconds']=round(frames/RATE,4)
  audition += [0]*int(.12*RATE)
 audition=[x/32767 for x in audition]
 write(OUT/'original_sfx_audition.wav',audition);music('town_loop',False);music('battle_loop',True);(OUT/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
