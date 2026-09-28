import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../config.dart';

/// Mints LiveKit JWT access tokens directly on the device using the
/// self-hosted server credentials from [AppConfig].
///
/// This is the ONLY token path the app uses: no backend call happens here,
/// so there is no "service not configured" failure mode beyond the bundled
/// credentials themselves. (The `trusted-service/` server exists as an
/// optional future path; nothing in the app depends on it.)
///
/// WARNING: the API secret ships inside the app binary. Anyone who extracts
/// it gains full control of the LiveKit server. Dev/test servers only.
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

  /// Backwards-compatible request shape: mints locally and returns the
  /// `{token, url}` map the voice service consumes.
  static Future<Map<String, dynamic>> request(
    String room, {
    String? identity,
    String? name,
  }) async {
    final token = generate(room: room, identity: identity ?? 'guest', name: name);
    return {'token': token, 'url': AppConfig.effectiveLivekitUrl};
  }
}
