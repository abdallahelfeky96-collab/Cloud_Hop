import '../lib/game/engine.dart';
import '../lib/game/match_result.dart';
void check(bool value,String label){if(!value)throw StateError(label);print('PASS $label');}
Map<String,dynamic> p(String id,int step,String status,{int finish=0,int movement=0})=>{'id':id,'step':step,'status':status,'finishedAt':finish,'movement':movement};
void main(){
  check(evaluateMatch([p('idle',0,'live'),p('active',300,'out',finish:100)],target:300,arcade:false)?.winner=='active','finish beats AFK and fall');
  check(evaluateMatch([p('a',300,'out',finish:80),p('b',300,'finished',finish:100)],target:300,arcade:false)?.winner=='a','first finish wins after elimination');
  check(evaluateMatch([p('a',0,'ready'),p('b',0,'live')],target:300,arcade:true)==null,'initial lobby cannot settle');
  check(evaluateMatch([p('idle',0,'live'),p('active',80,'spectator')],target:300,arcade:true)==null,'lone survivor keeps the round alive, spectators watch');
  check(evaluateMatch([p('a',80,'live'),p('b',90,'spectator')],target:300,arcade:true)==null,'elimination never ends the round early');
  check(evaluateMatch([p('a',80,'out'),p('b',90,'spectator')],target:300,arcade:true)?.winner=='b','all-out settles by highest steps');
  check(evaluateMatch([p('a',50,'out'),p('b',50,'spectator')],target:300,arcade:true)?.winner=='','all-out tie draws');
  check(evaluateMatch([p('a',80,'out'),p('b',90,'out')],target:300,arcade:true)?.winner=='b','first fall does not decide, steps do');
  check(evaluateMatch([p('a',1,'live'),p('b',20,'live')],target:300,arcade:false)==null,'two racers continue');
  check(evaluateMatch([p('a',0,'out'),p('b',0,'spectator')],target:300,arcade:true)?.winner=='','zero progress all eliminated draws');
  // Frozen-bot override: a standing rival keeps the shared round alive
  // (null), so the bot path falls back to steps instead of a survival win.
  MatchDecision? frozen(int self,int rival)=>evaluateMatch([p('self',self,'out'),p('rival',rival,'live')],target:300,arcade:true);
  check(frozen(350,150)==null,'standing rival keeps the round alive, no survival win');
  check(decideBotOutcome(decision:frozen(350,150),selfSteps:350,rivalSteps:150)==1,'out-climbed frozen bot wins');
  check(decideBotOutcome(decision:frozen(150,150),selfSteps:150,rivalSteps:150)==0,'equal steps draw');
  check(decideBotOutcome(decision:frozen(40,200),selfSteps:40,rivalSteps:200)==-1,'lower steps lose');
  check(decideBotOutcome(decision:frozen(0,150),selfSteps:0,rivalSteps:150)==-1,'AFK still loses');
  check(decideBotOutcome(decision:const MatchDecision('self','progress'),selfSteps:10,rivalSteps:900)==1,'decisive self verdict passes through');
  check(decideBotOutcome(decision:const MatchDecision('', 'draw'),selfSteps:10,rivalSteps:900)==0,'decisive draw passes through');
  check(decideBotOutcome(decision:null,selfSteps:200,rivalSteps:100)==1,'undecided round falls back to steps');
  final game=GameEngine(Progress())..start(courseSeed:123);
  for(var i=0;i<2400;i++){game.tick(1/120);}
  check(game.rocks.isEmpty,'no automatic rocks');
  final events=[{'id':'paid','by':'spectator','t0':10000,'x0':-20,'y0':game.camera-40,'vx':170,'vy':420,'count':10,'seed':44}];
  game.syncRocks(events,10000,'spectator');
  check(game.rocks.length==10,'paid event generates complete cascade including sender');
  check(game.rocks.every((r)=>r.vx>0&&r.vy>0&&r.scale>=.3&&r.scale<=2.5),'diagonal scaled meteors');
  game.syncRocks(events,10100,'other');
  check(game.rocks.length==10,'event deduplicated');
  for(var i=0;i<1200;i++){game.stepRocks(1/120);}
  check(game.rocks.isEmpty,'rocks culled at boundaries');
  game.syncRocks(events,15000,'other');
  check(game.rocks.isEmpty,'culled shower does not respawn');
}
