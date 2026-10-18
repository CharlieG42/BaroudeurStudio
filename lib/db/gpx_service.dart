import 'dart:io';
import 'dart:math';
import 'package:gpx/gpx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Résultat du calcul d'une trace GPX : distance totale et dénivelés.
class GpxStats {
  final double distanceKm;
  final int denivelePositifM;
  final int deniveleNegatifM;
  final int nombrePoints;

  GpxStats({
    required this.distanceKm,
    required this.denivelePositifM,
    required this.deniveleNegatifM,
    required this.nombrePoints,
  });
}

/// Point d'une trace GPX.
class PointGpx {
  final double latitude;
  final double longitude;

  /// Altitude en metres, null si le GPX n'en fournit pas.
  final double? altitudeM;

  const PointGpx({
    required this.latitude,
    required this.longitude,
    this.altitudeM,
  });
}

/// Trace GPX complete d'un jour, prete a etre affichee sur une carte.
class TraceGpx {
  final List<PointGpx> points;

  const TraceGpx(this.points);

  bool get estVide => points.length < 2;

  /// Vrai si au moins deux points ont une altitude.
  bool get aDesAltitudes =>
      points.where((p) => p.altitudeM != null).length >= 2;

  /// Profil altitude/distance : couples [distance_km, altitude_m] dans
  /// l'ordre du parcours (format de [ProfilAltitudeChart]). Les points
  /// sans altitude comptent pour la distance mais ne sont pas tracés.
  /// Le profil est echantillonne a [maxPoints] points au plus pour
  /// garder un dessin fluide sur les traces denses.
  List<List<double>> profilAltitude({int maxPoints = 400}) {
    final profil = <List<double>>[];
    double distanceM = 0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        final a = points[i - 1];
        final b = points[i];
        distanceM += GpxService.distanceHaversineM(
            a.latitude, a.longitude, b.latitude, b.longitude);
      }
      final altitude = points[i].altitudeM;
      if (altitude != null) profil.add([distanceM / 1000, altitude]);
    }
    if (profil.length <= maxPoints || maxPoints < 2) return profil;

    // Echantillonnage regulier en conservant le premier et le dernier.
    final pas = (profil.length - 1) / (maxPoints - 1);
    return [
      for (var i = 0; i < maxPoints; i++) profil[(i * pas).round()],
    ];
  }
}

/// Service de lecture de fichiers GPX et de calcul de statistiques
/// (distance, dénivelé positif/négatif) à partir des points de la trace.
class GpxService {
  static const _uuid = Uuid();

  // Seuil de lissage : les variations d'altitude point à point en dessous
  // de ce seuil sont ignorées dans le calcul du dénivelé. Le bruit GPS sur
  // l'altitude (souvent +/- 5-10m) gonflerait artificiellement le
  // dénivelé total sans ce filtrage.
  static const double _seuilLissageM = 3.0;

  /// Parse un fichier GPX et calcule ses statistiques (distance, dénivelé).
  Future<GpxStats> calculerStats(String gpxFilePath) async {
    final content = await File(gpxFilePath).readAsString();
    return statsDepuisPoints(parserPoints(content));
  }

  /// Lit un fichier GPX et renvoie sa trace (points dans l'ordre).
  Future<TraceGpx> lireTrace(String gpxFilePath) async {
    final content = await File(gpxFilePath).readAsString();
    return TraceGpx(parserPoints(content));
  }

  /// Extrait tous les points d'un contenu GPX : ceux de toutes les
  /// tracks/segments dans l'ordre, ou a defaut ceux des routes.
  /// Les points sans coordonnees sont ignores.
  static List<PointGpx> parserPoints(String content) {
    final gpxData = GpxReader().fromString(content);

    final wpts = <Wpt>[];
    for (final track in gpxData.trks) {
      for (final segment in track.trksegs) {
        wpts.addAll(segment.trkpts);
      }
    }
    // Si aucune track, on retombe sur les routes (rtes) s'il y en a.
    if (wpts.isEmpty) {
      for (final route in gpxData.rtes) {
        wpts.addAll(route.rtepts);
      }
    }

    return [
      for (final w in wpts)
        if (w.lat != null && w.lon != null)
          PointGpx(latitude: w.lat!, longitude: w.lon!, altitudeM: w.ele),
    ];
  }

  /// Distance totale et dénivelés d'une liste de points.
  static GpxStats statsDepuisPoints(List<PointGpx> points) {
    if (points.length < 2) {
      return GpxStats(
        distanceKm: 0,
        denivelePositifM: 0,
        deniveleNegatifM: 0,
        nombrePoints: points.length,
      );
    }

    double distanceTotaleM = 0;
    double denivelePositif = 0;
    double deniveleNegatif = 0;

    double? altitudeLissee;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      distanceTotaleM += distanceHaversineM(
          a.latitude, a.longitude, b.latitude, b.longitude);

      // Calcul du dénivelé avec lissage simple pour réduire le bruit GPS.
      if (b.altitudeM != null) {
        altitudeLissee ??= a.altitudeM;
        if (altitudeLissee != null) {
          final delta = b.altitudeM! - altitudeLissee;
          if (delta.abs() >= _seuilLissageM) {
            if (delta > 0) {
              denivelePositif += delta;
            } else {
              deniveleNegatif += delta.abs();
            }
            altitudeLissee = b.altitudeM;
          }
        }
      }
    }

    return GpxStats(
      distanceKm: distanceTotaleM / 1000,
      denivelePositifM: denivelePositif.round(),
      deniveleNegatifM: deniveleNegatif.round(),
      nombrePoints: points.length,
    );
  }

  /// Distance en mètres entre deux points GPS, formule de Haversine
  /// (approximation suffisante pour des distances de randonnée, ne tient
  /// pas compte du relief — la distance "à vol d'oiseau" segment par
  /// segment, sommée sur tous les segments, donne une bonne approximation
  /// de la distance parcourue au sol pour une trace suffisamment dense).
  static double distanceHaversineM(
      double lat1, double lon1, double lat2, double lon2) {
    const rayonTerreM = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return rayonTerreM * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);

  /// Copie un fichier GPX importé vers le dossier géré par l'app, pour un
  /// jour donné. Suit la même convention que MediaStorageService.
  Future<String> copierGpxPourJour({
    required int jourId,
    required String sourcePath,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final jourDir = Directory(p.join(docsDir.path, 'media', 'jour_$jourId'));
    if (!await jourDir.exists()) {
      await jourDir.create(recursive: true);
    }

    final destPath = p.join(jourDir.path, '${_uuid.v4()}.gpx');
    await File(sourcePath).copy(destPath);
    return destPath;
  }
}
