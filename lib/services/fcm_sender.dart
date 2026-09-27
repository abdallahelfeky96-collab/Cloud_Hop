import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';

/// Sends FCM pushes directly from this device (no relay, no functions).
///
/// Transport: FCM legacy send endpoint with a sender key supplied ONLY via
/// `--dart-define=FCM_SENDER_KEY=...`. The key is never embedded in source
/// or committed. When unset (default), every method returns false and the
/// app relies on foreground RTDB overlays + tap routing on next open.
///
/// NOTE: Google discontinued the legacy send API for most projects, so
/// delivery through this path can fail even with a key. The receive side
/// (PushService) accepts pushes from ANY sender, including a future
/// server-side one, without app changes.
class FcmSender {
  FcmSender._();

  static const _endpoint = 'https://fcm.googleapis.com/fcm/send';

  static Future<bool> _send({
    required String toUid,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      if (AppConfig.fcmSenderKey.isEmpty) return false;
      final snap = await FirebaseDatabase.instance
          .ref('fcmTokens/$toUid/token')
          .get()
          .timeout(const Duration(seconds: 8));
      final token = (snap.value ?? '').toString();
      if (token.isEmpty) return false;
      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse(_endpoint))
            .timeout(const Duration(seconds: 10));
        request.headers.set('Authorization', 'key=${AppConfig.fcmSenderKey}');
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'to': token,
          'notification': {'title': title, 'body': body},
          'data': data,
          'android': {'priority': 'high'},
        }));
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        await response.drain();
        return response.statusCode >= 200 && response.statusCode < 300;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('FCM direct send failed: $e');
      return false;
    }
  }

  static Future<bool> invite({
    required String toUid,
    required String code,
    required String fromName,
  }) => _send(
    toUid: toUid,
    title: 'Room invitation',
    body: '$fromName invited you to room $code',
    data: {'kind': 'invite', 'code': code, 'fromName': fromName},
  );

  static Future<bool> friendRequest({
    required String toUid,
    required String fromUid,
    required String fromName,
  }) => _send(
    toUid: toUid,
    title: 'Friend request',
    body: '$fromName wants to be your friend',
    data: {'kind': 'friend-request', 'from': fromUid, 'fromName': fromName},
  );

  static Future<bool> matchFound({
    required String toUid,
    required String code,
  }) => _send(
    toUid: toUid,
    title: 'Challenger found!',
    body: 'Room $code is starting',
    data: {'kind': 'match', 'code': code},
  );
}
