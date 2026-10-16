import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../config/google_drive_config.example.dart'
    show GoogleDriveConfig;

/// Client HTTP qui injecte le token d'acces Google en en-tete Authorization.
///
/// Alternative legere a extension_google_sign_in_as_googleapis_auth :
/// le jeton provient de [GoogleSignInAccount.authentication] et dure
/// environ une heure, ce qui suffit pour un test de connexion ou un
/// upload de sauvegarde. Pour une session plus longue, re-appeler
/// [GoogleSignInAccount.authentication] avant chaque requete.
class _BearerClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _BearerClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Resultat du test de connexion Google Drive.
class DriveConnectionResult {
  final bool ok;
  final String? compte;
  final String? quota;
  final String? erreur;

  const DriveConnectionResult({
    required this.ok,
    this.compte,
    this.quota,
    this.erreur,
  });
}

/// Service de connexion a Google Drive.
///
/// Gere la connexion Google (google_sign_in) avec le scope `drive.file`,
/// puis fournit un [drive.DriveApi] authentifie pour les uploads de
/// sauvegarde. Le premier appel de test utilise `about.get` : il renvoie
/// le compte connecte et le quota Drive, ce qui prouve en une requete
/// que l'API est activee et le scope accorde.
class DriveConnectionService {
  static final DriveConnectionService _instance =
      DriveConnectionService._internal();
  factory DriveConnectionService() => _instance;
  DriveConnectionService._internal();

  GoogleSignIn? _signIn;
  GoogleSignInAccount? _compte;

  GoogleSignIn get _googleSignIn => _signIn ??= GoogleSignIn(
        clientId: GoogleDriveConfig.androidClientId,
        serverClientId: GoogleDriveConfig.webServerClientId,
        scopes: [GoogleDriveConfig.driveScope],
      );

  /// Compte actuellement connecte (null si non connecte).
  GoogleSignInAccount? get compteActuel => _compte ?? _googleSignIn.currentUser;

  /// Vrai si un compte est deja connecte.
  bool get estConnecte => compteActuel != null;

  /// Se connecte (silencieusement si possible) et teste la Drive API
  /// via `about.get`. Renvoie le compte et le quota si tout fonctionne.
  Future<DriveConnectionResult> testerConnexion() async {
    try {
      var compte = _googleSignIn.currentUser;
      compte ??= await _googleSignIn.signInSilently();
      compte ??= await _googleSignIn.signIn();
      if (compte == null) {
        return const DriveConnectionResult(
          ok: false,
          erreur: 'Connexion annulée par l\'utilisateur.',
        );
      }
      _compte = compte;

      // about.get : prouve en un appel que la Drive API est activee
      // et que le scope drive.file est bien accorde.
      final client = await _clientAuthentifie(compte);
      final about =
          await drive.DriveApi(client).about.get($fields: 'user,storageQuota');
      client.close();

      final utilisateur =
          about.user?.emailAddress ?? about.user?.displayName ?? 'compte inconnu';
      final quotaLimit = about.storageQuota?.limit;

      return DriveConnectionResult(
        ok: true,
        compte: utilisateur,
        quota: quotaLimit != null
            ? '${_formatGo(quotaLimit)} Go'
            : 'quota indisponible',
      );
    } on drive.ApiRequestError catch (e) {
      return DriveConnectionResult(
        ok: false,
        erreur: 'Erreur Drive API (API activée ? scope accordé ?) : $e',
      );
    } catch (e) {
      return DriveConnectionResult(ok: false, erreur: e.toString());
    }
  }

  String _formatGo(String octets) {
    final valeur = int.tryParse(octets);
    if (valeur == null) return octets;
    return (valeur / (1024 * 1024 * 1024)).toStringAsFixed(1);
  }

  /// Deconnecte le compte Google courant.
  Future<void> deconnecter() async {
    await _googleSignIn.disconnect();
    await _googleSignIn.signOut();
    _compte = null;
  }

  /// Renvoie un client Drive authentifie (pour l'upload de sauvegardes).
  /// L'appelant est responsable de fermer le client HTTP.
  Future<drive.DriveApi> clientDrive() async {
    var compte = _googleSignIn.currentUser;
    compte ??= await _googleSignIn.signInSilently();
    compte ??= await _googleSignIn.signIn();
    if (compte == null) {
      throw StateError('Aucun compte Google connecté.');
    }
    _compte = compte;
    return drive.DriveApi(await _clientAuthentifie(compte));
  }

  Future<http.Client> _clientAuthentifie(GoogleSignInAccount compte) async {
    final auth = await compte.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Impossible d\'obtenir le jeton d\'accès Google.');
    }
    return _BearerClient(token);
  }

  @visibleForTesting
  void reinitialiserPourTests() {
    _signIn = null;
    _compte = null;
  }
}
