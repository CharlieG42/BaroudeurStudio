import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config/google_photos_config.dart';

/// Représente un média sélectionné par l'utilisateur dans le sélecteur
/// Google Photos, prêt à être téléchargé.
class GooglePickedMedia {
  final String id;
  final String filename;
  final String mimeType;
  final String baseUrl;

  GooglePickedMedia({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.baseUrl,
  });

  String get downloadUrl => '$baseUrl=d';
}

/// Exception levée lorsque l'utilisateur annule la sélection.
class PickerCancelledException implements Exception {
  final String message;
  PickerCancelledException(this.message);
  @override
  String toString() => message;
}

/// Service pour l'authentification Google et l'API Google Photos Picker.
class GooglePhotosPickerService {
  static const String _sessionsBaseUrl = 'https://photospicker.googleapis.com/v1/sessions';
  static const String _mediaItemsBaseUrl = 'https://photospicker.googleapis.com/v1/mediaItems';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [GooglePhotosConfig.scope],
    signInOption: SignInOption.standard,
  );

  /// Parse une durée au format Google ("5s", "300s") en secondes.
  static int? _parseDurationSeconds(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(1)!)?.round();
  }

  /// Obtient un access token valide.
  Future<String> _getAccessToken() async {
    GoogleSignInAccount? account = await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    
    if (account == null) {
      throw Exception("User cancelled sign-in");
    }

    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception("Failed to obtain access token");
    }
    
    return accessToken;
  }

  Map<String, String> _authHeaders(String accessToken) => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  Future<({String sessionId, String pickerUri})> _createSession(String accessToken) async {
    final response = await http.post(
      Uri.parse(_sessionsBaseUrl),
      headers: _authHeaders(accessToken),
      body: '{}',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create session: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (sessionId: data['id'] as String, pickerUri: data['pickerUri'] as String);
  }

  Future<void> _pollUntilMediaItemsSet(String sessionId, String accessToken) async {
    final uri = Uri.parse('$_sessionsBaseUrl/$sessionId');
    await Future.delayed(const Duration(seconds: 2));

    const maxErrors = 5;
    int errors = 0;

    while (true) {
      try {
        final response = await http.get(uri, headers: _authHeaders(accessToken));
        if (response.statusCode != 200) {
          throw Exception('Session check failed: ${response.body}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['mediaItemsSet'] as bool? ?? false) return;

        final pollingConfig = data['pollingConfig'] as Map<String, dynamic>?;
        final pollInterval = _parseDurationSeconds(pollingConfig?['pollInterval'] as String?) ?? 3;
        final timeout = _parseDurationSeconds(pollingConfig?['timeoutIn'] as String?) ?? 0;

        if (timeout <= 0) {
          throw PickerCancelledException('Selection expired');
        }

        await Future.delayed(Duration(seconds: pollInterval));
      } catch (e) {
        errors++;
        if (errors >= maxErrors) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<List<GooglePickedMedia>> _listSelectedMedia(String sessionId, String accessToken) async {
    final results = <GooglePickedMedia>[];
    String? pageToken;

    do {
      final uri = Uri.parse(_mediaItemsBaseUrl).replace(queryParameters: {
        'sessionId': sessionId,
        if (pageToken != null) 'pageToken': pageToken,
      });

      final response = await http.get(uri, headers: _authHeaders(accessToken));
      if (response.statusCode != 200) {
        throw Exception('Failed to list media: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (data['mediaItems'] as List?) ?? []) {
        final map = item as Map<String, dynamic>;
        final mediaFile = map['mediaFile'] as Map<String, dynamic>?;
        if (mediaFile == null) continue;

        results.add(GooglePickedMedia(
          id: map['id'] as String,
          filename: mediaFile['filename'] as String? ?? 'photo.jpg',
          mimeType: mediaFile['mimeType'] as String? ?? 'image/jpeg',
          baseUrl: mediaFile['baseUrl'] as String,
        ));
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return results;
  }

  Future<void> _deleteSession(String sessionId, String accessToken) async {
    try {
      await http.delete(Uri.parse('$_sessionsBaseUrl/$sessionId'), headers: _authHeaders(accessToken));
    } catch (_) {}
  }

  Future<List<GooglePickedMedia>> pickMedia({required Future<void> Function(String pickerUri) onPickerReady}) async {
    final accessToken = await _getAccessToken();
    final session = await _createSession(accessToken);

    try {
      await onPickerReady(session.pickerUri);
      await _pollUntilMediaItemsSet(session.sessionId, accessToken);
      return await _listSelectedMedia(session.sessionId, accessToken);
    } finally {
      await _deleteSession(session.sessionId, accessToken);
    }
  }

  Future<List<int>> downloadMediaBytes(GooglePickedMedia media, {required String accessToken}) async {
    final response = await http.get(Uri.parse(media.downloadUrl), headers: {'Authorization': 'Bearer $accessToken'});
    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<String> getCurrentAccessToken() => _getAccessToken();
}
