// Original Cloud Hop sketches. Standard Node only; no packages or samples.
const fs=require('fs'),path=require('path');
const SR=44100, TAU=Math.PI*2;
let seed=713;const noise=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/2147483648-1;};
function compose(name,bpm,bars,race){
 const beat=60/bpm,len=bars*4*beat,N=Math.ceil((len+1.8)*SR),L=new Float32Array(N),R=new Float32Array(N);
 function put(start,duration,fn,amp=.2,pan=0){const n=Math.ceil(duration*SR),off=Math.round(start*SR);for(let i=0;i<n && off+i<N;i++){const t=i/SR,v=fn(t,duration)*amp;L[off+i]+=v*Math.sqrt((1-pan)/2);R[off+i]+=v*Math.sqrt((1+pan)/2);}}
 function note(at,midi,dur,kind,amp=.2,pan=0){const f=440*2**((midi-69)/12);put(at,dur,(t,d)=>{const attack=Math.min(1,t/.007),release=Math.min(1,(d-t)/.055);let wave;
  if(kind==='bell')wave=(Math.sin(TAU*f*t)+.35*Math.sin(TAU*f*2*t)*Math.exp(-t*5)+.16*Math.sin(TAU*f*3*t)*Math.exp(-t*9))*Math.exp(-t*3.5);
  else if(kind==='bass')wave=(Math.sin(TAU*f*t)+.24*Math.sin(TAU*f*2*t)+.1*Math.sin(TAU*f*3*t))*Math.exp(-t*1.6);
  else if(kind==='pad')wave=(Math.sin(TAU*f*t)+.25*Math.sin(TAU*f*1.003*t)+.15*Math.sin(TAU*f*2*t))*.42*Math.min(1,t/.17);
  else wave=(Math.sin(TAU*f*t)+.3*Math.sin(TAU*f*2*t)+.13*Math.sin(TAU*f*3*t))*Math.exp(-t*2.8);
  return wave*attack*release;},amp,pan);}
 function drum(at,kind,amp=1){if(kind==='kick')put(at,.24,t=>Math.sin(TAU*(48*t+3.2*(1-Math.exp(-t*35))))*Math.exp(-t*21),.46*amp);
  if(kind==='snare')put(at,.18,t=>(noise()*.6+Math.sin(TAU*180*t)*.4)*Math.exp(-t*26),.24*amp,.1);
  if(kind==='hat')put(at,.07,t=>noise()*Math.exp(-t*70),.1*amp,-.3);}
 const progression=race?[[57,60,64],[53,57,60],[48,52,55],[55,59,62]]:[[48,52,55],[55,59,62],[57,60,64],[53,57,60]];
 const melodies=race?[[76,79,81,79,76,74,72,74],[77,76,72,69,72,76,77,79],[76,79,84,83,79,76,74,72],[74,79,83,81,79,77,76,74]]:[[76,79,79,76,74,72],[74,79,83,81,79,74],[76,81,79,76,72,69],[77,76,72,74,76,72]];
 for(let bar=0;bar<bars;bar++){
  const chord=progression[bar%4],start=bar*4*beat,section=Math.floor(bar/4);
  chord.forEach((m,j)=>note(start,m+12,beat*3.9,'pad',race?.075:.10,(j-1)*.48));
  for(let k=0;k<8;k++){const pos=k*.5;note(start+pos*beat,chord[k%3]+(k%4===3?24:12),beat*.34,'bell',race?.105:.10,k%2?.46:-.46);}
  for(let k=0;k<4;k++){
   note(start+k*beat,chord[0]-12+(k===2?7:0),beat*(race?.68:.8),'bass',race?.28:.21);
   if(race || k===0 || k===2)drum(start+k*beat,'kick',race?1:.72);
   if(k===1||k===3)drum(start+k*beat,'snare',race?.9:.36);
   for(let j=0;j<(race?2:1);j++)drum(start+(k+j*.5)*beat,'hat',race?.72:.42);
  }
  if(bar>=2){const melody=melodies[bar%4];melody.forEach((m,j)=>{
   const positions=race?[0,.5,1,1.5,2,2.5,3,3.5]:[0,.75,1.5,2,2.75,3.5];
   note(start+positions[j]*beat,m+(section%4===2?12:0),beat*(race?.43:.63),race?'lead':'bell',race?.22:.24,-.08);
  });}
  if(race && bar%4===3)for(let j=0;j<4;j++)drum(start+(3+j*.25)*beat,'snare',.35+j*.12);
 }
 // Musical tail, stereo room and beat delay. No hard cut on the preview.
 for(let i=0;i<N;i++){const d=Math.round(beat*.75*SR),room=Math.round(.067*SR);if(i>=d){L[i]+=R[i-d]*.15;R[i]+=L[i-d]*.15;}if(i>=room){L[i]+=L[i-room]*.055;R[i]+=R[i-room]*.055;}}
 let peak=0;for(let i=0;i<N;i++)peak=Math.max(peak,Math.abs(L[i]),Math.abs(R[i]));const gain=.88/peak;
 const out=Buffer.alloc(44+N*4);out.write('RIFF');out.writeUInt32LE(out.length-8,4);out.write('WAVEfmt ',8);out.writeUInt32LE(16,16);out.writeUInt16LE(1,20);out.writeUInt16LE(2,22);out.writeUInt32LE(SR,24);out.writeUInt32LE(SR*4,28);out.writeUInt16LE(4,32);out.writeUInt16LE(16,34);out.write('data',36);out.writeUInt32LE(N*4,40);
 for(let i=0;i<N;i++){const fade=Math.min(1,i/(SR*.04),(N-i)/(SR*1.6));out.writeInt16LE(Math.round(Math.max(-1,Math.min(1,L[i]*gain*fade))*32767),44+i*4);out.writeInt16LE(Math.round(Math.max(-1,Math.min(1,R[i]*gain*fade))*32767),46+i*4);}
 fs.writeFileSync(path.join(__dirname,name+'.wav'),out);console.log(name+': '+(N/SR).toFixed(1)+' seconds, '+bpm+' BPM, original stereo WAV');
}
compose('Cloud-Hop-Home-Sky-Garden',96,16,false);
compose('Cloud-Hop-Race-Sky-Sprint',144,24,true);
