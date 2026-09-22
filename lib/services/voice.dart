import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import 'social.dart';

class VoiceService extends ChangeNotifier {
  final SocialService social;
  VoiceService(this.social);
  Room? _room;
  bool muted = true, busy = false;
  int _generation = 0;
  bool get connected => _room?.connectionState == ConnectionState.connected;
  Future<void> join(String code) async {
    if (busy || connected) return;
    final generation = ++_generation;
    busy = true;
    notifyListeners();
    Room? pending;
    try {
      if (!await Permission.microphone.request().isGranted) {
        throw StateError(
          'Microphone permission is needed to join voice. You can still race.',
        );
      }
      final credentials = await social.call('voiceToken', {'code': code});
      pending = Room();
      await pending.connect(
        credentials['url'] as String,
        credentials['token'] as String,
      );
      if (generation != _generation) {
        await pending.disconnect();
        await pending.dispose();
        return;
      }
      _room = pending;
      _room!.addListener(notifyListeners);
      // Joining starts muted. The player explicitly unmutes to transmit.
      muted = true;
    } catch (_) {
      await pending?.disconnect();
      await pending?.dispose();
      rethrow;
    } finally {
      busy = false;
      if (generation == _generation) notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (!connected || busy) return;
    final generation = _generation;
    busy = true;
    try {
      await _room!.localParticipant?.setMicrophoneEnabled(muted);
      if (generation == _generation) muted = !muted;
    } finally {
      busy = false;
      if (generation == _generation) notifyListeners();
    }
  }

  Future<void> leave() async {
    _generation++;
    final old = _room;
    _room = null;
    muted = true;
    old?.removeListener(notifyListeners);
    await old?.disconnect();
    await old?.dispose();
  }
}
