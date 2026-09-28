import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../config.dart';

class TrustedService {
  static Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> data,
  ) async {
    final base = Uri.tryParse(AppConfig.trustedServiceUrl);
    if (base == null || base.scheme != 'https' || base.host.isEmpty)
      throw StateError('Voice and push service is not configured.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in first.');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Sign in again.');
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(base.resolve('/$action'))
          .timeout(const Duration(seconds: 10));
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(data));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200)
        throw StateError(
          'Online service unavailable (status ${response.statusCode}).',
        );
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw StateError('Invalid service response.');
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}
