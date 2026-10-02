import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/social.dart';
import 'cartoon_controls.dart';
import 'character_art.dart';
import 'lang.dart';
import 'screens.dart';

/// First-run setup: language, controls, character. Shown once after install
/// until the player taps Start, then never again (flag in prefs).
class OnboardingScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final VoidCallback onDone;
  const OnboardingScreen({
    super.key,
    required this.prefs,
    required this.onDone,
  });
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PlayerSettings settings = PlayerSettings(widget.prefs);
  final pages = PageController();
  int page = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    appLang.value = settings.language;
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void go(int next) {
    // Instant page jump: deterministic under test clocks and snappy
    // on-device, with the dots still tracking via onPageChanged.
    setState(() => page = next.clamp(0, 2));
    pages.jumpToPage(page);
  }

  Future<void> finish() async {
    if (saving) return;
    setState(() => saving = true);
    settings.language = appLang.value;
    await settings.save();
    await widget.prefs.setBool('onboardingDone', true);
    widget.onDone();
  }

  Widget option({
    required bool selected,
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: selected ? const Color(0xfffff4dc) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? teal : const Color(0xffcfddd6),
          width: selected ? 2.5 : 1,
        ),
      ),
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: ink),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: teal)),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: teal,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Scaffold(
      backgroundColor: const Color(0xffedf8f5),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              tr('Welcome to Cloud Hop'),
              style: const TextStyle(
                color: ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: page == i ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: page == i ? teal : const Color(0xffcfddd6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: pages,
                onPageChanged: (i) => setState(() => page = i),
                children: [
                  // 1 — Language, so the rest of setup reads in the player's
                  // own language.
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        tr('Choose your language'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      option(
                        selected: appLang.value == 'en',
                        leading: const Text(
                          'EN',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: teal,
                            fontSize: 20,
                          ),
                        ),
                        title: tr('English'),
                        subtitle: 'English',
                        onTap: () => setState(() {
                          appLang.value = 'en';
                          s.language = 'en';
                        }),
                      ),
                      option(
                        selected: appLang.value == 'ar',
                        leading: const Text(
                          'ع',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: teal,
                            fontSize: 22,
                          ),
                        ),
                        title: tr('Arabic'),
                        subtitle: 'العربية',
                        onTap: () => setState(() {
                          appLang.value = 'ar';
                          s.language = 'ar';
                        }),
                      ),
                    ],
                  ),
                  // 2 — Controls.
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        tr('Choose how to play'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      option(
                        selected: s.control == ControlMode.swipe,
                        leading: const CartoonSprite(CartoonArt.play, size: 44),
                        title: tr('Swipe'),
                        subtitle: tr('Flick to move and jump'),
                        onTap: () =>
                            setState(() => s.control = ControlMode.swipe),
                      ),
                      option(
                        selected: s.control == ControlMode.joystick,
                        leading: const CartoonSprite(
                          CartoonArt.joystick,
                          size: 44,
                        ),
                        title: tr('Joystick'),
                        subtitle: tr(
                          'Hold to hop continuously, drag to steer',
                        ),
                        onTap: () =>
                            setState(() => s.control = ControlMode.joystick),
                      ),
                    ],
                  ),
                  // 3 — Character.
                  ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        tr('Choose your character'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: CharacterPortrait(
                          character: s.character,
                          size: 110,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Mini avatars from assets/ui/characters.png so the
                      // preview matches the in-game sprite.
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final entry in CharacterArt.all)
                            _OnboardingCharacterChip(
                              character: entry.id,
                              label: tr(entry.label),
                              selected: s.character == entry.id,
                              onTap: () =>
                                  setState(() => s.character = entry.id),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  if (page > 0)
                    TextButton(
                      onPressed: saving ? null : () => go(page - 1),
                      child: Text(tr('Back')),
                    )
                  else
                    const SizedBox(width: 88),
                  const Spacer(),
                  if (page < 2)
                    FilledButton(
                      onPressed: () => go(page + 1),
                      child: Text(tr('Next')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: saving ? null : finish,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(tr('Start game')),
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

/// Selectable character chip for onboarding: mini avatar plus label.
class _OnboardingCharacterChip extends StatelessWidget {
  final String character, label;
  final bool selected;
  final VoidCallback onTap;
  const _OnboardingCharacterChip({
    required this.character,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
            CharacterMini(character: character, size: 32),
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
    );
  }
}
