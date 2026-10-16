import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;

import 'drive_connection_service.dart';

/// Categorie de sauvegarde Drive : un sous-dossier par module, car les
/// trois modules partagent l'extension .bwzt mais pas le contenu.
enum CategorieBackup { treks, voyages, preparation }

extension CategorieBackupExt on CategorieBackup {
  String get nomDossier {
    switch (this) {
      case CategorieBackup.treks:
        return 'treks';
      case CategorieBackup.voyages:
        return 'voyages';
      case CategorieBackup.preparation:
        return 'preparation';
    }
  }
}

/// Resultat d'une sauvegarde Drive.
class ResultatBackup {
  final bool ok;
  final String? nomFichier;
  final String? erreur;

  const ResultatBackup({required this.ok, this.nomFichier, this.erreur});
}

/// Service de sauvegarde Google Drive : envoie les archives .bwzt dans
/// le dossier `BaroudeurStudio/<categorie>/` du compte connecte.
///
/// Strategie : une seule version courante par objet. Le fichier Drive
/// est nomme `<prefixe>_<id>.bwzt` ; s'il existe deja, son contenu est
/// remplace (files.update) plutot que de creer un doublon horodate.
class DriveBackupService {
  static final DriveBackupService _instance = DriveBackupService._internal();
  factory DriveBackupService() => _instance;
  DriveBackupService._internal();

  static const String _dossierRacine = 'BaroudeurStudio';
  static const String _mimeTypeBwzt = 'application/zip';
  static const String _mimeTypeDossier =
      'application/vnd.google-apps.folder';

  final DriveConnectionService _connexion = DriveConnectionService();

  bool _enCours = false;

  /// Vrai si une sauvegarde est deja en cours (anti-reentrance pour le
  /// trigger opportuniste).
  bool get enCours => _enCours;

  /// Sauvegarde un fichier .bwzt genere par l'un des services d'export.
  ///
  /// [id] identifie l'objet sauvegarde (id du trek, du voyage, ou
  /// 'catalogue' pour la preparation) : il sert de cle de deduplication.
  Future<ResultatBackup> sauvegarder(
    File bwzt, {
    required CategorieBackup categorie,
    required String id,
  }) async {
    _enCours = true;
    try {
      final api = await _connexion.clientDrive();
      final dossierRacine = await _assurerDossier(api, _dossierRacine, null);
      final dossierCategorie =
          await _assurerDossier(api, categorie.nomDossier, dossierRacine.id);

      final nomFichier = '${categorie.nomDossier}_$id.bwzt';
      final contenu = drive.File()
        ..name = nomFichier
        ..mimeType = _mimeTypeBwzt;

      final existant = await _trouverFichier(api, nomFichier, dossierCategorie.id);
      final media = drive.Media(File(bwzt.path).openRead(), await bwzt.length());

      if (existant != null) {
        await api.files.update(contenu, existant.id!, uploadMedia: media);
      } else {
        contenu.parents = [dossierCategorie.id!];
        await api.files.create(contenu, uploadMedia: media);
      }
      return ResultatBackup(ok: true, nomFichier: nomFichier);
    } on drive.ApiRequestError catch (e) {
      return ResultatBackup(
          ok: false, erreur: 'Erreur Drive API : $e');
    } catch (e) {
      return ResultatBackup(ok: false, erreur: e.toString());
    } finally {
      _enCours = false;
    }
  }

  /// Trouve ou cree un dossier Drive par son nom dans un parent.
  Future<drive.File> _assurerDossier(
      drive.DriveApi api, String nom, String? parentId) async {
    final existant = await _trouverFichier(api, nom, parentId);
    if (existant != null) {
      return existant;
    }
    final dossier = drive.File()
      ..name = nom
      ..mimeType = _mimeTypeDossier
      ..parents = parentId != null ? [parentId] : null;
    return api.files.create(dossier);
  }

  Future<drive.File?> _trouverFichier(
      drive.DriveApi api, String nom, String? parentId) async {
    final clauseParent =
        parentId != null ? "'$parentId' in parents and " : '';
    final liste = await api.files.list(
        q: "${clauseParent}name = '$nom' and trashed = false",
        $fields: 'files(id,name,mimeType)',
        pageSize: 1);
    return liste.files?.isEmpty == true ? null : liste.files!.first;
  }
}
