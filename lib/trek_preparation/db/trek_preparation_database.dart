import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/materiel_models.dart';

/// Couche d'acces a la base de donnees du module de preparation de
/// trek. Fichier SQLite separe ('trek_preparation.db'), independant du
/// carnet de trek et du planificateur de voyage.
class TrekPreparationDatabase {
  static final TrekPreparationDatabase instance =
      TrekPreparationDatabase._internal();
  static Database? _database;

  TrekPreparationDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbDir = await getApplicationDocumentsDirectory();
    final path = p.join(dbDir.path, 'trek_preparation.db');
    return databaseFactory.openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE familles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE sous_familles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        famille_id INTEGER NOT NULL,
        nom TEXT NOT NULL,
        FOREIGN KEY (famille_id) REFERENCES familles (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE marques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE materiels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        marque_id INTEGER NOT NULL,
        description TEXT,
        poids_grammes REAL NOT NULL DEFAULT 0,
        famille_id INTEGER NOT NULL,
        sous_famille_id INTEGER,
        photo_path TEXT,
        FOREIGN KEY (marque_id) REFERENCES marques (id),
        FOREIGN KEY (famille_id) REFERENCES familles (id),
        FOREIGN KEY (sous_famille_id) REFERENCES sous_familles (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE listes_materiel (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL,
        date_trek TEXT,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE lignes_liste (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        liste_id INTEGER NOT NULL,
        materiel_id INTEGER NOT NULL,
        quantite INTEGER NOT NULL DEFAULT 1,
        pris INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (liste_id) REFERENCES listes_materiel (id) ON DELETE CASCADE,
        FOREIGN KEY (materiel_id) REFERENCES materiels (id) ON DELETE CASCADE
      )
    ''');
    await db.insert('familles', {'nom': 'Vêtement'});
    await db.insert('familles', {'nom': 'Sac à dos'});
    await db.insert('familles', {'nom': 'Couchage'});
    await db.insert('familles', {'nom': 'Cuisine'});
    await db.insert('familles', {'nom': 'Hygiène'});
    await db.insert('familles', {'nom': 'Électronique'});
    await db.insert('familles', {'nom': 'Divers'});
  }

  // FAMILLES

  Future<int> insertFamille(Famille famille) async {
    final db = await database;
    return db.insert('familles', famille.toMap()..remove('id'));
  }

  Future<List<Famille>> getFamilles() async {
    final db = await database;
    final maps = await db.query('familles', orderBy: 'nom COLLATE NOCASE ASC');
    return maps.map(Famille.fromMap).toList();
  }

  Future<int> updateFamille(Famille famille) async {
    final db = await database;
    return db.update(
      'familles',
      {'nom': famille.nom},
      where: 'id = ?',
      whereArgs: [famille.id],
    );
  }

  Future<int> deleteFamille(int id) async {
    final db = await database;
    return db.delete('familles', where: 'id = ?', whereArgs: [id]);
  }

  // SOUS-FAMILLES

  Future<int> insertSousFamille(SousFamille sousFamille) async {
    final db = await database;
    return db.insert('sous_familles', sousFamille.toMap()..remove('id'));
  }

  Future<List<SousFamille>> getSousFamillesForFamille(int familleId) async {
    final db = await database;
    final maps = await db.query(
      'sous_familles',
      where: 'famille_id = ?',
      whereArgs: [familleId],
      orderBy: 'nom COLLATE NOCASE ASC',
    );
    return maps.map(SousFamille.fromMap).toList();
  }

  Future<List<SousFamille>> getAllSousFamilles() async {
    final db = await database;
    final maps =
        await db.query('sous_familles', orderBy: 'nom COLLATE NOCASE ASC');
    return maps.map(SousFamille.fromMap).toList();
  }

  Future<int> updateSousFamille(SousFamille sousFamille) async {
    final db = await database;
    return db.update(
      'sous_familles',
      {'nom': sousFamille.nom},
      where: 'id = ?',
      whereArgs: [sousFamille.id],
    );
  }

  Future<int> deleteSousFamille(int id) async {
    final db = await database;
    return db.delete('sous_familles', where: 'id = ?', whereArgs: [id]);
  }

  // MARQUES

  Future<int> insertMarque(Marque marque) async {
    final db = await database;
    return db.insert('marques', marque.toMap()..remove('id'));
  }

  Future<List<Marque>> getMarques() async {
    final db = await database;
    final maps = await db.query('marques', orderBy: 'nom COLLATE NOCASE ASC');
    return maps.map(Marque.fromMap).toList();
  }

  Future<int> updateMarque(Marque marque) async {
    final db = await database;
    return db.update(
      'marques',
      {'nom': marque.nom},
      where: 'id = ?',
      whereArgs: [marque.id],
    );
  }

  Future<int> deleteMarque(int id) async {
    final db = await database;
    return db.delete('marques', where: 'id = ?', whereArgs: [id]);
  }

  // MATERIELS

  Future<int> insertMateriel(Materiel materiel) async {
    final db = await database;
    return db.insert('materiels', materiel.toMap()..remove('id'));
  }

  Future<List<Materiel>> getMateriels() async {
    final db = await database;
    final maps =
        await db.query('materiels', orderBy: 'nom COLLATE NOCASE ASC');
    return maps.map(Materiel.fromMap).toList();
  }

  Future<Materiel?> getMateriel(int id) async {
    final db = await database;
    final maps =
        await db.query('materiels', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Materiel.fromMap(maps.first);
  }

  Future<int> updateMateriel(Materiel materiel) async {
    final db = await database;
    return db.update(
      'materiels',
      materiel.toMap(),
      where: 'id = ?',
      whereArgs: [materiel.id],
    );
  }

  Future<int> deleteMateriel(int id) async {
    final db = await database;
    return db.delete('materiels', where: 'id = ?', whereArgs: [id]);
  }

  // LISTES DE MATERIEL

  Future<int> insertListe(ListeMateriel liste) async {
    final db = await database;
    return db.insert('listes_materiel', liste.toMap()..remove('id'));
  }

  Future<List<ListeMateriel>> getListes() async {
    final db = await database;
    final maps = await db.query('listes_materiel', orderBy: 'id DESC');
    return maps.map(ListeMateriel.fromMap).toList();
  }

  Future<int> updateListe(ListeMateriel liste) async {
    final db = await database;
    return db.update(
      'listes_materiel',
      liste.toMap(),
      where: 'id = ?',
      whereArgs: [liste.id],
    );
  }

  Future<int> deleteListe(int id) async {
    final db = await database;
    return db.delete('listes_materiel', where: 'id = ?', whereArgs: [id]);
  }

  // LIGNES DE LISTE

  Future<int> insertLigne(LigneListe ligne) async {
    final db = await database;
    return db.insert('lignes_liste', ligne.toMap()..remove('id'));
  }

  Future<int> updateLigne(LigneListe ligne) async {
    final db = await database;
    return db.update(
      'lignes_liste',
      ligne.toMap(),
      where: 'id = ?',
      whereArgs: [ligne.id],
    );
  }

  Future<int> deleteLigne(int id) async {
    final db = await database;
    return db.delete('lignes_liste', where: 'id = ?', whereArgs: [id]);
  }

  /// Toutes les lignes d'une liste, jointes avec le materiel, la famille,
  /// la sous-famille et la marque, pour l'affichage et les totaux.
  Future<List<LigneListeDetaillee>> getLignesDetaillees(int listeId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        l.id AS ligne_id,
        l.liste_id AS liste_id,
        l.materiel_id AS materiel_id,
        l.quantite AS quantite,
        l.pris AS pris,
        m.nom AS materiel_nom,
        m.marque_id AS marque_id,
        m.description AS description,
        m.poids_grammes AS poids_grammes,
        m.famille_id AS famille_id,
        m.sous_famille_id AS sous_famille_id,
        m.photo_path AS photo_path,
        f.nom AS famille_nom,
        sf.nom AS sous_famille_nom,
        ma.nom AS marque_nom
      FROM lignes_liste l
      JOIN materiels m ON m.id = l.materiel_id
      LEFT JOIN familles f ON f.id = m.famille_id
      LEFT JOIN sous_familles sf ON sf.id = m.sous_famille_id
      LEFT JOIN marques ma ON ma.id = m.marque_id
      WHERE l.liste_id = ?
      ORDER BY f.nom COLLATE NOCASE ASC, m.nom COLLATE NOCASE ASC
    ''', [listeId]);
    return maps.map((map) {
      return LigneListeDetaillee(
        ligne: LigneListe(
          id: map['ligne_id'] as int?,
          listeId: map['liste_id'] as int,
          materielId: map['materiel_id'] as int,
          quantite: map['quantite'] as int,
          pris: (map['pris'] as int) == 1,
        ),
        materiel: Materiel(
          id: map['materiel_id'] as int?,
          nom: map['materiel_nom'] as String,
          marqueId: map['marque_id'] as int,
          description: map['description'] as String? ?? '',
          poidsGrammes: (map['poids_grammes'] as num?)?.toDouble() ?? 0,
          familleId: map['famille_id'] as int,
          sousFamilleId: map['sous_famille_id'] as int?,
          photoPath: map['photo_path'] as String? ?? '',
        ),
        nomFamille: map['famille_nom'] as String? ?? '',
        nomSousFamille: map['sous_famille_nom'] as String? ?? '',
        nomMarque: map['marque_nom'] as String? ?? '',
      );
    }).toList();
  }

  /// Somme des poids par famille d'une liste (toutes lignes, prises ou
  /// non), pour l'affichage "poids par categorie".
  Future<List<PoidsParFamille>> getPoidsParFamille(int listeId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT
        COALESCE(f.nom, 'Divers') AS famille_nom,
        SUM(m.poids_grammes * l.quantite) AS poids_total
      FROM lignes_liste l
      JOIN materiels m ON m.id = l.materiel_id
      LEFT JOIN familles f ON f.id = m.famille_id
      WHERE l.liste_id = ?
      GROUP BY f.nom
      ORDER BY poids_total DESC
    ''', [listeId]);
    return maps
        .map((map) => PoidsParFamille(
              nomFamille: map['famille_nom'] as String,
              poidsGrammes: (map['poids_total'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  /// Poids total de la liste, en grammes.
  Future<double> getPoidsTotal(int listeId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(m.poids_grammes * l.quantite) AS total
      FROM lignes_liste l
      JOIN materiels m ON m.id = l.materiel_id
      WHERE l.liste_id = ?
    ''', [listeId]);
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Verifie si un materiel est deja present dans une liste.
  Future<bool> materielDansListe(int listeId, int materielId) async {
    final db = await database;
    final maps = await db.query(
      'lignes_liste',
      where: 'liste_id = ? AND materiel_id = ?',
      whereArgs: [listeId, materielId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }
}
