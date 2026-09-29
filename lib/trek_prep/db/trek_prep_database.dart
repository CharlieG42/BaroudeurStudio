import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/materiel.dart';

/// Couche d'acces a la base de donnees du module de preparation de
/// trek (checklist de materiel). Fichier SQLite separe
/// ('trek_prep.db'), independant du carnet de trek et du planificateur
/// de voyage, comme le reste des modules.
class TrekPrepDatabase {
  static final TrekPrepDatabase instance = TrekPrepDatabase._internal();
  static Database? _database;

  TrekPrepDatabase._internal();

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
    final path = join(dbDir.path, 'trek_prep.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
        marque_id INTEGER,
        description TEXT,
        poids_grammes REAL NOT NULL DEFAULT 0,
        famille_id INTEGER,
        sous_famille_id INTEGER,
        chemin_photo TEXT,
        FOREIGN KEY (marque_id) REFERENCES marques (id) ON DELETE SET NULL,
        FOREIGN KEY (famille_id) REFERENCES familles (id) ON DELETE SET NULL,
        FOREIGN KEY (sous_famille_id) REFERENCES sous_familles (id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE listes_materiel (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE listes_materiel_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        liste_id INTEGER NOT NULL,
        materiel_id INTEGER NOT NULL,
        quantite INTEGER NOT NULL DEFAULT 1,
        pris INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (liste_id) REFERENCES listes_materiel (id)
          ON DELETE CASCADE,
        FOREIGN KEY (materiel_id) REFERENCES materiels (id) ON DELETE CASCADE
      )
    ''');
    await _seedDefaultData(db);
  }

  /// Quelques familles par defaut pour demarrer vite ; l'utilisateur
  /// peut ensuite les modifier librement.
  Future<void> _seedDefaultData(Database db) async {
    const familles = [
      'Vêtements',
      'Chaussures',
      'Couchage',
      'Abri',
      'Sac',
      'Cuisine',
      'Nourriture',
      'Hygiène / Santé',
      'Navigation / Électronique',
      'Divers',
    ];
    for (final nom in familles) {
      await db.insert('familles', {'nom': nom});
    }
  }

  // FAMILLES

  Future<int> insertFamille(FamilleMateriel f) async {
    final db = await database;
    return db.insert('familles', f.toMap()..remove('id'));
  }

  Future<List<FamilleMateriel>> getFamilles() async {
    final db = await database;
    final maps = await db.query('familles', orderBy: 'nom COLLATE NOCASE');
    return maps.map(FamilleMateriel.fromMap).toList();
  }

  Future<int> updateFamille(FamilleMateriel f) async {
    final db = await database;
    return db.update(
      'familles',
      f.toMap(),
      where: 'id = ?',
      whereArgs: [f.id],
    );
  }

  /// Supprime une famille (et en cascade ses sous-familles). Les
  /// materiels rattaches perdent leur famille (SET NULL).
  Future<int> deleteFamille(int id) async {
    final db = await database;
    return db.delete('familles', where: 'id = ?', whereArgs: [id]);
  }

  // SOUS-FAMILLES

  Future<int> insertSousFamille(SousFamilleMateriel sf) async {
    final db = await database;
    return db.insert('sous_familles', sf.toMap()..remove('id'));
  }

  Future<List<SousFamilleMateriel>> getSousFamilles() async {
    final db = await database;
    final maps =
        await db.query('sous_familles', orderBy: 'nom COLLATE NOCASE');
    return maps.map(SousFamilleMateriel.fromMap).toList();
  }

  Future<int> updateSousFamille(SousFamilleMateriel sf) async {
    final db = await database;
    return db.update(
      'sous_familles',
      sf.toMap(),
      where: 'id = ?',
      whereArgs: [sf.id],
    );
  }

  Future<int> deleteSousFamille(int id) async {
    final db = await database;
    return db.delete('sous_familles', where: 'id = ?', whereArgs: [id]);
  }

  // MARQUES

  Future<int> insertMarque(MarqueMateriel m) async {
    final db = await database;
    return db.insert('marques', m.toMap()..remove('id'));
  }

  Future<List<MarqueMateriel>> getMarques() async {
    final db = await database;
    final maps = await db.query('marques', orderBy: 'nom COLLATE NOCASE');
    return maps.map(MarqueMateriel.fromMap).toList();
  }

  Future<int> updateMarque(MarqueMateriel m) async {
    final db = await database;
    return db.update('marques', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> deleteMarque(int id) async {
    final db = await database;
    return db.delete('marques', where: 'id = ?', whereArgs: [id]);
  }

  // MATERIELS

  Future<int> insertMateriel(Materiel m) async {
    final db = await database;
    return db.insert('materiels', m.toMap()..remove('id'));
  }

  Future<List<Materiel>> getMateriels() async {
    final db = await database;
    final maps = await db.query('materiels', orderBy: 'nom COLLATE NOCASE');
    return maps.map(Materiel.fromMap).toList();
  }

  Future<Materiel?> getMateriel(int id) async {
    final db = await database;
    final maps = await db.query('materiels', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Materiel.fromMap(maps.first);
  }

  Future<int> updateMateriel(Materiel m) async {
    final db = await database;
    return db.update(
      'materiels',
      m.toMap(),
      where: 'id = ?',
      whereArgs: [m.id],
    );
  }

  Future<int> deleteMateriel(int id) async {
    final db = await database;
    return db.delete('materiels', where: 'id = ?', whereArgs: [id]);
  }

  // LISTES (checklists par trek)

  Future<int> insertListe(String nom) async {
    final db = await database;
    return db.insert('listes_materiel', {'nom': nom});
  }

  Future<List<Map<String, dynamic>>> getListes() async {
    final db = await database;
    return db.query('listes_materiel', orderBy: 'id DESC');
  }

  Future<int> renameListe(int id, String nom) async {
    final db = await database;
    return db.update(
      'listes_materiel',
      {'nom': nom},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteListe(int id) async {
    final db = await database;
    return db.delete('listes_materiel', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addItemToListe({
    required int listeId,
    required int materielId,
    int quantite = 1,
  }) async {
    final db = await database;
    final existants = await db.query(
      'listes_materiel_items',
      where: 'liste_id = ? AND materiel_id = ?',
      whereArgs: [listeId, materielId],
    );
    if (existants.isEmpty) {
      await db.insert('listes_materiel_items', {
        'liste_id': listeId,
        'materiel_id': materielId,
        'quantite': quantite,
        'pris': 0,
      });
    } else {
      final q = (existants.first['quantite'] as int?) ?? 1;
      await db.update(
        'listes_materiel_items',
        {'quantite': q + quantite},
        where: 'id = ?',
        whereArgs: [existants.first['id']],
      );
    }
  }

  Future<void> removeItemFromListe(int itemId) async {
    final db = await database;
    await db.delete(
      'listes_materiel_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> setItemPris(int itemId, bool pris) async {
    final db = await database;
    await db.update(
      'listes_materiel_items',
      {'pris': pris ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> setItemQuantite(int itemId, int quantite) async {
    final db = await database;
    await db.update(
      'listes_materiel_items',
      {'quantite': quantite < 1 ? 1 : quantite},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Items d'une liste, enrichis des infos du materiel, de sa famille
  /// et de sa marque.
  Future<List<Map<String, dynamic>>> getItemsListe(int listeId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        i.id AS item_id,
        i.quantite AS quantite,
        i.pris AS pris,
        m.id AS materiel_id,
        m.nom AS materiel_nom,
        m.description AS description,
        m.poids_grammes AS poids_grammes,
        m.chemin_photo AS chemin_photo,
        ma.nom AS marque_nom,
        f.id AS famille_id,
        f.nom AS famille_nom,
        sf.nom AS sous_famille_nom
      FROM listes_materiel_items i
      JOIN materiels m ON m.id = i.materiel_id
      LEFT JOIN marques ma ON ma.id = m.marque_id
      LEFT JOIN familles f ON f.id = m.famille_id
      LEFT JOIN sous_familles sf ON sf.id = m.sous_famille_id
      WHERE i.liste_id = ?
      ORDER BY f.nom COLLATE NOCASE, sf.nom COLLATE NOCASE,
               m.nom COLLATE NOCASE
    ''', [listeId]);
  }
}
