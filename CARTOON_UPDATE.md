# Cartoon controls and full-screen update — 2026-09-23

Applied to the user's accepted Cloud_Hop-main project, not the earlier generated project. The preserved original archive and BASELINE.json remain unchanged.

Changes:
- Added assets/ui/cartoon_controls.png: a transparent atlas of 25 illustrated controls derived from the approved artwork. It is registered in pubspec.yaml; no package dependencies were added.
- Added lib/ui/cartoon_controls.dart: atlas loading/caching, explicit sprite regions, illustrated icon mapping, accessible labelled buttons, disabled states, gentle idle breathing, press squash/rebound, and reduced-motion support.
- Connected cartoon artwork to home/results, gameplay helpers, profile placeholder, shop, room, friends, voice, reward/revive, sound and mode controls. Real Google profile photos remain intact. Secondary form buttons use cream/gold colors with outlined rounded shapes. Standard radio indicators and utility glyphs without approved artwork remain functional.
- Platform gift/ad markers use the same artwork and gently bob when reduced motion is off.
- Main Play is an illustrated 128px animated control. Main action buttons retain 64px touch targets. The header title now scales down between profile/settings controls on narrow screens.
- Added Android native immersive system-bar and display-cutout handling via a Flutter MethodChannel, with edge-to-edge Flutter layout, transparent system-bar colors, and restoration after focus changes, app resume and ads. Background painting remains outside SafeArea; controls remain inside it.
- Updated existing test source selectors for the artwork widgets and disabled idle animation in static layout test captures. Tests were NOT executed.

Verification scope: source read-through and Dart source formatting only. No dependency installs, analyzer runs, tests, Android builds, releases, or deployments. Device-specific full-screen behavior, asset placement and animation feel are not runtime-verified. A device/OEM setting that forcibly hides the camera cutout may still override app presentation.

Existing preview images inherited from the user's archive describe the prior interface; they are not screenshots of this update. The new atlas is the artwork reference for this change.

Account, economy, matchmaking and physics behavior were not intentionally changed; the review findings in the acceptance report remain separate work.

Android/Flutter references used for the display implementation:
- https://developer.android.com/develop/ui/views/layout/display-cutout
- https://developer.android.com/develop/ui/views/layout/edge-to-edge
- https://api.flutter.dev/flutter/services/SystemChrome/setEnabledSystemUIMode.html
