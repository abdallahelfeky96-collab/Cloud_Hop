import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android handles preloading/mixing, independent of the 120 Hz physics loop.
class GameAudio {
  static const _channel = MethodChannel('cloud_hop/audio');
  bool _disposed = false, _active = false;
  String _state = '';
  Future<void> _call(String method, [Object? arguments]) async {
    if (_disposed || kIsWeb || defaultTargetPlatform != TargetPlatform.android)
      return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      /* Source-only/non-Android previews stay silent. */
    } on PlatformException catch (error) {
      debugPrint('Game audio: ${error.code}');
    }
  }

  void preload() => unawaited(_call('preload'));
  void sync({
    required bool playing,
    required bool sound,
    required bool foreground,
    required bool ad,
    required bool voice,
  }) {
    _active = sound && foreground && !ad;
    final ambience = playing && _active;
    final next = '$_active/$ambience/$voice';
    if (next == _state) return;
    _state = next;
    unawaited(
      _call('state', {'play': ambience, 'allowed': _active, 'voice': voice}),
    );
  }

  void cue(String name) {
    if (_active) unawaited(_call('cue', name));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await _call('release');
    _disposed = true;
  }
}
