# Firebase backend work needed for Cloud Hop

Project: cloud-hop-8732a. Google sign-in is already working in the supplied screenshots. The supplied google-services.json matches this project. No need to create a replacement Firebase project or expose the database publicly.

## 1. Publish scoped database rules
In Firebase Console, open this project:
- Build > Firestore Database > Rules: review and publish firebase/firestore.rules from this project. It permits a signed-in player to read/write their own validated progress.
- Build > Realtime Database > Rules: review and publish firebase/database.rules.json. It permits the intended room/player traffic and validates the new Race/Arcade fields.
Keep default/root access denied. Do not replace the rules with global read/write true. If the published rules grant no access at any path, sign-in can work while database requests fail with permission-denied.

These steps address the database denials only. Also inspect App Check request metrics if access is still denied after correct rules are published.

## 2. Deploy the server functions included in the project
The functions/ folder contains profile, friends, invitations, matchmaking, voiceToken, and settleRound. They must exist in the selected Firebase project and the client-configured region (us-central1 by default). settleRound watches this project's default Realtime Database and confirms shared Race/Arcade results.

The screenshots show not-found for profile and voiceToken in us-central1, consistent with undeployed endpoints or a region mismatch. App registration, an API key, and App Check registration do not deploy these functions.

Cloud Functions deployment requires Firebase's Blaze pay-as-you-go plan. Deployment uses Firebase CLI and server dependencies, separately from building an Android app. Those operations were NOT performed because this task is source-only with no installs or deployments. Before a future deployment, validate the updated room protocol/rules and functions together. Changing only the app is insufficient.

## 3. Configure the voice service
The existing voice implementation uses LiveKit. Set up a LiveKit project/server, then configure these server-side Firebase function secrets:
- LIVEKIT_URL
- LIVEKIT_API_KEY
- LIVEKIT_API_SECRET

Deploy voiceToken with those secrets. It authenticates the Firebase user, checks room membership and issues a short-lived voice token. Keep the API secret on the server; do not put it in Flutter code, google-services.json or messages. A Firebase API key is not a LiveKit credential.

## 4. Check App Check for the actual installed app
Review Firestore/Realtime Database request metrics and rejected requests. Ensure the Android signing certificate and Play Integrity configuration match the distributed app. A local debug build uses an explicitly registered debug token when APP_CHECK_DEBUG is enabled. Do not disable all database protections to work around attestation failures.

## 5. Verify on two devices after backend setup
Confirm progress saves; create/join a room; add a friend and accept an invitation; verify matching modes/targets; finish a race; exhaust Arcade attempts; toggle both microphones. This verification has NOT been run in this source-only task.

Official references:
https://firebase.google.com/docs/rules/manage-deploy
https://firebase.google.com/docs/functions/get-started
https://docs.livekit.io/frontends/build/authentication/
https://firebase.google.com/docs/app-check/flutter/default-providers
