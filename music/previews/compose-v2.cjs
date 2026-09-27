// Cloud Hop v2: original cartoon-adventure arrangements, synthesized without samples.
const fs=require('fs'),path=require('path');const SR=44100,T=Math.PI*2;
let rng=93891;function random(){rng=(Math.imul(rng,1664525)+1013904223)>>>0;return rng/2147483648-1;}
function render(file,tempo,bars,home){
 const beat=60/tempo,barBeats=home?3:4,body=bars*barBeats*beat,duration=body+2.4,n=Math.ceil(duration*SR),left=new Float32Array(n),right=new Float32Array(n);
 function voice(at,dur,fn,volume,pan){const off=Math.round(at*SR),count=Math.ceil(dur*SR),gl=Math.sqrt((1-pan)/2)*volume,gr=Math.sqrt((1+pan)/2)*volume;for(let j=0;j<count&&off+j<n;j++){const v=fn(j/SR,dur);left[off+j]+=v*gl;right[off+j]+=v*gr;}}
 function note(pos,midi,length,instrument,volume=.2,pan=0){const f=440*2**((midi-69)/12);let smooth=0;
  voice(pos*beat,length*beat+.12,(t,d)=>{
   const release=Math.min(1,Math.max(0,(d-t)/.13));let w=0,env=1;
   if(instrument==='flute') {const phase=T*f*t+.028*Math.sin(T*5.3*t);w=Math.sin(phase)+.15*Math.sin(phase*2)+.025*Math.sin(phase*3);env=Math.min(1,t/.035)*(.86+.14*Math.sin(Math.PI*t/d));}
   else if(instrument==='pizz') {w=Math.sin(T*f*t)+.34*Math.sin(T*f*2*t)+.11*Math.sin(T*f*3*t)+.04*Math.sin(T*f*5*t);env=Math.min(1,t/.006)*Math.exp(-t*8);}
   else if(instrument==='marimba'){w=Math.sin(T*f*t)+.3*Math.sin(T*f*4*t)*Math.exp(-t*16);env=Math.min(1,t/.004)*Math.exp(-t*5.5);}
   else if(instrument==='horn'){const phase=T*f*t+.012*Math.sin(T*4.8*t);w=Math.sin(phase)+.27*Math.sin(phase*2)+.1*Math.sin(phase*3);env=Math.min(1,t/.042)*(.65+.35*Math.exp(-t*4));}
   else if(instrument==='strings'){w=(Math.sin(T*f*t)+Math.sin(T*f*1.002*t)+Math.sin(T*f*.997*t))*.27+.08*Math.sin(T*f*2*t);env=Math.min(1,t/.22);}
   else {w=Math.sin(T*f*t)+.18*Math.sin(T*f*2*t);env=Math.min(1,t/.009)*Math.exp(-t*2.2);}
   return w*env*release;
  },volume,pan);
 }
 function drum(pos,type,volume=1){let smooth=0,prev=0;voice(pos*beat,type==='cymbal'?.7:.32,(t)=>{const noise=random();smooth+=.17*(noise-smooth);let x;
  if(type==='kick')x=Math.sin(T*(48*t+1.8*(1-Math.exp(-35*t))))*Math.exp(-t*19);
  else if(type==='tom')x=Math.sin(T*(100*t+2.5*(1-Math.exp(-12*t))))*Math.exp(-t*13);
  else if(type==='snare')x=(smooth*.65+Math.sin(T*185*t)*.18)*Math.exp(-t*22);
  else if(type==='cymbal')x=(noise-smooth)*Math.exp(-t*7)*.16;
  else x=(noise-smooth)*Math.exp(-t*65)*.2;
  return x;
 },volume*(type==='kick'?.4:.24),type==='shaker'?.35:0);}
 const homeChords=[[50,54,57],[55,59,62],[57,61,64],[50,54,57],[59,62,66],[55,59,62],[57,61,64],[50,54,57]];
 const raceChords=[[50,53,57],[58,62,65],[53,57,60],[48,52,55],[55,58,62],[58,62,65],[57,61,64],[50,53,57]];
 const homeMel=[[[0,78,.5],[.75,81,.5],[1.5,78,.5],[2.25,76,.45]],[[0,74,1],[1.5,71,.5],[2.25,74,.5]],[[0,76,.5],[.75,73,.5],[1.5,69,.5],[2.25,73,.45]],[[0,74,2.4]],[[0,78,.5],[.75,81,.5],[1.5,83,.5],[2.25,81,.45]],[[0,79,1],[1.5,78,.5],[2.25,74,.5]],[[0,76,.5],[.75,73,.5],[1.5,76,.5],[2.25,81,.45]],[[0,78,.5],[.75,76,.5],[1.5,74,1.2]]];
 const raceMel=[[[0,74,.65],[.75,77,.4],[1.5,81,.7],[2.5,79,.4],[3.25,77,.5]],[[0,74,.7],[1,77,.5],[1.75,82,.7],[3,81,.7]],[[0,81,.4],[.5,79,.4],[1.25,77,.6],[2.25,76,.4],[3,77,.7]],[[0,79,1.4],[1.75,76,.4],[2.5,72,.6],[3.25,74,.4]],[[0,79,.65],[.75,82,.4],[1.5,86,.7],[2.5,84,.4],[3.25,82,.5]],[[0,82,.65],[.75,81,.4],[1.5,77,.7],[2.5,74,1.1]],[[0,81,.65],[.75,80,.4],[1.5,81,.5],[2.25,85,.5],[3,81,.65]],[[0,77,.6],[.75,76,.5],[1.5,74,1.9]]];
 for(let b=0;b<bars;b++){
  const start=b*barBeats,c=(home?homeChords:raceChords)[b%8],last=b>=bars-2,build=b>=8,dyn=last?.75:build?1:.83;
  c.forEach((m,j)=>note(start,m+12,barBeats-.15,'strings',(home?.095:.12)*dyn,(j-1)*.55));
  if(home){
   note(start,c[0]-12,.85,'bass',.25,-.12);note(start+1.5,c[0]-5,.65,'bass',.18,-.12);
   [0,.5,1,1.5,2,2.5].forEach((p,k)=>note(start+p,c[k%3]+12,.34,'pizz',.15,k%2?.3:-.3));
   if(b>1){drum(start,'kick',.42);drum(start+1.5,'snare',.65);for(let k=0;k<6;k++)drum(start+k*.5,'shaker',k%3===0?.45:.25);}
   if(b>=2)(homeMel[b%8]).forEach(([p,m,d])=>note(start+p,m+(b>=16?0:0),d,'flute',.20,-.13));
   if(b%2===1&&b>=8)note(start+2.4,c[2]+24,.3,'marimba',.15,.45);
  }else{
   for(let k=0;k<8;k++)note(start+k*.5,c[k%3]+(k%4===3?12:0),.32,'pizz',.20*dyn,k%2?.32:-.32);
   [0,1.5,2,3.5].forEach((p,k)=>{note(start+p,c[0]-12+(k%2?7:0),.42,'bass',.27*dyn);drum(start+p,'kick',.85*dyn);});
   drum(start+1,'snare',1.1*dyn);drum(start+3,'snare',1.1*dyn);
   for(let k=0;k<8;k++)drum(start+k*.5,'shaker',k%2?.5:.7);
   if(b>=2)raceMel[b%8].forEach(([p,m,d])=>{note(start+p,m,d,'horn',.24*dyn,-.1);if(b>=16)note(start+p,m-12,d,'horn',.085,.18);});
   if(b%4===0)drum(start,'cymbal',.7);
   if(b%4===3&&!last)[3,3.33,3.66].forEach((p,k)=>drum(start+p,'tom',.55+k*.18));
  }
 }
 // Separate stereo reflections, subtle enough to keep the rhythm clear.
 const dl=Math.round(.103*SR),dr=Math.round(.137*SR);for(let i=0;i<n;i++){if(i>=dl)left[i]+=right[i-dl]*.12;if(i>=dr)right[i]+=left[i-dr]*.12;}
 let peak=0;for(let i=0;i<n;i++)peak=Math.max(peak,Math.abs(left[i]),Math.abs(right[i]));const gain=.87/peak;
 const buf=Buffer.alloc(44+n*4);buf.write('RIFF');buf.writeUInt32LE(buf.length-8,4);buf.write('WAVEfmt ',8);buf.writeUInt32LE(16,16);buf.writeUInt16LE(1,20);buf.writeUInt16LE(2,22);buf.writeUInt32LE(SR,24);buf.writeUInt32LE(SR*4,28);buf.writeUInt16LE(4,32);buf.writeUInt16LE(16,34);buf.write('data',36);buf.writeUInt32LE(n*4,40);
 for(let i=0;i<n;i++){const fade=Math.min(1,i/(SR*.025),(n-i)/(SR*2.1));buf.writeInt16LE(Math.round(Math.max(-1,Math.min(1,left[i]*gain*fade))*32767),44+i*4);buf.writeInt16LE(Math.round(Math.max(-1,Math.min(1,right[i]*gain*fade))*32767),46+i*4);}
 fs.writeFileSync(path.join(__dirname,file+'.wav'),buf);console.log(file+': '+duration.toFixed(1)+'s, '+tempo+' quarter-note BPM');
}
render('Cloud-Hop-Home-Cloud-Parade-v2',108,24,true);
render('Cloud-Hop-Race-Cloud-Dash-v2',142,24,false);
