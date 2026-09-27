# Character animation update — 2026-09-24

The gameplay character now uses a separate body atlas derived from the supplied male/female artwork, plus individually drawn shaded arms, legs and eyes. Original character artwork is preserved for profile portraits.

- Longer arms and legs swing in opposite phases and remain visible beyond the body silhouette.
- The animation phase follows running speed and airborne movement, separately from physics/jump charge.
- Eyes smoothly follow horizontal and vertical velocity, return toward neutral when stationary and blink periodically.
- Normal source-over compositing replaces multiply. An alpha-only color filter raises the generated body's near-opaque interior to full opacity while preserving clear surrounding space and antialiased edges.
- Existing reduced-motion preference suppresses limb cycling and blinking.
- Collision bounds, movement physics, coins, multiplayer and sound rules unchanged.

Verification: inspected new artwork and alpha samples; Dart formatting/parser completed. No app build, dependency installation or device testing performed. Flutter lint configuration cannot resolve without the project's dependencies.
