import 'package:flutter/foundation.dart';

/// Shared button feedback; nested controls produce one click per activation.
class UiSounds {
  static VoidCallback? click;
  static final _clock = Stopwatch()..start();
  static int _last = -1000;
  static ValueChanged<T> change<T>(ValueChanged<T> action) => (value) {
    wrap(() => action(value))!();
  };
  static VoidCallback? wrap(VoidCallback? action) {
    if (action == null) return null;
    return () {
      final now = _clock.elapsedMilliseconds;
      if (now - _last > 45) {
        _last = now;
        click?.call();
      }
      action();
    };
  }
}
