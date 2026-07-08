import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../models/trek.dart';
import '../../models/jour_trek.dart';
import '../../db/database_helper.dart';
import '../utils/filename_utils.dart';
import 'pdf_styles.dart';

/// Service d'export PDF pour les treks
/// Uniquement pour l'export texte (sans images pour éviter les problèmes de mémoire)
class PdfExportService {
  /// Génère un PDF avec le texte uniquement (pas d'images)
  Future<File> exportTrekToPdfTextOnly(Trek trek) async {
    final jours = await DatabaseHelper.instance.getJoursForTrek(trek.id!);
    
    final pdf = pw.Document();

    _addCoverPage(pdf, trek);
    _addTitlePage(pdf, trek);
    
    for (final jour in jours) {
      _addJourPageTextOnly(pdf, trek, jour);
    }

    _addEndPage(pdf, trek);

    final directory = await getApplicationDocumentsDirectory();
    final filePath = directory.path + '/' + FilenameUtils.generateExportFilename(trek.titre, 'pdf');
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// Imprime le PDF
  Future<void> printTrekPdf(Trek trek) async {
    final pdfFile = await exportTrekToPdfTextOnly(trek);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfFile.readAsBytesSync(),
    );
  }

  void _addCoverPage(pw.Document pdf, Trek trek) {
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.SizedBox(height: 50),
                pw.Text(
                  'Les Baroudeurs',
                  style: PdfStyles.titleStyle,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  trek.titre,
                  style: PdfStyles.subtitleStyle,
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  trek.region + ', ' + trek.pays,
                  style: PdfStyles.italicTextStyle,
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Un recit de voyage',
                  style: PdfStyles.italicTextStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addTitlePage(pw.Document pdf, Trek trek) {
    final duree = trek.dureeJours;
    final dateFormat = DateFormat('dd MMMM yyyy', 'fr');
    final dateDebut = DateTime.parse(trek.dateDebut);
    final dateFin = DateTime.parse(trek.dateFin);

    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 50),
              pw.Text(
                trek.titre,
                style: PdfStyles.titleStyle,
              ),
              pw.Divider(color: PdfStyles.secondaryColor, thickness: 2),
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      'Du:',
                      style: PdfStyles.labelStyle,
                    ),
                  ),
                  pw.Text(
                    dateFormat.format(dateDebut),
                    style: PdfStyles.bodyTextStyle,
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      'Au:',
                      style: PdfStyles.labelStyle,
                    ),
                  ),
                  pw.Text(
                    dateFormat.format(dateFin),
                    style: PdfStyles.bodyTextStyle,
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      'Duree:',
                      style: PdfStyles.labelStyle,
                    ),
                  ),
                  pw.Text(
                    duree.toString() + ' jour(s)',
                    style: PdfStyles.bodyTextStyle,
                  ),
                ],
              ),
              if (trek.distanceKm != null) ...[
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 120,
                      child: pw.Text(
                        'Distance:',
                        style: PdfStyles.labelStyle,
                      ),
                    ),
                    pw.Text(
                      trek.distanceKm!.toStringAsFixed(1) + ' km',
                      style: PdfStyles.bodyTextStyle,
                    ),
                  ],
                ),
              ],
              if (trek.denivelePositifM != null) ...[
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 120,
                      child: pw.Text(
                        'Denivele:',
                        style: PdfStyles.labelStyle,
                      ),
                    ),
                    pw.Text(
                      trek.denivelePositifM.toString() + ' m',
                      style: PdfStyles.bodyTextStyle,
                    ),
                  ],
                ),
              ],
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      'Compagnons:',
                      style: PdfStyles.labelStyle,
                    ),
                  ),
                  pw.Text(
                    trek.compagnons.isNotEmpty ? trek.compagnons : 'Seul(e)',
                    style: PdfStyles.bodyTextStyle,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addJourPageTextOnly(pw.Document pdf, Trek trek, JourTrek jour) {
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final jourDate = DateTime.parse(jour.date);

    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Container(
            padding: PdfStyles.containerPadding,
            color: PdfStyles.secondaryColor,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    dateFormat.format(jourDate),
                    style: PdfStyles.sectionTitleStyle,
                  ),
                ),
                if (jour.lieuDepart.isNotEmpty || jour.lieuArrivee.isNotEmpty)
                  pw.Text(
                    jour.lieuDepart + ' -> ' + jour.lieuArrivee,
                    style: PdfStyles.italicTextStyle,
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 15),
          if (jour.resume.isNotEmpty) ...[
            pw.Text(
              'Recit du jour:',
              style: PdfStyles.sectionTitleStyle,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              jour.resume,
              style: PdfStyles.bodyTextStyle,
            ),
            pw.SizedBox(height: 15),
          ],
          pw.Table.fromTextArray(
            headers: ['', ''],
            data: [
              ['Distance', (jour.distanceKm?.toStringAsFixed(1) ?? 'N/A') + ' km'],
              ['Meteo', jour.meteo],
              ['Emotions', jour.emotions],
              ['Difficultes', jour.difficultes],
              ['Decouvertes', jour.decouvertes],
            ],
            border: null,
            headerStyle: PdfStyles.labelStyle,
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: PdfStyles.tableCellPadding,
          ),
        ],
      ),
    );
  }

  void _addEndPage(pw.Document pdf, Trek trek) {
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.SizedBox(height: 100),
                pw.Text(
                  'Fin du recit',
                  style: PdfStyles.titleStyle,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  trek.titre,
                  style: PdfStyles.subtitleStyle,
                ),
                pw.SizedBox(height: 40),
                pw.Text(
                  "Merci d'avoir vecu cette aventure !",
                  style: PdfStyles.italicTextStyle,
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Les Baroudeurs - ' + DateTime.now().year.toString(),
                  style: PdfStyles.bodyTextStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}