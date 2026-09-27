# Gameplay and Firebase source update — 23 September 2026

## Gameplay
- Human room and Quick Challenge races show the microphone at bottom-right. It joins voice muted and then toggles mute/unmute. Voice still requires the existing voice backend configuration.
- Pause controls, rewarded revival, rewarded coin buttons and rewarded platform gifts are Classic-only. Beat My Best and Quick Challenge do not offer these rewards. Ordinary gifts and end-of-game interstitial ads are unchanged.

## Firebase source review
The bundled Android configuration and Dart fallback agree on project `cloud-hop-8732a`, Android package `com.cloudhop.cloud_hop`, app ID and Realtime Database URL. This checks source consistency, not a live connection or the installed APK's signing certificate.

Changes:
- A Firestore denial no longer marks an authenticated session as disconnected or blocks Google sign-in.
- Google sign-in initializes Firebase directly; successful anonymous sign-in is no longer a prerequisite.
- Errors identify the failing service and Firebase code; the profile displays diagnostics and a retry action.
- App Check activation now precedes Firebase service requests. Android uses Play Integrity; explicitly enabled non-release debug builds can use the debug provider.
- Cloud Functions region is configurable, defaulting to `us-central1`. Quick Challenge retries sign-in while preserving its five-second bot fallback.
- Pending progress writes capture their account owner to avoid writing to a different account after sign-in changes.

## Do read/write false rules affect it?
Yes, when no more-specific rule grants access, client database reads and writes are denied. This affects saved progress and room traffic, but database rules do not directly enable or disable Firebase Authentication. An administrator-restricted sign-in error requires checking Authentication settings separately.

Keep the databases private. Do NOT set global read/write to true. The supplied `firestore.rules` grant validated access to a player's own progress, and `database.rules.json` grant specific authenticated room operations. RTDB root false with explicit allowed child paths is normal; it is different from denying every path. The rules actually published in the console must match the intended secure rules for the correct project.

Friends, invitations and matchmaking use the functions in `functions/index.js`. Those functions use the Admin SDK, which bypasses client Firestore security rules. Their private social collections can remain denied to direct clients. The functions must be deployed in the configured region and have appropriate server permissions; registering an Android app and API key alone does not deploy them.

## Console checks still needed
1. Authentication: enable Google and Anonymous if guest online play is desired. For `admin-restricted-operation`, inspect account creation restrictions and enabled providers. Google sign-in can now proceed even if Anonymous is disabled.
2. Confirm the actual installed app's signing SHA-1 for Google sign-in and SHA-256 for App Check. For Play-distributed builds, include the Play App Signing certificate.
3. App Check: registration alone does not initialize the app SDK. Review request metrics and Play Integrity distribution requirements. Local debug testing requires `APP_CHECK_DEBUG=true` and registration of its debug token in Firebase; never publish or share that token. Release builds always use Play Integrity.
4. Publish the intended per-user Firestore and per-room RTDB rules to the correct databases. Review rules before publishing; no rules were deployed by this update.
5. Confirm the required callable functions exist in `us-central1`, or set `FIREBASE_FUNCTIONS_REGION` to their actual region. Inspect function logs when requests fail.
6. If an API key is restricted, verify its Android package/signing restrictions and required Firebase APIs. A client API key does not override Authentication, rules or App Check.

## Delivery limits
Source only. No dependencies installed, tests executed, app builds, releases, deployments or live Firebase requests were performed. Existing Dart formatter was used; runtime behavior is unverified.

`firebase_app_check: ^0.4.8` was declared in pubspec.yaml but not downloaded. pubspec.lock remains from the original project and needs normal dependency resolution later, when authorized. The original accepted ZIP is preserved unchanged.

References:
- https://firebase.google.com/docs/database/security
- https://firebase.google.com/docs/rules/basics
- https://firebase.google.com/docs/auth/flutter/anonymous-auth
- https://firebase.google.com/docs/app-check/flutter/default-providers
- https://firebase.google.com/docs/app-check/flutter/debug-provider
