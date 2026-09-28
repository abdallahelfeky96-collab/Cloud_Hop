# Emergency audit and refactor — 27 September 2026

## Baseline and scope
Latest supplied archive: Cloud_Hop-main (1).zip, preserved separately as Cloud_Hop-main.original.zip.
SHA-256: 5942D0318B1269DFF34DAD819380FC50FF004CCD68DB53AB37108B3133EC5D8B.
This is the new working baseline; the 23 September project was not overwritten.

Source review covered game engine/painter/input, match and social services, room lifecycle, voice, notification send/receive, progress persistence, UI/shop wiring, Firebase rules, Android configuration, audio loading and dependency declarations. This is a static code review with focused executable checks, not a production security certification or full Flutter/device validation.

## Findings and changes
| Area | Underlying problem | Change |
|---|---|---|
| Settlement | Three inconsistent paths; ready players excluded from alive count; idle survivors could win; local result bypassed shared room result | Shared pure evaluateMatch policy, finish timestamps first, ready barrier, AFK progress exclusion, current-round result metadata; eliminated clients wait for shared result |
| Startup | Same-room attach could run destructive leave; room map initially empty while listeners initialized; transient DB errors disconnected voice | Idempotent attach, initialize snapshot before listeners, atomic start timestamp only, retain stream through live transition, independent voice transport |
| Rematch | Old finish timestamps/lives survived; new round could see previous player state | Round identifier on player/result/throw records; reset own ready state and finish timestamp; stale round blocks settlement; preserve same-room rematch |
| Spectator | Out status sent before entering spectator; normal results/ads could remove player early | Immediate spectator state and publish; keep room screen until shared settlement; no mid-round rematch |
| Meteors | Automatic wild-rock timer; vertical one-rock throw; retired rocks could reappear from event log | Timer removed; paid event creates seeded 5–10 diagonal meteors, 0.3–2.5 scale, staggered starts and speed variation; boundary culling; event dedupe and round filtering |
| Payment | Rock ammo bypassed requested price; failed publication kept coins spent | Each accepted trigger costs 2000 coins; failed publication refunds; button-only trigger. Existing rock inventory is retained but no longer bypasses this explicit price |
| Voice | API signing secret in app; preconnect bookkeeping blocked reconnect; transient DB errors killed audio | Secret removed, room-scoped token fetched over authenticated HTTPS; preconnect shared by private/random rooms; recoverable retries; no mic transmission until user unmutes |
| Push | Retired FCM legacy endpoint; no expiry validation; delayed cold-start event could be lost; invalid room code could create a new room | FCM v1 trusted sender, subscribed-before-init notification routing, native/background and data-only local notifications, foreground suppression/dialog, expiresAt check and room validation before joining |
| Other | Friendship IDs split on underscore; old matched queue entries reused; missing gameplay.wav breaks loader | Preserve full UIDs; ignore stale queue records; restore approved nature ambience |
| Visuals | Round head without specified clothing | Existing hair/face retained above drawn outfit: white shirt, gold chain, light-blue shorts, white sneakers; pink flared dress and pink sneakers for female |

Shop prices, owned cosmetics, balances and core jump physics were preserved. Existing Firestore progress/profile persistence remains to avoid discarding users' saved data; rooms/social events use RTDB. Old Cloud Functions source is archived under legacy and excluded from the delivered ZIP; no active deployment config references Functions.

## Deliberate architecture exception: secret-bearing operations
All-device FCM v1 OAuth and LiveKit signing are NOT implemented. Shipping either administrative secret in Flutter would expose it to every app recipient. The pasted service-account key must be revoked; rotate the old bundled LiveKit secret too. No supplied private key was written to the working app.

A small ordinary HTTPS service is supplied under trusted-service (Node, deployable to Cloud Run or an existing host). It uses server-side Application Default Credentials for FCM HTTP v1 and environment secrets for LiveKit. It verifies Firebase ID tokens, room membership/invitation state, recipient permissions, expiry and a basic per-user rate limit. This uses ZERO Cloud Functions, but it is not a purely client-side architecture. Hosting and configuration remain required. Do not describe push/voice as live before that is complete.

## Validation
- 20 existing pure-Dart engine checks passed (shop, coins, input, physics, power-ups, lives, spectator and rematch).
- 13 additional pure-Dart checks passed (finish/AFK/ready policy and meteor behavior).
- Existing rock tests were updated from single accelerating rocks/skip-sender to the explicitly requested seeded shower model; their initial failure was an obsolete expectation, not hidden.
- Dart formatter parsed affected source; Node syntax check passed for trusted-service/server.mjs.
- A secret-pattern scan of 64 text source/config/document files found no private-key blocks or embedded LiveKit API-secret assignment patterns. This is a limited check, not a guarantee.
- No dependency installs, APK/app builds, deployments, Firebase emulator sessions or two-device tests were performed. Full Flutter analyzer/null-safety verification is pending dependency resolution. Source uses sound null safety, but 100% runtime safety is not claimed.

## Remaining risks / required checks
1. Client-authored scores and locally stored coins are not cheat-proof. Rules validate shape/membership/round, not physics or monetary authority. A modified client can falsify progress or bypass a local charge. Trusted authoritative settlement/economy would be needed to prevent that.
2. Shared finish order is based on server receipt timestamps. Network latency can differ from physical arrival order.
3. Preconnected mute/unmute avoids another room connection, but zero latency cannot be guaranteed by a network/audio SDK.
4. Notifications require permission, Play services, token registration and a running trusted sender. Android force-stop and OS delivery restrictions still apply.
5. Existing progress merge uses maximum values when reconciling cloud/local balances; multi-device spending is not a transactional wallet. It was not replaced because that requires a migration/economy decision.
6. New local-notification dependency is declared but not installed; pubspec.lock must be regenerated before a future build.
7. Visual rendering and private/random multiplayer must be checked on phones after setup. No exact screenshot comparison or live voice/FCM delivery was performed here.

See SETUP_WITHOUT_CLOUD_FUNCTIONS.md for setup and acceptance checks.
