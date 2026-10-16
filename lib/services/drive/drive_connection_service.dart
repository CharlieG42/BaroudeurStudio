import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../config/google_drive_config.example.dart'
    show GoogleDriveConfig;

/// Résultat du test de connexion Google Drive.
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

/// Service de connexion à Google Drive.
///
/// Gère la connexion Google (google_sign_in) avec le scope `drive.file`,
/// puis fournit un [drive.DriveApi] authentifié pour les uploads de
/// sauvegarde. Le premier appel de test utilise `about.get` : il renvoie
/// le compte connecté et le quota Drive, ce qui prouve en une requête
/// que l'API est activée et le scope accordé.
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

  /// Compte actuellement connecté (null si non connecté).
  GoogleSignInAccount? get compteActuel => _compte ?? _googleSignIn.currentUser;

  /// Vrai si un compte est déjà connecté.
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

      // about.get : prouve en un appel que la Drive API est activée
      // et que le scope drive.file est bien accordé.
      final authClient = await compte.authenticatedClient();
      if (authClient == null) {
        return const DriveConnectionResult(
          ok: false,
          erreur: 'Impossible d\'obtenir les identifiants Google.',
        );
      }
      final about = drive.DriveApi(authClient)
          .about
          .get($fields: 'user,storageQuota');
      authClient.close();

      final utilisateur = (await about).user?.emailAddress ??
          (await about).user?.displayName ??
          'compte inconnu';
      final quotaLimit = (await about).storageQuota?.limit;

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

  /// Déconnecte le compte Google courant.
  Future<void> deconnecter() async {
    await _googleSignIn.disconnect();
    await _googleSignIn.signOut();
    _compte = null;
  }

  /// Renvoie un client Drive authentifié (pour l'upload de sauvegardes).
  /// L'appelant est responsable de fermer le client HTTP.
  Future<drive.DriveApi> clientDrive() async {
    var compte = _googleSignIn.currentUser;
    compte ??= await _googleSignIn.signInSilently();
    compte ??= await _googleSignIn.signIn();
    if (compte == null) {
      throw StateError('Aucun compte Google connecté.');
    }
    _compte = compte;
    final authClient = await compte.authenticatedClient();
    if (authClient == null) {
      throw StateError('Impossible d\'obtenir les identifiants Google.');
    }
    return drive.DriveApi(authClient);
  }

  @visibleForTesting
  void reinitialiserPourTests() {
    _signIn = null;
    _compte = null;
  }
}
