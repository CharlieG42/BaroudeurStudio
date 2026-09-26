/// Un document attache a une etape : billet d'avion, confirmation de
/// reservation, ticket d'entree, photo de passeport... Fait du module
/// un vrai carnet de voyage, pas juste un planificateur d'itineraire.
class DocumentEtape {
  final int? id;
  final int etapeId;
  final String nomOriginal;
  final String cheminFichier; // chemin local, dans le stockage de l'app
  final String? typeMime;
  final int tailleOctets;
  final String dateAjout; // ISO 8601

  DocumentEtape({
    this.id,
    required this.etapeId,
    required this.nomOriginal,
    required this.cheminFichier,
    this.typeMime,
    required this.tailleOctets,
    required this.dateAjout,
  });

  bool get estImage {
    final ext = nomOriginal.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.heic');
  }

  bool get estPdf => nomOriginal.toLowerCase().endsWith('.pdf');

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'etape_id': etapeId,
      'nom_original': nomOriginal,
      'chemin_fichier': cheminFichier,
      'type_mime': typeMime,
      'taille_octets': tailleOctets,
      'date_ajout': dateAjout,
    };
  }

  factory DocumentEtape.fromMap(Map<String, dynamic> map) {
    return DocumentEtape(
      id: map['id'] as int?,
      etapeId: map['etape_id'] as int,
      nomOriginal: map['nom_original'] as String,
      cheminFichier: map['chemin_fichier'] as String,
      typeMime: map['type_mime'] as String?,
      tailleOctets: map['taille_octets'] as int? ?? 0,
      dateAjout: map['date_ajout'] as String,
    );
  }
}
