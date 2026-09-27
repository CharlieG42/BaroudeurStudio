import 'package:geolocator/geolocator.dart';

/// Position de l'utilisateur a afficher sur la carte du Trip Planner.
class PositionUtilisateur {
  final double latitude;
  final double longitude;
  final double precisionMetres;

  PositionUtilisateur({
    required this.latitude,
    required this.longitude,
    required this.precisionMetres,
  });
}

/// Exception levee lorsque la geolocalisation echoue : service desactive,
/// permission refusee, ou erreur technique. Le message est destine a
/// l'utilisateur final.
class GeolocalisationException implements Exception {
  final String message;
  const GeolocalisationException(this.message);
  @override
  String toString() => message;
}

/// Service de geolocalisation pour le module de planification : recupere
/// la position courante de l'utilisateur apres avoir verifie que le
/// service de localisation est actif et obtenu la permission requise
/// (demande de permission a la premiere utilisation, geolocator gere
/// la fenetre systeme).
///
/// Volontairement ponctuel (pas de flux continu) : la position est
/// demandee sur action explicite de l'utilisateur (bouton de
/// recentrage), ce qui respecte la batterie et la vie privee.
class GeolocalisationService {
  /// Retourne la position courante de l'utilisateur, ou null si aucune
  /// position n'est disponible (ex: permission refusee, service de
  /// localisation desactive). Leve [GeolocalisationException] en cas
  /// d'erreur technique inattendue.
  Future<PositionUtilisateur?> positionActuelle() async {
    bool serviceActif;
    try {
      serviceActif = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      throw const GeolocalisationException(
        'Impossible de verifier le service de localisation sur cet appareil.',
      );
    }
    if (!serviceActif) {
      throw const GeolocalisationException(
        'La localisation est desactivee sur cet appareil.',
      );
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      throw const GeolocalisationException(
        'Impossible de verifier la permission de localisation.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const GeolocalisationException(
        'Permission de localisation refusee.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const GeolocalisationException(
        'Permission de localisation refusee definitivement : active-la dans '
        'les parametres de l\'appareil.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );
      return PositionUtilisateur(
        latitude: position.latitude,
        longitude: position.longitude,
        precisionMetres: position.accuracy,
      );
    } on LocationException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
