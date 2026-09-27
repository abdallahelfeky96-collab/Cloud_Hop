# Current audio status

Gameplay music has been replaced by nature ambience. Live jump/flip/landing effects are separate. Home music remains disabled. See ../AUDIO_LIVE_UPDATE.md. Historical notes below are superseded.

# Music previews — replacement drafts await approval

The first drafts Sky Garden and Sky Sprint were rejected and remain reference-only. They are NOT approved or enabled in the game.

Replacement direction: cheerful cartoon adventure, using original synthesized orchestral-style instruments (not recordings of a live orchestra):
- Cloud-Hop-Home-Cloud-Parade-v2.wav: 42.4 seconds. Lilting 6/8 rhythm, flute-like melody, warm plucked strings and gentle percussion.
- Cloud-Hop-Race-Cloud-Dash-v2.wav: 43 seconds. Brisk 4/4 race theme, brass-like melody, string accompaniment, bass and stronger drums, with changes across phrases.

Both are original compositions generated locally with the included standard-Node scripts, no sample packs or dependencies. Stereo 44.1 kHz, 16-bit WAV. Listening previews include fade tails; final seamless loops can be made after approval.

All music remains outside Flutter's registered assets and is NOT played by the app. Awaiting explicit approval before integration. No music package was added or installed.

## Third drafts — current listening previews, not approved
Both previous pairs were rejected. The user requested calm, softer home music with little percussion, and gameplay music suggesting hopping rather than hurried running.
- Cloud-Hop-Home-Quiet-Clouds-v3.wav: 68 BPM, 59.5 seconds, sparse soft melody and sustained chords; no drums.
- Cloud-Hop-Gameplay-Little-Hops-v3.wav: 88 BPM, 46.6 seconds, short ascending phrases with held landing notes and breathing space; no drums.
Both use gentler timbres and materially lower encoded levels than v2. These are listening previews, not final seamless loops, and remain disabled pending approval. Playback loudness also depends on the user's device volume. Source: compose-v3.cjs.

## Fourth drafts — current previews, awaiting approval
V3 was rejected as too sleepy. V4 aims between the earlier extremes, using plucked melodies and light rhythmic accompaniment instead of sustained lullaby textures or a fast chase arrangement.
- Home Sunny Clouds v4: 92 BPM, warm plucked melody with sparse brushed percussion.
- Gameplay Hop Along v4: 112 BPM, a clearer rising/landing hook, offbeat chords, light wood/shaker percussion and a bass pulse.
Both have moderate, controlled encoded levels. These remain listening previews, NOT enabled in the app. Original composition/rendering source: compose-v4.cjs.

## Fifth drafts and gameplay effects — review assets
Home Sunny Clouds is now 104 BPM (previously 92), with a piano-like lead and stronger plucked/guitar-like harmonics. Gameplay Hop Along stays 112 BPM with firmer accompaniment. The original instrument sounds are synthesized, not recordings of a piano or guitar.
Three short cues are supplied: jump 0.22 seconds; soft cloud landing 0.17 seconds; special three-part flip 0.52 seconds. The mixed gameplay demo uses staged events to audition effects over music, not real game event timing.
These files are not yet wired to app playback, pending review. Intended integration: trigger jump once in GameEngine.jump, landing only when land() observes hadFlight, and the special flip cue once on the powered flip takeoff. Do not trigger landing every grounded physics frame or play the demonstration timeline in the app. The existing flip animation is one rotation; the three-part audio does not change gameplay or add a three-rotation stunt.
See FIREBASE_NEXT_STEPS.md for the backend work requested in this turn. No live backend changes or app builds were made.

