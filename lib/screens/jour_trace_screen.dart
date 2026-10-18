import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../db/gpx_service.dart';
import '../models/totaux_trek.dart';
import '../trip_planner/services/tuiles_hors_ligne_service.dart';
import '../trip_planner/widgets/profil_altitude_chart.dart';

/// Affiche la trace GPX d'un jour sur une carte OpenStreetMap, avec
/// les points de depart et d'arrivee, les statistiques du parcours et
/// son profil d'altitude.
///
/// Les tuiles deja telechargees pour le planificateur de voyage (fond
/// OSM) sont reutilisees hors ligne.
class JourTraceScreen extends StatefulWidget {
  final String cheminGpx;
  final String titre;

  const JourTraceScreen({
    super.key,
    required this.cheminGpx,
    required this.titre,
  });

  @override
  State<JourTraceScreen> createState() => _JourTraceScreenState();
}

class _JourTraceScreenState extends State<JourTraceScreen> {
  static const _couleurTrace = Color(0xFFD84315);

  late final Future<_DonneesTrace> _donnees = _charger();

  Future<_DonneesTrace> _charger() async {
    final trace = await GpxService().lireTrace(widget.cheminGpx);
    return _DonneesTrace(
      trace: trace,
      stats: GpxService.statsDepuisPoints(trace.points),
      profil: trace.profilAltitude(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: FutureBuilder<_DonneesTrace>(
        future: _donnees,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(
              Icons.error_outline,
              'Impossible de lire la trace GPX.\n${snapshot.error}',
            );
          }
          final donnees = snapshot.data!;
          if (donnees.trace.estVide) {
            return _message(
              Icons.route,
              'Cette trace GPX ne contient pas assez de points pour être affichée.',
            );
          }
          return OrientationBuilder(
            builder: (context, orientation) {
              final carte = _buildCarte(donnees.trace);
              final details = _buildDetails(donnees);
              if (orientation == Orientation.landscape) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: carte),
                    Expanded(flex: 2, child: details),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(flex: 3, child: carte),
                  Expanded(flex: 2, child: details),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCarte(TraceGpx trace) {
    final points =
        trace.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(32),
          maxZoom: 16,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.baroudeurs.studio',
          maxZoom: 19,
          tileProvider: TuilesHorsLigneTileProvider(nomFond: 'osm'),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 4,
              color: _couleurTrace,
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _marqueur(points.first, Icons.play_arrow, Colors.green.shade700,
                'Départ'),
            _marqueur(points.last, Icons.flag, Colors.red.shade700, 'Arrivée'),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© les contributeurs OpenStreetMap'),
          ],
        ),
      ],
    );
  }

  Marker _marqueur(LatLng point, IconData icone, Color couleur, String label) {
    return Marker(
      point: point,
      width: 30,
      height: 30,
      child: Tooltip(
        message: label,
        child: Container(
          decoration: BoxDecoration(
            color: couleur,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icone, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  Widget _buildDetails(_DonneesTrace donnees) {
    final stats = donnees.stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            Chip(
              avatar: const Icon(Icons.straighten, size: 16),
              label: Text(formaterDistanceKm(stats.distanceKm)),
            ),
            if (donnees.trace.aDesAltitudes) ...[
              Chip(
                avatar: const Icon(Icons.trending_up, size: 16),
                label: Text('+${stats.denivelePositifM} m'),
              ),
              Chip(
                avatar: const Icon(Icons.trending_down, size: 16),
                label: Text('-${stats.deniveleNegatifM} m'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (donnees.trace.aDesAltitudes)
          ProfilAltitudeChart(profil: donnees.profil)
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Cette trace ne contient pas d\'altitudes : '
              'profil indisponible.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _message(IconData icone, String texte) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(texte, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DonneesTrace {
  final TraceGpx trace;
  final GpxStats stats;
  final List<List<double>> profil;

  const _DonneesTrace({
    required this.trace,
    required this.stats,
    required this.profil,
  });
}
