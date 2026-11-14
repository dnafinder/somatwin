import 'package:flutter/material.dart';

import '../core/models.dart';

const Color kBg = Color(0xFF0B1620);
const Color kWireColor = Color(0xFF7FB7D6);
const Color kGhostColor = Color(0xFF8A94A0);

/// Palette daltonica (stessa famiglia dei referti MEDyLAB).
Color sevColor(Severity s) {
  switch (s) {
    case Severity.ok:
      return const Color(0xFF2BBF92);
    case Severity.watch:
      return const Color(0xFFF2C94C);
    case Severity.alert:
      return const Color(0xFFF2762E);
    case Severity.info:
      return kWireColor;
  }
}

String sevText(Severity s) {
  switch (s) {
    case Severity.ok:
      return 'Nella norma';
    case Severity.watch:
      return 'Da tenere d\'occhio';
    case Severity.alert:
      return 'Da approfondire';
    case Severity.info:
      return 'Informativo';
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1B9E77),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
  );
}

const String kDisclaimer =
    'Gli indici sono stime calcolate da misure e dati dichiarati. Non sono una diagnosi: '
    'l\'interpretazione clinica compete al medico. Il modello 3D e\' una ricostruzione '
    'parametrica: solo le sezioni misurate sono esatte.';
