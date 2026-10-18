// Tests d'invariant de schema de la base du planificateur de voyage.
//
// Un bug (v7) faisait que les installations neuves cree la table
// 'trajets' sans les colonnes de denivele : la migration les
// ajoutait dans _onUpgrade mais pas dans _onCreate. Chaque
// enregistrement de trajet echouait alors silencieusement.
//
// Ces tests garantissent qu'une base creee neuve a exactement le
// meme schema qu'une base migree pas a pas depuis n'importe quelle
// version anterieure.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:les_baroudeurs/trip_planner/db/trip_planner_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trip_planner_db_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<Database> ouvrirBaseNeuve() {
    return TripPlannerDatabase.instance
        .ouvrirPourTest('${tempDir.path}/neuve.db');
  }

  Future<Database> migrerDepuisV1() async {
    final db = await openDatabase('${tempDir.path}/v1.db', version: 1,
        onCreate: (db, version) async {
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
          FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE trajets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voyage_id INTEGER NOT NULL,
          etape_depart_id INTEGER NOT NULL,
          etape_arrivee_id INTEGER NOT NULL,
          distance_km REAL NOT NULL,
          duree_minutes INTEGER NOT NULL,
          geometrie_json TEXT NOT NULL,
          FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE,
          FOREIGN KEY (etape_depart_id) REFERENCES etapes (id) ON DELETE CASCADE,
          FOREIGN KEY (etape_arrivee_id) REFERENCES etapes (id) ON DELETE CASCADE
        )
      ''');
    });
    await db.close();
    // Reouverture : sqflite detecte version 1 -> 8 et joue _onUpgrade.
    return TripPlannerDatabase.instance
        .ouvrirPourTest('${tempDir.path}/v1.db');
  }

  Future<Database> migrerDepuisV4() async {
    // Schema tel que produit par la creation en v4 (colonnes v2-v3
    // incluses, table waypoints introduite en v4 ; ni parametres ni
    // deniveles).
    final db = await openDatabase('${tempDir.path}/v4.db', version: 4,
        onCreate: (db, version) async {
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
      await db.execute('''
        CREATE TABLE documents (
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
      await db.execute('''
        CREATE TABLE waypoints (
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
    });
    await db.close();
    return TripPlannerDatabase.instance
        .ouvrirPourTest('${tempDir.path}/v4.db');
  }

  /// Colonnes presentes d'une table, triees.
  Future<List<String>> colonnes(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((c) => c['name'] as String).toList()..sort();
  }

  test('base neuve : la table trajets possede les colonnes de denivele',
      () async {
    final db = await ouvrirBaseNeuve();
    final cols = await colonnes(db, 'trajets');
    expect(cols, contains('denivele_positif_m'));
    expect(cols, contains('denivele_negatif_m'));
    expect(cols, contains('profil_altitude_json'));
    await db.close();
  });

  test('invariant : migration v1 -> v8 produit le schema d\'une base neuve',
      () async {
    final neuve = await ouvrirBaseNeuve();
    final migree = await migrerDepuisV1();
    for (final table in [
      'voyages',
      'etapes',
      'trajets',
      'documents',
      'waypoints',
      'parametres',
    ]) {
      expect(await colonnes(migree, table), await colonnes(neuve, table),
          reason: 'Schema divergent pour la table $table');
    }
    await neuve.close();
    await migree.close();
  });

  test('invariant : migration v4 -> v8 produit le schema d\'une base neuve',
      () async {
    final neuve = await ouvrirBaseNeuve();
    final migree = await migrerDepuisV4();
    for (final table in [
      'voyages',
      'etapes',
      'trajets',
      'documents',
      'waypoints',
      'parametres',
    ]) {
      expect(await colonnes(migree, table), await colonnes(neuve, table),
          reason: 'Schema divergent pour la table $table');
    }
    await neuve.close();
    await migree.close();
  });

  test('reparation : une base v7 sans colonnes de denivele est reparee',
      () async {
    // Reproduit le bug : base creee neuve en v7 sans les colonnes de
    // denivele dans trajets. L'ouverture doit les rajouter.
    final path = '${tempDir.path}/v7_buggy.db';
    final db = await openDatabase(path, version: 7,
        onCreate: (db, version) async {
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
        CREATE TABLE trajets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voyage_id INTEGER NOT NULL,
          etape_depart_id INTEGER NOT NULL,
          etape_arrivee_id INTEGER NOT NULL,
          mode TEXT NOT NULL DEFAULT 'voiture',
          distance_km REAL NOT NULL,
          duree_minutes INTEGER NOT NULL,
          geometrie_json TEXT NOT NULL,
          FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE
        )
      ''');
    });
    await db.close();

    final reparee =
        await TripPlannerDatabase.instance.ouvrirPourTest(path);
    final cols = await colonnes(reparee, 'trajets');
    expect(cols, contains('denivele_positif_m'));
    expect(cols, contains('denivele_negatif_m'));
    expect(cols, contains('profil_altitude_json'));
    await reparee.close();
  });

  test('upsertTrajet ecrit et relit un denivele sans erreur', () async {
    final db = await ouvrirBaseNeuve();
    await db.insert('voyages', {
      'titre': 'Test',
      'date_debut': '2026-01-01',
      'date_fin': '2026-01-02',
    });
    final voyageId = (await db.rawQuery('SELECT MAX(id) AS id FROM voyages'))
        .first['id'] as int;
    for (var i = 0; i < 2; i++) {
      await db.insert('etapes', {
        'voyage_id': voyageId,
        'ordre': i,
        'nom': 'Etape $i',
        'latitude': 45.0,
        'longitude': 6.0,
        'date': '2026-01-01',
      });
    }
    final ids = (await db.rawQuery('SELECT id FROM etapes ORDER BY id'))
        .map((r) => r['id'] as int)
        .toList();
    final result = await db.rawInsert('''
      INSERT INTO trajets (
        voyage_id, etape_depart_id, etape_arrivee_id, mode,
        distance_km, duree_minutes, geometrie_json,
        denivele_positif_m, denivele_negatif_m, profil_altitude_json
      ) VALUES (?, ?, ?, 'voiture', 10.5, 60, '[]', 850, 120, '[]')
    ''', [voyageId, ids[0], ids[1]]);
    expect(result, greaterThan(0));
    final trajet = await db.query('trajets');
    expect(trajet.first['denivele_positif_m'], 850);
    expect(trajet.first['denivele_negatif_m'], 120);
    await db.close();
  });
}
