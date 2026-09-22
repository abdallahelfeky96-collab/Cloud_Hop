const {test} = require('node:test');
const assert = require('node:assert/strict');
const {authorizeVoice, makeVoiceToken} = require('../voice_policy');
test('only active room members can obtain voice access', () => {
 const room = {createdAt: 1000, players: {alice: {status:'ready'}, bob: {status:'out'}}};
 assert.equal(authorizeVoice(room, 'alice', 2000), true);
 assert.equal(authorizeVoice(room, 'bob', 2000), false);
 assert.equal(authorizeVoice(room, 'stranger', 2000), false);
 assert.equal(authorizeVoice(room, 'alice', 3601000), false);
 assert.equal(authorizeVoice(null, 'alice', 2000), false);
});
test('voice token grants only microphone in one room with a short expiry', async () => {
 const jwt = await makeVoiceToken('ABC123', 'alice', 'Alice', 'test-key', 'test-secret-only-for-unit-tests-not-a-real-key');
 const body = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
 assert.equal(body.sub, 'alice'); assert.equal(body.video.room, 'ABC123');
 assert.deepEqual(body.video.canPublishSources, ['microphone']);
 assert.equal(body.video.canPublishData, false);
 assert.ok(body.exp - body.nbf <= 300);
});
