/// Origine d'un waypoint : suggere automatiquement par le module
/// (recommandations autour du trace du voyage) ou cree manuellement
/// par l'utilisateur.
enum SourceWaypoint { recommande, personnel }

SourceWaypoint sourceWaypointFromString(String value) {
  return SourceWaypoint.values.firstWhere(
    (s) => s.name == value,
    orElse: () => SourceWaypoint.recommande,
  );
}

/// Un waypoint est un point d'interet qui n'est PAS une etape : il ne
/// participe ni au calcul des trajets, ni a l'ordre chronologique du
/// voyage. Deux usages :
///
/// - **Recommande** ([SourceWaypoint.recommande]) : POI OpenStreetMap
///   propose autour du trace (point de vue, cascade, monument...),
///   obtenu via Overpass au moment ou l'utilisateur demande des
///   suggestions, puis mis en cache en base.
/// - **Personnel** ([SourceWaypoint.personnel]) : epingle libre posee
///   par l'utilisateur sur la carte, sans contrainte.
///
/// Un waypoint peut etre converti en etape de type passage depuis
/// l'interface ; la conversion reutilise alors le mecanisme standard
/// d'insertion d'etape (recalcul des trajets inclus).
class Waypoint {
  final int? id;
  final int voyageId;
  final String nom;
  final double latitude;
  final double longitude;
  final SourceWaypoint source;

  /// Categorie lisible du POI (ex: 'tourism=viewpoint',
  /// 'natural=waterfall', 'personnel'). Sert uniquement a l'affichage
  /// (icone et libelle de la fiche detail).
  final String categorie;
  final String notes;
  final String? osmId; // identifiant du noeud OSM, pour dedupliquer les recommandations

  Waypoint({
    this.id,
    required this.voyageId,
    required this.nom,
    required this.latitude,
    required this.longitude,
    this.source = SourceWaypoint.recommande,
    this.categorie = '',
    this.notes = '',
    this.osmId,
  });

  bool get estPersonnel => source == SourceWaypoint.personnel;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voyage_id': voyageId,
      'nom': nom,
      'latitude': latitude,
      'longitude': longitude,
      'source': source.name,
      'categorie': categorie,
      'notes': notes,
      'osm_id': osmId,
    };
  }

  factory Waypoint.fromMap(Map<String, dynamic> map) {
    return Waypoint(
      id: map['id'] as int?,
      voyageId: map['voyage_id'] as int,
      nom: map['nom'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      source: sourceWaypointFromString(map['source'] as String? ?? 'recommande'),
      categorie: map['categorie'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      osmId: map['osm_id'] as String?,
    );
  }

  Waypoint copyWith({
    int? id,
    int? voyageId,
    String? nom,
    double? latitude,
    double? longitude,
    SourceWaypoint? source,
    String? categorie,
    String? notes,
    String? osmId,
  }) {
    return Waypoint(
      id: id ?? this.id,
      voyageId: voyageId ?? this.voyageId,
      nom: nom ?? this.nom,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      source: source ?? this.source,
      categorie: categorie ?? this.categorie,
      notes: notes ?? this.notes,
      osmId: osmId ?? this.osmId,
    );
  }
}
