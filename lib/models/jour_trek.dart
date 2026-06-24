class JourTrek {
  final int? id;
  final int trekId;
  final int numeroJour; // Jour 1, Jour 2, ...
  final String date; // format ISO8601 (yyyy-MM-dd)
  final String lieuDepart;
  final String lieuArrivee;
  final double? distanceKm;
  final int? denivelePositifM;
  final int? deniveleNegatifM;
  final String meteo;
  final String resume;
  final String emotions;
  final String difficultes;
  final String decouvertes;
  final String notesVocalesTranscription;
  final String? cheminGpx; // chemin du fichier GPX importé, copié localement
  final String? texteGenereIA; // texte du jour produit par l'IA (modifiable)

  JourTrek({
    this.id,
    required this.trekId,
    required this.numeroJour,
    required this.date,
    this.lieuDepart = '',
    this.lieuArrivee = '',
    this.distanceKm,
    this.denivelePositifM,
    this.deniveleNegatifM,
    this.meteo = '',
    this.resume = '',
    this.emotions = '',
    this.difficultes = '',
    this.decouvertes = '',
    this.notesVocalesTranscription = '',
    this.cheminGpx,
    this.texteGenereIA,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trek_id': trekId,
      'numero_jour': numeroJour,
      'date': date,
      'lieu_depart': lieuDepart,
      'lieu_arrivee': lieuArrivee,
      'distance_km': distanceKm,
      'denivele_positif_m': denivelePositifM,
      'denivele_negatif_m': deniveleNegatifM,
      'meteo': meteo,
      'resume': resume,
      'emotions': emotions,
      'difficultes': difficultes,
      'decouvertes': decouvertes,
      'notes_vocales_transcription': notesVocalesTranscription,
      'chemin_gpx': cheminGpx,
      'texte_genere_ia': texteGenereIA,
    };
  }

  factory JourTrek.fromMap(Map<String, dynamic> map) {
    return JourTrek(
      id: map['id'] as int?,
      trekId: map['trek_id'] as int,
      numeroJour: map['numero_jour'] as int,
      date: map['date'] as String,
      lieuDepart: map['lieu_depart'] as String? ?? '',
      lieuArrivee: map['lieu_arrivee'] as String? ?? '',
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      denivelePositifM: map['denivele_positif_m'] as int?,
      deniveleNegatifM: map['denivele_negatif_m'] as int?,
      meteo: map['meteo'] as String? ?? '',
      resume: map['resume'] as String? ?? '',
      emotions: map['emotions'] as String? ?? '',
      difficultes: map['difficultes'] as String? ?? '',
      decouvertes: map['decouvertes'] as String? ?? '',
      notesVocalesTranscription: map['notes_vocales_transcription'] as String? ?? '',
      cheminGpx: map['chemin_gpx'] as String?,
      texteGenereIA: map['texte_genere_ia'] as String?,
    );
  }

  JourTrek copyWith({
    int? id,
    int? trekId,
    int? numeroJour,
    String? date,
    String? lieuDepart,
    String? lieuArrivee,
    double? distanceKm,
    int? denivelePositifM,
    int? deniveleNegatifM,
    String? meteo,
    String? resume,
    String? emotions,
    String? difficultes,
    String? decouvertes,
    String? notesVocalesTranscription,
    String? cheminGpx,
    String? texteGenereIA,
  }) {
    return JourTrek(
      id: id ?? this.id,
      trekId: trekId ?? this.trekId,
      numeroJour: numeroJour ?? this.numeroJour,
      date: date ?? this.date,
      lieuDepart: lieuDepart ?? this.lieuDepart,
      lieuArrivee: lieuArrivee ?? this.lieuArrivee,
      distanceKm: distanceKm ?? this.distanceKm,
      denivelePositifM: denivelePositifM ?? this.denivelePositifM,
      deniveleNegatifM: deniveleNegatifM ?? this.deniveleNegatifM,
      meteo: meteo ?? this.meteo,
      resume: resume ?? this.resume,
      emotions: emotions ?? this.emotions,
      difficultes: difficultes ?? this.difficultes,
      decouvertes: decouvertes ?? this.decouvertes,
      notesVocalesTranscription:
          notesVocalesTranscription ?? this.notesVocalesTranscription,
      cheminGpx: cheminGpx ?? this.cheminGpx,
      texteGenereIA: texteGenereIA ?? this.texteGenereIA,
    );
  }
}
