import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/trek_list_screen.dart';

void main() async {
  // Initialisation obligatoire pour Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de sqflite_ffi pour desktop (Windows/macOS/Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Cache disque persistant des tuiles de carte (flutter_map >= 8.2) :
  // les tuiles vues en ligne sont stockees et rejouees hors ligne.
  // getOrCreateInstance est un singleton : ses parametres ne
  // s'appliquent qu'a la premiere creation, d'ou l'init ici, au
  // demarrage, avant tout affichage de carte.
  if (!kIsWeb && !Platform.isFuchsia) {
    final supportDir = await getApplicationSupportDirectory();
    BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: supportDir.path,
      maxCacheSize: 1000000000, // 1 Go
    );
  }
  runApp(const BaroudeurStudioApp());
}

class BaroudeurStudioApp extends StatelessWidget {
  const BaroudeurStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BaroudeurStudio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // vert rando
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const TrekListScreen(),
    );
  }
}
