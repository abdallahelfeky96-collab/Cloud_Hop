# Separate action sounds
Each event has its own WAV under assets/audio. Nature ambience is unchanged.

- jump.wav: quiet ordinary takeoff.
- land.wav: light contact on a platform, only after being airborne.
- flip.wav: special powered flip, replaces the ordinary jump cue for that move.
- rocket.wav: successful rocket activation.
- spring_set.wav: successfully placing the trampoline three steps ahead.
- spring.wav: bouncing off that trampoline.
- fall.wav: dropping below the screen, including falls rescued by an extra life.
- start.wav: starting a new run, including a multiplayer round.
- lose.wav: run elimination/loss; follows falling instead of sounding simultaneously. Victory/draw does not trigger it.
- exit.wav: returning from a run/results to home (not forcible OS termination).
- button.wav: enabled home actions such as Play, Settings, Profile, Shop, Friends, Room, Google and rewarded coins.

Short cues are preloaded through the existing native Android SoundPool. Menu effects are enabled separately from gameplay ambience. The sound setting, background/ad suppression and audio focus still apply. No synthesis/loading on each event; no dependency added.

The loss cue is allowed to finish before proceeding to game-over ad handling; pending feedback is cancelled if the user exits or starts another round. The actual game physics are not delayed.

The combined listening preview is not used by the game. Preview order: jump, land, rocket, trampoline placement, trampoline bounce, flip, fall, start, lose, exit, button.

Source read-through and Dart formatting only. No tests, builds, installations or deployments. Sound balance, native playback and event timing require phone verification. This document supersedes the earlier three-cue audio descriptions.
