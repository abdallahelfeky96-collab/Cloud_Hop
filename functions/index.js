const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getDatabase} = require('firebase-admin/database');
const {authorizeVoice, makeVoiceToken} = require('./voice_policy');
const {matchQueue} = require('./matching');
initializeApp();
const db = getFirestore();
const voiceKey = defineSecret('LIVEKIT_API_KEY'), voiceSecret = defineSecret('LIVEKIT_API_SECRET'), voiceUrl = defineSecret('LIVEKIT_URL');
const auth = request => { if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.'); return request.auth.uid; };
const clean = (s, n) => typeof s === 'string' ? s.trim().slice(0, n) : '';
const userRef = uid => db.collection('social').doc(uid);
const pair = (a, b) => [a, b].sort().join('_');

exports.profile = onCall(async r => {
  const uid = auth(r), name = clean(r.data.name, 16) || 'Pip';
  await userRef(uid).set({name, country: clean(r.data.country, 40), city: clean(r.data.city, 40)}, {merge: true});
  return {id: uid};
});

exports.friends = onCall(async r => {
  const uid = auth(r), action = r.data.action || 'list', other = clean(r.data.id, 128);
  if (action !== 'list') {
    if (!other || other === uid || !/^[\w-]+$/.test(other)) throw new HttpsError('invalid-argument', 'Enter another player ID.');
    const profile = await userRef(other).get();
    if (!profile.exists) throw new HttpsError('not-found', 'Player ID not found.');
    const ref = db.collection('friendships').doc(pair(uid, other));
    await db.runTransaction(async t => {
      const current = await t.get(ref);
      if (action === 'add') {
        if (!current.exists) t.set(ref, {members: [uid, other], from: uid, status: 'pending', createdAt: FieldValue.serverTimestamp()});
      } else if (action === 'accept' && current.exists && current.data().from === other) {
        t.update(ref, {status: 'accepted'});
      } else if (action === 'remove') t.delete(ref);
      else throw new HttpsError('failed-precondition', 'This request is no longer available.');
    });
  }
  const rows = await db.collection('friendships').where('members', 'array-contains', uid).limit(100).get();
  const friends = await Promise.all(rows.docs.map(async d => {
    const data = d.data(), id = data.members.find(x => x !== uid), p = await userRef(id).get();
    return {id, name: p.data()?.name || 'Player', status: data.status, incoming: data.from !== uid};
  }));
  return {friends};
});

exports.invitations = onCall(async r => {
  const uid = auth(r), action = r.data.action || 'list';
  if (action === 'send') {
    const other = clean(r.data.id, 128), code = clean(r.data.code, 80);
    if (!/^[\w-]+$/.test(other) || !/^[A-Za-z0-9]+$/.test(code)) throw new HttpsError('invalid-argument', 'Invalid invitation.');
    const friendship = await db.collection('friendships').doc(pair(uid, other)).get();
    if (friendship.data()?.status !== 'accepted') throw new HttpsError('permission-denied', 'Add this friend first.');
    const room = (await getDatabase().ref(`rooms/${code}`).get()).val();
    if (!room?.players?.[uid] || room.startAt || room.createdAt + 3600000 < Date.now()) throw new HttpsError('failed-precondition', 'Create a waiting room first.');
    await userRef(other).collection('invites').doc(uid).set({from: uid, name: (await userRef(uid).get()).data()?.name || 'Player', code, expiresAt: Date.now() + 300000});
  } else if (action === 'dismiss') {
    const from = clean(r.data.id, 128);
    if (!/^[\w-]+$/.test(from)) throw new HttpsError('invalid-argument', 'Invalid invitation.');
    await userRef(uid).collection('invites').doc(from).delete();
  }
  const rows = await userRef(uid).collection('invites').limit(100).get();
  return {invitations: rows.docs.map(d => d.data()).filter(d => d.expiresAt > Date.now())};
});

exports.matchmaking = onCall(async r => {
  const uid = auth(r), requestId = clean(r.data.requestId, 80), action = r.data.action;
  if (!/^[a-zA-Z0-9-]{16,80}$/.test(requestId) || !['start', 'poll', 'cancel'].includes(action)) throw new HttpsError('invalid-argument', 'Invalid search.');
  const name = (await userRef(uid).get()).data()?.name || 'Pip';
  const result = await getDatabase().ref('matchQueue').transaction(state => matchQueue(state, uid, requestId, action, Date.now(), name));
  const own = result.snapshot.child(uid).val();
  if (!own || own.requestId !== requestId) return {status: 'cancelled'};
  if (own.status !== 'matched') return {status: own.status};
  const match = own.match;
  await getDatabase().ref(`rooms/${match.code}`).transaction(existing => existing || {
    host: match.host, seed: parseInt(match.code.slice(1, 8), 16) % 2147483647 || 1,
    createdAt: match.createdAt, startAt: Date.now() + 2000,
    players: Object.fromEntries(Object.entries(match.participants).map(([id, name]) => [id, {name, x: 210, y: 623, step: 0, skin: 'pip', status: 'ready', updatedAt: Date.now()}]))
  });
  return {status: 'matched', code: match.code};
});

exports.voiceToken = onCall({secrets: [voiceKey, voiceSecret, voiceUrl]}, async r => {
  const uid = auth(r), code = clean(r.data.code, 80);
  if (!/^[A-Za-z0-9]+$/.test(code)) throw new HttpsError('invalid-argument', 'Invalid room.');
  const room = (await getDatabase().ref(`rooms/${code}`).get()).val();
  if (!authorizeVoice(room, uid, Date.now())) throw new HttpsError('permission-denied', 'Join an active room first.');
  return {url: voiceUrl.value(), token: await makeVoiceToken(code, uid, room.players[uid].name, voiceKey.value(), voiceSecret.value())};
});
