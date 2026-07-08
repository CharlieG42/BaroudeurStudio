import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Styles et constantes pour la génération PDF
class PdfStyles {
  // Couleurs principales
  static final primaryColor = PdfColor.fromInt(0xFFf5a665);
  static final secondaryColor = PdfColor.fromInt(0xFFd7b895);
  static final accentColor = PdfColor.fromInt(0xFFA67352);
  static final textColor = PdfColor.fromInt(0xFF000000);
  static final lightTextColor = PdfColor.fromInt(0xFF666666);
  
  // Dimensions
  static const double imageHeight = 120.0;
  static const double pageMargin = 20.0;
  static const double sectionSpacing = 15.0;
  static const double smallSpacing = 8.0;
  static const double mediumSpacing = 10.0;
  static const double largeSpacing = 20.0;

  // Styles de texte
  static final titleStyle = pw.TextStyle(
    fontSize: 36,
    fontWeight: pw.FontWeight.bold,
    color: primaryColor,
  );

  static final subtitleStyle = pw.TextStyle(
    fontSize: 24,
    fontWeight: pw.FontWeight.bold,
    color: accentColor,
  );

  static final sectionTitleStyle = pw.TextStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
    color: textColor,
  );

  static final bodyTextStyle = pw.TextStyle(
    fontSize: 12,
    color: textColor,
  );

  static final italicTextStyle = pw.TextStyle(
    fontSize: 14,
    fontStyle: pw.FontStyle.italic,
    color: lightTextColor,
  );

  static final labelStyle = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    color: accentColor,
  );

  // Bords et décoration
  static const containerPadding = pw.EdgeInsets.all(10);
  static const tableCellPadding = pw.EdgeInsets.all(5);
  static const double dividerThickness = 2.0;
  static const double borderRadius = 8.0;

  /// Crée un conteneur avec le style secondaire
  static pw.Widget secondaryContainer(pw.Widget child) {
    return pw.Container(
      padding: containerPadding,
      color: secondaryColor,
      child: child,
    );
  }

  /// Crée un séparateur horizontal
  static pw.Widget horizontalDivider() {
    return pw.Divider(color: secondaryColor, thickness: dividerThickness);
  }

  /// Crée un espace vertical
  static pw.Widget verticalSpace(double height) {
    return pw.SizedBox(height: height);
  }

  /// Crée une ligne d'information (label: valeur)
  static pw.Widget infoRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(label, style: labelStyle),
        ),
        pw.Text(value, style: bodyTextStyle),
      ],
    );
  }
}