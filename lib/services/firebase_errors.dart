import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// Keep the service and error code visible instead of calling every failure
/// an internet problem. Never include API keys or attestation tokens here.
String firebaseProblem(Object error, {required String service}) {
  if (error is TimeoutException)
    return '$service timed out. Check your connection and retry.';
  if (error is FirebaseException) {
    final code =
        error.code == 'unknown' &&
            (error.message ?? '').toLowerCase().contains('permission denied')
        ? 'permission-denied'
        : error.code;
    final tag = '$service [${error.plugin}/$code]';
    switch (code) {
      case 'operation-not-allowed':
        return '$tag: This sign-in provider is disabled. Enable Google or Anonymous in Firebase Authentication.';
      case 'admin-restricted-operation':
        return '$tag: Firebase administrator settings block this sign-in or account creation. Check Authentication providers and user-signup restrictions.';
      case 'permission-denied':
      case 'PERMISSION_DENIED':
        return '$tag: Access was denied. Check this service’s published rules and App Check request metrics.';
      case 'unauthenticated':
      case 'invalid-app-credential':
        return '$tag: Check the signed-in session and App Check attestation for this Android installation.';
      case 'app-not-authorized':
      case 'invalid-api-key':
        return '$tag: Check the Firebase project, Android package/signing fingerprints and API-key restrictions.';
      case 'network-request-failed':
      case 'unavailable':
        return '$tag: Service unavailable. Check the internet connection and retry.';
      case 'not-found':
        return '$tag: Check the deployed function name/region or requested resource.';
      default:
        return '$tag: Check the corresponding Firebase console settings and service logs.';
    }
  }
  if (error is PlatformException) {
    return '$service [${error.code}]: Check Google sign-in configuration and the installed app’s signing SHA-1/SHA-256.';
  }
  return '$service: ${error.toString().replaceFirst('Bad state: ', '')}';
}
