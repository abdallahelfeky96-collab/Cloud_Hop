import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../game/engine.dart';
import 'firebase_errors.dart';

class ProgressStore {
  late SharedPreferences prefs;
  // A session is distinct from Firestore/RTDB/Functions access. A rules denial
  // must never disable Google sign-in or an unrelated Firebase service.
  bool get cloud => user != null;
  String status = 'Offline save';
  String? authIssue, firestoreIssue;
  Future<void> _pending = Future.value();
  Future<void>? _initialization;
  Future<bool>? _connecting;

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
    if (!await retryCloud()) return local;
    try {
      final doc = await _readProgress(uid);
      if (doc.exists) {
        final map = doc.data()!;
        final remoteStamp = (map['savedAt'] as num?)?.toInt() ?? 0;
        final localOwner = prefs.getString('owner');
        final localStamp = prefs.getInt('savedAt') ?? 0;
        if (localOwner != uid || remoteStamp >= localStamp) {
          local = Progress.fromJson(Map<String, dynamic>.from(map['progress']));
        }
      }
      await prefs.setString('owner', uid);
      firestoreIssue = null;
      status = 'Signed in · Firestore progress connected';
    } catch (error) {
      _recordFirestoreError(error);
    }
    return local;
  }

  Future<void> initializeServices() async {
    if (_underTest)
      throw StateError('Firebase networking is disabled in widget tests.');
    if (!AppConfig.firebaseConfigured)
      throw StateError('Firebase configuration is missing.');
    _initialization ??= _initialize().catchError((
      Object error,
      StackTrace stack,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
    // A caller timeout does not cancel initialization or start a duplicate.
    await _initialization!.timeout(const Duration(seconds: 8));
  }

  Future<void> _initialize() async {
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
    if (Firebase.app().options.projectId != AppConfig.effectiveProject) {
      throw StateError(
        'The initialized Firebase project differs from the app configuration.',
      );
    }
    // Activate before Auth, Firestore, RTDB or Functions requests.
    // Debug tokens must be explicitly registered in App Check; never ship
    // a debug provider in a release build.
    await FirebaseAppCheck.instance.activate(
      providerAndroid: !kReleaseMode && AppConfig.appCheckDebug
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  }

  Future<void> checkConnection() async {
    if (!await retryCloud()) return;
    try {
      await _readProgress(uid);
      firestoreIssue = null;
      status = 'Signed in · Firestore progress connected';
    } catch (error) {
      _recordFirestoreError(error);
    }
  }

  Future<bool> retryCloud() async {
    if (_underTest) return false;
    if (_connecting != null) return _connecting!;
    final pending = _connect();
    _connecting = pending;
    try {
      return await pending;
    } finally {
      _connecting = null;
    }
  }

  Future<bool> _connect() async {
    try {
      await initializeServices();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously().timeout(
          const Duration(seconds: 8),
        );
      }
      authIssue = null;
      status =
          firestoreIssue ??
          'Firebase signed in; database access is checked separately';
      return true;
    } catch (error) {
      authIssue = firebaseProblem(error, service: 'Firebase guest sign-in');
      status = authIssue!;
      return false;
    }
  }

  String? get uidOrNull => user?.uid;

  String get uid {
    final id = uidOrNull;
    if (id == null) throw StateError('Sign in first.');
    return id;
  }

  User? get user {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool get isGoogle =>
      user != null &&
      !user!.isAnonymous &&
      user!.providerData.any(
        (p) => p.providerId == GoogleAuthProvider.PROVIDER_ID,
      );
  String? get displayName => user?.displayName;
  String? get email => user?.email;
  String? get photoUrl => user?.photoURL;

  // Crucially, this initializes Firebase/App Check, NOT anonymous sign-in.
  Future<void> signInWithGoogle() async {
    try {
      await initializeServices();
      await _pending;
      final account = await GoogleSignIn().signIn();
      if (account == null) throw StateError('Google sign-in was cancelled.');
      final google = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: google.idToken,
        accessToken: google.accessToken,
      );
      final auth = FirebaseAuth.instance;
      final anonymous = auth.currentUser;
      if (anonymous != null && anonymous.isAnonymous) {
        try {
          await anonymous.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
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
      authIssue = null;
      status = 'Signed in with Google';
    } catch (error) {
      authIssue = firebaseProblem(error, service: 'Google sign-in');
      status = authIssue!;
      throw StateError(status);
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readProgress(String owner) =>
      FirebaseFirestore.instance
          .collection('players')
          .doc(owner)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));

  void _recordFirestoreError(Object error) {
    firestoreIssue = firebaseProblem(error, service: 'Firestore progress');
    status =
        '${cloud ? 'Signed in. ' : ''}${firestoreIssue!} Local progress is kept.';
  }

  Future<Progress?> loadCloudProgress() async {
    if (!cloud) return null;
    final doc = await _readProgress(uid);
    if (!doc.exists) return null;
    return Progress.fromJson(
      Map<String, dynamic>.from(doc.data()!['progress']),
    );
  }

  // Retains the existing merge policy. A denied save service must not make a
  // successful Google login appear to have failed.
  Future<bool> mergeRemoteInto(Progress local) async {
    try {
      final remote = await loadCloudProgress();
      if (remote != null) {
        local.coins = local.coins > remote.coins ? local.coins : remote.coins;
        local.best = local.best > remote.best ? local.best : remote.best;
        local.skins.addAll(remote.skins);
        local.skies.addAll(remote.skies);
        for (final key in local.items.keys) {
          final have = local.items[key] ?? 0, there = remote.items[key] ?? 0;
          local.items[key] = have > there ? have : there;
        }
      }
      firestoreIssue = null;
      await save(local);
      return remote != null;
    } catch (error) {
      _recordFirestoreError(error);
      return false;
    }
  }

  Future<void> signOutGoogle() async {
    await _pending;
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    // Sign-out remains successful if anonymous accounts are disabled.
    await retryCloud();
  }

  Future<void> save(Progress p) {
    final payload = p.toJson(), stamp = DateTime.now().millisecondsSinceEpoch;
    final owner = user?.uid; // Bind queued saves to the original account.
    _pending = _pending.catchError((_) {}).then((_) async {
      await prefs.setString('progress', jsonEncode(payload));
      await prefs.setInt('savedAt', stamp);
      if (owner != null) await prefs.setString('owner', owner);
      if (owner != null && user?.uid == owner) {
        unawaited(
          FirebaseFirestore.instance
              .collection('players')
              .doc(owner)
              .set({'progress': payload, 'savedAt': stamp})
              .then((_) {
                if (user?.uid == owner) {
                  firestoreIssue = null;
                  status = 'Signed in · Firestore progress connected';
                }
              })
              .catchError((Object error) {
                if (user?.uid == owner) _recordFirestoreError(error);
              }),
        );
      }
    });
    return _pending;
  }

  Future<void> linkAccount(String email, String password) async {
    if (!cloud) throw StateError('Sign in first.');
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) throw StateError('Sign in first.');
    if (current.isAnonymous)
      await current.linkWithCredential(credential);
    else
      throw StateError('This profile already has an account.');
  }

  Future<Progress?> signIn(String email, String password) async {
    await initializeServices();
    await _pending;
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return loadCloudProgress();
  }
}
