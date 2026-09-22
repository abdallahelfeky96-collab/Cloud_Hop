import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/challenge.dart';
import 'progress_store.dart';

enum ControlMode { swipe, joystick }

class PlayerSettings {
  String name, country, city;
  bool sound;
  GameChoice choice;
  ControlMode control;
  final SharedPreferences prefs;
  PlayerSettings(this.prefs)
    : name = prefs.getString('name') ?? 'Pip',
      country = prefs.getString('country') ?? 'Egypt',
      city = prefs.getString('city') ?? 'Cairo',
      sound = prefs.getBool('sound') ?? true,
      choice = GameChoice.values[(prefs.getInt('choice') ?? 0).clamp(0, 2)],
      control =
          ControlMode.values[(prefs.getInt('control') ?? 0).clamp(0, 1)];
  Future<void> save() async {
    await prefs.setString('name', name);
    await prefs.setString('country', country);
    await prefs.setString('city', city);
    await prefs.setBool('sound', sound);
    await prefs.setInt('choice', choice.index);
    await prefs.setInt('control', control.index);
  }
}

class SocialService {
  final ProgressStore store;
  SocialService(this.store);
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!store.cloud) {
      throw StateError('Connect Firebase to use friends and online matches.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          action,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> register(PlayerSettings settings) async {
    await call('profile', {
      'name': settings.name,
      'country': settings.country,
      'city': settings.city,
    });
  }
}
