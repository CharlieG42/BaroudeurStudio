import 'package:flutter/material.dart';

import 'screens/trek_list_screen.dart';

void main() {
  runApp(const LesBaroudeursApp());
}

class LesBaroudeursApp extends StatelessWidget {
  const LesBaroudeursApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Les Baroudeurs',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // vert "rando"
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
      home: const TrekListScreen(),
    );
  }
}
