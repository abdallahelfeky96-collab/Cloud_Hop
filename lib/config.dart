class AppConfig {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseProject = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSender = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const testAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: true,
  );
  static const interstitialId = String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const rewardedId = String.fromEnvironment('ADMOB_REWARDED_ID');

  /// Compiled-in fallback for the bundled Firebase project, so online
  /// features connect even when the app is launched without
  /// `--dart-define-from-file`. Explicit dart-defines still take precedence.
  /// (Firebase client keys are public identifiers, also shipped in
  /// `android/app/google-services.json`.)
  static const _fallbackApiKey = 'AIzaSyCRcM2dV2KcTjtN6f08pdOVuUOTuitHZ_c';
  static const _fallbackAppId =
      '1:827500673982:android:a20425d066603a3f4097ef';
  static const _fallbackProject = 'cloud-hop-8732a';
  static const _fallbackSender = '827500673982';
  static const _fallbackDatabaseUrl =
      'https://cloud-hop-8732a-default-rtdb.firebaseio.com';

  static String get effectiveApiKey =>
      firebaseApiKey.isNotEmpty ? firebaseApiKey : _fallbackApiKey;
  static String get effectiveAppId =>
      firebaseAppId.isNotEmpty ? firebaseAppId : _fallbackAppId;
  static String get effectiveProject =>
      firebaseProject.isNotEmpty ? firebaseProject : _fallbackProject;
  static String get effectiveSender =>
      firebaseSender.isNotEmpty ? firebaseSender : _fallbackSender;
  static String get effectiveDatabaseUrl =>
      databaseUrl.isNotEmpty ? databaseUrl : _fallbackDatabaseUrl;

  static bool get firebaseConfigured =>
      effectiveApiKey.isNotEmpty &&
      effectiveAppId.isNotEmpty &&
      effectiveProject.isNotEmpty &&
      effectiveSender.isNotEmpty &&
      effectiveDatabaseUrl.isNotEmpty;
}
