class AppConfig {
  static const appCheckDebug = bool.fromEnvironment(
    'APP_CHECK_DEBUG',
    defaultValue: false,
  );
  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
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

  /// HTTPS service hosted on Cloud Run or an existing server; no Cloud Functions.
  /// NOTE: voice tokens are minted on-device (see LiveKitToken), so this
  /// endpoint is NOT on the voice path and may remain empty.
  static const trustedServiceUrl = String.fromEnvironment(
    'TRUSTED_SERVICE_URL',
  );

  // Self-hosted LiveKit voice server. Overrides via --dart-define.
  static const livekitUrl = String.fromEnvironment('LIVEKIT_URL');
  static const livekitKey = String.fromEnvironment('LIVEKIT_API_KEY');
  static const livekitSecret = String.fromEnvironment('LIVEKIT_API_SECRET');

  /// WARNING: the fallback secret below ships inside the APK and can be
  /// extracted from it — anyone holding it fully controls the LiveKit
  /// server. Acceptable for this private dev server only. For production,
  /// REMOVE the fallback secret and mint tokens on a server you operate
  /// (see trusted-service/server.mjs).
  static const _fallbackLivekitUrl = 'ws://84.8.113.65:7880';
  static const _fallbackLivekitKey = 'devkey';
  static const _fallbackLivekitSecret =
      'secret_livekit_cloud_hop_2026_key_123';

  static String get effectiveLivekitUrl =>
      livekitUrl.isNotEmpty ? livekitUrl : _fallbackLivekitUrl;
  static String get effectiveLivekitKey =>
      livekitKey.isNotEmpty ? livekitKey : _fallbackLivekitKey;
  static String get effectiveLivekitSecret =>
      livekitSecret.isNotEmpty ? livekitSecret : _fallbackLivekitSecret;

  static bool get livekitConfigured =>
      effectiveLivekitUrl.isNotEmpty &&
      effectiveLivekitKey.isNotEmpty &&
      effectiveLivekitSecret.isNotEmpty;

  /// Compiled-in fallback for the bundled Firebase project, so online
  /// features connect even when the app is launched without
  /// `--dart-define-from-file`. Explicit dart-defines still take precedence.
  /// (Firebase client keys are public identifiers, also shipped in
  /// `android/app/google-services.json`.)
  static const _fallbackApiKey = 'AIzaSyCRcM2dV2KcTjtN6f08pdOVuUOTuitHZ_c';
  static const _fallbackAppId = '1:827500673982:android:a20425d066603a3f4097ef';
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
