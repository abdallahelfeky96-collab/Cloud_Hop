/// Shared deterministic policy. A ready player is not an eliminated player.
class MatchDecision {
  final String winner, reason;
  const MatchDecision(this.winner, this.reason);
}

int matchInt(Object? value) => value is num ? value.toInt() : 0;

/// Practice-bot outcome override. A bot simulation freezes the moment play
/// stops, so a still-standing bot must never win by survival alone: when the
/// shared policy reports a rival survival win (or no decision, which means
/// the same thing here — play has stopped with the bot upright), the round
/// falls back to step comparison instead. Returns 1 (self wins), 0 (draw)
/// or -1 (rival wins). Decisive shared verdicts (finish/progress/draw)
/// pass through unchanged.
int decideBotOutcome({
  required MatchDecision? decision,
  required int selfSteps,
  required double rivalSteps,
}) {
  if (decision != null &&
      !(decision.reason == 'survival' && decision.winner == 'rival')) {
    if (decision.winner == 'self') return 1;
    if (decision.winner == '') return 0;
    return -1;
  }
  if (selfSteps > rivalSteps) return 1;
  if (selfSteps == rivalSteps) return 0;
  return -1;
}
MatchDecision? evaluateMatch(
  List<Map<String, dynamic>> players, {
  required int target,
  required bool arcade,
}) {
  if (players.length < 2) return null;
  final finishers =
      players
          .where(
            (p) =>
                !arcade &&
                matchInt(p['step']) >= target &&
                matchInt(p['finishedAt']) > 0,
          )
          .toList()
        ..sort((a, b) {
          final t = matchInt(a['finishedAt'])
              .compareTo(matchInt(b['finishedAt']));
          return t != 0 ? t : a['id'].toString().compareTo(b['id'].toString());
        });
  if (finishers.isNotEmpty)
    return MatchDecision(finishers.first['id'].toString(), 'finish');
  if (players.any((p) => p['status'] == 'ready')) return null;
  // The round continues while anyone is still standing. Eliminated players
  // spectate (or are out); their presence must never end the round, so a
  // lone survivor keeps playing instead of winning by default. Spectators
  // use rock throws to hurry up idle survivors.
  final live = players.where((p) => p['status'] == 'live').toList();
  if (live.isNotEmpty) return null;
  bool progressed(Map<String, dynamic> p) =>
      matchInt(p['step']) > 0 ||
      matchInt(p['score']) > 0 ||
      matchInt(p['movement']) > 0;
  final progress = players.where(progressed).toList();
  if (progress.isEmpty) return const MatchDecision('', 'draw');
  progress.sort((a, b) => matchInt(b['step']).compareTo(matchInt(a['step'])));
  if (progress.length > 1 &&
      matchInt(progress[0]['step']) == matchInt(progress[1]['step']))
    return const MatchDecision('', 'draw');
  return MatchDecision(progress.first['id'].toString(), 'progress');
}
