/// Un voyage represente un road trip planifie, independant des "treks"
/// du module carnet/livre illustre. Il regroupe une suite d'etapes.
class Voyage {
  final int? id;
  final String titre;
  final String dateDebut; // format ISO 'yyyy-MM-dd'
  final String dateFin; // format ISO 'yyyy-MM-dd'
  final String notes;

  Voyage({
    this.id,
    required this.titre,
    required this.dateDebut,
    required this.dateFin,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titre': titre,
      'date_debut': dateDebut,
      'date_fin': dateFin,
      'notes': notes,
    };
  }

  factory Voyage.fromMap(Map<String, dynamic> map) {
    return Voyage(
      id: map['id'] as int?,
      titre: map['titre'] as String,
      dateDebut: map['date_debut'] as String,
      dateFin: map['date_fin'] as String,
      notes: map['notes'] as String? ?? '',
    );
  }

  Voyage copyWith({
    int? id,
    String? titre,
    String? dateDebut,
    String? dateFin,
    String? notes,
  }) {
    return Voyage(
      id: id ?? this.id,
      titre: titre ?? this.titre,
      dateDebut: dateDebut ?? this.dateDebut,
      dateFin: dateFin ?? this.dateFin,
      notes: notes ?? this.notes,
    );
  }
}
