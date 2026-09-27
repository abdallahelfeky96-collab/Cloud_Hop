# Character and power-up refinement — 24 September 2026

- Arms shortened to small attached hands, with only a 3-unit swing instead of 11.
- Legs shortened to a 10-unit root-to-foot length instead of 15, with a 2.5-unit horizontal swing instead of 8. Feet stay aligned to the existing collision height.
- Face/hair no longer mirror suddenly on direction changes. Smoothed eye movement is limited to 0.65 horizontal and 0.55 vertical units; the body stays solid.
- Removed the coloured skin marker below the body.
- Practice rival passes its actual simulation animation phase, gaze, movement, airborne state and flip rotation into the shared character renderer.
- Trampoline is enabled in Classic, Race and Arcade whenever inventory is available. Existing three-steps-ahead placement, consumption-on-success, bounce and sound logic are retained. Like the rocket, this is a personal power-up; it does not rewrite opponents' courses.
- Replaced the block beneath the character with a full cartoon rocket backpack behind its body, including nose, window, fins, nozzle and exhaust. It follows the character transform.
- Approved action sound files remain unchanged.

The spoken start announcement has NOT been replaced: it still uses Android's installed offline voice. A natural recorded replacement and approval preview remain pending because no speech-generation tool is available in this session. No recording has been fabricated or claimed.

Validation: Dart formatter/parser completed for affected files and source event paths reviewed. No dependencies installed, app built, tests run or device animation verified. Flutter lint configuration remains unresolved without dependencies.
