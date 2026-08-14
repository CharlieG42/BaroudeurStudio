import 'dart:convert';
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
}
