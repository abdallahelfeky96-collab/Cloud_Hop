import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'livekit_token.dart';

/// Ephemeral LiveKit voice chat for a match room. Nothing is stored:
/// the token is minted on-device at join time and everything is released
/// on [leave] (disconnect + listener cancel + room dispose).
class VoiceService extends ChangeNotifier {
  VoiceService();
  Room? _room;
  CancelListenFunc? _cancelMicEvents;
  String lastError = '';
  bool muted = true, speaker = true, busy = false;
  int _generation = 0;
  bool get connected => _room?.connectionState == ConnectionState.connected;

  /// Source of truth for the microphone: the published track state.
  bool get micLive => _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  void _syncMicState() {
    final live = micLive;
    if (muted == live) {
      muted = !live;
      notifyListeners();
    }
  }

  void _watchMicEvents(Room room) {
    _cancelMicEvents = room.events.listen((event) {
      if (event is TrackMutedEvent ||
          event is TrackUnmutedEvent ||
          event is LocalTrackPublishedEvent) {
        _syncMicState();
      }
    });
  }

  /// Joins [code] as an audio-only participant: requests the microphone
  /// first, mints a 2-hour token locally, connects, then publishes the
  /// microphone unless [startMuted]. Remote tracks auto-subscribe and play.
  /// Pre-connect muted on room join so the mic tap unmutes with ~0 latency.
  Future<void> join(
    String code, {
    String? displayName,
    String? identity,
    bool startMuted = true,
  }) async {
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
      if (generation != _generation) return;
      final id = (identity ?? '').trim().isEmpty ? 'guest' : identity!.trim();
      final token = LiveKitToken.generate(
        room: code,
        identity: id,
        name: displayName,
      );
      final url = AppConfig.effectiveLivekitUrl;
      if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
        throw StateError('LiveKit server URL is invalid.');
      }
      pending = Room();
      await pending.connect(url, token);
      if (generation != _generation) {
        await pending.disconnect();
        await pending.dispose();
        return;
      }
      _room = pending;
      _room!.addListener(notifyListeners);
      _watchMicEvents(_room!);
      await AudioManager.instance.setSpeakerOutputPreferred(speaker);
      await _room!.localParticipant?.setMicrophoneEnabled(!startMuted);
      if (generation != _generation) return;
      // Read back the published track: only show ON when it is really live.
      _syncMicState();
      if (muted && !startMuted) {
        lastError = 'Microphone published but not live. Rejoin voice.';
        debugPrint('Voice publish: $lastError');
      } else {
        lastError = '';
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('Voice join failed: $e');
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
      if (generation == _generation) _syncMicState();
    } finally {
      busy = false;
      if (generation == _generation) notifyListeners();
    }
  }

  /// Speaker output on/off (earpiece/headset when off).
  Future<void> setSpeaker(bool on) async {
    speaker = on;
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(on);
    } catch (e) {
      debugPrint('Speaker toggle: $e');
    }
    notifyListeners();
  }

  /// Clean teardown: disconnects, cancels listeners and releases all audio
  /// track resources so no server connection leaks after a match.
  Future<void> leave() async {
    _generation++;
    final old = _room;
    _room = null;
    muted = true;
    lastError = '';
    _cancelMicEvents?.call();
    _cancelMicEvents = null;
    old?.removeListener(notifyListeners);
    await old?.disconnect();
    await old?.dispose();
  }
}
