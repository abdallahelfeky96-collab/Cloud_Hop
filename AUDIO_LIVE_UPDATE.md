# Current audio — nature ambience and live effects

Gameplay now uses a 60-second synthesized wind/leaves/bird ambience loop, replacing the Hop Along music asset. It has no melody, instruments or beat. This is original procedural sound design, not a location field recording. A crossfade connects the end and beginning. The home music remains an unapproved preview and is not enabled.

Jump (0.22s), landing (0.17s) and special three-part flip (0.52s) are separate assets. Actual local-player physics dispatches them: jump on takeoff, flip on powered flip takeoff, and landing only after airborne contact. Standing on a step does not retrigger landing. The existing flip animation remains one rotation; the three-part cue does not alter physics. Other players and the practice simulation do not generate local cues.

Android SoundPool preloads the short effects (about 160 KB PCM data total, plus native overhead), with up to four simultaneous streams. MediaPlayer streams the ambience separately. Asset copying is on a worker thread; music preparation is asynchronous. Sounds are not synthesized or loaded on each jump. The Flutter bridge sends events and changed playback state rather than per-frame sound commands.

Audio follows the sound setting and suspends during pause/background/ads, leaving gameplay, and audio-focus loss. Active voice lowers the background level; LiveKit can take exclusive audio focus depending on the device, in which case game sound yields. No new dependencies were added or installed.

Source-only delivery: source read-through and Dart formatting; no tests, builds, releases or deployments. Actual latency, frame rate, looping and microphone/audio-route coexistence have not been measured on a phone. The prior automatic approval review usage-limit interruption prevented the previous finishing/package step; that work was resumed successfully with this update.

Older music previews in the workspace are historical. They are not registered for playback. This source archive excludes those large rejected preview files; the active assets/audio folder contains the four files used by the Android implementation.
