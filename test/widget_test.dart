// Test de fumée basique : vérifie que l'application démarre sans planter
// et affiche bien l'écran d'accueil (liste des treks).

import 'package:flutter_test/flutter_test.dart';

import 'package:les_baroudeurs/main.dart';

void main() {
  testWidgets('L\'application démarre et affiche l\'écran des treks',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LesBaroudeursApp());

    // L'AppBar doit afficher le titre de l'app.
    expect(find.text('Les Baroudeurs'), findsOneWidget);
  });
}
