import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Statistiques d'un telechargement de zone hors ligne.
class ResultatTelechargementTuiles {
  final int total;
  final int reussies;
  final int echecs;

  ResultatTelechargementTuiles({
    required this.total,
    required this.reussies,
    required this.echecs,
  });
}

/// Bornes geographiques d'une zone (WGS84).
class ZoneTuiles {
  final double sud;
  final double ouest;
  final double nord;
  final double est;

  ZoneTuiles({
    required this.sud,
    required this.ouest,
    required this.nord,
    required this.est,
  });
}

/// Service de pre-telechargement des tuiles d'une zone : avant un
/// depart sans reseau, l'utilisateur enregistre sur son appareil tous
/// les fonds de carte de la zone affichee, pour une plage de zooms
/// donnee. Les tuiles sont stockees dans le dossier documents de
/// l'application, sous tuiles/<fond>/<z>/<x>/<y>, et lues par
/// [TuilesHorsLigneTileProvider] en priorite sur le reseau.
///
/// Le telechargement est volontairement sequentiel avec une petite
/// pause entre tuiles, pour rester raisonnable avec les serveurs de
/// tuiles publics (politique d'usage d'OpenStreetMap et de l'IGN).
class TuilesHorsLigneService {
  static const Map<String, String> _headers = {
    'User-Agent': 'BaroudeurStudio-TripPlanner/1.0 (usage personnel)',
  };

  /// Pause entre deux tuiles, pour ne pas marteler les serveurs
  /// publics de tuiles.
  static const Duration _pauseEntreTuiles = Duration(milliseconds: 50);

  /// Chemin du dossier racine des tuiles pre-telechargees. Resolu une
  /// fois puis mis en cache : [TuilesHorsLigneTileProvider] en a
  /// besoin de maniere synchrone.
  static String? _racineCachee;

  static Future<String> racine() async {
    if (_racineCachee != null) return _racineCachee!;
    final docs = await getApplicationDocumentsDirectory();
    final dossier = p.join(docs.path, 'tuiles');
    _racineCachee = dossier;
    return dossier;
  }

  /// Chemin local d'une tuile pour le fond donne (synchrone, apres
  /// [racine] resolu au moins une fois).
  static String cheminTuileSync(String nomFond, int z, int x, int y) {
    return p.join(_racineCachee ?? 'tuiles', nomFond, '$z', '$x', '$y');
  }

  /// Ecrit une tuile recue du reseau dans le stockage local.
  static Future<void> ecrireTuile(
    String nomFond,
    int z,
    int x,
    int y,
    List<int> bytes,
  ) async {
    final racine = await racine();
    final fichier = File(p.join(racine, nomFond, '$z', '$x', '$y'));
    await fichier.parent.create(recursive: true);
    await fichier.writeAsBytes(bytes, flush: true);
  }

  /// Indice x slippy d'une longitude pour un zoom donne.
  static int xTile(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  /// Indice y slippy d'une latitude pour un zoom donne.
  static int yTile(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 -
                math.log(math.tan(latRad) + 1 / math.cos(latRad)) /
                    math.pi) /
            2.0 *
            (1 << z))
        .floor();
  }

  /// Nombre de tuiles couvrant la zone pour la plage de zooms donnee.
  static int compterTuiles(ZoneTuiles zone, int zoomMin, int zoomMax) {
    var total = 0;
    for (var z = zoomMin; z <= zoomMax; z++) {
      final x0 = xTile(zone.ouest, z).clamp(0, (1 << z) - 1);
      final x1 = xTile(zone.est, z).clamp(0, (1 << z) - 1);
      final y0 = yTile(zone.nord, z).clamp(0, (1 << z) - 1);
      final y1 = yTile(zone.sud, z).clamp(0, (1 << z) - 1);
      total += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return total;
  }

  /// Telecharge toutes les tuiles de la zone pour la plage de zooms.
  /// [urlTemplate] est le gabarit d'URL du fond ({z}/{x}/{y}). Les
  /// tuiles deja presentes sont sautees sans requete reseau.
  static Future<ResultatTelechargementTuiles> telecharger({
    required ZoneTuiles zone,
    required int zoomMin,
    required int zoomMax,
    required String urlTemplate,
    required String nomFond,
    void Function(int telechargees, int total)? onProgression,
    bool Function()? doitAnnuler,
  }) async {
    await racine();
    final total = compterTuiles(zone, zoomMin, zoomMax);
    var reussies = 0;
    var echecs = 0;
    var traitees = 0;
    for (var z = zoomMin; z <= zoomMax; z++) {
      final x0 = xTile(zone.ouest, z).clamp(0, (1 << z) - 1);
      final x1 = xTile(zone.est, z).clamp(0, (1 << z) - 1);
      final y0 = yTile(zone.nord, z).clamp(0, (1 << z) - 1);
      final y1 = yTile(zone.sud, z).clamp(0, (1 << z) - 1);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          if (doitAnnuler?.call() == true) {
            return ResultatTelechargementTuiles(
              total: total,
              reussies: reussies,
              echecs: echecs,
            );
          }
          traitees++;
          final chemin = cheminTuileSync(nomFond, z, x, y);
          if (File(chemin).existsSync()) {
            reussies++;
            onProgression?.call(traitees, total);
            continue;
          }
          final url = urlTemplate
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');
          try {
            final response = await http
                .get(Uri.parse(url), headers: _headers)
                .timeout(const Duration(seconds: 20));
            if (response.statusCode == 200 &&
                response.bodyBytes.isNotEmpty) {
              await ecrireTuile(nomFond, z, x, y, response.bodyBytes);
              reussies++;
            } else {
              echecs++;
            }
          } catch (_) {
            echecs++;
          }
          onProgression?.call(traitees, total);
          await Future<void>.delayed(_pauseEntreTuiles);
        }
      }
    }
    return ResultatTelechargementTuiles(
      total: total,
      reussies: reussies,
      echecs: echecs,
    );
  }
}

/// Fournisseur de tuiles qui sert d'abord le stockage local (tuiles
/// pre-telechargees par [TuilesHorsLigneService]), puis retombe sur
/// le comportement reseau standard de flutter_map (avec son cache
/// integre). Remplace le simple NetworkTileProvider dans la carte
/// voyage : hors ligne, les zones pre-chargees restent affichables,
/// le GPS continue de fonctionner (il ne depend pas du reseau).
class TuilesHorsLigneTileProvider extends NetworkTileProvider {
  TuilesHorsLigneTileProvider({required this.nomFond});

  /// Nom du fond ('osm', 'ignPlan', 'ignPhoto') : determine le
  /// sous-dossier de stockage des tuiles locales.
  final String nomFond;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final chemin = TuilesHorsLigneService.cheminTuileSync(
      nomFond,
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );
    final fichier = File(chemin);
    if (fichier.existsSync()) {
      return FileImage(fichier);
    }
    return super.getImage(coordinates, options);
  }
}

/// Taille occupee par les tuiles pre-telechargees (octets), pour
/// l'affichage dans l'interface de gestion.
Future<int> tailleStockageTuiles() async {
  final racine = Directory(await TuilesHorsLigneService.racine());
  if (!await racine.exists()) return 0;
  var total = 0;
  await for (final entite in racine.list(recursive: true)) {
    if (entite is File) {
      total += await entite.length();
    }
  }
  return total;
}

/// Supprime toutes les tuiles pre-telechargees.
Future<void> viderStockageTuiles() async {
  final racine = Directory(await TuilesHorsLigneService.racine());
  if (await racine.exists()) {
    await racine.delete(recursive: true);
  }
}
