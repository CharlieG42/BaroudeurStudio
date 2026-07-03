import 'dart:io';
import 'dart:isolate';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../models/trek.dart';
import '../../models/jour_trek.dart';
import '../../models/media.dart';
import '../../db/database_helper.dart';
import '../../config/app_config.dart';
import '../utils/image_optimizer.dart';
import '../utils/filename_utils.dart';
import 'pdf_styles.dart';

/// Service d'export PDF pour les treks
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

  /// Génère un PDF avec images en arrière-plan
  /// Utilise un isolate pour éviter les problèmes de mémoire
  Future<File> exportTrekToPdfWithImages(Trek trek) async {
    final jours = await DatabaseHelper.instance.getJoursForTrek(trek.id!);
    final joursData = <Map<String, dynamic>>[];
    
    for (final jour in jours) {
      final medias = await DatabaseHelper.instance.getMediasForJour(jour.id!);
      joursData.add({
        'jour': jour,
        'medias': medias,
      });
    }

    final receivePort = ReceivePort();
    final sendPort = receivePort.sendPort;
    
    await Isolate.spawn(
      _generatePdfInBackground,
      {
        'trek': trek,
        'joursData': joursData,
        'sendPort': sendPort,
        'compressionQuality': AppConfig.imageCompressionQuality,
      },
    );
    
    final result = await receivePort.first as Map<String, dynamic>;
    
    if (result['error'] != null) {
      throw Exception('Erreur: ' + result['error'].toString());
    }
    
    return File(result['path']);
  }

  /// Imprime le PDF
  Future<void> printTrekPdf(Trek trek, {bool withImages = true}) async {
    final pdfFile = withImages 
        ? await exportTrekToPdfWithImages(trek)
        : await exportTrekToPdfTextOnly(trek);
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
                PdfStyles.verticalSpace(50),
                pw.Text('Les Baroudeurs', style: PdfStyles.titleStyle),
                PdfStyles.verticalSpace(20),
                pw.Text(trek.titre, style: PdfStyles.subtitleStyle),
                PdfStyles.verticalSpace(10),
                pw.Text(
                  trek.region + ', ' + trek.pays,
                  style: PdfStyles.italicTextStyle.copyWith(fontSize: 18),
                ),
                PdfStyles.verticalSpace(30),
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
              PdfStyles.verticalSpace(50),
              pw.Text(trek.titre, style: PdfStyles.subtitleStyle),
              PdfStyles.horizontalDivider(),
              PdfStyles.verticalSpace(20),
              PdfStyles.infoRow('Du:', dateFormat.format(dateDebut)),
              PdfStyles.verticalSpace(10),
              PdfStyles.infoRow('Au:', dateFormat.format(dateFin)),
              PdfStyles.verticalSpace(10),
              PdfStyles.infoRow('Duree:', duree.toString() + ' jour(s)'),
              if (trek.distanceKm != null) ...[
                PdfStyles.verticalSpace(10),
                PdfStyles.infoRow('Distance:', trek.distanceKm!.toStringAsFixed(1) + ' km'),
              ],
              if (trek.denivelePositifM != null) ...[
                PdfStyles.verticalSpace(10),
                PdfStyles.infoRow('Denivele:', trek.denivelePositifM.toString() + ' m'),
              ],
              PdfStyles.verticalSpace(20),
              PdfStyles.infoRow('Compagnons:', trek.compagnons.isNotEmpty ? trek.compagnons : 'Seul(e)'),
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
          PdfStyles.secondaryContainer(
            pw.Row(
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
          PdfStyles.verticalSpace(15),
          if (jour.resume.isNotEmpty) ...[
            pw.Text('Recit du jour:', style: PdfStyles.subtitleStyle.copyWith(fontSize: 16)),
            PdfStyles.verticalSpace(8),
            pw.Text(jour.resume, style: PdfStyles.bodyTextStyle),
            PdfStyles.verticalSpace(15),
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
                PdfStyles.verticalSpace(100),
                pw.Text('Fin du recit', style: PdfStyles.titleStyle),
                PdfStyles.verticalSpace(20),
                pw.Text(trek.titre, style: PdfStyles.subtitleStyle),
                PdfStyles.verticalSpace(40),
                pw.Text("Merci d'avoir vecu cette aventure !", style: PdfStyles.bodyTextStyle),
                PdfStyles.verticalSpace(20),
                pw.Text('Les Baroudeurs - ' + DateTime.now().year.toString(), style: PdfStyles.bodyTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _generatePdfInBackground(Map<String, dynamic> params) async {
    initializeDateFormatting('fr');
    
    final sendPort = params['sendPort'] as SendPort;
    final trek = params['trek'] as Trek;
    final joursData = params['joursData'] as List<Map<String, dynamic>>;
    final compressionQuality = params['compressionQuality'] as int? ?? 70;
    
    try {
      final pdf = pw.Document();
      
      _addCoverPageInIsolate(pdf, trek);
      _addTitlePageInIsolate(pdf, trek);
      
      for (final data in joursData) {
        final jour = data['jour'] as JourTrek;
        final medias = data['medias'] as List<Media>;
        _addJourPageInIsolate(pdf, trek, jour, medias, compressionQuality);
      }
      
      _addEndPageInIsolate(pdf, trek);

      final directory = await getApplicationDocumentsDirectory();
      final filePath = directory.path + '/Baroudeurs_Images_' + FilenameUtils.sanitizeFilename(trek.titre) + '.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      
      sendPort.send({'path': filePath});
    } catch (e) {
      sendPort.send({'error': e.toString()});
    }
  }

  static void _addCoverPageInIsolate(pw.Document pdf, Trek trek) {
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
                  style: const pw.TextStyle(
                    fontSize: 36,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  trek.titre,
                  style: const pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  trek.region + ', ' + trek.pays,
                  style: const pw.TextStyle(fontSize: 18),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Un recit de voyage',
                  style: const pw.TextStyle(
                    fontSize: 16,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _addTitlePageInIsolate(pw.Document pdf, Trek trek) {
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
                style: const pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      'Du:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(dateFormat.format(dateDebut)),
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
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(dateFormat.format(dateFin)),
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
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(duree.toString() + ' jour(s)'),
                ],
              ),
              pw.SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  static void _addJourPageInIsolate(pw.Document pdf, Trek trek, JourTrek jour, List<Media> medias, int compressionQuality) {
    final dateFormat = DateFormat('EEEE d MMMM yyyy', 'fr');
    final jourDate = DateTime.parse(jour.date);

    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            color: PdfStyles.secondaryColor,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    dateFormat.format(jourDate),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfStyles.textColor,
                    ),
                  ),
                ),
                if (jour.lieuDepart.isNotEmpty || jour.lieuArrivee.isNotEmpty)
                  pw.Text(
                    jour.lieuDepart + ' -> ' + jour.lieuArrivee,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfStyles.textColor,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 15),
          if (medias.isNotEmpty) ...[
            pw.GridView(
              crossAxisCount: 1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: medias.map((media) => _buildPhotoWidgetInIsolate(media, compressionQuality)).toList(),
            ),
            pw.SizedBox(height: 15),
          ],
          if (jour.resume.isNotEmpty) ...[
            pw.Text(
              'Recit du jour:',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfStyles.primaryColor,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              jour.resume,
              style: const pw.TextStyle(fontSize: 12, color: PdfStyles.textColor),
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfStyles.accentColor),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPhotoWidgetInIsolate(Media media, int compressionQuality) {
    try {
      final file = File(media.cheminFichier);
      final imageBytes = file.readAsBytesSync();
      final optimizedBytes = ImageOptimizer.optimizeImage(imageBytes, quality: compressionQuality);
      final image = pw.MemoryImage(optimizedBytes);
      
      return pw.Container(
        height: PdfStyles.imageHeight,
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(8),
          image: pw.DecorationImage(
            image: image,
            fit: pw.BoxFit.cover,
          ),
        ),
      );
    } catch (e) {
      return pw.Container(
        color: PdfColors.grey300,
        height: PdfStyles.imageHeight,
        child: pw.Center(
          child: pw.Text('Photo introuvable', style: const pw.TextStyle(color: PdfColors.white)),
        ),
      );
    }
  }

  static void _addEndPageInIsolate(pw.Document pdf, Trek trek) {
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
                  style: const pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  trek.titre,
                  style: const pw.TextStyle(
                    fontSize: 18,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
                pw.SizedBox(height: 40),
                pw.Text(
                  "Merci d'avoir vecu cette aventure !",
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Les Baroudeurs - ' + DateTime.now().year.toString(),
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}