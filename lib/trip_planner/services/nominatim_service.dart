import 'dart:convert';
import 'package:http/http.dart' as http;

/// Un lieu trouve par la recherche geographique.
class LieuTrouve {
  final String nomAffiche;
  final double latitude;
  final double longitude;

  LieuTrouve({
    required this.nomAffiche,
    required this.latitude,
    required this.longitude,
  });
}

/// Exception levee lorsque la recherche de lieu echoue (reseau,
/// timeout, erreur serveur...), a distinguer d'une recherche qui
/// aboutit simplement a aucun resultat.
class RechercheLieuException implements Exception {
  final String message;
  RechercheLieuException(this.message);

  @override
  String toString() => message;
}

/// Client pour l'API de geocodage Nominatim (OpenStreetMap), qui permet
/// de retrouver les coordonnees d'un lieu a partir de son nom (ex:
/// "Bryce Canyon National Park"). Sert a ajouter une etape sans avoir
/// a connaitre ses coordonnees GPS a l'avance.
///
/// Politique d'usage de nominatim.openstreetmap.org : maximum 1 requete
/// par seconde, User-Agent obligatoire, pas d'usage intensif/automatise.
/// Pour un usage intensif, heberger sa propre instance Nominatim.
/// https://operations.osmfoundation.org/policies/nominatim/
class NominatimService {
  static const String baseUrl = 'https://nominatim.openstreetmap.org';

  static const Map<String, String> _headers = {
    'User-Agent': 'BaroudeurStudio-TripPlanner/1.0 (usage personnel)',
    'Accept-Language': 'fr',
  };

  /// Recherche un lieu par son nom. Leve [RechercheLieuException] en
  /// cas d'echec (reseau, timeout, erreur serveur) au lieu de renvoyer
  /// silencieusement une liste vide, pour que l'UI puisse distinguer
  /// "aucun resultat" d'un vrai probleme technique.
  Future<List<LieuTrouve>> rechercherLieu(String requete) async {
    final texte = requete.trim();
    if (texte.isEmpty) return [];

    final uri = Uri.parse(
      '$baseUrl/search'
      '?q=${Uri.encodeQueryComponent(texte)}'
      '&format=jsonv2&limit=8&addressdetails=0',
    );

    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
    } on Exception {
      throw RechercheLieuException(
        'Impossible de contacter le service de recherche (verifie la '
        'connexion).',
      );
    }

    if (response.statusCode == 429) {
      throw RechercheLieuException(
        'Trop de recherches en peu de temps, patiente quelques secondes.',
      );
    }
    if (response.statusCode != 200) {
      throw RechercheLieuException(
        'Le service de recherche a repondu une erreur '
        '(${response.statusCode}).',
      );
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.map((item) {
        final m = item as Map<String, dynamic>;
        return LieuTrouve(
          nomAffiche: m['display_name'] as String,
          latitude: double.parse(m['lat'] as String),
          longitude: double.parse(m['lon'] as String),
        );
      }).toList();
    } catch (_) {
      throw RechercheLieuException('Reponse inattendue du service de recherche.');
    }
  }
}
