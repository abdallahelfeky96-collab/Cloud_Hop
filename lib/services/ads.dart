import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config.dart';

class AdService {
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _enabled = false, _showing = false, _disposed = false;
  bool get ready => _rewarded != null && !_showing;
  bool get mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get interstitialId => AppConfig.testAds
      ? 'ca-app-pub-3940256099942544/1033173712'
      : AppConfig.interstitialId;
  String get rewardedId => AppConfig.testAds
      ? 'ca-app-pub-3940256099942544/5224354917'
      : AppConfig.rewardedId;
  Future<void> initialize() async {
    if (!mobile || defaultTargetPlatform != TargetPlatform.android) return;
    // Ads are optional: if the consent platform channel is missing or throws,
    // keep the game playable instead of surfacing an unhandled async error.
    try {
      final consent = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (!consent.isCompleted) consent.complete();
          });
        },
        (error) {
          if (!consent.isCompleted) consent.complete();
        },
      );
      await consent.future;
      if (_disposed || !await ConsentInformation.instance.canRequestAds()) {
        return;
      }
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('Ads init skipped: $e');
      return;
    }
    _enabled = true;
    load();
  }

  void load() {
    if (!_enabled || _disposed) return;
    if (_interstitial == null && interstitialId.isNotEmpty) {
      InterstitialAd.load(
        adUnitId: interstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
            } else {
              _interstitial = ad;
            }
          },
          onAdFailedToLoad: (e) {},
        ),
      );
    }
    if (_rewarded == null && rewardedId.isNotEmpty) {
      RewardedAd.load(
        adUnitId: rewardedId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
            } else {
              _rewarded = ad;
            }
          },
          onAdFailedToLoad: (e) {},
        ),
      );
    }
  }

  Future<bool> betweenRuns() async {
    if (_showing) return false;
    final ad = _interstitial;
    _interstitial = null;
    if (ad == null) {
      load();
      return false;
    }
    _showing = true;
    final done = Completer<bool>();
    void finish(bool shown) {
      if (done.isCompleted) return;
      _showing = false;
      ad.dispose();
      done.complete(shown);
      load();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => finish(true),
      onAdFailedToShowFullScreenContent: (a, e) => finish(false),
    );
    try {
      await ad.show();
    } catch (_) {
      finish(false);
    }
    return done.future;
  }

  Future<bool> reward() async {
    if (_showing) return false;
    final ad = _rewarded;
    _rewarded = null;
    if (ad == null) {
      load();
      return false;
    }
    _showing = true;
    bool earned = false;
    final done = Completer<bool>();
    void finish() {
      if (done.isCompleted) return;
      _showing = false;
      ad.dispose();
      done.complete(earned);
      load();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => finish(),
      onAdFailedToShowFullScreenContent: (a, e) => finish(),
    );
    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
        },
      );
    } catch (_) {
      finish();
    }
    return done.future;
  }

  Future<void> privacy() async {
    if (!mobile) return;
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      done.complete();
    });
    await done.future;
  }

  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _rewarded?.dispose();
  }
}
