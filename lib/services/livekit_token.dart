import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../config.dart';

/// Mints LiveKit JWT access tokens directly on the device using the
/// self-hosted server credentials from [AppConfig].
///
/// WARNING: the API secret ships inside the app binary. Anyone who extracts
/// it gains full control of the LiveKit server. Dev/test servers only —
/// production should mint tokens server-side (see the `voiceToken` Cloud
/// Function in functions/).
class LiveKitToken {
  LiveKitToken._();

  /// Ephemeral voice token: valid 2 hours, scoped to a single room.
  /// No room state is stored anywhere; disconnecting discards everything.
  static String generate({
    required String room,
    required String identity,
    String? name,
    Duration ttl = const Duration(hours: 2),
  }) {
    final cleanRoom = room.trim();
    final cleanIdentity = identity.trim().isEmpty ? 'guest' : identity.trim();
    if (cleanRoom.isEmpty) throw StateError('Room name is required.');
    if (!AppConfig.livekitConfigured) {
      throw StateError('LiveKit server is not configured.');
    }
    final jwt = JWT(
      {
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        'video': {
          'roomJoin': true,
          'room': cleanRoom,
          'canPublish': true,
          'canSubscribe': true,
          'canPublishData': true,
        },
      },
      issuer: AppConfig.effectiveLivekitKey,
      subject: cleanIdentity,
    );
    return jwt.sign(
      SecretKey(AppConfig.effectiveLivekitSecret),
      expiresIn: ttl,
    );
  }
}
