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
/// directement depuis le système de fichiers (le dossier assets est versionné
/// et donc accessible pendant les tests), puis vérifient que les placeholders
/// sont correctement remplacés et que la structure de l'archive reste valide.
void main() {
  late String templateContentXml;
  late Archive templateArchive;

  setUpAll(() {
    initializeDateFormatting('fr_FR', null);

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

      expect(result, isNot(contains(OdpContentFiller.trekTitlePh)));
      expect(result, isNot(contains(OdpContentFiller.jourDepartPh)));
      expect(result, isNot(contains(OdpContentFiller.jourResumePh)));
      expect(result, isNot(contains(OdpContentFiller.jourImagePh)));
      expect(result, contains('Mon Trek &amp; Aventure'));
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

      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 5);
      expect(result, contains('Jour 1'));
      expect(result, contains('Jour 2'));
      expect(result, contains('Jour 3'));
      expect(result, contains('jour_1'));
      expect(result, contains('jour_2'));
      expect(result, contains('jour_3'));
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
      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        <JourTrek>[],
        <String?>[],
      );

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
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 3);
      expect(result, isNot(contains('{{')));
    });
  });

  // ===========================================================================
  // TESTS: PRESERVATION DES SAUTS DE LIGNE
  // ===========================================================================
  group('Preservation des sauts de ligne', () {
    test('convertit les sauts de ligne en <text:line-break/>', () {
      final trek = Trek(
        id: 1,
        titre: 'Trek',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'R',
        pays: 'P',
      );
      final jours = [
        JourTrek(
          id: 1,
          trekId: 1,
          numeroJour: 1,
          date: '2024-07-01',
          resume: 'Ligne 1\nLigne 2\nLigne 3',
        ),
      ];

      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        jours,
        <String?>[null],
      );

      expect(result, contains('Ligne 1<text:line-break/>Ligne 2'));
      expect(result, contains('Ligne 2<text:line-break/>Ligne 3'));
      expect(result, isNot(contains('Ligne 1\nLigne 2')));
    });

    test('gere les sauts de ligne Windows (\\r\\n)', () {
      final trek = Trek(
        id: 1,
        titre: 'Trek',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'R',
        pays: 'P',
      );
      final jours = [
        JourTrek(
          id: 1,
          trekId: 1,
          numeroJour: 1,
          date: '2024-07-01',
          resume: 'A\r\nB\r\nC',
        ),
      ];

      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        jours,
        <String?>[null],
      );

      expect(result, contains('A<text:line-break/>B'));
      expect(result, contains('B<text:line-break/>C'));
      expect(result, isNot(contains('\r')));
    });

    test('preserve les sauts de ligne dans le titre du trek', () {
      final trek = Trek(
        id: 1,
        titre: 'Titre\nSous-titre',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'R',
        pays: 'P',
      );

      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        <JourTrek>[],
        <String?>[],
      );

      expect(result, contains('Titre<text:line-break/>Sous-titre'));
    });

    test('echappe les caracteres speciaux ET preserve les sauts de ligne', () {
      final trek = Trek(
        id: 1,
        titre: 'A & B\n<C>',
        dateDebut: '2024-07-01',
        dateFin: '2024-07-01',
        region: 'R',
        pays: 'P',
      );

      final result = OdpContentFiller.fill(
        templateContentXml,
        trek,
        <JourTrek>[],
        <String?>[],
      );

      expect(result, contains('A &amp; B<text:line-break/>&lt;C&gt;'));
    });
  });

  // ===========================================================================
  // TESTS: CALCUL DES DIMENSIONS D'IMAGE
  // ===========================================================================
  group('computeImageDimensions', () {
    test('image paysage: largeur >= minWidthCm', () {
      // Image 1600x900 (paysage, ratio ~1.78)
      final dims = ImageDimensions(1600, 900);
      final result =
          OdpContentFiller.computeImageDimensions(dims, OdpImageSettings.defaults);

      expect(result.widthCm, greaterThanOrEqualTo(13.0));
      final ratio = result.widthCm / result.heightCm;
      expect(ratio, closeTo(1600 / 900, 0.01));
    });

    test('image portrait: hauteur >= minHeightCm', () {
      // Image 900x1600 (portrait, ratio ~0.56)
      final dims = ImageDimensions(900, 1600);
      final result =
          OdpContentFiller.computeImageDimensions(dims, OdpImageSettings.defaults);

      expect(result.heightCm, greaterThanOrEqualTo(8.0));
      final ratio = result.widthCm / result.heightCm;
      expect(ratio, closeTo(900 / 1600, 0.01));
    });

    test('image carree: satisfait les deux minimums', () {
      final dims = ImageDimensions(1000, 1000);
      final result =
          OdpContentFiller.computeImageDimensions(dims, OdpImageSettings.defaults);

      expect(result.heightCm, greaterThanOrEqualTo(8.0));
      expect(result.widthCm, greaterThanOrEqualTo(8.0));
      expect(result.widthCm, closeTo(result.heightCm, 0.01));
    });

    test('respecte les maximums', () {
      final dims = ImageDimensions(8000, 1000);
      final result =
          OdpContentFiller.computeImageDimensions(dims, OdpImageSettings.defaults);

      expect(result.widthCm, lessThanOrEqualTo(18.0));
    });

    test('retourne les minimums par defaut si dims est null', () {
      final result = OdpContentFiller.computeImageDimensions(
          null, OdpImageSettings.defaults);

      expect(result.widthCm, 13.0);
      expect(result.heightCm, 8.0);
    });

    test('parametres personnalises sont respectes', () {
      final settings = OdpImageSettings(minHeightCm: 10.0, minWidthCm: 15.0);
      final dims = ImageDimensions(900, 1600); // portrait
      final result = OdpContentFiller.computeImageDimensions(dims, settings);

      expect(result.heightCm, greaterThanOrEqualTo(10.0));
    });
  });

  // ===========================================================================
  // TESTS: CONFORMITE ODP (FLUX COMPLET)
  // ===========================================================================
  group('Conformite ODP (flux complet)', () {
    test('l\'archive generee est conforme: mimetype + manifest + images', () {
      final jourImagePaths = <String?>['Pictures/jour_0.jpg'];
      final jourImageDims = <ImageDimensions?>[ImageDimensions(1200, 900)];

      final fileContents = <String, Uint8List>{};
      for (final file in templateArchive) {
        if (file.isFile) {
          final data = file.content as List<int>;
          fileContents[file.name] = Uint8List.fromList(data);
        }
      }

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
      final contentXml =
          utf8.decode(fileContents['content.xml']!, allowMalformed: true);
      final filledContent = OdpContentFiller.fill(
        contentXml,
        trek,
        jours,
        jourImagePaths,
        jourImageDimensions: jourImageDims,
      );
      fileContents['content.xml'] =
          Uint8List.fromList(utf8.encode(filledContent));

      fileContents['Pictures/jour_0.jpg'] =
          fileContents['Pictures/1000000100000499000002A0DBB432AD.png']!;

      final manifestXml = utf8.decode(
          fileContents['META-INF/manifest.xml']!, allowMalformed: true);
      final toAdd = <String>[];
      for (final path in jourImagePaths) {
        if (path == null || path.isEmpty) continue;
        if (!manifestXml.contains('manifest:full-path="$path"')) {
          toAdd.add('  <manifest:file-entry manifest:full-path="$path" '
              'manifest:media-type="image/jpeg"/>');
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
          final copy =
              ArchiveFile(entry.key, entry.value.length, entry.value);
          copy.compress = true;
          newArchive.addFile(copy);
        }
      }

      final zipData = ZipEncoder().encode(newArchive)!;
      final outArchive = ZipDecoder().decodeBytes(zipData);

      expect(outArchive.first.name, 'mimetype');
      expect(outArchive.first.compress, isFalse);
      expect(
        utf8.decode(outArchive.first.content as List<int>),
        'application/vnd.oasis.opendocument.presentation',
      );
      expect(outArchive.findFile('Pictures/jour_0.jpg'), isNotNull);

      final outManifest = utf8.decode(
        outArchive.findFile('META-INF/manifest.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(outManifest, contains('manifest:full-path="Pictures/jour_0.jpg"'));

      final outContent = utf8.decode(
        outArchive.findFile('content.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(outContent, isNot(contains('{{')));
      expect(outContent, contains('Pictures/jour_0.jpg'));
      expect(outContent, contains('svg:width='));
      expect(outContent, contains('svg:height='));
    });
  });

  group('Archive ODP generee', () {
    test('le mimetype est bien present et non compresse dans le template', () {
      final mt = templateArchive.findFile('mimetype');
      expect(mt, isNotNull);
      expect(mt!.compress, isFalse);
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
}
