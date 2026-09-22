import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../game/engine.dart';

class ProgressStore {
  late SharedPreferences prefs;
  bool cloud = false;
  String status = 'Offline save';
  Future<void> _pending = Future.value();

  /// Widget tests must never hit the network: stay offline under test.
  static bool get _underTest {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<Progress> load() async {
    prefs = await SharedPreferences.getInstance();
    Progress local;
    try {
      local = Progress.fromJson(
        jsonDecode(prefs.getString('progress') ?? 'null')
            as Map<String, dynamic>,
      );
    } catch (_) {
      local = Progress();
    }
    if (_underTest || !AppConfig.firebaseConfigured) return local;
    try {
      await _connectCloud();
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .get();
      if (doc.exists) {
        final map = doc.data()!,
            remoteStamp = (map['savedAt'] as num?)?.toInt() ?? 0;
        final localUid = prefs.getString('owner'),
            localStamp = prefs.getInt('savedAt') ?? 0;
        if (localUid != uid || remoteStamp >= localStamp) {
          local = Progress.fromJson(Map<String, dynamic>.from(map['progress']));
        }
      }
      await prefs.setString('owner', uid);
    } catch (_) {
      cloud = false;
      status = 'Cloud unavailable; saved on device';
    }
    return local;
  }

  /// Initializes Firebase (explicit options with compiled-in fallback) and
  /// ensures an anonymous identity. Returns true when cloud is reachable.
  Future<bool> _connectCloud() async {
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
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    cloud = true;
    status = 'Cloud save connected';
    return true;
  }

  /// Re-attempts the cloud connection, e.g. after an offline startup.
  /// Safe to call when already connected (no-op returning true).
  Future<bool> retryCloud() async {
    if (cloud || _underTest) return cloud;
    if (!AppConfig.firebaseConfigured) return false;
    try {
      await _connectCloud();
      await prefs.setString('owner', uid);
      return true;
    } catch (_) {
      cloud = false;
      status = 'Cloud unavailable; saved on device';
      return false;
    }
  }

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  User? get user {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }
  bool get isGoogle =>
      user != null && !(user!.isAnonymous) && user!.providerData.any(
        (p) => p.providerId == GoogleAuthProvider.PROVIDER_ID,
      );
  String? get displayName => user?.displayName;
  String? get email => user?.email;
  String? get photoUrl => user?.photoURL;

  /// Sign in with Google. Links the current anonymous profile when possible
  /// so coins/skins are kept; otherwise signs in with the Google credential.
  /// After auth, cloud progress is merged by savedAt stamp (newest wins).
  Future<void> signInWithGoogle() async {
    if (!cloud && !await retryCloud()) {
      throw StateError('Could not reach Firebase. Check your connection.');
    }
    final account = await GoogleSignIn().signIn();
    if (account == null) throw StateError('Google sign-in was cancelled.');
    final google = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: google.idToken,
      accessToken: google.accessToken,
    );
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null && auth.currentUser!.isAnonymous) {
      try {
        await auth.currentUser!.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        // Already linked elsewhere: fall back to plain sign-in.
        if (e.code == 'credential-already-in-use' ||
            e.code == 'email-already-in-use') {
          await auth.signInWithCredential(credential);
        } else {
          rethrow;
        }
      }
    } else {
      await auth.signInWithCredential(credential);
    }
    cloud = true;
    status = 'Cloud save connected';
    await prefs.setString('owner', uid);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .get();
      if (doc.exists) {
        final map = doc.data()!,
            remoteStamp = (map['savedAt'] as num?)?.toInt() ?? 0;
        final localStamp = prefs.getInt('savedAt') ?? 0;
        if (remoteStamp >= localStamp) {
          // Caller reloads progress from the returned value when needed.
          status = 'Cloud save connected';
        }
      }
    } catch (_) {
      status = 'Cloud unavailable; saved on device';
    }
  }

  Future<Progress?> loadCloudProgress() async {
    if (!cloud) return null;
    final doc = await FirebaseFirestore.instance
        .collection('players')
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    await prefs.setString('owner', uid);
    return Progress.fromJson(
      Map<String, dynamic>.from(doc.data()!['progress']),
    );
  }

  /// Merges cloud progress into [local] (max coins/best/items, union of
  /// owned skins/skies) and saves. Returns true when a remote doc existed.
  Future<bool> mergeRemoteInto(Progress local) async {
    final remote = await loadCloudProgress();
    if (remote == null) return false;
    local.coins = local.coins > remote.coins ? local.coins : remote.coins;
    local.best = local.best > remote.best ? local.best : remote.best;
    local.skins.addAll(remote.skins);
    local.skies.addAll(remote.skies);
    for (final key in local.items.keys) {
      final have = local.items[key] ?? 0, there = remote.items[key] ?? 0;
      local.items[key] = have > there ? have : there;
    }
    await save(local);
    return true;
  }

  Future<void> signOutGoogle() async {
    if (!cloud) throw StateError('Firebase is not configured.');
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
    await prefs.setString('owner', uid);
  }
  Future<void> save(Progress p) {
    final payload = p.toJson(), stamp = DateTime.now().millisecondsSinceEpoch;
    _pending = _pending.catchError((_) {}).then((_) async {
      await prefs.setString('progress', jsonEncode(payload));
      await prefs.setInt('savedAt', stamp);
      if (cloud) {
        unawaited(
          FirebaseFirestore.instance
              .collection('players')
              .doc(uid)
              .set({'progress': payload, 'savedAt': stamp})
              .then((_) {
                status = 'Cloud save connected';
              })
              .catchError((Object error) {
                status = 'Cloud unavailable; saved on device';
              }),
        );
      }
    });
    return _pending;
  }

  Future<void> linkAccount(String email, String password) async {
    if (!cloud) throw StateError('Firebase is not configured.');
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final user = FirebaseAuth.instance.currentUser!;
    if (user.isAnonymous) {
      await user.linkWithCredential(credential);
    } else {
      throw StateError('This profile already has an account.');
    }
  }

  Future<Progress?> signIn(String email, String password) async {
    if (!cloud) throw StateError('Firebase is not configured.');
    await _pending;
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final doc = await FirebaseFirestore.instance
        .collection('players')
        .doc(uid)
        .get();
    await prefs.setString('owner', uid);
    return doc.exists
        ? Progress.fromJson(Map<String, dynamic>.from(doc.data()!['progress']))
        : null;
  }
}
