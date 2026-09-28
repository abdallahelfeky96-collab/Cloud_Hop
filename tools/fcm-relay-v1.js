// Cloud Hop FCM relay — runs on YOUR OWN server (e.g. the LiveKit VPS).
// This is NOT a Firebase Cloud Function and needs no Blaze plan.
//
// What it does: watches invites, friend requests and match claims in
// Realtime Database and delivers them as background push notifications
// through the FCM HTTP v1 API. The Admin SDK mints its own OAuth2 tokens
// from your service account, so there is nothing to configure besides
// the key file.
//
// Setup on the server:
//   1. npm install (uses tools/package.json)
//   2. Firebase console → Project settings → Service accounts →
//      Generate new private key. Save it on the SERVER ONLY as
//      service-account.json next to this file. NEVER commit it, NEVER
//      paste it into the app, and rotate it if it ever leaves the server.
//   3. GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//      FIREBASE_DATABASE_URL=https://cloud-hop-8732a-default-rtdb.firebaseio.com \
//      node tools/fcm-relay-v1.js
//      (keep it alive with pm2 or systemd)
//
// Payload contract with the app (see lib/services/push.dart):
//   {kind: invite|friend-request|match, code?, from?, fromName?}

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL:
    process.env.FIREBASE_DATABASE_URL ||
    'https://cloud-hop-8732a-default-rtdb.firebaseio.com',
});

const db = admin.database();
const messaging = admin.messaging();

// خريطة لتخزين الإشعارات التي أُرسلت مع توقيت إرسالها
const seenMap = new Map();

// مهلة منع التكرار لنفس الغرفة ونفس المستلم (15 ثانية للاختبار)
const COOLDOWN_MS = 15000; 

// تنظيف الخريطة آلياً كل دقيقة مسحاً للمفاتيح المنتهية
setInterval(() => {
  const now = Date.now();
  for (const [k, timestamp] of seenMap.entries()) {
    if (now - timestamp > COOLDOWN_MS) {
      seenMap.delete(k);
    }
  }
}, 10000);

const key = (...parts) => parts.join('|');

async function sendTo(uid, title, body, data) {
  try {
    const snap = await db.ref(`fcmTokens/${uid}/token`).get();
    const token = snap.val();
    if (typeof token !== 'string' || !token) {
      console.log(`[fcm] SKIP: No token found for ${uid}`);
      return;
    }

    await messaging.send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: { priority: 'high' },
    });
    console.log(`[fcm] SENT -> ${uid}: ${title} (${data.kind || ''})`);
  } catch (e) {
    console.log(`[fcm] ERROR for ${uid}: ${e.message}`);
  }
}

// 1. مراقبة الدعوات للغرف
function watchInvites() {
  const handleInvite = (inviteSnap, recipientUid) => {
    const inv = inviteSnap.val() || {};
    const roomCode = inv.code || inviteSnap.key || '';

    // المفتاح المركب: نوع الإشعار | رقم الغرفة | المستلم
    const k = key('invite', roomCode, recipientUid);
    const now = Date.now();

    // فحص هل نفس الغرفة أُرسلت لنفس المستلم خلال الـ 15 ثانية الأخير؟
    if (seenMap.has(k)) {
      const lastSentTime = seenMap.get(k);
      if (now - lastSentTime < COOLDOWN_MS) {
        console.log(`[fcm] BLOCKED: Duplicate invite for room '${roomCode}' to ${recipientUid} within ${COOLDOWN_MS / 1000}s.`);
        return;
      }
    }

    // تحديث وقت الإرسال أو إضافة المفتاح
    seenMap.set(k, now);

    sendTo(
      recipientUid,
      'Room invitation',
      `${inv.name || 'A friend'} invited you to room ${roomCode}`,
      {
        kind: 'invite',
        code: roomCode,
        fromUid: inv.from || '',
        fromName: inv.name || 'A friend',
        expiresAt: inv.expiresAt || '',
      }
    );
  };

  db.ref('invites').on('child_added', (uidSnap) => {
    const recipientUid = uidSnap.key;
    uidSnap.ref.on('child_added', (inviteSnap) => handleInvite(inviteSnap, recipientUid));
    uidSnap.ref.on('child_changed', (inviteSnap) => handleInvite(inviteSnap, recipientUid));
  });

  db.ref('invites').on('child_changed', (uidSnap) => {
    const recipientUid = uidSnap.key;
    uidSnap.ref.on('child_changed', (inviteSnap) => handleInvite(inviteSnap, recipientUid));
  });
}

// 2. مراقبة طلبات الصداقة
function watchFriendRequests() {
  const handleReq = (reqSnap, targetUid) => {
    const req = reqSnap.val() || {};
    if (req.status !== 'pending' || req.incoming !== true) return;

    const senderUid = reqSnap.key;
    const k = key('friend-request', senderUid, targetUid);
    const now = Date.now();

    if (seenMap.has(k)) {
      if (now - seenMap.get(k) < COOLDOWN_MS) return;
    }

    seenMap.set(k, now);

    sendTo(
      targetUid,
      'Friend request',
      `${req.name || 'Someone'} wants to be your friend`,
      {
        kind: 'friend-request',
        fromUid: senderUid,
        fromName: req.name || 'Someone',
      }
    );
  };

  db.ref('userFriends').on('child_added', (uidSnap) => {
    const targetUid = uidSnap.key;
    uidSnap.ref.on('child_added', (reqSnap) => handleReq(reqSnap, targetUid));
    uidSnap.ref.on('child_changed', (reqSnap) => handleReq(reqSnap, targetUid));
  });
}

// 3. قبول الصداقة
function watchAcceptances() {
  db.ref('userFriends').on('child_changed', (uidSnap) => {
    const owner = uidSnap.key;
    const map = uidSnap.val() || {};
    for (const [other, entry] of Object.entries(map)) {
      if (!entry || entry.status !== 'accepted' || entry.from !== owner) continue;

      const k = key('friend-accepted', owner, other);
      const now = Date.now();
      if (seenMap.has(k) && now - seenMap.get(k) < COOLDOWN_MS) continue;

      seenMap.set(k, now);

      sendTo(owner, 'Friend request accepted', `${entry.name || 'Someone'} is now your friend`, {
        kind: 'friend-accepted',
        fromUid: other,
        fromName: entry.name || 'Someone',
      });
    }
  });
}

// 4. مراقبة المباريات
function watchMatches() {
  db.ref('matchQueue').on('child_changed', (snap) => {
    const node = snap.val() || {};
    if (node.status !== 'matched' || !node.match) return;
    const parts = node.match.participants || {};
    for (const [pid] of Object.entries(parts)) {
      if (pid === snap.key) continue;

      const k = key('match', node.match.code, pid);
      const now = Date.now();
      if (seenMap.has(k) && now - seenMap.get(k) < COOLDOWN_MS) continue;

      seenMap.set(k, now);

      sendTo(pid, 'Challenger found!', `Room ${node.match.code} is starting`, {
        kind: 'match',
        code: node.match.code,
      });
    }
  });
}

watchInvites();
watchFriendRequests();
watchAcceptances();
watchMatches();
console.log('Cloud Hop FCM relay running with 15s smart cooldown logic...');