import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config.dart';
import 'progress_store.dart';

/// True only when the payload carries an explicit expiry that has passed.
/// A missing `expiresAt` (e.g. older relay payloads) is NOT expired: the
/// room-existence checks downstream are the real validity gate.
bool expiredPush(Map<String, String> data) {
  final raw = data['expiresAt'];
  if (raw == null || raw.isEmpty) return false;
  final expires = int.tryParse(raw);
  return expires != null && expires <= DateTime.now().millisecondsSinceEpoch;
}

Map<String, String> pushData(Map<String, dynamic> data) =>
    data.map((k, v) => MapEntry(k, v.toString()));
const inviteChannel = AndroidNotificationChannel(
  'cloud_hop_invites',
  'Game invitations',
  importance: Importance.high,
);
Future<FlutterLocalNotificationsPlugin> localPush({
  void Function(NotificationResponse)? tapped,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_cloudhop'),
    ),
    onDidReceiveNotificationResponse: tapped,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(inviteChannel);
  return plugin;
}

@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty)
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: AppConfig.effectiveApiKey,
        appId: AppConfig.effectiveAppId,
        messagingSenderId: AppConfig.effectiveSender,
        projectId: AppConfig.effectiveProject,
        databaseURL: AppConfig.effectiveDatabaseUrl,
      ),
    );
  final data = pushData(message.data);
  // The OS already displays notification payloads. Only display data-only here.
  if (message.notification != null || expiredPush(data)) return;
  final plugin = await localPush();
  await plugin.show(
    (message.messageId ?? jsonEncode(data)).hashCode & 0x7fffffff,
    'Cloud Hop invitation',
    'Tap to view your invitation',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'cloud_hop_invites',
        'Game invitations',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

class PushService {
  final ProgressStore store;
  PushService(this.store);
  final _links = StreamController<Map<String, String>>.broadcast();
  final _foreground = StreamController<Map<String, String>>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  Stream<Map<String, String>> get links => _links.stream;
  Stream<Map<String, String>> get foreground => _foreground.stream;
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final plugin = await localPush(
      tapped: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final raw = jsonDecode(payload);
          if (raw is Map)
            _links.add(raw.map((k, v) => MapEntry(k.toString(), v.toString())));
        } catch (_) {}
      },
    );
    await FirebaseMessaging.instance.requestPermission();
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((m) {
        final data = pushData(m.data);
        if (!expiredPush(data)) _foreground.add(data);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _links.add(pushData(m.data)),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(syncToken()),
      ),
    );
    await syncToken();
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _links.add(pushData(initial.data));
    final launch = await plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null) {
      try {
        final raw = jsonDecode(payload);
        if (raw is Map)
          _links.add(raw.map((k, v) => MapEntry(k.toString(), v.toString())));
      } catch (_) {}
    }
  }

  Future<void> syncToken() async {
    final uid = store.uidOrNull;
    if (uid == null || !store.cloud) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty || store.uidOrNull != uid) return;
      await FirebaseDatabase.instance.ref('fcmTokens/$uid').set({
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Push token sync failed: $e');
    }
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _links.close();
    await _foreground.close();
  }
}
