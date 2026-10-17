import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/voyage.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/document_etape.dart';
import '../models/parametres_planification.dart';
import '../models/waypoint.dart';

/// Version actuelle du schema de la base du planificateur de voyage.
/// Toute colonne ajoutee doit l'etre a la fois dans [_schemaTables]
/// (via la migration correspondante) et ici si la version est
/// incremente : l'invariant est verifie par
/// test/trip_planner_database_test.dart.
const int _kDbVersion = 8;

/// Colonnes attendues de chaque table du schema de la base du
/// planificateur de voyage, avec le type SQLite de creation (utilise
/// par la reparation ALTER TABLE de [_verifierSchema] ; les types
/// des CREATE TABLE d'installation restent la reference).
/// Sert de reference unique pour verifier/reparer les bases
/// existantes a l'ouverture : toute colonne ajoutee doit figurer ici
/// ET dans la migration qui l'introduit, sinon le test d'invariant
/// de schema echoue.
const Map<String, Map<String, String>> _schemaTables = {
  'voyages': {
    'id': 'INTEGER PRIMARY KEY AUTOINCREMENT',
    'titre': 'TEXT NOT NULL',
    'date_debut': 'TEXT NOT NULL',
    'date_fin': 'TEXT NOT NULL',
    'notes': 'TEXT',
  },
  'etapes': {
    'id': 'INTEGER PRIMARY KEY AUTOINCREMENT',
    'voyage_id': 'INTEGER NOT NULL',
    'ordre': 'INTEGER NOT NULL',
    'nom': 'TEXT NOT NULL',
    'latitude': 'REAL NOT NULL',
    'longitude': 'REAL NOT NULL',
    'date': 'TEXT NOT NULL',
    'type': "TEXT NOT NULL DEFAULT 'visite'",
    'notes': 'TEXT',
    'duree_visite_minutes': 'INTEGER',
    'heure_arrivee': 'TEXT',
    'date_depart': 'TEXT',
    'heure_depart': 'TEXT',
    'decalage_horaire_minutes': 'INTEGER',
    'parent_id': 'INTEGER',
  },
  'trajets': {
    'id': 'INTEGER PRIMARY KEY AUTOINCREMENT',
    'voyage_id': 'INTEGER NOT NULL',
    'etape_depart_id': 'INTEGER NOT NULL',
    'etape_arrivee_id': 'INTEGER NOT NULL',
    'mode': "TEXT NOT NULL DEFAULT 'voiture'",
    'distance_km': 'REAL NOT NULL',
    'duree_minutes': 'INTEGER NOT NULL',
    'geometrie_json': 'TEXT NOT NULL',
    'transporteur': 'TEXT',
    'lieu_depart': 'TEXT',
    'lieu_arrivee': 'TEXT',
    'heure_depart': 'TEXT',
    'heure_arrivee': 'TEXT',
    'notes': 'TEXT',
    'denivele_positif_m': 'REAL',
    'denivele_negatif_m': 'REAL',
    'profil_altitude_json': 'TEXT',
  },
  'documents': {
    'id': 'INTEGER PRIMARY KEY AUTOINCREMENT',
    'etape_id': 'INTEGER NOT NULL',
    'nom_original': 'TEXT NOT NULL',
    'chemin_fichier': 'TEXT NOT NULL',
    'type_mime': 'TEXT',
    'taille_octets': 'INTEGER NOT NULL DEFAULT 0',
    'date_ajout': 'TEXT NOT NULL',
  },
  'waypoints': {
    'id': 'INTEGER PRIMARY KEY AUTOINCREMENT',
    'voyage_id': 'INTEGER NOT NULL',
    'nom': 'TEXT NOT NULL',
    'latitude': 'REAL NOT NULL',
    'longitude': 'REAL NOT NULL',
    'source': "TEXT NOT NULL DEFAULT 'recommande'",
    'categorie': "TEXT NOT NULL DEFAULT ''",
    'notes': "TEXT NOT NULL DEFAULT ''",
    'osm_id': 'TEXT',
  },
  'parametres': {
    'cle': 'TEXT PRIMARY KEY',
    'valeur': 'TEXT NOT NULL',
  },
};

/// Couche d'acces a la base de donnees du module de planification de
/// voyage. Volontairement independante de [DatabaseHelper] (le carnet
/// de trek / livre illustre) : fichier SQLite separe
/// ('trip_planner.db'), aucune table partagee. Cela permet d'ajouter
/// ou de retirer ce module sans toucher au schema existant.
class TripPlannerDatabase {
  static final TripPlannerDatabase instance = TripPlannerDatabase._internal();
  static Database? _database;

  TripPlannerDatabase._internal();

  /// Reproduit l'initialisation complete (schema au complet) sur une
  /// base neuve, en ignorant le singleton. Utilise par les tests.
  Future<Database> ouvrirPourTest(String path) async {
    return openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: _verifierSchema,
    );
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbDir = (await getApplicationDocumentsDirectory()).path;
    final path = join(dbDir, 'trip_planner.db');

    return openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      // Verifie que toutes les colonnes attendues sont presentes,
      // quelle que soit la facon dont la base a ete creee
      // (installation neuve ou upgrade depuis une ancienne version).
      // Un bug de desynchronisation entre _onCreate et _onUpgrade
      // (colonnes de denivele manquantes sur les installations
      // neuves, v7) rendait chaque enregistrement de trajet impossible.
      onOpen: _verifierSchema,
    );
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
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
    if (oldVersion < 5) {
      await _createParametresTableIfMissing(db);
      await _addColumnIfMissing(db, 'trajets', 'denivele_positif_m', 'REAL');
      await _addColumnIfMissing(db, 'trajets', 'denivele_negatif_m', 'REAL');
      await _addColumnIfMissing(
        db,
        'trajets',
        'profil_altitude_json',
        'TEXT',
      );
    }
    if (oldVersion < 6) {
      await _addColumnIfMissing(
        db,
        'etapes',
        'decalage_horaire_minutes',
        'INTEGER',
      );
    }
    if (oldVersion < 7) {
      await _addColumnIfMissing(db, 'etapes', 'parent_id', 'INTEGER');
    }
    if (oldVersion < 8) {
      // Les deniveles etaient INTEGER ; SQLite etant faiblement type,
      // les valeurs existantes restent exploitables sans conversion.
      await _addColumnIfMissing(db, 'trajets', 'denivele_positif_m', 'REAL');
      await _addColumnIfMissing(db, 'trajets', 'denivele_negatif_m', 'REAL');
    }
  }

  /// Verifie que chaque table attendue possede toutes ses colonnes,
  /// et ajoute les colonnes manquantes (bases creees par une version
  /// anterieure desynchronisee). Contrairement a l'ancien correctif
  /// ponctuel limite aux colonnes de denivele, cette verification
  /// couvre l'ensemble du schema.
  Future<void> _verifierSchema(Database db) async {
    for (final entry in _schemaTables.entries) {
      final tables = await db.rawQuery(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
        ['table', entry.key],
      );
      if (tables.isEmpty) continue;
      final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final existing = columns.map((c) => c['name'] as String).toSet();
      for (final column in entry.value.entries) {
        if (!existing.contains(column.key)) {
          await db.execute(
            'ALTER TABLE ${entry.key} ADD COLUMN ${column.key} ${column.value}',
          );
        }
      }
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

  /// Table cle/valeur des parametres de planification (vitesses
  /// moyennes, preferences d'itineraire). Une ligne par cle, la valeur
  /// stockee en TEXT.
  Future<void> _createParametresTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parametres (
        cle TEXT PRIMARY KEY,
        valeur TEXT NOT NULL
      )
    ''');
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
        decalage_horaire_minutes INTEGER,
        parent_id INTEGER,
        FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE,
        FOREIGN KEY (parent_id) REFERENCES etapes (id) ON DELETE CASCADE
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
        denivele_positif_m REAL,
        denivele_negatif_m REAL,
        profil_altitude_json TEXT,
        FOREIGN KEY (voyage_id) REFERENCES voyages (id) ON DELETE CASCADE,
        FOREIGN KEY (etape_depart_id) REFERENCES etapes (id) ON DELETE CASCADE,
        FOREIGN KEY (etape_arrivee_id) REFERENCES etapes (id) ON DELETE CASCADE
      )
    ''');

    await _createDocumentsTableIfMissing(db);
    await _createWaypointsTableIfMissing(db);
    await _createParametresTableIfMissing(db);
  }

  // PARAMETRES

  /// Charge les parametres de planification ; les cles absentes
  /// prennent les valeurs par defaut de [ParametresPlanification].
  Future<ParametresPlanification> getParametres() async {
    final db = await database;
    final maps = await db.query('parametres');
    final map = <String, String?>{
      for (final m in maps) m['cle'] as String: m['valeur'] as String?,
    };
    return ParametresPlanification.fromMap(map);
  }

  /// Remplace l'ensemble des parametres par ceux donnes (ecriture
  /// cle/valeur, une ligne par entree).
  Future<void> saveParametres(ParametresPlanification p) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('parametres');
    for (final entry in p.toMap().entries) {
      batch.insert('parametres', {'cle': entry.key, 'valeur': entry.value});
    }
    await batch.commit();
  }

  // VOYAGES

  Future<int> insertVoyage(Voyage voyage) async {
    final db = await database;
    return _traceErreurs(
      'insertVoyage',
      () => db.insert('voyages', voyage.toMap()..remove('id')),
    );
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
    return _traceErreurs(
      'updateVoyage',
      () => db.update(
        'voyages',
        voyage.toMap(),
        where: 'id = ?',
        whereArgs: [voyage.id],
      ),
    );
  }

  Future<int> deleteVoyage(int id) async {
    final db = await database;
    return _traceErreurs('deleteVoyage', () async {
      final etapes = await getEtapesForVoyage(id);
      for (final etape in etapes) {
        if (etape.id != null) {
          await db.delete(
            'documents',
            where: 'etape_id = ?',
            whereArgs: [etape.id],
          );
        }
      }
      await db.delete('trajets', where: 'voyage_id = ?', whereArgs: [id]);
      await db.delete('etapes', where: 'voyage_id = ?', whereArgs: [id]);
      await db.delete('waypoints', where: 'voyage_id = ?', whereArgs: [id]);
      return db.delete('voyages', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ETAPES

  Future<int> insertEtape(Etape etape) async {
    final db = await database;
    return _traceErreurs(
      'insertEtape',
      () => db.insert('etapes', etape.toMap()..remove('id')),
    );
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
    return _traceErreurs(
      'updateEtape',
      () => db.update(
        'etapes',
        etape.toMap(),
        where: 'id = ?',
        whereArgs: [etape.id],
      ),
    );
  }

  Future<int> deleteEtape(int id) async {
    final db = await database;
    return _traceErreurs(
      'deleteEtape',
      () async {
        await db.delete('documents', where: 'etape_id = ?', whereArgs: [id]);
        await db.delete(
          'trajets',
          where: 'etape_depart_id = ? OR etape_arrivee_id = ?',
          whereArgs: [id, id],
        );
        return db.delete('etapes', where: 'id = ?', whereArgs: [id]);
      },
    );
  }

  // TRAJETS

  /// Enregistre (ou remplace) le trajet entre deux etapes consecutives.
  /// Un trajet existant pour la meme paire depart/arrivee est supprime
  /// avant insertion, pour eviter les doublons apres un recalcul.
  Future<int> upsertTrajet(Trajet trajet) async {
    final db = await database;
    return _traceErreurs('upsertTrajet', () async {
      await db.delete(
        'trajets',
        where: 'etape_depart_id = ? AND etape_arrivee_id = ?',
        whereArgs: [trajet.etapeDepartId, trajet.etapeArriveeId],
      );
      return db.insert('trajets', trajet.toMap()..remove('id'));
    });
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
    await _traceErreurs(
      'deleteTrajetsVoitureForVoyage',
      () => db.delete(
        'trajets',
        where: 'voyage_id = ? AND mode = ?',
        whereArgs: [voyageId, 'voiture'],
      ),
    );
  }

  Future<void> deleteTrajet(int id) async {
    final db = await database;
    await _traceErreurs(
      'deleteTrajet',
      () => db.delete('trajets', where: 'id = ?', whereArgs: [id]),
    );
  }

  Future<void> deleteTrajetsForVoyage(int voyageId) async {
    final db = await database;
    await _traceErreurs(
      'deleteTrajetsForVoyage',
      () => db.delete('trajets', where: 'voyage_id = ?', whereArgs: [voyageId]),
    );
  }

  // DOCUMENTS

  Future<int> insertDocument(DocumentEtape document) async {
    final db = await database;
    return _traceErreurs(
      'insertDocument',
      () => db.insert('documents', document.toMap()..remove('id')),
    );
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
    return _traceErreurs(
      'deleteDocument',
      () => db.delete('documents', where: 'id = ?', whereArgs: [id]),
    );
  }

  // WAYPOINTS

  Future<int> insertWaypoint(Waypoint waypoint) async {
    final db = await database;
    return _traceErreurs(
      'insertWaypoint',
      () => db.insert('waypoints', waypoint.toMap()..remove('id')),
    );
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
    return _traceErreurs(
      'updateWaypoint',
      () => db.update(
        'waypoints',
        waypoint.toMap(),
        where: 'id = ?',
        whereArgs: [waypoint.id],
      ),
    );
  }

  Future<int> deleteWaypoint(int id) async {
    final db = await database;
    return _traceErreurs(
      'deleteWaypoint',
      () => db.delete('waypoints', where: 'id = ?', whereArgs: [id]),
    );
  }

  /// Supprime les waypoints recommandes d'un voyage : utilise avant de
  /// recharger les suggestions, pour ne jamais toucher aux wayoints
  /// personnels de l'utilisateur.
  Future<void> deleteWaypointsRecommandesForVoyage(int voyageId) async {
    final db = await database;
    await _traceErreurs(
      'deleteWaypointsRecommandesForVoyage',
      () => db.delete(
        'waypoints',
        where: 'voyage_id = ? AND source = ?',
        whereArgs: [voyageId, 'recommande'],
      ),
    );
  }

  /// Encapsule une ecriture en base en traçant l'erreur avec le nom
  /// de l'operation avant de la propager : sans cela, une exception
  /// SQLite (colonne manquante, contrainte violee) est avalee par le
  /// contexte appelant et l'utilisateur ne voit qu'un chargement
  /// sans fin.
  Future<T> _traceErreurs<T>(
    String operation,
    Future<T> Function() ecriture,
  ) async {
    try {
      return await ecriture();
    } catch (e, stack) {
      debugPrint('Erreur base de donnees ($operation) : $e');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      rethrow;
    }
  }
}
