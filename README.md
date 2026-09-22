# Cloud Hop — Flutter project, version 0.3

SOURCE-ONLY HANDOFF. No Android APK, app bundle, release, deployment, or account creation has been performed. The final handoff was completed without further dependency installation or test runs after your source-only instruction.

## What changed

- Smoother swipe acceleration, reversal and braking. One upward gesture triggers one jump per touch; horizontal swipes steer on platforms and in the air. Up and diagonal swipes jump. Running still increases jump height. Gravity and the +10%-of-initial-speed platform treadmill progression are retained.
- Brief splash followed by a home screen with a large central Play icon, Start label, and Create a room & invite beneath it. Settings is at the top.
- Larger 64-pixel action buttons arranged horizontally. Results keep the central Play again button separate from the lower action row. Back returns to home. Gameplay helpers are in a horizontal row.
- Settings for player name, sound effects, selected mode, country and city. Sound currently controls the system click used for jump feedback; a music soundtrack is not included.
- Classic, Beat my best (a moving target, not a recording of a previous run), and Quick challenge modes.
- Quick challenge searches for a live opponent and falls back after five seconds to a clearly labelled practice bot. The bot alternates leads early and eases off later, allowing a comeback; it cannot guarantee a win if the player falls. Names use the chosen country/city pool. Five countries and two cities per country are included in lib/game/challenge.dart; expand that map to add more.
- Friends by Firebase player ID, accepted friend requests, friend removal, room invitations and joining. Invitations refresh while the Friends panel is open; push notifications are not included. Room codes can also be copied and shared manually.
- Optional room voice through LiveKit, with Firebase callable functions issuing microphone-only room tokens. Join voice requests microphone permission and starts muted; tap again to unmute. Leaving a room, ending a run or backgrounding the app disconnects voice. No camera or recording feature is included.
- Existing coin shop, skins, backgrounds, rockets (500 coins), life (1,000), trampoline (100), platform gifts, end-of-run interstitials and optional rewarded ads remain in the native project.

## Current verification status

Before the final source-only instruction, dependencies were resolved and lockfiles created. Flutter static analysis found no compile errors; lint fixes were then applied. Twelve engine checks, four control/bot checks, home/results layout tests, a small-phone home/game/back test, and seven Node matchmaking/voice-policy tests passed in their respective runs.

The last full Flutter run reported eight passing tests and one failing bot-flow test. That test used Flutter's default landscape viewport, although this app is portrait-only. Its viewport was corrected in the source; it has NOT been rerun. The final navigation edits also have not been retested. Rendered previews were generated locally, but physical-phone visuals, Android compilation, microphone audio between devices, live Firebase races, backend rule enforcement in emulators, and real ad display have not been verified. This is a development project, not a release-tested application.

## Project contents

- lib/main.dart: app lifecycle, screen flow, room lobby and gameplay HUD.
- lib/ui/: home/results design, settings and friends UI.
- lib/game/: physics, renderer, swipe recognition and practice rival.
- lib/services/: local/cloud progress, ads, room networking, friends and voice.
- functions/: Firebase callable backend for profiles, accepted friendships, invites, atomic matchmaking and voice tokens; backend tests and package lock.
- firebase/: Firestore and Realtime Database access rules.
- config/firebase.example.json: public Firebase and ad configuration template.
- android/: Flutter Android scaffold, launcher icon, microphone permission and signing template.
- test/: game, controls and widget tests.
- preview/: locally rendered home/results images.

## Setup later — instructions only

Nothing below has been deployed. You can keep working on the source without creating an account. Online features require Firebase; live voice additionally requires LiveKit Cloud or a self-hosted LiveKit server. Test ads are enabled by default.

When you decide to run the project, use a current Flutter SDK and Android development environment. This source was processed with Flutter 3.47.5 / Dart 3.13.4. From the project directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The SDK, downloaded dependencies, Android tools and local machine paths are deliberately excluded from the archive. Lockfiles are included for reproducibility.

## Firebase configuration

1. Create a Firebase project and register an Android app. Choose the permanent application ID before publishing; the current placeholder is com.cloudhop.cloud_hop. Update android/app/build.gradle.kts and the Kotlin MainActivity package/path if changing its namespace.
2. Enable Anonymous Authentication, create Firestore and Realtime Database, and configure Cloud Functions. Deploying functions may require a billing-enabled Firebase project. No billing or services were enabled for you.
3. Copy config/firebase.example.json to config/firebase.dev.json and fill the Firebase API key, Android app ID, project ID, messaging sender ID and full Realtime Database URL. Keep USE_TEST_ADS true.
4. The source initializes FirebaseOptions explicitly; this implementation does not require google-services.json or a Google Services Gradle plugin.
5. Later, from functions/, install packages using npm ci. Functions target Node 22. From the project root, use the Firebase CLI to deploy to your chosen project:

```sh
firebase deploy --only firestore:rules,database,functions --project YOUR_PROJECT_ID
flutter run --dart-define-from-file=config/firebase.dev.json
```

All callables default to us-central1, matching the client. Social profiles, friendships and invitations are server-managed; the client cannot read or write those collections directly under the provided rules. The matchmaking queue is also server-only. Race positions are client-reported, and the game economy remains client-managed, so these are not cheat-proof competitive rankings or paid currency. Anonymous player IDs are not recoverable after identity loss; account-linking UI is not included.

Test the rules and two-device flows before any public launch. Expired room cleanup and production rate limits/App Check should be configured for scale. A match already committed when someone cancels is explicitly left by that client. Network failures can still cause opponent disconnects, which should be verified on devices.

Reference: https://firebase.google.com/docs/flutter/setup

## LiveKit voice configuration

LiveKit carries audio; Firebase handles identity, room membership and token issuance. The secret values must never go into the app or the archive. With your own Firebase and LiveKit projects configured, set these Firebase function secrets later:

```sh
firebase functions:secrets:set LIVEKIT_URL --project YOUR_PROJECT_ID
firebase functions:secrets:set LIVEKIT_API_KEY --project YOUR_PROJECT_ID
firebase functions:secrets:set LIVEKIT_API_SECRET --project YOUR_PROJECT_ID
```

LIVEKIT_URL is the wss:// URL of your LiveKit server. Then deploy the functions. A caller must be an active member of the requested game room; tokens are restricted to that room and microphone publishing and have a five-minute initial connection expiry. Joined clients can receive audio and explicitly unmute to transmit. For production, also enforce server-side participant removal when membership ends; token expiry alone does not terminate an already established media session. Add player blocking/reporting and moderation appropriate to the intended audience before public voice access.

Reference: https://docs.livekit.io/transport/sdk-platforms/flutter/

## Ads and later release preparation

Google sample Android app and unit IDs are included. Interstitials are attempted after each run only when loaded and consent permits. Rewarded coins require the SDK reward callback; closing early earns nothing.

For live ads later, create your AdMob account/app and units, replace the sample app ID in android/app/src/main/AndroidManifest.xml, and set your ad unit IDs plus USE_TEST_ADS false in a private production configuration. Configure and test consent messages and privacy options. No live advertising account has been created.

Release signing is intentionally not configured. android/key.properties.example shows the required fields for a future private upload keystore. No build or release was performed. Before any Play Store upload, complete device testing, backend/voice setup, release signing, privacy/data-safety declarations and the current Play Console requirements.

Ads references: https://developers.google.com/admob/flutter/quick-start and https://developers.google.com/admob/flutter/test-ads
