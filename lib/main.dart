import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'game/engine.dart';
import 'game/painter.dart';
import 'services/ads.dart';
import 'services/progress_store.dart';
import 'services/race.dart';
import 'services/social.dart';
import 'services/voice.dart';
import 'game/challenge.dart';
import 'game/swipe_input.dart';
import 'ui/screens.dart';
import 'ui/friends.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
  late final Ticker ticker;
  late final RaceService race;
  final ads = AdService();
  Duration previous = Duration.zero;
  double accumulator = 0;
  final swipeInput = SwipeInput();
  late final PlayerSettings settings;
  late final SocialService social;
  late final VoiceService voice;
  PracticeRival? rival;
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
      onEnd: () {
        unawaited(handleGameOver());
      },
    );
    settings = PlayerSettings(widget.store.prefs);
    social = SocialService(widget.store);
    voice = VoiceService(social)..addListener(raceChanged);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ads.initialize().catchError((Object error) {
          debugPrint("Ads unavailable: $error");
        }),
      );
    });
  }

  void frame(Duration elapsed) {
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
      } else {
        if (_joyHeld) game.holdJump(_joyDir);
        game.tick(1 / 120);
      }
      if (game.mode == PlayMode.playing && rival != null) {
        rival!.tick(1 / 120, game);
        if (rival!.elapsed >= 120) game.end(allowRescue: false);
      }
      accumulator -= 1 / 120;
    }
    if (mounted) setState(() {});
  }

  void raceChanged() {
    if (race.error != null && voice.connected) unawaited(voice.leave());
    if (mounted) setState(() {});
  }

  void checkRace() {
    if (!race.active) return;
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
    if (race.started && !raceStarted) {
      raceStarted = true;
      endAd = false;
      game.start(courseSeed: race.seed);
      Navigator.of(context).popUntil((route) => route.isFirst);
      roomOpen = false;
      rival = null;
      game.say('GO! TWO MINUTES');
    }
    if (raceStarted && race.finished && game.mode != PlayMode.over) {
      game.end(allowRescue: false);
    }
    if (race.error != null && raceStarted) {
      game.say(race.error!);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      clearJoystick();
      game.stopInput();
      swipeInput.end();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached ||
          state == AppLifecycleState.hidden) {
        unawaited(voice.leave());
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
    if (race.active || reviveOffered) {
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
    if (reviveSeconds == null || adsBusy) return;
    cancelRevive();
    adsBusy = true;
    if (mounted) setState(() {});
    final earned = await ads.reward();
    adsBusy = false;
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
    if (rival != null) {
      result = rival!.bestTarget > 0
          ? (game.highest > rival!.bestTarget
                ? 'New personal best!'
                : 'Best target: ${rival!.bestTarget}')
          : (game.highest > rival!.step.floor()
                ? 'You win! · Practice bot'
                : 'Good race! · Practice bot');
    }
    await voice.leave();
    adsBusy = true;
    await widget.store.save(progress);
    await ads.betweenRuns();
    adsBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> startSolo() async {
    if (adsBusy || searching) return;
    if (game.mode == PlayMode.paused && !race.active) {
      game.mode = PlayMode.playing;
      return;
    }
    await Future.wait([voice.leave(), race.leave()]);
    raceStarted = false;
    rival = null;
    result = '';
    endAd = false;
    cancelRevive();
    reviveOffered = false;
    if (settings.choice == GameChoice.quick) {
      await findMatch();
      return;
    }
    if (settings.choice == GameChoice.personalBest) {
      rival = PracticeRival(
        settings.country,
        settings.city,
        bestTarget: math.max(1, progress.best),
      );
    }
    game.start();
  }

  Future<void> goHome() async {
    clearJoystick();
    game.stopInput();
    cancelRevive();
    game.mode = PlayMode.menu;
    rival = null;
    await cancelSearch();
    await Future.wait([voice.leave(), race.leave()]);
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
      unawaited(
        social
            .call('matchmaking', {'action': 'cancel', 'requestId': id})
            .then((match) async {
              // A committed match is left explicitly, so the other racer sees a disconnect.
              if (match['status'] == 'matched') {
                final abandoned = RaceService(widget.store);
                await abandoned.attachMatch(match['code'] as String);
                await abandoned.leave();
                abandoned.dispose();
              }
            })
            .catchError((Object e) {
              debugPrint('Search cleanup: $e');
            }),
      );
    }
  }

  Future<void> findMatch() async {
    final generation = ++searchGeneration;
    searching = true;
    game.mode = PlayMode.menu;
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(0x7fffffff)}';
    searchId = id;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    searchTimer = Timer(const Duration(seconds: 5), () {
      if (generation != searchGeneration || !mounted) return;
      unawaited(cancelSearch());
      startBot();
    });
    Map<String, dynamic> match = {'status': 'waiting'};
    try {
      if (widget.store.cloud) {
        match = await social.call('matchmaking', {
          'action': 'start',
          'requestId': id,
        });
      }
      while (generation == searchGeneration &&
          match['status'] == 'waiting' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (widget.store.cloud) {
          match = await social.call('matchmaking', {
            'action': 'poll',
            'requestId': id,
          });
        }
      }
      if (generation != searchGeneration || !mounted) return;
      if (widget.store.cloud && match['status'] == 'waiting') {
        match = await social.call('matchmaking', {
          'action': 'cancel',
          'requestId': id,
        });
      }
      if (generation != searchGeneration || !mounted) return;
      searchTimer?.cancel();
      searching = false;
      searchId = null;
      if (match['status'] == 'matched') {
        await race.attachMatch(match['code'] as String);
        toast('Challenger found. Starting together…');
      } else {
        startBot();
      }
    } catch (e) {
      if (generation != searchGeneration || !mounted) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (generation != searchGeneration || !mounted) return;
      await cancelSearch();
      startBot();
      toast('Online match unavailable. Practice bot selected.');
    }
  }

  void startBot() {
    searching = false;
    searchId = null;
    endAd = false;
    game.start();
    rival = PracticeRival(settings.country, settings.city, seed: game.seed);
    game.say('${rival!.name} · 2 MINUTES');
  }

  Future<void> showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SettingsSheet(
        settings: settings,
        playerId: widget.store.cloud ? widget.store.uid : null,
        onSave: () async {
          if (widget.store.cloud) await social.register(settings);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void refreshAuthFields() {
    photoUrl = widget.store.photoUrl;
    accountName =
        widget.store.displayName ?? widget.store.email ?? settings.name;
  }

  void attachAuthListener() {
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
      toast(e.toString().replaceFirst('StateError: ', ''));
    }
    googleBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> showProfile() async {
    if (!widget.store.cloud) {
      toast('Connecting to Firebase…');
      if (!await widget.store.retryCloud()) {
        toast('Could not reach Firebase. Check your connection.');
        return;
      }
      attachAuthListener();
      refreshAuthFields();
      if (!mounted) return;
      setState(() {});
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProfileSheet(
        store: widget.store,
        progress: progress,
        onChanged: () {
          photoUrl = widget.store.photoUrl;
          accountName =
              widget.store.displayName ??
              widget.store.email ??
              settings.name;
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
      toast('Connect Firebase to add friends and invite players.');
      return;
    }
    await social.register(settings).catchError((Object e) {
      debugPrint('Profile sync: $e');
    });
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
    if (race.code == null) return;
    try {
      if (voice.connected) {
        await voice.toggle();
      } else {
        await voice.join(race.code!);
      }
    } catch (e) {
      toast('Voice unavailable: $e');
    }
  }

  void clearJoystick() {
    _joyPointers.clear();
    _joyDir = 0;
  }

  void pause() {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> rewardCoins({Ledge? gift}) async {
    if (adsBusy || race.active) return;
    final old = game.mode;
    if (old == PlayMode.playing) game.mode = PlayMode.paused;
    adsBusy = true;
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
      _joyDir = dx < -12 ? -1 : dx > 12 ? 1 : 0;
      return;
    }
    final intent = swipeInput.update(
      details.localPosition.dx * scale,
      details.localPosition.dy * scale,
    );
    if (intent == null) return;
    game.swipe(intent);
    if (settings.sound && intent != Swipe.left && intent != Swipe.right) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
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
            onPressed: action,
            tooltip: label,
            icon: Icon(icon, color: color),
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
                        onPressed: () => Navigator.pop(sheet),
                        icon: const Icon(Icons.close),
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
                    onSelectionChanged: (set) =>
                        setSheet(() => category = set.first),
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
                              : Icons.horizontal_rule;
                          return Card(
                            child: ListTile(
                              leading: Icon(
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
                                onPressed:
                                    equipped ||
                                        (!owned && progress.coins < item.price)
                                    ? null
                                    : () {
                                        if (purchase(progress, item)) {
                                          unawaited(
                                            widget.store.save(progress),
                                          );
                                          setSheet(() {});
                                        }
                                      },
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
                  FilledButton.icon(
                    onPressed: adsBusy
                        ? null
                        : () async {
                            await rewardCoins();
                            if (sheet.mounted) setSheet(() {});
                          },
                    icon: const Icon(Icons.ondemand_video),
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
                    onPressed: () => unawaited(ads.privacy()),
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
      toast(
        'Firebase setup is required for live races. Solo mode works offline.',
      );
      return;
    }
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
                error = e.toString();
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
                      const Text('2–6 players · two minutes · same course'),
                      TextField(
                        controller: name,
                        maxLength: 16,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => action(() => race.enter(name: name.text)),
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
                        onPressed: busy
                            ? null
                            : () => action(
                                () => race.enter(
                                  name: name.text,
                                  joinCode: code.text,
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
                          AnimatedBuilder(
                            animation: voice,
                            builder: (_, _) => ActionOrb(
                              voice.connected && !voice.muted
                                  ? Icons.mic
                                  : Icons.mic_off,
                              voice.connected
                                  ? (voice.muted
                                        ? 'Unmute microphone'
                                        : 'Mute microphone')
                                  : 'Join voice (starts muted)',
                              voice.busy ? null : voiceAction,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Voice is optional. Join muted, then tap the mic to talk.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (voice.connected)
                        TextButton(
                          onPressed: () async {
                            await voice.leave();
                            if (dialog.mounted) setDialog(() {});
                          },
                          child: const Text('Leave voice'),
                        ),
                      ...race.peers.map(
                        (p) => ListTile(
                          dense: true,
                          title: Text(p['name'].toString()),
                          trailing: Text('Step ${p['step']}'),
                        ),
                      ),
                      if (race.startAt == 0 && race.room['host'] == race.uid)
                        FilledButton(
                          onPressed: busy || race.peers.length < 2
                              ? null
                              : () => action(race.start),
                          child: const Text('Start race'),
                        ),
                      if (race.startAt > 0 && !race.started)
                        const Text('Starting together…'),
                      TextButton(
                        onPressed: () => action(() async {
                          await voice.leave();
                          await race.leave();
                          raceStarted = false;
                          game.mode = PlayMode.menu;
                        }),
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
                  onPressed: () => Navigator.pop(dialog),
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
    final peers = race.active
        ? race.peers.where((p) => p['id'] != race.uid).map((p) {
            final target = Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
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
      final others = race.peers.where((p) => p['id'] != race.uid).toList();
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
                                      'Extra life activates automatically once per run.',
                                    ),
                                    badge: game.lifeUsed
                                        ? '✓'
                                        : '${progress.items['life']}',
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
                                  if (race.active) Text('${race.remaining}s'),
                                  if (rival != null)
                                    Text(
                                      '${(120 - rival!.elapsed).ceil().clamp(0, 120)}s · ${rival!.name}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (race.active)
                                    ActionOrb(
                                      voice.connected && !voice.muted
                                          ? Icons.mic
                                          : Icons.mic_off,
                                      'Room microphone',
                                      voice.busy ? null : voiceAction,
                                    ),
                                  if (!race.active)
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
                        if (game.adGift != null &&
                            !game.adGift!.claimed &&
                            !race.active)
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
                        ? '${race.peers.first['name']} wins!'
                        : result,
                    photoUrl: photoUrl,
                    accountName: accountName,
                    oppName: game.mode == PlayMode.over ? oppName : null,
                    oppScore: game.mode == PlayMode.over ? oppScore : null,
                    reviveSeconds: reviveSeconds,
                    isGoogle: widget.store.isGoogle,
                    googleBusy: googleBusy,
                    authBusy: googleBusy,
                    play: startSolo,
                    home: goHome,
                    room: showRace,
                    shop: showShop,
                    friends: showFriends,
                    reward: () => rewardCoins(),
                    preferences: showSettings,
                    profile: showProfile,
                    google: signInFromHome,
                    revive: acceptRevive,
                    decline: declineRevive,
                    cancelSearch: cancelSearch,
                  ),
                if (splash)
                  const ColoredBox(
                    color: Color(0xffedf8f5),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_rounded, color: teal, size: 88),
                          SizedBox(height: 16),
                          Text(
                            'CLOUD HOP',
                            style: TextStyle(
                              color: ink,
                              fontSize: 24,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(authSub?.cancel());
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
    unawaited(widget.store.save(progress));
    super.dispose();
  }
}
