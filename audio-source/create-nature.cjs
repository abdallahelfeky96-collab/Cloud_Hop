// Original synthesized outdoor ambience, not a field recording. No instruments or beat.
const fs=require('fs'),path=require('path');const sr=44100,duration=61,N=sr*duration;
const L=new Float32Array(N),R=new Float32Array(N);let seed=247918;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
let ll=0,lr=0,ml=0,mr=0;
for(let i=0;i<N;i++){
 const t=i/sr,a=rand()*2-1,b=rand()*2-1;
 ll+=.006*(a-ll);lr+=.006*(b-lr);ml+=.095*(a-ml);mr+=.095*(b-mr);
 const gust=.67+.19*Math.sin(t*.41)+.10*Math.sin(t*.173+1.9)+.05*Math.sin(t*1.07);
 const rustle=Math.max(0,Math.sin(t*.61+Math.sin(t*.29)))*.045;
 L[i]=gust*(ll*.36+(ml-ll)*.038)+(ml-ll)*rustle;
 R[i]=gust*(lr*.36+(mr-lr)*.038)+(mr-lr)*rustle;
}
// Irregular, distant chirp groups with curved pitches and slight breath/noise.
for(let at=3;at<duration-3;at+=3.2+rand()*5.5){
 const pan=rand()*1.6-.8,base=1750+rand()*1000,count=2+Math.floor(rand()*3),gain=.022+rand()*.015;
 for(let j=0;j<count;j++){
  const start=at+j*(.17+rand()*.10),d=.08+rand()*.10,off=Math.floor(start*sr);let phase=0;
  const sweep=(j%2?-1:1)*(300+rand()*550);
  for(let k=0;k<d*sr;k++){
   const t=k/sr,u=t/d;phase+=2*Math.PI*(base+sweep*Math.sin(u*Math.PI*.85)+80*Math.sin(t*2*Math.PI*32))/sr;
   const env=Math.sin(Math.PI*u)**1.8;
   const v=gain*env*(Math.sin(phase)+.07*Math.sin(phase*2));
   L[off+k]+=v*Math.sqrt((1-pan)/2);R[off+k]+=v*Math.sqrt((1+pan)/2);
   const echo=off+k+Math.round(.11*sr);if(echo<N){L[echo]+=v*.08*Math.sqrt((1+pan)/2);R[echo]+=v*.08*Math.sqrt((1-pan)/2);}
  }
 }
}
// Crossfade the final second into the first; rotate past the first second.
const cross=sr,M=N-cross,outL=new Float32Array(M),outR=new Float32Array(M);
for(let i=0;i<M;i++){const n=i+cross;let l=L[n],r=R[n];if(i>=M-cross){const k=i-(M-cross),w=k/(cross-1);l=l*(1-w)+L[k]*w;r=r*(1-w)+R[k]*w;}outL[i]=l;outR[i]=r;}
let peak=0,sum=0;for(let i=0;i<M;i++){peak=Math.max(peak,Math.abs(outL[i]),Math.abs(outR[i]));sum+=outL[i]**2+outR[i]**2;}
const gain=Math.min(.024/Math.sqrt(sum/(M*2)),.20/peak),buf=Buffer.alloc(44+M*4);buf.write('RIFF');buf.writeUInt32LE(buf.length-8,4);buf.write('WAVEfmt ',8);buf.writeUInt32LE(16,16);buf.writeUInt16LE(1,20);buf.writeUInt16LE(2,22);buf.writeUInt32LE(sr,24);buf.writeUInt32LE(sr*4,28);buf.writeUInt16LE(4,32);buf.writeUInt16LE(16,34);buf.write('data',36);buf.writeUInt32LE(M*4,40);
for(let i=0;i<M;i++){buf.writeInt16LE(Math.round(outL[i]*gain*32767),44+i*4);buf.writeInt16LE(Math.round(outR[i]*gain*32767),46+i*4);}
fs.writeFileSync(path.join(__dirname,'Cloud-Hop-Wind-Leaves-Birds.wav'),buf);console.log('60-second stereo nature loop; peak '+(20*Math.log10(peak*gain)).toFixed(1)+' dBFS. Synthesized wind, rustle, and sparse birds.');
