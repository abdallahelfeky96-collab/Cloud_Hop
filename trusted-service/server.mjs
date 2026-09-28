import http from 'node:http';
import {initializeApp, applicationDefault} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getDatabase} from 'firebase-admin/database';
import {GoogleAuth} from 'google-auth-library';
import {AccessToken} from 'livekit-server-sdk';
const project = 'cloud-hop-8732a';
initializeApp({credential:applicationDefault(), projectId:project, databaseURL:process.env.FIREBASE_DATABASE_URL || 'https://cloud-hop-8732a-default-rtdb.firebaseio.com'});
const oauth = new GoogleAuth({scopes:['https://www.googleapis.com/auth/firebase.messaging']});
const db = getDatabase();
const fail = (code, message) => { throw Object.assign(new Error(message), {code}); };
const read = async path => (await db.ref(path).get()).val();
http.createServer(async (req,res) => {
  try {
    if(req.method !== 'POST' || !['/voice','/push'].includes(req.url)) fail(404,'Not found');
    const bearer = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if(!bearer) fail(401,'Sign in');
    let uid;
    try { uid = (await getAuth().verifyIdToken(bearer,true)).uid; } catch { fail(401,'Sign in'); }
    let body=''; for await(const chunk of req){body+=chunk; if(body.length>8192)fail(413,'Too large');}
    const input=JSON.parse(body), now=Date.now();
    const rate=await db.ref(`serviceLimits/${uid}/${req.url.slice(1)}`).transaction(v=> now-(v||0)<1000 ? undefined : now);
    if(!rate.committed)fail(429,'Retry later');
    let result;
    if(req.url === '/voice') {
      if(typeof input.room !== 'string' || !/^[A-Z0-9]{6,80}$/.test(input.room))fail(400,'Invalid room');
      const room=await read(`rooms/${input.room}`);
      if(!room?.players?.[uid] || now-room.createdAt>3600000)fail(403,'Join room first');
      const url=process.env.LIVEKIT_URL, key=process.env.LIVEKIT_API_KEY, secret=process.env.LIVEKIT_API_SECRET;
      if(!url?.startsWith('wss://') || !key || !secret)fail(503,'Voice not configured');
      const token=new AccessToken(key,secret,{identity:uid,name:room.players[uid].name,ttl:'10m'});
      token.addGrant({roomJoin:true,room:input.room,canPublish:true,canSubscribe:true,canPublishData:false});
      result={url,token:await token.toJwt()};
    } else {
      const {kind,toUid,code}=input;
      if(typeof toUid !== 'string'|| !/^[\w-]{1,128}$/.test(toUid)||toUid===uid)fail(400,'Invalid recipient');
      const profile=await read(`userFriends/${toUid}/${uid}`);
      let title, text, expiresAt=now+300000;
      if(kind==='friend-request') {
        if(profile?.status!=='pending'||profile?.incoming!==true||profile?.from!==uid)fail(403,'Request missing');
        expiresAt=Number(profile.updatedAt)+86400000;
        title='Friend request';text='You have a new friend request';
      } else if(kind==='invite') {
        const invite=await read(`invites/${toUid}/${uid}`);
        if(!invite||invite.code!==code||invite.expiresAt<=now)fail(403,'Invite expired');
        const room=await read(`rooms/${code}`);
        if(!room?.players?.[uid]||room.startAt||now-room.createdAt>3600000)fail(403,'Room unavailable');
        expiresAt=invite.expiresAt;title='Room invitation';text=`${invite.name || 'A friend'} invited you to play`;
      } else if(kind==='match') {
        if(typeof code !== 'string'|| !/^[A-Z0-9]{6,80}$/.test(code))fail(400,'Invalid room');
        const room=await read(`rooms/${code}`);
        if(!room?.players?.[uid]||!room?.players?.[toUid]||now-room.createdAt>60000)fail(403,'Match unavailable');
        expiresAt=room.createdAt+60000;title='Challenger found';text='Your match is ready';
      } else fail(400,'Invalid kind');
      if(expiresAt<=now)fail(410,'Invite expired');
      const token=await read(`fcmTokens/${toUid}/token`);
      if(typeof token!=='string'||!token) { result={sent:false}; }
      else {
        const auth=await oauth.getClient();
        const response=await auth.request({url:`https://fcm.googleapis.com/v1/projects/${project}/messages:send`,method:'POST',data:{message:{token,notification:{title,body:text},data:{kind,from:uid,...(code?{code}:{}),timestamp:String(now),expiresAt:String(expiresAt)},android:{priority:'high',ttl:`${Math.max(0,Math.floor((expiresAt-now)/1000))}s`,notification:{channel_id:'cloud_hop_invites'}}}}});
        result={sent:!!response.data?.name};
      }
    }
    res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(result));
  } catch(e) {res.writeHead(Number.isInteger(e.code)?e.code:500,{'content-type':'application/json'});res.end(JSON.stringify({error:'Request could not be completed'}));}
}).listen(Number(process.env.PORT||8080));
