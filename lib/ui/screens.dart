import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/challenge.dart';
import '../game/engine.dart';
import '../services/progress_store.dart';
import '../services/social.dart';

const ink = Color(0xff213c4c), teal = Color(0xff207e78);
const modeNames = ['Classic', 'Beat my best', 'Quick challenge'];

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Badge(
      isLabelVisible: badge != null,
      label: Text(badge ?? ''),
      child: IconButton.filledTonal(
        onPressed: onTap,
        tooltip: label,
        icon: Icon(icon, size: 28, color: color),
        style: IconButton.styleFrom(
          minimumSize: const Size(64, 64),
          backgroundColor: Colors.white.withValues(alpha: .94),
          foregroundColor: ink,
        ),
      ),
    ),
  );
}

/// Google profile button. Placed opposite the settings icon in the home bar.
class ProfileAvatar extends StatelessWidget {
  final String? photoUrl, accountName;
  final bool busy;
  final VoidCallback onTap;
  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.accountName,
    required this.busy,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Tooltip(
      message: accountName ?? 'Sign in with Google',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white.withValues(alpha: .94),
          backgroundImage: photoUrl != null
              ? NetworkImage(photoUrl!)
              : null,
          onBackgroundImageError: photoUrl != null ? (_, _) {} : null,
          child: photoUrl == null
              ? const Icon(Icons.person_rounded, size: 32, color: ink)
              : null,
        ),
      ),
    ),
  );
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
      error = e.toString().replaceFirst('StateError: ', '');
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
                ? const Icon(Icons.person_rounded, size: 44, color: teal)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            signed
                ? (store.displayName ?? 'Google player')
                : 'Guest climber',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          if (signed && store.email != null)
            SelectableText(store.email!, style: const TextStyle(color: teal)),
          if (!signed)
            const Text(
              'Sign in to sync progress and race online.',
              style: TextStyle(color: teal, fontSize: 12),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : signed
                ? signOut
                : signIn,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            icon: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(signed ? Icons.logout_rounded : Icons.login_rounded),
            label: Text(signed ? 'Sign out' : 'Sign in with Google'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Linking keeps your current coins and skins.',
              style: TextStyle(fontSize: 11, color: teal),
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
              ? const Icon(Icons.person_rounded, size: 32, color: teal)
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
                painter: _OrbitRing(
                  color: Color(0xffc98a1b),
                  width: 4,
                ),
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
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 10),
                  ],
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
          child: Icon(Icons.smart_toy_rounded, size: 32, color: ink),
        ),
        'Mystery rival',
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
  const ResultFaceoff({
    super.key,
    required this.userPhoto,
    required this.userName,
    required this.userScore,
    required this.oppName,
    required this.oppScore,
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
            child: const Text(
              'WINNER',
              style: TextStyle(
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
            child: const Text(
              'DRAW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        const SizedBox(height: 4),
        SizedBox(
          width: 110,
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
        const Text('steps', style: TextStyle(color: teal, fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draw = userScore == oppScore;
    final userWins = userScore > oppScore;
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
                ? const Icon(Icons.person_rounded, size: 32, color: teal)
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
              const Text(
                'VS',
                style: TextStyle(
                  color: ink,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Icon(
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
          winner: !draw && !userWins,
          draw: draw,
        ),
      ],
    );
  }
}

class HomeOverlay extends StatelessWidget {
  final PlayMode mode;
  final PlayerSettings settings;
  final int coins, steps, earned;
  final bool busy, searching;
  final String result;
  final String? photoUrl, accountName, oppName;
  final int? oppScore;
  final bool authBusy, isGoogle, googleBusy;
  final int? reviveSeconds;
  final VoidCallback play,
      home,
      room,
      shop,
      friends,
      reward,
      preferences,
      profile,
      cancelSearch;
  final VoidCallback? google, revive, decline;
  const HomeOverlay({
    super.key,
    required this.mode,
    required this.settings,
    required this.coins,
    required this.steps,
    required this.earned,
    required this.busy,
    required this.searching,
    required this.result,
    this.photoUrl,
    this.accountName,
    this.oppName,
    this.oppScore,
    this.authBusy = false,
    this.isGoogle = false,
    this.googleBusy = false,
    this.reviveSeconds,
    required this.play,
    required this.home,
    required this.room,
    required this.shop,
    required this.friends,
    required this.reward,
    required this.preferences,
    required this.profile,
    this.google,
    this.revive,
    this.decline,
    required this.cancelSearch,
  });
  @override
  Widget build(BuildContext context) {
    final isHome = mode == PlayMode.menu;
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
                      onTap: profile,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'CLOUD HOP',
                      style: TextStyle(
                        color: ink,
                        fontSize: 19,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Colors.white,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (isHome)
                    ActionOrb(Icons.settings_rounded, 'Settings', preferences),
                ],
              ),
            ),
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
                    const Text(
                      'Finding your challenger…',
                      style: TextStyle(fontSize: 20, color: ink),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: cancelSearch,
                      child: const Text('Cancel'),
                    ),
                  ] else if (reviveSeconds != null) ...[
                    const Text(
                      'Keep climbing?',
                      style: TextStyle(
                        fontSize: 25,
                        color: ink,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.white, blurRadius: 8),
                        ],
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
                      onPressed: busy ? null : revive,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(230, 58),
                      ),
                      icon: const Icon(Icons.ondemand_video_rounded),
                      label: const Text('Watch ad · Revive'),
                    ),
                    TextButton(
                      onPressed: busy ? null : decline,
                      child: const Text('No thanks'),
                    ),
                  ] else ...[
                    Semantics(
                      label: mode == PlayMode.paused
                          ? 'Resume game'
                          : 'Start game',
                      button: true,
                      child: SizedBox(
                        width: 116,
                        height: 116,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            backgroundColor: teal,
                            elevation: 8,
                            shadowColor: teal.withValues(alpha: .3),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: busy ? null : play,
                          child: busy
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.play_arrow_rounded, size: 70),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      mode == PlayMode.paused
                          ? 'Resume'
                          : isHome
                          ? 'Start'
                          : 'Play again',
                      style: const TextStyle(
                        fontSize: 25,
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (isHome) ...[
                      Text(
                        modeNames[settings.choice.index],
                        style: const TextStyle(color: teal),
                      ),
                      const SizedBox(height: 28),
                      OutlinedButton.icon(
                        onPressed: busy ? null : room,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(230, 58),
                          backgroundColor: Colors.white.withValues(alpha: .7),
                        ),
                        icon: const Icon(Icons.group_add_rounded),
                        label: const Text('Create a room & invite'),
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
                  if (mode == PlayMode.over) ...[
                    Text(
                      result.isEmpty ? 'Nice climbing!' : result,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (oppName != null && oppScore != null)
                      ResultFaceoff(
                        userPhoto: photoUrl,
                        userName: settings.name,
                        userScore: steps,
                        oppName: oppName!,
                        oppScore: oppScore!,
                      )
                    else
                      Text(
                        'Step $steps  ·  +$earned coins',
                        style: const TextStyle(color: ink),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (isHome)
                    Text(
                      '$coins coins   ·   ${settings.name}',
                      style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (reviveSeconds == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ActionOrb(
                          Icons.shopping_bag_rounded,
                          'Shop',
                          busy || searching ? null : shop,
                        ),
                        ActionOrb(
                          Icons.people_alt_rounded,
                          'Friends & invitations',
                          busy || searching ? null : friends,
                        ),
                        ActionOrb(
                          Icons.ondemand_video_rounded,
                          'Watch ad for 100 coins',
                          busy || searching ? null : reward,
                        ),
                        ActionOrb(
                          isGoogle
                              ? Icons.verified_user_rounded
                              : Icons.account_circle_rounded,
                          isGoogle
                              ? 'Google account (signed in)'
                              : 'Sign in with Google',
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
                        settings.control == ControlMode.joystick
                            ? 'Hold to hop · Drag to steer'
                            : 'Swipe up to jump · Diagonal to steer',
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
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Make it yours',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            maxLength: 16,
            decoration: const InputDecoration(
              labelText: 'Player name',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sound effects'),
            value: s.sound,
            onChanged: (v) => setState(() => s.sound = v),
          ),
          const Text(
            'Game mode',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...GameChoice.values.map(
            (choice) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.choice == choice
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: teal,
              ),
              title: Text(modeNames[choice.index]),
              subtitle: Text(
                [
                  'Climb at your own pace',
                  'Chase your personal best target',
                  'Find a player or race a practice bot',
                ][choice.index],
              ),
              onTap: () => setState(() => s.choice = choice),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Controls',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...ControlMode.values.map(
            (mode) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                s.control == mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: teal,
              ),
              title: Text(mode == ControlMode.swipe ? 'Swipe' : 'Joystick'),
              subtitle: Text(
                mode == ControlMode.swipe
                    ? 'Flick to move and jump'
                    : 'Hold to hop continuously, drag to steer',
              ),
              onTap: () => setState(() => s.control = mode),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: s.country,
            decoration: const InputDecoration(
              labelText: 'Country for practice rivals',
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
            decoration: const InputDecoration(labelText: 'City'),
            items: regions[s.country]!.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: (v) => setState(() => s.city = v!),
          ),
          const SizedBox(height: 16),
          if (widget.playerId != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Your player ID'),
              subtitle: SelectableText(widget.playerId!),
              trailing: IconButton(
                tooltip: 'Copy player ID',
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: widget.playerId!)),
              ),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    s.name = name.text.trim().isEmpty
                        ? 'Pip'
                        : name.text.trim();
                    try {
                      await s.save();
                      await widget.onSave();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          error =
                              'Saved on device. Online profile could not update.';
                          saving = false;
                        });
                      }
                    }
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}
