import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/voyage.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/document_etape.dart';
import '../models/waypoint.dart';

/// Couche d'acces a la base de donnees du module de planification de
/// voyage. Volontairement independante de [DatabaseHelper] (le carnet
/// de trek / livre illustre) : fichier SQLite separe
/// ('trip_planner.db'), aucune table partagee. Cela permet d'ajouter
/// ou de retirer ce module sans toucher au schema existant.
class TripPlannerDatabase {
  static final TripPlannerDatabase instance = TripPlannerDatabase._internal();
  static Database? _database;

  TripPlannerDatabase._internal();

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
    final path = join(dbDir.path, 'trip_planner.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'etapes', 'heure_arrivee', 'TEXT');
      await _addColumnIfMissing(db, 'etapes', 'date_depart', 'TEXT');
      await _addColumnIfMissing(db, 'etapes', 'heure_depart', 'TEXT');
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        'trajets',
        'mode',
        "TEXT NOT NULL DEFAULT 'voiture'",
      );
      await _addColumnIfMissing(db, 'trajets', 'transporteur', 'TEXT');
      await _addColumnIfMissing(db, 'trajets', 'lieu_depart', 'TEXT');
      await _addColumnIfMissing(db, 'trajets', 'lieu_arrivee', 'TEXT');
      await _addColumnIfMissing(db, 'trajets', 'heure_depart', 'TEXT');
      await _addColumnIfMissing(db, 'trajets', 'heure_arrivee', 'TEXT');
      await _addColumnIfMissing(db, 'trajets', 'notes', 'TEXT');
      await _createDocumentsTableIfMissing(db);
    }
    if (oldVersion < 4) {
      await _createWaypointsTableIfMissing(db);
    }
  }

  /// Ajoute une colonne a une table existante si elle n'existe pas
  /// deja (SQLite ne supporte pas ADD COLUMN IF NOT EXISTS).
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createWaypointsTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS waypoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voyage_id INTEGER NOT NULL,
        nom TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        source TEXT NOT NULL DEFAULT 'recommande',
        categorie TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        osm_id TEXT,
        FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createDocumentsTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        etape_id INTEGER NOT NULL,
        nom_original TEXT NOT NULL,
        chemin_fichier TEXT NOT NULL,
        type_mime TEXT,
        taille_octets INTEGER NOT NULL DEFAULT 0,
        date_ajout TEXT NOT NULL,
        FOREIGN KEY (etape_id) REFERENCES etapes (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE voyages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        titre TEXT NOT NULL,
        date_debut TEXT NOT NULL,
        date_fin TEXT NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE etapes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voyage_id INTEGER NOT NULL,
        ordre INTEGER NOT NULL,
        nom TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'visite',
        notes TEXT,
        duree_visite_minutes INTEGER,
        heure_arrivee TEXT,
        date_depart TEXT,
        heure_depart TEXT,
        FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE trajets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voyage_id INTEGER NOT NULL,
        etape_depart_id INTEGER NOT NULL,
        etape_arrivee_id INTEGER NOT NULL,
        mode TEXT NOT NULL DEFAULT 'voiture',
        distance_km REAL NOT NULL,
        duree_minutes INTEGER NOT NULL,
        geometrie_json TEXT NOT NULL,
        transporteur TEXT,
        lieu_depart TEXT,
        lieu_arrivee TEXT,
        heure_depart TEXT,
        heure_arrivee TEXT,
        notes TEXT,
        FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE,
        FOREIGN KEY (etape_depart_id) REFERENCES etapes (id) ON DELETE CASCADE,
        FOREIGN KEY (etape_arrivee_id) REFERENCES etapes (id) ON DELETE CASCADE
      )
    ''');

    await _createDocumentsTableIfMissing(db);
    await _createWaypointsTableIfMissing(db);
  }

  // VOYAGES

  Future<int> insertVoyage(Voyage voyage) async {
    final db = await database;
    return db.insert('voyages', voyage.toMap()..remove('id'));
  }

  Future<List<Voyage>> getVoyages() async {
    final db = await database;
    final maps = await db.query('voyages', orderBy: 'date_debut ASC');
    return maps.map((m) => Voyage.fromMap(m)).toList();
  }

  Future<Voyage?> getVoyage(int id) async {
    final db = await database;
    final maps = await db.query('voyages', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Voyage.fromMap(maps.first);
  }

  Future<int> updateVoyage(Voyage voyage) async {
    final db = await database;
    return db.update(
      'voyages',
      voyage.toMap(),
      where: 'id = ?',
      whereArgs: [voyage.id],
    );
  }

  Future<int> deleteVoyage(int id) async {
    final db = await database;
    final etapes = await getEtapesForVoyage(id);
    for (final etape in etapes) {
      if (etape.id != null) {
        await db.delete('documents', where: 'etape_id = ?', whereArgs: [etape.id]);
      }
    }
    await db.delete('trajets', where: 'voyage_id = ?', whereArgs: [id]);
    await db.delete('etapes', where: 'voyage_id = ?', whereArgs: [id]);
    await db.delete('waypoints', where: 'voyage_id = ?', whereArgs: [id]);
    return db.delete('voyages', where: 'id = ?', whereArgs: [id]);
  }

  // ETAPES

  Future<int> insertEtape(Etape etape) async {
    final db = await database;
    return db.insert('etapes', etape.toMap()..remove('id'));
  }

  Future<List<Etape>> getEtapesForVoyage(int voyageId) async {
    final db = await database;
    final maps = await db.query(
      'etapes',
      where: 'voyage_id = ?',
      whereArgs: [voyageId],
      orderBy: 'ordre ASC',
    );
    return maps.map((m) => Etape.fromMap(m)).toList();
  }

  Future<int> updateEtape(Etape etape) async {
    final db = await database;
    return db.update(
      'etapes',
      etape.toMap(),
      where: 'id = ?',
      whereArgs: [etape.id],
    );
  }

  Future<int> deleteEtape(int id) async {
    final db = await database;
    await db.delete('documents', where: 'etape_id = ?', whereArgs: [id]);
    await db.delete(
      'trajets',
      where: 'etape_depart_id = ? OR etape_arrivee_id = ?',
      whereArgs: [id, id],
    );
    return db.delete('etapes', where: 'id = ?', whereArgs: [id]);
  }

  // TRAJETS

  /// Enregistre (ou remplace) le trajet entre deux etapes consecutives.
  /// Un trajet existant pour la meme paire depart/arrivee est supprime
  /// avant insertion, pour eviter les doublons apres un recalcul.
  Future<int> upsertTrajet(Trajet trajet) async {
    final db = await database;
    await db.delete(
      'trajets',
      where: 'etape_depart_id = ? AND etape_arrivee_id = ?',
      whereArgs: [trajet.etapeDepartId, trajet.etapeArriveeId],
    );
    return db.insert('trajets', trajet.toMap()..remove('id'));
  }

  Future<List<Trajet>> getTrajetsForVoyage(int voyageId) async {
    final db = await database;
    final maps = await db.query(
      'trajets',
      where: 'voyage_id = ?',
      whereArgs: [voyageId],
    );
    return maps.map((m) => Trajet.fromMap(m)).toList();
  }

  /// Supprime uniquement les trajets en mode "voiture" d'un voyage :
  /// utilise avant un recalcul automatique, pour ne jamais toucher aux
  /// transferts saisis manuellement (avion, train, bus...).
  Future<void> deleteTrajetsVoitureForVoyage(int voyageId) async {
    final db = await database;
    await db.delete(
      'trajets',
      where: 'voyage_id = ? AND mode = ?',
      whereArgs: [voyageId, 'voiture'],
    );
  }

  Future<void> deleteTrajet(int id) async {
    final db = await database;
    await db.delete('trajets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTrajetsForVoyage(int voyageId) async {
    final db = await database;
    await db.delete('trajets', where: 'voyage_id = ?', whereArgs: [voyageId]);
  }

  // DOCUMENTS

  Future<int> insertDocument(DocumentEtape document) async {
    final db = await database;
    return db.insert('documents', document.toMap()..remove('id'));
  }

  Future<List<DocumentEtape>> getDocumentsForEtape(int etapeId) async {
    final db = await database;
    final maps = await db.query(
      'documents',
      where: 'etape_id = ?',
      whereArgs: [etapeId],
      orderBy: 'date_ajout ASC',
    );
    return maps.map((m) => DocumentEtape.fromMap(m)).toList();
  }

  Future<int> deleteDocument(int id) async {
    final db = await database;
    return db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  // WAYPOINTS

  Future<int> insertWaypoint(Waypoint waypoint) async {
    final db = await database;
    return db.insert('waypoints', waypoint.toMap()..remove('id'));
  }

  Future<List<Waypoint>> getWaypointsForVoyage(int voyageId) async {
    final db = await database;
    final maps = await db.query(
      'waypoints',
      where: 'voyage_id = ?',
      whereArgs: [voyageId],
      orderBy: 'nom ASC',
    );
    return maps.map((m) => Waypoint.fromMap(m)).toList();
  }

  Future<int> updateWaypoint(Waypoint waypoint) async {
    final db = await database;
    return db.update(
      'waypoints',
      waypoint.toMap(),
      where: 'id = ?',
      whereArgs: [waypoint.id],
    );
  }

  Future<int> deleteWaypoint(int id) async {
    final db = await database;
    return db.delete('waypoints', where: 'id = ?', whereArgs: [id]);
  }

  /// Supprime les waypoints recommandes d'un voyage : utilise avant de
  /// recharger les suggestions, pour ne jamais toucher aux wayoints
  /// personnels de l'utilisateur.
  Future<void> deleteWaypointsRecommandesForVoyage(int voyageId) async {
    final db = await database;
    await db.delete(
      'waypoints',
      where: 'voyage_id = ? AND source = ?',
      whereArgs: [voyageId, 'recommande'],
    );
  }
}
