# Characters, Race, Arcade, lives and voice — source update

## User-visible changes
- Settings offers the supplied male and female character designs. The selection is explicit and saved on this device; no gender is inferred from Google identity. The chosen design is used in gameplay, and its identifier is shared with other racers. Purchased skin colors appear as small badges on the new designs.
- The supplied character PNG is preserved unchanged and bundled. The game paints the appropriate half and blends its white paper backdrop into the sky. Generating a transparent variant was blocked by the image service quota. The code retains motion, mirroring and flips; this is not a new multi-frame skeletal animation asset.
- Classic retains all owned extra lives: each fall consumes one until the bag is empty. A rewarded revival remains a separate, once-per-run Classic feature.
- Arcade replaces Beat My Best: last player standing wins. Race replaces Quick Challenge: finish goals are 100, 200, ... 1000 steps in Settings. Both can match online or fall back to a practice opponent after five seconds; friends can create/join rooms. Matchmaking separates Arcade and different Race goals.
- Competitive rounds give every player three attempts (two rescues), without using owned life inventory. Existing rocket/trampoline items remain available. The practice opponent uses the same physics and three-attempt limit, targets reachable platforms and builds run-up momentum. It no longer slows itself to guarantee a human win. Difficulty needs device playtesting.
- The mic control is removed from the room dialog. It appears bottom-right during human multiplayer gameplay. First tap requests microphone permission, joins voice and enables the mic; later taps mute/unmute. Backgrounding leaves voice. Voice cannot connect until its server setup is available.
- Race winners use server-stamped finish arrival; Arcade uses survival rather than the highest score. The new settleRound function stores one shared result, including draws. A fallen player can wait for that result or return home. Running rooms survive the host leaving.
- Failed room creation clears the attempted room, avoiding a fake room code after access denial. Permission errors are shortened, and Retry Firebase access now checks Firestore instead of only repeating Authentication.

## What the supplied screenshots establish
Google Authentication succeeded: the app and Firebase console show a Google user. Firestore and Realtime Database report permission denials. Cloud Functions profile and voiceToken return not-found from us-central1, consistent with absent endpoints or a region mismatch. These are distinct services; a new API key is not a remedy for those database rules or missing functions.

The supplied google-services.json matches cloud-hop-8732a, com.cloudhop.cloud_hop and the existing app/API identifiers. It was copied into android/app/google-services.json and the root reference copy. A .firebaserc now selects this project. No client secret or voice service secret is included.

## Backend configuration still required (not performed)
1. In cloud-hop-8732a, review and publish firebase/firestore.rules to Firestore and firebase/database.rules.json to the correct Realtime Database. Keep the root private; use the supplied scoped authenticated grants. A configuration with no grants and read/write false blocks client progress and rooms.
2. Review App Check metrics for these requests. Authentication success alone does not prove Firestore/RTDB App Check acceptance. Retain valid Play Integrity or registered development debug configuration.
3. The functions source must be deployed in the client's configured region, us-central1 by default. Required exports include profile, friends, invitations, matchmaking, voiceToken and the new settleRound database trigger. settleRound targets cloud-hop-8732a-default-rtdb in us-central1.
4. Voice additionally requires a LiveKit server/project and the server-side secrets LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET. Keep these secrets on the server, never in the Flutter app or google-services.json. Firebase app registration does not create a voice server.
5. Coordinate deployment of the updated room rules and functions with this new client protocol. Older rules reject the new mode/target/character/lives/finishedAt fields. Without settleRound, online rounds cannot confirm a winner. No server change has been deployed by this task.

The server settles results from client-reported progress; it is not an authoritative physics/anti-cheat server. No live console, deployed endpoint, device microphone or multiplayer session was tested.

## Music and verification
Music previews and their original composition source are in music/previews. They are awaiting user approval and are not enabled in the app.

Source read-through, existing Dart formatter, and JavaScript syntax-only checks were performed. Existing test source expectations were updated for the new lives/opponent behavior, but NO tests were executed. No dependency installation, app build, release or deployment. Runtime layout, voice, physics balance and network behavior remain unverified. The earlier declared App Check dependency still needs authorized dependency resolution later.

References:
- https://firebase.google.com/docs/firestore/security/get-started
- https://firebase.google.com/docs/database/security
- https://firebase.google.com/docs/functions/database-events
- https://firebase.google.com/docs/app-check/flutter/default-providers
