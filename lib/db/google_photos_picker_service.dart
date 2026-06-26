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

  /// Construit l'URL de téléchargement complète à partir du baseUrl.
  /// Pour les photos : suffixe "=d" pour télécharger le fichier original
  /// avec ses métadonnées EXIF.
  String get downloadUrl => '$baseUrl=d';
}

/// Exception levée lorsque l'utilisateur annule la sélection ou que la
/// session expire avant qu'il ait terminé.
class PickerCancelledException implements Exception {
  final String message;
  PickerCancelledException(this.message);
  @override
  String toString() => message;
}

/// Service gérant l'authentification Google et l'utilisation de la
/// Google Photos Picker API : création de session, attente de la
/// sélection utilisateur, récupération des médias choisis.
class GooglePhotosPickerService {
  static const _sessionsBaseUrl = 'https://photospicker.googleapis.com/v1/sessions';
  static const _mediaItemsBaseUrl = 'https://photospicker.googleapis.com/v1/mediaItems';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: GooglePhotosConfig.androidClientId,
    serverClientId: GooglePhotosConfig.webServerClientId,
  );
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.signIn();
    _initialized = true;
  }

  /// Connecte l'utilisateur à son compte Google (si pas déjà connecté) et
  /// retourne un access token valide pour le scope Picker API.
  /// Lève une exception si l'utilisateur annule la connexion.
  Future<String> _getAccessToken() async {
    await _ensureInitialized();

    const scopes = [GooglePhotosConfig.scope];

    // Utilise l'API moderne de google_sign_in v7+
    final authClient = await _googleSignIn.attemptLightweightAuthentication();
    if (authClient == null) {
      // Si pas de session existante, demande une authentification complète
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception("User cancelled sign-in");
      }
      final authHeaders = await account.authHeaders;
      return authHeaders['authorization']?.split(' ').last ?? '';
    }

    // Si authClient est disponible, utilise-le pour obtenir le token
    final authorization = await authClient.authorizeScopes(scopes);
    return authorization.accessToken;
  }

  Map<String, String> _authHeaders(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  /// Crée une nouvelle session Picker et retourne (sessionId, pickerUri).
  Future<({String sessionId, String pickerUri})> _createSession(String accessToken) async {
    final response = await http.post(
      Uri.parse(_sessionsBaseUrl),
      headers: _authHeaders(accessToken),
      body: '{}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Impossible de créer une session Google Photos (code ${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (sessionId: data['id'] as String, pickerUri: data['pickerUri'] as String);
  }

  /// Interroge l'état de la session jusqu'à ce que l'utilisateur ait
  /// terminé sa sélection (mediaItemsSet == true), ou jusqu'au timeout.
  /// Suit les intervalles de polling recommandés par l'API.
  ///
  /// Un court délai initial est observé avant le premier appel, et les
  /// erreurs réseau transitoires (fréquentes juste après le retour au
  /// premier plan de l'app sur Android, lorsque la connectivité n'est
  /// pas encore complètement rétablie) sont tolérées avec un nombre
  /// limité de réessais, plutôt que de faire échouer tout le flux.
  Future<void> _pollUntilMediaItemsSet(String sessionId, String accessToken) async {
    final uri = Uri.parse('$_sessionsBaseUrl/$sessionId');

    // Laisse le temps à la connectivité réseau de se stabiliser après
    // le retour de Chrome au premier plan, avant le tout premier appel.
    await Future.delayed(const Duration(seconds: 2));

    const maxConsecutiveNetworkErrors = 5;
    int consecutiveNetworkErrors = 0;

    while (true) {
      http.Response response;
      try {
        response = await http.get(uri, headers: _authHeaders(accessToken));
        consecutiveNetworkErrors = 0;
      } on Exception catch (e) {
        consecutiveNetworkErrors++;
        if (consecutiveNetworkErrors >= maxConsecutiveNetworkErrors) {
          throw Exception(
            'Connexion réseau instable, impossible de contacter Google Photos : $e',
          );
        }
        // Erreur réseau transitoire : on attend un peu et on réessaie,
        // sans relancer toute la session.
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Erreur lors de la vérification de la session (code ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final mediaItemsSet = data['mediaItemsSet'] as bool? ?? false;

      if (mediaItemsSet) return;

      final pollingConfig = data['pollingConfig'] as Map<String, dynamic>?;
      final pollIntervalStr = pollingConfig?['pollInterval'] as String?; // ex: "5s"
      final timeoutStr = pollingConfig?['timeoutIn'] as String?;

      final pollInterval = _parseDurationSeconds(pollIntervalStr) ?? 3;
      final timeout = _parseDurationSeconds(timeoutStr) ?? 0;

      if (timeout <= 0) {
        throw PickerCancelledException(
          'La sélection a expiré sans qu\'aucune photo ne soit choisie.',
        );
      }

      await Future.delayed(Duration(seconds: pollInterval));
    }
  }

  /// Parse une durée au format Google ("5s", "300s") en secondes entières.
  int? _parseDurationSeconds(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(value);
    if (match == null) return null;
    return double.tryParse(match.group(1)!)?.round();
  }

  /// Récupère la liste complète des médias sélectionnés par l'utilisateur
  /// pour une session donnée (gère la pagination).
  Future<List<GooglePickedMedia>> _listSelectedMedia(
    String sessionId,
    String accessToken,
  ) async {
    final results = <GooglePickedMedia>[];
    String? pageToken;

    do {
      final uri = Uri.parse(_mediaItemsBaseUrl).replace(queryParameters: {
        'sessionId': sessionId,
        if (pageToken != null) 'pageToken': pageToken,
      });

      final response = await http.get(uri, headers: _authHeaders(accessToken));

      if (response.statusCode != 200) {
        throw Exception(
          'Erreur lors de la récupération des médias (code ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['mediaItems'] as List<dynamic>?) ?? [];

      for (final item in items) {
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

  /// Supprime la session côté serveur (bonne pratique recommandée par
  /// Google pour éviter d'accumuler des sessions inutilisées).
  Future<void> _deleteSession(String sessionId, String accessToken) async {
    try {
      await http.delete(
        Uri.parse('$_sessionsBaseUrl/$sessionId'),
        headers: _authHeaders(accessToken),
      );
    } catch (_) {
      // best-effort : la suppression de session n'est pas critique
      // pour l'utilisateur si elle échoue.
    }
  }

  /// Lance le flux complet : authentification, ouverture du sélecteur
  /// Google Photos via [onPickerReady] (à qui on transmet l'URL à ouvrir
  /// dans le navigateur), attente de la sélection, puis retour de la
  /// liste des médias choisis.
  ///
  /// [onPickerReady] doit ouvrir l'URL reçue (ex: via url_launcher) et
  /// peut être utilisé pour mettre à jour l'UI ("ouverture du sélecteur
  /// Google Photos...").
  Future<List<GooglePickedMedia>> pickMedia({
    required Future<void> Function(String pickerUri) onPickerReady,
  }) async {
    final accessToken = await _getAccessToken();
    final session = await _createSession(accessToken);

    try {
      await onPickerReady(session.pickerUri);
      await _pollUntilMediaItemsSet(session.sessionId, accessToken);
      final media = await _listSelectedMedia(session.sessionId, accessToken);
      return media;
    } finally {
      await _deleteSession(session.sessionId, accessToken);
    }
  }

  /// Télécharge le contenu binaire d'un média sélectionné.
  Future<List<int>> downloadMediaBytes(
    GooglePickedMedia media, {
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse(media.downloadUrl),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Échec du téléchargement de ${media.filename} (code ${response.statusCode})',
      );
    }

    return response.bodyBytes;
  }

  /// Retourne le token d'accès courant, pour réutilisation lors du
  /// téléchargement (évite de redemander une authentification).
  Future<String> getCurrentAccessToken() => _getAccessToken();
}
