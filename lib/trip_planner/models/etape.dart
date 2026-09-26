/// Type d'etape : un point de chute a visiter, ou une simple etape de
/// passage sur la route (ex: pause essence, ville traversee sans visite).
enum TypeEtape { visite, passage }

TypeEtape typeEtapeFromString(String value) {
  return TypeEtape.values.firstWhere(
    (t) => t.name == value,
    orElse: () => TypeEtape.visite,
  );
}

/// Une etape est un point de chute geolocalise dans le voyage :
/// une ville, un parc national, un point de vue, un hebergement...
///
/// [date] est la date d'arrivee, toujours renseignee (utilisee pour le
/// tri et l'affichage par defaut). Pour une etape de type [visite],
/// [heureArrivee], [dateDepart] et [heureDepart] permettent de preciser
/// une plage (utile pour un sejour de plusieurs jours au meme endroit,
/// ex: 2 nuits a Las Vegas). Tous sont optionnels : une etape peut
/// n'avoir qu'une date, sans heure precise.
class Etape {
  final int? id;
  final int voyageId;
  final int ordre; // position dans le voyage, 0-based
  final String nom;
  final double latitude;
  final double longitude;
  final String date; // date d'arrivee, format ISO 'yyyy-MM-dd'
  final TypeEtape type;
  final String notes;
  final int? dureeVisiteMinutes;
  final String? heureArrivee; // format 'HH:mm'
  final String? dateDepart; // format ISO 'yyyy-MM-dd', defaut = date
  final String? heureDepart; // format 'HH:mm'

  Etape({
    this.id,
    required this.voyageId,
    required this.ordre,
    required this.nom,
    required this.latitude,
    required this.longitude,
    required this.date,
    this.type = TypeEtape.visite,
    this.notes = '',
    this.dureeVisiteMinutes,
    this.heureArrivee,
    this.dateDepart,
    this.heureDepart,
  });

  /// Date de depart effective : [dateDepart] si renseignee, sinon la
  /// meme journee que l'arrivee.
  String get dateDepartEffective => dateDepart ?? date;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voyage_id': voyageId,
      'ordre': ordre,
      'nom': nom,
      'latitude': latitude,
      'longitude': longitude,
      'date': date,
      'type': type.name,
      'notes': notes,
      'duree_visite_minutes': dureeVisiteMinutes,
      'heure_arrivee': heureArrivee,
      'date_depart': dateDepart,
      'heure_depart': heureDepart,
    };
  }

  factory Etape.fromMap(Map<String, dynamic> map) {
    return Etape(
      id: map['id'] as int?,
      voyageId: map['voyage_id'] as int,
      ordre: map['ordre'] as int,
      nom: map['nom'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      date: map['date'] as String,
      type: typeEtapeFromString(map['type'] as String? ?? 'visite'),
      notes: map['notes'] as String? ?? '',
      dureeVisiteMinutes: map['duree_visite_minutes'] as int?,
      heureArrivee: map['heure_arrivee'] as String?,
      dateDepart: map['date_depart'] as String?,
      heureDepart: map['heure_depart'] as String?,
    );
  }

  Etape copyWith({
    int? id,
    int? voyageId,
    int? ordre,
    String? nom,
    double? latitude,
    double? longitude,
    String? date,
    TypeEtape? type,
    String? notes,
    int? dureeVisiteMinutes,
    String? heureArrivee,
    String? dateDepart,
    String? heureDepart,
    bool effacerHeureArrivee = false,
    bool effacerDateDepart = false,
    bool effacerHeureDepart = false,
  }) {
    return Etape(
      id: id ?? this.id,
      voyageId: voyageId ?? this.voyageId,
      ordre: ordre ?? this.ordre,
      nom: nom ?? this.nom,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      date: date ?? this.date,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      dureeVisiteMinutes: dureeVisiteMinutes ?? this.dureeVisiteMinutes,
      heureArrivee:
          effacerHeureArrivee ? null : (heureArrivee ?? this.heureArrivee),
      dateDepart: effacerDateDepart ? null : (dateDepart ?? this.dateDepart),
      heureDepart:
          effacerHeureDepart ? null : (heureDepart ?? this.heureDepart),
    );
  }
}
