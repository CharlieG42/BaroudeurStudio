class Trek {
  final int? id;
  final String titre;
  final DateTime dateDebut;  // ✅ Changé de String à DateTime
  final DateTime dateFin;    // ✅ Changé de String à DateTime
  final String region;
  final String pays;
  final double? distanceKm;
  final int? denivelePositifM;
  final String modeVoyage;
  final String compagnons;

  Trek({
    this.id,
    required this.titre,
    required this.dateDebut,
    required this.dateFin,
    required this.region,
    required this.pays,
    this.distanceKm,
    this.denivelePositifM,
    this.modeVoyage = '',
    this.compagnons = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'date_debut': dateDebut.toIso8601String(),  // ✅ Conversion en String pour la DB
      'date_fin': dateFin.toIso8601String(),
      'region': region,
      'pays': pays,
      'distance_km': distanceKm,
      'denivele_positif_m': denivelePositifM,
      'mode_voyage': modeVoyage,
      'compagnons': compagnons,
    };
  }

  factory Trek.fromMap(Map<String, dynamic> map) {
    return Trek(
      id: map['id'] as int?,
      titre: map['titre'] as String,
      dateDebut: DateTime.parse(map['date_debut'] as String),  // ✅ Conversion de String à DateTime
      dateFin: DateTime.parse(map['date_fin'] as String),
      region: map['region'] as String,
      pays: map['pays'] as String,
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      denivelePositifM: map['denivele_positif_m'] as int?,
      modeVoyage: map['mode_voyage'] as String? ?? '',
      compagnons: map['compagnons'] as String? ?? '',
    );
  }

  // ✅ Calcul de la durée en jours
  int get dureeJours {
    return dateFin.difference(dateDebut).inDays + 1;
  }

  Trek copyWith({
    int? id,
    String? titre,
    DateTime? dateDebut,
    DateTime? dateFin,
    String? region,
    String? pays,
    double? distanceKm,
    int? denivelePositifM,
    String? modeVoyage,
    String? compagnons,
  }) {
    return Trek(
      id: id ?? this.id,
      titre: titre ?? this.titre,
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
      region: region ?? this.region,
      pays: pays ?? this.pays,
      distanceKm: distanceKm ?? this.distanceKm,
      denivelePositifM: denivelePositifM ?? this.denivelePositifM,
      modeVoyage: modeVoyage ?? this.modeVoyage,
      compagnons: compagnons ?? this.compagnons,
    );
  }
}