import 'dart:async';

import 'lang.dart';
import 'ui_sounds.dart';
import 'cartoon_controls.dart';
import 'character_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/challenge.dart';
import '../game/engine.dart';
import '../services/progress_store.dart';
import '../services/social.dart';

const ink = Color(0xff213c4c), teal = Color(0xff207e78);
const modeNames = ['Classic', 'Arcade', 'Race'];
const modeDescriptions = [
  'Climb at your own pace',
  'Last player standing · three attempts each',
  'First to the finish · three attempts each',
];

class ActionOrb extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? badge;
  final Color? color;
  const ActionOrb(
    this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.badge,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final art = artForIcon(icon);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Badge(
        isLabelVisible: badge != null,
        label: Text(badge ?? ''),
        backgroundColor: const Color(0xffce6753),
        textColor: Colors.white,
        child: art != null
            ? CartoonButton(
                art: art,
                label: label,
                onTap: UiSounds.wrap(onTap),
                idle: [
                  CartoonArt.rocket,
                  CartoonArt.gift,
                  CartoonArt.revive,
                ].contains(art),
              )
            : IconButton(
                onPressed: UiSounds.wrap(onTap),
                tooltip: label,
                icon: CartoonIcon(icon, color: color),
                style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
              ),
      ),
    );
  }
}

/// Google profile button. Placed opposite the settings icon in the home bar.
class ProfileAvatar extends StatelessWidget {
  final String? photoUrl, accountName;
  final bool busy;
  final VoidCallback? onTap;
  /// Green tick over the avatar once this player has asked for a rematch.
  final bool rematchRequested;
  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.accountName,
    required this.busy,
    this.onTap,
    this.rematchRequested = false,
  });
  @override
  Widget build(BuildContext context) {
    final avatar = Padding(
      padding: const EdgeInsets.all(4),
      child: photoUrl == null
          ? CartoonButton(
              art: CartoonArt.profile,
              label: accountName ?? 'Player profile',
              onTap: UiSounds.wrap(busy ? null : onTap),
              size: 60,
            )
          : Tooltip(
              message: accountName ?? 'Sign in with Google',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: UiSounds.wrap(busy ? null : onTap),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withValues(alpha: .94),
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl!)
                      : null,
                  onBackgroundImageError: photoUrl != null ? (_, _) {} : null,
                  child: photoUrl == null
                      ? const CartoonIcon(
                          Icons.person_rounded,
                          size: 32,
                          color: ink,
                        )
                      : null,
                ),
              ),
            ),
    );
    if (!rematchRequested) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: teal,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet for Google sign-in / sign-out and profile display.
class ProfileSheet extends StatefulWidget {
  final ProgressStore store;
  final Progress progress;
  final VoidCallback onChanged;
  const ProfileSheet({
    super.key,
    required this.store,
    required this.progress,
    required this.onChanged,
  });
  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      error = friendlyOnlineError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> signIn() => run(() async {
    await widget.store.signInWithGoogle();
    await widget.store.mergeRemoteInto(widget.progress);
    widget.onChanged();
  });

  Future<void> signOut() => run(() async {
    await widget.store.signOutGoogle();
    widget.onChanged();
  });

  @override
  Widget build(BuildContext context) {
    final store = widget.store, signed = store.isGoogle;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white,
            backgroundImage: store.photoUrl != null
                ? NetworkImage(store.photoUrl!)
                : null,
            onBackgroundImageError: store.photoUrl != null ? (_, _) {} : null,
            child: store.photoUrl == null
                ? const CartoonIcon(Icons.person_rounded, size: 44, color: teal)
                : null,
          ),
          const SizedBox(height: 12),
          SelectableText(store.status, style: const TextStyle(fontSize: 12)),
          TextButton(
            onPressed: UiSounds.wrap(
              busy
                  ? null
                  : () => run(() async {
                      await store.checkConnection();
                      widget.onChanged();
                    }),
            ),
            child: Text(tr('Retry Firebase access')),
          ),
          Text(
            signed
                ? (store.displayName ?? tr('Google player'))
                : tr('Guest climber'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          if (signed && store.email != null)
            SelectableText(store.email!, style: const TextStyle(color: teal)),
          if (!signed)
            Text(
              tr('Sign in to sync progress and race online.'),
              style: const TextStyle(color: teal, fontSize: 12),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: UiSounds.wrap(
              busy
                  ? null
                  : signed
                  ? signOut
                  : signIn,
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            icon: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : CartoonIcon(
                    signed ? Icons.logout_rounded : Icons.login_rounded,
                  ),
            label: Text(
              signed ? tr('Sign out') : tr('Sign in with Google'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('Linking keeps your current coins and skins.'),
              style: const TextStyle(fontSize: 11, color: teal),
            ),
          ),
        ],
      ),
    );
  }
}

/// One broken ring; rotating it reads as an orbiting loader.
class _OrbitRing extends CustomPainter {
  final Color color;
  final double width;
  const _OrbitRing({required this.color, this.width = 5});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - width,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(rect, i * 2.1, 1.4, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRing old) =>
      old.color != color || old.width != width;
}

/// Pre-game face-off: player avatar left, mystery rival right, and two
/// counter-revolving orbit rings around a playful VS mark while searching.
class MatchFaceoff extends StatefulWidget {
  final String? photoUrl;
  final String playerName;
  const MatchFaceoff({
    super.key,
    required this.photoUrl,
    required this.playerName,
  });
  @override
  State<MatchFaceoff> createState() => _MatchFaceoffState();
}

class _MatchFaceoffState extends State<MatchFaceoff>
    with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      spin.stop();
    } else if (!spin.isAnimating) {
      spin.repeat();
    }
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  Widget _side(Widget avatar, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      avatar,
      const SizedBox(height: 6),
      SizedBox(
        width: 92,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _side(
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white,
          backgroundImage: widget.photoUrl != null
              ? NetworkImage(widget.photoUrl!)
              : null,
          onBackgroundImageError: widget.photoUrl != null ? (_, _) {} : null,
          child: widget.photoUrl == null
              ? const CartoonIcon(Icons.person_rounded, size: 32, color: teal)
              : null,
        ),
        widget.playerName,
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 124,
        height: 124,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: spin,
              child: const CustomPaint(
                size: Size(124, 124),
                painter: _OrbitRing(color: teal),
              ),
            ),
            RotationTransition(
              turns: ReverseAnimation(spin),
              child: const CustomPaint(
                size: Size(94, 94),
                painter: _OrbitRing(color: Color(0xffc98a1b), width: 4),
              ),
            ),
            Transform.rotate(
              angle: -0.08,
              child: const Text(
                'VS',
                style: TextStyle(
                  color: Color(0xffb7791f),
                  fontSize: 34,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  shadows: [Shadow(color: Colors.white, blurRadius: 10)],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      _side(
        const CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white,
          child: CartoonIcon(Icons.smart_toy_rounded, size: 32, color: ink),
        ),
        tr('Mystery rival'),
      ),
    ],
  );
}

/// Post-game face-off: both climbers side-by-side with final step counts.
/// The winner gets a gold ring, trophy and WINNER badge; ties show DRAW.
class ResultFaceoff extends StatelessWidget {
  final String? userPhoto;
  final String userName, oppName;
  final int userScore, oppScore;
  final int? outcome;
  const ResultFaceoff({
    super.key,
    required this.userPhoto,
    required this.userName,
    required this.userScore,
    required this.oppName,
    required this.oppScore,
    this.outcome,
  });

  Widget _card({
    required Widget avatar,
    required String name,
    required int score,
    required bool winner,
    required bool draw,
  }) {
    final highlight = draw
        ? teal
        : winner
        ? const Color(0xffc98a1b)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: highlight == null
                ? null
                : Border.all(color: highlight, width: 3),
          ),
          child: avatar,
        ),
        if (winner)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xffc98a1b),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr('WINNER'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        else if (draw)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: teal,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr('DRAW'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        else
          const SizedBox(height: 22),
        const SizedBox(height: 4),
        SizedBox(
          width: 100,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$score',
          style: const TextStyle(
            color: ink,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(tr('steps'), style: const TextStyle(color: teal, fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draw = outcome == null ? userScore == oppScore : outcome == 0;
    final userWins = outcome == null ? userScore > oppScore : outcome == 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          avatar: CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            backgroundImage: userPhoto != null
                ? NetworkImage(userPhoto!)
                : null,
            onBackgroundImageError: userPhoto != null ? (_, _) {} : null,
            child: userPhoto == null
                ? const CartoonIcon(Icons.person_rounded, size: 32, color: teal)
                : null,
          ),
          name: userName,
          score: userScore,
          winner: userWins,
          draw: draw,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Text(
                tr('VS'),
                style: const TextStyle(
                  color: ink,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              CartoonIcon(
                draw ? Icons.handshake_rounded : Icons.emoji_events_rounded,
                color: draw ? teal : const Color(0xffc98a1b),
                size: 30,
              ),
            ],
          ),
        ),
        _card(
          avatar: CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              oppName.isEmpty ? '?' : oppName[0].toUpperCase(),
              style: const TextStyle(
                color: ink,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          name: oppName,
          score: oppScore,
          winner: outcome == null ? !draw && !userWins : outcome == -1,
          draw: draw,
        ),
      ],
    );
  }
}

/// Multiplayer results ranking. Shown instead of the 1v1 face-off when a room
/// has more than two players, so every racer appears ranked by finishing
/// position and score. The winner keeps the gold highlight; the local player
/// is outlined in teal.
class MultiplayerLeaderboard extends StatelessWidget {
  final List<
    ({
      String name,
      int score,
      bool isSelf,
      bool isWinner,
      String character,
    })
  >
  standings;
  final String userName;
  final String? userPhoto;
  const MultiplayerLeaderboard({
    super.key,
    required this.standings,
    required this.userName,
    this.userPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < standings.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _LeaderboardRow(
                rank: i + 1,
                name: standings[i].name,
                score: standings[i].score,
                isSelf: standings[i].isSelf,
                isWinner: standings[i].isWinner,
                character: standings[i].character,
                photo: standings[i].isSelf ? userPhoto : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank, score;
  final String name, character;
  final bool isSelf, isWinner;
  final String? photo;
  const _LeaderboardRow({
    required this.rank,
    required this.name,
    required this.score,
    required this.isSelf,
    required this.isWinner,
    required this.character,
    this.photo,
  });

  @override
  Widget build(BuildContext context) {
    final medal = isWinner ? const Color(0xffc98a1b) : const Color(0xffcfddd6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isWinner ? const Color(0xfffff6dd) : Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelf ? teal : medal,
          width: isSelf ? 2.5 : 1.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isWinner ? const Color(0xffc98a1b) : ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Mini character avatar from assets/ui/characters.png, ringed for
          // the winner and the local player. A Google photo still wins when
          // the racer set one.
          photo == null
              ? CharacterMini(
                  character: character,
                  size: 32,
                  border: isSelf ? teal : (isWinner ? medal : null),
                )
              : CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.white,
                  backgroundImage: NetworkImage(photo!),
                  onBackgroundImageError: (_, _) {},
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSelf ? tr('You') : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (isWinner)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: CartoonIcon(
                Icons.emoji_events_rounded,
                color: Color(0xffc98a1b),
                size: 20,
              ),
            ),
          Text(
            '$score',
            style: const TextStyle(
              color: teal,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeOverlay extends StatelessWidget {
  final PlayMode mode;
  final PlayerSettings settings;
  final int coins, steps, earned;
  final bool busy, searching;
  final bool showRewards;
  final String result;
  final String? photoUrl, accountName, oppName;
  final int? oppScore;
  /// Every racer ranked for multiplayer results. Empty (or exactly two
  /// entries) keeps the 1v1 face-off.
  final List<
    ({
      String name,
      int score,
      bool isSelf,
      bool isWinner,
      String character,
    })
  >
  standings;
  final int? outcome;
  final bool authBusy, isGoogle, googleBusy;
  final int? reviveSeconds;
  final String? spectateLeader, voiceLabel, voiceBadge;
  final bool spectateHost, rematchWaiting, inRace;
  final int spectateVotes, rockAmmo;
  /// This guest asked for a rematch: ticks the avatar on the home screen.
  final bool rematchRequested;
  final VoidCallback play,
      home,
      room,
      shop,
      friends,
      reward,
      preferences,
      profile,
      modes,
      cancelSearch;
  final VoidCallback? google, revive, decline, rematch, voiceToggle, throwRock;
  const HomeOverlay({
    super.key,
    required this.mode,
    required this.settings,
    required this.coins,
    required this.steps,
    required this.earned,
    required this.busy,
    required this.searching,
    this.showRewards = true,
    required this.result,
    this.photoUrl,
    this.accountName,
    this.oppName,
    this.oppScore,
    this.standings = const [],
    this.outcome,
    this.authBusy = false,
    this.isGoogle = false,
    this.googleBusy = false,
    this.reviveSeconds,
    this.spectateLeader,
    this.spectateHost = false,
    this.spectateVotes = 0,
    this.rockAmmo = 0,
    this.inRace = false,
    this.rematchRequested = false,
    this.rematchWaiting = false,
    this.voiceLabel,
    this.voiceBadge,
    required this.play,
    required this.home,
    required this.room,
    required this.shop,
    required this.friends,
    required this.reward,
    required this.preferences,
    required this.profile,
    required this.modes,
    this.google,
    this.revive,
    this.decline,
    this.rematch,
    this.voiceToggle,
    this.throwRock,
    required this.cancelSearch,
  });
  @override
  Widget build(BuildContext context) {
    final isHome = mode == PlayMode.menu;
    // Result screen: the host restarts the same room, a guest asks for it.
    final resultAction = rematchWaiting
        ? tr('Waiting for host…')
        : inRace && !spectateHost
        ? tr('Request rematch')
        : tr('Play again');
    return DecoratedBox(
      // Translucent so the live gameplay demo (attract mode) shows through.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xffedf8f5).withValues(alpha: .62),
            const Color(0xffd9eff2).withValues(alpha: .45),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (!isHome)
                    ActionOrb(Icons.arrow_back_rounded, 'Back to home', home)
                  else ...[
                    // Google profile sits opposite the settings icon.
                    ProfileAvatar(
                      photoUrl: photoUrl,
                      accountName: accountName,
                      busy: authBusy,
                      onTap: UiSounds.wrap(profile),
                      rematchRequested: rematchRequested,
                    ),
                    const SizedBox(width: 4),
                    const Expanded(child: CloudHopLogo(height: 76)),
                  ],
                  if (!isHome) const Spacer(),
                  if (isHome)
                    ActionOrb(Icons.settings_rounded, 'Settings', preferences),
                ],
              ),
            ),
            if (mode == PlayMode.over && reviveSeconds == null && !searching)
              Positioned(
                top: 92,
                left: 20,
                right: 20,
                bottom: 108,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              result.isEmpty ? tr('Nice climbing!') : result,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              constraints: const BoxConstraints(maxWidth: 400),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 18,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xfffffbeb,
                                ).withValues(alpha: .9),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: const Color(0xffe4c98a),
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Multiplayer rooms rank every racer instead
                                  // of showing the 1v1 face-off. 1v1 keeps the
                                  // existing two-avatar layout untouched.
                                  if (standings.length > 2)
                                    MultiplayerLeaderboard(
                                      standings: standings,
                                      userName: settings.name,
                                      userPhoto: photoUrl,
                                    )
                                  else if (oppName != null && oppScore != null)
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: ResultFaceoff(
                                        userPhoto: photoUrl,
                                        userName: settings.name,
                                        userScore: steps,
                                        oppName: oppName!,
                                        oppScore: oppScore!,
                                        outcome: outcome,
                                      ),
                                    )
                                  else ...[
                                    CircleAvatar(
                                      radius: 32,
                                      backgroundColor: Colors.white,
                                      backgroundImage: photoUrl == null
                                          ? null
                                          : NetworkImage(photoUrl!),
                                      child: photoUrl == null
                                          ? const CartoonIcon(
                                              Icons.person_rounded,
                                              size: 48,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      settings.name,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '$steps steps',
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Text(
                                    '+$earned coins',
                                    style: const TextStyle(
                                      color: teal,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            SizedBox.square(
                              dimension: 128,
                              child: busy
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : CartoonButton(
                                      art: CartoonArt.play,
                                      label: resultAction,
                                      onTap: rematchWaiting
                                          ? null
                                          : UiSounds.wrap(play),
                                      size: 128,
                                      idle: true,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              resultAction,
                              style: const TextStyle(
                                fontSize: 23,
                                color: ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (inRace &&
                                !spectateHost &&
                                spectateVotes > 0 &&
                                !rematchWaiting)
                              Text(
                                trn('{n} want a rematch', spectateVotes),
                                style: const TextStyle(color: teal, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (mode != PlayMode.over || reviveSeconds != null || searching)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (searching) ...[
                      MatchFaceoff(
                        photoUrl: photoUrl,
                        playerName: settings.name,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        tr('Finding your challenger…'),
                        style: const TextStyle(fontSize: 20, color: ink),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: UiSounds.wrap(cancelSearch),
                        child: Text(tr('Cancel')),
                      ),
                    ] else if (reviveSeconds != null) ...[
                      Text(
                        tr('Keep climbing?'),
                        style: const TextStyle(
                          fontSize: 25,
                          color: ink,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.white, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: reviveSeconds! / 5,
                              strokeWidth: 10,
                              backgroundColor: Colors.white.withValues(
                                alpha: .5,
                              ),
                              color: teal,
                            ),
                            Center(
                              child: Text(
                                '${reviveSeconds!}',
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: UiSounds.wrap(busy ? null : revive),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(230, 58),
                        ),
                        icon: const CartoonSprite(CartoonArt.revive, size: 40),
                        label: Text(tr('Watch ad · Revive')),
                      ),
                      TextButton(
                        onPressed: UiSounds.wrap(busy ? null : decline),
                        child: Text(tr('No thanks')),
                      ),
                    ] else if (mode == PlayMode.spectate) ...[
                      Text(
                        tr('SPECTATING'),
                        style: const TextStyle(
                          fontSize: 25,
                          color: ink,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(color: Colors.white, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        spectateLeader == null
                            ? tr('Watching the round…')
                            : trn('Watching {n}', spectateLeader!),
                        style: const TextStyle(color: teal, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Send a diagonal meteor shower'),
                        style: const TextStyle(color: ink, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: UiSounds.wrap(busy ? null : throwRock),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(230, 58),
                        ),
                        icon: const Icon(
                          Icons.circle,
                          color: Color(0xff6b5a4e),
                        ),
                        label: Text(
                          rockAmmo > 0
                              ? trn('Throw Rocks ({n} left)', rockAmmo)
                              : tr('Throw Rocks (500 coins each)'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (voiceToggle != null)
                        ActionOrb(
                          Icons.mic_off,
                          voiceLabel ?? 'Voice',
                          busy ? null : voiceToggle,
                          badge: voiceBadge,
                        ),
                      FilledButton.icon(
                        onPressed: UiSounds.wrap(
                          busy
                              ? null
                              : rematchWaiting
                              ? null
                              : rematch,
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(230, 58),
                        ),
                        icon: const CartoonSprite(CartoonArt.room, size: 40),
                        label: Text(
                          rematchWaiting
                              ? tr('Waiting for host…')
                              : spectateHost
                              ? tr('Play again — same room')
                              : tr('Request rematch'),
                        ),
                      ),
                      if (!spectateHost && spectateVotes > 0 && !rematchWaiting)
                        Text(
                          trn('{n} want a rematch', spectateVotes),
                          style: const TextStyle(color: teal, fontSize: 12),
                        ),
                      TextButton(
                        onPressed: UiSounds.wrap(busy ? null : home),
                        child: Text(tr('Exit to menu')),
                      ),
                    ] else ...[
                      SizedBox.square(
                        dimension: 128,
                        child: busy
                            ? const Center(child: CircularProgressIndicator())
                            : CartoonButton(
                                art: CartoonArt.play,
                                label: mode == PlayMode.paused
                                    ? 'Resume game'
                                    : 'Start game',
                                onTap: UiSounds.wrap(play),
                                size: 128,
                                idle: true,
                              ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr(
                          mode == PlayMode.paused
                              ? 'Resume'
                              : isHome
                              ? 'Start'
                              : 'Play again',
                        ),
                        style: const TextStyle(
                          fontSize: 25,
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (isHome) ...[
                        Text(
                          tr(modeNames[settings.choice.index]),
                          style: const TextStyle(color: teal),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: UiSounds.wrap(busy ? null : modes),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(230, 48),
                            backgroundColor: Colors.white.withValues(alpha: .7),
                          ),
                          icon: const CartoonIcon(
                            Icons.tune_rounded,
                            size: 26,
                            color: teal,
                          ),
                          label: Text(tr('Modes')),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: UiSounds.wrap(busy ? null : room),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(230, 58),
                            backgroundColor: Colors.white.withValues(alpha: .7),
                          ),
                          icon: const CartoonSprite(CartoonArt.room, size: 42),
                          label: Text(tr('Create a room & invite')),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            Positioned(
              bottom: 18,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  if (isHome)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CartoonIcon(Icons.monetization_on, size: 18),
                        Text(
                          ' $coins   ·   ',
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.circle,
                          size: 14,
                          color: Color(0xff6b5a4e),
                        ),
                        Flexible(
                          child: Text(
                            ' $rockAmmo   ·   ${settings.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (reviveSeconds == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (inRace)
                          ActionOrb(
                            Icons.circle,
                            tr('Throw rocks'),
                            busy || searching ? null : throwRock,
                            badge: '$rockAmmo',
                            color: const Color(0xff6b5a4e),
                          )
                        else
                          ActionOrb(
                            Icons.shopping_bag_rounded,
                            tr('Shop'),
                            busy || searching ? null : shop,
                          ),
                        ActionOrb(
                          Icons.people_alt_rounded,
                          tr('Friends & invitations'),
                          busy || searching ? null : friends,
                        ),
                        if (showRewards)
                          ActionOrb(
                            Icons.ondemand_video_rounded,
                            tr('Watch ad for 100 coins'),
                            busy || searching ? null : reward,
                          ),
                        ActionOrb(
                          isGoogle
                              ? Icons.verified_user_rounded
                              : Icons.account_circle_rounded,
                          isGoogle
                              ? tr('Google account (signed in)')
                              : tr('Sign in with Google'),
                          busy || searching || googleBusy ? null : google,
                          badge: isGoogle ? '✓' : null,
                          color: isGoogle ? teal : null,
                        ),
                      ],
                    ),
                  if (isHome)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tr(
                          settings.control == ControlMode.joystick
                              ? 'Hold to hop · Drag to steer'
                              : 'Swipe up to jump · Diagonal to steer',
                        ),
                        style: const TextStyle(color: teal, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home-screen "Modes" popup: pick the game mode without digging through
/// settings. Edits apply to the live [PlayerSettings] instance so the home
/// screen label updates behind the sheet; [onChanged] lets the caller resync
/// its own mode mirror (run choice) and repaint.
class ModePickerSheet extends StatefulWidget {
  final PlayerSettings settings;
  final VoidCallback onChanged;
  const ModePickerSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  @override
  State<ModePickerSheet> createState() => _ModePickerSheetState();
}

class _ModePickerSheetState extends State<ModePickerSheet> {
  bool saving = false;

  Future<void> _apply() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.settings.save();
    } catch (_) {
      // Keep the choice in memory even if the local write fails, matching the
      // settings sheet: the mode still applies to this session.
    }
    if (!mounted) return;
    setState(() => saving = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Game mode'),
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Choose the mode you want to play'),
            style: const TextStyle(color: teal, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ...GameChoice.values.map(
                  (choice) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CartoonSprite(
                      choice == GameChoice.race
                          ? CartoonArt.challenge
                          : CartoonArt.classic,
                    ),
                    trailing: CartoonIcon(
                      s.choice == choice
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: teal,
                    ),
                    title: Text(tr(modeNames[choice.index])),
                    subtitle: Text(tr(modeDescriptions[choice.index])),
                    onTap: saving
                        ? null
                        : UiSounds.wrap(() {
                            s.choice = choice;
                            unawaited(_apply());
                          }),
                  ),
                ),
                if (s.choice == GameChoice.race)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<int>(
                      initialValue: s.raceTarget,
                      decoration: InputDecoration(
                        labelText: tr('Race finish line'),
                      ),
                      items: List.generate(
                        10,
                        (i) => DropdownMenuItem(
                          value: (i + 1) * 100,
                          child: Text('${(i + 1) * 100} steps'),
                        ),
                      ),
                      onChanged: saving
                          ? null
                          : (v) {
                              s.raceTarget = v!;
                              unawaited(_apply());
                            },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: UiSounds.wrap(() => Navigator.pop(context)),
            style: FilledButton.styleFrom(minimumSize: const Size(230, 56)),
            icon: const Icon(Icons.check_rounded, color: Colors.white),
            label: Text(saving ? tr('Saving…') : tr('Done')),
          ),
        ],
      ),
    );
  }
}

/// Selectable character chip: the mini avatar plus its label, highlighted
/// when it is the current pick.
class _CharacterChip extends StatelessWidget {
  final String character, label;
  final bool selected;
  final VoidCallback onTap;
  const _CharacterChip({
    required this.character,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: UiSounds.wrap(onTap),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xfffff4dc) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? teal : const Color(0xffcfddd6),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CharacterMini(character: character, size: 30),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  final PlayerSettings settings;
  final String? playerId;
  final Future<void> Function() onSave;
  const SettingsSheet({
    super.key,
    required this.settings,
    required this.playerId,
    required this.onSave,
  });
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final name = TextEditingController(text: widget.settings.name);
  bool saving = false;
  String? error;
  String? details;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  tr('Make it yours'),
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 16,
                  decoration: InputDecoration(
                    labelText: tr('Player name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: appLang.value,
                  decoration: InputDecoration(
                    labelText: tr('Language'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  ],
                  onChanged: (v) => setState(() {
                    appLang.value = v!;
                    s.language = v;
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                    title: Text(tr('Nature ambience & sound effects')),
                  secondary: CartoonSprite(
                    s.sound ? CartoonArt.sound : CartoonArt.soundOff,
                  ),
                  value: s.sound,
                  onChanged: (v) => setState(() => s.sound = v),
                ),
                Text(
                  tr('Game mode'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ...GameChoice.values.map(
                  (choice) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CartoonSprite(
                      choice == GameChoice.race
                          ? CartoonArt.challenge
                          : CartoonArt.classic,
                    ),
                    trailing: CartoonIcon(
                      s.choice == choice
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: teal,
                    ),
                    title: Text(tr(modeNames[choice.index])),
                    subtitle: Text(tr(modeDescriptions[choice.index])),
                    onTap: UiSounds.wrap(
                      () => setState(() => s.choice = choice),
                    ),
                  ),
                ),
                if (s.choice == GameChoice.race)
                  DropdownButtonFormField<int>(
                    initialValue: s.raceTarget,
                    decoration: InputDecoration(
                      labelText: tr('Race finish line'),
                    ),
                    items: List.generate(
                      10,
                      (i) => DropdownMenuItem(
                        value: (i + 1) * 100,
                        child: Text('${(i + 1) * 100} steps'),
                      ),
                    ),
                    onChanged: (v) => setState(() => s.raceTarget = v!),
                  ),
                const SizedBox(height: 16),
                Text(
                  tr('Playing character'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Center(
                  child: CharacterPortrait(character: s.character, size: 96),
                ),
                // Mini avatars from assets/ui/characters.png, so the preview
                // matches the sprite the player will actually race as.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final entry in CharacterArt.all)
                      _CharacterChip(
                        character: entry.id,
                        label: tr(entry.label),
                        selected: s.character == entry.id,
                        onTap: () => setState(() => s.character = entry.id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Controls'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ...ControlMode.values.map(
                  (mode) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CartoonSprite(
                      mode == ControlMode.joystick
                          ? CartoonArt.joystick
                          : CartoonArt.play,
                    ),
                    trailing: CartoonIcon(
                      s.control == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: teal,
                    ),
                    title: Text(
                      tr(mode == ControlMode.swipe ? 'Swipe' : 'Joystick'),
                    ),
                    subtitle: Text(
                      tr(
                        mode == ControlMode.swipe
                            ? 'Flick to move and jump'
                            : 'Hold to hop continuously, drag to steer',
                      ),
                    ),
                    onTap: UiSounds.wrap(
                      () => setState(() => s.control = mode),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: s.country,
                  decoration: InputDecoration(
                    labelText: tr('Country for practice rivals'),
                  ),
                  items: regions.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    s.country = v!;
                    s.city = regions[v]!.keys.first;
                  }),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(s.country),
                  initialValue: s.city,
                  decoration: InputDecoration(labelText: tr('City')),
                  items: regions[s.country]!.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setState(() => s.city = v!),
                ),
                const SizedBox(height: 16),
                if (widget.playerId != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Your player ID')),
                    subtitle: SelectableText(widget.playerId!),
                    trailing: IconButton(
                      tooltip: tr('Copy player ID'),
                      icon: const CartoonIcon(Icons.copy),
                      onPressed: UiSounds.wrap(
                        () => Clipboard.setData(
                          ClipboardData(text: widget.playerId!),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          if (details != null)
            TextButton.icon(
              onPressed: UiSounds.wrap(
                () => Clipboard.setData(ClipboardData(text: details!)),
              ),
              icon: const Icon(Icons.copy, size: 16),
                              label: Text(tr('Copy connection details')),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: UiSounds.wrap(
              saving
                  ? null
                  : () async {
                      setState(() {
                        saving = true;
                        error = null;
                        details = null;
                      });
                      s.name = name.text.trim().isEmpty
                          ? 'Pip'
                          : name.text.trim();
                      try {
                        await s.save();
                        await s.prefs.setBool('profileSyncPending', true);
                      } catch (e) {
                        if (mounted)
                          setState(() {
                            error = tr(
                              'Could not save on this device. Please retry.',
                            );
                            saving = false;
                          });
                        return;
                      }
                      try {
                        await widget.onSave();
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted)
                          setState(() {
                            error =
                                tr('Saved on this device. ') +
                                (e is OnlineServiceFailure
                                    ? e.message
                                    : tr(
                                        'Online profile sync is pending.',
                                      ));
                            details = e.toString();
                            saving = false;
                          });
                      }
                    },
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text(
              saving
                  ? tr('Saving…')
                  : error != null
                  ? tr('Retry online sync')
                  : tr('Save settings'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Approved teal-and-gold artwork, shared by the home header and splash.
class CloudHopLogo extends StatelessWidget {
  final double height;
  const CloudHopLogo({super.key, this.height = 100});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/ui/cloud_hop_logo.png',
    height: height,
    fit: BoxFit.contain,
    semanticLabel: 'Cloud Hop',
  );
}
