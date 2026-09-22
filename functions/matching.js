// Pure transaction reducer. Repeated polls cannot match a player twice.
function matchQueue(input, uid, requestId, action, now, name) {
  const state = structuredClone(input || {});
  for (const [id, item] of Object.entries(state)) {
    if (now - item.createdAt > 180000) delete state[id];
  }
  let own = state[uid];
  if (action === 'cancel' && (!own || (own.requestId !== requestId && requestId.localeCompare(own.requestId) > 0))) {
    state[uid] = {requestId, name, createdAt: now, deadline: now, status: 'cancelled'};
    return state;
  }
  if (action === 'start' && (!own || own.requestId !== requestId)) {
    if (own && requestId.localeCompare(own.requestId) < 0) return state;
    own = state[uid] = {requestId, name, createdAt: now, deadline: now + 5000, status: 'waiting'};
  }
  if (!own || own.requestId !== requestId) return state;
  if (own.status === 'matched' || own.status === 'bot' || own.status === 'cancelled') return state;
  if (action === 'cancel' || now >= own.deadline) {
    own.status = action === 'cancel' ? 'cancelled' : 'bot';
    return state;
  }
  const opponent = Object.entries(state).find(([id, p]) => id !== uid && p.status === 'waiting' && p.deadline > now);
  if (opponent) {
    const [otherId, other] = opponent;
    // The request UUID makes room collisions negligible and is never a client room code.
    const code = `M${[requestId, other.requestId].sort().join('').replace(/-/g, '')}`;
    const match = {code, host: uid, createdAt: now, participants: {[uid]: name, [otherId]: other.name}};
    own.status = other.status = 'matched';
    own.match = other.match = match;
  }
  return state;
}
module.exports = {matchQueue};
