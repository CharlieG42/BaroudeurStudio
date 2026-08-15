import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:les_baroudeurs/models/trek.dart';
import 'package:les_baroudeurs/models/jour_trek.dart';
import 'package:les_baroudeurs/services/odp/odp_content_filler.dart';

/// Tests du remplissage du template ODP avec chapitrage.
///
/// Chaque jour devient un chapitre: une page de titre (date + trajet) suivie
/// d'une page par entrée média (image + texte lié).
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

  // ===========================================================================
  // TESTS: CHAPITRAGE
  // ===========================================================================
  group('Chapitrage', () {
    test('genere couverture + page titre + page image + fin pour 1 jour 1 photo', () {
      final trek = Trek(
        id: 1, titre: 'Trek Test',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'Alpes', pays: 'France',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B', resume: 'Resume du jour',
          ),
          entries: [
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_0.png',
              dimensions: ImageDimensions(1600, 900),
              text: 'Legende de la photo',
            ),
          ],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      // Aucun placeholder ne doit rester.
      expect(result, isNot(contains('{{')));

      // Structure: couverture + préambule + titre chapitre + page image + fin = 5 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 5);

      // Le titre du trek doit apparaitre.
      expect(result, contains('Trek Test'));
      // La page de titre du chapitre doit contenir "Jour 1".
      expect(result, contains('Jour 1'));
      // L'image doit etre referencee.
      expect(result, contains('Pictures/jour_0_img_0.png'));
      // La legende doit etre presente.
      expect(result, contains('Legende de la photo'));
    });

    test('genere plusieurs pages image pour un jour avec plusieurs photos', () {
      final trek = Trek(
        id: 1, titre: 'Trek Multi',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B',
          ),
          entries: [
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_0.png',
              dimensions: ImageDimensions(1600, 900),
              text: 'Legende 1',
            ),
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_1.png',
              dimensions: ImageDimensions(900, 1600),
              text: 'Legende 2',
            ),
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_2.png',
              dimensions: ImageDimensions(1200, 1200),
              text: 'Legende 3',
            ),
          ],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      // couverture + préambule + titre chapitre + 3 pages image + fin = 7 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 7);

      // Chaque image doit etre referencee.
      expect(result, contains('Pictures/jour_0_img_0.png'));
      expect(result, contains('Pictures/jour_0_img_1.png'));
      expect(result, contains('Pictures/jour_0_img_2.png'));

      // Chaque legende doit etre presente.
      expect(result, contains('Legende 1'));
      expect(result, contains('Legende 2'));
      expect(result, contains('Legende 3'));

      // Les pages doivent avoir des noms uniques.
      expect(result, contains('jour_1_img_1'));
      expect(result, contains('jour_1_img_2'));
      expect(result, contains('jour_1_img_3'));
    });

    test('genere une page texte seule si aucune photo', () {
      final trek = Trek(
        id: 1, titre: 'Trek Texte',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B',
            resume: 'Resume sans photo',
          ),
          entries: [
            MediaEntry(text: 'Resume sans photo'),
          ],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      // couverture + préambule + titre + 1 page texte + fin = 5 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 5);
      expect(result, contains('Resume sans photo'));
      expect(result, isNot(contains('Pictures/jour_')));
    });

    test('genere une page avec resume si aucune entree media', () {
      final trek = Trek(
        id: 1, titre: 'Trek Vide',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B',
            resume: 'Resume du jour vide',
          ),
          entries: [],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      // couverture + préambule + titre + 1 page resume + fin = 5 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 5);
      expect(result, contains('Resume du jour vide'));
    });

    test('genere plusieurs chapitres pour plusieurs jours', () {
      final trek = Trek(
        id: 1, titre: 'Trek 2 Jours',
        dateDebut: '2024-07-01', dateFin: '2024-07-02',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B',
          ),
          entries: [
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_0.png',
              dimensions: ImageDimensions(1600, 900),
              text: 'Photo jour 1',
            ),
          ],
        ),
        JourChapterData(
          jour: JourTrek(
            id: 2, trekId: 1, numeroJour: 2, date: '2024-07-02',
            lieuDepart: 'B', lieuArrivee: 'C',
          ),
          entries: [
            MediaEntry(
              imagePath: 'Pictures/jour_1_img_0.png',
              dimensions: ImageDimensions(1600, 900),
              text: 'Photo jour 2',
            ),
            MediaEntry(
              imagePath: 'Pictures/jour_1_img_1.png',
              dimensions: ImageDimensions(1200, 900),
              text: 'Photo 2 jour 2',
            ),
          ],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      // couverture + préambule + chap1(titre+1img) + chap2(titre+2img) + fin = 8 pages.
      final pages = OdpContentFiller.extractTopLevelPages(result);
      expect(pages.length, 8);

      // Les deux chapitres doivent etre presents.
      expect(result, contains('chapitre_1'));
      expect(result, contains('chapitre_2'));
      expect(result, contains('Jour 1'));
      expect(result, contains('Jour 2'));
    });
  });

  // ===========================================================================
  // TESTS: PRESERVATION DES SAUTS DE LIGNE
  // ===========================================================================
  group('Preservation des sauts de ligne', () {
    test('convertit les sauts de ligne en <text:line-break/>', () {
      final trek = Trek(
        id: 1, titre: 'Trek',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            resume: 'Ligne 1\nLigne 2\nLigne 3',
          ),
          entries: [MediaEntry(text: 'Ligne 1\nLigne 2\nLigne 3')],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      expect(result, contains('Ligne 1<text:line-break/>Ligne 2'));
      expect(result, contains('Ligne 2<text:line-break/>Ligne 3'));
      expect(result, isNot(contains('Ligne 1\nLigne 2')));
    });

    test('gere les sauts de ligne Windows (\\r\\n)', () {
      final trek = Trek(
        id: 1, titre: 'Trek',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            resume: 'A\r\nB\r\nC',
          ),
          entries: [MediaEntry(text: 'A\r\nB\r\nC')],
        ),
      ];

      final result = OdpContentFiller.fill(templateContentXml, trek, chapters);

      expect(result, contains('A<text:line-break/>B'));
      expect(result, contains('B<text:line-break/>C'));
      expect(result, isNot(contains('\r')));
    });

    test('preserve les sauts de ligne dans le titre du trek', () {
      final trek = Trek(
        id: 1, titre: 'Titre\nSous-titre',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );

      final result = OdpContentFiller.fill(
        templateContentXml, trek, <JourChapterData>[],
      );

      expect(result, contains('Titre<text:line-break/>Sous-titre'));
    });

    test('echappe les caracteres speciaux ET preserve les sauts de ligne', () {
      final trek = Trek(
        id: 1, titre: 'A & B\n<C>',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'R', pays: 'P',
      );

      final result = OdpContentFiller.fill(
        templateContentXml, trek, <JourChapterData>[],
      );

      expect(result, contains('A &amp; B<text:line-break/>&lt;C&gt;'));
    });
  });

  // ===========================================================================
  // TESTS: CALCUL DES DIMENSIONS D'IMAGE
  // ===========================================================================
  group('computeImageDimensions', () {
    test('image paysage: largeur >= minWidthCm', () {
      final dims = ImageDimensions(1600, 900);
      final result =
          OdpContentFiller.computeImageDimensions(dims, OdpImageSettings.defaults);

      expect(result.widthCm, greaterThanOrEqualTo(13.0));
      final ratio = result.widthCm / result.heightCm;
      expect(ratio, closeTo(1600 / 900, 0.01));
    });

    test('image portrait: hauteur >= minHeightCm', () {
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
      final dims = ImageDimensions(900, 1600);
      final result = OdpContentFiller.computeImageDimensions(dims, settings);

      expect(result.heightCm, greaterThanOrEqualTo(10.0));
    });
  });

  // ===========================================================================
  // TESTS: CONFORMITE ODP (FLUX COMPLET)
  // ===========================================================================
  group('Conformite ODP (flux complet)', () {
    test('l\'archive generee est conforme: mimetype + manifest + images', () {
      final chapters = [
        JourChapterData(
          jour: JourTrek(
            id: 1, trekId: 1, numeroJour: 1, date: '2024-07-01',
            lieuDepart: 'A', lieuArrivee: 'B', resume: 'J1',
          ),
          entries: [
            MediaEntry(
              imagePath: 'Pictures/jour_0_img_0.png',
              dimensions: ImageDimensions(1200, 900),
              text: 'Legende',
            ),
          ],
        ),
      ];

      final fileContents = <String, Uint8List>{};
      for (final file in templateArchive) {
        if (file.isFile) {
          fileContents[file.name] = Uint8List.fromList(file.content as List<int>);
        }
      }

      final trek = Trek(
        id: 1, titre: 'Trek Test',
        dateDebut: '2024-07-01', dateFin: '2024-07-01',
        region: 'Alpes', pays: 'France',
      );
      final contentXml =
          utf8.decode(fileContents['content.xml']!, allowMalformed: true);
      final filledContent = OdpContentFiller.fill(
        contentXml, trek, chapters,
      );
      fileContents['content.xml'] =
          Uint8List.fromList(utf8.encode(filledContent));

      fileContents['Pictures/jour_0_img_0.png'] =
          fileContents['Pictures/1000000100000499000002A0DBB432AD.png']!;

      final manifestXml = utf8.decode(
          fileContents['META-INF/manifest.xml']!, allowMalformed: true);
      final insertBefore = manifestXml.indexOf('</manifest:manifest>');
      final updatedManifest = '${manifestXml.substring(0, insertBefore)}'
          '  <manifest:file-entry manifest:full-path="Pictures/jour_0_img_0.png" manifest:media-type="image/png"/>\n'
          '${manifestXml.substring(insertBefore)}';
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
      expect(outArchive.findFile('Pictures/jour_0_img_0.png'), isNotNull);

      final outManifest = utf8.decode(
        outArchive.findFile('META-INF/manifest.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(outManifest,
          contains('manifest:full-path="Pictures/jour_0_img_0.png"'));

      final outContent = utf8.decode(
        outArchive.findFile('content.xml')!.content as List<int>,
        allowMalformed: true,
      );
      expect(outContent, isNot(contains('{{')));
      expect(outContent, contains('Pictures/jour_0_img_0.png'));
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
