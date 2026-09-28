import 'dart:ui' as ui;

import 'ui/cartoon_controls.dart';
import 'ui/character_art.dart';
import 'services/firebase_errors.dart';

import 'dart:async';

import 'ui/ui_sounds.dart';

import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'game/engine.dart';
import 'game/match_result.dart';
import 'game/painter.dart';
import 'services/ads.dart';
import 'services/game_audio.dart';
import 'services/progress_store.dart';
import 'services/race.dart';
import 'services/social.dart';
import 'services/push.dart';
import 'services/voice.dart';
import 'game/challenge.dart';
import 'game/swipe_input.dart';
import 'ui/screens.dart';
import 'ui/friends.dart';

/// Edge-to-edge background with native immersive bars and cutout support.
Future<void> applyGameDisplay() async {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    await const MethodChannel('cloud_hop/fullscreen')
        .invokeMethod<void>('apply');
  } on MissingPluginException {
    /* Non-Android previews stay edge-to-edge. */
  } on PlatformException catch (e) {
    debugPrint('Fullscreen: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await applyGameDisplay();
  final store = ProgressStore(),
      progress = await ProgressStoreLoader.load(store);
  runApp(CloudHop(store: store, progress: progress));
}

class ProgressStoreLoader {
  static Future<Progress> load(ProgressStore store) => store.load();
}

class CloudHop extends StatelessWidget {
  final ProgressStore store;
  final Progress progress;
  const CloudHop({super.key, required this.store, required this.progress});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cloud Hop',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff355f4b)),
      fontFamily: 'sans-serif',
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: const Color(0xff254d43),
          backgroundColor: const Color(0xffffe3a3),
          minimumSize: const Size(56, 56),
          elevation: 3,
          shadowColor: const Color(0xff70958a),
          side: const BorderSide(color: Color(0xff527565), width: 2),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xff254d43),
          backgroundColor: const Color(0xfffff4dc),
          minimumSize: const Size(56, 56),
          side: const BorderSide(color: Color(0xff527565), width: 2),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xfffff8e8)),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xfffff8e8),
      ),
    ),
    home: PlayScreen(store: store, progress: progress),
  );
}

class PlayScreen extends StatefulWidget {
  final ProgressStore store;
  final Progress progress;
  const PlayScreen({super.key, required this.store, required this.progress});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameEngine game;
  ui.Image? controlArtwork, characterArtwork;
  int? resultOutcome;
  late final Ticker ticker;
  late final RaceService race;
  final ads = AdService();
  final gameAudio = GameAudio();
  bool audioForeground = true;
  int audioRound = 0;
  int audioFeedbackRound = -1;
  Duration previous = Duration.zero;
  double accumulator = 0;
  final swipeInput = SwipeInput();
  late final PlayerSettings settings;
  late final SocialService social;
  late final VoiceService voice;
  PracticeRival? rival;
  GameChoice runChoice = GameChoice.classic;
  bool get classicMode =>
      !race.active &&
      (game.mode == PlayMode.menu ? settings.choice : runChoice) ==
          GameChoice.classic;
  bool searching = false, splash = true;
  int searchGeneration = 0;
  String? searchId;
  String result = '';
  Timer? splashTimer, searchTimer, reviveTimer;
  StreamSubscription<User?>? authSub;
  String? photoUrl, accountName;
  bool googleBusy = false;
  int? reviveSeconds;
  bool reviveOffered = false;
  bool dirty = false,
      adsBusy = false,
      endAd = false,
      raceStarted = false,
      roomOpen = false;
  late Timer saveTimer, networkTimer;
  late final PushService push;
  StreamSubscription? _pushLinksSub, _pushMsgsSub, _invitesSub, _friendsSub;
  final _seenPushKeys = <String>{};
  bool _overlayOpen = false, _invitesAttached = false;
  String? _voicePreconnectedFor;
  int _voiceRetryAtMs = 0;
  final peerPositions = <String, Offset>{};
  Progress get progress => widget.progress;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game = GameEngine(
      progress,
      onChanged: () {
        dirty = true;
      },
      onSound: (cue) {
        if (cue == 'start') audioRound++;
        syncAudio();
        gameAudio.cue(cue);
      },
      onEnd: () {
        unawaited(handleGameOver());
      },
    );
    settings = PlayerSettings(widget.store.prefs);
    game.character = settings.character;
    unawaited(
      CharacterArt.animatedBody.then((image) {
        if (mounted) setState(() => characterArtwork = image);
      }),
    );
    social = SocialService(widget.store);
    push = PushService(widget.store);
    voice = VoiceService()..addListener(raceChanged);
    race = RaceService(widget.store)..addListener(raceChanged);
    splashTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => splash = false);
    });
    if (widget.store.cloud) {
      refreshAuthFields();
      attachAuthListener();
      unawaited(
        social.register(settings).catchError((Object e) {
          debugPrint('Profile sync: $e');
        }),
      );
    }
    UiSounds.click = () {
      syncAudio();
      gameAudio.cue('button');
    };
    gameAudio.preload();
    ticker = createTicker(frame)..start();
    saveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (dirty) {
        dirty = false;
        unawaited(widget.store.save(progress));
      }
    });
    networkTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (race.active && raceStarted) unawaited(race.send(game));
    });
    unawaited(
      CartoonAtlas.image
          .then((image) {
            if (mounted) setState(() => controlArtwork = image);
          })
          .catchError((Object error) {
            debugPrint('Control artwork: $error');
          }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ads.initialize().catchError((Object error) {
          debugPrint("Ads unavailable: $error");
        }),
      );
      unawaited(askPermissionsOnce());
      unawaited(_initPush());
    });
  }

  /// One-time microphone + notification prompts on game open, so race voice
  /// and invite alerts work without mid-game popups. Never blocks startup.
  Future<void> askPermissionsOnce() async {
    try {
      if (widget.store.prefs.getBool('permsAsked') == true) return;
      await widget.store.prefs.setBool('permsAsked', true);
      await Permission.microphone.request();
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Permissions: $e');
    }
  }

  /// Push + realtime invite overlays: FCM tap links plus live RTDB watchers
  /// for invites and friend requests while the app is open.
  Future<void> _initPush() async {
    try {
      _pushLinksSub = push.links.listen(_handlePushLink);
      _pushMsgsSub = push.foreground.listen(_showPushDialog);
      await push.init();
      _attachRealtimeOverlays();
    } catch (e) {
      debugPrint('Push overlays: $e');
    }
  }

  /// Deep link from a tapped notification: explicit Accept/Decline pop-ups
  /// for invites, friend requests and accepted requests. Matches auto-join.
  Future<void> _handlePushLink(Map<String, String> data) async {
    if (!mounted || _overlayOpen) return;
    if (expiredPush(data)) {
      toast('Invite Expired');
      return;
    }
    final kind = data['kind'];
    if (kind == 'invite') {
      final code = (data['code'] ?? '').trim();
      if (code.isEmpty) return;
      _inviteDialog(data);
      return;
    }
    if (kind == 'match') {
      final code = (data['code'] ?? '').trim();
      if (code.isEmpty || race.active) return;
      try {
        await race.attachMatch(code);
        raceStarted = false;
        toast('Joining room $code…');
        await showRace();
      } catch (e) {
        debugPrint('Push join failed: $e');
        toast('Could not join room $code.');
      }
      return;
    }
    if (kind == 'friend-request') {
      final from = (data['fromUid'] ?? data['from'] ?? '').trim();
      final name = (data['fromName'] ?? 'Someone').trim();
      if (from.isEmpty) return;
      _friendRequestDialog(from, name);
      return;
    }
    if (kind == 'friend-accepted') {
      final name = (data['fromName'] ?? 'Someone').trim();
      _friendAcceptedDialog(name);
    }
  }

  /// Shared join flow for an accepted invite: validates the room, then joins.
  Future<void> _joinFromInvite(Map<String, String> data) async {
    if (!mounted) return;
    final code = (data['code'] ?? '').trim();
    if (code.isEmpty || race.active) return;
    try {
      if (!RegExp(r'^[A-Z0-9]{6,80}$').hasMatch(code)) {
        toast('Invite Expired');
        return;
      }
      final snapshot = await FirebaseDatabase.instance.ref('rooms/$code').get();
      final room = snapshot.value;
      if (room is! Map || room['result'] != null || room['startAt'] != null) {
        toast('Invite Expired');
        return;
      }
      await race.enter(
        name: settings.name,
        joinCode: code,
        character: settings.character,
      );
      raceStarted = false;
      toast('Joining room $code…');
      await showRace();
    } catch (e) {
      debugPrint('Push join failed: $e');
      toast('Could not join room $code.');
    }
  }

  void _inviteDialog(Map<String, String> data) {
    if (!mounted || _overlayOpen) return;
    final code = (data['code'] ?? '').trim();
    final from = (data['fromName'] ?? 'A friend').trim();
    final fromUid = (data['fromUid'] ?? data['from'] ?? '').trim();
    if (code.isEmpty) return;
    _overlayOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Room invitation'),
        content: Text('$from invited you to room $code.'),
        actions: [
          TextButton(
            onPressed: () async {
              _overlayOpen = false;
              Navigator.pop(dialog);
              if (fromUid.isNotEmpty) {
                try {
                  await social.dismissInvite(fromUid);
                } catch (e) {
                  debugPrint('Decline invite: $e');
                }
              }
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () async {
              _overlayOpen = false;
              Navigator.pop(dialog);
              await _joinFromInvite(data);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((_) => _overlayOpen = false);
  }

  void _friendRequestDialog(String fromUid, String name) {
    if (!mounted || _overlayOpen) return;
    _overlayOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Friend request'),
        content: Text('$name wants to be your friend.'),
        actions: [
          TextButton(
            onPressed: () async {
              _overlayOpen = false;
              Navigator.pop(dialog);
              try {
                await social.removeFriend(fromUid);
              } catch (e) {
                debugPrint('Decline request: $e');
              }
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () async {
              _overlayOpen = false;
              Navigator.pop(dialog);
              try {
                await social.acceptFriend(fromUid);
                toast('$name is now your friend');
              } catch (e) {
                toast('Could not accept request.');
              }
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((_) => _overlayOpen = false);
  }

  void _friendAcceptedDialog(String name) {
    if (!mounted || _overlayOpen) return;
    _overlayOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Friend request accepted'),
        content: Text('$name is now your friend.'),
        actions: [
          TextButton(
            onPressed: () {
              _overlayOpen = false;
              Navigator.pop(dialog);
            },
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              _overlayOpen = false;
              Navigator.pop(dialog);
              await showFriends();
            },
            child: const Text('View friends'),
          ),
        ],
      ),
    ).then((_) => _overlayOpen = false);
  }

  /// Foreground pushes reuse the exact same Accept/Decline pop-ups as taps.
  void _showPushDialog(Map<String, String> data) {
    if (!mounted || _overlayOpen || expiredPush(data)) return;
    final kind = data['kind'];
    if (kind == 'invite') {
      _inviteDialog(data);
      return;
    }
    if (kind == 'friend-request') {
      final from = (data['fromUid'] ?? data['from'] ?? '').trim();
      final name = (data['fromName'] ?? 'Someone').trim();
      if (from.isEmpty) return;
      _friendRequestDialog(from, name);
      return;
    }
    if (kind == 'friend-accepted') {
      _friendAcceptedDialog((data['fromName'] ?? 'Someone').trim());
    }
  }

  /// Live RTDB overlays for invites + friend requests (foreground path that
  /// needs no push transport at all).
  void _attachRealtimeOverlays() {
    if (_invitesAttached || !widget.store.cloud) return;
    _invitesAttached = true;
    final uid = widget.store.uidOrNull;
    if (uid == null) return;
    _invitesSub = FirebaseDatabase.instance.ref('invites/$uid').onValue.listen((
      event,
    ) {
      if (!mounted) return;
      final map = event.snapshot.value as Map? ?? {};
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in map.entries) {
        if (entry.value is! Map) continue;
        final m = Map<String, dynamic>.from(entry.value as Map);
        final code = (m['code'] ?? '').toString();
        final from = (m['from'] ?? entry.key).toString();
        if (code.isEmpty || ((m['expiresAt'] as num?) ?? 0).toInt() <= now) {
          continue;
        }
        final key = 'invite:$from:$code';
        if (_seenPushKeys.contains(key)) continue;
        _seenPushKeys.add(key);
        _showPushDialog({
          'kind': 'invite',
          'code': code,
          'from': from,
          'fromName': (m['name'] ?? 'A friend').toString(),
        });
        break;
      }
    }, onError: (Object e) => debugPrint('Invite watch: $e'));
    _friendsSub = FirebaseDatabase.instance
        .ref('userFriends/$uid')
        .onValue
        .listen((event) {
          if (!mounted) return;
          final map = event.snapshot.value as Map? ?? {};
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final entry in map.entries) {
            if (entry.value is! Map) continue;
            final m = Map<String, dynamic>.from(entry.value as Map);
            if (m['status'] != 'pending' || m['incoming'] != true) continue;
            final from = entry.key.toString();
            final key = 'friend:$from';
            if (_seenPushKeys.contains(key)) continue;
            _seenPushKeys.add(key);
            _showPushDialog({
              'kind': 'friend-request',
              'fromUid': from,
              'fromName': (m['name'] ?? 'Someone').toString(),
            });
            break;
          }
          // Fresh acceptances of MY outgoing requests (updated in the last
          // minute): the other side just accepted — tell me once.
          for (final entry in map.entries) {
            if (entry.value is! Map) continue;
            final m = Map<String, dynamic>.from(entry.value as Map);
            if (m['status'] != 'accepted') continue;
            if (((m['updatedAt'] as num?) ?? 0).toInt() <=
                now - 60000) {
              continue;
            }
            final other = entry.key.toString();
            final key = 'accepted:$other:${m['updatedAt']}';
            if (_seenPushKeys.contains(key)) continue;
            _seenPushKeys.add(key);
            _showPushDialog({
              'kind': 'friend-accepted',
              'fromUid': other,
              'fromName': (m['name'] ?? 'Someone').toString(),
            });
            break;
          }
        }, onError: (Object e) => debugPrint('Friend watch: $e'));
  }

  void syncAudio() => gameAudio.sync(
    playing: game.mode == PlayMode.playing,
    sound: settings.sound,
    foreground: audioForeground,
    ad: adsBusy,
    voice: voice.connected || voice.busy,
  );

  void frame(Duration elapsed) {
    syncAudio();
    if (previous != Duration.zero) {
      accumulator += math.min(
        (elapsed - previous).inMicroseconds / 1000000,
        .05,
      );
    }
    previous = elapsed;
    checkRace();
    while (accumulator >= 1 / 120) {
      if (game.mode == PlayMode.menu) {
        game.attract(1 / 120);
      } else if (game.mode == PlayMode.spectate) {
        game.tickSpectate(1 / 120, _spectateLeaderY());
      } else {
        if (_joyHeld) game.holdJump(_joyDir);
        game.tick(1 / 120);
      }
      // One shared throw pipeline for live play and spectating alike:
      // merge network rocks, test hits while playing, prune stale throws.
      if (race.active &&
          (game.mode == PlayMode.playing ||
              game.mode == PlayMode.spectate)) {
        final selfId = race.uidOrNull ?? '';
        game.syncRocks(race.throwEvents, race.serverNow, selfId);
        if (game.mode == PlayMode.playing) game.checkRockHits(selfId);
        _pruneRocksThrottled();
      }
      if (game.mode == PlayMode.playing && rival != null) {
        rival!.tick(1 / 120, game);
        final opponent = rival!;
        if (runChoice == GameChoice.race &&
            (game.highest >= settings.raceTarget ||
                opponent.step >= settings.raceTarget)) {
          resultOutcome = game.highest >= settings.raceTarget ? 1 : -1;
          game.end(allowRescue: false);
        } else if (runChoice == GameChoice.arcade && opponent.out) {
          resultOutcome =
              game.highest == 0 &&
                  game.movementDistance == 0 &&
                  opponent.step > 0
              ? -1
              : 1;
          game.end(allowRescue: false);
        }
      }
      accumulator -= 1 / 120;
    }
    if (mounted) setState(() {});
  }

  void raceChanged() {
    // Transient database errors do not tear down independent voice transport.
    if (mounted) setState(() {});
  }

  void checkRace() {
    if (!race.active) {
      _voicePreconnectedFor = null;
      return;
    }
    // Shared room pre-connect; mute/unmute avoids reconnecting the room.
    preconnectVoice();
    if (race.error != null && race.room.isEmpty) {
      final message = race.error!;
      unawaited(voice.leave());
      unawaited(race.leave());
      if (raceStarted && game.mode == PlayMode.playing)
        game.end(allowRescue: false);
      raceStarted = false;
      toast(message);
      return;
    }
    // Same-room rematch from the host: everyone auto-starts the new round.
    final rematchRound = race.rematchRound;
    if (rematchRound > _seenRematchRound) {
      _seenRematchRound = rematchRound;
      _applyRematch();
    }
    if (race.started && !raceStarted) {
      raceStarted = true;
      endAd = false;
      runChoice = race.arcade ? GameChoice.arcade : GameChoice.race;
      resultOutcome = null;
      game.character = settings.character;
      game.competitive = true;
      game.allowRewardAds = false;
      game.start(courseSeed: race.effectiveSeed);
      Navigator.of(context).popUntil((route) => route.isFirst);
      roomOpen = false;
      rival = null;
      game.say(
        race.arcade ? 'LAST PLAYER STANDING' : 'FIRST TO ${race.target} STEPS',
      );
    }
    if (raceStarted && !race.finished) _maybeSettleRound();
    if (raceStarted && race.finished) {
      final finishedSelfId = race.uidOrNull;
      resultOutcome = race.winner.isEmpty || finishedSelfId == null
          ? 0
          : race.winner == finishedSelfId
          ? 1
          : -1;
      if (game.mode == PlayMode.spectate) game.mode = PlayMode.over;
      if (game.mode != PlayMode.over)
        game.end(allowRescue: false);
      else if (!endAd && audioFeedbackRound != audioRound)
        unawaited(finishRun());
    }
    if (raceStarted &&
        !race.arcade &&
        game.highest >= race.target &&
        !game.awaitingFinish) {
      game.say('FINISH! Waiting for the result…');
      game.awaitingFinish = true;
      game.stopInput();
    }
    if (race.error != null && raceStarted) {
      game.say(race.error!);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    audioForeground = state == AppLifecycleState.resumed;
    syncAudio();
    if (state == AppLifecycleState.resumed) unawaited(applyGameDisplay());
    if (state != AppLifecycleState.resumed) {
      clearJoystick();
      game.stopInput();
      swipeInput.end();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached ||
          state == AppLifecycleState.hidden) {
        unawaited(voice.leave());
        _voicePreconnectedFor = null;
      }
      if (!race.active && game.mode == PlayMode.playing) {
        game.mode = PlayMode.paused;
      }
      unawaited(widget.store.save(progress));
    }
  }

  /// First game-over per run offers a 5s revive countdown; live races and
  /// repeat game-overs go straight to the regular (interstitial) ad flow.
  Future<void> handleGameOver() async {
    if (race.active && !race.finished) {
      // Publish spectator immediately; never route elimination through results/ads.
      game.enterSpectate();
      await race.send(game);
      if (!mounted) return;
      _maybeSettleRound();
      setState(() {});
      return;
    }
    if (rival != null && resultOutcome == null) {
      final decision = evaluateMatch(
        [
          {
            'id': 'self',
            'step': game.highest,
            'score': game.points,
            'movement': game.movementDistance.round(),
            'status': 'out',
            'finishedAt': game.highest >= settings.raceTarget ? 1 : 0,
          },
          {
            'id': 'rival',
            'step': rival!.step.toInt(),
            'status': rival!.out ? 'out' : 'live',
            'finishedAt': rival!.step >= settings.raceTarget ? 2 : 0,
          },
        ],
        target: settings.raceTarget,
        arcade: runChoice == GameChoice.arcade,
      );
      // A frozen bot cannot win by survival: out-climbing it decides.
      resultOutcome = decideBotOutcome(
        decision: decision,
        selfSteps: game.highest,
        rivalSteps: rival!.step,
      );
    }
    final endedRound = audioRound;
    if (resultOutcome != 1 && resultOutcome != 0) {
      audioFeedbackRound = endedRound;
      await Future<void>.delayed(const Duration(milliseconds: 430));
      if (!mounted || endedRound != audioRound || game.mode != PlayMode.over)
        return;
      syncAudio();
      gameAudio.cue('lose');
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted || endedRound != audioRound || game.mode != PlayMode.over)
        return;
    }
    audioFeedbackRound = -1;
    if (!classicMode || reviveOffered) {
      await finishRun();
      return;
    }
    reviveOffered = true;
    reviveSeconds = 5;
    if (mounted) setState(() {});
    reviveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      reviveSeconds = reviveSeconds! - 1;
      if (reviveSeconds! <= 0) {
        timer.cancel();
        reviveTimer = null;
        reviveSeconds = null;
        unawaited(finishRun());
      }
      if (mounted) setState(() {});
    });
  }

  void cancelRevive() {
    reviveTimer?.cancel();
    reviveTimer = null;
    reviveSeconds = null;
  }

  /// User accepted: play the rewarded ad (typically ~30s). Reward grants the
  /// one-time revive and the run continues; anything else falls through to
  /// the regular skippable interstitial via [finishRun].
  Future<void> acceptRevive() async {
    if (!classicMode || reviveSeconds == null || adsBusy) return;
    cancelRevive();
    adsBusy = true;
    syncAudio();
    if (mounted) setState(() {});
    final earned = await ads.reward();
    await applyGameDisplay();
    adsBusy = false;
    syncAudio();
    if (earned && game.revive()) {
      endAd = false;
      if (mounted) setState(() {});
      return;
    }
    await finishRun();
  }

  /// User declined or timer expired: regular interstitial (skippable after
  /// ~5s) via [finishRun].
  void declineRevive() {
    if (reviveSeconds == null) return;
    cancelRevive();
    unawaited(finishRun());
  }

  Future<void> finishRun() async {
    if (endAd) return;
    endAd = true;
    adsBusy = true;
    syncAudio();
    if (rival != null) {
      resultOutcome ??= runChoice == GameChoice.arcade ? -1 : 2;
      result = resultOutcome == 1 ? 'You win!' : 'Out of attempts';
      if (resultOutcome == -1 &&
          rival!.step >= settings.raceTarget &&
          runChoice == GameChoice.race)
        result = '${rival!.name} wins!';
    }
    await voice.leave();
    adsBusy = true;
    syncAudio();
    await widget.store.save(progress);
    await ads.betweenRuns();
    await applyGameDisplay();
    adsBusy = false;
    syncAudio();
    if (mounted) setState(() {});
  }

  /// "Play again" while in a room stays in the same room: the host starts
  /// a fresh round, everyone else votes and auto-starts on the rematch.
  Future<void> playAgainInRoom() async {
    if (!race.active || !race.finished || adsBusy) return;
    final isHost = race.room['host'] == race.uidOrNull;
    try {
      if (isHost) {
        await race.startRematch();
        toast('Rematch started — same room!');
      } else {
        await race.requestRematch();
        _rematchWaiting = true;
        result = 'Rematch requested · waiting for host';
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Rematch failed: $e');
      toast(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  /// Local standings when the round is decided but no server result exists.
  /// Champion (last standing) or top-step winner, ties draw.
  /// Applies a host rematch broadcast: fresh course, countdown, ready mark.
  void _applyRematch() {
    cancelRevive();
    reviveOffered = false;
    endAd = false;
    result = '';
    resultOutcome = null;
    _rematchWaiting = false;
    _allDecidedAtMs = 0;
    race.finishSent = false;
    peerPositions.clear();
    game.reset(courseSeed: race.effectiveSeed);
    game.mode = PlayMode.menu;
    raceStarted = false;
    game.say('REMATCH! GET READY');
    unawaited(race.publishStatus('ready'));
    if (mounted) setState(() {});
  }

  Future<void> startSolo() async {
    if (adsBusy || searching) return;
    if (game.mode == PlayMode.paused && !race.active) {
      game.mode = PlayMode.playing;
      return;
    }
    if (race.active) {
      await playAgainInRoom();
      return;
    }
    await Future.wait([voice.leave(), race.leave()]);
    _seenRematchRound = 0;
    _rematchWaiting = false;
    _allDecidedAtMs = 0;
    raceStarted = false;
    rival = null;
    result = '';
    resultOutcome = null;
    endAd = false;
    cancelRevive();
    reviveOffered = false;
    runChoice = settings.choice;
    game.character = settings.character;
    game.competitive = runChoice != GameChoice.classic;
    game.allowRewardAds = runChoice == GameChoice.classic;
    if (settings.choice != GameChoice.classic) {
      syncAudio();
      gameAudio.cue('challenge_voice');
      await findMatch();
      return;
    }
    game.start();
  }

  Future<void> goHome() async {
    audioRound++;
    syncAudio();
    gameAudio.cue('exit');
    clearJoystick();
    game.stopInput();
    cancelRevive();
    game.mode = PlayMode.menu;
    rival = null;
    await cancelSearch();
    await Future.wait([voice.leave(), race.leave()]);
    _seenRematchRound = 0;
    _rematchWaiting = false;
    _allDecidedAtMs = 0;
    game.rocks.clear();
    game.rockHits.clear();
    raceStarted = false;
    result = '';
    if (mounted) setState(() {});
  }

  Future<void> cancelSearch() async {
    searchTimer?.cancel();
    searchGeneration++;
    searching = false;
    final id = searchId;
    searchId = null;
    if (id != null && widget.store.cloud) {
      unawaited(() async {
        try {
          final poll = await social.matchPoll();
          await social.matchCancel();
          // A committed match is left explicitly, so the other racer sees a disconnect.
          if (poll['status'] == 'matched') {
            final abandoned = RaceService(widget.store);
            await abandoned.attachMatch(poll['code'] as String);
            await abandoned.leave();
            abandoned.dispose();
          }
        } catch (e) {
          debugPrint('Search cleanup: $e');
        }
      }());
    }
  }

  Future<void> findMatch() async {
    final generation = ++searchGeneration;
    searching = true;
    game.mode = PlayMode.menu;
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(0x7fffffff)}';
    searchId = id;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    searchTimer = Timer(const Duration(seconds: 12), () {
      if (generation != searchGeneration || !mounted || !searching) return;
      unawaited(cancelSearch());
      startBot();
    });
    Map<String, dynamic> match = {'status': 'waiting'};
    try {
      if (!widget.store.cloud) await widget.store.retryCloud();
      if (generation != searchGeneration || !mounted) return;
      attachAuthListener();
      final offlineFromStart = !widget.store.cloud;
      if (offlineFromStart) {
        // Never fail silently: auth death is the #1 reason searches "find
        // nobody". The status carries the underlying reason.
        toast('Offline (${widget.store.status}). Playing practice rival.');
      }
      // Direct client matchmaking: publish, then the smaller uid creates.
      var createdRoom = false;
      Future<void> tryCreate() async {
        final opp = await social.matchScan();
        final myUid = widget.store.uidOrNull;
        if (opp == null || myUid == null || myUid.compareTo(opp['id']!) >= 0) {
          return;
        }
        final mode = settings.choice == GameChoice.arcade ? 'arcade' : 'race';
        final code = await race.createMatchRoom(
          participants: {myUid: settings.name, opp['id']!: opp['name']!},
          mode: mode,
          target: settings.raceTarget,
          skin: progress.skin,
          character: settings.character,
        );
        await social.matchClaimMine(
          code: code,
          peerId: opp['id']!,
          peerName: opp['name']!,
          myName: settings.name,
        );
        createdRoom = true;
        match = {'status': 'matched', 'code': code};
        searchTimer?.cancel();
        // Auto-start together (the old server did this): let the joiner
        // attach, then start for both sides. Abort cleanly if cancelled.
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (generation != searchGeneration || !mounted) {
            await race.leave();
            createdRoom = false;
            match = {'status': 'waiting'};
            return;
          }
        }
        try {
          await race.start();
        } catch (e) {
          debugPrint('Auto-start failed: $e');
          await race.leave();
          createdRoom = false;
          match = {'status': 'waiting'};
        }
      }

      if (widget.store.cloud) {
        await social.matchPublish(
          requestId: id,
          mode: settings.choice == GameChoice.arcade ? 'arcade' : 'race',
          target: settings.raceTarget,
          name: settings.name,
        );
        await tryCreate();
      }
      while (generation == searchGeneration &&
          match['status'] == 'waiting' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (widget.store.cloud) {
          final poll = await social.matchPoll();
          if (poll['status'] == 'matched') {
            match = poll;
            break;
          }
          await tryCreate();
        }
      }
      if (generation != searchGeneration || !mounted) return;
      if (widget.store.cloud && match['status'] == 'waiting') {
        await social.matchCancel();
      }
      if (generation != searchGeneration || !mounted) return;
      searchTimer?.cancel();
      searching = false;
      searchId = null;
      if (match['status'] == 'matched') {
        // The creator already watches its room; joiners attach here.
        if (!createdRoom) {
          await race.attachMatch(match['code'] as String);
        }
        toast('Challenger found. Starting together…');
      } else {
        debugPrint(
          'Matchmaking unpaired: mode=${settings.choice} '
          'target=${settings.raceTarget} cloud=${widget.store.cloud} '
          'seen=${social.lastQueueTotal} '
          'compatible=${social.lastQueueCompatible}',
        );
        startBot();
        if (!offlineFromStart && widget.store.cloud) {
          if (social.lastQueueCompatible > 0) {
            toast('Match failed to start. Playing practice rival.');
          } else if (social.lastQueueTotal > 0) {
            toast(
              'Found ${social.lastQueueTotal} player(s) in other modes. '
              'Playing practice rival.',
            );
          } else {
            toast('No players searching. Playing practice rival.');
          }
        }
      }
    } catch (e) {
      if (generation != searchGeneration || !mounted) return;
      searchTimer?.cancel(); // Preserve the twelve-second fallback without racing its timer.
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (generation != searchGeneration || !mounted) return;
      await cancelSearch();
      startBot();
      debugPrint('Matchmaking failed: $e');
      toast(
        e is OnlineServiceFailure
            ? '${e.message} Playing a practice rival.'
            : 'Online match unavailable. Playing a practice rival.',
      );
    }
  }

  void startBot() {
    runChoice = settings.choice == GameChoice.arcade
        ? GameChoice.arcade
        : GameChoice.race;
    game.competitive = true;
    game.character = settings.character;
    game.allowRewardAds = false;
    searching = false;
    searchId = null;
    endAd = false;
    game.start();
    rival = PracticeRival(settings.country, settings.city, seed: game.seed);
    game.say(
      runChoice == GameChoice.arcade
          ? 'LAST PLAYER STANDING'
          : 'FIRST TO ${settings.raceTarget} STEPS',
    );
  }

  Future<void> showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsSheet(
        settings: settings,
        playerId: widget.store.cloud ? widget.store.uidOrNull : null,
        onSave: () async {
          if (!widget.store.cloud && !await widget.store.retryCloud()) {
            throw OnlineServiceFailure(
              'profile',
              'unavailable',
              widget.store.status,
            );
          }
          await social.register(settings);
          // Retry may have (re)connected: rebind auth state for the avatar.
          attachAuthListener();
          refreshAuthFields();
          if (mounted) setState(() {});
        },
      ),
    );
    game.character = settings.character;
    if (mounted) setState(() {});
  }

  void refreshAuthFields() {
    photoUrl = widget.store.photoUrl;
    accountName =
        widget.store.displayName ?? widget.store.email ?? settings.name;
  }

  void attachAuthListener() {
    unawaited(push.syncToken());
    _attachRealtimeOverlays();
    if (authSub != null) return;
    try {
      authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted) return;
        setState(() {
          photoUrl = user?.photoURL;
          accountName = user?.displayName ?? user?.email ?? settings.name;
        });
      });
    } catch (_) {
      // Firebase unavailable; online features stay gated until retry.
    }
  }

  /// Direct Google sign-in from the home bottom bar. Guests link their
  /// current profile; signed-in users get the profile sheet instead.
  Future<void> signInFromHome() async {
    if (widget.store.isGoogle) {
      await showProfile();
      return;
    }
    if (googleBusy || adsBusy) return;
    googleBusy = true;
    if (mounted) setState(() {});
    try {
      await widget.store.signInWithGoogle();
      await widget.store.mergeRemoteInto(progress);
      attachAuthListener();
      refreshAuthFields();
      unawaited(push.syncToken());
      unawaited(
        social.register(settings).catchError((Object e) {
          debugPrint('Profile sync: $e');
        }),
      );
      toast(
        widget.store.displayName != null
            ? 'Signed in as ${widget.store.displayName}'
            : 'Signed in with Google',
      );
    } catch (e) {
      toast(friendlyOnlineError(e));
    }
    googleBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> showProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProfileSheet(
        store: widget.store,
        progress: progress,
        onChanged: () {
          attachAuthListener();
          photoUrl = widget.store.photoUrl;
          accountName =
              widget.store.displayName ?? widget.store.email ?? settings.name;
          unawaited(
            social.register(settings).catchError((Object e) {
              debugPrint('Profile sync: $e');
            }),
          );
          if (mounted) setState(() {});
        },
      ),
    );
    if (mounted) {
      setState(() {
        photoUrl = widget.store.photoUrl;
        accountName =
            widget.store.displayName ?? widget.store.email ?? settings.name;
      });
    }
  }

  Future<void> showFriends() async {
    if (!widget.store.cloud) {
      if (!await widget.store.retryCloud()) {
        toast(widget.store.status);
        return;
      }
      attachAuthListener();
    }
    try {
      await social.register(settings);
    } catch (e) {
      debugPrint('Friends unavailable: $e');
      toast(friendlyOnlineError(e));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FriendsSheet(
        social: social,
        roomCode: race.active && race.startAt == 0 ? race.code : null,
        join: (code) async {
          await voice.leave();
          await race.enter(name: settings.name, joinCode: code);
          raceStarted = false;
        },
      ),
    );
    if (mounted && race.active && !roomOpen && !race.started) await showRace();
  }

  Future<void> voiceAction() async {
    if (!race.active || rival != null) return;
    if (voice.busy) {
      // A join is still handshaking: queue the unmute instead of dropping
      // the tap, so the mic goes live the instant it connects.
      voice.queueUnmute();
      return;
    }
    final roomCode = race.code;
    if (roomCode == null) return;
    try {
      if (voice.connected) {
        await voice.toggle();
      } else {
        // Unique identity per player: sharing one id kicks others off it.
        // Manual taps join unmuted; background pre-connects stay muted.
        await voice.join(
          roomCode,
          displayName: settings.name,
          identity: widget.store.uidOrNull,
          startMuted: false,
        );
        if (race.code != roomCode || !mounted) {
          await voice.leave();
          return;
        }
        if (!voice.micLive) {
          toast(
            voice.lastError.isEmpty
                ? 'Microphone is still off. Tap the mic to retry.'
                : voice.lastError,
          );
        }
      }
    } catch (e) {
      debugPrint('Voice connection failed: $e');
      final detail = e.toString().replaceFirst('StateError: ', '');
      toast(
        e is OnlineServiceFailure
            ? (e.code == 'not-found'
                  ? 'Voice service is not configured yet. You can keep playing.'
                  : e.message)
            : detail.length > 140
            ? 'Voice failed: ${detail.substring(0, 140)}…'
            : 'Voice failed: $detail',
      );
    }
  }

  void clearJoystick() {
    _joyPointers.clear();
    _joyDir = 0;
  }

  int _lastRockPruneMs = 0, _lastThrowMs = 0, _lastSettleMs = 0;

  /// Client-side round settlement (replaces the server trigger): mirrors
  /// the finish/survival/all-out rules and writes the result first-writer-
  /// wins. Throttled; losers abort silently on the existing result.
  void _maybeSettleRound() {
    final now = race.serverNow;
    if (now - _lastSettleMs < 2000) return;
    _lastSettleMs = now;
    if (race.effectiveStartAt == 0 || now < race.effectiveStartAt + 3000) {
      return;
    }
    unawaited(race.settleResult());
  }

  int _seenRematchRound = 0, _allDecidedAtMs = 0;
  bool _rematchWaiting = false;
  bool get _spectating => game.mode == PlayMode.spectate;

  /// World Y of the leading live player for the spectator camera.
  double _spectateLeaderY() {
    final pool = race.livePeers.isNotEmpty ? race.livePeers : race.peers;
    double? topY;
    var topStep = -1;
    for (final p in pool) {
      final step = ((p['step'] as num?) ?? 0).toInt();
      if (step > topStep) {
        topStep = step;
        topY = (p['y'] as num?)?.toDouble();
      }
    }
    return topY ?? game.camera + 300;
  }

  String? get _spectateLeader {
    final live = race.livePeers;
    if (live.isEmpty) return null;
    var top = live.first;
    for (final p in live) {
      if (((p['step'] as num?) ?? 0) > ((top['step'] as num?) ?? 0)) top = p;
    }
    return top['name'].toString();
  }

  void _pruneRocksThrottled() {
    if (!race.active) return;
    final now = race.serverNow;
    if (now - _lastRockPruneMs < 2000) return;
    _lastRockPruneMs = now;
    unawaited(race.pruneRocks(now));
  }

  /// Spectator tap: drop a boulder from above the tap point.
  void throwRockAt(Offset local, double maxWidth) {
    if (!_spectating || !race.active) return;
    final scale = 420 / maxWidth;
    _spendAndThrow((local.dx * scale).clamp(20.0, 400.0));
  }

  /// Spectator Throw-Rock button: auto-aimed at the current leader.
  void throwRockAtLeader() {
    if (!_spectating || !race.active) return;
    _spendAndThrow(_spectateLeaderX());
  }

  /// Bottom-bar rocks button: throws while spectating, otherwise reports
  /// ammo (rocks are pre-game purchases, never mid-round).
  void throwRockFromBar() {
    if (_spectating && race.active) {
      throwRockAtLeader();
      return;
    }
    final ammo = progress.items['rock'] ?? 0;
    toast(
      ammo > 0
          ? '$ammo rocks ready — spectate a live round to throw'
          : 'Buy rocks pre-game (500 coins each)',
    );
  }

  double _spectateLeaderX() {
    final live = race.livePeers;
    Map<String, dynamic>? top;
    for (final p in live.isEmpty ? race.peers : live) {
      if (top == null ||
          ((p['step'] as num?) ?? 0) > ((top['step'] as num?) ?? 0)) {
        top = p;
      }
    }
    return ((top?['x'] as num?)?.toDouble() ?? 210).clamp(20.0, 400.0);
  }

  /// Rock economy: every throw (tap or button shower) spends exactly one
  /// rock ammo, bought in the shop for 500 coins — before or mid-round.
  /// No coins fallback: throws must be purchased first.
  bool _throwBusy = false;
  Future<void> _spendAndThrow(double worldX) async {
    final now = race.serverNow;
    if (_throwBusy ||
        !_spectating ||
        !race.active ||
        race.finished ||
        now - _lastThrowMs < 800)
      return;
    final ammo = progress.items['rock'] ?? 0;
    if (ammo <= 0) {
      toast('Out of rocks — buy them in the shop before the next round');
      return;
    }
    _throwBusy = true;
    progress.items['rock'] = ammo - 1;
    dirty = true;
    final key = await race.sendRock(
      x0: worldX < 210 ? -20 : 440,
      y0: game.camera - 40,
      vx: worldX < 210 ? 170 : -170,
      vy: 420,
      t0: now,
    );
    if (key == null) {
      progress.items['rock'] = ammo;
      toast('Throw failed. Rock refunded.');
    } else {
      _lastThrowMs = now;
    }
    await widget.store.save(progress);
    _throwBusy = false;
    if (mounted) setState(() {});
  }

  void pause() {
    if (!classicMode) return;
    clearJoystick();
    game.stopInput();
    if (race.active) {
      game.say('LIVE RACE CONTINUES');
      return;
    }
    game.mode = PlayMode.paused;
  }

  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> rewardCoins({Ledge? gift}) async {
    if (!classicMode || adsBusy) return;
    final old = game.mode;
    if (old == PlayMode.playing) game.mode = PlayMode.paused;
    adsBusy = true;
    syncAudio();
    game.stopInput();
    final earned = await ads.reward();
    if (earned) {
      if (gift != null && !gift.claimed) {
        game.grantGift(gift);
      } else {
        progress.coins += 100;
      }
      await widget.store.save(progress);
      toast(gift == null ? '100 coins added' : 'Gift collected');
    } else {
      toast('No reward earned. Ad may still be loading or was closed early.');
    }
    adsBusy = false;
    syncAudio();
    if (old == PlayMode.playing) game.mode = old;
    if (mounted) setState(() {});
  }

  final _joyPointers = <int>{};
  double _joyStartX = 0;
  int _joyDir = 0;
  bool get _joyHeld => _joyPointers.isNotEmpty;
  bool get _joystickMode => settings.control == ControlMode.joystick;

  void _joyDown(PointerDownEvent e, double width) {
    if (!_joystickMode || game.mode != PlayMode.playing) return;
    _joyPointers.add(e.pointer);
    if (_joyPointers.length == 1) {
      _joyStartX = e.localPosition.dx * (420 / width);
      _joyDir = 0;
    }
  }

  void _joyEnd(int pointer) {
    if (_joyPointers.remove(pointer) && _joyPointers.isEmpty) {
      _joyDir = 0;
      game.stopInput();
    }
  }

  void gesture(DragUpdateDetails details) {
    if (game.mode != PlayMode.playing) return;
    final scale = 420 / MediaQuery.sizeOf(context).width;
    if (_joystickMode) {
      final dx = details.localPosition.dx * scale - _joyStartX;
      _joyDir = dx < -12
          ? -1
          : dx > 12
          ? 1
          : 0;
      return;
    }
    final intent = swipeInput.update(
      details.localPosition.dx * scale,
      details.localPosition.dy * scale,
    );
    if (intent == null) return;
    game.swipe(intent);
  }

  Widget circle(
    IconData icon,
    String label,
    VoidCallback? action, {
    String? count,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton.filledTonal(
            onPressed: UiSounds.wrap(action),
            tooltip: label,
            icon: CartoonIcon(icon, color: color),
            iconSize: 28,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .82),
              fixedSize: const Size(60, 60),
            ),
          ),
          if (count != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xff355f4b),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> showShop() async {
    // Shop is pre-game only: nothing can be bought mid-round.
    if (race.active) {
      toast('Leave the race before opening the shop.');
      return;
    }
    if (game.mode == PlayMode.playing) pause();
    String category = 'items';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          return FractionallySizedBox(
            heightFactor: .86,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Sky shop',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text('◉ ${progress.coins}'),
                      IconButton(
                        onPressed: UiSounds.wrap(() => Navigator.pop(sheet)),
                        icon: const CartoonIcon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    '10 steps = 1 coin · Land a flip = 10 coins',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'items', label: Text('Helpers')),
                      ButtonSegment(value: 'skins', label: Text('Skins')),
                      ButtonSegment(value: 'skies', label: Text('Skies')),
                    ],
                    selected: {category},
                    onSelectionChanged: UiSounds.change(
                      (set) => setSheet(() => category = set.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: products.where((p) => p.category == category).map(
                        (item) {
                          final owned = category == 'skins'
                              ? progress.skins.contains(item.id)
                              : category == 'skies'
                              ? progress.skies.contains(item.id)
                              : false;
                          final equipped = category == 'skins'
                              ? progress.skin == item.id
                              : category == 'skies'
                              ? progress.sky == item.id
                              : false;
                          final icon = category == 'skins'
                              ? Icons.face
                              : category == 'skies'
                              ? Icons.cloud
                              : item.id == 'rocket'
                              ? Icons.rocket_launch
                              : item.id == 'life'
                              ? Icons.favorite
                              : item.id == 'rock'
                              ? Icons.circle
                              : Icons.horizontal_rule;
                          return Card(
                            child: ListTile(
                              leading: CartoonIcon(
                                icon,
                                color: category == 'skins'
                                    ? skinColor(item.id)
                                    : const Color(0xff588369),
                              ),
                              title: Text(item.name),
                              subtitle: Text(
                                item.description +
                                    (category == 'items'
                                        ? '\nIn bag: ${progress.items[item.id]}'
                                        : ''),
                              ),
                              trailing: TextButton(
                                onPressed: UiSounds.wrap(
                                  equipped ||
                                          (!owned &&
                                              progress.coins < item.price)
                                      ? null
                                      : () {
                                          if (purchase(progress, item)) {
                                            unawaited(
                                              widget.store.save(progress),
                                            );
                                            setSheet(() {});
                                          }
                                        },
                                ),
                                child: Text(
                                  equipped
                                      ? 'Equipped'
                                      : owned
                                      ? 'Equip'
                                      : '${item.price} ◉',
                                ),
                              ),
                            ),
                          );
                        },
                      ).toList(),
                    ),
                  ),
                  if (classicMode)
                    FilledButton.icon(
                      onPressed: UiSounds.wrap(
                        adsBusy
                            ? null
                            : () async {
                                await rewardCoins();
                                if (sheet.mounted) setSheet(() {});
                              },
                      ),
                      icon: const CartoonIcon(Icons.ondemand_video),
                      label: const Text('Watch ad · +100 coins'),
                    ),
                  if (AppConfig.testAds)
                    const Text(
                      'Google test ads · no live revenue',
                      style: TextStyle(fontSize: 10),
                    ),
                  Text(
                    widget.store.status,
                    style: const TextStyle(fontSize: 10),
                  ),
                  TextButton(
                    onPressed: UiSounds.wrap(() => unawaited(ads.privacy())),
                    child: const Text('Ad privacy choices'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> showRace() async {
    if (!widget.store.cloud) {
      if (!await widget.store.retryCloud()) {
        toast(widget.store.status);
        return;
      }
      attachAuthListener();
    }
    if (!mounted) return;
    if (game.mode == PlayMode.playing && !race.active) pause();
    final name = TextEditingController(text: settings.name),
        code = TextEditingController();
    String error = '';
    bool busy = false;
    roomOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialog) => AnimatedBuilder(
          animation: race,
          builder: (context, child) {
            Future<void> action(Future<void> Function() work) async {
              if (busy) return;
              setDialog(() => busy = true);
              try {
                await work();
                error = '';
              } catch (e) {
                error = firebaseProblem(e, service: 'Room connection');
              }
              if (dialog.mounted) setDialog(() => busy = false);
            }

            return AlertDialog(
              title: const Text('Live challenge'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!race.active) ...[
                      Text(
                        settings.choice == GameChoice.arcade
                            ? 'Arcade · last player standing · 3 attempts each'
                            : 'Race · ${settings.raceTarget} steps · 3 attempts each',
                      ),
                      TextField(
                        controller: name,
                        maxLength: 16,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      FilledButton(
                        onPressed: UiSounds.wrap(
                          busy
                              ? null
                              : () => action(
                                  () => race.enter(
                                    name: name.text,
                                    mode: settings.choice == GameChoice.arcade
                                        ? 'arcade'
                                        : 'race',
                                    target: settings.raceTarget,
                                    character: settings.character,
                                  ),
                                ),
                        ),
                        child: const Text('Create room'),
                      ),
                      TextField(
                        controller: code,
                        maxLength: 6,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Room code',
                        ),
                      ),
                      TextButton(
                        onPressed: UiSounds.wrap(
                          busy
                              ? null
                              : () => action(
                                  () => race.enter(
                                    name: name.text,
                                    joinCode: code.text,
                                    character: settings.character,
                                  ),
                                ),
                        ),
                        child: const Text('Join room'),
                      ),
                    ] else ...[
                      SelectableText(
                        race.code!,
                        style: const TextStyle(
                          fontSize: 30,
                          letterSpacing: 4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ActionOrb(Icons.copy, 'Copy room invitation', () {
                            Clipboard.setData(
                              ClipboardData(
                                text: 'Join my Cloud Hop room: ${race.code}',
                              ),
                            );
                            toast('Room invitation copied');
                          }),
                          ActionOrb(
                            Icons.person_add,
                            'Invite friends',
                            showFriends,
                          ),
                        ],
                      ),
                      const Text(
                        'Use the microphone at the bottom-right during gameplay to talk or mute.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (voice.connected)
                        TextButton(
                          onPressed: UiSounds.wrap(() async {
                            await voice.leave();
                            if (dialog.mounted) setDialog(() {});
                          }),
                          child: const Text('Leave voice'),
                        ),
                      ...race.peers.map(
                        (p) => ListTile(
                          dense: true,
                          title: Text(p['name'].toString()),
                          trailing: Text('Step ${p['step']}'),
                        ),
                      ),
                      if (race.startAt == 0 &&
                          race.room['host'] == race.uidOrNull)
                        FilledButton(
                          onPressed: UiSounds.wrap(
                            busy || race.peers.length < 2
                                ? null
                                : () {
                                    syncAudio();
                                    gameAudio.cue('challenge_voice');
                                    action(race.start);
                                  },
                          ),
                          child: const Text('Start race'),
                        ),
                      if (race.startAt > 0 && !race.started)
                        const Text('Starting together…'),
                      TextButton(
                        onPressed: UiSounds.wrap(
                          () => action(() async {
                            await voice.leave();
                            await race.leave();
                            raceStarted = false;
                            game.mode = PlayMode.menu;
                          }),
                        ),
                        child: const Text('Leave room'),
                      ),
                    ],
                    if (error.isNotEmpty)
                      Text(error, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: UiSounds.wrap(() => Navigator.pop(dialog)),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      ),
    );
    roomOpen = false;
    name.dispose();
    code.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = game.mode == PlayMode.playing;
    final reduced = MediaQuery.of(context).disableAnimations;
    final selfId = race.uidOrNull;
    final peers = race.active
        ? race.peers.where((p) => p['id'] != selfId).map((p) {
            final target = Offset(
              (p['x'] as num?)?.toDouble() ?? 210.0,
              (p['y'] as num?)?.toDouble() ?? 623.0,
            );
            final position = Offset.lerp(
              peerPositions[p['id']] ?? target,
              target,
              .25,
            )!;
            peerPositions[p['id']] = position;
            return {...p, 'x': position.dx, 'y': position.dy};
          }).toList()
        : <Map<String, dynamic>>[];
    if (rival != null) peers.add(rival!.peer);
    // Post-game face-off scores: best opponent, else practice bot, else solo.
    String? oppName;
    int? oppScore;
    if (race.active) {
      final others = race.peers.where((p) => p['id'] != selfId).toList();
      others.sort(
        (a, b) => a['id'] == race.winner
            ? -1
            : b['id'] == race.winner
            ? 1
            : 0,
      );
      if (others.isNotEmpty) {
        oppName = others.first['name'].toString();
        oppScore = ((others.first['step'] as num?) ?? 0).toInt();
      }
    } else if (rival != null) {
      oppName = rival!.name;
      oppScore = rival!.step.floor();
    }
    return PopScope(
      canPop: game.mode == PlayMode.menu && !race.active && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(goHome());
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, box) {
            game.viewHeight = box.maxHeight / (box.maxWidth / 420);
            return Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) => _joyDown(e, box.maxWidth),
                  onPointerUp: (e) => _joyEnd(e.pointer),
                  onPointerCancel: (e) => _joyEnd(e.pointer),
                  child: GestureDetector(
                    dragStartBehavior: DragStartBehavior.down,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      if (game.mode == PlayMode.spectate) {
                        // Use the explicit paid Throw Rock button only.
                      }
                    },
                    onPanStart: (d) {
                      if (_joystickMode) return;
                      final scale = 420 / box.maxWidth;
                      swipeInput.begin(
                        d.localPosition.dx * scale,
                        d.localPosition.dy * scale,
                      );
                    },
                    onPanUpdate: gesture,
                    onPanEnd: (_) => swipeInput.end(),
                    onPanCancel: swipeInput.end,
                    child: CustomPaint(
                      painter: GamePainter(
                        game,
                        controls: controlArtwork,
                        characters: characterArtwork,
                        peers: peers,
                        reducedMotion: reduced,
                      ),
                    ),
                  ),
                ),
                if (playing)
                  SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  ActionOrb(
                                    Icons.arrow_back_rounded,
                                    'Back to home',
                                    goHome,
                                  ),
                                  const Spacer(),
                                  ActionOrb(
                                    Icons.rocket_launch_rounded,
                                    'Rocket',
                                    progress.items['rocket']! > 0
                                        ? () => game.use('rocket')
                                        : null,
                                    badge: '${progress.items['rocket']}',
                                  ),
                                  ActionOrb(
                                    Icons.horizontal_rule_rounded,
                                    'Trampoline',
                                    progress.items['spring']! > 0
                                        ? () => game.use('spring')
                                        : null,
                                    badge: '${progress.items['spring']}',
                                  ),
                                  ActionOrb(
                                    Icons.favorite_rounded,
                                    'Automatic extra life',
                                    () => toast(
                                      classicMode
                                          ? 'Each fall uses one owned life, until none remain.'
                                          : 'Everyone starts with three attempts. Inventory lives are not spent.',
                                    ),
                                    badge: '${game.availableLives}',
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Text(
                                    'STEP ${game.highest} · LV ${game.level}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: ink,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (race.active)
                                    Text(
                                      race.arcade
                                          ? 'Last standing'
                                          : 'Goal ${race.target}',
                                    ),
                                  if (rival != null)
                                    Text(
                                      runChoice == GameChoice.arcade
                                          ? '${rival!.name} · Arcade'
                                          : 'Goal ${settings.raceTarget}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (classicMode)
                                    ActionOrb(
                                      Icons.pause_rounded,
                                      'Pause',
                                      pause,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (game.messageTime > 0)
                          Positioned(
                            top: 154,
                            left: 18,
                            right: 18,
                            child: Text(
                              game.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: ink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (race.active)
                          Positioned(
                            bottom: 24,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ActionOrb(
                                  voice.connected && !voice.muted
                                      ? Icons.mic
                                      : Icons.mic_off,
                                  voice.connected
                                      ? (voice.muted
                                            ? 'Unmute microphone'
                                            : 'Mute microphone')
                                      : 'Turn microphone on',
                                  voice.busy ? null : voiceAction,
                                  badge: voice.busy
                                      ? '…'
                                      : voice.connected
                                      ? (voice.muted ? 'OFF' : 'ON')
                                      : null,
                                ),
                                ActionOrb(
                                  voice.speaker
                                      ? Icons.volume_up
                                      : Icons.volume_off,
                                  voice.speaker
                                      ? 'Speaker on'
                                      : 'Speaker off (earpiece)',
                                  voice.busy
                                      ? null
                                      : () => voice.setSpeaker(!voice.speaker),
                                  badge: voice.connected
                                      ? (voice.speaker ? 'ON' : 'OFF')
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        if (game.adGift != null &&
                            !game.adGift!.claimed &&
                            classicMode)
                          Positioned(
                            bottom: 24,
                            right: 16,
                            child: ActionOrb(
                              Icons.card_giftcard,
                              'Watch ad for gift',
                              () => rewardCoins(gift: game.adGift),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!playing)
                  HomeOverlay(
                    mode: game.mode,
                    settings: settings,
                    coins: progress.coins,
                    steps: game.highest,
                    earned: game.runCoins,
                    busy: adsBusy || (race.active && !raceStarted),
                    searching: searching,
                    result:
                        race.active && race.finished && race.peers.isNotEmpty
                        ? (race.winner.isEmpty
                              ? 'Draw!'
                              : '${race.winnerName} wins!')
                        : result,
                    photoUrl: photoUrl,
                    accountName: accountName,
                    oppName: game.mode == PlayMode.over ? oppName : null,
                    oppScore: game.mode == PlayMode.over ? oppScore : null,
                    outcome: race.active && !race.finished ? 2 : resultOutcome,
                    reviveSeconds: reviveSeconds,
                    isGoogle: widget.store.isGoogle,
                    googleBusy: googleBusy,
                    authBusy: googleBusy,
                    play: () {
                      startSolo();
                    },
                    home: goHome,
                    room: () {
                      showRace();
                    },
                    shop: () {
                      showShop();
                    },
                    friends: () {
                      showFriends();
                    },
                    showRewards: classicMode,
                    reward: () {
                      rewardCoins();
                    },
                    preferences: () {
                      showSettings();
                    },
                    profile: () {
                      showProfile();
                    },
                    google: () {
                      signInFromHome();
                    },
                    revive: acceptRevive,
                    decline: declineRevive,
                    spectateLeader: _spectateLeader,
                    spectateHost:
                        race.active && race.room['host'] == race.uidOrNull,
                    spectateVotes: race.active ? race.rematchVotes : 0,
                    rockAmmo: progress.items['rock'] ?? 0,
                    inRace: race.active,
                    throwRock: throwRockFromBar,
                    rematchWaiting: _rematchWaiting,
                    rematch: race.finished ? playAgainInRoom : null,
                    voiceLabel: voice.connected
                        ? (voice.muted ? 'Unmute' : 'Mute')
                        : 'Join voice',
                    voiceBadge: voice.busy
                        ? '…'
                        : voice.connected
                        ? (voice.muted ? 'OFF' : 'ON')
                        : null,
                    voiceToggle: voice.busy ? null : voiceAction,
                    cancelSearch: cancelSearch,
                  ),
                if (splash)
                  const ColoredBox(
                    color: Color(0xffedf8f5),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CartoonIcon(
                            Icons.cloud_rounded,
                            color: teal,
                            size: 88,
                          ),
                          SizedBox(height: 16),
                          CloudHopLogo(height: 100),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Pre-connects voice muted to reduce delay; audio/network latency still applies.
  /// Silent: failures surface when the user taps the mic instead.
  void preconnectVoice() {
    final code = race.code;
    if (code == null ||
        !race.active ||
        voice.connected ||
        voice.busy ||
        DateTime.now().millisecondsSinceEpoch < _voiceRetryAtMs) {
      return;
    }
    _voicePreconnectedFor = code;
    unawaited(
      voice
          .join(
            code,
            displayName: settings.name,
            identity: widget.store.uidOrNull,
          )
          .catchError((Object e) {
            debugPrint('Voice pre-connect: $e');
            _voicePreconnectedFor = null;
            _voiceRetryAtMs = DateTime.now().millisecondsSinceEpoch + 30000;
          }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(authSub?.cancel());
    unawaited(push.dispose());
    unawaited(_pushLinksSub?.cancel());
    unawaited(_pushMsgsSub?.cancel());
    unawaited(_invitesSub?.cancel());
    unawaited(_friendsSub?.cancel());
    cancelRevive();
    splashTimer?.cancel();
    searchGeneration++;
    unawaited(cancelSearch());
    voice.removeListener(raceChanged);
    unawaited(voice.leave().then((_) => voice.dispose()));
    ticker.dispose();
    saveTimer.cancel();
    networkTimer.cancel();
    race.removeListener(raceChanged);
    race.dispose();
    ads.dispose();
    UiSounds.click = null;
    unawaited(gameAudio.dispose());
    unawaited(widget.store.save(progress));
    super.dispose();
  }
}
