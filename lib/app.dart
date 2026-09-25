import 'package:flutter/material.dart';

class ScriptureListenerApp extends StatelessWidget {
  const ScriptureListenerApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scripture Listener',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD6A84B),
          brightness: Brightness.dark,
          surface: const Color(0xFF101112),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101112),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101112),
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 56),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: home,
    );
  }
}
