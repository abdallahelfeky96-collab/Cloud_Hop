import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'progress_store.dart';

/// Background entry point. Notification messages display in the tray
/// automatically; this keeps the isolate valid for data handling.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.effectiveApiKey,
          appId: AppConfig.effectiveAppId,
          messagingSenderId: AppConfig.effectiveSender,
          projectId: AppConfig.effectiveProject,
          databaseURL: AppConfig.effectiveDatabaseUrl,
        ),
      );
    }
  } catch (e) {
    debugPrint('Push background init: $e');
  }
}

/// Payload contract shared with the sender (see tools/fcm-relay.js):
/// `{kind: invite|friend-request|match, code?, from?, fromName?}`.
/// Works for Anonymous (guest) and Google users alike: routing keys are
/// Firebase uids, and the FCM token is stored per uid.
class PushService {
  final ProgressStore store;
  PushService(this.store);

  final _links = StreamController<Map<String, String>>.broadcast();
  final _foreground = StreamController<Map<String, String>>.broadcast();

  /// Taps on notifications (background/terminated).
  Stream<Map<String, String>> get links => _links.stream;

  /// Messages arriving while the app is open.
  Stream<Map<String, String>> get foreground => _foreground.stream;

  static Map<String, String> _dataOf(RemoteMessage message) => {
    for (final e in message.data.entries) e.key: e.value.toString(),
  };

  Future<void> init() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
      FirebaseMessaging.onMessage.listen((m) {
        final data = _dataOf(m);
        if (data['kind'] != null) _foreground.add(data);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final data = _dataOf(m);
        if (data['kind'] != null) _links.add(data);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final data = _dataOf(initial);
        if (data['kind'] != null) {
          // Delivered after first frame by the consumer via links stream.
          unawaited(
            Future<void>.delayed(
              const Duration(seconds: 1),
              () => _links.add(data),
            ),
          );
        }
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        unawaited(syncToken());
      });
      await syncToken();
    } catch (e) {
      debugPrint('Push init: $e');
    }
  }

  /// Registers this device for background pushes. Safe to call repeatedly
  /// (e.g. after every sign-in or retry): no-ops while signed out.
  Future<void> syncToken() async {
    try {
      final uid = store.uidOrNull;
      if (uid == null || !store.cloud) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await FirebaseDatabase.instance.ref('fcmTokens/$uid').set({
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Push token sync: $e');
    }
  }
}
