enum MediaType { photo, video, audio }

extension MediaTypeExtension on MediaType {
  String get value {
    switch (this) {
      case MediaType.photo:
        return 'photo';
      case MediaType.video:
        return 'video';
      case MediaType.audio:
        return 'audio';
    }
  }

  static MediaType fromValue(String value) {
    switch (value) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      default:
        return MediaType.photo;
    }
  }
}

class Media {
  final int? id;
  final int jourId;
  final MediaType type;
  final String cheminFichier; // chemin vers le fichier copié dans le dossier de l'app
  final String nomOriginal; // nom du fichier original, pour référence
  final String? legende;
  final String dateAjout; // ISO8601

  Media({
    this.id,
    required this.jourId,
    required this.type,
    required this.cheminFichier,
    required this.nomOriginal,
    this.legende,
    required this.dateAjout,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jour_id': jourId,
      'type': type.value,
      'chemin_fichier': cheminFichier,
      'nom_original': nomOriginal,
      'legende': legende,
      'date_ajout': dateAjout,
    };
  }

  factory Media.fromMap(Map<String, dynamic> map) {
    return Media(
      id: map['id'] as int?,
      jourId: map['jour_id'] as int,
      type: MediaTypeExtension.fromValue(map['type'] as String),
      cheminFichier: map['chemin_fichier'] as String,
      nomOriginal: map['nom_original'] as String,
      legende: map['legende'] as String?,
      dateAjout: map['date_ajout'] as String,
    );
  }
}
