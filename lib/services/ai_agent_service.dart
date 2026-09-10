import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../firebase_options.dart';

/// AI credentials, tools, quotas and writes live exclusively on the backend.
class AIAgentService {
  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
      ? _callWindows(name, data)
      : _callFirebase(name, data);

  Future<Map<String, dynamic>> _callFirebase(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await _functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// The FlutterFire cloud_functions plugin is not registered on Windows.
  /// Callable functions use a documented HTTP envelope, so use the signed-in
  /// user's Firebase ID token for the desktop build instead.
  Future<Map<String, dynamic>> _callWindows(
    String name,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'ai_sign_in',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'ai_sign_in',
      );
    }

    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    final uri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/$name',
    );
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 120));

    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        body = Map<String, dynamic>.from(decoded);
      }
    }
    final error = body['error'];
    if (error is Map) {
      final status = '${error['status'] ?? 'UNKNOWN'}';
      final code = status.toLowerCase().replaceAll('_', '-');
      throw FirebaseFunctionsException(
        code: code,
        message: '${error['message'] ?? 'ai_unavailable'}',
        details: error['details'],
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'ai_unavailable',
      );
    }
    final result = body['result'];
    if (result is! Map) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'ai_unavailable',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<String> chat({
    required String message,
    required List<Map<String, String>> history,
    required String language,
  }) async {
    final result = await call('aiChat', {
      'requestId': const Uuid().v4(),
      'message': message,
      'history': history.length > 12
          ? history.sublist(history.length - 12)
          : history,
      'language': language,
    });
    return result['text'] as String;
  }

  Future<Map<String, dynamic>> usage() => call('aiUsage', {});
  Future<Map<String, dynamic>> preview(Map<String, dynamic> input) =>
      call('aiImportPreview', {'requestId': const Uuid().v4(), ...input});
  Future<Map<String, dynamic>> commit(
    String draftId,
    List<Map<String, dynamic>> records,
  ) => call('aiImportCommit', {'draftId': draftId, 'records': records});
  void dispose() {}
}
