# Screenshot fixes and required server setup — 24 September 2026

## Findings
1. Settings: the screenshot confirms local saving succeeded but online profile saving failed. It does not reveal the exact backend error. The profile callable is included in source; deploying it and matching project/region must be verified. Saving settings now retains local data, exposes a concise error and copyable diagnostics, and offers retry. Save stays pinned below the scrollable settings list with bottom/keyboard padding.
2. Matchmaking: the screenshot shows the intended practice fallback after online matchmaking failed. It is not evidence of a successful human match. The error path now retains technical diagnostics in debug logs and gives a short explanatory message. Fixed a race between the fallback timer and the error handler. Human matching still requires the deployed matchmaking function and working database permissions.
3. Voice: the screenshot explicitly reports voiceToken / us-central1 / not-found. This is consistent with a missing callable endpoint, wrong region or wrong project; live deployment was not inspected. The app now checks token availability before requesting microphone permission, validates returned credentials, and cancels stale joins when leaving a room. Technical exception dumps no longer cover gameplay. Practice rivals have no microphone because no human voice room exists.
4. Rival names overlapped the hair. Name labels are now above the taller sprite with a light backing.
5. Character selection is now included in profile synchronization. Callable deployment region is explicitly us-central1, matching the default client setting.

## Backend checklist (not executed)
Use the existing Firebase project cloud-hop-8732a. Do not create another project or replace the API key as a workaround.

1. In Firebase Console > Functions, check for profile, friends, invitations, matchmaking, voiceToken and settleRound in us-central1. A developer with Firebase CLI access can inspect:
   firebase functions:list --project cloud-hop-8732a
2. Confirm the project supports Cloud Functions deployment (Firebase documentation currently requires Blaze). Review billing in the console before changing a plan.
3. Configure the existing LiveKit service's secrets on the server only, never in Flutter or google-services.json:
   firebase functions:secrets:set LIVEKIT_URL --project cloud-hop-8732a
   firebase functions:secrets:set LIVEKIT_API_KEY --project cloud-hop-8732a
   firebase functions:secrets:set LIVEKIT_API_SECRET --project cloud-hop-8732a
   LIVEKIT_URL must be the secure wss:// URL. The other values come from that same LiveKit project.
4. After server dependencies are available and reviewed, deploy this project's functions from the project root:
   firebase deploy --only functions --project cloud-hop-8732a
5. Review and publish the scoped rules in firebase/firestore.rules and firebase/database.rules.json. Deny-by-default roots are intentional. If every path denies access with no scoped allowance, signed-in users cannot save progress or join rooms. Keep the database private; do not use globally public read/write rules.
6. Inspect App Check metrics and the installed Android app's signing certificate if permission-denied remains. App registration and API keys do not deploy Functions or grant database access.
7. Verify on two devices: profile sync, matching same mode/target, rooms, invitations, mic on/off, shared results. This has not been performed.

## Validation and limits
Dart formatting/parser and node --check functions/index.js completed. No dependencies installed, tests executed, app built, backend deployed or device playback verified. The updated source fixes client issues; it cannot make an absent server endpoint exist until the backend is deployed/configured.

References:
https://firebase.google.com/docs/functions/locations
https://firebase.google.com/docs/functions/get-started
https://firebase.google.com/docs/database/security
https://docs.livekit.io/frontends/build/authentication/
