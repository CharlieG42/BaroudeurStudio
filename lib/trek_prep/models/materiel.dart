/// Famille de materiel (ex : Vetements, Couchage, Cuisine...).
/// La liste est entierement personnalisable par l'utilisateur.
class FamilleMateriel {
  final int? id;
  final String nom;

  FamilleMateriel({this.id, required this.nom});

  Map<String, dynamic> toMap() => {'id': id, 'nom': nom};

  factory FamilleMateriel.fromMap(Map<String, dynamic> map) =>
      FamilleMateriel(id: map['id'] as int?, nom: map['nom'] as String);
}

/// Sous-famille de materiel rattachee a une famille
/// (ex : Vetements > Chaussures).
class SousFamilleMateriel {
  final int? id;
  final int familleId;
  final String nom;

  SousFamilleMateriel({this.id, required this.familleId, required this.nom});

  Map<String, dynamic> toMap() =>
      {'id': id, 'famille_id': familleId, 'nom': nom};

  factory SousFamilleMateriel.fromMap(Map<String, dynamic> map) =>
      SousFamilleMateriel(
        id: map['id'] as int?,
        familleId: map['famille_id'] as int,
        nom: map['nom'] as String,
      );
}

/// Marque de materiel (ex : MSR, Millet...).
class MarqueMateriel {
  final int? id;
  final String nom;

  MarqueMateriel({this.id, required this.nom});

  Map<String, dynamic> toMap() => {'id': id, 'nom': nom};

  factory MarqueMateriel.fromMap(Map<String, dynamic> map) =>
      MarqueMateriel(id: map['id'] as int?, nom: map['nom'] as String);
}

/// Un element de materiel (ex : tente 2 places).
class Materiel {
  final int? id;
  final String nom;
  final int? marqueId;
  final String? description;
  final double poidsGrammes;
  final int? familleId;
  final int? sousFamilleId;
  final String? cheminPhoto;

  Materiel({
    this.id,
    required this.nom,
    this.marqueId,
    this.description,
    this.poidsGrammes = 0,
    this.familleId,
    this.sousFamilleId,
    this.cheminPhoto,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'marque_id': marqueId,
        'description': description,
        'poids_grammes': poidsGrammes,
        'famille_id': familleId,
        'sous_famille_id': sousFamilleId,
        'chemin_photo': cheminPhoto,
      };

  factory Materiel.fromMap(Map<String, dynamic> map) => Materiel(
        id: map['id'] as int?,
        nom: map['nom'] as String,
        marqueId: map['marque_id'] as int?,
        description: map['description'] as String?,
        poidsGrammes: (map['poids_grammes'] as num?)?.toDouble() ?? 0,
        familleId: map['famille_id'] as int?,
        sousFamilleId: map['sous_famille_id'] as int?,
        cheminPhoto: map['chemin_photo'] as String?,
      );
}
