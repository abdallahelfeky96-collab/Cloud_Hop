# Setup without Cloud Functions

Nothing in this checklist was executed. No dependencies were installed and nothing was deployed.

1. Revoke the service-account key shared in the conversation. Do not embed a replacement key in Android. Rotate the LiveKit secret from the old app as well.
2. Review/publish this version's firebase/database.rules.json and existing firebase/firestore.rules. The new round/count/seed/score/movement fields require the matching rules. Keep root access denied.
3. Host trusted-service on Cloud Run or your existing HTTPS Node 22 server. Resolve its declared packages in that deployment environment. Use an attached service identity/Application Default Credentials, with the minimum permissions for Firebase ID-token verification, required RTDB reads/limits and FCM message sending. No key JSON belongs in Flutter.
4. Configure server environment: LIVEKIT_URL (wss://...), LIVEKIT_API_KEY, LIVEKIT_API_SECRET; optionally FIREBASE_DATABASE_URL for the correct instance. Keep secrets in your server's secret store. Server defaults to project cloud-hop-8732a and its supplied default RTDB.
5. Configure Flutter with TRUSTED_SERVICE_URL=https://your-service-host. The app sends its Firebase ID token to /voice and /push. These routes verify authorization and must not be exposed as unauthenticated open senders. Review production rate limits/monitoring before publishing.
6. At a later authorized build step, resolve Flutter dependencies, regenerate pubspec.lock and run full flutter analyze plus widget tests. flutter_local_notifications is added in pubspec.yaml; Android desugaring/channel/icon source is included.
7. Test notifications with the app foreground, background and normally terminated. Foreground must show only an in-app invitation; tapping a current notification opens the actual room/friend dialog. Expired/missing timestamps show Invite Expired. Native notification and local data-only notification paths must not duplicate.
8. Test two real devices in private and random rooms: first Start, three attempts, spectator overlay, 2000-coin throw, 5–10 diagonal rocks, finish ordering, AFK opponent, same-room rematch and mic reconnect. Verify the host closing a lobby is the only intentional lobby deletion.
9. Test the requested male/female outfits, controls, inventory, shop purchases and approved sounds. Review server access logs without logging authorization tokens or voice credentials.

The trusted service is necessary for secure FCM v1/LiveKit credentials; this is a deliberate exception to the requested entirely client-side implementation. It does not use Cloud Functions.

Official references:
https://firebase.google.com/docs/cloud-messaging/server-environment
https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
https://docs.livekit.io/frontends/build/authentication/
https://pub.dev/packages/flutter_local_notifications/versions/19.5.0
