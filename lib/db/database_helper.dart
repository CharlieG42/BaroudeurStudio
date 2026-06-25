import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/trek.dart';
import '../models/jour_trek.dart';
import '../models/media.dart';

/// Couche d'acces a la base de donnees SQLite.
/// Fonctionne sur Android/iOS (sqflite natif) et sur macOS/Windows/Linux
/// (sqflite_common_ffi, qui s'appuie sur sqlite3 natif).
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Sur desktop (macOS/Windows/Linux), on doit initialiser sqflite_ffi
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbDir = await getApplicationDocumentsDirectory();
    final path = join(dbDir.path, 'les_baroudeurs.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE treks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        titre TEXT NOT NULL,
        date_debut TEXT NOT NULL,
        date_fin TEXT NOT NULL,
        region TEXT NOT NULL,
        pays TEXT NOT NULL,
        distance_km REAL,
        denivele_positif_m INTEGER,
        mode_voyage TEXT,
        compagnons TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE jours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trek_id INTEGER NOT NULL,
        numero_jour INTEGER NOT NULL,
        date TEXT NOT NULL,
        lieu_depart TEXT,
        lieu_arrivee TEXT,
        distance_km REAL,
        denivele_positif_m INTEGER,
        denivele_negatif_m INTEGER,
        meteo TEXT,
        resume TEXT,
        emotions TEXT,
        difficultes TEXT,
        decouvertes TEXT,
        notes_vocales_transcription TEXT,
        chemin_gpx TEXT,
        texte_genere_ia TEXT,
        FOREIGN KEY (trek_id) REFERENCES treks (id) ON DELETE CASCADE
      )
    ''');

    await _createMediasTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMediasTable(db);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'jours', 'denivele_positif_m', 'INTEGER');
      await _addColumnIfMissing(db, 'jours', 'denivele_negatif_m', 'INTEGER');
      await _addColumnIfMissing(db, 'jours', 'notes_vocales_transcription', 'TEXT');
      await _addColumnIfMissing(db, 'jours', 'chemin_gpx', 'TEXT');
      await _addColumnIfMissing(db, 'jours', 'texte_genere_ia', 'TEXT');
    }
  }

  /// Ajoute une colonne a une table existante si elle n'existe pas deja.
  /// SQLite ne supporte pas ALTER TABLE ... ADD COLUMN IF NOT EXISTS,
  /// donc on verifie manuellement via PRAGMA table_info avant d'ajouter.
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

  Future<void> _createMediasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medias (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        jour_id INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'photo',
        chemin_fichier TEXT NOT NULL,
        nom_original TEXT,
        legende TEXT,
        date_ajout TEXT NOT NULL,
        FOREIGN KEY (jour_id) REFERENCES jours (id) ON DELETE CASCADE
      )
    ''');
  }

  // TREKS

  Future<int> insertTrek(Trek trek) async {
    final db = await database;
    return db.insert('treks', trek.toMap()..remove('id'));
  }

  Future<List<Trek>> getTreks() async {
    final db = await database;
    final maps = await db.query('treks', orderBy: 'date_debut DESC');
    return maps.map((m) => Trek.fromMap(m)).toList();
  }

  Future<Trek?> getTrek(int id) async {
    final db = await database;
    final maps = await db.query('treks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Trek.fromMap(maps.first);
  }

  Future<int> updateTrek(Trek trek) async {
    final db = await database;
    return db.update(
      'treks',
      trek.toMap(),
      where: 'id = ?',
      whereArgs: [trek.id],
    );
  }

  Future<int> deleteTrek(int id) async {
    final db = await database;
    await db.delete('jours', where: 'trek_id = ?', whereArgs: [id]);
    return db.delete('treks', where: 'id = ?', whereArgs: [id]);
  }

  // JOURS

  Future<int> insertJour(JourTrek jour) async {
    final db = await database;
    return db.insert('jours', jour.toMap()..remove('id'));
  }

  Future<List<JourTrek>> getJoursForTrek(int trekId) async {
    final db = await database;
    final maps = await db.query(
      'jours',
      where: 'trek_id = ?',
      whereArgs: [trekId],
      orderBy: 'numero_jour ASC',
    );
    return maps.map((m) => JourTrek.fromMap(m)).toList();
  }

  Future<int> updateJour(JourTrek jour) async {
    final db = await database;
    return db.update(
      'jours',
      jour.toMap(),
      where: 'id = ?',
      whereArgs: [jour.id],
    );
  }

  Future<int> deleteJour(int id) async {
    final db = await database;
    return db.delete('jours', where: 'id = ?', whereArgs: [id]);
  }

  // MEDIAS

  Future<int> insertMedia(Media media) async {
    final db = await database;
    return db.insert('medias', media.toMap()..remove('id'));
  }

  Future<List<Media>> getMediasForJour(int jourId) async {
    final db = await database;
    final maps = await db.query(
      'medias',
      where: 'jour_id = ?',
      whereArgs: [jourId],
      orderBy: 'date_ajout ASC',
    );
    return maps.map((m) => Media.fromMap(m)).toList();
  }

  Future<Media?> getMedia(int id) async {
    final db = await database;
    final maps = await db.query('medias', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Media.fromMap(maps.first);
  }

  Future<int> updateMediaLegende(int id, String legende) async {
    final db = await database;
    return db.update(
      'medias',
      {'legende': legende},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteMedia(int id) async {
    final db = await database;
    return db.delete('medias', where: 'id = ?', whereArgs: [id]);
  }
}
