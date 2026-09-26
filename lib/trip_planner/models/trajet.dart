import 'dart:convert';

/// Moyen de transport utilise pour relier deux etapes consecutives.
/// [voiture], [velo] et [marche] sont calcules automatiquement via
/// OSRM (un profil de routage different pour chacun) ; les autres
/// modes ([avion], [train], [bus], [autre]) sont saisis manuellement
/// par l'utilisateur.
enum ModeTransport { voiture, velo, marche, avion, train, bus, autre }

extension ModeTransportInfo on ModeTransport {
  /// Vrai pour les modes dont le trajet est calcule automatiquement
  /// par un service de routage (OSRM), faux pour les modes saisis
  /// manuellement (vol, train, bus, autre).
  bool get estAutoCalcule =>
      this == ModeTransport.voiture ||
      this == ModeTransport.velo ||
      this == ModeTransport.marche;
}

ModeTransport modeTransportFromString(String value) {
  return ModeTransport.values.firstWhere(
    (m) => m.name == value,
    orElse: () => ModeTransport.voiture,
  );
}

/// Un trajet relie deux etapes consecutives du voyage.
///
/// Pour le mode [ModeTransport.voiture], il est calcule automatiquement
/// via un service de routage (OSRM) : distance, duree et trace sont mis
/// en cache pour eviter de rappeler l'API a chaque affichage de la
/// carte. Pour les autres modes (avion, train, bus, autre), il est saisi
/// manuellement par l'utilisateur (transporteur/numero, lieux, heures)
/// et n'est jamais recalcule automatiquement.
class Trajet {
  final int? id;
  final int voyageId;
  final int etapeDepartId;
  final int etapeArriveeId;
  final ModeTransport mode;
  final double distanceKm;
  final int dureeMinutes;
  final String
      geometrieJson; // JSON: liste de [lat, lon] representant le trace
  final String? transporteur; // ex: "Southwest Airlines - WN 1234"
  final String? lieuDepart; // ex: "Aeroport McCarran (LAS)"
  final String? lieuArrivee;
  final String? heureDepart; // format 'HH:mm'
  final String? heureArrivee; // format 'HH:mm'
  final String notes;

  Trajet({
    this.id,
    required this.voyageId,
    required this.etapeDepartId,
    required this.etapeArriveeId,
    this.mode = ModeTransport.voiture,
    required this.distanceKm,
    required this.dureeMinutes,
    required this.geometrieJson,
    this.transporteur,
    this.lieuDepart,
    this.lieuArrivee,
    this.heureDepart,
    this.heureArrivee,
    this.notes = '',
  });

  /// Decode le trace en une liste de couples [latitude, longitude].
  /// Vide pour les trajets non routiers (pas de trace calcule).
  List<List<double>> get points {
    if (geometrieJson.isEmpty) return [];
    final decoded = jsonDecode(geometrieJson) as List<dynamic>;
    return decoded
        .map((p) => (p as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList())
        .toList();
  }

  static String encodePoints(List<List<double>> points) {
    return jsonEncode(points);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voyage_id': voyageId,
      'etape_depart_id': etapeDepartId,
      'etape_arrivee_id': etapeArriveeId,
      'mode': mode.name,
      'distance_km': distanceKm,
      'duree_minutes': dureeMinutes,
      'geometrie_json': geometrieJson,
      'transporteur': transporteur,
      'lieu_depart': lieuDepart,
      'lieu_arrivee': lieuArrivee,
      'heure_depart': heureDepart,
      'heure_arrivee': heureArrivee,
      'notes': notes,
    };
  }

  factory Trajet.fromMap(Map<String, dynamic> map) {
    return Trajet(
      id: map['id'] as int?,
      voyageId: map['voyage_id'] as int,
      etapeDepartId: map['etape_depart_id'] as int,
      etapeArriveeId: map['etape_arrivee_id'] as int,
      mode: modeTransportFromString(map['mode'] as String? ?? 'voiture'),
      distanceKm: (map['distance_km'] as num).toDouble(),
      dureeMinutes: map['duree_minutes'] as int,
      geometrieJson: map['geometrie_json'] as String? ?? '[]',
      transporteur: map['transporteur'] as String?,
      lieuDepart: map['lieu_depart'] as String?,
      lieuArrivee: map['lieu_arrivee'] as String?,
      heureDepart: map['heure_depart'] as String?,
      heureArrivee: map['heure_arrivee'] as String?,
      notes: map['notes'] as String? ?? '',
    );
  }
}
