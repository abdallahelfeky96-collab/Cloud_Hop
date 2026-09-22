const {AccessToken, TrackSource} = require('livekit-server-sdk');
function authorizeVoice(room, uid, now) {
  return !!(room?.players?.[uid] && room.players[uid].status !== 'out' && room.createdAt + 3600000 > now);
}
async function makeVoiceToken(code, uid, name, key, secret) {
  const token = new AccessToken(key, secret, {identity: uid, name, ttl: '5m'});
  token.addGrant({roomJoin: true, room: code, canPublish: true, canPublishSources: [TrackSource.MICROPHONE], canSubscribe: true, canPublishData: false});
  return token.toJwt();
}
module.exports = {authorizeVoice, makeVoiceToken};
