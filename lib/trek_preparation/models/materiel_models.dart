/// Modeles du module de preparation de trek (checklist de materiel).
/// Famille / sous-famille / marque sont personnalisables par
/// l'utilisateur et stockees en base, tout comme le materiel.

class Famille {
  final int? id;
  final String nom;

  Famille({this.id, required this.nom});

  Map<String, dynamic> toMap() => {'id': id, 'nom': nom};

  factory Famille.fromMap(Map<String, dynamic> map) =>
      Famille(id: map['id'] as int?, nom: map['nom'] as String);
}

class SousFamille {
  final int? id;
  final int familleId;
  final String nom;

  SousFamille({this.id, required this.familleId, required this.nom});

  Map<String, dynamic> toMap() =>
      {'id': id, 'famille_id': familleId, 'nom': nom};

  factory SousFamille.fromMap(Map<String, dynamic> map) => SousFamille(
        id: map['id'] as int?,
        familleId: map['famille_id'] as int,
        nom: map['nom'] as String,
      );
}

class Marque {
  final int? id;
  final String nom;

  Marque({this.id, required this.nom});

  Map<String, dynamic> toMap() => {'id': id, 'nom': nom};

  factory Marque.fromMap(Map<String, dynamic> map) =>
      Marque(id: map['id'] as int?, nom: map['nom'] as String);
}

class Materiel {
  final int? id;
  final String nom;
  final int marqueId;
  final String description;
  final double poidsGrammes;
  final int familleId;
  final int? sousFamilleId;
  final String photoPath;

  Materiel({
    this.id,
    required this.nom,
    required this.marqueId,
    this.description = '',
    this.poidsGrammes = 0,
    required this.familleId,
    this.sousFamilleId,
    this.photoPath = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'marque_id': marqueId,
        'description': description,
        'poids_grammes': poidsGrammes,
        'famille_id': familleId,
        'sous_famille_id': sousFamilleId,
        'photo_path': photoPath,
      };

  factory Materiel.fromMap(Map<String, dynamic> map) => Materiel(
        id: map['id'] as int?,
        nom: map['nom'] as String,
        marqueId: map['marque_id'] as int,
        description: map['description'] as String? ?? '',
        poidsGrammes: (map['poids_grammes'] as num?)?.toDouble() ?? 0,
        familleId: map['famille_id'] as int,
        sousFamilleId: map['sous_famille_id'] as int?,
        photoPath: map['photo_path'] as String? ?? '',
      );
}

/// Une liste de materiel a prendre pour un trek donne.
class ListeMateriel {
  final int? id;
  final String nom;
  final String dateTrek;
  final String notes;

  ListeMateriel({
    this.id,
    required this.nom,
    this.dateTrek = '',
    this.notes = '',
  });

  Map<String, dynamic> toMap() =>
      {'id': id, 'nom': nom, 'date_trek': dateTrek, 'notes': notes};

  factory ListeMateriel.fromMap(Map<String, dynamic> map) => ListeMateriel(
        id: map['id'] as int?,
        nom: map['nom'] as String,
        dateTrek: map['date_trek'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
      );
}

/// Une ligne d'une liste : un materiel, une quantite, un etat "pris".
class LigneListe {
  final int? id;
  final int listeId;
  final int materielId;
  final int quantite;
  final bool pris;

  LigneListe({
    this.id,
    required this.listeId,
    required this.materielId,
    this.quantite = 1,
    this.pris = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'liste_id': listeId,
        'materiel_id': materielId,
        'quantite': quantite,
        'pris': pris ? 1 : 0,
      };

  factory LigneListe.fromMap(Map<String, dynamic> map) => LigneListe(
        id: map['id'] as int?,
        listeId: map['liste_id'] as int,
        materielId: map['materiel_id'] as int,
        quantite: (map['quantite'] as int?) ?? 1,
        pris: (map['pris'] as int?) == 1,
      );
}

/// Ligne enrichie apres jointure avec le materiel et sa famille, pour
/// l'affichage et le comptage des poids.
class LigneListeDetaillee {
  final LigneListe ligne;
  final Materiel materiel;
  final String nomFamille;
  final String nomSousFamille;
  final String nomMarque;

  LigneListeDetaillee({
    required this.ligne,
    required this.materiel,
    this.nomFamille = '',
    this.nomSousFamille = '',
    this.nomMarque = '',
  });

  /// Poids total de la ligne (poids unitaire x quantite), en grammes.
  double get poidsTotal => materiel.poidsGrammes * ligne.quantite;
}

/// Regroupement du poids par famille : sert a afficher le poids par
/// categorie et le poids total de la liste.
class PoidsParFamille {
  final String nomFamille;
  final double poidsGrammes;

  PoidsParFamille({required this.nomFamille, required this.poidsGrammes});
}
