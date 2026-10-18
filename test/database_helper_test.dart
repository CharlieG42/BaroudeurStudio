// Tests d'invariant de schema de la base du carnet de trek
// (DatabaseHelper). Garantissent qu'une base creee neuve (v4) a
// exactement le meme schema qu'une base migree depuis la version 1
// ou 2 : c'est le meme type de bug que celui des colonnes de
// denivele manquantes du planificateur (v7).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:les_baroudeurs/db/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('carnet_db_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<Database> ouvrirBaseNeuve() {
    return DatabaseHelper.instance.ouvrirPourTest('${tempDir.path}/neuve.db');
  }

  /// Schema de la version 1 (avant medias et colonnes de denivele
  /// des jours), pour forcer un upgrade complet 1 -> 4.
  /// La table treks possedait deja distance_km, denivele_positif_m,
  /// mode_voyage et compagnons des la premiere version (aucune
  /// migration ne les ajoute) : seul preambule arrive en v4.
  Future<Database> migrerDepuisV1() async {
    final db = await openDatabase('${tempDir.path}/v1.db', version: 1,
        onCreate: (db, version) async {
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
          meteo TEXT,
          resume TEXT,
          emotions TEXT,
          difficultes TEXT,
          decouvertes TEXT,
          FOREIGN KEY (trek_id) REFERENCES treks (id) ON DELETE CASCADE
        )
      ''');
    });
    await db.close();
    return DatabaseHelper.instance.ouvrirPourTest('${tempDir.path}/v1.db');
  }

  Future<List<String>> colonnes(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((c) => c['name'] as String).toList()..sort();
  }

  test('invariant : migration v1 -> v4 produit le schema d\'une base neuve',
      () async {
    final neuve = await ouvrirBaseNeuve();
    final migree = await migrerDepuisV1();
    for (final table in ['treks', 'jours', 'medias']) {
      expect(await colonnes(migree, table), await colonnes(neuve, table),
          reason: 'Schema divergent pour la table $table');
    }
    await neuve.close();
    await migree.close();
  });

  test('base neuve : la table jours possede les colonnes de denivele',
      () async {
    final db = await ouvrirBaseNeuve();
    final cols = await colonnes(db, 'jours');
    expect(cols, contains('denivele_positif_m'));
    expect(cols, contains('denivele_negatif_m'));
    expect(cols, contains('chemin_gpx'));
    expect(cols, contains('texte_genere_ia'));
    await db.close();
  });

  test('base migree : la table treks possede preambule (v4)', () async {
    final db = await migrerDepuisV1();
    final cols = await colonnes(db, 'treks');
    expect(cols, contains('preambule'));
    expect(await colonnes(db, 'medias'), contains('est_couverture'));
    await db.close();
  });
}
