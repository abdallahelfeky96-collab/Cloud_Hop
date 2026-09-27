# Live action audio update — 2026-09-24

- Jump, landing, rocket, trampoline placement/bounce, exit and loss retain separate event-driven WAV cues.
- Falling plays once when descending into the bottom 150 pixels, before leaving the screen; landing/jumping resets it.
- Running power above 0.72 performs a single flip; above 0.90 performs three rotations. Separate flip/triple_flip clips match the 0.52-second animation.
- Shared button callback feedback covers gameplay controls, home, dialogs, shop, friends, profile, result actions and segmented selectors. Nested controls produce one click. Disabled controls stay silent.
- Nature ambience plays only during active gameplay, respecting sound, foreground, ads and audio focus.
- Non-Classic solo Start/Play and room host Start announce exactly: "Let's see who will touch the sky."
- Announcement uses Android TextToSpeech with an installed offline English voice. No dependency added, no automatic voice download. Missing offline voice means no spoken announcement. It respects sound/focus/lifecycle and stops on Home. It is synthesized speech, not a recording of the assistant.

Validation: Dart formatting/parser completed; no dependency installation, tests, Android build, deployment or device playback. Flutter lint include remains unresolved in this source-only environment. Windows voice export failed, so no recording preview is supplied. Verify audio balance, TTS availability and event timing on a phone before release.
