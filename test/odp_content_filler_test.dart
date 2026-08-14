import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:les_baroudeurs/models/trek.dart';
import 'package:les_baroudeurs/models/jour_trek.dart';
import 'package:les_baroudeurs/services/odp/odp_content_filler.dart';

/// Tests du remplissage du template ODP.
///
/// Ces tests chargent le template `assets/templates/template_baroudeurstudio.odp`
/// directement depuis le systeme de fichiers (le dossier assets est versionne
/// et donc accessible pendant les tests), puis verifient que les placeholders
/// sont correctement remplaces et que la structure de l'archive reste valide.
void main() {
  late String templateContentXml;
  late Archive templateArchive;

  setUpAll(() {
    // Les donnees de locale fr sont necessaires pour DateFormat('...', 'fr').
    initializeDateFormatting('fr_FR', null);

    // Le template ODP est un ZIP; on le lit depuis le systeme de fichiers.
    final templatePath =
        '${Directory.current.path}/assets/templates/template_baroudeurstudio.odp';
    final bytes = File(templatePath).readAsBytesSync();
    templateArchive = ZipDecoder().decodeBytes(bytes);
    final contentFile = templateArchive.findFile('content.xml');
    expect(contentFile, isNotNull,
        reason: 'Le template doit contenir un content.xml');
    templateContentXml =
        utf8.decode(contentFile!.content as List<int>, allowMalformed: true);
  });

  group('Template ODP', () {
    test('contient les placeholders attendus', () {
      expect(templateContentXml, contains(OdpContentFiller.trekTitlePh));
      expect(templateContentXml, contains(OdpContentFiller.jourDepartPh));
      expect(templateContentXml, contains(OdpContentFiller.jourResumePh));
      expect(templateContentXml, contains(OdpContentFiller.jourImagePh));
    });

    test('contient au moins 3 pages (couverture, jour, fin)', () {
      final pages = OdpContentFiller.extractTopLevelPages(templateContentXml);
      expect(pages.length, greaterThanOrEqualTo(3));
    });
  });

  group('OdpContentFiller.fill', () {
    test('remplace tous les placeholders pour un trek avec un jour', () {
      final trek = Trek(
        id: 1,
        titre: 'Mon Trek & Aventure',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'Chamonix',
        pays: 'France',
      );
      final jours = [
        JourTrek(
          id: 1,
          trekId: 1,
          numeroJour: 1,
          date: '2024-07-01',
          lieuDepart: 'Chamonix',
          lieuArrivee: 'Argentiere',
          resume: 'Belle journee en montagne',
        ),
      ];
      final imagePaths = <String?>['Pictures/jour_0.jpg'];

      final result =
          OdpContentFiller.fill(templateContentXml, trek, jours, imagePaths);

      // Aucun placeholder ne doit rester.
      expect(result, isNot(contains(OdpContentFiller.trekTitlePh)));
      expect(result, isNot(contains(OdpContentFiller.jourDepartPh)));
      expect(result, isNot(contains(OdpContentFiller.jourResumePh)));
      expect(result, isNot(contains(OdpContentFiller.jourImagePh)));
      // Le titre echappe doit apparaitre.
      expect(result, contains('Mon Trek &amp; Aventure'));
      // L'image du jour doit etre referencee.
      expect(result, contains('Pictures/jour_0.jpg'));
    });

    test('duplique la page jour pour chaque JourTrek', () {
      final trek = Trek(
        id: 1,
        titre: 'Trek 3 jours',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-03',
        region: 'Alpes',
        pays: 'France',
      );
      final jours = [
        JourTrek(
          id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
          lieuDepart: 'A', lieuArrivee: 'B', resume: 'Jour 1',
        ),
        JourTrek(
          id: 2, trekId: 1, numeroJour: 2, date: '2024-07-02',
          lieuDepart: 'B', lieuArrivee: 'C', resume: 'Jour 2',
        ),
        JourTrek(
          id: 3, trekId: 1, numeroJour: 3, date: '2024-07-03',
          lieuDepart: 'C', lieuArrivee: 'D', resume: 'Jour 3',
        ),
      ];
      final imagePaths = <String?>[
        'Pictures/jour_0.jpg',
        null,
        'Pictures/jour_2.jpg',
      ];

      final result =
          OdpContentFiller.fill(templateContentXml, trek, jours, imagePaths);

      // 1 couverture + 3 jours + 1 fin = 5 pages de premier niveau.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 5);
      // Les resumes doivent etre presents.
      expect(result, contains('Jour 1'));
      expect(result, contains('Jour 2'));
      expect(result, contains('Jour 3'));
      // Les noms de pages doivent etre uniques.
      expect(result, contains('jour_1'));
      expect(result, contains('jour_2'));
      expect(result, contains('jour_3'));
      // Les images des jours 0 et 2, pas la 1.
      expect(result, contains('Pictures/jour_0.jpg'));
      expect(result, isNot(contains('Pictures/jour_1.jpg')));
      expect(result, contains('Pictures/jour_2.jpg'));
    });

    test('echappe les caracteres speciaux XML', () {
      final trek = Trek(
        id: 1,
        titre: 'A < B & C > D "E" \'F\'',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'Test',
        pays: 'FR',
      );
      final jours = <JourTrek>[];
      final imagePaths = <String?>[];

      final result =
          OdpContentFiller.fill(templateContentXml, trek, jours, imagePaths);

      expect(result, contains('A &lt; B &amp; C &gt; D &quot;E&quot; &apos;F&apos;'));
    });

    test('garde une page jour vide si aucun jour', () {
      final trek = Trek(
        id: 1,
        titre: 'Trek vide',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'Nulle part',
        pays: 'FR',
      );
      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        <JourTrek>[],
        <String?>[],
      );
      // Couverture + page jour vide + page de fin = 3 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 3);
      expect(result, isNot(contains('{{')));
    });
  });

  group('Archive ODP generee', () {
    test('le mimetype est bien present et non compresse dans le template', () {
      final mt = templateArchive.findFile('mimetype');
      expect(mt, isNotNull);
      expect(mt!.compress, isFalse,
          reason: 'mimetype doit etre stocke non compresse (conformite ODP)');
      final content = utf8.decode(mt.content as List<int>);
      expect(content, 'application/vnd.oasis.opendocument.presentation');
    });

    test('le template preserve styles.xml, settings.xml et meta.xml', () {
      expect(templateArchive.findFile('styles.xml'), isNotNull);
      expect(templateArchive.findFile('settings.xml'), isNotNull);
      expect(templateArchive.findFile('meta.xml'), isNotNull);
      expect(templateArchive.findFile('META-INF/manifest.xml'), isNotNull);
    });
  });

  /// Ce test reproduit le flux complet du OdpExportService (sans l'IO des
  /// images reelles) pour verifier que l'archive ODP generee est conforme:
  ///  - mimetype en 1ere position et non compresse,
  ///  - toutes les images referencees dans content.xml sont presentes dans
  ///    l'archive ET declarees dans META-INF/manifest.xml.
  ///
  /// C'est le test de regression pour le bug de corruption ODP cause par
  /// l'utilisation de Archive.removeFile() (bug du package archive 3.x qui
  /// corrompt les _fileMap apres suppression).
  group('Conformite ODP (flux complet)', () {
    test('l\'archive generee est conforme: mimetype + manifest + images', () {
      final jourImagePaths = <String?>['Pictures/jour_0.jpg'];

      // Lire IMMEDIATEMENT le contenu de tous les fichiers (comme le service).
      final fileContents = <String, Uint8List>{};
      for (final file in templateArchive) {
        if (file.isFile) {
          final data = file.content as List<int>;
          fileContents[file.name] = Uint8List.fromList(data);
        }
      }

      // Remplir content.xml.
      final trek = Trek(
        id: 1,
        titre: 'Trek Test',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'Alpes',
        pays: 'France',
      );
      final jours = [
        JourTrek(
          id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
          lieuDepart: 'A', lieuArrivee: 'B', resume: 'J1',
        ),
      ];
      final contentXml = utf8.decode(fileContents['content.xml']!, allowMalformed: true);
      final filledContent =
          OdpContentFiller.fill(contentXml, trek, jours, jourImagePaths);
      fileContents['content.xml'] = Uint8List.fromList(utf8.encode(filledContent));

      // Ajouter l'image (dummy: reutilise le PNG du template).
      fileContents['Pictures/jour_0.jpg'] =
          fileContents['Pictures/1000000100000499000002A0DBB432AD.png']!;

      // Mettre a jour le manifest.
      final manifestXml = utf8.decode(
        fileContents['META-INF/manifest.xml']!, allowMalformed: true);
      final toAdd = <String>[];
      for (final path in jourImagePaths) {
        if (path == null || path.isEmpty) continue;
        if (!manifestXml.contains('manifest:full-path="$path"')) {
          toAdd.add(
            '  <manifest:file-entry manifest:full-path="$path" '
            'manifest:media-type="image/jpeg"/>',
          );
        }
      }
      var updatedManifest = manifestXml;
      if (toAdd.isNotEmpty) {
        final insertBefore = manifestXml.indexOf('</manifest:manifest>');
        updatedManifest = '${manifestXml.substring(0, insertBefore)}'
            '${toAdd.join('\n')}\n'
            '${manifestXml.substring(insertBefore)}';
      }
      fileContents['META-INF/manifest.xml'] =
          Uint8List.fromList(utf8.encode(updatedManifest));

      // Re-encoder l'archive (comme le service).
      final newArchive = Archive();
      final mtData = fileContents['mimetype']!;
      final mt = ArchiveFile('mimetype', mtData.length, mtData);
      mt.compress = false;
      newArchive.addFile(mt);
      fileContents.remove('mimetype');
      for (final file in templateArchive) {
        if (file.name == 'mimetype') continue;
        if (!file.isFile) {
          newArchive.addFile(file);
          continue;
        }
        final data = fileContents[file.name];
        if (data == null) continue;
        final copy = ArchiveFile(file.name, data.length, data);
        copy.compress = true;
        newArchive.addFile(copy);
        fileContents.remove(file.name);
      }
      for (final entry in fileContents.entries) {
        if (entry.key.startsWith('Pictures/jour_')) {
          final copy = ArchiveFile(entry.key, entry.value.length, entry.value);
          copy.compress = true;
          newArchive.addFile(copy);
        }
      }

      final zipData = ZipEncoder().encode(newArchive)!;

      // Decoder pour verifier la conformite.
      final outArchive = ZipDecoder().decodeBytes(zipData);

      // 1. mimetype en 1ere position, non compresse.
      expect(outArchive.first.name, 'mimetype');
      expect(outArchive.first.compress, isFalse);
      expect(
        utf8.decode(outArchive.first.content as List<int>),
        'application/vnd.oasis.opendocument.presentation',
      );

      // 2. L'image jour_0.jpg est presente dans l'archive.
      final imgFile = outArchive.findFile('Pictures/jour_0.jpg');
      expect(imgFile, isNotNull,
          reason: 'L\'image du jour doit etre dans l\'archive');

      // 3. L'image jour_0.jpg est declaree dans le manifest.
      final outManifest = utf8.decode(
        outArchive.findFile('META-INF/manifest.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(
        outManifest,
        contains('manifest:full-path="Pictures/jour_0.jpg"'),
        reason: 'Chaque fichier de l\'archive doit etre declare dans le manifest',
      );

      // 4. content.xml est bien forme (pas de placeholders restants).
      final outContent = utf8.decode(
        outArchive.findFile('content.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(outContent, isNot(contains('{{')));
      expect(outContent, contains('Pictures/jour_0.jpg'));
    });
  });
}
