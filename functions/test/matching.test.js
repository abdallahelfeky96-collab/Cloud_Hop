const {test} = require('node:test');
const assert = require('node:assert/strict');
const {matchQueue} = require('../matching');
test('two waiting players match once; a third cannot steal the match', () => {
 let s = matchQueue(null, 'a', 'aaaaaaaaaaaaaaaa', 'start', 1000, 'A');
 s = matchQueue(s, 'b', 'bbbbbbbbbbbbbbbb', 'start', 2000, 'B');
 assert.equal(s.a.status, 'matched'); assert.equal(s.a.match.code, s.b.match.code);
 s = matchQueue(s, 'c', 'cccccccccccccccc', 'start', 2100, 'C');
 assert.equal(s.c.status, 'waiting');
});
test('five second deadline excludes stale opponents and yields bot', () => {
 let s = matchQueue(null, 'a', 'aaaaaaaaaaaaaaaa', 'start', 1000, 'A');
 s = matchQueue(s, 'b', 'bbbbbbbbbbbbbbbb', 'start', 6000, 'B');
 assert.equal(s.b.status, 'waiting');
 s = matchQueue(s, 'a', 'aaaaaaaaaaaaaaaa', 'poll', 6000, 'A');
 assert.equal(s.a.status, 'bot');
});
test('cancellation and old request ids cannot overwrite new searches', () => {
 let s = matchQueue(null, 'a', 'aaaaaaaaaaaaaaaa', 'start', 1000, 'A');
 s = matchQueue(s, 'a', 'aaaaaaaaaaaaaaaa', 'cancel', 1100, 'A');
 assert.equal(s.a.status, 'cancelled');
 s = matchQueue(s, 'a', 'bbbbbbbbbbbbbbbb', 'start', 1200, 'A');
 s = matchQueue(s, 'a', 'aaaaaaaaaaaaaaaa', 'cancel', 1300, 'A');
 assert.equal(s.a.status, 'waiting');
});
test('cancelling a committed match returns the match rather than orphaning peer', () => {
 let s = matchQueue(null, 'a', 'aaaaaaaaaaaaaaaa', 'start', 1000, 'A');
 s = matchQueue(s, 'b', 'bbbbbbbbbbbbbbbb', 'start', 2000, 'B');
 s = matchQueue(s, 'a', 'aaaaaaaaaaaaaaaa', 'cancel', 2001, 'A');
 assert.equal(s.a.status, 'matched');
});
test('cancel arriving before start prevents a ghost search', () => {
 let s = matchQueue(null, 'a', 'aaaaaaaaaaaaaaaa', 'cancel', 1000, 'A');
 s = matchQueue(s, 'a', 'aaaaaaaaaaaaaaaa', 'start', 1100, 'A');
 assert.equal(s.a.status, 'cancelled');
 s = matchQueue(s, 'a', 'bbbbbbbbbbbbbbbb', 'cancel', 1200, 'A');
 s = matchQueue(s, 'a', 'bbbbbbbbbbbbbbbb', 'start', 1300, 'A');
 assert.equal(s.a.status, 'cancelled');
});
